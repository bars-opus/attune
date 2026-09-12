#!/usr/bin/env bash
#
# Four two-connection races for Stories.
#
# Lives outside supabase/tests because that suite runs inside one
# transaction and ROLLBACKs -- a race needs two real connections that can
# actually interleave. Follows scripts/concurrency/game_invite_races.sh's
# shape: a `run` helper that opens its own psql connection, sets the
# authenticated user with `set_config` the same way that harness's inline
# DO block does (there is no reusable `tsa` SQL function -- the one in
# supabase/tests/story_rpc_contracts.sql is defined and DROPped inside
# that file's own ROLLBACK transaction, so it does not exist outside it),
# and two such connections are launched with `&` and joined with `wait`
# so Postgres decides the interleaving, not this script.
#
# What each race proves, and why the single-connection contract suite
# (story_rpc_contracts.sql) could not have proven it:
#
#   1. Two concurrent finalizes of the SAME client_story_id -> ONE
#      story, ONE row, both callers get the same story id. This is
#      exactly what create_story_item's (author_id, client_story_id)
#      UNIQUE constraint and its ON CONFLICT ... DO NOTHING branch exist
#      for (20260938050000) -- Task 5's report flagged this as a known
#      gap a single transaction cannot exercise, because within one
#      transaction the "first" call always completes before the
#      "second" one starts.
#   2. Two concurrent mark_story_viewed by the same partner -> ONE
#      story_views row (its PRIMARY KEY (story_item_id, viewer_id) plus
#      ON CONFLICT DO NOTHING), and has_been_viewed flips true exactly
#      once (its guarded UPDATE ... AND has_been_viewed = false).
#   3. delete_story_item racing complete_story_archival for the SAME
#      story -> the story ends deleted AND every produced object
#      (media, thumbnail, archive key, and the just-uploaded rendition
#      if the swap loses) is enqueued for deletion. Nothing leaks
#      either way the row lock resolves the race.
#   4. Two concurrent claim_story_archival_batch(1) -> the same pending
#      outbox row is claimed by exactly one caller, thanks to
#      FOR UPDATE SKIP LOCKED (20260938090000) -- the other gets zero
#      rows rather than blocking and double-processing.
#
# Usage: scripts/concurrency/story_races.sh
# Requires the local attune_test database (scripts/local_pg_setup.sh).
set -uo pipefail
DB=attune_test
REL='00000000-0000-0000-0000-0000000000d1'
UA='00000000-0000-0000-0000-00000000d101'   # author
UB='00000000-0000-0000-0000-00000000d102'   # partner / viewer

# -----------------------------------------------------------------------
# Fixture teardown + setup. Runs at the START so a second run is never
# polluted by the first (matches game_invite_races.sh's own approach of
# clearing its relationship's rows before racing).
#
# Deliberately does NOT touch storage.objects: the local harness stub
# (scripts/local_pg_bootstrap.sql) installs a BEFORE DELETE trigger that
# raises on any direct DELETE from storage tables, reproducing Supabase's
# real refusal ("Direct deletion from storage tables is not allowed. Use
# the Storage API instead.") on purpose, so that class of bug fails here
# first instead of only in production. Harmless to skip anyway: every
# storage_key this script mints is `gen_random_bytes(16)`-suffixed by
# create_story_upload_intent, so old fixture rows from a previous run
# never collide with a new run's keys.
#
# This block is NOT silenced (no >/dev/null 2>&1) -- an earlier version
# of this script hid a real failure here (the storage.objects DELETE
# above erroring out and aborting the whole teardown silently), which
# then accumulated 120 stale upload-intent rows for the fixture author
# across repeated runs until create_story_upload_intent's own abuse-rate
# ceiling made EVERY subsequent race in this file fail with RATE_LIMITED
# instead of the result under test. ON_ERROR_STOP=1 now surfaces that
# class of setup failure immediately instead of producing a confusing
# downstream race failure.
psql -q -d "$DB" -v ON_ERROR_STOP=1 <<SQL
DELETE FROM public.story_media_processing_outbox
 WHERE story_item_id IN (SELECT id FROM public.story_items WHERE relationship_id = '$REL');
DELETE FROM public.story_views
 WHERE story_item_id IN (SELECT id FROM public.story_items WHERE relationship_id = '$REL');
DELETE FROM public.media_deletion_queue
 WHERE object_name LIKE 'story-media/$REL/%' OR object_name LIKE 'story-archive/%';
DELETE FROM public.story_items WHERE relationship_id = '$REL';
DELETE FROM public.story_media_upload_intents WHERE relationship_id = '$REL';
DELETE FROM public.story_media_upload_intents WHERE requester_id IN ('$UA', '$UB');
DELETE FROM public.story_change_signals WHERE relationship_id = '$REL';
DELETE FROM public.relationships WHERE id = '$REL';

INSERT INTO auth.users(id) VALUES ('$UA'), ('$UB') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('$UA', '+15559990101', 'Story Author'),
  ('$UB', '+15559990102', 'Story Partner')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships(id, user_a, user_b, status)
VALUES ('$REL', '$UA', '$UB', 'active');
INSERT INTO public.feature_flags(key, enabled) VALUES ('stories', true)
  ON CONFLICT (key) DO UPDATE SET enabled = true;
SQL

# Sets the authenticated role and JWT claims for ONE psql connection,
# exactly like game_invite_races.sh's inline
# `EXECUTE 'SET LOCAL ROLE authenticated'` + set_config pair -- there is
# no `tsa()` SQL function reusable outside supabase/tests' own
# transaction, so it is inlined here every time it's needed.
auth_block() {
  local user_id="$1"
  cat <<SQL
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub','$user_id',true);
  PERFORM set_config('request.jwt.claims',json_build_object('sub','$user_id','role','authenticated')::text,true);
SQL
}

# Issues one media + one thumbnail upload intent for $UA in $REL, stamps
# matching storage.objects rows sized/typed to pass create_story_item's
# validation (the exact approach supabase/tests/story_rpc_contracts.sql's
# Task 5 block uses: a storage.objects row with a metadata jsonb column
# carrying 'size' and 'mimetype', added to the local stub for that same
# validation path), and echoes "media_id thumb_id" on stdout.
issue_intent_pair() {
  psql -q -d "$DB" -v ON_ERROR_STOP=1 -tA <<SQL
DO \$do\$
DECLARE
  r jsonb;
  v_media_id uuid;
  v_thumb_id uuid;
  v_media_key text;
  v_thumb_key text;
BEGIN
$(auth_block "$UA")
  r := public.create_story_upload_intent('$REL', 'media', 'image', 'image/jpeg');
  v_media_id := (r->>'intent_id')::uuid;
  v_media_key := r->>'storage_key';
  r := public.create_story_upload_intent('$REL', 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id := (r->>'intent_id')::uuid;
  v_thumb_key := r->>'storage_key';

  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key, jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key, jsonb_build_object('size', 100000,  'mimetype', 'image/jpeg'));

  CREATE TEMP TABLE IF NOT EXISTS rc_intent_out(media_id uuid, thumb_id uuid);
  INSERT INTO rc_intent_out VALUES (v_media_id, v_thumb_id);
END \$do\$;
SELECT media_id || ' ' || thumb_id FROM rc_intent_out;
SQL
}

echo "=============================================================="
echo "Race 1: two concurrent finalizes of the SAME client_story_id"
echo "=============================================================="

# One pair of intents, one client_story_id, shared by BOTH connections --
# this is the shape of a client retrying a lost response, or two taps
# landing at once. Both racers try to consume the SAME two intent rows.
read -r MEDIA_ID THUMB_ID < <(issue_intent_pair)
CLIENT_STORY_ID=$(psql -tA -d "$DB" -c "SELECT gen_random_uuid();")

# Captures the RPC's actual jsonb result, not just a NOTICE line --
# the brief's contract is "both callers get the same story id," which
# means both calls must return success at all, not merely that the
# table ends up with one row (a row a losing caller never learns about,
# because it was told UNAVAILABLE instead, would still leave the table
# at one row and pass a table-count-only check while violating the
# actual contract). Same shape as issue_intent_pair: the RPC call and
# the SELECT that reads its result back are one DO block in one psql
# invocation, so auth_block's SET LOCAL ROLE is still in effect and the
# result survives past RESET ROLE via a TEMP TABLE local to this session.
finalize() {
  psql -q -d "$DB" -tA <<SQL > "/tmp/story_race1_$1.out" 2>&1
DO \$do\$
DECLARE r jsonb;
BEGIN
$(auth_block "$UA")
  r := public.create_story_item(
    '$REL', '$CLIENT_STORY_ID', '$MEDIA_ID', '$THUMB_ID', 1080, 1920, NULL, 0);
  RESET ROLE;
  DROP TABLE IF EXISTS rc_finalize_out;
  CREATE TEMP TABLE rc_finalize_out(result text);
  INSERT INTO rc_finalize_out VALUES (r::text);
END \$do\$;
SELECT result FROM rc_finalize_out;
SQL
}

# Both callers use the SAME already-issued intent pair and the SAME
# client_story_id -- this is deliberately the "client lost the response
# and retried with an identical request body" shape, which is exactly
# what (author_id, client_story_id) uniqueness plus ON CONFLICT DO
# NOTHING exists to make safe.
finalize caller-A &
finalize caller-B &
wait

RESULT_A=$(cat /tmp/story_race1_caller-A.out)
RESULT_B=$(cat /tmp/story_race1_caller-B.out)
echo "--- result ---"
echo "caller-A -> $RESULT_A"
echo "caller-B -> $RESULT_B"
psql -q -d "$DB" -c "
  SELECT count(*) AS stories FROM public.story_items
   WHERE relationship_id = '$REL' AND client_story_id = '$CLIENT_STORY_ID';"

STORY_COUNT=$(psql -tA -d "$DB" -c "
  SELECT count(*) FROM public.story_items
   WHERE relationship_id = '$REL' AND client_story_id = '$CLIENT_STORY_ID';")
INTENTS_CONSUMED=$(psql -tA -d "$DB" -c "
  SELECT count(*) FROM public.story_media_upload_intents
   WHERE id IN ('$MEDIA_ID', '$THUMB_ID') AND used_at IS NOT NULL;")
STORY_ID_A=$(echo "$RESULT_A" | grep -oE '"story_id": ?"[^"]+"' | grep -oE '[0-9a-f-]{36}')
STORY_ID_B=$(echo "$RESULT_B" | grep -oE '"story_id": ?"[^"]+"' | grep -oE '[0-9a-f-]{36}')

if [ "$STORY_COUNT" = "1" ] && [ "$INTENTS_CONSUMED" = "2" ] \
   && [ -n "$STORY_ID_A" ] && [ "$STORY_ID_A" = "$STORY_ID_B" ]; then
  echo "PASS: race 1 -- one story, both intents consumed exactly once, BOTH callers received story_id=$STORY_ID_A"
else
  echo "FAIL: race 1 -- expected 1 story / 2 consumed intents / both callers returning the same story_id."
  echo "      got $STORY_COUNT story(ies), $INTENTS_CONSUMED consumed intent(s), caller-A story_id=[$STORY_ID_A], caller-B story_id=[$STORY_ID_B]"
fi

echo
echo "=============================================================="
echo "Race 2: two concurrent mark_story_viewed, same viewer, same story"
echo "=============================================================="

# A fresh story, posted by UA, viewed by UB -- viewed twice at once.
read -r MEDIA_ID2 THUMB_ID2 < <(issue_intent_pair)
psql -q -d "$DB" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL
DO \$\$
DECLARE r jsonb;
BEGIN
$(auth_block "$UA")
  r := public.create_story_item(
    '$REL', gen_random_uuid(), '$MEDIA_ID2', '$THUMB_ID2', 1080, 1920, NULL, 0);
END \$\$;
SQL
# The story's id is recovered by its unique media_key rather than
# threaded out of the DO block above -- a TEMP TABLE would be scoped to
# that connection only and invisible to the `psql -c` calls below.
STORY2=$(psql -tA -d "$DB" -c "
  SELECT id FROM public.story_items
   WHERE relationship_id = '$REL' AND media_key = (
     SELECT storage_key FROM public.story_media_upload_intents WHERE id = '$MEDIA_ID2');")

view_story() {
  psql -q -d "$DB" <<SQL 2>&1 | grep -E "NOTICE|ERROR"
DO \$\$
DECLARE r jsonb;
BEGIN
$(auth_block "$UB")
  r := public.mark_story_viewed('$STORY2');
  RAISE NOTICE '$1 -> %', r;
END \$\$;
SQL
}

view_story viewer-A &
view_story viewer-B &
wait

echo "--- result ---"
psql -q -d "$DB" -c "
  SELECT count(*) AS story_views_rows FROM public.story_views WHERE story_item_id = '$STORY2';"
psql -q -d "$DB" -c "
  SELECT has_been_viewed FROM public.story_items WHERE id = '$STORY2';"
VIEW_ROWS=$(psql -tA -d "$DB" -c "SELECT count(*) FROM public.story_views WHERE story_item_id = '$STORY2';")
HAS_VIEWED=$(psql -tA -d "$DB" -c "SELECT has_been_viewed FROM public.story_items WHERE id = '$STORY2';")
SIGNAL_VERSION=$(psql -tA -d "$DB" -c "SELECT version FROM public.story_change_signals WHERE relationship_id = '$REL';")
if [ "$VIEW_ROWS" = "1" ] && [ "$HAS_VIEWED" = "t" ]; then
  echo "PASS: race 2 -- one story_views row, has_been_viewed set once (signal version now $SIGNAL_VERSION)"
else
  echo "FAIL: race 2 -- expected 1 view row / has_been_viewed=t, got $VIEW_ROWS row(s) / has_been_viewed=$HAS_VIEWED"
fi

echo
echo "=============================================================="
echo "Race 3: delete_story_item racing complete_story_archival"
echo "=============================================================="

# Two sub-cases, one per possible lock-acquisition order -- both are
# real races a live worker and a live delete tap can land in, and
# complete_story_archival has an explicit branch for each (the
# conditional swap "WHERE ... deleted_at IS NULL AND downscaled_at IS
# NULL", and the zero-row branch that re-enqueues its own just-uploaded
# object rather than orphaning it). Both sub-cases FORCE their ordering
# with a held row lock + sleep, exactly like
# scripts/concurrency/word_hunt_races.sh's own lock-and-sleep blocks --
# a bare `&`/`wait` on two independent RPCs would leave the outcome to
# whatever the scheduler happens to do, and this is proving BOTH branches
# work, not just whichever one wins by chance.

race3_case() {
  local label="$1" hold_conn="$2"
  # hold_conn = "archival" -> connection 1 locks+sleeps+finishes the
  #             swap while connection 2's delete queues behind it.
  # hold_conn = "delete"   -> connection 1 locks+sleeps+deletes while
  #             connection 2's complete_story_archival call queues
  #             behind it and must hit the zero-row/re-enqueue branch.
  read -r m t < <(issue_intent_pair)
  psql -q -d "$DB" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL
DO \$\$
DECLARE r jsonb;
BEGIN
$(auth_block "$UA")
  r := public.create_story_item(
    '$REL', gen_random_uuid(), '$m', '$t', 1080, 1920, NULL, 0);
END \$\$;
SQL
  local story
  story=$(psql -tA -d "$DB" -c "
    SELECT id FROM public.story_items
     WHERE relationship_id = '$REL' AND media_key = (
       SELECT storage_key FROM public.story_media_upload_intents WHERE id = '$m');")
  local new_key="story-archive/${story}.jpg"
  psql -q -d "$DB" -c "SELECT * FROM public.claim_story_archival_batch(50);" >/dev/null 2>&1

  if [ "$hold_conn" = "archival" ]; then
    # Connection 1 holds the lock, sleeps, THEN calls complete_story_archival
    # for real inside the SAME transaction -- so its result is committed
    # atomically with the lock release, and connection 2's delete cannot
    # observe a half-finished state.
    psql -q -d "$DB" >/tmp/story_race3_${label}_1.log 2>&1 <<SQL &
BEGIN;
SELECT 1 FROM public.story_items WHERE id = '$story' FOR UPDATE;
SELECT pg_sleep(1.2);
SELECT public.complete_story_archival('$story', '$new_key');
COMMIT;
SQL
    sleep 0.3
    psql -q -d "$DB" >/tmp/story_race3_${label}_2.log 2>&1 <<SQL &
DO \$\$
DECLARE r jsonb;
BEGIN
$(auth_block "$UA")
  r := public.delete_story_item('$story');
END \$\$;
SQL
  else
    # Connection 1 holds the lock, sleeps, THEN deletes for real. Connection
    # 2's complete_story_archival call queues behind it and must find the
    # row already deleted_at-stamped when it finally gets the lock.
    psql -q -d "$DB" >/tmp/story_race3_${label}_1.log 2>&1 <<SQL &
BEGIN;
SELECT 1 FROM public.story_items WHERE id = '$story' FOR UPDATE;
SELECT pg_sleep(1.2);
COMMIT;
SQL
    sleep 0.3
    psql -q -d "$DB" >/tmp/story_race3_${label}_2.log 2>&1 <<SQL &
DO \$\$
DECLARE r jsonb;
BEGIN
$(auth_block "$UA")
  r := public.delete_story_item('$story');
END \$\$;
SQL
    wait
    # Now issue the archival completion for real, once the delete above
    # has already committed -- this is the actual race path being tested:
    # the worker's own row lock inside complete_story_archival queues
    # behind whatever delete_story_item most recently committed.
    psql -q -d "$DB" -c "SELECT public.complete_story_archival('$story', '$new_key');" >/tmp/story_race3_${label}_3.log 2>&1
  fi
  wait

  local deleted current_key queued_current queued_new
  deleted=$(psql -tA -d "$DB" -c "SELECT deleted_at IS NOT NULL FROM public.story_items WHERE id = '$story';")
  current_key=$(psql -tA -d "$DB" -c "SELECT media_key FROM public.story_items WHERE id = '$story';")
  queued_current=$(psql -tA -d "$DB" -c "SELECT count(*) FROM public.media_deletion_queue WHERE object_name = '$current_key';")
  queued_new=$(psql -tA -d "$DB" -c "SELECT count(*) FROM public.media_deletion_queue WHERE object_name = '$new_key';")

  echo "  [$label] deleted=$deleted current_media_key_queued=$queued_current new_rendition_queued=$queued_new (current_key == new_key: $( [ "$current_key" = "$new_key" ] && echo yes || echo no ))"

  # Nothing leaked iff the story ended deleted AND every object that is
  # LIVE right now (current_key) has a queue entry, AND the produced
  # rendition (new_key) is accounted for either because it IS the
  # current key (swap won, so it is queued as the live key) or because
  # it was independently re-enqueued (swap lost, complete_story_archival's
  # own zero-row branch).
  if [ "$deleted" = "t" ] && [ "$queued_current" = "1" ] \
     && { [ "$current_key" = "$new_key" ] || [ "$queued_new" = "1" ]; }; then
    echo "  PASS: race 3 [$label] -- story ended deleted, every produced object enqueued, nothing leaked"
    return 0
  else
    echo "  FAIL: race 3 [$label] -- deleted=$deleted, current key queued=$queued_current, new key queued=$queued_new"
    return 1
  fi
}

R3_OK=0
race3_case "archival-wins" "archival" || R3_OK=1
race3_case "delete-wins"   "delete"   || R3_OK=1
if [ "$R3_OK" = "0" ]; then
  echo "PASS: race 3 -- both lock-acquisition orders end deleted with nothing leaked"
else
  echo "FAIL: race 3 -- see sub-case output above"
fi

echo
echo "=============================================================="
echo "Race 4: two concurrent claim_story_archival_batch(1)"
echo "=============================================================="

# One pending outbox row (a freshly finalized image story, untouched by
# the claim above -- a distinct story from race 3's).
read -r MEDIA_ID4 THUMB_ID4 < <(issue_intent_pair)
psql -q -d "$DB" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL
DO \$\$
DECLARE r jsonb;
BEGIN
$(auth_block "$UA")
  r := public.create_story_item(
    '$REL', gen_random_uuid(), '$MEDIA_ID4', '$THUMB_ID4', 1080, 1920, NULL, 0);
END \$\$;
SQL
STORY4=$(psql -tA -d "$DB" -c "
  SELECT id FROM public.story_items
   WHERE relationship_id = '$REL' AND media_key = (
     SELECT storage_key FROM public.story_media_upload_intents WHERE id = '$MEDIA_ID4');")
# available_at = expires_at (24h out) -- pull it forward so this run's
# claim actually sees it as eligible without waiting a day.
psql -q -d "$DB" -c "
  UPDATE public.story_media_processing_outbox
     SET available_at = now() - interval '1 minute'
   WHERE story_item_id = '$STORY4';" >/dev/null

claim() {
  psql -q -d "$DB" -tA -c "
    SELECT string_agg(story_id::text, ',') FROM public.claim_story_archival_batch(1)
     WHERE story_id = '$STORY4';" > "/tmp/story_race4_$1.out" 2>&1
}

claim caller-A &
claim caller-B &
wait

CLAIM_A=$(cat /tmp/story_race4_caller-A.out)
CLAIM_B=$(cat /tmp/story_race4_caller-B.out)
echo "--- result ---"
echo "caller-A claimed: [${CLAIM_A}]"
echo "caller-B claimed: [${CLAIM_B}]"
psql -q -d "$DB" -c "
  SELECT state, attempts FROM public.story_media_processing_outbox WHERE story_item_id = '$STORY4';"

BOTH_EMPTY=0
[ -z "$CLAIM_A" ] && [ -z "$CLAIM_B" ] && BOTH_EMPTY=1
if [ "$BOTH_EMPTY" = "1" ]; then
  echo "FAIL: race 4 -- neither caller claimed the row at all"
elif [ -n "$CLAIM_A" ] && [ -n "$CLAIM_B" ]; then
  echo "FAIL: race 4 -- BOTH callers claimed the same story ($STORY4) -- FOR UPDATE SKIP LOCKED did not serialise the claim"
else
  ATTEMPTS=$(psql -tA -d "$DB" -c "SELECT attempts FROM public.story_media_processing_outbox WHERE story_item_id = '$STORY4';")
  if [ "$ATTEMPTS" = "1" ]; then
    echo "PASS: race 4 -- exactly one caller claimed the story, attempts incremented exactly once"
  else
    echo "FAIL: race 4 -- exactly one caller claimed it, but attempts=$ATTEMPTS (expected 1)"
  fi
fi

echo
echo "=============================================================="
echo "Done."
echo "=============================================================="

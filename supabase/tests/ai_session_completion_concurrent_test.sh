#!/usr/bin/env bash
# The three COMPLETION RPCs raced against the two CLOSURE paths.
#
# WHY THIS SCRIPT EXISTS. The final whole-branch review's N1 (Critical)
# found that commit_ai_session_ideas_turn, stage_ai_session_nearby_result
# and publish_ai_session_nearby_result took the ai_session_requests row
# FOR UPDATE as their FIRST lock and only then touched ai_sessions, with
# no relationship advisory lock at all -- the documented order
# (relationship advisory lock -> quota advisory lock -> session row ->
# request row) with its last two elements inverted. end_ai_session,
# purge_ai_session_content, admit_ai_session_generation and
# reconcile_ai_session_leases all take that order, so each completion RPC
# was a guaranteed deadlock partner for all four.
#
# Measured on the unmodified shipped bodies, two concurrent psql
# backends, no sleeps and no instrumentation, 10 trials per pair per
# ordering on freshly built fixtures:
#
#   commit  x end    10/10 and 10/10 deadlocks
#   stage   x end    10/10 and  9/10
#   publish x end     9/10 and  8/10
#   commit  x purge   7/10 and  7/10  (+3 and +3 purger-victim runs)
#   stage   x purge   7/10 and  8/10  (+3 and +1)
#   publish x purge  10/10 and  9/10  (+4 and +7)
#
# The victim ALTERNATES: three of the commit x end trials killed
# end_ai_session, i.e. the user's own "End session" failing with a raw
# SQLSTATE 40P01 for an operation that is unconditional for a current
# member of an active shared session.
#
# THE PURGER CASE IS THE WORST ONE and is why N1 is Critical rather than
# Important. purge_expired_ai_sessions wraps each session in a
# per-session `EXCEPTION WHEN OTHERS` so one wedged session cannot stop
# the platform's every-minute purge -- correct for its purpose, and this
# script does not ask for it to change. But it SWALLOWED the deadlock
# into a WARNING: 21 of those 60 purger trials logged
#   purge_expired_ai_sessions: session <id> could not be purged
#   (deadlock detected) -- skipped, will retry next run
# and left an EXPIRED session at state='active' with its content
# RETAINED. Spec 8.2.3's five-minute purge-lag target and the Global
# Constraint that session content is deleted in the same transaction
# that closes the session are both missed, silently.
#
# WHY NO EXISTING TEST CAUGHT IT. All four pre-existing *.sh concurrency
# scripts race only prepare/activate/admit/end -- precisely the
# conforming subset. Verified at the time: no committed test raced any
# completion RPC against anything. The single test class capable of
# finding this covered only the RPCs that were already correct. That gap
# is what this file closes.
#
# WHAT THIS SCRIPT ASSERTS. For each of the six (completion RPC x closure
# path) pairs, in BOTH launch orderings, over TRIALS trials each:
#
#   1. ZERO deadlocks. Any `deadlock detected` on either backend fails
#      the script, naming the pair and the trial. This is the primary
#      assertion -- the fix is a lock-order fix and a deadlock is its
#      direct refutation.
#   2. The purger NEVER swallows a deadlock into a WARNING. Checked by
#      matching the purger's own warning text on its backend's output,
#      separately from leg 1, because that failure is strictly worse
#      than a lost completion: the session stays active with content.
#   3. No forbidden middle. Whatever the interleaving, the session must
#      not end up closed with an in-flight ('reserved'/'started'/
#      'staged') request still hanging off it, and content must not
#      survive a closure.
#   4. Liveness, not just safety. Exactly one of the two admissible
#      outcomes must have happened -- the completion committed, or the
#      closure closed the session -- never neither. A fix that made both
#      sides fail cleanly would satisfy legs 1-3 and be useless.
#
# EACH TRIAL BUILDS ITS OWN FIXTURE with FRESH RANDOM uuids and
# DETERMINISTIC per-trial phone numbers, so this script is re-runnable
# against a dirty database -- deliberately unlike most AI-session tests,
# because it runs many trials in one invocation and a mid-run collision
# would silently reduce the trial count. users.phone is UNIQUE and an
# ON CONFLICT DO NOTHING insert that silently drops is how two earlier
# fixture bugs in this plan worked, so the fixture does NOT use
# ON CONFLICT: a collision RAISES, the trial reports SETUP FAILED, and
# the script exits non-zero rather than counting a trial that never ran.
#
# PLUS, added by Task 1 FIX ROUND 1: publish x discard, in both
# orderings, at each of several configurable gaps in discard's
# DELETE->UPDATE window. That pair was Task 1 review Finding 1
# (Critical): it survived 20260953120000 and was recorded as fixed. This
# script was the test class that should have caught it and did not,
# because it raced only the two CLOSURE paths. See the block above
# run_publish_discard() for the defect, the measured sensitivity of the
# window, and why the gap is not optional.
#
# Usage:
#   supabase/tests/ai_session_completion_concurrent_test.sh [TRIALS] [GAPS]
# TRIALS defaults to 10 (the required minimum per pair per ordering).
# The completion x closure section runs 12 pair/ordering combinations,
# so that is 120 races; the publish x discard section runs 2 orderings
# per gap, and GAPS defaults to "0,0.001,0.010" (the realistic-timing
# control plus the 1 ms and 10 ms windows the reviewer measured at 14/15
# and 15/15 deadlocks pre-fix), so 6 more combinations = 60 races. 180
# races at the defaults. Hardcodes -d attune_test like the other *.sh
# contracts.
set -uo pipefail
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"

DB="attune_test"
TRIALS="${1:-10}"
FAILED=0
SUMMARY=()

# users.phone is UNIQUE across the WHOLE suite, and this script inserts
# two users per trial across 12 pair/orderings -- 240 rows at the default
# trial count, far too many to hand-claim from the plan's fixture
# registry. They are therefore generated, from a per-invocation RUN_TAG
# plus a per-trial counter, inside a numeric range this file claims
# exclusively:
#
#   +1555 9 <5 digits>   -- the +15559xxxxx block
#
# Nothing else in supabase/tests/ uses a +15559 number with a 5-digit
# tail (the suite's +15559xxxxxx fixtures are all 7-digit tails:
# +15559990001, +15559991002 and so on), and this is RE-SWEPT by the
# collision check below rather than trusted.
#
# RUN_TAG makes the numbers differ between invocations, which is what
# makes this script re-runnable against a dirty database -- deliberately
# unlike most AI-session tests. That matters here specifically because
# one invocation runs 120+ races: with fixed numbers, a second run (or a
# run after any other test had claimed one of them) would fail every
# trial's SETUP and the script would report 12 pairs of "0 deadlocks"
# while having raced nothing at all. A vacuous green is the one outcome
# this file must not be able to produce.
RUN_TAG=$(( ($$ * 7919 + $(date +%s) ) % 90 + 10 ))   # 2 digits, 10..99
PHONE_BASE="+15559${RUN_TAG}"
PHONE_SERIAL=0

q() { psql -q -d "$DB" -t -A -c "$1" 2>&1; }

# ----------------------------------------------------------------------
# One race. $1 = completion RPC (commit|stage|publish)
#            $2 = closure path (end|purge)
#            $3 = launch order (ab = completion first, ba = closure first)
run_pair() {
  local rpc="$1" opp="$2" order="$3"
  local deadlocks=0 purge_warns=0 i
  local label="$rpc x $opp (order $order)"

  for i in $(seq 1 "$TRIALS"); do
    local rel ua ub pha phb mode expire setup session req tok td
    rel=$(uuidgen | tr 'A-Z' 'a-z')
    ua=$(uuidgen | tr 'A-Z' 'a-z')
    ub=$(uuidgen | tr 'A-Z' 'a-z')
    # One monotonic serial across the whole invocation, so no two trials
    # of any pair can collide with each other, and RUN_TAG keeps two
    # invocations apart. A collision with the rest of the suite RAISES
    # (there is no ON CONFLICT in the fixture) and is reported as
    # SETUP FAILED, which fails the script -- it never silently reduces
    # the trial count.
    PHONE_SERIAL=$((PHONE_SERIAL + 1))
    pha="${PHONE_BASE}$(printf '%03d' $((PHONE_SERIAL * 2 - 1)))"
    phb="${PHONE_BASE}$(printf '%03d' $((PHONE_SERIAL * 2)))"
    mode="ideas"; [ "$rpc" = "commit" ] || mode="nearby"
    # The purger only acts on a session past its expiry, so the purge
    # pairs expire the session first. The end pairs leave it live --
    # end_ai_session does not care about expiry.
    expire=""
    [ "$opp" = "purge" ] && expire="UPDATE public.ai_sessions SET expires_at = now() - interval '1 hour' WHERE id = v_session;"

    setup=$(psql -q -d "$DB" -t -A 2>&1 <<SQL
DO \$\$
DECLARE
  v_session uuid;
  v_admit record;
BEGIN
  -- No ON CONFLICT anywhere: a fixture collision must RAISE and be
  -- reported, never silently drop a row and leave the trial testing a
  -- half-built session. users.phone is UNIQUE and a silently dropped
  -- insert is how two earlier fixture bugs in this plan worked.
  INSERT INTO auth.users (id, email) VALUES
    ('$ua', 'completion_race_a_${RUN_TAG}_${PHONE_SERIAL}@t.test'),
    ('$ub', 'completion_race_b_${RUN_TAG}_${PHONE_SERIAL}@t.test');
  INSERT INTO public.users (id, phone, display_name) VALUES
    ('$ua', '$pha', 'A'), ('$ub', '$phb', 'B');
  INSERT INTO public.relationships (id, user_a, user_b, status)
    VALUES ('$rel', '$ua', '$ub', 'active');
  -- clock_timestamp(), never now(): now() is frozen per transaction, so
  -- two consent events written in one DO block would share an identical
  -- created_at and the consent lookup's tiebreak would fall to id DESC
  -- on a random uuid, making publish's consent gate a coin flip.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    ('$rel', '$ua', 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    ('$rel', '$ub', 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    '$ua', gen_random_uuid(), '$rel', '$mode', 'shared', NULL, false);
  PERFORM public.approve_ai_session_context('$ua', v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context('$ub', v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session('$ua', v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    '$ua', gen_random_uuid(), v_session, 1, '$mode:completionrace');
  IF v_admit.request_id IS NULL THEN
    RAISE EXCEPTION 'admission failed: outcome=%', v_admit.outcome;
  END IF;
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  -- publish needs a STAGED result to publish; the other two act on a
  -- 'started' request.
  IF '$rpc' = 'publish' THEN
    PERFORM public.stage_ai_session_nearby_result(
      v_admit.worker_token, v_admit.request_id, 'a nearby reply', '[]'::jsonb);
  END IF;
  $expire
  RAISE NOTICE 'FIXTURE % % %', v_session, v_admit.request_id, v_admit.worker_token;
END \$\$;
SQL
)
    read -r _ session req tok <<<"$(echo "$setup" | grep -o 'FIXTURE .*' | head -1)"
    if [ -z "${tok:-}" ]; then
      # ABORT, do not continue. A SETUP failure means this trial raced
      # nothing, and continuing would print "0 deadlocks" for a pair
      # that was never exercised -- the vacuous green this file must not
      # be able to produce. Fixture collisions have bitten this plan six
      # times; the loud exit is the lesson.
      echo "FAIL  $label trial $i: SETUP FAILED -- $(echo "$setup" | tr '\n' ' ')"
      echo
      echo "EXPLOIT: a fixture could not be built, so this pair raced nothing. Rebuild the database (bash scripts/local_pg_setup.sh) and re-run; if it persists, a uuid/phone/email in this script collides with the rest of the suite and must be re-claimed."
      exit 1
    fi

    local a_sql b_sql
    case "$rpc" in
      commit)  a_sql="SELECT committed FROM public.commit_ai_session_ideas_turn('$tok','$req','an instruction','a reply',NULL);" ;;
      stage)   a_sql="SELECT public.stage_ai_session_nearby_result('$tok','$req','a nearby reply','[]'::jsonb);" ;;
      publish) a_sql="SELECT committed FROM public.publish_ai_session_nearby_result('$ua','$req');" ;;
    esac
    case "$opp" in
      end)   b_sql="SELECT public.end_ai_session('$ub','$session');" ;;
      purge) b_sql="SELECT public.purge_expired_ai_sessions();" ;;
    esac

    # Two SEPARATE psql processes -- separate Postgres backends, which is
    # what makes the race real. Both launch orderings are run by the
    # caller loop so neither side is systematically given the lock
    # first: with the inversion present, BOTH orderings deadlocked.
    td=$(mktemp -d)
    if [ "$order" = "ab" ]; then
      psql -q -d "$DB" -t -A -c "$a_sql" > "$td/a" 2>&1 &
      psql -q -d "$DB" -t -A -c "$b_sql" > "$td/b" 2>&1 &
    else
      psql -q -d "$DB" -t -A -c "$b_sql" > "$td/b" 2>&1 &
      psql -q -d "$DB" -t -A -c "$a_sql" > "$td/a" 2>&1 &
    fi
    wait

    # ---- LEG 1: zero deadlocks, on either side. ----------------------
    if grep -q 'deadlock detected' "$td/a" "$td/b"; then
      deadlocks=$((deadlocks + 1))
      echo "FAIL  $label trial $i: DEADLOCK -- the lock order is inverted again"
      echo "      completion backend: $(tr '\n' ' ' < "$td/a" | head -c 400)"
      echo "      closure backend:    $(tr '\n' ' ' < "$td/b" | head -c 400)"
      FAILED=1
    fi

    # ---- LEG 2: the purger never swallows a deadlock into a WARNING. --
    # Checked separately from leg 1 and with its own message, because
    # this failure shape is strictly worse: the completion is merely
    # lost, whereas here an EXPIRED session stays active with its
    # content retained and only a cron-log WARNING records it.
    if [ "$opp" = "purge" ] && grep -q 'could not be purged' "$td/b"; then
      purge_warns=$((purge_warns + 1))
      echo "FAIL  $label trial $i: the purger SWALLOWED a failure into a WARNING -- an expired session is left unpurged with its content retained"
      echo "      $(grep -h 'could not be purged' "$td/b" | head -1)"
      FAILED=1
    fi

    local a_out b_out final_state inflight content
    a_out=$(cat "$td/a"); b_out=$(cat "$td/b")
    rm -rf "$td"

    final_state=$(q "SELECT state FROM public.ai_sessions WHERE id = '$session';")

    # ---- LEG 3: no forbidden middle. ---------------------------------
    if [ "$final_state" = "closed" ]; then
      inflight=$(q "SELECT count(*) FROM public.ai_session_requests WHERE session_id = '$session' AND state IN ('reserved','started','staged');")
      if [ "$inflight" != "0" ]; then
        echo "FAIL  $label trial $i: $inflight request row(s) left in-flight under a CLOSED session -- a request survived the closure unresolved"
        FAILED=1
      fi
      content=$(q "SELECT (SELECT count(*) FROM public.ai_session_turns WHERE session_id = '$session')
                        + (SELECT count(*) FROM public.ai_session_approvals WHERE session_id = '$session')
                        + (SELECT count(*) FROM public.ai_session_staging WHERE session_id = '$session');")
      if [ "$content" != "0" ]; then
        echo "FAIL  $label trial $i: $content content row(s) survived a closure -- Global Constraint: session content is deleted in the SAME transaction that closes the session"
        FAILED=1
      fi
    fi

    # ---- LEG 4: liveness. One of the two sides must have won. --------
    # Without this, a "fix" that made both sides fail cleanly -- no
    # deadlock, no warning, no forbidden middle -- would pass. For the
    # purge pairs the session was expired before the race, so a session
    # still 'active' with no completion committed means the purger
    # silently did nothing, which is the N1 consequence restated.
    local req_state
    req_state=$(q "SELECT state FROM public.ai_session_requests WHERE id = '$req';")
    if [ "$final_state" != "closed" ] && [ "$req_state" != "committed" ] && [ "$req_state" != "staged" ]; then
      echo "FAIL  $label trial $i: NEITHER side completed -- session state='$final_state', request state='$req_state'. One of the two admissible outcomes must happen; a race where both sides quietly fail is not a fix."
      echo "      completion backend: $(echo "$a_out" | tr '\n' ' ' | head -c 300)"
      echo "      closure backend:    $(echo "$b_out" | tr '\n' ' ' | head -c 300)"
      FAILED=1
    fi
  done

  SUMMARY+=("$(printf '  %-34s trials=%-3s deadlocks=%-3s purge_warnings=%s' "$label" "$TRIALS" "$deadlocks" "$purge_warns")")
  echo "  $label: $TRIALS trials, $deadlocks deadlocks, $purge_warns purger warnings"
}


# ======================================================================
# publish_ai_session_nearby_result x discard_ai_session_nearby_staging
#
# WHY THIS PAIR IS HERE NOW. Task 1's review (Finding 1, Critical) found
# that this pair STILL deadlocked after 20260953120000, and that Task 1
# had recorded it as fixed. This script was the test class that should
# have caught it and did not: it raced only the two CLOSURE paths, which
# is what the brief asked for, and discard is neither. That scope gap is
# how the finding slipped through, so the pair is wired in permanently.
#
# THE DEFECT IT PINS. discard took the ai_session_staging row FIRST
# (its DELETE) and the ai_session_requests row SECOND, and took NO
# relationship advisory lock at all. publish takes the advisory lock,
# then the session row, then the request row, and only ~74 lines later
# the staging row. Opposite orders over the same two rows, with no
# advisory lock on the discard side for publish's to serialize against:
# a textbook cycle. 20260953150000 gives discard the standard prefix
# (relationship advisory -> session row -> request row -> staging row),
# which is what closes it.
#
# WHY A CONFIGURABLE GAP IS NOT OPTIONAL HERE. The window is
# SUB-MILLISECOND on the real bodies, so a tight race is very nearly
# VACUOUS -- Task 1 measured 12/12 clean and concluded the pair was
# fixed, and the reviewer got 0/70 the same way before adding server
# load. Measured sensitivity on the FIXED publish against the UNFIXED
# discard, a gap inserted in discard's DELETE->UPDATE window:
#
#   gap     trials  deadlocks
#   none       70       0      <-- the vacuous window
#   none       40       1      (with 20 backends of additional load)
#   1 ms       15      14
#   10 ms      15      15
#   50 ms      15      15
#   250 ms     20      20
#
# A test that raced only the tight window would therefore report green
# against the BROKEN body -- precisely the failure this file exists to
# prevent. So the gapped windows are the primary legs and gap=0 is kept
# only as the realistic-timing control.
#
# HOW THE GAP IS INJECTED, and why this is sound. A gap inside discard's
# DELETE->UPDATE window cannot be produced from outside the function, so
# for the gapped legs the script CREATE OR REPLACEs discard with a copy
# that is byte-identical to the shipped body except for one added
# `PERFORM pg_sleep(<gap>)` between the DELETE and the UPDATE. The LOCK
# SEQUENCE under test is therefore the real one -- same advisory lock,
# same session row, same request row, same staging row, same order. When
# the gapped legs finish the script RESTORES the shipped body by
# re-applying the migration and ASSERTS the restore by md5 against the
# value captured before the first mutation, failing the script if it
# does not round-trip exactly. Without that assertion a crashed run
# could leave a sleeping discard in the database and every later test
# would be measuring a body nobody shipped.
#
# The gap list is configurable as $2 (comma-separated seconds) and
# defaults to the two windows the reviewer measured at 14/15 and 15/15
# pre-fix, which is the bar this fix round has to clear.
# ----------------------------------------------------------------------

# The migration that WINS for discard_ai_session_nearby_staging, used to
# restore the shipped body after the gapped legs mutate it.
#
# RESOLVED DYNAMICALLY, not hardcoded. It used to name
# 20260953150000_ai_session_discard_lock_order_fix.sql directly, and that
# broke the moment a later migration superseded that body: the restore
# re-applied a file that no longer wins, the md5 check correctly refused
# to confirm it, and this script failed with "the shipped
# discard_ai_session_nearby_staging body was NOT restored" -- a true
# report of a stale pointer, not of a lock-order defect. (Caught for real
# by Task 5 of the merge-blocker plan, whose 20260953190000 added
# discard's explicit NULL-actor guard.)
#
# The winner is the LAST migration by filename sort that actually
# redefines the function -- the same rule the migration runner applies,
# so this cannot disagree with what is deployed. The md5 assertion in
# restore_shipped_discard() is what makes a wrong answer here loud rather
# than silent, so the two together are safe.
DISCARD_MIGRATION="$(grep -l 'CREATE OR REPLACE FUNCTION public\.discard_ai_session_nearby_staging' supabase/migrations/*.sql 2>/dev/null | sort | tail -1)"
if [ -z "$DISCARD_MIGRATION" ]; then
  echo "FAIL  no migration defines discard_ai_session_nearby_staging -- cannot restore the shipped body after the gapped legs"
  exit 1
fi
PRISTINE_DISCARD_MD5=""

discard_md5() {
  q "SELECT md5(prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'discard_ai_session_nearby_staging';"
}

# Install discard with a sleep of $1 seconds between the staging DELETE
# and the request UPDATE. Everything else -- every lock, in order -- is
# the shipped body.
install_gapped_discard() {
  local gap="$1"
  psql -q -d "$DB" -v ON_ERROR_STOP=1 -t -A >/dev/null 2>&1 <<SQL
CREATE OR REPLACE FUNCTION public.discard_ai_session_nearby_staging(
  p_actor_id uuid, p_request_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS \$fn\$
DECLARE
  v_actor uuid;
  v_session_id uuid;
  v_relationship_id uuid;
BEGIN
  SELECT st.session_id, se.relationship_id
  INTO v_session_id, v_relationship_id
  FROM public.ai_session_staging st
  JOIN public.ai_sessions se ON se.id = st.session_id
  WHERE st.request_id = p_request_id;
  IF v_session_id IS NULL THEN RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));
  PERFORM 1 FROM public.ai_sessions WHERE id = v_session_id FOR UPDATE;
  PERFORM 1 FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE;
  SELECT requester_id INTO v_actor
  FROM public.ai_session_staging WHERE request_id = p_request_id;
  IF v_actor IS NULL THEN RETURN; END IF;
  IF v_actor != p_actor_id THEN
    RAISE EXCEPTION 'Only the requester may discard their own staged result';
  END IF;
  DELETE FROM public.ai_session_staging WHERE request_id = p_request_id;
  PERFORM pg_sleep($gap);
  UPDATE public.ai_session_requests SET state = 'cancelled' WHERE id = p_request_id;
  PERFORM public.mark_ai_assistant_usage_outcome(p_actor_id, p_request_id, 'succeeded', 2::smallint);
END; \$fn\$;
SQL
}

# Put the shipped body back, and PROVE it. A gapped body left behind
# would silently poison every later test in the suite.
restore_shipped_discard() {
  if [ ! -f "$DISCARD_MIGRATION" ]; then
    echo "FAIL  cannot restore the shipped discard body: $DISCARD_MIGRATION not found (run this script from the repository root)"
    FAILED=1
    return 1
  fi
  psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$DISCARD_MIGRATION" >/dev/null 2>&1
  local now
  now=$(discard_md5)
  if [ -z "$PRISTINE_DISCARD_MD5" ] || [ "$now" != "$PRISTINE_DISCARD_MD5" ]; then
    echo "FAIL  the shipped discard_ai_session_nearby_staging body was NOT restored"
    echo "      expected md5 $PRISTINE_DISCARD_MD5, got $now"
    echo "EXPLOIT: a gapped (pg_sleep) discard body may be left in $DB. Every later contract would be measuring a body nobody shipped. Rebuild: bash scripts/local_pg_setup.sh"
    FAILED=1
    return 1
  fi
  return 0
}

# One publish x discard race. $1 = launch order (ab = publish first,
# ba = discard first). $2 = gap in seconds, informational only (the body
# is already installed by the caller).
run_publish_discard() {
  local order="$1" gap="$2"
  local deadlocks=0 i
  local label="publish x discard (order $order, gap ${gap}s)"

  for i in $(seq 1 "$TRIALS"); do
    local rel ua ub pha phb setup session req tok td
    rel=$(uuidgen | tr 'A-Z' 'a-z')
    ua=$(uuidgen | tr 'A-Z' 'a-z')
    ub=$(uuidgen | tr 'A-Z' 'a-z')
    PHONE_SERIAL=$((PHONE_SERIAL + 1))
    pha="${PHONE_BASE}$(printf '%03d' $((PHONE_SERIAL * 2 - 1)))"
    phb="${PHONE_BASE}$(printf '%03d' $((PHONE_SERIAL * 2)))"

    # A FRESH fixture per trial is load-bearing for THIS pair
    # specifically: both sides consume the single staging row, so after
    # one trial has run the row is gone and every later trial on the
    # same fixture would race nothing and report a clean 0. (That is
    # exactly how the dispatching agent's own repro saw 1/12 -- trial 1
    # deadlocked and trials 2-12 could not.) No ON CONFLICT: a
    # collision RAISES and is reported as SETUP FAILED.
    setup=$(psql -q -d "$DB" -t -A 2>&1 <<SQL
DO \$\$
DECLARE
  v_session uuid;
  v_admit record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    ('$ua', 'pxd_race_a_${RUN_TAG}_${PHONE_SERIAL}@t.test'),
    ('$ub', 'pxd_race_b_${RUN_TAG}_${PHONE_SERIAL}@t.test');
  INSERT INTO public.users (id, phone, display_name) VALUES
    ('$ua', '$pha', 'A'), ('$ub', '$phb', 'B');
  INSERT INTO public.relationships (id, user_a, user_b, status)
    VALUES ('$rel', '$ua', '$ub', 'active');
  -- clock_timestamp(), never now(): now() is frozen per transaction, so
  -- two consent events written in one DO block would share an identical
  -- created_at and the consent lookup's tiebreak would fall to id DESC
  -- on a random uuid, making publish's consent gate a coin flip.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    ('$rel', '$ua', 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    ('$rel', '$ub', 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    '$ua', gen_random_uuid(), '$rel', 'nearby', 'shared', NULL, false);
  PERFORM public.approve_ai_session_context('$ua', v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context('$ub', v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session('$ua', v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    '$ua', gen_random_uuid(), v_session, 1, 'nearby:pxdrace');
  IF v_admit.request_id IS NULL THEN
    RAISE EXCEPTION 'admission failed: outcome=%', v_admit.outcome;
  END IF;
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  -- BOTH sides act on a STAGED result: publish commits it, discard
  -- throws it away. That shared staging row is the contended resource.
  PERFORM public.stage_ai_session_nearby_result(
    v_admit.worker_token, v_admit.request_id, 'a nearby reply', '[]'::jsonb);
  RAISE NOTICE 'FIXTURE % % %', v_session, v_admit.request_id, v_admit.worker_token;
END \$\$;
SQL
)
    read -r _ session req tok <<<"$(echo "$setup" | grep -o 'FIXTURE .*' | head -1)"
    if [ -z "${tok:-}" ]; then
      echo "FAIL  $label trial $i: SETUP FAILED -- $(echo "$setup" | tr '\n' ' ')"
      echo
      echo "EXPLOIT: a fixture could not be built, so this pair raced nothing. Rebuild the database (bash scripts/local_pg_setup.sh) and re-run; if it persists, a uuid/phone/email in this script collides with the rest of the suite and must be re-claimed."
      restore_shipped_discard
      exit 1
    fi

    # Both sides are user-initiated actions by the REQUESTER: publish
    # commits the staged Nearby result into the transcript, discard
    # throws it away. Both are requester-only, so both take '$ua'.
    local a_sql b_sql
    a_sql="SELECT committed FROM public.publish_ai_session_nearby_result('$ua','$req');"
    b_sql="SELECT public.discard_ai_session_nearby_staging('$ua','$req');"

    td=$(mktemp -d)
    if [ "$order" = "ab" ]; then
      psql -q -d "$DB" -t -A -c "$a_sql" > "$td/a" 2>&1 &
      psql -q -d "$DB" -t -A -c "$b_sql" > "$td/b" 2>&1 &
    else
      psql -q -d "$DB" -t -A -c "$b_sql" > "$td/b" 2>&1 &
      psql -q -d "$DB" -t -A -c "$a_sql" > "$td/a" 2>&1 &
    fi
    wait

    # ---- LEG 1: zero deadlocks, on either side. ----------------------
    # The reviewer's captured victim was the DISCARD side -- the user's
    # own "discard this Nearby result" failing with a raw SQLSTATE
    # 40P01 -- so both files are checked, not just publish's.
    if grep -q 'deadlock detected' "$td/a" "$td/b"; then
      deadlocks=$((deadlocks + 1))
      echo "FAIL  $label trial $i: DEADLOCK -- publish and discard take the staging and request rows in opposite orders again"
      echo "      publish backend: $(tr '\n' ' ' < "$td/a" | head -c 400)"
      echo "      discard backend: $(tr '\n' ' ' < "$td/b" | head -c 400)"
      FAILED=1
    fi

    local a_out b_out req_state staging_left turns
    a_out=$(cat "$td/a"); b_out=$(cat "$td/b")
    rm -rf "$td"

    req_state=$(q "SELECT state FROM public.ai_session_requests WHERE id = '$req';")
    staging_left=$(q "SELECT count(*) FROM public.ai_session_staging WHERE request_id = '$req';")
    turns=$(q "SELECT count(*) FROM public.ai_session_turns WHERE request_id = '$req';")

    # ---- LEG 2: exactly ONE of the two outcomes, never a mixture. ----
    # publish and discard are mutually exclusive terminal acts on one
    # staged result. The admissible end states are exactly:
    #   published -> request 'committed', 2 turns, staging row consumed
    #   discarded -> request 'cancelled', 0 turns, staging row consumed
    # Anything else is a real corruption, and this leg is what makes a
    # deadlock-free-but-wrong "fix" fail: serializing the two correctly
    # must still leave one of these two states, not a blend.
    if [ "$req_state" = "committed" ]; then
      if [ "$turns" != "2" ]; then
        echo "FAIL  $label trial $i: request 'committed' but $turns turn row(s), expected 2 -- the publish half-applied"
        FAILED=1
      fi
    elif [ "$req_state" = "cancelled" ]; then
      if [ "$turns" != "0" ]; then
        echo "FAIL  $label trial $i: request 'cancelled' (discarded) but $turns turn row(s) exist -- a discarded Nearby result reached the permanent transcript"
        FAILED=1
      fi
    else
      # ---- LEG 3: liveness. ------------------------------------------
      # One of the two user actions MUST have taken effect. A race in
      # which both sides quietly fail would satisfy legs 1 and 2 and be
      # useless -- the user pressed a button and nothing happened.
      echo "FAIL  $label trial $i: NEITHER side completed -- request state='$req_state', turns=$turns. One of publish or discard must take effect; a race where both quietly fail is not a fix."
      echo "      publish backend: $(echo "$a_out" | tr '\n' ' ' | head -c 300)"
      echo "      discard backend: $(echo "$b_out" | tr '\n' ' ' | head -c 300)"
      FAILED=1
    fi

    # ---- LEG 4: the staging row is consumed either way. -------------
    # Both admissible outcomes delete it. A surviving staging row means
    # the loser's work was rolled back but the winner's was not applied
    # -- or that the staged result is still readable after the user
    # discarded it.
    if [ "$staging_left" != "0" ]; then
      echo "FAIL  $label trial $i: $staging_left staging row(s) survived -- both publish and discard consume the staged result, so neither side can have completed"
      FAILED=1
    fi
  done

  SUMMARY+=("$(printf '  %-34s trials=%-3s deadlocks=%-3s gap=%ss' "publish x discard ($order)" "$TRIALS" "$deadlocks" "$gap")")
  echo "  $label: $TRIALS trials, $deadlocks deadlocks"
}
echo "Racing the three completion RPCs against end_ai_session and purge_expired_ai_sessions"
echo "($TRIALS trials per pair per ordering, 12 combinations)"
for rpc in commit stage publish; do
  for opp in end purge; do
    for order in ab ba; do
      run_pair "$rpc" "$opp" "$order"
    done
  done
done

# ----------------------------------------------------------------------
# publish x discard, both orderings, at each requested gap.
#
# The gap list is $2, comma-separated seconds. The default is
# "0,0.001,0.010": the realistic-timing control, then the two windows
# the reviewer measured at 14/15 and 15/15 deadlocks against the
# unfixed discard. gap=0 runs against the SHIPPED body with no mutation
# at all; the nonzero gaps run against a body that differs from the
# shipped one by exactly one added pg_sleep and is restored (and the
# restore asserted by md5) before the script exits.
GAPS="${2:-0,0.001,0.010}"

PRISTINE_DISCARD_MD5=$(discard_md5)
if [ -z "$PRISTINE_DISCARD_MD5" ]; then
  echo "FAIL  discard_ai_session_nearby_staging does not exist in $DB -- cannot race publish x discard"
  echo "EXPLOIT: migration 20260953150000 has not been applied. Rebuild: bash scripts/local_pg_setup.sh"
  exit 1
fi

# The pair cannot be raced at all unless BOTH sides take the relationship
# advisory lock, so assert that structurally before spending trials. A
# reverted discard (re-applied 20260953080000, last) would otherwise race
# green at gap=0 and the whole point of this section would be lost --
# which is precisely the shape of the finding that put it here.
if [ "$(q "SELECT position('pg_advisory_xact_lock' in prosrc) > 0 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'discard_ai_session_nearby_staging';")" != "t" ]; then
  echo "FAIL  the live discard_ai_session_nearby_staging takes NO relationship advisory lock"
  echo "EXPLOIT: that is Task 8's superseded body (20260953080000); 20260953150000 WINS and adds the advisory lock. Re-apply migrations in order."
  exit 1
fi

echo
echo "Racing publish_ai_session_nearby_result against discard_ai_session_nearby_staging"
echo "($TRIALS trials per ordering, gaps: $GAPS)"
PXD_RESTORE_NEEDED=0
IFS=',' read -r -a GAP_LIST <<< "$GAPS"
for gap in "${GAP_LIST[@]}"; do
  if [ "$gap" != "0" ]; then
    install_gapped_discard "$gap"
    PXD_RESTORE_NEEDED=1
    # A gapped body that failed to install would race the shipped one
    # and report a clean green for a window it never actually opened.
    if [ "$(discard_md5)" = "$PRISTINE_DISCARD_MD5" ]; then
      echo "FAIL  the gapped discard body (gap ${gap}s) did not install -- this leg would race the tight window and report a vacuous 0"
      FAILED=1
      continue
    fi
  fi
  for order in ab ba; do
    run_publish_discard "$order" "$gap"
  done
done

if [ "$PXD_RESTORE_NEEDED" != "0" ]; then
  restore_shipped_discard && echo "  shipped discard body restored and verified by md5 ($PRISTINE_DISCARD_MD5)"
fi

echo
echo "summary:"
for line in "${SUMMARY[@]}"; do echo "$line"; done

if [ "$FAILED" != "0" ]; then
  echo
  echo "EXPLOIT: the completion RPCs are not deadlock-free. See the failures above."
  exit 1
fi

echo
echo "all 12 completion x closure pair/orderings deadlock-free; purger never swallowed a failure into a WARNING"
echo "publish x discard deadlock-free in both orderings at gaps: $GAPS"

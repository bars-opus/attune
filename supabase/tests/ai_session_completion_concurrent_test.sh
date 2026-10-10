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
# Usage:
#   supabase/tests/ai_session_completion_concurrent_test.sh [TRIALS]
# TRIALS defaults to 10 (the required minimum per pair per ordering);
# the script runs 12 pair/ordering combinations, so the default is 120
# races. Hardcodes -d attune_test like the other *.sh contracts.
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

echo "Racing the three completion RPCs against end_ai_session and purge_expired_ai_sessions"
echo "($TRIALS trials per pair per ordering, 12 combinations)"
for rpc in commit stage publish; do
  for opp in end purge; do
    for order in ab ba; do
      run_pair "$rpc" "$opp" "$order"
    done
  done
done

echo
echo "summary:"
for line in "${SUMMARY[@]}"; do echo "$line"; done

if [ "$FAILED" != "0" ]; then
  echo
  echo "EXPLOIT: the completion RPCs are not deadlock-free against the closure paths. See the failures above."
  exit 1
fi

echo
echo "all 12 completion x closure pair/orderings deadlock-free; purger never swallowed a failure into a WARNING"

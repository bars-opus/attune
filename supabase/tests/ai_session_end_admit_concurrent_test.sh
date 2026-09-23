#!/usr/bin/env bash
# CORRECTION 2 / the plan's own self-review gap: end_ai_session racing
# admit_ai_session_generation on the SAME session must never leave an
# inconsistent result. The plan states this must be PROVEN with a
# concurrent script, not merely asserted from the lock-order rule.
#
# Both RPCs take pg_advisory_xact_lock(hashtext(relationship_id)) as
# their FIRST lock, then the session row -- the Global Constraints lock
# order. That makes the two transactions fully serialized against each
# other on this session, so exactly one of two outcomes is admissible:
#
#   OUTCOME A -- end wins the lock:
#     the session is 'closed', its content is purged, and the admission
#     (running second, re-reading the session under the relationship
#     lock) sees state != 'active' and RAISEs 'UNAVAILABLE'. Because it
#     raises rather than returns, its whole transaction rolls back --
#     so no request row and no quota reservation survive. Critically
#     there must be NO orphan: a request row that outlived the purge,
#     or a quota reservation charged for a request that then vanished.
#
#   OUTCOME B -- admit wins the lock:
#     the admission completes FULLY (request row inserted, quota
#     reserved) and commits; end then runs, closes the session, purges
#     content, and resolves that now-unreachable request to a terminal
#     state rather than leaving it readable as perpetually in-flight.
#     The quota reservation legitimately stays charged (it was a real
#     admitted attempt) but must have a resolved request row to account
#     for it.
#
# The forbidden middle is what this script actually hunts: a session
# 'closed' while a 'reserved'/'started' request row still hangs off it,
# or a quota reservation with no request row at all.
#
# Uses fixed UUIDs -- run `bash scripts/local_pg_setup.sh` first for a
# fresh DB, or a dirty rerun fails loudly on a UUID collision.
set -euo pipefail

REL="b1000000-0000-0000-0000-000000000033"
USER_A="b1000000-0000-0000-0000-000000000034"
USER_B="b1000000-0000-0000-0000-000000000035"
REQ="b1000000-0000-0000-0000-000000000733"

SETUP=$(psql -q -d attune_test -t -A <<SQL
INSERT INTO auth.users (id, email) VALUES
  ('$USER_A', 'endrace_a@t.test'), ('$USER_B', 'endrace_b@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('$USER_A', '+15550018001', 'A'), ('$USER_B', '+15550018002', 'B') ON CONFLICT DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES ('$REL', '$USER_A', '$USER_B', 'active') ON CONFLICT DO NOTHING;
INSERT INTO public.ai_processing_consent_events (relationship_id, user_id, policy_version, action, idempotency_key)
  VALUES ('$REL', '$USER_A', 'v1', 'granted', gen_random_uuid()),
         ('$REL', '$USER_B', 'v1', 'granted', gen_random_uuid());
SELECT session_id FROM public.prepare_ai_session('$USER_A', gen_random_uuid(), '$REL', 'ideas', 'shared', NULL, false);
SQL
)
SESSION=$(echo "$SETUP" | tail -n1)

psql -q -d attune_test <<SQL
SELECT public.approve_ai_session_context('$USER_A', '$SESSION', 1, 'd', 'v1');
SELECT public.approve_ai_session_context('$USER_B', '$SESSION', 1, 'd', 'v1');
SELECT public.activate_ai_session('$USER_A', '$SESSION', 1);
SQL

# Fire the two operations CONCURRENTLY from separate psql processes --
# separate Postgres backends, which is what makes the race real. The
# PARTNER (user B) ends, while the CREATOR (user A) admits: the
# either-partner-ends path crossing the admission path.
#
# HEAD_START selects which side is given the lock first, so BOTH
# admissible outcomes are actually exercised rather than whichever one
# the scheduler happens to favour. Run with no argument, the unbiased
# race runs (which in practice lands on OUTCOME A every time on this
# hardware -- the admission does strictly more work before reaching the
# lock); run with "admit", the admission is wrapped in a transaction
# that holds the relationship lock across a sleep, deterministically
# forcing OUTCOME B. The caller below runs both.
HEAD_START="${1:-none}"
RESULTS_DIR=$(mktemp -d)

if [ "$HEAD_START" = "admit" ]; then
  psql -q -d attune_test -t -A > "$RESULTS_DIR/admit.txt" 2>&1 <<SQL &
BEGIN;
SELECT outcome, request_id FROM public.admit_ai_session_generation('$USER_A', '$REQ', '$SESSION', 1, 'ideas:endrace');
SELECT pg_sleep(2);
COMMIT;
SQL
  sleep 0.5
  psql -q -d attune_test -t -A -c \
    "SELECT public.end_ai_session('$USER_B', '$SESSION');" \
    > "$RESULTS_DIR/end.txt" 2>&1 &
  wait
else
  psql -q -d attune_test -t -A -c \
    "SELECT outcome, request_id FROM public.admit_ai_session_generation('$USER_A', '$REQ', '$SESSION', 1, 'ideas:endrace');" \
    > "$RESULTS_DIR/admit.txt" 2>&1 &
  psql -q -d attune_test -t -A -c \
    "SELECT public.end_ai_session('$USER_B', '$SESSION');" \
    > "$RESULTS_DIR/end.txt" 2>&1 &
  wait
fi

echo "--- admit result ---"
cat "$RESULTS_DIR/admit.txt"
echo "--- end result ---"
cat "$RESULTS_DIR/end.txt"
echo "--------------------"

ADMIT_OUT=$(cat "$RESULTS_DIR/admit.txt")
rm -rf "$RESULTS_DIR"

# The end must ALWAYS succeed -- it is unconditional for a current
# member of an active shared session, whichever order the lock is won.
FINAL_STATE=$(psql -q -d attune_test -t -A -c "SELECT state FROM public.ai_sessions WHERE id = '$SESSION';")
if [ "$FINAL_STATE" != "closed" ]; then
  echo "EXPLOIT: after a concurrent end+admit the session is '$FINAL_STATE', expected 'closed' -- the end was lost"
  exit 1
fi

# INVARIANT 1 (the forbidden middle): no request row may remain
# in-flight under a closed session.
INFLIGHT=$(psql -q -d attune_test -t -A -c \
  "SELECT count(*) FROM public.ai_session_requests WHERE session_id = '$SESSION' AND state IN ('reserved','started','staged');")
if [ "$INFLIGHT" != "0" ]; then
  echo "EXPLOIT: $INFLIGHT request row(s) left in-flight under a CLOSED session -- an un-purged request survived end_ai_session"
  exit 1
fi

# INVARIANT 2: content purged regardless of who won.
CONTENT=$(psql -q -d attune_test -t -A -c \
  "SELECT (SELECT count(*) FROM public.ai_session_turns WHERE session_id = '$SESSION')
        + (SELECT count(*) FROM public.ai_session_approvals WHERE session_id = '$SESSION')
        + (SELECT count(*) FROM public.ai_session_staging WHERE session_id = '$SESSION');")
if [ "$CONTENT" != "0" ]; then
  echo "EXPLOIT: $CONTENT content row(s) survived end_ai_session under concurrency"
  exit 1
fi

# INVARIANT 3 (the other forbidden middle): a quota reservation must
# never outlive its request row. Either both exist (admit won and
# committed, end then resolved it) or neither does (admit rolled back).
REQ_ROWS=$(psql -q -d attune_test -t -A -c "SELECT count(*) FROM public.ai_session_requests WHERE id = '$REQ';")
QUOTA_ROWS=$(psql -q -d attune_test -t -A -c "SELECT count(*) FROM public.ai_assistant_usage WHERE request_id = '$REQ';")
if [ "$QUOTA_ROWS" -gt "$REQ_ROWS" ]; then
  echo "EXPLOIT: $QUOTA_ROWS quota reservation(s) charged but only $REQ_ROWS request row(s) exist -- quota leaked for a request that vanished"
  exit 1
fi

# Classify which admissible outcome actually happened, and check the
# consistency conditions specific to it.
if echo "$ADMIT_OUT" | grep -q '^admitted'; then
  WINNER="B (admit won the lock, then end closed and resolved it)"
  if [ "$REQ_ROWS" != "1" ]; then
    echo "EXPLOIT: admit returned 'admitted' but $REQ_ROWS request row(s) exist -- the admitted request vanished"
    exit 1
  fi
  REQ_STATE=$(psql -q -d attune_test -t -A -c "SELECT state FROM public.ai_session_requests WHERE id = '$REQ';")
  case "$REQ_STATE" in
    cancelled|failed|committed) : ;;
    *)
      echo "EXPLOIT: the admitted request is left in non-terminal state '$REQ_STATE' under a closed session"
      exit 1
      ;;
  esac
  # The epoch must have advanced, fencing the worker token this
  # admission just handed out -- otherwise a stale worker could still
  # commit a completion into a session the user already ended.
  ADMIT_EPOCH=$(psql -q -d attune_test -t -A -c "SELECT generation_epoch FROM public.ai_session_requests WHERE id = '$REQ';")
  SESSION_EPOCH=$(psql -q -d attune_test -t -A -c "SELECT generation_epoch FROM public.ai_sessions WHERE id = '$SESSION';")
  if [ "$SESSION_EPOCH" -le "$ADMIT_EPOCH" ]; then
    echo "EXPLOIT: session epoch $SESSION_EPOCH did not advance past the in-flight request's epoch $ADMIT_EPOCH -- a stale worker is left unfenced"
    exit 1
  fi
else
  WINNER="A (end won the lock, admission correctly rejected)"
  # The admission must have been REJECTED, not silently half-applied.
  if ! echo "$ADMIT_OUT" | grep -qE 'UNAVAILABLE|ERROR'; then
    echo "EXPLOIT: end won the race but the admission neither succeeded nor was rejected: '$ADMIT_OUT'"
    exit 1
  fi
  # Its whole transaction must have rolled back -- no row, no quota.
  if [ "$REQ_ROWS" != "0" ]; then
    echo "EXPLOIT: the rejected admission still left $REQ_ROWS request row(s) behind"
    exit 1
  fi
  if [ "$QUOTA_ROWS" != "0" ]; then
    echo "EXPLOIT: the rejected admission still charged $QUOTA_ROWS quota reservation(s)"
    exit 1
  fi
fi

echo "concurrent end+admit on one session: outcome $WINNER -- session closed, content purged, no in-flight request, no leaked quota"

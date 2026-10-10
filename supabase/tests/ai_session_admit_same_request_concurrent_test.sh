#!/usr/bin/env bash
# Proves admit_ai_session_generation is idempotent under genuine
# concurrent contention on the SAME request_id: exactly one caller may
# get 'admitted', and every other caller must get 'already_admitted'
# carrying the IDENTICAL attempt_n and worker_token -- never a second
# distinct admission, never a different attempt_n. Spec §6.2 step 2
# ("For an existing actor/request ID, return its state/result ...
# never a new provider lease").
#
# This is the same-key race that Plan A Task 5's
# ai_assistant_provider_start_concurrent_test.sh proves for the
# provider-start marker; the brief's own count-9/10 script proves the
# DIFFERENT-key attempt-boundary race instead, so both are needed.
#
# Uses fixed UUIDs -- run `bash scripts/local_pg_setup.sh` first for a
# fresh DB, or a dirty rerun fails loudly on a UUID collision.
#
# FIXTURE UUIDs (moved during Task 9's fix round 1): this script
# originally shared REL/USER_A with Task 6's
# ai_session_dispatch_claim_contracts.sql
# (...-000000000007 / ...-00000000006a). That contract leaves an ACTIVE
# private session on that (creator, relationship) pair, so once this
# script was wired into scripts/local_pg_setup.sh -- which runs the SQL
# suite first -- its own prepare_ai_session hit Task 3's
# one-private-session-per-creator-per-relationship slot limit
# ("A private session is already pending or active for this creator"),
# $SESSION came back empty, and every admission failed on an empty-string
# uuid cast. The script only ever passed because nothing invoked it after
# the SQL suite had run.
#
# This is the same fixture-collision class Tasks 4, 5 and 7 each hit; the
# fix is the same one Task 7's fix round applied -- move to a genuinely
# free block rather than loosen anything. ...-000000000038 /
# ...-00000000038a / ...-000000000702 were swept against every
# supabase/tests/* file and every migration before use. No assertion,
# expected value or RPC argument changed.
set -euo pipefail

REL="b1000000-0000-0000-0000-000000000038"
USER_A="b1000000-0000-0000-0000-00000000038a"
# FIXTURE COMPLETION (Task 3, merge-blockers plan). This script
# previously built a ONE-SIDED relationship (user_b NULL) with no
# consent events. admit_ai_session_generation now enforces the
# membership + AI-processing consent gate spec §7.2 requires
# (20260953140000), so every admission needs a real partner and two
# current grants. An ADDITION, not a correction -- the fixture was
# incomplete relative to §7.2, not wrong relative to the code as it
# then stood. NO assertion or expected outcome below is changed, so
# this script still proves exactly the lock-order/limit property it
# was written to prove.
# ai_processing_consent_events.idempotency_key is NOT NULL.
USER_B="b1000000-0000-0000-0000-000000000134"
REQ="b1000000-0000-0000-0000-000000000702"

SETUP=$(psql -q -d attune_test -t -A <<SQL
INSERT INTO auth.users (id, email) VALUES ('$USER_A', 'admitrace_same_a@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$USER_A', '+15550019001', 'A') ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id, email) VALUES ('$USER_B', 'admitgate_partner_same@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$USER_B', '+15550021005', 'B') ON CONFLICT DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ('$REL', '$USER_A', '$USER_B', 'active') ON CONFLICT DO NOTHING;
INSERT INTO public.ai_processing_consent_events (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES ('$REL', '$USER_A', 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
         ('$REL', '$USER_B', 'v1', 'granted', gen_random_uuid(), clock_timestamp());
SELECT session_id FROM public.prepare_ai_session('$USER_A', gen_random_uuid(), '$REL', 'ideas', 'private', NULL, false);
SQL
)
SESSION=$(echo "$SETUP" | tail -n1)

# Fail LEGIBLY if the fixture could not create a session. Without this,
# an empty $SESSION is interpolated into the admissions below and each
# one dies with `invalid input syntax for type uuid: ""` -- which reads
# like a product bug rather than the fixture collision it actually is.
# Task 9's fix round 1 hit exactly that.
case "$SESSION" in
  [0-9a-f]*-*-*-*-*) : ;;
  *)
    echo "SETUP FAILED: prepare_ai_session returned no session id. Raw setup output:"
    echo "$SETUP"
    exit 1
    ;;
esac

psql -q -d attune_test <<SQL
SELECT public.approve_ai_session_context('$USER_A', '$SESSION', 1, 'd', 'v1');
SELECT public.activate_ai_session('$USER_A', '$SESSION', 1);
SQL

# Fire 10 concurrent admissions with the SAME request_id from separate
# psql processes (separate Postgres backends -- this is what makes the
# race real, unlike sequential calls in one session).
RESULTS_DIR=$(mktemp -d)
for i in $(seq 1 10); do
  psql -q -d attune_test -t -A -c \
    "SELECT outcome, attempt_n, worker_token FROM public.admit_ai_session_generation('$USER_A', '$REQ', '$SESSION', 1, 'ideas:same-req');" \
    > "$RESULTS_DIR/result_$i.txt" 2>&1 &
done
wait

echo "--- raw results ---"
cat "$RESULTS_DIR"/result_*.txt
echo "-------------------"

ADMITTED_COUNT=$(cat "$RESULTS_DIR"/result_*.txt | grep -c '^admitted|' || true)
ALREADY_COUNT=$(cat "$RESULTS_DIR"/result_*.txt | grep -c '^already_admitted|' || true)
ADMITTED_LINE=$(cat "$RESULTS_DIR"/result_*.txt | grep '^admitted|' | head -n1 || true)
rm -rf "$RESULTS_DIR"

if [ "$ADMITTED_COUNT" != "1" ]; then
  echo "EXPLOIT: expected exactly 1 of 10 concurrent same-request_id admissions to return 'admitted', got $ADMITTED_COUNT"
  exit 1
fi
if [ "$ALREADY_COUNT" != "9" ]; then
  echo "EXPLOIT: expected the other 9 concurrent same-request_id calls to return 'already_admitted', got $ALREADY_COUNT"
  exit 1
fi

# The admitted attempt_n/worker_token must be exactly what every
# already_admitted caller was handed.
EXPECTED_ATTEMPT=$(echo "$ADMITTED_LINE" | cut -d'|' -f2)
EXPECTED_TOKEN=$(echo "$ADMITTED_LINE" | cut -d'|' -f3)

if [ "$EXPECTED_ATTEMPT" != "1" ]; then
  echo "EXPLOIT: the single admitted call should be attempt_n=1 on a fresh session, got $EXPECTED_ATTEMPT"
  exit 1
fi

# Exactly one request row, exactly one attempt consumed on the session.
ROW_COUNT=$(psql -q -d attune_test -t -A -c "SELECT count(*) FROM public.ai_session_requests WHERE session_id = '$SESSION';")
if [ "$ROW_COUNT" != "1" ]; then
  echo "EXPLOIT: 10 concurrent same-request_id admissions created $ROW_COUNT request rows, expected exactly 1"
  exit 1
fi

DB_STATE=$(psql -q -d attune_test -t -A -c "SELECT attempt_n || '|' || worker_token FROM public.ai_session_requests WHERE id = '$REQ';")
if [ "$DB_STATE" != "$EXPECTED_ATTEMPT|$EXPECTED_TOKEN" ]; then
  echo "EXPLOIT: the committed request row ($DB_STATE) does not match what the admitted caller returned ($EXPECTED_ATTEMPT|$EXPECTED_TOKEN)"
  exit 1
fi

FINAL_COUNT=$(psql -q -d attune_test -t -A -c "SELECT attempt_count FROM public.ai_sessions WHERE id = '$SESSION';")
if [ "$FINAL_COUNT" != "1" ]; then
  echo "EXPLOIT: 10 concurrent same-request_id admissions consumed $FINAL_COUNT session attempts, expected exactly 1"
  exit 1
fi

QUOTA_COUNT=$(psql -q -d attune_test -t -A -c "SELECT count(*) FROM public.ai_assistant_usage WHERE request_id = '$REQ';")
if [ "$QUOTA_COUNT" != "1" ]; then
  echo "EXPLOIT: 10 concurrent same-request_id admissions consumed $QUOTA_COUNT quota reservations, expected exactly 1"
  exit 1
fi

echo "concurrent same-request_id admission: 1 admitted + 9 already_admitted, identical attempt_n/worker_token, 1 request row, 1 attempt, 1 quota reservation"

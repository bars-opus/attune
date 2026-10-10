#!/usr/bin/env bash
# At attempt_count=9, two concurrent distinct admissions: exactly one
# must reach attempt_n=10; the other must get 'busy' or 'limit_reached',
# never attempt_n=11. Spec §6.2, §11 item 1.
# Uses fixed UUIDs -- run `bash scripts/local_pg_setup.sh` first for a
# fresh DB, or a dirty rerun fails loudly on a UUID collision.
set -euo pipefail

REL="b1000000-0000-0000-0000-000000000006"
USER_A="b1000000-0000-0000-0000-00000000005a"
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
USER_B="b1000000-0000-0000-0000-000000000133"

SETUP=$(psql -q -d attune_test -t -A <<SQL
INSERT INTO auth.users (id, email) VALUES ('$USER_A', 'race9_a@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$USER_A', '+15550013001', 'A') ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id, email) VALUES ('$USER_B', 'admitgate_partner_race9@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$USER_B', '+15550021004', 'B') ON CONFLICT DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ('$REL', '$USER_A', '$USER_B', 'active') ON CONFLICT DO NOTHING;
INSERT INTO public.ai_processing_consent_events (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES ('$REL', '$USER_A', 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
         ('$REL', '$USER_B', 'v1', 'granted', gen_random_uuid(), clock_timestamp());
SELECT session_id FROM public.prepare_ai_session('$USER_A', gen_random_uuid(), '$REL', 'ideas', 'private', NULL, false);
SQL
)
SESSION=$(echo "$SETUP" | tail -n1)

psql -q -d attune_test <<SQL
SELECT public.approve_ai_session_context('$USER_A', '$SESSION', 1, 'd', 'v1');
SELECT public.activate_ai_session('$USER_A', '$SESSION', 1);
-- Fast-forward to attempt_count=9 by admitting and immediately
-- completing 9 attempts as terminal (state='failed'), so the "one
-- in-flight attempt" check does not block the next admission -- this
-- test is about the ATTEMPT COUNT boundary, not the in-flight check
-- (that is Contract 2 in the sequential test above).
DO \$\$
DECLARE v_req uuid; v_i int;
BEGIN
  FOR v_i IN 1..9 LOOP
    SELECT request_id INTO v_req FROM public.admit_ai_session_generation(
      '$USER_A', gen_random_uuid(), '$SESSION', 1, 'ideas:fp-' || v_i
    );
    UPDATE public.ai_session_requests SET state = 'failed' WHERE id = v_req;
  END LOOP;
END \$\$;
SQL

# Two concurrent admissions from separate connections, both at
# attempt_count=9.
RESULTS_DIR=$(mktemp -d)
for i in 1 2; do
  psql -q -d attune_test -t -A -c \
    "SELECT outcome, attempt_n FROM public.admit_ai_session_generation('$USER_A', gen_random_uuid(), '$SESSION', 1, 'ideas:race-$i');" \
    > "$RESULTS_DIR/result_$i.txt" 2>&1 &
done
wait

ADMITTED_10_COUNT=$(cat "$RESULTS_DIR"/result_*.txt | grep -c '^admitted|10$' || true)
cat "$RESULTS_DIR"/result_*.txt
rm -rf "$RESULTS_DIR"

if [ "$ADMITTED_10_COUNT" != "1" ]; then
  echo "EXPLOIT: expected exactly 1 of 2 concurrent admissions at count=9 to reach attempt_n=10, got $ADMITTED_10_COUNT"
  exit 1
fi

FINAL_COUNT=$(psql -q -d attune_test -t -A -c "SELECT attempt_count FROM public.ai_sessions WHERE id = '$SESSION';")
if [ "$FINAL_COUNT" != "10" ]; then
  echo "EXPLOIT: final attempt_count should be exactly 10, got $FINAL_COUNT"
  exit 1
fi

echo "concurrent admission at count=9: exactly one reached attempt_n=10, final count=10"

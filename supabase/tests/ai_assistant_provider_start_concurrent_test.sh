#!/usr/bin/env bash
# Proves claim_ai_assistant_provider_start grants exactly one "true"
# claim under genuine concurrent contention on the same request_id.
# Spec §11 item 2.
# Uses fixed UUIDs -- run `bash scripts/local_pg_setup.sh` first for a
# fresh DB, or a dirty rerun fails loudly on a UUID collision.
set -euo pipefail

REL="c8000000-0000-0000-0000-000000000003"
USER_A="c8000000-0000-0000-0000-00000000020a"
USER_B="c8000000-0000-0000-0000-00000000020b"
REQ="c8000000-0000-0000-0000-000000000301"

psql -q -d attune_test <<SQL
INSERT INTO auth.users (id, email) VALUES ('$USER_A', 'race_a@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$USER_A', '+15559991001', 'A') ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id, email) VALUES ('$USER_B', 'race_b@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$USER_B', '+15559991002', 'B') ON CONFLICT DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ('$REL', '$USER_A', '$USER_B', 'active') ON CONFLICT DO NOTHING;
SELECT public.reserve_ai_assistant_quota('$USER_A', '$REQ', '$REL', 'assist');
SQL

# Fire 20 concurrent claim attempts on the SAME request_id from
# separate psql processes (separate Postgres backends -- this is what
# makes the race real, unlike sequential calls in one session).
RESULTS_DIR=$(mktemp -d)
for i in $(seq 1 20); do
  psql -q -d attune_test -t -A -c \
    "SELECT public.claim_ai_assistant_provider_start('$USER_A', '$REQ');" \
    > "$RESULTS_DIR/result_$i.txt" &
done
wait

TRUE_COUNT=$(grep -l '^t$' "$RESULTS_DIR"/result_*.txt | wc -l | tr -d ' ')
rm -rf "$RESULTS_DIR"

if [ "$TRUE_COUNT" != "1" ]; then
  echo "EXPLOIT: expected exactly 1 of 20 concurrent claims to return true, got $TRUE_COUNT"
  exit 1
fi

echo "concurrent provider-start claim: exactly one grant out of 20 racing attempts"

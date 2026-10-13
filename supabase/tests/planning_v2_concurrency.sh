#!/usr/bin/env bash
# Planning v2 concurrency (P1 Task 5). Review Focus 1 + spec acceptance 3.
#  Case 1: both partners open Planning for the first time simultaneously
#          -> exactly 7 categories and 7 templates.
#  Case 2: both partners tick DIFFERENT items of one checklist at the same
#          moment -> both ticks persist.
#  Case 3: both partners save the SAME text block from version 1
#          -> exactly one succeeds, the other gets planning:stale_version.
#  Case 4: one partner deletes a custom category while the other saves a
#          block inside it -> no deadlock (final review I1).
#  Case 5: one partner deletes a custom category while the other taps
#          "Start next one" on an entry in it -> no deadlock; the copy is
#          refused (not_found) rather than created in a deleted category.
#  Case 6: both partners take the 20th pin of a category at the same moment
#          -> exactly one succeeds, the other gets planning:limit_reached.
# Uses fixed UUIDs: run `bash scripts/local_pg_setup.sh --no-tests` first.
set -euo pipefail
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
DB="${ATTUNE_TEST_DB:-attune_test}"

REL="2f000000-0000-0000-0000-000000000001"
A="2f000000-0000-0000-0000-0000000000a1"
B="2f000000-0000-0000-0000-0000000000b1"
ENTRY="2f000000-0000-0000-0000-00000000e001"
LIST="2f000000-0000-0000-0000-00000000b001"
TEXT="2f000000-0000-0000-0000-00000000b002"
I1="2f000000-0000-0000-0000-0000000001a1"
I2="2f000000-0000-0000-0000-0000000001a2"

psql -q -d "$DB" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO auth.users (id, email) VALUES ('$A','v2cc_a@t.test'),('$B','v2cc_b@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$A','+12500000001','A'),('$B','+12500000002','B') ON CONFLICT DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ('$REL','$A','$B','active') ON CONFLICT DO NOTHING;
SQL

as_user() { # $1 user, $2 sql; holds the transaction open 1s so calls overlap
  psql -q -d "$DB" -t -A -v ON_ERROR_STOP=1 <<SQL
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"$1"}', true);
$2
SELECT pg_sleep(1);
COMMIT;
SQL
}

# Case 1
as_user "$A" "SELECT public.get_planning_home('$REL') IS NOT NULL;" >/dev/null & P1=$!
as_user "$B" "SELECT public.get_planning_home('$REL') IS NOT NULL;" >/dev/null & P2=$!
# A bare `wait` ignores exit codes: without the seeding lock the second
# partner's open ERRORS on the seed_key unique constraint while the count
# still reads 6. Each session must succeed, not just the end state.
wait $P1 || { echo "FAIL case 1: partner A's first open errored"; exit 1; }
wait $P2 || { echo "FAIL case 1: partner B's first open errored"; exit 1; }
CATS=$(psql -q -d "$DB" -t -A -c "SELECT count(*) FROM public.planning_categories WHERE relationship_id='$REL'")
TPLS=$(psql -q -d "$DB" -t -A -c "SELECT count(*) FROM public.planning_entries WHERE relationship_id='$REL' AND is_template")
[ "$CATS" = "9" ] && [ "$TPLS" = "9" ] || { echo "FAIL case 1: $CATS categories, $TPLS templates"; exit 1; }

# Setup for cases 2 and 3
as_user "$A" "
SELECT public.create_planning_entry('$ENTRY', (SELECT id FROM public.planning_categories WHERE relationship_id='$REL' AND seed_key='groceries'), 'Run', false, 'GHS') IS NOT NULL;
SELECT public.add_planning_block('$LIST', '$ENTRY', 'checklist', '{}', NULL, NULL, NULL) IS NOT NULL;
SELECT public.add_planning_block_item('$I1', '$LIST', 'Tomatoes', NULL, NULL, NULL, NULL) IS NOT NULL;
SELECT public.add_planning_block_item('$I2', '$LIST', 'Milk', NULL, NULL, NULL, '$I1') IS NOT NULL;
SELECT public.add_planning_block('$TEXT', '$ENTRY', 'text', '{\"delta\":[{\"insert\":\"v1\\n\"}]}', NULL, NULL, '$LIST') IS NOT NULL;" >/dev/null

# Case 2
as_user "$A" "SELECT public.set_planning_block_item_checked('$I1', true, gen_random_uuid()) IS NOT NULL;" >/dev/null & P1=$!
as_user "$B" "SELECT public.set_planning_block_item_checked('$I2', true, gen_random_uuid()) IS NOT NULL;" >/dev/null & P2=$!
wait $P1 || { echo "FAIL case 2: partner A's tick errored"; exit 1; }
wait $P2 || { echo "FAIL case 2: partner B's tick errored"; exit 1; }
TICKED=$(psql -q -d "$DB" -t -A -c "SELECT count(*) FROM public.planning_block_items WHERE block_id='$LIST' AND checked_at IS NOT NULL")
[ "$TICKED" = "2" ] || { echo "FAIL case 2: $TICKED of 2 ticks persisted"; exit 1; }

# Case 3
OUT=$(mktemp -d)
( as_user "$A" "SELECT public.update_planning_block('$TEXT', 1, '{\"delta\":[{\"insert\":\"A\\n\"}]}', NULL, NULL) IS NOT NULL;" >"$OUT/a" 2>&1 || true ) &
( as_user "$B" "SELECT public.update_planning_block('$TEXT', 1, '{\"delta\":[{\"insert\":\"B\\n\"}]}', NULL, NULL) IS NOT NULL;" >"$OUT/b" 2>&1 || true ) &
wait
STALE=$(cat "$OUT/a" "$OUT/b" | grep -c "planning:stale_version" || true)
VERSION=$(psql -q -d "$DB" -t -A -c "SELECT version FROM public.planning_blocks WHERE id='$TEXT'")
[ "$STALE" = "1" ] && [ "$VERSION" = "2" ] || { echo "FAIL case 3: stale=$STALE version=$VERSION"; cat "$OUT/a" "$OUT/b"; exit 1; }

# Cases 4 and 5 (final review I1). Each RPC's FIRST lock is taken by hand
# and held, so the interleaving that deadlocked is forced every run instead
# of depending on timing: the waiting RPC then re-takes that same lock (a
# no-op) and continues exactly as it would in production.
CAT="2f000000-0000-0000-0000-00000000ca01"
E2="2f000000-0000-0000-0000-00000000e002"
B3="2f000000-0000-0000-0000-00000000b003"
as_user "$A" "
SELECT public.create_planning_category('$CAT', '$REL', 'Moving', 'box', 'orange') IS NOT NULL;
SELECT public.create_planning_entry('$E2', '$CAT', 'Boxes', false, 'GHS') IS NOT NULL;
SELECT public.add_planning_block('$B3', '$E2', 'text', '{\"delta\":[{\"insert\":\"v1\\n\"}]}', NULL, NULL, NULL) IS NOT NULL;" >/dev/null

held() { # $1 user, $2 lock statement, $3 rpc; takes the lock, waits, then runs the rpc
  psql -q -d "$DB" -t -A <<SQL
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"$1"}', true);
$2
SELECT pg_sleep(1);
$3
COMMIT;
SQL
}

# Case 4: B already holds the entry (update_planning_block's first lock); A deletes the category.
( held "$B" "SELECT 1 FROM public.planning_entries WHERE id='$E2' FOR UPDATE;" \
    "SELECT public.update_planning_block('$B3', 1, '{\"delta\":[{\"insert\":\"B\\n\"}]}', NULL, NULL) IS NOT NULL;" >"$OUT/c4b" 2>&1 || true ) &
( sleep 0.3; as_user "$A" "SELECT public.delete_planning_category('$CAT') IS NOT NULL;" >"$OUT/c4a" 2>&1 || true ) &
wait
if grep -q "deadlock detected" "$OUT/c4a" "$OUT/c4b"; then echo "FAIL case 4: deadlock"; cat "$OUT/c4a" "$OUT/c4b"; exit 1; fi

# Case 5: A already holds the category (delete_planning_category's first lock); B duplicates an entry in it.
E3="2f000000-0000-0000-0000-00000000e003"
E4="2f000000-0000-0000-0000-00000000e004"
CAT2="2f000000-0000-0000-0000-00000000ca02"
as_user "$A" "
SELECT public.create_planning_category('$CAT2', '$REL', 'Wedding', 'ring', 'rose') IS NOT NULL;
SELECT public.create_planning_entry('$E3', '$CAT2', 'Venue', false, 'GHS') IS NOT NULL;" >/dev/null
( held "$A" "SELECT 1 FROM public.planning_categories WHERE id='$CAT2' FOR UPDATE;" \
    "SELECT public.delete_planning_category('$CAT2') IS NOT NULL;" >"$OUT/c5a" 2>&1 || true ) &
( sleep 0.3; as_user "$B" "SELECT public.duplicate_planning_entry('$E3', '$E4', 'Venue again') IS NOT NULL;" >"$OUT/c5b" 2>&1 || true ) &
wait
if grep -q "deadlock detected" "$OUT/c5a" "$OUT/c5b"; then echo "FAIL case 5: deadlock"; cat "$OUT/c5a" "$OUT/c5b"; exit 1; fi
LIVE_IN_DELETED=$(psql -q -d "$DB" -t -A -c "SELECT count(*) FROM public.planning_entries e JOIN public.planning_categories c ON c.id = e.category_id WHERE c.id = '$CAT2' AND c.deleted_at IS NOT NULL AND e.deleted_at IS NULL")
[ "$LIVE_IN_DELETED" = "0" ] || { echo "FAIL case 5: $LIVE_IN_DELETED live entry in a deleted category"; exit 1; }

# Case 6: 19 pins exist; both partners pin a different entry concurrently.
CAT3="2f000000-0000-0000-0000-00000000ca03"
as_user "$A" "
SELECT public.create_planning_category('$CAT3', '$REL', 'Pins', 'star', 'teal') IS NOT NULL;
SELECT count(public.create_planning_entry(gen_random_uuid(), '$CAT3', 'P' || g, false, 'GHS')) FROM generate_series(1, 21) g;
SELECT count(public.pin_planning_entry(id, true)) FROM (
  SELECT id FROM public.planning_entries WHERE category_id = '$CAT3' AND NOT is_template ORDER BY id LIMIT 19) x;" >/dev/null
P20=$(psql -q -d "$DB" -t -A -c "SELECT id FROM public.planning_entries WHERE category_id='$CAT3' AND NOT is_template AND pinned_at IS NULL ORDER BY id LIMIT 1")
P21=$(psql -q -d "$DB" -t -A -c "SELECT id FROM public.planning_entries WHERE category_id='$CAT3' AND NOT is_template AND pinned_at IS NULL ORDER BY id DESC LIMIT 1")
( as_user "$A" "SELECT public.pin_planning_entry('$P20', true) IS NOT NULL;" >"$OUT/c6a" 2>&1 || true ) &
( as_user "$B" "SELECT public.pin_planning_entry('$P21', true) IS NOT NULL;" >"$OUT/c6b" 2>&1 || true ) &
wait
PINS=$(psql -q -d "$DB" -t -A -c "SELECT count(*) FROM public.planning_entries WHERE category_id='$CAT3' AND pinned_at IS NOT NULL AND deleted_at IS NULL")
LIMITED=$(cat "$OUT/c6a" "$OUT/c6b" | grep -c "planning:limit_reached" || true)
[ "$PINS" = "20" ] && [ "$LIMITED" = "1" ] || { echo "FAIL case 6: $PINS pins, $LIMITED refused"; cat "$OUT/c6a" "$OUT/c6b"; exit 1; }

echo "planning_v2_concurrency: PASS"

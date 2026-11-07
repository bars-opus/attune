#!/usr/bin/env bash
#
# Two-connection races between the Dating kill switch (Spec 2 §2.4) and the
# people it can meet: pausing, leaving by withdrawing a consent, leaving,
# moving one's Dating country, across one country and across a border.
#
# Lives outside supabase/tests because those run in a single transaction
# and a lock race needs two connections that really interleave. Written for
# the Spec 2 W1 final fix (I-1, M-3): before it, a pause or a consent
# withdrawal that met a switch failed with a raw 40P01 deadlock and the
# person's action was lost (final review races r3, r4, r4c, r5).
#
# What each case proves (none can be proven in one transaction):
#   same-country (pause, plain pause, withdrawal, country change, exit):
#     every Dating writer takes the person's same-gender locks SHARED with
#     the setup lock, before any row, and the switch takes them EXCLUSIVE
#     before any row, so the two serialise: no deadlock at all, and the
#     person's action takes effect.
#   cross-border (pause, withdrawal): a writer in another country whose
#     introductions the switch is ending can still close a lock cycle on
#     the introduction rows; the loser retries inside its own transaction
#     (savepoints) and both complete. No 40P01 ever reaches a caller.
#
# The interleaving is forced by a one-shot BEFORE trigger that sleeps in
# the session that asks for it (GUC race.sleep_<table>_<op>), so the first
# side holds its first row when the second side starts.
#
# Usage: scripts/concurrency/dating_kill_switch_races.sh <scratch_db>
# The database MUST be a throwaway copy with every migration applied and
# the seed rows present (for example: createdb from `pg_dump -s` of a
# migrated database plus its config tables). This script installs a "race"
# schema, delay triggers on six Dating tables and test keys on the
# database (ALTER DATABASE). It refuses attune_test and attune_spec3a.
set -uo pipefail
DB="${1:-}"
case "$DB" in
  ''|attune_test|attune_spec3a|postgres|template0|template1)
    echo "usage: $0 <scratch_db>  (never attune_test or attune_spec3a)" >&2
    exit 2 ;;
esac
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
P="psql -X -q -d $DB"

# ---------------------------------------------------------------- harness
cat > "$T/setup.sql" <<SQL
\set ON_ERROR_STOP 1
ALTER DATABASE $DB SET app.settings.dating_field_key = 'race-field-key-0123456789abcdef-0123456789';
ALTER DATABASE $DB SET app.settings.dating_exclusion_key = 'race-exclusion-key';
\c $DB
SELECT private.seed_dating_exclusion_key_fingerprint(), private.seed_dating_field_key_fingerprint();
UPDATE public.feature_flags SET enabled = true WHERE key IN ('dating_mode_enabled', 'dating_same_gender_matching');
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "same_gender_enabled": true}') ->> 'ok';
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') ->> 'ok';

CREATE SCHEMA IF NOT EXISTS race;
CREATE OR REPLACE FUNCTION race.delay() RETURNS trigger LANGUAGE plpgsql AS \$\$
DECLARE
  v text := current_setting('race.sleep_' || TG_TABLE_NAME || '_' || lower(TG_OP), true);
BEGIN
  IF coalesce(v, '') <> '' AND nextval(split_part(v, ':', 2)::regclass) = 1 THEN
    PERFORM pg_sleep(split_part(v, ':', 1)::numeric);
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END \$\$;
DO \$\$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['dating_profile_sensitive', 'dating_enrollments', 'dating_profiles', 'dating_preferences',
                           'dating_introductions', 'dating_matches'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS zz_race_delay ON public.%I', t);
    EXECUTE format('CREATE TRIGGER zz_race_delay BEFORE UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION race.delay()', t);
  END LOOP;
END \$\$;
CREATE OR REPLACE FUNCTION race.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS \$\$
  SELECT ('5e2f0000-0000-0000-0000-0000000000' || p_n)::uuid;
\$\$;
CREATE OR REPLACE FUNCTION race.call(p_user uuid, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS \$\$
DECLARE v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, false);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE p_sql INTO v;
  RESET ROLE;
  RETURN v;
END \$\$;
CREATE OR REPLACE FUNCTION race.key(p text) RETURNS text LANGUAGE sql AS \$\$
  SELECT 'race-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
\$\$;
-- An eligible adult with every D4 consent, through D2, D3, D5, D6, active.
CREATE OR REPLACE FUNCTION race.person(p_n text, p_country text, p_region text, p_identity text, p_seeking text[],
                                       p_pools text[] DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS \$\$
DECLARE
  v_u constant uuid := race.id(p_n);
  v jsonb;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_u, '15558709' || p_n, now(), now() - interval '60 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, '15558709' || p_n, 'Race Person ' || p_n, 'dating', now() - interval '60 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_u, current_date - interval '30 years 10 days');
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile', 'special_category_faith']) AS p;
  v := race.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', race.key('d2')));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'D2 %', v; END IF;
  v := race.call(v_u, format('SELECT public.save_dating_location(%L, %L, %L, NULL, ''region'')', race.key('d3'), p_country, p_region));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'D3 %', v; END IF;
  v := race.call(v_u, format('SELECT public.save_dating_identity(%L, %L, NULL, NULL, %L::text[], true)', race.key('d5'), p_identity, p_pools));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'D5 %', v; END IF;
  v := race.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, %L::text[], 25, 40)', race.key('d6'), p_seeking));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'D6 %', v; END IF;
  UPDATE public.dating_profiles SET profile_state = 'active', verification_state = 'verified' WHERE user_id = v_u;
  UPDATE public.dating_enrollments SET state = 'active', activated_at = now() WHERE user_id = v_u;
  RETURN v_u;
END \$\$;
CREATE OR REPLACE FUNCTION race.intro(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE plpgsql AS \$\$
DECLARE v_low uuid; v_high uuid; v_id uuid;
BEGIN
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (least(p_a, p_b), 'race') RETURNING id INTO v_low;
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (greatest(p_a, p_b), 'race') RETURNING id INTO v_high;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state,
                                           algorithm_version, snapshot_low_id, snapshot_high_id, internal_score)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'some_shared_ground', 'presented',
          'race', v_low, v_high, 0.5) RETURNING id INTO v_id;
  RETURN v_id;
END \$\$;
CREATE OR REPLACE FUNCTION race.match(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS \$\$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active') RETURNING id;
\$\$;
CREATE OR REPLACE FUNCTION race.enrol(p_u uuid) RETURNS text LANGUAGE sql AS \$\$
  SELECT e.state || '/' || coalesce(e.pause_reason, '-') FROM public.dating_enrollments AS e WHERE e.user_id = p_u;
\$\$;
CREATE OR REPLACE FUNCTION race.reset() RETURNS void LANGUAGE plpgsql AS \$\$
BEGIN
  DELETE FROM public.dating_matches WHERE user_low_id::text LIKE '5e2f%' OR user_high_id::text LIKE '5e2f%';
  DELETE FROM public.dating_introductions WHERE user_low_id::text LIKE '5e2f%' OR user_high_id::text LIKE '5e2f%';
  DELETE FROM public.dating_feature_snapshots WHERE user_id::text LIKE '5e2f%';
  DELETE FROM auth.users WHERE id::text LIKE '5e2f%';
  DELETE FROM public.users WHERE id::text LIKE '5e2f%';
  DELETE FROM private.dating_kill_switch_pending;
  DELETE FROM public.dating_rpc_idempotency WHERE user_id::text LIKE '5e2f%';
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  IF NOT (public.dating_country_config('GH')).same_gender_enabled THEN
    PERFORM public.publish_country_config('GH', '{"same_gender_enabled": true}');
  END IF;
END \$\$;
CREATE SEQUENCE IF NOT EXISTS race.s1;
CREATE OR REPLACE FUNCTION race.deadlocks() RETURNS bigint LANGUAGE sql AS \$\$
  SELECT deadlocks FROM pg_stat_database WHERE datname = current_database();
\$\$;
SQL
if ! $P -v ON_ERROR_STOP=1 -f "$T/setup.sql" > "$T/setup.log" 2>&1; then
  echo "setup failed:"; cat "$T/setup.log"; exit 1
fi

fail=0
# run <name> <fixture sql> <session A sql> <session B sql> <check sql> [serialised]
# The check prints 'ok' or the reason; any ERROR in either session fails.
# With "serialised" the case must also detect no deadlock at all: the two
# sides waited for each other's same-gender lock instead.
run() {
  local name=$1
  printf '%s\n' "$2" > "$T/fx.sql"; printf '%s\n' "$3" > "$T/a.sql"
  printf '%s\n' "$4" > "$T/b.sql"; printf '%s\n' "$5" > "$T/ck.sql"
  if ! $P -v ON_ERROR_STOP=1 -f "$T/fx.sql" > "$T/fx.log" 2>&1; then
    echo "FAIL  $name: fixture: $(grep -m1 ERROR "$T/fx.log")"; fail=1; return
  fi
  local before; before=$($P -Atc 'SELECT race.deadlocks()')
  ( $P -At -f "$T/a.sql" > "$T/a.log" 2>&1 ) & local pa=$!
  ( $P -At -f "$T/b.sql" > "$T/b.log" 2>&1 ) & local pb=$!
  wait $pa $pb
  sleep 0.6 # pg_stat_database is updated on a short delay
  local after; after=$($P -Atc 'SELECT race.deadlocks()')
  local check; check=$($P -At -f "$T/ck.sql" 2>&1 | tail -1)
  local err; err=$(grep -h -m1 -E 'ERROR|deadlock' "$T/a.log" "$T/b.log")
  if [ -n "$err" ]; then
    echo "FAIL  $name: a caller saw: $err"; fail=1
  elif [ "${6:-}" = serialised ] && [ "$after" != "$before" ]; then
    echo "FAIL  $name: $((after - before)) deadlock(s): the shared lock order did not serialise it"; fail=1
  elif [ "$check" != "ok" ]; then
    echo "FAIL  $name: $check"; fail=1
  else
    echo "PASS  $name (deadlocks detected and retried: $((after - before)))"
  fi
}

# Same-country fixture: P non-binary (meets everyone), A a woman meeting
# women, M a plain man; P-A introduced and matched, A-M introduced.
FX_GH="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
SELECT race.person('01', 'GH', 'AA', 'non_binary', ARRAY['man','non_binary','woman'], ARRAY['woman']),
       race.person('02', 'GH', 'AA', 'woman', ARRAY['woman']),
       race.person('03', 'GH', 'AA', 'man', ARRAY['woman']);
SELECT race.intro(race.id('01'), race.id('02')), race.match(race.id('01'), race.id('02')),
       race.intro(race.id('01'), race.id('03')), race.intro(race.id('02'), race.id('03'));"
SWITCH_GH="SELECT pg_sleep(0.5); SELECT public.publish_country_config('GH', '{\"same_gender_enabled\": false}') ->> 'affected';"
# The switch must have run too (a switch that failed and was left pending
# would also leave the other side unharmed): P, the non-binary person in
# Ghana, is paused by it, Ghana is switched off, and nothing is pending.
SWITCH_RAN="(SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = race.id('01')) = 'paused/same_gender_switch'
             AND NOT (public.dating_country_config('GH')).same_gender_enabled
             AND NOT EXISTS (SELECT 1 FROM private.dating_kill_switch_pending)"

run "pause (not plain) vs the country switch" "$FX_GH" \
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT race.call(race.id('02'), format('SELECT to_jsonb(public.pause_dating_mode(%L))', race.key('pause'))) ->> 'state';" \
  "$SWITCH_GH" \
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run' WHEN race.enrol(race.id('02')) = 'paused/user' THEN 'ok' ELSE 'pause lost: ' || coalesce(race.enrol(race.id('02')), 'none') END;" serialised

run "pause (plain man) vs the country switch" "$FX_GH" \
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT race.call(race.id('03'), format('SELECT to_jsonb(public.pause_dating_mode(%L))', race.key('pause'))) ->> 'state';" \
  "$SWITCH_GH" \
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run' WHEN race.enrol(race.id('03')) = 'paused/user' THEN 'ok' ELSE 'pause lost: ' || coalesce(race.enrol(race.id('03')), 'none') END;" serialised

run "consent withdrawal (leaving) vs the country switch" "$FX_GH" \
  "SET race.sleep_dating_profile_sensitive_delete = '2:race.s1';
   SELECT race.call(race.id('02'), format('SELECT to_jsonb(public.record_dating_consent(%L, ''dating_opt_in'', ''withdraw'', ''dating-2.0'', NULL))', race.key('wd')));" \
  "$SWITCH_GH" \
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run'
               WHEN race.enrol(race.id('02')) = 'exited/-' AND NOT private.dating_consent_granted(race.id('02'), 'dating_opt_in')
                    AND NOT EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = race.id('02'))
               THEN 'ok' ELSE 'withdrawal lost: ' || coalesce(race.enrol(race.id('02')), 'none') END;" serialised

run "exit vs the country switch" "$FX_GH" \
  "SET race.sleep_dating_profile_sensitive_delete = '2:race.s1';
   SELECT race.call(race.id('02'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \
  "$SWITCH_GH" \
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run' WHEN race.enrol(race.id('02')) = 'exited/-' THEN 'ok' ELSE 'exit lost: ' || coalesce(race.enrol(race.id('02')), 'none') END;" serialised

run "country change (GB to GH) vs the global flag off" \
  "SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
   SELECT race.person('01', 'GB', 'TLI', 'woman', ARRAY['woman']), race.person('02', 'GB', 'TLI', 'woman', ARRAY['woman']);
   SELECT race.intro(race.id('01'), race.id('02')), race.match(race.id('01'), race.id('02'));" \
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT race.call(race.id('02'), format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''country'')', race.key('d3')));" \
  "SELECT pg_sleep(0.5); UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';" \
  "SELECT CASE WHEN (SELECT country_code FROM public.dating_profiles WHERE user_id = race.id('02')) = 'GH'
                    AND (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE user_low_id = race.id('01')) = 'closed/other'
               THEN 'ok' ELSE 'move lost or match kept: ' || coalesce((SELECT country_code FROM public.dating_profiles WHERE user_id = race.id('02')), '-') END;" serialised

# Cross-border fixture: W a plain woman in the UK, introduced to Q1 and Q2,
# both non-binary in Ghana (W-Q2 stored first, so W locks it first while
# the switch, which goes in id order, takes W-Q1 first).
FX_XB="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
SELECT race.person('06', 'GB', 'TLI', 'woman', ARRAY['man']),
       race.person('07', 'GH', 'AA', 'non_binary', ARRAY['man','non_binary','woman'], ARRAY['woman']),
       race.person('08', 'GH', 'AA', 'non_binary', ARRAY['man','non_binary','woman'], ARRAY['woman']);
SELECT race.intro(race.id('06'), race.id('08')), race.intro(race.id('06'), race.id('07'));"

run "pause across the border vs the country switch" "$FX_XB" \
  "SET race.sleep_dating_introductions_update = '2:race.s1';
   SELECT race.call(race.id('06'), format('SELECT to_jsonb(public.pause_dating_mode(%L))', race.key('pause'))) ->> 'state';" \
  "$SWITCH_GH" \
  "SELECT CASE WHEN race.enrol(race.id('06')) = 'paused/user'
                    AND race.enrol(race.id('07')) = 'paused/same_gender_switch' AND race.enrol(race.id('08')) = 'paused/same_gender_switch'
               THEN 'ok' ELSE 'pause or switch lost: ' || concat_ws(' ', race.enrol(race.id('06')), race.enrol(race.id('07')), race.enrol(race.id('08'))) END;"

run "withdrawal across the border vs the country switch" "$FX_XB" \
  "SET race.sleep_dating_introductions_delete = '2:race.s1';
   SELECT race.call(race.id('06'), format('SELECT to_jsonb(public.record_dating_consent(%L, ''dating_opt_in'', ''withdraw'', ''dating-2.0'', NULL))', race.key('wd')));" \
  "$SWITCH_GH" \
  "SELECT CASE WHEN race.enrol(race.id('06')) = 'exited/-' AND race.enrol(race.id('07')) = 'paused/same_gender_switch'
               THEN 'ok' ELSE 'withdrawal or switch lost: ' || concat_ws(' ', race.enrol(race.id('06')), race.enrol(race.id('07'))) END;"

$P -c "SELECT race.reset();" > /dev/null 2>&1
exit $fail

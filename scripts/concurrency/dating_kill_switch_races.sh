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
#   same-country (pause, plain pause, withdrawal, country change, exit,
#   and Spec 2 W2's path change):
#     every Dating writer takes the person's same-gender locks SHARED with
#     the setup lock, before any row, and the switch takes them EXCLUSIVE
#     before any row, so the two serialise: no deadlock at all, and the
#     person's action takes effect.
#   path change behind a long switch (Spec 2 W2 Task 3 fix round 1): the
#     path change never fails, even under a statement timeout shorter than
#     the switch; its pause gives up after its own lock_timeout, is counted,
#     and the gate cron's sweep pauses the person afterwards.
#   resume vs a path change (both orders): whichever lands first, the
#     person ends paused with path_change on Just for me.
#   the gentle-wait reflection (Spec 2 W2 Task 4 fix round 1): clearing it
#     and opening D0 never wait, neither behind a long country switch nor
#     behind the person's own setup write, under a 3s statement timeout;
#     a view D0 could not mark is skipped and counted.
#   photo writers vs leaving (Spec 2 W3c): an insert, an exit behind
#     which the insert waits past its lock_timeout, a CSAM hit (its hold
#     suspends the enrolment) and a delete behind a held photo row: the
#     setup lock serialises them, leaving always completes, the loser
#     answers a named refusal, and a delete answers busy in time.
#   a gone CSAM hit's Dating hold vs leaving (Spec 2 W3c Task 9): the
#     hold takes the setup lock first; exit completes, the hold is kept.
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
# migrated database plus its config tables, public.metric_key_prefixes
# among them: without its 'dating.' row no Dating counter is kept and the
# "was counted" cases fail; setup refuses such a copy. `createdb -T` of a
# migrated database copies everything). This script installs a "race"
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
ALTER DATABASE $DB SET app.settings.dating_push_key = 'race-push-key'; -- Spec 2 W3 final (M-1): the notice cases queue a push (R-44)
\c $DB
DO \$\$ BEGIN -- W2 final review M-7: the counters these cases read need their prefix row
  IF NOT EXISTS (SELECT 1 FROM public.metric_key_prefixes WHERE prefix = 'dating.') THEN
    RAISE EXCEPTION 'race setup: public.metric_key_prefixes has no dating. row (copy the config tables too)';
  END IF;
END \$\$;
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
                           'dating_introductions', 'dating_matches',
                           'dating_profile_photos', 'dating_photo_upload_intents'] LOOP -- Spec 2 W3c (Task 8)
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
  DELETE FROM race.outcome; -- Spec 2 W2 Task 3 fix round 1
  IF EXISTS (SELECT 1 FROM race.saved_fn) THEN -- a stubbed completeness check is put back
    EXECUTE (SELECT def FROM race.saved_fn);
    DELETE FROM race.saved_fn;
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  IF NOT (public.dating_country_config('GH')).same_gender_enabled THEN
    PERFORM public.publish_country_config('GH', '{"same_gender_enabled": true}');
  END IF;
END \$\$;
CREATE SEQUENCE IF NOT EXISTS race.s1;
-- Spec 2 W2 Task 3 fix round 1: a refusal the check must see.
CREATE TABLE IF NOT EXISTS race.outcome (name text PRIMARY KEY, result text);
CREATE TABLE IF NOT EXISTS race.saved_fn (def text);
-- [p_user] runs [p_sql]; its error (or 'ok') is kept under [p_name].
CREATE OR REPLACE FUNCTION race.try(p_name text, p_user uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS \$\$
DECLARE v text := 'ok';
BEGIN
  BEGIN
    PERFORM race.call(p_user, p_sql);
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  INSERT INTO race.outcome (name, result) VALUES (p_name, v) ON CONFLICT (name) DO UPDATE SET result = EXCLUDED.result;
  RETURN v;
END \$\$;
-- Resume's completeness check passes (the fixtures have no photos); race.reset() puts it back.
CREATE OR REPLACE FUNCTION race.stub_complete() RETURNS void LANGUAGE plpgsql AS \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM race.saved_fn) THEN
    INSERT INTO race.saved_fn (def) SELECT pg_get_functiondef('public.dating_profile_complete(uuid)'::regprocedure);
  END IF;
  CREATE OR REPLACE FUNCTION public.dating_profile_complete(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS 'SELECT true';
END \$\$;
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

# Spec 2 W2: the users.path trigger (Dating -> Just for me) takes the same
# lock order, so a path change and the switch serialise and the pause holds.
run "path change (Dating to Just for me) vs the country switch" "$FX_GH" \
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT race.call(race.id('03'), 'SELECT public.set_my_path(''just_me'')') ->> 'tab';" \
  "$SWITCH_GH" \
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run'
               WHEN race.enrol(race.id('03')) = 'paused/path_change'
                    AND (SELECT path FROM public.users WHERE id = race.id('03')) = 'just_me'
               THEN 'ok' ELSE 'path pause lost: ' || coalesce(race.enrol(race.id('03')), 'none') END;" serialised

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

# Spec 2 W2 (migration 1): begin_dating_enrollment and the 15-minute gate
# cron take the shared lock order too. A begin re-tap and the cron each
# serialise with the country switch; the cron against the global flag off
# (country locks in id order across GH and GB) may meet a real deadlock,
# which the switch's own retry absorbs: nobody's pause is lost, nothing is
# left pending. Everyone here fails gate 2 (EULA v1) so the cron pauses them.
# The begin re-tap lands first (it holds the setup lock), then the switch
# pauses the same-gender draft: begin's write and the switch's pause both hold.
run "gate cron vs the country switch" "$FX_GH
   UPDATE public.users SET eula_version = '1' WHERE id::text LIKE '5e2f%';" \
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT public.enforce_dating_lifecycle_gates();" \
  "$SWITCH_GH" \
  "SELECT CASE WHEN (public.dating_country_config('GH')).same_gender_enabled OR EXISTS (SELECT 1 FROM private.dating_kill_switch_pending)
               THEN 'the switch did not run'
               WHEN (SELECT count(*) FROM public.dating_enrollments
                      WHERE user_id IN (race.id('01'), race.id('02'), race.id('03')) AND state = 'paused' AND pause_reason IS NOT NULL) = 3
               THEN 'ok' ELSE 'a pause lost: ' || concat_ws(' ', race.enrol(race.id('01')), race.enrol(race.id('02')), race.enrol(race.id('03'))) END;" serialised

run "begin (re-tap) vs the country switch" "$FX_GH
   UPDATE public.dating_enrollments SET state = 'profile_draft', opted_in_at = now() - interval '1 day' WHERE user_id = race.id('02');" \
  "SET race.sleep_dating_enrollments_update = '2:race.s1';
   SELECT race.call(race.id('02'), format('SELECT to_jsonb(public.begin_dating_enrollment(''dating-2.0'', %L))', race.key('begin'))) ->> 'state';" \
  "$SWITCH_GH" \
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run'
               WHEN race.enrol(race.id('02')) = 'paused/same_gender_switch'
                    AND (SELECT e.terms_version = 'dating-2.0' AND e.opted_in_at > now() - interval '1 minute'
                           FROM public.dating_enrollments AS e WHERE e.user_id = race.id('02'))
               THEN 'ok' ELSE 'begin lost: ' || coalesce(race.enrol(race.id('02')), 'none') END;" serialised

run "gate cron vs the global flag off" \
  "SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
   SELECT race.person('01', 'GH', 'AA', 'woman', ARRAY['woman']), race.person('02', 'GB', 'TLI', 'woman', ARRAY['woman']);
   UPDATE public.users SET eula_version = '1' WHERE id::text LIKE '5e2f%';" \
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT public.enforce_dating_lifecycle_gates();" \
  "SELECT pg_sleep(0.5); UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';" \
  "SELECT CASE WHEN EXISTS (SELECT 1 FROM private.dating_kill_switch_pending) THEN 'the switch left work pending'
               WHEN (SELECT count(*) FROM public.dating_enrollments
                      WHERE user_id IN (race.id('01'), race.id('02')) AND state = 'paused' AND pause_reason IS NOT NULL) = 2
               THEN 'ok' ELSE 'a pause lost: ' || concat_ws(' ', race.enrol(race.id('01')), race.enrol(race.id('02'))) END;"

# Spec 2 W2 Task 3 fix round 1 (batch-2 review C-1, I-1): the switch first.
# It holds Ghana's same-gender lock about 8s; the path change starts 1s in,
# under an Auth-like 3s statement timeout. The path change completes (its
# pause gives up and is counted); the gate cron's sweep then pauses it.
run "path change behind a long country switch (3s statement timeout)" "$FX_GH
   INSERT INTO race.outcome SELECT 'failed_before', coalesce(sum(count), 0)::text FROM public.metric_counters WHERE key = 'dating.path_pause.failed';" \
  "SELECT pg_sleep(1); SET statement_timeout = '3s';
   SELECT race.call(race.id('03'), 'SELECT public.set_my_path(''just_me'')') ->> 'tab';" \
  "SET race.sleep_dating_profiles_update = '8:race.s1';
   SELECT public.publish_country_config('GH', '{\"same_gender_enabled\": false}') ->> 'affected';" \
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run'
               WHEN (SELECT path FROM public.users WHERE id = race.id('03')) IS DISTINCT FROM 'just_me' THEN 'the path change was lost'
               WHEN race.enrol(race.id('03')) IS DISTINCT FROM 'active/-' THEN 'the pause did not wait: ' || coalesce(race.enrol(race.id('03')), 'none')
               WHEN (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.path_pause.failed')
                    <= (SELECT result::bigint FROM race.outcome WHERE name = 'failed_before') THEN 'the failed pause was not counted'
               ELSE 'ok' END AS before_sweep \\gset
   SELECT public.enforce_dating_lifecycle_gates();
   SELECT CASE WHEN :'before_sweep' <> 'ok' THEN :'before_sweep'
               WHEN race.enrol(race.id('03')) = 'paused/path_change' THEN 'ok'
               ELSE 'not swept: ' || coalesce(race.enrol(race.id('03')), 'none') END;" serialised

# Resume vs a path change, the path change first: it holds the setup lock
# while it pauses; resume waits, then reads Just for me and refuses.
run "path change (first) vs resume" "$FX_GH" \
  "SET race.sleep_dating_enrollments_update = '2:race.s1';
   SELECT race.call(race.id('03'), 'SELECT public.set_my_path(''just_me'')') ->> 'tab';" \
  "SELECT pg_sleep(0.5);
   SELECT race.try('resume', race.id('03'), format('SELECT to_jsonb(public.resume_dating_mode(%L))', race.key('resume')));" \
  "SELECT CASE WHEN (SELECT result FROM race.outcome WHERE name = 'resume') IS DISTINCT FROM 'path_not_dating'
               THEN 'resume was not refused: ' || coalesce((SELECT result FROM race.outcome WHERE name = 'resume'), 'none')
               WHEN (SELECT path FROM public.users WHERE id = race.id('03')) = 'just_me' AND race.enrol(race.id('03')) = 'paused/path_change'
               THEN 'ok' ELSE 'path pause lost: ' || coalesce(race.enrol(race.id('03')), 'none') END;" serialised

# Resume first: it holds the setup lock while it resumes; the path pause
# waits (its own 1s lock_timeout, retried), then pauses the resumed person.
run "resume (first) vs path change" "$FX_GH
   SELECT race.stub_complete();
   UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user', paused_at = now() WHERE user_id = race.id('03');
   UPDATE public.dating_profiles SET profile_state = 'paused' WHERE user_id = race.id('03');" \
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT race.try('resume', race.id('03'), format('SELECT to_jsonb(public.resume_dating_mode(%L))', race.key('resume')));" \
  "SELECT pg_sleep(0.5);
   SELECT race.call(race.id('03'), 'SELECT public.set_my_path(''just_me'')') ->> 'tab';" \
  "SELECT CASE WHEN (SELECT result FROM race.outcome WHERE name = 'resume') IS DISTINCT FROM 'ok'
               THEN 'resume refused: ' || coalesce((SELECT result FROM race.outcome WHERE name = 'resume'), 'none')
               WHEN (SELECT path FROM public.users WHERE id = race.id('03')) = 'just_me' AND race.enrol(race.id('03')) = 'paused/path_change'
               THEN 'ok' ELSE 'path pause lost: ' || coalesce(race.enrol(race.id('03')), 'none') END;" serialised

# Spec 2 W2 Task 4 fix round 1 (batch-3 review I-1, I-2): person 02 (a
# Ghanaian woman meeting women) is in a gentle wait with saved answers. A
# clear and a D0 open each start 1s into an 8s country switch, or into an
# 5s hold of 02's own setup lock (a setup writer), under an Auth-like 3s
# statement timeout: both answer at once, and the switch still runs.
FX_WAIT="DELETE FROM public.relationships WHERE user_a::text LIKE '5e2f%' OR user_b::text LIKE '5e2f%';
$FX_GH
INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (race.id('09'), '1555870909', now(), now());
INSERT INTO public.users (id, phone, display_name, path, created_at) VALUES (race.id('09'), '1555870909', 'Race Ex', 'dating', now());
INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (race.id('02'), race.id('09'), 'ended', now() - interval '5 days');
INSERT INTO public.dating_gentle_wait_reflections (user_id, answers, saved_at) VALUES (race.id('02'), '{\"q1\": \"private words\"}', now());
INSERT INTO race.outcome SELECT 'skipped_before', coalesce(sum(count), 0)::text FROM public.metric_counters WHERE key = 'dating.gentle_wait.seen_skipped';"
REFLECTION="(SELECT answers::text || '/' || CASE WHEN seen_at IS NULL THEN 'unseen' ELSE 'seen' END
               FROM public.dating_gentle_wait_reflections WHERE user_id = race.id('02'))"
SWITCH_LONG="SET race.sleep_dating_profiles_update = '8:race.s1';
   SELECT public.publish_country_config('GH', '{\"same_gender_enabled\": false}') ->> 'affected';"
OWN_LOCK="BEGIN; SELECT pg_advisory_xact_lock(hashtext('dating_setup'), hashtext(race.id('02')::text)); SELECT pg_sleep(5); COMMIT;"

run "clear a reflection behind a long country switch (3s statement timeout)" "$FX_WAIT" \
  "SELECT pg_sleep(1); SET statement_timeout = '3s';
   SELECT race.call(race.id('02'), 'SELECT public.save_gentle_wait_reflection(''{}'')') ->> 'ok';" \
  "$SWITCH_LONG" \
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run'
               WHEN (SELECT answers IS NULL AND saved_at IS NULL FROM public.dating_gentle_wait_reflections WHERE user_id = race.id('02'))
               THEN 'ok' ELSE 'not cleared: ' || coalesce($REFLECTION, 'none') END;" serialised

run "open D0 behind a long country switch (3s statement timeout)" "$FX_WAIT" \
  "SELECT pg_sleep(1); SET statement_timeout = '3s';
   SELECT race.call(race.id('02'), 'SELECT public.get_my_gentle_wait_reflection()') ->> 'ok';" \
  "$SWITCH_LONG" \
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run'
               WHEN $REFLECTION = '{\"q1\": \"private words\"}/seen' THEN 'ok'
               ELSE 'view not marked: ' || coalesce($REFLECTION, 'none') END;" serialised

run "clear a reflection behind the person's own setup write (3s statement timeout)" "$FX_WAIT" \
  "SELECT pg_sleep(1); SET statement_timeout = '3s';
   SELECT race.call(race.id('02'), 'SELECT public.save_gentle_wait_reflection(''{}'')') ->> 'ok';" \
  "$OWN_LOCK" \
  "SELECT CASE WHEN (SELECT answers IS NULL AND saved_at IS NULL FROM public.dating_gentle_wait_reflections WHERE user_id = race.id('02'))
               THEN 'ok' ELSE 'not cleared: ' || coalesce($REFLECTION, 'none') END;"

run "open D0 behind the person's own setup write (3s statement timeout)" "$FX_WAIT" \
  "SELECT pg_sleep(1); SET statement_timeout = '3s';
   SELECT race.call(race.id('02'), 'SELECT public.get_my_gentle_wait_reflection()') ->> 'ok';" \
  "$OWN_LOCK" \
  "SELECT CASE WHEN $REFLECTION IS DISTINCT FROM '{\"q1\": \"private words\"}/unseen' THEN 'the view was marked under a held lock: ' || coalesce($REFLECTION, 'none')
               WHEN (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.gentle_wait.seen_skipped')
                    <= (SELECT result::bigint FROM race.outcome WHERE name = 'skipped_before') THEN 'the skipped view was not counted'
               ELSE 'ok' END;"

# Spec 2 W3a (R-6): "Tell me when it's here" vs the publish that opens it.
# The request takes the publisher's advisory lock, so whichever lands first,
# no request is left behind for a place that is open, and a request made
# first is told.
FX_NOTICE="SELECT race.reset(); DELETE FROM public.scheduled_notifications WHERE user_id::text LIKE '5e2f%';
SELECT public.publish_country_config('GH', '{\"open_regions\": [\"AA\", \"AH\"]}') ->> 'ok';
SELECT race.person('05', 'GH', 'AA', 'woman', ARRAY['man']);"
NOTICE_LEFT="(SELECT count(*) FROM public.dating_notify_requests WHERE user_id = race.id('05'))"
NOTICE_TOLD="(SELECT count(*) FROM public.scheduled_notifications WHERE user_id = race.id('05') AND metadata ->> 'type' = 'me_update')"

run "a notice request behind the publish that opens its region" "$FX_NOTICE" \
  "SELECT pg_sleep(0.5); SELECT race.call(race.id('05'), 'SELECT public.request_dating_country_notice(''GH'', ''TV'')') ->> 'reason';" \
  "BEGIN; SELECT public.publish_country_config('GH', '{\"open_regions\": [\"AA\", \"AH\", \"TV\"]}') ->> 'ok'; SELECT pg_sleep(1.2); COMMIT;" \
  "SELECT CASE WHEN $NOTICE_LEFT = 0 THEN 'ok' ELSE 'a request was left for an open region' END;" serialised

run "the publish behind a notice request for its region" "$FX_NOTICE" \
  "BEGIN; SELECT race.call(race.id('05'), 'SELECT public.request_dating_country_notice(''GH'', ''TV'')') ->> 'ok'; SELECT pg_sleep(1.2); COMMIT;" \
  "SELECT pg_sleep(0.5); SELECT public.publish_country_config('GH', '{\"open_regions\": [\"AA\", \"AH\", \"TV\"]}') ->> 'notified';" \
  "SELECT CASE WHEN $NOTICE_LEFT = 0 AND $NOTICE_TOLD = 1 THEN 'ok' ELSE 'left ' || $NOTICE_LEFT || ', told ' || $NOTICE_TOLD END;" serialised

# Spec 2 W3a fix round 1 (M-7): leaving while a publish both opens the
# region the person asked about and turns same-gender off. The publish
# tells after its kill switch, so it takes the notice row last, as exit
# does: they serialise, and leaving never meets a deadlock.
FX_EXIT_NOTICE="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART; DELETE FROM public.scheduled_notifications WHERE user_id::text LIKE '5e2f%';
SELECT public.publish_country_config('GH', '{\"open_regions\": [\"AA\", \"AH\"]}') ->> 'ok';
SELECT race.person('06', 'GH', 'AA', 'woman', ARRAY['woman']);
SELECT race.call(race.id('06'), 'SELECT public.request_dating_country_notice(''GH'', ''TV'')') ->> 'ok';"

run "exit vs a publish that opens the asked-for region and switches same-gender off" "$FX_EXIT_NOTICE" \
  "SET race.sleep_dating_profile_sensitive_delete = '2:race.s1';
   SELECT race.call(race.id('06'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \
  "SELECT pg_sleep(0.5); SELECT public.publish_country_config('GH', '{\"open_regions\": [\"AA\", \"AH\", \"TV\"], \"same_gender_enabled\": false}') ->> 'ok';" \
  "SELECT CASE WHEN race.enrol(race.id('06')) IS DISTINCT FROM 'exited/-' THEN 'exit lost: ' || coalesce(race.enrol(race.id('06')), 'none')
               WHEN (public.dating_country_config('GH')).same_gender_enabled THEN 'the switch did not publish'
               WHEN EXISTS (SELECT 1 FROM private.dating_kill_switch_pending) THEN 'the switch was left pending'
               WHEN EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = race.id('06')) THEN 'a request was left after leaving'
               ELSE 'ok' END;" serialised

# Spec 2 W3c (Task 8): a photo writer vs leaving. Every photo writer that
# adds takes the person's setup lock first, as exit does, through a bounded
# retry (dating:busy after three), and the CSAM recorder takes it before the
# photo row (a hit's hold suspends the enrolment, which exit locks first),
# so a photo write and leaving serialise: no deadlock, leaving completes
# and removes every photo and upload, and the writer that loses answers a
# named refusal, never a raw lock error. A photo delete is never gated and
# never waits without bound: behind a held row it answers busy in time.
FX_PHOTO="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
-- A CSAM hit's hold survives the account (enforcement survival, by phone):
-- the race people's phones are reused, so a scratch copy forgets it here.
DELETE FROM public.enforcement_records WHERE scope = 'dating';
INSERT INTO storage.buckets (id, name) VALUES ('dating-profile-photos', 'dating-profile-photos') ON CONFLICT (id) DO NOTHING;
SELECT race.person('04', 'GB', 'TLI', 'woman', ARRAY['man']);
INSERT INTO race.outcome SELECT 'intent', race.call(race.id('04'), 'SELECT public.create_dating_photo_upload_intent(''image/jpeg'')')::text;
DO \$\$ BEGIN
  IF (SELECT (result::jsonb ->> 'ok')::boolean FROM race.outcome WHERE name = 'intent') IS NOT TRUE THEN
    RAISE EXCEPTION 'photo fixture: no upload intent: %', (SELECT result FROM race.outcome WHERE name = 'intent');
  END IF;
END \$\$;
INSERT INTO storage.objects (bucket_id, name, owner)
SELECT 'dating-profile-photos', result::jsonb ->> 'storage_key', race.id('04') FROM race.outcome WHERE name = 'intent';"
PHOTO_INTENT="(SELECT result::jsonb ->> 'intent_id' FROM race.outcome WHERE name = 'intent')"
PHOTO_KEY="(SELECT result::jsonb ->> 'storage_key' FROM race.outcome WHERE name = 'intent')"
PHOTO_ROW="(SELECT id FROM public.dating_profile_photos WHERE user_id = race.id('04'))"
PHOTO_LEFT="((SELECT count(*) FROM public.dating_profile_photos WHERE user_id = race.id('04'))
             + (SELECT count(*) FROM public.dating_photo_upload_intents WHERE user_id = race.id('04')))"
LEFT_04="(SELECT e.exited_at IS NOT NULL FROM public.dating_enrollments AS e WHERE e.user_id = race.id('04'))"
FX_PHOTO_IN="$FX_PHOTO
SELECT race.call(race.id('04'), format('SELECT public.insert_dating_profile_photo(%L, 1::smallint)', $PHOTO_INTENT)) ->> 'ok';
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE user_id = race.id('04')) THEN
    RAISE EXCEPTION 'photo fixture: the photo was not attached';
  END IF;
END \$\$;"

run "a photo insert vs exit" "$FX_PHOTO" \
  "SET race.sleep_dating_photo_upload_intents_update = '2:race.s1';
   SELECT race.call(race.id('04'), format('SELECT public.insert_dating_profile_photo(%L, 1::smallint)', $PHOTO_INTENT)) ->> 'ok';" \
  "SELECT pg_sleep(0.5);
   SELECT race.call(race.id('04'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \
  "SELECT CASE WHEN $LEFT_04 IS NOT TRUE THEN 'exit lost: ' || coalesce(race.enrol(race.id('04')), 'none')
               WHEN $PHOTO_LEFT <> 0 THEN 'a photo or upload was left after leaving'
               WHEN NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = $PHOTO_KEY) THEN 'the object was not queued for deletion'
               ELSE 'ok' END;" serialised

run "exit vs a photo insert (behind the insert's 2s lock_timeout)" "$FX_PHOTO" \
  "SET race.sleep_dating_profile_sensitive_delete = '3:race.s1';
   SELECT race.call(race.id('04'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \
  "SELECT pg_sleep(0.5);
   INSERT INTO race.outcome SELECT 'insert', race.call(race.id('04'), format('SELECT public.insert_dating_profile_photo(%L, 1::smallint)', $PHOTO_INTENT))::text;" \
  "SELECT CASE WHEN $LEFT_04 IS NOT TRUE THEN 'exit lost: ' || coalesce(race.enrol(race.id('04')), 'none')
               WHEN $PHOTO_LEFT <> 0 THEN 'a photo or upload was left after leaving'
               WHEN (SELECT result::jsonb ->> 'reason' FROM race.outcome WHERE name = 'insert') IN ('intent_unavailable', 'not_eligible') THEN 'ok'
               ELSE 'the insert answered ' || coalesce((SELECT result FROM race.outcome WHERE name = 'insert'), 'nothing') END;" serialised

run "a CSAM hit vs exit (the hit first)" "$FX_PHOTO_IN" \
  "SET race.sleep_dating_profile_photos_update = '2:race.s1';
   SELECT public.record_dating_photo_csam($PHOTO_ROW, 'hit') ->> 'ok';" \
  "SELECT pg_sleep(0.5);
   SELECT race.call(race.id('04'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \
  "SELECT CASE WHEN $LEFT_04 IS NOT TRUE THEN 'exit lost: ' || coalesce(race.enrol(race.id('04')), 'none')
               WHEN $PHOTO_LEFT <> 0 THEN 'a photo or upload was left after leaving'
               WHEN NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions
                                 WHERE user_id = race.id('04') AND restriction_type = 'moderation_hold' AND lifted_at IS NULL)
               THEN 'the hit''s hold was lost'
               ELSE 'ok' END;" serialised

run "a photo delete behind a held photo row (answers within its bound)" "$FX_PHOTO_IN" \
  "BEGIN; SELECT 1 FROM public.dating_profile_photos WHERE user_id = race.id('04') FOR UPDATE; SELECT pg_sleep(5); COMMIT;" \
  "SELECT pg_sleep(0.5); SET statement_timeout = '4500ms';
   INSERT INTO race.outcome SELECT 'delete', race.call(race.id('04'), format('SELECT public.delete_dating_profile_photo(%L)', $PHOTO_ROW))::text;" \
  "SELECT CASE WHEN (SELECT result FROM race.outcome WHERE name = 'delete') IS DISTINCT FROM '{\"ok\": false, \"reason\": \"busy\"}'
               THEN 'the delete answered ' || coalesce((SELECT result FROM race.outcome WHERE name = 'delete'), 'nothing')
               ELSE 'ok' END AS held \\gset
   SELECT race.call(race.id('04'), format('SELECT public.delete_dating_profile_photo(%L)', $PHOTO_ROW)) ->> 'ok' AS again \\gset
   SELECT CASE WHEN :'held' <> 'ok' THEN :'held'
               WHEN :'again' IS DISTINCT FROM 'true' OR $PHOTO_ROW IS NOT NULL THEN 'the delete after the hold did not remove the photo'
               ELSE 'ok' END;"

# Spec 2 W3c fix round 1 (M-4): the CSAM recorder's photo-row lock is under
# its bounded retry: behind a held row it answers dating:busy (the job
# retries), never a raw lock timeout. (I-1): an orphan match takes the
# person's setup lock before the intent row, so it and leaving serialise.
run "a CSAM outcome behind a held photo row (dating:busy in time)" "$FX_PHOTO_IN" \
  "BEGIN; SELECT 1 FROM public.dating_profile_photos WHERE user_id = race.id('04') FOR UPDATE; SELECT pg_sleep(8); COMMIT;" \
  "SELECT pg_sleep(0.5); SET statement_timeout = '7500ms';
   DO \$\$ BEGIN
     PERFORM public.record_dating_photo_csam((SELECT id FROM public.dating_profile_photos WHERE user_id = race.id('04')), 'clear');
     INSERT INTO race.outcome VALUES ('csam', 'answered');
   EXCEPTION WHEN OTHERS THEN
     INSERT INTO race.outcome VALUES ('csam', SQLSTATE || ':' || SQLERRM);
   END \$\$;" \
  "SELECT CASE WHEN (SELECT result FROM race.outcome WHERE name = 'csam') = '55P03:dating:busy' THEN 'ok'
               ELSE 'the CSAM outcome answered ' || coalesce((SELECT result FROM race.outcome WHERE name = 'csam'), 'nothing') END;"

run "an orphan CSAM match vs exit (the match first)" "$FX_PHOTO
UPDATE public.dating_photo_upload_intents SET expires_at = now() - interval '1 hour', orphan_claimed_at = now() WHERE user_id = race.id('04');" \
  "SET race.sleep_dating_photo_upload_intents_update = '2:race.s1';
   SELECT public.record_dating_orphan_scan($PHOTO_INTENT::uuid, 'hit') ->> 'ok';" \
  "SELECT pg_sleep(0.5);
   SELECT race.call(race.id('04'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \
  "SELECT CASE WHEN $LEFT_04 IS NOT TRUE THEN 'exit lost: ' || coalesce(race.enrol(race.id('04')), 'none')
               WHEN $PHOTO_LEFT <> 0 THEN 'a photo or upload was left after leaving'
               WHEN NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions
                                 WHERE user_id = race.id('04') AND restriction_type = 'moderation_hold' AND lifted_at IS NULL)
               THEN 'the orphan match''s hold was lost'
               ELSE 'ok' END;" serialised

# Spec 2 W3c (Task 9, B; R-25): a gone hit's Dating hold
# (record_dating_csam_hold, the photo row deleted mid-scan) takes the
# person's setup lock before the enrolment and profile its hold suspends
# (it sleeps holding the enrolment), as exit does: the two serialise, exit
# completes and the hold is kept.
run "a gone hit's Dating hold vs exit (the hold first)" "$FX_PHOTO" \
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT public.record_dating_csam_hold(race.id('04')) ->> 'ok';" \
  "SELECT pg_sleep(0.5);
   SELECT race.call(race.id('04'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \
  "SELECT CASE WHEN NOT (SELECT is_called FROM race.s1) THEN 'the hold never reached the profile (no race)'
               WHEN $LEFT_04 IS NOT TRUE THEN 'exit lost: ' || coalesce(race.enrol(race.id('04')), 'none')
               WHEN $PHOTO_LEFT <> 0 THEN 'a photo or upload was left after leaving'
               WHEN NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions
                                 WHERE user_id = race.id('04') AND restriction_type = 'moderation_hold' AND lifted_at IS NULL)
               THEN 'the gone hit''s hold was lost'
               ELSE 'ok' END;" serialised

$P -c "SELECT race.reset();" > /dev/null 2>&1
exit $fail

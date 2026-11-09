-- Spec 2 W3b, migration 1 (§4.9 W3b; §2.2 "Faith lists (W3b seed)"; plan
-- R-17, R-18, R-19): the reviewed faith and denomination lists for Ghana and
-- the UK, published through publish_country_config (which keeps each row's
-- dating_enabled; only when the list differs, so a replay publishes
-- nothing; a refusal raises), and get_dating_setup_lists() for D3, D5, D6
-- and D8. The lists are reviewer content (W3 gate). No region-list edit:
-- the cultural reviewer has none yet.
-- Grants in 20261107160010_dating_v2_setup_lists_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $lists$
DECLARE
  v jsonb;
  v_code text;
  v_list jsonb;
BEGIN
  FOR v_code, v_list IN VALUES
    ('GH', '[{"code": "christian", "name_key": "dating_faith_christian", "denominations": [
               {"code": "catholic", "name_key": "dating_denomination_catholic"},
               {"code": "anglican", "name_key": "dating_denomination_anglican"},
               {"code": "methodist", "name_key": "dating_denomination_methodist"},
               {"code": "presbyterian", "name_key": "dating_denomination_presbyterian"},
               {"code": "pentecostal_charismatic", "name_key": "dating_denomination_pentecostal_charismatic"},
               {"code": "seventh_day_adventist", "name_key": "dating_denomination_seventh_day_adventist"},
               {"code": "other_christian", "name_key": "dating_denomination_other_christian"}]},
             {"code": "muslim", "name_key": "dating_faith_muslim", "denominations": []},
             {"code": "traditional", "name_key": "dating_faith_traditional", "denominations": []},
             {"code": "other", "name_key": "dating_faith_other", "denominations": []},
             {"code": "none", "name_key": "dating_faith_none", "denominations": []},
             {"code": "prefer_not_to_say", "name_key": "dating_faith_prefer_not_to_say", "denominations": []}]'::jsonb),
    ('GB', '[{"code": "christian", "name_key": "dating_faith_christian", "denominations": [
               {"code": "catholic", "name_key": "dating_denomination_catholic"},
               {"code": "church_of_england_anglican", "name_key": "dating_denomination_church_of_england_anglican"},
               {"code": "orthodox", "name_key": "dating_denomination_orthodox"},
               {"code": "pentecostal_charismatic", "name_key": "dating_denomination_pentecostal_charismatic"},
               {"code": "other_christian", "name_key": "dating_denomination_other_christian"}]},
             {"code": "muslim", "name_key": "dating_faith_muslim", "denominations": []},
             {"code": "hindu", "name_key": "dating_faith_hindu", "denominations": []},
             {"code": "sikh", "name_key": "dating_faith_sikh", "denominations": []},
             {"code": "jewish", "name_key": "dating_faith_jewish", "denominations": []},
             {"code": "buddhist", "name_key": "dating_faith_buddhist", "denominations": []},
             {"code": "other", "name_key": "dating_faith_other", "denominations": []},
             {"code": "none", "name_key": "dating_faith_none", "denominations": []},
             {"code": "prefer_not_to_say", "name_key": "dating_faith_prefer_not_to_say", "denominations": []}]'::jsonb)
  LOOP
    IF (public.dating_country_config(v_code)).faith_list IS DISTINCT FROM v_list THEN
      v := public.publish_country_config(v_code, jsonb_build_object(
             'faith_list', v_list, 'published_by', 'migration:dating_v2_setup_lists'));
      IF (v ->> 'ok')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'dating_v2_setup_lists: the % faith list was not published: %', v_code, v;
      END IF;
    END IF;
  END LOOP;
END $lists$;

-- D3, D5, D6, D8 (R-17): config only, plus the caller's own phone country,
-- its note (Tier 1/2 phone countries; the location variant is W4b/W8b's,
-- R-18) and default ages. No gender, no seeking, nobody else.
CREATE OR REPLACE FUNCTION public.get_dating_setup_lists()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_phone_country text;
  v_tier smallint;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  v_phone_country := private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user));
  IF v_phone_country IS NOT NULL THEN
    v_tier := (public.dating_country_config(v_phone_country)).tier;
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'countries', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'code', c.country_code::text,
               'same_gender', coalesce(private.dating_same_gender_on(c.country_code::text), false),
               'regions', coalesce((
                 SELECT jsonb_agg(jsonb_build_object(
                          'code', r ->> 'code',
                          'name_key', r ->> 'name_key',
                          'open', c.open_regions IS NULL OR (r ->> 'code') = ANY (c.open_regions),
                          'sides', coalesce(r -> 'sides', '[]'::jsonb)) ORDER BY r ->> 'code')
                   FROM jsonb_array_elements(c.region_list) AS r), '[]'::jsonb),
               'faiths', c.faith_list) ORDER BY c.country_code)
        FROM public.country_safety_config AS c
       WHERE c.is_current AND c.dating_enabled), '[]'::jsonb),
    'phone_country', v_phone_country,
    'note_country', CASE WHEN v_tier IN (1, 2) THEN v_phone_country END,
    'default_ages', to_jsonb(private.dating_default_ages(public.account_age(v_user))));
END;
$$;
REVOKE ALL ON FUNCTION public.get_dating_setup_lists() FROM PUBLIC, anon, service_role;

COMMIT;

-- Spec 2 W8b (§2.1 gate 7, §2.3, §2.5, §3.1, §3.11, §4.3, §4.4, §4.9 W8b,
-- §5.10, §6.7, §7.1; R-71..R-80): the traveller. The flag
-- dating_traveller_detection (off); the device check's record (the IP's
-- country only, never the IP; a phone Dating doesn't trust records
-- nothing; at most one record per 15 minutes; the location signal at 7);
-- the trip on the one overwritten row; gate 7; the away state, the trip
-- and the plain-icon offer in the home; the person's trip choice.
-- Grants in 20261122100010_dating_v2_traveller_grants.sql. Ends by revoking
-- everything it creates from every API role (the W6 final pattern: a push
-- that stops between this file and its twin fails closed).
BEGIN;
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------
-- 1. The flag (off; supabase/sql/dev_enable_spec2_dating_flags.sql turns
--    it on in development) and its production gate (Spec 1's gate
--    trigger). The device check records the context with the flag off
--    too (W5's same-gender and freshness rules read it); the flag decides
--    what a trip changes: gate 7, the trip in the home, the reads' hiding
--    and the location signal.
-- ---------------------------------------------------------------------
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('dating_traveller_detection', 'Spec 2 W8 gate: the section 7.7 device checks pass on release builds (lock screen, screenshots, the plain icon, a traveller with a VPN set to Ghana and to the UAE on a UK account); the IP database attribution is in the app''s licences and the privacy notice')
ON CONFLICT (flag_key) DO NOTHING;
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_traveller_detection', false)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. The trip, on the one overwritten row (§2.3, §2.5): since when the
--    person has been back where Dating is allowed (a trip ends after 7
--    days of it; final server fix M-2), and the
--    person's own "Show it on this phone anyway". Still no country and no
--    history.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_session_context
  ADD COLUMN IF NOT EXISTS home_since timestamptz,
  ADD COLUMN IF NOT EXISTS show_here boolean NOT NULL DEFAULT false;
-- Fix round 4 (R-T4-9): show_here and the note mark are an away trip's
-- only (Dating not allowed there: the same for everyone, no identity in
-- it). A same-gender trip's note and "Show it on this phone anyway" live on
-- the person's phone and nowhere on the server (any server record of them
-- would be one only a person beyond man-woman makes, §793, S-5): the reads
-- take the phone's choice as p_show_same_gender.

-- ---------------------------------------------------------------------
-- 3. Helpers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_traveller_on()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(public.dating_flag_enabled('dating_traveller_detection'), false);
$$;

-- Whether [p_user] has any pool or seeking value beyond man-woman (§2.5):
-- a woman or a man in their own pool only, seeking only the other. An
-- answer that can't be read counts as yes (the note shows; nothing opens).
CREATE OR REPLACE FUNCTION private.dating_wants_same_gender(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_identity jsonb;
  v_seeking jsonb;
  v_me text;
  v_pools text[];
  v_seek text[];
BEGIN
  SELECT private.dating_field_decrypt(s.identity_enc), private.dating_field_decrypt(s.seeking_enc)
    INTO v_identity, v_seeking
    FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
  v_me := v_identity ->> 'identity';
  v_pools := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(v_identity -> 'pools') = 'array'
                                                         THEN v_identity -> 'pools' END));
  v_seek := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(v_seeking -> 'seeking') = 'array'
                                                        THEN v_seeking -> 'seeking' END));
  RETURN NOT coalesce(v_me IN ('woman', 'man')
                      AND v_pools = ARRAY[v_me]
                      AND v_seek = ARRAY[CASE v_me WHEN 'woman' THEN 'man' ELSE 'woman' END], false);
EXCEPTION WHEN OTHERS THEN
  RETURN true;
END;
$$;

-- Fix round 3 (Re2-M-1): the introduction states that count, one list for
-- the trip and for Task 5's reads: shown to that side (not generated, not
-- before its visible-from time) and not over.
CREATE OR REPLACE FUNCTION private.dating_intro_counts(p_state text, p_visible_from timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(p_state IN ('presented', 'interested', 'matched') AND p_visible_from <= now(), false);
$$;

-- Fix round 3 (Re2-I-1); W8 final server fix (I-1, round 2: one rule
-- everywhere): whether [p_viewer] and [p_other] are man-woman, judged only
-- by what the viewer can see: the viewer's own identity and seeking, and
-- the other's gender only if they show it (gender_visible). Otherwise the
-- pair is man-woman only if everyone the viewer seeks is the other gender
-- of the viewer's (a woman who meets only men met a man). The other's
-- hidden pools are never read, on the viewer's own phone or on another
-- person's Today (any narrowing by them would let what hides tell the
-- viewer the pool the other person hid; S-5). Anything that can't be read
-- is not man-woman (the protective direction). The forms of earlier
-- rounds (a p_public flag) are gone; only development databases had them.
DROP FUNCTION IF EXISTS private.dating_pair_seen_as_man_woman(uuid, uuid, boolean);
CREATE OR REPLACE FUNCTION private.dating_pair_seen_as_man_woman(p_viewer uuid, p_other uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_me text;
  v_seek text[];
  v_opposite text;
BEGIN
  v_me := private.dating_identity_of(p_viewer);
  IF v_me IS NULL OR v_me NOT IN ('woman', 'man') THEN
    RETURN false;
  END IF;
  v_opposite := CASE v_me WHEN 'woman' THEN 'man' ELSE 'woman' END;
  IF coalesce((SELECT p.gender_visible FROM public.dating_profiles AS p WHERE p.user_id = p_other), false) THEN
    RETURN private.dating_pair_is_man_woman(v_me, private.dating_identity_of(p_other));
  END IF;
  SELECT ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(x -> 'seeking') = 'array' THEN x -> 'seeking' END))
    INTO v_seek
    FROM (SELECT private.dating_field_decrypt(s.seeking_enc) AS x
            FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_viewer) AS q;
  RETURN coalesce(cardinality(v_seek), 0) > 0 AND v_seek <@ ARRAY[v_opposite]; -- the viewer's seeking set, never the other's pools
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;

-- Fix round 2 (Re-I-1), round 3 (Re2-I-1, Re2-M-1): whether [p_user] has
-- a match (live or ended) or an introduction that counts
-- (dating_intro_counts) that isn't man-woman as [p_user] sees it. A side
-- that is gone is no pair (dating_trip_hides judges nothing for it either).
CREATE OR REPLACE FUNCTION private.dating_has_same_gender_pair(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_matches AS m
                  WHERE p_user IN (m.user_low_id, m.user_high_id)
                    AND m.user_low_id IS NOT NULL AND m.user_high_id IS NOT NULL
                    AND NOT private.dating_pair_seen_as_man_woman(p_user,
                          CASE WHEN m.user_low_id = p_user THEN m.user_high_id ELSE m.user_low_id END))
      OR EXISTS (SELECT 1 FROM public.dating_introductions AS i
                  WHERE p_user IN (i.user_low_id, i.user_high_id)
                    AND private.dating_intro_counts(i.state,
                          CASE WHEN i.user_low_id = p_user THEN i.visible_from_low ELSE i.visible_from_high END)
                    AND NOT private.dating_pair_seen_as_man_woman(p_user,
                          CASE WHEN i.user_low_id = p_user THEN i.user_high_id ELSE i.user_low_id END));
$$;

-- Fix round 2 (Re-I-1): the one same-gender trip rule, read by the trip
-- (dating_trip_json, and so the choice) and by the hiding
-- (dating_same_gender_hiding, dating_trip_hides), so whatever hides is
-- explained and can be chosen. Same-gender isn't allowed where [p_user]
-- is, and either they would meet beyond man-woman at home (a pool or
-- seeking value beyond it, with same-gender on in their Dating country) or
-- they have a pair that isn't man-woman as they see it. Authenticated
-- reads only (it decrypts; S-4).
CREATE OR REPLACE FUNCTION private.dating_same_gender_trip(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_c public.dating_session_context;
BEGIN
  SELECT * INTO v_c FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  IF v_c.user_id IS NULL OR v_c.same_gender_allowed_here IS NOT FALSE THEN
    RETURN false;
  END IF;
  RETURN (coalesce(private.dating_same_gender_on((SELECT p.country_code::text FROM public.dating_profiles AS p
                                                    WHERE p.user_id = p_user)), false)
          AND private.dating_wants_same_gender(p_user))
         OR private.dating_has_same_gender_pair(p_user);
END;
$$;

-- Fix round 3 (Re2 concern 1), round 4 (R-T4-9): whether the viewer's
-- same-gender trip hides their pairs that aren't man-woman, before the
-- phone's own choice. A read takes "Show it on this phone anyway" from the
-- phone (p_show_same_gender boolean DEFAULT false) and passes
-- dating_same_gender_hiding(viewer) AND NOT coalesce(p_show_same_gender,
-- false), computed once per read, to dating_trip_hides' four-argument form.
CREATE OR REPLACE FUNCTION private.dating_same_gender_hiding(p_viewer uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_viewer IS NOT NULL AND private.dating_traveller_on()
         AND private.dating_same_gender_trip(p_viewer);
$$;

-- §2.5: whether the trip hides the pair of [p_viewer] and [p_other] from
-- [p_viewer] now. On the viewer's own phone: everything while Dating isn't
-- allowed where they are (unless they chose "Show it on this phone anyway"
-- there: show_here), and, elsewhere, every pair that isn't man-woman as
-- they can see it (final server fix round 2: the one viewer-visible rule,
-- never the other's hidden pools) while their same-gender trip hides it ([p_viewer_sg]: the
-- read's dating_same_gender_hiding(p_viewer) AND NOT p_show_same_gender,
-- computed once). From another person's Today ([p_kind] 'introduction'):
-- while the other person is somewhere same-gender isn't allowed (their
-- context row: no identity in it), a pair that isn't man-woman as the
-- viewer can already see it (final server fix I-1, superseding fix round
-- 4's "as the traveller sees it": that used a hidden gender, so a card's
-- going told the viewer the traveller wasn't a plain man or woman; now the
-- viewer learns only that the traveller is somewhere that restricts, for a
-- pair the viewer already knows isn't man-woman). With the flag off,
-- nothing. An identity that can't be read is not man-woman (hidden).
CREATE OR REPLACE FUNCTION private.dating_trip_hides(p_viewer uuid, p_other uuid, p_kind text, p_viewer_sg boolean)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_me public.dating_session_context;
  v_them public.dating_session_context;
BEGIN
  IF p_viewer IS NULL OR NOT private.dating_traveller_on() THEN
    RETURN false;
  END IF;
  SELECT * INTO v_me FROM public.dating_session_context AS c WHERE c.user_id = p_viewer;
  IF v_me.user_id IS NOT NULL AND NOT v_me.show_here AND v_me.dating_allowed_here IS FALSE THEN
    RETURN true;
  END IF;
  -- The other side gone (a deleted account's ended chat): nothing more to judge.
  IF p_other IS NULL THEN
    RETURN false;
  END IF;
  IF coalesce(p_viewer_sg, false) AND v_me.dating_allowed_here IS NOT FALSE -- fix round 3: the trip's own rule, computed once
     AND NOT coalesce(private.dating_pair_seen_as_man_woman(p_viewer, p_other), false) THEN -- fix round 3 (Re2-I-1); final server fix round 2: as the viewer can see them
    RETURN true;
  END IF;
  IF p_kind = 'introduction' THEN
    SELECT * INTO v_them FROM public.dating_session_context AS c WHERE c.user_id = p_other;
    IF v_them.user_id IS NOT NULL AND v_them.same_gender_allowed_here IS FALSE
       AND NOT coalesce(private.dating_pair_seen_as_man_woman(p_viewer, p_other), false) THEN -- final server fix (I-1): as the viewer can see them
      RETURN true;
    END IF;
  END IF;
  RETURN false;
END;
$$;

-- The three-argument form (Task 5's single reads): the same, with the
-- viewer's same-gender hiding computed here.
CREATE OR REPLACE FUNCTION private.dating_trip_hides(p_viewer uuid, p_other uuid, p_kind text)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.dating_trip_hides(p_viewer, p_other, p_kind, private.dating_same_gender_hiding(p_viewer));
$$;

-- The trip as the person's home shows it (§3.1 away, §3.11): its kind,
-- whether the in-app note is still to show (once per trip, never a push)
-- and the person's own "Show it on this phone anyway". Only with the flag
-- on and only while the place restricts: Dating not allowed here (away:
-- the context row's plaintext, the same for everyone there), or the
-- same-gender trip rule (same_gender: its kind only; fix round 4, R-T4-9:
-- the note and the choice are the phone's). Otherwise {}.
CREATE OR REPLACE FUNCTION private.dating_trip_json(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_c public.dating_session_context;
BEGIN
  IF p_user IS NULL OR NOT private.dating_traveller_on() THEN
    RETURN '{}'::jsonb;
  END IF;
  SELECT * INTO v_c FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  IF v_c.user_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;
  IF v_c.dating_allowed_here IS FALSE THEN
    RETURN pg_catalog.jsonb_build_object('trip', pg_catalog.jsonb_build_object(
      'kind', 'away', 'note', v_c.trip_note_shown_at IS NULL, 'show_here', v_c.show_here));
  END IF;
  IF NOT private.dating_same_gender_trip(p_user) THEN -- fix round 2 (Re-I-1): the hiding's own rule
    RETURN '{}'::jsonb;
  END IF;
  RETURN '{"trip": {"kind": "same_gender"}}'::jsonb; -- fix round 4 (R-T4-9): the phone keeps the rest
END;
$$;

-- §3.2 D13, §6.7: the plain-icon offer, when the effective tier is 1 or 2
-- (the latest context's, else the phone's and the Dating country's: a VPN
-- never hides the offer). Only when true, so no other home answer changes.
CREATE OR REPLACE FUNCTION private.dating_icon_offer_json(p_user uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN coalesce(
           (SELECT c.effective_tier FROM public.dating_session_context AS c WHERE c.user_id = p_user),
           (public.dating_effective_context(
              private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = p_user)),
              (SELECT p.country_code::text FROM public.dating_profiles AS p WHERE p.user_id = p_user),
              NULL, NULL) ->> 'effective_tier')::smallint, 3) <= 2
         THEN '{"offer_plain_icon": true}'::jsonb ELSE '{}'::jsonb END;
$$;

-- ---------------------------------------------------------------------
-- 4. The device check (§2.3, §4.4, §4.7): dating-device-check's one call.
--    The IP is resolved to a country in the edge function and never
--    reaches the database; only the country codes come here, are used in
--    the moment and are never stored. A phone Dating doesn't trust records
--    nothing. Only someone with Dating data gets a row. At most one record
--    per 15 minutes (§2.3), so the away streak counts checks at least 15
--    minutes apart; the location signal opens at 7 in a row (§5.10, flag
--    on). An away trip ends after 7 days back where Dating is allowed (the
--    final server fix, M-2: home is anywhere Dating is allowed, not only
--    the Dating country): the note may show again on the next one, and
--    "Show it on this phone anyway" ends with it. Fix round 4 (R-T4-9): nothing here touches dating_profile_sensitive.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_dating_device_check(
  p_user uuid, p_device_hash text, p_ip_country text, p_network_country text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_state text;
  v_row public.dating_session_context;
  v_on constant boolean := private.dating_traveller_on();
  v_here text;
  v_sg_home boolean; -- fix round 1 (I-2): same-gender allowed in the Dating country
BEGIN
  IF p_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF (p_ip_country IS NOT NULL AND p_ip_country !~ '^[A-Za-z]{2}$')
     OR (p_network_country IS NOT NULL AND p_network_country !~ '^[A-Za-z]{2}$')
     OR (p_device_hash IS NOT NULL AND p_device_hash !~ '^[0-9a-f]{64}$') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  v_state := private.dating_device_state(p_user, p_device_hash);
  IF v_state IS DISTINCT FROM 'trusted' AND v_state IS DISTINCT FROM 'unbound' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'trusted', false, 'away', false, 'here', NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = p_user) THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'trusted', v_state = 'trusted', 'away', false, 'here', NULL);
  END IF;
  -- Two checks at once (two opens): the second waits, then finds the row fresh.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_device_check'), pg_catalog.hashtext(p_user::text));
  SELECT * INTO v_row FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  v_sg_home := coalesce(private.dating_same_gender_on((SELECT p.country_code::text FROM public.dating_profiles AS p
                                                        WHERE p.user_id = p_user)), false);
  IF v_row.user_id IS NULL OR v_row.checked_at <= now() - interval '15 minutes' THEN
    PERFORM public.record_dating_session_context(p_user, upper(p_ip_country), upper(p_network_country));
    UPDATE public.dating_session_context AS c
       SET home_since = CASE WHEN c.dating_allowed_here IS FALSE -- R-T4-3: never home where Dating isn't allowed
                             THEN NULL ELSE coalesce(c.home_since, now()) END -- final server fix (M-2): home is where Dating is allowed, not the Dating country
     WHERE c.user_id = p_user
    RETURNING * INTO v_row;
    IF v_row.home_since <= now() - interval '7 days'
       AND (v_row.trip_note_shown_at IS NOT NULL OR v_row.show_here) THEN
      UPDATE public.dating_session_context AS c SET trip_note_shown_at = NULL, show_here = false
       WHERE c.user_id = p_user RETURNING * INTO v_row;
    END IF;
    IF v_on AND v_row.mismatch_streak = 7 THEN
      PERFORM private.dating_open_signal_case(p_user, 'location_mismatch', 'P3');
    END IF;
  END IF;
  -- The place, for the note's words only, while it restricts more than
  -- home: Dating isn't allowed there, or same-gender isn't while it is at
  -- home (fix round 1, I-2: the trip's own rule, with no identity read).
  IF v_on AND (v_row.dating_allowed_here IS FALSE
               OR (v_row.same_gender_allowed_here IS FALSE AND v_sg_home)) THEN
    -- Fix round 1 (M-1): the country that restricts: the IP's, then the
    -- network's, then (the IP unresolved) the phone's, as §2.3 places them.
    SELECT k.code INTO v_here
      FROM unnest(ARRAY[private.dating_iso_country(upper(p_ip_country)),
                        private.dating_iso_country(upper(p_network_country)),
                        CASE WHEN private.dating_iso_country(upper(p_ip_country)) IS NULL
                             THEN private.dating_iso_country(private.dating_phone_country(
                                    (SELECT a.phone FROM auth.users AS a WHERE a.id = p_user))) END])
           WITH ORDINALITY AS k(code, n)
      CROSS JOIN LATERAL public.dating_country_config(k.code) AS c
     WHERE k.code IS NOT NULL
       AND CASE WHEN v_row.dating_allowed_here IS FALSE THEN NOT c.dating_enabled AND c.tier IN (1, 2)
                ELSE NOT c.same_gender_enabled END
     ORDER BY k.n
     LIMIT 1;
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'trusted', v_state = 'trusted',
    'away', v_on AND v_row.dating_allowed_here IS FALSE, 'here', v_here);
END;
$$;

-- ---------------------------------------------------------------------
-- 5. The person's choice on an away trip (§3.11): "Show it on this phone
--    anyway" (true: only what this person's own reads hide; the server
--    still makes no introduction the context forbids) or "Keep it hidden"
--    (false). Either marks the note seen for the trip. Both need the
--    trusted phone (fix round 1, C-1). Fix round 4 (R-T4-9): the away
--    kind only (Dating not allowed where the person is: the same for
--    everyone, no identity read). A same-gender trip's choice is the
--    phone's, so anything else answers no_trip before the key is claimed
--    and leaves nothing (R-T4-1); a claimed key is only ever an ok one, so
--    a replay answers ok (or no_trip once the trip is over). Fix round 5
--    (Re4-M-1): the identity-free test is made on a plain read first, so a
--    call that answers no_trip takes no row lock either; a call that sees
--    an away trip locks the context row and tests again under the lock.
--    R-T4-10: that lock comes before the phone's row (leaving's order: the
--    sensitive row, the context row, then the phones); nothing here
--    touches the sensitive row.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_dating_trip_choice(p_idempotency_key text, p_show_here boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_c public.dating_session_context;
  v_away boolean;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_show_here IS NULL OR private.dating_key_ok(p_idempotency_key) IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- The away trip the home shows: the flag on and Dating not allowed where
  -- the person is. Nothing else is the server's to choose (R-T4-9). Fix
  -- round 5 (Re4-M-1): a plain read first; no lock unless it is one.
  SELECT * INTO v_c FROM public.dating_session_context AS c WHERE c.user_id = v_user;
  v_away := private.dating_traveller_on() AND v_c.user_id IS NOT NULL AND v_c.dating_allowed_here IS FALSE;
  IF v_away THEN
    -- R-T4-1: the trip is read again under the context row's lock (a device
    -- check that ends it waits). R-T4-10: taken before the phone's row is touched.
    SELECT * INTO v_c FROM public.dating_session_context AS c WHERE c.user_id = v_user FOR UPDATE;
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN -- fix round 1 (C-1): every value, one answer
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF NOT v_away OR NOT private.dating_traveller_on() OR v_c.user_id IS NULL OR v_c.dating_allowed_here IS NOT FALSE THEN -- under the lock
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'no_trip');
  END IF;
  IF NOT public.claim_dating_idempotency('set_dating_trip_choice', p_idempotency_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', true); -- a replay: that key's choice was already made
  END IF;
  UPDATE public.dating_session_context AS c
     SET show_here = p_show_here, trip_note_shown_at = coalesce(c.trip_note_shown_at, now())
   WHERE c.user_id = v_user;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------
-- 6. (W7 carry M-6) Whether a person reads reports, restrictions and
--    appeals now: 'staffed' only in production with an active safety
--    owner and an active moderator (the report's own rule, W7 final I-9);
--    otherwise 'testing', and the app drops every review-time sentence.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_review_mode()
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN private.attune_environment() = 'production'
               AND EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'safety_owner')
               AND EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'moderator')
              THEN 'staffed' ELSE 'testing' END;
$$;


-- ---------------------------------------------------------------------
-- Re-created from their live bodies; only the lines marked
-- "-- Spec 2 W8b" change.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate'::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_profile jsonb;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
BEGIN
  IF p_scope IS NULL OR p_scope NOT IN ('setup', 'candidate') THEN
    RAISE EXCEPTION 'eligibility:invalid_scope' USING ERRCODE = '22023';
  END IF;
  -- 1. Feature.
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE THEN
    RETURN 'feature_unavailable';
  END IF;
  -- 1b. (Fix round 1, I-1) Carried restrictions are readable only under a
  -- set exclusion key whose stored fingerprint matches. Otherwise nobody is
  -- eligible, under the generic system reason (never a personal one),
  -- counted best-effort (a read-only caller can't write; the refusal stands).
  IF private.dating_exclusion_key_ready() IS NOT TRUE THEN
    BEGIN
      PERFORM private.bump_metric_internal('dating.eligibility.key_not_ready');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN 'feature_unavailable';
  END IF;
  -- 2. Account: an adult by Spec 1's DOB, a confirmed phone, EULA v2.
  IF p_user IS NULL
     OR coalesce(public.account_age(p_user), 0) < 18
     OR NOT EXISTS (SELECT 1 FROM auth.users AS a WHERE a.id = p_user AND a.phone_confirmed_at IS NOT NULL)
     OR NOT EXISTS (SELECT 1 FROM public.users AS u
                     WHERE u.id = p_user AND u.eula_accepted_at IS NOT NULL
                       AND coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, 0) >= 2) THEN
    RETURN 'account_unavailable';
  END IF;
  -- 3. Standing. (Fix round 1, I-1) A person whose own HMAC can't be
  -- computed under the set key can't be checked against carried records.
  IF public.dating_account_in_good_standing(p_user) IS NOT TRUE
     OR public.dating_phone_hmac_for_user(p_user) IS NULL THEN
    RETURN 'account_unavailable';
  END IF;
  -- 4. Relationship guard.
  IF public.dating_has_relationship(p_user) IS NOT FALSE THEN
    RETURN 'relationship_active';
  END IF;
  -- 4b. Spec 2 W2 (Task 3 fix round 1, I-1): a candidate whose chosen path is
  -- Spec 2 W2 not Dating is never introduced, even before the path pause lands.
  -- Spec 2 W2 Candidates only (setup's answer drives the cron's 'gates' pause;
  -- Spec 2 W2 a path change has its own); NULL, never chosen, is no signal.
  IF p_scope = 'candidate' AND coalesce((SELECT u.path FROM public.users AS u WHERE u.id = p_user) <> 'dating', false) THEN -- Spec 2 W2
    RETURN 'account_unavailable'; -- Spec 2 W2
  END IF; -- Spec 2 W2
  -- 5. Gentle wait (Spec 2 W2, A-9): candidates only; setup goes ahead.
  IF p_scope = 'candidate' AND private.dating_gentle_wait_opens_at(p_user) IS NOT NULL THEN -- Spec 2 W2
    RETURN 'gentle_wait'; -- Spec 2 W2
  END IF; -- Spec 2 W2
  IF p_scope = 'candidate' AND EXISTS (SELECT 1 FROM public.relationships AS r -- Spec 2 W2 fix round 1 (M-3): an ending with no date is never "no wait"
                                        WHERE p_user IN (r.user_a, r.user_b) AND r.status = 'ended' AND r.ended_at IS NULL) THEN -- Spec 2 W2
    BEGIN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.gentle_wait.undated'); -- Spec 2 W2
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W2
      NULL; -- Spec 2 W2
    END; -- Spec 2 W2
    RETURN 'account_unavailable'; -- Spec 2 W2
  END IF; -- Spec 2 W2
  -- 6. Country and region.
  SELECT to_jsonb(p) INTO v_profile FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  v_country := v_profile ->> 'country_code';
  v_region := v_profile ->> 'region_code';
  IF v_country IS NULL THEN
    RETURN CASE WHEN p_scope = 'setup' THEN private.dating_device_gate(p_user) ELSE 'country_closed' END; -- Spec 2 W4b: gate 8
  END IF;
  v_config := public.dating_country_config(v_country);
  IF v_config IS NULL OR v_config.dating_enabled IS NOT TRUE THEN
    RETURN 'country_closed';
  END IF;
  IF v_config.open_regions IS NOT NULL
     AND (v_region IS NULL OR (v_region = ANY (v_config.open_regions)) IS NOT TRUE) THEN
    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN private.dating_device_gate(p_user) ELSE 'region_closed' END; -- Spec 2 W4b: gate 8
  END IF;
  -- 7. Spec 2 W8b (§2.1, §2.5): here and now. Candidates only, with the flag:
  -- Spec 2 W8b the latest session context says Dating isn't allowed where the person is.
  IF p_scope = 'candidate' AND private.dating_traveller_on() -- Spec 2 W8b
     AND EXISTS (SELECT 1 FROM public.dating_session_context AS c -- Spec 2 W8b
                  WHERE c.user_id = p_user AND c.dating_allowed_here IS FALSE) THEN -- Spec 2 W8b
    RETURN 'away'; -- Spec 2 W8b
  END IF; -- Spec 2 W8b
  -- 8. Spec 2 W4b (§2.1, R-17): a trusted device, for the caller's own requests.
  RETURN private.dating_device_gate(p_user); -- Spec 2 W4b
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_home()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
  v_enrol public.dating_enrollments;
  v_opens timestamptz;
  v_after timestamptz;
  v_err text;
  v_undated boolean; -- Spec 2 W3a (fix round 1, M-2, M-4)
  v_cand text; -- Spec 2 W3a
  v_has jsonb; -- Spec 2 W3a (C-2)
  v_trip jsonb; -- Spec 2 W8b (fix round 2, Re-M-1): the trip, read once
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_has := jsonb_build_object('has_data', private.dating_has_data(v_user)) -- Spec 2 W7a: and an accepted appeal (§3.7), only when there is one
           || CASE WHEN private.dating_appeal_accepted(v_user) THEN jsonb_build_object('appeal_accepted', true) ELSE '{}'::jsonb END; -- Spec 2 W7a
  v_reason := public.dating_eligibility(v_user, 'setup');
  SELECT p.country_code::text, p.region_code INTO v_country, v_region
    FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN
    IF public.dating_require_trusted_device() IS NOT TRUE THEN -- Spec 2 W4b (fix round 1, M-4): nothing about the person to another phone
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable'); -- Spec 2 W4b
    END IF; -- Spec 2 W4b
    v_country := coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))); -- Spec 2 W3a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a (R-4, R-5)
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'reverify_device', -- Spec 2 W3a (C-2); Spec 2 W4b
      'variant', private.dating_reverify_variant(v_user)); -- Spec 2 W4b (§3.3.4): setup_restart or verified
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'account_unavailable' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', private.dating_unavailable_state(v_user)); -- Spec 2 W3a (C-2)
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'country_closed' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'country_closed', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'region_closed' THEN
    v_config := public.dating_country_config(v_country);
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'region_closed', 'country', v_country, 'region', v_region, -- Spec 2 W3a (C-2)
      'open_regions', to_jsonb(coalesce(v_config.open_regions, ARRAY[]::text[])), -- Spec 2 W3a
      'notify', private.dating_notice_state(v_user, v_country, v_region)); -- Spec 2 W3a
  END IF;
  SELECT * INTO v_enrol FROM public.dating_enrollments AS e WHERE e.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || CASE WHEN v_enrol.state = 'paused' -- Spec 2 W3a (C-2)
                THEN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (fix round 1, M-3)
                                        'can_resume', false) -- Spec 2 W3a (T4 fix round 1, I-2): a shared space is open now
                     || private.dating_check_standing(v_user, v_enrol.pause_reason) -- Spec 2 W4b (T3 M-4): where the check stands
                     || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a
                             ELSE '{}'::jsonb END -- Spec 2 W3a
                     || private.dating_trip_json(v_user) -- Spec 2 W8 final server fix (M-1): the reads hide on a trip while paused too
                ELSE jsonb_build_object('state', 'unavailable') END;
  END IF;
  IF v_reason IS DISTINCT FROM 'eligible' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'suspended' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- suspended without a live restriction (W7a routes it) -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'paused' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (C-2)
      'can_resume', coalesce(v_enrol.pause_reason IS DISTINCT FROM 'verification' OR public.dating_age_gate_holds(v_user), false)) -- Spec 2 W4a (fix round 1, M-2): a verification pause resumes once the check holds; W3a (T4 fix round 1, I-2): no shared space holds it
      || private.dating_check_standing(v_user, v_enrol.pause_reason) -- Spec 2 W4b (T3 M-4): where the check stands
      || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a (the §2.4 note)
              ELSE '{}'::jsonb END -- Spec 2 W3a
      || private.dating_trip_json(v_user); -- Spec 2 W8 final server fix (M-1): the reads hide on a trip while paused too
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);
  v_undated := EXISTS (SELECT 1 FROM public.relationships AS r -- Spec 2 W3a (fix round 1, M-2, M-4): an ending with no date
                       WHERE v_user IN (r.user_a, r.user_b) AND r.status = 'ended' AND r.ended_at IS NULL); -- Spec 2 W3a
  IF v_enrol.state = 'active' THEN
    -- Spec 2 W3a (fix round 1, M-2): read here, so a home read never
    -- Spec 2 W3a reaches the candidate check's undated-ending counter.
    IF v_undated THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (M-2)
    END IF; -- Spec 2 W3a (M-2)
    -- Spec 2 W3a (W2 carry): never "you're live" while the candidate check
    -- Spec 2 W3a refuses for anything but the wait (an undated ending, a
    -- Spec 2 W3a path off Dating); the wait itself is the cool-off below.
    v_cand := public.dating_eligibility(v_user, 'candidate'); -- Spec 2 W3a
    v_trip := private.dating_trip_json(v_user); -- Spec 2 W8b (fix round 2, Re-M-1): read once
    IF v_cand IS NOT DISTINCT FROM 'away' OR v_trip -> 'trip' ->> 'kind' IS NOT DISTINCT FROM 'away' THEN -- Spec 2 W8b (§2.1 gate 7, §3.1, §3.11; fix round 1, I-1: in the gentle wait too)
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'away') -- Spec 2 W8b
             || v_trip; -- Spec 2 W8b
    END IF; -- Spec 2 W8b
    IF v_cand IS DISTINCT FROM 'eligible' AND v_cand IS DISTINCT FROM 'gentle_wait' THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a
    END IF; -- Spec 2 W3a
    -- The first drop is the later of the open date and the 72 h cool-off
    -- from account creation (§2.1, §2.8).
    v_after := greatest(coalesce(v_opens, '-infinity'::timestamptz),
                        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours');
    IF v_after > now() THEN
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'cool_off', 'first_drop_at', private.dating_first_drop_at(v_user, v_after)) -- Spec 2 W3a (C-2); Spec 2 W8b
             || v_trip; -- Spec 2 W8b (§3.11): a same-gender trip
    END IF;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'active') -- Spec 2 W3a (C-2); Spec 2 W8b
           || v_trip; -- Spec 2 W8b (§3.11): a same-gender trip
  END IF;
  IF v_opens IS NOT NULL THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'gentle_wait', 'ended_at', (v_opens AT TIME ZONE 'UTC' - interval '30 days') AT TIME ZONE 'UTC', 'opens_at', v_opens, -- in UTC (a DST change moves nothing) -- Spec 2 W3a (C-2)
                              'next_step', private.dating_next_step(v_user), -- Spec 2 W3a
                              'can_shorten', coalesce(private.dating_gentle_wait_can_shorten(v_user), false), -- Spec 2 W3a (carry 8)
                              'first_drop_at', private.dating_first_drop_at(v_user, greatest(v_opens, now(), -- Spec 2 W3a
                                (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours'))); -- Spec 2 W3a
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'how' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'not_started', -- Spec 2 W3a (D1 line 6)
      'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (fix round 1, M-4): no date to promise
        ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END); -- Spec 2 W3a
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'verify' -- Spec 2 W4a (§3.1): a person or the ID vendor is checking
     AND EXISTS (SELECT 1 FROM public.dating_verification_sessions AS vs -- Spec 2 W4a
                  WHERE vs.user_id = v_user AND vs.kind = 'activation' AND vs.state = 'awaiting_review') THEN -- Spec 2 W4a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'verifying', 'next_step', 'verify'); -- Spec 2 W4a
  END IF; -- Spec 2 W4a
  RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user), -- Spec 2 W3a (C-2)
    'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (D13; fix round 1, M-4)
      ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
      (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END) -- Spec 2 W3a; Spec 2 W8b
    || private.dating_icon_offer_json(v_user); -- Spec 2 W8b (§3.2 D13, A-11): the plain-icon offer in Tier 1/2
EXCEPTION WHEN raise_exception THEN
  -- An unreadable field or a missing field key is no state the person can
  -- act on: the neutral 'unavailable', never a raw error. Anything else raises.
  -- Every re-creation keeps this handler (W4, W5, W7, W8 add decrypting
  -- readers; nothing in v1's call graph decrypts yet). Counted best-effort.
  v_err := SQLERRM;
  IF v_err IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    BEGIN
      PERFORM private.bump_metric_internal(CASE WHEN v_err = 'dating:field_key_missing'
                                                THEN 'dating.field_key.missing' ELSE 'dating.home.unreadable_field' END);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (C-2)
  END IF;
  RAISE;
END;
$function$;

DROP FUNCTION IF EXISTS public.get_my_dating_today(); -- Spec 2 W8b (R-T5-1): the phone's choice is a parameter
CREATE OR REPLACE FUNCTION public.get_my_dating_today(p_show_same_gender boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_cfg jsonb;
  v_p public.dating_profiles;
  v_d public.dating_preferences;
  v_t public.dating_settings;
  v_tz text;
  v_drop timestamptz;
  v_cards jsonb := '[]'::jsonb;
  v_waiting jsonb := '[]'::jsonb;
  v_moments jsonb;
  v_state text;
  v_seen boolean;
  v_i public.dating_introductions;
  v_card jsonb;
  v_region text;
  v_sg boolean; -- Spec 2 W8b (§2.5)
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user AND e.state = 'active')
     OR public.dating_eligibility(v_user, 'candidate') IS DISTINCT FROM 'eligible' THEN
    -- Fix round 1 (M-5): a paused person gets the paused state (§3.1's
    -- home `paused`: "Dating is paused. Nobody new sees you."), never cards.
    RETURN jsonb_build_object('ok', false, 'reason',
      CASE WHEN EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user AND e.state = 'paused')
           THEN 'paused' ELSE 'not_eligible' END);
  END IF;
  -- Spec 2 W8b (§2.5; R-T5-2): the viewer's same-gender hiding, once per read; this phone's
  -- Spec 2 W8b "Show it on this phone anyway" (p_show_same_gender) lifts it on this read only.
  v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END; -- Spec 2 W8b
  v_cfg := (private.dating_intro_config()).o_config;
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  SELECT * INTO v_d FROM public.dating_preferences AS d WHERE d.user_id = v_user;
  SELECT * INTO v_t FROM public.dating_settings AS t WHERE t.user_id = v_user;
  SELECT r ->> 'name_key' INTO v_region
    FROM jsonb_array_elements((public.dating_country_config(v_p.country_code)).region_list) AS r WHERE r ->> 'code' = v_p.region_code;
  FOR v_i IN SELECT * FROM private.dating_visible_introductions(v_user) AS x
              ORDER BY CASE WHEN x.user_low_id = v_user THEN x.visible_from_low ELSE x.visible_from_high END DESC, x.id LOOP
    CONTINUE WHEN private.dating_trip_hides(v_user, CASE WHEN v_i.user_low_id = v_user THEN v_i.user_high_id ELSE v_i.user_low_id END, 'introduction', v_sg); -- Spec 2 W8b (§2.5): hidden on a trip
    v_card := private.dating_card(v_user, CASE WHEN v_i.user_low_id = v_user THEN v_i.user_high_id ELSE v_i.user_low_id END, v_i);
    CONTINUE WHEN v_card IS NULL;
    -- Delivered at the last drop: today; earlier: still waiting (no date
    -- is ever sent: no countdown, Fable M8).
    IF (CASE WHEN v_i.user_low_id = v_user THEN v_i.visible_from_low ELSE v_i.visible_from_high END) > now() - interval '24 hours' THEN
      v_cards := v_cards || jsonb_build_array(v_card);
    ELSE
      v_waiting := v_waiting || jsonb_build_array(v_card);
    END IF;
  END LOOP;

  SELECT coalesce(jsonb_agg(jsonb_build_object('match_id', m.id, 'display_name', p.display_name) ORDER BY m.matched_at), '[]'::jsonb)
    INTO v_moments
    FROM public.dating_matches AS m
    JOIN public.dating_profiles AS p ON p.user_id = CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END
   WHERE m.state = 'active' AND v_user IN (m.user_low_id, m.user_high_id)
     AND CASE WHEN m.user_low_id = v_user THEN m.low_moment_seen_at ELSE m.high_moment_seen_at END IS NULL -- Spec 2 W8b
     AND NOT private.dating_trip_hides(v_user, p.user_id, 'match', v_sg); -- Spec 2 W8b (§2.5): the match moment too

  v_seen := EXISTS (SELECT 1 FROM public.dating_introductions AS i
                     WHERE v_user IN (i.user_low_id, i.user_high_id)
                       AND CASE WHEN i.user_low_id = v_user THEN i.visible_from_low ELSE i.visible_from_high END <= now());
  -- The person's next drop with an introduction waiting for it.
  SELECT min(CASE WHEN i.user_low_id = v_user THEN i.visible_from_low ELSE i.visible_from_high END) INTO v_drop
    FROM public.dating_introductions AS i
   WHERE v_user IN (i.user_low_id, i.user_high_id) AND i.state IN ('generated', 'presented', 'interested')
     AND CASE WHEN i.user_low_id = v_user THEN i.visible_from_low ELSE i.visible_from_high END > now()
     AND NOT private.dating_trip_hides(v_user, CASE WHEN i.user_low_id = v_user THEN i.user_high_id ELSE i.user_low_id END, 'introduction', v_sg) -- Spec 2 W8b (§2.5): never promise a hidden one
     -- Fix round 1 (M-3): never promise one that can't arrive: the pair
     -- is still safe and the other person is current, as the visible set.
     AND coalesce(public.dating_candidate_is_current(CASE WHEN i.user_low_id = v_user THEN i.user_high_id ELSE i.user_low_id END), false)
     AND coalesce(private.dating_pair_safe(i.user_low_id, i.user_high_id,
                                           public.dating_phone_hmac_for_user(i.user_low_id),
                                           public.dating_phone_hmac_for_user(i.user_high_id)), false);
  v_state := CASE
    WHEN coalesce(private.dating_cool_off_ends_at(v_user) > now(), true) THEN 'cool_off'
    WHEN jsonb_array_length(v_cards) > 0 THEN 'delivered'
    WHEN v_drop IS NOT NULL THEN 'before_drop'
    -- Spec 2 W8b (§2.5; fix round 1, I-1): dating_open_chats' rule, counting only what this phone shows.
    WHEN (SELECT count(*) FROM public.dating_matches AS m -- Spec 2 W8b
           WHERE m.state = 'active' AND v_user IN (m.user_low_id, m.user_high_id) -- Spec 2 W8b
             AND m.low_we_met_at IS NULL AND m.high_we_met_at IS NULL -- Spec 2 W8b
             AND (m.matched_at > now() - interval '7 days' -- Spec 2 W8b
                  OR EXISTS (SELECT 1 FROM public.dating_messages AS d -- Spec 2 W8b
                              WHERE d.match_id = m.id AND d.created_at > now() - interval '14 days')) -- Spec 2 W8b
             AND NOT private.dating_trip_hides(v_user, CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END, 'match', v_sg)) -- Spec 2 W8b
         >= coalesce((v_cfg ->> 'open_chat_pause_at')::int, 3) THEN 'paused_open_chats' -- Spec 2 W8b
    -- Fix round 1 (M-4): only cards not yet answered, as dating_capacity.
    WHEN (SELECT count(*) FROM jsonb_array_elements(v_waiting) AS c WHERE c ->> 'acted' IS NULL)
         >= coalesce((v_cfg ->> 'waiting_max')::int, 6) THEN 'queue_full'
    ELSE 'empty' END;

  RETURN jsonb_build_object(
    'ok', true,
    'today_state', v_state,
    'drop_at', CASE WHEN v_state = 'before_drop' THEN v_drop
                    WHEN v_state = 'cool_off' THEN private.dating_first_drop_at(v_user, greatest(now(), private.dating_cool_off_ends_at(v_user))) END,
    'region_name_key', v_region,
    'my_name', v_p.display_name, -- the moment's own first-letter avatar (§3.5)
    'cards', v_cards,
    'waiting', v_waiting,
    'moments', v_moments,
    -- Once, after the first introduction (§3.4); shared ground only.
    'family_question', v_seen AND v_p.family_involvement IS NULL AND v_t.family_asked_at IS NULL,
    -- §5.6: no introduction for 14 days in a row, shown once.
    'quiet_note', v_t.quiet_note_at IS NULL
      AND coalesce((SELECT e.activated_at FROM public.dating_enrollments AS e WHERE e.user_id = v_user) < now() - interval '14 days', false)
      AND NOT EXISTS (SELECT 1 FROM public.dating_introductions AS i
                       WHERE v_user IN (i.user_low_id, i.user_high_id) AND i.created_at > now() - interval '14 days'),
    'data_saver', coalesce(v_t.data_saver, false),
    'widen', jsonb_build_object('min_age', v_d.min_age, 'max_age', v_d.max_age, 'scope', v_d.region_scope));
EXCEPTION WHEN raise_exception THEN
  -- An unreadable answer or a missing field key: never a raw error.
  IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  RAISE;
END;
$function$;

DROP FUNCTION IF EXISTS public.get_my_dating_introductions(); -- Spec 2 W8b (R-T5-1): the phone's choice is a parameter
CREATE OR REPLACE FUNCTION public.get_my_dating_introductions(p_show_same_gender boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_cards jsonb := '[]'::jsonb;
  v_i public.dating_introductions;
  v_card jsonb;
  v_sg boolean; -- Spec 2 W8b (§2.5)
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  -- Fix round 1 (M-5): a paused person gets the paused state, as Today;
  -- anyone else not active and eligible reads no cards.
  IF EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user AND e.state = 'paused') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'paused');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user AND e.state = 'active')
     OR public.dating_eligibility(v_user, 'candidate') IS DISTINCT FROM 'eligible' THEN
    RETURN jsonb_build_object('ok', true, 'cards', '[]'::jsonb);
  END IF;
  -- Spec 2 W8b (§2.5; R-T5-2): the viewer's same-gender hiding, once per read; this phone's
  -- Spec 2 W8b "Show it on this phone anyway" (p_show_same_gender) lifts it on this read only.
  v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END; -- Spec 2 W8b
  FOR v_i IN SELECT * FROM private.dating_visible_introductions(v_user) AS x ORDER BY x.created_at DESC, x.id LOOP
    CONTINUE WHEN private.dating_trip_hides(v_user, CASE WHEN v_i.user_low_id = v_user THEN v_i.user_high_id ELSE v_i.user_low_id END, 'introduction', v_sg); -- Spec 2 W8b (§2.5): hidden on a trip
    v_card := private.dating_card(v_user, CASE WHEN v_i.user_low_id = v_user THEN v_i.user_high_id ELSE v_i.user_low_id END, v_i);
    IF v_card IS NOT NULL THEN
      v_cards := v_cards || jsonb_build_array(v_card);
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'cards', v_cards);
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  RAISE;
END;
$function$;

DROP FUNCTION IF EXISTS public.act_on_dating_introduction(text, uuid, text); -- Spec 2 W8b (R-T5-1): the phone's choice is a parameter
CREATE OR REPLACE FUNCTION public.act_on_dating_introduction(p_idempotency_key text, p_introduction_id uuid, p_action text,
  p_show_same_gender boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_i public.dating_introductions;
  v_other text;
  v_mine text;
  v_match uuid;
  v_try integer;
  v_sg boolean; -- Spec 2 W8b (§2.5)
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_action IS NULL OR p_action NOT IN ('interested', 'passed') OR p_introduction_id IS NULL
     OR p_idempotency_key IS NULL OR char_length(p_idempotency_key) NOT BETWEEN 16 AND 128
     OR p_idempotency_key !~ '^[A-Za-z0-9_:.-]+$' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF public.dating_eligibility(v_user, 'candidate') IS DISTINCT FROM 'eligible'
     OR NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user AND e.state = 'active') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;
  -- Spec 2 W8b (§2.5; R-T5-2): the viewer's same-gender hiding, once per read; this phone's
  -- Spec 2 W8b "Show it on this phone anyway" (p_show_same_gender) lifts it on this read only.
  v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END; -- Spec 2 W8b
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      -- A replay answers as the first did.
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'act_on_dating_introduction' AND k.idempotency_key = p_idempotency_key) THEN
        SELECT a.action INTO v_mine FROM public.dating_interest_actions AS a
         WHERE a.actor_user_id = v_user AND a.idempotency_key = p_idempotency_key;
        RETURN jsonb_build_object('ok', true, 'action', v_mine,
          'matched', EXISTS (SELECT 1 FROM public.dating_interest_actions AS a
                              JOIN public.dating_matches AS m ON m.introduction_id = a.introduction_id
                             WHERE a.actor_user_id = v_user AND a.idempotency_key = p_idempotency_key)) -- Spec 2 W6a
          || coalesce((SELECT jsonb_build_object('match_id', m.id) FROM public.dating_interest_actions AS a -- Spec 2 W6a (carry 7)
                         JOIN public.dating_matches AS m ON m.introduction_id = a.introduction_id -- Spec 2 W6a
                        WHERE a.actor_user_id = v_user AND a.idempotency_key = p_idempotency_key), '{}'::jsonb); -- Spec 2 W6a
      END IF;
      SELECT * INTO v_i FROM public.dating_introductions AS i
       WHERE i.id = p_introduction_id AND v_user IN (i.user_low_id, i.user_high_id)
       FOR UPDATE;
      IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM private.dating_visible_introductions(v_user) AS x WHERE x.id = v_i.id) -- Spec 2 W8b
         OR private.dating_trip_hides(v_user, CASE WHEN v_i.user_low_id = v_user THEN v_i.user_high_id ELSE v_i.user_low_id END, 'introduction', v_sg) THEN -- Spec 2 W8b (§2.5): hidden on a trip
        -- Gone, not the caller's, not yet theirs to see, over, or a pair
        -- that is no longer safe: one answer. A pair no longer safe ends.
        IF FOUND AND v_i.state IN ('generated', 'presented', 'interested')
           AND private.dating_pair_safe(v_i.user_low_id, v_i.user_high_id,
                 public.dating_phone_hmac_for_user(v_i.user_low_id), public.dating_phone_hmac_for_user(v_i.user_high_id)) IS NOT TRUE THEN
          UPDATE public.dating_introductions SET state = 'invalidated' WHERE id = v_i.id;
        END IF;
        RETURN jsonb_build_object('ok', false, 'reason', 'introduction_unavailable');
      END IF;
      v_mine := CASE WHEN v_i.user_low_id = v_user THEN v_i.low_action ELSE v_i.high_action END;
      IF v_mine IS NOT NULL THEN
        -- No rewind (§3.4): the first answer stands.
        RETURN jsonb_build_object('ok', true, 'action', v_mine, 'matched', v_i.state = 'matched') -- Spec 2 W6a
          || coalesce((SELECT jsonb_build_object('match_id', m.id) FROM public.dating_matches AS m WHERE m.introduction_id = v_i.id), '{}'::jsonb); -- Spec 2 W6a (carry 7)
      END IF;
      BEGIN
        PERFORM public.check_dating_rate_limit('interest_action', 60, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      PERFORM public.claim_dating_idempotency('act_on_dating_introduction', p_idempotency_key);
      INSERT INTO public.dating_interest_actions (introduction_id, actor_user_id, action, idempotency_key, acted_at)
      VALUES (v_i.id, v_user, p_action, p_idempotency_key, now())
      ON CONFLICT (introduction_id, actor_user_id) DO NOTHING;
      v_other := CASE WHEN v_i.user_low_id = v_user THEN v_i.high_action ELSE v_i.low_action END;
      UPDATE public.dating_introductions AS i
         SET low_action = CASE WHEN i.user_low_id = v_user THEN p_action ELSE i.low_action END,
             high_action = CASE WHEN i.user_high_id = v_user THEN p_action ELSE i.high_action END,
             state = CASE WHEN p_action = 'passed' THEN 'passed'
                          WHEN v_other = 'interested' THEN 'matched' ELSE 'interested' END
       WHERE i.id = v_i.id;
      IF p_action = 'passed' THEN -- Spec 2 W6a (carry 1): never introduced again, even after leaving
        PERFORM private.dating_mark_pair(v_i.user_low_id, v_i.user_high_id); -- Spec 2 W6a
      END IF; -- Spec 2 W6a
      IF p_action = 'interested' AND v_other = 'interested' THEN
        INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state, matched_at, created_at)
        VALUES (v_i.id, v_i.user_low_id, v_i.user_high_id, 'active', now(), now())
        ON CONFLICT (introduction_id) DO NOTHING
        RETURNING id INTO v_match;
        IF v_match IS NOT NULL THEN
          PERFORM private.bump_metric_internal('dating.mutual');
        END IF;
      END IF;
      RETURN jsonb_build_object('ok', true, 'action', p_action, 'matched', p_action = 'interested' AND v_other IS NOT DISTINCT FROM 'interested') -- Spec 2 W6a
        || CASE WHEN p_action = 'interested' AND v_other IS NOT DISTINCT FROM 'interested' -- Spec 2 W6a (carry 7): the match it made
                THEN jsonb_build_object('match_id', coalesce(v_match, (SELECT m.id FROM public.dating_matches AS m WHERE m.introduction_id = v_i.id))) -- Spec 2 W6a
                ELSE '{}'::jsonb END; -- Spec 2 W6a
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$function$;

DROP FUNCTION IF EXISTS public.get_my_dating_matches(boolean); -- Spec 2 W8b (R-T5-1): the phone's choice is a parameter
CREATE OR REPLACE FUNCTION public.get_my_dating_matches(p_include_ended boolean DEFAULT false,
  p_show_same_gender boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_rows jsonb;
  v_ended jsonb;
  v_sg boolean; -- Spec 2 W8b (§2.5)
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  -- Spec 2 W8b (§2.5; R-T5-2): the viewer's same-gender hiding, once per read; this phone's
  -- Spec 2 W8b "Show it on this phone anyway" (p_show_same_gender) lifts it on this read only.
  v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END; -- Spec 2 W8b
  SELECT coalesce(pg_catalog.jsonb_agg(c.row ORDER BY c.at DESC, c.id), '[]'::jsonb) INTO v_rows
    FROM (SELECT m.id, coalesce(l.created_at, m.matched_at) AS at,
                 pg_catalog.jsonb_build_object(
                   'match_id', m.id,
                   'display_name', (SELECT p.display_name FROM public.dating_profiles AS p WHERE p.user_id = s.other),
                   'age', public.account_age(s.other),
                   'last', CASE WHEN l.id IS NULL THEN NULL ELSE
                             private.dating_message_json(l, s.side, m.low_swap_at IS NOT NULL AND m.high_swap_at IS NOT NULL) END,
                   'new', EXISTS (SELECT 1 FROM public.dating_messages AS d
                                   WHERE d.match_id = m.id AND d.sender_side <> s.side
                                     AND private.dating_message_visible(d, s.side) -- Spec 2 W6c
                                     AND d.created_at > coalesce(s.seen, '-infinity'))) AS row
            FROM public.dating_matches AS m
           CROSS JOIN LATERAL (SELECT CASE WHEN m.user_low_id = v_user THEN 'low' ELSE 'high' END AS side,
                                      CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END AS other,
                                      CASE WHEN m.user_low_id = v_user THEN m.low_seen_at ELSE m.high_seen_at END AS seen) AS s
            LEFT JOIN LATERAL (SELECT d.* FROM public.dating_messages AS d WHERE d.match_id = m.id
                                  AND private.dating_message_visible(d, s.side) -- Spec 2 W6c
                                ORDER BY d.created_at DESC, d.id DESC LIMIT 1) AS l ON true
           WHERE v_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active' AND s.other IS NOT NULL
             AND NOT private.dating_pair_blocked(m.user_low_id, m.user_high_id) -- fix round 1 (M-5); Spec 2 W8b
             AND NOT private.dating_trip_hides(v_user, s.other, 'match', v_sg)) AS c; -- Spec 2 W8b (§2.5): hidden on this phone on a trip
  IF coalesce(p_include_ended, false) THEN
    SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'match_id', m.id,
             'display_name', (SELECT p.display_name FROM public.dating_profiles AS p
                               WHERE p.user_id = CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END),
             'ended_at', e.at) ORDER BY e.at DESC, m.id), '[]'::jsonb) -- Spec 2 W7a (W7b Task 5 fix round 1, R-T3-3): the end
      INTO v_ended
      FROM public.dating_matches AS m
     CROSS JOIN LATERAL (SELECT coalesce(CASE WHEN m.state = 'active' -- Spec 2 W7a (R-T3-3): a chat only a block ended, from the block
                                              THEN private.dating_pair_blocked_since(m.user_low_id, m.user_high_id) END, -- Spec 2 W7a
                                         m.closed_at, m.matched_at) AS at) AS e -- Spec 2 W7a
     WHERE v_user IN (m.user_low_id, m.user_high_id)
       AND NOT private.dating_trip_hides(v_user, CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END, 'match', v_sg) -- Spec 2 W8b (§2.5): ended ones too
       AND (((m.state <> 'active' OR m.user_low_id IS NULL OR m.user_high_id IS NULL) AND m.evidence_until > now()) -- Spec 2 W7a
            OR (m.state = 'active' -- Spec 2 W7a (W6 T2 N-4; fix round 1, M-8): a chat only a block ended, for 30 days from it
                AND private.dating_pair_blocked_since(m.user_low_id, m.user_high_id) > now() - interval '30 days')); -- Spec 2 W7a
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'conversations', v_rows)
      || CASE WHEN coalesce(p_include_ended, false) THEN pg_catalog.jsonb_build_object('ended', v_ended) ELSE '{}'::jsonb END;
END;
$function$;

DROP FUNCTION IF EXISTS public.get_dating_messages(uuid, timestamptz, integer); -- Spec 2 W8b (R-T5-1): the phone's choice is a parameter
CREATE OR REPLACE FUNCTION public.get_dating_messages(p_match_id uuid, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 50,
  p_show_same_gender boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_both boolean;
  v_limit integer;
  v_rows jsonb;
  v_more boolean;
  v_seen timestamptz;
  v_ids uuid[]; -- Spec 2 W6c (Task 9 fix round 1, I-2)
  v_keys timestamptz[]; -- Spec 2 W6c
  v_edge timestamptz; -- Spec 2 W6c
  v_sg boolean; -- Spec 2 W8b (§2.5)
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR (p_limit IS NOT NULL AND p_limit NOT BETWEEN 1 AND 100) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  v_limit := coalesce(p_limit, 50);
  SELECT * INTO v_m FROM public.dating_matches AS m
   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
     AND (m.state = 'active' OR m.evidence_until > now());
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  -- Spec 2 W8b (§2.5; R-T5-2): the viewer's same-gender hiding, once per read; this phone's
  -- Spec 2 W8b "Show it on this phone anyway" (p_show_same_gender) lifts it on this read only.
  v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END; -- Spec 2 W8b
  IF private.dating_trip_hides(v_user, CASE WHEN v_m.user_low_id = v_user THEN v_m.user_high_id ELSE v_m.user_low_id END, 'match', v_sg) THEN -- Spec 2 W8b (§2.5)
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable'); -- Spec 2 W8b: hidden on this phone on a trip
  END IF; -- Spec 2 W8b
  v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
  v_both := v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL;
  -- Spec 2 W6c (Task 9 fix round 1, I-2): the candidates are the newest texts by time (a text sits at its own
  -- time) and every guided answer this side can see; each sits at private.dating_message_sort_at.
  SELECT pg_catalog.array_agg(q.id ORDER BY q.k DESC, q.id DESC), pg_catalog.array_agg(q.k ORDER BY q.k DESC, q.id DESC) -- Spec 2 W6c
    INTO v_ids, v_keys -- Spec 2 W6c
    FROM (SELECT d.id, private.dating_message_sort_at(d) AS k FROM public.dating_messages AS d -- Spec 2 W6c
           WHERE d.id IN ((SELECT t.id FROM public.dating_messages AS t -- Spec 2 W6c
                            WHERE t.match_id = p_match_id AND t.kind <> 'guided_answer' -- Spec 2 W6c
                              AND (p_before IS NULL OR t.created_at < p_before) -- Spec 2 W6c
                            ORDER BY t.created_at DESC, t.id DESC LIMIT v_limit + 1) -- Spec 2 W6c
                          UNION -- Spec 2 W6c
                          SELECT g.id FROM public.dating_messages AS g -- Spec 2 W6c
                           WHERE g.match_id = p_match_id AND g.kind = 'guided_answer' -- Spec 2 W6c
                             AND private.dating_message_visible(g, v_side))) AS q -- Spec 2 W6c (§3.6): answers appear together
   WHERE p_before IS NULL OR q.k < p_before; -- Spec 2 W6c
  -- The page: the newest v_limit, and any row tied with the last (a revealed pair is never split). -- Spec 2 W6c
  v_edge := CASE WHEN coalesce(pg_catalog.array_length(v_keys, 1), 0) > v_limit THEN v_keys[v_limit] END; -- Spec 2 W6c
  SELECT coalesce(pg_catalog.jsonb_agg(private.dating_message_json(d, v_side, v_both) -- Spec 2 W6c
                                       || pg_catalog.jsonb_build_object('at', u.k) ORDER BY u.k DESC, u.id DESC), '[]'::jsonb) -- Spec 2 W6c: where it sits
    INTO v_rows -- Spec 2 W6c
    FROM ROWS FROM (pg_catalog.unnest(v_ids), pg_catalog.unnest(v_keys)) AS u(id, k) -- Spec 2 W6c
    JOIN public.dating_messages AS d ON d.id = u.id -- Spec 2 W6c
   WHERE v_edge IS NULL OR u.k >= v_edge; -- Spec 2 W6c
  v_more := v_edge IS NOT NULL AND EXISTS (SELECT 1 FROM public.dating_messages AS d -- Spec 2 W6c
                                            WHERE d.match_id = p_match_id AND d.created_at < v_edge -- Spec 2 W6c
                                              AND private.dating_message_visible(d, v_side) -- Spec 2 W6c
                                              AND private.dating_message_sort_at(d) < v_edge); -- Spec 2 W6c
  -- Fix round 1 (M-7): seen up to the newest incoming message this page
  -- returned, never the clock, so one committed while the page was read
  -- keeps its dot.
  v_seen := (SELECT max((x ->> 'at')::timestamptz) FROM pg_catalog.jsonb_array_elements(v_rows) AS x
              WHERE NOT (x ->> 'mine')::boolean);
  IF p_before IS NULL THEN
    UPDATE public.dating_matches AS m
       SET low_seen_at = CASE WHEN v_side = 'low' THEN v_seen ELSE m.low_seen_at END,
           high_seen_at = CASE WHEN v_side = 'high' THEN v_seen ELSE m.high_seen_at END
     WHERE m.id = p_match_id AND v_seen IS NOT NULL
       AND v_seen > coalesce(CASE WHEN v_side = 'low' THEN m.low_seen_at ELSE m.high_seen_at END, '-infinity');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'chat', private.dating_chat_header(v_m, v_side),
                                       'messages', v_rows, 'more', v_more);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_dating_restriction()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  r public.dating_account_restrictions;
  a public.dating_appeals;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Fix round 1 (M-4): the carry and the release wait at most 2 s; a read
  -- that can't get its locks answers busy (counted), never an error.
  BEGIN
    PERFORM private.dating_carry_over(v_user);
    PERFORM private.dating_release_suspension(v_user);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure -- Spec 2 W8b
            OR unique_violation THEN -- Spec 2 W8b (W7 carry n4-2): a reference-code clash is busy, never an error
    PERFORM private.bump_metric_internal('dating.restriction.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
  SELECT * INTO r FROM public.dating_account_restrictions AS x
   WHERE x.user_id = v_user AND x.restriction_type <> 'under_review'
     AND x.lifted_at IS NULL AND x.starts_at <= now() AND (x.ends_at IS NULL OR x.ends_at > now())
   ORDER BY x.id_check_code IS NULL, -- Spec 2 W7c (final r2, m-3; final, I-1): the asked check (with its code) first while live
            CASE WHEN x.restriction_type = 'suspended' AND x.ends_at IS NULL THEN 0 -- Spec 2 W7c
                 WHEN x.restriction_type = 'suspended' THEN 1
                 WHEN x.restriction_type = 'age_review' THEN 2 ELSE 3 END,
            x.ends_at DESC NULLS FIRST, x.created_at DESC
   LIMIT 1;
  IF r.id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'restriction', NULL,
                                         'appeal_accepted', private.dating_appeal_accepted(v_user), -- Spec 2 W8b
                                         'review', private.dating_review_mode()); -- Spec 2 W8b (W7 carry M-6)
  END IF;
  SELECT * INTO a FROM public.dating_appeals AS x WHERE x.restriction_id = r.id;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'appeal_accepted', private.dating_appeal_accepted(v_user),
    'review', private.dating_review_mode(), -- Spec 2 W8b (W7 carry M-6)
    'restriction', pg_catalog.jsonb_build_object(
      'id', r.id,
      'type', CASE r.restriction_type WHEN 'moderation_hold' THEN 'hold' ELSE r.restriction_type END,
      'ends_at', r.ends_at,
      'category', r.category,
      -- Spec 2 W7c (final, client I-3, I-1): where it came from (never who reported or
      -- Spec 2 W7c decided), and the asked check's reference code for the ID email.
      'source', CASE WHEN r.restriction_type = 'moderation_hold' AND r.category = 'csam' THEN 'csam' -- Spec 2 W7c
                     WHEN r.id_check_code IS NOT NULL THEN 'id_check' -- Spec 2 W7c
                     WHEN r.source = 'carried_over' THEN 'carried' -- Spec 2 W7c
                     WHEN r.source = 'report' THEN 'p0_interim' -- Spec 2 W7c
                     WHEN r.source = 'csam_hash' THEN 'csam' -- Spec 2 W7c
                     ELSE r.source END, -- Spec 2 W7c: moderator, age_assurance
      'id_check_code', r.id_check_code, -- Spec 2 W7c
      'can_appeal', r.appealable AND a.id IS NULL,
      'appeal', CASE WHEN a.id IS NULL THEN NULL
                     ELSE pg_catalog.jsonb_build_object('state', a.state, 'submitted_at', a.submitted_at,
                                                        'decided_at', a.decided_at) END));
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_dating_appeal(p_idempotency_key text, p_restriction_id uuid, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_text constant text := NULLIF(btrim(coalesce(p_text, '')), '');
  r public.dating_account_restrictions;
  v_appeal uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_restriction_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) OR coalesce(char_length(v_text), 0) > 500 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'submit_dating_appeal' AND k.idempotency_key = p_idempotency_key) THEN
        RETURN pg_catalog.jsonb_build_object('ok', true, 'review', private.dating_review_mode()); -- Spec 2 W8b (W7 carry M-6)
      END IF;
      SELECT * INTO r FROM public.dating_account_restrictions AS x
       WHERE x.id = p_restriction_id AND x.user_id = v_user
       FOR UPDATE;
      IF r.id IS NULL OR NOT r.appealable OR r.lifted_at IS NOT NULL OR r.starts_at > now()
         OR (r.ends_at IS NOT NULL AND r.ends_at <= now()) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'appeal_unavailable');
      END IF;
      IF EXISTS (SELECT 1 FROM public.dating_appeals AS a WHERE a.restriction_id = r.id) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_appealed');
      END IF;
      PERFORM public.claim_dating_idempotency('submit_dating_appeal', p_idempotency_key);
      INSERT INTO public.dating_appeals (restriction_id, user_id, text) VALUES (r.id, v_user, v_text)
      RETURNING id INTO v_appeal;
      INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, appeal_id, sla_due_at)
      VALUES ('appeal', 'P2', v_user, public.dating_phone_hmac_for_user(v_user), v_appeal, now() + interval '7 days');
      PERFORM private.bump_metric_internal('dating.appeal.submitted');
      RETURN pg_catalog.jsonb_build_object('ok', true, 'review', private.dating_review_mode()); -- Spec 2 W8b (W7 carry M-6)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        PERFORM private.bump_metric_internal('dating.appeal.busy'); -- Spec 2 W7c (final, M-1): counted, as the report's
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_report_answer(p_report uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT pg_catalog.jsonb_build_object('ok', true,
           'review', private.dating_review_mode(), -- Spec 2 W8b (fix round 1, M-6): W7c final I-9's rule, now one helper
           'sla_hours', greatest(1, ceil(extract(epoch FROM (r.sla_due_at - r.created_at)) / 3600)::int))
    FROM public.dating_reports AS r WHERE r.id = p_report;
$function$;

CREATE OR REPLACE FUNCTION public.send_dating_digests()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  r record;
  v_n integer := 0;
  v_drop timestamptz;
  v_due uuid[] := '{}'; -- Spec 2 W5 final (M-3)
  v_sent uuid[] := '{}'; -- Spec 2 W5 final (M-3)
  v_user uuid; -- Spec 2 W5 final (M-3)
  v_state text; -- Spec 2 W5 final (M-3)
BEGIN
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE THEN
    RETURN 0;
  END IF;
  -- No push key, no push (fail closed, counted; the cron never raises).
  IF public.app_setting('dating_push_key') IS NULL THEN
    PERFORM private.bump_metric_internal('dating.digest.push_key_missing');
    RETURN 0;
  END IF;
  FOR r IN
    SELECT t.user_id, t.digest_sent_at
      FROM public.dating_settings AS t
      JOIN public.dating_enrollments AS e ON e.user_id = t.user_id AND e.state = 'active'
     WHERE t.digest_push
     ORDER BY t.user_id
  LOOP
    BEGIN -- Spec 2 W5 final (M-3): one person's error never stops the others' digests
    -- The drop that fell in the last hour, if one did.
    v_drop := private.dating_first_drop_at(r.user_id, now() - interval '1 hour');
    CONTINUE WHEN v_drop > now();
    CONTINUE WHEN r.digest_sent_at IS NOT NULL AND r.digest_sent_at >= v_drop - interval '1 hour';
    CONTINUE WHEN NOT (
      EXISTS (SELECT 1 FROM private.dating_visible_introductions(r.user_id) AS x
               WHERE CASE WHEN x.user_low_id = r.user_id THEN x.visible_from_low ELSE x.visible_from_high END > now() - interval '24 hours' -- Spec 2 W8b
                 -- Spec 2 W8b (§2.5; carry 3, R-T5-4): never for a card whose other person is somewhere
                 -- Spec 2 W8b same-gender isn't allowed while it is at their home (identity-free, S-5).
                 AND NOT (private.dating_traveller_on() -- Spec 2 W8b
                          AND EXISTS (SELECT 1 FROM public.dating_session_context AS c -- Spec 2 W8b
                                        JOIN public.dating_profiles AS p ON p.user_id = c.user_id -- Spec 2 W8b
                                       WHERE c.user_id = CASE WHEN x.user_low_id = r.user_id THEN x.user_high_id ELSE x.user_low_id END -- Spec 2 W8b
                                         AND c.same_gender_allowed_here IS FALSE -- Spec 2 W8b
                                         AND coalesce(private.dating_same_gender_on(p.country_code::text), false)))) -- Spec 2 W8b
      OR EXISTS (SELECT 1 FROM public.dating_matches AS m
                  WHERE m.state = 'active' AND r.user_id IN (m.user_low_id, m.user_high_id)
                    AND m.matched_at > coalesce(r.digest_sent_at, '-infinity'::timestamptz)));
    v_due := v_due || r.user_id; -- Spec 2 W5 final (M-3): the loop only reads; it takes no row lock
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W5 final (M-3): counted by SQLSTATE only, never a message
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE; -- Spec 2 W5 final (M-3)
      PERFORM private.bump_metric_internal('dating.digest.failed'); -- Spec 2 W5 final (M-3)
      PERFORM private.bump_metric_internal('dating.digest.failed.' || lower(v_state)); -- Spec 2 W5 final (M-3)
    END; -- Spec 2 W5 final (M-3)
  END LOOP;
  -- Spec 2 W5 final (M-3): the writes, after every read: the push queue's row
  -- Spec 2 W5 final (its key share on the person's users row) and then one
  -- Spec 2 W5 final statement marking the sent, so no row lock is held while
  -- Spec 2 W5 final anyone is still being read (commit per person: W5a gate).
  FOREACH v_user IN ARRAY v_due LOOP -- Spec 2 W5 final (M-3)
    BEGIN -- Spec 2 W5 final (M-3)
      IF private.dating_queue_me_update(v_user, 'digest', 'new') THEN -- Spec 2 W5 final (M-3)
        v_n := v_n + 1; -- Spec 2 W5 final (M-3)
      END IF; -- Spec 2 W5 final (M-3)
      v_sent := v_sent || v_user; -- Spec 2 W5 final (M-3)
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W5 final (M-3)
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE; -- Spec 2 W5 final (M-3)
      PERFORM private.bump_metric_internal('dating.digest.failed'); -- Spec 2 W5 final (M-3)
      PERFORM private.bump_metric_internal('dating.digest.failed.' || lower(v_state)); -- Spec 2 W5 final (M-3)
    END; -- Spec 2 W5 final (M-3)
  END LOOP; -- Spec 2 W5 final (M-3)
  BEGIN -- Spec 2 W5 final (M-3): the cron never raises; a push already queued is deduplicated by its day key
    UPDATE public.dating_settings SET digest_sent_at = now() WHERE user_id = ANY (v_sent); -- Spec 2 W5 final (M-3)
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W5 final (M-3)
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE; -- Spec 2 W5 final (M-3)
    PERFORM private.bump_metric_internal('dating.digest.failed'); -- Spec 2 W5 final (M-3)
    PERFORM private.bump_metric_internal('dating.digest.failed.' || lower(v_state)); -- Spec 2 W5 final (M-3)
  END; -- Spec 2 W5 final (M-3)
  RETURN v_n;
END;
$function$;

-- ---------------------------------------------------------------------
-- Self-revoke (the W6 final pattern); the twin grants.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  private.dating_traveller_on(), private.dating_wants_same_gender(uuid),
  private.dating_trip_hides(uuid, uuid, text), private.dating_trip_json(uuid),
  private.dating_icon_offer_json(uuid),
  private.dating_has_same_gender_pair(uuid), private.dating_same_gender_trip(uuid),
  private.dating_intro_counts(text, timestamptz), private.dating_pair_seen_as_man_woman(uuid, uuid),
  private.dating_same_gender_hiding(uuid),
  private.dating_trip_hides(uuid, uuid, text, boolean),
  public.record_dating_device_check(uuid, text, text, text),
  public.set_dating_trip_choice(text, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_review_mode() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.get_my_dating_today(boolean), public.get_my_dating_introductions(boolean),
  public.act_on_dating_introduction(text, uuid, text, boolean), public.get_my_dating_matches(boolean, boolean),
  public.get_dating_messages(uuid, timestamptz, integer, boolean)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

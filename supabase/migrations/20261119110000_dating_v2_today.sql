-- supabase/migrations/20261119110000_dating_v2_today.sql
-- Spec 2 W5b (§4.9 W5b, §3.4, §3.5, §3.13, §4.4, §4.7, §5.8; carries 8,
-- 12-14): Today. The card others see (one builder: the person's own
-- answers as they chose to show them, the reason ids, the viewable photos'
-- count and captions, never a storage path, who they'd like to meet or a
-- hidden field); get_my_dating_today() (the day state, today's cards and
-- the ones still waiting, the match moments, the family question and the
-- quiet note); get_my_dating_introductions() v2 (every card the person can
-- answer, for /dating/introduction/:id); act v2 (answers {ok, reason},
-- never raises a refusal; per-side visibility; the caller's own phone
-- first; one match from simultaneous interest; no push); the match moment
-- marks; the Today notes; dating_photo_keys_for_viewer for dating-photo-urls
-- (the phone checked first, only viewable photos, never before mutual
-- interest when the person chose that); send_dating_digests and its cron.
-- An answer that is not a filter (the family question, a name, what is
-- shown) no longer ends the person's open introductions.
-- Dating stays off. Idempotent.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- =====================================================================
-- 1. Columns: each side's match moment (§3.5); the Today notes and the
--    digest's last send (§3.4, §3.13, §5.6).
-- =====================================================================
ALTER TABLE public.dating_matches
  ADD COLUMN IF NOT EXISTS low_moment_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS high_moment_seen_at timestamptz;
ALTER TABLE public.dating_settings
  ADD COLUMN IF NOT EXISTS family_asked_at timestamptz,
  ADD COLUMN IF NOT EXISTS quiet_note_at timestamptz,
  ADD COLUMN IF NOT EXISTS digest_sent_at timestamptz;

-- =====================================================================
-- 2. The v1 read goes (W5b replaces it; no caller in lib/).
-- =====================================================================
DROP FUNCTION IF EXISTS public.get_my_dating_introductions(integer);

-- =====================================================================
-- 3. The card (§3.4, §5.8; carries 13, 14).
-- =====================================================================
-- Fix round 2 (I-3): whether a photo caption carries contact details,
-- by spec §6.1's patterns for dating_mask_contacts (phone runs with O/o
-- as 0, dates taken out first; numbers in words; emails, "at"/"dot"
-- included; URLs and bare domains with the listed TLDs, "dot com"
-- spelled out; @handles; a platform or contact word; crypto
-- addresses). Fix round 4 (M-12, I-5): it reads the content filter's own
-- fold first (private.normalize_for_filter, accents dropped), reads
-- leetspeak and split letters for the platform words, and knows Ghana's
-- common apps and mobile money. Captions are labels, so it fails closed: a false positive
-- only leaves the label off. W6a replaces it with dating_mask_contacts
-- span masking.
CREATE OR REPLACE FUNCTION private.dating_caption_has_contact(p_caption text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  WITH n AS (
    -- fix round 4 (M-12): the content filter's own fold (NFKC, lower case,
    -- confusables, its separators to a space), then accents dropped (ä a);
    -- for the digits, calendar dates taken out before the fold
    SELECT p_caption AS raw,
           pg_catalog.normalize(pg_catalog.regexp_replace(
             pg_catalog.normalize(private.normalize_for_filter(p_caption), 'NFD'),
             '[\u0300-\u036F\u1AB0-\u1AFF\u1DC0-\u1DFF\u20D0-\u20FF\uFE20-\uFE2F]', '', 'g'), 'NFC') AS f,
           private.normalize_for_filter(pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.normalize(p_caption, 'NFKC')),
             '\m(\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}|\d{4}-\d{1,2}-\d{1,2})\M', ' ', 'g')) AS undated),
  l AS (
    -- fix round 4 (M-12), for the platform words only: leetspeak beside a
    -- letter (4 a, 5 s, 3 e, 0 o, @ a; twice, so runs resolve)
    SELECT n.raw, n.f, n.undated,
           pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
           pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(n.f,
             '(?<=[a-z])4|4(?=[a-z])', 'a', 'g'), '(?<=[a-z])5|5(?=[a-z])', 's', 'g'), '(?<=[a-z])3|3(?=[a-z])', 'e', 'g'),
             '(?<=[a-z])0|0(?=[a-z])', 'o', 'g'), '(?<=[a-z])@|@(?=[a-z])', 'a', 'g'),
             '(?<=[a-z])4|4(?=[a-z])', 'a', 'g'), '(?<=[a-z])5|5(?=[a-z])', 's', 'g'), '(?<=[a-z])3|3(?=[a-z])', 'e', 'g'),
             '(?<=[a-z])0|0(?=[a-z])', 'o', 'g'), '(?<=[a-z])@|@(?=[a-z])', 'a', 'g') AS leet
      FROM n),
  c AS (
    SELECT l.raw,
           -- (fix round 4: split letters are joined in the platform-word texts
           -- below, which subsumes round 3's space-only join here)
           l.f AS t,
           -- the platform-word texts: 1 read as i, or as l, beside a letter;
           -- single letters split by spaces, dots, dashes or underscores joined
           pg_catalog.regexp_replace(pg_catalog.regexp_replace(l.leet, '(?<=[a-z])1|1(?=[a-z])', 'i', 'g'),
                          '(?<![a-z0-9])([a-z])[\s._-]+(?=[a-z](?![a-z0-9]))', '\1', 'g') AS wi,
           pg_catalog.regexp_replace(pg_catalog.regexp_replace(l.leet, '(?<=[a-z])1|1(?=[a-z])', 'l', 'g'),
                          '(?<![a-z0-9])([a-z])[\s._-]+(?=[a-z](?![a-z0-9]))', '\1', 'g') AS wl,
           -- the digits: O/o beside a digit as 0, l/I/i as 1, and (fix round 4,
           -- M-12) any run of other characters between digits taken out
           pg_catalog.regexp_replace(
             pg_catalog.regexp_replace(
               pg_catalog.regexp_replace(
                 pg_catalog.regexp_replace(l.undated, '(?<=\d)o|o(?=\d)', '0', 'g'),
                 '(?<=\d)[li]|[li](?=\d)', '1', 'g'),
               '(?<=\d)o|o(?=\d)', '0', 'g'),
             '(?<=\d)[^a-z0-9]+(?=\d)', '', 'g') AS digits
      FROM l)
  SELECT p_caption IS NOT NULL AND (
       -- platform and contact words; fix round 4 (I-5): Ghana's common apps
       -- and mobile money too
       c.wi ~ '\m(snapchat|snap|sc|telegram|tg|signal|whatsapp|watsapp|wassap|facebook|fb|messenger|instagram|insta|ig|tiktok|twitter|threads|gmail|yahoo|hotmail|outlook|icloud|email|e-mail|mail|number|call|text|dm|dms|inbox|handle|venmo|onlyfans|imo|botim|viber|wechat|discord|kik|youtube|yt|linkedin|reddit|momo)\M'
    OR c.wl ~ '\m(snapchat|snap|sc|telegram|tg|signal|whatsapp|watsapp|wassap|facebook|fb|messenger|instagram|insta|ig|tiktok|twitter|threads|gmail|yahoo|hotmail|outlook|icloud|email|e-mail|mail|number|call|text|dm|dms|inbox|handle|venmo|onlyfans|imo|botim|viber|wechat|discord|kik|youtube|yt|linkedin|reddit|momo)\M'
    OR c.wi ~ '\m(snap ?chat|tele ?gram|whats ?app|wats ?app|insta ?gram|face ?book|tik ?tok|cash ?app|only ?fans|we ?chat|you ?tube|linked ?in|the ?gram)\M'
    OR c.wl ~ '\m(snap ?chat|tele ?gram|whats ?app|wats ?app|insta ?gram|face ?book|tik ?tok|cash ?app|only ?fans|we ?chat|you ?tube|linked ?in|the ?gram)\M'
    -- fix round 4 (I-5): "line" only as a LINE id, and a reddit u/handle
    OR c.t ~ '\mline ?id\M|\mline\s*:' OR c.t ~ '(^|[^a-z0-9])u/[a-z0-9_-]'
    OR c.t ~ '\m(add|find|message|contact|hit) me\M' OR c.t ~ '\mof link\M' OR c.t ~ '\$[a-z]'
    OR c.t ~ '\m(wa|x)\M\s*[:@]' OR c.t ~ '\mx\.com\M'
    OR c.digits ~ '\d{7,}'
    OR c.t ~ '(\m(zero|oh|o|one|two|three|four|five|six|seven|eight|nine|double|triple)\M[^a-z0-9]*){7,}'
    -- a handle has no space after the @ ("Sunset @ Labadi" shows)
    OR c.t ~ '@[a-z0-9_.]'
    -- "name at domain dot tld" within a token or two (fix round 4: two, the
    -- second of two letters or more), no comma between, never a plain word
    -- after the dot ("at dusk, dot of light" shows); and a spaced " . "
    OR c.t ~ '(\mat\M|\(at\)|\[at\])[\s()\[\]]*[a-z0-9-]+([\s()\[\]]+[a-z0-9-]{2,})?[\s()\[\]]*(\mdot\M|\(dot\)|\[dot\])[\s()\[\]]*(?!(of|on|in|the|a|an|and|to|at)\M)[a-z]{2,}\M'
    OR c.t ~ '\mat\M\s+[a-z0-9-]+\s+\.\s+[a-z]{2,}\M'
    OR c.t ~ 'https?://|\mwww\.'
    OR c.t ~ '[a-z0-9-]\.(com|net|org|gh|ng|uk|co|io|me|app|link|ly)\M'
    OR c.t ~ '\mdot\s*(com|net|org|gh|ng|uk|co|io|me|app|link|ly)\M'
    OR c.t ~ '\m0x[0-9a-f]{40}\M' OR c.raw ~ '\mT[1-9A-HJ-NP-Za-km-z]{33}\M' OR c.t ~ '\mbc1[0-9a-z]{25,62}\M')
  FROM c;
$$;

-- A photo others may see: approved and cleared by the inline CSAM scan
-- (never a hit, an error or one waiting), the derived "viewable" rule.
CREATE OR REPLACE FUNCTION private.dating_photo_viewable(p_moderation text, p_csam text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(p_moderation = 'approved' AND p_csam = 'clear', false);
$$;

-- [p_subject] as [p_viewer] sees them on introduction [p_intro]. Built
-- from the subject's own rows; decrypts only what the subject chose to
-- show. NULL when the subject has no profile.
CREATE OR REPLACE FUNCTION private.dating_card(p_viewer uuid, p_subject uuid, p_intro public.dating_introductions)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_p public.dating_profiles;
  v_s public.dating_profile_sensitive;
  v_identity jsonb;
  v_faith jsonb;
  v_marital text;
  v_region jsonb;
  v_side jsonb;
  v_photos jsonb;
  v_v public.dating_profiles;
  v_reasons text[];
BEGIN
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = p_subject;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_s FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_subject;
  -- Fix round 2 (I-4): the reasons that come only from shared answers are
  -- re-checked against both people's answers now, so a hidden timeline or
  -- a changed family answer leaves the card and nothing ends: the timeline
  -- reason holds while both still say marriage, the same timeline and
  -- show it (else it reads as the plain same intention, still true:
  -- intention ends introductions when it changes); family_same_<x> while
  -- both still answer <x>. With none left, §5.8's fallback.
  SELECT * INTO v_v FROM public.dating_profiles AS p WHERE p.user_id = p_viewer;
  SELECT coalesce(array_agg(x.r ORDER BY x.n), '{}') INTO v_reasons
    FROM (SELECT u.n,
                 CASE WHEN u.r = 'same_intention_timeline' THEN
                        CASE WHEN v_p.intention = 'marriage' AND v_v.intention = 'marriage'
                                  AND v_p.marriage_timeline = v_v.marriage_timeline
                                  AND v_p.timeline_visible AND v_v.timeline_visible THEN u.r
                             WHEN v_p.intention = v_v.intention THEN 'same_intention' END
                      -- Spec 2 W5b T6 fix round 1 (M-4): a faith reason holds only while both still show faith
                      WHEN u.r IN ('same_faith', 'faith_matters') THEN
                        CASE WHEN v_p.faith_visible IS TRUE AND v_v.faith_visible IS TRUE THEN u.r END
                      WHEN u.r LIKE 'family\_same\_%' THEN
                        CASE WHEN v_p.family_involvement = v_v.family_involvement
                                  AND u.r = 'family_same_' || v_p.family_involvement THEN u.r END
                      ELSE u.r END AS r
            FROM unnest(p_intro.reasons) WITH ORDINALITY AS u(r, n)) AS x
   WHERE x.r IS NOT NULL;
  IF cardinality(v_reasons) = 0 AND cardinality(p_intro.reasons) > 0 THEN
    v_reasons := CASE WHEN v_p.country_code = v_v.country_code AND v_p.region_code = v_v.region_code THEN ARRAY['same_region']
                      WHEN v_p.country_code IS DISTINCT FROM v_v.country_code THEN ARRAY['across_borders']
                      ELSE '{}'::text[] END;
  END IF;
  IF v_p.gender_visible THEN
    v_identity := private.dating_field_decrypt(v_s.identity_enc);
  END IF;
  IF v_p.faith_visible THEN
    v_faith := private.dating_field_decrypt(v_s.faith_enc);
  END IF;
  IF v_p.marital_visible THEN
    v_marital := private.dating_field_decrypt(v_s.marital_enc) ->> 'marital';
  END IF;
  SELECT r INTO v_region FROM jsonb_array_elements((public.dating_country_config(v_p.country_code)).region_list) AS r
   WHERE r ->> 'code' = v_p.region_code;
  -- The side is never a field; it is named only by its own reason.
  IF 'same_side' = ANY (p_intro.reasons) THEN
    SELECT x INTO v_side FROM jsonb_array_elements(v_region -> 'sides') AS x WHERE x ->> 'code' = v_p.side_code;
  END IF;
  -- Fix round 1 (I-2, owner): a caption reaches the card only when the
  -- content filter the prompts and the card's free text use passes it; a
  -- caption it flags (contact details, unkind) is left off the card, so
  -- it fails closed. The owner's own list is unchanged.
  -- Fix round 1 (M-7): no photo is listed while the photo flag is off
  -- (the keys refuse then too).
  IF public.dating_flag_enabled('dating_profile_photos') IS TRUE THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'position', f.position,
             -- W6a: replace with dating_mask_contacts span masking
             'caption', CASE WHEN private.content_filter_verdict(f.caption, NULL) IS NULL
                              AND coalesce(private.dating_caption_has_contact(f.caption), true) IS FALSE THEN f.caption END) -- fix round 2 (I-3)
             ORDER BY f.position), '[]'::jsonb)
      INTO v_photos
      FROM public.dating_profile_photos AS f
     WHERE f.user_id = p_subject AND private.dating_photo_viewable(f.moderation_state, f.csam_state);
  ELSE
    v_photos := '[]'::jsonb;
  END IF;
  RETURN jsonb_build_object(
    'id', p_intro.id,
    'display_name', v_p.display_name,
    'age', public.account_age(p_subject),
    'region_name_key', v_region ->> 'name_key',
    'side_name_key', v_side ->> 'name_key',
    'intention', v_p.intention,
    'marriage_timeline', CASE WHEN v_p.intention = 'marriage' AND v_p.timeline_visible THEN v_p.marriage_timeline END,
    'children_have', v_p.children_have,
    'children_want', v_p.children_want,
    'gender', CASE WHEN v_identity IS NULL THEN NULL ELSE jsonb_build_object(
      'identity', v_identity ->> 'identity', 'specific', v_identity ->> 'specific',
      'specific_text', v_identity ->> 'specific_text') END,
    'pronouns', v_identity ->> 'pronouns',
    'faith', CASE WHEN v_faith IS NULL THEN NULL ELSE jsonb_build_object(
      'faith', v_faith ->> 'faith', 'denomination', v_faith ->> 'denomination') END,
    'marital', CASE WHEN v_marital IN ('divorced', 'widowed') THEN v_marital END,
    'prompts', coalesce((SELECT jsonb_agg(jsonb_build_object('prompt_id', q.prompt_id, 'answer', q.answer) ORDER BY q.position)
                           FROM public.dating_prompts AS q
                          WHERE q.user_id = p_subject AND q.moderation_state = 'approved'), '[]'::jsonb),
    'reasons', to_jsonb(v_reasons), -- fix round 2 (I-4): re-checked above
    -- D9: while the subject keeps photos for mutual interest, none (and
    -- the card says they're coming); else the viewable ones, captions as
    -- their spoken labels (§3.4 accessibility).
    'photos_after_mutual', v_p.photos_after_mutual,
    'photos', CASE WHEN v_p.photos_after_mutual THEN '[]'::jsonb ELSE v_photos END,
    'acted', CASE WHEN p_intro.user_low_id = p_viewer THEN p_intro.low_action ELSE p_intro.high_action END);
END;
$$;

-- The introductions [p_viewer] can answer now: their side's drop has
-- come, their own seven days are not over, they haven't passed, the pair
-- is still safe (blocks, former partners, never-introduce: kept rows too)
-- and both are current candidates. Never "they liked you": only the
-- viewer's own action is read.
CREATE OR REPLACE FUNCTION private.dating_visible_introductions(p_viewer uuid)
RETURNS SETOF public.dating_introductions
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT i.*
    FROM public.dating_introductions AS i
   WHERE p_viewer IN (i.user_low_id, i.user_high_id)
     AND i.state IN ('generated', 'presented', 'interested')
     AND i.expires_at > now()
     AND CASE WHEN i.user_low_id = p_viewer
              THEN i.visible_from_low <= now() AND i.low_action IS DISTINCT FROM 'passed'
                   AND i.visible_from_low + make_interval(days => coalesce(((private.dating_intro_config()).o_config ->> 'lifetime_days')::int, 7)) > now()
              ELSE i.visible_from_high <= now() AND i.high_action IS DISTINCT FROM 'passed'
                   AND i.visible_from_high + make_interval(days => coalesce(((private.dating_intro_config()).o_config ->> 'lifetime_days')::int, 7)) > now() END
     AND coalesce(public.dating_candidate_is_current(CASE WHEN i.user_low_id = p_viewer THEN i.user_high_id ELSE i.user_low_id END), false)
     AND coalesce(private.dating_pair_safe(i.user_low_id, i.user_high_id,
                                           public.dating_phone_hmac_for_user(i.user_low_id),
                                           public.dating_phone_hmac_for_user(i.user_high_id)), false);
$$;

-- =====================================================================
-- 4. Today (§3.4, §5.6; carry 8).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.get_my_dating_today()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE -- Spec 2 W5 final (I-1): PostgREST runs a STABLE RPC READ ONLY, where the device check's touch of last_seen_at (§2.3 freshness, R-3) fails and is swallowed
SECURITY DEFINER
SET search_path = ''
AS $$
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
  v_cfg := (private.dating_intro_config()).o_config;
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  SELECT * INTO v_d FROM public.dating_preferences AS d WHERE d.user_id = v_user;
  SELECT * INTO v_t FROM public.dating_settings AS t WHERE t.user_id = v_user;
  SELECT r ->> 'name_key' INTO v_region
    FROM jsonb_array_elements((public.dating_country_config(v_p.country_code)).region_list) AS r WHERE r ->> 'code' = v_p.region_code;
  FOR v_i IN SELECT * FROM private.dating_visible_introductions(v_user) AS x
              ORDER BY CASE WHEN x.user_low_id = v_user THEN x.visible_from_low ELSE x.visible_from_high END DESC, x.id LOOP
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
     AND CASE WHEN m.user_low_id = v_user THEN m.low_moment_seen_at ELSE m.high_moment_seen_at END IS NULL;

  v_seen := EXISTS (SELECT 1 FROM public.dating_introductions AS i
                     WHERE v_user IN (i.user_low_id, i.user_high_id)
                       AND CASE WHEN i.user_low_id = v_user THEN i.visible_from_low ELSE i.visible_from_high END <= now());
  -- The person's next drop with an introduction waiting for it.
  SELECT min(CASE WHEN i.user_low_id = v_user THEN i.visible_from_low ELSE i.visible_from_high END) INTO v_drop
    FROM public.dating_introductions AS i
   WHERE v_user IN (i.user_low_id, i.user_high_id) AND i.state IN ('generated', 'presented', 'interested')
     AND CASE WHEN i.user_low_id = v_user THEN i.visible_from_low ELSE i.visible_from_high END > now()
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
    WHEN private.dating_open_chats(v_user, now()) >= coalesce((v_cfg ->> 'open_chat_pause_at')::int, 3) THEN 'paused_open_chats'
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
$$;

-- Every card the person can answer now (§4.4 v2; /dating/introduction/:id).
CREATE OR REPLACE FUNCTION public.get_my_dating_introductions()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE -- Spec 2 W5 final (I-1): as Today, so the device check's touch is a write PostgREST allows
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_cards jsonb := '[]'::jsonb;
  v_i public.dating_introductions;
  v_card jsonb;
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
  FOR v_i IN SELECT * FROM private.dating_visible_introductions(v_user) AS x ORDER BY x.created_at DESC, x.id LOOP
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
$$;

-- =====================================================================
-- 5. Act v2 (§3.4, §4.10; R-17): fixed answers, never a raised refusal.
--    The caller's own phone first; the caller's setup lock, then the
--    introduction row (the shared order: exit takes the same lock first),
--    with a bounded retry; one uniform answer for an introduction that
--    isn't the caller's, doesn't exist, isn't theirs to see yet or is
--    over (H2). A permanent safety reason (a block, former partners, a
--    never-introduce entry) ends the pair; a counterpart who is away for
--    now (paused, not seen) leaves it as it is. Mutual interest makes one
--    match (the second actor waits on the row) and queues no push.
-- =====================================================================
DROP FUNCTION IF EXISTS public.act_on_dating_introduction(text, uuid, text);
CREATE FUNCTION public.act_on_dating_introduction(p_idempotency_key text, p_introduction_id uuid, p_action text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
-- Fix round 1 (M-6): each lock wait (the setup lock, the row) gives up in
-- 2 s, so the 55P03 arm retries and the third ends 'busy' (6 s at most,
-- inside the API's statement timeout), never a raw timeout.
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_i public.dating_introductions;
  v_other text;
  v_mine text;
  v_match uuid;
  v_try integer;
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
                             WHERE a.actor_user_id = v_user AND a.idempotency_key = p_idempotency_key));
      END IF;
      SELECT * INTO v_i FROM public.dating_introductions AS i
       WHERE i.id = p_introduction_id AND v_user IN (i.user_low_id, i.user_high_id)
       FOR UPDATE;
      IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM private.dating_visible_introductions(v_user) AS x WHERE x.id = v_i.id) THEN
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
        RETURN jsonb_build_object('ok', true, 'action', v_mine, 'matched', v_i.state = 'matched');
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
      IF p_action = 'interested' AND v_other = 'interested' THEN
        INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state, matched_at, created_at)
        VALUES (v_i.id, v_i.user_low_id, v_i.user_high_id, 'active', now(), now())
        ON CONFLICT (introduction_id) DO NOTHING
        RETURNING id INTO v_match;
        IF v_match IS NOT NULL THEN
          PERFORM private.bump_metric_internal('dating.mutual');
        END IF;
      END IF;
      RETURN jsonb_build_object('ok', true, 'action', p_action, 'matched', p_action = 'interested' AND v_other IS NOT DISTINCT FROM 'interested');
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- =====================================================================
-- 6. The match moment and the Today notes (§3.4, §3.5, §5.6). The same
--    answer whoever's match it is (no membership oracle).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.mark_dating_match_moment_seen(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  UPDATE public.dating_matches AS m
     SET low_moment_seen_at = CASE WHEN m.user_low_id = v_user THEN coalesce(m.low_moment_seen_at, now()) ELSE m.low_moment_seen_at END,
         high_moment_seen_at = CASE WHEN m.user_high_id = v_user THEN coalesce(m.high_moment_seen_at, now()) ELSE m.high_moment_seen_at END
   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id);
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.dismiss_dating_today_note(p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_note IS NULL OR p_note NOT IN ('family', 'quiet') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;
  INSERT INTO public.dating_settings AS t (user_id, family_asked_at, quiet_note_at)
  VALUES (v_user, CASE WHEN p_note = 'family' THEN now() END, CASE WHEN p_note = 'quiet' THEN now() END)
  ON CONFLICT (user_id) DO UPDATE
    SET family_asked_at = CASE WHEN p_note = 'family' THEN coalesce(t.family_asked_at, now()) ELSE t.family_asked_at END,
        quiet_note_at = CASE WHEN p_note = 'quiet' THEN coalesce(t.quiet_note_at, now()) ELSE t.quiet_note_at END,
        updated_at = now();
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- =====================================================================
-- 7. Photo keys for dating-photo-urls (§4.4, §4.7; carries 12-14), the
--    service role's. The viewer's phone is checked first (the hash the
--    edge function computed from x-attune-device); only viewable photos;
--    for an introduction, only one the viewer can answer now and never
--    while the other person keeps photos for mutual interest; for a
--    match, the other member's while it is active. One answer for every
--    refusal; never a key for anyone else's photo.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.dating_photo_keys_for_viewer(p_viewer uuid, p_kind text, p_id uuid, p_device_hash text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_subject uuid;
  v_keys jsonb;
BEGIN
  IF p_viewer IS NULL OR p_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('introduction', 'match') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'photos_unavailable');
  END IF;
  IF coalesce(private.dating_device_state(p_viewer, p_device_hash) IN ('trusted', 'unbound'), false) IS NOT TRUE
     OR (p_device_hash IS NULL AND EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = p_viewer)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE OR public.dating_flag_enabled('dating_profile_photos') IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'photos_unavailable');
  END IF;
  IF p_kind = 'introduction' THEN
    SELECT CASE WHEN x.user_low_id = p_viewer THEN x.user_high_id ELSE x.user_low_id END INTO v_subject
      FROM private.dating_visible_introductions(p_viewer) AS x
     WHERE x.id = p_id
       AND public.dating_candidate_is_current(p_viewer)
       AND NOT (SELECT p.photos_after_mutual FROM public.dating_profiles AS p
                 WHERE p.user_id = CASE WHEN x.user_low_id = p_viewer THEN x.user_high_id ELSE x.user_low_id END);
  ELSE
    SELECT CASE WHEN m.user_low_id = p_viewer THEN m.user_high_id ELSE m.user_low_id END INTO v_subject
      FROM public.dating_matches AS m
     WHERE m.id = p_id AND m.state = 'active' AND p_viewer IN (m.user_low_id, m.user_high_id)
       AND m.user_low_id IS NOT NULL AND m.user_high_id IS NOT NULL
       AND private.dating_pair_safe(m.user_low_id, m.user_high_id,
             public.dating_phone_hmac_for_user(m.user_low_id), public.dating_phone_hmac_for_user(m.user_high_id));
  END IF;
  IF v_subject IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'photos_unavailable');
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('position', f.position, 'key', f.storage_key) ORDER BY f.position), '[]'::jsonb)
    INTO v_keys
    FROM public.dating_profile_photos AS f
   WHERE f.user_id = v_subject AND private.dating_photo_viewable(f.moderation_state, f.csam_state);
  RETURN jsonb_build_object('ok', true, 'photos', v_keys);
END;
$$;

-- =====================================================================
-- 8. The daily digest (§3.13): at most one a day, at the person's drop
--    time, only if they turned it on, only with new introductions today or
--    a match since the last digest. The neutral me_update push (W3a);
--    quiet hours fold it through the push queue. Hourly at :05.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.send_dating_digests()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
               WHERE CASE WHEN x.user_low_id = r.user_id THEN x.visible_from_low ELSE x.visible_from_high END > now() - interval '24 hours')
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
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-digest') THEN
    PERFORM cron.unschedule('dating-digest');
  END IF;
  PERFORM cron.schedule('dating-digest', '5 * * * *', 'SELECT public.send_dating_digests()');
END $$;

-- =====================================================================
-- 9. Functions re-created from their LIVE bodies (Spec 2 W5b lines only).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.invalidate_dating_on_profile_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'dating_profiles' THEN -- Spec 2 W5b (§3.4): not a filter input, nothing ends
    -- Spec 2 W5b fix round 2 (I-4): every profile column a hard filter reads (place,
    -- Spec 2 W5b intention, children, the states the candidate check reads), and
    -- Spec 2 W5b whether faith shows. The timeline and family feed card reasons only;
    -- Spec 2 W5b the card re-checks those live, so changing them ends nothing.
    IF (OLD.country_code, OLD.region_code, OLD.side_code, OLD.intention, OLD.children_have, OLD.children_want, -- Spec 2 W5b
        OLD.faith_visible, OLD.profile_state, OLD.moderation_state, OLD.verification_state) -- Spec 2 W5b
       IS NOT DISTINCT FROM (NEW.country_code, NEW.region_code, NEW.side_code, NEW.intention, NEW.children_have, -- Spec 2 W5b
        NEW.children_want, NEW.faith_visible, NEW.profile_state, NEW.moderation_state, NEW.verification_state) THEN -- Spec 2 W5b
      RETURN NEW; -- Spec 2 W5b
    END IF; -- Spec 2 W5b
  END IF; -- Spec 2 W5b
  PERFORM public.invalidate_dating_for_user(NEW.user_id,'profile_or_preference_changed');
  RETURN NEW;
END;
$function$;


-- =====================================================================
-- 9b. (Task 4 ruling, §5.2) The filter inputs kept in the sensitive row
--     (who the person is and their pools, who they'd like to meet, faith
--     and how much it matters) end the person's open introductions when
--     they change. Until W5b the identity and faith saves did that through
--     the profile write each makes (any profile write ended them); now that
--     the profile trigger looks only at the profile's own filter columns,
--     the sensitive row needs its own trigger (the same function; its
--     non-profile branch invalidates).
--     The ciphertext changes on every save, so a re-save ends them, as
--     before W5b. Marital status (never a filter) is not watched.
-- =====================================================================
DROP TRIGGER IF EXISTS invalidate_dating_on_sensitive_change ON public.dating_profile_sensitive;
CREATE TRIGGER invalidate_dating_on_sensitive_change
  AFTER UPDATE OF identity_enc, seeking_enc, faith_enc ON public.dating_profile_sensitive
  FOR EACH ROW
  WHEN (OLD.identity_enc IS DISTINCT FROM NEW.identity_enc OR OLD.seeking_enc IS DISTINCT FROM NEW.seeking_enc
        OR OLD.faith_enc IS DISTINCT FROM NEW.faith_enc)
  EXECUTE FUNCTION public.invalidate_dating_on_profile_change();

-- =====================================================================
-- 10. Grants (re-asserted by the twin). The reads, act and the marks are
--     the app's; the photo keys the service role's (dating-photo-urls);
--     the digest is cron's; the helpers are the database's own.
-- =====================================================================
REVOKE ALL ON FUNCTION private.dating_photo_viewable(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_caption_has_contact(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_card(uuid, uuid, public.dating_introductions) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_visible_introductions(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_today() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.act_on_dating_introduction(text, uuid, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.mark_dating_match_moment_seen(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.dismiss_dating_today_note(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_today(), public.get_my_dating_introductions(),
  public.act_on_dating_introduction(text, uuid, text), public.mark_dating_match_moment_seen(uuid),
  public.dismiss_dating_today_note(text) TO authenticated;
REVOKE ALL ON FUNCTION public.dating_photo_keys_for_viewer(uuid, text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dating_photo_keys_for_viewer(uuid, text, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.send_dating_digests() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;

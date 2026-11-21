-- supabase/migrations/20261120100000_dating_v2_chat.sql
-- Spec 2 W6a (§4.9 W6a, §3.6, §4.3, §4.4, §4.5, §6.1, §7.1, §7.5 mutants 10-12;
-- carries 1-7): contact masking (one masker, the card's captions masked
-- instead of dropped); the pair marker (a one-way code for a pair that
-- passed, blocked or ended it, read by generation's never-introduced-before
-- filter, kept 2 years); the dating chat (messages, the chat signals, send,
-- read, the conversations list, swap, block and unmatch with fixed
-- answers); the kill switch reads both members of an open pair (carry 5);
-- act names the match it made (carry 7); open chats and first messages
-- read the messages (carry 6). Dating messages never enter public.messages,
-- relationship_message_counters or the couples safety outbox. No flag
-- changes. Grants: 20261120100010_dating_v2_chat_grants.sql.
-- Final server fix (W6 final server review, 2026-11-21): every closing
-- path seals its 30-day evidence window and names its reason (I-1; a
-- trigger and a CHECK make it structural); the chat needs Dating itself on
-- (I-3); closers lock the match before they bump a chat signal (I-5); the
-- masker's fail-closed fallback masks every word and is counted (I-8); an
-- untrusted phone's withdrawal answers {ok} alone (M-2); a block closes an
-- open match the numbers now block by HMAC (M-3); generation reads the
-- exclusion key once per partition (M-8); the signals' match index (M-9);
-- the kill switch keeps a plain held identity (M-11); a marker's two years
-- run from its latest end (M-13); this migration revokes what it creates
-- (I-2: a split push fails closed).
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Contact masking (§6.1; carry 3). private.dating_mask_contacts(text)
--    is the one masker: dating_messages.body_masked at insert, photo
--    captions on the card. supabase/functions/_shared/dating_mask.ts is its
--    line-by-line TypeScript mirror; both run
--    supabase/tests/fixtures/dating_mask_cases.json (mask_version 1).
--    Each span becomes "•••". The shadow folds each character once:
--    ASCII to lower case, anything else through Spec 1's own forms (I-17:
--    private.normalize_for_filter, then private.match_form while still not
--    ASCII), so there is no fold table here.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_mask_fold(p_c text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
SET search_path = ''
AS $$
DECLARE
  v text;
BEGIN
  IF pg_catalog.ascii(p_c) < 128 THEN
    -- Fix round 1: every control character is a space (the scan's marker,
    -- U+0001, then never occurs in a view).
    RETURN CASE WHEN pg_catalog.ascii(p_c) <= 32 OR pg_catalog.ascii(p_c) = 127 THEN ' ' ELSE pg_catalog.lower(p_c COLLATE "C") END;
  END IF;
  -- Read between two "0"s: a separator stays a space, a removed character
  -- leaves nothing.
  v := private.normalize_for_filter('0' || p_c || '0');
  v := pg_catalog.substr(v, 2, pg_catalog.char_length(v) - 2);
  IF v ~ '[^\u0001-\u007f]' THEN
    v := private.match_form('0' || v || '0');
    v := pg_catalog.substr(v, 2, pg_catalog.char_length(v) - 2);
  END IF;
  RETURN pg_catalog.regexp_replace(pg_catalog.regexp_replace(v, '[\U00010000-\U0010FFFF]', U&'\FFFD', 'g'),
                                   '[\x01-\x1f\x7f]', ' ', 'g'); -- fix round 1
END;
$$;

-- The leetspeak view (one character for one): a digit, @ or $ next to a
-- letter read as that letter; 1 as [p_one] ('i' or 'l'); twice.
CREATE OR REPLACE FUNCTION private.dating_mask_leet(p_s text, p_one text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
SET search_path = ''
AS $$
DECLARE
  v text := p_s;
  r record;
BEGIN
  FOR i IN 1..2 LOOP
    FOR r IN SELECT d, l FROM (VALUES (1, '4', 'a'), (2, '3', 'e'), (3, '0', 'o'), (4, '5', 's'), (5, '7', 't'),
                                      (6, '@', 'a'), (7, '\$', 's'), (8, '1', p_one)) AS t(k, d, l) ORDER BY k LOOP
      v := pg_catalog.regexp_replace(v, '(?<=[a-z])' || r.d || '|' || r.d || '(?=[a-z])', r.l, 'g');
    END LOOP;
  END LOOP;
  RETURN v;
END;
$$;

-- The digits view (one character for one): calendar dates, year ranges and
-- times blanked to x; then o next to a digit as 0, l or i as 1; twice.
CREATE OR REPLACE FUNCTION private.dating_mask_digits(p_s text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
SET search_path = ''
AS $$
DECLARE
  v text := p_s;
  d text;
  a integer;
  m text;
BEGIN
  FOREACH d IN ARRAY ARRAY[
      '(?<![0-9])[0-9]{1,2}[/.-][0-9]{1,2}[/.-](?:[0-9]{4}|[0-9]{2})(?![0-9])',
      '(?<![0-9])[0-9]{4}[/.-][0-9]{1,2}[/.-][0-9]{1,2}(?![0-9])',
      '(?<![0-9])(?:19|20)[0-9]{2} ?[-/] ?(?:(?:19|20)[0-9]{2}|[0-9]{2})(?![0-9])',
      '(?<![0-9])[0-9]{1,2}:[0-5][0-9](?![0-9])',
      -- Fix round 1 (M-2): a date with spaces, a run of years, each with no
      -- other digits beside it.
      '(?<![0-9][^a-z0-9]{0,3})[0-9]{1,2} [0-9]{1,2} (?:19|20)[0-9]{2}(?![^a-z0-9]{0,3}[0-9])',
      '(?<![0-9][^a-z0-9]{0,3})(?:19|20)[0-9]{2}(?:[ ,/&-]{1,3}(?:19|20)[0-9]{2})+(?![^a-z0-9]{0,3}[0-9])'] LOOP
    a := 1;
    LOOP
      a := pg_catalog.regexp_instr(v, d, a);
      EXIT WHEN a = 0;
      m := pg_catalog.regexp_substr(v, d, a);
      v := overlay(v PLACING pg_catalog.repeat('x', pg_catalog.char_length(m)) FROM a FOR pg_catalog.char_length(m));
      a := a + pg_catalog.char_length(m);
    END LOOP;
  END LOOP;
  FOR i IN 1..2 LOOP
    v := pg_catalog.regexp_replace(v, '(?<=[0-9])o|o(?=[0-9])', '0', 'g');
    v := pg_catalog.regexp_replace(v, '(?<=[0-9])[li]|[li](?=[0-9])', '1', 'g');
  END LOOP;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION private.dating_mask_contacts(p_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
SET search_path = ''
AS $$
DECLARE
  v_stop constant text[] := pg_catalog.string_to_array('a about account again also am an and are at banned be blocked but call chat closed dead deleted different dm dms down for from gone handle here i id im in is it its later link locked me my name new no not now number of off ok okay old on or page please pls private public same so that the then there this to too up us user username video was we with yes you your awful bad better fine good great poor really slow soon strong terrible today tomorrow tonight use used using very weak work worked working works worse', ' ');
  v_platform constant text[] := pg_catalog.string_to_array('snapchat telegram whatsapp watsapp instagram facebook onlyfans linkedin youtube cashapp tiktok paypal wechat whtsapp instgrm twitter discord snpcht wassap reddit tlgrm botim viber venmo whtsp fcbk momo kik thegram messenger threads signal insta snap line imo', ' ');
  v_after constant text := '^((?:[ :=@_-]+(?:is|its|id|handle|username|user|name|account|page)(?![a-z0-9]))*[ :=@_-]+(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9]))';
  v_chars text[];
  v_cache jsonb := '{}'::jsonb;
  v_f text;
  v_x text;
  v_s text := '';
  v_chg text := '';
  v_pos integer[] := '{}';
  v_li text;
  v_ll text;
  v_dv text;
  v_view text;
  v_from integer;
  v_a integer;
  v_b integer;
  v_m text;
  v_h text;
  v_g text[];
  v_ok boolean;
  v_end integer;
  v_c text;
  v_n integer;
  v_word boolean;
  v_t text;
  v_r text;
  v_len integer;
  v_sa integer[] := '{}';
  v_sb integer[] := '{}';
  v_out text := '';
  v_i integer := 1;
  v_last_a integer;
  v_last_b integer;
  r record;
  s record;
BEGIN
  IF p_text IS NULL THEN
    RETURN NULL;
  END IF;
  -- 1. The shadow, with each character's place in the text and whether
  --    folding changed it (a character outside ASCII).
  v_chars := pg_catalog.regexp_split_to_array(p_text, '');
  FOR i IN 1..coalesce(pg_catalog.array_length(v_chars, 1), 0) LOOP
    v_f := v_cache ->> v_chars[i];
    IF v_f IS NULL THEN
      v_f := private.dating_mask_fold(v_chars[i]);
      v_cache := v_cache || pg_catalog.jsonb_build_object(v_chars[i], v_f);
    END IF;
    FOREACH v_x IN ARRAY pg_catalog.regexp_split_to_array(v_f, '') LOOP
      CONTINUE WHEN v_x = '';
      v_s := v_s || v_x;
      v_pos := v_pos || i;
      v_chg := v_chg || CASE WHEN pg_catalog.ascii(v_chars[i]) < 128 THEN '0' ELSE '1' END;
    END LOOP;
  END LOOP;
  -- Fix round 1 (M-3): the scan's marker (U+0001) is never in the shadow
  -- (the fold makes every control character a space); were it there, the
  -- scan would misread its matches, so it raises (the insert's wrapper
  -- then masks closed).
  IF pg_catalog.strpos(v_s, E'\x01') > 0 THEN
    RAISE EXCEPTION 'dating_mask_contacts: the scan marker is in the text';
  END IF;
  -- 2. The views.
  v_li := private.dating_mask_leet(v_s, 'i');
  v_ll := private.dating_mask_leet(v_s, 'l');
  v_dv := private.dating_mask_digits(v_s);
  -- 3. The rules, in order; a stop word as the handle rejects a match.
  FOR r IN
    SELECT t.k, t.name, t.view, t.re, t.grp, t.chk FROM (VALUES
      (1, 'strong', 'li', '(?<![a-z0-9])(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik)(?![a-z0-9])(?:[ :=@_-]+(?:is|its|id|handle|username|user|name|account|page)(?![a-z0-9]))*[ :=@_-]+(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, 'names'),
      (2, 'strong', 'll', '(?<![a-z0-9])(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik)(?![a-z0-9])(?:[ :=@_-]+(?:is|its|id|handle|username|user|name|account|page)(?![a-z0-9]))*[ :=@_-]+(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, 'names'),
      (3, 'weak_said', 'li', '(?<![a-z0-9])(?:the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x)(?![a-z0-9])(?: *[:=@] *| +(?:is|id|handle|username) *[:=]? *)(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, NULL),
      (4, 'weak_said', 'll', '(?<![a-z0-9])(?:the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x)(?![a-z0-9])(?: *[:=@] *| +(?:is|id|handle|username) *[:=]? *)(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, NULL),
      (5, 'my_platform', 'li', '(?<![a-z0-9])(?:my|mine|our)(?: +|_)(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik|the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x)(?![a-z0-9])(?:[ _]+(?:handle|id|name|username|account|page)(?![a-z0-9]))?(?:[ _]+is(?![a-z0-9]))?[ :=@_-]+(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, NULL),
      (6, 'weak_handle', 'li', '(?<![a-z0-9])(?:the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x)(?![a-z0-9])[ :=_-]+(@?(?:[a-z0-9_.-]*[0-9_.][a-z0-9_.-]*[a-z0-9_]|[0-9]+))(?![a-z0-9])', 1, NULL),
      (7, 'evasive', 'li', '(?<![a-z0-9])(instagram|messenger|facebook|linkedin|onlyfans|snapchat|telegram|whatsapp|cashapp|discord|instgrm|thegram|threads|twitter|watsapp|whtsapp|youtube|paypal|reddit|signal|snpcht|tiktok|wassap|wechat|botim|insta|tlgrm|venmo|viber|whtsp|fcbk|line|momo|snap|imo|kik)(?![a-z0-9])', NULL, 'evasive'),
      (8, 'evasive', 'll', '(?<![a-z0-9])(instagram|messenger|facebook|linkedin|onlyfans|snapchat|telegram|whatsapp|cashapp|discord|instgrm|thegram|threads|twitter|watsapp|whtsapp|youtube|paypal|reddit|signal|snpcht|tiktok|wassap|wechat|botim|insta|tlgrm|venmo|viber|whtsp|fcbk|line|momo|snap|imo|kik)(?![a-z0-9])', NULL, 'evasive'),
      (9, 'spaced', 'li', '(?<![a-z0-9])[a-z](?:[ ._-][a-z]){2,}(?![a-z0-9])', NULL, 'spaced'),
      (10, 'on_platform', 'li', '(?<![a-z0-9])(@?[a-z0-9_.-]*[0-9_.][a-z0-9_.-]*[a-z0-9_]) +on +(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik|the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x)(?![a-z0-9])', 1, NULL),
      (11, 'on_platform_alone', 'li', '^ *([a-z0-9][a-z0-9_.-]*[a-z0-9_]) +on +(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik|the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x) *[.!]* *$', 1, NULL),
      (12, 'line_id', 'li', '(?<![a-z0-9])line[ _-]?id(?![a-z0-9])[ :=_-]*(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, NULL),
      (13, 'reddit', 's', '(?<![a-z0-9/])u/[a-z0-9_-]+', NULL, NULL),
      (14, 'handle_is', 'li', '(?<![a-z0-9])(?:handle|username|user[ _-]?name|user[ _-]?id)(?: +is)?[ :=@_-]+(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, NULL),
      (15, 'at_handle', 's', '(?<![a-z0-9_.@])@[a-z0-9_]+(?:\.[a-z0-9_]+)*', NULL, NULL),
      (16, 'email', 's', '[a-z0-9._%+-]*[a-z0-9]@ ?[a-z0-9-]+(?:\.[a-z0-9-]+)*', NULL, NULL),
      (17, 'email', 's', '[a-z0-9._%+-]*[a-z0-9] @[a-z0-9-]+(?:\.[a-z0-9-]+)*', NULL, NULL),
      (18, 'email', 's', '(?<![a-z0-9])[a-z0-9._%+-]*[a-z0-9] +@ +(?:protonmail|googlemail|hotmail|outlook|icloud|proton|yahoo|gmail|ymail|aol|gmx)(?![a-z0-9])(?:\.[a-z]+)*', NULL, NULL),
      (19, 'provider', 's', '(?<![a-z0-9])([a-z0-9._-]+) +(?:at +|\(at\) *|\[at\] *)?(?:protonmail|googlemail|hotmail|outlook|icloud|proton|yahoo|gmail|ymail|aol|gmx)(?![a-z0-9])(?: *(?:\.|dot(?![a-z0-9])|\(dot\)) *(?:com|net|co|uk)(?![a-z0-9]))*', 1, NULL),
      (20, 'provider', 's', '(?<![a-z0-9])(?:at +|\(at\) *|\[at\] *)?(?:protonmail|googlemail|hotmail|outlook|icloud|proton|yahoo|gmail|ymail|aol|gmx)(?![a-z0-9])(?: *(?:\.|dot(?![a-z0-9])|\(dot\)) *(?:com|net|co|uk)(?![a-z0-9]))+', NULL, NULL),
      (21, 'spelled_email', 's', '(?<![a-z0-9])[a-z0-9._-]+(?: dot [a-z0-9_-]+)* *(?: at |\(at\)|\[at\]) *[a-z0-9-]+(?: +[a-z0-9-]{2,})? *(?: dot |\(dot\)|\[dot\]| \. ) *(?:info|link|app|biz|com|edu|gov|net|org|xyz|co|gh|io|ly|me|ng|uk)(?![a-z0-9])(?:(?: dot |\.)(?:info|link|app|biz|com|edu|gov|net|org|xyz|co|gh|io|ly|me|ng|uk)(?![a-z0-9]))*', NULL, NULL),
      (22, 'spelled_domain', 's', '(?<![a-z0-9])[a-z0-9-]+ (?:dot|\.) (?:info|link|app|biz|com|edu|gov|net|org|xyz|co|gh|io|ly|me|ng|uk)(?![a-z0-9])(?: (?:dot|\.) (?:info|link|app|biz|com|edu|gov|net|org|xyz|co|gh|io|ly|me|ng|uk)(?![a-z0-9]))*', NULL, NULL),
      (23, 'url', 's', 'https?://[^ ]+|(?<![a-z0-9])www\.[^ ]+', NULL, NULL),
      (24, 'domain', 's', '(?<![a-z0-9])[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.(?:info|link|app|biz|com|edu|gov|net|org|xyz|co|gh|io|ly|me|ng|uk)(?![a-z0-9])(?:/[^ ]*)?', NULL, NULL),
      (25, 'domain_path', 's', '(?<![a-z0-9])[a-z0-9][a-z0-9-]*\.[a-z]{2,}/[^ ]+', NULL, NULL),
      (26, 'cashtag', 's', '(?<![a-z0-9$])\$[a-z][a-z0-9_]*', NULL, NULL),
      (27, 'crypto', 's', '(?<![a-z0-9])(?:0x[0-9a-f]{40}|bc1[0-9a-z]{25,62}|t[1-9a-z]{33})(?![a-z0-9])', NULL, NULL),
      (28, 'phone', 'dv', '(?<![0-9])\+?\(?[0-9](?:[^a-z0-9]{0,3}[0-9]){6,}\)?', NULL, NULL),
      (29, 'number_words', 's', '(?<![a-z0-9])(?:mmiensa|mmienu|nwotwe|triple|double|baako|seven|three|eight|nkron|hwee|enan|enum|four|five|nine|nsia|nson|zero|one|six|two|oh|o|[0-9]+)(?![a-z0-9])(?:[ ,.-]+(?:mmiensa|mmienu|nwotwe|triple|double|baako|seven|three|eight|nkron|hwee|enan|enum|four|five|nine|nsia|nson|zero|one|six|two|oh|o|[0-9]+)(?![a-z0-9]))+', NULL, 'number_words'),
      (30, 'strong_me', 'li', '(?<![a-z0-9])(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik)(?![a-z0-9]) +(?:me|us)(?![a-z0-9])(?: +(?:on|at|via)(?![a-z0-9]))?[ :=@_-]+(@?(?=[a-z0-9_.-]*[a-z])[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, NULL),
      (31, 'strong_me', 'll', '(?<![a-z0-9])(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik)(?![a-z0-9]) +(?:me|us)(?![a-z0-9])(?: +(?:on|at|via)(?![a-z0-9]))?[ :=@_-]+(@?(?=[a-z0-9_.-]*[a-z])[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, NULL),
      (32, 'invite_platform', 'li', '(?<=(?:^|[^a-z0-9])(?:add|find|follow|message|contact|hit|dm|text|ping|reach|inbox|catch)(?: +(?:me|us))?(?: +up)? +(?:on|at|via|in) +)(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik|the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x)(?![a-z0-9])[ :=@_-]+(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, NULL),
      (33, 'invite_platform', 'll', '(?<=(?:^|[^a-z0-9])(?:add|find|follow|message|contact|hit|dm|text|ping|reach|inbox|catch)(?: +(?:me|us))?(?: +up)? +(?:on|at|via|in) +)(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik|the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x)(?![a-z0-9])[ :=@_-]+(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])', 1, NULL),
      (34, 'platform_alone', 'li', '^ *(?:insta|snap|sc|ig|tg|yt)(?![a-z0-9])[ :=_-]+(@?[a-z0-9][a-z0-9_.-]*[a-z0-9_])(?![a-z0-9])(?= *[.!]* *$)', 1, NULL)
    ) AS t(k, name, view, re, grp, chk) ORDER BY t.k
  LOOP
    v_view := CASE r.view WHEN 's' THEN v_s WHEN 'li' THEN v_li WHEN 'll' THEN v_ll ELSE v_dv END;
    v_len := pg_catalog.char_length(v_view);
    v_from := 1;
    LOOP
      -- Fix round 1 (M-3): the first match from v_from, its text and its
      -- handle in one call that stops at that match (regexp_instr and
      -- regexp_substr find every match to the end on each call). The
      -- marker U+0001 is never in a view (the fold makes it a space).
      EXIT WHEN v_from > v_len;
      v_r := pg_catalog.regexp_replace(v_view, r.re,
               E'\x01\\&\x01' || CASE WHEN r.grp IS NULL THEN '' ELSE '\' || r.grp || E'\x01' END, v_from, 1);
      v_a := pg_catalog.strpos(v_r, E'\x01');
      EXIT WHEN v_a = 0;
      v_m := pg_catalog.split_part(v_r, E'\x01', 2);
      v_b := v_a + pg_catalog.char_length(v_m);
      v_ok := pg_catalog.char_length(v_m) > 0;
      IF v_ok AND r.grp IS NOT NULL THEN
        v_h := pg_catalog.ltrim(pg_catalog.split_part(v_r, E'\x01', 3), '@');
        IF v_h = ANY (v_stop) THEN
          v_ok := false;
        END IF;
      END IF;
      IF v_ok AND r.chk = 'evasive' THEN
        v_ok := pg_catalog.substr(v_s, v_a, v_b - v_a) <> pg_catalog.substr(v_view, v_a, v_b - v_a)
             OR pg_catalog.strpos(pg_catalog.substr(v_chg, v_a, v_b - v_a), '1') > 0;
      END IF;
      IF v_ok AND r.chk = 'spaced' THEN
        v_ok := pg_catalog.translate(v_m, ' ._-', '') = ANY (v_platform);
      END IF;
      IF v_ok AND r.chk IN ('evasive', 'spaced') THEN
        -- its handle, if one follows
        v_g := pg_catalog.regexp_match(pg_catalog.substr(v_view, v_b), v_after);
        IF v_g IS NOT NULL AND NOT (pg_catalog.ltrim(v_g[2], '@') = ANY (v_stop)) THEN
          v_b := v_b + pg_catalog.char_length(v_g[1]);
        END IF;
      END IF;
      IF v_ok AND r.chk = 'number_words' THEN
        v_n := 0;
        v_word := false;
        FOREACH v_t IN ARRAY pg_catalog.regexp_split_to_array(v_m, '[ ,.-]+') LOOP
          CONTINUE WHEN v_t = '';
          IF v_t ~ '^[0-9]+$' THEN
            v_n := v_n + pg_catalog.char_length(v_t);
          ELSE
            v_n := v_n + 1;
            v_word := true;
          END IF;
        END LOOP;
        v_ok := v_word AND v_n >= 7;
      END IF;
      IF v_ok AND r.chk = 'names' THEN
        -- "facebook Ama Boateng": up to two more capitalised words
        v_end := v_b;
        FOR j IN 1..2 LOOP
          v_g := pg_catalog.regexp_match(pg_catalog.substr(v_view, v_end), '^( +([a-z][a-z''-]*[a-z])(?![a-z0-9]))');
          EXIT WHEN v_g IS NULL;
          v_c := v_chars[v_pos[v_end + pg_catalog.char_length(v_g[1]) - pg_catalog.char_length(v_g[2])]];
          EXIT WHEN v_c IS NULL OR v_c = pg_catalog.lower(v_c COLLATE "pg_c_utf8") OR v_g[2] = ANY (v_stop);
          v_end := v_end + pg_catalog.char_length(v_g[1]);
        END LOOP;
        v_b := v_end;
      END IF;
      IF v_ok THEN
        v_sa := v_sa || v_pos[v_a];
        -- Fix round 1 (M-6): up to the next folded character, so marks that
        -- fold to nothing (a keycap's U+FE0F U+20E3) go with their digit.
        v_sb := v_sb || greatest(v_pos[v_b - 1] + 1, coalesce(v_pos[v_b], pg_catalog.array_length(v_chars, 1) + 1));
        v_from := v_b;
      ELSE
        v_from := v_a + 1;
      END IF;
    END LOOP;
  END LOOP;
  -- 4. The spans, merged, each "•••".
  FOR s IN SELECT u.a, u.b FROM unnest(v_sa, v_sb) AS u(a, b) ORDER BY u.a, u.b LOOP
    IF v_last_a IS NOT NULL AND s.a <= v_last_b THEN
      v_last_b := greatest(v_last_b, s.b);
    ELSE
      IF v_last_a IS NOT NULL THEN
        v_out := v_out || pg_catalog.array_to_string(v_chars[v_i:v_last_a - 1], '') || '•••';
        v_i := v_last_b;
      END IF;
      v_last_a := s.a;
      v_last_b := s.b;
    END IF;
  END LOOP;
  IF v_last_a IS NOT NULL THEN
    v_out := v_out || pg_catalog.array_to_string(v_chars[v_i:v_last_a - 1], '') || '•••';
    v_i := v_last_b;
  END IF;
  RETURN v_out || coalesce(pg_catalog.array_to_string(v_chars[v_i:pg_catalog.array_length(v_chars, 1)], ''), '');
END;
$$;

-- Final server fix (I-8): the fail-closed fallback masks every run of
-- characters that is not white space. The masker's spans are made of such
-- characters (a handle, a spelled-out email, number words, a spaced-out
-- platform name), so nothing it would mask can pass here; parity on each
-- rule is not attempted, it masks more. Only the line breaks and spaces
-- are left.
CREATE OR REPLACE FUNCTION private.dating_mask_fallback(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT pg_catalog.regexp_replace(p_text, '[^[:space:]]+', '•••', 'g');
$$;

-- Fail closed for presentation (§6.1): if the masker raises, the fallback
-- above; delivery never waits. Pure (no counter): the writers below use
-- dating_mask_counted.
CREATE OR REPLACE FUNCTION private.dating_mask_contacts_safe(p_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
SET search_path = ''
AS $$
BEGIN
  RETURN private.dating_mask_contacts(p_text);
EXCEPTION WHEN OTHERS THEN
  RETURN private.dating_mask_fallback(p_text); -- final server fix (I-8)
END;
$$;

-- Final server fix (I-8): what a message or a caption stores. The masker
-- runs in its own block; if it raises, the fallback is stored and the
-- failure is counted (dating.mask.failed, in health), never silent.
CREATE OR REPLACE FUNCTION private.dating_mask_counted(p_text text)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_text IS NULL THEN
    RETURN NULL;
  END IF;
  BEGIN
    RETURN private.dating_mask_contacts(p_text);
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      PERFORM private.bump_metric_internal('dating.mask.failed');
    EXCEPTION WHEN OTHERS THEN
      NULL; -- the counter never stops the write
    END;
    RETURN private.dating_mask_fallback(p_text);
  END;
END;
$$;

-- Captions only: an invitation to move off the app with nothing to mask
-- ("DM me", "add me on snap"); the card drops such a caption.
CREATE OR REPLACE FUNCTION private.dating_caption_invites(p_text text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
SET search_path = ''
AS $$
DECLARE
  v_s text := '';
  v_li text;
  v_ll text;
  v_c text;
  v_re text;
BEGIN
  IF p_text IS NULL THEN
    RETURN false;
  END IF;
  FOREACH v_c IN ARRAY pg_catalog.regexp_split_to_array(p_text, '') LOOP
    v_s := v_s || private.dating_mask_fold(v_c);
  END LOOP;
  v_li := private.dating_mask_leet(v_s, 'i');
  v_ll := private.dating_mask_leet(v_s, 'l');
  FOREACH v_re IN ARRAY ARRAY[
      '(?<![a-z0-9])(?:add|find|message|contact|hit|dm|text|call|ping|inbox|follow) +(?:me|us)(?![a-z0-9])',
      '(?<![a-z0-9])(?:slide|come) +into +my +dms?(?![a-z0-9])',
      '(?<![a-z0-9])(?:snap[ _-]?chat|tele[ _-]?gram|whats[ _-]?app|wats[ _-]?app|insta[ _-]?gram|face[ _-]?book|only[ _-]?fans|linked[ _-]?in|you[ _-]?tube|cash[ _-]?app|tik[ _-]?tok|pay[ _-]?pal|we[ _-]?chat|whtsapp|instgrm|twitter|discord|snpcht|wassap|reddit|tlgrm|botim|viber|venmo|whtsp|fcbk|momo|kik|the[ _-]?gram|messenger|threads|signal|insta|snap|line|imo|sc|ig|fb|tg|yt|wa|x) +(?:me|us)(?![a-z0-9])',
      '(?<![a-z0-9])of +link(?![a-z0-9])',
      '(?<![a-z0-9])link +in +(?:my +)?bio(?![a-z0-9])'] LOOP
    IF v_li ~ v_re OR v_ll ~ v_re THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. Captions (carry 3, owner 2026-11-20 "Mask contacts on card"): each
--    caption is masked once, when it is written, so the card reads it
--    without masking per view; a caption that only invites someone off
--    the app ("DM me") stays off the card, as one the content filter
--    flags as unkind does.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_profile_photos
  ADD COLUMN IF NOT EXISTS caption_masked text,
  ADD COLUMN IF NOT EXISTS caption_invites boolean;

CREATE OR REPLACE FUNCTION private.dating_photo_caption_mask()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER -- fix round 1 (M-1): any writer, the service role's too, gets a masked caption
SET search_path = ''
AS $$
BEGIN
  NEW.caption_masked := CASE WHEN NEW.caption IS NULL THEN NULL ELSE private.dating_mask_counted(NEW.caption) END; -- final server fix (I-8): counted
  NEW.caption_invites := CASE WHEN NEW.caption IS NULL THEN false ELSE coalesce(private.dating_caption_invites(NEW.caption), true) END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS dating_photo_caption_mask ON public.dating_profile_photos;
CREATE TRIGGER dating_photo_caption_mask
  BEFORE INSERT OR UPDATE OF caption ON public.dating_profile_photos
  FOR EACH ROW EXECUTE FUNCTION private.dating_photo_caption_mask();

-- Every caption there is today (the trigger fires on the caption column).
UPDATE public.dating_profile_photos SET caption = caption WHERE caption IS NOT NULL;

-- ---------------------------------------------------------------------
-- 2b. Carry 5: the identity a person held before a move, encrypted, read
--     only by the kill switch to judge their open pairs (see section 4).
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_profile_sensitive ADD COLUMN IF NOT EXISTS held_identity_enc bytea;

-- ---------------------------------------------------------------------
-- 3. The pair marker (owner decision 2026-11-20, carry 1). When a pair
--    passes ("Not for me"), blocks, unmatches or closes kindly, a one-way
--    code of the two phones' HMACs is kept: no name, no id, no phone, not
--    even which of them acted. It outlives leaving Dating and deleting
--    either account (it is keyed to the numbers, not the accounts), so the
--    pair is never introduced again after one of them leaves and comes
--    back; generation's never-introduced-before filter reads it. Kept 2
--    years (purge_after), then deleted by purge_dating_retention (W6c).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dating_pair_markers (
  pair_code text PRIMARY KEY CONSTRAINT dating_pair_markers_code_check CHECK (pair_code ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  purge_after timestamptz NOT NULL DEFAULT now() + interval '2 years'
);
ALTER TABLE public.dating_pair_markers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS dating_pair_markers_purge_idx ON public.dating_pair_markers (purge_after);

-- The code of the pair with these two phone HMACs: keyed with the
-- exclusion key (an HMAC of the two HMACs in order), so it can be checked
-- only for two numbers already in hand, and never read back as either.
-- NULL without the key or either HMAC (nothing is kept then).
-- Final server fix (M-8): the same code with the key in hand, so
-- generation reads the key once per partition, not once per candidate pair.
CREATE OR REPLACE FUNCTION private.dating_pair_code(p_ha text, p_hb text, p_key text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_ha IS NULL OR p_hb IS NULL OR p_ha = p_hb OR coalesce(p_key, '') = '' THEN
    RETURN NULL;
  END IF;
  RETURN pg_catalog.encode(extensions.hmac('dating_pair_marker|' || least(p_ha, p_hb) || '|' || greatest(p_ha, p_hb),
                                           p_key, 'sha256'), 'hex');
END;
$$;

CREATE OR REPLACE FUNCTION private.dating_pair_code(p_ha text, p_hb text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.dating_pair_code(p_ha, p_hb, public.app_setting('dating_exclusion_key'));
$$;

-- Keeps the marker of the pair [p_a], [p_b]; never raises: a pair it
-- can't code (no key, a member with no phone) is counted, and the caller
-- goes on.
CREATE OR REPLACE FUNCTION private.dating_mark_pair(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code text;
BEGIN
  IF p_a IS NULL OR p_b IS NULL OR p_a = p_b THEN
    RETURN false;
  END IF;
  v_code := private.dating_pair_code(public.dating_phone_hmac_for_user(p_a), public.dating_phone_hmac_for_user(p_b));
  IF v_code IS NULL THEN
    PERFORM private.bump_metric_internal('dating.pair_marker.unwritten');
    RETURN false;
  END IF;
  -- Final server fix (M-13): each later end of the pair keeps the marker
  -- two years from that end, not from the first one.
  INSERT INTO public.dating_pair_markers AS k (pair_code) VALUES (v_code)
  ON CONFLICT (pair_code) DO UPDATE SET purge_after = greatest(k.purge_after, now() + interval '2 years');
  RETURN true;
END;
$$;

-- §5.2 14 v2: never introduced before, and no marker for the pair's
-- numbers (the people's HMACs, as generation holds them).
-- Final server fix (M-8): the same check with the exclusion key in hand
-- (generation reads it once per partition).
CREATE OR REPLACE FUNCTION private.dating_pair_new(p_a uuid, p_b uuid, p_ha text, p_hb text, p_key text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT NOT EXISTS (SELECT 1 FROM public.dating_introductions AS i WHERE i.pair_key = public.dating_pair_key(p_a, p_b))
     AND NOT EXISTS (SELECT 1 FROM public.dating_matches AS m WHERE m.pair_key = public.dating_pair_key(p_a, p_b))
     AND NOT EXISTS (SELECT 1 FROM public.dating_pair_markers AS k WHERE k.pair_code = private.dating_pair_code(p_ha, p_hb, p_key));
$$;

CREATE OR REPLACE FUNCTION private.dating_pair_new(p_a uuid, p_b uuid, p_ha text, p_hb text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.dating_pair_new(p_a, p_b, p_ha, p_hb, public.app_setting('dating_exclusion_key'));
$$;

-- The pairs that already passed, blocked or unmatched (development data;
-- production has none). Only with the key; the markers it kept. A function
-- (fix round 1, M-4) so the contract can run it.
CREATE OR REPLACE FUNCTION private.dating_backfill_pair_markers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_n integer;
BEGIN
  IF coalesce(public.app_setting('dating_exclusion_key'), '') = '' THEN
    RETURN 0;
  END IF;
  INSERT INTO public.dating_pair_markers (pair_code)
  SELECT private.dating_pair_code(public.dating_phone_hmac_for_user(i.user_low_id), public.dating_phone_hmac_for_user(i.user_high_id))
    FROM public.dating_introductions AS i
   WHERE (i.low_action = 'passed' OR i.high_action = 'passed' OR i.state = 'passed')
  UNION
  SELECT private.dating_pair_code(public.dating_phone_hmac_for_user(m.user_low_id), public.dating_phone_hmac_for_user(m.user_high_id))
    FROM public.dating_matches AS m
   WHERE m.state IN ('unmatched', 'blocked')
  UNION
  SELECT private.dating_pair_code(h.blocker_hmac, h.blocked_hmac) FROM public.dating_block_hmacs AS h
  EXCEPT SELECT NULL
  ON CONFLICT (pair_code) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

DO $$
BEGIN
  PERFORM private.dating_backfill_pair_markers();
END $$;

-- ---------------------------------------------------------------------
-- 4. The dating chat (§3.6, §4.3, §4.4, §4.5, §6.1). Its own table, never
--    public.messages (no relationship, no couples trigger, no counter, no
--    couples safety outbox). Text only, 1-1,000 characters. Each message
--    is masked at insert (body_masked, mask_version); a reader gets the
--    masked text until both have swapped (low_swap_at and high_swap_at),
--    then the text as written; nothing lifts the mask by itself. No read
--    receipts, typing or presence: the per-side seen marks below only
--    decide the conversations list's dot for the reader, never what the
--    other person sees.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_matches
  ADD COLUMN IF NOT EXISTS chat_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS low_swap_at timestamptz,
  ADD COLUMN IF NOT EXISTS high_swap_at timestamptz,
  ADD COLUMN IF NOT EXISTS low_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS high_seen_at timestamptz;

-- Final server fix (I-1, §4.8): a match that is not active always has its
-- evidence window. Rows closed before every closer set one get it from
-- their close (most are past it, so the next purge removes them); any
-- writer that leaves it out gets it from this trigger (and 'other' when it
-- names no reason); the CHECK makes it structural.
UPDATE public.dating_matches AS m
   SET evidence_until = coalesce(m.closed_at, now()) + interval '30 days',
       closed_at = coalesce(m.closed_at, now()),
       closed_reason = coalesce(m.closed_reason, 'other')
 WHERE m.state <> 'active' AND m.evidence_until IS NULL;
CREATE OR REPLACE FUNCTION private.dating_matches_seal_window()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.closed_at := coalesce(NEW.closed_at, now());
  NEW.closed_reason := coalesce(NEW.closed_reason, 'other');
  NEW.evidence_until := now() + interval '30 days';
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_matches_seal_window ON public.dating_matches;
CREATE TRIGGER dating_matches_seal_window
  BEFORE INSERT OR UPDATE ON public.dating_matches
  FOR EACH ROW WHEN (NEW.state <> 'active' AND NEW.evidence_until IS NULL)
  EXECUTE FUNCTION private.dating_matches_seal_window();
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_evidence_window_check;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_evidence_window_check
  CHECK (state = 'active' OR evidence_until IS NOT NULL);

CREATE TABLE IF NOT EXISTS public.dating_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  sender_side text NOT NULL CONSTRAINT dating_messages_side_check CHECK (sender_side IN ('low', 'high')),
  sender_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  kind text NOT NULL DEFAULT 'text' CONSTRAINT dating_messages_kind_check CHECK (kind IN ('text', 'guided_answer', 'close_kindly')),
  question_id text CONSTRAINT dating_messages_question_check CHECK (question_id IS NULL OR question_id ~ '^[a-z0-9_]{1,40}$'),
  body text NOT NULL CONSTRAINT dating_messages_body_check CHECK (char_length(body) BETWEEN 1 AND 1000),
  body_masked text NOT NULL,
  mask_version smallint NOT NULL,
  idempotency_key text NOT NULL,
  -- clock time, so messages sent in one transaction keep their order
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT dating_messages_key_unique UNIQUE (match_id, sender_side, idempotency_key)
);
CREATE INDEX IF NOT EXISTS dating_messages_match_idx ON public.dating_messages (match_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS dating_messages_sender_idx ON public.dating_messages (sender_user_id, created_at DESC);
ALTER TABLE public.dating_messages ENABLE ROW LEVEL SECURITY;

-- A recipient's "something changed" bump, read over realtime: the person's
-- own rows only, no content (§4.3). Fix round 1 (I-3): the key is a random
-- id. Realtime does not apply RLS to DELETE events and a DELETE frame
-- carries the primary key (the default replica identity), so the key must
-- not name a person or a match; (user_id, match_id) is unique for the bump.
CREATE TABLE IF NOT EXISTS public.dating_chat_signals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  match_id uuid NOT NULL REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  bumped_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dating_chat_signals_user_match_key UNIQUE (user_id, match_id)
);
ALTER TABLE public.dating_chat_signals ENABLE ROW LEVEL SECURITY;
-- Final server fix (M-9): a match's delete (the purge, an account's
-- deletion) finds its signal rows through an index.
CREATE INDEX IF NOT EXISTS dating_chat_signals_match_idx ON public.dating_chat_signals (match_id);
DROP POLICY IF EXISTS dating_chat_signals_own ON public.dating_chat_signals;
CREATE POLICY dating_chat_signals_own ON public.dating_chat_signals
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables
                      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'dating_chat_signals') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.dating_chat_signals;
  END IF;
END $$;

-- Bumps [p_user]'s signal for [p_match] (never raises; nobody to bump is
-- nothing).
CREATE OR REPLACE FUNCTION private.dating_bump_chat(p_user uuid, p_match uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.dating_chat_signals (user_id, match_id, bumped_at)
  SELECT p_user, p_match, now() WHERE p_user IS NOT NULL AND p_match IS NOT NULL
  ON CONFLICT (user_id, match_id) DO UPDATE SET bumped_at = now();
$$;

-- Final server fix (I-3): the chat runs only while Dating itself is on and
-- the chat's own flag is on. Send and the swap offer read it (answering
-- unavailable); Block, Unmatch, Close kindly, a withdrawal and the reads
-- never do (they reduce exposure or show what is there).
CREATE OR REPLACE FUNCTION private.dating_chat_on()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.dating_flag_enabled('dating_mode_enabled') IS TRUE
     AND public.dating_flag_enabled('dating_match_messaging') IS TRUE;
$$;

-- Fix round 1 (I-1, M-5): is the pair blocked either way, by account or by
-- phone HMAC? The chat's header and list read it, so a block by number
-- alone reads as ended, as the send already answers closed.
CREATE OR REPLACE FUNCTION private.dating_pair_blocked(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_blocks AS k
                  WHERE k.blocker_user_id IN (p_a, p_b) AND k.blocked_user_id IN (p_a, p_b) AND k.blocker_user_id <> k.blocked_user_id)
      OR EXISTS (SELECT 1 FROM public.dating_block_hmacs AS k
                  CROSS JOIN LATERAL (SELECT public.dating_phone_hmac_for_user(p_a) AS ha, public.dating_phone_hmac_for_user(p_b) AS hb) AS y
                  WHERE (k.blocker_hmac, k.blocked_hmac) IN ((y.ha, y.hb), (y.hb, y.ha)));
$$;

-- Fix round 1 (M-1): a body made only of blank or invisible characters
-- (Unicode spaces, zero-width and joiner characters, Hangul fillers, the
-- braille blank, soft hyphen, direction marks, a lone variation selector).
CREATE OR REPLACE FUNCTION private.dating_body_blank(p_text text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT pg_catalog.btrim(p_text, E' \t\n\r\x0b\x0c'
           || U&'\0085\00A0\00AD\034F\115F\1160\1680\180E\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A'
           || U&'\200B\200C\200D\200E\200F\2028\2029\202F\205F\2060\2061\2062\2063\2064\2800\3000\3164\FE0E\FE0F\FEFF\FFA0') = '';
$$;

-- §4.4 chat spec §4.4: may the caller send in [p_match_id] now? A member
-- of an active match with both members, no block either way (by account
-- or by phone HMAC), and no live restriction or hold. Used by
-- send_dating_message and by the INSERT policy below; false for anyone
-- else's match or none (one answer).
CREATE OR REPLACE FUNCTION public.dating_can_send(p_match_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce((
    SELECT m.state = 'active' AND m.user_low_id IS NOT NULL AND m.user_high_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.dating_blocks AS b
                        WHERE (b.blocker_user_id = m.user_low_id AND b.blocked_user_id = m.user_high_id)
                           OR (b.blocker_user_id = m.user_high_id AND b.blocked_user_id = m.user_low_id))
       AND NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs AS h,
                              (SELECT public.dating_phone_hmac_for_user(m.user_low_id) AS lo,
                                      public.dating_phone_hmac_for_user(m.user_high_id) AS hi) AS x
                        WHERE (h.blocker_hmac = x.lo AND h.blocked_hmac = x.hi) OR (h.blocker_hmac = x.hi AND h.blocked_hmac = x.lo))
       AND public.dating_account_in_good_standing(auth.uid())
      FROM public.dating_matches AS m
     WHERE m.id = p_match_id AND auth.uid() IN (m.user_low_id, m.user_high_id)), false);
$$;

-- Defence in depth (§4.5): no API role may insert (the grant is revoked),
-- and were one ever granted, a row must still be the caller's own, in a
-- match they may send in.
DROP POLICY IF EXISTS dating_messages_insert_member ON public.dating_messages;
CREATE POLICY dating_messages_insert_member ON public.dating_messages
  FOR INSERT TO authenticated
  WITH CHECK (sender_user_id = (SELECT auth.uid()) AND public.dating_can_send(match_id));

-- One message as [p_side] reads it: the masked text until both swapped.
CREATE OR REPLACE FUNCTION private.dating_message_json(p_m public.dating_messages, p_side text, p_both boolean)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT pg_catalog.jsonb_build_object('id', p_m.id, 'mine', p_m.sender_side = p_side, 'kind', p_m.kind,
           'question_id', p_m.question_id, 'text', CASE WHEN p_both THEN p_m.body ELSE p_m.body_masked END,
           'at', p_m.created_at);
$$;

-- The idempotency key rule of act v2 and block (16-128, [A-Za-z0-9_:.-]).
CREATE OR REPLACE FUNCTION private.dating_key_ok(p_key text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_key IS NOT NULL AND pg_catalog.char_length(p_key) BETWEEN 16 AND 128 AND p_key ~ '^[A-Za-z0-9_:.-]+$';
$$;

-- §3.6 send. Fixed answers, never a raise but the unsigned caller:
-- {ok, message} | {ok:false, reason: invalid | reverify_device |
-- match_unavailable | closed | restricted | rate_limited | busy}. A replay
-- (the same key in the same match) answers the first message. The match
-- row is locked first (FOR NO KEY UPDATE), so a block, an unmatch or a
-- leave that commits first is seen (the stale-client rule) and a send
-- that commits first is never undone by one. W6a sends text; W6c adds
-- the guided answers and Close kindly.
CREATE OR REPLACE FUNCTION public.send_dating_message(p_idempotency_key text, p_match_id uuid, p_body text,
                                                      p_kind text DEFAULT 'text', p_question_id text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_other uuid;
  v_msg public.dating_messages;
  v_masked text;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key)
     OR p_kind IS DISTINCT FROM 'text' OR p_question_id IS NOT NULL
     OR p_body IS NULL OR pg_catalog.btrim(p_body) = '' OR pg_catalog.char_length(p_body) > 1000 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF private.dating_body_blank(p_body) THEN -- fix round 1 (M-1): only blank or invisible characters
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
       FOR NO KEY UPDATE;
      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      v_other := CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
      -- A replay answers as the first did, whatever happened since.
      SELECT * INTO v_msg FROM public.dating_messages AS d
       WHERE d.match_id = p_match_id AND d.sender_side = v_side AND d.idempotency_key = p_idempotency_key;
      IF FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', true, 'message',
          private.dating_message_json(v_msg, v_side, v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL));
      END IF;
      IF public.dating_flag_enabled('dating_match_messaging') IS NOT TRUE THEN -- fix round 1 (I-2): the chat's flag (§4.10)
        -- Fix round 1b: messages are paused (an incident), the match has not ended.
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
      END IF;
      IF v_m.state <> 'active' OR v_other IS NULL OR public.dating_can_send(p_match_id) IS NOT TRUE THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason',
          CASE WHEN v_m.state = 'active' AND v_other IS NOT NULL AND public.dating_account_in_good_standing(v_user) IS NOT TRUE
               THEN 'restricted' ELSE 'closed' END);
      END IF;
      BEGIN
        PERFORM public.check_dating_rate_limit('dating_message', 500, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      v_masked := private.dating_mask_contacts_safe(p_body);
      INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, kind, question_id, body, body_masked,
                                          mask_version, idempotency_key)
      VALUES (p_match_id, v_side, v_user, 'text', NULL, p_body, v_masked, 1, p_idempotency_key)
      RETURNING * INTO v_msg;
      UPDATE public.dating_matches AS m
         SET chat_started_at = coalesce(m.chat_started_at, now()),
             low_seen_at = CASE WHEN v_side = 'low' THEN clock_timestamp() ELSE m.low_seen_at END,
             high_seen_at = CASE WHEN v_side = 'high' THEN clock_timestamp() ELSE m.high_seen_at END
       WHERE m.id = p_match_id;
      PERFORM private.dating_bump_chat(v_other, p_match_id);
      IF v_masked IS DISTINCT FROM p_body THEN
        PERFORM private.bump_metric_internal('dating.mask_hit');
      END IF;
      RETURN pg_catalog.jsonb_build_object('ok', true, 'message',
        private.dating_message_json(v_msg, v_side, v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL));
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- The chat's header as [p_side] sees it.
CREATE OR REPLACE FUNCTION private.dating_chat_header(p_m public.dating_matches, p_side text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_other constant uuid := CASE WHEN p_side = 'low' THEN p_m.user_high_id ELSE p_m.user_low_id END;
  v_mine constant timestamptz := CASE WHEN p_side = 'low' THEN p_m.low_swap_at ELSE p_m.high_swap_at END;
  v_theirs constant timestamptz := CASE WHEN p_side = 'low' THEN p_m.high_swap_at ELSE p_m.low_swap_at END;
BEGIN
  RETURN pg_catalog.jsonb_build_object(
    'match_id', p_m.id,
    'display_name', (SELECT p.display_name FROM public.dating_profiles AS p WHERE p.user_id = v_other),
    'age', CASE WHEN v_other IS NULL THEN NULL ELSE public.account_age(v_other) END,
    'state', CASE WHEN p_m.state = 'active' AND v_other IS NOT NULL
                       AND NOT private.dating_pair_blocked(p_m.user_low_id, p_m.user_high_id) THEN 'active' ELSE 'ended' END, -- fix round 1 (M-5)
    'swap', pg_catalog.jsonb_build_object('mine', v_mine IS NOT NULL, 'theirs', v_theirs IS NOT NULL,
                                          'both', v_mine IS NOT NULL AND v_theirs IS NOT NULL,
                                          'from', p_m.matched_at + interval '72 hours'));
END;
$$;

-- §3.6 read: the newest [p_limit] (1-100, default 50) messages before
-- [p_before] (none: the newest), newest first, and the header; the
-- caller's own matches only, an ended one for its 30-day evidence window
-- (read-only). Reading the newest page marks the conversation seen for
-- the list's dot. VOLATILE: it writes the mark and the phone's last use,
-- and PostgREST runs a STABLE RPC read-only (W5 final I-1).
CREATE OR REPLACE FUNCTION public.get_dating_messages(p_match_id uuid, p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_both boolean;
  v_limit integer;
  v_rows jsonb;
  v_more boolean;
  v_seen timestamptz;
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
  v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
  v_both := v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL;
  SELECT coalesce(pg_catalog.jsonb_agg(private.dating_message_json(x, v_side, v_both) ORDER BY x.created_at DESC, x.id DESC), '[]'::jsonb),
         count(*) > v_limit
    INTO v_rows, v_more
    FROM (SELECT d.* FROM public.dating_messages AS d
           WHERE d.match_id = p_match_id AND (p_before IS NULL OR d.created_at < p_before)
           ORDER BY d.created_at DESC, d.id DESC
           LIMIT v_limit + 1) AS x;
  IF v_more THEN
    v_rows := v_rows - v_limit;
  END IF;
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
$$;

-- §3.5 the conversations list: the caller's active matches (newest
-- activity first) with the other person's first name and age, the last
-- message as the caller reads it, and a dot (never a count) for
-- something new; with [p_include_ended], the matches that ended in the
-- last 30 days (their evidence window). VOLATILE (the phone's last use).
CREATE OR REPLACE FUNCTION public.get_my_dating_matches(p_include_ended boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_rows jsonb;
  v_ended jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
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
                                     AND d.created_at > coalesce(s.seen, '-infinity'))) AS row
            FROM public.dating_matches AS m
           CROSS JOIN LATERAL (SELECT CASE WHEN m.user_low_id = v_user THEN 'low' ELSE 'high' END AS side,
                                      CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END AS other,
                                      CASE WHEN m.user_low_id = v_user THEN m.low_seen_at ELSE m.high_seen_at END AS seen) AS s
            LEFT JOIN LATERAL (SELECT d.* FROM public.dating_messages AS d WHERE d.match_id = m.id
                                ORDER BY d.created_at DESC, d.id DESC LIMIT 1) AS l ON true
           WHERE v_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active' AND s.other IS NOT NULL
             AND NOT private.dating_pair_blocked(m.user_low_id, m.user_high_id)) AS c; -- fix round 1 (M-5)
  IF coalesce(p_include_ended, false) THEN
    SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'match_id', m.id,
             'display_name', (SELECT p.display_name FROM public.dating_profiles AS p
                               WHERE p.user_id = CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END),
             'ended_at', coalesce(m.closed_at, m.matched_at)) ORDER BY coalesce(m.closed_at, m.matched_at) DESC, m.id), '[]'::jsonb)
      INTO v_ended
      FROM public.dating_matches AS m
     WHERE v_user IN (m.user_low_id, m.user_high_id)
       AND (m.state <> 'active' OR m.user_low_id IS NULL OR m.user_high_id IS NULL)
       AND m.evidence_until > now();
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'conversations', v_rows)
      || CASE WHEN coalesce(p_include_ended, false) THEN pg_catalog.jsonb_build_object('ended', v_ended) ELSE '{}'::jsonb END;
END;
$$;

-- §3.6, §6.1 swap. Offered from 72 hours after the match; either may
-- withdraw an offer until both have swapped; after both, it can't be
-- undone. Both answer {ok, swap:{mine, theirs, both}} | {ok:false,
-- reason: invalid | reverify_device | match_unavailable | closed |
-- too_early (with from) | already_swapped | busy}.
CREATE OR REPLACE FUNCTION private.dating_swap_write(p_match_id uuid, p_offer boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_mine timestamptz;
  v_theirs timestamptz;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF p_offer AND public.dating_require_trusted_device() IS NOT TRUE THEN -- fix round 1 (M-10): withdraw only reduces exposure
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
       FOR NO KEY UPDATE;
      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      v_mine := CASE WHEN v_side = 'low' THEN v_m.low_swap_at ELSE v_m.high_swap_at END;
      v_theirs := CASE WHEN v_side = 'low' THEN v_m.high_swap_at ELSE v_m.low_swap_at END;
      IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
      END IF;
      IF p_offer AND private.dating_chat_on() IS NOT TRUE THEN -- fix round 1 (I-2); final server fix (I-3): Dating itself too
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable'); -- fix round 1b: paused, not ended
      END IF;
      -- Fix round 1 (I-1): an offer needs what a send needs (no block either
      -- way, the offerer in good standing; §6.3), with send's answers.
      IF p_offer AND public.dating_can_send(p_match_id) IS NOT TRUE THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason',
          CASE WHEN public.dating_account_in_good_standing(v_user) IS NOT TRUE THEN 'restricted' ELSE 'closed' END);
      END IF;
      IF p_offer AND now() < v_m.matched_at + interval '72 hours' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'too_early', 'from', v_m.matched_at + interval '72 hours');
      END IF;
      IF NOT p_offer AND v_mine IS NOT NULL AND v_theirs IS NOT NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_swapped');
      END IF;
      v_mine := CASE WHEN p_offer THEN coalesce(v_mine, now()) ELSE NULL END;
      UPDATE public.dating_matches AS m
         SET low_swap_at = CASE WHEN v_side = 'low' THEN v_mine ELSE m.low_swap_at END,
             high_swap_at = CASE WHEN v_side = 'high' THEN v_mine ELSE m.high_swap_at END
       WHERE m.id = p_match_id;
      PERFORM private.dating_bump_chat(CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END, p_match_id);
      IF p_offer AND v_theirs IS NOT NULL
         AND (CASE WHEN v_side = 'low' THEN v_m.low_swap_at ELSE v_m.high_swap_at END) IS NULL THEN
        PERFORM private.bump_metric_internal('dating.swap');
      END IF;
      RETURN pg_catalog.jsonb_build_object('ok', true, 'swap', pg_catalog.jsonb_build_object(
        'mine', v_mine IS NOT NULL, 'theirs', v_theirs IS NOT NULL, 'both', v_mine IS NOT NULL AND v_theirs IS NOT NULL));
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

CREATE OR REPLACE FUNCTION public.offer_dating_contact_swap(p_match_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.dating_swap_write(p_match_id, true);
$$;

-- Final server fix (M-2): a withdrawal from a phone that is not the
-- person's trusted one still withdraws (it reduces exposure) but answers
-- {ok} alone: no swap state, no ended match, no "both swapped" reaches a
-- phone the person has not verified. Its refusals that name nothing about
-- the match (invalid, match_unavailable, busy) stay.
CREATE OR REPLACE FUNCTION public.withdraw_dating_contact_swap(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v jsonb;
BEGIN
  v := private.dating_swap_write(p_match_id, false);
  IF public.dating_require_trusted_device() IS NOT TRUE
     AND coalesce(v ->> 'reason', '') NOT IN ('invalid', 'match_unavailable', 'busy') THEN
    RETURN pg_catalog.jsonb_build_object('ok', true);
  END IF;
  RETURN v;
END;
$$;

-- §3.6 Block and Unmatch from the chat (carry 4: fixed answers, never a
-- raise but the unsigned caller; the lock order of exit and of the card's
-- Block: the setup lock, then the match row, then its introduction's).
-- Whole replacements: both returned void and raised before. Neither is
-- gated by the phone or by eligibility (they reduce exposure; Ruling
-- R-36); a member of the match only. {ok} | {ok:false, reason: invalid |
-- match_unavailable | rate_limited | busy}.
DROP FUNCTION IF EXISTS public.block_dating_match(text, uuid);
CREATE FUNCTION public.block_dating_match(p_idempotency_key text, p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_other uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'block_dating_match' AND k.idempotency_key = p_idempotency_key) THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
       FOR UPDATE;
      v_other := CASE WHEN v_m.user_low_id = v_user THEN v_m.user_high_id ELSE v_m.user_low_id END;
      IF NOT FOUND OR v_other IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      PERFORM 1 FROM public.dating_introductions AS i WHERE i.id = v_m.introduction_id FOR UPDATE;
      BEGIN
        PERFORM public.check_dating_rate_limit('block', 20, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      PERFORM public.claim_dating_idempotency('block_dating_match', p_idempotency_key);
      PERFORM public.block_dating_user(p_idempotency_key, v_other);
      PERFORM private.bump_metric_internal('dating.block');
      RETURN pg_catalog.jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

DROP FUNCTION IF EXISTS public.unmatch_dating_match(text, uuid);
CREATE FUNCTION public.unmatch_dating_match(p_idempotency_key text, p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_other uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'unmatch_dating_match' AND k.idempotency_key = p_idempotency_key) THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
       FOR UPDATE;
      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      v_other := CASE WHEN v_m.user_low_id = v_user THEN v_m.user_high_id ELSE v_m.user_low_id END;
      PERFORM 1 FROM public.dating_introductions AS i WHERE i.id = v_m.introduction_id FOR UPDATE;
      PERFORM public.claim_dating_idempotency('unmatch_dating_match', p_idempotency_key);
      -- §3.6: "You won't be introduced again." Kept whoever ended the match
      -- first (fix round 1, M-6); a second marker is never written.
      PERFORM private.dating_mark_pair(v_m.user_low_id, v_m.user_high_id);
      -- Already ended (by either side or anything else): nothing more to do.
      IF v_m.state = 'active' THEN
        UPDATE public.dating_matches AS m
           SET state = 'unmatched', closed_reason = 'unmatched', closed_at = coalesce(m.closed_at, now()),
               evidence_until = now() + interval '30 days'
         WHERE m.id = p_match_id;
        PERFORM private.dating_bump_chat(v_other, p_match_id);
        PERFORM private.bump_metric_internal('dating.unmatch');
      END IF;
      RETURN pg_catalog.jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Functions re-created from their live bodies; only the lines marked
--    "-- Spec 2 W6a" change.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.dating_card(p_viewer uuid, p_subject uuid, p_intro dating_introductions)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
             -- Spec 2 W6a (carry 3): masked once when written, never dropped for a contact detail
             'caption', CASE WHEN private.content_filter_verdict(f.caption, ARRAY['slur', 'explicit']) IS NULL -- Spec 2 W6a
                              AND f.caption_invites IS FALSE THEN f.caption_masked END) -- Spec 2 W6a
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
$function$;

CREATE OR REPLACE FUNCTION public.dating_pair_passes_hard_filters(p_a uuid, p_b uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_at constant timestamptz := now();
  v_a private.dating_gen_person;
  v_b private.dating_gen_person;
BEGIN
  IF p_a IS NULL OR p_b IS NULL OR p_a = p_b OR v_cfg IS NULL THEN
    RETURN false;
  END IF;
  -- 1, 15 (W5c adds the moderation removal to the person check).
  IF private.dating_person_current(p_a, v_at, v_cfg) IS NOT TRUE
     OR private.dating_person_current(p_b, v_at, v_cfg) IS NOT TRUE THEN
    RETURN false;
  END IF;
  v_a := private.dating_person(p_a, v_at, v_cfg);
  v_b := private.dating_person(p_b, v_at, v_cfg);
  RETURN coalesce(private.dating_admits(v_a, v_b, v_cfg)
                  AND private.dating_pair_safe(p_a, p_b, v_a.hmac, v_b.hmac)
                  AND private.dating_pair_new(p_a, p_b, v_a.hmac, v_b.hmac), false); -- Spec 2 W6a (carry 1): the pair marker
EXCEPTION WHEN raise_exception THEN
  -- An unreadable answer or a missing field key admits nobody.
  IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    RETURN false;
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_generate_partition(p_country text, p_region text, p_key text, p_window date, p_now timestamp with time zone, p_version text, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_seed constant text := encode(extensions.digest(p_version || p_window::text || p_key, 'sha256'), 'hex');
  v_max constant integer := coalesce((p_cfg ->> 'max_attempts')::int, 3);
  v_people_max constant integer := (p_cfg ->> 'partition_people_max')::int;
  v_scan constant integer := (p_cfg ->> 'scan_limit')::int;
  v_fw constant numeric := coalesce((p_cfg #>> '{rank,feasibility_weight}')::numeric, 10);
  v_vw constant numeric := coalesce((p_cfg #>> '{rank,values_weight}')::numeric, 3);
  v_band constant numeric := coalesce((p_cfg #>> '{rank,band_width}')::numeric, 3);
  v_jit constant numeric := coalesce((p_cfg #>> '{rank,jitter}')::numeric, 2.0);
  v_window constant interval := make_interval(days => coalesce((p_cfg #>> '{rank,exposure_window_days}')::int, 7));
  v_life constant interval := make_interval(days => (p_cfg ->> 'lifetime_days')::int);
  v_run public.dating_generation_runs;
  v_u record;
  v_c record;
  v_cap integer;
  v_id uuid;
  v_seq integer := 0;
  v_state text;
  v_person private.dating_gen_person;
  v_n_home integer := 0; -- fix round 1 (I-2): current people loaded, per group
  v_n_abroad integer := 0;
  v_truncated boolean := false;
  v_n integer; -- fix round 1 (M-6): rows locked
  v_lock text;
  v_xkey constant text := public.app_setting('dating_exclusion_key'); -- Spec 2 W6a (final server fix, M-8): read once per partition
BEGIN
  INSERT INTO public.dating_generation_runs AS r
    (algorithm_version, cohort_window, state, seed, partition_key, attempts, started_at)
  VALUES (p_version, p_window::text, 'processing', v_seed, p_key, 1, now())
  ON CONFLICT (algorithm_version, cohort_window, partition_key) DO UPDATE
    SET state = 'processing', attempts = r.attempts + 1, started_at = now(), last_error_code = NULL
    WHERE r.state IN ('pending', 'failed') AND r.attempts < v_max
  RETURNING * INTO v_run;
  -- No row: completed, being run, or out of attempts. Never ours (§5.7).
  IF v_run.id IS NULL THEN
    RETURN jsonb_build_object('partition', p_key, 'skipped', 'partition_unavailable');
  END IF;

  BEGIN
    DROP TABLE IF EXISTS pg_temp.dating_gen_people;
    CREATE TEMP TABLE dating_gen_people (
      user_id uuid PRIMARY KEY,
      p private.dating_gen_person NOT NULL,
      home boolean NOT NULL,
      exposure integer NOT NULL,
      capacity integer NOT NULL
    ) ON COMMIT DROP;
    -- The partition's own people, then those elsewhere open to it (§5.5).
    -- Fix round 1 (I-2): each group's bound (partition_people_max) counts
    -- current candidates only, and who falls past it rotates with the
    -- cohort's seed, never the same people every day; a run that leaves
    -- anyone out is counted (dating.generation.truncated.<country>).
    FOR v_u IN
      SELECT x.user_id, x.home
        FROM (SELECT p.user_id, true AS home
                FROM public.dating_profiles AS p
                JOIN public.dating_enrollments AS e ON e.user_id = p.user_id AND e.state = 'active'
               WHERE p.country_code::text = p_country AND (p_region IS NULL OR p.region_code = p_region)
              UNION ALL
              SELECT d.user_id, false
                FROM public.dating_preferences AS d
                JOIN public.dating_profiles AS p ON p.user_id = d.user_id
                JOIN public.dating_enrollments AS e ON e.user_id = d.user_id AND e.state = 'active'
               WHERE p_country = ANY (d.open_abroad::text[]) AND p.country_code::text IS DISTINCT FROM p_country) AS x
       ORDER BY x.home DESC, md5(v_seed || x.user_id::text), x.user_id
    LOOP
      BEGIN
        CONTINUE WHEN private.dating_person_current(v_u.user_id, p_now, p_cfg) IS NOT TRUE;
        IF (v_u.home AND v_n_home >= v_people_max) OR (NOT v_u.home AND v_n_abroad >= v_people_max) THEN
          v_truncated := true;
          CONTINUE;
        END IF;
        v_person := private.dating_person(v_u.user_id, p_now, p_cfg);
        CONTINUE WHEN v_person IS NULL;
        INSERT INTO pg_temp.dating_gen_people (user_id, p, home, exposure, capacity)
        VALUES (v_u.user_id, v_person, v_u.home,
                (SELECT count(*)::int FROM public.dating_introductions AS i
                  WHERE v_u.user_id IN (i.user_low_id, i.user_high_id)
                    AND i.created_at > p_now - v_window AND i.created_at <= p_now),
                private.dating_capacity(v_u.user_id, p_now, p_cfg));
        IF v_u.home THEN
          v_n_home := v_n_home + 1;
        ELSE
          v_n_abroad := v_n_abroad + 1;
        END IF;
      EXCEPTION WHEN raise_exception THEN
        IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
          PERFORM private.bump_metric_internal('dating.generation.unreadable');
        ELSE
          RAISE;
        END IF;
      END;
    END LOOP;
    IF v_truncated THEN
      PERFORM private.bump_metric_internal('dating.generation.truncated.' || lower(p_country));
    END IF;

    -- §5.4 1: fewest introductions in 7 days first, ties by the seed.
    FOR v_u IN
      SELECT g.user_id, g.p FROM pg_temp.dating_gen_people AS g
       WHERE g.home
       ORDER BY g.exposure, md5(v_seed || g.user_id::text), g.user_id
    LOOP
      SELECT g.capacity INTO v_cap FROM pg_temp.dating_gen_people AS g WHERE g.user_id = v_u.user_id;
      CONTINUE WHEN v_cap <= 0;
      FOR v_c IN
        WITH scanned AS MATERIALIZED (
          -- §5.5: at most scan_limit candidates looked at per person.
          SELECT g.user_id, g.p, g.exposure FROM pg_temp.dating_gen_people AS g
           WHERE g.user_id <> v_u.user_id AND g.capacity > 0
             AND (g.p).age BETWEEN (v_u.p).min_age AND (v_u.p).max_age
             AND (v_u.p).age BETWEEN (g.p).min_age AND (g.p).max_age
           ORDER BY g.exposure, md5(v_seed || g.user_id::text), g.user_id
           LIMIT v_scan
        ), admitted AS MATERIALIZED (
          SELECT s.* FROM scanned AS s WHERE private.dating_admits(v_u.p, s.p, p_cfg)
        ), passing AS (
          SELECT a.user_id, a.p, a.exposure,
                 -- §5.4 3: feasibility 0-3
                 (CASE WHEN (v_u.p).intention = (a.p).intention THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).children_want = (a.p).children_want AND (a.p).children_want IN ('yes', 'no') THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).country = (a.p).country AND (v_u.p).region = (a.p).region
                          AND ((v_u.p).side IS NULL OR (a.p).side IS NULL OR (v_u.p).side = (a.p).side) THEN 1 ELSE 0 END) AS f,
                 -- §5.4 4: stated values 0-4
                 (CASE WHEN (v_u.p).intention = 'marriage' AND (a.p).intention = 'marriage'
                         AND (v_u.p).timeline = (a.p).timeline THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).importance = (a.p).importance THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).faith = (a.p).faith AND (a.p).faith <> 'prefer_not_to_say' THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).family = (a.p).family THEN 1 ELSE 0 END) AS v,
                 -- §5.4 7: (first 3 bytes of md5(seed || U || c)) mod 1000 / 1000 x 2.0
                 ((('x' || substr(md5(v_seed || v_u.user_id::text || a.user_id::text), 1, 6))::bit(24)::int % 1000)::numeric
                   / 1000 * v_jit) AS jitter
            FROM admitted AS a
           WHERE private.dating_pair_safe(v_u.user_id, a.user_id, (v_u.p).hmac, (a.p).hmac)
             AND private.dating_pair_new(v_u.user_id, a.user_id, (v_u.p).hmac, (a.p).hmac, v_xkey) -- Spec 2 W6a (carry 1; final server fix, M-8: the key read once)
        ), banded AS (
          SELECT x.*, v_fw * x.f + v_vw * x.v AS base, max(v_fw * x.f + v_vw * x.v) OVER () AS best FROM passing AS x
        )
        SELECT b.user_id, b.p, b.f, b.v, b.exposure, b.jitter FROM banded AS b
         WHERE b.base >= b.best - v_band
         ORDER BY b.exposure + b.jitter, md5(v_seed || b.user_id::text), b.user_id
      LOOP
        EXIT WHEN v_cap <= 0;
        CONTINUE WHEN (SELECT g.capacity FROM pg_temp.dating_gen_people AS g WHERE g.user_id = v_c.user_id) <= 0;
        -- Fix round 2 (N-1): both still enrolled at this statement, a plain
        -- re-check. The run never locks an enrolment, so no leave, pause,
        -- resume or switch ever waits on it; the close below and the hourly
        -- sweep (expire_dating_introductions) take what a leave commits
        -- while the run is open. The two users' rows are taken KEY SHARE
        -- SKIP LOCKED, lowest id first: the introduction's own foreign-key
        -- lock, taken without waiting on a deletion in progress (busy:
        -- tried three times, then skipped and counted).
        v_lock := 'gone';
        FOR v_try IN 1..3 LOOP
          v_lock := 'gone';
          EXIT WHEN (SELECT count(*) FROM public.dating_enrollments AS e
                      WHERE e.user_id IN (v_u.user_id, v_c.user_id) AND e.state = 'active') <> 2;
          SELECT count(*) INTO v_n FROM (SELECT 1 FROM public.users AS u WHERE u.id IN (v_u.user_id, v_c.user_id)
                                          ORDER BY u.id FOR KEY SHARE SKIP LOCKED) AS l;
          v_lock := CASE WHEN v_n = 2 THEN 'held' ELSE 'busy' END;
          EXIT WHEN v_lock = 'held' OR v_try = 3;
          PERFORM pg_catalog.pg_sleep(0.05);
        END LOOP;
        IF v_lock = 'busy' THEN
          PERFORM private.bump_metric_internal('dating.generation.busy');
        END IF;
        CONTINUE WHEN v_lock IS DISTINCT FROM 'held';
        v_id := NULL;
        INSERT INTO public.dating_introductions AS i
          (pair_key, user_low_id, user_high_id, state, algorithm_version, cohort_window, partition_key,
           visible_from_low, visible_from_high, expires_at, reasons, rank_detail, created_at)
        SELECT public.dating_pair_key(v_u.user_id, v_c.user_id), least(v_u.user_id, v_c.user_id), greatest(v_u.user_id, v_c.user_id),
               'generated', p_version, p_window, p_key,
               CASE WHEN v_u.user_id < v_c.user_id THEN (v_u.p).visible_from ELSE (v_c.p).visible_from END,
               CASE WHEN v_u.user_id < v_c.user_id THEN (v_c.p).visible_from ELSE (v_u.p).visible_from END,
               greatest((v_u.p).visible_from, (v_c.p).visible_from) + v_life,
               private.dating_reasons(v_u.p, v_c.p),
               jsonb_build_object('f', v_c.f, 'v', v_c.v, 'exposure', v_c.exposure, 'jitter', round(v_c.jitter, 3), 'seq', v_seq + 1),
               p_now
        ON CONFLICT (pair_key) DO NOTHING
        RETURNING i.id INTO v_id;
        CONTINUE WHEN v_id IS NULL;
        v_seq := v_seq + 1;
        v_cap := v_cap - 1;
        UPDATE pg_temp.dating_gen_people AS g SET capacity = g.capacity - 1 WHERE g.user_id IN (v_u.user_id, v_c.user_id);
        -- §5.4 8: the candidate's exposure rises for the rest of the run.
        UPDATE pg_temp.dating_gen_people AS g SET exposure = g.exposure + 1 WHERE g.user_id = v_c.user_id;
      END LOOP;
    END LOOP;

    -- Spec 2 W5 final (M-2): a filter answer changed while the run was open
    -- Spec 2 W5 final (who to meet, the age range, the scope: any of filters
    -- Spec 2 W5 final 2-10) is read again here, and this run's introductions
    -- Spec 2 W5 final the answers now refuse go before they publish. Each
    -- Spec 2 W5 final introduced person is read once (never more than the
    -- Spec 2 W5 final people loaded above), each pair checked by the pure
    -- Spec 2 W5 final filter; an unreadable person fails the partition (retried).
    WITH m AS MATERIALIZED ( -- Spec 2 W5 final (M-2)
      SELECT x.id, private.dating_person(x.id, p_now, p_cfg) AS p -- Spec 2 W5 final (M-2)
        FROM (SELECT DISTINCT u.id FROM public.dating_introductions AS i, -- Spec 2 W5 final (M-2)
                     unnest(ARRAY[i.user_low_id, i.user_high_id]) AS u(id) -- Spec 2 W5 final (M-2)
               WHERE i.created_at = p_now AND i.partition_key = p_key) AS x) -- Spec 2 W5 final (M-2)
    DELETE FROM public.dating_introductions AS i USING m AS a, m AS b -- Spec 2 W5 final (M-2)
     WHERE i.created_at = p_now AND i.partition_key = p_key -- Spec 2 W5 final (M-2)
       AND a.id = i.user_low_id AND b.id = i.user_high_id -- Spec 2 W5 final (M-2)
       AND private.dating_admits(a.p, b.p, p_cfg) IS NOT TRUE; -- Spec 2 W5 final (M-2)
    GET DIAGNOSTICS v_n = ROW_COUNT; -- Spec 2 W5 final (M-2)
    v_seq := v_seq - v_n; -- Spec 2 W5 final (M-2)
    -- Fix round 2 (N-1, N-4): the close. Anyone no longer active by now (a
    -- leave or a pause that committed while the run was open) loses this
    -- run's introductions; what a leave commits after this, the hourly
    -- sweep takes.
    DELETE FROM public.dating_introductions AS i
     WHERE i.created_at = p_now AND i.partition_key = p_key
       AND EXISTS (SELECT 1 FROM unnest(ARRAY[i.user_low_id, i.user_high_id]) AS u(id)
                    WHERE NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = u.id AND e.state = 'active'));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_seq := v_seq - v_n;

    -- §5.6, §6.9: an empty day per person and region; deliveries per country.
    PERFORM private.bump_metric_internal('dating.empty_day.' || lower(p_country) || '.' || lower(coalesce((g.p).region, 'none')))
       FROM pg_temp.dating_gen_people AS g
      WHERE g.home AND NOT EXISTS (SELECT 1 FROM public.dating_introductions AS i
                                    WHERE g.user_id IN (i.user_low_id, i.user_high_id) AND i.created_at = p_now);
    IF v_seq > 0 THEN
      PERFORM private.bump_metric_internal('dating.intros_delivered.' || lower(p_country)) FROM generate_series(1, v_seq);
    END IF;
    UPDATE public.dating_generation_runs SET state = 'completed', completed_at = now() WHERE id = v_run.id;
  EXCEPTION
  -- Fix round 1 (I-1): a statement timeout or a cancel (57014, which OTHERS
  -- never catches) fails this partition only, as any error does; the tick
  -- then starts nothing more, and what it finished stays.
  WHEN query_canceled THEN
    UPDATE public.dating_generation_runs AS r
       SET state = CASE WHEN r.attempts >= v_max THEN 'dead_letter' ELSE 'failed' END,
           last_error_code = '57014', completed_at = now()
     WHERE r.id = v_run.id;
    PERFORM private.bump_metric_internal('dating.generation.failed');
    RETURN jsonb_build_object('partition', p_key, 'error', '57014');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    UPDATE public.dating_generation_runs
       SET state = CASE WHEN attempts >= v_max THEN 'dead_letter' ELSE 'failed' END,
           last_error_code = v_state, completed_at = now()
     WHERE id = v_run.id;
    PERFORM private.bump_metric_internal('dating.generation.failed');
    RETURN jsonb_build_object('partition', p_key, 'error', v_state);
  END;
  RETURN jsonb_build_object('partition', p_key, 'cohort', p_window, 'created', v_seq);
END;
$function$;

CREATE OR REPLACE FUNCTION public.act_on_dating_introduction(p_idempotency_key text, p_introduction_id uuid, p_action text)
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
                             WHERE a.actor_user_id = v_user AND a.idempotency_key = p_idempotency_key)) -- Spec 2 W6a
          || coalesce((SELECT jsonb_build_object('match_id', m.id) FROM public.dating_interest_actions AS a -- Spec 2 W6a (carry 7)
                         JOIN public.dating_matches AS m ON m.introduction_id = a.introduction_id -- Spec 2 W6a
                        WHERE a.actor_user_id = v_user AND a.idempotency_key = p_idempotency_key), '{}'::jsonb); -- Spec 2 W6a
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

CREATE OR REPLACE FUNCTION public.block_dating_user(p_idempotency_key text, p_target_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_pair_key text;
  v_hmac_closed uuid[]; -- Spec 2 W6a (final server fix, M-3)
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF v_user_id = p_target_user_id THEN
    RAISE EXCEPTION 'invalid_target' USING ERRCODE = '22023';
  END IF;

  IF NOT public.claim_dating_idempotency('block_dating_user', p_idempotency_key) THEN
    RETURN;
  END IF;

  v_pair_key := public.dating_pair_key(v_user_id, p_target_user_id);

  INSERT INTO public.dating_blocks (
    blocker_user_id,
    blocked_user_id,
    pair_key
  )
  VALUES (
    v_user_id,
    p_target_user_id,
    v_pair_key
  )
  ON CONFLICT (blocker_user_id, blocked_user_id) DO NOTHING;

  -- Spec 2 W1a: the pair also survives either account's deletion.
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  SELECT h.blocker, h.blocked
    FROM (SELECT public.dating_phone_hmac_for_user(v_user_id) AS blocker,
                 public.dating_phone_hmac_for_user(p_target_user_id) AS blocked) AS h
   WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
  ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;

  PERFORM private.dating_mark_pair(v_user_id, p_target_user_id); -- Spec 2 W6a (carry 1)
  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE pair_key = v_pair_key
    AND state IN ('generated', 'presented', 'interested');

  UPDATE public.dating_matches
  SET state = 'blocked',
      closed_reason = 'blocked', -- Spec 2 W1a
      evidence_until = now() + interval '30 days', -- Spec 2 W1a
      closed_at = COALESCE(closed_at, now())
  WHERE public.dating_pair_key(user_low_id, user_high_id) = v_pair_key
    AND state = 'active';
  PERFORM private.dating_bump_chat(p_target_user_id, m.id) FROM public.dating_matches AS m WHERE m.pair_key = v_pair_key; -- Spec 2 W6a
  -- Spec 2 W6a (fix round 1, M-5): an open chat between the same numbers'
  -- other accounts (blocked by phone HMAC) reads ended; both told.
  -- Spec 2 W6a (final server fix, M-3): it closes too (blocked, sealed for the 30-day
  -- Spec 2 W6a evidence window, so the purge removes it on schedule), then both are told.
  WITH c AS (UPDATE public.dating_matches AS m -- Spec 2 W6a (final server fix, M-3)
                SET state = 'blocked', closed_reason = 'blocked', closed_at = coalesce(m.closed_at, now()), -- Spec 2 W6a (final server fix, M-3)
                    evidence_until = now() + interval '30 days' -- Spec 2 W6a (final server fix, M-3)
              WHERE m.state = 'active' AND m.pair_key IS DISTINCT FROM v_pair_key -- Spec 2 W6a
                AND (v_user_id IN (m.user_low_id, m.user_high_id) OR p_target_user_id IN (m.user_low_id, m.user_high_id)) -- Spec 2 W6a
                AND private.dating_pair_blocked(m.user_low_id, m.user_high_id) -- Spec 2 W6a
             RETURNING m.id) -- Spec 2 W6a (final server fix, M-3)
  SELECT coalesce(pg_catalog.array_agg(c.id), '{}'::uuid[]) INTO v_hmac_closed FROM c; -- Spec 2 W6a (final server fix, M-3)
  PERFORM private.dating_bump_chat(x.u, m.id) -- Spec 2 W6a
     FROM public.dating_matches AS m CROSS JOIN LATERAL (VALUES (m.user_low_id), (m.user_high_id)) AS x(u) -- Spec 2 W6a
    WHERE m.id = ANY (v_hmac_closed); -- Spec 2 W6a (final server fix, M-3)
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_dating_location(p_idempotency_key text, p_country text, p_region text, p_side text, p_scope text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country constant text := upper(coalesce(p_country, ''));
  v_config public.country_safety_config;
  v_region jsonb;
  v_old_country text;
  v_changed_at timestamptz;
  v_ages integer[];
  v_try integer; -- W1 final fix (I-1)
  v_identity_enc bytea; -- W1 final fix (M-2)
  v_seeking_enc bytea; -- W1 final fix (M-2)
  v_read record; -- W1 final fix (M-2)
  v_identity jsonb; -- W1 final fix (M-2)
  v_seeking jsonb; -- W1 final fix (M-2)
  v_unreadable boolean; -- W1 final fix (M-2)
  v_base text; -- W1 final fix (M-2)
  v_before jsonb; -- W1 final fix (M-2)
  v_rows integer; -- W1 final fix (M-2)
  v_restrict boolean; -- W1 final fix (M-2)
BEGIN
  -- W1 final fix (I-1): the new country's same-gender lock is taken with the
  -- W1 final fix setup lock (old, new and other countries in one sorted pass).
  IF v_user IS NOT NULL AND v_country ~ '^[A-Z]{2}$' THEN -- W1 final fix (I-1)
    PERFORM private.dating_lock_setup(v_user, ARRAY[v_country]); -- W1 final fix (I-1)
  END IF; -- W1 final fix (I-1)
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  v_config := public.dating_country_config(v_country);
  IF v_config.country_code IS NULL THEN
    RETURN private.dating_invalid('country');
  END IF;
  IF v_config.dating_enabled IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'country_closed');
  END IF;
  SELECT r INTO v_region FROM jsonb_array_elements(v_config.region_list) AS r WHERE r ->> 'code' = p_region;
  IF v_region IS NULL THEN
    RETURN private.dating_invalid('region');
  END IF;
  IF v_config.open_regions IS NOT NULL AND (p_region = ANY (v_config.open_regions)) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'region_closed');
  END IF;
  IF p_side IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(v_region -> 'sides', '[]'::jsonb)) AS s
                                         WHERE s ->> 'code' = p_side) THEN
    RETURN private.dating_invalid('side');
  END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('side', 'region', 'country') OR (p_scope = 'side' AND p_side IS NULL) THEN
    RETURN private.dating_invalid('scope');
  END IF;
  -- B8 I-2: the other countries' shared same-gender locks (sorted), then the row.
  PERFORM private.dating_lock_same_gender_all(ARRAY(SELECT c::text FROM public.dating_preferences AS d, unnest(d.open_abroad) AS c
                                                     WHERE d.user_id = v_user));
  SELECT p.country_code, p.country_changed_at INTO v_old_country, v_changed_at
    FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
  IF v_old_country IS NOT NULL AND v_old_country IS DISTINCT FROM v_country
     AND v_changed_at IS NOT NULL AND v_changed_at > now() - interval '30 days' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'country_change_limited');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_location', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'privacy');
  END IF;

  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1): a lock conflict is retried (each attempt its own savepoint)
  BEGIN -- W1 final fix (I-1)
  v_restrict := false; -- W1 final fix (M-2)
  IF private.dating_ensure_profile(v_user) THEN
    PERFORM private.bump_metric_internal('dating.setup.started');
  END IF;
  -- W1 final fix (M-2): moving into a country whose same-gender rule is off
  -- W1 final fix gives her pairs the kill switch's treatment, judged by the
  -- W1 final fix answers she held before the move (unreadable or missing is
  -- W1 final fix never man-woman): active matches close ('other', sealed for
  -- W1 final fix the 30-day evidence window), open introductions end, and
  -- W1 final fix she is paused (same_gender_switch) as the switch would pause
  -- W1 final fix her. Nobody is told.
  IF v_old_country IS NOT NULL AND v_old_country IS DISTINCT FROM v_country -- W1 final fix (M-2)
     AND private.dating_same_gender_on(v_country) IS NOT TRUE THEN -- W1 final fix (M-2)
    SELECT coalesce(s.identity_enc, s.held_identity_enc), s.seeking_enc INTO v_identity_enc, v_seeking_enc -- Spec 2 W6a (carry 5, fix round 1 I-1): what was held
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user FOR UPDATE; -- W1 final fix (M-2)
    v_read := private.dating_switch_read(v_identity_enc); -- W1 final fix (M-2)
    v_identity := v_read.o_value; -- W1 final fix (M-2)
    v_unreadable := v_read.o_unreadable; -- W1 final fix (M-2)
    v_read := private.dating_switch_read(v_seeking_enc); -- W1 final fix (M-2)
    v_seeking := v_read.o_value; -- W1 final fix (M-2)
    v_unreadable := v_unreadable OR v_read.o_unreadable; -- W1 final fix (M-2)
    v_base := CASE WHEN v_unreadable THEN 'unreadable' ELSE v_identity ->> 'identity' END; -- W1 final fix (M-2)
    v_before := jsonb_build_object(v_user::text, v_base); -- W1 final fix (M-2): hers as it was (NULL: no answer)
    UPDATE public.dating_matches AS m -- W1 final fix (M-2)
       SET state = 'closed', closed_reason = 'other', closed_at = coalesce(m.closed_at, now()), -- W1 final fix (M-2)
           evidence_until = now() + interval '30 days' -- W1 final fix (M-2)
     WHERE m.state = 'active' AND v_user IN (m.user_low_id, m.user_high_id) -- W1 final fix (M-2)
       AND NOT EXISTS (SELECT 1 FROM (SELECT private.dating_switch_identity(m.user_low_id, v_before) AS a, -- W1 final fix (M-2)
                                             private.dating_switch_identity(m.user_high_id, v_before) AS b) AS g -- W1 final fix (M-2)
                        WHERE ARRAY[g.a, g.b] IN (ARRAY['woman', 'man'], ARRAY['man', 'woman'])); -- W1 final fix (M-2)
    GET DIAGNOSTICS v_rows = ROW_COUNT; -- W1 final fix (M-2)
    v_restrict := v_rows > 0; -- W1 final fix (M-2): a pair ended (for the pause rule below)
    PERFORM private.dating_bump_chat(x.u, m.id) -- Spec 2 W6a (fix round 1b, carry 6): both members of each pair this move closed
       FROM public.dating_matches AS m CROSS JOIN LATERAL (VALUES (m.user_low_id), (m.user_high_id)) AS x(u) -- Spec 2 W6a
      WHERE v_user IN (m.user_low_id, m.user_high_id) AND m.state = 'closed' AND m.closed_reason = 'other' AND m.closed_at = now(); -- Spec 2 W6a
    UPDATE public.dating_introductions AS i SET state = 'invalidated' -- W1 final fix (M-2)
     WHERE i.state IN ('generated', 'presented', 'interested') AND v_user IN (i.user_low_id, i.user_high_id) -- W1 final fix (M-2)
       AND NOT EXISTS (SELECT 1 FROM (SELECT private.dating_switch_identity(i.user_low_id, v_before) AS a, -- W1 final fix (M-2)
                                             private.dating_switch_identity(i.user_high_id, v_before) AS b) AS g -- W1 final fix (M-2)
                        WHERE ARRAY[g.a, g.b] IN (ARRAY['woman', 'man'], ARRAY['man', 'woman'])); -- W1 final fix (M-2)
    GET DIAGNOSTICS v_rows = ROW_COUNT; -- W1 final fix (M-2)
    -- W1 final fix (M-2): paused as the switch pauses: her answers aren't
    -- W1 final fix allowed there (an identity other than plain woman/man, a
    -- W1 final fix who-to-meet other than exactly the opposite, or unreadable),
    -- W1 final fix or she had no identity and was in a pair (never man-woman).
    -- W1 final fix A plain mover's ended pairs don't pause her (nor the switch).
    v_restrict := (v_identity IS NULL AND NOT v_unreadable AND (v_restrict OR v_rows > 0)) OR v_unreadable -- W1 final fix (M-2)
      OR (v_identity IS NOT NULL AND NOT coalesce(v_base IN ('woman', 'man') -- W1 final fix (M-2)
            AND v_identity ->> 'specific' IS NULL AND v_identity ->> 'specific_text' IS NULL -- W1 final fix (M-2)
            AND v_identity ->> 'pronouns' IS NULL AND v_identity -> 'pools' = jsonb_build_array(v_base), false)) -- W1 final fix (M-2)
      OR (v_seeking IS NOT NULL AND NOT coalesce(v_base IN ('woman', 'man') -- W1 final fix (M-2)
            AND v_seeking -> 'seeking' = jsonb_build_array(CASE v_base WHEN 'woman' THEN 'man' ELSE 'woman' END), false)); -- W1 final fix (M-2)
    IF v_restrict THEN -- W1 final fix (M-2): an enrolment already paused keeps its first reason
      UPDATE public.dating_enrollments AS e -- W1 final fix (M-2)
         SET state = 'paused', pause_reason = 'same_gender_switch', paused_at = coalesce(e.paused_at, now()), -- W1 final fix (M-2)
             updated_at = now() -- W1 final fix (M-2)
       WHERE e.user_id = v_user AND e.state IN ('active', 'profile_draft'); -- W1 final fix (M-2)
    END IF; -- W1 final fix (M-2)
  END IF; -- W1 final fix (M-2)
  UPDATE public.dating_profiles AS p
     SET country_code = v_country, region_code = p_region, side_code = p_side,
         country_changed_at = CASE WHEN p.country_code IS DISTINCT FROM v_country AND p.country_code IS NOT NULL
                                   THEN now() ELSE p.country_changed_at END,
         profile_state = CASE WHEN v_restrict AND p.profile_state = 'active' THEN 'paused' ELSE p.profile_state END, -- W1 final fix (M-2)
         updated_at = now()
   WHERE p.user_id = v_user;
  -- A new Dating country: gender and who-to-meet are asked again (§2.4).
  IF v_old_country IS NOT NULL AND v_old_country IS DISTINCT FROM v_country THEN
    UPDATE public.dating_profile_sensitive AS s
       SET held_identity_enc = CASE WHEN v_restrict THEN NULL ELSE coalesce(s.identity_enc, s.held_identity_enc) END, -- Spec 2 W6a (carry 5)
           identity_enc = NULL, seeking_enc = NULL, updated_at = now() -- Spec 2 W6a
     WHERE s.user_id = v_user;
    UPDATE public.dating_profiles AS p SET gender_visible = false WHERE p.user_id = v_user;
    UPDATE public.dating_preferences AS d
       SET open_abroad = array_remove(d.open_abroad, v_country::char(2)) WHERE d.user_id = v_user;
    -- B8 I-2: gender and who-to-meet are unknown again (not plain).
    PERFORM private.dating_prune_unsafe_abroad(v_user);
  END IF;
  v_ages := private.dating_default_ages(public.account_age(v_user));
  INSERT INTO public.dating_preferences AS d (user_id, min_age, max_age, region_scope)
  VALUES (v_user, v_ages[1], v_ages[2], p_scope)
  ON CONFLICT (user_id) DO UPDATE SET region_scope = EXCLUDED.region_scope, updated_at = now();
  PERFORM private.bump_metric_internal('dating.setup.step.d3');
  EXIT; -- W1 final fix (I-1)
  EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
    IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1)
  END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)
  RETURN jsonb_build_object('ok', true, 'next_step', 'privacy');
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_dating_identity(p_idempotency_key text, p_identity text, p_specific text, p_pronouns text, p_extra_pools text[], p_visible boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_extra constant text[] := coalesce(p_extra_pools, ARRAY[]::text[]);
  v_known constant text[] := ARRAY['trans_woman', 'trans_man', 'genderfluid', 'genderqueer', 'agender', 'intersex'];
  v_old jsonb;
  v_pools text[];
  v_verdict text;
  v_new jsonb;
  v_seeking jsonb;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF private.dating_consent_granted(v_user, 'special_category_profile') IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_country IS NULL THEN
    RETURN private.dating_invalid('country');
  END IF;
  -- I-5: the country's same-gender lock (shared), then the profile row.
  -- B8 I-2: with the other countries' locks, all sorted by code.
  PERFORM private.dating_lock_same_gender_all(ARRAY[v_country] || ARRAY(
            SELECT c::text FROM public.dating_preferences AS d, unnest(d.open_abroad) AS c WHERE d.user_id = v_user));
  PERFORM 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
  -- Off-country (§2.4): only Woman or Man, nothing more; anything else is
  -- not_available, raised by nothing, stored nowhere, counted nowhere.
  IF private.dating_same_gender_on(v_country) IS NOT TRUE
     AND (p_identity IS DISTINCT FROM 'woman' AND p_identity IS DISTINCT FROM 'man'
          OR p_specific IS NOT NULL OR p_pronouns IS NOT NULL OR cardinality(v_extra) > 0) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_available');
  END IF;
  IF p_identity IS NULL OR p_identity NOT IN ('woman', 'man', 'non_binary') THEN
    RETURN private.dating_invalid('identity');
  END IF;
  IF p_specific IS NOT NULL AND NOT (p_specific = ANY (v_known))
     AND NOT coalesce((p_specific COLLATE "pg_c_utf8") ~ '^[[:alpha:]][[:alpha:] -]{0,29}$' AND char_length(btrim(p_specific)) BETWEEN 1 AND 30, false) THEN
    RETURN private.dating_invalid('specific');
  END IF;
  -- PF-F7: letters, '/', space and hyphen only (at least one letter).
  IF p_pronouns IS NOT NULL
     AND (char_length(btrim(p_pronouns)) NOT BETWEEN 1 AND 20
          OR NOT coalesce((btrim(p_pronouns) COLLATE "pg_c_utf8") ~ '^[[:alpha:]/ -]+$', false)
          OR NOT coalesce((p_pronouns COLLATE "pg_c_utf8") ~ '[[:alpha:]]', false)) THEN
    RETURN private.dating_invalid('pronouns');
  END IF;
  IF NOT coalesce(v_extra <@ ARRAY['woman', 'man'], false)
     OR (cardinality(v_extra) > 0 AND p_identity IS DISTINCT FROM 'non_binary') THEN
    RETURN private.dating_invalid('pools');
  END IF;
  -- PF-F7: the free text shown on the card is filtered like the prompts,
  -- after the off-country refusal (§2.4 first) and the validation; a hit
  -- stores, claims and counts nothing.
  v_verdict := private.content_filter_verdict(concat_ws(' ', p_specific, p_pronouns), NULL);
  IF v_verdict IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', CASE WHEN v_verdict = 'contact_info' THEN 'contact_details' ELSE 'unkind' END);
  END IF;
  IF private.dating_field_key_present() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  BEGIN
    IF NOT public.claim_dating_idempotency('save_dating_identity', p_idempotency_key) THEN
      RETURN jsonb_build_object('ok', true, 'next_step', 'meet');
    END IF;

    PERFORM private.dating_ensure_profile(v_user);
    v_pools := CASE p_identity WHEN 'non_binary'
                 THEN ARRAY['non_binary'] || ARRAY(SELECT DISTINCT e FROM unnest(v_extra) AS e ORDER BY e)
                 ELSE ARRAY[p_identity] END;
    SELECT private.dating_field_decrypt(s.identity_enc) INTO v_old
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
    v_new := jsonb_build_object(
             'identity', p_identity,
             'specific', CASE WHEN p_specific = ANY (v_known) THEN p_specific END,
             'specific_text', CASE WHEN p_specific IS NOT NULL AND NOT (p_specific = ANY (v_known)) THEN btrim(p_specific) END,
             'pronouns', nullif(btrim(p_pronouns), ''),
             'pools', to_jsonb(v_pools));
    UPDATE public.dating_profile_sensitive AS s
       SET identity_enc = private.dating_field_encrypt(v_new),
           held_identity_enc = NULL, -- Spec 2 W6a (carry 5): answered again
           -- A changed identity where same-gender is off: who-to-meet is asked again.
           seeking_enc = CASE WHEN private.dating_same_gender_on(v_country) IS NOT TRUE
                               AND v_old ->> 'identity' IS DISTINCT FROM p_identity THEN NULL
                              ELSE s.seeking_enc END,
           updated_at = now()
     WHERE s.user_id = v_user;
    UPDATE public.dating_profiles AS p SET gender_visible = coalesce(p_visible, false), updated_at = now()
     WHERE p.user_id = v_user;
    -- B8 I-2: not plain now (with who-to-meet as stored): unsafe other countries go.
    SELECT private.dating_field_decrypt(s.seeking_enc) INTO v_seeking
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
    IF private.dating_profile_plain(v_new, v_seeking) IS NOT TRUE THEN
      PERFORM private.dating_prune_unsafe_abroad(v_user);
    END IF;
    PERFORM private.bump_metric_internal('dating.setup.step.d5');
  EXCEPTION WHEN raise_exception THEN
    -- An unreadable value or a missing key (D5): unavailable, and the
    -- block's claim, rows and counters are undone (batch-6 carry).
    IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
    END IF;
    RAISE;
  END;
  RETURN jsonb_build_object('ok', true, 'next_step', 'meet');
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_switch_identity(p_user uuid, p_before jsonb)
 RETURNS text
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  SELECT CASE WHEN p_before ? p_user::text THEN p_before ->> p_user::text
              ELSE (SELECT CASE WHEN d.o_unreadable THEN 'unreadable' ELSE d.o_value ->> 'identity' END
                      FROM public.dating_profile_sensitive AS s
                     CROSS JOIN LATERAL private.dating_switch_read(coalesce(s.identity_enc, s.held_identity_enc)) AS d -- Spec 2 W6a (carry 5)
                     WHERE s.user_id = p_user) END;
$function$;

CREATE OR REPLACE FUNCTION public.apply_same_gender_switch(p_country text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_code constant text := upper(btrim(p_country));
  v_codes text[];
  v_off text[];
  v_c text;
  r record;
  v_identity_enc bytea;
  v_seeking_enc bytea;
  v_read record;
  v_identity jsonb;
  v_seeking jsonb;
  v_unreadable boolean;
  v_bad_identity boolean;
  v_bad_seeking boolean;
  v_base text;
  v_strip boolean;
  v_kept_base text;
  v_open_pair boolean;
  v_held_only boolean; -- Spec 2 W6a (carry 5, fix round 1)
  v_held_enc bytea; -- Spec 2 W6a (final server fix, M-11)
  v_held jsonb; -- Spec 2 W6a (final server fix, M-11)
  v_held_base text; -- Spec 2 W6a (final server fix, M-11)
  v_before jsonb;
  v_count integer := 0;
BEGIN
  IF p_country IS NOT NULL
     AND (coalesce(v_code ~ '^[A-Z]{2}$', false) IS NOT TRUE OR private.dating_iso_country(v_code) IS NULL) THEN
    RAISE EXCEPTION 'dating:invalid_country';
  END IF;
  -- A missing or replaced key would make every answer unreadable, and the
  -- restrictive path would then wipe them all.
  IF private.dating_field_key_usable() IS NOT TRUE THEN
    IF private.dating_field_key_present() THEN -- fix round 1, M-6: present but replaced or unseeded
      RAISE EXCEPTION 'dating:field_key_not_ready';
    END IF;
    RAISE EXCEPTION 'dating:field_key_missing';
  END IF;

  -- 1. The exclusive same-gender lock of every affected country, before any
  --    row (setup writers hold it shared while they decide; batch-7 I-5).
  --    Every country: all that are configured or named by a profile or an
  --    other-countries list, in COLLATE "C" order (dating_lock_same_gender_all's).
  v_codes := CASE WHEN p_country IS NOT NULL THEN ARRAY[v_code]
                  ELSE ARRAY(SELECT DISTINCT x.c COLLATE "C"
                               FROM (SELECT c.country_code::text AS c FROM public.country_safety_config AS c
                                     UNION SELECT p.country_code::text FROM public.dating_profiles AS p
                                     UNION SELECT a::text FROM public.dating_preferences AS d, unnest(d.open_abroad) AS a) AS x
                              WHERE x.c IS NOT NULL
                              ORDER BY 1) END;
  FOREACH v_c IN ARRAY v_codes LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_same_gender'), pg_catalog.hashtext(v_c));
  END LOOP;
  -- Read after the locks: the countries that now refuse same-gender.
  v_off := ARRAY(SELECT c FROM unnest(v_codes) AS c WHERE private.dating_same_gender_on(c) IS NOT TRUE ORDER BY 1);
  IF cardinality(v_off) = 0 THEN
    DELETE FROM private.dating_kill_switch_pending AS k WHERE p_country IS NULL OR k.scope = v_code;
    RETURN 0;
  END IF;

  -- The identities as they were, for the introduction and match passes
  -- (a woman whose pronouns are deleted below is still in a man-woman pair).
  SELECT coalesce(jsonb_object_agg(s.user_id::text, CASE WHEN d.o_unreadable THEN to_jsonb('unreadable'::text)
                                                         ELSE d.o_value -> 'identity' END), '{}'::jsonb)
    INTO v_before
    FROM public.dating_profiles AS p
    JOIN public.dating_profile_sensitive AS s ON s.user_id = p.user_id
   CROSS JOIN LATERAL private.dating_switch_read(coalesce(s.identity_enc, s.held_identity_enc)) AS d -- Spec 2 W6a (carry 5)
   WHERE p.country_code::text = ANY (v_off);

  -- 2. The people there: enrolment, then sensitive, then profile.
  FOR r IN
    SELECT p.user_id
      FROM public.dating_profiles AS p
     WHERE p.country_code::text = ANY (v_off)
     ORDER BY p.user_id
  LOOP
    PERFORM 1 FROM public.dating_enrollments AS e WHERE e.user_id = r.user_id FOR UPDATE;
    SELECT coalesce(s.identity_enc, s.held_identity_enc), s.seeking_enc, -- Spec 2 W6a (carry 5, fix round 1): judged by what was held
           s.identity_enc IS NULL AND s.held_identity_enc IS NOT NULL, -- Spec 2 W6a
           s.held_identity_enc -- Spec 2 W6a (final server fix, M-11)
      INTO v_identity_enc, v_seeking_enc, v_held_only, v_held_enc -- Spec 2 W6a
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = r.user_id FOR UPDATE;
    CONTINUE WHEN NOT FOUND;
    -- Spec 2 W6a (final server fix, M-11): a held identity keeps a plain woman or man answer
    -- Spec 2 W6a (the kill switch's own judge, so a second run before the person answers again
    -- Spec 2 W6a still sees a man-woman pair); a woman or man answer loses only its
    -- Spec 2 W6a disallowed parts; anything else held (another identity, unreadable) is cleared.
    IF v_held_enc IS NOT NULL THEN -- Spec 2 W6a (final server fix, M-11)
      v_read := private.dating_switch_read(v_held_enc); -- Spec 2 W6a
      v_held := CASE WHEN v_read.o_unreadable THEN NULL ELSE v_read.o_value END; -- Spec 2 W6a
      v_held_base := v_held ->> 'identity'; -- Spec 2 W6a
      IF coalesce(v_held_base IN ('woman', 'man'), false) IS NOT TRUE THEN -- Spec 2 W6a
        UPDATE public.dating_profile_sensitive AS s SET held_identity_enc = NULL, updated_at = now() -- Spec 2 W6a
         WHERE s.user_id = r.user_id; -- Spec 2 W6a
      ELSIF v_held ->> 'specific' IS NOT NULL OR v_held ->> 'specific_text' IS NOT NULL -- Spec 2 W6a
            OR v_held ->> 'pronouns' IS NOT NULL OR v_held -> 'pools' IS DISTINCT FROM jsonb_build_array(v_held_base) THEN -- Spec 2 W6a
        UPDATE public.dating_profile_sensitive AS s -- Spec 2 W6a
           SET held_identity_enc = private.dating_field_encrypt(jsonb_build_object( -- Spec 2 W6a
                 'identity', v_held_base, 'specific', NULL, 'specific_text', NULL, 'pronouns', NULL, -- Spec 2 W6a
                 'pools', jsonb_build_array(v_held_base))), updated_at = now() -- Spec 2 W6a
         WHERE s.user_id = r.user_id; -- Spec 2 W6a
      END IF; -- Spec 2 W6a
    END IF; -- Spec 2 W6a (final server fix, M-11)
    v_read := private.dating_switch_read(v_identity_enc);
    v_identity := v_read.o_value;
    v_unreadable := v_read.o_unreadable;
    v_read := private.dating_switch_read(v_seeking_enc);
    v_seeking := v_read.o_value;
    v_unreadable := v_unreadable OR v_read.o_unreadable;
    v_base := CASE WHEN v_unreadable THEN NULL ELSE v_identity ->> 'identity' END;
    v_bad_identity := v_unreadable OR (v_identity IS NOT NULL
      AND (coalesce(v_base, '') NOT IN ('woman', 'man')
           OR v_identity ->> 'specific' IS NOT NULL OR v_identity ->> 'specific_text' IS NOT NULL
           OR v_identity ->> 'pronouns' IS NOT NULL
           OR v_identity -> 'pools' IS DISTINCT FROM jsonb_build_array(v_base)));
    -- M-4: a woman/man identity loses only its disallowed parts.
    v_strip := v_bad_identity AND coalesce(v_base IN ('woman', 'man'), false);
    v_kept_base := CASE WHEN v_bad_identity AND NOT v_strip THEN NULL ELSE v_base END;
    v_bad_seeking := v_unreadable OR (v_seeking IS NOT NULL
      AND (v_kept_base IS NULL
           OR v_seeking -> 'seeking' IS DISTINCT FROM
              jsonb_build_array(CASE v_kept_base WHEN 'woman' THEN 'man' ELSE 'woman' END)));
    -- I-3: no stored identity in an open pair is never "man-woman".
    v_open_pair := v_identity IS NULL AND NOT v_unreadable
      AND (EXISTS (SELECT 1 FROM public.dating_matches AS m
                    WHERE m.state = 'active' AND r.user_id IN (m.user_low_id, m.user_high_id))
           OR EXISTS (SELECT 1 FROM public.dating_introductions AS i
                       WHERE i.state IN ('generated', 'presented', 'interested')
                         AND r.user_id IN (i.user_low_id, i.user_high_id)));
    CONTINUE WHEN NOT (v_bad_identity OR v_bad_seeking OR v_open_pair);
    IF v_unreadable THEN
      PERFORM private.bump_metric_internal('dating.kill_switch.unreadable');
    END IF;
    UPDATE public.dating_profile_sensitive AS s
       SET identity_enc = CASE WHEN v_held_only THEN NULL -- Spec 2 W6a (carry 5, fix round 1): what was held is never written as an answer
                               WHEN NOT v_bad_identity THEN s.identity_enc -- Spec 2 W6a
                               WHEN v_strip THEN private.dating_field_encrypt(jsonb_build_object(
                                 'identity', v_base, 'specific', NULL, 'specific_text', NULL, 'pronouns', NULL,
                                 'pools', jsonb_build_array(v_base)))
                               ELSE NULL END,
           seeking_enc = CASE WHEN v_bad_seeking THEN NULL ELSE s.seeking_enc END,
           updated_at = now()
     WHERE s.user_id = r.user_id;
    UPDATE public.dating_profiles AS p
       SET gender_visible = CASE WHEN v_bad_identity THEN false ELSE p.gender_visible END,
           profile_state = CASE WHEN p.profile_state = 'active' THEN 'paused' ELSE p.profile_state END,
           updated_at = now()
     WHERE p.user_id = r.user_id;
    UPDATE public.dating_enrollments AS e
       SET state = 'paused', pause_reason = 'same_gender_switch', paused_at = coalesce(e.paused_at, now()),
           updated_at = now()
     WHERE e.user_id = r.user_id AND e.state IN ('active', 'profile_draft');
    v_count := v_count + 1;
  END LOOP;

  -- 3. The switched countries leave every not-plain person's other-countries
  --    list (batch-8 I-2c; the locks are held). Unreadable is not plain.
  FOR r IN
    SELECT d.user_id
      FROM public.dating_preferences AS d
     WHERE d.open_abroad::text[] && v_off
     ORDER BY d.user_id
  LOOP
    v_identity_enc := NULL;
    v_seeking_enc := NULL;
    SELECT s.identity_enc, s.seeking_enc INTO v_identity_enc, v_seeking_enc
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = r.user_id;
    v_read := private.dating_switch_read(v_identity_enc);
    v_identity := v_read.o_value;
    v_unreadable := v_read.o_unreadable;
    v_read := private.dating_switch_read(v_seeking_enc);
    v_seeking := v_read.o_value;
    v_unreadable := v_unreadable OR v_read.o_unreadable;
    IF v_unreadable THEN -- (never someone step 2 handled: it deleted what it couldn't read)
      PERFORM private.bump_metric_internal('dating.kill_switch.unreadable');
    END IF;
    IF v_unreadable OR private.dating_profile_plain(v_identity, v_seeking) IS NOT TRUE THEN
      PERFORM private.dating_prune_unsafe_abroad(r.user_id);
    END IF;
  END LOOP;

  -- 4. Every open introduction touching a switched country that isn't
  --    known to be man-woman (an unreadable or missing identity is not).
  UPDATE public.dating_introductions AS i
     SET state = 'invalidated'
   WHERE i.state IN ('generated', 'presented', 'interested')
     AND EXISTS (SELECT 1 FROM public.dating_profiles AS p
                  WHERE p.user_id IN (i.user_low_id, i.user_high_id)
                    AND p.country_code::text = ANY (v_off))
     AND NOT EXISTS (SELECT 1 FROM (SELECT private.dating_switch_identity(i.user_low_id, v_before) AS a,
                                           private.dating_switch_identity(i.user_high_id, v_before) AS b) AS g
                      WHERE ARRAY[g.a, g.b] IN (ARRAY['woman', 'man'], ARRAY['man', 'woman']));

  -- 5. Owner ruling 2026-11-06 (PF-F2): every active match touching a
  --    switched country that isn't man-woman closes, neutrally ('other'),
  --    sealed for the 30-day evidence window. Nobody is told.
  UPDATE public.dating_matches AS m
     SET state = 'closed', closed_reason = 'other', closed_at = coalesce(m.closed_at, now()),
         evidence_until = now() + interval '30 days'
   WHERE m.state = 'active'
     AND EXISTS (SELECT 1 FROM public.dating_profiles AS p
                  WHERE p.user_id IN (m.user_low_id, m.user_high_id)
                    AND p.country_code::text = ANY (v_off))
     AND NOT EXISTS (SELECT 1 FROM (SELECT private.dating_switch_identity(m.user_low_id, v_before) AS a,
                                           private.dating_switch_identity(m.user_high_id, v_before) AS b) AS g
                      WHERE ARRAY[g.a, g.b] IN (ARRAY['woman', 'man'], ARRAY['man', 'woman']));
  PERFORM private.dating_bump_chat(x.u, m.id) -- Spec 2 W6a (fix round 1b, carry 6): both members of each pair the switch closed
     FROM public.dating_matches AS m CROSS JOIN LATERAL (VALUES (m.user_low_id), (m.user_high_id)) AS x(u) -- Spec 2 W6a
    WHERE m.state = 'closed' AND m.closed_reason = 'other' AND m.closed_at = now() -- Spec 2 W6a
      AND EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id IN (m.user_low_id, m.user_high_id) -- Spec 2 W6a
                     AND p.country_code::text = ANY (v_off)); -- Spec 2 W6a
  -- I-1: what was switched is no longer pending.
  DELETE FROM private.dating_kill_switch_pending AS k WHERE p_country IS NULL OR k.scope = v_code;
  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_open_chats(p_user uuid, p_at timestamp with time zone)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT count(*)::integer FROM public.dating_matches AS m
   WHERE m.state = 'active' AND p_user IN (m.user_low_id, m.user_high_id)
     AND (m.matched_at > p_at - interval '7 days' -- Spec 2 W6a (§5.3): or a message in the last 14 days
          OR EXISTS (SELECT 1 FROM public.dating_messages AS d -- Spec 2 W6a
                      WHERE d.match_id = m.id AND d.created_at > p_at - interval '14 days')); -- Spec 2 W6a
$function$;

CREATE OR REPLACE FUNCTION private.dating_first_messages(p_user uuid, p_since timestamp with time zone, p_at timestamp with time zone)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT count(*)::integer -- Spec 2 W6a (carry 6): the matches the person wrote in
    FROM public.dating_matches AS m JOIN public.dating_introductions AS i ON i.id = m.introduction_id -- Spec 2 W6a
   WHERE p_user IN (i.user_low_id, i.user_high_id) AND i.created_at > p_since -- Spec 2 W6a
     AND i.created_at <= p_at -- Spec 2 W6a (fix round 1, M-8): by the run's time
     AND EXISTS (SELECT 1 FROM public.dating_messages AS d WHERE d.match_id = m.id AND d.sender_user_id = p_user -- Spec 2 W6a
                  AND d.created_at <= p_at); -- Spec 2 W6a (fix round 1, M-8)
$function$;

CREATE OR REPLACE FUNCTION private.dating_dragnet_holds(p_user uuid, p_at timestamp with time zone, p_cfg jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_since constant timestamptz := p_at - make_interval(days => coalesce((p_cfg #>> '{dragnet,window_days}')::int, 14));
  v_intros integer;
  v_interested integer;
  v_matches integer;
  v_first integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE CASE WHEN i.user_low_id = p_user THEN i.low_action ELSE i.high_action END = 'interested')
    INTO v_intros, v_interested
    FROM public.dating_introductions AS i
   WHERE p_user IN (i.user_low_id, i.user_high_id) AND i.created_at > v_since AND i.created_at <= p_at;
  IF v_intros < coalesce((p_cfg #>> '{dragnet,min_intros}')::int, 15)
     OR v_interested < v_intros * coalesce((p_cfg #>> '{dragnet,interested_ratio}')::numeric, 0.9) THEN
    RETURN false;
  END IF;
  SELECT count(*) INTO v_matches
    FROM public.dating_matches AS m JOIN public.dating_introductions AS i ON i.id = m.introduction_id
   WHERE p_user IN (i.user_low_id, i.user_high_id) AND i.created_at > v_since AND i.created_at <= p_at;
  v_first := private.dating_first_messages(p_user, v_since, p_at); -- Spec 2 W6a (fix round 1, M-8): the run's time
  RETURN coalesce(v_matches > 0
                  AND v_first <= v_matches * coalesce((p_cfg #>> '{dragnet,first_message_ratio}')::numeric, 0.2), false);
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_exit_internal(p_user uuid, p_keep_never_introduce boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_found boolean;
  v_exited_at timestamptz;
  v_closed uuid[]; -- Spec 2 W6a (final server fix, I-5)
BEGIN
  IF p_user IS NULL THEN
    RETURN;
  END IF;
  -- The row order: the enrolment before the profile (as activation, the
  -- pauses and the parked trigger).
  SELECT e.exited_at INTO v_exited_at FROM public.dating_enrollments AS e WHERE e.user_id = p_user FOR UPDATE;
  v_found := FOUND;
  -- Uploads never attached go with their storage objects; photo rows queue
  -- their own objects (dating_photos_queue_media_before_delete). Both go
  -- through queue_media_deletion, so the CSAM evidence guard holds back an
  -- object under an open, unquarantined match.
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
     FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user -- Spec 2 W3c (Task 9 fix round 1, I-1): an intent names its photo's object
      AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f -- Spec 2 W3c (Task 9 fix round 1, I-1)
                       WHERE f.storage_key = i.storage_key AND f.csam_state = 'hit'); -- Spec 2 W3c (Task 9 fix round 1, I-1): not a hit's
  DELETE FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user;
  DELETE FROM public.dating_profile_photos AS f WHERE f.user_id = p_user;
  DELETE FROM public.dating_prompts AS q WHERE q.user_id = p_user;
  DELETE FROM public.dating_settings AS t WHERE t.user_id = p_user;
  DELETE FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
  DELETE FROM public.dating_preferences AS d WHERE d.user_id = p_user;
  DELETE FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  DELETE FROM public.dating_date_reflections AS r WHERE r.author_user_id = p_user;
  DELETE FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  DELETE FROM public.dating_notify_requests AS n WHERE n.user_id = p_user;
  IF to_regclass('public.dating_gentle_wait_reflections') IS NOT NULL THEN -- W2's table
    EXECUTE 'DELETE FROM public.dating_gentle_wait_reflections WHERE user_id = $1' USING p_user;
  END IF;
  IF NOT coalesce(p_keep_never_introduce, false) THEN
    DELETE FROM public.dating_never_introduce AS n WHERE n.owner_user_id = p_user;
  ELSE -- Spec 2 W4b (fix rounds 1-2, C-1): kept, never shown again, its label gone
    UPDATE public.dating_never_introduce AS n SET kept_at = coalesce(n.kept_at, now()), shown_at = NULL, label = NULL -- Spec 2 W4b
     WHERE n.owner_user_id = p_user; -- Spec 2 W4b
  END IF;
  -- Spec 2 W4a: the verification sessions go, a human review's photos with
  -- Spec 2 W4a them (queued, as every Dating object), and the identity
  -- Spec 2 W4a result, which covered the photos deleted above. -- Spec 2 W4 final
  -- Spec 2 W4 final (I-1a ruling): an age pass goes too (it belongs to the
  -- Spec 2 W4 final face that earned it; a new setup checks the age again);
  -- Spec 2 W4 final a fail (and Spec 1's hold) stays while the account exists.
  PERFORM public.queue_media_deletion('dating-verification-review', o.name) -- Spec 2 W4a
     FROM storage.objects AS o -- Spec 2 W4a
    WHERE o.bucket_id = 'dating-verification-review' -- Spec 2 W4a
      AND split_part(o.name, '/', 1) IN (SELECT vs.id::text FROM public.dating_verification_sessions AS vs -- Spec 2 W4a
                                          WHERE vs.user_id = p_user); -- Spec 2 W4a
  DELETE FROM public.dating_verification_sessions AS vs WHERE vs.user_id = p_user; -- Spec 2 W4a
  DELETE FROM public.dating_trusted_devices AS td WHERE td.user_id = p_user; -- Spec 2 W4b (§3.3.4): leaving unbinds every phone
  UPDATE public.dating_age_verifications AS av -- Spec 2 W4a
     SET identity_method = NULL, identity_result = NULL, identity_vendor = NULL, -- Spec 2 W4a
         identity_decided_at = NULL, decided_by = NULL, updated_at = now() -- Spec 2 W4a
   WHERE av.user_id = p_user AND av.identity_result IS NOT NULL; -- Spec 2 W4a
  UPDATE public.dating_age_verifications AS av -- Spec 2 W4 final (I-1a)
     SET age_method = NULL, age_result = NULL, challenge_age = NULL, age_vendor = NULL, age_decided_at = NULL, -- Spec 2 W4 final (I-1a)
         updated_at = now() -- Spec 2 W4 final (I-1a)
   WHERE av.user_id = p_user AND av.age_result = 'pass' AND av.revoked_at IS NULL; -- Spec 2 W4 final (I-1a): a fail stays
  -- Conversations close for both and stay sealed for the evidence window.
  -- Spec 2 W6a (final server fix, I-5): the match rows first, then the signal (send's lock
  -- Spec 2 W6a order: a send from the person's other phone never deadlocks with the leave).
  SELECT coalesce(pg_catalog.array_agg(x.id), '{}'::uuid[]) INTO v_closed -- Spec 2 W6a (final server fix, I-5)
    FROM (SELECT m.id FROM public.dating_matches AS m -- Spec 2 W6a
           WHERE p_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active' -- Spec 2 W6a
             FOR NO KEY UPDATE OF m) AS x; -- Spec 2 W6a
  UPDATE public.dating_matches AS m
     SET state = 'closed', closed_reason = 'exit', closed_at = coalesce(m.closed_at, now()),
         evidence_until = now() + interval '30 days'
   WHERE p_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active';
  PERFORM private.dating_bump_chat(CASE WHEN m.user_low_id = p_user THEN m.user_high_id ELSE m.user_low_id END, m.id) -- Spec 2 W6a (fix round 1, M-5): the other's open chat reads it ended
     FROM public.dating_matches AS m WHERE m.id = ANY (v_closed); -- Spec 2 W6a (final server fix, I-5): after the close
  -- Introductions go (their interest actions cascade; a match keeps its row).
  DELETE FROM public.dating_introductions AS i WHERE p_user IN (i.user_low_id, i.user_high_id);
  -- Spec 2 W5a: the trait snapshots are gone (§4.10)
  -- "When you left" (§3.8; fix round 1, I-1): every consent whose latest
  -- event is a grant is withdrawn now, on the server's clock, so coming back
  -- needs D4 again. Kept with the consents (Q17 exception 3). A second exit
  -- finds nothing standing and writes nothing (M-2).
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT p_user, 'exit:' || l.purpose || ':' || replace(gen_random_uuid()::text, '-', ''), l.purpose, 'withdrawn',
         l.policy_version, clock_timestamp()
    FROM (SELECT DISTINCT ON (c.purpose) c.purpose, c.action, c.policy_version
            FROM public.dating_consent_events AS c
           WHERE c.user_id = p_user
           ORDER BY c.purpose, c.occurred_at DESC, c.created_at DESC, (c.action = 'withdrawn') DESC) AS l
   WHERE l.action = 'granted';
  -- A suspension stays (only the data goes); a second exit keeps the first
  -- "when you left" (M-2).
  UPDATE public.dating_enrollments AS e
     SET state = CASE WHEN e.state = 'suspended' THEN 'suspended' ELSE 'exited' END,
         exited_at = coalesce(e.exited_at, now()), paused_at = NULL, pause_reason = NULL, updated_at = now()
   WHERE e.user_id = p_user;
  IF v_found AND v_exited_at IS NULL THEN
    PERFORM private.bump_metric_internal('dating.exit');
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE -- W1 final fix (I-1)
  v_try integer; -- W1 final fix (I-1)
  v_closed uuid[]; -- Spec 2 W6a (final server fix, I-5)
BEGIN
  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1)
  BEGIN -- W1 final fix (I-1)
  -- Spec 2 W5a: the trait snapshots are gone (§4.10)

  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
    AND state IN ('generated', 'presented', 'interested');

  -- Close existing active matches ONLY for reasons that are genuinely an exit
  -- from Dating: leaving (exit), terms/opt-in withdrawal (dating_consent_withdrawn
  -- — this ALSO sets profile_state='exited', so it must close matches too, per
  -- re-review DATING-H5a; note Spec §3.3/:113 "matches remain on withdrawal"
  -- governs HISTORICAL-DATA consent only, not terms/opt-in), suspension
  -- (account_restricted), and profile deletion. Pause, HISTORICAL-consent
  -- withdrawal, profile edits, and scheduled revalidation deliberately PRESERVE
  -- matches (Spec §14 :612 pause; :113 historical-consent).
  IF p_reason IN (
    'exit', 'dating_consent_withdrawn', 'account_restricted', 'profile_deleted', -- Spec 2 W4a
    'age_review', 'age_verification_invalid' -- Spec 2 W4a (§6.3, §4.10): every match closes
  ) THEN
    -- Spec 2 W6a (final server fix, I-5): the match rows first, then the signals (send's order).
    SELECT coalesce(pg_catalog.array_agg(x.id), '{}'::uuid[]) INTO v_closed -- Spec 2 W6a (final server fix, I-5)
      FROM (SELECT m.id FROM public.dating_matches AS m -- Spec 2 W6a
             WHERE p_user_id IN (m.user_low_id, m.user_high_id) AND m.state = 'active' -- Spec 2 W6a
               FOR NO KEY UPDATE OF m) AS x; -- Spec 2 W6a
    UPDATE public.dating_matches
    SET state = 'closed',
        closed_at = COALESCE(closed_at, now()), -- Spec 2 W4a
        -- Spec 2 W6a (final server fix, I-1): every closing reason names itself and seals the
        -- Spec 2 W6a 30-day evidence window (a suspension or hold included), so the other person
        -- Spec 2 W6a keeps the ended chat and its Report window, and the purge removes it on schedule.
        closed_reason = CASE WHEN p_reason IN ('age_review', 'age_verification_invalid') THEN p_reason -- Spec 2 W4a
                             ELSE coalesce(closed_reason, CASE p_reason WHEN 'account_restricted' THEN 'account_restricted' -- Spec 2 W6a
                                                                      WHEN 'exit' THEN 'exit' -- Spec 2 W6a
                                                                      WHEN 'profile_deleted' THEN 'account_deleted' -- Spec 2 W6a
                                                                      ELSE 'other' END) END, -- Spec 2 W6a (final server fix, I-1)
        evidence_until = now() + interval '30 days' -- Spec 2 W6a (final server fix, I-1; §4.8)
    WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
      AND state = 'active';
    PERFORM private.dating_bump_chat(x.u, m.id) -- Spec 2 W6a (fix round 1b, carry 6): both members' open chats read it ended
       FROM public.dating_matches AS m CROSS JOIN LATERAL (VALUES (m.user_low_id), (m.user_high_id)) AS x(u) -- Spec 2 W6a
      WHERE m.id = ANY (v_closed); -- Spec 2 W6a (final server fix, I-5): after the close
  END IF;
  EXIT; -- W1 final fix (I-1)
  EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
    IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1)
  END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_account_deletion(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_rel record;
  v_key_set boolean; -- Spec 2 W1a (PF-F6)
  v_closed uuid[]; -- Spec 2 W6a (final server fix, I-5)
  v_try integer; -- Spec 2 W6a (final server fix, I-5)
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'deletion:no_user';
  END IF;

  -- Spec 2 W1a (§6.3, R5): Dating carry-over, before anything is deleted.
  -- A missing key with a live restriction refuses (retried once the key is
  -- in Vault, PF-F6). The carry (records under each restriction's stamped
  -- HMAC, block pairs, report HMACs) runs; a failure there is counted and
  -- never refuses (W1 final fix, M-4). The auth.users trigger runs it again
  -- at the delete.
  v_key_set := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NOT NULL;
  IF NOT v_key_set AND EXISTS (
       SELECT 1 FROM public.dating_account_restrictions AS dar
        WHERE dar.user_id = p_user_id AND dar.lifted_at IS NULL
          AND (dar.ends_at IS NULL OR dar.ends_at > now())) THEN
    RAISE EXCEPTION 'deletion:enforcement_key_missing';
  END IF;
  -- Spec 2 W1 final fix (M-4, PF-F6): only the missing key refuses; any
  -- Spec 2 W1 final fix other carry failure is counted and the deletion goes
  -- Spec 2 W1 final fix on (the auth.users trigger carries again at the
  -- Spec 2 W1 final fix delete, counting late_carry_failed if that fails too).
  BEGIN -- Spec 2 W1 final fix (M-4)
    PERFORM private.dating_deletion_carry(p_user_id, false);
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W1 final fix (M-4)
    RAISE WARNING 'dating_deletion:carry:%', SQLSTATE; -- Spec 2 W1 final fix (M-4)
    PERFORM private.bump_metric_internal('dating.deletion.prepare_carry_failed'); -- Spec 2 W1 final fix (M-4)
  END; -- Spec 2 W1 final fix (M-4)
  -- Spec 1 W9d (O4): the Opinions strike count and live ban carry under
  -- Spec 1 W9d the HMACs stamped when they were placed. Never refuses
  -- Spec 1 W9d (PF-F6); the auth.users trigger carries again at the delete.
  BEGIN -- Spec 1 W9d
    PERFORM private.opinion_deletion_carry(p_user_id, false); -- Spec 1 W9d
  EXCEPTION WHEN OTHERS THEN -- Spec 1 W9d
    RAISE WARNING 'opinion_deletion:carry:%', SQLSTATE; -- Spec 1 W9d
    PERFORM private.bump_metric_internal('opinions.deletion.prepare_carry_failed'); -- Spec 1 W9d
  END; -- Spec 1 W9d
  -- 3. Matches close (account_deleted) and stay sealed for 30 days; the
  --    cascade sets their member ids to NULL (and its trigger seals any
  --    match this step missed, so a failure here warns and counts).
  -- Spec 2 W6a (final server fix, I-5): the match rows first, then the signals (send's
  -- Spec 2 W6a lock order), so a send never deadlocks this step; a lock conflict is
  -- Spec 2 W6a retried, and after the third the deletion refuses (dating:busy, the app
  -- Spec 2 W6a retries) instead of skipping the close and the other person's notice.
  FOR v_try IN 1..3 LOOP -- Spec 2 W6a (final server fix, I-5)
  BEGIN
    SELECT coalesce(pg_catalog.array_agg(x.id), '{}'::uuid[]) INTO v_closed -- Spec 2 W6a (final server fix, I-5)
      FROM (SELECT m.id FROM public.dating_matches AS m -- Spec 2 W6a
             WHERE p_user_id IN (m.user_low_id, m.user_high_id) AND m.state = 'active' -- Spec 2 W6a
               FOR NO KEY UPDATE OF m) AS x; -- Spec 2 W6a
    UPDATE public.dating_matches AS m
       SET state = CASE WHEN m.state = 'active' THEN 'closed' ELSE m.state END,
           closed_reason = CASE WHEN m.state = 'active' THEN 'account_deleted' ELSE m.closed_reason END,
           closed_at = coalesce(m.closed_at, now()),
           evidence_until = CASE WHEN m.state = 'active' OR m.evidence_until IS NULL
                                 THEN now() + interval '30 days' ELSE m.evidence_until END
     WHERE p_user_id IN (m.user_low_id, m.user_high_id);
    PERFORM private.dating_bump_chat(CASE WHEN m.user_low_id = p_user_id THEN m.user_high_id ELSE m.user_low_id END, m.id) -- Spec 2 W6a (fix round 1, M-5)
       FROM public.dating_matches AS m WHERE m.id = ANY (v_closed); -- Spec 2 W6a (final server fix, I-5): after the close
    EXIT; -- Spec 2 W6a (final server fix, I-5)
  EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W6a (final server fix, I-5)
    IF v_try = 3 THEN -- Spec 2 W6a
      RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; -- Spec 2 W6a: never a skipped close
    END IF; -- Spec 2 W6a
  WHEN OTHERS THEN -- Spec 2 W6a (final server fix, I-5): any other error, as before
    RAISE WARNING 'dating_deletion:matches:%', SQLSTATE;
    PERFORM private.bump_metric_internal('dating.deletion.step_failed.matches');
    EXIT; -- Spec 2 W6a (final server fix, I-5)
  END;
  END LOOP; -- Spec 2 W6a (final server fix, I-5)
  -- 5. The cascade removes everything else (profile, photos via the media
  --    queue below, introductions, the never-introduce list, ...).

  FOR v_rel IN
    SELECT r.id, r.status FROM public.relationships r
    WHERE p_user_id IN (r.user_a, r.user_b)
    FOR UPDATE
  LOOP
    IF v_rel.status IN ('active', 'paused') THEN
      PERFORM public.relationship_end_internal(v_rel.id, p_user_id);
    ELSIF v_rel.status = 'pending' THEN
      DELETE FROM public.relationships WHERE id = v_rel.id;
      CONTINUE;
    END IF;

    -- What carries the person's answers or profile and cannot be split by
    -- person: games (positional answer_a/answer_b; rounds, per-user answers,
    -- Love map rounds and mirror truth go with them), 36-question journeys
    -- (AI text about the pair), the analysis sessions' role attribution, the
    -- profile-derived compatibility card. The partner's own game answers go
    -- with the shared sessions (D.3 #1 over D.2; review I1). Pulse,
    -- verdicts and patterns stay: role-free, both already saw them, the
    -- partner may export them in the window; the 12-month purge removes them.
    DELETE FROM public.game_sessions WHERE relationship_id = v_rel.id;
    DELETE FROM public.game_session_rounds WHERE relationship_id = v_rel.id;
    DELETE FROM public.thirty_six_question_journeys WHERE relationship_id = v_rel.id;
    DELETE FROM public.thirty_six_questions_seen WHERE relationship_id = v_rel.id;
    DELETE FROM public.game_questions_seen WHERE relationship_id = v_rel.id;
    DELETE FROM public.analysis_sessions WHERE relationship_id = v_rel.id;
    DELETE FROM public.attachment_compatibility_cache WHERE relationship_id = v_rel.id;
    DELETE FROM public.ask2_state WHERE relationship_id = v_rel.id;
  END LOOP;

  -- The person's own media. Their messages, clips and dating photos go in
  -- the cascade; queue now so nothing depends on trigger order there.
  PERFORM public.queue_media_deletion('message-media', m.media_url),
          public.queue_media_deletion('message-media', m.media_thumbnail_url)
  FROM public.messages m WHERE m.sender_id = p_user_id;
  PERFORM public.queue_media_deletion('message-media', c.media_url)
  FROM public.streak_clips c JOIN public.messages m ON m.id = c.message_id
  WHERE m.sender_id = p_user_id;
  PERFORM public.queue_media_deletion('dating-profile-photos', p.storage_key)
  FROM public.dating_profile_photos p WHERE p.user_id = p_user_id -- Spec 2 W3c (Task 9 fix round 1, I-1)
    AND p.csam_state IS DISTINCT FROM 'hit'; -- Spec 2 W3c (Task 9 fix round 1, I-1): a hit's object is Spec 1's
  -- Uploads never attached to anything: no row names them (review I5).
  PERFORM public.queue_media_deletion('message-media', i.storage_key)
  FROM public.message_media_upload_intents i WHERE i.requester_id = p_user_id;
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
  FROM public.dating_photo_upload_intents i WHERE i.user_id = p_user_id -- Spec 2 W3c (Task 9 fix round 1, I-1)
    AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f -- Spec 2 W3c (Task 9 fix round 1, I-1)
                     WHERE f.storage_key = i.storage_key AND f.csam_state = 'hit'); -- Spec 2 W3c (Task 9 fix round 1, I-1)
  PERFORM public.queue_media_deletion('story-media', i.storage_key)
  FROM public.story_media_upload_intents i WHERE i.requester_id = p_user_id;
  PERFORM public.queue_media_deletion('relationship-avatars', i.storage_key)
  FROM public.relationship_avatar_upload_intents i WHERE i.requester_id = p_user_id;
  -- Their downloads (Spec 3c; data_export_jobs is created in 20261018120000,
  -- resolved when this runs): every part of every job goes now, then the jobs.
  IF to_regclass('public.data_export_jobs') IS NOT NULL THEN
    EXECUTE $q$
      UPDATE public.media_deletion_queue q SET not_before = now(), deleted_at = NULL
      FROM public.data_export_jobs j
      WHERE j.user_id = $1 AND q.bucket_id = 'data-exports' AND q.object_name LIKE j.id::text || '/%'
    $q$ USING p_user_id;
    EXECUTE 'DELETE FROM public.data_export_jobs WHERE user_id = $1' USING p_user_id;
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------
-- 6. Gone: W5b's caption helper (the card masks now) and the two-argument
--    pair check (both callers read the marker through the four-argument
--    one).
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS private.dating_caption_has_contact(text);
DROP FUNCTION IF EXISTS private.dating_pair_new(uuid, uuid);
-- Task 2 fix round 1 (M-8): first messages take the run's time.
DROP FUNCTION IF EXISTS private.dating_first_messages(uuid, timestamptz);

-- ---------------------------------------------------------------------
-- 7. Final server fix (I-2): a split push fails closed. Every object this
--    migration creates is revoked here, in its own transaction, from
--    PUBLIC, anon, authenticated and the service role (the hosted project
--    grants new objects to all of them by default); its twin
--    (20261120100010) then grants what the app is meant to have. A
--    function re-created from its live body keeps its grants (CREATE OR
--    REPLACE) and is left to the twin.
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE public.dating_pair_markers, public.dating_messages, public.dating_chat_signals
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  private.dating_mask_fold(text), private.dating_mask_leet(text, text), private.dating_mask_digits(text),
  private.dating_mask_contacts(text), private.dating_mask_contacts_safe(text), private.dating_mask_fallback(text),
  private.dating_mask_counted(text), private.dating_caption_invites(text), private.dating_photo_caption_mask(),
  private.dating_pair_code(text, text), private.dating_pair_code(text, text, text), private.dating_mark_pair(uuid, uuid),
  private.dating_pair_new(uuid, uuid, text, text), private.dating_pair_new(uuid, uuid, text, text, text),
  private.dating_backfill_pair_markers(), private.dating_bump_chat(uuid, uuid), private.dating_pair_blocked(uuid, uuid),
  private.dating_body_blank(text), private.dating_chat_on(), private.dating_message_json(public.dating_messages, text, boolean),
  private.dating_key_ok(text), private.dating_chat_header(public.dating_matches, text), private.dating_swap_write(uuid, boolean),
  private.dating_first_messages(uuid, timestamptz, timestamptz), private.dating_matches_seal_window(),
  public.dating_can_send(uuid), public.send_dating_message(text, uuid, text, text, text),
  public.get_dating_messages(uuid, timestamptz, integer), public.get_my_dating_matches(boolean),
  public.offer_dating_contact_swap(uuid), public.withdraw_dating_contact_swap(uuid),
  public.block_dating_match(text, uuid), public.unmatch_dating_match(text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

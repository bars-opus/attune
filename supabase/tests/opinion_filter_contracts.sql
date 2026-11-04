-- supabase/tests/opinion_filter_contracts.sql
-- Spec 1 W9a (§4.2, §4.3 W9a, §7.1, §7.4): the shared normaliser and the
-- pre-post content filter. The shared goldens and the fold table go
-- through the SQL forms; the verdict blocks contact details and the term
-- lists and lets ordinary posts through; a draft term never matches
-- outside development; each of the six Opinion writers refuses with
-- content:contact_info / content:slur / content:explicit while
-- opinions_safety_v1 is on, and allows everything while it is off; with
-- the flag off each writer is its pre-W9 body plus one line that does
-- nothing (owner ruling 2026-11-04: byte-for-byte unchanged).
-- Every code point (not only the goldens) is checked against the TS port
-- by opinion_filter_parity_contracts.sql.
-- (W9b appends section G: the at-risk reason and review queue v0.)
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a, from the repo root
-- (the two JSON files are read with \set):
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_filter_contracts.sql
-- Fixture ids 5f9a0000-0000-0000-0000-0000000000NN, phones +155586000NN
-- (spec §7.1's W9 range) on auth.users and public.users. Fixture terms are
-- invented placeholders, not real slurs. Every refusal is checked by its
-- message.
\set goldens `cat supabase/tests/fixtures/unicode_normaliser_goldens.json`
\set fold `cat supabase/functions/_shared/unicode_fold_table.json`
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f9a0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- The message raised by [p_sql] run as [p_user] (NULL when it ran).
CREATE FUNCTION pg_temp.err_as(p_user uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- The message and the HINT raised by [p_sql] run as [p_user] (NULL when
-- it ran); a missing HINT reads "-".
CREATE FUNCTION pg_temp.hint_as(p_user uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
  v_hint text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    v := SQLERRM || ' hint=' || coalesce(nullif(v_hint, ''), '-');
  END;
  RESET ROLE;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.flag(p_on boolean) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.feature_flags (key, enabled) VALUES ('opinions_safety_v1', p_on)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
$$;

-- plpgsql, so the file reaches section A before the migration exists.
CREATE FUNCTION pg_temp.verdict(p_text text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN private.content_filter_verdict(p_text, NULL);
END $$;

-- Fixtures: seven people (one for the refusals and edits, one who wrote
-- the post others comment on, five who each post once, because a post
-- starts a 60-second cooldown).
INSERT INTO auth.users (id, phone)
SELECT pg_temp.id(n), '155586000' || n FROM unnest(ARRAY['01', '02', '03', '04', '05', '06', '07']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name)
SELECT pg_temp.id(n), '+155586000' || n, 'W9a ' || n FROM unnest(ARRAY['01', '02', '03', '04', '05', '06', '07']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id)
SELECT pg_temp.id(n) FROM unnest(ARRAY['01', '02', '03', '04', '05', '06', '07']) AS n
ON CONFLICT (id) DO NOTHING;
-- Only the fixture terms below: whatever the scratch database holds is set
-- aside (rolled back with the rest).
DO $$
BEGIN
  IF to_regclass('private.content_filter_terms') IS NOT NULL THEN
    DELETE FROM private.content_filter_terms;
  END IF;
END $$;

-- =====================================================================
-- A. Objects and grants: the filter is the database's own; the writers
--    keep their grants (signed-in only).
-- =====================================================================
DO $$
DECLARE
  v_sig text;
BEGIN
  IF to_regclass('private.content_filter_terms') IS NULL
     OR to_regprocedure('private.normalize_for_filter(text)') IS NULL
     OR to_regprocedure('private.match_form(text)') IS NULL
     OR to_regprocedure('private.digits_from_words(text)') IS NULL
     OR to_regprocedure('private.has_contact_info(text)') IS NULL
     OR to_regprocedure('private.content_filter_verdict(text,text[])') IS NULL
     OR to_regprocedure('private.assert_opinion_content_ok(text)') IS NULL
     OR to_regprocedure('private.mask_number_shapes(text)') IS NULL
     OR to_regprocedure('private.assert_poll_options_ok(text[])') IS NULL
     OR to_regprocedure('private.assert_part_content_ok(text,text)') IS NULL
     OR to_regprocedure('private.assert_comment_content_ok(text,text)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W9a objects are missing';
  END IF;
  IF has_table_privilege('authenticated', 'private.content_filter_terms', 'SELECT')
     OR has_table_privilege('service_role', 'private.content_filter_terms', 'SELECT')
     OR has_table_privilege('anon', 'private.content_filter_terms', 'SELECT')
     OR has_sequence_privilege('authenticated', 'private.content_filter_terms_id_seq', 'USAGE')
     OR has_sequence_privilege('service_role', 'private.content_filter_terms_id_seq', 'USAGE')
     OR has_sequence_privilege('anon', 'private.content_filter_terms_id_seq', 'USAGE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the term lists must have no grants';
  END IF;
  FOREACH v_sig IN ARRAY ARRAY['private.normalize_for_filter(text)', 'private.match_form(text)',
    'private.digits_from_words(text)', 'private.has_contact_info(text)',
    'private.content_filter_verdict(text,text[])', 'private.assert_opinion_content_ok(text)',
    'private.mask_number_shapes(text)', 'private.assert_poll_options_ok(text[])',
    'private.assert_part_content_ok(text,text)', 'private.assert_comment_content_ok(text,text)'] LOOP
    IF has_function_privilege('authenticated', v_sig, 'EXECUTE')
       OR has_function_privilege('anon', v_sig, 'EXECUTE')
       OR has_function_privilege('service_role', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % must have no grants', v_sig;
    END IF;
  END LOOP;
  -- None of them can write: with the flag off the writers' one added line
  -- (the assert) changes nothing.
  IF EXISTS (SELECT 1 FROM pg_proc
              WHERE oid IN (to_regprocedure('private.normalize_for_filter(text)'), to_regprocedure('private.match_form(text)'),
                            to_regprocedure('private.digits_from_words(text)'), to_regprocedure('private.has_contact_info(text)'),
                            to_regprocedure('private.content_filter_verdict(text,text[])'), to_regprocedure('private.assert_opinion_content_ok(text)'),
                            to_regprocedure('private.mask_number_shapes(text)'), to_regprocedure('private.assert_poll_options_ok(text[])'),
                            to_regprocedure('private.assert_part_content_ok(text,text)'), to_regprocedure('private.assert_comment_content_ok(text,text)'))
                AND provolatile = 'v') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a filter function is VOLATILE';
  END IF;
  FOREACH v_sig IN ARRAY ARRAY['public.create_opinion(text)', 'public.create_opinion_with_poll(text,text[])',
    'public.create_opinion_with_quote(text,uuid)', 'public.edit_opinion(uuid,text)',
    'public.create_opinion_comment(uuid,text,uuid,text)', 'public.edit_opinion_comment(uuid,text)'] LOOP
    IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE')
       OR has_function_privilege('anon', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % lost its grants (signed-in only)', v_sig;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- B. All the shared goldens (73 at fold table 2026-11-04.5) give the same
--    base and match forms here as in the TypeScript port (spec §7.1,
--    review I-17), and the match form is idempotent: a stored term is its
--    own match form (content_filter_terms_term_check relies on it).
-- =====================================================================
CREATE TEMP TABLE w9a_goldens ON COMMIT DROP AS
SELECT c->>'name' AS name, c->>'input' AS input, c->>'base' AS base, c->>'match' AS match
  FROM jsonb_array_elements((:'goldens'::jsonb)->'cases') AS c;

DO $$
DECLARE
  r record;
BEGIN
  IF (SELECT count(*) FROM w9a_goldens) < 73 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the goldens file lost cases';
  END IF;
  FOR r IN SELECT * FROM w9a_goldens ORDER BY name LOOP
    IF private.normalize_for_filter(r.input) IS DISTINCT FROM r.base THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: golden % base form is "%", expected "%"',
        r.name, private.normalize_for_filter(r.input), r.base;
    END IF;
    IF private.match_form(r.input) IS DISTINCT FROM r.match THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: golden % match form is "%", expected "%"',
        r.name, private.match_form(r.input), r.match;
    END IF;
    IF private.match_form(private.match_form(r.input)) IS DISTINCT FROM private.match_form(r.input)
       OR private.match_form(r.match) IS DISTINCT FROM r.match THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: golden % match form is not idempotent ("%")',
        r.name, private.match_form(private.match_form(r.input));
    END IF;
    IF private.normalize_for_filter(r.base) IS DISTINCT FROM r.base THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: golden % base form is not idempotent ("%")',
        r.name, private.normalize_for_filter(r.base);
    END IF;
  END LOOP;
  IF private.normalize_for_filter(NULL) IS NOT NULL OR private.match_form(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: NULL text did not stay NULL';
  END IF;
END $$;

-- =====================================================================
-- C. The migration's translate() strings equal the fold table: every
--    entry does what the table says (match.strip_marks included), and
--    nothing outside the table changes in the swept blocks (Latin-1 to
--    Cyrillic, General Punctuation, CJK punctuation).
-- =====================================================================
CREATE TEMP TABLE w9a_fold ON COMMIT DROP AS SELECT :'fold'::jsonb AS t;

DO $$
DECLARE
  t constant jsonb := (SELECT w9a_fold.t FROM w9a_fold);
  c text;
  i int;
  v_from text;
  v_to text;
  v_listed text;
  v_cp int;
BEGIN
  FOR c IN SELECT regexp_split_to_table(t #>> '{base,remove}', '') LOOP
    IF private.normalize_for_filter('a' || c || 'b') <> 'ab' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table base.remove U+% is not removed', to_hex(ascii(c));
    END IF;
  END LOOP;
  FOREACH v_from IN ARRAY ARRAY['confusables', 'digits'] LOOP
    v_to := t #>> ARRAY['base', v_from, 'to'];
    FOR i IN 1 .. char_length(t #>> ARRAY['base', v_from, 'from']) LOOP
      c := substr(t #>> ARRAY['base', v_from, 'from'], i, 1);
      IF private.normalize_for_filter('x' || c || 'x') <> 'x' || substr(v_to, i, 1) || 'x' THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: fold table base.% U+% is not folded to %', v_from, to_hex(ascii(c)), substr(v_to, i, 1);
      END IF;
    END LOOP;
  END LOOP;
  FOR c IN SELECT regexp_split_to_table(t #>> '{base,separators}', '') LOOP
    CONTINUE WHEN normalize('a' || c || 'b', NFKC) <> 'a' || c || 'b';  -- NFKC turns it into a kept dot first
    IF private.normalize_for_filter('a' || c || 'b') <> 'a b' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table base.separators U+% is not a separator', to_hex(ascii(c));
    END IF;
  END LOOP;
  FOR c IN SELECT regexp_split_to_table(t #>> '{base,kept}', '') LOOP
    IF private.normalize_for_filter('a' || c || 'b') <> 'a' || c || 'b' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table base.kept % is not kept', c;
    END IF;
  END LOOP;
  FOREACH v_from IN ARRAY ARRAY['west_african', 'leet'] LOOP
    v_to := t #>> ARRAY['match', v_from, 'to'];
    FOR i IN 1 .. char_length(t #>> ARRAY['match', v_from, 'from']) LOOP
      c := substr(t #>> ARRAY['match', v_from, 'from'], i, 1);
      IF private.match_form('x' || c || 'x') <> 'x' || substr(v_to, i, 1) || 'x' THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: fold table match.% % is not folded to %', v_from, c, substr(v_to, i, 1);
      END IF;
    END LOOP;
  END LOOP;
  FOR c, v_to IN SELECT key, value FROM jsonb_each_text(t #> '{match,west_african,multi}') LOOP
    IF private.match_form('x' || c || 'x') <> 'x' || v_to || 'x' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table match.west_african.multi % is not folded to %', c, v_to;
    END IF;
  END LOOP;
  FOR i IN 1 .. char_length(t #>> '{base,compat_pins,from}') LOOP
    c := substr(t #>> '{base,compat_pins,from}', i, 1);
    IF private.normalize_for_filter('x' || c || 'x') <> 'x' || substr(t #>> '{base,compat_pins,to}', i, 1) || 'x' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table base.compat_pins U+% is not pinned', to_hex(ascii(c));
    END IF;
  END LOOP;
  FOR i IN 1 .. char_length(t #>> '{match,between_ascii_letters,from}') LOOP
    c := substr(t #>> '{match,between_ascii_letters,from}', i, 1);
    IF private.match_form('x' || c || 'x') <> 'x' || substr(t #>> '{match,between_ascii_letters,to}', i, 1) || 'x'
       OR private.match_form('x' || c || ' x') <> 'x x' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table match.between_ascii_letters % is not folded between letters only', c;
    END IF;
  END LOOP;
  -- Every Default_Ignorable_Code_Point, assigned or not, and the
  -- interlinear annotation controls, are removed (batch-2 review I-3,
  -- re-review N-1).
  FOR v_cp IN SELECT g FROM (VALUES (173, 173), (847, 847), (1564, 1564), (4447, 4448), (6068, 6069), (6155, 6159),
                                    (8203, 8207), (8234, 8238), (8288, 8292), (8294, 8303), (12644, 12644),
                                    (8293, 8293), (65024, 65039), (65279, 65279), (65440, 65440), (65520, 65528),
                                    (65529, 65531), (113824, 113827), (119155, 119162), (917504, 921599)) AS r(a, z),
                          generate_series(r.a, r.z) AS g LOOP
    IF private.normalize_for_filter('a' || chr(v_cp) || 'b') <> 'ab' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: default-ignorable U+% is not removed', to_hex(v_cp);
    END IF;
  END LOOP;
  FOR c IN SELECT regexp_split_to_table(t #>> '{match,strip_marks}', '') LOOP
    IF private.match_form('x' || c || 'x') <> 'xx' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table match.strip_marks U+% is not dropped', to_hex(ascii(c));
    END IF;
  END LOOP;
  FOR c IN SELECT regexp_split_to_table(t #>> '{match,separators}', '') LOOP
    IF private.match_form('a' || c || 'b') <> 'a b' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table match.separators % is not a separator', c;
    END IF;
  END LOOP;
  -- Nothing the table doesn't list is changed (beyond NFKC and lower case).
  v_listed := (t #>> '{base,compat_pins,from}') || (t #>> '{base,remove}') || (t #>> '{base,confusables,from}') || (t #>> '{base,digits,from}')
              || (t #>> '{base,separators}') || (t #>> '{base,kept}') || ' ';
  FOR v_cp IN SELECT g FROM generate_series(160, 1327) AS g
              UNION ALL SELECT g FROM generate_series(8192, 8303) AS g
              UNION ALL SELECT g FROM generate_series(12288, 12351) AS g LOOP
    c := chr(v_cp);
    CONTINUE WHEN strpos(v_listed, c) > 0;
    -- NFKC or lower case changes it (or composes it with its neighbours).
    CONTINUE WHEN lower(normalize('a' || c || 'b', NFKC) COLLATE "pg_c_utf8") <> 'a' || c || 'b';
    IF private.normalize_for_filter('a' || c || 'b') <> 'a' || c || 'b' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: U+% is changed by the base form but is not in the fold table', to_hex(v_cp);
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- D. Contact details: blocked in every listed shape; ordinary posts,
--    years, amounts and times pass (spec §4.3 W9a, §9).
-- =====================================================================
DO $$
DECLARE
  v text;
  r record;
BEGIN
  FOREACH v IN ARRAY ARRAY[
    'Call me on 024 412 3456',
    'my number is 0244123456',
    '+233 24 412 3456',
    '+44 7911 123456',
    '00233 24 412 3456',
    '233244123456',
    '(415) 555-0132',
    '415.555.0132',
    '4155550132',
    '+1 415 555 0132',
    '+81 3 1234 5678',
    '0803-123-4567',
    'zero two four four one two three four five six',
    'call oh two four four one two three four five six',
    '024 four one two three four five six',
    'four one five five five five zero one three two',
    'kofi.mensah@gmail.com',
    'write to kofi@school.de',
    'kofi at gmail dot com',
    'kofi (at) yahoo (dot) com',
    'kofi @ hotmail . co . uk',
    'http://example.org',
    'see https://kofi.de/home',
    'see www.mysite.net',
    'www.kofi.de',
    'wa.me/233244123456',
    'wa.me/kofi',
    'come to t.me/kofi',
    'bit.ly/abc123',
    'rb.gy/abc',
    'my site is kofi.com',
    'follow @kofi_99',
    'IG: kofi.99',
    'snap @ kofimensah',
    'snap: kofi_99',
    'signal: kofi.m',
    'threads:kofi99',
    'telegram:kofi',
    -- batch-2 review I-1: phone shapes that stay blocked with the
    -- number-shape mask and the tail rule.
    '0-2-4-4-1-2-3-4-5-6',
    '02.44.12.34.56',
    '06 12 34 56 78',
    '024-412-3456',
    '024.412.3456',
    '+233-24-412-3456',
    '233 24 412 3456',
    '27 82 123 4567',
    '44 7911 123456',
    '86 138 0013 8000',
    -- review M-1: not years; not thousands; a + run past 15 digits.
    '0244 1234 5678',
    '233 244 12 34 56',
    '0 000 000 000',
    '+233 24 412 3456 0000000',
    -- review M-3: the other dots; M-4: a real handle that starts like a
    -- stop word.
    U&'kofi\FF20gmail\3002com',
    U&'see www\06D4kofi\06D4com',
    U&'see www\FF61kofi\FF61de',
    '@allison99',
    -- W9 final I-1: a handle that starts like a time is still a handle
    '@5pmkofi',
    '@1pm.kofi',
    '@10am10',
    '@5pm_',
    '@12am.x',
    '@123456',
    'add me @kofi',
    -- W9 final re-review N-2: a time-shaped handle after a platform name
    'ig: @5pm',
    'ig:@5pm',
    'insta: @10am',
    'tiktok: @7pm',
    'telegram: @10am',
    'whatsapp: @7pm',
    'snap: @5pm',
    'snap:@7pm',
    U&'\0660\0662\0664\0664\0661\0662\0663\0664\0665\0666'
  ] LOOP
    IF pg_temp.verdict(v) IS DISTINCT FROM 'contact_info' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: contact details were not caught: "%" gave %', v, pg_temp.verdict(v);
    END IF;
  END LOOP;
  FOREACH v IN ARRAY ARRAY[
    '1999 2004 2010',
    'We met in 1999, broke up in 2004 and got back together in 2010.',
    'I paid 250 000 000 naira for the land',
    'A bridge costs 4 400 000 000 000',
    U&'He wants GH\20B5 2,500,000,000 for the house',
    'Es ist 10.000.000 Euro',
    'Meet me at 7:30pm on 12/05/2024',
    '2024/05/12 13:30',
    'Final scores: 2-0 1-1 0-3 2-2 1-0',
    'I was born in 1990. 2001 was hard',
    'one or two times a week, maybe three',
    'Mr.Mensah said hi.Thanks',
    'I am at home, not @ work',
    'Oh no, oh well',
    -- Plan PF-C4 (pre-flight scan C-4): counts, score lists and platform
    -- names that are English words.
    '1 2 3 4 5 6 7 8 9 10',
    '1-0 2-1 3-3 0-0 2-2 1-1',
    'Red flag signal: jealousy',
    'common threads: trust',
    'oh snap: forgot',
    'signal: 5 bars, threads: 2024 edition',
    -- batch-2 review I-1: dates with times, score lists that start with 0,
    -- lotto and number lists.
    'Meet me 12/05/2024 13.30',
    'On 27/05/2024 13.30 at Osu',
    '12.05.2024 13.30',
    '12-05-2024 13.30',
    'See you 05/06/2024 10am',
    'We met on 01/02/1990 10:30',
    'Results 0-1 2-0 1-1 3-2 0-0',
    'Final scores: 0-0 1-1 2-2 3-1 0-2',
    'Lotto numbers 3 12 25 33 41 49',
    'Bingo: 10 20 30 40 50 60',
    'ages 18 25 30 35 40 45',
    'Score 100 98 97 96 95',
    'Born 01/02/1990',
    'Buses at 07.30 08.15 09.45',
    U&'Results 2\20131 3\20140 1 \2013 1 0-0 2-2',
    -- a count that ends in a 3-digit group (plan PF-C4's inner-group rule)
    'Room numbers 1 2 3 4 5 6 7 8 9 101',
    -- re-review N-2: price lists and lists that start with a calling code
    'my rent went 1200 1500 1800 over three years',
    'prices 1500 2000 2500',
    'prices 150 200 250 3000',
    '1200/1500/1800',
    'Bingo 10 20 30 40 50 100',
    '12/25/2024 1030',
    'Team scores 44 12 10 15 22 18',
    -- the year, thousands and 15-digit exemptions, each where another rule
    -- would otherwise fire
    'Moves: 1999, 2004 and +2015 2020 2024',
    'He paid 44 000 000 000 naira',
    'Order ref 1234567890123456',
    -- review M-1: 8 digits from 0; 16 digits with no +; no TLD; 2-letter @
    'Ticket 0123 4567',
    'Ref 1234 5678 9012 3456',
    'a@b.c',
    'hi @op',
    -- review M-4: forum talk
    'Hey @everyone, what do you think?',
    'thanks @all and @here, ask the @admin or @mods',
    -- W9 final I-1: "@" read as "at" before a time, with no space
    'meet me @5pm at the mall',
    'dinner @10am tomorrow',
    '@7pm',
    '@5pm',
    '@10am',
    '@ 9',
    'see you @ 5pm',
    'dinner @5pm.',
    'lunch @12pm, then home',
    'call @11am!',
    'church @9 a.m.',
    'meet @7p.m. ok',
    'meet @6:30pm',
    'Meet @1.15 pm'
  ] LOOP
    IF pg_temp.verdict(v) IS NOT NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary post was blocked: "%" gave %', v, pg_temp.verdict(v);
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM w9a_goldens WHERE name LIKE 'ordinary_%' OR name LIKE 'twi_%' LOOP
    IF pg_temp.verdict(r.input) IS NOT NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: ordinary golden % was blocked (%)', r.name, pg_temp.verdict(r.input);
    END IF;
  END LOOP;
  IF private.content_filter_verdict('call 0244123456', ARRAY['slur', 'explicit']) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a family that was not asked for was checked';
  END IF;
END $$;

-- =====================================================================
-- E. Term lists: token and squashed matching in the match form; a Twi
--    term typed with e-open/o-open or with e/o; local number words; draft
--    terms and draft number words only in development (plan P-6).
--    Placeholder terms only.
-- =====================================================================
INSERT INTO private.content_filter_terms (family, term, match_mode, locale, source, review_ref) VALUES
  ('slur', private.match_form(U&'k\0254k\0254\0254'), 'token', 'tw', 'reviewed', 'contract fixture'),
  ('explicit', private.match_form('blorpington'), 'squashed', 'en', 'reviewed', 'contract fixture'),
  ('explicit', private.match_form('zzdraftword'), 'token', 'en', 'draft', NULL);
INSERT INTO private.content_filter_terms (family, term, digit, locale, source, review_ref) VALUES
  ('number_word', private.match_form('fixturetwo'), '2', 'tw', 'reviewed', 'contract fixture'),
  ('number_word', private.match_form('fixturethree'), '3', 'tw', 'draft', NULL);
INSERT INTO private.content_filter_terms (family, term, digit, locale, source, review_ref, active) VALUES
  ('number_word', private.match_form('fixturefour'), '4', 'tw', 'reviewed', 'contract fixture', false);

DO $$
DECLARE
  v_msg text;
  v_t0 timestamptz;
  v_calls bigint;
BEGIN
  IF pg_temp.verdict(U&'He called me k\0254k\0254\0254 again') IS DISTINCT FROM 'slur'
     OR pg_temp.verdict('He called me KOKOO again') IS DISTINCT FROM 'slur'
     OR pg_temp.verdict('He called me k0k00 again') IS DISTINCT FROM 'slur' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Twi term did not match typed with and without its letters';
  END IF;
  IF pg_temp.verdict('kokoos are red') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a token term matched inside another word';
  END IF;
  IF pg_temp.verdict('b l o r p i n g t o n') IS DISTINCT FROM 'explicit'
     OR pg_temp.verdict(U&'blorp\200Bington') IS DISTINCT FROM 'explicit'
     OR pg_temp.verdict('xblorpingtonx') IS DISTINCT FROM 'explicit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a squashed term was not matched across separators';
  END IF;
  IF pg_temp.verdict('a zzdraftword here') IS DISTINCT FROM 'explicit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft term did not match in development';
  END IF;
  IF pg_temp.verdict('024 fixturetwo four four one two three four five six') IS DISTINCT FROM 'contact_info'
     OR private.digits_from_words('fixturetwo') <> '2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewed local number word was not read as a digit';
  END IF;
  IF private.digits_from_words('fixturethree') <> '3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft local number word was not read in development';
  END IF;
  -- Production: draft terms are inert; reviewed terms still match.
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF pg_temp.verdict('a zzdraftword here') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft term matched outside development';
  END IF;
  IF private.digits_from_words('fixturethree') <> 'fixturethree'
     OR private.digits_from_words('fixturetwo') <> '2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft local number word was read outside development (or a reviewed one was not)';
  END IF;
  IF pg_temp.verdict('He called me kokoo again') IS DISTINCT FROM 'slur' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewed term stopped matching in production';
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  -- With no active number word, English digit words are still read (the
  -- plan PF-C11 short-cut skips only the term lookups).
  UPDATE private.content_filter_terms SET active = false WHERE family = 'number_word';
  IF private.digits_from_words('call zero two four fixturetwo') <> 'call 024 fixturetwo' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: digit words were not read with no number word loaded (%)',
      private.digits_from_words('call zero two four fixturetwo');
  END IF;
  UPDATE private.content_filter_terms SET active = true WHERE family = 'number_word' AND term <> 'fixturefour';
  -- An inactive term never matches: the operator's switch for a false
  -- positive (batch-2 review M-1).
  -- A leet-typed number word still reads (the a-z short-cut is exact).
  IF private.digits_from_words('call f1xturetwo') <> 'call 2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a leet-typed local number word was not read (%)', private.digits_from_words('call f1xturetwo');
  END IF;
  IF private.digits_from_words('fixturefour fixturetwo') <> 'fixturefour 2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inactive local number word was read (%)', private.digits_from_words('fixturefour fixturetwo');
  END IF;
  UPDATE private.content_filter_terms SET active = false WHERE family = 'slur';
  IF pg_temp.verdict('He called me kokoo again') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deactivated term still matched';
  END IF;
  UPDATE private.content_filter_terms SET active = true WHERE family = 'slur';
  -- One number-word lookup per distinct token (batch-2 review I-5): a
  -- 5000-character post with a number word loaded gets its verdict fast.
  PERFORM pg_temp.verdict(repeat('we met at the market and talked ', 160));
  v_t0 := clock_timestamp();
  IF pg_temp.verdict(repeat('we met at the market and talked ', 160)) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the long ordinary post was blocked';
  END IF;
  -- A 2 s backstop only (batch-4 fix round 1, I-3: a tight wall-clock
  -- bound failed under load); the call count below pins the behaviour.
  IF clock_timestamp() - v_t0 > interval '2 seconds' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 5000-character verdict with a number word loaded took %', clock_timestamp() - v_t0;
  END IF;
  -- And deterministically: match_form runs once per distinct token that
  -- is not plain a-z, never once per token (function call counts; needs a
  -- superuser to switch track_functions on, as on attune_spec3a).
  BEGIN
    PERFORM set_config('track_functions', 'pl', true);
    v_calls := coalesce((SELECT calls FROM pg_stat_xact_user_functions WHERE funcid = 'private.match_form(text)'::regprocedure), 0);
    PERFORM private.digits_from_words(repeat(U&'\025B \0254 ', 1000) || 'fixturetwo');
    v_calls := coalesce((SELECT calls FROM pg_stat_xact_user_functions WHERE funcid = 'private.match_form(text)'::regprocedure), 0) - v_calls;
    IF v_calls <> 2 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the number-word lookup ran match_form % times for 2 distinct non-a-z tokens', v_calls;
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'opinion_filter_contracts: track_functions needs a superuser; the call-count check was skipped';
  END;
  -- A term must be stored in the match form; a reviewed one names its review.
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, source) VALUES ('slur', U&'K\0254k\0254', 'draft');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a term not in the match form was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_term_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, source) VALUES ('slur', 'unreviewed', 'reviewed');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewed term without its review was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_reviewed_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
  -- Number words: never squashed; a digit if and only if a number word;
  -- a term is at most 80 characters (batch-2 review M-1).
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, match_mode, digit, source) VALUES ('number_word', 'fixturesix', 'squashed', '6', 'draft');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a squashed number word was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_squashed_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, source) VALUES ('number_word', 'fixtureseven', 'draft');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a number word without its digit was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_digit_family_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, digit, source) VALUES ('slur', 'fixtureeight', '8', 'draft');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a slur with a digit was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_digit_family_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, source) VALUES ('slur', repeat('z', 81), 'draft');
    RAISE EXCEPTION 'CONTRACT VIOLATED: an 81-character term was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_term_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, match_mode, source) VALUES ('slur', 'abc', 'squashed', 'draft');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a short squashed term was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_squashed_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
END $$;

-- =====================================================================
-- F. The six writers (spec §4.3 W9a, §7.4): flag on, each refuses by
--    reason before anything is written; flag off, each allows the same
--    text.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.id('01');
  v_own_opinion uuid;
  v_own_comment uuid;
  v_target uuid;
  v_before int;
  v_case record;
  v_t0 timestamptz;
  v_calls bigint;
  v_ref interval;
  v_tracked boolean := true;
BEGIN
  INSERT INTO public.opinions (user_id, content) VALUES (pg_temp.id('04'), 'W9a contract: a post to comment on and quote.')
  RETURNING id INTO v_target;
  INSERT INTO public.opinions (user_id, content) VALUES (v_u, 'W9a contract: my own post, to edit.')
  RETURNING id INTO v_own_opinion;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content) VALUES (v_target, v_u, 'W9a contract: my own comment.')
  RETURNING id INTO v_own_comment;
  PERFORM pg_temp.flag(true);
  SELECT count(*) INTO v_before FROM public.opinions;

  FOR v_case IN
    SELECT * FROM (VALUES
      ('contact_info', 'Call me on 0244123456 tonight'),
      ('slur', 'He called me kokoo again'),
      ('explicit', 'She sent b l o r p i n g t o n')
    ) AS x(reason, body)
  LOOP
    IF pg_temp.err_as(v_u, format('SELECT public.create_opinion(%L)', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', ''No''])', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', %L])', 'W9a contract: an ordinary question?', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, v_target)) IS DISTINCT FROM 'content:' || v_case.reason
       -- before the target is looked up: an unknown target still gets the content reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, gen_random_uuid())) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.edit_opinion(%L, %L)', v_own_opinion, v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L)', v_target, v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, 'W9a contract: I agree.', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.edit_opinion_comment(%L, %L)', v_own_comment, v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a writer did not refuse % with content:% (create %, poll %, poll option %, quote %, quote unknown %, edit %, comment %, quoted text %, edit comment %)',
        v_case.body, v_case.reason,
        pg_temp.err_as(v_u, format('SELECT public.create_opinion(%L)', v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', ''No''])', v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', %L])', 'W9a contract: an ordinary question?', v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, v_target)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, gen_random_uuid())),
        pg_temp.err_as(v_u, format('SELECT public.edit_opinion(%L, %L)', v_own_opinion, v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L)', v_target, v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, 'W9a contract: I agree.', v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.edit_opinion_comment(%L, %L)', v_own_comment, v_case.body));
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.opinions) <> v_before
     OR (SELECT content FROM public.opinions WHERE id = v_own_opinion) <> 'W9a contract: my own post, to edit.'
     OR (SELECT count(*) FROM public.opinion_comments WHERE opinion_id = v_target) <> 1
     OR (SELECT content FROM public.opinion_comments WHERE id = v_own_comment) <> 'W9a contract: my own comment.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused post or edit still wrote something';
  END IF;
  -- Which part was refused (batch-3 review I-3): a reply's quoted text and
  -- a poll option say so in the HINT, so the app never blames the writer's
  -- own words; the writer's own text carries no HINT and is checked first.
  FOR v_case IN
    SELECT * FROM (VALUES
      ('contact_info', 'Call me on 0244123456 tonight'),
      ('slur', 'He called me kokoo again'),
      ('explicit', 'She sent b l o r p i n g t o n')
    ) AS x(reason, body)
  LOOP
    IF pg_temp.hint_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, 'W9a contract: I agree.', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason || ' hint=quoted_text'
       OR pg_temp.hint_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', %L])', 'W9a contract: an ordinary question?', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason || ' hint=poll_option'
       OR pg_temp.hint_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, v_case.body, 'wa.me/kofi')) IS DISTINCT FROM 'content:' || v_case.reason || ' hint=-'
       OR pg_temp.hint_as(v_u, format('SELECT public.create_opinion_comment(%L, %L)', v_target, v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason || ' hint=-'
       OR pg_temp.hint_as(v_u, format('SELECT public.create_opinion(%L)', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason || ' hint=-'
       OR pg_temp.hint_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', ''No''])', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason || ' hint=-'
       OR pg_temp.hint_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, v_target)) IS DISTINCT FROM 'content:' || v_case.reason || ' hint=-'
       OR pg_temp.hint_as(v_u, format('SELECT public.edit_opinion(%L, %L)', v_own_opinion, v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason || ' hint=-'
       OR pg_temp.hint_as(v_u, format('SELECT public.edit_opinion_comment(%L, %L)', v_own_comment, v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason || ' hint=-' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % was refused without naming the right part (quoted %, poll option %, own first %, comment %, create %, poll %, quote %, edit %, edit comment %)',
        v_case.body,
        pg_temp.hint_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, 'W9a contract: I agree.', v_case.body)),
        pg_temp.hint_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', %L])', 'W9a contract: an ordinary question?', v_case.body)),
        pg_temp.hint_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, v_case.body, 'wa.me/kofi')),
        pg_temp.hint_as(v_u, format('SELECT public.create_opinion_comment(%L, %L)', v_target, v_case.body)),
        pg_temp.hint_as(v_u, format('SELECT public.create_opinion(%L)', v_case.body)),
        pg_temp.hint_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', ''No''])', v_case.body)),
        pg_temp.hint_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, v_target)),
        pg_temp.hint_as(v_u, format('SELECT public.edit_opinion(%L, %L)', v_own_opinion, v_case.body)),
        pg_temp.hint_as(v_u, format('SELECT public.edit_opinion_comment(%L, %L)', v_own_comment, v_case.body));
    END IF;
  END LOOP;
  -- An over-long quoted text is the writers' own limit, not a filter
  -- refusal: no HINT.
  IF pg_temp.hint_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, repeat(''x'', 5001))', v_target, 'W9a contract: I agree.')) IS DISTINCT FROM 'invalid_content hint=-' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an over-long quoted text gave %',
      pg_temp.hint_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, repeat(''x'', 5001))', v_target, 'W9a contract: I agree.'));
  END IF;
  -- Over-long text, quoted text and poll options are refused before any
  -- scan, fast (batch-2 review I-4).
  FOR v_case IN
    SELECT * FROM (VALUES
      ('invalid_content', format('SELECT public.create_opinion_comment(%L, %L, NULL, repeat(''a b '', 262144))', v_target, 'W9a contract: I agree.'), 1),
      ('invalid_content', format('SELECT public.create_opinion_comment(%L, %L, NULL, repeat(''x'', 5001))', v_target, 'W9a contract: I agree.'), 1),
      ('invalid_content', format('SELECT public.create_opinion_with_quote(repeat(''a b '', 262144), %L)', v_target), 0),
      ('poll_option_too_long', 'SELECT public.create_opinion_with_poll(''W9a contract: a poll'', ARRAY[''Yes'', repeat(''a b '', 262144)])', 0),
      ('poll_option_count', 'SELECT public.create_opinion_with_poll(''W9a contract: a poll'', ARRAY[''a'', ''b'', ''c'', ''d'', ''Call me on 0244123456''])', 0),
      ('poll_option_count', 'SELECT public.create_opinion_with_poll(''W9a contract: a poll'', array_fill(''Call me on 0244123456''::text, ARRAY[20000]))', 0)
    ) AS x(reason, body, max_verdicts)
  LOOP
    -- Oversized input is refused before any scan: deterministically, by
    -- the verdict's call count (only the short main comment text is
    -- scanned), with a 2 s backstop (batch-4 fix round 1, I-3: the old
    -- 200 ms bound failed under load; the bug it guards cost 55 s).
    BEGIN
      PERFORM set_config('track_functions', 'pl', true);
    EXCEPTION WHEN insufficient_privilege THEN
      v_tracked := false;
    END;
    v_calls := coalesce((SELECT calls FROM pg_stat_xact_user_functions WHERE funcid = 'private.content_filter_verdict(text,text[])'::regprocedure), 0);
    v_t0 := clock_timestamp();
    IF pg_temp.err_as(v_u, v_case.body) IS DISTINCT FROM v_case.reason THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: oversized input was not refused with % (gave %): %', v_case.reason, pg_temp.err_as(v_u, v_case.body), left(v_case.body, 80);
    END IF;
    IF clock_timestamp() - v_t0 > interval '2 seconds' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: oversized input took % to refuse: %', clock_timestamp() - v_t0, left(v_case.body, 80);
    END IF;
    v_calls := coalesce((SELECT calls FROM pg_stat_xact_user_functions WHERE funcid = 'private.content_filter_verdict(text,text[])'::regprocedure), 0) - v_calls;
    IF v_tracked AND v_calls > v_case.max_verdicts THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: oversized input was scanned (% verdicts, at most % expected) before it was refused: %', v_calls, v_case.max_verdicts, left(v_case.body, 80);
    END IF;
  END LOOP;
  IF NOT v_tracked THEN
    RAISE NOTICE 'opinion_filter_contracts: track_functions needs a superuser; the oversized-input call counts were skipped';
  END IF;
  -- Blank options never reach the assert, and options are checked trimmed
  -- (re-review N-3).
  -- (batch-4 fix round 1, I-3) Deterministic where track_functions can
  -- be switched on (a superuser, as on attune_spec3a): exactly the 4
  -- non-blank options reach assert_part_content_ok. Elsewhere, relative to
  -- the load: within 10 times a plain trim-and-count of the same array,
  -- plus 50 ms (scanning every blank option is about 35 times it).
  v_t0 := clock_timestamp();
  PERFORM count(*) FROM unnest(array_fill(' '::text, ARRAY[200000]) || ARRAY['Yes', 'No']) AS o WHERE btrim(o) <> '';
  v_ref := clock_timestamp() - v_t0;
  v_calls := coalesce((SELECT calls FROM pg_stat_xact_user_functions WHERE funcid = 'private.assert_part_content_ok(text,text)'::regprocedure), 0);
  v_t0 := clock_timestamp();
  BEGIN
    PERFORM private.assert_poll_options_ok(array_fill(' '::text, ARRAY[200000]) || ARRAY['Yes', 'No']);
    PERFORM private.assert_poll_options_ok(ARRAY['Yes', repeat(' ', 6000) || 'No' || repeat(' ', 6000)]);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: blank or space-padded poll options were refused (%)', SQLERRM;
  END;
  IF v_tracked THEN
    v_calls := coalesce((SELECT calls FROM pg_stat_xact_user_functions WHERE funcid = 'private.assert_part_content_ok(text,text)'::regprocedure), 0) - v_calls;
    IF v_calls <> 4 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: 200000 blank poll options made % option checks, expected 4', v_calls;
    END IF;
  ELSIF clock_timestamp() - v_t0 > 10 * v_ref + interval '50 milliseconds' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 200000 blank poll options took % to check (reference %)', clock_timestamp() - v_t0, v_ref;
  END IF;
  -- An ordinary post still goes through with the filter on.
  IF pg_temp.err_as(pg_temp.id('05'), 'SELECT public.create_opinion(''W9a contract: we met in 1999 and married in 2004.'')') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary post was refused with the filter on';
  END IF;

  -- Flag off: no filter; each writer allows the same text.
  PERFORM pg_temp.flag(false);
  IF pg_temp.err_as(pg_temp.id('02'), 'SELECT public.create_opinion(''Call me on 0244123456 tonight'')') IS NOT NULL
     OR pg_temp.err_as(pg_temp.id('03'), format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', %L])', 'He called me kokoo again', 'Call 0244123456')) IS NOT NULL
     OR pg_temp.err_as(v_u, format('SELECT public.edit_opinion(%L, %L)', v_own_opinion, 'She sent b l o r p i n g t o n')) IS NOT NULL
     OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, 'Call me on 0244123456', 'kokoo')) IS NOT NULL
     OR pg_temp.err_as(v_u, format('SELECT public.edit_opinion_comment(%L, %L)', v_own_comment, 'He called me kokoo again')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 off, a writer still filtered';
  END IF;
  IF pg_temp.err_as(pg_temp.id('06'), format('SELECT public.create_opinion_with_quote(%L, %L)', 'wa.me/233244123456', v_target)) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 off, create_opinion_with_quote still filtered';
  END IF;
  -- The pre-W9 poll writer accepts a two-dimensional options array; the
  -- added line must not turn it into an error.
  IF pg_temp.err_as(pg_temp.id('07'), 'SELECT public.create_opinion_with_poll(''W9a contract: a poll'', ARRAY[[''Yes'', ''No''], [''Maybe'', ''Later'']])') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 off, a two-dimensional poll was refused (%)',
      pg_temp.err_as(pg_temp.id('07'), 'SELECT public.create_opinion_with_poll(''W9a contract: a poll'', ARRAY[[''Yes'', ''No''], [''Maybe'', ''Later'']])');
  END IF;
END $$;

-- =====================================================================
-- F2. Flag off is byte-for-byte (owner ruling 2026-11-04): each writer is
--     its pre-W9 live body (the md5 below is pg_get_functiondef of the body
--     Task 1 saved before migration 16) plus ONE line, marked
--     "-- Spec 1 W9a", that is the assert; with opinions_safety_v1 off the
--     assert raises for nothing and (being STABLE) writes nothing. A later
--     migration that re-creates a writer must re-pin its md5 here.
-- =====================================================================
DO $$
DECLARE
  r record;
  v_def text;
  v_marked text[];
  v text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.create_opinion(text)', '652def173437eec68c3f473f1239d377'),
      ('public.create_opinion_with_poll(text,text[])', '7625996b437a70bf9da6bc4528092444'),
      ('public.create_opinion_with_quote(text,uuid)', '0d15dce3d90b6401870c97bd6a7e3f92'),
      ('public.edit_opinion(uuid,text)', '4bd69bc224c359600761326567657676'),
      ('public.create_opinion_comment(uuid,text,uuid,text)', 'ed4570f8852cba20a780195c9a8a2dfc'),
      ('public.edit_opinion_comment(uuid,text)', 'e21131d926bcad80766a5246455ba5f8')
    ) AS x(sig, before_md5) LOOP
    v_def := pg_get_functiondef(r.sig::regprocedure);
    v_marked := ARRAY(SELECT l FROM regexp_split_to_table(v_def, E'\n') AS l WHERE l LIKE '%-- Spec 1 W9a%');
    IF coalesce(array_length(v_marked, 1), 0) <> 1
       OR coalesce(v_marked[1] !~ '^  PERFORM private\.(assert_opinion_content_ok\(p_content\)|assert_comment_content_ok\(p_content, p_quoted_text\)|assert_poll_options_ok\(p_poll_options\)); -- Spec 1 W9a$', true) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % must carry exactly one W9a line, the assert (has %)', r.sig, v_marked;
    END IF;
    IF md5(replace(v_def, v_marked[1] || E'\n', '')) <> r.before_md5 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not its pre-W9 body plus the assert line', r.sig;
    END IF;
  END LOOP;
  PERFORM pg_temp.flag(false);
  FOREACH v IN ARRAY ARRAY['Call me on 0244123456 tonight', 'He called me kokoo again', 'She sent b l o r p i n g t o n',
                           'a zzdraftword here', 'wa.me/kofi', 'kofi at gmail dot com'] LOOP
    BEGIN
      PERFORM private.assert_opinion_content_ok(v);
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 off, the assert raised % for "%"', SQLERRM, v;
    END;
  END LOOP;
  BEGIN
    PERFORM private.assert_opinion_content_ok(repeat('x', 6000));
    PERFORM private.assert_poll_options_ok(ARRAY['a', 'b', 'c', 'd', 'e', repeat('x', 61), 'wa.me/kofi']);
    PERFORM private.assert_comment_content_ok('wa.me/kofi', 'He called me kokoo again');
    PERFORM private.assert_comment_content_ok(repeat('x', 6000), repeat('x', 6000));
    PERFORM private.assert_part_content_ok('She sent b l o r p i n g t o n', 'quoted_text');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 off, a length or option check raised %', SQLERRM;
  END;
END $$;

-- =====================================================================
-- G. (W9b) "Someone may be at risk": valid, priority, never moves
--    report_count or hides the post (D13); review queue v0 is the service
--    role's only, oldest first, with a 280-character excerpt and no
--    reporter (spec §4.3 W9b, §7.1).
-- =====================================================================
CREATE FUNCTION pg_temp.as_service() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
END $$;

DO $$
DECLARE
  v_author constant uuid := pg_temp.id('04');
  v_reporter constant uuid := pg_temp.id('02');
  v_other constant uuid := pg_temp.id('03');
  v_o uuid;
  v_c uuid;
  v_q jsonb;
  v_ids text[];
  v_msg text;
BEGIN
  INSERT INTO public.opinions (user_id, content, report_count, created_at)
  VALUES (v_author, 'W9b contract: I do not want to be here any more. ' || repeat('x', 400), 9, clock_timestamp())
  RETURNING id INTO v_o;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content)
  VALUES (v_o, v_author, 'W9b contract: a comment from someone who may be at risk.')
  RETURNING id INTO v_c;

  IF pg_temp.err_as(v_reporter, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk')) IS NOT NULL
     OR pg_temp.err_as(v_reporter, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk')) IS NOT NULL
     OR pg_temp.err_as(v_reporter, format('SELECT public.report_opinion_comment(%L, %L)', v_c, 'Someone may be at risk')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the at-risk reason was refused';
  END IF;
  IF (SELECT count(*) FROM public.forum_reports WHERE reported_by = v_reporter AND (opinion_id = v_o OR comment_id = v_c)
        AND reason = 'Someone may be at risk' AND priority) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the at-risk reports were not recorded once each, as priority';
  END IF;
  IF (SELECT report_count FROM public.opinions WHERE id = v_o) <> 9
     OR (SELECT hidden_pending_review FROM public.opinions WHERE id = v_o)
     OR (SELECT report_count FROM public.opinion_comments WHERE id = v_c) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an at-risk report moved report_count or hid the post';
  END IF;
  -- Another reason still counts (and the tenth report still hides).
  PERFORM pg_temp.err_as(v_other, format('SELECT public.report_opinion(%L, %L)', v_o, 'Spam'));
  IF (SELECT report_count FROM public.opinions WHERE id = v_o) <> 10
     OR NOT (SELECT hidden_pending_review FROM public.opinions WHERE id = v_o) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Spam report no longer counts toward auto-hide';
  END IF;
  IF pg_temp.err_as(v_other, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk!'))
       IS DISTINCT FROM 'invalid_reason' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown reason was accepted';
  END IF;
  -- A priority report a person has already reviewed (it must leave the queue).
  PERFORM pg_temp.err_as(v_other, format('SELECT public.report_opinion_comment(%L, %L)', v_c, 'Hate speech or discrimination'));
  UPDATE public.forum_reports SET status = 'reviewed_kept' WHERE reported_by = v_other AND comment_id = v_c;

  -- Review queue v0: not for clients.
  v_msg := pg_temp.err_as(v_reporter, 'SELECT public.admin_list_priority_reports(50)');
  IF coalesce(v_msg, '') !~ 'permission denied' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in client could read review queue v0 (%)', v_msg;
  END IF;
  IF has_function_privilege('anon', 'public.admin_list_priority_reports(integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.admin_list_priority_reports(integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.admin_list_priority_reports(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 grants are wrong (service role only)';
  END IF;
  -- Oldest first: one transaction gives every row the same now().
  UPDATE public.forum_reports SET created_at = now() - interval '2 minutes' WHERE reported_by = v_reporter AND opinion_id = v_o;
  UPDATE public.forum_reports SET created_at = now() - interval '1 minute' WHERE reported_by = v_reporter AND comment_id = v_c;
  UPDATE public.forum_reports SET status = 'reviewed_kept'
   WHERE status = 'pending' AND opinion_id IS DISTINCT FROM v_o AND comment_id IS DISTINCT FROM v_c;
  PERFORM pg_temp.as_service();
  v_q := public.admin_list_priority_reports(50);
  RESET ROLE;
  SELECT array_agg(e->>'reason' ORDER BY ord) INTO v_ids FROM jsonb_array_elements(v_q) WITH ORDINALITY AS x(e, ord);
  IF v_ids IS DISTINCT FROM ARRAY['Someone may be at risk', 'Someone may be at risk'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 listed % (expected the two pending at-risk reports, not Spam)', v_ids;
  END IF;
  IF (v_q->0->>'content_type') <> 'opinion' OR (v_q->0->>'content_id')::uuid <> v_o
     OR char_length(v_q->0->>'excerpt') <> 280 OR (v_q->1->>'content_type') <> 'comment'
     OR (v_q->0) ? 'reported_by' OR v_q::text LIKE '%' || v_reporter::text || '%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 rows are wrong (oldest first, 280-character excerpt, no reporter): %', v_q;
  END IF;
  -- W9 final M-9: a comment item names its post, so it can be read in
  -- context without a hand query.
  IF (v_q->0->>'opinion_id') IS DISTINCT FROM v_o::text OR (v_q->1->>'opinion_id') IS DISTINCT FROM v_o::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 items must carry their post (opinion_id): %', v_q;
  END IF;
  -- The post was hidden by the tenth (Spam) report and is not removed
  -- (batch-4 fix round 1, M-4).
  IF (v_q->0->>'hidden_pending_review') IS DISTINCT FROM 'true' OR (v_q->0->>'content_removed') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 does not show the hidden, unremoved post as such: %', v_q->0;
  END IF;
  -- A client JWT is refused even by the owner role.
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_list_priority_reports(50);
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 answered an authenticated JWT';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'forbidden' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expected forbidden, got %', v_msg; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- =====================================================================
-- G2. (W9b; owner rulings (a) and (c), pre-flight PF-C1) One account can
--     never move report_count twice on one item, whatever reasons it
--     gives, so one account can never auto-hide a post (not gated: the
--     flag is off here). An at-risk report is never dropped: an earlier
--     report from the same account on the same item is upgraded to it
--     (priority, pending, reviewed_at NULL, created_at now(), so it is
--     back in review queue v0) without counting again; a later ordinary
--     report never downgrades it; a repeat while pending changes nothing;
--     a repeat after a person reviewed it re-opens it. Every comment
--     report reason reaches the server and is recorded, flag on or off.
--     No report tells anyone anything.
-- =====================================================================
DO $$
DECLARE
  v_author constant uuid := pg_temp.id('04');
  v_one constant uuid := pg_temp.id('05');
  v_two constant uuid := pg_temp.id('06');
  v_three constant uuid := pg_temp.id('07');
  v_reasons constant text[] := ARRAY['Identifies a real person', 'Harmful or dangerous content',
    'Explicit sexual content', 'Hate speech or discrimination', 'Spam', 'Other', 'Someone may be at risk'];
  v_priority constant boolean[] := ARRAY[true, true, false, true, false, false, true];
  v_notices_before int;
  v_o uuid;
  v_c uuid;
  v_cs uuid[] := ARRAY[]::uuid[];
  v_id uuid;
  v_flag boolean;
  v_reason text;
  v_msg text;
  v_q jsonb;
  v_listed uuid[];
  v_n int;
  i int;
  k int := 0;
BEGIN
  PERFORM pg_temp.flag(false);
  INSERT INTO public.opinions (user_id, content)
  VALUES (v_author, 'W9b contract G2: a post one account reports again and again.')
  RETURNING id INTO v_o;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content)
  VALUES (v_o, v_author, 'W9b contract G2: a comment one account reports again and again.')
  RETURNING id INTO v_c;
  FOR i IN 1 .. 14 LOOP
    INSERT INTO public.opinion_comments (opinion_id, user_id, content)
    VALUES (v_o, v_author, 'W9b contract G2: comment ' || i) RETURNING id INTO v_id;
    v_cs := v_cs || v_id;
  END LOOP;
  SELECT count(*) INTO v_notices_before FROM public.scheduled_notifications;

  -- (a) Twelve reports from one account, in every ordinary reason (Spam
  -- first): one row each, counted once, never hidden.
  FOR i IN 1 .. 12 LOOP
    v_reason := v_reasons[1 + (i + 3) % 6];
    v_msg := coalesce(pg_temp.err_as(v_one, format('SELECT public.report_opinion(%L, %L)', v_o, v_reason)), '')
          || coalesce(pg_temp.err_as(v_one, format('SELECT public.report_opinion_comment(%L, %L)', v_c, v_reason)), '');
    IF v_msg <> '' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a repeat report raised %', v_msg;
    END IF;
  END LOOP;
  IF (SELECT report_count FROM public.opinions WHERE id = v_o) <> 1
     OR (SELECT report_count FROM public.opinion_comments WHERE id = v_c) <> 1
     OR (SELECT hidden_pending_review FROM public.opinions WHERE id = v_o)
     OR (SELECT hidden_pending_review FROM public.opinion_comments WHERE id = v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: repeat reports from one account moved report_count (post %, comment %)',
      (SELECT report_count FROM public.opinions WHERE id = v_o),
      (SELECT report_count FROM public.opinion_comments WHERE id = v_c);
  END IF;
  IF (SELECT count(*) FROM public.forum_reports
       WHERE reported_by = v_one AND (opinion_id = v_o OR comment_id = v_c)) <> 2
     OR EXISTS (SELECT 1 FROM public.forum_reports
                 WHERE reported_by = v_one AND (opinion_id = v_o OR comment_id = v_c)
                   AND (reason <> 'Spam' OR priority OR status <> 'pending')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: repeat ordinary reports from one account changed its first report';
  END IF;

  -- PF-C1: an earlier report a person already reviewed, then at-risk from
  -- the same account: upgraded and back in the queue, not counted again.
  UPDATE public.forum_reports
     SET status = 'reviewed_kept', reviewed_at = now(), created_at = now() - interval '3 days'
   WHERE reported_by = v_one AND (opinion_id = v_o OR comment_id = v_c);
  IF pg_temp.err_as(v_one, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk')) IS NOT NULL
     OR pg_temp.err_as(v_one, format('SELECT public.report_opinion_comment(%L, %L)', v_c, 'Someone may be at risk')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an at-risk report after an earlier report was refused';
  END IF;
  IF (SELECT count(*) FROM public.forum_reports
       WHERE reported_by = v_one AND (opinion_id = v_o OR comment_id = v_c)
         AND reason = 'Someone may be at risk' AND priority AND status = 'pending'
         AND reviewed_at IS NULL AND created_at = now()) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an at-risk report after an earlier report from the same account was dropped (not upgraded): %',
      (SELECT jsonb_agg(to_jsonb(r) - 'reported_by') FROM public.forum_reports AS r
        WHERE r.reported_by = v_one AND (r.opinion_id = v_o OR r.comment_id = v_c));
  END IF;
  IF (SELECT report_count FROM public.opinions WHERE id = v_o) <> 1
     OR (SELECT report_count FROM public.opinion_comments WHERE id = v_c) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: upgrading a report to at-risk moved report_count';
  END IF;

  -- A pending Spam report, then at-risk from the same account: upgraded.
  PERFORM pg_temp.err_as(v_two, format('SELECT public.report_opinion(%L, %L)', v_o, 'Spam'));
  IF (SELECT report_count FROM public.opinions WHERE id = v_o) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second account''s Spam report did not count';
  END IF;
  UPDATE public.forum_reports SET created_at = now() - interval '1 hour'
   WHERE reported_by = v_two AND opinion_id = v_o;
  PERFORM pg_temp.err_as(v_two, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk'));
  IF NOT EXISTS (SELECT 1 FROM public.forum_reports
                  WHERE reported_by = v_two AND opinion_id = v_o AND reason = 'Someone may be at risk'
                    AND priority AND status = 'pending' AND created_at = now())
     OR (SELECT report_count FROM public.opinions WHERE id = v_o) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pending Spam report followed by at-risk was not upgraded once, uncounted';
  END IF;

  -- The at-risk report repeated while pending: nothing moves (it keeps its
  -- place in the queue); a later ordinary report never downgrades it.
  UPDATE public.forum_reports SET created_at = now() - interval '1 hour'
   WHERE reported_by = v_two AND opinion_id = v_o;
  PERFORM pg_temp.err_as(v_two, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk'));
  PERFORM pg_temp.err_as(v_two, format('SELECT public.report_opinion(%L, %L)', v_o, 'Spam'));
  IF (SELECT count(*) FROM public.forum_reports
       WHERE reported_by = v_two AND opinion_id = v_o AND reason = 'Someone may be at risk'
         AND priority AND status = 'pending' AND created_at = now() - interval '1 hour') <> 1
     OR (SELECT count(*) FROM public.forum_reports WHERE reported_by = v_two AND opinion_id = v_o) <> 1
     OR (SELECT report_count FROM public.opinions WHERE id = v_o) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated at-risk report, or a later Spam report, changed the pending at-risk report or the count';
  END IF;

  -- At-risk first, then an ordinary reason, on a comment: still at-risk, never counted.
  PERFORM pg_temp.err_as(v_three, format('SELECT public.report_opinion_comment(%L, %L)', v_c, 'Someone may be at risk'));
  PERFORM pg_temp.err_as(v_three, format('SELECT public.report_opinion_comment(%L, %L)', v_c, 'Hate speech or discrimination'));
  IF NOT EXISTS (SELECT 1 FROM public.forum_reports
                  WHERE reported_by = v_three AND comment_id = v_c AND reason = 'Someone may be at risk' AND priority)
     OR (SELECT report_count FROM public.opinion_comments WHERE id = v_c) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary report after an at-risk one downgraded it or counted';
  END IF;

  -- A person reviewed the at-risk report; the same account reports it at
  -- risk again: it is re-opened (pending, back in the queue), not counted.
  UPDATE public.forum_reports
     SET status = 'reviewed_kept', reviewed_at = now(), created_at = now() - interval '1 day'
   WHERE reported_by = v_two AND opinion_id = v_o;
  PERFORM pg_temp.err_as(v_two, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk'));
  IF NOT EXISTS (SELECT 1 FROM public.forum_reports
                  WHERE reported_by = v_two AND opinion_id = v_o AND reason = 'Someone may be at risk'
                    AND priority AND status = 'pending' AND reviewed_at IS NULL AND created_at = now())
     OR (SELECT report_count FROM public.opinions WHERE id = v_o) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new at-risk report after a reviewed one was dropped or counted';
  END IF;

  -- Every one of them is in review queue v0.
  PERFORM pg_temp.as_service();
  v_q := public.admin_list_priority_reports(200);
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  SELECT array_agg((e->>'report_id')::uuid) INTO v_listed FROM jsonb_array_elements(v_q) AS e;
  IF NOT (ARRAY(SELECT r.id FROM public.forum_reports AS r
                 WHERE r.reported_by IN (v_one, v_two, v_three) AND (r.opinion_id = v_o OR r.comment_id = v_c))
          <@ coalesce(v_listed, ARRAY[]::uuid[]))
     OR (SELECT count(*) FROM public.forum_reports AS r
          WHERE r.reported_by IN (v_one, v_two, v_three) AND (r.opinion_id = v_o OR r.comment_id = v_c)) <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an upgraded or re-opened at-risk report is missing from review queue v0: %', v_q;
  END IF;

  -- (c) Every comment report reason reaches the server and is recorded
  -- with its priority, flag on or off; only at-risk leaves the count alone.
  FOREACH v_flag IN ARRAY ARRAY[true, false] LOOP
    PERFORM pg_temp.flag(v_flag);
    FOR i IN 1 .. 7 LOOP
      k := k + 1;
      v_msg := pg_temp.err_as(v_one, format('SELECT public.report_opinion_comment(%L, %L)', v_cs[k], v_reasons[i]));
      IF v_msg IS NOT NULL
         OR NOT EXISTS (SELECT 1 FROM public.forum_reports
                         WHERE reported_by = v_one AND comment_id = v_cs[k] AND reason = v_reasons[i]
                           AND priority = v_priority[i] AND status = 'pending')
         OR (SELECT report_count FROM public.opinion_comments WHERE id = v_cs[k])
              <> (CASE WHEN v_reasons[i] = 'Someone may be at risk' THEN 0 ELSE 1 END) THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: the comment reason "%" (flag %) did not reach the server as recorded (%)',
          v_reasons[i], v_flag, coalesce(v_msg, 'no error');
      END IF;
    END LOOP;
  END LOOP;
  PERFORM pg_temp.flag(false);

  -- Nobody was told anything about any report.
  SELECT count(*) INTO v_n FROM public.scheduled_notifications;
  IF v_n <> v_notices_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reports queued % notification(s)', v_n - v_notices_before;
  END IF;
END $$;

-- =====================================================================
-- G3. (W9b, batch-4 fix round 1) forum_reports is written only by the
--     report RPCs: a signed-in client can no longer plant a backdated
--     priority row at the head of review queue v0 (C-1). The queue lists
--     at-risk reports first, then the oldest (I-1); it caps at 200 rows,
--     defaults to 50, and says whether the item is removed or hidden
--     (M-4). An escalated report upgraded to at-risk is pending again; an
--     escalated at-risk report repeated stays escalated (M-2).
--     private.is_priority_reason is the report RPCs' only (M-1).
-- =====================================================================
DO $$
DECLARE
  v_author constant uuid := pg_temp.id('04');
  v_one constant uuid := pg_temp.id('05');
  v_two constant uuid := pg_temp.id('06');
  v_o uuid;
  v_c_old uuid;
  v_c_new uuid;
  v_c_older uuid;
  v_q jsonb;
  v_msg text;
  v_role text;
  v_priv text;
BEGIN
  INSERT INTO public.opinions (user_id, content)
  VALUES (v_author, 'W9b contract G3: a post for the queue checks.')
  RETURNING id INTO v_o;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content)
  VALUES (v_o, v_author, 'W9b contract G3: an older comment reported for hate speech.')
  RETURNING id INTO v_c_old;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content)
  VALUES (v_o, v_author, 'W9b contract G3: a newer comment reported at risk.')
  RETURNING id INTO v_c_new;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content)
  VALUES (v_o, v_author, 'W9b contract G3: the oldest comment reported at risk.')
  RETURNING id INTO v_c_older;

  -- C-1, the reviewer's probe: a signed-in client inserts a backdated
  -- priority row directly, with any reason it likes.
  v_msg := pg_temp.err_as(v_one, format(
    $q$INSERT INTO public.forum_reports (reported_by, opinion_id, reason, priority, status, created_at)
       VALUES (%L, %L, 'anything at all, any length', true, 'pending', '2000-01-01')$q$, v_one, v_o));
  IF coalesce(v_msg, '') !~ 'permission denied for table forum_reports' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in client wrote forum_reports directly (%)', coalesce(v_msg, 'a backdated priority row was inserted');
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOREACH v_priv IN ARRAY ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] LOOP
      IF has_table_privilege(v_role, 'public.forum_reports', v_priv) THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % holds % on forum_reports (the report RPCs are its only writers)', v_role, v_priv;
      END IF;
    END LOOP;
  END LOOP;
  -- M-1: the priority list is the report RPCs' own.
  IF has_function_privilege('anon', 'private.is_priority_reason(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.is_priority_reason(text)', 'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc AS p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
                 WHERE p.oid = 'private.is_priority_reason(text)'::regprocedure AND a.grantee = 0) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: private.is_priority_reason is executable by PUBLIC, anon or authenticated';
  END IF;
  -- Batch-6 ruling: report_count moves only through the report RPCs; the
  -- unowned increment_opinion_report_count is no client's.
  IF has_function_privilege('anon', 'public.increment_opinion_report_count(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.increment_opinion_report_count(uuid)', 'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc AS p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
                 WHERE p.oid = 'public.increment_opinion_report_count(uuid)'::regprocedure AND a.grantee = 0) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: increment_opinion_report_count is executable by PUBLIC, anon or authenticated (one account could raise any report_count)';
  END IF;

  -- I-1: an older pending "Hate speech" report and a newer at-risk one:
  -- the at-risk one is listed first, even with a limit of 1.
  UPDATE public.forum_reports SET status = 'reviewed_kept' WHERE status = 'pending';
  PERFORM pg_temp.err_as(v_one, format('SELECT public.report_opinion_comment(%L, %L)', v_c_old, 'Hate speech or discrimination'));
  UPDATE public.forum_reports SET created_at = now() - interval '1 hour' WHERE reported_by = v_one AND comment_id = v_c_old;
  PERFORM pg_temp.err_as(v_one, format('SELECT public.report_opinion_comment(%L, %L)', v_c_new, 'Someone may be at risk'));
  PERFORM pg_temp.as_service();
  v_q := public.admin_list_priority_reports(1);
  IF jsonb_array_length(v_q) <> 1 OR (v_q->0->>'content_id')::uuid IS DISTINCT FROM v_c_new THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 (limit 1) did not list the at-risk report before an older Hate speech report: %', v_q;
  END IF;
  v_q := public.admin_list_priority_reports(2);
  IF (v_q->0->>'content_id')::uuid IS DISTINCT FROM v_c_new OR (v_q->1->>'content_id')::uuid IS DISTINCT FROM v_c_old THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 is not at-risk first, then the rest: %', v_q;
  END IF;
  RESET ROLE;

  -- Among at-risk reports, the oldest first (also under a limit).
  PERFORM pg_temp.err_as(v_two, format('SELECT public.report_opinion_comment(%L, %L)', v_c_older, 'Someone may be at risk'));
  UPDATE public.forum_reports SET created_at = now() - interval '2 hours' WHERE reported_by = v_two AND comment_id = v_c_older;
  -- M-4: the queue says whether the item was removed (here directly, by
  -- the owner role, so no strike).
  UPDATE public.opinion_comments SET removed_at = now() WHERE id = v_c_new;
  PERFORM pg_temp.as_service();
  v_q := public.admin_list_priority_reports(1);
  IF (v_q->0->>'content_id')::uuid IS DISTINCT FROM v_c_older THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 (limit 1) did not list the oldest at-risk report: %', v_q;
  END IF;
  v_q := public.admin_list_priority_reports(3);
  IF (v_q->1->>'content_id')::uuid IS DISTINCT FROM v_c_new
     OR (v_q->1->>'content_removed') IS DISTINCT FROM 'true'
     OR (v_q->0->>'content_removed') IS DISTINCT FROM 'false'
     OR (v_q->0->>'hidden_pending_review') IS DISTINCT FROM 'false'
     OR (v_q->2->>'content_id')::uuid IS DISTINCT FROM v_c_old THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 order or content_removed is wrong: %', v_q;
  END IF;
  RESET ROLE;

  -- M-4: at most 200 rows, 50 by default, at least 1.
  WITH c AS (
    INSERT INTO public.opinion_comments (opinion_id, user_id, content)
    SELECT v_o, v_author, 'W9b contract G3: seed ' || g FROM generate_series(1, 201) AS g
    RETURNING id
  )
  INSERT INTO public.forum_reports (reported_by, comment_id, reason, priority)
  SELECT v_two, c.id, 'Hate speech or discrimination', true FROM c;
  PERFORM pg_temp.as_service();
  IF jsonb_array_length(public.admin_list_priority_reports(100000)) <> 200
     OR jsonb_array_length(public.admin_list_priority_reports(NULL)) <> 50
     OR jsonb_array_length(public.admin_list_priority_reports()) <> 50
     OR jsonb_array_length(public.admin_list_priority_reports(0)) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 limits are wrong (100000 -> %, NULL -> %, 0 -> %)',
      jsonb_array_length(public.admin_list_priority_reports(100000)),
      jsonb_array_length(public.admin_list_priority_reports(NULL)),
      jsonb_array_length(public.admin_list_priority_reports(0));
  END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);

  -- M-2: an escalated Spam report, then at-risk from the same account:
  -- one pending at-risk row (it must reach queue v0), not counted again.
  PERFORM pg_temp.err_as(v_one, format('SELECT public.report_opinion(%L, %L)', v_o, 'Spam'));
  UPDATE public.forum_reports SET status = 'escalated', reviewed_at = now() WHERE reported_by = v_one AND opinion_id = v_o;
  PERFORM pg_temp.err_as(v_one, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk'));
  IF (SELECT count(*) FROM public.forum_reports
       WHERE reported_by = v_one AND opinion_id = v_o AND reason = 'Someone may be at risk'
         AND priority AND status = 'pending' AND reviewed_at IS NULL) <> 1
     OR (SELECT report_count FROM public.opinions WHERE id = v_o) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an escalated Spam report followed by at-risk was not one pending, uncounted at-risk report';
  END IF;
  -- An escalated at-risk report, repeated: it stays escalated.
  UPDATE public.forum_reports SET status = 'escalated' WHERE reported_by = v_one AND opinion_id = v_o;
  PERFORM pg_temp.err_as(v_one, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk'));
  IF (SELECT status FROM public.forum_reports WHERE reported_by = v_one AND opinion_id = v_o) IS DISTINCT FROM 'escalated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated at-risk report de-escalated an escalated at-risk report';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'opinion_filter_contracts: all held'; END $$;
ROLLBACK;

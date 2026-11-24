-- supabase/tests/dating_v2_device_contracts.sql
-- Spec 2 W8 (§3.13, §2.3, §2.5, §3.11, §6.7, §7.1, §7.2 S4): device
-- discretion and travel.
--   A (W8a). Every Dating push is neutral: every function or procedure
--      that writes the push queue and is Dating's (by name, by naming a
--      public or private Dating relation, by being a trigger on a Dating
--      table, or reached by name from one of those; and Dating's triggers
--      on the queue) writes only payloads of the keys type, route, title
--      and body: me_update routed to me or me_checkin routed to me_checkin,
--      titled "Attune", with one of §3.13's three bodies (or the body
--      private.dating_me_update_body returns, itself audited), no literal
--      in it saying "dating", never edited in place, written as a JSON
--      literal or joined by || to anything but another such object (§3.13,
--      Fable M4, I-9). The helpers a Dating function reaches are followed
--      to a fixpoint. The app routes exactly those (Spec 2 W10, A-7: the
--      old dating_mutual_match case is gone).
--      Spec 2 W9 (carry 1): the walk covers every schema's SQL and
--      plpgsql functions and follows each write to the triggers that fire
--      on that table for that operation (a Dating write into
--      relationships, timeline_events, game_sessions ... brings their
--      triggers in); a queue write may be quoted, schema-qualified or a
--      MERGE; nothing reached writes the other queue tables, calls
--      send-notification or OneSignal, or EXECUTEs a statement built at
--      run time.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_device_contracts.sql
BEGIN;

-- =====================================================================
-- A. Every Dating push is neutral (W8a).
-- =====================================================================
-- Fix rounds 1-2 (I-1, I-2, M-4): a function's source is read with its
-- quoted literals and comments masked (pg_temp.w8a_mask keeps every
-- position), so a payload is read as a whole across lines, and a jsonb
-- `||` is told from a text one. pg_temp.w8a_spans: every
-- json(b)_build_object call (its name, its open and its close paren);
-- pg_temp.w8a_args splits a call's arguments at their top-level commas;
-- pg_temp.w8a_concats: each `||` with what stands on either side of it.
CREATE FUNCTION pg_temp.w8a_mask(p text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE
  c text[] := string_to_array(p, NULL);
  n int := coalesce(cardinality(string_to_array(p, NULL)), 0);
  i int := 1;
  st int := 0;
BEGIN
  WHILE i <= n LOOP
    IF st = 0 THEN
      IF c[i] = '''' THEN
        st := 1;
      ELSIF c[i] = '-' AND i < n AND c[i + 1] = '-' THEN
        st := 2; c[i] := ' ';
      ELSIF c[i] = '/' AND i < n AND c[i + 1] = '*' THEN
        st := 3; c[i] := ' ';
      END IF;
    ELSIF st = 1 THEN
      IF c[i] = '''' THEN st := 0; ELSE c[i] := 'x'; END IF;
    ELSIF st = 2 THEN
      IF c[i] = E'\n' THEN st := 0; ELSE c[i] := ' '; END IF;
    ELSIF c[i] = '*' AND i < n AND c[i + 1] = '/' THEN
      c[i] := ' '; c[i + 1] := ' '; i := i + 1; st := 0;
    ELSIF c[i] <> E'\n' THEN
      c[i] := ' ';
    END IF;
    i := i + 1;
  END LOOP;
  RETURN array_to_string(c, '');
END $f$;
CREATE FUNCTION pg_temp.w8a_spans(p_src text) RETURNS TABLE(s int, o int, e int) LANGUAGE plpgsql AS $f$
DECLARE
  m text := lower(pg_temp.w8a_mask(p_src));
  v_start int := 1;
  i int;
  d int;
BEGIN
  LOOP
    s := regexp_instr(m, '\mjsonb?_build_object\s*\(', v_start, 1, 0);
    EXIT WHEN s = 0;
    o := regexp_instr(m, '\mjsonb?_build_object\s*\(', v_start, 1, 1) - 1;
    i := o + 1; d := 1;
    WHILE i <= length(m) AND d > 0 LOOP
      IF substr(m, i, 1) = '(' THEN d := d + 1; ELSIF substr(m, i, 1) = ')' THEN d := d - 1; END IF;
      i := i + 1;
    END LOOP;
    IF d = 0 THEN e := i - 1; RETURN NEXT; END IF;
    v_start := o + 1;
  END LOOP;
END $f$;
CREATE FUNCTION pg_temp.w8a_args(p text) RETURNS text[] LANGUAGE plpgsql AS $f$
DECLARE
  m text := pg_temp.w8a_mask(p);
  v_out text[] := '{}';
  v_from int := 1;
  i int := 1;
  d int := 0;
BEGIN
  WHILE i <= length(m) LOOP
    IF substr(m, i, 1) = '(' THEN
      d := d + 1;
    ELSIF substr(m, i, 1) = ')' THEN
      d := d - 1;
    ELSIF substr(m, i, 1) = ',' AND d = 0 THEN
      v_out := v_out || pg_temp.w8a_strip(p, m, v_from, i - 1);
      v_from := i + 1;
    END IF;
    i := i + 1;
  END LOOP;
  RETURN v_out || pg_temp.w8a_strip(p, m, v_from, length(m));
END $f$;
-- One argument: the original text with its comments dropped (blanked in
-- the mask), trimmed.
CREATE FUNCTION pg_temp.w8a_strip(p text, m text, a int, b int) RETURNS text LANGUAGE sql AS $f$
  SELECT btrim(string_agg(CASE WHEN substr(m, i, 1) = ' ' AND substr(p, i, 1) <> ' ' THEN ' ' ELSE substr(p, i, 1) END, '' ORDER BY i),
               E' \t\r\n')
    FROM generate_series(a, b) AS i $f$;
-- A quoted literal's text, or NULL when the value is not one literal.
CREATE FUNCTION pg_temp.w8a_lit(p text) RETURNS text LANGUAGE sql AS $f$
  SELECT CASE WHEN p ~ '^''([^'']|'''')*''$'
              THEN replace(substr(p, 2, length(p) - 2), '''''', '''') END $f$;
-- What a token beside `||` is: jsonb (a jsonb variable or parameter, the
-- metadata column, a ::json(b) cast, a json-making call) or plain.
CREATE FUNCTION pg_temp.w8a_kind(p_tok text, p_call boolean, p_jsonb text[]) RETURNS text LANGUAGE sql AS $f$
  SELECT CASE
    WHEN p_tok IS NULL THEN 'plain'
    WHEN p_call THEN CASE WHEN p_tok ~ '(^|\.)(to_jsonb?|row_to_json|jsonb?_\w+|json_object\w*)$' THEN 'jsonb' ELSE 'plain' END
    WHEN p_tok ~ '::\s*jsonb?$' THEN 'jsonb'
    WHEN regexp_replace(regexp_replace(p_tok, '::\s*\w+$', ''), '^.*\.', '') = ANY (p_jsonb || ARRAY['metadata']) THEN 'jsonb'
    ELSE 'plain' END $f$;
CREATE FUNCTION pg_temp.w8a_concats(p_src text, p_jsonb text[])
  RETURNS TABLE(l_kind text, l_e int, l_tok text, r_kind text, r_s int, r_tok text) LANGUAGE plpgsql AS $f$
DECLARE
  m text := lower(pg_temp.w8a_mask(p_src));
  v_s int[] := ARRAY(SELECT sp.s FROM pg_temp.w8a_spans(p_src) AS sp);
  v_e int[] := ARRAY(SELECT sp.e FROM pg_temp.w8a_spans(p_src) AS sp);
  v_start int := 1;
  i int;
  j int;
  k int;
  d int;
  v_name text;
BEGIN
  LOOP
    i := strpos(substr(m, v_start), '||');
    EXIT WHEN i = 0;
    i := i + v_start - 1;
    -- Left of it.
    j := i - 1;
    WHILE j >= 1 AND substr(m, j, 1) ~ '\s' LOOP j := j - 1; END LOOP;
    l_e := j; l_tok := NULL;
    IF j >= 1 AND substr(m, j, 1) = ')' THEN
      IF j = ANY (v_e) THEN
        l_kind := 'obj';
      ELSE
        k := j; d := 0;
        LOOP
          IF substr(m, k, 1) = ')' THEN d := d + 1; ELSIF substr(m, k, 1) = '(' THEN d := d - 1; END IF;
          EXIT WHEN d = 0 OR k <= 1;
          k := k - 1;
        END LOOP;
        l_tok := substring(substr(m, 1, k - 1) FROM '([a-z0-9_.]*)\s*$');
        l_kind := pg_temp.w8a_kind(nullif(l_tok, ''), true, p_jsonb);
      END IF;
    ELSE
      l_tok := substring(substr(m, 1, j) FROM '([a-z0-9_.:'']*)$');
      l_kind := pg_temp.w8a_kind(nullif(l_tok, ''), false, p_jsonb);
    END IF;
    -- Right of it.
    j := i + 2;
    WHILE j <= length(m) AND substr(m, j, 1) ~ '\s' LOOP j := j + 1; END LOOP;
    r_s := j; r_tok := NULL;
    v_name := substring(substr(m, j) FROM '^((pg_catalog\.)?jsonb?_build_object)\s*\(');
    IF v_name IS NOT NULL AND (j + CASE WHEN v_name ~ '^pg_catalog\.' THEN 11 ELSE 0 END) = ANY (v_s) THEN
      r_kind := 'obj';
    ELSIF substr(m, j, 1) = '(' THEN
      k := j; d := 0;
      LOOP
        IF substr(m, k, 1) = '(' THEN d := d + 1; ELSIF substr(m, k, 1) = ')' THEN d := d - 1; END IF;
        EXIT WHEN d = 0 OR k >= length(m);
        k := k + 1;
      END LOOP;
      r_tok := substr(m, j, k - j + 1);
      r_kind := CASE WHEN r_tok ~ '(jsonb?_build_object|::\s*jsonb?\M|to_jsonb?|row_to_json)'
                       OR r_tok ~ ('\m(' || array_to_string(p_jsonb || ARRAY['metadata'], '|') || ')\M')
                     THEN 'jsonb' ELSE 'plain' END;
    ELSE
      r_tok := substring(substr(m, j) FROM '^([a-z0-9_.'']+(\s*::\s*\w+)?)');
      r_kind := pg_temp.w8a_kind(r_tok, substr(m, j + coalesce(length(r_tok), 0)) ~ '^\s*\(', p_jsonb);
    END IF;
    RETURN NEXT;
    v_start := i + 2;
  END LOOP;
END $f$;

-- Spec 2 W9 (carry 1): the functions (every schema's SQL and plpgsql
-- ones), the edges (a call by name; a write, to each trigger that fires on
-- its table for its operation) and the walk from Dating's functions to its
-- fixpoint, tagged by root as before.
CREATE TEMP TABLE w9a_fn AS
  SELECT p.oid, p.oid::regprocedure::text AS sig, p.proname::text AS proname, p.prosrc AS src
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prokind IN ('f', 'p')
     AND p.prolang IN (SELECT l.oid FROM pg_language AS l WHERE l.lanname IN ('plpgsql', 'sql'));
-- Spec 2 W9 (Task 3 fix round 1, I-1, M-1): every write, by table and
-- operation ('i', 'u', 'd'; a MERGE all three; an upsert's ON CONFLICT DO
-- UPDATE 'u' too), then the foreign keys' cascades: a DELETE that cascades
-- deletes from the child (recursively); SET NULL / SET DEFAULT, or an
-- UPDATE's cascade, updates the child (one level: its own key is not
-- changed).
CREATE TEMP TABLE w9a_write AS
  WITH RECURSIVE dw (a, rel, op, deep) AS (
    SELECT DISTINCT c.oid, tc.oid, o.op, true
      FROM w9a_fn AS c CROSS JOIN LATERAL regexp_matches(c.src,
             '\m(insert\s+into|update|delete\s+from|merge\s+into)\s+(?:only\s+)?(?:"?([a-z_][a-z0-9_]*)"?\s*\.\s*)?"?([a-z_][a-z0-9_]*)"?', 'gi') AS m
      JOIN pg_class AS tc ON tc.relname = lower(m[3]) AND tc.relkind IN ('r', 'p')
      JOIN pg_namespace AS tn ON tn.oid = tc.relnamespace AND tn.nspname = coalesce(lower(m[2]), 'public')
      CROSS JOIN LATERAL unnest(CASE WHEN lower(m[1]) ~ '^insert' THEN ARRAY['i'] WHEN lower(m[1]) = 'update' THEN ARRAY['u']
                                     WHEN lower(m[1]) ~ '^delete' THEN ARRAY['d'] ELSE ARRAY['i', 'u', 'd'] END) AS o(op)
    UNION
    SELECT DISTINCT c.oid, tc.oid, 'u', true
      FROM w9a_fn AS c CROSS JOIN LATERAL regexp_matches(c.src,
             '\minsert\s+into\s+(?:only\s+)?(?:"?([a-z_][a-z0-9_]*)"?\s*\.\s*)?"?([a-z_][a-z0-9_]*)"?[^;]*\mon\s+conflict\M[^;]*\mdo\s+update\M', 'gi') AS m
      JOIN pg_class AS tc ON tc.relname = lower(m[2]) AND tc.relkind IN ('r', 'p')
      JOIN pg_namespace AS tn ON tn.oid = tc.relnamespace AND tn.nspname = coalesce(lower(m[1]), 'public')
    UNION
    SELECT dw.a, k.conrelid, CASE WHEN dw.op = 'd' AND k.confdeltype = 'c' THEN 'd' ELSE 'u' END,
           dw.op = 'd' AND k.confdeltype = 'c'
      FROM dw JOIN pg_constraint AS k ON k.contype = 'f' AND k.confrelid = dw.rel
     WHERE dw.deep AND ((dw.op = 'd' AND k.confdeltype IN ('c', 'n', 'd')) OR (dw.op = 'u' AND k.confupdtype IN ('c', 'n', 'd'))))
  SELECT DISTINCT dw.a, dw.rel, dw.op FROM dw;
CREATE TEMP TABLE w9a_edge AS
  SELECT DISTINCT c.oid AS a, f.oid AS b
    FROM w9a_fn AS c CROSS JOIN LATERAL regexp_matches(c.src, '([a-z_][a-z0-9_]*)\s*\(', 'gi') AS m
    JOIN w9a_fn AS f ON f.proname = lower(m[1])
  UNION
  SELECT DISTINCT w.a, t.tgfoid
    FROM w9a_write AS w JOIN pg_trigger AS t ON t.tgrelid = w.rel AND NOT t.tgisinternal
   WHERE t.tgtype & CASE w.op WHEN 'i' THEN 4 WHEN 'u' THEN 16 ELSE 8 END <> 0;
CREATE TEMP TABLE w9a_dat AS
  SELECT fn.* FROM w9a_fn AS fn
   WHERE fn.proname ~ '(dating|moderation)' OR fn.src ~ '(public|private)\.dating_\w+'
      OR fn.oid IN (SELECT t.tgfoid FROM pg_trigger AS t JOIN pg_class AS tc ON tc.oid = t.tgrelid
                     JOIN pg_namespace AS tn ON tn.oid = tc.relnamespace
                    WHERE NOT t.tgisinternal AND tn.nspname NOT IN ('pg_catalog', 'information_schema')
                      AND tc.relname ~ '^dating_');
CREATE TEMP TABLE w9a_reach AS
  WITH RECURSIVE reach (root, oid) AS (
    SELECT CASE WHEN d.proname = 'moderation_opinions_remove' THEN d.proname ELSE 'dating' END, d.oid FROM w9a_dat AS d
    UNION
    SELECT reach.root, e.b FROM reach JOIN w9a_edge AS e ON e.a = reach.oid)
  SELECT * FROM reach;

DO $$
DECLARE
  r record;
  c record;
  v_spans int[][];
  v_grp int[];
  v_n int;
  v_k int;
  v_li int;
  v_ri int;
  v_lo int;
  v_hi int;
  v_obj text;
  v_args text[];
  v_keys text[];
  v_jsonb text[];
  v_types text[];
  v_routes text[];
  v_val text;
  v_lit text;
  v_bad text := '';
  -- §3.13's three pushes, the only bodies a Dating push may carry.
  v_copies constant text[] := ARRAY['You have something new in Attune.',
                                    'A quick check-in from Attune.',
                                    'Something you asked about is ready in Attune.'];
  v_payload_keys constant text[] := ARRAY['''type''', '''route''', '''title''', '''body'''];
BEGIN
  -- Dating's functions: by name, by naming a Dating relation (public or
  -- private), or as a trigger on a Dating table (Task 9, Re-2-M1). Audited:
  -- each of them (function or procedure) that writes the push queue,
  -- qualified or not, and every queue writer reached from any of them
  -- through helpers called by name, to a fixpoint; and Dating's
  -- triggers on the queue. One walk is exempt, by root and writer, as it is
  -- not a Dating push: moderation_opinions_remove reaches Opinions'
  -- enqueue_forum_notification (through admin_confirm_content_removal).
  -- (W8 final server fix, Task 9 M-2: prepare_account_deletion's walk to
  -- the Relationship path's relationship_cancel_pending_pushes, through
  -- relationship_end_internal, is no longer exempt: that writer only
  -- cancels, so it passes the audit, and is audited like any other.)
  FOR r IN
    -- Spec 2 W9 (carry 1): the walk is w9a_reach (above); a queue write may
    -- be quoted, schema-qualified or a MERGE.
    WITH fn AS (SELECT * FROM w9a_fn),
    dat AS (SELECT * FROM w9a_dat),
    reach AS (SELECT * FROM w9a_reach),
    wr AS (
      SELECT * FROM fn
       WHERE fn.src ~* '\m(insert\s+into|update|merge\s+into)\s+(only\s+)?("?[a-z_]+"?\s*\.\s*)?"?scheduled_notifications"?\M')
    SELECT wr.oid, wr.sig, wr.src FROM wr
     WHERE wr.oid IN (SELECT reach.oid FROM reach
                       WHERE (reach.root, wr.proname::text) IS DISTINCT FROM ('moderation_opinions_remove', 'enqueue_forum_notification'))
       -- Spec 2 W9: the push queue's own triggers (its guards, reached now
       -- through every write to it) are audited only when they are Dating's
       -- (the UNION below), as before.
       AND wr.oid NOT IN (SELECT t.tgfoid FROM pg_trigger AS t
                           WHERE t.tgrelid = 'public.scheduled_notifications'::regclass AND NOT t.tgisinternal)
    UNION
    SELECT dat.oid, dat.sig, dat.src FROM dat
     WHERE dat.oid IN (SELECT t.tgfoid FROM pg_trigger AS t
                        WHERE t.tgrelid = 'public.scheduled_notifications'::regclass AND NOT t.tgisinternal)
  LOOP
    -- The function's jsonb variables and parameters.
    v_jsonb := ARRAY(SELECT DISTINCT lower(m[1]) FROM regexp_matches(r.src, '\m([a-z_][a-z0-9_]*)\s+(?:constant\s+)?jsonb?\M', 'gi') AS m)
            || ARRAY(SELECT DISTINCT lower(m[1]) FROM regexp_matches(pg_get_function_arguments(r.oid), '\m([a-z_][a-z0-9_]*)\s+jsonb?\M', 'gi') AS m);
    -- The payload objects, and the ones a jsonb `||` joins (I-2): a jsonb
    -- `||` joins only json(b)_build_object calls; anything else beside it
    -- (a jsonb variable or parameter, a literal, a call) fails.
    v_spans := ARRAY(SELECT ARRAY[sp.s, sp.o, sp.e] FROM pg_temp.w8a_spans(r.src) AS sp ORDER BY sp.s);
    v_n := coalesce(array_length(v_spans, 1), 0);
    v_grp := ARRAY(SELECT g FROM generate_series(1, v_n) AS g);
    FOR c IN SELECT * FROM pg_temp.w8a_concats(r.src, v_jsonb) LOOP
      CONTINUE WHEN 'obj' NOT IN (c.l_kind, c.r_kind) AND 'jsonb' NOT IN (c.l_kind, c.r_kind);
      IF c.l_kind <> 'obj' THEN
        v_bad := v_bad || format(E'\n  %s concatenates %s onto a push payload', r.sig, coalesce(c.l_tok, 'an expression'));
      END IF;
      IF c.r_kind <> 'obj' THEN
        v_bad := v_bad || format(E'\n  %s concatenates %s onto a push payload', r.sig, coalesce(c.r_tok, 'an expression'));
      END IF;
      IF c.l_kind = 'obj' AND c.r_kind = 'obj' THEN
        -- One payload: the two objects' groups merge.
        v_li := (SELECT g FROM generate_series(1, v_n) AS g WHERE v_spans[g][3] = c.l_e LIMIT 1);
        v_ri := (SELECT g FROM generate_series(1, v_n) AS g WHERE v_spans[g][1] IN (c.r_s, c.r_s + 11) LIMIT 1);
        v_lo := least(v_grp[v_li], v_grp[v_ri]);
        v_hi := greatest(v_grp[v_li], v_grp[v_ri]);
        v_grp := ARRAY(SELECT CASE WHEN u.x = v_hi THEN v_lo ELSE u.x END
                         FROM unnest(v_grp) WITH ORDINALITY AS u(x, o) ORDER BY u.o);
      END IF;
    END LOOP;
    -- Each payload (a group of joined objects, or one object naming a
    -- payload key), read as a whole.
    v_k := 0;
    FOR c IN SELECT DISTINCT x AS grp FROM unnest(v_grp) AS x LOOP
      v_args := '{}';
      v_obj := '';
      FOR g IN 1 .. v_n LOOP
        IF v_grp[g] = c.grp THEN
          v_obj := v_obj || E'\n' || substr(r.src, v_spans[g][2] + 1, v_spans[g][3] - v_spans[g][2] - 1);
          v_args := v_args || pg_temp.w8a_args(substr(r.src, v_spans[g][2] + 1, v_spans[g][3] - v_spans[g][2] - 1));
          IF cardinality(pg_temp.w8a_args(substr(r.src, v_spans[g][2] + 1, v_spans[g][3] - v_spans[g][2] - 1))) % 2 = 1 THEN
            v_bad := v_bad || format(E'\n  %s builds an object with an odd argument count', r.sig);
          END IF;
        END IF;
      END LOOP;
      v_keys := ARRAY(SELECT v_args[i] FROM generate_subscripts(v_args, 1) AS i WHERE i % 2 = 1);
      CONTINUE WHEN NOT (v_keys && v_payload_keys)
                AND (SELECT count(*) FROM unnest(v_grp) AS x WHERE x = c.grp) = 1;
      v_k := v_k + 1;
      IF NOT (v_keys <@ v_payload_keys) THEN
        v_bad := v_bad || format(E'\n  %s puts keys %s in a push payload', r.sig, v_keys);
      END IF;
      -- Every value of every key (a key given twice is checked twice).
      v_types := '{}'; v_routes := '{}';
      FOR i IN 1 .. coalesce(array_length(v_args, 1), 0) / 2 LOOP
        v_val := v_args[2 * i];
        v_lit := pg_temp.w8a_lit(v_val);
        CASE v_args[2 * i - 1]
          WHEN '''type''' THEN
            v_types := v_types || coalesce(v_lit, v_val);
            IF v_lit IS NULL OR v_lit NOT IN ('me_update', 'me_checkin') THEN
              v_bad := v_bad || format(E'\n  %s writes push type %s', r.sig, v_val);
            END IF;
          WHEN '''route''' THEN
            v_routes := v_routes || coalesce(v_lit, v_val);
          WHEN '''title''' THEN
            IF v_lit IS DISTINCT FROM 'Attune' THEN
              v_bad := v_bad || format(E'\n  %s titles a push other than Attune', r.sig);
            END IF;
          WHEN '''body''' THEN
            -- A copy; the helper's call itself; or a CONSTANT declared from
            -- the helper and never assigned again (fix round 2, Re-M-2).
            IF NOT (coalesce(v_lit = ANY (v_copies), false)
                    OR v_val ~ '^private\.dating_me_update_body\s*\([^()]*\)$'
                    OR (v_val ~ '^[a-z_][a-z0-9_]*$'
                        AND r.src ~* ('\m' || v_val || '\s+constant\s+text\s*(:=|=|default)\s*private\.dating_me_update_body\s*\([^()]*\)\s*;')
                        AND r.src !~* ('\m' || v_val || '\s*:?=[^=]')
                        AND r.src !~* ('\minto\s+(strict\s+)?([a-z0-9_]+\s*,\s*)*' || v_val || '\M')
                        AND r.src !~* ('\mfor\s+' || v_val || '\M'))) THEN
              v_bad := v_bad || format(E'\n  %s writes the push body %s', r.sig, v_val);
            END IF;
          ELSE
            NULL;
        END CASE;
      END LOOP;
      IF NOT ('''type''' = ANY (v_keys)) OR NOT ('''title''' = ANY (v_keys)) OR NOT ('''body''' = ANY (v_keys)) THEN
        v_bad := v_bad || format(E'\n  %s writes push type %s', r.sig, 'none (a payload without its type, title or body)');
      END IF;
      -- The route is the type's: me_update to me, me_checkin to me_checkin.
      IF cardinality(ARRAY(SELECT DISTINCT x FROM unnest(v_types) AS x)) <> 1
         OR ARRAY(SELECT DISTINCT x FROM unnest(v_routes) AS x)
            IS DISTINCT FROM ARRAY[CASE v_types[1] WHEN 'me_update' THEN 'me' ELSE 'me_checkin' END] THEN
        v_bad := v_bad || format(E'\n  %s routes a %s push to %s', r.sig, coalesce(v_types[1], 'untyped'), v_routes);
      END IF;
      -- Every literal in the payload, on any line: none says "dating".
      IF EXISTS (SELECT 1 FROM regexp_matches(v_obj, '''((?:[^'']|'''')*)''', 'g') AS m WHERE m[1] ~* 'dating') THEN
        v_bad := v_bad || format(E'\n  %s puts "dating" in a push payload', r.sig);
      END IF;
    END LOOP;
    -- A writer (an insert) has a payload this audit reads; an update (a
    -- cancel) needs none.
    IF r.src ~* '\m(insert\s+into|merge\s+into)\s+(only\s+)?("?[a-z_]+"?\s*\.\s*)?"?scheduled_notifications"?\M' AND v_k = 0 THEN -- Spec 2 W9
      v_bad := v_bad || format(E'\n  %s writes a push this audit cannot read', r.sig);
    END IF;
    -- Backstops over the whole source (a payload built another way).
    v_types := ARRAY(SELECT DISTINCT m[1] FROM regexp_matches(r.src, '''type''\s*,\s*''([^'']*)''', 'g') AS m);
    IF NOT (v_types <@ ARRAY['me_update', 'me_checkin']) THEN
      v_bad := v_bad || format(E'\n  %s writes push types %s', r.sig, v_types);
    END IF;
    IF EXISTS (SELECT 1 FROM regexp_matches(r.src, '''route''\s*,\s*''([^'']*)''', 'g') AS m
                WHERE m[1] NOT IN ('me', 'me_checkin')) THEN
      v_bad := v_bad || format(E'\n  %s routes a push outside me and me_checkin', r.sig);
    END IF;
    IF EXISTS (SELECT 1 FROM regexp_matches(r.src, '''title''\s*,\s*''([^'']*)''', 'g') AS m WHERE m[1] <> 'Attune') THEN
      v_bad := v_bad || format(E'\n  %s titles a push other than Attune', r.sig);
    END IF;
    IF EXISTS (SELECT 1 FROM regexp_matches(r.src, '''body''\s*,\s*''((?:[^'']|'''')*)''', 'g') AS m
                WHERE replace(m[1], '''''', '''') <> ALL (v_copies)) THEN
      v_bad := v_bad || format(E'\n  %s writes a push body that is not one of the copies', r.sig);
    END IF;
    -- A payload edited in place, or written as a JSON literal, can't be read.
    IF r.src ~* '(\mjsonb?_(set|insert|set_lax)\s*\(|\mmetadata\s*\|\||\|\|\s*(\w+\.)?metadata\M)' THEN
      v_bad := v_bad || format(E'\n  %s edits a push payload in place', r.sig);
    END IF;
    IF EXISTS (SELECT 1 FROM regexp_matches(r.src, '''((?:[^'']|'''')*)''', 'g') AS m
                WHERE m[1] ~ '^\s*\{.*"(type|route|title|body)"') THEN
      v_bad := v_bad || format(E'\n  %s writes a push payload as a JSON literal', r.sig);
    END IF;
  END LOOP;
  -- Spec 2 W9 (carry 1): nothing the Dating walk reaches writes another
  -- queue table (the push queue's own triggers aside), calls
  -- send-notification or OneSignal, or EXECUTEs a statement built at run
  -- time (format, a variable, ||: a write the walk could not follow).
  FOR r IN
    SELECT f.oid, f.sig, f.src, lower(pg_temp.w8a_mask(f.src)) AS msrc, n.nspname::text AS nsp -- Spec 2 W9 (fix round 1)
      FROM w9a_fn AS f JOIN pg_proc AS p ON p.oid = f.oid JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE f.oid IN (SELECT x.oid FROM w9a_reach AS x WHERE x.root = 'dating')
  LOOP
    IF r.src ~* '\m(insert\s+into|update|merge\s+into)\s+(only\s+)?("?[a-z_]+"?\s*\.\s*)?"?(in_app_notifications|message_notification_outbox|verdict_notification_outbox)"?\M'
       AND r.oid NOT IN (SELECT t.tgfoid FROM pg_trigger AS t
                          WHERE t.tgrelid = 'public.scheduled_notifications'::regclass AND NOT t.tgisinternal) THEN
      v_bad := v_bad || format(E'\n  %s writes a notification queue other than the neutral push queue', r.sig);
    END IF;
    IF r.src ~* '(send-notification|onesignal)' THEN
      v_bad := v_bad || format(E'\n  %s sends a notification itself', r.sig);
    END IF;
    -- Spec 2 W9 (Task 3 fix round 1, M-4): an allow list. Every EXECUTE
    -- is one literal (quoted, or dollar-quoted with only $n inside) and
    -- then USING, INTO or ';', or a GRANT/REVOKE EXECUTE ON FUNCTION or a
    -- trigger's EXECUTE FUNCTION; anything else is built at run time.
    IF (SELECT count(*) FROM regexp_matches(r.msrc, '\mexecute\M', 'g'))
       > (SELECT count(*) FROM regexp_matches(r.msrc,
            '\mexecute\s+(?:(?:''x*'')+|\$(\w*)\$(?:[^$]|\$[0-9])*\$\1\$)\s*(?:using|into|;)', 'g'))
         + (SELECT count(*) FROM regexp_matches(r.msrc,
            '\mexecute\s+(?:on\s+(?:all\s+)?(?:function|procedure|routine)s?|function|procedure)\M', 'g')) THEN
      v_bad := v_bad || format(E'\n  %s runs a statement built at run time, which the audit cannot follow', r.sig);
    END IF;
    -- Spec 2 W9 (Task 3 fix round 1, M-3): an HTTP call (its URL may come
    -- from anywhere) only from the two reached today: photo processing and
    -- the moderation alert. The transport itself (net, supabase_functions)
    -- aside.
    IF r.src ~* '\mhttp(_[a-z]+)?\s*\(' AND r.nsp NOT IN ('net', 'supabase_functions')
       AND r.sig NOT IN ('dating_moderation_sla_check(timestamp with time zone)', 'enqueue_dating_photo_processing()') THEN
      v_bad := v_bad || format(E'\n  %s makes an HTTP call the audit has not allowed', r.sig);
    END IF;
  END LOOP;
  -- Spec 2 W9 (Task 3 fix round 1, M-3): a trigger that fires on a write
  -- the Dating walk reaches takes no arguments (a dashboard webhook keeps
  -- its URL there), is not supabase_functions' and is SQL or plpgsql.
  FOR r IN
    SELECT DISTINCT t.tgname::text AS tgname, t.tgrelid::regclass::text AS tbl
      FROM w9a_write AS w JOIN pg_trigger AS t ON t.tgrelid = w.rel AND NOT t.tgisinternal
      JOIN pg_proc AS p ON p.oid = t.tgfoid JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE w.a IN (SELECT x.oid FROM w9a_reach AS x WHERE x.root = 'dating')
       AND t.tgtype & CASE w.op WHEN 'i' THEN 4 WHEN 'u' THEN 16 ELSE 8 END <> 0
       AND (t.tgnargs > 0 OR n.nspname = 'supabase_functions'
            OR p.prolang NOT IN (SELECT l.oid FROM pg_language AS l WHERE l.lanname IN ('plpgsql', 'sql')))
  LOOP
    v_bad := v_bad || format(E'\n  trigger %s on %s fires on a Dating write and takes arguments or calls out, which the audit cannot read',
                             r.tgname, r.tbl);
  END LOOP;
  -- Spec 2 W9 (Task 3 fix round 1, M-2): a SQL-standard body (BEGIN
  -- ATOMIC) keeps no source the walk can read.
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
      FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prosqlbody IS NOT NULL
  LOOP
    v_bad := v_bad || format(E'\n  %s has a SQL-standard body, which the audit cannot read', r.sig);
  END LOOP;
  -- The body helper: every body it returns is one of the copies, and each
  -- is the whole answer (fix round 2, Re-M-3: never a copy || more).
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig, p.prosrc AS src
      FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'private' AND p.proname = 'dating_me_update_body'
  LOOP
    IF r.src !~* '\mthen\s+''' OR r.src ~* '\m(then|else)\s+(?!null\M)[^''\s]'
       OR EXISTS (SELECT 1 FROM regexp_matches(r.src, '\m(?:then|else)\s+''((?:[^'']|'''')*)''\s*(\S*)', 'gi') AS m
                   WHERE replace(m[1], '''''', '''') <> ALL (v_copies) OR m[2] !~* '^(when|else|end|;)') THEN
      v_bad := v_bad || format(E'\n  %s returns a push body that is not one of the copies', r.sig);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Dating push is not neutral:%', v_bad;
  END IF;
  -- The writers and the helper this audit reads (so a rename can't empty it).
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'dating_queue_me_update')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'schedule_dating_checkin')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'dating_me_update_body') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Dating push writers moved; the audit reads nothing';
  END IF;
END $$;

-- =====================================================================
-- Setup for B onward (W8b): the keys, the flags (the traveller flag is
-- turned on here only, inside this file's transaction), Ghana and the UK
-- open, and the people. Fixture ids 8a800000-...-0000000000nn, phones
-- +1555981nn: B 01-29, C 30-59.
-- =====================================================================
DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w8-device-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w8-field-key-0123456789abcdef-0123', true);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w8-push-key', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset
INSERT INTO public.feature_flags (key, enabled)
VALUES ('dating_mode_enabled', true), ('dating_candidate_generation', true), ('dating_same_gender_matching', true),
       ('dating_match_messaging', true), ('dating_profile_photos', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset
UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() WHERE state = 'active';
UPDATE public.dating_algorithm_configs
   SET state = 'active', activated_at = now(), product_review_ref = 'DEV-product', clinical_review_ref = 'DEV-clinical',
       fairness_review_ref = 'DEV-fairness', safety_review_ref = 'DEV-safety'
 WHERE version = 'introductions_v2';

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('8a800000-0000-0000-0000-' || lpad(p_n, 12, '0'))::uuid;
$$;
-- The phone's install id (the x-attune-device header) and its hash.
CREATE FUNCTION pg_temp.dev(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('w8-device-' || p_n);
$$;
CREATE FUNCTION pg_temp.hash(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(extensions.digest(pg_temp.dev(p_n), 'sha256'), 'hex');
$$;
CREATE FUNCTION pg_temp.ready(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
  d constant jsonb := '{"identity": "woman", "seeking": ["man"], "country": "GH", "region": "AA", "years": 30,
    "days": 40, "phone": null, "state": "active"}'::jsonb || o;
  v_phone constant text := coalesce(d ->> 'phone', '+1555981' || p_n);
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, ltrim(v_phone, '+'), now(), now() - make_interval(days => (d ->> 'days')::int));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, v_phone, 'Trip ' || p_n, 'dating', now() - make_interval(days => (d ->> 'days')::int), now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, (current_date - make_interval(years => (d ->> 'years')::int) - interval '10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, activated_at)
  VALUES (v_u, d ->> 'state', now(), CASE WHEN d ->> 'state' = 'active' THEN now() END);
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, moderation_state, verification_state,
    country_code, region_code, intention, timeline_visible, not_married_attested_at, attestation_version,
    children_have, children_want, faith_visible)
  VALUES (v_u, 'Trip ' || p_n, 'active', 'approved', 'verified', d ->> 'country', d ->> 'region',
    'committed', true, now(), '2026-10-v1', false, 'yes', false);
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, region_scope, open_abroad, want_must_match, exclude_parents)
  VALUES (v_u, 25, 40, 'country', '{}', false, false);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt(jsonb_build_object('identity', d ->> 'identity', 'pools', jsonb_build_array(d ->> 'identity'))),
          private.dating_field_encrypt(jsonb_build_object('seeking', d -> 'seeking')));
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer, moderation_state)
  SELECT v_u, n, CASE n WHEN 1 THEN 'perfect_sunday' ELSE 'ask_me_about' END, 'A traveller fixture answer ' || n, 'approved'
    FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_u, 'w8/' || v_u || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at,
    identity_method, identity_result, identity_vendor, identity_decided_at)
  VALUES (v_u, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now());
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w8-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS p;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_u, pg_temp.hash(p_n), now(), now());
  RETURN v_u;
END $$;
-- A UK person (region TLI).
CREATE FUNCTION pg_temp.uk(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE sql AS $$
  SELECT pg_temp.ready(p_n, '{"country": "GB", "region": "TLI", "phone": null}'::jsonb || o);
$$;
CREATE FUNCTION pg_temp.as_person(p uuid, p_device text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.headers', CASE WHEN p_device IS NULL THEN '' ELSE json_build_object('x-attune-device', p_device)::text END, true);
END $$;
CREATE FUNCTION pg_temp.as_db() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.headers', '', true);
END $$;
-- [p]'s own call from phone [p_n] (null: no install id), as jsonb.
CREATE FUNCTION pg_temp.j(p uuid, p_n text, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p, CASE WHEN p_n IS NULL THEN NULL ELSE pg_temp.dev(p_n) END);
  EXECUTE p_sql INTO v;
  PERFORM pg_temp.as_db();
  RETURN v::jsonb;
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_db();
  RETURN jsonb_build_object('raised', SQLSTATE || ':' || SQLERRM);
END $$;
-- dating-device-check's call, as the service role: [p] on phone [p_n].
CREATE FUNCTION pg_temp.check(p uuid, p_n text, p_ip text, p_net text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.record_dating_device_check(p, CASE WHEN p_n IS NULL THEN NULL ELSE pg_temp.hash(p_n) END, p_ip, p_net);
  RESET ROLE;
  RETURN v;
END $$;
-- The row's last check moves [p_min] minutes back (the next check records).
CREATE FUNCTION pg_temp.age(p uuid, p_min int) RETURNS void LANGUAGE sql AS $$
  UPDATE public.dating_session_context SET checked_at = checked_at - make_interval(mins => p_min) WHERE user_id = p;
$$;
CREATE FUNCTION pg_temp.ctx(p uuid) RETURNS public.dating_session_context LANGUAGE sql AS $$
  SELECT * FROM public.dating_session_context WHERE user_id = p;
$$;
CREATE FUNCTION pg_temp.flag(p_on boolean) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_traveller_detection', p_on)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
$$;
CREATE FUNCTION pg_temp.key(p text) RETURNS text LANGUAGE sql AS $$
  SELECT 'w8-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
$$;
CREATE FUNCTION pg_temp.home(p uuid, p_n text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, 'SELECT public.get_dating_home()');
$$;

-- =====================================================================
-- B1. The flag is off as the migration leaves it, with its production
--     gate; record_dating_device_check is the service role's alone and
--     the trip choice the app's.
-- =====================================================================
DO $$
BEGIN
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'dating_traveller_detection') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_traveller_detection is not off';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_traveller_detection') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_traveller_detection has no production gate';
  END IF;
  IF has_function_privilege('authenticated', 'public.record_dating_device_check(uuid,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_dating_device_check(uuid,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.set_dating_trip_choice(text,boolean)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.set_dating_trip_choice(text,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the W8b grants are wrong';
  END IF;
END $$;

-- =====================================================================
-- B2. The device check records only for someone with Dating data, from a
--     phone Dating trusts (or before any is bound), at most once per 15
--     minutes; refusals are fixed codes; no country is stored.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.uk('01');
  v_x constant uuid := pg_temp.id('02');
  v jsonb;
  v_at timestamptz;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_x, '155598102', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_x, '+155598102', 'No dating');
  IF pg_temp.check(gen_random_uuid(), '01', 'GB') ->> 'reason' IS DISTINCT FROM 'unavailable'
     OR pg_temp.check(v_a, '01', 'G1') ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.check(v_a, '01', 'GB', 'ABC') ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad device check is not a fixed refusal';
  END IF;
  v := pg_temp.check(v_a, '99', 'AE');
  IF v IS DISTINCT FROM '{"ok": true, "away": false, "here": null, "trusted": false}'::jsonb OR (pg_temp.ctx(v_a)).user_id IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone Dating does not trust recorded a context: %', v;
  END IF;
  v := pg_temp.check(v_x, NULL, 'AE');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR EXISTS (SELECT 1 FROM public.dating_session_context WHERE user_id = v_x) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone with no Dating data got a context row: %', v;
  END IF;
  v := pg_temp.check(v_a, '01', 'fr');
  IF (v ->> 'trusted')::boolean IS NOT TRUE OR (pg_temp.ctx(v_a)).away_from_home IS NOT TRUE
     OR (pg_temp.ctx(v_a)).mismatch_streak IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first check did not record: % %', v, to_jsonb(pg_temp.ctx(v_a));
  END IF;
  v_at := (pg_temp.ctx(v_a)).checked_at;
  PERFORM pg_temp.check(v_a, '01', 'ES');
  IF (pg_temp.ctx(v_a)).checked_at IS DISTINCT FROM v_at OR (pg_temp.ctx(v_a)).mismatch_streak IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a check within 15 minutes recorded again';
  END IF;
  PERFORM pg_temp.age(v_a, 16);
  PERFORM pg_temp.check(v_a, '01', 'ES');
  IF (pg_temp.ctx(v_a)).mismatch_streak IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a check 16 minutes later did not count';
  END IF;
  -- No column can hold a country or an address: every one is a flag, a
  -- number, a time or the person's id.
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'dating_session_context'
                AND data_type IN ('text', 'character', 'character varying', 'inet', 'cidr', 'jsonb', 'json', 'bytea', 'ARRAY')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_session_context has a column that can hold a country or an address';
  END IF;
END $$;

-- =====================================================================
-- B3. Gate 7 (§2.1): with the flag on, a candidate whose latest context
--     says Dating isn't allowed where they are is 'away' (and out of
--     others' days); setup goes ahead; with the flag off nothing changes.
--     The answer names the place only while it restricts, and only with
--     the flag on.
-- =====================================================================
DO $$
DECLARE
  v_g constant uuid := pg_temp.ready('03');
  v jsonb;
BEGIN
  v := pg_temp.check(v_g, '03', 'AE');
  IF v ->> 'away' IS DISTINCT FROM 'false' OR v ->> 'here' IS NOT NULL
     OR public.dating_eligibility(v_g, 'candidate') IS DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off a trip changed something: % %', v, public.dating_eligibility(v_g, 'candidate');
  END IF;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.age(v_g, 16);
  v := pg_temp.check(v_g, '03', 'AE');
  IF v IS DISTINCT FROM '{"ok": true, "away": true, "here": "AE", "trusted": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the check in the UAE answered %', v;
  END IF;
  IF public.dating_eligibility(v_g, 'candidate') IS DISTINCT FROM 'away'
     OR public.dating_eligibility(v_g, 'setup') IS DISTINCT FROM 'eligible'
     OR public.dating_candidate_is_current(v_g) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: gate 7 is wrong: % / %', public.dating_eligibility(v_g, 'candidate'),
      public.dating_eligibility(v_g, 'setup');
  END IF;
  -- Back in Ghana: the gate opens at once.
  PERFORM pg_temp.age(v_g, 16);
  v := pg_temp.check(v_g, '03', 'GH');
  IF public.dating_eligibility(v_g, 'candidate') IS DISTINCT FROM 'eligible' OR v ->> 'here' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: home again, the gate stayed shut: %', v;
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- B4. The home (§3.1, §3.11): away is its own state with the trip; a UK
--     person who meets women visiting Ghana carries a same-gender trip
--     (state active; fix round 4: its kind only, the note and the choice
--     are the phone's), one who meets men none; the away note shows until
--     the person chooses; the plain-icon offer is for Tier 1/2 at D13 only.
--     With the flag off: no trip, no away.
-- =====================================================================
DO $$
DECLARE
  v_g constant uuid := pg_temp.ready('04');
  v_w constant uuid := pg_temp.uk('05', '{"seeking": ["woman"]}');
  v_m constant uuid := pg_temp.uk('06');
  v_s constant uuid := pg_temp.ready('07', '{"state": "profile_draft"}');
  v_u constant uuid := pg_temp.uk('08', '{"state": "profile_draft"}');
  v jsonb;
BEGIN
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_g, '04', 'AE');
  v := pg_temp.home(v_g, '04');
  IF v ->> 'state' IS DISTINCT FROM 'away'
     OR v -> 'trip' IS DISTINCT FROM '{"kind": "away", "note": true, "show_here": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the away home is %', v;
  END IF;
  PERFORM pg_temp.check(v_w, '05', 'GH');
  PERFORM pg_temp.check(v_m, '06', 'GH');
  v := pg_temp.home(v_w, '05');
  IF v ->> 'state' IS DISTINCT FROM 'active'
     OR v -> 'trip' IS DISTINCT FROM '{"kind": "same_gender"}'::jsonb THEN -- fix round 4 (R-T4-9)
    RAISE EXCEPTION 'CONTRACT VIOLATED: a same-gender trip home is %', v;
  END IF;
  v := pg_temp.home(v_m, '06');
  IF v ->> 'state' IS DISTINCT FROM 'active' OR v ? 'trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a man-woman person in Ghana carries a trip: %', v;
  END IF;
  -- D13: Ghana (Tier 1) is offered the plain icon, the UK (Tier 3) not.
  IF (pg_temp.home(v_s, '07') ->> 'offer_plain_icon') IS DISTINCT FROM 'true'
     OR pg_temp.home(v_u, '08') ? 'offer_plain_icon'
     OR pg_temp.home(v_g, '04') ? 'offer_plain_icon' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the plain-icon offer is wrong: % / %', pg_temp.home(v_s, '07'), pg_temp.home(v_u, '08');
  END IF;
  PERFORM pg_temp.flag(false);
  v := pg_temp.home(v_g, '04');
  IF v ->> 'state' IS DISTINCT FROM 'active' OR v ? 'trip' OR pg_temp.home(v_w, '05') ? 'trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the home shows a trip: %', v;
  END IF;
END $$;

-- =====================================================================
-- B5. The trip choice (§3.11; fix round 4, R-T4-9: an away trip's only):
--     Show it on this phone anyway and Keep it hidden each mark the note
--     seen; a replay is the same answer and changes nothing; both need a
--     trusted phone; nothing to choose is no_trip and spends no key (a
--     retry once there is a trip acts); a trip ends after 7 days back home
--     (the note may show on the next one; showing ends with it), and a
--     replay of its key then answers no_trip.
-- =====================================================================
DO $$
DECLARE
  v_g constant uuid := pg_temp.ready('09');
  v_k constant text := pg_temp.key('show');
  v_k0 constant text := pg_temp.key('none');
  v jsonb;
BEGIN
  PERFORM pg_temp.flag(true);
  IF pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', v_k0)) ->> 'reason'
     IS DISTINCT FROM 'no_trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a choice with no trip was taken';
  END IF;
  -- R-T4-1, fix round 4: no_trip answers before the claim.
  IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS i WHERE i.user_id = v_g AND i.idempotency_key = v_k0) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a choice refused with no_trip spent its key';
  END IF;
  PERFORM pg_temp.check(v_g, '09', 'AE');
  IF pg_temp.j(v_g, '09', 'SELECT public.set_dating_trip_choice(''short'', true)') ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, NULL)', v_k)) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(v_g, '98', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('x'))) ->> 'reason'
        IS DISTINCT FROM 'reverify_device' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad trip choice was taken';
  END IF;
  v := pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', v_k));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.home(v_g, '09') -> 'trip' IS DISTINCT FROM '{"kind": "away", "note": false, "show_here": true}'::jsonb
     OR pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', v_k)) IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway answered % and left %', v, pg_temp.home(v_g, '09');
  END IF;
  -- Fix round 1 (C-1): Keep it hidden needs the trusted phone too (any other
  -- answer would tell that phone whether there is a trip, and of what kind).
  v := pg_temp.j(v_g, '98', format('SELECT public.set_dating_trip_choice(%L, false)', pg_temp.key('hide98')));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}'::jsonb OR (pg_temp.ctx(v_g)).show_here IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Keep it hidden from a phone Dating does not trust answered %', v;
  END IF;
  v := pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, false)', pg_temp.key('hide')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR (pg_temp.ctx(v_g)).show_here IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Keep it hidden answered %', v;
  END IF;
  -- A replay answers ok and changes nothing (Keep it hidden stands).
  v := pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', v_k));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR (pg_temp.ctx(v_g)).show_here IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay of Show it on this phone anyway answered % and acted again', v;
  END IF;
  -- R-T4-1, fix round 4: a key refused with no_trip was never spent, so
  -- its retry now that there is a trip acts.
  v := pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', v_k0));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR (pg_temp.ctx(v_g)).show_here IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a key refused with no_trip was spent: % (show_here %)', v, (pg_temp.ctx(v_g)).show_here;
  END IF;
  PERFORM pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('show2')));
  -- Home for 6 days: the same trip. For 8: it ended.
  PERFORM pg_temp.age(v_g, 16);
  PERFORM pg_temp.check(v_g, '09', 'GH');
  UPDATE public.dating_session_context SET home_since = now() - interval '6 days' WHERE user_id = v_g;
  PERFORM pg_temp.age(v_g, 16);
  PERFORM pg_temp.check(v_g, '09', 'GH');
  IF (pg_temp.ctx(v_g)).trip_note_shown_at IS NULL OR (pg_temp.ctx(v_g)).show_here IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 6 days home ended the trip';
  END IF;
  UPDATE public.dating_session_context SET home_since = now() - interval '8 days' WHERE user_id = v_g;
  PERFORM pg_temp.age(v_g, 16);
  PERFORM pg_temp.check(v_g, '09', 'GH');
  IF (pg_temp.ctx(v_g)).trip_note_shown_at IS NOT NULL OR (pg_temp.ctx(v_g)).show_here IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 8 days home did not end the trip: %', to_jsonb(pg_temp.ctx(v_g));
  END IF;
  IF pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('home'))) ->> 'reason'
     IS DISTINCT FROM 'no_trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a choice was taken at home';
  END IF;
  -- The trip its key chose is over: a replay answers no_trip, never ok for nothing.
  IF pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', v_k)) IS DISTINCT FROM '{"ok": false, "reason": "no_trip"}'::jsonb
     OR (pg_temp.ctx(v_g)).show_here IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay after the trip ended answered %', pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', v_k));
  END IF;
  -- Abroad again: the next trip's note shows.
  PERFORM pg_temp.age(v_g, 16);
  PERFORM pg_temp.check(v_g, '09', 'AE');
  IF pg_temp.home(v_g, '09') -> 'trip' ->> 'note' IS DISTINCT FROM 'true' OR (pg_temp.ctx(v_g)).home_since IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the next trip has no note';
  END IF;
  PERFORM pg_temp.flag(false);
  IF pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('off'))) ->> 'reason'
     IS DISTINCT FROM 'no_trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a trip choice was taken with the flag off';
  END IF;
END $$;

-- =====================================================================
-- B6. The location signal (§5.10): with the flag on, 7 checks in a row
--     away from the Dating country open one low-priority signal case;
--     with the flag off, none.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.uk('10');
  v_b constant uuid := pg_temp.uk('11');
BEGIN
  PERFORM pg_temp.flag(true);
  FOR i IN 1..8 LOOP
    PERFORM pg_temp.check(v_a, '10', 'FR');
    PERFORM pg_temp.age(v_a, 16);
    IF i = 6 AND EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = v_a) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the signal opened before 7';
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.dating_moderation_cases
       WHERE target_user_id = v_a AND kind = 'signal' AND signal_kind = 'location_mismatch' AND priority = 'P3') IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 7 checks away did not open one P3 location signal';
  END IF;
  PERFORM pg_temp.flag(false);
  FOR i IN 1..8 LOOP
    PERFORM pg_temp.check(v_b, '11', 'FR');
    PERFORM pg_temp.age(v_b, 16);
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the location signal opened with the flag off';
  END IF;
END $$;

-- =====================================================================
-- B7. (Task 4 rulings R-T4-1, R-T4-3; fix round 1 C-1, I-2, M-1) A trip
--     is what the home shows: nothing to choose where the home shows no
--     trip (a man-woman person in Ghana), and a refused choice never
--     spends its key. Every answer to a phone Dating doesn't trust is the
--     same, whoever the person is and whatever they choose. The phone's
--     country standing in for an unresolved IP is "here" (§2.3): a UK
--     woman who meets women on a Ghana number has the same-gender trip
--     whose hiding Task 5 applies and a note naming Ghana. Fix round 4
--     (R-T4-9): her note and "Show it on this phone anyway" are her phone's
--     (passed to the reads as p_show_same_gender); the server's choice
--     answers her no_trip and keeps nothing, as for the man-woman person.
-- =====================================================================
DO $$
DECLARE
  v_m constant uuid := pg_temp.uk('12');
  v_p constant uuid := pg_temp.uk('13', '{"seeking": ["woman"], "phone": "+233201981013"}');
  v_q constant uuid := pg_temp.ready('14', '{"phone": "+971501981014"}');
  v_o constant uuid := pg_temp.uk('15', '{"seeking": ["woman"]}');
  v jsonb;
  v_untrusted jsonb := '[]'::jsonb;
  v_who uuid;
  v_n text;
  v_phone text;
  v_show boolean;
BEGIN
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_m, '12', 'GH');
  v := pg_temp.j(v_m, '12', format('SELECT public.set_dating_trip_choice(%L, false)', pg_temp.key('mw')));
  IF v ->> 'reason' IS DISTINCT FROM 'no_trip' OR (pg_temp.ctx(v_m)).trip_note_shown_at IS NOT NULL
     OR (SELECT c.xmax::text FROM public.dating_session_context AS c WHERE c.user_id = v_m) <> '0' -- fix round 5 (Re4-M-1): no row lock
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS i WHERE i.user_id = v_m AND i.operation = 'set_dating_trip_choice') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a choice was taken where the home shows no trip: %', v;
  END IF;
  v := pg_temp.check(v_p, '13', NULL);
  IF (pg_temp.ctx(v_p)).same_gender_allowed_here IS NOT FALSE OR (pg_temp.ctx(v_p)).away_from_home IS NOT FALSE
     OR v IS DISTINCT FROM '{"ok": true, "away": false, "here": "GH", "trusted": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the phone''s country is not where the same-gender trip is: % %', v, to_jsonb(pg_temp.ctx(v_p));
  END IF;
  v := pg_temp.home(v_p, '13');
  IF v ->> 'state' IS DISTINCT FROM 'active'
     OR v -> 'trip' IS DISTINCT FROM '{"kind": "same_gender"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the phone-country same-gender trip home is %', v;
  END IF;
  -- What Task 5's reads hide, the home explains; the phone's choice
  -- (p_show_same_gender) brings it back on that phone.
  IF private.dating_trip_hides(v_p, v_o, 'match') IS NOT TRUE
     OR private.dating_trip_hides(v_p, v_o, 'match', private.dating_same_gender_hiding(v_p) AND NOT false) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same-gender pair is not hidden on the trip';
  END IF;
  IF private.dating_trip_hides(v_p, v_o, 'match', private.dating_same_gender_hiding(v_p) AND NOT true) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the phone''s Show it on this phone anyway did not bring the pair back';
  END IF;
  -- C-1: a phone Dating doesn't trust (another install id, or none) gets one
  -- answer for both people and both choices, and changes nothing.
  FOREACH v_who IN ARRAY ARRAY[v_p, v_m] LOOP
    v_n := CASE WHEN v_who = v_p THEN '13' ELSE '12' END;
    FOREACH v_phone IN ARRAY ARRAY['98', NULL] LOOP
      FOREACH v_show IN ARRAY ARRAY[true, false] LOOP
        v := pg_temp.j(v_who, v_phone, format('SELECT public.set_dating_trip_choice(%L, %L)', pg_temp.key('u' || v_n), v_show));
        v_untrusted := v_untrusted || jsonb_build_array(v);
      END LOOP;
    END LOOP;
  END LOOP;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_untrusted) AS a(x)
              WHERE a.x IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}'::jsonb)
     OR (pg_temp.ctx(v_p)).trip_note_shown_at IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS i WHERE i.user_id IN (v_p, v_m)
                 AND i.operation = 'set_dating_trip_choice' AND i.idempotency_key LIKE 'w8-u%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone Dating does not trust learned something: %', v_untrusted;
  END IF;
  -- Fix round 4 (R-T4-9): the server takes no same-gender choice (an older
  -- app's call): no_trip before any claim, nothing written, both values.
  FOREACH v_show IN ARRAY ARRAY[false, true] LOOP
    v := pg_temp.j(v_p, '13', format('SELECT public.set_dating_trip_choice(%L, %L)', pg_temp.key('sg'), v_show));
    IF v IS DISTINCT FROM '{"ok": false, "reason": "no_trip"}'::jsonb
       OR (pg_temp.ctx(v_p)).trip_note_shown_at IS NOT NULL OR (pg_temp.ctx(v_p)).show_here IS NOT FALSE
       OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS i WHERE i.user_id = v_p AND i.operation = 'set_dating_trip_choice') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the server took a same-gender choice: % %', v, to_jsonb(pg_temp.ctx(v_p));
    END IF;
  END LOOP;
  -- Fix round 5 (Re4-M-1): neither the untrusted calls nor the no_trip ones
  -- left a row lock (her row was only inserted and updated by the check).
  IF (SELECT c.xmax::text FROM public.dating_session_context AS c WHERE c.user_id = v_p) <> '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a no_trip call left a row lock on the context row';
  END IF;
  -- While same-gender stays restricted where she is, the trip stays (8 days
  -- there, re-checked): the phone's answered note has a trip to belong to.
  PERFORM pg_temp.age(v_p, 16);
  PERFORM pg_temp.check(v_p, '13', NULL);
  UPDATE public.dating_session_context SET home_since = now() - interval '8 days' WHERE user_id = v_p;
  PERFORM pg_temp.age(v_p, 16);
  PERFORM pg_temp.check(v_p, '13', NULL);
  IF pg_temp.home(v_p, '13') -> 'trip' IS DISTINCT FROM '{"kind": "same_gender"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: somewhere same-gender is restricted the trip ended: %', pg_temp.home(v_p, '13');
  END IF;
  v := pg_temp.check(v_q, '14', NULL);
  IF (pg_temp.ctx(v_q)).dating_allowed_here IS NOT FALSE OR (pg_temp.ctx(v_q)).away_from_home IS NOT FALSE
     OR pg_temp.home(v_q, '14') ->> 'state' IS DISTINCT FROM 'away' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the UAE phone fixture is not away: %', to_jsonb(pg_temp.ctx(v_q));
  END IF;
  IF v IS DISTINCT FROM '{"ok": true, "away": true, "here": "AE", "trusted": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the IP unresolved, here is not the phone''s country: %', v;
  END IF;
  IF (pg_temp.ctx(v_q)).home_since IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: somewhere Dating is not allowed counted as back home: %', to_jsonb(pg_temp.ctx(v_q));
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- B8. (Task 4 fix round 1: I-1, M-1, M-3) An active person in their
--     gentle wait somewhere Dating isn't allowed is away (the section
--     hides); the cool-off carries a same-gender trip only; here names the
--     country that restricts (the network's when the IP's allows); the
--     plain-icon offer reads the context row's tier; an answer that can't
--     be read counts as beyond man-woman.
-- =====================================================================
DO $$
DECLARE
  v_c constant uuid := pg_temp.uk('16', '{"seeking": ["woman"], "days": 1}');
  v_w constant uuid := pg_temp.ready('17');
  v_ex constant uuid := pg_temp.id('18');
  v_n constant uuid := pg_temp.ready('19');
  v_s constant uuid := pg_temp.uk('20', '{"state": "profile_draft"}');
  v_r constant uuid := pg_temp.uk('21');
  v jsonb;
BEGIN
  PERFORM pg_temp.flag(true);
  -- I-1: the gentle wait (gate 5) answers before gate 7; the home is away.
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_ex, '155598118', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_ex, '+155598118', 'Ex 18');
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_w, v_ex, 'ended', now() - interval '3 days');
  PERFORM pg_temp.check(v_w, '17', 'AE');
  v := pg_temp.home(v_w, '17');
  IF public.dating_eligibility(v_w, 'candidate') IS DISTINCT FROM 'gentle_wait'
     OR v ->> 'state' IS DISTINCT FROM 'away'
     OR v -> 'trip' IS DISTINCT FROM '{"kind": "away", "note": true, "show_here": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gentle wait in the UAE is not away: % (%)', v, public.dating_eligibility(v_w, 'candidate');
  END IF;
  -- The cool-off (72 hours) carries the same-gender trip; here names Ghana.
  v := pg_temp.check(v_c, '16', 'GH');
  IF v IS DISTINCT FROM '{"ok": true, "away": false, "here": "GH", "trusted": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same-gender trip''s check answered %', v;
  END IF;
  v := pg_temp.home(v_c, '16');
  IF v ->> 'state' IS DISTINCT FROM 'cool_off'
     OR v -> 'trip' IS DISTINCT FROM '{"kind": "same_gender"}'::jsonb THEN -- fix round 4 (R-T4-9)
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cool-off home on a same-gender trip is %', v;
  END IF;
  -- M-1: the IP's country allows Dating, the network's doesn't: here is it.
  v := pg_temp.check(v_n, '19', 'GH', 'AE');
  IF v IS DISTINCT FROM '{"ok": true, "away": true, "here": "AE", "trusted": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: here is not the country that restricts: %', v;
  END IF;
  -- M-3: a UK person in setup whose last check was in Ghana is offered the
  -- plain icon (the context row's Tier 1), though the UK is Tier 3.
  PERFORM pg_temp.check(v_s, '20', 'GH');
  IF (pg_temp.ctx(v_s)).effective_tier IS DISTINCT FROM 1::smallint
     OR (pg_temp.home(v_s, '20') ->> 'offer_plain_icon') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the context row''s tier did not offer the plain icon: %', pg_temp.home(v_s, '20');
  END IF;
  -- M-3: an answer that can't be read counts as beyond man-woman.
  IF private.dating_wants_same_gender(v_r) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a man-woman answer read as beyond man-woman';
  END IF;
  UPDATE public.dating_profile_sensitive SET seeking_enc = '\x00'::bytea WHERE user_id = v_r;
  IF private.dating_wants_same_gender(v_r) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable answer counted as man-woman';
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- B9. (Task 4 fix rounds 2 and 3: Re-I-1, Re2-I-1, Re2-M-1) One rule for
--     the note and the hiding, with each pair judged as the viewer sees
--     it. A UK woman who meets men, matched with a non-binary person in the
--     man pool who doesn't show their gender, visits Ghana: she met a man,
--     so nothing hides and no note says otherwise. Matched with one who
--     shows it: the conversation hides and the home shows the trip; her
--     phone's Show it on this phone anyway (fix round 4: p_show_same_gender,
--     never the server's) brings it back. An introduction not yet shown
--     (generated) counts for nothing. After a same-gender switch (here the
--     global one) an ended conversation with someone who shows their gender
--     hides at home with the trip, which lasts past 7 days while the switch
--     does.
-- =====================================================================
DO $$
DECLARE
  v_w constant uuid := pg_temp.uk('22');
  v_n constant uuid := pg_temp.uk('23', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_k constant uuid := pg_temp.uk('24', '{"seeking": ["woman"]}');
  v_x constant uuid := pg_temp.uk('25', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_v constant uuid := pg_temp.uk('60', '{"seeking": ["woman"]}');
  v_l constant uuid := pg_temp.uk('26');
  v_y constant uuid := pg_temp.uk('27');
  v jsonb;
BEGIN
  UPDATE public.dating_profile_sensitive
     SET identity_enc = private.dating_field_encrypt('{"identity": "non_binary", "pools": ["man"]}'::jsonb)
   WHERE user_id IN (v_n, v_x);
  UPDATE public.dating_profiles SET gender_visible = (user_id = v_x) WHERE user_id IN (v_n, v_x);
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, pair_key)
  VALUES (least(v_w, v_n), greatest(v_w, v_n), 'active', public.dating_pair_key(v_w, v_n)),
         (least(v_y, v_x), greatest(v_y, v_x), 'active', public.dating_pair_key(v_y, v_x));
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, pair_key, closed_at, closed_reason, evidence_until)
  VALUES (least(v_k, v_v), greatest(v_k, v_v), 'closed', public.dating_pair_key(v_k, v_v), now(), 'other', now() + interval '30 days');
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version)
  VALUES (public.dating_pair_key(v_l, v_x), least(v_l, v_x), greatest(v_l, v_x), 'generated', 'w8-contract');
  PERFORM pg_temp.flag(true);
  -- Hidden gender: she met a man. Nothing hides, no note.
  PERFORM pg_temp.check(v_w, '22', 'GH');
  IF private.dating_wants_same_gender(v_w) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture is not a man-woman seeker';
  END IF;
  IF private.dating_trip_hides(v_w, v_n, 'match') IS NOT FALSE OR pg_temp.home(v_w, '22') ? 'trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match''s hidden gender showed through the trip: %', pg_temp.home(v_w, '22');
  END IF;
  -- Shown gender: the match hides (R-79), and the home says why.
  PERFORM pg_temp.check(v_y, '27', 'GH');
  IF private.dating_trip_hides(v_y, v_x, 'match') IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match that is not man-woman does not hide in Ghana (R-79)';
  END IF;
  v := pg_temp.home(v_y, '27');
  IF v -> 'trip' IS DISTINCT FROM '{"kind": "same_gender"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a conversation hides in Ghana with no note: %', v;
  END IF;
  IF private.dating_trip_hides(v_y, v_x, 'match', private.dating_same_gender_hiding(v_y)) IS NOT TRUE
     OR private.dating_trip_hides(v_y, v_x, 'match', false) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the four-argument hiding does not follow the viewer''s rule';
  END IF;
  -- Fix round 4 (R-T4-9): the choice is the phone's. The server's answers
  -- no_trip and changes nothing; the read's p_show_same_gender brings the
  -- conversation back.
  v := pg_temp.j(v_y, '27', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('nb')));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "no_trip"}'::jsonb OR private.dating_trip_hides(v_y, v_x, 'match') IS NOT TRUE
     OR private.dating_trip_hides(v_y, v_x, 'match', private.dating_same_gender_hiding(v_y) AND NOT true) IS NOT FALSE
     OR pg_temp.home(v_y, '27') -> 'trip' IS DISTINCT FROM '{"kind": "same_gender"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway did not bring the conversation back: % %', v, pg_temp.home(v_y, '27');
  END IF;
  -- A generated introduction (not yet shown) counts for nothing; nothing
  -- hides for a person with no trip, whoever the other is.
  PERFORM pg_temp.check(v_l, '26', 'GH');
  IF private.dating_trip_hides(v_l, v_n, 'match') IS NOT FALSE OR pg_temp.home(v_l, '26') ? 'trip'
     OR private.dating_trip_hides(v_l, v_x, 'match') IS NOT FALSE THEN -- fix round 4: one who shows they are not a man
    RAISE EXCEPTION 'CONTRACT VIOLATED: something hides for a person with no trip (a generated introduction counted?)';
  END IF;
  -- After a same-gender switch (W1's kill switch strips and hides a
  -- non-binary identity): the stripped person's ended conversation reads
  -- man-woman to the woman who met them as a man; nothing hides, no note.
  -- A woman who meets women: her ended woman-woman conversation hides,
  -- the trip explains it (she is paused, so the trip is read directly),
  -- the choice works, and it stays answered past 7 days while the switch
  -- lasts.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  PERFORM pg_temp.check(v_y, '27', 'GB');
  IF private.dating_trip_hides(v_y, v_x, 'match') IS NOT FALSE OR private.dating_trip_json(v_y) <> '{}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the switch a stripped identity showed through the trip: %', private.dating_trip_json(v_y);
  END IF;
  PERFORM pg_temp.check(v_k, '24', 'GB');
  IF private.dating_trip_hides(v_k, v_v, 'match') IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ended conversation does not hide after the switch';
  END IF;
  v := private.dating_trip_json(v_k);
  IF v IS DISTINCT FROM '{"trip": {"kind": "same_gender"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the switch an ended conversation hides with no note: %', v;
  END IF;
  v := pg_temp.j(v_k, '24', format('SELECT public.set_dating_trip_choice(%L, false)', pg_temp.key('ks')));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "no_trip"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the server took the switch''s same-gender choice: %', v;
  END IF;
  UPDATE public.dating_session_context SET home_since = now() - interval '8 days' WHERE user_id = v_k;
  PERFORM pg_temp.age(v_k, 16);
  PERFORM pg_temp.check(v_k, '24', 'GB');
  IF private.dating_trip_json(v_k) IS DISTINCT FROM '{"trip": {"kind": "same_gender"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch''s trip ended after 7 days while the switch lasts: %', private.dating_trip_json(v_k);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- B10. (Task 4 fix round 4, R-T4-9; §793, S-5) No server row tells a
--      same-gender traveller from a man-woman person, each app making the
--      calls it really makes. A UK woman who meets women and one who meets
--      men each open the app in Ghana, twice (the first's home answers the
--      same-gender trip and she answers its note on her phone, which calls
--      nothing; the second's home has no trip), then in the UAE (both see
--      the away note and choose Keep it hidden), then come home for 8 days
--      and their app retries that key. Every row either has in any table
--      keyed by a person is the same in number and in which were written or
--      rewritten; their context rows, claims, sensitive row (its columns and
--      updated_at), cases and the metric counters they move are the same,
--      mid-way and at the end. An older app's same-gender call answers
--      no_trip and leaves nothing either.
-- =====================================================================
-- [p]'s rows (their ctids) in every table of public, private and auth keyed
-- by a person.
CREATE FUNCTION pg_temp.rows_of(p uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  r record;
  v jsonb := '{}'::jsonb;
  v_ids jsonb;
BEGIN
  FOR r IN SELECT c.table_schema AS s, c.table_name AS t, c.column_name AS k
             FROM information_schema.columns AS c
             JOIN information_schema.tables AS b ON b.table_schema = c.table_schema AND b.table_name = c.table_name
            WHERE b.table_type = 'BASE TABLE' AND c.table_schema IN ('public', 'private', 'auth') AND c.data_type = 'uuid'
              AND (c.column_name ~ '(^|_)user_id$' OR c.column_name IN ('user_low_id', 'user_high_id', 'user_a', 'user_b')
                   OR (c.table_schema, c.table_name, c.column_name) IN (('auth', 'users', 'id'), ('public', 'users', 'id')))
            ORDER BY 1, 2, 3 LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(x.ctid::text), ''[]''::jsonb) FROM %I.%I AS x WHERE x.%I = $1', r.s, r.t, r.k)
      INTO v_ids USING p;
    IF v_ids <> '[]'::jsonb THEN
      v := v || jsonb_build_object(r.s || '.' || r.t || '.' || r.k, v_ids);
    END IF;
  END LOOP;
  RETURN v;
END $$;
-- Per table: [rows now, rows written or rewritten since [p_start], rows gone].
CREATE FUNCTION pg_temp.touched(p_start jsonb, p_now jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_object_agg(q.k, jsonb_build_array(
           jsonb_array_length(coalesce(p_now -> q.k, '[]'::jsonb)),
           (SELECT count(*) FROM jsonb_array_elements_text(coalesce(p_now -> q.k, '[]'::jsonb)) AS x(c)
             WHERE NOT coalesce(p_start -> q.k, '[]'::jsonb) ? x.c),
           (SELECT count(*) FROM jsonb_array_elements_text(coalesce(p_start -> q.k, '[]'::jsonb)) AS x(c)
             WHERE NOT coalesce(p_now -> q.k, '[]'::jsonb) ? x.c))), '{}'::jsonb)
    FROM (SELECT jsonb_object_keys(p_start) UNION SELECT jsonb_object_keys(p_now)) AS q(k);
$$;
CREATE FUNCTION pg_temp.trace(p uuid, p_start jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'rows', pg_temp.touched(p_start, pg_temp.rows_of(p)),
    'ctx', (SELECT to_jsonb(c) - 'user_id' - 'checked_at' - 'home_since' - 'trip_note_shown_at'
                   || jsonb_build_object('home_since', c.home_since IS NOT NULL, 'note', c.trip_note_shown_at IS NOT NULL)
              FROM public.dating_session_context AS c WHERE c.user_id = p),
    'claims', (SELECT coalesce(jsonb_agg(jsonb_build_array(i.operation, length(i.idempotency_key))
                                         ORDER BY i.operation, length(i.idempotency_key)), '[]'::jsonb)
                 FROM public.dating_rpc_idempotency AS i WHERE i.user_id = p),
    'sensitive', (SELECT jsonb_build_object(
                           'set', (SELECT jsonb_agg(e.key ORDER BY e.key) FROM jsonb_each(to_jsonb(s)) AS e WHERE e.value <> 'null'::jsonb),
                           'key_version', s.key_version, 'updated', s.updated_at)
                    FROM public.dating_profile_sensitive AS s WHERE s.user_id = p),
    'cases', (SELECT count(*) FROM public.dating_moderation_cases AS m WHERE m.target_user_id = p));
$$;
CREATE FUNCTION pg_temp.metrics() RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_object_agg(m.key, m.count), '{}'::jsonb) FROM public.metric_counters AS m
   WHERE m.day = (now() AT TIME ZONE 'utc')::date;
$$;
CREATE FUNCTION pg_temp.delta(a jsonb, b jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_object_agg(k, (b ->> k)::bigint - coalesce((a ->> k)::bigint, 0)), '{}'::jsonb)
    FROM jsonb_object_keys(b) AS k WHERE (b ->> k)::bigint IS DISTINCT FROM coalesce((a ->> k)::bigint, 0);
$$;
CREATE FUNCTION pg_temp.choose(p uuid, p_n text, p_key text, p_show boolean) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.set_dating_trip_choice(%L, %L)', p_key, p_show));
$$;
DO $$
DECLARE
  v_a constant uuid := pg_temp.uk('28', '{"seeking": ["woman"]}');
  v_b constant uuid := pg_temp.uk('29');
  v_who uuid;
  v_n text;
  v_key text;
  v_ans jsonb;
  v_answers jsonb := '{}'::jsonb;
  v_homes jsonb := '{}'::jsonb;
  v_start jsonb := '{}'::jsonb;
  v_mid jsonb := '{}'::jsonb;
  v_m0 jsonb;
  v_m1 jsonb;
  v_deltas jsonb := '{}'::jsonb;
BEGIN
  PERFORM pg_temp.flag(true);
  FOREACH v_who IN ARRAY ARRAY[v_a, v_b] LOOP
    v_n := CASE WHEN v_who = v_a THEN '28' ELSE '29' END;
    v_key := 'w8-e' || v_n || '-' || md5('e' || v_n);
    v_start := v_start || jsonb_build_object(v_n, pg_temp.rows_of(v_who));
    v_m0 := pg_temp.metrics();
    v_ans := '[]'::jsonb;
    -- Ghana, twice: each app reads its home. The first's note is answered
    -- on her phone (no call); the second has none.
    PERFORM pg_temp.check(v_who, v_n, 'GH');
    v_homes := v_homes || jsonb_build_object(v_n, pg_temp.home(v_who, v_n) -> 'trip');
    PERFORM pg_temp.age(v_who, 16);
    PERFORM pg_temp.check(v_who, v_n, 'GH');
    PERFORM pg_temp.home(v_who, v_n);
    v_mid := v_mid || jsonb_build_object(v_n, pg_temp.trace(v_who, v_start -> v_n));
    -- The UAE: both see the away note and choose Keep it hidden.
    PERFORM pg_temp.age(v_who, 16);
    PERFORM pg_temp.check(v_who, v_n, 'AE');
    PERFORM pg_temp.home(v_who, v_n);
    v_ans := v_ans || jsonb_build_array(pg_temp.choose(v_who, v_n, v_key, false));
    -- Home for 8 days; the app retries that key.
    PERFORM pg_temp.age(v_who, 16);
    PERFORM pg_temp.check(v_who, v_n, 'GB');
    UPDATE public.dating_session_context SET home_since = now() - interval '8 days' WHERE user_id = v_who;
    PERFORM pg_temp.age(v_who, 16);
    PERFORM pg_temp.check(v_who, v_n, 'GB');
    PERFORM pg_temp.home(v_who, v_n);
    v_ans := v_ans || jsonb_build_array(pg_temp.choose(v_who, v_n, v_key, false));
    v_m1 := pg_temp.metrics();
    v_answers := v_answers || jsonb_build_object(v_n, v_ans);
    v_deltas := v_deltas || jsonb_build_object(v_n, pg_temp.delta(v_m0, v_m1));
  END LOOP;
  IF v_homes IS DISTINCT FROM '{"28": {"kind": "same_gender"}, "29": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the B10 people are not a same-gender traveller and a man-woman person: %', v_homes;
  END IF;
  IF v_answers -> '28' IS DISTINCT FROM '[{"ok": true}, {"ok": false, "reason": "no_trip"}]'::jsonb
     OR v_answers -> '29' IS DISTINCT FROM v_answers -> '28' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the B10 answers are %', v_answers;
  END IF;
  IF v_mid -> '28' IS DISTINCT FROM v_mid -> '29' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in Ghana a server row tells them apart: % / %', v_mid -> '28', v_mid -> '29';
  END IF;
  IF pg_temp.trace(v_a, v_start -> '28') IS DISTINCT FROM pg_temp.trace(v_b, v_start -> '29') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the trip a server row tells them apart: % / %',
      pg_temp.trace(v_a, v_start -> '28'), pg_temp.trace(v_b, v_start -> '29');
  END IF;
  IF v_deltas -> '28' IS DISTINCT FROM v_deltas -> '29' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the metrics tell them apart: %', v_deltas;
  END IF;
  -- The trace sees what is written (the context row and the UAE claim).
  IF pg_temp.trace(v_a, v_start -> '28') -> 'rows' -> 'public.dating_rpc_idempotency.user_id' IS DISTINCT FROM '[1, 1, 0]'::jsonb
     OR pg_temp.trace(v_a, v_start -> '28') -> 'rows' -> 'public.dating_session_context.user_id' IS DISTINCT FROM '[1, 1, 0]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the B10 trace does not see the writes: %', pg_temp.trace(v_a, v_start -> '28') -> 'rows';
  END IF;
  -- An older app's call on the same-gender trip (both open in Ghana again;
  -- only the first calls, both values): no_trip, and nothing tells them apart.
  PERFORM pg_temp.age(v_a, 16);
  PERFORM pg_temp.check(v_a, '28', 'GH');
  PERFORM pg_temp.age(v_b, 16);
  PERFORM pg_temp.check(v_b, '29', 'GH');
  IF pg_temp.choose(v_a, '28', 'w8-e28-' || md5('old-false'), false) IS DISTINCT FROM '{"ok": false, "reason": "no_trip"}'::jsonb
     OR pg_temp.choose(v_a, '28', 'w8-e28-' || md5('old-true'), true) IS DISTINCT FROM '{"ok": false, "reason": "no_trip"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the server took a same-gender choice';
  END IF;
  IF pg_temp.trace(v_a, v_start -> '28') IS DISTINCT FROM pg_temp.trace(v_b, v_start -> '29') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an older app''s same-gender call left a trace: % / %',
      pg_temp.trace(v_a, v_start -> '28'), pg_temp.trace(v_b, v_start -> '29');
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- B11. (Task 4 fix round 4; §2.5 "from another person's Today"; W8 final
--      server fix I-1, superseding round 4's "as the traveller sees it")
--      The other person's Today clause judges the pair only by what the
--      viewer can already see: the viewer's own identity and seeking, the
--      traveller's gender only if shown, otherwise the viewer's whole
--      seeking set, never the traveller's hidden pools. So a woman who
--      meets men keeps the card of a non-binary traveller in the man pool
--      who doesn't show their gender, exactly as she keeps a man's (to her
--      both are men she met); a non-binary viewer loses a woman traveller's
--      card (the viewer knows the pair isn't man-woman); a viewer who seeks
--      everyone loses every hidden-gender traveller's card alike, whatever
--      pool the traveller is in, and keeps a man who shows his gender. The
--      traveller's own phone judges by what the traveller can see (round
--      2: the same rule; C8 pins it for a traveller who seeks everyone).
--      Matches are judged by the viewer's own clause only; home again, the
--      card is back.
-- =====================================================================
DO $$
DECLARE
  v_t1 constant uuid := pg_temp.uk('61', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_v1 constant uuid := pg_temp.uk('62');
  v_t2 constant uuid := pg_temp.uk('63');
  v_v2 constant uuid := pg_temp.uk('64', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_t3 constant uuid := pg_temp.uk('65', '{"identity": "man", "seeking": ["woman"]}');
  v_v3 constant uuid := pg_temp.uk('66', '{"seeking": ["man", "non_binary", "woman"]}');
  v_t4 constant uuid := pg_temp.uk('67', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_t5 constant uuid := pg_temp.uk('68', '{"identity": "man", "seeking": ["woman"]}');
  v jsonb;
BEGIN
  UPDATE public.dating_profile_sensitive
     SET identity_enc = private.dating_field_encrypt('{"identity": "non_binary", "pools": ["man"]}'::jsonb)
   WHERE user_id IN (v_t1, v_v2);
  UPDATE public.dating_profile_sensitive
     SET identity_enc = private.dating_field_encrypt('{"identity": "non_binary", "pools": ["woman"]}'::jsonb)
   WHERE user_id = v_t4;
  UPDATE public.dating_profiles SET gender_visible = false WHERE user_id IN (v_t1, v_v2, v_t3, v_t4);
  UPDATE public.dating_profiles SET gender_visible = true WHERE user_id = v_t5;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_t1, '61', 'GH');
  PERFORM pg_temp.check(v_t2, '63', 'GH');
  PERFORM pg_temp.check(v_t3, '65', 'GH');
  PERFORM pg_temp.check(v_t4, '67', 'GH');
  PERFORM pg_temp.check(v_t5, '68', 'GH');
  PERFORM pg_temp.check(v_v1, '62', 'GB');
  PERFORM pg_temp.check(v_v2, '64', 'GB');
  PERFORM pg_temp.check(v_v3, '66', 'GB');
  SELECT jsonb_object_agg(x.n, jsonb_build_array(
           private.dating_trip_hides(x.v, x.t, 'introduction', private.dating_same_gender_hiding(x.v)),
           private.dating_trip_hides(x.v, x.t, 'introduction')))
    INTO v
    FROM (VALUES ('v1_t1', v_v1, v_t1), ('v1_t3', v_v1, v_t3), ('v2_t2', v_v2, v_t2), ('v3_t1', v_v3, v_t1),
                 ('v3_t3', v_v3, v_t3), ('v3_t4', v_v3, v_t4), ('v3_t5', v_v3, v_t5)) AS x(n, v, t);
  -- The leak I-1 closes: her answer for the non-binary traveller is her
  -- answer for the man (neither hidden: she met men).
  IF v -> 'v1_t1' IS DISTINCT FROM '[false, false]'::jsonb OR v -> 'v1_t3' IS DISTINCT FROM v -> 'v1_t1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Today clause used the traveller''s hidden gender: %', v;
  END IF;
  IF v -> 'v2_t2' IS DISTINCT FROM '[true, true]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Today clause ignored the viewer''s own identity: %', v;
  END IF;
  -- Seeking everyone: one answer for every hidden-gender traveller, man
  -- pool or woman pool or a man (never the traveller's pools).
  IF v -> 'v3_t1' IS DISTINCT FROM '[true, true]'::jsonb OR v -> 'v3_t3' IS DISTINCT FROM v -> 'v3_t1'
     OR v -> 'v3_t4' IS DISTINCT FROM v -> 'v3_t1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Today clause read a hidden-gender traveller''s pools: %', v;
  END IF;
  IF v -> 'v3_t5' IS DISTINCT FROM '[false, false]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Today clause hid a man who shows his gender from a woman: %', v;
  END IF;
  -- The traveller's own phone: by what the traveller can see (round 2).
  IF private.dating_trip_hides(v_t1, v_v1, 'introduction', private.dating_same_gender_hiding(v_t1)) IS NOT TRUE
     OR private.dating_trip_hides(v_t3, v_v1, 'introduction', private.dating_same_gender_hiding(v_t3)) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the traveller''s own clause changed';
  END IF;
  IF private.dating_trip_hides(v_v3, v_t1, 'match', private.dating_same_gender_hiding(v_v3)) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Today clause reached a match';
  END IF;
  PERFORM pg_temp.age(v_t1, 16);
  PERFORM pg_temp.check(v_t1, '61', 'GB');
  IF private.dating_trip_hides(v_v3, v_t1, 'introduction', private.dating_same_gender_hiding(v_v3)) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: home again, the traveller''s card stayed hidden';
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- B12. (Task 4 fix round 4, R-T4-9, R-T4-10; Re3-M-2) The catalogue. No
--      column holds a trip choice beyond the identity-free ones; nothing
--      that reads the same-gender rule writes anything (get_dating_home's
--      one write is its missing-key counter, on the error path); the trip
--      choice reads no identity; neither it nor the device check touches
--      dating_profile_sensitive, and the choice takes the context row
--      before the phone's row (leaving's order: sensitive, context, then
--      the phones). Fix round 5 (Re4-I-1): "reads the same-gender rule" is
--      every function that reaches one of the 7 helpers through functions
--      called by name, to a fixpoint; the gate is shown to catch a writer
--      behind a helper (made and rolled back here).
-- =====================================================================
-- The functions reaching a same-gender helper that write (or are volatile).
CREATE FUNCTION pg_temp.sg_writers() RETURNS text[] LANGUAGE sql AS $$
  WITH RECURSIVE fn AS (
    SELECT n.nspname || '.' || p.proname AS name, p.proname::text COLLATE "default" AS proname, p.prosrc AS src, p.provolatile
      FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'private') AND p.prokind IN ('f', 'p')),
  reach (proname) AS (
    SELECT unnest(ARRAY['dating_same_gender_trip', 'dating_has_same_gender_pair', 'dating_wants_same_gender',
                        'dating_same_gender_hiding', 'dating_trip_json', 'dating_trip_hides', 'dating_pair_seen_as_man_woman'])
    UNION
    SELECT f.proname FROM reach JOIN fn AS f ON f.src ~ ('\m' || reach.proname || '\s*\('))
  SELECT coalesce(array_agg(DISTINCT f.name ORDER BY f.name), '{}'::text[]) FROM fn AS f
   WHERE f.proname IN (SELECT reach.proname FROM reach)
     AND (f.provolatile = 'v'
          OR f.src ~* '(\minsert\M|\mupdate\M|\mdelete\M|claim_dating_idempotency|bump_metric|dating_field_encrypt|dating_open_signal_case|nextval|set_config)');
$$;
DO $$
DECLARE
  v_cols text[];
  v_writers text[];
  v_probe text[];
  v_src text;
  v_sig text; -- Task 5
BEGIN
  SELECT array_agg(column_name::text ORDER BY column_name::text) INTO v_cols
    FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'dating_session_context';
  IF v_cols IS DISTINCT FROM ARRAY['away_from_home', 'checked_at', 'dating_allowed_here', 'effective_tier', 'home_since',
                                   'ip_resolved', 'mismatch_streak', 'same_gender_allowed_here', 'show_here',
                                   'trip_note_shown_at', 'user_id'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_session_context has columns beyond the identity-free ones: %', v_cols;
  END IF;
  SELECT array_agg(table_schema || '.' || table_name || '.' || column_name ORDER BY table_schema || '.' || table_name || '.' || column_name) INTO v_cols
    FROM information_schema.columns
   WHERE table_schema IN ('public', 'private') AND column_name ~* '(trip|same_gender|show_here|show_anyway|note_seen|note_shown)';
  IF v_cols IS DISTINCT FROM ARRAY['public.country_safety_config.same_gender_enabled', 'public.dating_reports.reporter_tripped_family',
                                   'public.dating_session_context.same_gender_allowed_here', 'public.dating_session_context.show_here',
                                   'public.dating_session_context.trip_note_shown_at'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a column can hold a trip choice: %', v_cols;
  END IF;
  v_writers := pg_temp.sg_writers();
  -- Task 5 (carry 4, R-T5-5): the reads that hide are VOLATILE (PostgREST
  -- must let them touch the phone's last use, W5/W6); what each writes is
  -- pinned below.
  IF v_writers IS DISTINCT FROM ARRAY['public.act_on_dating_introduction', 'public.confirm_dating_couple_link', -- Spec 2 W9
                                      'public.get_dating_couple_link', -- Spec 2 W9 (final server fix, M-6): VOLATILE
                                      'public.get_dating_home', 'public.get_dating_messages',
                                      'public.get_my_dating_introductions', 'public.get_my_dating_matches',
                                      'public.get_my_dating_today', 'public.request_dating_couple_link'] THEN -- Spec 2 W9
    RAISE EXCEPTION 'CONTRACT VIOLATED: something that reads the same-gender rule writes: %', v_writers;
  END IF;
  -- The gate is transitive: a STABLE card helper that hides, and a read
  -- that marks what it returns presented (Task 5's likely shape).
  BEGIN
    CREATE FUNCTION private.zz_w8_cards(p uuid) RETURNS SETOF uuid LANGUAGE sql STABLE AS $f$
      SELECT i.id FROM public.dating_introductions AS i
       WHERE p IN (i.user_low_id, i.user_high_id)
         AND NOT private.dating_trip_hides(p, CASE WHEN i.user_low_id = p THEN i.user_high_id ELSE i.user_low_id END, 'introduction')
    $f$;
    CREATE FUNCTION public.zz_w8_read(p uuid) RETURNS void LANGUAGE sql AS $f$
      UPDATE public.dating_introductions SET state = 'presented' WHERE id IN (SELECT private.zz_w8_cards(p))
    $f$;
    v_probe := pg_temp.sg_writers();
    RAISE EXCEPTION USING ERRCODE = 'W8B05';
  EXCEPTION WHEN SQLSTATE 'W8B05' THEN
    NULL;
  END;
  IF v_probe IS DISTINCT FROM ARRAY['public.act_on_dating_introduction', 'public.confirm_dating_couple_link', -- Spec 2 W9
                                    'public.get_dating_couple_link', -- Spec 2 W9 (final server fix, M-6)
                                    'public.get_dating_home', 'public.get_dating_messages',
                                    'public.get_my_dating_introductions', 'public.get_my_dating_matches',
                                    'public.get_my_dating_today', 'public.request_dating_couple_link', -- Spec 2 W9
                                    'public.zz_w8_read'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the catalogue gate missed a writer behind a helper: %', v_probe;
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.get_dating_home()'::regprocedure);
  IF regexp_count(v_src, '(\minsert\M|\mupdate\M|\mdelete\M|claim_dating_idempotency|bump_metric|dating_field_encrypt|dating_open_signal_case|nextval|set_config)', 1, 'i') <> 1
     OR position('PERFORM private.bump_metric_internal(CASE WHEN v_err = ''dating:field_key_missing''' IN v_src) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_home writes beyond its missing-key counter';
  END IF;
  -- Task 5 (R-T5-5): Today, the introductions read and the conversation
  -- list write nothing themselves; the phone's touch (in
  -- dating_require_trusted_device, the same for everyone) comes before
  -- the same-gender rule is read.
  -- Spec 2 W9 (final server fix, M-6): the link page's read too.
  FOREACH v_sig IN ARRAY ARRAY['public.get_my_dating_today(boolean)', 'public.get_my_dating_introductions(boolean)',
                               'public.get_my_dating_matches(boolean,boolean)',
                               'public.get_dating_couple_link(uuid,boolean)'] LOOP -- Spec 2 W9 (final server fix, M-6)
    v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = v_sig::regprocedure);
    IF regexp_count(v_src, '(\minsert\M|\mupdate\M|\mdelete\M|claim_dating_idempotency|bump_metric|dating_field_encrypt|dating_open_signal_case|nextval|set_config)', 1, 'i') <> 0
       OR position('dating_require_trusted_device' IN v_src) = 0
       OR position('dating_require_trusted_device' IN v_src) > position('dating_same_gender_hiding' IN v_src) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % writes, or reads the same-gender rule before the phone''s touch', v_sig;
    END IF;
  END LOOP;
  -- The messages read's one write is the seen mark, made after the hiding
  -- (never on a conversation it hides).
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.get_dating_messages(uuid,timestamp with time zone,integer,boolean)'::regprocedure);
  IF regexp_count(v_src, '(\minsert\M|\mupdate\M|\mdelete\M|claim_dating_idempotency|bump_metric|dating_field_encrypt|dating_open_signal_case|nextval|set_config)', 1, 'i') <> 1
     OR position('UPDATE public.dating_matches' IN v_src) < position('dating_trip_hides' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the messages read writes beyond its seen mark, or before the hiding';
  END IF;
  -- Acting writes only past the hiding: before it, only the card's row
  -- lock (FOR UPDATE), taken for every card alike.
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.act_on_dating_introduction(text,uuid,text,boolean)'::regprocedure);
  IF regexp_count(left(v_src, position('dating_trip_hides' IN v_src)), '(\minsert\M|\mupdate\M|\mdelete\M|claim_dating_idempotency|bump_metric|dating_field_encrypt|dating_open_signal_case|nextval|set_config)', 1, 'i') <> 1
     OR position('FOR UPDATE' IN v_src) > position('dating_trip_hides' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: acting writes before the hiding';
  END IF;
  -- Spec 2 W9 (carry 5): asking and the second Yes write only past the
  -- hiding; before it, only their row locks (the match; and the request).
  FOREACH v_sig IN ARRAY ARRAY['public.request_dating_couple_link(text,uuid,boolean,boolean):1',
                               'public.confirm_dating_couple_link(text,uuid,boolean,boolean):2'] LOOP
    v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = split_part(v_sig, ':', 1)::regprocedure);
    IF regexp_count(left(v_src, position('dating_trip_hides' IN v_src)), '(\minsert\M|\mupdate\M|\mdelete\M|claim_dating_idempotency|bump_metric|dating_field_encrypt|dating_open_signal_case|nextval|set_config)', 1, 'i')
         <> split_part(v_sig, ':', 2)::int THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % writes before the hiding', split_part(v_sig, ':', 1);
    END IF;
  END LOOP;
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.set_dating_trip_choice(text,boolean)'::regprocedure);
  IF v_src ~* '(same_gender|dating_profile_sensitive|decrypt|identity_enc|dating_identity_of|dating_trip_json|dating_wants|dating_pair_)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the trip choice reads identity or the sensitive row';
  END IF;
  IF position('FOR UPDATE' IN v_src) = 0 OR position('dating_require_trusted_device' IN v_src) = 0
     OR position('FOR UPDATE' IN v_src) > position('dating_require_trusted_device' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the trip choice does not take the context row before the phone''s row';
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.record_dating_device_check(uuid,text,text,text)'::regprocedure);
  IF v_src ~* '(dating_profile_sensitive|decrypt)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the device check touches the sensitive row';
  END IF;
END $$;

-- =====================================================================
-- B13. (W8 final server fix M-1, M-2) A paused person's reads hide on a
--      trip as anyone's do, so their home carries the trip too: a paused
--      Ghana person in the UAE (and one paused while in a relationship)
--      sees the away note and can choose; a paused UK woman who meets
--      women in Ghana carries the same-gender trip. An away trip ends after
--      7 days where Dating is allowed, wherever that is: a Ghana person who
--      lives in London (always away from the Dating country) who chose
--      Show it on this phone anyway in Dubai has it end after 7 days back
--      in London, and the next trip's note shows. Fixtures 125-129.
-- =====================================================================
DO $$
DECLARE
  v_pa constant uuid := pg_temp.ready('125', '{"state": "paused"}');
  v_pw constant uuid := pg_temp.uk('126', '{"state": "paused", "seeking": ["woman"]}');
  v_pr constant uuid := pg_temp.ready('127', '{"state": "paused"}');
  v_partner constant uuid := pg_temp.ready('128');
  v_l constant uuid := pg_temp.ready('129');
  v jsonb;
BEGIN
  UPDATE public.dating_enrollments SET pause_reason = 'user' WHERE user_id IN (v_pa, v_pw);
  UPDATE public.dating_enrollments SET pause_reason = 'relationship' WHERE user_id = v_pr;
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_pr, v_partner, 'active');
  PERFORM pg_temp.flag(true);
  -- M-1: the paused homes.
  PERFORM pg_temp.check(v_pa, '125', 'AE');
  PERFORM pg_temp.check(v_pw, '126', 'GH');
  PERFORM pg_temp.check(v_pr, '127', 'AE');
  v := pg_temp.home(v_pa, '125');
  IF v ->> 'state' IS DISTINCT FROM 'paused'
     OR v -> 'trip' IS DISTINCT FROM '{"kind": "away", "note": true, "show_here": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused person on an away trip is not shown the trip: %', v;
  END IF;
  v := pg_temp.home(v_pr, '127');
  IF v ->> 'state' IS DISTINCT FROM 'paused' OR v ->> 'can_resume' IS DISTINCT FROM 'false'
     OR v -> 'trip' IS DISTINCT FROM '{"kind": "away", "note": true, "show_here": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person paused in a relationship on an away trip is not shown the trip: %', v;
  END IF;
  v := pg_temp.home(v_pw, '126');
  IF v ->> 'state' IS DISTINCT FROM 'paused' OR v -> 'trip' IS DISTINCT FROM '{"kind": "same_gender"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused person on a same-gender trip is not shown the trip: %', v;
  END IF;
  IF pg_temp.j(v_pa, '125', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('pa'))) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.home(v_pa, '125') -> 'trip' IS DISTINCT FROM '{"kind": "away", "note": false, "show_here": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused person could not choose on an away trip: %', pg_temp.home(v_pa, '125');
  END IF;
  -- M-2: a Ghana person living in London.
  PERFORM pg_temp.check(v_l, '129', 'GB');
  IF (pg_temp.ctx(v_l)).away_from_home IS NOT TRUE OR (pg_temp.ctx(v_l)).dating_allowed_here IS NOT TRUE
     OR (pg_temp.ctx(v_l)).home_since IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: London does not count as where Dating is allowed for the Ghana fixture: %', to_jsonb(pg_temp.ctx(v_l));
  END IF;
  PERFORM pg_temp.age(v_l, 16);
  PERFORM pg_temp.check(v_l, '129', 'AE');
  IF pg_temp.j(v_l, '129', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('dxb'))) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (pg_temp.ctx(v_l)).home_since IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Dubai trip fixture is wrong: %', to_jsonb(pg_temp.ctx(v_l));
  END IF;
  -- Back in London: 6 days is the same trip, 8 ends it.
  PERFORM pg_temp.age(v_l, 16);
  PERFORM pg_temp.check(v_l, '129', 'GB');
  UPDATE public.dating_session_context SET home_since = now() - interval '6 days' WHERE user_id = v_l;
  PERFORM pg_temp.age(v_l, 16);
  PERFORM pg_temp.check(v_l, '129', 'GB');
  IF (pg_temp.ctx(v_l)).show_here IS NOT TRUE OR (pg_temp.ctx(v_l)).trip_note_shown_at IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 6 days in London ended the trip: %', to_jsonb(pg_temp.ctx(v_l));
  END IF;
  UPDATE public.dating_session_context SET home_since = now() - interval '8 days' WHERE user_id = v_l;
  PERFORM pg_temp.age(v_l, 16);
  PERFORM pg_temp.check(v_l, '129', 'GB');
  IF (pg_temp.ctx(v_l)).show_here IS NOT FALSE OR (pg_temp.ctx(v_l)).trip_note_shown_at IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 7 days where Dating is allowed did not end the trip of someone away from the Dating country: %',
      to_jsonb(pg_temp.ctx(v_l));
  END IF;
  PERFORM pg_temp.age(v_l, 16);
  PERFORM pg_temp.check(v_l, '129', 'AE');
  v := pg_temp.home(v_l, '129');
  IF v -> 'trip' IS DISTINCT FROM '{"kind": "away", "note": true, "show_here": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dubai again, Dating is on screen with no note: %', v;
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- C helpers: an introduction visible to both now, an active match, a
-- message, and the people in a read. Task 5 (R-T5-1): a read that hides
-- takes this phone's "Show it on this phone anyway" for a same-gender trip
-- as p_show_same_gender; [p_show] passes it, and without it the call is the
-- app's of today (no parameter: false).
CREATE FUNCTION pg_temp.intro(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version,
                                           visible_from_low, visible_from_high, expires_at)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'presented', 'introductions_v2',
          now() - interval '1 hour', now() - interval '1 hour', now() + interval '6 days')
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at, pair_key)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active', now() - interval '2 days', public.dating_pair_key(p_a, p_b))
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.read(p_fn text, p_args text, p_show boolean) RETURNS text LANGUAGE sql AS $$
  SELECT 'SELECT public.' || p_fn || '(' || p_args
         || CASE WHEN p_show IS NULL THEN '' ELSE CASE WHEN p_args = '' THEN '' ELSE ', ' END
                                                 || 'p_show_same_gender => ' || p_show::text END || ')';
$$;
CREATE FUNCTION pg_temp.today_json(p uuid, p_n text, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, pg_temp.read('get_my_dating_today', '', p_show));
$$;
-- The introduction ids on [p]'s Today, sorted.
CREATE FUNCTION pg_temp.today(p uuid, p_n text, p_show boolean DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT string_agg(c ->> 'id', ',' ORDER BY c ->> 'id')
                     FROM jsonb_array_elements(v -> 'cards') AS c), '')
         || CASE WHEN v ->> 'ok' = 'true' THEN '' ELSE '!' || coalesce(v ->> 'reason', v ->> 'raised', '?') END
    FROM (SELECT pg_temp.today_json(p, p_n, p_show) AS v) AS x;
$$;
-- The match ids in [p]'s conversations, then the ended ones as e:<id>, sorted.
CREATE FUNCTION pg_temp.chats(p uuid, p_n text, p_show boolean DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT string_agg(c ->> 'match_id', ',' ORDER BY c ->> 'match_id')
                     FROM jsonb_array_elements(v -> 'conversations') AS c), '')
         || coalesce((SELECT string_agg(',e:' || (c ->> 'match_id'), '' ORDER BY c ->> 'match_id')
                        FROM jsonb_array_elements(v -> 'ended') AS c), '')
         || CASE WHEN v ->> 'ok' = 'true' THEN '' ELSE '!' || coalesce(v ->> 'reason', v ->> 'raised', '?') END
    FROM (SELECT pg_temp.j(p, p_n, pg_temp.read('get_my_dating_matches', 'true', p_show)) AS v) AS x;
$$;
CREATE FUNCTION pg_temp.intros(p uuid, p_n text, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, pg_temp.read('get_my_dating_introductions', '', p_show));
$$;
CREATE FUNCTION pg_temp.messages(p uuid, p_n text, p_match uuid, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, pg_temp.read('get_dating_messages', quote_literal(p_match), p_show));
$$;
CREATE FUNCTION pg_temp.act(p uuid, p_n text, p_intro uuid, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, pg_temp.read('act_on_dating_introduction',
                                        format('%L, %L, %L', pg_temp.key('act'), p_intro, 'interested'), p_show));
$$;
-- How often [p_sig] ran in this transaction (track_functions; see C5).
CREATE FUNCTION pg_temp.calls(p_sig text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT s.calls FROM pg_stat_xact_user_functions AS s WHERE s.funcid = p_sig::regprocedure), 0);
$$;

-- =====================================================================
-- C1. A same-gender trip (§2.5): a UK woman who meets women, in Accra.
--     On her phone her same-gender introduction and conversation are
--     hidden (Today, the introductions read, acting, the list, the
--     messages, the match moment); on the other woman's Today she is
--     hidden too; the other woman's conversation with her stays; a
--     man-woman traveller keeps every introduction. "Show it on this
--     phone anyway" (Task 5, R-T5-1: the read's p_show_same_gender, the
--     phone's own choice) shows hers on that read only; the other woman's
--     reads are unaffected by it, and by her own. With the flag off nothing
--     is hidden.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.uk('30', '{"seeking": ["woman"]}');
  v_b constant uuid := pg_temp.uk('31', '{"seeking": ["woman"]}');
  v_c constant uuid := pg_temp.uk('32', '{"seeking": ["woman"]}');
  v_e constant uuid := pg_temp.uk('33', '{"identity": "man", "seeking": ["woman"]}');
  v_f constant uuid := pg_temp.uk('34');
  v_ab uuid;
  v_ac uuid;
  v_ef uuid;
  v jsonb;
BEGIN
  v_ab := pg_temp.intro(v_a, v_b);
  v_ef := pg_temp.intro(v_e, v_f);
  v_ac := pg_temp.match(v_a, v_c);
  -- The match moment, still unseen on both sides.
  IF pg_temp.today(v_a, '30') IS DISTINCT FROM v_ab::text OR pg_temp.chats(v_a, '30') IS DISTINCT FROM v_ac::text
     OR jsonb_array_length(pg_temp.today_json(v_a, '30') -> 'moments') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture is not visible before the trip: % / %', pg_temp.today(v_a, '30'), pg_temp.chats(v_a, '30');
  END IF;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_a, '30', 'GH');
  PERFORM pg_temp.check(v_e, '33', 'GH');
  v := pg_temp.today_json(v_a, '30');
  IF pg_temp.today(v_a, '30') IS DISTINCT FROM '' OR jsonb_array_length(v -> 'moments') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: her same-gender introduction or moment shows on her phone in Accra: %', v;
  END IF;
  IF jsonb_array_length(pg_temp.intros(v_a, '30') -> 'cards') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the introductions read shows it';
  END IF;
  IF pg_temp.act(v_a, '30', v_ab) ->> 'reason' IS DISTINCT FROM 'introduction_unavailable'
     OR (SELECT state || coalesce(low_action, '') || coalesce(high_action, '') FROM public.dating_introductions WHERE id = v_ab)
        IS DISTINCT FROM 'presented'
     OR EXISTS (SELECT 1 FROM public.dating_interest_actions WHERE introduction_id = v_ab) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden introduction could be acted on';
  END IF;
  IF pg_temp.chats(v_a, '30') IS DISTINCT FROM ''
     OR pg_temp.messages(v_a, '30', v_ac) ->> 'reason' IS DISTINCT FROM 'match_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: her same-gender conversation shows on her phone in Accra';
  END IF;
  IF pg_temp.today(v_b, '31') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: she is on the other woman''s Today while in Accra';
  END IF;
  IF pg_temp.chats(v_c, '32') IS DISTINCT FROM v_ac::text
     OR pg_temp.messages(v_c, '32', v_ac) ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other woman lost their conversation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pg_temp.today_json(v_c, '32') -> 'moments') AS x
                  WHERE x ->> 'match_id' = v_ac::text) THEN -- fix round 1 (M-1)
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other woman lost the match moment with her: %', pg_temp.today_json(v_c, '32');
  END IF;
  IF pg_temp.today(v_e, '33') IS DISTINCT FROM v_ef::text OR pg_temp.today(v_f, '34') IS DISTINCT FROM v_ef::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a man-woman introduction was hidden on a trip';
  END IF;
  -- Show it on this phone anyway: the phone's choice, on the read it passes.
  IF pg_temp.today(v_a, '30', true) IS DISTINCT FROM v_ab::text
     OR jsonb_array_length(pg_temp.today_json(v_a, '30', true) -> 'moments') <> 1
     OR jsonb_array_length(pg_temp.intros(v_a, '30', true) -> 'cards') <> 1
     OR pg_temp.chats(v_a, '30', true) IS DISTINCT FROM v_ac::text
     OR pg_temp.messages(v_a, '30', v_ac, true) ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway is wrong: % / % / %',
      pg_temp.today(v_a, '30', true), pg_temp.chats(v_a, '30', true), pg_temp.intros(v_a, '30', true);
  END IF;
  -- On her phone only: false is the app's own default, and nothing stays.
  IF pg_temp.today(v_a, '30', false) IS DISTINCT FROM '' OR pg_temp.today(v_a, '30') IS DISTINCT FROM ''
     OR pg_temp.chats(v_a, '30') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the phone''s choice outlived its read';
  END IF;
  -- The other woman's phone choice is about her own trip, never this one.
  IF pg_temp.today(v_b, '31', true) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone''s choice lifted the traveller''s protection';
  END IF;
  -- An older app's server choice changes nothing (B pins its no_trip).
  IF pg_temp.j(v_a, '30', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('c1'))) ->> 'reason'
     IS DISTINCT FROM 'no_trip' OR pg_temp.today(v_a, '30') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the server took a same-gender choice';
  END IF;
  -- What the phone shows it can act on.
  IF pg_temp.act(v_a, '30', v_ab, true) ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway could not act on what it shows: %', pg_temp.act(v_a, '30', v_ab, true);
  END IF;
  PERFORM pg_temp.flag(false);
  IF pg_temp.today(v_a, '30') IS DISTINCT FROM v_ab::text OR pg_temp.today(v_b, '31') IS DISTINCT FROM v_ab::text
     OR pg_temp.chats(v_a, '30') IS DISTINCT FROM v_ac::text
     OR jsonb_array_length(pg_temp.today_json(v_a, '30') -> 'moments') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off a trip still hides something';
  END IF;
END $$;

-- =====================================================================
-- C1b. (Task 5 fix round 1: review I-1, M-1) On a same-gender trip her
--      Today never says she has conversations going that her list hides:
--      the open-chat pause counts only the conversations this phone shows
--      ("Show it on this phone anyway" counts them again). The other woman
--      keeps their ended conversation.
-- =====================================================================
DO $$
DECLARE
  v_p constant uuid := pg_temp.uk('52', '{"seeking": ["woman"]}');
  v_q1 constant uuid := pg_temp.uk('53', '{"seeking": ["woman"]}');
  v_q2 constant uuid := pg_temp.uk('54', '{"seeking": ["woman"]}');
  v_q3 constant uuid := pg_temp.uk('55', '{"seeking": ["woman"]}');
  v_r constant uuid := pg_temp.uk('56', '{"seeking": ["woman"]}');
  v_pr uuid;
BEGIN
  PERFORM pg_temp.match(v_p, v_q1);
  PERFORM pg_temp.match(v_p, v_q2);
  PERFORM pg_temp.match(v_p, v_q3);
  v_pr := pg_temp.match(v_p, v_r);
  UPDATE public.dating_matches SET state = 'closed', closed_reason = 'unmatched', closed_at = now() - interval '2 days',
         evidence_until = now() + interval '28 days' WHERE id = v_pr;
  IF pg_temp.today_json(v_p, '52') ->> 'today_state' IS DISTINCT FROM 'paused_open_chats'
     OR pg_temp.chats(v_r, '56') IS DISTINCT FROM ',e:' || v_pr THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C1b fixture is not paused with three conversations: % / %',
      pg_temp.today_json(v_p, '52') ->> 'today_state', pg_temp.chats(v_r, '56');
  END IF;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_p, '52', 'GH');
  IF pg_temp.chats(v_p, '52') IS DISTINCT FROM ''
     OR pg_temp.today_json(v_p, '52') ->> 'today_state' IS NOT DISTINCT FROM 'paused_open_chats' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Today counts the conversations hidden on her phone: % / %',
      pg_temp.chats(v_p, '52'), pg_temp.today_json(v_p, '52') ->> 'today_state';
  END IF;
  IF pg_temp.today_json(v_p, '52', true) ->> 'today_state' IS DISTINCT FROM 'paused_open_chats' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: shown anyway, Today does not count her conversations: %', pg_temp.today_json(v_p, '52', true);
  END IF;
  IF pg_temp.chats(v_r, '56') IS DISTINCT FROM ',e:' || v_pr THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other woman lost the ended conversation with her: %', pg_temp.chats(v_r, '56');
  END IF;
  PERFORM pg_temp.flag(false);
  IF pg_temp.today_json(v_p, '52') ->> 'today_state' IS DISTINCT FROM 'paused_open_chats' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the open-chat pause still hides something';
  END IF;
END $$;

-- =====================================================================
-- C1c. (Task 9: Task 5 re-review M-8) Today's open-chat pause is a copy of
--      dating_open_chats' rule (R-T5-10, so it can leave out what a trip
--      hides). With the flag off it pauses exactly when the shared rule
--      reaches open_chat_pause_at: an old match with a recent message
--      counts, an old one without a message doesn't, nor does a We met
--      one; closing one fresh match lifts the pause. Fixtures 57, 110-115.
--      W8 final server fix (Task 9 M-6a): the windows' edges are pinned:
--      an old match whose last message is 15 days old doesn't count, nor
--      does a match 8 days old with no message.
-- =====================================================================
DO $$
DECLARE
  v_p constant uuid := pg_temp.ready('57');
  v_at constant int := coalesce(((private.dating_intro_config()).o_config ->> 'open_chat_pause_at')::int, 3);
  v_men uuid[] := '{}';
  v_m uuid[] := '{}';
  v_state text;
  v_open int;
BEGIN
  PERFORM pg_temp.flag(false);
  FOR i IN 110 .. 114 LOOP
    v_men := v_men || pg_temp.ready(i::text, '{"identity": "man", "seeking": ["woman"]}');
    v_m := v_m || pg_temp.match(v_p, v_men[i - 109]);
  END LOOP;
  v_men := v_men || pg_temp.ready('115', '{"identity": "man", "seeking": ["woman"]}');
  v_m := v_m || pg_temp.match(v_p, v_men[6]);
  -- 1: old, a message 3 days ago (counts); 2: old, no message (doesn't);
  -- 3: fresh, We met (doesn't); 4 and 5: fresh (count). Task 9 M-6a:
  -- 2's last message is 15 days old (doesn't); 6: 8 days old, no message
  -- (doesn't).
  UPDATE public.dating_matches SET matched_at = now() - interval '10 days' WHERE id = v_m[1];
  UPDATE public.dating_matches SET matched_at = now() - interval '16 days' WHERE id = v_m[2];
  UPDATE public.dating_matches SET matched_at = now() - interval '8 days' WHERE id = v_m[6];
  UPDATE public.dating_matches SET low_we_met_at = now() - interval '1 day' WHERE id = v_m[3];
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key, created_at)
  VALUES (v_m[1], CASE WHEN v_men[1] < v_p THEN 'low' ELSE 'high' END, v_men[1], 'hello', 'hello', 1, 'w8-c1c-1',
          now() - interval '3 days'),
         (v_m[2], CASE WHEN v_men[2] < v_p THEN 'low' ELSE 'high' END, v_men[2], 'hello', 'hello', 1, 'w8-c1c-2',
          now() - interval '15 days');
  FOR step IN 1 .. 2 LOOP
    IF step = 2 THEN
      UPDATE public.dating_matches SET state = 'closed', closed_reason = 'unmatched', closed_at = now(),
             evidence_until = now() + interval '30 days' WHERE id = v_m[4];
    END IF;
    v_state := pg_temp.today_json(v_p, '57') ->> 'today_state';
    v_open := private.dating_open_chats(v_p, now());
    IF v_at <> 3 OR v_open IS DISTINCT FROM 4 - step
       OR (step = 1 AND v_state IS DISTINCT FROM 'paused_open_chats') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the C1c fixture is not % open conversations (pause at %): % / %',
        4 - step, v_at, v_open, v_state;
    END IF;
    IF (v_state = 'paused_open_chats') IS DISTINCT FROM (v_open >= v_at) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off Today''s open-chat pause drifted from dating_open_chats: % with % open (pause at %)',
        v_state, v_open, v_at;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- C1d. (Spec 2 W9, carry 3) C1c's windows from the inside: an old match
--      whose last message is 13 days old counts, and so does a match 6
--      days old with no message; with a fresh one that is the pause (3),
--      on Today and in dating_open_chats alike. Fixtures 140-143.
-- =====================================================================
DO $$
DECLARE
  v_p constant uuid := pg_temp.ready('140');
  v_at constant int := coalesce(((private.dating_intro_config()).o_config ->> 'open_chat_pause_at')::int, 3);
  v_men uuid[] := '{}';
  v_m uuid[] := '{}';
  v_state text;
  v_open int;
BEGIN
  PERFORM pg_temp.flag(false);
  FOR i IN 141 .. 143 LOOP
    v_men := v_men || pg_temp.ready(i::text, '{"identity": "man", "seeking": ["woman"]}');
    v_m := v_m || pg_temp.match(v_p, v_men[i - 140]);
  END LOOP;
  -- 1: 20 days old, its last message 13 days ago; 2: 6 days old, no
  -- message; 3: fresh.
  UPDATE public.dating_matches SET matched_at = now() - interval '20 days' WHERE id = v_m[1];
  UPDATE public.dating_matches SET matched_at = now() - interval '6 days' WHERE id = v_m[2];
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key, created_at)
  VALUES (v_m[1], CASE WHEN v_men[1] < v_p THEN 'low' ELSE 'high' END, v_men[1], 'hello', 'hello', 1, 'w9-c1d-1',
          now() - interval '13 days');
  v_state := pg_temp.today_json(v_p, '140') ->> 'today_state';
  v_open := private.dating_open_chats(v_p, now());
  IF v_at <> 3 OR v_open IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C1d fixture is not 3 open conversations (pause at %): %', v_at, v_open;
  END IF;
  IF v_state IS DISTINCT FROM 'paused_open_chats' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Today''s open-chat pause drops a conversation inside its windows: % with % open',
      v_state, v_open;
  END IF;
END $$;

-- =====================================================================
-- C2. Away where Dating isn't allowed (§2.5): a Ghana person in the UAE.
--     Their conversations, ended ones too, are hidden on their phone
--     unless they choose to show them (the server's away choice; the
--     phone's same-gender choice never lifts it); the other person keeps
--     the conversation; their Today is not theirs to read (gate 7) and
--     they are on nobody's.
-- =====================================================================
DO $$
DECLARE
  v_g constant uuid := pg_temp.ready('35');
  v_h constant uuid := pg_temp.ready('36', '{"identity": "man", "seeking": ["woman"]}');
  v_k constant uuid := pg_temp.ready('37', '{"identity": "man", "seeking": ["woman"]}');
  v_x constant uuid := pg_temp.ready('41', '{"identity": "man", "seeking": ["woman"]}');
  v_gh uuid;
  v_gk uuid;
  v_gx uuid;
BEGIN
  v_gh := pg_temp.match(v_g, v_h);
  v_gk := pg_temp.intro(v_g, v_k);
  -- An ended conversation, still listed for its 30 days.
  v_gx := pg_temp.match(v_g, v_x);
  UPDATE public.dating_matches SET state = 'closed', closed_reason = 'unmatched', closed_at = now() - interval '2 days',
         evidence_until = now() + interval '28 days' WHERE id = v_gx;
  IF pg_temp.chats(v_g, '35') IS DISTINCT FROM v_gh::text || ',e:' || v_gx
     OR pg_temp.today(v_k, '37') IS DISTINCT FROM v_gk::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C2 fixture is not listed: %', pg_temp.chats(v_g, '35');
  END IF;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_g, '35', 'AE');
  IF pg_temp.chats(v_g, '35') IS DISTINCT FROM ''
     OR pg_temp.messages(v_g, '35', v_gh) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.today(v_g, '35') IS DISTINCT FROM '!not_eligible'
     OR pg_temp.today(v_k, '37') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: away, Dating shows: % / % / %', pg_temp.chats(v_g, '35'), pg_temp.today(v_g, '35'),
      pg_temp.today(v_k, '37');
  END IF;
  IF pg_temp.chats(v_g, '35', true) IS DISTINCT FROM ''
     OR pg_temp.messages(v_g, '35', v_gh, true) ->> 'reason' IS DISTINCT FROM 'match_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the phone''s same-gender choice lifted the away hiding';
  END IF;
  IF pg_temp.chats(v_h, '36') IS DISTINCT FROM v_gh::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other person lost the conversation with someone away';
  END IF;
  PERFORM pg_temp.j(v_g, '35', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('c2')));
  IF pg_temp.chats(v_g, '35') IS DISTINCT FROM v_gh::text || ',e:' || v_gx OR pg_temp.today(v_k, '37') IS DISTINCT FROM ''
     OR pg_temp.messages(v_g, '35', v_gh) ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: shown anyway, the conversations did not come back (or the card did)';
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- C3. (W7 carries) The restriction read and the appeal's answer say
--     whether a person reviews now: staffed only in production with an
--     active safety owner and moderator (M-6); a reference-code clash in
--     the carry-over is busy, counted, never an error (n4-2).
-- =====================================================================
DO $$
DECLARE
  v_p constant uuid := pg_temp.ready('38');
  v_o constant uuid := pg_temp.ready('39');
  v_m constant uuid := pg_temp.ready('40');
  v_busy bigint;
  v jsonb;
  v_key text;
  v_rep uuid; -- fix round 1 (M-6)
BEGIN
  INSERT INTO public.dating_reports (category, priority, sla_due_at)
  VALUES ('harassment', 'P2', now() + interval '24 hours') RETURNING id INTO v_rep;
  IF pg_temp.j(v_p, '38', 'SELECT public.get_my_dating_restriction()') ->> 'review' IS DISTINCT FROM 'testing'
     OR private.dating_report_answer(v_rep) ->> 'review' IS DISTINCT FROM 'testing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restriction read (or the report''s answer) has no testing review';
  END IF;
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_o, 'safety_owner'), (v_m, 'moderator');
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF private.dating_review_mode() IS DISTINCT FROM 'staffed'
     OR pg_temp.j(v_p, '38', 'SELECT public.get_my_dating_restriction()') ->> 'review' IS DISTINCT FROM 'staffed'
     OR private.dating_report_answer(v_rep) ->> 'review' IS DISTINCT FROM 'staffed' THEN -- fix round 1 (M-6)
    RAISE EXCEPTION 'CONTRACT VIOLATED: production with a safety owner and a moderator is not staffed';
  END IF;
  UPDATE public.dating_moderators SET active = false WHERE user_id = v_m;
  IF private.dating_review_mode() IS DISTINCT FROM 'testing'
     OR private.dating_report_answer(v_rep) ->> 'review' IS DISTINCT FROM 'testing' THEN -- fix round 1 (M-6)
    RAISE EXCEPTION 'CONTRACT VIOLATED: no active moderator still reads staffed';
  END IF;
  UPDATE public.dating_moderators SET active = true WHERE user_id = v_m;
  UPDATE public.dating_moderators SET active = false WHERE user_id = v_o;
  IF private.dating_review_mode() IS DISTINCT FROM 'testing'
     OR private.dating_report_answer(v_rep) ->> 'review' IS DISTINCT FROM 'testing' THEN -- fix round 1 (M-6)
    RAISE EXCEPTION 'CONTRACT VIOLATED: no active safety owner still reads staffed';
  END IF;
  UPDATE public.dating_moderators SET active = true WHERE user_id = v_o;
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF private.dating_review_mode() IS DISTINCT FROM 'testing'
     OR private.dating_report_answer(v_rep) ->> 'review' IS DISTINCT FROM 'testing' THEN -- fix round 1 (M-6)
    RAISE EXCEPTION 'CONTRACT VIOLATED: outside production a staffed team still reads staffed';
  END IF;
  -- n4-2: the carry-over raising unique_violation answers busy.
  SELECT coalesce(sum(count), 0) INTO v_busy FROM public.metric_counters WHERE key = 'dating.restriction.busy';
  CREATE FUNCTION private.dating_carry_over_w8_clash() RETURNS trigger LANGUAGE plpgsql AS $t$
  BEGIN
    RAISE unique_violation USING MESSAGE = 'w8 clash';
  END $t$;
  CREATE TRIGGER w8_clash BEFORE INSERT ON public.dating_account_restrictions
    FOR EACH ROW EXECUTE FUNCTION private.dating_carry_over_w8_clash();
  INSERT INTO public.enforcement_records (scope, phone_hmac, restriction_type, category, effect_until, purge_after)
  VALUES ('dating', public.dating_phone_hmac_for_user(v_p), 'suspended', 'harassment', now() + interval '10 days',
          now() + interval '2 years');
  -- The read is its own statement (an IF a OR b has no evaluation order).
  v := pg_temp.j(v_p, '38', 'SELECT public.get_my_dating_restriction()');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "busy"}'::jsonb
     OR (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.restriction.busy') <> v_busy + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reference-code clash raised or went uncounted: %', v;
  END IF;
  DROP TRIGGER w8_clash ON public.dating_account_restrictions;
  DROP FUNCTION private.dating_carry_over_w8_clash();
  -- With the clash gone the record carries: the restriction and its one
  -- appeal say testing too, the replay as the first.
  v := pg_temp.j(v_p, '38', 'SELECT public.get_my_dating_restriction()');
  IF v ->> 'review' IS DISTINCT FROM 'testing' OR v #>> '{restriction,type}' IS DISTINCT FROM 'suspended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the carried restriction read is %', v;
  END IF;
  v_key := pg_temp.key('ap');
  v := pg_temp.j(v_p, '38', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', v_key, v #>> '{restriction,id}'));
  IF v IS DISTINCT FROM '{"ok": true, "review": "testing"}'::jsonb
     OR pg_temp.j(v_p, '38', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', v_key,
                                    (SELECT id FROM public.dating_account_restrictions WHERE user_id = v_p)))
        IS DISTINCT FROM '{"ok": true, "review": "testing"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the appeal answered % (or its replay differs)', v;
  END IF;
  -- Staffed, the appeal's replay says so (it reads the mode now).
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF pg_temp.j(v_p, '38', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', v_key,
                                 (SELECT id FROM public.dating_account_restrictions WHERE user_id = v_p))) ->> 'review'
     IS DISTINCT FROM 'staffed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the appeal''s answer does not read the review mode';
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
END $$;

-- =====================================================================
-- C4. (Task 4 carry: the other person's Today clause, R-T4-9 item 3) A
--     card that clause hides is refused if acted on (the phone's own
--     choice never lifts it), promises no drop, and is left out of the
--     digest. The digest is a server write, so its rule reads no identity
--     (S-5, R-T5-4): a man-woman card with someone on the same kind of
--     trip leaves the same trace; a card with someone at home is sent.
-- =====================================================================
DO $$
DECLARE
  v_t1 constant uuid := pg_temp.uk('42', '{"seeking": ["woman"]}');
  v_w1 constant uuid := pg_temp.uk('43', '{"seeking": ["woman"]}');
  v_t2 constant uuid := pg_temp.uk('44');
  v_w2 constant uuid := pg_temp.uk('45', '{"identity": "man", "seeking": ["woman"]}');
  v_w3 constant uuid := pg_temp.uk('46', '{"seeking": ["woman"]}');
  v_h constant uuid := pg_temp.uk('47', '{"seeking": ["woman"]}');
  v_w4 constant uuid := pg_temp.uk('48', '{"seeking": ["woman"]}');
  v_g1 constant uuid := pg_temp.ready('50');
  v_g2 constant uuid := pg_temp.ready('51', '{"identity": "man", "seeking": ["woman"]}');
  v_i1 uuid;
  v_i2 uuid;
  v_i4 uuid;
  v_off integer;
  v_tz text;
  v_slot time;
  v_local timestamp;
  v_d jsonb;
  v jsonb;
BEGIN
  v_i1 := pg_temp.intro(v_t1, v_w1);
  v_i2 := pg_temp.intro(v_t2, v_w2);
  PERFORM pg_temp.intro(v_w3, v_h);
  PERFORM pg_temp.intro(v_g1, v_g2);
  v_i4 := pg_temp.intro(v_t1, v_w4);
  UPDATE public.dating_introductions SET state = 'generated', visible_from_low = now() + interval '2 hours',
         visible_from_high = now() + interval '2 hours' WHERE id = v_i4;
  IF pg_temp.today_json(v_w4, '48') ->> 'today_state' IS DISTINCT FROM 'before_drop' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C4 fixture promises no drop: %', pg_temp.today_json(v_w4, '48');
  END IF;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_t1, '42', 'GH');
  PERFORM pg_temp.check(v_t2, '44', 'GH');
  -- At home in Ghana: same-gender isn't allowed there, nor at home (no trip).
  PERFORM pg_temp.check(v_g1, '50', 'GH');
  IF pg_temp.today(v_w1, '43') IS DISTINCT FROM '' OR pg_temp.today(v_w2, '45') IS DISTINCT FROM v_i2::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Today clause is wrong: % / %', pg_temp.today(v_w1, '43'), pg_temp.today(v_w2, '45');
  END IF;
  IF pg_temp.act(v_w1, '43', v_i1) ->> 'reason' IS DISTINCT FROM 'introduction_unavailable'
     OR pg_temp.act(v_w1, '43', v_i1, true) ->> 'reason' IS DISTINCT FROM 'introduction_unavailable'
     OR (SELECT state || coalesce(low_action, '') || coalesce(high_action, '') FROM public.dating_introductions WHERE id = v_i1)
        IS DISTINCT FROM 'presented'
     OR EXISTS (SELECT 1 FROM public.dating_interest_actions WHERE introduction_id = v_i1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a card the traveller''s Today clause hides could be acted on';
  END IF;
  v := pg_temp.today_json(v_w4, '48');
  IF v ->> 'today_state' = 'before_drop' OR v ->> 'drop_at' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden card promises a drop: %', v;
  END IF;
  -- The digest, at a drop that fell in the last hour (W5's own set-up).
  FOR v_off IN -12..14 LOOP
    v_tz := 'Etc/GMT' || CASE WHEN v_off > 0 THEN '-' || v_off WHEN v_off < 0 THEN '+' || (-v_off) ELSE '' END;
    v_local := now() AT TIME ZONE v_tz;
    v_slot := (date_trunc('hour', v_local) + CASE WHEN extract(minute FROM v_local) >= 30 THEN interval '30 minutes' ELSE interval '0' END)::time;
    EXIT WHEN v_slot BETWEEN time '07:00' AND time '22:00';
  END LOOP;
  UPDATE public.users SET timezone = v_tz WHERE id IN (v_w1, v_w2, v_w3, v_g2);
  INSERT INTO public.dating_settings (user_id, drop_time, digest_push)
  VALUES (v_w1, v_slot, true), (v_w2, v_slot, true), (v_w3, v_slot, true), (v_g2, v_slot, true);
  PERFORM public.send_dating_digests();
  SELECT jsonb_object_agg(x.n, jsonb_build_object(
           'queued', (SELECT count(*) FROM public.scheduled_notifications AS s WHERE s.user_id = x.u),
           'sent_at', (SELECT t.digest_sent_at IS NOT NULL FROM public.dating_settings AS t WHERE t.user_id = x.u)))
    INTO v_d
    FROM (VALUES ('w1', v_w1), ('w2', v_w2), ('w3', v_w3), ('g2', v_g2)) AS x(n, u);
  IF v_d -> 'w3' IS DISTINCT FROM '{"queued": 1, "sent_at": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C4 control digest was not sent: %', v_d;
  END IF;
  IF v_d -> 'w1' IS DISTINCT FROM '{"queued": 0, "sent_at": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a card the Today clause hides was in the digest: %', v_d;
  END IF;
  IF v_d -> 'w1' IS DISTINCT FROM v_d -> 'w2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the digest tells a same-gender traveller''s card from a man-woman one: %', v_d;
  END IF;
  IF v_d -> 'g2' IS DISTINCT FROM '{"queued": 1, "sent_at": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a card with someone at home in Ghana was left out of the digest: %', v_d;
  END IF;
  -- Fix round 1 (M-2): with the flag off (the device check still records
  -- the place) the card is in the digest again.
  PERFORM pg_temp.flag(false);
  PERFORM public.send_dating_digests();
  IF (SELECT count(*) FROM public.scheduled_notifications AS s WHERE s.user_id = v_w1) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off a trip still keeps a card out of the digest';
  END IF;
END $$;

-- =====================================================================
-- C5. (R-T5-2) A viewer with 40 pairs on a same-gender trip: each read
--     works out the same-gender rule once (never per row), and "Show it on
--     this phone anyway" not at all; the reads stay quick. Fixtures 70-109
--     (C's 30-59 hold too few). The call count needs track_functions
--     (superuser locally; where it can't be set, only the timing runs).
-- =====================================================================
DO $$
DECLARE
  v_v constant uuid := pg_temp.uk('49', '{"seeking": ["woman"]}');
  v_o uuid;
  v_m uuid;
  n integer;
  v_sql text;
  v_show boolean;
  v_before bigint;
  v_t0 timestamptz;
  v_ms numeric;
  v_times text := '';
  v_counted boolean := true;
  v jsonb;
  v_rows integer;
BEGIN
  FOR n IN 70..109 LOOP
    v_o := pg_temp.uk(n::text, '{"seeking": ["woman"]}');
    IF n < 90 THEN
      PERFORM pg_temp.intro(v_v, v_o);
    ELSE
      v_m := pg_temp.match(v_v, v_o);
    END IF;
  END LOOP;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_v, '49', 'GH');
  BEGIN
    PERFORM set_config('track_functions', 'all', true);
  EXCEPTION WHEN insufficient_privilege THEN
    v_counted := false;
    RAISE NOTICE 'C5: track_functions cannot be set here; the call count is not checked';
  END;
  FOREACH v_show IN ARRAY ARRAY[false, true] LOOP
    FOREACH v_sql IN ARRAY ARRAY[pg_temp.read('get_my_dating_today', '', v_show),
                                 pg_temp.read('get_my_dating_introductions', '', v_show),
                                 pg_temp.read('get_my_dating_matches', 'true', v_show),
                                 pg_temp.read('get_dating_messages', quote_literal(v_m), v_show)] LOOP
      v_before := pg_temp.calls('private.dating_same_gender_trip(uuid)');
      v_t0 := clock_timestamp();
      v := pg_temp.j(v_v, '49', v_sql);
      v_ms := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000);
      v_times := v_times || format(' %s=%sms', split_part(split_part(v_sql, '(', 1), '.', 2) || CASE WHEN v_show THEN '+show' ELSE '' END, v_ms);
      IF v_counted AND pg_temp.calls('private.dating_same_gender_trip(uuid)') - v_before <> (CASE WHEN v_show THEN 0 ELSE 1 END) THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % worked out the same-gender rule % times', v_sql,
          pg_temp.calls('private.dating_same_gender_trip(uuid)') - v_before;
      END IF;
      v_rows := coalesce(jsonb_array_length(v -> 'cards'), jsonb_array_length(v -> 'conversations'),
                         CASE WHEN v ->> 'ok' = 'true' THEN 1 ELSE 0 END);
      IF v_rows <> (CASE WHEN NOT v_show THEN 0 WHEN v_sql LIKE '%messages%' THEN 1 ELSE 20 END) THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % read % rows: %', v_sql, v_rows, left(v::text, 200);
      END IF;
      IF v_ms > 5000 THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % took % ms for 40 pairs', v_sql, v_ms;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'C5 (40 pairs):%', v_times;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- C6. (R-T5-1, R-T5-2) The catalogue: each read that hides takes the
--     phone's choice and has no other signature left (PostgREST has one
--     function to call); it works out the same-gender rule once and passes
--     it to every hiding call (the four-argument form only).
-- =====================================================================
DO $$
DECLARE
  v_sig text;
  v_src text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY['public.get_my_dating_today(boolean)', 'public.get_my_dating_introductions(boolean)',
                               'public.act_on_dating_introduction(text,uuid,text,boolean)',
                               'public.get_my_dating_matches(boolean,boolean)',
                               'public.get_dating_messages(uuid,timestamp with time zone,integer,boolean)'] LOOP
    IF to_regprocedure(v_sig) IS NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % does not take the phone''s choice', v_sig;
    END IF;
    IF (SELECT count(*) FROM pg_proc AS p WHERE p.pronamespace = 'public'::regnamespace
          AND p.proname = split_part(split_part(v_sig, '(', 1), '.', 2)) <> 1 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % has another signature left', v_sig;
    END IF;
    v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = v_sig::regprocedure);
    IF regexp_count(v_src, 'dating_same_gender_hiding\s*\(') <> 1
       OR regexp_count(v_src, 'dating_trip_hides\s*\(') = 0
       OR regexp_count(v_src, 'dating_trip_hides\s*\(') <> regexp_count(v_src, '''(introduction|match)'', v_sg\)')
       OR position('p_show_same_gender' IN v_src) = 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % does not work out the same-gender rule once for every hiding call', v_sig;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- C7. (W8 final server fix I-1) The other person's Today clause through
--     the reads: a woman who meets men keeps on Today, in the
--     introductions read and in the drop promise a hidden-gender
--     non-binary traveller in the man pool exactly as a hidden-gender man
--     on the same trip; a woman who seeks everyone has both hidden, and a
--     traveller in the woman pool, alike: Today, the introductions read,
--     the drop promise and acting (introduction_unavailable, nothing
--     written). The traveller's own phone hides her too (by what the
--     traveller can see: T1 is non-binary). Fixtures 116-122.
-- =====================================================================
DO $$
DECLARE
  v_v1 constant uuid := pg_temp.uk('116');
  v_t1 constant uuid := pg_temp.uk('117', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_t3 constant uuid := pg_temp.uk('118', '{"identity": "man", "seeking": ["woman"]}');
  v_v3 constant uuid := pg_temp.uk('119', '{"seeking": ["man", "non_binary", "woman"]}');
  v_t4 constant uuid := pg_temp.uk('120', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_d1 constant uuid := pg_temp.uk('121');
  v_d3 constant uuid := pg_temp.uk('122', '{"seeking": ["man", "non_binary", "woman"]}');
  v_i11 uuid;
  v_i13 uuid;
  v_i31 uuid;
  v_i34 uuid;
  v_a jsonb;
  v_b jsonb;
BEGIN
  UPDATE public.dating_profile_sensitive
     SET identity_enc = private.dating_field_encrypt('{"identity": "non_binary", "pools": ["man"]}'::jsonb)
   WHERE user_id = v_t1;
  UPDATE public.dating_profile_sensitive
     SET identity_enc = private.dating_field_encrypt('{"identity": "non_binary", "pools": ["woman"]}'::jsonb)
   WHERE user_id = v_t4;
  UPDATE public.dating_profiles SET gender_visible = false WHERE user_id IN (v_t1, v_t3, v_t4);
  v_i11 := pg_temp.intro(v_v1, v_t1);
  v_i13 := pg_temp.intro(v_v1, v_t3);
  v_i31 := pg_temp.intro(v_v3, v_t1);
  v_i34 := pg_temp.intro(v_v3, v_t4);
  -- The drop promise: each viewer's only introduction, still to come.
  v_a := to_jsonb(ARRAY[pg_temp.intro(v_d1, v_t1), pg_temp.intro(v_d3, v_t1)]);
  UPDATE public.dating_introductions SET state = 'generated', visible_from_low = now() + interval '2 hours',
         visible_from_high = now() + interval '2 hours'
   WHERE id::text IN (SELECT jsonb_array_elements_text(v_a));
  -- The fixture: with the flag off every card shows and both drops are promised.
  PERFORM pg_temp.check(v_t1, '117', 'GH');
  PERFORM pg_temp.check(v_t3, '118', 'GH');
  PERFORM pg_temp.check(v_t4, '120', 'GH');
  IF pg_temp.today(v_v3, '119') IS DISTINCT FROM (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM unnest(ARRAY[v_i31, v_i34]) AS x)
     OR pg_temp.today_json(v_d3, '122') ->> 'today_state' IS DISTINCT FROM 'before_drop'
     OR pg_temp.today_json(v_d1, '121') ->> 'today_state' IS DISTINCT FROM 'before_drop' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C7 fixture does not show every card with the flag off: % / %',
      pg_temp.today(v_v3, '119'), pg_temp.today_json(v_d3, '122');
  END IF;
  PERFORM pg_temp.flag(true);
  IF pg_temp.today(v_v1, '116') IS DISTINCT FROM (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM unnest(ARRAY[v_i11, v_i13]) AS x)
     OR jsonb_array_length(pg_temp.intros(v_v1, '116') -> 'cards') <> 2
     OR pg_temp.today_json(v_d1, '121') ->> 'today_state' IS DISTINCT FROM 'before_drop' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden-gender traveller in the man pool left the Today of a woman who meets men: % / % / %',
      pg_temp.today(v_v1, '116'), pg_temp.intros(v_v1, '116'), pg_temp.today_json(v_d1, '121');
  END IF;
  v_a := pg_temp.act(v_v3, '119', v_i31);
  v_b := pg_temp.act(v_v3, '119', v_i34);
  IF pg_temp.today(v_v3, '119') IS DISTINCT FROM ''
     OR jsonb_array_length(pg_temp.intros(v_v3, '119') -> 'cards') <> 0
     OR pg_temp.today_json(v_d3, '122') ->> 'today_state' = 'before_drop'
     OR pg_temp.today_json(v_d3, '122') ->> 'drop_at' IS NOT NULL
     OR v_a ->> 'reason' IS DISTINCT FROM 'introduction_unavailable' OR v_b IS DISTINCT FROM v_a
     OR EXISTS (SELECT 1 FROM public.dating_interest_actions WHERE introduction_id IN (v_i31, v_i34)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a viewer who seeks everyone told hidden-gender travellers apart: % / % / % / %',
      pg_temp.today(v_v3, '119'), pg_temp.today_json(v_d3, '122'), v_a, v_b;
  END IF;
  IF pg_temp.today(v_t1, '117') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the traveller''s own Today shows a pair that isn''t man-woman to them: %', pg_temp.today(v_t1, '117');
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- C8. (W8 final server fix round 2: one viewer-visible rule) The
--     traveller's own phone judges a pair only by what the traveller can
--     see too: a UK woman who seeks everyone, in Ghana, with three
--     hidden-gender matches (a non-binary person in the man pool, one in
--     the woman pool, and a man) and two hidden-gender introductions (man
--     pool, woman pool) has all of them hidden alike, so what hides never
--     tells her a pool; "Show it on this phone anyway" brings all back.
--     With the flag off all show. Fixtures 130-135.
-- =====================================================================
DO $$
DECLARE
  v_s constant uuid := pg_temp.uk('130', '{"seeking": ["man", "non_binary", "woman"]}');
  v_nm constant uuid := pg_temp.uk('131', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_nw constant uuid := pg_temp.uk('132', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_mm constant uuid := pg_temp.uk('133', '{"identity": "man", "seeking": ["woman"]}');
  v_im constant uuid := pg_temp.uk('134', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_iw constant uuid := pg_temp.uk('135', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_all text;
  v_cards text;
BEGIN
  UPDATE public.dating_profile_sensitive
     SET identity_enc = private.dating_field_encrypt('{"identity": "non_binary", "pools": ["man"]}'::jsonb)
   WHERE user_id IN (v_nm, v_im);
  UPDATE public.dating_profile_sensitive
     SET identity_enc = private.dating_field_encrypt('{"identity": "non_binary", "pools": ["woman"]}'::jsonb)
   WHERE user_id IN (v_nw, v_iw);
  UPDATE public.dating_profiles SET gender_visible = false WHERE user_id IN (v_nm, v_nw, v_mm, v_im, v_iw);
  v_all := (SELECT string_agg(x::text, ',' ORDER BY x::text)
              FROM unnest(ARRAY[pg_temp.match(v_s, v_nm), pg_temp.match(v_s, v_nw), pg_temp.match(v_s, v_mm)]) AS x);
  v_cards := (SELECT string_agg(x::text, ',' ORDER BY x::text)
                FROM unnest(ARRAY[pg_temp.intro(v_s, v_im), pg_temp.intro(v_s, v_iw)]) AS x);
  PERFORM pg_temp.check(v_s, '130', 'GH');
  IF pg_temp.chats(v_s, '130') IS DISTINCT FROM v_all OR pg_temp.today(v_s, '130') IS DISTINCT FROM v_cards THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C8 fixture does not show everything with the flag off: % / %',
      pg_temp.chats(v_s, '130'), pg_temp.today(v_s, '130');
  END IF;
  PERFORM pg_temp.flag(true);
  IF pg_temp.home(v_s, '130') -> 'trip' IS DISTINCT FROM '{"kind": "same_gender"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C8 traveller has no same-gender trip: %', pg_temp.home(v_s, '130');
  END IF;
  IF pg_temp.chats(v_s, '130') IS DISTINCT FROM '' OR pg_temp.today(v_s, '130') IS DISTINCT FROM ''
     OR jsonb_array_length(pg_temp.intros(v_s, '130') -> 'cards') <> 0
     OR (SELECT count(DISTINCT private.dating_trip_hides(v_s, x, 'match')) FROM unnest(ARRAY[v_nm, v_nw, v_mm]) AS x) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the traveller''s own phone told hidden-gender pairs apart by pool: % / %',
      pg_temp.chats(v_s, '130'), pg_temp.today(v_s, '130');
  END IF;
  IF pg_temp.chats(v_s, '130', true) IS DISTINCT FROM v_all OR pg_temp.today(v_s, '130', true) IS DISTINCT FROM v_cards THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway did not bring every hidden-gender pair back: % / %',
      pg_temp.chats(v_s, '130', true), pg_temp.today(v_s, '130', true);
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- @@W8-END@@
DO $$ BEGIN RAISE NOTICE 'dating_v2_device_contracts: all held'; END $$;
ROLLBACK;

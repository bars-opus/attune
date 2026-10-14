-- Reflection Journal as notes (spec docs/superpowers/specs/2026-10-14-journal-notes-design.md).
-- An entry becomes a title plus ordered text/photo blocks. Owner-only: no
-- relationship_id anywhere, no partner path. `content` stays the entry's
-- plain text (server-derived), so analysis keeps reading it unchanged.

ALTER TABLE public.reflection_journal_entries
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS pinned_at timestamptz;
ALTER TABLE public.reflection_journal_entries DROP CONSTRAINT IF EXISTS reflection_journal_entries_title_check;
ALTER TABLE public.reflection_journal_entries ADD CONSTRAINT reflection_journal_entries_title_check
  CHECK (title IS NULL OR char_length(title) BETWEEN 1 AND 120);
-- A new entry is empty until written.
ALTER TABLE public.reflection_journal_entries DROP CONSTRAINT IF EXISTS reflection_journal_entries_content_check;
ALTER TABLE public.reflection_journal_entries ALTER COLUMN content SET DEFAULT '';
CREATE INDEX IF NOT EXISTS reflection_journal_entries_pinned_idx
  ON public.reflection_journal_entries(user_id, pinned_at DESC)
  WHERE pinned_at IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.reflection_journal_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id uuid NOT NULL REFERENCES public.reflection_journal_entries(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  position int NOT NULL,
  kind text NOT NULL CHECK (kind IN ('text', 'photo')),
  payload jsonb NOT NULL CHECK (octet_length(payload::text) <= 16384),
  plain_text text CHECK (plain_text IS NULL OR char_length(plain_text) <= 10000),
  version int NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS reflection_journal_blocks_entry_idx
  ON public.reflection_journal_blocks(entry_id, position);

DROP TRIGGER IF EXISTS set_reflection_journal_blocks_updated_at ON public.reflection_journal_blocks;
CREATE TRIGGER set_reflection_journal_blocks_updated_at
BEFORE UPDATE ON public.reflection_journal_blocks
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.reflection_journal_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reflection_journal_blocks FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.reflection_journal_blocks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reflection_journal_blocks TO service_role;
DROP POLICY IF EXISTS reflection_journal_blocks_select_own ON public.reflection_journal_blocks;
CREATE POLICY reflection_journal_blocks_select_own ON public.reflection_journal_blocks
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- ---- helpers (not callable by clients) ------------------------------------

CREATE OR REPLACE FUNCTION public.journal_fail(p_code text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'journal:%', p_code USING ERRCODE = 'P0001';
END $$;

-- The caller's live entry, locked; not_found for anything else (no
-- existence oracle for other people's entries).
CREATE OR REPLACE FUNCTION public.journal_lock_entry(p_entry_id uuid)
RETURNS public.reflection_journal_entries
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); e public.reflection_journal_entries;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO e FROM public.reflection_journal_entries
   WHERE id = p_entry_id AND user_id = v_uid AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  RETURN e;
END $$;

-- content = the text blocks' plain text, in order, blank-line joined. A
-- changed text makes the last tone stale (as update_journal_entry did).
CREATE OR REPLACE FUNCTION public.journal_refresh_content(p_entry_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_new text;
BEGIN
  SELECT coalesce(string_agg(rtrim(b.plain_text, E' \n\t'), E'\n\n' ORDER BY b.position), '')
    INTO v_new
    FROM public.reflection_journal_blocks b
   WHERE b.entry_id = p_entry_id AND b.kind = 'text' AND btrim(coalesce(b.plain_text, ''), E' \n\t') <> '';
  UPDATE public.reflection_journal_entries
     SET content = v_new,
         tone = CASE WHEN content IS DISTINCT FROM v_new THEN NULL ELSE tone END
   WHERE id = p_entry_id;
END $$;

CREATE OR REPLACE FUNCTION public.journal_summary(e public.reflection_journal_entries) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', e.id,
    'title', e.title,
    'snippet', left(btrim(regexp_replace(e.content, '\s+', ' ', 'g')), 80),
    'has_photo', EXISTS (SELECT 1 FROM public.reflection_journal_blocks b WHERE b.entry_id = e.id AND b.kind = 'photo'),
    'pinned', e.pinned_at IS NOT NULL,
    'tone', e.tone,
    'created_at', e.created_at,
    'updated_at', e.updated_at)
$$;

-- Validates and cleans a block payload; returns (payload, plain_text).
CREATE OR REPLACE FUNCTION public.journal_clean_payload(
  e public.reflection_journal_entries, p_kind text, p_payload jsonb,
  OUT payload jsonb, OUT plain_text text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF p_kind = 'text' THEN
    plain_text := public.planning_validate_delta(p_payload->'delta');
    payload := jsonb_build_object('delta', p_payload->'delta');
    IF char_length(plain_text) > 10000 OR octet_length(payload::text) > 16384 THEN
      PERFORM public.journal_fail('too_long');
    END IF;
  ELSIF p_kind = 'photo' THEN
    IF coalesce(p_payload->>'path', '') !~ ('^' || e.user_id || '/' || e.id || '/[A-Za-z0-9._-]{1,100}$') THEN
      PERFORM public.journal_fail('invalid_input');
    END IF;
    payload := jsonb_build_object('path', p_payload->>'path');
    plain_text := NULL;
  ELSE
    PERFORM public.journal_fail('invalid_input');
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.journal_fail(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.journal_lock_entry(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.journal_refresh_content(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.journal_summary(public.reflection_journal_entries) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.journal_clean_payload(public.reflection_journal_entries, text, jsonb) FROM PUBLIC, anon, authenticated;

-- ---- reads ------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_journal_entry(p_entry_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); e public.reflection_journal_entries;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO e FROM public.reflection_journal_entries
   WHERE id = p_entry_id AND user_id = v_uid AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  RETURN jsonb_build_object(
    'entry', to_jsonb(e) - 'deleted_at',
    'blocks', coalesce((SELECT jsonb_agg(to_jsonb(b) - 'user_id' ORDER BY b.position)
                          FROM public.reflection_journal_blocks b WHERE b.entry_id = e.id), '[]'::jsonb),
    'analysis', (SELECT jsonb_build_object('status', a.status, 'tone', a.tone,
                                           'observation', a.observation, 'confidence', a.confidence)
                   FROM public.reflection_journal_analysis a
                  WHERE a.entry_id = e.id ORDER BY a.updated_at DESC LIMIT 1));
END $$;

-- Pinned entries come apart, on the first page only; the rest are paged by
-- the day they were written.
CREATE OR REPLACE FUNCTION public.list_journal_entries(p_before timestamptz DEFAULT NULL, p_limit int DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_limit int := least(greatest(coalesce(p_limit, 30), 1), 100);
  v_rows jsonb;
  v_pinned jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  -- The subquery hands back whole table rows (s.x), so journal_summary gets
  -- the table's row type, not an anonymous record.
  SELECT coalesce(jsonb_agg(public.journal_summary(s.x) ORDER BY (s.x).created_at DESC), '[]'::jsonb) INTO v_rows
    FROM (SELECT e AS x FROM public.reflection_journal_entries e
           WHERE e.user_id = v_uid AND e.deleted_at IS NULL AND e.pinned_at IS NULL
             AND e.created_at < coalesce(p_before, 'infinity'::timestamptz)
           ORDER BY e.created_at DESC LIMIT v_limit) s;
  IF p_before IS NULL THEN
    SELECT coalesce(jsonb_agg(public.journal_summary(x) ORDER BY x.pinned_at DESC), '[]'::jsonb) INTO v_pinned
      FROM public.reflection_journal_entries x
     WHERE x.user_id = v_uid AND x.deleted_at IS NULL AND x.pinned_at IS NOT NULL;
  END IF;
  RETURN jsonb_build_object('pinned', v_pinned, 'entries', v_rows,
                            'has_more', jsonb_array_length(v_rows) = v_limit);
END $$;

-- ---- writes -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_journal_entry_v2(p_prompt_used text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  INSERT INTO public.reflection_journal_entries (user_id, content, prompt_used)
  VALUES (v_uid, '', nullif(btrim(p_prompt_used), ''))
  RETURNING id INTO v_id;
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  VALUES (v_id, v_uid, 0, 'text', '{"delta":[{"insert":"\n"}]}'::jsonb, '');
  RETURN public.get_journal_entry(v_id);
END $$;

CREATE OR REPLACE FUNCTION public.rename_journal_entry(p_entry_id uuid, p_title text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_title text := nullif(btrim(p_title), ''); e public.reflection_journal_entries;
BEGIN
  e := public.journal_lock_entry(p_entry_id);
  IF char_length(v_title) > 120 THEN PERFORM public.journal_fail('too_long'); END IF;
  UPDATE public.reflection_journal_entries SET title = v_title WHERE id = e.id RETURNING * INTO e;
  RETURN to_jsonb(e) - 'deleted_at';
END $$;

CREATE OR REPLACE FUNCTION public.set_journal_pin(p_entry_id uuid, p_pinned boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE e public.reflection_journal_entries;
BEGIN
  e := public.journal_lock_entry(p_entry_id);
  UPDATE public.reflection_journal_entries
     SET pinned_at = CASE WHEN p_pinned THEN coalesce(pinned_at, now()) ELSE NULL END
   WHERE id = e.id;
END $$;

-- A stale version is returned as a conflict (with the stored block), never
-- an overwrite: the client asks the person which to keep.
CREATE OR REPLACE FUNCTION public.save_journal_text(p_block_id uuid, p_version int, p_delta jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); b public.reflection_journal_blocks; e public.reflection_journal_entries; c record;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO b FROM public.reflection_journal_blocks
   WHERE id = p_block_id AND user_id = v_uid AND kind = 'text';
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  e := public.journal_lock_entry(b.entry_id);
  SELECT * INTO b FROM public.reflection_journal_blocks WHERE id = p_block_id FOR UPDATE;
  IF b.version <> p_version THEN
    RETURN jsonb_build_object('status', 'conflict', 'block', to_jsonb(b) - 'user_id');
  END IF;
  c := public.journal_clean_payload(e, 'text', jsonb_build_object('delta', p_delta));
  UPDATE public.reflection_journal_blocks
     SET payload = c.payload, plain_text = c.plain_text, version = version + 1
   WHERE id = b.id RETURNING * INTO b;
  PERFORM public.journal_refresh_content(e.id);
  RETURN jsonb_build_object('status', 'saved', 'block', to_jsonb(b) - 'user_id');
END $$;

CREATE OR REPLACE FUNCTION public.insert_journal_block(
  p_entry_id uuid, p_after uuid, p_kind text, p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE e public.reflection_journal_entries; b public.reflection_journal_blocks; c record; v_pos int;
BEGIN
  e := public.journal_lock_entry(p_entry_id);
  IF (SELECT count(*) FROM public.reflection_journal_blocks WHERE entry_id = e.id) >= 50 THEN
    PERFORM public.journal_fail('limit');
  END IF;
  IF p_kind = 'photo' AND (SELECT count(*) FROM public.reflection_journal_blocks
                            WHERE entry_id = e.id AND kind = 'photo') >= 10 THEN
    PERFORM public.journal_fail('limit');
  END IF;
  c := public.journal_clean_payload(e, p_kind, p_payload);
  IF p_after IS NULL THEN
    SELECT coalesce(max(position) + 1, 0) INTO v_pos FROM public.reflection_journal_blocks WHERE entry_id = e.id;
  ELSE
    SELECT position + 1 INTO v_pos FROM public.reflection_journal_blocks WHERE id = p_after AND entry_id = e.id;
    IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
    UPDATE public.reflection_journal_blocks SET position = position + 1 WHERE entry_id = e.id AND position >= v_pos;
  END IF;
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  VALUES (e.id, e.user_id, v_pos, p_kind, c.payload, c.plain_text)
  RETURNING * INTO b;
  IF p_kind = 'text' THEN PERFORM public.journal_refresh_content(e.id); END IF;
  RETURN to_jsonb(b) - 'user_id';
END $$;

CREATE OR REPLACE FUNCTION public.delete_journal_block(p_block_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); b public.reflection_journal_blocks; e public.reflection_journal_entries;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO b FROM public.reflection_journal_blocks WHERE id = p_block_id AND user_id = v_uid;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  e := public.journal_lock_entry(b.entry_id);
  IF (SELECT count(*) FROM public.reflection_journal_blocks WHERE entry_id = e.id) <= 1 THEN
    PERFORM public.journal_fail('last_block');
  END IF;
  DELETE FROM public.reflection_journal_blocks WHERE id = b.id;
  IF b.kind = 'text' THEN PERFORM public.journal_refresh_content(e.id); END IF;
END $$;

CREATE OR REPLACE FUNCTION public.move_journal_block(p_block_id uuid, p_to int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); b public.reflection_journal_blocks; e public.reflection_journal_entries; v_n int; v_to int;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO b FROM public.reflection_journal_blocks WHERE id = p_block_id AND user_id = v_uid;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  e := public.journal_lock_entry(b.entry_id);
  SELECT count(*) INTO v_n FROM public.reflection_journal_blocks WHERE entry_id = e.id;
  v_to := least(greatest(coalesce(p_to, 0), 0), v_n - 1);
  WITH ordered AS (
    SELECT id, row_number() OVER (ORDER BY position, created_at) - 1 AS i
      FROM public.reflection_journal_blocks WHERE entry_id = e.id AND id <> b.id)
  UPDATE public.reflection_journal_blocks x
     SET position = CASE WHEN o.i < v_to THEN o.i ELSE o.i + 1 END
    FROM ordered o WHERE x.id = o.id;
  UPDATE public.reflection_journal_blocks SET position = v_to WHERE id = b.id;
  PERFORM public.journal_refresh_content(e.id);
END $$;

CREATE OR REPLACE FUNCTION public.restore_journal_entry(p_entry_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  UPDATE public.reflection_journal_entries SET deleted_at = NULL
   WHERE id = p_entry_id AND user_id = v_uid AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
END $$;

-- Real deletion: blocks and analysis cascade; photo files are queued by the
-- block trigger below.
CREATE OR REPLACE FUNCTION public.purge_journal_entry(p_entry_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  DELETE FROM public.reflection_journal_entries WHERE id = p_entry_id AND user_id = v_uid;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
END $$;

-- Deletions left past their Undo window (the app closed mid-Undo) go for good.
CREATE OR REPLACE FUNCTION public.purge_my_deleted_journal_entries() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_n int;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  DELETE FROM public.reflection_journal_entries
   WHERE user_id = v_uid AND deleted_at IS NOT NULL AND deleted_at < now() - interval '10 minutes';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

-- ---- photo files follow their blocks ------------------------------------------

CREATE OR REPLACE FUNCTION public.journal_block_queue_photo() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF OLD.kind = 'photo' THEN
    PERFORM public.queue_media_deletion('journal-media', OLD.payload->>'path');
  END IF;
  RETURN OLD;
END $$;
DROP TRIGGER IF EXISTS journal_block_queue_photo ON public.reflection_journal_blocks;
CREATE TRIGGER journal_block_queue_photo
BEFORE DELETE ON public.reflection_journal_blocks
FOR EACH ROW EXECUTE FUNCTION public.journal_block_queue_photo();

-- ---- legacy RPCs (older app builds) keep blocks in step -----------------------

CREATE OR REPLACE FUNCTION public.create_journal_entry(p_content text, p_prompt_used text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_user_id uuid := auth.uid(); v_entry_id uuid;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000'; END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) = 0 THEN
    RAISE EXCEPTION 'content_required' USING ERRCODE = '22023';
  END IF;
  IF char_length(p_content) > 10000 THEN PERFORM public.journal_fail('too_long'); END IF;
  INSERT INTO public.reflection_journal_entries (user_id, content, prompt_used)
  VALUES (v_user_id, p_content, p_prompt_used) RETURNING id INTO v_entry_id;
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  VALUES (v_entry_id, v_user_id, 0, 'text',
          jsonb_build_object('delta', jsonb_build_array(jsonb_build_object('insert', p_content || E'\n'))),
          p_content);
  RETURN v_entry_id;
END $$;

-- The whole text becomes one block at the top; photos stay.
CREATE OR REPLACE FUNCTION public.update_journal_entry(p_entry_id uuid, p_content text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000'; END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) = 0 THEN
    RAISE EXCEPTION 'content_required' USING ERRCODE = '22023';
  END IF;
  IF char_length(p_content) > 10000 THEN PERFORM public.journal_fail('too_long'); END IF;
  UPDATE public.reflection_journal_entries SET content = p_content, tone = NULL
   WHERE id = p_entry_id AND user_id = v_user_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'entry_not_found' USING ERRCODE = '22023'; END IF;
  DELETE FROM public.reflection_journal_blocks WHERE entry_id = p_entry_id AND kind = 'text';
  UPDATE public.reflection_journal_blocks SET position = position + 1 WHERE entry_id = p_entry_id;
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  VALUES (p_entry_id, v_user_id, 0, 'text',
          jsonb_build_object('delta', jsonb_build_array(jsonb_build_object('insert', p_content || E'\n'))),
          p_content);
END $$;

-- ---- grants ----------------------------------------------------------------------

DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.get_journal_entry(uuid)', 'public.list_journal_entries(timestamptz, int)',
    'public.create_journal_entry_v2(text)', 'public.rename_journal_entry(uuid, text)',
    'public.set_journal_pin(uuid, boolean)', 'public.save_journal_text(uuid, int, jsonb)',
    'public.insert_journal_block(uuid, uuid, text, jsonb)', 'public.delete_journal_block(uuid)',
    'public.move_journal_block(uuid, int)', 'public.restore_journal_entry(uuid)',
    'public.purge_journal_entry(uuid)', 'public.purge_my_deleted_journal_entries()'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.journal_block_queue_photo() FROM PUBLIC, anon, authenticated;

-- ---- backfill: every existing entry becomes text blocks (≤ 3 000 characters each) ----

-- Splits long text at the last paragraph break before the limit, else a
-- line break, else a space (the separator is dropped); only a stretch with
-- no space at all is cut hard. Never mid-word, so the text reads the same
-- and a later save (which joins blocks with a blank line) rebuilds it.
CREATE OR REPLACE FUNCTION public.journal_split_text(p_text text, p_max int DEFAULT 3000)
RETURNS SETOF text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_rest text := coalesce(p_text, '');
  v_head text;
  v_sep text;
  v_found text;
  v_pos int;
  v_cut int;
BEGIN
  WHILE char_length(v_rest) > p_max LOOP
    v_head := left(v_rest, p_max);
    v_cut := 0;
    FOREACH v_sep IN ARRAY ARRAY[E'\n\n', E'\n', ' '] LOOP
      v_pos := strpos(reverse(v_head), reverse(v_sep));
      IF v_pos > 0 THEN
        -- 1-based start of the last occurrence of v_sep in v_head.
        v_cut := char_length(v_head) - v_pos - char_length(v_sep) + 2;
        IF v_cut > 1 THEN v_found := v_sep; EXIT; END IF;
        v_cut := 0;
      END IF;
    END LOOP;
    IF v_cut > 1 THEN
      RETURN NEXT left(v_rest, v_cut - 1);
      v_rest := substr(v_rest, v_cut + char_length(v_found));
    ELSE
      RETURN NEXT v_head;
      v_rest := substr(v_rest, p_max + 1);
    END IF;
  END LOOP;
  RETURN NEXT v_rest;
END $$;
REVOKE ALL ON FUNCTION public.journal_split_text(text, int) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.journal_backfill_blocks() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  SELECT e.id, e.user_id, (c.n - 1)::int, 'text',
         jsonb_build_object('delta', jsonb_build_array(jsonb_build_object('insert', c.chunk || E'\n'))),
         c.chunk
    FROM public.reflection_journal_entries e
    CROSS JOIN LATERAL public.journal_split_text(e.content) WITH ORDINALITY AS c(chunk, n)
   WHERE NOT EXISTS (SELECT 1 FROM public.reflection_journal_blocks b WHERE b.entry_id = e.id);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.journal_backfill_blocks() FROM PUBLIC, anon, authenticated;
SELECT public.journal_backfill_blocks();

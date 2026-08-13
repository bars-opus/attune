-- Message actions: reply (already shipped), copy (client-only, no schema),
-- star, pin, edit, delete. Resolves CHAT_SYSTEM_SPEC.md's Month-4
-- "separate retention and audit contract" gate on edit/delete — see
-- docs/superpowers/specs/2026-08-13-message-actions-design.md for the
-- full decision record (soft-delete tombstone, kept edit history, no
-- analysis retraction, 5-minute window, star=private/pin=shared).
--
-- Filename note: the task brief specified 20260813120000_message_actions.sql,
-- but 20260813120000_reflection_journal.sql already occupies that exact
-- version. The Supabase CLI keys schema_migrations on the 14-digit version,
-- so two files sharing one version collide on push. Renamed to 20260831120000
-- (after 20260830120000_chat_pulse_signals.sql, the current latest) — this
-- also keeps the migration ordered after the reply columns it coexists with.
--
-- Style precedent: 20260730120000_edit_window_opinions_comments_forum_posts.sql
-- (SECURITY DEFINER + SET search_path, error codes not free text, REVOKE ALL
-- FROM PUBLIC, anon then GRANT EXECUTE TO authenticated). That feature uses a
-- 15-minute window; this one uses 5 minutes deliberately (design spec
-- decision 7 — live chat moves faster than a forum post, and a shorter
-- window reduces the "did you edit that?" trust question).

-- ---------------------------------------------------------------------
-- 1. messages: soft-delete + edit tombstone columns
-- ---------------------------------------------------------------------

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS edited_at timestamptz;

COMMENT ON COLUMN public.messages.deleted_at IS
  'Soft-delete tombstone. When set, content/media_url/media_type/media_thumbnail_url are NULL and both partners render "This message was deleted". The row and id persist so reply_to_message_id references and included_in_session_id analysis rows stay valid.';
COMMENT ON COLUMN public.messages.edited_at IS
  'Set on every edit. content holds the CURRENT version; prior versions live in message_edit_history.';

-- messages_payload_present (20260705120000_chat_system_v1_2.sql) asserts
-- "content is non-blank OR media_url is not null". delete_message NULLs both,
-- so without relaxing this constraint every soft delete would fail with
-- 23514. Widen it to also admit a tombstoned row, keeping the original
-- guarantee intact for every live message (deleted_at IS NULL).
--
-- Same for messages_content_length: it already tolerates NULL content, so it
-- needs no change — checked, left alone deliberately.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'messages_payload_present'
  ) THEN
    ALTER TABLE public.messages DROP CONSTRAINT messages_payload_present;
  END IF;

  ALTER TABLE public.messages
    ADD CONSTRAINT messages_payload_present
    CHECK (
      deleted_at IS NOT NULL
      OR (content IS NOT NULL AND char_length(btrim(content)) > 0)
      OR media_url IS NOT NULL
    );
END
$$;

-- The column-level SELECT grant on messages is an explicit allowlist
-- (20260705190000_chat_system_v1_3.sql revoked the table-wide grant so
-- analysis columns stay service-only). New columns are NOT covered by it —
-- 20260828120000_chat_message_replies_select_grant.sql exists solely because
-- the reply migration forgot this. Grant both new columns here so the same
-- bug is not re-introduced. Note these are SELECT-only: messages still has no
-- UPDATE grant for authenticated at all, so deleted_at/edited_at can only be
-- written by the SECURITY DEFINER RPCs below.
GRANT SELECT (deleted_at, edited_at) ON public.messages TO authenticated;

-- ---------------------------------------------------------------------
-- 2. message_edit_history: append-only audit trail
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.message_edit_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  previous_content text NOT NULL,
  edited_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_message_edit_history_message
  ON public.message_edit_history (message_id, edited_at);

ALTER TABLE public.message_edit_history ENABLE ROW LEVEL SECURITY;

-- Both relationship members may read edit history (either partner can see
-- what the other edited — matches decision 2's evidentiary-value rationale
-- in the design spec). No INSERT/UPDATE/DELETE grant for authenticated —
-- rows are written only via edit_message's internal INSERT (SECURITY
-- DEFINER bypasses RLS/grants). This satisfies Checklist 2.22's
-- append-only requirement structurally, not via a trigger.
DROP POLICY IF EXISTS message_edit_history_select ON public.message_edit_history;
CREATE POLICY message_edit_history_select ON public.message_edit_history
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.relationships r ON r.id = m.relationship_id
      WHERE m.id = message_edit_history.message_id
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
        AND r.chat_archived_at IS NULL
    )
  );

REVOKE ALL ON public.message_edit_history FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.message_edit_history TO authenticated;

-- ---------------------------------------------------------------------
-- 3. message_stars: private per-user bookmarks
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.message_stars (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  starred_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_stars_user
  ON public.message_stars (user_id, starred_at DESC);

ALTER TABLE public.message_stars ENABLE ROW LEVEL SECURITY;

-- Owner-only, both directions: USING gates SELECT/DELETE, WITH CHECK gates
-- INSERT. A user can neither see nor create another user's stars, so a
-- partner can never learn what the other starred (design decision 5).
DROP POLICY IF EXISTS message_stars_owner ON public.message_stars;
CREATE POLICY message_stars_owner ON public.message_stars
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

REVOKE ALL ON public.message_stars FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.message_stars TO authenticated;

-- ---------------------------------------------------------------------
-- 4. message_pins: shared, relationship-wide, capped at 3 (via RPC)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.message_pins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  pinned_by uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  pinned_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (relationship_id, message_id)
);

CREATE INDEX IF NOT EXISTS idx_message_pins_relationship
  ON public.message_pins (relationship_id, pinned_at DESC);

-- The UNIQUE (relationship_id, message_id) index leads with relationship_id,
-- so it cannot serve a lookup by message_id alone. Without this, the
-- ON DELETE CASCADE from messages sequentially scans message_pins.
CREATE INDEX IF NOT EXISTS idx_message_pins_message
  ON public.message_pins (message_id);

ALTER TABLE public.message_pins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_pins_select ON public.message_pins;
-- Archived-chat guard matches messages_select_members
-- (20260705120000_chat_system_v1_2.sql:239-250) exactly: once a chat is
-- archived neither partner can read the underlying messages, so pins over
-- them must disappear too rather than leaving a readable/deletable shadow
-- of an archived conversation.
CREATE POLICY message_pins_select ON public.message_pins
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = message_pins.relationship_id
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
        AND r.chat_archived_at IS NULL
    )
  );

DROP POLICY IF EXISTS message_pins_delete ON public.message_pins;
CREATE POLICY message_pins_delete ON public.message_pins
  FOR DELETE TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = message_pins.relationship_id
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
        AND r.chat_archived_at IS NULL
    )
  );

-- SELECT/DELETE only — no INSERT grant. Inserting a pin always goes through
-- pin_message so the 3-pin cap is enforced server-side (Checklist 2.5).
-- Either partner may unpin, matching the chat-naming "no per-partner
-- override" precedent.
REVOKE ALL ON public.message_pins FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON public.message_pins TO authenticated;

-- ---------------------------------------------------------------------
-- 5. delete_message: soft delete, sender-only, 5-minute window
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_locked_id uuid;
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Lock the row BEFORE the ownership/window check so two near-simultaneous
  -- calls (e.g. a double-tap, or a client retry racing the original) cannot
  -- both read pre-delete state (Checklist 2.16). The second caller blocks
  -- here, then re-reads the committed deleted_at and falls through to the
  -- not_deletable path below rather than double-clearing content.
  --
  -- The lock is taken WITHOUT the ownership/window predicates: filtering
  -- them here would make a losing race return "no row" for a reason
  -- indistinguishable from "not yours", and would leave the row unlocked
  -- while we evaluated the checks.
  SELECT id INTO v_locked_id
  FROM public.messages
  WHERE id = p_message_id
  FOR UPDATE;

  UPDATE public.messages
  SET content = NULL,
      media_url = NULL,
      media_type = NULL,
      media_thumbnail_url = NULL,
      deleted_at = now()
  WHERE id = p_message_id
    AND sender_id = v_uid
    AND deleted_at IS NULL
    AND created_at > now() - interval '5 minutes'
  RETURNING id INTO v_updated_id;

  -- One error for "not found", "already deleted", "not yours", and
  -- "window expired" — deliberately, matching edit_opinion's precedent:
  -- distinguishing these would let a caller probe whether a message ID
  -- exists or who sent it (Checklist 2.4). A retried delete lands here
  -- (deleted_at is already set), so the retry fails cleanly and is a no-op
  -- rather than re-clearing content or moving deleted_at forward
  -- (Checklist 2.18).
  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_deletable' USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_message(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_message(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 6. edit_message: append history, overwrite content, sender-only,
--    5-minute window
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.edit_message(p_message_id uuid, p_new_content text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sender_id uuid;
  v_created_at timestamptz;
  v_deleted_at timestamptz;
  v_current_content text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Length bound matches the messages_content_length CHECK (<= 10000) so the
  -- RPC rejects with a clean error code instead of letting a 23514 surface
  -- (Checklist 2.1 — validated server-side, not just in the client).
  IF p_new_content IS NULL OR char_length(btrim(p_new_content)) = 0
     OR char_length(p_new_content) > 10000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  -- Lock first, check second (Checklist 2.16). Reading the fields into
  -- variables rather than testing content IS NULL directly matters here: a
  -- media-only message has NULL content legitimately, so the brief's
  -- "v_current_content IS NULL means not editable" shortcut would both
  -- misreport a media message as not-editable and, worse, mask a NOT NULL
  -- violation on message_edit_history.previous_content.
  SELECT sender_id, created_at, deleted_at, content
    INTO v_sender_id, v_created_at, v_deleted_at, v_current_content
  FROM public.messages
  WHERE id = p_message_id
  FOR UPDATE;

  -- Single error for every failure mode, same rationale as delete_message.
  IF v_sender_id IS NULL
     OR v_sender_id <> v_uid
     OR v_deleted_at IS NOT NULL
     OR v_created_at <= now() - interval '5 minutes'
     OR v_current_content IS NULL THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;

  -- Append the PRE-edit content. Written under SECURITY DEFINER, which is
  -- the only write path into this table — authenticated holds SELECT only.
  INSERT INTO public.message_edit_history (message_id, previous_content)
  VALUES (p_message_id, v_current_content);

  UPDATE public.messages
  SET content = p_new_content,
      edited_at = now()
  WHERE id = p_message_id;
END;
$$;

REVOKE ALL ON FUNCTION public.edit_message(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 7. pin_message: enforce 3-pin cap server-side
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.pin_message(p_relationship_id uuid, p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_already_pinned boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Same "active, not archived" condition messages_insert_sender_active
  -- (20260705120000_chat_system_v1_2.sql:252-265) requires to SEND a message:
  -- creating a pin is a write into a live conversation, so it must not be
  -- possible in a paused/ended/archived chat. This also covers a pending
  -- relationship, where user_b is still NULL and the invite is unaccepted.
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND (r.user_a = v_uid OR r.user_b = v_uid)
      AND r.status = 'active'
      AND r.chat_archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  -- Message must exist, belong to this relationship, and not be tombstoned.
  -- Checking relationship_id here (not just id) prevents pinning a message
  -- from someone else's chat into your own pin banner.
  IF NOT EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = p_message_id
      AND m.relationship_id = p_relationship_id
      AND m.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_pinnable' USING ERRCODE = '42501';
  END IF;

  -- Retried pin is a no-op, checked BEFORE the cap so a client retry on an
  -- already-pinned message never trips pin_limit_reached (Checklist 2.18).
  SELECT EXISTS (
    SELECT 1 FROM public.message_pins
    WHERE relationship_id = p_relationship_id AND message_id = p_message_id
  ) INTO v_already_pinned;

  IF v_already_pinned THEN
    RETURN;
  END IF;

  IF (
    SELECT count(*) FROM public.message_pins
    WHERE relationship_id = p_relationship_id
  ) >= 3 THEN
    -- P0001 (raise_exception), not 23505: nothing violated a uniqueness
    -- constraint here — this is a business-rule cap, and reusing 23505 would
    -- be indistinguishable from a genuine ON CONFLICT duplicate below.
    RAISE EXCEPTION 'pin_limit_reached' USING ERRCODE = 'P0001';
  END IF;

  -- ON CONFLICT DO NOTHING is the belt to the check above's braces: it also
  -- absorbs the case where both partners pin the same message in the same
  -- instant, which the EXISTS check alone would let through to a 23505.
  --
  -- Accepted, documented TOCTOU (design spec, Checklist 2.16): count(*) then
  -- INSERT means two partners pinning DIFFERENT messages at the same instant
  -- could momentarily produce 4 pins. Failure mode is cosmetic, not a
  -- security or correctness issue, and the realistic concurrency is
  -- once-in-a-blue-moon — not worth advisory-lock machinery.
  INSERT INTO public.message_pins (relationship_id, message_id, pinned_by)
  VALUES (p_relationship_id, p_message_id, v_uid)
  ON CONFLICT (relationship_id, message_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.pin_message(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pin_message(uuid, uuid) TO authenticated;

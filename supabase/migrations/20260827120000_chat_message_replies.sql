-- Reply/quote support for 1:1 chat messages, mirroring forum_posts'
-- reply_to_post_id/quoted_text exactly (same reasoning: quoted_text is a
-- content snapshot so the preview survives the parent being edited/removed
-- later, avoiding a join just to render it).
-- See docs/superpowers/specs/2026-08-12-chat-universal-bubble-reply-design.md.

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS reply_to_message_id uuid
    REFERENCES public.messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS quoted_text text;

COMMENT ON COLUMN public.messages.reply_to_message_id IS
  'Parent message this one replies to, if any. ON DELETE SET NULL: message deletion is not a launch feature, but a reply must never be force-deleted just because its parent is removed later.';
COMMENT ON COLUMN public.messages.quoted_text IS
  'Snapshot of the parent message''s content at reply time, for rendering the quoted-preview block without a join.';

-- A reply's parent must be a message in the SAME relationship — messages_
-- insert_sender_active (20260705120000_chat_system_v1_2.sql) already
-- restricts relationship_id to the caller's own active relationship, but
-- says nothing about reply_to_message_id independently pointing somewhere
-- else. RLS alone can't express "these two columns must agree," hence a
-- trigger — same pattern as validate_message_media_before_insert
-- (20260705133000_chat_media_month2.sql).
CREATE OR REPLACE FUNCTION public.validate_message_reply_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_relationship_id uuid;
BEGIN
  IF NEW.reply_to_message_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT relationship_id INTO v_parent_relationship_id
  FROM public.messages
  WHERE id = NEW.reply_to_message_id;

  IF v_parent_relationship_id IS NULL THEN
    RAISE EXCEPTION 'Reply target message does not exist';
  END IF;

  IF v_parent_relationship_id IS DISTINCT FROM NEW.relationship_id THEN
    RAISE EXCEPTION 'Reply target must be in the same relationship';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_message_reply_before_insert ON public.messages;
CREATE TRIGGER validate_message_reply_before_insert
BEFORE INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.validate_message_reply_before_insert();

-- messages_insert_sender_active's column-level GRANT
-- (20260705120000_chat_system_v1_2.sql) is an explicit allowlist — without
-- adding these two columns to it, every reply insert fails with a
-- permission error even though the row-level policy itself would allow it.
REVOKE INSERT ON public.messages FROM authenticated;
GRANT INSERT (
  relationship_id,
  sender_id,
  client_message_id,
  content,
  media_url,
  media_type,
  reply_to_message_id,
  quoted_text
) ON public.messages TO authenticated;

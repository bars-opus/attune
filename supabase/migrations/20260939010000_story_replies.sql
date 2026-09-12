-- Story replies: messages.story_item_id and its validation trigger.
--
-- Spec §5.4 (docs/superpowers/specs/2026-09-11-stories-design.md): a
-- reply may reference a story alongside the existing
-- reply_to_message_id/quoted_text pair (20260827120000). quoted_text
-- remains the durable snapshot -- server-normalized to "Photo story" or
-- "Video story" -- so the preview survives the story being soft-deleted
-- or expiring without a join. story_item_id is the live link, nullable
-- so ON DELETE SET NULL can clear it on hard cascade (§5.4's last
-- bullet) while quoted_text stays intact (test 6).
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS story_item_id uuid
    REFERENCES public.story_items(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.messages.story_item_id IS
  'Story this message quotes, if any. Nullable and ON DELETE SET NULL: '
  'a hard-deleted story must not force-delete the reply that quoted it. '
  'quoted_text (server-normalized to "Photo story"/"Video story" by '
  'validate_message_story_reply_before_insert) is the durable snapshot '
  'that keeps the reply readable after the live link is gone, per '
  'spec §5.4.';

-- validate_message_story_reply_before_insert: the trust seam.
--
-- Messages are inserted directly today (not through a story-reply RPC,
-- spec §5.4's opening rationale) precisely so the existing chat outbox
-- keeps working unmodified. That means RLS's messages_insert_sender_active
-- (20260705120000) is the only gate on the message row itself, and it
-- knows nothing about story_item_id -- it was written before stories
-- existed. A client could otherwise INSERT a message with relationship_id
-- set to their own (real) relationship but story_item_id pointing at ANY
-- story row's id, in ANY other couple's relationship, and RLS would never
-- notice: it only checks that the message's own relationship_id belongs
-- to the caller, not that story_item_id agrees with it. Hence a trigger,
-- same pattern as validate_message_reply_before_insert
-- (20260827120000) and validate_message_media_before_insert
-- (20260705133000_chat_media_month2.sql).
--
-- What "live" means here is deliberately narrower than "not expired":
-- spec §5.4 says expiry alone does not break the link (an expired story
-- still opens from the calendar), so this trigger does NOT check
-- expires_at. It DOES require deleted_at IS NULL (soft-deleted stories
-- are refused -- test 3) and requires the story's relationship to be the
-- SAME ACTIVE, unarchived relationship as the message being sent (test 2,
-- test 4), matching story_relationship_is_open's own "active + unarchived"
-- condition (20260938020000) rather than re-deriving a laxer rule.
--
-- The sender-is-a-member requirement in spec §5.4 is already implied
-- transitively once this trigger requires the story's relationship_id to
-- equal NEW.relationship_id: messages_insert_sender_active already pins
-- NEW.relationship_id to one the sender belongs to. This function still
-- re-checks membership explicitly against the relationship the STORY
-- belongs to (not just trusting NEW.relationship_id's own policy), so the
-- guarantee holds even if a future migration ever loosens the messages
-- INSERT policy without revisiting this trigger.
--
-- Every failure path -- story missing, wrong relationship, deleted story,
-- ended/archived relationship -- raises the SAME generic message. A
-- distinct message per case would let a client binary-search which
-- story ids exist versus which merely belong to someone else, i.e. turn
-- this into an existence oracle across every relationship, not just the
-- caller's own.
CREATE OR REPLACE FUNCTION public.validate_message_story_reply_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_story record;
BEGIN
  IF NEW.story_item_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT si.relationship_id, si.media_type, si.deleted_at
    INTO v_story
  FROM public.story_items si
  WHERE si.id = NEW.story_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Story unavailable';
  END IF;

  IF v_story.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Story unavailable';
  END IF;

  IF v_story.relationship_id IS DISTINCT FROM NEW.relationship_id THEN
    RAISE EXCEPTION 'Story unavailable';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = v_story.relationship_id
      AND r.status = 'active'
      AND r.chat_archived_at IS NULL
      AND (r.user_a = NEW.sender_id OR r.user_b = NEW.sender_id)
  ) THEN
    RAISE EXCEPTION 'Story unavailable';
  END IF;

  NEW.quoted_text := CASE v_story.media_type
    WHEN 'video' THEN 'Video story'
    ELSE 'Photo story'
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_message_story_reply_before_insert
  ON public.messages;
CREATE TRIGGER validate_message_story_reply_before_insert
BEFORE INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.validate_message_story_reply_before_insert();

-- messages_insert_sender_active's column-level GRANT (20260705120000,
-- extended by 20260827120000 for reply_to_message_id/quoted_text) is an
-- explicit allowlist -- without adding story_item_id here, every reply-
-- to-a-story insert fails with a permission error even though the row
-- policy and this trigger would both allow it. quoted_text is already
-- grantable (added in 20260827120000); it does not need to be listed
-- again, and this trigger overwrites it server-side regardless of what a
-- client sends.
-- The messages column-grant block lives in its own migration
-- (20260939020000_story_reply_grants.sql) so scripts/local_pg_grants.sql
-- can replay it after its blanket grant, the same way the Stories tables
-- and Word Hunt do. Keeping it here instead would mean the harness's
-- blanket "GRANT INSERT ON ALL TABLES" silently re-opened the column
-- allowlist locally while production kept it narrow -- the exact
-- divergence that hid the media_*/is_view_once loss found in review.

-- messages is NOT in scripts/local_pg_grants.sql's REVOKE-replay list
-- (unlike story_items/story_views/etc., which the harness's blanket
-- table-level GRANT would otherwise silently re-open -- see
-- 20260938100000_stories_table_grants.sql). That gap predates this
-- migration: the harness's blanket "GRANT INSERT ON ALL TABLES" already
-- overrides messages' column-level INSERT allowlist for every column
-- (verified empirically -- has_column_privilege('authenticated',
-- 'messages','delivered_at','INSERT') is already true on a from-scratch
-- local rebuild, despite delivered_at never being listed in any INSERT
-- grant). Column-level privilege therefore is not a load-bearing
-- security boundary in THIS local harness today for any messages column,
-- story_item_id included -- production is unaffected (Supabase grants at
-- CREATE time and never re-runs a blanket grant afterward, the same
-- reasoning local_pg_grants.sql documents at its top). The trigger above
-- is the actual gate for story_item_id in both environments: it runs
-- regardless of which columns a client's role can literally write, so
-- widening/narrowing the column grant changes nothing about whether a
-- cross-relationship story can be quoted. Not fixing the pre-existing
-- messages grants gap here -- it is unrelated to story replies, predates
-- this task, and touching messages' base INSERT/SELECT grants is exactly
-- the kind of broad, non-surgical change to a shared core table this
-- project treats as its own separate, flagged piece of work.

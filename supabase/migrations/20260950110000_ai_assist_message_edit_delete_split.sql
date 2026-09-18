-- AI Assistant Plan A, Task 8: split edit_message/delete_message
-- behavior for message_origin = 'attune_assist' messages.
--
-- Spec §5.3: "may be deleted under the existing five-minute sender rule
-- but may not be edited in place." Both bodies below are the EXISTING
-- bodies from 20260831120000_message_actions.sql (read in full before
-- writing this migration) plus additive, Assist-specific branches. No
-- existing behavior for ordinary user messages is removed.

-- ---------------------------------------------------------------------
-- edit_message: reject outright for an Assist message, before the
-- lock/window logic runs at all. Checked ahead of the length-bound
-- validation too, so a caller learns "not editable" rather than
-- "invalid_content" when both would otherwise apply -- the origin check
-- is the more specific, and more informative, failure reason.
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
  v_relationship_id uuid;
  v_message_origin text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Length bound matches the messages_content_length CHECK (<= 10000) so the
  -- RPC rejects with a clean error code instead of letting a 23514 surface
  -- (Checklist 2.1 -- validated server-side, not just in the client).
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
  SELECT sender_id, created_at, deleted_at, content, relationship_id,
         message_origin
    INTO v_sender_id, v_created_at, v_deleted_at, v_current_content,
         v_relationship_id, v_message_origin
  FROM public.messages
  WHERE id = p_message_id
  FOR UPDATE;

  -- Attune Assist messages are immutable-in-place regardless of
  -- sender/window (spec §5.3). Checked with its own dedicated error code
  -- so a client can distinguish "this is an Assist message" from every
  -- other not_editable cause and skip straight to offering delete instead
  -- of a retry. Placed right after the lock/read, before the general
  -- not_editable predicate below, so an Assist message never falls through
  -- to that shared error and loses this distinction.
  IF v_message_origin = 'attune_assist' THEN
    RAISE EXCEPTION 'assist_message_immutable' USING ERRCODE = '42501';
  END IF;

  -- Single error for every failure mode, same rationale as delete_message.
  -- The final NOT EXISTS disjunct is the same "active, not archived"
  -- condition pin_message enforces: editing is a write into a live
  -- conversation, so a paused/ended/archived chat (reachable via the
  -- read-only "Previous relationships" view) must reject it.
  IF v_sender_id IS NULL
     OR v_sender_id <> v_uid
     OR v_deleted_at IS NOT NULL
     OR v_created_at <= now() - interval '5 minutes'
     OR v_current_content IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.relationships r
       WHERE r.id = v_relationship_id
         AND r.status = 'active'
         AND r.chat_archived_at IS NULL
     ) THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;

  -- Append the PRE-edit content. Written under SECURITY DEFINER, which is
  -- the only write path into this table -- authenticated holds SELECT only.
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
-- delete_message: unchanged sender/window/soft-delete behavior, plus an
-- additive Assist-specific tombstone step in the SAME transaction --
-- clear assistant_payload, reset message_origin to 'user' (so
-- messages_assistant_payload_shape stays satisfied on the tombstoned
-- row), and delete the ai_assist_planning_links row if one exists.
--
-- Concurrency: the existing FOR UPDATE lock (taken unconditionally,
-- before any predicate, exactly as in the pre-Task-8 body) is on the
-- SAME messages row this new branch reads (message_origin) and writes
-- (assistant_payload/message_origin) -- this is Task 6's safe shape, not
-- Task 4's or Task 7's disjoint-lock shape: there is no second row whose
-- check could race ahead of the lock. A second concurrent delete call on
-- the same message blocks on FOR UPDATE until the first transaction
-- commits, then re-reads deleted_at (already set by the first) and fails
-- the UPDATE's own predicate, landing on not_deletable -- it never
-- reaches the new Assist branch a second time, so the link-row DELETE
-- (itself idempotent -- DELETE of zero rows is not an error) is only
-- ever executed by the winning transaction. Empirically verified with
-- the same filesystem-barrier two-psql-process technique used for Tasks
-- 4/7 -- see task-8-report.md.
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
  v_locked_origin text;
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
  SELECT id, message_origin INTO v_locked_id, v_locked_origin
  FROM public.messages
  WHERE id = p_message_id
  FOR UPDATE;

  UPDATE public.messages
  SET content = NULL,
      media_url = NULL,
      media_type = NULL,
      media_thumbnail_url = NULL,
      deleted_at = now(),
      -- Additive Assist-specific tombstone fields. For an ordinary user
      -- message these are already NULL/'user', so the assignment is a
      -- no-op there -- this does not change behavior for the common case.
      assistant_payload = CASE
        WHEN v_locked_origin = 'attune_assist' THEN NULL
        ELSE assistant_payload
      END,
      message_origin = CASE
        WHEN v_locked_origin = 'attune_assist' THEN 'user'
        ELSE message_origin
      END
  WHERE id = p_message_id
    AND sender_id = v_uid
    AND deleted_at IS NULL
    AND created_at > now() - interval '5 minutes'
    -- Same "active, not archived" condition pin_message enforces below (and
    -- messages_insert_sender_active requires to SEND): deleting is a write
    -- into a live conversation, so it must not be possible in a
    -- paused/ended/archived chat -- reachable via the read-only "Previous
    -- relationships" view, which reuses ChatScreen.
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = messages.relationship_id
        AND r.status = 'active'
        AND r.chat_archived_at IS NULL
    )
  RETURNING id INTO v_updated_id;

  -- One error for "not found", "already deleted", "not yours", and
  -- "window expired" -- deliberately, matching edit_opinion's precedent:
  -- distinguishing these would let a caller probe whether a message ID
  -- exists or who sent it (Checklist 2.4). A retried delete lands here
  -- (deleted_at is already set), so the retry fails cleanly and is a no-op
  -- rather than re-clearing content or moving deleted_at forward
  -- (Checklist 2.18).
  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_deletable' USING ERRCODE = '42501';
  END IF;

  -- Preserve any Planning entity this Assist message's proposal already
  -- spawned: delete only the link ROW, never the planning_items/
  -- planning_events row it points at. ai_assist_planning_links.message_id
  -- has ON DELETE CASCADE from messages, but this is a soft delete (the
  -- messages row and id persist), so that FK never fires here -- this
  -- explicit DELETE is the only removal path for the link, and it removes
  -- nothing else. DELETE of zero rows (no link ever existed, or a retried
  -- call finds it already gone) is not an error -- idempotent by
  -- construction, matching contract 4.
  IF v_locked_origin = 'attune_assist' THEN
    DELETE FROM public.ai_assist_planning_links WHERE message_id = p_message_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_message(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_message(uuid) TO authenticated;

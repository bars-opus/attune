-- Draft insertion (service-role only) and the share RPC. Spec §5.3,
-- §7.2.
CREATE OR REPLACE FUNCTION public.insert_ai_assist_draft(
  p_id uuid, p_relationship_id uuid, p_requester_id uuid,
  p_target_message_id uuid, p_reply_text text, p_assistant_payload jsonb
) RETURNS public.ai_assist_drafts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.ai_assist_drafts;
BEGIN
  INSERT INTO public.ai_assist_drafts (
    id, relationship_id, requester_id, target_message_id, reply_text,
    assistant_payload, created_at, expires_at
  ) VALUES (
    p_id, p_relationship_id, p_requester_id, p_target_message_id,
    btrim(p_reply_text), p_assistant_payload, now(), now() + interval '15 minutes'
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;
-- No GRANT to authenticated at all -- only service_role (which the edge
-- function's own connection runs as) may call this. This is the
-- enforcement for "no user may supply draft output to this function"
-- (spec §7.2) -- verified by contract 1 in
-- ai_assist_draft_share_contracts.sql.
--
-- DEVIATION FROM THE BRIEF: the brief's own SQL relied on "the table
-- owner ... may call this" and revoked from PUBLIC/anon/authenticated
-- only, leaving service_role with no explicit grant. That is wrong on
-- real Supabase: service_role has BYPASSRLS, but BYPASSRLS only skips
-- row-level security -- it grants no function EXECUTE privilege at all.
-- A function's default ACL is EXECUTE TO PUBLIC unless revoked, and
-- service_role is a normal (non-superuser) role that is a member of
-- PUBLIC like any other -- so revoking from PUBLIC without an explicit
-- GRANT ... TO service_role afterwards would have left the edge
-- function itself unable to call insert_ai_assist_draft in production.
-- This exact gap was caught here by index.test.ts's real-Postgres
-- service-role test double (makeServiceRoleClient(), the same adapter
-- Task 5 uses for analyse-message/analyse-session) failing with
-- "permission denied for function insert_ai_assist_draft" the first
-- time the Ideas success-path test ran against this migration as
-- originally written -- see task-6-report.md.
REVOKE ALL ON FUNCTION public.insert_ai_assist_draft(uuid, uuid, uuid, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insert_ai_assist_draft(uuid, uuid, uuid, uuid, text, jsonb)
  TO service_role;

-- share_ai_assist_draft: the only authenticated command over a draft.
-- Locks the draft row (FOR UPDATE) before checking anything else, which
-- is what makes two concurrent share attempts on the SAME draft safe --
-- see the report for why this specific ordering (lock, THEN check
-- shared_message_id) is load-bearing and not just defensive style,
-- following Task 4's advisory-lock precedent for a check-then-act RPC.
CREATE OR REPLACE FUNCTION public.share_ai_assist_draft(
  p_draft_id uuid
) RETURNS public.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_draft public.ai_assist_drafts;
  v_target public.messages;
  v_rel public.relationships;
  v_consent record;
  v_message_id uuid;
  v_row public.messages;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- FOR UPDATE takes a row lock on this specific draft for the rest of
  -- this transaction. A second concurrent call for the SAME p_draft_id
  -- blocks here until the first transaction commits or rolls back --
  -- exactly the per-row serialization Task 4's per-user advisory lock
  -- provided for the quota check, scoped here to one draft instead of
  -- one user (a blanket table lock would be unnecessary and would
  -- serialize unrelated drafts/relationships against each other for no
  -- reason). Once the first caller commits, the second caller's SELECT
  -- re-reads the now-updated row and sees shared_message_id already set
  -- -- the idempotent-return branch below -- rather than racing past it.
  SELECT * INTO v_draft FROM public.ai_assist_drafts
  WHERE id = p_draft_id FOR UPDATE;
  IF v_draft.id IS NULL THEN
    RAISE EXCEPTION 'Draft unavailable';
  END IF;
  IF v_draft.requester_id IS DISTINCT FROM v_actor THEN
    RAISE EXCEPTION 'Draft unavailable';
  END IF;

  -- Idempotent re-share of an already-shared draft.
  IF v_draft.shared_message_id IS NOT NULL THEN
    SELECT * INTO v_row FROM public.messages WHERE id = v_draft.shared_message_id;
    RETURN v_row;
  END IF;

  IF v_draft.expires_at <= now() THEN
    RAISE EXCEPTION 'Draft expired';
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_draft.relationship_id
    AND status = 'active' AND chat_archived_at IS NULL
    AND (user_a = v_actor OR user_b = v_actor);
  IF v_rel.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  IF v_draft.target_message_id IS NOT NULL THEN
    SELECT * INTO v_target FROM public.messages
    WHERE id = v_draft.target_message_id AND deleted_at IS NULL;
    IF v_target.id IS NULL THEN
      RAISE EXCEPTION 'Target unavailable';
    END IF;
  END IF;

  SELECT * INTO v_consent FROM public.get_ai_processing_consent_status(v_draft.relationship_id);
  IF NOT v_consent.both_granted THEN
    RAISE EXCEPTION 'Consent required';
  END IF;

  v_message_id := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    message_origin, assistant_payload, is_system_notice,
    message_analysis_skipped, source, created_at
  ) VALUES (
    v_message_id, v_draft.relationship_id, v_actor, gen_random_uuid(),
    v_draft.reply_text, 'attune_assist', v_draft.assistant_payload, false,
    true, 'native', now()
  )
  RETURNING * INTO v_row;

  UPDATE public.ai_assist_drafts SET shared_message_id = v_message_id
  WHERE id = p_draft_id;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.share_ai_assist_draft(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_ai_assist_draft(uuid)
  TO authenticated;

-- supabase/migrations/20261017120000_seen_receipts.sql
--
-- "Show when we've seen things": one per-couple setting for chat read ticks
-- and story seen-state (Spec 1a Task 2; research 06 §3 F4; SOUL §8 "NEVER:
-- read receipts ... as defaults ... or re-enableable by one partner alone";
-- SPEC §11 constraint 12).
--
-- Storage: one row per (relationship, member), RPC-only, the same shape as
-- together_member_prefs. Effective = both rows present and both on. No row
-- means off, so a couple linked on or after the ship cutoff is off until both
-- turn it on. Either member's off is effective at once and the partner is
-- told nothing: no push, no signal, no event. The RPCs return the caller's
-- own vote and the effective state, never the partner's row.
--
-- The setting is NOT stored on relationships: until 20261017110000 members
-- could UPDATE that table from the client, and it is in the realtime
-- publication.

CREATE TABLE public.seen_receipt_prefs (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seen_on boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, user_id)
);
ALTER TABLE public.seen_receipt_prefs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.seen_receipt_prefs FROM PUBLIC, anon, authenticated;

-- The one place the rule lives. Internal: mark_conversation_read,
-- mark_story_viewed and the story list RPCs (all SECURITY DEFINER) call it.
-- Active only: a paused or ended couple shares nothing, whatever the votes.
CREATE FUNCTION public.seen_receipts_effective(p_relationship_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.relationships r
    JOIN public.seen_receipt_prefs a ON a.relationship_id = r.id AND a.user_id = r.user_a
    JOIN public.seen_receipt_prefs b ON b.relationship_id = r.id AND b.user_id = r.user_b
    WHERE r.id = p_relationship_id
      AND r.status = 'active'
      AND r.chat_archived_at IS NULL
      AND a.seen_on AND b.seen_on
  )
$$;
REVOKE ALL ON FUNCTION public.seen_receipts_effective(uuid) FROM PUBLIC, anon, authenticated;

-- The caller, if a member of this active OR PAUSED, unarchived relationship.
-- Paused is allowed so a paused member can still withdraw (SPEC §11.12 --
-- revocable alone, always); seen_receipts_effective is what keeps receipts
-- from flowing while paused.
CREATE FUNCTION public.seen_receipts_member(p_relationship_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'seen_receipts:unauthenticated' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status IN ('active', 'paused')
      AND r.chat_archived_at IS NULL
      AND (r.user_a = v_uid OR r.user_b = v_uid)
  ) THEN
    RAISE EXCEPTION 'seen_receipts:not_found' USING ERRCODE = 'P0001';
  END IF;
  RETURN v_uid;
END $$;
REVOKE ALL ON FUNCTION public.seen_receipts_member(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.get_seen_receipts(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.seen_receipts_member(p_relationship_id);
BEGIN
  RETURN jsonb_build_object(
    'mine', coalesce((SELECT p.seen_on FROM public.seen_receipt_prefs p
                       WHERE p.relationship_id = p_relationship_id AND p.user_id = v_me), false),
    'effective', public.seen_receipts_effective(p_relationship_id));
END $$;

CREATE FUNCTION public.set_seen_receipts(p_relationship_id uuid, p_on boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.seen_receipts_member(p_relationship_id);
BEGIN
  IF p_on IS NULL THEN
    RAISE EXCEPTION 'seen_receipts:invalid_input' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO public.seen_receipt_prefs (relationship_id, user_id, seen_on, updated_at)
  VALUES (p_relationship_id, v_me, p_on, now())
  ON CONFLICT (relationship_id, user_id)
  DO UPDATE SET seen_on = EXCLUDED.seen_on, updated_at = now();
  RETURN jsonb_build_object('mine', p_on, 'effective', public.seen_receipts_effective(p_relationship_id));
END $$;

REVOKE ALL ON FUNCTION public.get_seen_receipts(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_seen_receipts(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_seen_receipts(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_seen_receipts(uuid, boolean) TO authenticated;

-- Default by link date (research 06 §10 Q2: default off wins). Couples linked
-- before the cutoff keep today's behaviour, on for both until either turns it
-- off; couples linked on or after it get no rows, i.e. off. The DEFAULT is
-- now(): the migration's own call below makes the cutoff the deploy moment,
-- so there is no date constant to keep in step with a release. The contract
-- test passes an explicit cutoff. invite_accepted_at is trusted only because
-- 20261017110000 made it unwritable from the client. Idempotent.
CREATE FUNCTION public.seen_receipts_backfill_defaults(
  p_cutoff timestamptz DEFAULT now()
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  WITH ins AS (
    INSERT INTO public.seen_receipt_prefs (relationship_id, user_id, seen_on)
    SELECT r.id, m.user_id, true
    FROM public.relationships r
    CROSS JOIN LATERAL (VALUES (r.user_a), (r.user_b)) AS m(user_id)
    WHERE r.user_b IS NOT NULL
      AND r.status IN ('active', 'paused')
      AND (r.invite_accepted_at IS NULL OR r.invite_accepted_at < p_cutoff)
    ON CONFLICT (relationship_id, user_id) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM ins;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.seen_receipts_backfill_defaults(timestamptz) FROM PUBLIC, anon, authenticated;

DO $$ BEGIN PERFORM public.seen_receipts_backfill_defaults(); END $$;

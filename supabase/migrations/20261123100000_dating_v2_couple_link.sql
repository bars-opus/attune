-- Spec 2 W9 (§3.9, §4.3, §4.4, §4.9 W9, §7.1; S-4, S-6, A-3, I-12, I-13,
-- C-4; Rulings R-W9-1..R-W9-9): "Become a couple on Attune". The flag
-- dating_couple_link (off); link requests, the second Yes's one
-- transaction (the invite exchange's row transitions, both paused, both
-- paths Relationship, every other open conversation closed neutrally,
-- the first messages kept only when both chose it, masked unless both
-- swapped), the link origin (members only), the post-link offer, How we
-- met, the export's own-data Dating part (dating_export_for_job, bound
-- to a building job, at most three reads, each recorded) and
-- export_relationship re-created from its live body with the How we met
-- card, and prepare_account_deletion re-created from its live body: a
-- deleted account takes its couple's How we met card. Grants in
-- 20261123100010_dating_v2_couple_link_grants.sql. Ends by
-- revoking everything it creates from every API role (the W6 final
-- pattern: a push that stops between this file and its twin fails
-- closed).
BEGIN;
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------
-- 1. The flag (off; supabase/sql/dev_enable_spec2_dating_flags.sql turns
--    it on in development) and its production gate (Spec 1's gate
--    trigger). With it off nothing W9 adds answers anything but
--    unavailable (and the reads answer nothing to show).
-- ---------------------------------------------------------------------
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('dating_couple_link', 'Spec 2 W9 gate: counsel confirms the export scope (own data only, own sent messages, no counterpart data) and the How we met copy rule (both consent); the copy, DV and LGBTQ+ reviewers sign the Become a couple copy')
ON CONFLICT (flag_key) DO NOTHING;
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_couple_link', false)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. The tables (§4.3). Every one: RLS on, nothing for any API role (the
--    self-revoke and the twin; S-5: no service role either). Reads and
--    writes go through the definer functions below.
-- ---------------------------------------------------------------------
-- A request to become a couple, one open per match (§3.9 steps 1-3). The
-- requester's own Yes is its confirmation; it lapses 14 days on, with no
-- copy. Deleted with its match (the 30-day evidence window's purge).
CREATE TABLE IF NOT EXISTS public.dating_couple_link_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  requested_by_side text NOT NULL CHECK (requested_by_side IN ('low', 'high')),
  low_confirmed_at timestamptz,
  high_confirmed_at timestamptz,
  low_keep_messages boolean NOT NULL DEFAULT false,
  high_keep_messages boolean NOT NULL DEFAULT false,
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'linked', 'declined', 'cancelled', 'expired')),
  -- Purged with its relationship (Task 1 fix round 1, I-1): a linked
  -- request must never stop a relationship's deletion (the nightly purge).
  relationship_id uuid REFERENCES public.relationships (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '14 days',
  decided_at timestamptz,
  CONSTRAINT dating_couple_link_requests_requester_confirmed CHECK (
    (requested_by_side = 'low' AND low_confirmed_at IS NOT NULL)
    OR (requested_by_side = 'high' AND high_confirmed_at IS NOT NULL)),
  -- §3.9: no relationship before both say yes.
  CONSTRAINT dating_couple_link_requests_linked_by_both CHECK (
    state <> 'linked' OR (low_confirmed_at IS NOT NULL AND high_confirmed_at IS NOT NULL AND relationship_id IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS dating_couple_link_requests_one_open
  ON public.dating_couple_link_requests (match_id) WHERE state = 'open';
CREATE INDEX IF NOT EXISTS dating_couple_link_requests_match_idx
  ON public.dating_couple_link_requests (match_id, created_at DESC);
-- Final server fix (M-5): every relationship delete checks this cascade.
CREATE INDEX IF NOT EXISTS dating_couple_link_requests_relationship_idx
  ON public.dating_couple_link_requests (relationship_id) WHERE relationship_id IS NOT NULL;
ALTER TABLE public.dating_couple_link_requests ENABLE ROW LEVEL SECURITY;

-- "How we met" (§3.9 step 3, A-3): the first 50 messages, copied only when
-- both chose it, masked unless both had swapped. Purged with the
-- relationship (§4.8). items: [{by, kind, question_id, text, at}], by the
-- sender's user id (the reads and the export say "me" or "partner").
CREATE TABLE IF NOT EXISTS public.couple_how_we_met (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships (id) ON DELETE CASCADE,
  items jsonb NOT NULL CHECK (jsonb_typeof(items) = 'array' AND jsonb_array_length(items) BETWEEN 1 AND 50),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.couple_how_we_met ENABLE ROW LEVEL SECURITY;

-- Where a relationship came from (S-6, I-12; Ruling R-W9-3): the day the
-- two matched, when they linked, and each side's two once-only moments:
-- "You decided together." seen, and the 30-day offer closed ("Keep for
-- now" never asks again). Purged with the relationship; a deleted account
-- leaves its side empty. Read only by members (get_dating_link_origin,
-- get_dating_post_link_offer).
CREATE TABLE IF NOT EXISTS public.dating_link_origins (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships (id) ON DELETE CASCADE,
  matched_at timestamptz NOT NULL,
  linked_at timestamptz NOT NULL DEFAULT now(),
  low_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  high_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  low_moment_seen_at timestamptz,
  high_moment_seen_at timestamptz,
  low_offer_closed_at timestamptz,
  high_offer_closed_at timestamptz
);
CREATE INDEX IF NOT EXISTS dating_link_origins_low_idx ON public.dating_link_origins (low_user_id);
CREATE INDEX IF NOT EXISTS dating_link_origins_high_idx ON public.dating_link_origins (high_user_id);
ALTER TABLE public.dating_link_origins ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- 3. Helpers.
-- ---------------------------------------------------------------------
-- The couple link's switch: its own flag and the chat's (a link starts in
-- a chat).
CREATE OR REPLACE FUNCTION private.dating_link_on()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.dating_flag_enabled('dating_couple_link') IS TRUE AND private.dating_chat_on() IS TRUE;
$$;

-- Ruling R-W9-6: someone in an Attune relationship (active or paused) or
-- under an account hold can't ask. Asked of the caller alone (a request
-- never says anything about the other person's life); at the second Yes
-- the invite exchange's own checks ask it of both.
CREATE OR REPLACE FUNCTION private.dating_link_blocked(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_user IS NULL
      OR EXISTS (SELECT 1 FROM public.relationships AS r
                  WHERE p_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused'))
      OR EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.resolved_at IS NULL);
$$;

-- What the chat shows of the couple link, for [p_side] of [p_m] (§3.9;
-- Ruling R-W9-2): null (nothing; Become a couple not offered), or
-- {state}: 'none' (either has said We met: this side may ask), 'asked'
-- (this side asked; waiting), 'asked_you' (the other side asked: the card
-- and the sheet), 'not_ready' (the other side said Not right now to this
-- side's request, for 14 days), 'linked' (with 'moment': this side has
-- not seen "You decided together." yet). A lapsed request is nothing.
-- Read only after the reader's own trip check (S-5): it names no gender,
-- pool or trip.
CREATE OR REPLACE FUNCTION private.dating_link_json(p_m public.dating_matches, p_side text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_other constant uuid := CASE WHEN p_side = 'low' THEN p_m.user_high_id ELSE p_m.user_low_id END;
  v_r public.dating_couple_link_requests;
  v_o public.dating_link_origins;
BEGIN
  IF p_m.id IS NULL OR p_side NOT IN ('low', 'high') OR NOT private.dating_link_on() THEN
    RETURN NULL;
  END IF;
  IF p_m.state = 'closed' AND p_m.closed_reason = 'couple_linked' THEN
    SELECT o.* INTO v_o FROM public.dating_couple_link_requests AS r
      JOIN public.dating_link_origins AS o ON o.relationship_id = r.relationship_id
     WHERE r.match_id = p_m.id AND r.state = 'linked';
    IF v_o.relationship_id IS NULL THEN
      RETURN NULL;
    END IF;
    -- Final server fix (M-1): the moment only while the relationship is
    -- open; once it has ended the sealed chat reads plainly ended.
    RETURN pg_catalog.jsonb_build_object('state', 'linked', 'moment',
      (CASE WHEN p_side = 'low' THEN v_o.low_moment_seen_at ELSE v_o.high_moment_seen_at END) IS NULL
      AND EXISTS (SELECT 1 FROM public.relationships AS x
                   WHERE x.id = v_o.relationship_id AND x.status IN ('active', 'paused')));
  END IF;
  IF p_m.state <> 'active' OR v_other IS NULL OR p_m.user_low_id IS NULL OR p_m.user_high_id IS NULL
     OR private.dating_pair_blocked(p_m.user_low_id, p_m.user_high_id) THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_r FROM public.dating_couple_link_requests AS r
   WHERE r.match_id = p_m.id AND r.state = 'open' AND r.expires_at > now();
  IF v_r.id IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('state', CASE WHEN v_r.requested_by_side = p_side THEN 'asked' ELSE 'asked_you' END,
                                         'request_id', v_r.id);
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_couple_link_requests AS r
              WHERE r.match_id = p_m.id AND r.state = 'declined' AND r.requested_by_side = p_side
                AND r.decided_at > now() - interval '14 days') THEN
    RETURN pg_catalog.jsonb_build_object('state', 'not_ready');
  END IF;
  IF p_m.low_we_met_at IS NULL AND p_m.high_we_met_at IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN pg_catalog.jsonb_build_object('state', 'none');
END;
$$;

-- ---------------------------------------------------------------------
-- 4. The couple link (§3.9, §4.4).
-- ---------------------------------------------------------------------
-- The link page's read (§3.14 /dating/link/:matchId; Ruling R-W9-2): the
-- other person's first name and the link's state, as the chat's header
-- shows them, behind the same trip check as the chat (S-5). VOLATILE
-- (final server fix, M-6; W5's R-T5-5): a read that hides by trip touches
-- the phone's last use like the chat's read, so PostgREST must let it
-- write; it writes nothing else.
CREATE OR REPLACE FUNCTION public.get_dating_couple_link(p_match_id uuid, p_show_same_gender boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_sg boolean;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF NOT private.dating_link_on() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_m FROM public.dating_matches AS m
   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
     AND (m.state = 'active' OR m.evidence_until > now());
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END;
  IF private.dating_trip_hides(v_user, CASE WHEN v_m.user_low_id = v_user THEN v_m.user_high_id ELSE v_m.user_low_id END,
                               'match', v_sg) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
  RETURN pg_catalog.jsonb_build_object('ok', true,
    'display_name', (SELECT p.display_name FROM public.dating_profiles AS p
                      WHERE p.user_id = CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END),
    'link', private.dating_link_json(v_m, v_side));
END;
$$;

-- Step 1: "Ask {Name}". The requester's Yes, and whether they would keep
-- the first messages. A replay (or a second tap) answers the same;
-- refusals are fixed codes. Ruling R-W9-6: only the caller's own life is
-- asked (never the other person's); Ruling R-W9-5: after the other side's
-- "Not right now" this side may ask again only 14 days on (not_ready);
-- the other side may ask any time. Carry 5 (S-5): a match the caller's own
-- trip hides is match_unavailable, as every read; the other side's trip
-- changes nothing in the answer (they see the request once it shows on
-- their phone). p_key is checked for its format only and never claimed:
-- a repeat is answered by the request's state (the open request is this
-- side's own), not by the key (Task 1 fix round 1, M-2).
CREATE OR REPLACE FUNCTION public.request_dating_couple_link(p_key text, p_match_id uuid, p_keep_messages boolean,
                                                           p_show_same_gender boolean DEFAULT false)
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
  v_r public.dating_couple_link_requests;
  v_sg boolean;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR p_keep_messages IS NULL OR NOT private.dating_key_ok(p_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF NOT private.dating_link_on() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user); -- the shared lock order (setup first)
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id) FOR NO KEY UPDATE;
      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      v_other := CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
      v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END;
      IF private.dating_trip_hides(v_user, v_other, 'match', v_sg) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL
         OR private.dating_pair_blocked(v_m.user_low_id, v_m.user_high_id) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
      END IF;
      -- A lapsed request ends (with no copy) before anything is asked again.
      UPDATE public.dating_couple_link_requests AS r SET state = 'expired', decided_at = r.expires_at
       WHERE r.match_id = p_match_id AND r.state = 'open' AND r.expires_at <= now();
      SELECT * INTO v_r FROM public.dating_couple_link_requests AS r WHERE r.match_id = p_match_id AND r.state = 'open';
      IF v_r.id IS NOT NULL THEN
        IF v_r.requested_by_side = v_side THEN
          RETURN pg_catalog.jsonb_build_object('ok', true, 'request_id', v_r.id);
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'asked_you');
      END IF;
      IF v_m.low_we_met_at IS NULL AND v_m.high_we_met_at IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_yet');
      END IF;
      IF EXISTS (SELECT 1 FROM public.dating_couple_link_requests AS r
                  WHERE r.match_id = p_match_id AND r.state = 'declined' AND r.requested_by_side = v_side
                    AND r.decided_at > now() - interval '14 days') THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_ready');
      END IF;
      IF private.dating_link_blocked(v_user) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
      END IF;
      INSERT INTO public.dating_couple_link_requests (match_id, requested_by_side, low_confirmed_at, high_confirmed_at,
                                                      low_keep_messages, high_keep_messages)
      VALUES (p_match_id, v_side, CASE WHEN v_side = 'low' THEN now() END, CASE WHEN v_side = 'high' THEN now() END,
              v_side = 'low' AND p_keep_messages, v_side = 'high' AND p_keep_messages)
      RETURNING * INTO v_r;
      -- Both chats read the request (the asker's other phone too).
      PERFORM private.dating_bump_chat(v_m.user_low_id, p_match_id);
      PERFORM private.dating_bump_chat(v_m.user_high_id, p_match_id);
      PERFORM private.bump_metric_internal('dating.couple_link.asked');
      RETURN pg_catalog.jsonb_build_object('ok', true, 'request_id', v_r.id);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- "Not right now" (step 2): the other side's answer. Nothing is said to
-- anyone but the asker ("{Name} isn't ready yet.", from the header). An
-- exposure-reducing write: no flag, no trusted phone (W5-W7 lesson). A
-- replay answers ok.
CREATE OR REPLACE FUNCTION public.decline_dating_couple_link(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_r public.dating_couple_link_requests;
  v_m public.dating_matches;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      SELECT m.* INTO v_m FROM public.dating_couple_link_requests AS r
        JOIN public.dating_matches AS m ON m.id = r.match_id
       WHERE r.id = p_request_id AND v_user IN (m.user_low_id, m.user_high_id)
         FOR NO KEY UPDATE OF m;
      SELECT * INTO v_r FROM public.dating_couple_link_requests AS r WHERE r.id = p_request_id FOR UPDATE;
      IF v_m.id IS NULL OR v_r.requested_by_side = (CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      IF v_r.state = 'declined' THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      IF v_r.state <> 'open' OR v_r.expires_at <= now() THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      UPDATE public.dating_couple_link_requests SET state = 'declined', decided_at = now() WHERE id = p_request_id;
      PERFORM private.dating_bump_chat(v_m.user_low_id, v_m.id);
      PERFORM private.dating_bump_chat(v_m.user_high_id, v_m.id);
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

-- The asker takes it back while it is open (the other side's card goes;
-- nothing is said). Exposure-reducing too. A replay answers ok; once linked
-- it is too late (linked).
CREATE OR REPLACE FUNCTION public.cancel_dating_couple_link(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_r public.dating_couple_link_requests;
  v_m public.dating_matches;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      SELECT m.* INTO v_m FROM public.dating_couple_link_requests AS r
        JOIN public.dating_matches AS m ON m.id = r.match_id
       WHERE r.id = p_request_id AND v_user IN (m.user_low_id, m.user_high_id)
         FOR NO KEY UPDATE OF m;
      SELECT * INTO v_r FROM public.dating_couple_link_requests AS r WHERE r.id = p_request_id FOR UPDATE;
      IF v_m.id IS NULL OR v_r.requested_by_side <> (CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      IF v_r.state = 'cancelled' THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      IF v_r.state = 'linked' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'linked');
      END IF;
      IF v_r.state <> 'open' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      UPDATE public.dating_couple_link_requests SET state = 'cancelled', decided_at = now() WHERE id = p_request_id;
      PERFORM private.dating_bump_chat(v_m.user_low_id, v_m.id);
      PERFORM private.dating_bump_chat(v_m.user_high_id, v_m.id);
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

-- Step 3: the second Yes, in one transaction (§3.9, §8 W9; Rulings
-- R-W9-1, R-W9-4). Locks: both people's setup locks (every Dating
-- writer's first lock), the match and the request, then both users rows
-- lowest id first (the invite exchange's order; its own locks are then
-- already held). The relationship is made by the invite exchange itself
-- (Ruling R-W9-1): the pending row create-relationship-invite inserts,
-- then accept_relationship_invite_v2 unchanged (active with both members,
-- the relationship_invite_acceptances row), so every existing trigger
-- fires as it does for an invite: the
-- relationship guard pauses Dating for both (with 'relationship'), the
-- new chapter archives old ended ones. Then both paths become
-- Relationship, every other open conversation of either person closes as
-- 'other_linked' (the neutral "This conversation has ended."), this one as
-- 'couple_linked'; the first 50 messages are kept only when both chose it,
-- masked unless both swapped (A-3). No push (Ruling R-W9-7). A replay by
-- the confirmer answers the same relationship. p_key is checked for its
-- format only and never claimed: idempotency is by the request's state (a
-- linked request answers its relationship to the confirmer). A busy answer
-- after a sent Yes can hide a link that landed, so the app re-reads the
-- link rather than calling it a failure (Task 1 fix round 1, M-2).
CREATE OR REPLACE FUNCTION public.confirm_dating_couple_link(p_key text, p_request_id uuid, p_keep_messages boolean,
                                                           p_show_same_gender boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_low uuid;
  v_high uuid;
  v_m public.dating_matches;
  v_r public.dating_couple_link_requests;
  v_side text;
  v_asker uuid;
  v_sg boolean;
  v_code text;
  v_rel uuid;
  v_acc jsonb;
  v_closed uuid[];
  v_both boolean;
  v_items jsonb;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL OR p_keep_messages IS NULL OR NOT private.dating_key_ok(p_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF NOT private.dating_link_on() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  -- The pair, read without a lock, so both setup locks come first.
  SELECT m.user_low_id, m.user_high_id INTO v_low, v_high
    FROM public.dating_couple_link_requests AS r JOIN public.dating_matches AS m ON m.id = r.match_id
   WHERE r.id = p_request_id AND v_user IN (m.user_low_id, m.user_high_id);
  IF v_low IS NULL OR v_high IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup_pair(v_low, v_high);
      SELECT m.* INTO v_m FROM public.dating_couple_link_requests AS r
        JOIN public.dating_matches AS m ON m.id = r.match_id
       WHERE r.id = p_request_id AND v_user IN (m.user_low_id, m.user_high_id)
         FOR UPDATE OF m;
      SELECT * INTO v_r FROM public.dating_couple_link_requests AS r WHERE r.id = p_request_id FOR UPDATE;
      IF v_m.id IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      IF v_r.state = 'linked' AND v_r.requested_by_side <> v_side AND v_r.relationship_id IS NOT NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', true, 'relationship_id', v_r.relationship_id);
      END IF;
      v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END;
      IF private.dating_trip_hides(v_user, CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END,
                                   'match', v_sg) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      IF v_r.state <> 'open' OR v_r.expires_at <= now() THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      -- §3.9: the asker's own Yes is the first; it never makes the couple.
      IF v_r.requested_by_side = v_side THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'asked');
      END IF;
      IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL
         OR private.dating_pair_blocked(v_m.user_low_id, v_m.user_high_id) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
      END IF;
      -- Both users rows, lowest id first (the invite exchange's order).
      -- Either in an open Attune relationship or under a hold: the invite
      -- exchange's own checks refuse it below (unavailable).
      PERFORM 1 FROM public.users AS u WHERE u.id IN (v_m.user_low_id, v_m.user_high_id) ORDER BY u.id FOR UPDATE;
      v_asker := CASE WHEN v_r.requested_by_side = 'low' THEN v_m.user_low_id ELSE v_m.user_high_id END;
      -- The invite exchange itself (Ruling R-W9-1, the controller's: one
      -- pairing path). The pending row create-relationship-invite inserts
      -- (its columns; a 12-character code no one is shown, 7 days), then the
      -- invite exchange's own accept_relationship_invite_v2, unchanged: the
      -- pending -> active transition, the acceptance row, the acceptor's
      -- own and the inviter's other pending invites gone, the acceptor's
      -- path, About us's drafts and the invite metrics, with every trigger
      -- firing as for an invite.
      v_code := upper(left(replace(gen_random_uuid()::text, '-', ''), 12));
      INSERT INTO public.relationships (user_a, status, invite_code, invite_expires_at)
      VALUES (v_asker, 'pending', v_code, now() + interval '7 days')
      RETURNING id INTO v_rel;
      v_acc := public.accept_relationship_invite_v2(v_user, v_code);
      IF (v_acc ->> 'relationship_id')::uuid IS DISTINCT FROM v_rel OR (v_acc ->> 'status') IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'link:invite_mismatch';
      END IF;
      -- The asker's path too (the invite exchange sets only the acceptor's).
      PERFORM public.set_user_path_internal(v_asker, 'relationship');
      -- Every open conversation of either person closes; this one as linked.
      SELECT coalesce(pg_catalog.array_agg(x.id), '{}'::uuid[]) INTO v_closed
        FROM (SELECT m.id FROM public.dating_matches AS m
               WHERE m.state = 'active'
                 AND (m.user_low_id IN (v_m.user_low_id, v_m.user_high_id) OR m.user_high_id IN (v_m.user_low_id, v_m.user_high_id))
               ORDER BY m.id FOR NO KEY UPDATE OF m) AS x;
      UPDATE public.dating_matches AS m
         SET state = 'closed', closed_at = coalesce(m.closed_at, now()), evidence_until = now() + interval '30 days',
             closed_reason = CASE WHEN m.id = v_m.id THEN 'couple_linked' ELSE 'other_linked' END
       WHERE m.id = ANY (v_closed);
      UPDATE public.dating_couple_link_requests AS r SET state = 'cancelled', decided_at = now()
       WHERE r.match_id = ANY (v_closed) AND r.state = 'open' AND r.id <> p_request_id;
      PERFORM private.dating_bump_chat(x.u, m.id)
         FROM public.dating_matches AS m CROSS JOIN LATERAL (VALUES (m.user_low_id), (m.user_high_id)) AS x(u)
        WHERE m.id = ANY (v_closed);
      -- "How we met" (A-3): only when both chose it; masked unless both swapped.
      IF p_keep_messages AND (CASE WHEN v_r.requested_by_side = 'low' THEN v_r.low_keep_messages ELSE v_r.high_keep_messages END) THEN
        v_both := v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL;
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                 'by', q.sender_user_id, 'kind', q.kind, 'question_id', q.question_id,
                 'text', CASE WHEN v_both THEN q.body ELSE q.body_masked END, 'at', q.k) ORDER BY q.k, q.id)
          INTO v_items
          FROM (SELECT d.*, private.dating_message_sort_at(d) AS k FROM public.dating_messages AS d
                 WHERE d.match_id = v_m.id AND d.kind IN ('text', 'guided_answer')
                   AND private.dating_message_visible(d, 'low') AND private.dating_message_visible(d, 'high')
                 ORDER BY private.dating_message_sort_at(d), d.id LIMIT 50) AS q;
        IF v_items IS NOT NULL THEN
          INSERT INTO public.couple_how_we_met (relationship_id, items) VALUES (v_rel, v_items);
        END IF;
      END IF;
      INSERT INTO public.dating_link_origins (relationship_id, matched_at, linked_at, low_user_id, high_user_id,
                                              low_moment_seen_at, high_moment_seen_at)
      VALUES (v_rel, v_m.matched_at, now(), v_m.user_low_id, v_m.user_high_id,
              CASE WHEN v_side = 'low' THEN now() END, CASE WHEN v_side = 'high' THEN now() END);
      UPDATE public.dating_couple_link_requests
         SET state = 'linked', relationship_id = v_rel, decided_at = now(),
             low_confirmed_at = coalesce(low_confirmed_at, CASE WHEN v_side = 'low' THEN now() END),
             high_confirmed_at = coalesce(high_confirmed_at, CASE WHEN v_side = 'high' THEN now() END),
             low_keep_messages = CASE WHEN v_side = 'low' THEN p_keep_messages ELSE low_keep_messages END,
             high_keep_messages = CASE WHEN v_side = 'high' THEN p_keep_messages ELSE high_keep_messages END
       WHERE id = p_request_id;
      PERFORM private.bump_metric_internal('dating.couple_link');
      RETURN pg_catalog.jsonb_build_object('ok', true, 'relationship_id', v_rel);
    EXCEPTION
      WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
        -- A busy Dating pause raises dating:busy with the lock error's
        -- SQLSTATE after its own three tries: no nesting (W1 N-M3), so the
        -- worst case is three lock waits before busy.
        IF v_try = 3 OR SQLERRM = 'dating:busy' THEN
          RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
        END IF;
      WHEN raise_exception THEN
        -- The invite exchange's refusals (a relationship opened meanwhile,
        -- a hold, an age): the whole attempt is undone.
        IF SQLERRM IN ('relationship:already_open', 'account:hold') OR SQLERRM LIKE 'invite:%' THEN
          RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
        END IF;
        RAISE;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Where the couple came from, and what follows (§3.9 steps 4-6; S-6,
--    I-12, C-4; Rulings R-W9-3, R-W9-8).
-- ---------------------------------------------------------------------
-- The match date for About us's chip (I-12), to the relationship's two
-- members only, while it is open (active or paused). Anyone else, a
-- relationship with no Dating origin, an ended one, or the flag off: the
-- same opaque answer (S-6). The validity check never branches on
-- membership first (Fable H2).
CREATE OR REPLACE FUNCTION public.get_dating_link_origin(p_relationship_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_at timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  SELECT o.matched_at INTO v_at
    FROM public.dating_link_origins AS o JOIN public.relationships AS r ON r.id = o.relationship_id
   WHERE p_relationship_id IS NOT NULL AND o.relationship_id = p_relationship_id
     AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
     AND public.dating_flag_enabled('dating_couple_link') IS TRUE;
  IF v_at IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'link_origin_unavailable');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'matched_at', v_at);
END;
$$;

-- The "How we met" card (§3.9 step 3, §8 W9: a row on About us opens it),
-- to the two members only, while the relationship is open: each message
-- as both saw it, "mine" for the reader's own. Anyone else, no card, or
-- the flag off: the same opaque answer.
CREATE OR REPLACE FUNCTION public.get_how_we_met(p_relationship_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_items jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  SELECT h.items INTO v_items
    FROM public.couple_how_we_met AS h JOIN public.relationships AS r ON r.id = h.relationship_id
   WHERE p_relationship_id IS NOT NULL AND h.relationship_id = p_relationship_id
     AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
     AND public.dating_flag_enabled('dating_couple_link') IS TRUE;
  IF v_items IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'how_we_met_unavailable');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'items',
    (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'mine', (x.v ->> 'by') = v_user::text, 'kind', x.v ->> 'kind', 'question_id', x.v -> 'question_id',
              'text', x.v ->> 'text', 'at', x.v -> 'at') ORDER BY x.n)
       FROM pg_catalog.jsonb_array_elements(v_items) WITH ORDINALITY AS x(v, n)));
END;
$$;

-- What the Relationship home's link_offer card shows for the caller (C-4;
-- Ruling R-W9-3): 'linked' ("You decided together.", once, for whoever did
-- not see it at the second Yes), then from 30 days after linking 'delete'
-- ("Delete your Dating profile and preferences?", until either answer,
-- and only while there is Dating data to delete), else null. Only the
-- caller's open relationship's origin counts.
CREATE OR REPLACE FUNCTION public.get_dating_post_link_offer()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_o public.dating_link_origins;
  v_low boolean;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_flag_enabled('dating_couple_link') IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', NULL);
  END IF;
  SELECT o.* INTO v_o
    FROM public.dating_link_origins AS o JOIN public.relationships AS r ON r.id = o.relationship_id
   WHERE v_user IN (o.low_user_id, o.high_user_id) AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
   ORDER BY o.linked_at DESC LIMIT 1;
  IF v_o.relationship_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', NULL);
  END IF;
  v_low := v_o.low_user_id = v_user;
  IF (CASE WHEN v_low THEN v_o.low_moment_seen_at ELSE v_o.high_moment_seen_at END) IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', 'linked');
  END IF;
  IF now() >= v_o.linked_at + interval '30 days'
     AND (CASE WHEN v_low THEN v_o.low_offer_closed_at ELSE v_o.high_offer_closed_at END) IS NULL
     AND private.dating_has_data(v_user) THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', 'delete');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', NULL);
END;
$$;

-- The card's answers (Ruling R-W9-3): 'linked' once "You decided
-- together." has shown; 'delete' for "Keep for now" (never asked again).
-- "Delete my Dating data" opens Leave Dating (§3.8), whose exit removes
-- the data the offer needs. A replay answers ok.
CREATE OR REPLACE FUNCTION public.dismiss_dating_post_link_offer(p_offer text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_rel uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_offer IS NULL OR p_offer NOT IN ('linked', 'delete') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT o.relationship_id INTO v_rel
    FROM public.dating_link_origins AS o JOIN public.relationships AS r ON r.id = o.relationship_id
   WHERE v_user IN (o.low_user_id, o.high_user_id) AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
   ORDER BY o.linked_at DESC LIMIT 1;
  IF v_rel IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'offer_unavailable');
  END IF;
  UPDATE public.dating_link_origins AS o
     SET low_moment_seen_at = CASE WHEN p_offer = 'linked' AND o.low_user_id = v_user
                                   THEN coalesce(o.low_moment_seen_at, now()) ELSE o.low_moment_seen_at END,
         high_moment_seen_at = CASE WHEN p_offer = 'linked' AND o.high_user_id = v_user
                                    THEN coalesce(o.high_moment_seen_at, now()) ELSE o.high_moment_seen_at END,
         low_offer_closed_at = CASE WHEN p_offer = 'delete' AND o.low_user_id = v_user
                                    THEN coalesce(o.low_offer_closed_at, now()) ELSE o.low_offer_closed_at END,
         high_offer_closed_at = CASE WHEN p_offer = 'delete' AND o.high_user_id = v_user
                                     THEN coalesce(o.high_offer_closed_at, now()) ELSE o.high_offer_closed_at END
   WHERE o.relationship_id = v_rel;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------
-- 6. The export's own-data Dating part (§4.2, §4.3, S-4, I-13; Ruling
--    R-W9-9).
-- ---------------------------------------------------------------------
-- Each call of dating_export_for_job, by job: no content (S-4).
CREATE TABLE IF NOT EXISTS public.dating_export_reads (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_id uuid NOT NULL REFERENCES public.data_export_jobs (id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS dating_export_reads_job_idx ON public.dating_export_reads (job_id);
ALTER TABLE public.dating_export_reads ENABLE ROW LEVEL SECURITY;

-- The one service-role path to decrypted fields (S-4): no user id; the job
-- must be building (its user is the one who asked, through
-- request_my_export; no API role can make or rewrite a job, below); at
-- most three reads of Dating data a job (the worker's three tries of a
-- part), each recorded. Only calls that return are logged (a raise, such
-- as export:unavailable, rolls its row back), and someone with no Dating
-- data never spends a read (fix round 1, Task 4 review I-1: their live
-- export must never fail on this). The person's own data only: what they set up
-- and chose (decrypted), their own sent messages (as they wrote them), and
-- nothing about anyone they matched (no name, no age, no message of
-- theirs, no reason a conversation ended). No id of any kind. NULL when
-- there is no Dating data (build-data-exports then writes no dating.json).
CREATE OR REPLACE FUNCTION public.dating_export_for_job(p_job_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job public.data_export_jobs;
  v_user uuid;
  v_s public.dating_profile_sensitive;
  v_identity jsonb;
  v_seeking jsonb;
  v_faith jsonb;
  v_marital jsonb;
BEGIN
  SELECT * INTO v_job FROM public.data_export_jobs AS j WHERE j.id = p_job_id FOR UPDATE;
  IF v_job.id IS NULL OR v_job.status IS DISTINCT FROM 'building' THEN
    RAISE EXCEPTION 'export:not_building';
  END IF;
  v_user := v_job.user_id;
  IF NOT (private.dating_has_data(v_user)
          OR EXISTS (SELECT 1 FROM public.dating_consent_events AS c WHERE c.user_id = v_user)
          OR EXISTS (SELECT 1 FROM public.dating_messages AS d WHERE d.sender_user_id = v_user)
          OR EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user)) THEN
    RETURN NULL;
  END IF;
  IF (SELECT count(*) FROM public.dating_export_reads AS x WHERE x.job_id = p_job_id) >= 3 THEN
    RAISE EXCEPTION 'export:read_limit';
  END IF;
  INSERT INTO public.dating_export_reads (job_id) VALUES (p_job_id);
  SELECT * INTO v_s FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
  BEGIN
    v_identity := private.dating_field_decrypt(v_s.identity_enc);
    v_seeking := private.dating_field_decrypt(v_s.seeking_enc);
    v_faith := private.dating_field_decrypt(v_s.faith_enc);
    v_marital := private.dating_field_decrypt(v_s.marital_enc);
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
      RAISE EXCEPTION 'export:unavailable';
    END IF;
    RAISE;
  END;
  RETURN pg_catalog.jsonb_build_object(
    'format', 'attune-dating-export', 'version', 1, 'generated_at', now(),
    'about', 'Your own Dating data: what you set up and chose, and the messages you sent. Nothing anyone else wrote or chose is in it.',
    'enrolment', (SELECT pg_catalog.jsonb_build_object('state', e.state, 'terms_version', e.terms_version,
                    'opted_in_at', e.opted_in_at, 'activated_at', e.activated_at, 'paused_at', e.paused_at,
                    'pause_reason', e.pause_reason, 'exited_at', e.exited_at)
                    FROM public.dating_enrollments AS e WHERE e.user_id = v_user),
    'profile', (SELECT pg_catalog.jsonb_build_object('display_name', p.display_name, 'country', p.country_code,
                  'region', p.region_code, 'side', p.side_code, 'intention', p.intention,
                  'marriage_timeline', p.marriage_timeline, 'timeline_visible', p.timeline_visible,
                  'attested_not_married_at', p.not_married_attested_at, 'children_have', p.children_have,
                  'children_want', p.children_want, 'family_involvement', p.family_involvement,
                  'gender_visible', p.gender_visible, 'faith_visible', p.faith_visible, 'marital_visible', p.marital_visible,
                  'photos_after_mutual', p.photos_after_mutual, 'state', p.profile_state, 'verified_at', p.verified_at)
                  FROM public.dating_profiles AS p WHERE p.user_id = v_user),
    'about_you', pg_catalog.jsonb_build_object('identity', v_identity, 'seeking', v_seeking -> 'seeking',
                                               'faith', v_faith, 'marital', v_marital ->> 'marital'),
    'preferences', (SELECT pg_catalog.jsonb_build_object('min_age', d.min_age, 'max_age', d.max_age,
                      'region_scope', d.region_scope, 'open_abroad', to_jsonb(d.open_abroad),
                      'want_must_match', d.want_must_match, 'exclude_parents', d.exclude_parents)
                      FROM public.dating_preferences AS d WHERE d.user_id = v_user),
    'settings', (SELECT pg_catalog.jsonb_build_object('drop_time', to_char(t.drop_time, 'HH24:MI'), 'data_saver', t.data_saver,
                   'digest_push', t.digest_push, 'chat_push', t.chat_push, 'show_when_away', t.show_when_away)
                   FROM public.dating_settings AS t WHERE t.user_id = v_user),
    'prompts', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('prompt', q.prompt_id, 'answer', q.answer,
                           'state', q.moderation_state) ORDER BY q.position)
                           FROM public.dating_prompts AS q WHERE q.user_id = v_user), '[]'::jsonb),
    'photos', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('position', f.position, 'caption', f.caption,
                          'state', f.moderation_state, 'added_at', f.created_at) ORDER BY f.position)
                          FROM public.dating_profile_photos AS f WHERE f.user_id = v_user), '[]'::jsonb),
    'consents', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('purpose', c.purpose, 'action', c.action,
                            'policy_version', c.policy_version, 'at', c.occurred_at) ORDER BY c.occurred_at, c.created_at)
                            FROM public.dating_consent_events AS c WHERE c.user_id = v_user), '[]'::jsonb),
    'verification', (SELECT pg_catalog.jsonb_build_object('age_method', a.age_method, 'age_result', a.age_result,
                       'age_decided_at', a.age_decided_at, 'identity_method', a.identity_method,
                       'identity_result', a.identity_result, 'identity_decided_at', a.identity_decided_at,
                       'revoked_at', a.revoked_at)
                       FROM public.dating_age_verifications AS a WHERE a.user_id = v_user),
    'trusted_phones', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('verified_at', t.verified_at,
                                  'last_seen_at', t.last_seen_at) ORDER BY t.verified_at)
                                  FROM public.dating_trusted_devices AS t WHERE t.user_id = v_user), '[]'::jsonb),
    'never_introduce', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('label', n.label, 'added_at', n.created_at)
                                   ORDER BY n.created_at)
                                   FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_user), '[]'::jsonb),
    'gentle_wait', (SELECT pg_catalog.jsonb_build_object('answers', g.answers, 'saved_at', g.saved_at)
                      FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_user),
    'date_reflections', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('response', r.response, 'note', r.note,
                                    'at', r.created_at) ORDER BY r.created_at)
                                    FROM public.dating_date_reflections AS r WHERE r.author_user_id = v_user), '[]'::jsonb),
    'conversations', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                 'name', 'conversation-' || c.n, 'matched_at', c.matched_at,
                                 'state', CASE WHEN c.state = 'active' THEN 'open' ELSE 'ended' END, 'ended_at', c.closed_at,
                                 'my_messages', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                     'at', d.created_at, 'kind', d.kind, 'question', d.question_id, 'text', d.body)
                                     ORDER BY d.created_at, d.id)
                                   FROM public.dating_messages AS d
                                  WHERE d.match_id = c.id AND d.sender_user_id = v_user), '[]'::jsonb)) ORDER BY c.n)
                                 FROM (SELECT m.id, m.matched_at, m.state, m.closed_at,
                                              row_number() OVER (ORDER BY m.matched_at, m.id) AS n
                                         FROM public.dating_matches AS m
                                        WHERE v_user IN (m.user_low_id, m.user_high_id)) AS c), '[]'::jsonb),
    'reports_i_made', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('category', r.category,
                                  'details', r.details, 'at', r.created_at) ORDER BY r.created_at)
                                  FROM public.dating_reports AS r WHERE r.reporter_user_id = v_user), '[]'::jsonb),
    'restrictions', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('type', x.restriction_type,
                                'category', x.category, 'starts_at', x.starts_at, 'ends_at', x.ends_at,
                                'lifted_at', x.lifted_at) ORDER BY x.starts_at)
                                FROM public.dating_account_restrictions AS x WHERE x.user_id = v_user), '[]'::jsonb),
    'appeals', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('text', a.text, 'state', a.state,
                           'submitted_at', a.submitted_at, 'decided_at', a.decided_at) ORDER BY a.submitted_at)
                           FROM public.dating_appeals AS a WHERE a.user_id = v_user), '[]'::jsonb));
END;
$$;

-- Fix round 1 (C-1; S-4): the binding above holds only while no API role
-- can make or rewrite a job. Supabase's default privileges left the
-- service role able to INSERT, UPDATE and DELETE data_export_jobs (Spec
-- 3c granted it SELECT only). Every writer is a definer function owned by
-- the table's owner (request_my_export, claim_data_export,
-- export_finish_part, export_retry_part, fail_data_export,
-- export_restart_old_order_jobs, export_expire_stale,
-- prepare_account_deletion, purge_stale_personal_rows); get-export-url
-- only reads it, and the cron job only counts it. SELECT stays.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.data_export_jobs FROM service_role;


-- ---------------------------------------------------------------------
-- Re-created from their live bodies; only the lines marked
-- "-- Spec 2 W9" change.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_chat_header(p_m dating_matches, p_side text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_other constant uuid := CASE WHEN p_side = 'low' THEN p_m.user_high_id ELSE p_m.user_low_id END;
  v_mine constant timestamptz := CASE WHEN p_side = 'low' THEN p_m.low_swap_at ELSE p_m.high_swap_at END;
  v_theirs constant timestamptz := CASE WHEN p_side = 'low' THEN p_m.high_swap_at ELSE p_m.low_swap_at END;
  v_blocked constant boolean := private.dating_pair_blocked(p_m.user_low_id, p_m.user_high_id); -- Spec 2 W6c (fix round 1, M-5)
BEGIN
  RETURN pg_catalog.jsonb_build_object(
    'match_id', p_m.id,
    'display_name', (SELECT p.display_name FROM public.dating_profiles AS p WHERE p.user_id = v_other),
    'age', CASE WHEN v_other IS NULL THEN NULL ELSE public.account_age(v_other) END,
    'state', CASE WHEN p_m.state = 'active' AND v_other IS NOT NULL
                       AND NOT private.dating_pair_blocked(p_m.user_low_id, p_m.user_high_id) THEN 'active' ELSE 'ended' END, -- fix round 1 (M-5)
    'swap', pg_catalog.jsonb_build_object('mine', v_mine IS NOT NULL, 'theirs', v_theirs IS NOT NULL,
                                          'both', v_mine IS NOT NULL AND v_theirs IS NOT NULL,
                                          'from', p_m.matched_at + interval '72 hours'), -- Spec 2 W6c
    'we_met', CASE WHEN v_blocked THEN NULL ELSE pg_catalog.jsonb_build_object( -- Spec 2 W6c (fix round 1, M-5: none for a blocked pair)
      'mine', (CASE WHEN p_side = 'low' THEN p_m.low_we_met_at ELSE p_m.high_we_met_at END) IS NOT NULL, -- Spec 2 W6c
      'theirs', (CASE WHEN p_side = 'low' THEN p_m.high_we_met_at ELSE p_m.low_we_met_at END) IS NOT NULL) END, -- Spec 2 W6c
    'timebox', CASE WHEN p_m.state <> 'active' OR v_other IS NULL OR v_blocked THEN NULL -- Spec 2 W6c (§3.6; fix round 1, M-5)
                    WHEN now() >= p_m.matched_at + interval '21 days' -- Spec 2 W6c
                         AND p_m.low_we_met_at IS NULL AND p_m.high_we_met_at IS NULL -- Spec 2 W6c
                         AND (CASE WHEN p_side = 'low' THEN p_m.low_day21_at ELSE p_m.high_day21_at END) IS NULL THEN 'day21' -- Spec 2 W6c
                    WHEN now() >= p_m.matched_at + interval '7 days' AND now() < p_m.matched_at + interval '21 days' -- Spec 2 W6c
                         AND p_m.low_we_met_at IS NULL AND p_m.high_we_met_at IS NULL -- Spec 2 W6c (fix round 1, M-4)
                         AND (CASE WHEN p_side = 'low' THEN p_m.low_day7_at ELSE p_m.high_day7_at END) IS NULL THEN 'day7' -- Spec 2 W6c
               END, -- Spec 2 W6c; Spec 2 W9
    'link', private.dating_link_json(p_m, p_side)); -- Spec 2 W9 (§3.9): the couple link, as this side sees it
END;
$function$;

CREATE OR REPLACE FUNCTION public.export_relationship(p_user_id uuid, p_relationship_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_rel public.relationships;
  v_i_am_a boolean;
  v_out jsonb;
  v_start date;
BEGIN
  -- Only a relationship the person is in (re-review M6: callers are the
  -- worker's, but the ids are never trusted).
  SELECT * INTO v_rel FROM public.relationships
  WHERE id = p_relationship_id AND p_user_id IN (user_a, user_b);
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
  v_i_am_a := v_rel.user_a = p_user_id;
  v_start := least(v_rel.created_at::date, coalesce(v_rel.started_at, v_rel.created_at::date));

  v_out := jsonb_build_object(
    'status', v_rel.status,
    'started_on', v_rel.started_at,
    'ended_at', v_rel.ended_at,
    'partner_first_name', (
      SELECT CASE WHEN split_part(btrim(u.display_name), ' ', 1) ~ '^\+?[0-9 ()-]*$' THEN NULL
                  ELSE split_part(btrim(u.display_name), ' ', 1) END
      FROM public.users u
      WHERE u.id = CASE WHEN v_i_am_a THEN v_rel.user_b ELSE v_rel.user_a END),

    -- Chat is paged separately (export_chat_page): a long history must
    -- not be one statement or one in-memory value (plan review I7).
    'chat_messages', (SELECT count(*) FROM public.messages m
                      WHERE m.relationship_id = p_relationship_id AND NOT m.is_system_notice
                        AND coalesce(m.media_type, '') <> 'streak'),

    'places', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'from', public.export_who(p_user_id, pu.user_id), 'at', pu.created_at,
        'label', pu.label, 'note', pu.note, 'city', pu.city, 'country', pu.country,
        -- The partner's exact spots over time would be a location history of
        -- them: their pins keep only the place names (plan review I2).
        'latitude', CASE WHEN pu.user_id = p_user_id THEN pu.latitude END,
        'longitude', CASE WHEN pu.user_id = p_user_id THEN pu.longitude END) ORDER BY pu.created_at)
      FROM public.place_updates pu WHERE pu.relationship_id = p_relationship_id
    ), '[]'::jsonb),

    -- Planning: entries, blocks, items. Templates and deleted rows out;
    -- expenses as a flat per-entry list, no totals (D.2, D6).
    'planning', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'title', e.title, 'status', e.status, 'currency', e.currency,
        'created_by', public.export_who(p_user_id, e.created_by), 'created_at', e.created_at,
        'blocks', coalesce((
          SELECT jsonb_agg(jsonb_build_object(
            'type', b.block_type, 'text', b.plain_text,
            'date_start', b.date_start, 'date_end', b.date_end,
            'photos', CASE WHEN b.block_type = 'photo' THEN (
              SELECT jsonb_agg('media/' || public.export_file_name('planning', x.path))
              FROM jsonb_array_elements_text(coalesce(b.payload->'paths', '[]'::jsonb)) AS x(path)) END,
            'url', CASE WHEN b.block_type = 'link' THEN b.payload->>'url' END,
            'created_by', public.export_who(p_user_id, b.created_by),
            'items', coalesce((
              SELECT jsonb_agg(jsonb_build_object(
                'text', it.text, 'section', it.section, 'done', it.checked_at IS NOT NULL,
                'due', it.due_date, 'amount_minor', it.amount_minor, 'currency', it.currency,
                'paid_by', public.export_who(p_user_id, it.paid_by),
                'assigned_to', public.export_who(p_user_id, it.assigned_to),
                'date_start', it.date_start, 'date_end', it.date_end) ORDER BY it.sort_key)
              FROM public.planning_block_items it
              WHERE it.block_id = b.id AND it.deleted_at IS NULL), '[]'::jsonb)
          ) ORDER BY b.sort_key)
          FROM public.planning_blocks b
          WHERE b.entry_id = e.id AND b.deleted_at IS NULL), '[]'::jsonb)
      ) ORDER BY e.created_at)
      FROM public.planning_entries e
      WHERE e.relationship_id = p_relationship_id AND e.deleted_at IS NULL AND NOT e.is_template
    ), '[]'::jsonb),

    -- Calendar: exactly what the person sees (their private items, shared
    -- items, "Busy" for the partner's busy-only; never the partner's private).
    -- Events the person created or that were shared with them (D.2): never
    -- the partner's private or busy-only items (plan review I3). The whole
    -- relationship, not a window (D.3 #5).
    'calendar', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'kind', t.item_kind, 'id', 'c' || t.rank_id, 'date', t.item_date,
        'starts_at', t.starts_at, 'ends_at', t.ends_at, 'all_day', t.all_day,
        'title', t.title, 'visibility', t.visibility,
        'note', t.note, 'location', t.location,
        'recurring', t.recurring, 'continuation', t.continuation,
        'created_by', public.export_who(p_user_id, t.created_by)) ORDER BY t.item_date)
      FROM (
        SELECT ti.*,
               dense_rank() OVER (ORDER BY ti.item_kind, ti.item_id) AS rank_id,
               CASE WHEN ti.item_kind = 'event' THEN ce.note END AS note,
               CASE WHEN ti.item_kind = 'event' THEN ce.location_name END AS location,
               coalesce(ce.rrule IS NOT NULL OR ce.ritual_id IS NOT NULL, false) AS recurring,
               coalesce(NOT ti.all_day AND ti.starts_at IS NOT NULL
                 AND ti.item_date > (ti.starts_at AT TIME ZONE coalesce(ti.tz, 'UTC'))::date, false) AS continuation
        FROM public.together_items_for(p_user_id, p_relationship_id, v_start, current_date + 365) ti
        LEFT JOIN public.couple_events ce ON ti.item_kind = 'event' AND ce.id = ti.item_id
        WHERE ti.item_kind IN ('event', 'reminder', 'planning_date')
          AND NOT (ti.visibility = 'busy_only' AND ti.created_by IS DISTINCT FROM p_user_id)
      ) t
    ), '[]'::jsonb),

    'reminders', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'type', r.reminder_type, 'title', r.title, 'note', r.note,
        'remind_at', r.remind_at, 'recurrence', r.recurrence) ORDER BY r.remind_at)
      FROM public.reminders r WHERE r.relationship_id = p_relationship_id
    ), '[]'::jsonb),

    -- Spec 1 W5 (§4.3 W5): About us, its values and who changed each one
    -- ('me' or 'partner', never an id) and when.
    'about_us', (
      SELECT jsonb_build_object(
        'together_since', cp.together_since,
        'together_since_precision', cp.together_since_precision,
        'stage', cp.stage, 'stage_words', cp.stage_words,
        'ceremonies', cp.ceremonies, 'living', cp.living,
        'children', cp.children, 'child_age_bands', to_jsonb(cp.child_age_bands),
        'anniversary_source', cp.anniversary_source,
        'changes', coalesce((
          SELECT jsonb_agg(jsonb_build_object(
            'field', c.field, 'by', public.export_who(p_user_id, c.by), 'at', c.at) ORDER BY c.at, c.field)
          FROM (VALUES ('together_since', cp.together_since_changed_by, cp.together_since_changed_at),
                       ('stage', cp.stage_changed_by, cp.stage_changed_at),
                       ('ceremonies', cp.ceremonies_changed_by, cp.ceremonies_changed_at),
                       ('living', cp.living_changed_by, cp.living_changed_at),
                       ('children', cp.children_changed_by, cp.children_changed_at),
                       ('anniversary', cp.anniversary_changed_by, cp.anniversary_changed_at)) AS c(field, by, at)
          WHERE c.at IS NOT NULL), '[]'::jsonb))
      FROM public.couple_profiles cp WHERE cp.relationship_id = p_relationship_id),

    -- Spec 2 W9 (§3.9, I-13): the How we met card, each message as both saw it.
    'how_we_met', (SELECT jsonb_agg(jsonb_build_object( -- Spec 2 W9
        'from', public.export_who(p_user_id, (x.v->>'by')::uuid), 'kind', x.v->>'kind', -- Spec 2 W9
        'question', x.v->'question_id', -- Spec 2 W9 (final server fix, M-2): a guided answer keeps its question
        'text', x.v->>'text', 'at', x.v->'at') ORDER BY x.n) -- Spec 2 W9
      FROM public.couple_how_we_met h, jsonb_array_elements(h.items) WITH ORDINALITY AS x(v, n) -- Spec 2 W9
      WHERE h.relationship_id = p_relationship_id), -- Spec 2 W9
    'family', coalesce((
      SELECT jsonb_agg(jsonb_build_object('name', f.name, 'birthday', f.birthday) ORDER BY f.name)
      FROM public.couple_family_members f WHERE f.relationship_id = p_relationship_id
    ), '[]'::jsonb),

    'moments', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'type', t.event_type, 'title', t.title, 'note', t.note, 'on', t.occurred_at,
        'logged_by', public.export_who(p_user_id, t.logged_by),
        -- Spec 7 (B2; review I6): shared through "Share a win".
        'win', CASE WHEN t.is_win THEN true END) ORDER BY t.occurred_at)
      FROM public.timeline_events t
      WHERE t.relationship_id = p_relationship_id AND t.deleted_at IS NULL
        AND (t.visibility = 'shared' OR t.logged_by = p_user_id)
    ), '[]'::jsonb),

    -- The person's own stories only (the partner's are not exportable).
    'my_stories', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'type', s.media_type, 'on', s.occurred_on, 'at', s.created_at,
        'media_file', 'media/' || public.export_story_file_name(s.media_key, s.media_type),
        'place', (SELECT jsonb_build_object('label', sp.label, 'latitude', sp.lat, 'longitude', sp.lng)
                  FROM public.story_places sp WHERE sp.story_item_id = s.id)) ORDER BY s.created_at)
      FROM public.story_items s
      WHERE s.relationship_id = p_relationship_id AND s.author_id = p_user_id AND s.deleted_at IS NULL
    ), '[]'::jsonb),

    -- Shared Pulse history and verdicts (both already saw them); role-free.
    'pulse', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'week_ending', ps.week_ending, 'overall', ps.overall_score,
        'communication', ps.communication, 'connection', ps.connection,
        'conflict_health', ps.conflict_health, 'alignment', ps.alignment,
        'confidence', ps.data_confidence) ORDER BY ps.week_ending)
      FROM public.pulse_scores ps WHERE ps.relationship_id = p_relationship_id
    ), '[]'::jsonb),
    'verdicts', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'period_start', v.period_start, 'period_end', v.period_end,
        'headline', v.headline,
        'strengths', (SELECT jsonb_agg(jsonb_build_object('title', x->>'title', 'body', x->>'body'))
                      FROM jsonb_array_elements(coalesce(v.strengths, '[]'::jsonb)) x),
        'watch_areas', (SELECT jsonb_agg(jsonb_build_object('title', x->>'title', 'body', x->>'body'))
                        FROM jsonb_array_elements(coalesce(v.watch_areas, '[]'::jsonb)) x),
        'one_action', v.one_action, 'disclaimer', v.disclaimer) ORDER BY v.period_start)
      FROM public.verdicts v WHERE v.relationship_id = p_relationship_id AND v.status = 'published'
    ), '[]'::jsonb),

    -- Games: the person's own answers always; the partner's only once the
    -- round revealed them (both answered).
    'game_rounds', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'game', coalesce(gs.game_type, r.game_type, 'love_map'),
        'question', r.question_text_snapshot,
        'at', r.created_at,
        'my_answer', CASE WHEN v_i_am_a THEN r.answer_a ELSE r.answer_b END,
        'partner_answer', CASE WHEN r.both_answered THEN
                            CASE WHEN v_i_am_a THEN r.answer_b ELSE r.answer_a END END) ORDER BY r.created_at)
      FROM public.game_session_rounds r
      LEFT JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE coalesce(r.relationship_id, gs.relationship_id) = p_relationship_id
        AND (r.answer_a IS NOT NULL OR r.answer_b IS NOT NULL)
    ), '[]'::jsonb),
    'thirty_six_answers', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'question', r.question_text_snapshot,
        'from', public.export_who(p_user_id, a.user_id),
        'answer', a.answer_text, 'at', a.submitted_at) ORDER BY a.submitted_at)
      FROM public.thirty_six_question_answers a
      JOIN public.game_session_rounds r ON r.id = a.round_id
      JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE gs.relationship_id = p_relationship_id AND NOT coalesce(a.is_removed, false)
        AND (a.user_id = p_user_id OR r.both_answered)
    ), '[]'::jsonb),
    -- The person's own This-or-That picks (plan review M3).
    'this_or_that_picks', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'question', r.question_text_snapshot, 'picked', a.choice, 'at', r.created_at) ORDER BY r.created_at)
      FROM public.this_or_that_round_answers a
      JOIN public.game_session_rounds r ON r.id = a.round_id
      JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE gs.relationship_id = p_relationship_id AND a.user_id = p_user_id
    ), '[]'::jsonb),
    'love_map_truths', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'about', public.export_who(p_user_id, t.subject_id), 'truth', t.truth_text))
      FROM public.mirror_round_truth t
      JOIN public.game_session_rounds r ON r.id = t.round_id
      LEFT JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE coalesce(r.relationship_id, gs.relationship_id) = p_relationship_id
        AND (t.subject_id = p_user_id OR r.both_answered)
    ), '[]'::jsonb)
  );
  RETURN v_out;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_home()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
  v_enrol public.dating_enrollments;
  v_opens timestamptz;
  v_after timestamptz;
  v_err text;
  v_undated boolean; -- Spec 2 W3a (fix round 1, M-2, M-4)
  v_cand text; -- Spec 2 W3a
  v_has jsonb; -- Spec 2 W3a (C-2)
  v_trip jsonb; -- Spec 2 W8b (fix round 2, Re-M-1): the trip, read once
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_has := jsonb_build_object('has_data', private.dating_has_data(v_user)) -- Spec 2 W7a: and an accepted appeal (§3.7), only when there is one
           || CASE WHEN private.dating_appeal_accepted(v_user) THEN jsonb_build_object('appeal_accepted', true) ELSE '{}'::jsonb END -- Spec 2 W7a; Spec 2 W9
           || CASE WHEN public.dating_flag_enabled('dating_couple_link') IS TRUE THEN jsonb_build_object('couple_link', true) ELSE '{}'::jsonb END; -- Spec 2 W9 (R-W9-16)
  v_reason := public.dating_eligibility(v_user, 'setup');
  SELECT p.country_code::text, p.region_code INTO v_country, v_region
    FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN
    IF public.dating_require_trusted_device() IS NOT TRUE THEN -- Spec 2 W4b (fix round 1, M-4): nothing about the person to another phone
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable'); -- Spec 2 W4b
    END IF; -- Spec 2 W4b
    v_country := coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))); -- Spec 2 W3a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a (R-4, R-5)
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'reverify_device', -- Spec 2 W3a (C-2); Spec 2 W4b
      'variant', private.dating_reverify_variant(v_user)); -- Spec 2 W4b (§3.3.4): setup_restart or verified
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'account_unavailable' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', private.dating_unavailable_state(v_user)); -- Spec 2 W3a (C-2)
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'country_closed' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'country_closed', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'region_closed' THEN
    v_config := public.dating_country_config(v_country);
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'region_closed', 'country', v_country, 'region', v_region, -- Spec 2 W3a (C-2)
      'open_regions', to_jsonb(coalesce(v_config.open_regions, ARRAY[]::text[])), -- Spec 2 W3a
      'notify', private.dating_notice_state(v_user, v_country, v_region)); -- Spec 2 W3a
  END IF;
  SELECT * INTO v_enrol FROM public.dating_enrollments AS e WHERE e.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || CASE WHEN v_enrol.state = 'paused' -- Spec 2 W3a (C-2)
                THEN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (fix round 1, M-3)
                                        'can_resume', false) -- Spec 2 W3a (T4 fix round 1, I-2): a shared space is open now
                     || private.dating_check_standing(v_user, v_enrol.pause_reason) -- Spec 2 W4b (T3 M-4): where the check stands
                     || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a
                             ELSE '{}'::jsonb END -- Spec 2 W3a
                     || private.dating_trip_json(v_user) -- Spec 2 W8 final server fix (M-1): the reads hide on a trip while paused too
                ELSE jsonb_build_object('state', 'unavailable') END;
  END IF;
  IF v_reason IS DISTINCT FROM 'eligible' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'suspended' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- suspended without a live restriction (W7a routes it) -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'paused' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (C-2)
      'can_resume', coalesce(v_enrol.pause_reason IS DISTINCT FROM 'verification' OR public.dating_age_gate_holds(v_user), false)) -- Spec 2 W4a (fix round 1, M-2): a verification pause resumes once the check holds; W3a (T4 fix round 1, I-2): no shared space holds it
      || private.dating_check_standing(v_user, v_enrol.pause_reason) -- Spec 2 W4b (T3 M-4): where the check stands
      || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a (the §2.4 note)
              ELSE '{}'::jsonb END -- Spec 2 W3a
      || private.dating_trip_json(v_user); -- Spec 2 W8 final server fix (M-1): the reads hide on a trip while paused too
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);
  v_undated := EXISTS (SELECT 1 FROM public.relationships AS r -- Spec 2 W3a (fix round 1, M-2, M-4): an ending with no date
                       WHERE v_user IN (r.user_a, r.user_b) AND r.status = 'ended' AND r.ended_at IS NULL); -- Spec 2 W3a
  IF v_enrol.state = 'active' THEN
    -- Spec 2 W3a (fix round 1, M-2): read here, so a home read never
    -- Spec 2 W3a reaches the candidate check's undated-ending counter.
    IF v_undated THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (M-2)
    END IF; -- Spec 2 W3a (M-2)
    -- Spec 2 W3a (W2 carry): never "you're live" while the candidate check
    -- Spec 2 W3a refuses for anything but the wait (an undated ending, a
    -- Spec 2 W3a path off Dating); the wait itself is the cool-off below.
    v_cand := public.dating_eligibility(v_user, 'candidate'); -- Spec 2 W3a
    v_trip := private.dating_trip_json(v_user); -- Spec 2 W8b (fix round 2, Re-M-1): read once
    IF v_cand IS NOT DISTINCT FROM 'away' OR v_trip -> 'trip' ->> 'kind' IS NOT DISTINCT FROM 'away' THEN -- Spec 2 W8b (§2.1 gate 7, §3.1, §3.11; fix round 1, I-1: in the gentle wait too)
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'away') -- Spec 2 W8b
             || v_trip; -- Spec 2 W8b
    END IF; -- Spec 2 W8b
    IF v_cand IS DISTINCT FROM 'eligible' AND v_cand IS DISTINCT FROM 'gentle_wait' THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a
    END IF; -- Spec 2 W3a
    -- The first drop is the later of the open date and the 72 h cool-off
    -- from account creation (§2.1, §2.8).
    v_after := greatest(coalesce(v_opens, '-infinity'::timestamptz),
                        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours');
    IF v_after > now() THEN
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'cool_off', 'first_drop_at', private.dating_first_drop_at(v_user, v_after)) -- Spec 2 W3a (C-2); Spec 2 W8b
             || v_trip; -- Spec 2 W8b (§3.11): a same-gender trip
    END IF;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'active') -- Spec 2 W3a (C-2); Spec 2 W8b
           || v_trip; -- Spec 2 W8b (§3.11): a same-gender trip
  END IF;
  IF v_opens IS NOT NULL THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'gentle_wait', 'ended_at', (v_opens AT TIME ZONE 'UTC' - interval '30 days') AT TIME ZONE 'UTC', 'opens_at', v_opens, -- in UTC (a DST change moves nothing) -- Spec 2 W3a (C-2)
                              'next_step', private.dating_next_step(v_user), -- Spec 2 W3a
                              'can_shorten', coalesce(private.dating_gentle_wait_can_shorten(v_user), false), -- Spec 2 W3a (carry 8)
                              'first_drop_at', private.dating_first_drop_at(v_user, greatest(v_opens, now(), -- Spec 2 W3a
                                (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours'))); -- Spec 2 W3a
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'how' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'not_started', -- Spec 2 W3a (D1 line 6)
      'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (fix round 1, M-4): no date to promise
        ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END); -- Spec 2 W3a
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'verify' -- Spec 2 W4a (§3.1): a person or the ID vendor is checking
     AND EXISTS (SELECT 1 FROM public.dating_verification_sessions AS vs -- Spec 2 W4a
                  WHERE vs.user_id = v_user AND vs.kind = 'activation' AND vs.state = 'awaiting_review') THEN -- Spec 2 W4a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'verifying', 'next_step', 'verify'); -- Spec 2 W4a
  END IF; -- Spec 2 W4a
  RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user), -- Spec 2 W3a (C-2)
    'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (D13; fix round 1, M-4)
      ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
      (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END) -- Spec 2 W3a; Spec 2 W8b
    || private.dating_icon_offer_json(v_user); -- Spec 2 W8b (§3.2 D13, A-11): the plain-icon offer in Tier 1/2
EXCEPTION WHEN raise_exception THEN
  -- An unreadable field or a missing field key is no state the person can
  -- act on: the neutral 'unavailable', never a raw error. Anything else raises.
  -- Every re-creation keeps this handler (W4, W5, W7, W8 add decrypting
  -- readers; nothing in v1's call graph decrypts yet). Counted best-effort.
  v_err := SQLERRM;
  IF v_err IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    BEGIN
      PERFORM private.bump_metric_internal(CASE WHEN v_err = 'dating:field_key_missing'
                                                THEN 'dating.field_key.missing' ELSE 'dating.home.unreadable_field' END);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (C-2)
  END IF;
  RAISE;
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
    DELETE FROM public.couple_how_we_met WHERE relationship_id = v_rel.id; -- Spec 2 W9 (final server fix, I-1): the departed person's copied messages go
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
-- Self-revoke (the W6 final pattern); the twin grants.
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE
  public.dating_couple_link_requests,
  public.couple_how_we_met,
  public.dating_link_origins,
  public.dating_export_reads
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  private.dating_link_on(),
  private.dating_link_blocked(uuid),
  private.dating_link_json(public.dating_matches, text),
  public.get_dating_couple_link(uuid, boolean),
  public.request_dating_couple_link(text, uuid, boolean, boolean),
  public.decline_dating_couple_link(uuid),
  public.cancel_dating_couple_link(uuid),
  public.confirm_dating_couple_link(text, uuid, boolean, boolean),
  public.get_dating_link_origin(uuid),
  public.get_how_we_met(uuid),
  public.get_dating_post_link_offer(),
  public.dismiss_dating_post_link_offer(text),
  public.dating_export_for_job(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

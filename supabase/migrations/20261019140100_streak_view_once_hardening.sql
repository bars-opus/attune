-- View-once streak hardening (chat W4 Task 5b; reviews task-5 I-1, I-2,
-- M-1, M-3, M-4 and task-4 Issue 2).
--
-- The rule: a streak is seen once (or N times, per the sender's budget),
-- inside a 30-minute replay window that opens at the first view, and is
-- gone after. 20261019140000 enforced that on the clip READ; this makes it
-- hold everywhere else the bytes or the budget can be reached:
--
--   1. Storage. message_media_select_relationship_members let any member
--      sign any key referenced by a message in an open chat, and a streak's
--      key sits in messages.media_url (selected on every message read, so
--      it is in every client cache). A member holding the key could sign an
--      expired streak indefinitely with a raw API call. The policy now
--      signs a streak's key only while the streak is viewable for the
--      caller: the sender until the recipient opens it; the recipient while
--      plays are left and inside the window.
--   2. Abandoned streaks. Nothing destroyed a streak the recipient watched
--      once and never reopened: clip rows, the storage object and the key
--      all lived until the message or chapter was deleted. A pg_cron sweep
--      destroys every streak past its window every 10 minutes.
--   3. streak_clips_for_viewing requires a live streak: a non-streak id is
--      "Streak unavailable" (it used to run the destroy step, i.e. a write,
--      on any message addressed to the caller), a deleted streak is empty.
--      expire_streak_clips touches messages only when it changes something.
--   4. Idempotent spend. mark_streak_viewed decremented on every call, so
--      the client could not retry a lost response, and spending had to wait
--      for the viewer to EXIT (app killed / quick exit / PIN lock = view
--      never spent). mark_streak_viewed(p_message_id, p_open_id) records
--      each (message, viewer, open) it charged and answers a repeat with
--      the stored count. The client now spends the moment the first clip is
--      presented and may retry with the same open id. The 1-arg form stays
--      for older clients: it is the same spend with a fresh open id.
--   6. The first READ opens the window (review I-1). Only the spend set
--      viewed_at, so a recipient who fetched the clips and never spent
--      (raw API calls) could replay an unopened streak forever, and the
--      sweep never saw it. streak_clips_for_viewing stamps
--      messages.first_read_at on the recipient's first read of an
--      attached streak; the window runs from
--      LEAST(viewed_at, first_read_at) — strictly the earlier of the two,
--      so a spend at T+29 cannot push a window opened by a read at T past
--      T+30 (LEAST ignores a NULL side) — in the read RPC, the table read
--      policy, the storage policy, the spend RPC and the sweep. viewed_at
--      stays the honest "Opened" receipt (set at presentation). The
--      column is server-only: no client privilege. Policies reach it
--      through public.streak_replay_open (they run as the caller, who
--      cannot select it).
--      The recipient may SIGN only once the window has started
--      (first_read_at or viewed_at set): a client that never calls the
--      read RPC (key taken from messages.media_url, signed directly)
--      cannot sign an unopened streak. The honest client reads, then
--      signs, then plays; the RPC is VOLATILE, so its stamp commits with
--      the call. OWNER FLAG: clients older than the Task 5 read RPC sign
--      without calling it and lose streak playback until updated.
--   7. A tap before the sender's clip row lands (the message is inserted
--      first, the clip attached after) is free: the spend answers the
--      budget without charging, recording or opening (review M-1).
--   5. One window boundary everywhere: viewable while
--      viewed_at > now() - 30 minutes (strictly inside). At exactly 30:00
--      the streak is expired. The RPCs used `<` (still serving at 30:00),
--      the RLS `>`, the Dart util `>= 30 min` -> 0. Now: RPCs `<=` expire,
--      RLS / storage `>` viewable, Dart unchanged.
--
-- Destroying streak media: the queue entry carries not_before = now() + 10
-- minutes, the signed-URL TTL the client uses (600 s,
-- SupabaseChatRepository._signedUrlTtl). The spend now lands while the
-- clip is still PLAYING (at presentation, not exit), so the last view's
-- destroy step runs mid-playback; a drain inside that window would pull
-- the object out from under a video still streaming by range requests.
-- The grace costs no privacy: once the budget or window is gone the key is
-- unsignable (item 1), and a URL already signed was valid that long anyway.
--
-- Never DELETE FROM storage.objects (hosted refuses it): media goes
-- through public.media_deletion_queue, drained via the Storage API.
--
-- Grants live in 20261019140110_streak_view_once_hardening_grants.sql.

-- ── 6. The read anchor ──────────────────────────────────────────────────
-- Server-only: no grant (authenticated holds column-level privileges on
-- messages only, so a new column is invisible to it; read_receipt
-- contracts pin the SELECT allowlist).
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS first_read_at timestamptz;
COMMENT ON COLUMN public.messages.first_read_at IS
  'Streaks: when the recipient first fetched the clips (streak_clips_for_viewing). Anchors the 30-minute replay window with viewed_at. Server-only.';

-- The recipient's rule, for policies (which run as the caller and cannot
-- read first_read_at): plays left, and inside the window. Membership is
-- re-checked so an id from another couple answers false.
CREATE OR REPLACE FUNCTION public.streak_replay_open(p_message_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.messages m
    JOIN public.relationships r ON r.id = m.relationship_id
    WHERE m.id = p_message_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND COALESCE(m.streak_views_remaining, 0) > 0
      AND (LEAST(m.viewed_at, m.first_read_at) IS NULL
           OR LEAST(m.viewed_at, m.first_read_at) > now() - interval '30 minutes')
  );
$$;

-- Storage signing for the recipient: the same rule, and the window must
-- already have started (the gated read stamped it, or a spend did).
CREATE OR REPLACE FUNCTION public.streak_recipient_may_sign(p_message_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.streak_replay_open(p_message_id)
     AND EXISTS (
       SELECT 1 FROM public.messages m
       WHERE m.id = p_message_id
         AND LEAST(m.viewed_at, m.first_read_at) IS NOT NULL
     );
$$;

-- ── 4. Spend ledger ─────────────────────────────────────────────────────
-- One row per open the server charged. Internal bookkeeping: RLS on with
-- no policies, and no client privileges (grants file), so only the
-- SECURITY DEFINER spend reaches it. Rows go with their message.
CREATE TABLE IF NOT EXISTS public.streak_view_spends (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  viewer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  open_id uuid NOT NULL,
  remaining integer NOT NULL,
  spent_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, viewer_id, open_id)
);
ALTER TABLE public.streak_view_spends ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.streak_view_spends IS
  'Idempotency ledger for mark_streak_viewed(uuid, uuid): one row per viewer open that was charged. Server-only.';

-- ── 3 (+ grace). The shared destroy step ────────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_streak_clips(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Queued first, with the grace: the BEFORE DELETE trigger on
  -- streak_clips (streak_clips_queue_media_before_delete) then hits
  -- ON CONFLICT DO NOTHING instead of queueing it for the next drain.
  INSERT INTO public.media_deletion_queue (bucket_id, object_name, not_before)
  SELECT DISTINCT 'message-media', c.media_url, now() + interval '10 minutes'
  FROM public.streak_clips c
  WHERE c.message_id = p_message_id
    AND c.media_url IS NOT NULL AND c.media_url <> ''
  ON CONFLICT (bucket_id, object_name) DO NOTHING;

  DELETE FROM public.streak_clips c WHERE c.message_id = p_message_id;

  -- Only when it changes something: every UPDATE bumps updated_at (sync
  -- cursor + realtime) on both phones.
  UPDATE public.messages m SET streak_views_remaining = 0
  WHERE m.id = p_message_id AND m.streak_views_remaining <> 0;
END;
$$;

-- ── 3 + 5. The gated clip read ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_msg public.messages%ROWTYPE;
  v_member boolean := false;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_msg FROM public.messages m WHERE m.id = p_message_id;
  IF FOUND THEN
    SELECT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_msg.relationship_id
        AND (r.user_a = v_user OR r.user_b = v_user)
        AND public.relationship_chat_open_for(r.id, v_user)
    ) INTO v_member;
  END IF;
  -- Same answer for "someone else's", "does not exist" and "not a streak":
  -- no oracle, and no write reachable through a non-streak id.
  IF NOT v_member OR v_msg.media_type IS DISTINCT FROM 'streak' THEN
    RAISE EXCEPTION 'Streak unavailable';
  END IF;

  -- Deleted for everyone: delete_message already queued the media.
  IF v_msg.deleted_at IS NOT NULL THEN RETURN; END IF;

  IF v_msg.sender_id = v_user THEN
    IF v_msg.viewed_at IS NOT NULL THEN RETURN; END IF;
  ELSE
    IF COALESCE(v_msg.streak_views_remaining, 0) <= 0 THEN RETURN; END IF;
    -- Viewable strictly inside the window: at exactly 30:00 it is gone.
    -- The window runs from the first read or the first view, whichever
    -- exists (viewed_at once spent).
    IF LEAST(v_msg.viewed_at, v_msg.first_read_at)
       <= now() - interval '30 minutes' THEN
      PERFORM public.expire_streak_clips(p_message_id);
      RETURN;
    END IF;
    -- This read opens the window (once; only when there is something to
    -- see). The budget is untouched: spending stays at presentation.
    UPDATE public.messages m SET first_read_at = now()
    WHERE m.id = p_message_id
      AND m.first_read_at IS NULL
      AND EXISTS (SELECT 1 FROM public.streak_clips c
                  WHERE c.message_id = p_message_id);
  END IF;

  RETURN QUERY
    SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
    FROM public.streak_clips c
    WHERE c.message_id = p_message_id
    ORDER BY c.clip_index;
END;
$$;

-- ── 4 + 5. The idempotent spend ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_streak_viewed(p_message_id uuid, p_open_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_msg public.messages%ROWTYPE;
  v_left integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_open_id IS NULL THEN
    RAISE EXCEPTION 'Open id required';
  END IF;

  -- Membership as before (a member of the relationship). Not a streak is
  -- the same answer as not yours: no oracle, and no budget/viewed_at write
  -- on an ordinary message.
  IF NOT EXISTS (
    SELECT 1 FROM public.messages m
    JOIN public.relationships r ON r.id = m.relationship_id
    WHERE m.id = p_message_id
      AND m.media_type = 'streak'
      AND (r.user_a = v_user OR r.user_b = v_user)
  ) THEN
    RAISE EXCEPTION 'Streak unavailable';
  END IF;

  -- Serialises concurrent spends of one streak (a retry racing its own
  -- original, two devices): the ledger check below then sees the winner.
  SELECT * INTO v_msg FROM public.messages m WHERE m.id = p_message_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Streak unavailable';  -- deleted in between
  END IF;

  IF v_msg.sender_id = v_user THEN
    IF v_msg.viewed_at IS NOT NULL THEN
      RAISE EXCEPTION 'Streak already opened';
    END IF;
    -- In flight: the sender's replay spends nothing and marks nothing.
    RETURN v_msg.streak_views_remaining;
  END IF;

  -- Recipient. A repeat of a charged open answers what it answered.
  SELECT s.remaining INTO v_left
  FROM public.streak_view_spends s
  WHERE s.message_id = p_message_id
    AND s.viewer_id = v_user
    AND s.open_id = p_open_id;
  IF FOUND THEN
    RETURN v_left;
  END IF;

  IF v_msg.deleted_at IS NOT NULL THEN
    -- Deleted for everyone: nothing left to see, nothing to charge.
    RETURN 0;
  END IF;

  -- Not attached yet (the sender's clip row lands after the message):
  -- nothing can have been seen, so nothing is charged, recorded or opened.
  -- Clip rows are only ever removed once the budget is 0, so an opened or
  -- spent streak never takes this branch.
  IF v_msg.viewed_at IS NULL AND NOT EXISTS (
    SELECT 1 FROM public.streak_clips c WHERE c.message_id = p_message_id
  ) THEN
    RETURN COALESCE(v_msg.streak_views_remaining, 0);
  END IF;

  IF LEAST(v_msg.viewed_at, v_msg.first_read_at)
     <= now() - interval '30 minutes' THEN
    -- Past the window (strictly-inside convention) even with plays left.
    PERFORM public.expire_streak_clips(p_message_id);
    v_left := 0;
  ELSE
    -- One UPDATE: the window opens on the FIRST view, and GREATEST floors
    -- the budget so a spent streak cannot go negative.
    UPDATE public.messages m
       SET streak_views_remaining =
             GREATEST(COALESCE(m.streak_views_remaining, 0) - 1, 0),
           viewed_at = COALESCE(m.viewed_at, now())
     WHERE m.id = p_message_id
     RETURNING m.streak_views_remaining INTO v_left;

    IF v_left = 0 THEN
      PERFORM public.expire_streak_clips(p_message_id);
    END IF;
  END IF;

  INSERT INTO public.streak_view_spends (message_id, viewer_id, open_id, remaining)
  VALUES (p_message_id, v_user, p_open_id, v_left)
  ON CONFLICT (message_id, viewer_id, open_id) DO NOTHING;

  RETURN v_left;
END;
$$;

-- Older clients call the 1-arg form once per viewing, at exit. Same rules,
-- same spend, a fresh open each call (so exactly the old "decrement on
-- every call" behaviour, now through one implementation).
CREATE OR REPLACE FUNCTION public.mark_streak_viewed(p_message_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.mark_streak_viewed(p_message_id, pg_catalog.gen_random_uuid());
END;
$$;

-- ── 1 + 5. Storage signing follows the same rule ────────────────────────
-- The live definition (20261018100200) plus one clause for streaks. The
-- sender branch is strict here (unlike streak_clips' table policy, storage
-- has no upsert that needs SELECT on an opened row).
DROP POLICY IF EXISTS message_media_select_relationship_members ON storage.objects;
CREATE POLICY message_media_select_relationship_members ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'message-media'
    AND EXISTS (
      SELECT 1 FROM public.messages m
      WHERE (m.media_url = objects.name OR m.media_thumbnail_url = objects.name)
        AND public.relationship_chat_open(m.relationship_id)
        AND (
          m.media_type IS DISTINCT FROM 'streak'
          OR CASE
               WHEN m.sender_id = auth.uid() THEN m.viewed_at IS NULL
               ELSE public.streak_recipient_may_sign(m.id)
             END
        )
    )
  );

-- The table read policy (20261019140000) with the same anchor for the
-- recipient. The sender branch stays `true` (the attach upsert's conflict
-- check needs SELECT on the opened row; see 140000).
DROP POLICY IF EXISTS streak_clips_members_read ON public.streak_clips;
CREATE POLICY streak_clips_members_read ON public.streak_clips
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = streak_clips.message_id
        AND public.relationship_chat_open(m.relationship_id)
        AND CASE
              WHEN m.sender_id = auth.uid() THEN true
              ELSE public.streak_replay_open(m.id)
            END
    )
  );

-- ── 2. The abandoned-streak sweep ───────────────────────────────────────
-- Every streak with plays left whose window has closed (anchored on the
-- first view, else the first read). Not limited to
-- rows that still have clips: zeroing the budget is the correct state
-- regardless, it takes the row out of the partial index below for good,
-- and so each run's scan stays proportional to newly abandoned streaks.
-- Bounded per run; the next run picks up any remainder.
--
-- Earlier drafts of this migration created the sweep's index under other
-- names (on viewed_at, then on COALESCE(viewed_at, first_read_at)). Hosted
-- never ran a draft; a dev database that did must not keep a stale second
-- index maintained on every messages write.
DROP INDEX IF EXISTS public.messages_streak_open_window_idx;
DROP INDEX IF EXISTS public.messages_streak_window_anchor_idx;
CREATE INDEX IF NOT EXISTS messages_streak_first_anchor_idx
  ON public.messages ((LEAST(viewed_at, first_read_at)))
  WHERE media_type = 'streak' AND streak_views_remaining > 0;

CREATE OR REPLACE FUNCTION public.sweep_abandoned_streaks()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
  v_n integer := 0;
BEGIN
  FOR v_id IN
    SELECT m.id FROM public.messages m
    WHERE m.media_type = 'streak'
      AND m.streak_views_remaining > 0
      AND LEAST(m.viewed_at, m.first_read_at) <= now() - interval '30 minutes'
    ORDER BY LEAST(m.viewed_at, m.first_read_at)
    LIMIT 500
  LOOP
    PERFORM public.expire_streak_clips(v_id);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- Idempotent and guarded like 20261019120100: unschedule by name first,
-- and a database without pg_cron applies the migration cleanly.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron not installed; sweep-abandoned-streaks not scheduled here';
    RETURN;
  END IF;

  PERFORM cron.unschedule(jobid) FROM cron.job
  WHERE jobname = 'sweep-abandoned-streaks';

  PERFORM cron.schedule(
    'sweep-abandoned-streaks',
    '*/10 * * * *',
    'SELECT public.sweep_abandoned_streaks();'
  );
END $$;

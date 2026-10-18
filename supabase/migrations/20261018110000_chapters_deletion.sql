-- Spec 3b (research 06 §3 F13 (2), F1 (7); 05 D.2, D.3 #1): deletion is
-- deletion. Account deletion removes the person's own data, the shared-answer
-- data of every relationship they were in, and queues their media; an
-- archived relationship is hard-deleted 12 months after archive unless on
-- legal hold. Storage objects are always queued before the rows naming them
-- go. Plan: docs/superpowers/plans/2026-10-18-spec3b-chapters-deletion.md.

-- ---------------------------------------------------------------------
-- 1. User FKs that blocked auth.admin.deleteUser (NO ACTION).
-- ---------------------------------------------------------------------
ALTER TABLE public.game_session_rounds DROP CONSTRAINT IF EXISTS game_session_rounds_active_partner_id_fkey;
ALTER TABLE public.game_session_rounds ADD CONSTRAINT game_session_rounds_active_partner_id_fkey
  FOREIGN KEY (active_partner_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.game_sessions DROP CONSTRAINT IF EXISTS game_sessions_current_turn_user_id_fkey;
ALTER TABLE public.game_sessions ADD CONSTRAINT game_sessions_current_turn_user_id_fkey
  FOREIGN KEY (current_turn_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.game_sessions DROP CONSTRAINT IF EXISTS game_sessions_winner_user_id_fkey;
ALTER TABLE public.game_sessions ADD CONSTRAINT game_sessions_winner_user_id_fkey
  FOREIGN KEY (winner_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
-- NOT NULL columns: a vote and a poll are the person's own.
ALTER TABLE public.poll_votes DROP CONSTRAINT IF EXISTS poll_votes_user_id_fkey;
ALTER TABLE public.poll_votes ADD CONSTRAINT poll_votes_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.post_polls DROP CONSTRAINT IF EXISTS post_polls_created_by_fkey;
ALTER TABLE public.post_polls ADD CONSTRAINT post_polls_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ---------------------------------------------------------------------
-- 2. R3b-2: insights and translator logs are the person's own; they outlive
--    the relationship's deletion, unattached (the client only ever shows the
--    active or open relationship's rows).
-- ---------------------------------------------------------------------
ALTER TABLE public.personal_insights ALTER COLUMN relationship_id DROP NOT NULL;
ALTER TABLE public.personal_insights DROP CONSTRAINT IF EXISTS personal_insights_relationship_id_fkey;
ALTER TABLE public.personal_insights ADD CONSTRAINT personal_insights_relationship_id_fkey
  FOREIGN KEY (relationship_id) REFERENCES public.relationships(id) ON DELETE SET NULL;
ALTER TABLE public.translator_logs ALTER COLUMN relationship_id DROP NOT NULL;
ALTER TABLE public.translator_logs DROP CONSTRAINT IF EXISTS translator_logs_relationship_id_fkey;
ALTER TABLE public.translator_logs ADD CONSTRAINT translator_logs_relationship_id_fkey
  FOREIGN KEY (relationship_id) REFERENCES public.relationships(id) ON DELETE SET NULL;

-- Final review I-3: the person's own weekly check-ins and private Pulse
-- score are private and theirs (D.2): kept, unattached, after the purge.
ALTER TABLE public.weekly_checkins ALTER COLUMN relationship_id DROP NOT NULL;
ALTER TABLE public.weekly_checkins DROP CONSTRAINT IF EXISTS weekly_checkins_relationship_id_fkey;
ALTER TABLE public.weekly_checkins ADD CONSTRAINT weekly_checkins_relationship_id_fkey
  FOREIGN KEY (relationship_id) REFERENCES public.relationships(id) ON DELETE SET NULL;
ALTER TABLE public.pulse_private_scores ALTER COLUMN relationship_id DROP NOT NULL;
ALTER TABLE public.pulse_private_scores DROP CONSTRAINT IF EXISTS pulse_private_scores_relationship_id_fkey;
ALTER TABLE public.pulse_private_scores ADD CONSTRAINT pulse_private_scores_relationship_id_fkey
  FOREIGN KEY (relationship_id) REFERENCES public.relationships(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------
-- 3. Legal hold (F1 (7)). Written only by the service role (grants file).
-- ---------------------------------------------------------------------
ALTER TABLE public.relationships
  ADD COLUMN IF NOT EXISTS legal_hold boolean NOT NULL DEFAULT false;

-- Final review I-1: the inviter's own pending row cannot set the server's
-- columns (legal hold, an archive or an ender). Restated from 20261017110000.
DROP POLICY IF EXISTS "relationship inviter insert" ON public.relationships;
CREATE POLICY "relationship inviter insert" ON public.relationships
  FOR INSERT TO authenticated
  WITH CHECK (
    user_a = auth.uid() AND user_b IS NULL AND status = 'pending'
    AND NOT legal_hold
    AND chat_archived_at IS NULL AND chat_archived_reason IS NULL
    AND ended_at IS NULL AND ended_by IS NULL AND paused_at IS NULL AND paused_by IS NULL
  );

-- ---------------------------------------------------------------------
-- 4. R3b-5: media is queued before the row that names it is deleted.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.messages_queue_media_before_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.queue_media_deletion('message-media', OLD.media_url);
  PERFORM public.queue_media_deletion('message-media', OLD.media_thumbnail_url);
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS messages_queue_media_before_delete ON public.messages;
CREATE TRIGGER messages_queue_media_before_delete
  BEFORE DELETE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_queue_media_before_delete();

CREATE OR REPLACE FUNCTION public.streak_clips_queue_media_before_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.queue_media_deletion('message-media', OLD.media_url);
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS streak_clips_queue_media_before_delete ON public.streak_clips;
CREATE TRIGGER streak_clips_queue_media_before_delete
  BEFORE DELETE ON public.streak_clips
  FOR EACH ROW EXECUTE FUNCTION public.streak_clips_queue_media_before_delete();

CREATE OR REPLACE FUNCTION public.dating_photos_queue_media_before_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.queue_media_deletion('dating-profile-photos', OLD.storage_key);
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS dating_photos_queue_media_before_delete ON public.dating_profile_photos;
CREATE TRIGGER dating_photos_queue_media_before_delete
  BEFORE DELETE ON public.dating_profile_photos
  FOR EACH ROW EXECUTE FUNCTION public.dating_photos_queue_media_before_delete();

CREATE OR REPLACE FUNCTION public.relationships_queue_media_before_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.queue_media_deletion('relationship-avatars', OLD.chat_avatar_url);
  PERFORM public.queue_media_deletion('relationship-avatars', OLD.chat_avatar_thumbnail_url);
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS relationships_queue_media_before_delete ON public.relationships;
CREATE TRIGGER relationships_queue_media_before_delete
  BEFORE DELETE ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.relationships_queue_media_before_delete();

-- Everything stored under the relationship's own path prefix, including
-- objects no row names any more.
CREATE OR REPLACE FUNCTION public.relationship_queue_storage(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_obj record;
BEGIN
  FOR v_obj IN
    SELECT o.bucket_id, o.name FROM storage.objects o
    WHERE (o.bucket_id = 'planning-media' AND o.name LIKE p_relationship_id::text || '/%')
       OR (o.bucket_id = 'story-media' AND o.name LIKE 'story-media/' || p_relationship_id::text || '/%')
       OR (o.bucket_id = 'relationship-avatars'
           AND o.name LIKE 'relationship-avatars/' || p_relationship_id::text || '/%')
  LOOP
    PERFORM public.queue_media_deletion(v_obj.bucket_id, v_obj.name);
  END LOOP;
  -- Uploads for this relationship that no row names (review I5).
  PERFORM public.queue_media_deletion('message-media', i.storage_key)
  FROM public.message_media_upload_intents i WHERE i.relationship_id = p_relationship_id;
  PERFORM public.queue_media_deletion('story-media', i.storage_key)
  FROM public.story_media_upload_intents i WHERE i.relationship_id = p_relationship_id;
  PERFORM public.queue_media_deletion('relationship-avatars', i.storage_key)
  FROM public.relationship_avatar_upload_intents i WHERE i.relationship_id = p_relationship_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. The 12-month purge (F1 (7)).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_relationship(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.relationship_queue_storage(p_relationship_id);
  -- Cascades to every relationship-keyed table; the triggers above and the
  -- story trigger queue the media rows name. Survivors by FK: anonymised
  -- safety events, dating exclusions, Healing journeys and snapshots,
  -- personal insights and translator logs (unattached).
  DELETE FROM public.relationships WHERE id = p_relationship_id AND NOT legal_hold;
END;
$$;

CREATE OR REPLACE FUNCTION public.purge_archived_relationships()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_id uuid;
  v_n integer := 0;
BEGIN
  FOR v_id IN
    SELECT r.id FROM public.relationships r
    WHERE NOT r.legal_hold
      AND (
        (r.status = 'archived' AND r.chat_archived_at <= now() - interval '12 months')
        -- Both accounts deleted: nobody is left to read or export it.
        OR (r.user_a IS NULL AND r.user_b IS NULL)
      )
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM public.purge_relationship(v_id);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

DO $$
BEGIN
  PERFORM cron.unschedule('purge_archived_relationships')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge_archived_relationships');
END $$;
SELECT cron.schedule(
  'purge_archived_relationships', '41 3 * * *',
  $$ SELECT public.purge_archived_relationships(); $$
);

-- ---------------------------------------------------------------------
-- 6. R3b-4: before auth.admin.deleteUser. For every relationship the person
--    was in: end it if still active or paused (no push; the partner keeps a
--    30-day window over what remains), and delete the shared-answer and
--    derived data that cannot be split by person. Then queue the person's
--    own media. deleteUser's cascade removes the user-keyed rows.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prepare_account_deletion(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel record;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'deletion:no_user';
  END IF;

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
  FROM public.dating_profile_photos p WHERE p.user_id = p_user_id;
  -- Uploads never attached to anything: no row names them (review I5).
  PERFORM public.queue_media_deletion('message-media', i.storage_key)
  FROM public.message_media_upload_intents i WHERE i.requester_id = p_user_id;
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
  FROM public.dating_photo_upload_intents i WHERE i.user_id = p_user_id;
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
$$;

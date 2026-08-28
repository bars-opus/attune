-- Streaks: several clips, one message.
--
-- media_type widens in BOTH tables here. When voice notes broke
-- (5c23cfc8) the upload-intents constraint had been widened and messages'
-- had not, so the intent succeeded, the file uploaded, and only the final
-- insert failed -- which read as a client bug rather than a schema gap.
-- Both branches below are transcribed from the live definitions, so this
-- is provably a widening.
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_media_type_check;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_media_type_check
  CHECK (media_type IS NULL
         OR media_type IN ('image', 'audio', 'video', 'streak'));

ALTER TABLE public.message_media_upload_intents
  DROP CONSTRAINT IF EXISTS message_media_upload_intents_media_type_check;
ALTER TABLE public.message_media_upload_intents
  ADD CONSTRAINT message_media_upload_intents_media_type_check
  CHECK (media_type IN ('image', 'audio', 'video', 'streak'));

-- Remaining views. 1 = strict view-once (the default); the sender may opt
-- into up to 3. NOT NULL because a null budget on a streak would be
-- ambiguous exactly where ambiguity costs privacy.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS streak_views_remaining int NOT NULL DEFAULT 1;

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_streak_views_remaining_check;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_streak_views_remaining_check
  CHECK (streak_views_remaining BETWEEN 0 AND 3);

CREATE TABLE IF NOT EXISTS public.streak_clips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL
    REFERENCES public.messages(id) ON DELETE CASCADE,
  clip_index int NOT NULL,
  media_url text NOT NULL,
  media_thumbnail_url text,
  duration_ms int NOT NULL CHECK (duration_ms > 0),
  width int,
  height int,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, clip_index)
);

CREATE INDEX IF NOT EXISTS idx_streak_clips_message
  ON public.streak_clips(message_id, clip_index);

ALTER TABLE public.streak_clips ENABLE ROW LEVEL SECURITY;

-- Members of the owning relationship only, reached through the message.
DROP POLICY IF EXISTS streak_clips_members_read ON public.streak_clips;
CREATE POLICY streak_clips_members_read
ON public.streak_clips FOR SELECT
USING (
  message_id IN (
    SELECT m.id FROM public.messages m
    JOIN public.relationships r ON r.id = m.relationship_id
    WHERE (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.chat_archived_at IS NULL
  )
);

-- Only the sender writes clips, and only for their own message.
DROP POLICY IF EXISTS streak_clips_sender_write ON public.streak_clips;
CREATE POLICY streak_clips_sender_write
ON public.streak_clips FOR INSERT
WITH CHECK (
  message_id IN (
    SELECT m.id FROM public.messages m
    WHERE m.sender_id = auth.uid()
  )
);

COMMENT ON TABLE public.streak_clips IS
  'Ordered segments of one streak message. Playback is clip_index ASC.';

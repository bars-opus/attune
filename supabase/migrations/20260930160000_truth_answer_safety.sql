-- Runs truth answers through the same safety check as chat messages.
--
-- TRUTH_OR_DARE.md §4.4: truth answers are free text and may carry
-- distressing content, so they run through the same hard-coded keyword
-- detection as chat, with resources surfaced privately to the READER —
-- not the writer — and the game continuing uninterrupted.
--
-- None of that existed. SafetyTriggerService.checkTruthAnswer was a stub
-- returning false, called from nowhere, and game_session_rounds
-- .safety_triggered was read by the client but never written. A free-text
-- field in an intimate game had no safety net at all.
--
-- Mirrors chat exactly rather than inventing a second mechanism: a row
-- lands in an outbox, a worker scans it with the shared config, and a
-- match becomes a safety_events row. Keyword detection stays server-side
-- so the wordlist is not shipped in the client bundle.

CREATE TABLE IF NOT EXISTS public.truth_answer_safety_outbox (
  round_id uuid PRIMARY KEY
    REFERENCES public.game_session_rounds(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL
    REFERENCES public.relationships(id) ON DELETE CASCADE,
  -- Which side answered, so the worker knows which column to read and who
  -- the reader is. The reader is the OTHER partner: resources go to whoever
  -- is about to read the answer.
  answering_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  source_event_key text,
  state text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  last_error_code text,
  processing_started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS truth_answer_safety_outbox_pending_idx
  ON public.truth_answer_safety_outbox (created_at)
  WHERE state = 'pending';

-- Server-side only: it names game rounds across every relationship.
ALTER TABLE public.truth_answer_safety_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.truth_answer_safety_outbox
  FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.truth_answer_safety_outbox TO service_role;

-- Queues a truth answer for scanning.
--
-- AFTER UPDATE rather than INSERT: rounds are created empty when the
-- session starts and the answer arrives later, so the insert carries no
-- text to scan.
CREATE OR REPLACE FUNCTION public.queue_truth_answer_safety()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_answering uuid;
  v_relationship uuid;
  v_new_answer text;
BEGIN
  -- Truths only. A dare has no free text to scan.
  IF NEW.chosen_type IS DISTINCT FROM 'truth' THEN
    RETURN NEW;
  END IF;

  -- Exactly one side's answer is newly present. '__revealed__' is the
  -- sentinel filling the non-active partner's slot in this alternating
  -- game (TRUTH_OR_DARE.md §2.2) — it is not text anyone wrote.
  IF NEW.answer_a IS NOT NULL
     AND NEW.answer_a <> '__revealed__'
     AND OLD.answer_a IS DISTINCT FROM NEW.answer_a THEN
    v_new_answer := NEW.answer_a;
  ELSIF NEW.answer_b IS NOT NULL
     AND NEW.answer_b <> '__revealed__'
     AND OLD.answer_b IS DISTINCT FROM NEW.answer_b THEN
    v_new_answer := NEW.answer_b;
  ELSE
    RETURN NEW;
  END IF;

  SELECT r.id,
         CASE WHEN NEW.answer_a IS NOT NULL
                   AND NEW.answer_a <> '__revealed__'
                   AND OLD.answer_a IS DISTINCT FROM NEW.answer_a
              THEN r.user_a ELSE r.user_b END
    INTO v_relationship, v_answering
    FROM public.game_sessions s
    JOIN public.relationships r ON r.id = s.relationship_id
   WHERE s.id = NEW.session_id
     AND r.status = 'active';

  IF v_relationship IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.truth_answer_safety_outbox (
    round_id, relationship_id, answering_user_id, source_event_key
  )
  VALUES (
    NEW.id,
    v_relationship,
    v_answering,
    -- Same shape as chat's, so a replayed scan upserts onto one
    -- safety_events row rather than raising the same concern twice.
    encode(
      digest('truth_answer:' || v_relationship::text || ':' || NEW.id::text,
             'sha256'),
      'hex'
    )
  )
  ON CONFLICT (round_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS queue_truth_answer_safety ON public.game_session_rounds;
CREATE TRIGGER queue_truth_answer_safety
  AFTER UPDATE ON public.game_session_rounds
  FOR EACH ROW EXECUTE FUNCTION public.queue_truth_answer_safety();

REVOKE ALL ON FUNCTION public.queue_truth_answer_safety() FROM PUBLIC, anon;

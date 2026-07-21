-- supabase/migrations/20260721120000_message_sentiment.sql
-- Layer 1 (analyse-message) already asks Claude for a "sentiment" field per
-- message but validateLayerOne() discarded it before the UPDATE. Persisting
-- it is what lets Ask-2 eligibility detect "the first positive-valence
-- observation" (ATTUNE_MASTER_SPEC.md decision 29) instead of guessing from
-- tone_score, which was designed for NVC/conflict detection, not general
-- positive-affect detection.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS sentiment text
    CHECK (sentiment IS NULL OR sentiment IN ('positive', 'neutral', 'negative', 'charged'));

CREATE INDEX IF NOT EXISTS idx_messages_positive_sentiment
  ON public.messages (relationship_id, created_at)
  WHERE sentiment = 'positive';

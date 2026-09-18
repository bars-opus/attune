-- AI Assistant: on-demand, pull-only Assist/Understand modes from a chat
-- message. Spec: docs/superpowers/specs/2026-09-15-ai-assistant-design.md
-- (this file implements §7.2's schema additions).
--
-- Assist mode's shared output becomes an ordinary messages row with
-- unforgeable server-owned provenance (message_origin/assistant_payload).
-- Understand mode never persists anything -- it has no table here at all.

ALTER TABLE public.messages
  ADD COLUMN message_origin text NOT NULL DEFAULT 'user'
    CHECK (message_origin IN ('user', 'attune_assist')),
  ADD COLUMN assistant_payload jsonb;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_assistant_payload_shape CHECK (
    (message_origin = 'user' AND assistant_payload IS NULL)
    OR
    (message_origin = 'attune_assist' AND assistant_payload IS NOT NULL)
  );

-- Server-only preview. A generation the requester has not yet chosen to
-- share; never client-writable, never client-readable directly (the edge
-- function that created it is the only reader, via a service-role
-- connection, until the requester calls share_ai_assist_draft -- Task 6).
CREATE TABLE public.ai_assist_drafts (
  id                 uuid PRIMARY KEY,
  relationship_id    uuid NOT NULL REFERENCES public.relationships(id)
                       ON DELETE CASCADE,
  requester_id       uuid NOT NULL REFERENCES public.users(id)
                       ON DELETE CASCADE,
  target_message_id  uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  reply_text         text NOT NULL CHECK (
                       char_length(btrim(reply_text)) BETWEEN 1 AND 2000
                     ),
  assistant_payload  jsonb NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  expires_at         timestamptz NOT NULL,
  shared_message_id  uuid UNIQUE REFERENCES public.messages(id)
                       ON DELETE SET NULL,
  CHECK (expires_at = created_at + interval '15 minutes')
);

CREATE INDEX idx_ai_assist_drafts_purge
  ON public.ai_assist_drafts (created_at);

-- One row per (request_id, user_id, mode). This is the entire atomic
-- quota/idempotency ledger -- see share_quota_reserve in Task 4.
CREATE TABLE public.ai_assistant_usage (
  request_id      uuid PRIMARY KEY,
  user_id         uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
                   ON DELETE CASCADE,
  mode            text NOT NULL CHECK (mode IN ('assist', 'understand')),
  provider_calls  smallint NOT NULL DEFAULT 0
                   CHECK (provider_calls BETWEEN 0 AND 2),
  outcome         text NOT NULL CHECK (outcome IN (
                    'reserved', 'succeeded', 'rejected', 'provider_failed',
                    'cancelled'
                  )),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- The rolling-24h quota count scans this shape; user_id + created_at is
-- the exact predicate share_quota_reserve's COUNT uses (Task 4).
CREATE INDEX idx_ai_assistant_usage_rolling_window
  ON public.ai_assistant_usage (user_id, created_at);

CREATE INDEX idx_ai_assistant_usage_purge
  ON public.ai_assistant_usage (created_at);

-- Append-only. A "current" grant/withdrawal is whichever row for
-- (relationship_id, user_id, policy_version) has the latest
-- (created_at, id) -- see idx_ai_processing_consent_current below and
-- record_ai_processing_consent (Task 3).
CREATE TABLE public.ai_processing_consent_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
                   ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  policy_version  text NOT NULL CHECK (
                    char_length(btrim(policy_version)) BETWEEN 1 AND 80
                  ),
  action          text NOT NULL CHECK (action IN ('granted', 'withdrawn')),
  idempotency_key uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key)
);

CREATE INDEX idx_ai_processing_consent_current
  ON public.ai_processing_consent_events
  (relationship_id, user_id, policy_version, created_at DESC, id DESC);

-- Links a shared Assist message to the Planning entity its proposal
-- created, so both partners' clients can render "Added to Planning" and
-- so a later Planning soft-delete can find its way back here (Task 7).
-- Composite FKs mirror Planning's own cross-couple-impossible pattern
-- (PLANNING.md §4).
CREATE TABLE public.ai_assist_planning_links (
  message_id       uuid PRIMARY KEY REFERENCES public.messages(id)
                     ON DELETE CASCADE,
  relationship_id  uuid NOT NULL REFERENCES public.relationships(id)
                     ON DELETE CASCADE,
  planning_item_id  uuid,
  planning_event_id uuid,
  created_by        uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  CHECK (num_nonnulls(planning_item_id, planning_event_id) = 1),
  FOREIGN KEY (planning_item_id, relationship_id)
    REFERENCES public.planning_items(id, relationship_id) ON DELETE CASCADE,
  FOREIGN KEY (planning_event_id, relationship_id)
    REFERENCES public.planning_events(id, relationship_id) ON DELETE CASCADE
);

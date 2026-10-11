-- Spec §7.1: ai_session_requests, ai_session_turns, ai_session_staging,
-- ai_session_publications.

CREATE TABLE public.ai_session_requests (
  id                     uuid PRIMARY KEY,
  session_id             uuid NOT NULL REFERENCES public.ai_sessions(id) ON DELETE CASCADE,
  actor_id               uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- 1..10; the ordinal pair for this attempt is exactly (2n-1, 2n).
  attempt_n              smallint NOT NULL CHECK (attempt_n BETWEEN 1 AND 10),
  -- A hash/fingerprint of the request's own operation shape EXCLUDING
  -- location (spec §6.2: "operation fingerprint without location") --
  -- used to detect "same request_id, different payload" conflicts.
  -- Never raw instruction text (spec §7.1: "No raw pending instruction/
  -- context/location").
  operation_fingerprint  text NOT NULL,
  -- Non-renewable: set once at admission, never updated. Only the
  -- worker holding this exact token may claim the provider-start marker
  -- or commit a completion for this request (spec §6.2).
  worker_token           uuid NOT NULL,
  generation_epoch       int NOT NULL,
  lease_deadline         timestamptz NOT NULL,
  state                  text NOT NULL CHECK (state IN (
                           'reserved', 'started', 'staged', 'committed',
                           'failed', 'cancelled'
                         )),
  provider_started_at    timestamptz,
  terminal_code          text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id, attempt_n)
);

CREATE INDEX idx_ai_session_requests_lease_deadline
  ON public.ai_session_requests (lease_deadline) WHERE state IN ('reserved', 'started');

ALTER TABLE public.ai_session_requests ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.ai_session_turns (
  session_id  uuid NOT NULL REFERENCES public.ai_sessions(id) ON DELETE CASCADE,
  request_id  uuid NOT NULL REFERENCES public.ai_session_requests(id) ON DELETE CASCADE,
  ordinal     smallint NOT NULL CHECK (ordinal BETWEEN 1 AND 20),
  role        text NOT NULL CHECK (role IN ('user', 'attune')),
  author_id   uuid REFERENCES public.users(id) ON DELETE SET NULL,
  kind        text NOT NULL CHECK (kind IN ('ideas_answer', 'redirect', 'nearby_result')),
  payload     jsonb NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, ordinal),
  CHECK ((role = 'user') = (author_id IS NOT NULL))
);

ALTER TABLE public.ai_session_turns ENABLE ROW LEVEL SECURITY;

-- Requester-only bounded Nearby staging. No coordinates (spec §7.1:
-- "no coordinates"). Expires at min(now+2min, session expiry) --
-- computed by the staging RPC (Task 9), not a generated column here,
-- since it depends on the session's own expires_at at insert time.
CREATE TABLE public.ai_session_staging (
  session_id    uuid NOT NULL REFERENCES public.ai_sessions(id) ON DELETE CASCADE,
  request_id    uuid NOT NULL REFERENCES public.ai_session_requests(id) ON DELETE CASCADE,
  requester_id  uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reply_text    text NOT NULL CHECK (char_length(reply_text) BETWEEN 1 AND 2000),
  sources       jsonb NOT NULL,
  expires_at    timestamptz NOT NULL,
  PRIMARY KEY (session_id, request_id)
);

CREATE INDEX idx_ai_session_staging_expiry ON public.ai_session_staging (expires_at);

ALTER TABLE public.ai_session_staging ENABLE ROW LEVEL SECURITY;

-- Service-only session/request -> ordinary chat message mapping.
-- consumed_marker survives message_id going NULL (spec §7.1: "Keep a
-- content-free consumed marker through the session lifetime even if
-- the message is deleted; message FK may become NULL but must not
-- cascade away the consumed marker").
CREATE TABLE public.ai_session_publications (
  session_id      uuid NOT NULL REFERENCES public.ai_sessions(id) ON DELETE CASCADE,
  request_id      uuid NOT NULL REFERENCES public.ai_session_requests(id) ON DELETE CASCADE,
  message_id      uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  consumed_marker boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, request_id)
);

ALTER TABLE public.ai_session_publications ENABLE ROW LEVEL SECURITY;

-- AI Sessions static tables. Spec §7.1.
--
-- No client-readable "ended_by"-shaped column anywhere in this file
-- (spec §5.4) -- ending is recorded only as a state transition to
-- 'closed', never with an attributable actor column.

CREATE TABLE public.ai_sessions (
  id                    uuid PRIMARY KEY,
  relationship_id       uuid NOT NULL REFERENCES public.relationships(id)
                          ON DELETE CASCADE,
  -- The private owner, fixed for the session's lifetime (spec §7.1:
  -- "Private owner fixed"). For a shared session this is the opener;
  -- the accepting partner's membership lives in ai_session_approvals,
  -- not here -- there is no separate "participants" array column,
  -- since "who has approved" already answers "who is a member" for a
  -- shared session (both current relationship members are the only
  -- possible approvers; a relationship can only ever have two).
  creator_id            uuid NOT NULL REFERENCES public.users(id)
                          ON DELETE CASCADE,
  kind                  text NOT NULL CHECK (kind IN ('ideas', 'nearby')),
  visibility            text NOT NULL CHECK (visibility IN ('private', 'shared')),
  state                 text NOT NULL CHECK (state IN ('preparing', 'active', 'closed')),
  -- Advances on admission/completion/publication (spec §4.3). Optimistic
  -- concurrency token for generate's expected_revision.
  revision              int NOT NULL DEFAULT 1 CHECK (revision >= 1),
  -- Frozen at activation; does NOT advance with `revision` afterward
  -- (spec §4.3: "The session's state revision advances on admission/
  -- completion/publication; it does not invalidate the frozen context
  -- approvals"). Starts at 0 in preparing state (no context approved
  -- yet); Task 4 sets it at activation.
  context_revision      int NOT NULL DEFAULT 0 CHECK (context_revision >= 0),
  -- Incremented whenever an in-flight lease is forcibly invalidated
  -- (End, source edit, membership change) so a stale worker's late
  -- completion can be fenced by comparing epochs (spec §6.2's
  -- "Completion transaction fences on... epoch").
  generation_epoch      int NOT NULL DEFAULT 0 CHECK (generation_epoch >= 0),
  attempt_count         smallint NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 10),
  created_at            timestamptz NOT NULL DEFAULT now(),
  activated_at          timestamptz,
  -- Advances ONLY on admission (spec §5.2), never on reads/typing/
  -- retries/publication. NULL until the first admitted attempt.
  last_admitted_at       timestamptz,
  -- expires_at = min(last_admitted_at + 15min, activated_at + 60min)
  -- once active; preparation_deadline governs the preparing state
  -- instead (spec §5.2). Computed by the RPCs in Tasks 4/6, not by a
  -- generated column -- last_admitted_at changes on every admission and
  -- Postgres GENERATED columns cannot reference "now()"-relative logic
  -- that depends on a sibling column updated in the same statement in
  -- the way this recomputation needs.
  expires_at            timestamptz,
  preparation_deadline  timestamptz NOT NULL,
  CHECK (
    (state = 'preparing' AND activated_at IS NULL)
    OR (state != 'preparing' AND activated_at IS NOT NULL)
  )
);

CREATE INDEX idx_ai_sessions_relationship_state
  ON public.ai_sessions (relationship_id, state);
CREATE INDEX idx_ai_sessions_expiry
  ON public.ai_sessions (expires_at) WHERE state = 'active';
CREATE INDEX idx_ai_sessions_preparation_expiry
  ON public.ai_sessions (preparation_deadline) WHERE state = 'preparing';

ALTER TABLE public.ai_sessions ENABLE ROW LEVEL SECURITY;
-- Deliberately no policy at all -- see Task 1's own contract test for
-- why "RLS enabled, zero policies" is the enforcement mechanism, not
-- decoration around a REVOKE.

CREATE TABLE public.ai_session_approvals (
  session_id     uuid NOT NULL REFERENCES public.ai_sessions(id) ON DELETE CASCADE,
  member_id      uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  revision       int NOT NULL,
  digest         text NOT NULL,
  policy_version text NOT NULL,
  accepted_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, member_id, revision)
);

ALTER TABLE public.ai_session_approvals ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.ai_session_sources (
  session_id            uuid NOT NULL REFERENCES public.ai_sessions(id) ON DELETE CASCADE,
  source_message_id     uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  source_version        timestamptz NOT NULL,
  approved_clipped_text text NOT NULL CHECK (char_length(approved_clipped_text) <= 4000),
  -- 'target' (the long-pressed/selected message) or 'window' (one of
  -- the up-to-6 shared-window messages). At most one 'target' row and
  -- at most 6 'window' rows per session -- enforced by Task 5's
  -- approval RPC, not a table constraint (a partial unique index can
  -- cap 'target' to one row, but capping 'window' to six needs a
  -- COUNT check the RPC already has to do for the approval-digest
  -- computation anyway).
  source_role           text NOT NULL CHECK (source_role IN ('target', 'window')),
  PRIMARY KEY (session_id, source_message_id)
);

CREATE UNIQUE INDEX idx_ai_session_sources_one_target
  ON public.ai_session_sources (session_id)
  WHERE source_role = 'target';

ALTER TABLE public.ai_session_sources ENABLE ROW LEVEL SECURITY;

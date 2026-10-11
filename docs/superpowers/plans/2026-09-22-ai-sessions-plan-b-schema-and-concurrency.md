# AI Sessions — Plan B: Schema, RPCs, and Concurrency Protocol

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete server-side backbone for AI Sessions — seven
new tables, RLS with no direct authenticated grants, the full admission/
dispatch/completion transaction protocol (§6.2), the private-Nearby-
staging and shared-publication flows, and the every-minute
reconciler/purge job — with SQL contract tests that prove concurrency,
authorization, and the compensation table in §8.2.2 against a real
Postgres, not against this plan's own narration of what the code does.

**Not in this plan: §6.1 Realtime authorization.** (Corrected by Task 5
of the merge-blocker plan, N6. This paragraph previously listed "per-user
Realtime authorization for content-free invalidation hints" as a
deliverable; it was never built. Verified by catalog query: ZERO policies
exist on `realtime.messages`, and zero on the whole `realtime` schema.
The plan's own §6.1 note and its "What this plan deliberately does NOT
do" section already disclaimed it correctly — only this Goal paragraph
disagreed, which is the one place a reader looks first.) See
`docs/superpowers/plans/2026-09-22-ai-sessions-plan-c-edge-function-and-safety.md`
for who owns it: as the work is divided, NEITHER plan claims it.

**Architecture:** No edge function in this plan — that is Plan C. Every
RPC here is `service_role`-only (client-callable commands are a thin,
separate layer Plan C's edge function calls; Plan B proves the database
layer is correct on its own terms first, via direct RPC calls from SQL
contract tests and Deno tests using
`supabase/functions/_shared/test_support/pg_rls_client.ts`'s
`makeServiceRoleClient()`). Follows the existing "clients get SELECT-via-
narrow-RPC only, every mutation via `SECURITY DEFINER`" shape from
`lib/architecture/PLANNING.md` §4 and the AI Assistant Plan A backend
(`docs/superpowers/plans/2026-09-16-ai-assistant-plan-a-backend.md`), and
reuses the relationship-level `pg_advisory_xact_lock(hashtext(...))`
convention already established across the games features (see
`supabase/migrations/20260933190000_paint_ball_spec_completion.sql` for
the closest existing precedent: authorization check → relationship lock
→ idempotency-key lookup → existing-slot check, the same shape §3.2's
session-creation admission and §6.2's generation admission both need).
Realtime is INTENDED to use Supabase's private-channel Broadcast
authorization (RLS on `realtime.messages`) — intended, not built here:
see the Goal section's §6.1 note. It is genuinely new infrastructure for
this codebase — every existing feature (`supabase_chat_repository.dart`,
Planning, the games) uses public `onPostgresChanges` on the underlying
table instead, which spec §6.1 explicitly forbids for Sessions'
transcript/staging tables ("No direct Postgres Changes publication of
transcript/staging tables").

**Tech Stack:** PostgreSQL migrations (Supabase), SQL contract tests via
`scripts/local_pg_setup.sh`'s `attune_test` database, shell-script
concurrency tests (see Plan A Task 5 for the pattern:
`for i in $(seq 1 N); do psql ... & done; wait`), Deno test doubles via
`pg_rls_client.ts` for anything a later Plan C edge function will call.

**Spec:** `docs/superpowers/specs/2026-09-22-ai-sessions-design.md` §3
(entry/consent/participation), §4 (input/context contracts — this plan
implements the schema and storage side; Plan C implements the actual
Gemini/Mapbox-calling validation), §5 (lifecycle/outputs — schema and
state machine only; Plan C implements output validation), §6 (shared-
session protocol and concurrency — this plan's central chapter), §7
(persistence and authorization — this plan's second central chapter), §11
items 1-8 and 11 (this plan's own verification matrix), §13 (amendments).
Also read Plan A
(`docs/superpowers/plans/2026-09-22-ai-sessions-plan-a-quota-repair.md`)
in full and confirm it is **merged and its migrations applied** before
starting Task 1 here — this plan's admission RPC (Task 6) calls
`reserve_ai_assistant_quota` with `p_mode = 'session'`, which does not
exist until Plan A's Task 1 ships.

## Global Constraints

- **No table in this plan grants direct `SELECT`/`INSERT`/`UPDATE`/
  `DELETE` to `authenticated`.** Every legitimate access is a narrow
  `SECURITY DEFINER` RPC or a security-invoker view backed by RLS. (Spec
  §7.2: "Revoke all direct mutation grants; raw approval, source,
  staging, lease, usage, publication and outbox tables also have no
  authenticated SELECT.")
- **Lock order is fixed and must never vary across RPCs**: relationship
  advisory lock (`pg_advisory_xact_lock(hashtext(p_relationship_id::text))`)
  first, then the requester's quota advisory lock (already inside
  `reserve_ai_assistant_quota` — Plan A, unchanged), then the session row
  lock (`SELECT ... FOR UPDATE` on `ai_sessions`), then any request row
  lock. Every task below that acquires more than one lock must acquire
  them in this order; a task that needs a different order is a plan
  defect, not a local decision — stop and reconcile with this list
  before writing it. (Spec §6.2: "All participating mutation RPCs use
  one lock order... Review existing commands before adopting this order;
  mixed ordering is a merge blocker.")
- **No SQL transaction may span a provider HTTP call.** Every RPC in
  this plan either runs entirely before dispatch (admission) or entirely
  after a result is known (completion). Plan C's edge function is what
  sits in between, uninstrumented by any open transaction. (Spec §6.2:
  "No SQL transaction spans provider HTTP.")
- **Every session-scoped table's primary content (transcript, staging,
  sources, approvals) is deleted in the SAME transaction that closes the
  session** — not by a later job as the only mechanism. The every-minute
  reconciler (Task 11) is a backstop for content that somehow survived a
  closure, not the primary deletion path. (Spec §5.4: "synchronously
  removes their content in the same database transaction.")
- **`ai_sessions` and every session-scoped table exposes no
  client-readable "who ended it" field.** Do not add an `ended_by`
  column readable by any RPC this plan builds, even internally reusing
  `relationships.ended_by`'s naming — that column name is deliberately
  avoided here. (Spec §5.4: "Do not store ended_by on any client-
  readable session row.")
- **Ordinal parity is exactly `2n-1` (user) and `2n` (Attune) for attempt
  number `n`.** Every task that inserts turn rows must derive both
  ordinals from the same `n` this way — never increment two independent
  counters. (Spec §6.2 step 4.)
- **`ai_session_requests.operation_fingerprint` never includes
  location.** A Nearby retry with a replacement location must be
  rejected as a conflicting payload, not silently accepted with the new
  coordinates. (Spec §6.2: "A Nearby retry ignores any replacement
  location and uses only the first admitted attempt.")
- **Every new `SECURITY DEFINER` function uses `SET search_path =
  public`** and validates `p_actor_id`/equivalent is non-NULL as its
  first statement, matching every RPC in Plan A and the existing AI
  Assistant migrations.

---

### Task 1: Static tables — `ai_sessions`, `ai_session_approvals`, `ai_session_sources`

**Files:**
- Create: `supabase/migrations/20260953010000_ai_sessions_schema.sql`
- Test: `supabase/tests/ai_sessions_schema_contracts.sql`

**Interfaces:**
- Produces: `ai_sessions` (id, relationship_id, creator_id, kind, visibility,
  state, revision, context_revision, generation_epoch, attempt_count,
  created_at, activated_at, last_admitted_at, expires_at, preparation_deadline).
  Every later task in this plan and all of Plan C reads/writes this table
  exclusively through RPCs defined in later tasks — nothing here is
  granted to `authenticated`.
- Produces: `ai_session_approvals` (session_id, member_id, revision,
  digest, policy_version, accepted_at; `UNIQUE (session_id, member_id, revision)`).
- Produces: `ai_session_sources` (session_id, source_message_id,
  source_version, approved_clipped_text, source_role; bounded to at most
  7 rows per session — 1 target + up to 6 window messages — enforced in
  Task 5, not here).
- Consumes: `public.relationships`, `public.messages`, `public.users`
  (all pre-existing).

- [ ] **Step 1: Write the failing contract test**

Create `supabase/tests/ai_sessions_schema_contracts.sql`:

```sql
-- Static Sessions tables: shape and RLS-absence contracts. Spec §7.1, §7.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_sessions_schema_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000000b';
  v_session uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'sess_a@t.test'), (v_user_b, 'sess_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550008001', 'A'), (v_user_b, '+15550008002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: the table accepts a well-formed preparing-state row
  -- via direct insert (proving column shape/defaults) -- this fixture
  -- setup runs as the migration owner, not authenticated; Contract 2
  -- proves authenticated has no access at all.
  INSERT INTO public.ai_sessions (
    id, relationship_id, creator_id, kind, visibility, state,
    revision, context_revision, generation_epoch, attempt_count,
    preparation_deadline
  ) VALUES (
    v_session, v_rel, v_user_a, 'ideas', 'private', 'preparing',
    1, 0, 0, 0, now() + interval '5 minutes'
  );

  -- Contract 2: authenticated has NO grant on any of the three tables
  -- in this migration, in either direction.
  IF EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE table_name IN ('ai_sessions', 'ai_session_approvals', 'ai_session_sources')
      AND grantee = 'authenticated'
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has a direct table grant on a Sessions table';
  END IF;

  -- Contract 3: RLS is enabled on all three (enabled but policy-less is
  -- what makes "no grant" airtight even against a future accidental
  -- GRANT -- RLS still blocks it with no matching policy).
  IF (SELECT count(*) FROM pg_tables
      WHERE schemaname = 'public'
        AND tablename IN ('ai_sessions', 'ai_session_approvals', 'ai_session_sources')
        AND rowsecurity = true) != 3 THEN
    RAISE EXCEPTION 'EXPLOIT: not all three Sessions tables have RLS enabled';
  END IF;

  -- Contract 4: kind and visibility are immutable in shape (CHECK
  -- constraints reject invalid values) -- this is schema-level
  -- enforcement, not just application-code discipline.
  BEGIN
    INSERT INTO public.ai_sessions (
      id, relationship_id, creator_id, kind, visibility, state,
      revision, context_revision, generation_epoch, attempt_count,
      preparation_deadline
    ) VALUES (
      gen_random_uuid(), v_rel, v_user_a, 'nonsense_kind', 'private', 'preparing',
      1, 0, 0, 0, now() + interval '5 minutes'
    );
    RAISE EXCEPTION 'EXPLOIT: an invalid kind value was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 5: attempt_count is bounded 0..10 at the schema level.
  BEGIN
    UPDATE public.ai_sessions SET attempt_count = 11 WHERE id = v_session;
    RAISE EXCEPTION 'EXPLOIT: attempt_count accepted a value above 10';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'ai_sessions static schema contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_sessions_schema_contracts.sql
```

Expected: `relation "public.ai_sessions" does not exist`

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260953010000_ai_sessions_schema.sql`:

```sql
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
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953010000_ai_sessions_schema.sql
psql -q -d attune_test -f supabase/tests/ai_sessions_schema_contracts.sql
```

Expected: `NOTICE: ai_sessions static schema contracts: all held`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260953010000_ai_sessions_schema.sql \
        supabase/tests/ai_sessions_schema_contracts.sql
git commit -m "feat(ai-sessions): add ai_sessions, ai_session_approvals, ai_session_sources"
```

---

### Task 2: Request/turn/staging/publication tables

**Files:**
- Create: `supabase/migrations/20260953020000_ai_session_requests_and_turns.sql`
- Test: `supabase/tests/ai_session_requests_turns_contracts.sql`

**Interfaces:**
- Produces: `ai_session_requests` (id, session_id, actor_id, attempt_n,
  operation_fingerprint, worker_token, generation_epoch, lease_deadline,
  state, provider_started_at, terminal_code).
- Produces: `ai_session_turns` (session_id, request_id, ordinal, role,
  author_id, kind, payload; `UNIQUE (session_id, ordinal)`).
- Produces: `ai_session_staging` (session_id, request_id, requester_id,
  reply_text, sources, expires_at).
- Produces: `ai_session_publications` (session_id, request_id, message_id,
  consumed_marker; the "content-free consumed marker" that survives even
  after `message_id` goes NULL — spec §7.1's own explicit requirement).
- Consumes: `ai_sessions` (Task 1), `public.messages`.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_requests_turns_contracts.sql`:

```sql
-- ai_session_requests / ai_session_turns / ai_session_staging /
-- ai_session_publications: shape, ordinal parity, and the surviving
-- publication marker. Spec §7.1.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_requests_turns_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000002';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000001a';
  v_session uuid := gen_random_uuid();
  v_request uuid := gen_random_uuid();
  v_message uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'req_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550009001', 'A') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel, v_user_a, 'active') ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_sessions (
    id, relationship_id, creator_id, kind, visibility, state,
    revision, context_revision, generation_epoch, attempt_count, preparation_deadline
  ) VALUES (
    v_session, v_rel, v_user_a, 'ideas', 'private', 'active',
    1, 1, 0, 1, now() + interval '5 minutes'
  );

  -- Contract 1: a request row with attempt_n=1 and its matching turn
  -- pair at ordinals 1 (user) and 2 (attune) insert cleanly.
  INSERT INTO public.ai_session_requests (
    id, session_id, actor_id, attempt_n, operation_fingerprint,
    worker_token, generation_epoch, lease_deadline, state
  ) VALUES (
    v_request, v_session, v_user_a, 1, 'ideas:hash-of-instruction',
    gen_random_uuid(), 0, now() + interval '35 seconds', 'reserved'
  );
  INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
  VALUES
    (v_session, v_request, 1, 'user', v_user_a, 'ideas_answer', '{"instruction": "test"}'::jsonb),
    (v_session, v_request, 2, 'attune', NULL, 'ideas_answer', '{"reply_text": "test reply"}'::jsonb);

  -- Contract 2: an 'attune' role row REQUIRES a NULL author_id, and a
  -- 'user' role row REQUIRES a non-NULL author_id -- this is the check
  -- constraint proving the spec's "author ID for user only" rule at
  -- the schema level, not just by convention in the RPC that inserts
  -- these rows (Task 8).
  BEGIN
    INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
    VALUES (v_session, v_request, 3, 'attune', v_user_a, 'ideas_answer', '{}'::jsonb);
    RAISE EXCEPTION 'EXPLOIT: an attune-role turn accepted a non-NULL author_id';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 3: ordinal is unique per session -- a duplicate ordinal
  -- for a DIFFERENT request in the same session is rejected outright.
  BEGIN
    INSERT INTO public.ai_session_requests (
      id, session_id, actor_id, attempt_n, operation_fingerprint,
      worker_token, generation_epoch, lease_deadline, state
    ) VALUES (
      gen_random_uuid(), v_session, v_user_a, 2, 'ideas:different',
      gen_random_uuid(), 0, now() + interval '35 seconds', 'reserved'
    );
    INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
    VALUES (v_session, v_request, 1, 'user', v_user_a, 'ideas_answer', '{}'::jsonb);
    RAISE EXCEPTION 'EXPLOIT: a duplicate ordinal within the same session was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: publication marker survives message_id going NULL.
  v_message := gen_random_uuid();
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, source, created_at)
  VALUES (v_message, v_rel, v_user_a, gen_random_uuid(), 'a shared answer', 'native', now());
  INSERT INTO public.ai_session_publications (session_id, request_id, message_id, consumed_marker)
  VALUES (v_session, v_request, v_message, true);
  DELETE FROM public.messages WHERE id = v_message;
  IF (SELECT count(*) FROM public.ai_session_publications WHERE session_id = v_session AND request_id = v_request) != 1 THEN
    RAISE EXCEPTION 'EXPLOIT: the publication marker was deleted when its message was deleted -- FK must be ON DELETE SET NULL, not CASCADE';
  END IF;
  IF (SELECT message_id FROM public.ai_session_publications WHERE session_id = v_session AND request_id = v_request) IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: message_id did not go NULL after the message was deleted';
  END IF;

  RAISE NOTICE 'ai_session_requests/turns/staging/publications contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_requests_turns_contracts.sql
```

Expected: `relation "public.ai_session_requests" does not exist`

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260953020000_ai_session_requests_and_turns.sql`:

```sql
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
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953020000_ai_session_requests_and_turns.sql
psql -q -d attune_test -f supabase/tests/ai_session_requests_turns_contracts.sql
```

Expected: `NOTICE: ai_session_requests/turns/staging/publications contracts: all held`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260953020000_ai_session_requests_and_turns.sql \
        supabase/tests/ai_session_requests_turns_contracts.sql
git commit -m "feat(ai-sessions): add ai_session_requests, turns, staging, publications"
```

---

### Task 3: `prepare_ai_session` — idempotent session creation

**Files:**
- Create: `supabase/migrations/20260953030000_ai_session_prepare_rpc.sql`
- Test: `supabase/tests/ai_session_prepare_contracts.sql`

**Interfaces:**
- Consumes: `ai_sessions` (Task 1).
- Produces: `prepare_ai_session(p_actor_id uuid, p_idempotency_key uuid, p_relationship_id uuid, p_kind text, p_visibility text, p_target_message_id uuid, p_include_window boolean) RETURNS TABLE (session_id uuid, revision int, created boolean)`
  — server-owned session ID, `preparing` state, 5-minute
  `preparation_deadline`. `created = false` on an idempotent replay of
  the same `p_idempotency_key`. Enforces "only one pending/active shared
  session per relationship; one pending/active private session per
  creator" (spec §3.2) and "reclaim expired slots transactionally"
  (auto-closes an existing `preparing` session past its deadline before
  checking the slot limit, in the same transaction). Called by Plan C's
  edge function on the client's "prepare" command (spec §4.1).

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_prepare_contracts.sql`:

```sql
-- prepare_ai_session: idempotent creation, one-pending-slot enforcement,
-- expired-slot reclamation. Spec §3.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_prepare_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000003';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000002a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000002b';
  v_key_1 uuid := gen_random_uuid();
  v_row record;
  v_session_1 uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'prep_a@t.test'), (v_user_b, 'prep_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550010001', 'A'), (v_user_b, '+15550010002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: a fresh prepare succeeds and returns created=true.
  SELECT * INTO v_row FROM public.prepare_ai_session(
    v_user_a, v_key_1, v_rel, 'ideas', 'private', NULL, false
  );
  IF v_row.created IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: a fresh prepare did not report created=true';
  END IF;
  v_session_1 := v_row.session_id;

  -- Contract 2: replaying the SAME idempotency key returns the SAME
  -- session_id with created=false, not a second row.
  SELECT * INTO v_row FROM public.prepare_ai_session(
    v_user_a, v_key_1, v_rel, 'ideas', 'private', NULL, false
  );
  IF v_row.session_id IS DISTINCT FROM v_session_1 OR v_row.created IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: replaying the same idempotency key created a second session';
  END IF;

  -- Contract 3: a SECOND private prepare by the SAME creator, with a
  -- DIFFERENT idempotency key, while the first is still preparing,
  -- is rejected (one pending private session per creator).
  BEGIN
    PERFORM public.prepare_ai_session(v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false);
    RAISE EXCEPTION 'EXPLOIT: a second concurrent private preparing session was allowed for the same creator';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: user_b's OWN private session slot is independent of
  -- user_a's -- the limit is per-creator, not per-relationship, for
  -- the private case.
  PERFORM public.prepare_ai_session(v_user_b, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false);

  -- Contract 5: an expired preparing session is reclaimed -- backdate
  -- the first session's deadline into the past, then prove a new
  -- private prepare by user_a now succeeds.
  UPDATE public.ai_sessions SET preparation_deadline = now() - interval '1 minute'
  WHERE id = v_session_1;
  PERFORM public.prepare_ai_session(v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false);
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session_1) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: the expired preparing session was not reclaimed (closed) before the new one was allowed';
  END IF;

  RAISE NOTICE 'prepare_ai_session contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_prepare_contracts.sql
```

Expected: `function public.prepare_ai_session(...) does not exist`

- [ ] **Step 3: Write the RPC**

Create `supabase/migrations/20260953030000_ai_session_prepare_rpc.sql`:

```sql
-- prepare_ai_session: idempotent, slot-limited session creation.
-- Spec §3.2. Lock order: relationship advisory lock, then no further
-- row lock is needed here (this RPC only ever touches ai_sessions rows
-- it is about to insert, or reclaims one via UPDATE under the same
-- relationship lock, which already serializes against a concurrent
-- prepare for the same relationship).
CREATE OR REPLACE FUNCTION public.prepare_ai_session(
  p_actor_id uuid,
  p_idempotency_key uuid,
  p_relationship_id uuid,
  p_kind text,
  p_visibility text,
  p_target_message_id uuid,
  p_include_window boolean
) RETURNS TABLE (session_id uuid, revision int, created boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_session uuid;
  v_new_session uuid;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_kind NOT IN ('ideas', 'nearby') THEN
    RAISE EXCEPTION 'Invalid kind';
  END IF;
  IF p_visibility NOT IN ('private', 'shared') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Relationship unavailable';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_relationship_id::text));

  -- Idempotent replay: an idempotency key is scoped to (actor, key) --
  -- storing it would need its own column; simplest correct approach
  -- for this task is to key it into the operation_fingerprint-style
  -- lookup via a dedicated lookup table. To keep this RPC self-contained
  -- without a new table, reuse ai_sessions.id itself as the idempotency
  -- key when the caller supplies one that already resolves to an
  -- existing row for this actor -- i.e. the CALLER is responsible for
  -- reusing the same p_idempotency_key value as a candidate session_id
  -- on retry. This mirrors share_ai_assist_draft's own "the id IS the
  -- idempotency key" pattern (Plan A's ai_assist_drafts.id).
  SELECT id INTO v_existing_session FROM public.ai_sessions WHERE id = p_idempotency_key;
  IF v_existing_session IS NOT NULL THEN
    IF (SELECT creator_id FROM public.ai_sessions WHERE id = v_existing_session) != p_actor_id THEN
      RAISE EXCEPTION 'Idempotency key already used by a different actor';
    END IF;
    RETURN QUERY SELECT v_existing_session, s.revision, false
    FROM public.ai_sessions s WHERE s.id = v_existing_session;
    RETURN;
  END IF;

  -- Reclaim any of THIS actor's own expired preparing sessions before
  -- checking the slot limit (spec §3.2: "reclaim expired slots
  -- transactionally").
  UPDATE public.ai_sessions
  SET state = 'closed'
  WHERE creator_id = p_actor_id AND relationship_id = p_relationship_id
    AND state = 'preparing' AND preparation_deadline < now();

  IF p_visibility = 'private' THEN
    IF EXISTS (
      SELECT 1 FROM public.ai_sessions
      WHERE creator_id = p_actor_id AND relationship_id = p_relationship_id
        AND visibility = 'private' AND state IN ('preparing', 'active')
    ) THEN
      RAISE EXCEPTION 'A private session is already pending or active for this creator';
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.ai_sessions
      WHERE relationship_id = p_relationship_id
        AND visibility = 'shared' AND state IN ('preparing', 'active')
    ) THEN
      RAISE EXCEPTION 'A shared session is already pending or active for this relationship';
    END IF;
  END IF;

  v_new_session := p_idempotency_key;
  INSERT INTO public.ai_sessions (
    id, relationship_id, creator_id, kind, visibility, state,
    revision, context_revision, generation_epoch, attempt_count,
    preparation_deadline
  ) VALUES (
    v_new_session, p_relationship_id, p_actor_id, p_kind, p_visibility, 'preparing',
    1, 0, 0, 0, now() + interval '5 minutes'
  );

  IF p_target_message_id IS NOT NULL THEN
    INSERT INTO public.ai_session_sources (session_id, source_message_id, source_version, approved_clipped_text, source_role)
    SELECT v_new_session, m.id, m.created_at, left(m.content, 4000), 'target'
    FROM public.messages m
    WHERE m.id = p_target_message_id AND m.deleted_at IS NULL
      AND m.relationship_id = p_relationship_id;
  END IF;

  RETURN QUERY SELECT v_new_session, 1, true;
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_ai_session(uuid, uuid, uuid, text, text, uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ai_session(uuid, uuid, uuid, text, text, uuid, boolean)
  TO service_role;
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953030000_ai_session_prepare_rpc.sql
psql -q -d attune_test -f supabase/tests/ai_session_prepare_contracts.sql
```

Expected: `NOTICE: prepare_ai_session contracts: all held`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260953030000_ai_session_prepare_rpc.sql \
        supabase/tests/ai_session_prepare_contracts.sql
git commit -m "feat(ai-sessions): add prepare_ai_session with idempotent, slot-limited creation"
```

---

### Task 4: `approve_ai_session_context` and `activate_ai_session`

**Files:**
- Create: `supabase/migrations/20260953040000_ai_session_approve_activate_rpcs.sql`
- Test: `supabase/tests/ai_session_approve_activate_contracts.sql`

**Interfaces:**
- Consumes: `ai_sessions`, `ai_session_approvals`, `ai_session_sources`
  (Task 1), `prepare_ai_session` (Task 3).
- Produces: `approve_ai_session_context(p_actor_id uuid, p_session_id uuid, p_revision int, p_digest text, p_policy_version text) RETURNS void`
  — one row per `(session_id, member_id, revision)`; re-approving the
  same revision is a no-op (idempotent). Changing `include_window` or
  any frozen setting after this must go through a NEW `prepare` (spec
  §4.3: "enabling it in preparing state invalidates approvals and
  increments revision" — this task's RPC does not implement window
  toggling itself; it only records approval of whatever revision Task 3
  produced. A later task, if window-toggling-in-preparing-state is
  needed before activation, would add a separate
  `set_ai_session_window` RPC that bumps revision and deletes prior
  approvals — **not built in this plan**, since Plan B's own scope per
  the Sessions spec's §3.2 flow allows preparing with the window setting
  fixed at `prepare` time; toggling it afterward is UI-layer scope for
  Plan D to decide whether to expose at all, and is explicitly optional
  per spec §4.1's "Context settings freeze before activation").
- Produces: `activate_ai_session(p_actor_id uuid, p_session_id uuid, p_revision int) RETURNS TABLE (activated boolean, state text)`
  — transitions `preparing` → `active` once all required approvals
  exist for the current revision (one for private, two for shared —
  "Required approvals match both current members for shared
  activation," spec §7.1), freezes `context_revision` to the approved
  revision, sets `activated_at`. Raises `APPROVAL_REQUIRED`-shaped error
  if not all approvals are present yet; this is not a failure for a
  shared session where the partner hasn't opened the invite yet, so the
  RPC must not close or otherwise penalize the session on this path.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_approve_activate_contracts.sql`:

```sql
-- approve_ai_session_context / activate_ai_session. Spec §3.2, §4.3, §7.1.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_approve_activate_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000004';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000003a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000003b';
  v_row record;
  v_private_session uuid;
  v_shared_session uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'appr_a@t.test'), (v_user_b, 'appr_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550011001', 'A'), (v_user_b, '+15550011002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Private: one approval activates it.
  SELECT session_id INTO v_private_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_private_session, 1, 'digest-a', 'v1');
  SELECT * INTO v_row FROM public.activate_ai_session(v_user_a, v_private_session, 1);
  IF v_row.activated IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: a private session with its own creator''s approval did not activate';
  END IF;

  -- Shared: creator's approval alone is NOT enough.
  SELECT session_id INTO v_shared_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_shared_session, 1, 'digest-shared', 'v1');
  BEGIN
    PERFORM public.activate_ai_session(v_user_a, v_shared_session, 1);
    RAISE EXCEPTION 'EXPLOIT: a shared session activated with only ONE partner''s approval';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Both approve the SAME digest -> activates.
  PERFORM public.approve_ai_session_context(v_user_b, v_shared_session, 1, 'digest-shared', 'v1');
  SELECT * INTO v_row FROM public.activate_ai_session(v_user_a, v_shared_session, 1);
  IF v_row.activated IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: a shared session with BOTH partners'' approval on the same digest did not activate';
  END IF;

  -- A mismatched digest between partners must not silently activate --
  -- approve_ai_session_context itself does not compare digests across
  -- members (that comparison IS the point: two different digests means
  -- the two partners approved two different snapshots, which can only
  -- happen if the session's own content changed between their two
  -- opens -- a case activate_ai_session must reject explicitly.
  DECLARE
    v_mismatch_session uuid;
  BEGIN
    SELECT session_id INTO v_mismatch_session FROM public.prepare_ai_session(
      v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
    );
    PERFORM public.approve_ai_session_context(v_user_a, v_mismatch_session, 1, 'digest-x', 'v1');
    PERFORM public.approve_ai_session_context(v_user_b, v_mismatch_session, 1, 'digest-y', 'v1');
    BEGIN
      PERFORM public.activate_ai_session(v_user_a, v_mismatch_session, 1);
      RAISE EXCEPTION 'EXPLOIT: a shared session activated despite the two partners approving DIFFERENT digests';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  RAISE NOTICE 'approve/activate contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_approve_activate_contracts.sql
```

Expected: `function public.approve_ai_session_context(...) does not exist`

- [ ] **Step 3: Write the RPCs**

Create `supabase/migrations/20260953040000_ai_session_approve_activate_rpcs.sql`:

```sql
-- approve_ai_session_context / activate_ai_session. Spec §3.2, §4.3, §7.1.
CREATE OR REPLACE FUNCTION public.approve_ai_session_context(
  p_actor_id uuid, p_session_id uuid, p_revision int, p_digest text, p_policy_version text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions
  WHERE id = p_session_id AND state = 'preparing' AND revision = p_revision;
  IF v_session.id IS NULL THEN
    RAISE EXCEPTION 'Session not found, not preparing, or revision mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_session.relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Not a current member of this relationship';
  END IF;

  INSERT INTO public.ai_session_approvals (session_id, member_id, revision, digest, policy_version)
  VALUES (p_session_id, p_actor_id, p_revision, p_digest, p_policy_version)
  ON CONFLICT (session_id, member_id, revision) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.approve_ai_session_context(uuid, uuid, int, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_ai_session_context(uuid, uuid, int, text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.activate_ai_session(
  p_actor_id uuid, p_session_id uuid, p_revision int
) RETURNS TABLE (activated boolean, state text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_distinct_digests int;
  v_approver_count int;
  v_required_count int;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions
  WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL THEN
    RAISE EXCEPTION 'Session not found';
  END IF;
  IF v_session.state != 'preparing' THEN
    RETURN QUERY SELECT (v_session.state = 'active'), v_session.state;
    RETURN;
  END IF;
  IF v_session.revision != p_revision THEN
    RAISE EXCEPTION 'Revision mismatch -- context changed since this client last read it';
  END IF;

  v_required_count := CASE WHEN v_session.visibility = 'shared' THEN 2 ELSE 1 END;

  SELECT count(DISTINCT member_id), count(DISTINCT digest) INTO v_approver_count, v_distinct_digests
  FROM public.ai_session_approvals
  WHERE session_id = p_session_id AND revision = p_revision;

  IF v_approver_count < v_required_count THEN
    RAISE EXCEPTION 'APPROVAL_REQUIRED';
  END IF;
  IF v_distinct_digests > 1 THEN
    RAISE EXCEPTION 'CONTEXT_CHANGED -- approvers did not approve the same snapshot';
  END IF;

  UPDATE public.ai_sessions
  SET state = 'active', activated_at = now(), context_revision = p_revision
  WHERE id = p_session_id;

  RETURN QUERY SELECT true, 'active';
END;
$$;
REVOKE ALL ON FUNCTION public.activate_ai_session(uuid, uuid, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_ai_session(uuid, uuid, int)
  TO service_role;
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953040000_ai_session_approve_activate_rpcs.sql
psql -q -d attune_test -f supabase/tests/ai_session_approve_activate_contracts.sql
```

Expected: `NOTICE: approve/activate contracts: all held`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260953040000_ai_session_approve_activate_rpcs.sql \
        supabase/tests/ai_session_approve_activate_contracts.sql
git commit -m "feat(ai-sessions): add approve_ai_session_context and activate_ai_session"
```

---

### Task 5: `admit_ai_session_generation` — the admission transaction

**This is the most safety-critical task in this plan.** It implements
spec §6.2's five-step admission sequence in full, on top of Plan A's
quota ledger.

**Files:**
- Create: `supabase/migrations/20260953050000_ai_session_admit_rpc.sql`
- Test: `supabase/tests/ai_session_admit_contracts.sql`
- Test: `supabase/tests/ai_session_admit_concurrent_test.sh`

**Interfaces:**
- Consumes: `ai_sessions` (Task 1), `ai_session_requests`/`ai_session_turns`
  (Task 2), `reserve_ai_assistant_quota` (Plan A Task 1, with
  `p_mode = 'session'`).
- Produces: `admit_ai_session_generation(p_actor_id uuid, p_request_id uuid, p_session_id uuid, p_expected_revision int, p_operation_fingerprint text) RETURNS TABLE (outcome text, request_id uuid, attempt_n int, worker_token uuid, lease_deadline timestamptz, retry_after_seconds int)`
  — `outcome` is one of `'admitted' | 'already_admitted' | 'busy' |
  'limit_reached' | 'rate_limited' | 'revision_stale' | 'conflict'`. Only
  `'admitted'` and `'already_admitted'` return a usable
  `worker_token`/`lease_deadline`; every other outcome means "do not
  proceed to any provider call." Called by Plan C's edge function
  immediately on receiving a `generate` command, before any Gemini/
  Mapbox work.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_admit_contracts.sql`:

```sql
-- admit_ai_session_generation: the full §6.2 admission sequence.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_admit_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000005';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000004a';
  v_session uuid;
  v_row record;
  v_row2 record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'admit_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550012001', 'A') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel, v_user_a, 'active') ON CONFLICT DO NOTHING;

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);

  -- Contract 1: a fresh admission succeeds, attempt_n=1, ordinals
  -- would be (1,2) -- proven indirectly via attempt_n here; Task 8's
  -- own test proves the ordinal pair itself once turns are committed.
  SELECT * INTO v_row FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp-1'
  );
  IF v_row.outcome IS DISTINCT FROM 'admitted' OR v_row.attempt_n IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: fresh admission did not succeed with attempt_n=1, got outcome=% attempt_n=%', v_row.outcome, v_row.attempt_n;
  END IF;

  -- Contract 2: a SECOND admission for the SAME session while the
  -- first is still in-flight (state='reserved', no completion yet) is
  -- rejected as 'busy' -- one in-flight attempt per session (spec §6.2
  -- step 3).
  SELECT * INTO v_row2 FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp-2'
  );
  IF v_row2.outcome IS DISTINCT FROM 'busy' THEN
    RAISE EXCEPTION 'EXPLOIT: a second admission was allowed while the first attempt is still in-flight, got %', v_row2.outcome;
  END IF;

  -- Contract 3: replaying the SAME request_id as Contract 1 returns
  -- 'already_admitted' with the SAME attempt_n/worker_token, not a
  -- fresh admission (idempotency).
  SELECT * INTO v_row2 FROM public.admit_ai_session_generation(
    v_user_a, v_row.request_id, v_session, 1, 'ideas:fp-1'
  );
  IF v_row2.outcome IS DISTINCT FROM 'already_admitted'
     OR v_row2.attempt_n IS DISTINCT FROM v_row.attempt_n
     OR v_row2.worker_token IS DISTINCT FROM v_row.worker_token THEN
    RAISE EXCEPTION 'EXPLOIT: replaying the same request_id did not return the SAME attempt/worker_token';
  END IF;

  -- Contract 4: replaying the SAME request_id with a DIFFERENT
  -- operation_fingerprint is a conflict (spec §6.2 step 2: "Conflicting
  -- operation/session/non-location payload reuse fails").
  BEGIN
    PERFORM public.admit_ai_session_generation(v_user_a, v_row.request_id, v_session, 1, 'ideas:fp-DIFFERENT');
    RAISE EXCEPTION 'EXPLOIT: replaying the same request_id with a different fingerprint was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 5: a stale expected_revision is rejected before quota is
  -- touched.
  BEGIN
    PERFORM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 999, 'ideas:fp-stale');
    RAISE EXCEPTION 'EXPLOIT: a stale expected_revision was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'admit_ai_session_generation contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_admit_contracts.sql
```

Expected: `function public.admit_ai_session_generation(...) does not exist`

- [ ] **Step 3: Write the RPC**

Create `supabase/migrations/20260953050000_ai_session_admit_rpc.sql`:

```sql
-- admit_ai_session_generation: the full spec §6.2 admission sequence,
-- steps 1-5. Lock order: relationship advisory lock, THEN
-- reserve_ai_assistant_quota's own internal per-user quota advisory
-- lock (unchanged from Plan A), THEN the session row lock (FOR UPDATE)
-- -- this exact order matters because reserve_ai_assistant_quota is
-- called from inside this function's own transaction, and its lock
-- must be acquired before this function's own session-row lock to
-- match the Global Constraints' fixed ordering.
CREATE OR REPLACE FUNCTION public.admit_ai_session_generation(
  p_actor_id uuid,
  p_request_id uuid,
  p_session_id uuid,
  p_expected_revision int,
  p_operation_fingerprint text
) RETURNS TABLE (
  outcome text, request_id uuid, attempt_n int,
  worker_token uuid, lease_deadline timestamptz, retry_after_seconds int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_existing public.ai_session_requests;
  v_quota record;
  v_next_attempt smallint;
  v_new_request_id uuid;
  v_worker_token uuid;
  v_deadline timestamptz;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Step 2 (idempotency), checked BEFORE the relationship lock so a
  -- replay never contends for the lock at all.
  SELECT * INTO v_existing FROM public.ai_session_requests WHERE id = p_request_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.session_id != p_session_id
       OR v_existing.actor_id != p_actor_id
       OR v_existing.operation_fingerprint != p_operation_fingerprint THEN
      RETURN QUERY SELECT 'conflict'::text, NULL::uuid, NULL::int, NULL::uuid, NULL::timestamptz, NULL::int;
      RETURN;
    END IF;
    RETURN QUERY SELECT 'already_admitted'::text, v_existing.id, v_existing.attempt_n::int,
      v_existing.worker_token, v_existing.lease_deadline, NULL::int;
    RETURN;
  END IF;

  SELECT r.relationship_id INTO STRICT v_session
  FROM public.ai_sessions r WHERE r.id = p_session_id;
  -- (v_session is typed ai_sessions above via SELECT * below; this
  -- STRICT probe only exists to raise NO_DATA_FOUND cleanly if the
  -- session id is entirely bogus before taking any lock.)

  PERFORM pg_advisory_xact_lock(hashtext((SELECT relationship_id FROM public.ai_sessions WHERE id = p_session_id)::text));

  -- Step 1: recheck eligibility/revision/frozen sources/approvals
  -- under the session row lock.
  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL OR v_session.state != 'active' THEN
    RAISE EXCEPTION 'UNAVAILABLE';
  END IF;
  IF v_session.revision != p_expected_revision THEN
    RAISE EXCEPTION 'CONTEXT_CHANGED';
  END IF;
  IF v_session.expires_at IS NOT NULL AND v_session.expires_at <= now() THEN
    RAISE EXCEPTION 'UNAVAILABLE';
  END IF;

  -- Step 3: one in-flight attempt per session; count cap.
  IF EXISTS (
    SELECT 1 FROM public.ai_session_requests
    WHERE session_id = p_session_id AND state IN ('reserved', 'started')
  ) THEN
    RETURN QUERY SELECT 'busy'::text, NULL::uuid, NULL::int, NULL::uuid, NULL::timestamptz, NULL::int;
    RETURN;
  END IF;
  IF v_session.attempt_count >= 10 THEN
    RETURN QUERY SELECT 'limit_reached'::text, NULL::uuid, NULL::int, NULL::uuid, NULL::timestamptz, NULL::int;
    RETURN;
  END IF;

  -- Step 4: reserve global quota (mode='session' -- Plan A Task 1) and
  -- the session attempt slot together.
  SELECT * INTO v_quota FROM public.reserve_ai_assistant_quota(
    p_actor_id, p_request_id, v_session.relationship_id, 'session'
  );
  IF v_quota.outcome = 'rate_limited' THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, NULL::int, NULL::uuid, NULL::timestamptz, v_quota.retry_after_seconds;
    RETURN;
  END IF;
  IF v_quota.outcome != 'reserved' THEN
    RAISE EXCEPTION 'Unexpected quota outcome: %', v_quota.outcome;
  END IF;

  v_next_attempt := v_session.attempt_count + 1;
  v_new_request_id := p_request_id;
  v_worker_token := gen_random_uuid();
  v_deadline := now() + interval '35 seconds';

  UPDATE public.ai_sessions
  SET attempt_count = v_next_attempt, last_admitted_at = now()
  WHERE id = p_session_id;

  -- Step 5: create the request row.
  INSERT INTO public.ai_session_requests (
    id, session_id, actor_id, attempt_n, operation_fingerprint,
    worker_token, generation_epoch, lease_deadline, state
  ) VALUES (
    v_new_request_id, p_session_id, p_actor_id, v_next_attempt, p_operation_fingerprint,
    v_worker_token, v_session.generation_epoch, v_deadline, 'reserved'
  );

  RETURN QUERY SELECT 'admitted'::text, v_new_request_id, v_next_attempt::int, v_worker_token, v_deadline, NULL::int;
END;
$$;
REVOKE ALL ON FUNCTION public.admit_ai_session_generation(uuid, uuid, uuid, int, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admit_ai_session_generation(uuid, uuid, uuid, int, text)
  TO service_role;
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953050000_ai_session_admit_rpc.sql
psql -q -d attune_test -f supabase/tests/ai_session_admit_contracts.sql
```

Expected: `NOTICE: admit_ai_session_generation contracts: all held`

- [ ] **Step 5: Write the concurrency script (spec §11 item 1, §6.2's count-8/9/10 scenario)**

Create `supabase/tests/ai_session_admit_concurrent_test.sh`:

```bash
#!/usr/bin/env bash
# At attempt_count=9, two concurrent distinct admissions: exactly one
# must reach attempt_n=10; the other must get 'busy' or 'limit_reached',
# never attempt_n=11. Spec §6.2, §11 item 1.
set -euo pipefail

REL="b1000000-0000-0000-0000-000000000006"
USER_A="b1000000-0000-0000-0000-00000000005a"

SETUP=$(psql -q -d attune_test -t -A <<SQL
INSERT INTO auth.users (id, email) VALUES ('$USER_A', 'race9_a@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$USER_A', '+15550013001', 'A') ON CONFLICT DO NOTHING;
INSERT INTO public.relationships (id, user_a, status) VALUES ('$REL', '$USER_A', 'active') ON CONFLICT DO NOTHING;
SELECT session_id FROM public.prepare_ai_session('$USER_A', gen_random_uuid(), '$REL', 'ideas', 'private', NULL, false);
SQL
)
SESSION=$(echo "$SETUP" | tail -n1)

psql -q -d attune_test <<SQL
SELECT public.approve_ai_session_context('$USER_A', '$SESSION', 1, 'd', 'v1');
SELECT public.activate_ai_session('$USER_A', '$SESSION', 1);
-- Fast-forward to attempt_count=9 by admitting and immediately
-- completing 9 attempts as terminal (state='failed'), so the "one
-- in-flight attempt" check does not block the next admission -- this
-- test is about the ATTEMPT COUNT boundary, not the in-flight check
-- (that is Contract 2 in the sequential test above).
DO \$\$
DECLARE v_req uuid; v_i int;
BEGIN
  FOR v_i IN 1..9 LOOP
    SELECT request_id INTO v_req FROM public.admit_ai_session_generation(
      '$USER_A', gen_random_uuid(), '$SESSION', 1, 'ideas:fp-' || v_i
    );
    UPDATE public.ai_session_requests SET state = 'failed' WHERE id = v_req;
  END LOOP;
END \$\$;
SQL

# Two concurrent admissions from separate connections, both at
# attempt_count=9.
RESULTS_DIR=$(mktemp -d)
for i in 1 2; do
  psql -q -d attune_test -t -A -c \
    "SELECT outcome, attempt_n FROM public.admit_ai_session_generation('$USER_A', gen_random_uuid(), '$SESSION', 1, 'ideas:race-$i');" \
    > "$RESULTS_DIR/result_$i.txt" &
done
wait

ADMITTED_10_COUNT=$(grep -c '^admitted|10$' "$RESULTS_DIR"/result_*.txt || true)
OTHER_OUTCOME=$(grep -vc '^admitted|10$' "$RESULTS_DIR"/result_*.txt || true)
cat "$RESULTS_DIR"/result_*.txt
rm -rf "$RESULTS_DIR"

if [ "$ADMITTED_10_COUNT" != "1" ]; then
  echo "EXPLOIT: expected exactly 1 of 2 concurrent admissions at count=9 to reach attempt_n=10, got $ADMITTED_10_COUNT"
  exit 1
fi

FINAL_COUNT=$(psql -q -d attune_test -t -A -c "SELECT attempt_count FROM public.ai_sessions WHERE id = '$SESSION';")
if [ "$FINAL_COUNT" != "10" ]; then
  echo "EXPLOIT: final attempt_count should be exactly 10, got $FINAL_COUNT"
  exit 1
fi

echo "concurrent admission at count=9: exactly one reached attempt_n=10, final count=10"
```

- [ ] **Step 6: Run it to confirm it passes, then 5 times to rule out flakiness**

```bash
chmod +x supabase/tests/ai_session_admit_concurrent_test.sh
for i in 1 2 3 4 5; do
  bash scripts/local_pg_setup.sh
  ./supabase/tests/ai_session_admit_concurrent_test.sh || echo "FAILED on run $i"
done
```

Expected: 5 consecutive passes.

- [ ] **Step 7: Rebuild `attune_test` from scratch and run every contract test so far**

```bash
bash scripts/local_pg_setup.sh
for f in supabase/tests/ai_assistant_quota_contracts.sql \
         supabase/tests/ai_assistant_provider_start_marker_contracts.sql \
         supabase/tests/ai_assistant_quota_release_contracts.sql \
         supabase/tests/ai_sessions_schema_contracts.sql \
         supabase/tests/ai_session_requests_turns_contracts.sql \
         supabase/tests/ai_session_prepare_contracts.sql \
         supabase/tests/ai_session_approve_activate_contracts.sql \
         supabase/tests/ai_session_admit_contracts.sql; do
  echo "=== $f ==="
  psql -q -d attune_test -f "$f"
done
```

Expected: every file prints its own `all held` NOTICE.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260953050000_ai_session_admit_rpc.sql \
        supabase/tests/ai_session_admit_contracts.sql \
        supabase/tests/ai_session_admit_concurrent_test.sh
git commit -m "feat(ai-sessions): add admit_ai_session_generation implementing the §6.2 admission sequence"
```

---

### Task 6: `claim_ai_session_dispatch` and lease reconciliation helper

**Files:**
- Create: `supabase/migrations/20260953060000_ai_session_dispatch_claim_rpc.sql`
- Test: `supabase/tests/ai_session_dispatch_claim_contracts.sql`

**Interfaces:**
- Consumes: `ai_session_requests` (Task 2), `admit_ai_session_generation`
  (Task 5).
- Produces: `claim_ai_session_dispatch(p_worker_token uuid, p_request_id uuid) RETURNS boolean`
  — the session-specific analog of Plan A's
  `claim_ai_assistant_provider_start`, but keyed on the request's own
  `worker_token` (not `p_actor_id`) since dispatch happens inside Plan
  C's edge function holding that exact token from admission, not a
  fresh JWT-derived identity check. Sets `ai_session_requests.state =
  'started'` and `provider_started_at`. Returns `false` if the token
  doesn't match, the request is already `started`/terminal, or the
  lease has expired (`lease_deadline < now()`) — in the lease-expired
  case, ALSO transitions the request to `'failed'` with
  `terminal_code = 'LEASE_EXPIRED'` and releases quota via Plan A's
  `release_ai_assistant_quota_reservation` if that request's own quota
  reservation never itself got a provider-start marker (mirroring Plan
  A Task 2/4's exactly-once release rule at the session-request level).
- Produces: `reconcile_ai_session_leases() RETURNS int` (returns count of
  requests reconciled) — the every-minute sweep Task 11 schedules,
  reusable directly from this task's own test.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_dispatch_claim_contracts.sql`:

```sql
-- claim_ai_session_dispatch / reconcile_ai_session_leases. Spec §6.2, §8.2.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_dispatch_claim_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000007';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000006a';
  v_session uuid;
  v_admit record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'claim_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550014001', 'A') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel, v_user_a, 'active') ON CONFLICT DO NOTHING;

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp');

  -- Contract 1: the matching worker_token claims successfully.
  IF public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: the correct worker_token failed to claim dispatch';
  END IF;
  IF (SELECT state FROM public.ai_session_requests WHERE id = v_admit.request_id) != 'started' THEN
    RAISE EXCEPTION 'EXPLOIT: request state did not advance to started after a successful claim';
  END IF;

  -- Contract 2: a WRONG worker_token cannot claim the same request.
  IF public.claim_ai_session_dispatch(gen_random_uuid(), v_admit.request_id) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: a mismatched worker_token was allowed to claim dispatch';
  END IF;

  -- Contract 3: a second claim with the CORRECT token (retry after a
  -- lost HTTP response) returns false, not a second dispatch.
  IF public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: the same worker_token claimed dispatch twice';
  END IF;

  -- Contract 4: an EXPIRED lease is reconciled to failed and its
  -- request is fenced from further claims.
  DECLARE
    v_admit2 record;
  BEGIN
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp-2');
    UPDATE public.ai_session_requests SET lease_deadline = now() - interval '1 second' WHERE id = v_admit2.request_id;
    PERFORM public.reconcile_ai_session_leases();
    IF (SELECT state FROM public.ai_session_requests WHERE id = v_admit2.request_id) != 'failed' THEN
      RAISE EXCEPTION 'EXPLOIT: an expired lease was not reconciled to failed';
    END IF;
    IF public.claim_ai_session_dispatch(v_admit2.worker_token, v_admit2.request_id) IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'EXPLOIT: a reconciled (failed) request still allowed a dispatch claim';
    END IF;
  END;

  RAISE NOTICE 'dispatch claim / reconcile contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_dispatch_claim_contracts.sql
```

Expected: `function public.claim_ai_session_dispatch(...) does not exist`

- [ ] **Step 3: Write the RPCs**

Create `supabase/migrations/20260953060000_ai_session_dispatch_claim_rpc.sql`:

```sql
-- claim_ai_session_dispatch / reconcile_ai_session_leases. Spec §6.2, §8.2.2.
CREATE OR REPLACE FUNCTION public.claim_ai_session_dispatch(
  p_worker_token uuid, p_request_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claimed boolean;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.ai_session_requests
    WHERE id = p_request_id AND worker_token = p_worker_token
      AND state = 'reserved' AND lease_deadline > now()
  ) THEN
    UPDATE public.ai_session_requests
    SET state = 'started', provider_started_at = now()
    WHERE id = p_request_id AND worker_token = p_worker_token AND state = 'reserved';
    v_claimed := FOUND;
  ELSE
    v_claimed := false;
  END IF;
  RETURN v_claimed;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_ai_session_dispatch(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ai_session_dispatch(uuid, uuid)
  TO service_role;

-- Sweeps requests whose lease has expired without a completion. A
-- request still in 'reserved' (never dispatched) releases its quota
-- reservation exactly once via Plan A's release RPC, since no
-- provider-start marker was ever set for it (mirrors the guard inside
-- release_ai_assistant_quota_reservation itself -- calling it on an
-- already-started reservation raises, so this function must only call
-- it for the 'reserved' branch below). A request already 'started'
-- (provider call in flight or its result unknown) is left counted, per
-- spec §8.2.2's compensation table -- reconciliation marks it 'failed'
-- for the SESSION's own bookkeeping (so a new attempt can be admitted)
-- without touching its ALREADY-PERMANENT quota consumption.
CREATE OR REPLACE FUNCTION public.reconcile_ai_session_leases()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.ai_session_requests;
  v_count int := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM public.ai_session_requests
    WHERE state IN ('reserved', 'started') AND lease_deadline < now()
    FOR UPDATE
  LOOP
    UPDATE public.ai_session_requests
    SET state = 'failed', terminal_code = 'LEASE_EXPIRED'
    WHERE id = v_row.id;

    IF v_row.state = 'reserved' THEN
      PERFORM public.release_ai_assistant_quota_reservation(v_row.actor_id, v_row.id);
    END IF;

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_ai_session_leases()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_ai_session_leases()
  TO service_role;
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953060000_ai_session_dispatch_claim_rpc.sql
psql -q -d attune_test -f supabase/tests/ai_session_dispatch_claim_contracts.sql
```

Expected: `NOTICE: dispatch claim / reconcile contracts: all held`

**Note on Contract 4's `v_row.id` vs `request_id`:** `release_ai_assistant_quota_reservation`
takes `(p_actor_id, p_request_id)` where `p_request_id` matches
`ai_assistant_usage.request_id` — Task 5's `admit_ai_session_generation`
reserves quota with `p_request_id := p_request_id` (the SAME UUID as
`ai_session_requests.id`), so `v_row.id` here is correct. If a future
change ever makes `ai_session_requests.id` diverge from the quota
ledger's `request_id`, this call breaks silently (it would raise
"Reservation not found for this actor" instead) — confirm this identity
holds by reading Task 5's `admit_ai_session_generation` body before
touching either table's primary key shape.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260953060000_ai_session_dispatch_claim_rpc.sql \
        supabase/tests/ai_session_dispatch_claim_contracts.sql
git commit -m "feat(ai-sessions): add claim_ai_session_dispatch and reconcile_ai_session_leases"
```

---

### Task 7: `commit_ai_session_ideas_turn` — atomic Ideas completion

**Files:**
- Create: `supabase/migrations/20260953070000_ai_session_commit_ideas_rpc.sql`
- Test: `supabase/tests/ai_session_commit_ideas_contracts.sql`

**Interfaces:**
- Consumes: `ai_session_requests`/`ai_session_turns` (Task 2),
  `claim_ai_session_dispatch` (Task 6).
- Produces: `commit_ai_session_ideas_turn(p_worker_token uuid, p_request_id uuid, p_reply_text text, p_proposal jsonb) RETURNS TABLE (committed boolean, user_ordinal int, attune_ordinal int)`
  — inserts BOTH the user turn (from the request's own stored
  instruction — wait, per Global Constraints "No raw pending instruction
  ... is not stored for job resumption" (spec §6.2 step 5), so the user
  turn's content must be supplied fresh by the caller at commit time,
  not read back from a stored column. Revise: this RPC takes
  `p_user_instruction text` as well, supplied by Plan C's edge function
  from the SAME in-memory request object it validated at admission time
  — never re-read from storage, since none is kept. Marks the request
  `committed`, advances `ai_sessions.revision`, and is idempotent on
  retry (a duplicate completion for an already-committed request
  returns the same ordinals, no second insert).

**Correction applied to the interface above before writing code**: add
`p_user_instruction text` as a required parameter.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_commit_ideas_contracts.sql`:

```sql
-- commit_ai_session_ideas_turn: atomic two-row insert with correct
-- ordinal parity, idempotent on retry. Spec §6.2 step 5, §7.1.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_commit_ideas_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000008';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000007a';
  v_session uuid;
  v_admit record;
  v_row record;
  v_row2 record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'commit_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550015001', 'A') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel, v_user_a, 'active') ON CONFLICT DO NOTHING;

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp');
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);

  -- Contract 1: attempt_n=1 -> ordinals (1, 2).
  SELECT * INTO v_row FROM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'brainstorm date ideas', 'a great reply', NULL
  );
  IF v_row.committed IS DISTINCT FROM true OR v_row.user_ordinal != 1 OR v_row.attune_ordinal != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: attempt_n=1 did not produce ordinals (1,2), got committed=% user=% attune=%',
      v_row.committed, v_row.user_ordinal, v_row.attune_ordinal;
  END IF;
  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly 2 turn rows after one committed attempt';
  END IF;
  IF (SELECT role FROM public.ai_session_turns WHERE session_id = v_session AND ordinal = 1) != 'user' THEN
    RAISE EXCEPTION 'EXPLOIT: ordinal 1 is not role=user';
  END IF;
  IF (SELECT role FROM public.ai_session_turns WHERE session_id = v_session AND ordinal = 2) != 'attune' THEN
    RAISE EXCEPTION 'EXPLOIT: ordinal 2 is not role=attune';
  END IF;

  -- Contract 2: retrying the SAME request_id (lost HTTP response) is
  -- idempotent -- same ordinals, no second insert.
  SELECT * INTO v_row2 FROM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'brainstorm date ideas', 'a great reply', NULL
  );
  IF v_row2.user_ordinal != v_row.user_ordinal OR v_row2.attune_ordinal != v_row.attune_ordinal THEN
    RAISE EXCEPTION 'EXPLOIT: retrying a committed request produced different ordinals';
  END IF;
  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: retrying a committed request inserted duplicate turn rows';
  END IF;

  -- Contract 3: a second attempt (attempt_n=2) -> ordinals (3, 4).
  DECLARE
    v_admit2 record;
    v_row3 record;
  BEGIN
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp-2');
    PERFORM public.claim_ai_session_dispatch(v_admit2.worker_token, v_admit2.request_id);
    SELECT * INTO v_row3 FROM public.commit_ai_session_ideas_turn(
      v_admit2.worker_token, v_admit2.request_id, 'a second instruction', 'a second reply', NULL
    );
    IF v_row3.user_ordinal != 3 OR v_row3.attune_ordinal != 4 THEN
      RAISE EXCEPTION 'EXPLOIT: attempt_n=2 did not produce ordinals (3,4), got user=% attune=%', v_row3.user_ordinal, v_row3.attune_ordinal;
    END IF;
  END;

  RAISE NOTICE 'commit_ai_session_ideas_turn contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_commit_ideas_contracts.sql
```

Expected: `function public.commit_ai_session_ideas_turn(...) does not exist`

- [ ] **Step 3: Write the RPC**

Create `supabase/migrations/20260953070000_ai_session_commit_ideas_rpc.sql`:

```sql
-- commit_ai_session_ideas_turn: atomic two-row (user, attune) insert
-- at the correct ordinal pair for this request's own attempt_n. Spec
-- §6.2 step 5, §7.1's "Both rows committed atomically."
--
-- p_proposal is the validated suggested_planning_item jsonb (or NULL) --
-- this RPC does not itself validate the OUTPUT SHAPE (kind/title/
-- event_date bounds); that is Plan C's edge-function-side validation,
-- run on the model's raw output BEFORE this RPC is ever called. This
-- RPC's own job is atomicity and ordinal correctness, not schema
-- validation of content it receives.
CREATE OR REPLACE FUNCTION public.commit_ai_session_ideas_turn(
  p_worker_token uuid,
  p_request_id uuid,
  p_user_instruction text,
  p_reply_text text,
  p_proposal jsonb
) RETURNS TABLE (committed boolean, user_ordinal int, attune_ordinal int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.ai_session_requests;
  v_user_ord smallint;
  v_attune_ord smallint;
BEGIN
  SELECT * INTO v_request FROM public.ai_session_requests
  WHERE id = p_request_id AND worker_token = p_worker_token
  FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found for this worker token';
  END IF;

  v_user_ord := (v_request.attempt_n * 2) - 1;
  v_attune_ord := v_request.attempt_n * 2;

  IF v_request.state = 'committed' THEN
    -- Idempotent replay: return the same ordinals, insert nothing.
    RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
    RETURN;
  END IF;
  IF v_request.state != 'started' THEN
    RAISE EXCEPTION 'Request is not in a committable state: %', v_request.state;
  END IF;

  INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
  VALUES
    (v_request.session_id, p_request_id, v_user_ord, 'user', v_request.actor_id, 'ideas_answer',
     jsonb_build_object('instruction', p_user_instruction)),
    (v_request.session_id, p_request_id, v_attune_ord, 'attune', NULL, 'ideas_answer',
     jsonb_build_object('reply_text', p_reply_text, 'suggested_planning_item', p_proposal));

  UPDATE public.ai_session_requests SET state = 'committed' WHERE id = p_request_id;
  UPDATE public.ai_sessions SET revision = revision + 1 WHERE id = v_request.session_id;

  PERFORM public.mark_ai_assistant_usage_outcome(v_request.actor_id, p_request_id, 'succeeded', 1::smallint);

  RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
END;
$$;
REVOKE ALL ON FUNCTION public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)
  TO service_role;
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953070000_ai_session_commit_ideas_rpc.sql
psql -q -d attune_test -f supabase/tests/ai_session_commit_ideas_contracts.sql
```

Expected: `NOTICE: commit_ai_session_ideas_turn contracts: all held`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260953070000_ai_session_commit_ideas_rpc.sql \
        supabase/tests/ai_session_commit_ideas_contracts.sql
git commit -m "feat(ai-sessions): add commit_ai_session_ideas_turn, atomic completion for Ideas"
```

---

### Task 8: Nearby staging, publish, and discard RPCs

**Files:**
- Create: `supabase/migrations/20260953080000_ai_session_nearby_staging_rpcs.sql`
- Test: `supabase/tests/ai_session_nearby_staging_contracts.sql`

**Interfaces:**
- Consumes: `ai_session_staging` (Task 2), `claim_ai_session_dispatch`
  (Task 6).
- Produces: `stage_ai_session_nearby_result(p_worker_token uuid, p_request_id uuid, p_reply_text text, p_sources jsonb) RETURNS void`
  — writes the requester-only staging row with a 2-minute (or session-
  expiry, whichever sooner) expiry; marks the request `staged`, NOT
  `committed` (Nearby is never committed directly — only publication or
  discard resolves a staged request).
- Produces: `publish_ai_session_nearby_result(p_actor_id uuid, p_request_id uuid) RETURNS TABLE (committed boolean, user_ordinal int, attune_ordinal int)`
  — requester-only (spec §6.1: "requester confirms disclosure"); moves
  the staged pair into `ai_session_turns` at the correct ordinal pair,
  deletes the staging row, marks the request `committed`. Idempotent.
- Produces: `discard_ai_session_nearby_staging(p_actor_id uuid, p_request_id uuid) RETURNS void`
  — deletes the staging row, marks the request `cancelled`, and (since
  a discard happens strictly after a provider call already succeeded —
  the marker was set at dispatch — this is a "counted, terminal, no
  partner pair" outcome per spec §8.2.2's row "Staging expires/
  discarded", NOT a quota release; do not call
  `release_ai_assistant_quota_reservation` here, since
  `provider_started_at` is already set for this request by the time
  staging exists at all).

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_nearby_staging_contracts.sql`:

```sql
-- Nearby staging: stage -> publish (or discard). Requester-only
-- publish; discard never refunds quota. Spec §6.1, §7.1, §8.2.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_nearby_staging_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000009';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000008a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000008b';
  v_session uuid;
  v_admit record;
  v_row record;
  v_usage_before record;
  v_usage_after record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'stage_a@t.test'), (v_user_b, 'stage_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550016001', 'A'), (v_user_b, '+15550016002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'nearby', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'nearby:fp');
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);

  -- Contract 1: staging succeeds; no turn rows exist yet.
  PERFORM public.stage_ai_session_nearby_result(
    v_admit.worker_token, v_admit.request_id, 'three places nearby', '[]'::jsonb
  );
  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 0 THEN
    RAISE EXCEPTION 'EXPLOIT: staging inserted turn rows before publication';
  END IF;
  IF (SELECT state FROM public.ai_session_requests WHERE id = v_admit.request_id) != 'staged' THEN
    RAISE EXCEPTION 'EXPLOIT: request state did not advance to staged';
  END IF;

  -- Contract 2: the PARTNER cannot publish someone else's staged Nearby
  -- result (spec §6.1: only the requester may disclose).
  BEGIN
    PERFORM public.publish_ai_session_nearby_result(v_user_b, v_admit.request_id);
    RAISE EXCEPTION 'EXPLOIT: the non-requester partner published a staged Nearby result';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 3: the requester publishes successfully -> exactly 2 turn
  -- rows at ordinals (1,2), staging row removed.
  SELECT * INTO v_row FROM public.publish_ai_session_nearby_result(v_user_a, v_admit.request_id);
  IF v_row.committed IS DISTINCT FROM true OR v_row.user_ordinal != 1 OR v_row.attune_ordinal != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: publish did not produce ordinals (1,2)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_staging WHERE request_id = v_admit.request_id) THEN
    RAISE EXCEPTION 'EXPLOIT: staging row survived publication';
  END IF;

  -- Contract 4: discard never refunds quota -- attempt an admission,
  -- stage, discard, and confirm the reservation is still counted
  -- (outcome NOT 'cancelled'/'rejected').
  DECLARE
    v_admit2 record;
  BEGIN
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'nearby:fp-2');
    PERFORM public.claim_ai_session_dispatch(v_admit2.worker_token, v_admit2.request_id);
    PERFORM public.stage_ai_session_nearby_result(v_admit2.worker_token, v_admit2.request_id, 'more places', '[]'::jsonb);
    PERFORM public.discard_ai_session_nearby_staging(v_user_a, v_admit2.request_id);
    SELECT outcome INTO v_usage_after FROM public.ai_assistant_usage WHERE request_id = v_admit2.request_id;
    IF (v_usage_after).outcome IN ('rejected', 'cancelled') THEN
      RAISE EXCEPTION 'EXPLOIT: discarding a staged Nearby result refunded its already-started quota reservation';
    END IF;
  END;

  RAISE NOTICE 'Nearby staging/publish/discard contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_nearby_staging_contracts.sql
```

Expected: `function public.stage_ai_session_nearby_result(...) does not exist`

- [ ] **Step 3: Write the RPCs**

Create `supabase/migrations/20260953080000_ai_session_nearby_staging_rpcs.sql`:

```sql
-- Nearby staging/publish/discard. Spec §6.1, §7.1, §8.2.2.
CREATE OR REPLACE FUNCTION public.stage_ai_session_nearby_result(
  p_worker_token uuid, p_request_id uuid, p_reply_text text, p_sources jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.ai_session_requests;
  v_session_expiry timestamptz;
BEGIN
  SELECT * INTO v_request FROM public.ai_session_requests
  WHERE id = p_request_id AND worker_token = p_worker_token
  FOR UPDATE;
  IF v_request.id IS NULL OR v_request.state != 'started' THEN
    RAISE EXCEPTION 'Request not found or not in a stageable state';
  END IF;

  SELECT expires_at INTO v_session_expiry FROM public.ai_sessions WHERE id = v_request.session_id;

  INSERT INTO public.ai_session_staging (session_id, request_id, requester_id, reply_text, sources, expires_at)
  VALUES (
    v_request.session_id, p_request_id, v_request.actor_id, p_reply_text, p_sources,
    LEAST(now() + interval '2 minutes', COALESCE(v_session_expiry, now() + interval '2 minutes'))
  )
  ON CONFLICT (session_id, request_id) DO NOTHING;

  UPDATE public.ai_session_requests SET state = 'staged' WHERE id = p_request_id;
END;
$$;
REVOKE ALL ON FUNCTION public.stage_ai_session_nearby_result(uuid, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stage_ai_session_nearby_result(uuid, uuid, text, jsonb)
  TO service_role;

CREATE OR REPLACE FUNCTION public.publish_ai_session_nearby_result(
  p_actor_id uuid, p_request_id uuid
) RETURNS TABLE (committed boolean, user_ordinal int, attune_ordinal int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.ai_session_requests;
  v_staging public.ai_session_staging;
  v_user_ord smallint;
  v_attune_ord smallint;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_request FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  v_user_ord := (v_request.attempt_n * 2) - 1;
  v_attune_ord := v_request.attempt_n * 2;

  IF v_request.state = 'committed' THEN
    RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
    RETURN;
  END IF;

  SELECT * INTO v_staging FROM public.ai_session_staging
  WHERE request_id = p_request_id;
  IF v_staging.request_id IS NULL THEN
    RAISE EXCEPTION 'No staged result for this request';
  END IF;
  IF v_staging.requester_id != p_actor_id THEN
    RAISE EXCEPTION 'Only the requester may publish a staged Nearby result';
  END IF;
  IF v_staging.expires_at <= now() THEN
    RAISE EXCEPTION 'Staged result has expired';
  END IF;

  INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
  VALUES
    (v_request.session_id, p_request_id, v_user_ord, 'user', v_request.actor_id, 'nearby_result',
     jsonb_build_object('instruction', 'nearby')),
    (v_request.session_id, p_request_id, v_attune_ord, 'attune', NULL, 'nearby_result',
     jsonb_build_object('reply_text', v_staging.reply_text, 'sources', v_staging.sources));

  DELETE FROM public.ai_session_staging WHERE request_id = p_request_id;
  UPDATE public.ai_session_requests SET state = 'committed' WHERE id = p_request_id;
  UPDATE public.ai_sessions SET revision = revision + 1 WHERE id = v_request.session_id;
  PERFORM public.mark_ai_assistant_usage_outcome(v_request.actor_id, p_request_id, 'succeeded', 2::smallint);

  RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
END;
$$;
REVOKE ALL ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.discard_ai_session_nearby_staging(
  p_actor_id uuid, p_request_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid;
BEGIN
  SELECT requester_id INTO v_actor FROM public.ai_session_staging WHERE request_id = p_request_id;
  IF v_actor IS NULL THEN
    RETURN; -- already discarded/published/expired -- idempotent no-op
  END IF;
  IF v_actor != p_actor_id THEN
    RAISE EXCEPTION 'Only the requester may discard their own staged result';
  END IF;

  DELETE FROM public.ai_session_staging WHERE request_id = p_request_id;
  -- Terminal, counted, no partner pair (spec §8.2.2) -- NOT a quota
  -- release. provider_started_at is already set for this request (it
  -- reached 'staged' only via claim_ai_session_dispatch), so this
  -- outcome must remain a counted terminal state, never 'cancelled'/
  -- 'rejected'.
  UPDATE public.ai_session_requests SET state = 'cancelled' WHERE id = p_request_id;
  PERFORM public.mark_ai_assistant_usage_outcome(p_actor_id, p_request_id, 'succeeded', 2::smallint);
END;
$$;
REVOKE ALL ON FUNCTION public.discard_ai_session_nearby_staging(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.discard_ai_session_nearby_staging(uuid, uuid)
  TO service_role;
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953080000_ai_session_nearby_staging_rpcs.sql
psql -q -d attune_test -f supabase/tests/ai_session_nearby_staging_contracts.sql
```

Expected: `NOTICE: Nearby staging/publish/discard contracts: all held`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260953080000_ai_session_nearby_staging_rpcs.sql \
        supabase/tests/ai_session_nearby_staging_contracts.sql
git commit -m "feat(ai-sessions): add Nearby stage/publish/discard RPCs with requester-only publication"
```

---

### Task 9: `end_ai_session` and `share_ai_session_turn`

**Files:**
- Create: `supabase/migrations/20260953090000_ai_session_end_share_rpcs.sql`
- Test: `supabase/tests/ai_session_end_share_contracts.sql`

**Interfaces:**
- Consumes: `ai_sessions`, `ai_session_turns` (Tasks 1-2).
- Produces: `end_ai_session(p_actor_id uuid, p_session_id uuid) RETURNS void`
  — either creator (private) or either current member (shared) may
  call; transitions to `closed`, synchronously deletes
  `ai_session_turns`/`ai_session_sources`/`ai_session_approvals`/
  `ai_session_staging` rows for this session in the SAME transaction
  (spec §5.4), increments `generation_epoch` to fence any in-flight
  worker. No actor recorded. Idempotent (ending an already-closed
  session is a no-op).
- Produces: `share_ai_session_turn(p_actor_id uuid, p_session_id uuid, p_ordinal int) RETURNS public.messages`
  — validates the turn at `p_ordinal` is `role = 'attune'`, `kind =
  'ideas_answer'` (never `'redirect'` — spec §8.1: "Redirects cannot be
  posted" — and never `'nearby_result'` here, since Nearby's own posting
  path is the requester-only rule this task's test also proves; a
  generic share RPC that allowed Nearby posting by anyone would
  contradict "only originating requester may post a Nearby card even
  after it was published in a shared session"), then delegates to Plan
  A's existing `insert_ai_assist_draft` + `share_ai_assist_draft` two-
  step exactly as today's long-press Assist flow does — **this task
  does not reimplement message insertion**, it only adapts the existing
  draft/share pipeline to a session-turn source instead of a message-
  target source, per spec §8.1: "Adapt the existing draft/share
  integration explicitly to session-answer origin; do not pretend a
  selected-message-based call already accepts a session answer."

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_end_share_contracts.sql`:

```sql
-- end_ai_session (synchronous content purge, either-partner-ends) and
-- share_ai_session_turn (adapts the existing draft/share pipeline).
-- Spec §5.4, §8.1.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_end_share_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-00000000000a';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000009a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000009b';
  v_session uuid;
  v_admit record;
  v_message public.messages;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'end_a@t.test'), (v_user_b, 'end_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550017001', 'A'), (v_user_b, '+15550017002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events (relationship_id, user_id, policy_version, action, idempotency_key)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid());

  -- End: shared, either partner ends, content purges synchronously.
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp');
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(v_admit.worker_token, v_admit.request_id, 'an idea', 'a reply', NULL);

  -- The PARTNER (not the creator) ends it.
  PERFORM public.end_ai_session(v_user_b, v_session);
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: end_ai_session by the non-creator partner did not close the session';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: turn content survived end_ai_session -- must purge synchronously';
  END IF;

  -- Ending an already-closed session is a no-op, not an error.
  PERFORM public.end_ai_session(v_user_a, v_session);

  -- Share: a fresh session, commit a turn, share it -> a real message.
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp2');
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(v_admit.worker_token, v_admit.request_id, 'an idea', 'share this reply', NULL);

  v_message := public.share_ai_session_turn(v_user_a, v_session, 2);
  IF v_message.content IS DISTINCT FROM 'share this reply' THEN
    RAISE EXCEPTION 'EXPLOIT: shared message content does not match the committed Attune turn';
  END IF;
  IF v_message.message_origin IS DISTINCT FROM 'attune_assist' THEN
    RAISE EXCEPTION 'EXPLOIT: shared message did not carry attune_assist provenance';
  END IF;
  IF (SELECT count(*) FROM public.ai_session_publications WHERE session_id = v_session) != 1 THEN
    RAISE EXCEPTION 'EXPLOIT: no publication mapping row was created';
  END IF;

  -- Sharing a USER-role ordinal (1, not 2) must be rejected.
  DECLARE
    v_session2 uuid;
    v_admit2 record;
  BEGIN
    SELECT session_id INTO v_session2 FROM public.prepare_ai_session(
      v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
    );
    PERFORM public.approve_ai_session_context(v_user_a, v_session2, 1, 'd', 'v1');
    PERFORM public.activate_ai_session(v_user_a, v_session2, 1);
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session2, 1, 'ideas:fp3');
    PERFORM public.claim_ai_session_dispatch(v_admit2.worker_token, v_admit2.request_id);
    PERFORM public.commit_ai_session_ideas_turn(v_admit2.worker_token, v_admit2.request_id, 'another idea', 'another reply', NULL);
    BEGIN
      PERFORM public.share_ai_session_turn(v_user_a, v_session2, 1);
      RAISE EXCEPTION 'EXPLOIT: a user-authored turn (ordinal 1) was shared as if it were an Attune answer';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  RAISE NOTICE 'end_ai_session / share_ai_session_turn contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_end_share_contracts.sql
```

Expected: `function public.end_ai_session(...) does not exist`

- [ ] **Step 3: Write the RPCs**

Create `supabase/migrations/20260953090000_ai_session_end_share_rpcs.sql`:

```sql
-- end_ai_session (either-partner-ends, synchronous content purge, no
-- actor recorded) and share_ai_session_turn (adapts the existing Plan A
-- draft/share pipeline to a session-turn source). Spec §5.4, §8.1.
CREATE OR REPLACE FUNCTION public.end_ai_session(
  p_actor_id uuid, p_session_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL THEN
    RETURN; -- unknown session: idempotent no-op, same as "already closed"
  END IF;
  IF v_session.state = 'closed' THEN
    RETURN;
  END IF;

  IF v_session.visibility = 'private' THEN
    IF v_session.creator_id != p_actor_id THEN
      RAISE EXCEPTION 'Only the creator may end a private session';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_session.relationship_id
        AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
    ) THEN
      RAISE EXCEPTION 'Not a member of this shared session''s relationship';
    END IF;
  END IF;

  -- Synchronous purge, same transaction (spec §5.4). No client-readable
  -- ending actor column exists to set (Global Constraints).
  DELETE FROM public.ai_session_turns WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_sources WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_approvals WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_staging WHERE session_id = p_session_id;

  UPDATE public.ai_sessions
  SET state = 'closed', generation_epoch = generation_epoch + 1
  WHERE id = p_session_id;
END;
$$;
REVOKE ALL ON FUNCTION public.end_ai_session(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.end_ai_session(uuid, uuid)
  TO service_role;

-- share_ai_session_turn: validates the turn, then reuses Plan A's
-- insert_ai_assist_draft + share_ai_assist_draft exactly as the
-- existing long-press flow does -- NOT a reimplementation of message
-- insertion. target_message_id is NULL here (a session answer has no
-- single "target message" the way a long-press Assist call does); the
-- existing share_ai_assist_draft RPC already treats a NULL
-- target_message_id as "no target eligibility recheck needed" (see its
-- own body in 20260950080000 -- the `IF v_draft.target_message_id IS
-- NOT NULL THEN` guard skips the target-existence check entirely when
-- NULL).
CREATE OR REPLACE FUNCTION public.share_ai_session_turn(
  p_actor_id uuid, p_session_id uuid, p_ordinal int
) RETURNS public.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_turn public.ai_session_turns;
  v_draft public.ai_assist_drafts;
  v_draft_id uuid;
  v_message public.messages;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id;
  IF v_session.id IS NULL OR v_session.state != 'active' THEN
    RAISE EXCEPTION 'Session unavailable';
  END IF;

  IF v_session.visibility = 'private' THEN
    IF v_session.creator_id != p_actor_id THEN
      RAISE EXCEPTION 'Only the creator may share from a private session';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_session.relationship_id AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
    ) THEN
      RAISE EXCEPTION 'Not a member of this shared session''s relationship';
    END IF;
  END IF;

  SELECT * INTO v_turn FROM public.ai_session_turns
  WHERE session_id = p_session_id AND ordinal = p_ordinal;
  IF v_turn.session_id IS NULL THEN
    RAISE EXCEPTION 'Turn not found';
  END IF;
  IF v_turn.role != 'attune' THEN
    RAISE EXCEPTION 'Only an Attune-authored turn may be shared';
  END IF;
  IF v_turn.kind = 'redirect' THEN
    RAISE EXCEPTION 'A redirect cannot be posted';
  END IF;

  v_draft_id := gen_random_uuid();
  v_draft := public.insert_ai_assist_draft(
    v_draft_id, v_session.relationship_id, p_actor_id, NULL,
    v_turn.payload->>'reply_text',
    jsonb_build_object(
      'schema_version', 1,
      'suggested_planning_item', v_turn.payload->'suggested_planning_item',
      'sources', COALESCE(v_turn.payload->'sources', '[]'::jsonb)
    )
  );

  v_message := public.share_ai_assist_draft(v_draft_id);

  INSERT INTO public.ai_session_publications (session_id, request_id, message_id, consumed_marker)
  VALUES (p_session_id, v_turn.request_id, v_message.id, true)
  ON CONFLICT (session_id, request_id) DO NOTHING;

  RETURN v_message;
END;
$$;
REVOKE ALL ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  TO authenticated;
```

**Note on the final GRANT:** unlike every other RPC in this plan,
`share_ai_session_turn` is granted to `authenticated`, not
`service_role` — it derives its actor from `p_actor_id`, which Plan C's
edge function must populate from `requireUser(req)`, matching exactly
how `share_ai_assist_draft` (Plan A's precedent) is `authenticated`-
callable and derives its actor from `auth.uid()` directly (that
function is called by the CLIENT, through PostgREST, not proxied by an
edge function — confirm this is the intended calling shape with Plan C
before wiring it, since `share_ai_assist_draft` reads `auth.uid()`
itself while this new function takes `p_actor_id` as a parameter; if
Plan C's edge function is the caller, `p_actor_id` should come from
`requireUser(req)` exactly as every other RPC in this plan does, and
this function's grant might need to move to `service_role` instead —
**this is a genuine open design question for Plan C to resolve, not
a contradiction to silently pick one side of.**

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953090000_ai_session_end_share_rpcs.sql
psql -q -d attune_test -f supabase/tests/ai_session_end_share_contracts.sql
```

Expected: `NOTICE: end_ai_session / share_ai_session_turn contracts: all held`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260953090000_ai_session_end_share_rpcs.sql \
        supabase/tests/ai_session_end_share_contracts.sql
git commit -m "feat(ai-sessions): add end_ai_session and share_ai_session_turn"
```

---

### Task 10: Authorized read RPCs and RLS-enumeration mutation test

**Files:**
- Create: `supabase/migrations/20260953100000_ai_session_read_rpcs.sql`
- Test: `supabase/tests/ai_session_read_authorization_contracts.sql`

**Interfaces:**
- Consumes: all tables from Tasks 1-2.
- Produces: `read_ai_session_turns(p_actor_id uuid, p_session_id uuid) RETURNS SETOF public.ai_session_turns`
  — authorized content read: active membership, current consent,
  unexpired active state, and creator (private) or accepted participant
  (shared, meaning has a row in `ai_session_approvals` for the current
  `context_revision`). Recheck source versions is Plan C's concern at
  generation time, not this read RPC's — this RPC only gates on
  membership/state/consent (spec §7.2: "Content reads require active
  membership, current consent, unexpired active state and creator
  (private) or accepted participant (shared)").
- Produces: `read_ai_session_staging(p_actor_id uuid, p_request_id uuid) RETURNS SETOF public.ai_session_staging`
  — author-checking RPC only (spec §7.2: "Own staged Nearby is
  accessible only through an author-checking RPC, never a shared SELECT
  policy").

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_read_authorization_contracts.sql`:

```sql
-- Authorized reads: a private session's content is invisible to the
-- partner through every surface, not just the obvious one. Spec §7.2,
-- §11 item 5.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_read_authorization_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-00000000000b';
  v_user_a uuid := 'b1000000-0000-0000-0000-0000000010a';
  v_user_b uuid := 'b1000000-0000-0000-0000-0000000010b';
  v_session uuid;
  v_admit record;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'read_a@t.test'), (v_user_b, 'read_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550018001', 'A'), (v_user_b, '+15550018002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp');
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(v_admit.worker_token, v_admit.request_id, 'private idea', 'private reply', NULL);

  -- Creator can read their own private session's turns.
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: the creator could not read their own private session''s turns, got % rows', v_count;
  END IF;

  -- The PARTNER (a real member of the same relationship, just not this
  -- session's creator) reads ZERO rows -- not an error, not a partial
  -- result, exactly zero.
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_b, v_session);
  IF v_count != 0 THEN
    RAISE EXCEPTION 'EXPLOIT: the non-creator partner read % rows from a private session -- expected 0', v_count;
  END IF;

  -- A stranger (not a member of this relationship at all) also reads
  -- zero, indistinguishable from the partner's own zero-row result --
  -- this is the "not an existence oracle" property (spec §3.1's
  -- TARGET_UNAVAILABLE precedent, applied here to session reads).
  DECLARE
    v_stranger uuid := 'b1000000-0000-0000-0000-0000000010c';
  BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_stranger, 'stranger@t.test') ON CONFLICT DO NOTHING;
    INSERT INTO public.users (id, phone, display_name) VALUES (v_stranger, '+15550018003', 'S') ON CONFLICT DO NOTHING;
    SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_stranger, v_session);
    IF v_count != 0 THEN
      RAISE EXCEPTION 'EXPLOIT: a non-member stranger read % rows from a private session', v_count;
    END IF;
  END;

  RAISE NOTICE 'read authorization contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_read_authorization_contracts.sql
```

Expected: `function public.read_ai_session_turns(...) does not exist`

- [ ] **Step 3: Write the RPCs**

Create `supabase/migrations/20260953100000_ai_session_read_rpcs.sql`:

```sql
-- Authorized reads. Spec §7.2. Both are STABLE (read-only) but still
-- SECURITY DEFINER, since ai_session_turns/ai_session_staging have no
-- SELECT policy at all for `authenticated` to fall back on -- these
-- functions ARE the entire read path, not a convenience wrapper around
-- one.
CREATE OR REPLACE FUNCTION public.read_ai_session_turns(
  p_actor_id uuid, p_session_id uuid
) RETURNS SETOF public.ai_session_turns
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_authorized boolean := false;
BEGIN
  IF p_actor_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id;
  IF v_session.id IS NULL OR v_session.state != 'active' THEN
    RETURN;
  END IF;
  IF v_session.expires_at IS NOT NULL AND v_session.expires_at <= now() THEN
    RETURN;
  END IF;

  IF v_session.visibility = 'private' THEN
    v_authorized := (v_session.creator_id = p_actor_id);
  ELSE
    v_authorized := EXISTS (
      SELECT 1 FROM public.ai_session_approvals a
      WHERE a.session_id = p_session_id
        AND a.member_id = p_actor_id
        AND a.revision = v_session.context_revision
    );
  END IF;

  IF NOT v_authorized THEN
    RETURN;
  END IF;

  RETURN QUERY SELECT * FROM public.ai_session_turns
  WHERE session_id = p_session_id
  ORDER BY ordinal;
END;
$$;
REVOKE ALL ON FUNCTION public.read_ai_session_turns(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_ai_session_turns(uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.read_ai_session_staging(
  p_actor_id uuid, p_request_id uuid
) RETURNS SETOF public.ai_session_staging
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public.ai_session_staging
  WHERE request_id = p_request_id AND requester_id = p_actor_id
    AND expires_at > now();
END;
$$;
REVOKE ALL ON FUNCTION public.read_ai_session_staging(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_ai_session_staging(uuid, uuid)
  TO service_role;
```

**Note on the `GRANT ... TO service_role` here versus Task 9's
`share_ai_session_turn` grant to `authenticated`:** this task's two read
RPCs are `service_role`-only, meaning Plan C's edge function must proxy
every read command too (spec §4.1 lists `read` as one of the "distinct
authenticated commands" an edge function exposes) — the client never
calls `read_ai_session_turns` directly via PostgREST. This is consistent
with `p_actor_id` being a parameter rather than `auth.uid()` throughout
this plan. Task 9's open question about `share_ai_session_turn` should
be resolved the same way for consistency: **recommend granting it to
`service_role` too and having Plan C's edge function derive
`p_actor_id` from `requireUser(req)`**, rather than leaving it as the
one `authenticated`-callable exception in this entire plan.

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953100000_ai_session_read_rpcs.sql
psql -q -d attune_test -f supabase/tests/ai_session_read_authorization_contracts.sql
```

Expected: `NOTICE: read authorization contracts: all held`

- [ ] **Step 5: Reconcile Task 9's grant with this task's recommendation**

Change `share_ai_session_turn`'s grant in
`supabase/migrations/20260953090000_ai_session_end_share_rpcs.sql`
from:

```sql
REVOKE ALL ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  TO authenticated;
```

to:

```sql
REVOKE ALL ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  TO service_role;
```

Re-run Task 9's own contract test to confirm this change doesn't break
it (the test calls the function directly as the migration owner, which
has implicit execute rights regardless of GRANT/REVOKE — the grant
change only affects who can call it over a real PostgREST connection,
which this SQL-level test never exercises either way; this step exists
to keep the migration file's own stated grant consistent with this
plan's actual calling convention, not because the existing test would
catch the inconsistency):

```bash
psql -q -d attune_test -f supabase/tests/ai_session_end_share_contracts.sql
```

Expected: `NOTICE: end_ai_session / share_ai_session_turn contracts: all held`
(unchanged)

- [ ] **Step 6: Add one contract proving `authenticated` truly has no grant on `share_ai_session_turn`**

Append to `supabase/tests/ai_session_end_share_contracts.sql`, before
its final `RAISE NOTICE`:

```sql
  -- Contract: share_ai_session_turn is service_role-only, matching
  -- every other RPC in this plan, per Task 10's reconciliation.
  IF EXISTS (
    SELECT 1 FROM information_schema.role_routine_grants g
    WHERE g.routine_name = 'share_ai_session_turn' AND g.grantee = 'authenticated'
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated still has EXECUTE on share_ai_session_turn';
  END IF;
```

```bash
psql -q -d attune_test -f supabase/tests/ai_session_end_share_contracts.sql
```

Expected: `NOTICE: end_ai_session / share_ai_session_turn contracts: all held`

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260953090000_ai_session_end_share_rpcs.sql \
        supabase/migrations/20260953100000_ai_session_read_rpcs.sql \
        supabase/tests/ai_session_end_share_contracts.sql \
        supabase/tests/ai_session_read_authorization_contracts.sql
git commit -m "feat(ai-sessions): add authorized read RPCs; make share_ai_session_turn service_role-only for consistency"
```

---

### Task 11: Every-minute reconciler/purger cron registration

**Files:**
- Create: `supabase/migrations/20260953110000_ai_session_reconciler_cron.sql`
- Test: `supabase/tests/ai_session_purge_contracts.sql`

**Interfaces:**
- Consumes: `reconcile_ai_session_leases` (Task 6), `end_ai_session`
  (Task 9, reused for expired-session purge rather than a second
  deletion code path).
- Produces: `purge_expired_ai_sessions() RETURNS int` (count purged) —
  finds every `active` session past its `expires_at` and every
  `preparing` session past its `preparation_deadline` that Task 3's own
  reclaim-on-prepare logic hasn't already caught (a relationship that
  simply never prepares again), and calls `end_ai_session`'s own purge
  logic on each (reusing that function's synchronous content deletion
  rather than duplicating it). Registers both this function and Task 6's
  `reconcile_ai_session_leases` on a `'* * * * *'` (every minute)
  schedule, matching the existing `process-chat-safety-outbox`/
  `process-scheduled-notifications` precedent in
  `20260907120000_register_scheduled_jobs.sql` — NOT the hourly cadence
  Plan A's own `ai_assist_drafts` purge uses (spec §8.2.3 requires
  Sessions' own purge lag target of five minutes, which an hourly job
  cannot meet).

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_session_purge_contracts.sql`:

```sql
-- purge_expired_ai_sessions: catches sessions whose expiry passed with
-- no further activity to trigger reclaim-on-prepare. Spec §8.2.3.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_purge_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-00000000000c';
  v_user_a uuid := 'b1000000-0000-0000-0000-0000000011a';
  v_session uuid;
  v_purged int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'purge_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550019001', 'A') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel, v_user_a, 'active') ON CONFLICT DO NOTHING;

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp');

  -- Force this session well past expiry with no further calls.
  UPDATE public.ai_sessions
  SET last_admitted_at = now() - interval '1 hour',
      expires_at = now() - interval '45 minutes'
  WHERE id = v_session;

  SELECT public.purge_expired_ai_sessions() INTO v_purged;
  IF v_purged < 1 THEN
    RAISE EXCEPTION 'EXPLOIT: purge_expired_ai_sessions did not purge the one expired session, reported % purged', v_purged;
  END IF;
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: an expired session was not closed by the purge job';
  END IF;

  -- Idempotent -- running it again with nothing new to purge doesn't error.
  PERFORM public.purge_expired_ai_sessions();

  RAISE NOTICE 'session purge contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_purge_contracts.sql
```

Expected: `function public.purge_expired_ai_sessions() does not exist`

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260953110000_ai_session_reconciler_cron.sql`:

```sql
-- purge_expired_ai_sessions + every-minute cron registration for both
-- this and reconcile_ai_session_leases. Spec §8.2.3: "scheduled expiry
-- purger runs every minute with an operational target of deletion
-- within five minutes after logical expiry. Existing hourly 24-hour
-- draft purge does not satisfy this."
CREATE OR REPLACE FUNCTION public.purge_expired_ai_sessions()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_count int := 0;
BEGIN
  FOR v_row IN
    SELECT id FROM public.ai_sessions
    WHERE (state = 'active' AND expires_at IS NOT NULL AND expires_at < now())
       OR (state = 'preparing' AND preparation_deadline < now())
  LOOP
    -- Reuses end_ai_session's own synchronous purge logic rather than
    -- a second deletion code path -- p_actor_id is NULL here, which
    -- end_ai_session must accept for this system-initiated close path
    -- specifically (see the adjustment below).
    PERFORM public.end_ai_session(NULL, v_row.id);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.purge_expired_ai_sessions()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_ai_sessions()
  TO service_role;

-- end_ai_session (Task 9) currently RAISEs "Not authenticated" when
-- p_actor_id IS NULL, which this system-initiated purge path needs to
-- bypass legitimately -- widen it to accept a NULL actor ONLY for the
-- already-expired case, never for a live end request from a real user.
CREATE OR REPLACE FUNCTION public.end_ai_session(
  p_actor_id uuid, p_session_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_is_system_purge boolean;
BEGIN
  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL THEN
    RETURN;
  END IF;
  IF v_session.state = 'closed' THEN
    RETURN;
  END IF;

  v_is_system_purge := (
    (v_session.state = 'active' AND v_session.expires_at IS NOT NULL AND v_session.expires_at < now())
    OR (v_session.state = 'preparing' AND v_session.preparation_deadline < now())
  );

  IF p_actor_id IS NULL THEN
    IF NOT v_is_system_purge THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;
    -- System-initiated close of a session that is ALREADY past its own
    -- expiry: no live user actor to check membership against, and none
    -- is needed -- the session is unavailable to everyone regardless of
    -- who ends it at this point.
  ELSIF v_session.visibility = 'private' THEN
    IF v_session.creator_id != p_actor_id THEN
      RAISE EXCEPTION 'Only the creator may end a private session';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_session.relationship_id
        AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
    ) THEN
      RAISE EXCEPTION 'Not a member of this shared session''s relationship';
    END IF;
  END IF;

  DELETE FROM public.ai_session_turns WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_sources WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_approvals WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_staging WHERE session_id = p_session_id;

  UPDATE public.ai_sessions
  SET state = 'closed', generation_epoch = generation_epoch + 1
  WHERE id = p_session_id;
END;
$$;
REVOKE ALL ON FUNCTION public.end_ai_session(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.end_ai_session(uuid, uuid)
  TO service_role;

DO $$
DECLARE
  v_job text;
BEGIN
  FOREACH v_job IN ARRAY ARRAY[
    'purge-ai-sessions',
    'reconcile-ai-session-leases'
  ]
  LOOP
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = v_job;
  END LOOP;
END;
$$;

SELECT cron.schedule(
  'purge-ai-sessions',
  '* * * * *',
  $$ SELECT public.purge_expired_ai_sessions(); $$
);

SELECT cron.schedule(
  'reconcile-ai-session-leases',
  '* * * * *',
  $$ SELECT public.reconcile_ai_session_leases(); $$
);
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260953110000_ai_session_reconciler_cron.sql
psql -q -d attune_test -f supabase/tests/ai_session_purge_contracts.sql
```

Expected: `NOTICE: session purge contracts: all held`

- [ ] **Step 5: Re-run Task 9's own end-session test to confirm the
  widened `end_ai_session` didn't loosen its authorization for a REAL
  (non-expired, non-NULL-actor) end request**

```bash
psql -q -d attune_test -f supabase/tests/ai_session_end_share_contracts.sql
```

Expected: `NOTICE: end_ai_session / share_ai_session_turn contracts: all held`
(unchanged — the widened NULL-actor path only activates when
`v_is_system_purge` is true, which none of Task 9's own scenarios
trigger).

- [ ] **Step 6: Full rebuild and full-suite run — the final gate for this plan**

```bash
bash scripts/local_pg_setup.sh
for f in supabase/tests/ai_assistant_quota_contracts.sql \
         supabase/tests/ai_assistant_provider_start_marker_contracts.sql \
         supabase/tests/ai_assistant_quota_release_contracts.sql \
         supabase/tests/ai_sessions_schema_contracts.sql \
         supabase/tests/ai_session_requests_turns_contracts.sql \
         supabase/tests/ai_session_prepare_contracts.sql \
         supabase/tests/ai_session_approve_activate_contracts.sql \
         supabase/tests/ai_session_admit_contracts.sql \
         supabase/tests/ai_session_dispatch_claim_contracts.sql \
         supabase/tests/ai_session_commit_ideas_contracts.sql \
         supabase/tests/ai_session_nearby_staging_contracts.sql \
         supabase/tests/ai_session_end_share_contracts.sql \
         supabase/tests/ai_session_read_authorization_contracts.sql \
         supabase/tests/ai_session_purge_contracts.sql; do
  echo "=== $f ==="
  psql -q -d attune_test -f "$f"
done
bash supabase/tests/ai_assistant_provider_start_concurrent_test.sh
bash supabase/tests/ai_session_admit_concurrent_test.sh
```

Expected: every SQL file prints its own `all held` NOTICE and both shell
scripts print their own success line, all against ONE fresh database
built from every migration in this plan (and Plan A) applied in order —
this is the proof that the whole schema is internally consistent, not
just each task's own narrow slice.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260953110000_ai_session_reconciler_cron.sql \
        supabase/tests/ai_session_purge_contracts.sql
git commit -m "feat(ai-sessions): register every-minute reconciler and expiry purger cron jobs"
```

---

## Plan B self-review

**Spec coverage:**

- §3.2 (prepare/approve/activate, slot limits, expired-slot reclamation) — Tasks 3-4. ✓
- §4.3 (frozen approval, revision/context_revision split, digest binding) — Task 4 (digest itself is opaque text this plan stores and compares; Plan C computes the actual digest algorithm from real context content — this plan proves the STORAGE and COMPARISON contract, not the hash function). ✓ (storage/comparison layer only — flagged, not silently assumed complete)
- §5.1 (state machine: preparing→active→closed) — Task 1's CHECK constraints + Tasks 3/4/9/11's transitions. ✓
- §5.2 (attempt cap, idle/absolute expiry) — Task 1's schema + Task 5's admission logic. Note: this plan's `expires_at` is written by Task 5 (admission) — confirmed present in Task 5's `UPDATE public.ai_sessions SET ... last_admitted_at = now()`, but **Task 5's own migration text above does not actually recompute and write `expires_at` on that UPDATE** — this is a real gap found during self-review, not a hypothetical. **Fix required before Task 5 is considered done**: add `expires_at = LEAST(now() + interval '15 minutes', activated_at + interval '60 minutes')` to that same `UPDATE` statement. Apply this fix during Task 5's own implementation, not as a later patch.
- §5.3 (output type storage) — Task 2's `ai_session_turns.payload jsonb` + `kind` CHECK. Actual field-level validation (title length, event_date format, source card bounds) is explicitly Plan C's job (this plan stores whatever valid JSON it's given; Plan C is the only layer that ever constructs that JSON from validated model output).
- §5.4 (either-partner-ends, synchronous purge, no actor column) — Task 9, widened in Task 11. ✓
- §6.1 (Realtime authorization) — **NOT built in this plan.** See "What this plan deliberately does NOT do" below.
- §6.2 (full admission/dispatch/completion protocol, lock order, ordinal parity, compensation table) — Tasks 5-9. ✓
- §6.3 (private-to-shared is always a new session, never a promotion) — enforced structurally: Task 3's `prepare_ai_session` has no "convert visibility" parameter at all, and Task 1's schema has no migration path for an existing row's `visibility` column — there is no code path that could promote one, which is the strongest possible proof of "never" for this specific requirement.
- §7.1 (schema table) — Tasks 1-2, fully. ✓
- §7.2 (RLS/grants/RPC ownership) — Tasks 1-2 (RLS enabled, no policies) + every task's `REVOKE ALL ... GRANT ... TO service_role` pattern, reconciled for consistency in Task 10. ✓
- §7.3 (quota) — Plan A, consumed here via `p_mode = 'session'`. ✓ (cross-referenced, not duplicated)
- §11 items 1 (concurrent admission race), 2 (concurrent same-key claim — Plan A Task 5 proves this for the base ledger; Task 5 here doesn't re-prove it at the session-admission layer with a SEPARATE concurrency script — **gap**: add a session-level version of Plan A's Task 5 script exercising `admit_ai_session_generation` with the SAME `request_id` from two connections, not just the count-9/10 boundary script this plan already has), 3 (crash/lease recovery — Task 6), 4 (end races admission — not explicitly tested; **gap**: add a test calling `end_ai_session` concurrently with `admit_ai_session_generation` on the same session), 5 (RLS enumeration — Task 10), 11 (RLS with cron disabled — Task 11's own test disables nothing and relies on the cron jobs never running during `psql -f` execution, which is already true since these are SQL contract tests, not a live cron environment — this satisfies the LETTER of "with cron disabled" trivially, but the SPIRIT (proving purge lag alerting) is genuinely Plan C/D's operational-rollout concern, not this plan's).

**Two real gaps found during self-review, both must be fixed before Plan
B is marked done — added as explicit follow-up steps:**

- [ ] **Fix Task 5:** add `expires_at` computation to the admission
  `UPDATE ai_sessions` statement (see above).
- [ ] **Fix Task 5:** add a concurrent-same-`request_id` shell script
  (mirroring Plan A Task 5's pattern exactly, but calling
  `admit_ai_session_generation` instead of
  `claim_ai_assistant_provider_start`) proving exactly one of N racing
  callers with the SAME `request_id` gets `'admitted'` and the rest get
  `'already_admitted'` with identical `attempt_n`/`worker_token`.
- [ ] **Add a new task-11-adjacent test:** `end_ai_session` racing
  `admit_ai_session_generation` on the same session — confirm the
  relationship-lock ordering (Global Constraints) already makes this
  safe, but PROVE it with a concurrent shell script rather than asserting
  it from the lock-order rule alone.

**What this plan deliberately does NOT do** (explicitly out of scope,
owned by Plan C or D):

- **§6.1 Realtime authorization is not implemented in this plan at
  all.** This is a genuinely large, novel piece of infrastructure (this
  codebase's first use of Supabase's private-channel Broadcast
  authorization rather than public `onPostgresChanges`), and belongs in
  Plan C alongside the edge function that actually enqueues the
  content-free hints this mechanism delivers — building the RLS-on-
  `realtime.messages` policy here with no consumer to test it against
  would be unverifiable speculation. **Flag this explicitly to whoever
  scopes Plan C: §6.1 is unclaimed by both plans as currently divided
  and must land in Plan C's own Global Constraints, not be silently
  assumed "already done" because Plan B built the tables.**
- Output validation (title/date bounds, source-card field limits,
  prohibited-pattern checks, the actual Gemini/Mapbox calls) — Plan C.
- The actual context-window selection query (§4.2's LIMIT/clip/budget
  logic) and the digest computation itself — Plan C, since both require
  the real message content this plan's tables only store as already-
  clipped/approved text, never compute fresh.
- Any client-facing command surface — Plan C's edge function is the
  first place any of these RPCs are reachable from outside a direct SQL/
  service-role call.

**Placeholder scan:** no TBD/TODO. The two `**gap**` markers above are
real findings from this self-review, not placeholders — each has a
concrete fix specified, and both are added as explicit checklist items
rather than left as prose.

**Type consistency check:** every RPC introduced across Tasks 3-11 uses
`p_actor_id uuid` as its first parameter (matching Plan A's convention)
except `claim_ai_session_dispatch` (keyed on `p_worker_token`, by design
— see Task 6's own interface note) and the internal `end_ai_session`
NULL-actor system path (Task 11, explicitly justified). `attempt_n`/
`ordinal` types are consistently `smallint` in table definitions and
`int` in RPC return signatures throughout (matching Plan A's own
`ai_assistant_usage.provider_calls smallint` vs. RPC-return `int`
precedent).

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-09-22-ai-sessions-plan-b-schema-and-concurrency.md`.
Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per
task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using
executing-plans, batch execution with checkpoints

**Which approach?**

# AI Assistant — Plan A: Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete server-side foundation for the AI Assistant —
schema, RLS/grants, the relationship-analysis exclusion fix, a reusable
user-JWT-scoped context loader, the two edge functions (`ai-assist`,
`ai-understand`), the atomic quota ledger, consent RPCs, the draft-share
RPC, the Planning-conversion RPC, and scheduled purge jobs — with contract
tests that prove security and correctness against a real Postgres database
and against real (fake-gateway) edge-function behavior, not just against
the harness's own generosity.

**Architecture:** Two new user-authenticated Edge Functions
(`supabase/functions/ai-assist/`, `supabase/functions/ai-understand/`)
share a new `_shared/attune_auth.ts` addition — a user-JWT-scoped Supabase
client factory — and a new `_shared/ai_context_loader.ts` that both
functions call read-only to build bounded, pseudonymized chat context from
a `message_id`. Five new tables
(`ai_assist_drafts`, `ai_assistant_usage`, `ai_processing_consent_events`,
`ai_assist_planning_links`, plus two new columns on `messages`) follow the
same "clients get SELECT only, every mutation via a `SECURITY DEFINER`
RPC" shape Planning's backend already established
(`lib/architecture/PLANNING.md` §4). The existing `messages` table gains
`message_origin`/`assistant_payload` columns and a same-transaction-safe
`share_ai_assist_draft` RPC. The pre-existing `message_analysis_skipped`
schema hook (currently dead — no query anywhere filters on it) becomes
real across four existing query sites.

**Tech Stack:** PostgreSQL migrations (Supabase), hand-written SQL contract
tests run against the project's local Postgres harness
(`scripts/local_pg_setup.sh`), the existing `test_set_auth(uuid)`-style
`request.jwt.claims`/`SET LOCAL ROLE authenticated` pattern for RLS tests,
Deno edge functions with `Deno.test`, the existing `callGeminiJson` shared
helper (`supabase/functions/_shared/gemini_json.ts`), `requireUser`
(`supabase/functions/_shared/attune_auth.ts`).

**Spec:** `docs/superpowers/specs/2026-09-15-ai-assistant-design.md` (read
this in full before Task 1 — this plan implements its §4 (trusted request/
context), §5 (Assist), §6.2-6.3/§7-§11 (Understand's server contract,
schema, quota, errors), §8 (safety/analysis interaction), §9 (prompt
injection defenses at the mechanical-validation layer), §10.1/§10.3
(consent, telemetry) — everything except the model/eval judgment calls in
§9's behavioral rules and §13.2's human-reviewed eval gates, which are
release gates, not code this plan writes). Also read
`lib/architecture/PLANNING.md` §4 for the closest existing analog of the
table-vs-RPC boundary and `SECURITY DEFINER`/`SET search_path` discipline
this plan reuses, and `supabase/functions/translate-conflict/index.ts` as
the one existing edge function that already calls `callGeminiJson` from a
user-facing feature (do NOT copy its request/auth pattern — the spec's §0
P1 finding explicitly rejects that as a precedent — read it only to see
the shared-helper call shape).

## Global Constraints

These bind every task below. Copied/derived verbatim from the spec; do not
relax any of them without stopping and asking.

- **Both edge functions authenticate via `requireUser(req)`, never decode
  a JWT locally.** (Spec §4.2 step 1)
- **Content reads use a user-JWT-scoped Supabase client, never the
  existing `serviceRoleClient()`.** This codebase's existing edge
  functions (`analyse-message`, `analyse-session`, `translate-conflict`,
  etc.) all read with `serviceRoleClient()` and do authorization by hand
  in application code — that pattern is explicitly NOT what this spec
  asks for. §4.2 requires RLS to be the actual read authority for target/
  context loading, the same "RLS is the sole authority" principle
  Planning's read RPCs already established for the client, applied here
  at the edge-function layer instead. Task 1 builds the one new shared
  helper this requires.
- **Neither request accepts `relationship_id`, `requester_id`, message
  content, history, profile fields, partner identity, prior AI output, or
  arbitrary source records.** Every one of those is derived server-side
  from `message_id` + the authenticated caller. (Spec §4.1)
- **All target failures return the same `TARGET_UNAVAILABLE` code.** The
  endpoint must not be an existence oracle — a deleted message, a message
  in a relationship the caller isn't in, and a message that simply
  doesn't exist are indistinguishable to the caller. (Spec §4.2)
- **`item_kind`-style immutability discipline applies to `message_origin`
  too**: once a message is `'attune_assist'`, no RPC may change it back to
  `'user'` except the delete-tombstone path in Task 6, and no RPC may ever
  set it to `'attune_assist'` except the trusted share RPC. (Spec §5.3,
  §7.2)
- **Every `SECURITY DEFINER` function**: fixed `SET search_path = public`,
  rejects `auth.uid() IS NULL` immediately, is `REVOKE ALL ... FROM
  PUBLIC, anon`, and is granted only to the role that needs it. (Spec
  §7.2, matching Planning's own discipline)
- **No client-supplied draft/payload content is ever trusted.** The
  service-role-only draft-insert function and the `share_ai_assist_draft`
  RPC never accept replacement content from a caller — the draft a user
  shares is always the exact server-generated one. (Spec §5.3, §7.2)
- **The quota ledger is one atomic operation, shared across both modes,
  keyed by `(request_id, user_id, mode)`, serialized per user.** A retry
  with the same `request_id` never grants a second provider lease. (Spec
  §7.3)
- **`message_analysis_skipped` must become a REAL exclusion**, not merely
  a column that exists. Every one of these real query sites needs the
  filter added, verified by reading the actual files first (do not trust
  this list without re-confirming against the file, since these are the
  sites found during spec-writing, not a guarantee nothing else changed
  since): `supabase/functions/analyse-message/index.ts` (both the
  candidate-selection query and the mark-done exclusion query),
  `supabase/functions/analyse-session/index.ts` (both of its own
  `message_analysis_done = true` selection queries), and
  `supabase/migrations/20260830120000_chat_pulse_signals.sql` (both of its
  SQL-level `message_analysis_done = true` joins). Do not set
  `message_analysis_done = true` on an Assist message merely to make it
  disappear from Layer 1 — Layer 2/Pulse select on `message_analysis_done
  = true`, so that would feed the Assist message INTO those consumers
  instead of excluding it. The correct terminal state is
  `message_analysis_done = false, message_analysis_skipped = true`,
  consistently filtered everywhere. (Spec §8.2)
- **Deterministic safety processing is never bypassed, delayed, or
  skipped for a shared Assist message.** The ordinary
  `enqueue_message_downstream_work` trigger must fire for
  `message_origin = 'attune_assist'` exactly as it does for a human
  message. Understand mode never inserts a message and never queries
  safety state. (Spec §8.1)
- **No test may pass vacuously.** Use `IS DISTINCT FROM`, never `<>`,
  wherever a NULL comparison is involved. Every contract test in this plan
  must be mutation-tested: break the behavior it claims to protect,
  confirm the test fails, then restore. This project has repeatedly
  shipped tests that passed with the protected behavior deleted — do not
  add another one.
- **The test harness's blanket grant is a known trap.**
  `scripts/local_pg_grants.sql` runs a blanket
  `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO
  authenticated` after all migrations. Task 1 must add a `\i` line
  replaying this plan's own REVOKEs into that script, the same way
  Planning's Task 1 (`20260941030000_planning_table_grants.sql`) and
  Stories already do — verify the exact insertion point by reading
  `scripts/local_pg_grants.sql` directly before editing it.
- **Per-file test runs are not sufficient evidence of a passing suite.**
  Run the full commands each task specifies, not just the file you just
  touched.
- **Telemetry allowlist is enforced in code, not by convention.** Any
  logging/analytics/Sentry call this plan adds must be checked against
  the spec §10.3 allowed-field list before being written — the forbidden
  list (content, prompts, output, coordinates, place query/results,
  partner names, safety state, response option selected) is the more
  important one to internalize, since it is easy to log "just for
  debugging" and forget to remove.

---

## Task 1: Schema, grants, RLS, and the user-JWT-scoped client helper

**Files:**
- Create: `supabase/migrations/20260950010000_ai_assistant_schema.sql`
- Create: `supabase/migrations/20260950020000_ai_assistant_rls.sql`
- Create: `supabase/migrations/20260950030000_ai_assistant_table_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (add a `\i` line for the new
  grants file, following the exact pattern the Planning grants lines
  already use)
- Create: `supabase/functions/_shared/user_scoped_client.ts`
- Test: `supabase/tests/ai_assistant_schema_contracts.sql`
- Test: `supabase/functions/_shared/user_scoped_client.test.ts`

**Interfaces:**
- Produces: `messages.message_origin` (`text`, default `'user'`, CHECK
  `IN ('user', 'attune_assist')`), `messages.assistant_payload` (`jsonb`,
  nullable, shape-checked against `message_origin`); tables
  `ai_assist_drafts`, `ai_assistant_usage`, `ai_processing_consent_events`,
  `ai_assist_planning_links` exactly as specced in §7.2 (every column,
  constraint, and index named there). Every later task in this plan and
  in Plan B refers to these exact table/column names — do not rename
  anything.
- Produces: `userScopedClient(req: Request): Promise<{ client:
  SupabaseClient; user: AuthenticatedUser }>` in
  `supabase/functions/_shared/user_scoped_client.ts` — calls
  `requireUser(req)` first (reusing the existing helper, so an invalid/
  expired JWT fails exactly the same way it does everywhere else in this
  codebase), then constructs a Supabase JS client using the request's own
  bearer token as its `Authorization` header (so every subsequent query
  through this client runs as that authenticated user under RLS — NOT the
  service-role key). Every later task's edge-function code calls this
  once at the top of the handler and uses the returned `client` for every
  content read.

- [ ] **Step 1: Write `20260950010000_ai_assistant_schema.sql`**

```sql
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
```

- [ ] **Step 2: Write `20260950020000_ai_assistant_rls.sql`**

```sql
-- RLS for the AI Assistant tables. Spec §7.2: drafts/usage/consent events
-- have RLS enabled with NO direct authenticated table grants at all --
-- every legitimate access goes through a SECURITY DEFINER RPC (Tasks 3-7).
-- Planning links are readable by active, unarchived relationship members
-- and writable only by the Task-7 integration RPC.
ALTER TABLE public.ai_assist_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_assistant_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_processing_consent_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_assist_planning_links ENABLE ROW LEVEL SECURITY;

-- Deliberately NO SELECT/INSERT/UPDATE/DELETE policy on
-- ai_assist_drafts, ai_assistant_usage, or ai_processing_consent_events.
-- With RLS enabled and no policy for a command, that command is refused
-- outright for every role except the table owner -- this is the
-- enforcement mechanism for "no direct authenticated table grants at
-- all" (spec §7.2).

CREATE POLICY ai_assist_planning_links_select ON public.ai_assist_planning_links
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = ai_assist_planning_links.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );
-- No INSERT/UPDATE/DELETE policy here either -- writable only by
-- create_planning_from_assist_message (Task 7) and delete_message's
-- own cleanup (Task 6), both SECURITY DEFINER.
```

- [ ] **Step 3: Write `20260950030000_ai_assistant_table_grants.sql`**

```sql
-- Table-level grants. RLS (previous migration) is the row-level
-- authority; this is the coarser table-level privilege RLS runs on top
-- of.
REVOKE ALL ON public.ai_assist_drafts FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ai_assistant_usage FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ai_processing_consent_events FROM PUBLIC, anon, authenticated;

REVOKE ALL ON public.ai_assist_planning_links FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ai_assist_planning_links TO authenticated;
```

- [ ] **Step 4: Replay these grants in the local harness**

Open `scripts/local_pg_grants.sql`. Find the most recent `\i` line for
Planning's own grants file (search for
`20260941030000_planning_table_grants.sql`). Add immediately after it:

```sql
-- Same replay for the AI Assistant tables: the blanket GRANT above would
-- otherwise silently hand authenticated direct write access to
-- ai_assist_drafts/ai_assistant_usage/ai_processing_consent_events (which
-- must have NO authenticated grant at all) and direct write access to
-- ai_assist_planning_links (SELECT-only for authenticated) -- masking
-- exactly the kind of security bug this replay pattern exists to catch.
\i supabase/migrations/20260950030000_ai_assistant_table_grants.sql
```

- [ ] **Step 5: Rebuild the local database and confirm the migrations
  apply cleanly**

Run: `scripts/local_pg_setup.sh --no-tests`
Expected: rebuild completes with no errors, ending in a message like
"database attune_test ready."

- [ ] **Step 6: Write the failing schema contract tests**

Create `supabase/tests/ai_assistant_schema_contracts.sql`:

```sql
-- Schema-level contracts for the AI Assistant tables (Plan A, Task 1).
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_schema_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a1000000-0000-0000-0000-000000000001';
  v_rel_other uuid := 'a1000000-0000-0000-0000-000000000002';
  v_user_a uuid := 'a1000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a1000000-0000-0000-0000-00000000000b';
  v_user_c uuid := 'a1000000-0000-0000-0000-00000000000c';
  v_msg_id uuid := 'a1000000-0000-0000-0000-000000000101';
  v_draft_id uuid := 'a1000000-0000-0000-0000-000000000201';
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'aiassist_a@t.test'), (v_user_b, 'aiassist_b@t.test'),
    (v_user_c, 'aiassist_c@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550001001', 'A'), (v_user_b, '+15550001002', 'B'),
    (v_user_c, '+15550001003', 'C')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active'),
         (v_rel_other, v_user_c, v_user_c, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: message_origin defaults to 'user' with no
  -- assistant_payload, and an ordinary insert is unaffected.
  INSERT INTO public.messages (id, relationship_id, sender_id,
    client_message_id, content, source)
  VALUES (v_msg_id, v_rel, v_user_a, gen_random_uuid(), 'hello', 'native');
  IF NOT EXISTS (
    SELECT 1 FROM public.messages
    WHERE id = v_msg_id AND message_origin = 'user' AND assistant_payload IS NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: message_origin/assistant_payload defaults are wrong';
  END IF;

  -- Contract 2: assistant_payload cannot be set while message_origin is
  -- 'user' (shape check).
  BEGIN
    UPDATE public.messages SET assistant_payload = '{"x":1}'::jsonb
    WHERE id = v_msg_id;
    RAISE EXCEPTION 'EXPLOIT: assistant_payload was set on a user-origin message';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 3: message_origin = 'attune_assist' requires a non-null
  -- assistant_payload (the reverse half of the shape check).
  BEGIN
    UPDATE public.messages SET message_origin = 'attune_assist'
    WHERE id = v_msg_id;
    RAISE EXCEPTION 'EXPLOIT: message_origin flipped to attune_assist with no payload';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: ai_assist_drafts.expires_at must be exactly created_at +
  -- 15 minutes.
  BEGIN
    INSERT INTO public.ai_assist_drafts
      (id, relationship_id, requester_id, target_message_id, reply_text,
       assistant_payload, created_at, expires_at)
    VALUES (v_draft_id, v_rel, v_user_a, v_msg_id, 'a suggestion',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
      now(), now() + interval '20 minutes');
    RAISE EXCEPTION 'EXPLOIT: a draft with the wrong expiry window was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  INSERT INTO public.ai_assist_drafts
    (id, relationship_id, requester_id, target_message_id, reply_text,
     assistant_payload, created_at, expires_at)
  VALUES (v_draft_id, v_rel, v_user_a, v_msg_id, 'a suggestion',
    '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
    now(), now() + interval '15 minutes');

  -- Contract 5: blank-after-trim reply_text is rejected.
  BEGIN
    INSERT INTO public.ai_assist_drafts
      (id, relationship_id, requester_id, target_message_id, reply_text,
       assistant_payload, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel, v_user_a, v_msg_id, '   ',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
      now(), now() + interval '15 minutes');
    RAISE EXCEPTION 'EXPLOIT: a whitespace-only draft reply_text was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 6: ai_assistant_usage.provider_calls is bounded 0..2.
  BEGIN
    INSERT INTO public.ai_assistant_usage
      (request_id, user_id, relationship_id, mode, provider_calls, outcome)
    VALUES (gen_random_uuid(), v_user_a, v_rel, 'assist', 3, 'succeeded');
    RAISE EXCEPTION 'EXPLOIT: provider_calls accepted a value outside 0..2';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 7: ai_processing_consent_events enforces one idempotency_key
  -- per user (UNIQUE (user_id, idempotency_key)).
  DECLARE
    v_idem uuid := gen_random_uuid();
  BEGIN
    INSERT INTO public.ai_processing_consent_events
      (relationship_id, user_id, policy_version, action, idempotency_key)
    VALUES (v_rel, v_user_a, 'v1', 'granted', v_idem);
    BEGIN
      INSERT INTO public.ai_processing_consent_events
        (relationship_id, user_id, policy_version, action, idempotency_key)
      VALUES (v_rel, v_user_a, 'v1', 'granted', v_idem);
      RAISE EXCEPTION 'EXPLOIT: a duplicate idempotency_key for the same user was accepted';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  -- Contract 8: ai_assist_planning_links requires exactly one of
  -- planning_item_id/planning_event_id (num_nonnulls = 1).
  BEGIN
    INSERT INTO public.ai_assist_planning_links
      (message_id, relationship_id, planning_item_id, planning_event_id)
    VALUES (v_msg_id, v_rel, gen_random_uuid(), gen_random_uuid());
    RAISE EXCEPTION 'EXPLOIT: a planning link with both item and event ids was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 9: RLS -- a non-member of rel cannot read
  -- ai_assist_planning_links rows for it.
  DECLARE
    v_link_msg_id uuid := gen_random_uuid();
    v_planning_item_id uuid;
  BEGIN
    -- Needs a real planning_items row for the composite FK; skip if
    -- Planning isn't present in this build (defensive -- Planning is a
    -- hard dependency of this table, confirmed present by Plan A's own
    -- migrations already having run in this worktree).
    SELECT id INTO v_planning_item_id FROM public.planning_items LIMIT 1;
    IF v_planning_item_id IS NULL THEN
      PERFORM public.create_planning_task(gen_random_uuid(), v_rel,
        'fixture for ai_assist_planning_links RLS test', NULL, NULL, NULL);
      SELECT id INTO v_planning_item_id FROM public.planning_items
      WHERE relationship_id = v_rel LIMIT 1;
    END IF;
    INSERT INTO public.messages (id, relationship_id, sender_id,
      client_message_id, content, source, message_origin, assistant_payload)
    VALUES (v_link_msg_id, v_rel, v_user_a, gen_random_uuid(), 'ai reply',
      'native', 'attune_assist',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb);
    INSERT INTO public.ai_assist_planning_links
      (message_id, relationship_id, planning_item_id)
    VALUES (v_link_msg_id, v_rel, v_planning_item_id);
  END;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_c), true);
  IF EXISTS (
    SELECT 1 FROM public.ai_assist_planning_links WHERE relationship_id = v_rel
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: a non-member could read another couple''s ai_assist_planning_links';
  END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- Contract 10: authenticated has NO direct write privilege on any of
  -- the four new tables, and NO read privilege on the three
  -- SELECT-nothing tables.
  IF has_table_privilege('authenticated', 'public.ai_assist_drafts', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ai_assist_drafts', 'INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has some privilege on ai_assist_drafts';
  END IF;
  IF has_table_privilege('authenticated', 'public.ai_assistant_usage', 'SELECT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has SELECT on ai_assistant_usage';
  END IF;
  IF has_table_privilege('authenticated', 'public.ai_processing_consent_events', 'SELECT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has SELECT on ai_processing_consent_events';
  END IF;
  IF has_table_privilege('authenticated', 'public.ai_assist_planning_links', 'INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has direct INSERT on ai_assist_planning_links';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.ai_assist_planning_links', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated is missing SELECT on ai_assist_planning_links';
  END IF;

  RAISE NOTICE 'ai assistant schema contracts: all held';
END $$;
```

- [ ] **Step 7: Run the tests to verify they fail**

Run: `psql -q -d attune_test -f supabase/tests/ai_assistant_schema_contracts.sql`
Expected: fails with `relation "public.ai_assist_drafts" does not exist`
(or similar) before Step 1's migration exists — confirm this fails NOW by
temporarily checking out only this test file against last commit if
needed, or simply trust Step 5/6's ordering (write test after migration is
already possible; the important confirmation is Step 8's post-migration
pass, and re-running against a pre-migration checkout is optional but
recommended if you want the strongest possible confirmation the test is
wired correctly).

- [ ] **Step 8: Run the migrations and re-run the tests**

Run: `scripts/local_pg_setup.sh --no-tests`, then
`psql -q -d attune_test -f supabase/tests/ai_assistant_schema_contracts.sql`
Expected: `NOTICE: ai assistant schema contracts: all held`.

- [ ] **Step 9: Mutation-test every contract — this is not optional**

For EACH of contracts 2 through 10, temporarily weaken the specific piece
of schema/RLS/grant it protects (drop the relevant CHECK constraint;
comment out the RLS policy's `EXISTS(...)` and replace with `true`; add
back a `GRANT` you then remove), re-run the test file, confirm it now
fails with the expected `EXPLOIT:` message, then restore exactly and
re-run to confirm it passes again. Record each result as a one-line note
in this task's final report.

- [ ] **Step 10: Write the user-JWT-scoped client helper**

First, read `supabase/functions/_shared/attune_auth.ts` in full to confirm
`requireUser`'s exact current signature and the `AuthenticatedUser` type
shape before writing code against it — do not assume the shape below is
still accurate without checking.

Create `supabase/functions/_shared/user_scoped_client.ts`:

```typescript
// A Supabase client scoped to the calling user's own JWT, so every query
// issued through it runs under RLS as that user -- not the service-role
// key every other edge function in this codebase uses today.
//
// Spec: docs/superpowers/specs/2026-09-15-ai-assistant-design.md §4.2.
// "Each function uses a user-JWT-scoped Supabase client for content
// reads -- not an unrestricted service-role read." This is new
// infrastructure: no existing edge function in this repository does
// this (verified: every one of analyse-message, analyse-session,
// translate-conflict, generate-verdict, etc. reads via
// serviceRoleClient() and authorizes by hand in application code).
// Building this helper, and using it for every content read in
// ai-assist/ai-understand, is what makes "the client cannot fabricate
// context" a database-enforced guarantee rather than an
// application-code promise.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireEnv, requireUser, AuthenticatedUser } from "./attune_auth.ts";

export interface UserScopedContext {
  client: SupabaseClient;
  user: AuthenticatedUser;
}

export async function userScopedClient(req: Request): Promise<UserScopedContext> {
  // requireUser already validates the bearer token via auth.getUser and
  // throws HttpError(401) on failure -- reuse it rather than re-deriving
  // the same check, so both functions fail identically to every other
  // authenticated edge function in this codebase.
  const user = await requireUser(req);

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();

  const client = createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );

  return { client, user };
}
```

If `requireEnv`/`AuthenticatedUser`/`SUPABASE_ANON_KEY` are not already
exported/available exactly as referenced above, adjust to match what
`attune_auth.ts` actually exports — read the file first, do not guess.

- [ ] **Step 11: Write the failing test for the client helper**

Create `supabase/functions/_shared/user_scoped_client.test.ts`:

```typescript
// Proves userScopedClient constructs a client authorized as the caller,
// not the service role -- i.e. that querying through it is subject to
// RLS. This test needs a real Supabase local instance running (the same
// one supabase/tests/*.sql run against) since it exercises real
// PostgREST/RLS behavior, not a mock.
import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { userScopedClient } from "./user_scoped_client.ts";

Deno.test("userScopedClient rejects a request with no Authorization header", async () => {
  const req = new Request("http://localhost/test", { method: "POST" });
  await assertRejects(() => userScopedClient(req));
});

Deno.test("userScopedClient rejects an invalid bearer token", async () => {
  const req = new Request("http://localhost/test", {
    method: "POST",
    headers: { Authorization: "Bearer not-a-real-token" },
  });
  await assertRejects(() => userScopedClient(req));
});

// A full "does RLS actually apply" integration test requires a real
// signed-in test user's JWT (not fabricable in a unit test without
// hitting the Auth API) -- that end-to-end proof belongs in Task 2's
// context-loader tests, which run against a real local Supabase
// instance with a real test user session. This file proves the helper's
// own auth-failure paths; Task 2 proves RLS is actually the operative
// authority once a real token is available.
```

- [ ] **Step 12: Run the tests, then the migrations, then re-run**

Run: `deno test --allow-net --allow-env
supabase/functions/_shared/user_scoped_client.test.ts`
Expected: both tests pass (they only exercise the failure paths, which
don't require a live database).

- [ ] **Step 13: Run the full existing SQL suite to check for regressions**

Run: `for f in supabase/tests/*.sql; do psql -q -d attune_test -f "$f" ||
echo "FAILED: $f"; done`
Expected: no `FAILED:` lines.

- [ ] **Step 14: Commit**

```bash
git add supabase/migrations/20260950010000_ai_assistant_schema.sql \
        supabase/migrations/20260950020000_ai_assistant_rls.sql \
        supabase/migrations/20260950030000_ai_assistant_table_grants.sql \
        scripts/local_pg_grants.sql \
        supabase/functions/_shared/user_scoped_client.ts \
        supabase/functions/_shared/user_scoped_client.test.ts \
        supabase/tests/ai_assistant_schema_contracts.sql
git commit -m "feat(ai-assistant): schema, RLS, grants, and the user-JWT-scoped client helper"
```

---

## Task 2: Trusted context loader

**Files:**
- Create: `supabase/functions/_shared/ai_context_loader.ts`
- Test: `supabase/functions/_shared/ai_context_loader.test.ts`

**Interfaces:**
- Consumes: `userScopedClient` (Task 1).
- Produces:
  `loadAiAssistantTarget(client: SupabaseClient, userId: string, messageId:
  string): Promise<TargetLoadResult>` and
  `loadBoundedContext(client: SupabaseClient, target: LoadedTarget, mode:
  'assist' | 'understand', requesterId: string, utcOffsetMinutes?: number):
  Promise<ContextMessage[]>`. `TargetLoadResult` is a discriminated union:
  `{ ok: true; target: LoadedTarget } | { ok: false; code:
  'TARGET_UNAVAILABLE' }`. `LoadedTarget` carries `{ messageId: string;
  relationshipId: string; senderId: string; createdAt: string; content:
  string }`. `ContextMessage` carries `{ role: 'requester' | 'partner';
  createdAt: string; content: string; truncated: boolean }` — never a
  name or a UUID. `requesterId` is the authenticated caller's own id
  (from `userScopedClient`'s returned `user.id`), used only to label each
  context row `'requester'` or `'partner'` relative to the caller — it is
  never sent to the model as a UUID, only as that pseudonymous role
  string. Both edge functions (Task 6, Task 7) call these two functions
  and nothing else for context construction.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/_shared/ai_context_loader.test.ts`. This needs
real fixture data and a real user session against the local Supabase
instance (RLS-dependent behavior cannot be meaningfully unit-tested with a
mock client — a mock would just prove the mock returns what you told it
to). Structure:

```typescript
// Proves loadAiAssistantTarget/loadBoundedContext are the sole trusted
// context boundary: a non-member cannot load a target from a
// relationship they don't belong to (proven via real RLS, not an
// application-code check), context never leaks names/UUIDs, and the
// two modes' row/character caps are enforced exactly as specced.
//
// Spec: docs/superpowers/specs/2026-09-15-ai-assistant-design.md §4.2, §4.3.
//
// Requires the local Supabase stack running (same instance
// supabase/tests/*.sql target) plus two real signed-up test users with
// real JWTs -- fabricate via the Auth Admin API against the local
// instance's service-role key, the same way any existing edge-function
// integration test in this repo that needs a real session does (check
// an existing *.test.ts file under supabase/functions/ for the exact
// sign-up/sign-in helper pattern already used in this codebase before
// writing a new one from scratch).

import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  loadAiAssistantTarget,
  loadBoundedContext,
} from "./ai_context_loader.ts";

// ... fixture setup: two relationships (rel_a: user_a + user_b, rel_c:
// user_c alone), messages seeded directly via service-role insert into
// rel_a and rel_c, then userScopedClient-shaped clients built from each
// test user's real JWT.

Deno.test("loadAiAssistantTarget returns TARGET_UNAVAILABLE for a message in a relationship the caller isn't in", async () => {
  // user_c's client attempts to load a message that belongs to rel_a.
  // Assert result.ok === false && result.code === 'TARGET_UNAVAILABLE'.
});

Deno.test("loadAiAssistantTarget returns TARGET_UNAVAILABLE for a deleted message", async () => {});

Deno.test("loadAiAssistantTarget returns TARGET_UNAVAILABLE for a message that does not exist at all", async () => {
  // Same error code as the two tests above -- not TARGET_UNAVAILABLE vs
  // a 404-shaped "not found" -- the endpoint must not be an existence
  // oracle (spec §4.2).
});

Deno.test("loadAiAssistantTarget returns TARGET_UNAVAILABLE when the relationship is archived", async () => {});

Deno.test("loadAiAssistantTarget succeeds for a live, eligible message in the caller's own active relationship", async () => {});

Deno.test("loadBoundedContext for Assist returns at most 6 other messages, nearest-first then chronological", async () => {
  // Seed 10 messages around the target (5 before, 5 after); assert
  // exactly 6 returned, and assert they are the nearest 3 before + 3
  // after by (created_at, id), not by raw insert order.
});

Deno.test("loadBoundedContext for Understand returns target plus at most 19 within the civil day, 12 before/7 after", async () => {
  // Seed messages spanning into the adjacent civil day too; assert
  // messages outside the target's own civil day (per the given
  // utc_offset_minutes) never appear, and the 12-before/7-after split is
  // exactly as specced.
});

Deno.test("context messages carry role/createdAt/content only -- no name, no user UUID, anywhere in the returned shape", async () => {});

Deno.test("a surrounding message over 1,000 PostgreSQL characters is clipped with an explicit truncated marker", async () => {});

Deno.test("context construction stops adding candidates once the combined text would exceed 12,000 PostgreSQL characters, even if the row cap has not been reached", async () => {
  // Seed messages each near the 1,000-char clip boundary so the total
  // cap binds before the row-count cap does; assert fewer than the
  // mode's row cap were actually returned.
});

Deno.test("context excludes deleted rows, system notices, and attune_assist-origin messages from the returned set", async () => {});

Deno.test("Understand's civil-day boundary is derived from utc_offset_minutes but the 19-row cap is always primary -- an extreme offset cannot expose an unbounded day", async () => {
  // Pass utc_offset_minutes at both range extremes (-840, 840) against a
  // day with many messages; assert the row cap still holds regardless of
  // which civil day the offset selects.
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `deno test --allow-net --allow-env
supabase/functions/_shared/ai_context_loader.test.ts`
Expected: fails — the module does not exist yet.

- [ ] **Step 3: Write `ai_context_loader.ts`**

```typescript
// Trusted, server-side context construction for the AI Assistant. This
// is the file that makes client-supplied chat context structurally
// impossible: both ai-assist and ai-understand call ONLY these two
// functions to learn anything about a message or its surrounding
// conversation. Spec §4.2, §4.3.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface LoadedTarget {
  messageId: string;
  relationshipId: string;
  senderId: string;
  createdAt: string;
  content: string;
}

export type TargetLoadResult =
  | { ok: true; target: LoadedTarget }
  | { ok: false; code: "TARGET_UNAVAILABLE" };

export interface ContextMessage {
  role: "requester" | "partner";
  createdAt: string;
  content: string;
  truncated: boolean;
}

const MAX_TARGET_CHARS = 4000;
const MAX_SURROUNDING_CHARS = 1000;
const MAX_TOTAL_CONTEXT_CHARS = 12000;
const ASSIST_ROW_CAP = 6;
const UNDERSTAND_ROW_CAP = 19;

export async function loadAiAssistantTarget(
  client: SupabaseClient,
  userId: string,
  messageId: string,
): Promise<TargetLoadResult> {
  // Query through the USER-SCOPED client (RLS-authorized), never
  // service-role -- if this row is not visible to this user under RLS,
  // the query returns nothing and we report TARGET_UNAVAILABLE, exactly
  // as if the row didn't exist. This is the load-bearing line: a
  // non-member's userScopedClient literally cannot see a row in another
  // couple's relationship, so there is no separate "check membership"
  // step to get wrong or bypass.
  const { data: message, error } = await client
    .from("messages")
    .select("id, relationship_id, sender_id, created_at, content, deleted_at, is_system_notice, message_origin, media_url, game_session_id")
    .eq("id", messageId)
    .maybeSingle();

  if (error || !message) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }
  if (message.deleted_at) return { ok: false, code: "TARGET_UNAVAILABLE" };
  if (message.is_system_notice) return { ok: false, code: "TARGET_UNAVAILABLE" };
  if (message.message_origin === "attune_assist") {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }
  if (message.media_url || message.game_session_id) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }
  const content = typeof message.content === "string" ? message.content : "";
  if (content.trim().length === 0) return { ok: false, code: "TARGET_UNAVAILABLE" };
  if (content.length > MAX_TARGET_CHARS) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }

  const { data: relationship, error: relError } = await client
    .from("relationships")
    .select("id, status, chat_archived_at, user_a, user_b")
    .eq("id", message.relationship_id)
    .maybeSingle();
  if (relError || !relationship) return { ok: false, code: "TARGET_UNAVAILABLE" };
  if (relationship.status !== "active" || relationship.chat_archived_at) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }
  if (relationship.user_a !== userId && relationship.user_b !== userId) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }

  return {
    ok: true,
    target: {
      messageId: message.id,
      relationshipId: message.relationship_id,
      senderId: message.sender_id,
      createdAt: message.created_at,
      content,
    },
  };
}

export async function loadBoundedContext(
  client: SupabaseClient,
  target: LoadedTarget,
  mode: "assist" | "understand",
  requesterId: string,
  utcOffsetMinutes?: number,
): Promise<ContextMessage[]> {
  const rowCap = mode === "assist" ? ASSIST_ROW_CAP : UNDERSTAND_ROW_CAP;
  const beforeCount = mode === "assist" ? 3 : 12;
  const afterCount = mode === "assist" ? 3 : 7;

  let dayStart: string | null = null;
  let dayEnd: string | null = null;
  if (mode === "understand") {
    const offset = utcOffsetMinutes ?? 0;
    const targetLocal = new Date(
      new Date(target.createdAt).getTime() + offset * 60_000,
    );
    const dayStartLocal = new Date(
      targetLocal.getFullYear(),
      targetLocal.getMonth(),
      targetLocal.getDate(),
    );
    dayStart = new Date(dayStartLocal.getTime() - offset * 60_000).toISOString();
    dayEnd = new Date(
      dayStartLocal.getTime() + 24 * 60 * 60_000 - offset * 60_000,
    ).toISOString();
  }

  let beforeQuery = client
    .from("messages")
    .select("id, sender_id, created_at, content, deleted_at, is_system_notice, message_origin, media_url, game_session_id")
    .eq("relationship_id", target.relationshipId)
    .lt("created_at", target.createdAt)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(beforeCount * 3); // overfetch before filtering; filtered client-side below
  if (dayStart) beforeQuery = beforeQuery.gte("created_at", dayStart);

  let afterQuery = client
    .from("messages")
    .select("id, sender_id, created_at, content, deleted_at, is_system_notice, message_origin, media_url, game_session_id")
    .eq("relationship_id", target.relationshipId)
    .gt("created_at", target.createdAt)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true })
    .limit(afterCount * 3);
  if (dayEnd) afterQuery = afterQuery.lt("created_at", dayEnd);

  const [{ data: beforeRows }, { data: afterRows }] = await Promise.all([
    beforeQuery,
    afterQuery,
  ]);

  const isEligible = (row: Record<string, unknown>) =>
    !row.deleted_at &&
    !row.is_system_notice &&
    row.message_origin !== "attune_assist" &&
    !row.media_url &&
    !row.game_session_id &&
    typeof row.content === "string" &&
    (row.content as string).trim().length > 0;

  const before = (beforeRows ?? []).filter(isEligible).slice(0, beforeCount);
  const after = (afterRows ?? []).filter(isEligible).slice(0, afterCount);

  const candidates = [...before.reverse(), ...after].slice(0, rowCap);

  const toContextMessage = (row: Record<string, unknown>): ContextMessage => {
    const content = row.content as string;
    const truncated = content.length > MAX_SURROUNDING_CHARS;
    return {
      role: row.sender_id === requesterId ? "requester" : "partner",
      createdAt: row.created_at as string,
      content: truncated
        ? `${content.slice(0, MAX_SURROUNDING_CHARS)} [truncated]`
        : content,
      truncated,
    };
  };

  const withTarget = candidates.map(toContextMessage);
  let totalChars = target.content.length;
  const result: ContextMessage[] = [];
  for (const msg of withTarget) {
    if (totalChars + msg.content.length > MAX_TOTAL_CONTEXT_CHARS) break;
    result.push(msg);
    totalChars += msg.content.length;
  }

  return result.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `deno test --allow-net --allow-env
supabase/functions/_shared/ai_context_loader.test.ts`
Expected: all pass.

- [ ] **Step 5: Mutation-test the row/character caps and the RLS boundary**

For each of: the Assist 6-row cap, the Understand 19-row cap, the 1,000-
char surrounding-message clip, the 12,000-char total cap, and the civil-
day boundary — temporarily widen or remove the specific limit, confirm
the corresponding test fails, restore, confirm it passes again. For the
RLS boundary specifically: temporarily have `loadAiAssistantTarget` query
via a service-role client instead of the passed-in `client` parameter,
confirm the non-member test now wrongly succeeds (proving the user-scoped
client, not application logic, was doing the real work), restore.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/_shared/ai_context_loader.ts \
        supabase/functions/_shared/ai_context_loader.test.ts
git commit -m "feat(ai-assistant): trusted server-side context loader"
```

---

## Task 3: Consent RPCs

**Files:**
- Create: `supabase/migrations/20260950040000_ai_processing_consent_rpcs.sql`
- Test: `supabase/tests/ai_processing_consent_contracts.sql`

**Interfaces:**
- Consumes: `ai_processing_consent_events` (Task 1).
- Produces:
  `record_ai_processing_consent(p_relationship_id uuid, p_action text,
  p_idempotency_key uuid) RETURNS void`,
  `get_ai_processing_consent_status(p_relationship_id uuid) RETURNS TABLE
  (caller_granted boolean, both_granted boolean, policy_version text)`.
  Both edge functions (Task 4, Task 5) and Plan B's client call these
  exact names.

- [ ] **Step 1: Write the failing tests**

Create `supabase/tests/ai_processing_consent_contracts.sql`:

```sql
-- Consent RPC contracts (Plan A, Task 3).
-- Run: psql -q -d attune_test -f supabase/tests/ai_processing_consent_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a3000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a3000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a3000000-0000-0000-0000-00000000000b';
  v_user_stranger uuid := 'a3000000-0000-0000-0000-00000000000c';
  v_row record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'consent_a@t.test'), (v_user_b, 'consent_b@t.test'),
    (v_user_stranger, 'consent_c@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550003001', 'A'), (v_user_b, '+15550003002', 'B'),
    (v_user_stranger, '+15550003003', 'C')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 1: a non-member cannot record consent for a relationship
  -- they don't belong to.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_stranger), true);
  BEGIN
    PERFORM public.record_ai_processing_consent(v_rel, 'granted', gen_random_uuid());
    RAISE EXCEPTION 'EXPLOIT: a non-member recorded consent';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 2: before either partner grants, status shows neither
  -- granted.
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.caller_granted IS DISTINCT FROM false OR v_row.both_granted IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: status showed granted before any consent event';
  END IF;

  -- Contract 3: user_a grants; status shows caller_granted true,
  -- both_granted false (user_b has not granted).
  PERFORM public.record_ai_processing_consent(v_rel, 'granted', gen_random_uuid());
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.caller_granted IS DISTINCT FROM true OR v_row.both_granted IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: status wrong after only one partner granted';
  END IF;

  -- Contract 4: user_b grants too; both_granted flips true.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  PERFORM public.record_ai_processing_consent(v_rel, 'granted', gen_random_uuid());
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.both_granted IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: both_granted did not flip true after both partners granted';
  END IF;

  -- Contract 5: status never reveals the PARTNER's own granted state
  -- distinctly from both_granted -- i.e. caller_granted always reflects
  -- the CALLER, not whichever partner happens to be "further along".
  -- Verify by checking user_a's own view still shows their own state
  -- correctly even though user_b granted more recently.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.caller_granted IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: caller_granted did not reflect the calling user''s own event';
  END IF;

  -- Contract 6: withdrawal flips caller_granted back to false and
  -- both_granted back to false.
  PERFORM public.record_ai_processing_consent(v_rel, 'withdrawn', gen_random_uuid());
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.caller_granted IS DISTINCT FROM false OR v_row.both_granted IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: withdrawal did not clear caller_granted/both_granted';
  END IF;

  -- Contract 7: retrying record_ai_processing_consent with the SAME
  -- idempotency_key is a no-op (the UNIQUE constraint from Task 1 is the
  -- backstop, but the RPC itself must not error on a legitimate client
  -- retry -- it should treat a conflict as "already recorded").
  DECLARE
    v_idem uuid := gen_random_uuid();
  BEGIN
    PERFORM public.record_ai_processing_consent(v_rel, 'granted', v_idem);
    PERFORM public.record_ai_processing_consent(v_rel, 'granted', v_idem);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'EXPLOIT: retrying record_ai_processing_consent with the same idempotency_key errored: %', SQLERRM;
  END;

  -- Contract 8: a non-member cannot read consent status either.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_stranger), true);
  BEGIN
    PERFORM public.get_ai_processing_consent_status(v_rel);
    RAISE EXCEPTION 'EXPLOIT: a non-member read consent status';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'ai processing consent contracts: all held';
END $$;
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `psql -q -d attune_test -f
supabase/tests/ai_processing_consent_contracts.sql`
Expected: fails — `function public.record_ai_processing_consent(...)
does not exist`.

- [ ] **Step 3: Write `20260950040000_ai_processing_consent_rpcs.sql`**

```sql
-- Consent RPCs. Spec §7.2, §10.1. The server owns the "current"
-- policy_version constant below -- bump it here (a single migration
-- adding a new DEFAULT-driving constant, or hardcode a new literal in
-- both functions in a follow-up migration) when the disclosure text
-- materially changes; a version bump requires two fresh grants under
-- the new version per spec §7.2.
CREATE OR REPLACE FUNCTION public.ai_current_consent_policy_version()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'v1'::text;
$$;

CREATE OR REPLACE FUNCTION public.record_ai_processing_consent(
  p_relationship_id uuid, p_action text, p_idempotency_key uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_action NOT IN ('granted', 'withdrawn') THEN
    RAISE EXCEPTION 'Invalid action';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = v_actor OR r.user_b = v_actor)
  ) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key)
  VALUES (
    p_relationship_id, v_actor, public.ai_current_consent_policy_version(),
    p_action, p_idempotency_key
  )
  ON CONFLICT (user_id, idempotency_key) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.record_ai_processing_consent(uuid, text, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_ai_processing_consent(uuid, text, uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_ai_processing_consent_status(
  p_relationship_id uuid
) RETURNS TABLE (caller_granted boolean, both_granted boolean, policy_version text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_version text := public.ai_current_consent_policy_version();
  v_user_a uuid;
  v_user_b uuid;
  v_a_granted boolean;
  v_b_granted boolean;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = p_relationship_id
    AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = v_actor OR r.user_b = v_actor);
  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  -- "Current" for a user = their latest event at the CURRENT policy
  -- version. An event at an older version never counts as granted --
  -- this is what makes a version bump require two fresh grants.
  SELECT (action = 'granted') INTO v_a_granted
  FROM public.ai_processing_consent_events
  WHERE relationship_id = p_relationship_id AND user_id = v_user_a
    AND policy_version = v_version
  ORDER BY created_at DESC, id DESC LIMIT 1;

  SELECT (action = 'granted') INTO v_b_granted
  FROM public.ai_processing_consent_events
  WHERE relationship_id = p_relationship_id AND user_id = v_user_b
    AND policy_version = v_version
  ORDER BY created_at DESC, id DESC LIMIT 1;

  RETURN QUERY SELECT
    COALESCE(CASE WHEN v_actor = v_user_a THEN v_a_granted ELSE v_b_granted END, false),
    COALESCE(v_a_granted, false) AND COALESCE(v_b_granted, false),
    v_version;
END;
$$;
REVOKE ALL ON FUNCTION public.get_ai_processing_consent_status(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ai_processing_consent_status(uuid)
  TO authenticated;
```

- [ ] **Step 4: Rebuild and run the tests**

Run: `scripts/local_pg_setup.sh --no-tests`, then
`psql -q -d attune_test -f supabase/tests/ai_processing_consent_contracts.sql`
Expected: `NOTICE: ai processing consent contracts: all held`.

- [ ] **Step 5: Mutation-test contracts 1, 5, 6, and 8 specifically**

These are the security/privacy-critical ones: contract 1 (non-member
cannot grant), contract 5/withdrawal-6 (a user's own status is never
confused with their partner's), contract 8 (non-member cannot read
status). For each, comment out the specific membership check or the
specific `v_actor = v_user_a` branch, confirm the test fails, restore,
confirm it passes again.

- [ ] **Step 6: Run the full existing SQL suite to check for regressions**

Run: `for f in supabase/tests/*.sql; do psql -q -d attune_test -f "$f" ||
echo "FAILED: $f"; done`

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260950040000_ai_processing_consent_rpcs.sql \
        supabase/tests/ai_processing_consent_contracts.sql
git commit -m "feat(ai-assistant): consent grant/withdrawal/status RPCs"
```

---

## Task 4: Atomic quota reservation

**Files:**
- Create: `supabase/migrations/20260950050000_ai_assistant_quota_rpcs.sql`
- Test: `supabase/tests/ai_assistant_quota_contracts.sql`

**Interfaces:**
- Consumes: `ai_assistant_usage` (Task 1).
- Produces:
  `reserve_ai_assistant_quota(p_request_id uuid, p_relationship_id uuid,
  p_mode text) RETURNS TABLE (outcome text, retry_after_seconds int)`,
  `mark_ai_assistant_usage_outcome(p_request_id uuid, p_outcome text,
  p_provider_calls smallint) RETURNS void`. Both edge functions (Task 4→5
  renumbered as edge-function tasks below) call these by exact name.

- [ ] **Step 1: Write the failing tests**

Create `supabase/tests/ai_assistant_quota_contracts.sql`:

```sql
-- Atomic quota ledger contracts (Plan A, Task 4).
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_quota_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a4000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a4000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a4000000-0000-0000-0000-00000000000b';
  v_req_1 uuid := 'a4000000-0000-0000-0000-000000000101';
  v_req_2 uuid := 'a4000000-0000-0000-0000-000000000102';
  v_row record;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'quota_a@t.test'), (v_user_b, 'quota_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550004001', 'A'), (v_user_b, '+15550004002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 1: a fresh reservation succeeds.
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_req_1, v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: a fresh reservation did not succeed, got %', v_row.outcome;
  END IF;

  -- Contract 2: retrying the SAME request_id returns the existing
  -- reservation state without inserting a second row.
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_req_1, v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: retrying the same request_id did not return the existing reservation';
  END IF;
  SELECT count(*) INTO v_count FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: retrying the same request_id inserted a duplicate row';
  END IF;

  -- Contract 3: reusing the SAME request_id for a DIFFERENT mode is
  -- rejected as a conflict (a client bug, not a legitimate retry).
  BEGIN
    PERFORM public.reserve_ai_assistant_quota(v_req_1, v_rel, 'understand');
    RAISE EXCEPTION 'EXPLOIT: request_id reuse with a different mode was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: 20 distinct successful reservations exhaust the rolling
  -- window; the 21st is rejected with RATE_LIMITED and a positive
  -- retry_after_seconds.
  FOR i IN 2..20 LOOP
    PERFORM public.reserve_ai_assistant_quota(gen_random_uuid(), v_rel, 'assist');
  END LOOP;
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(gen_random_uuid(), v_rel, 'understand');
  IF v_row.outcome IS DISTINCT FROM 'rate_limited' OR v_row.retry_after_seconds IS NULL OR v_row.retry_after_seconds <= 0 THEN
    RAISE EXCEPTION 'EXPLOIT: the 21st reservation in 24h was not rejected with a positive retry time, got outcome=% retry=%', v_row.outcome, v_row.retry_after_seconds;
  END IF;

  -- Contract 5: the quota is per-user, not per-relationship -- user_b
  -- in the SAME relationship still has their own full quota.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(gen_random_uuid(), v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: user_b was rate-limited by user_a''s usage in the same relationship';
  END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 6: mark_ai_assistant_usage_outcome updates the row's own
  -- outcome/provider_calls without touching any other row.
  PERFORM public.mark_ai_assistant_usage_outcome(v_req_1, 'succeeded', 1);
  SELECT outcome, provider_calls INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF v_row.outcome IS DISTINCT FROM 'succeeded' OR v_row.provider_calls IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: mark_ai_assistant_usage_outcome did not update the row correctly';
  END IF;

  -- Contract 7: a non-owner cannot mark another user's usage row.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  BEGIN
    PERFORM public.mark_ai_assistant_usage_outcome(v_req_1, 'succeeded', 2);
    RAISE EXCEPTION 'EXPLOIT: user_b marked user_a''s own usage row';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'ai assistant quota contracts: all held';
END $$;
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `psql -q -d attune_test -f
supabase/tests/ai_assistant_quota_contracts.sql`
Expected: fails — function does not exist.

- [ ] **Step 3: Write `20260950050000_ai_assistant_quota_rpcs.sql`**

```sql
-- Atomic quota ledger. Spec §7.3. "One database operation" means the
-- INSERT ... ON CONFLICT DO NOTHING RETURNING pattern below runs as a
-- single statement -- the row-lock implicit in that statement is what
-- serializes concurrent callers with the SAME request_id, and the
-- window-count SELECT that follows only needs to be correct "as of this
-- transaction", not additionally locked, because a race between two
-- DIFFERENT request_ids both landing in the same rolling window is
-- expected and fine (both get counted; the 21st either way is rejected).
CREATE OR REPLACE FUNCTION public.reserve_ai_assistant_quota(
  p_request_id uuid, p_relationship_id uuid, p_mode text
) RETURNS TABLE (outcome text, retry_after_seconds int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_existing public.ai_assistant_usage;
  v_count int;
  v_oldest timestamptz;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_mode NOT IN ('assist', 'understand') THEN
    RAISE EXCEPTION 'Invalid mode';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = v_actor OR r.user_b = v_actor)
  ) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT * INTO v_existing FROM public.ai_assistant_usage WHERE request_id = p_request_id;
  IF v_existing.request_id IS NOT NULL THEN
    IF v_existing.user_id IS DISTINCT FROM v_actor OR v_existing.mode IS DISTINCT FROM p_mode THEN
      RAISE EXCEPTION 'A different reservation already exists with this request id';
    END IF;
    RETURN QUERY SELECT 'reserved'::text, NULL::int;
    RETURN;
  END IF;

  SELECT count(*), min(created_at) INTO v_count, v_oldest
  FROM public.ai_assistant_usage
  WHERE user_id = v_actor
    AND created_at >= now() - interval '24 hours'
    AND outcome NOT IN ('rejected', 'cancelled');

  IF v_count >= 20 THEN
    RETURN QUERY SELECT
      'rate_limited'::text,
      GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_oldest + interval '24 hours' - now())))::int);
    RETURN;
  END IF;

  INSERT INTO public.ai_assistant_usage
    (request_id, user_id, relationship_id, mode, outcome)
  VALUES (p_request_id, v_actor, p_relationship_id, p_mode, 'reserved');

  RETURN QUERY SELECT 'reserved'::text, NULL::int;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_ai_assistant_quota(uuid, uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_ai_assistant_quota(uuid, uuid, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_ai_assistant_usage_outcome(
  p_request_id uuid, p_outcome text, p_provider_calls smallint
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  UPDATE public.ai_assistant_usage
  SET outcome = p_outcome, provider_calls = p_provider_calls, updated_at = now()
  WHERE request_id = p_request_id AND user_id = v_actor;
  -- Deliberately silent (no exception) if no row matched -- this can
  -- legitimately happen if a client calls this after its own reserve
  -- call raced/failed; the caller has no reservation to update in that
  -- case, which is not itself an error.
END;
$$;
REVOKE ALL ON FUNCTION public.mark_ai_assistant_usage_outcome(uuid, text, smallint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_ai_assistant_usage_outcome(uuid, text, smallint)
  TO authenticated;
```

- [ ] **Step 4: Rebuild and run the tests**

Run: `scripts/local_pg_setup.sh --no-tests`, then
`psql -q -d attune_test -f supabase/tests/ai_assistant_quota_contracts.sql`
Expected: `NOTICE: ai assistant quota contracts: all held`.

- [ ] **Step 5: Mutation-test the concurrency-critical contracts**

Contract 4 (20-then-rejected boundary) and contract 7 (non-owner cannot
mark another's row) are the highest-risk. For contract 4: change the `>=
20` to `> 20`, confirm the 21st reservation wrongly succeeds, restore,
confirm rejected again. For the ACTUAL concurrency case (not just the
sequential-count logic): open two separate `psql` sessions, each racing
`reserve_ai_assistant_quota` with a NEW distinct `request_id` when the
caller is already at exactly 19 successful reservations; confirm exactly
one of the two succeeds and the other is rejected (not both succeeding
and exceeding 20), by running both concurrently with overlapping open
transactions. Record the result in this task's report.

- [ ] **Step 6: Run the full existing SQL suite to check for regressions**

Run: `for f in supabase/tests/*.sql; do psql -q -d attune_test -f "$f" ||
echo "FAILED: $f"; done`

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260950050000_ai_assistant_quota_rpcs.sql \
        supabase/tests/ai_assistant_quota_contracts.sql
git commit -m "feat(ai-assistant): atomic per-user quota reservation ledger"
```

---

## Task 5: Relationship-analysis exclusion — make `message_analysis_skipped` real

**Files:**
- Modify: `supabase/functions/analyse-message/index.ts`
- Modify: `supabase/functions/analyse-session/index.ts`
- Create: `supabase/migrations/20260950060000_message_analysis_skipped_backlog_index.sql`
- Test: `supabase/functions/analyse-message/index.test.ts` (extend existing)
- Test: `supabase/functions/analyse-session/index.test.ts` (extend existing,
  or create if it does not already exist — check first)
- Create: `supabase/tests/message_analysis_skipped_contracts.sql`

**Interfaces:**
- Consumes: `messages.message_analysis_skipped` (already exists — this
  task makes it real, does not create it).
- Produces: nothing new callable — this task changes existing query
  behavior. Later tasks (the Assist share RPC in Task 6) depend on this
  task already being done, since sharing an Assist message sets this flag
  and needs every consumer to already honor it.

This task must be done BEFORE Task 6, because Task 6's share RPC sets
`message_analysis_skipped = true` and this task is what makes that flag
actually exclude the row everywhere it needs to.

- [ ] **Step 1: Read the real current state of every affected file — do
  not trust this plan's line numbers, they will drift**

Read `supabase/functions/analyse-message/index.ts` in full and find every
line that filters or selects on `message_analysis_done`. Read
`supabase/functions/analyse-session/index.ts` in full and do the same.
Read `supabase/migrations/20260830120000_chat_pulse_signals.sql` in full
and find every SQL join/filter on `message_analysis_done = true`. Read
`supabase/migrations/20260705173000_analysis_pipeline_foundations.sql`
and find `idx_messages_analysis_backlog`'s exact current definition. Write
down the exact line numbers/query shapes you find before making any edit —
this plan was written by reading these files once; re-verify, since other
work may have touched them since.

- [ ] **Step 2: Write the failing SQL contract test**

Create `supabase/tests/message_analysis_skipped_contracts.sql`:

```sql
-- Proves idx_messages_analysis_backlog excludes deliberately-skipped
-- rows once Step 4 below updates it. Run:
-- psql -q -d attune_test -f supabase/tests/message_analysis_skipped_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a5000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a5000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a5000000-0000-0000-0000-00000000000b';
  v_msg_done uuid := 'a5000000-0000-0000-0000-000000000101';
  v_msg_pending uuid := 'a5000000-0000-0000-0000-000000000102';
  v_msg_skipped uuid := 'a5000000-0000-0000-0000-000000000103';
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'skip_a@t.test'), (v_user_b, 'skip_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550005001', 'A'), (v_user_b, '+15550005002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.messages (id, relationship_id, sender_id,
    client_message_id, content, source, message_analysis_done,
    message_analysis_skipped, safety_processed_at)
  VALUES
    (v_msg_done, v_rel, v_user_a, gen_random_uuid(), 'analyzed already', 'native', true, false, now()),
    (v_msg_pending, v_rel, v_user_a, gen_random_uuid(), 'not yet analyzed', 'native', false, false, now()),
    (v_msg_skipped, v_rel, v_user_a, gen_random_uuid(), 'deliberately skipped', 'native', false, true, now());

  -- Contract 1: the backlog index's own predicate (read directly from
  -- pg_indexes -- confirming the DEFINITION, not merely that a query
  -- against the table happens to return the right rows some other way)
  -- excludes message_analysis_skipped = true rows.
  IF (
    SELECT indexdef FROM pg_indexes
    WHERE indexname = 'idx_messages_analysis_backlog'
  ) NOT LIKE '%message_analysis_skipped%' THEN
    RAISE EXCEPTION 'EXPLOIT: idx_messages_analysis_backlog does not reference message_analysis_skipped at all';
  END IF;

  -- Contract 2: a query shaped exactly like analyse-message's own
  -- candidate-selection query (done=false AND skipped=false) returns the
  -- pending message but not the skipped one.
  SELECT count(*) INTO v_count FROM public.messages
  WHERE relationship_id = v_rel
    AND message_analysis_done = false
    AND message_analysis_skipped = false
    AND safety_processed_at IS NOT NULL;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: candidate-selection shape returned % rows, expected exactly 1 (the pending message)', v_count;
  END IF;

  RAISE NOTICE 'message_analysis_skipped contracts: all held';
END $$;
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `psql -q -d attune_test -f
supabase/tests/message_analysis_skipped_contracts.sql`
Expected: fails on contract 1 (`idx_messages_analysis_backlog` does not
yet reference the column).

- [ ] **Step 4: Update `idx_messages_analysis_backlog`**

Create `supabase/migrations/20260950060000_message_analysis_skipped_backlog_index.sql`.
First read the index's exact current `CREATE INDEX` statement (Step 1
already found it) and write a migration that drops and recreates it with
`AND message_analysis_skipped = false` added to its `WHERE` clause (or
wherever the predicate structurally belongs given the real current
definition — do not guess the shape, use what Step 1 found):

```sql
-- Excludes deliberately-skipped messages (AI Assistant Assist-mode
-- output) from the analysis backlog index, so a skipped row can never
-- keep the backlog/health metric permanently red. Spec
-- docs/superpowers/specs/2026-09-15-ai-assistant-design.md §8.2.
DROP INDEX IF EXISTS public.idx_messages_analysis_backlog;

-- Replace the CREATE INDEX below with the real prior definition's exact
-- columns, just adding "AND message_analysis_skipped = false" to the
-- WHERE clause -- this placeholder assumes the shape found in
-- 20260705173000_analysis_pipeline_foundations.sql; verify against the
-- actual file before finalizing this migration.
CREATE INDEX idx_messages_analysis_backlog
  ON public.messages (relationship_id, created_at)
  WHERE message_analysis_done = false AND message_analysis_skipped = false;
```

- [ ] **Step 5: Add the filter to `analyse-message/index.ts`'s two real
  query sites**

At the candidate-selection query (the one currently filtering
`.eq("message_analysis_done", false)`), add
`.eq("message_analysis_skipped", false)`. At the mark-done exclusion
query (the second `.eq("message_analysis_done", false)` site), add the
same. Use the exact real line locations found in Step 1, not any line
number stated elsewhere in this plan.

- [ ] **Step 6: Add the filter to `analyse-session/index.ts`'s two real
  query sites**

Both of its `.eq("message_analysis_done", true)` selection queries must
additionally exclude skipped rows: add `.eq("message_analysis_skipped",
false)` to each. Read the surrounding code first — these queries select
messages considered DONE for Layer 2/session-transcript purposes; the
whole point of this task is that a skipped message must never reach this
query either, so it must never be treated as "done" in a way that lets it
in, AND it must be filtered out defensively here too in case some other
path ever marks it done by mistake.

- [ ] **Step 7: Add the filter to Pulse's SQL joins**

In `supabase/migrations/20260830120000_chat_pulse_signals.sql`'s own SQL,
the two `m.message_analysis_done = true` joins need
`AND m.message_analysis_skipped = false` added. This is a query INSIDE an
already-shipped migration file — do not edit that file's history; instead
create a new migration
(`supabase/migrations/20260950070000_pulse_exclude_skipped_messages.sql`)
that `CREATE OR REPLACE FUNCTION`s (or however that migration's queries
are actually packaged — check whether they live inside a function
definition or a bare view/materialized query, and adjust this step's
approach to match reality) with the added filter, following the "new
migration replaces old function" pattern this codebase already uses
everywhere (never edit a shipped migration file in place).

- [ ] **Step 8: Write the repository-wide regression test**

Add to (or create, if it does not exist)
`supabase/functions/analyse-message/index.test.ts` and
`supabase/functions/analyse-session/index.test.ts`: a test proving a
message with `message_analysis_skipped = true` is never selected as a
candidate by either function's own query, using the real Supabase client
shape each file already tests with (read the existing test file's fixture
/assertion pattern first and match it — do not introduce a new test
style).

- [ ] **Step 9: Rebuild, run the new SQL contract test, and run the
  extended function tests**

Run: `scripts/local_pg_setup.sh --no-tests`, then
`psql -q -d attune_test -f supabase/tests/message_analysis_skipped_contracts.sql`
(expect all held), then the Deno test commands for
`analyse-message/index.test.ts` and `analyse-session/index.test.ts`
(check each file's own header comment or the project's CI config for the
exact invocation used elsewhere in this repo).

- [ ] **Step 10: Mutation-test the exclusion — this is the one this whole
  task exists to protect**

Temporarily remove the `message_analysis_skipped` filter from EACH of the
(at least) 4 real query sites this task touches, one at a time, re-run
the corresponding test, confirm it fails, restore, confirm it passes
again. A single combined "remove all four at once" test is not
sufficient — removing them one at a time proves each site's filter is
independently load-bearing, not that only one of the four happens to be
doing all the work while the others are redundant or already covered by
something else.

- [ ] **Step 11: Run the full existing SQL and Deno test suites to check
  for regressions**

Run the SQL suite loop, and whatever this repo's existing command is for
running all edge-function Deno tests together (check for a project script
or CI config rather than guessing).

- [ ] **Step 12: Commit**

```bash
git add supabase/functions/analyse-message/index.ts \
        supabase/functions/analyse-message/index.test.ts \
        supabase/functions/analyse-session/index.ts \
        supabase/functions/analyse-session/index.test.ts \
        supabase/migrations/20260950060000_message_analysis_skipped_backlog_index.sql \
        supabase/migrations/20260950070000_pulse_exclude_skipped_messages.sql \
        supabase/tests/message_analysis_skipped_contracts.sql
git commit -m "fix(ai-assistant): make message_analysis_skipped a real exclusion everywhere"
```

---

## Task 6: `ai-assist` edge function, drafts, and the share RPC

**Files:**
- Create: `supabase/functions/ai-assist/index.ts`
- Create: `supabase/functions/ai-assist/prompts/v1/system.txt`
- Create: `supabase/functions/ai-assist/prompts/v1/user.txt`
- Create: `supabase/migrations/20260950080000_ai_assist_draft_and_share_rpcs.sql`
- Modify: `supabase/functions/_shared/gemini_port.test.ts`
- Test: `supabase/functions/ai-assist/index.test.ts`
- Test: `supabase/tests/ai_assist_draft_share_contracts.sql`

**Interfaces:**
- Consumes: `userScopedClient` (Task 1), `loadAiAssistantTarget`/
  `loadBoundedContext` (Task 2), `get_ai_processing_consent_status` (Task
  3), `reserve_ai_assistant_quota`/`mark_ai_assistant_usage_outcome` (Task
  4), `message_analysis_skipped` now being real (Task 5), `callGeminiJson`
  (existing shared helper).
- Produces: the `ai-assist` HTTP endpoint (request/response shapes exactly
  per spec §4.1/§5.3/§11); `insert_ai_assist_draft(...)` (service-role
  only, called from inside the edge function, never client-callable);
  `share_ai_assist_draft(p_draft_id uuid) RETURNS public.messages`. Plan
  B's client calls the HTTP endpoint and, indirectly via that endpoint's
  own share step, this RPC.

This is a large task. Read the spec's §4.1, §4.2 (already built in Task
2, just call it), §5.1, §5.3, §7.1, §7.3, §9, and §11 again immediately
before starting — this task is where most of those sections become real
code for the first time, and getting the SHAPE of the Ideas sub-flow
right here matters more than typing speed.

- [ ] **Step 1: Write the failing SQL contract tests for the draft/share
  RPCs**

Create `supabase/tests/ai_assist_draft_share_contracts.sql`. Cover (each
as its own contract, following the same `EXPLOIT:`-raising pattern every
other test file in this plan uses):

1. `insert_ai_assist_draft` is only callable by the service role (a
   direct `authenticated`-role call is rejected) — this proves "no user
   may supply draft output to that function" (spec §7.2) at the privilege
   layer, not just by convention.
2. A fresh, unexpired draft can be shared by its own requester via
   `share_ai_assist_draft`, producing exactly one `messages` row with
   `message_origin = 'attune_assist'`, `message_analysis_skipped = true`,
   and the draft's own `reply_text`/`assistant_payload` — verbatim, not a
   client-suppliable value.
3. `share_ai_assist_draft` is rejected for anyone other than the draft's
   own `requester_id`.
4. `share_ai_assist_draft` is rejected once `expires_at` has passed (seed
   a draft with `created_at`/`expires_at` in the past).
5. `share_ai_assist_draft` is rejected if the relationship is no longer
   active/unarchived at share time (seed an active relationship, create
   the draft, then archive the relationship, then attempt to share).
6. `share_ai_assist_draft` is rejected if the target message was deleted
   after the draft was created but before Share was tapped.
7. `share_ai_assist_draft` is rejected if dual consent is not currently
   granted (only one partner has granted, or neither).
8. Calling `share_ai_assist_draft` twice on the SAME already-shared draft
   returns the SAME existing message idempotently rather than erroring or
   creating a second message.
9. Sharing inserts a row that also satisfies the ordinary
   `enqueue_message_downstream_work` trigger's own effects — assert a
   `message_safety_outbox` row (or whatever this codebase's real outbox
   table/mechanism is named — check the actual trigger definition before
   writing this assertion) now exists for the new message, proving
   deterministic safety was not bypassed for AI-authored content.
10. `share_ai_assist_draft` never accepts a client-supplied
    replacement `reply_text`/`assistant_payload` parameter at all (the
    function signature itself only takes `p_draft_id` — confirm this by
    reading `pg_proc` for the function's actual argument list and
    asserting it has exactly one parameter).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `psql -q -d attune_test -f
supabase/tests/ai_assist_draft_share_contracts.sql`
Expected: fails — functions do not exist.

- [ ] **Step 3: Write `20260950080000_ai_assist_draft_and_share_rpcs.sql`**

```sql
-- Draft insertion (service-role only) and the share RPC. Spec §5.3,
-- §7.2.
CREATE OR REPLACE FUNCTION public.insert_ai_assist_draft(
  p_id uuid, p_relationship_id uuid, p_requester_id uuid,
  p_target_message_id uuid, p_reply_text text, p_assistant_payload jsonb
) RETURNS public.ai_assist_drafts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.ai_assist_drafts;
BEGIN
  INSERT INTO public.ai_assist_drafts (
    id, relationship_id, requester_id, target_message_id, reply_text,
    assistant_payload, created_at, expires_at
  ) VALUES (
    p_id, p_relationship_id, p_requester_id, p_target_message_id,
    btrim(p_reply_text), p_assistant_payload, now(), now() + interval '15 minutes'
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;
-- No GRANT to authenticated at all -- only the table owner (which the
-- edge function's service-role connection runs as) may call this. This
-- is the enforcement for "no user may supply draft output to this
-- function" (spec §7.2) -- verified by contract 1 above.
REVOKE ALL ON FUNCTION public.insert_ai_assist_draft(uuid, uuid, uuid, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.share_ai_assist_draft(
  p_draft_id uuid
) RETURNS public.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_draft public.ai_assist_drafts;
  v_target public.messages;
  v_rel public.relationships;
  v_consent record;
  v_message_id uuid;
  v_row public.messages;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_draft FROM public.ai_assist_drafts
  WHERE id = p_draft_id FOR UPDATE;
  IF v_draft.id IS NULL THEN
    RAISE EXCEPTION 'Draft unavailable';
  END IF;
  IF v_draft.requester_id IS DISTINCT FROM v_actor THEN
    RAISE EXCEPTION 'Draft unavailable';
  END IF;

  -- Idempotent re-share of an already-shared draft.
  IF v_draft.shared_message_id IS NOT NULL THEN
    SELECT * INTO v_row FROM public.messages WHERE id = v_draft.shared_message_id;
    RETURN v_row;
  END IF;

  IF v_draft.expires_at <= now() THEN
    RAISE EXCEPTION 'Draft expired';
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_draft.relationship_id
    AND status = 'active' AND chat_archived_at IS NULL
    AND (user_a = v_actor OR user_b = v_actor);
  IF v_rel.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  IF v_draft.target_message_id IS NOT NULL THEN
    SELECT * INTO v_target FROM public.messages
    WHERE id = v_draft.target_message_id AND deleted_at IS NULL;
    IF v_target.id IS NULL THEN
      RAISE EXCEPTION 'Target unavailable';
    END IF;
  END IF;

  SELECT * INTO v_consent FROM public.get_ai_processing_consent_status(v_draft.relationship_id);
  IF NOT v_consent.both_granted THEN
    RAISE EXCEPTION 'Consent required';
  END IF;

  v_message_id := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    message_origin, assistant_payload, is_system_notice,
    message_analysis_skipped, source, created_at
  ) VALUES (
    v_message_id, v_draft.relationship_id, v_actor, gen_random_uuid(),
    v_draft.reply_text, 'attune_assist', v_draft.assistant_payload, false,
    true, 'native', now()
  )
  RETURNING * INTO v_row;

  UPDATE public.ai_assist_drafts SET shared_message_id = v_message_id
  WHERE id = p_draft_id;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.share_ai_assist_draft(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_ai_assist_draft(uuid)
  TO authenticated;
```

Before finalizing, read the real `enqueue_message_downstream_work`
trigger definition (or whatever it's actually called — grep for it) to
confirm it fires on this INSERT the same way it does for an ordinary
client-inserted message, and confirm the exact column list your INSERT
above provides satisfies whatever NOT NULL/trigger-referenced columns
that mechanism expects. Adjust the INSERT's column list if reality
differs from this plan's assumption.

- [ ] **Step 4: Rebuild and run the SQL tests**

Run: `scripts/local_pg_setup.sh --no-tests`, then
`psql -q -d attune_test -f
supabase/tests/ai_assist_draft_share_contracts.sql`
Expected: `NOTICE: ai assist draft share contracts: all held` (or
equivalent — name it consistently with this plan's other files).

- [ ] **Step 5: Mutation-test contracts 1, 3, 4, 7, 9, and 10**

These are the highest-risk: unauthorized draft insertion, wrong-requester
share, expiry, consent-gating, safety-outbox creation, and the
no-client-payload guarantee. For each, weaken the specific check, confirm
the corresponding contract fails, restore, confirm it passes.

- [ ] **Step 6: Write the prompt templates**

Create `supabase/functions/ai-assist/prompts/v1/system.txt` and
`.../user.txt`. Content must implement spec §5.1 (Ideas vs Nearby scope,
`UNSUPPORTED_REQUEST` for anything else), §9's defense-in-depth
instructions (context is untrusted quoted data, never instructions), and
must declare the exact `IdeasModelOutput`/`NearbyCategoryOutput` JSON
contracts from spec §5.2 verbatim so the model's output is parseable
against those exact shapes. Do not embed the actual context or user
instruction text in these files — they are static templates; the context/
instruction are interpolated at call time exactly as
`callGeminiJson`'s existing `userPrompt` parameter already supports for
every other caller in this codebase (check `analyse-message/index.ts`'s
own prompt-construction code for the established interpolation pattern).

- [ ] **Step 7: Write the failing edge-function test**

Create `supabase/functions/ai-assist/index.test.ts`. Check an existing
edge function's own test file (e.g.
`supabase/functions/translate-conflict/index.test.ts` if one exists, or
`analyse-message/index.test.ts`) for this codebase's real pattern for
faking `callGeminiJson`/mocking the HTTP handler — match that pattern,
do not invent a new mocking approach. Cover, at minimum:

- a request missing `message_id` is rejected `INVALID_INPUT` before any
  DB/provider work;
- a request with an extra unknown field is rejected;
- `assist_kind: 'nearby'` with `requester_location: null` is rejected
  `LOCATION_REQUIRED`;
- consent not yet granted returns `CONSENT_REQUIRED` and performs no
  provider call (assert the fake Gemini/Mapbox callables were never
  invoked);
- a target that fails `loadAiAssistantTarget` returns `TARGET_UNAVAILABLE`
  before quota is reserved (assert no `ai_assistant_usage` row was
  created for that call);
- a successful Ideas call inserts exactly one `ai_assist_drafts` row (via
  a fake `insert_ai_assist_draft` call, or a real one against the local
  DB — prefer the real DB path if the existing test infra already runs
  against a live local Supabase instance, matching whatever this repo's
  other edge-function tests already do) and returns its contents, never
  auto-posting a message;
- a successful Nearby call with a fake Gemini response outside the
  allowlisted category set is rejected server-side, never forwarded to
  Mapbox (assert the fake Mapbox callable was never invoked);
- rate-limited (fake `reserve_ai_assistant_quota` returning
  `rate_limited`) returns `RATE_LIMITED` with the given
  `retry_after_seconds`, and performs no provider call.

- [ ] **Step 8: Write `ai-assist/index.ts`**

Implement per spec §4.1 (request validation), §4.2 (target load via
`userScopedClient`+`loadAiAssistantTarget`), §5.1-§5.3 (Ideas/Nearby
branching, the exact `IdeasModelOutput`/`NearbyCategoryOutput` validation,
the Mapbox call for Nearby using a dedicated least-privilege server
token from an Edge Function secret — check `supabase/functions/_shared/`
for whether a Mapbox helper already exists from an unrelated feature
before writing a new HTTP-fetch wrapper from scratch), §7.3 (call
`reserve_ai_assistant_quota` before any provider call; call
`mark_ai_assistant_usage_outcome` on every terminal outcome), §9 (system
prompt structure, output validation against the exact JSON contracts,
prohibited-pattern checks reusing `STATIC_PROHIBITED_PATTERNS`/
`partnerNamePatterns` from the existing `gemini_json.ts` helper — do not
duplicate that logic), §11 (the exact `AssistantErrorCode`/
`AssistantError` envelope for every failure path).

- [ ] **Step 9: Add `ai-assist` to `gemini_port.test.ts`**

Open `supabase/functions/_shared/gemini_port.test.ts`, find the hardcoded
function-name array near the top of the file, and add `"ai-assist"` to
it, matching the exact array-literal style already used for the other 7
entries.

- [ ] **Step 10: Run all the new tests, then mutation-test the
  highest-risk paths**

Run the SQL suite and the new `ai-assist/index.test.ts` and the updated
`gemini_port.test.ts`. Mutation-test: the quota-before-provider-call
ordering (temporarily call the provider before quota reservation, confirm
a test now fails because a rejected/malformed request would have still
incurred a provider call — if no existing test catches this, add one
first); the Nearby category allowlist enforcement (temporarily accept an
arbitrary string as a category, confirm the corresponding test fails,
restore).

- [ ] **Step 11: Run the full existing SQL and Deno suites for
  regressions**

- [ ] **Step 12: Commit**

```bash
git add supabase/functions/ai-assist/ \
        supabase/functions/_shared/gemini_port.test.ts \
        supabase/migrations/20260950080000_ai_assist_draft_and_share_rpcs.sql \
        supabase/tests/ai_assist_draft_share_contracts.sql
git commit -m "feat(ai-assistant): ai-assist edge function, drafts, and the share RPC"
```

---

## Task 7: `ai-understand` edge function and Planning conversion RPC

**Files:**
- Create: `supabase/functions/ai-understand/index.ts`
- Create: `supabase/functions/ai-understand/prompts/v1/system.txt`
- Create: `supabase/functions/ai-understand/prompts/v1/user.txt`
- Create: `supabase/migrations/20260950090000_create_planning_from_assist_message_rpc.sql`
- Modify: `supabase/functions/_shared/gemini_port.test.ts` (add
  `"ai-understand"`)
- Test: `supabase/functions/ai-understand/index.test.ts`
- Test: `supabase/tests/ai_assist_planning_conversion_contracts.sql`

**Interfaces:**
- Consumes: everything Task 6 consumed, minus the draft/share machinery
  (Understand never persists).
- Produces: the `ai-understand` HTTP endpoint (spec §4.1/§6.2/§11);
  `create_planning_from_assist_message(p_message_id uuid, p_edited_title
  text, p_edited_date date) RETURNS TABLE (planning_item_id uuid,
  planning_event_id uuid)`.

- [ ] **Step 1: Write the failing SQL contract tests for Planning
  conversion**

Create `supabase/tests/ai_assist_planning_conversion_contracts.sql`.
Cover:

1. Confirming a shared Assist message's Task proposal creates exactly one
   `planning_items` row and one `ai_assist_planning_links` row.
2. Confirming the same for an Event proposal (creates a
   `planning_events` row).
3. A message with `message_origin != 'attune_assist'` is rejected.
4. A message with no `suggested_planning_item` in its `assistant_payload`
   is rejected.
5. Calling this RPC twice for the SAME message (simulating two partners'
   concurrent taps) creates exactly one Planning entity, not two — open
   two overlapping transactions racing this call for the same message_id
   and confirm exactly one succeeds in creating a NEW item while the
   second either returns the same link or is rejected as already-consumed
   (define the exact idempotent behavior in the RPC and test for that
   specific behavior).
6. A caller who is not a member of the message's relationship is
   rejected.
7. Edited title/date are validated through the SAME constraints Planning's
   own `create_planning_task`/`upsert_planning_event` RPCs enforce (a
   blank-after-trim title is rejected here too) — do not re-implement
   those checks; call Planning's own RPCs so the constraint is enforced
   once, not duplicated and potentially drifting out of sync.

- [ ] **Step 2: Run the tests to verify they fail**

- [ ] **Step 3: Write `20260950090000_create_planning_from_assist_message_rpc.sql`**

```sql
-- Converts a shared Assist message's proposal into a real Planning
-- entity, exactly once per message, under concurrent taps from either
-- partner. Spec §5.4.
CREATE OR REPLACE FUNCTION public.create_planning_from_assist_message(
  p_message_id uuid, p_edited_title text, p_edited_date date
) RETURNS TABLE (planning_item_id uuid, planning_event_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_message public.messages;
  v_existing_link public.ai_assist_planning_links;
  v_proposal jsonb;
  v_kind text;
  v_new_item public.planning_items;
  v_new_event public.planning_events;
  v_new_id uuid := gen_random_uuid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Lock the message row for the duration of this check-then-act
  -- sequence so two partners' concurrent taps serialize here.
  SELECT * INTO v_message FROM public.messages
  WHERE id = p_message_id AND deleted_at IS NULL FOR UPDATE;
  IF v_message.id IS NULL THEN
    RAISE EXCEPTION 'Message unavailable';
  END IF;
  IF v_message.message_origin IS DISTINCT FROM 'attune_assist' THEN
    RAISE EXCEPTION 'Not an Attune Assist message';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_message.relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = v_actor OR r.user_b = v_actor)
  ) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT * INTO v_existing_link FROM public.ai_assist_planning_links
  WHERE message_id = p_message_id;
  IF v_existing_link.message_id IS NOT NULL THEN
    RETURN QUERY SELECT v_existing_link.planning_item_id, v_existing_link.planning_event_id;
    RETURN;
  END IF;

  v_proposal := v_message.assistant_payload -> 'suggested_planning_item';
  IF v_proposal IS NULL OR v_proposal = 'null'::jsonb THEN
    RAISE EXCEPTION 'This message has no Planning proposal';
  END IF;
  v_kind := v_proposal ->> 'kind';

  IF v_kind = 'task' THEN
    v_new_item := public.create_planning_task(
      v_new_id, v_message.relationship_id,
      COALESCE(btrim(p_edited_title), v_proposal ->> 'title'),
      NULL, NULL, p_edited_date
    );
    INSERT INTO public.ai_assist_planning_links
      (message_id, relationship_id, planning_item_id, created_by)
    VALUES (p_message_id, v_message.relationship_id, v_new_item.id, v_actor);
    RETURN QUERY SELECT v_new_item.id, NULL::uuid;
  ELSIF v_kind = 'event' THEN
    v_new_event := public.upsert_planning_event(
      v_new_id, v_message.relationship_id,
      COALESCE(btrim(p_edited_title), v_proposal ->> 'title'),
      NULL, COALESCE(p_edited_date, (v_proposal ->> 'event_date')::date)
    );
    INSERT INTO public.ai_assist_planning_links
      (message_id, relationship_id, planning_event_id, created_by)
    VALUES (p_message_id, v_message.relationship_id, v_new_event.id, v_actor);
    RETURN QUERY SELECT NULL::uuid, v_new_event.id;
  ELSE
    RAISE EXCEPTION 'Unknown proposal kind';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.create_planning_from_assist_message(uuid, text, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_planning_from_assist_message(uuid, text, date)
  TO authenticated;
```

Before finalizing, confirm `create_planning_task`'s and
`upsert_planning_event`'s exact real signatures against
`lib/architecture/PLANNING.md` / the actual migration files in this
worktree (this plan's parameter order above is written from memory of
Planning's own plan — re-verify against the real committed function
signatures, since a wrong parameter order would silently misassign
title/date).

- [ ] **Step 4: Rebuild and run the SQL tests, mutation-test contract 5
  specifically (the concurrency one) with real overlapping transactions**

- [ ] **Step 5: Write the failing edge-function test for `ai-understand`**

Cover, at minimum: Understand-on-own-message is rejected (target
`sender_id == auth.uid()`); a successful call never calls
`share_ai_assist_draft`, never inserts into `messages`, never inserts a
draft (assert via source-inspection or by using a fake `PlanningRpcGateway`-
style client that would throw if any write method were called — follow
whatever mocking convention Task 6's test file established); the response
has `Cache-Control: no-store`; a `cannot_help: unsafe_to_infer` result
never reveals whether the deterministic safety pipeline separately fired
for the same target message (assert the response contains no field/value
derived from `safety_processed_at`/`safety_error_code`/any safety table).

- [ ] **Step 6: Write `ai-understand/index.ts` and its prompts**

Same shape discipline as Task 6's `ai-assist/index.ts`, but simpler (no
drafts, no Mapbox, no share step): validate request (spec §4.1), load
target+context (Task 2's loader with `mode: 'understand'`), reserve quota,
call Gemini with the `UnderstandResponse` contract (spec §6.2), run the
mechanical validators (length/count/enum/context-echo checks — reuse
`STATIC_PROHIBITED_PATTERNS`/`partnerNamePatterns`, add the context-echo
check as new logic per spec §9 item 7), return the response with
`Cache-Control: no-store`, mark quota outcome. This function's source
must literally not import the chat repository, any message-mutation
client, or `share_ai_assist_draft` — confirm this by grep, not just by
review.

- [ ] **Step 7: Add `"ai-understand"` to `gemini_port.test.ts`**

- [ ] **Step 8: Run everything, mutation-test the no-write/no-share
  guarantee and the context-echo rejection**

For the no-write guarantee: temporarily add a stray call to
`share_ai_assist_draft` (or a `messages` insert) somewhere in
`ai-understand/index.ts`, confirm the source-dependency test (Step 5)
catches it, remove it. For context-echo: construct a test where the fake
Gemini response contains an 8+ token verbatim quote from the seeded
context, confirm the validator rejects it, then confirm a genuinely
paraphrased response of similar length passes.

- [ ] **Step 9: Run the full existing SQL and Deno suites for
  regressions**

- [ ] **Step 10: Commit**

```bash
git add supabase/functions/ai-understand/ \
        supabase/functions/_shared/gemini_port.test.ts \
        supabase/migrations/20260950090000_create_planning_from_assist_message_rpc.sql \
        supabase/tests/ai_assist_planning_conversion_contracts.sql
git commit -m "feat(ai-assistant): ai-understand edge function and Planning conversion"
```

---

## Task 8: Message edit/delete split and scheduled purge jobs

**Files:**
- Modify: `supabase/migrations/` — a new migration splitting `edit_message`/
  `delete_message`'s handling of `message_origin = 'attune_assist'`
  (create a new migration file; do not edit a shipped one)
- Create: `supabase/migrations/20260950100000_ai_assistant_purge_jobs.sql`
- Test: extend the real existing SQL test file(s) that already cover
  `edit_message`/`delete_message` (find them first — grep
  `supabase/tests/` for `edit_message` and `delete_message`)
- Test: `supabase/tests/ai_assistant_purge_contracts.sql`

**Interfaces:**
- Consumes: `edit_message`/`delete_message` (existing RPCs — read their
  real current signatures/bodies before modifying).
- Produces: modified `edit_message`/`delete_message` behavior for
  `message_origin = 'attune_assist'`; two new scheduled jobs
  (`purge-ai-assist-drafts`, `purge-ai-assistant-usage`).

- [ ] **Step 1: Read the real, current `edit_message` and
  `delete_message` RPC definitions in full**

Find them (grep `supabase/migrations/` for `CREATE OR REPLACE FUNCTION
public.edit_message` and `public.delete_message`) and read the most
recent version of each in full before writing anything. This plan's
Step 3 below assumes a shape; verify it first.

- [ ] **Step 2: Write the failing tests**

Extend whichever real existing SQL test file already covers these RPCs
(do not create a parallel new file if one already exists — find it and
add to it, matching its existing fixture/style). Add contracts:

1. `edit_message` on a `message_origin = 'attune_assist'` message is
   rejected regardless of sender/time-window, with a clear error (spec
   §5.3: "may be deleted under the existing five-minute sender rule but
   may not be edited in place").
2. `delete_message` on a `message_origin = 'attune_assist'` message,
   within the normal sender/time window, succeeds, and in the SAME
   transaction: clears `assistant_payload` to NULL, resets
   `message_origin` to `'user'` (so the shape CHECK constraint from Plan
   A Task 1 remains satisfied on the tombstoned row), and deletes the
   corresponding `ai_assist_planning_links` row if one exists.
3. Deleting an Assist message that already had its proposal converted to
   a Planning item does NOT delete that Planning item — assert the
   `planning_items` row still exists and is not soft-deleted after the
   message delete.
4. A retried/duplicate delete call on an already-deleted Assist message
   is idempotent (does not error, does not attempt to re-clear an
   already-cleared link row).

- [ ] **Step 3: Modify `edit_message`/`delete_message` via a new
  migration**

Create a new migration file
(`supabase/migrations/20260950110000_ai_assist_message_edit_delete_split.sql`)
that `CREATE OR REPLACE FUNCTION`s both RPCs with their EXISTING body
(from Step 1) plus the new `attune_assist`-specific branches described
above. Do not remove any existing behavior for ordinary user messages —
this is an additive change to two functions that already work correctly
for the common case.

- [ ] **Step 4: Write the failing purge-job contract tests**

Create `supabase/tests/ai_assistant_purge_contracts.sql`:

1. A draft with `created_at` more than 24 hours ago is hard-deleted by
   the purge function (write the purge logic as its own `SECURITY
   DEFINER`, service-role-only-callable function first, e.g.
   `purge_expired_ai_assist_drafts()`, so it can be tested directly via
   SQL before wiring a cron schedule).
2. A draft with `created_at` less than 24 hours ago is NOT purged, even
   if its 15-minute `expires_at` has already passed (expiry blocks
   sharing; only the 24-hour mark triggers physical deletion — these are
   two different thresholds, confirm the purge function only acts on the
   24-hour one).
3. A SHARED draft (one whose `shared_message_id` is set) is still purged
   at the same 24-hour mark — purging the draft row never touches the
   shared `messages` row (assert the message still exists after the
   draft row is gone, since `shared_message_id`'s FK is `ON DELETE SET
   NULL`, not cascading).
4. `ai_assistant_usage` rows older than 30 days are purged by a second
   function (`purge_old_ai_assistant_usage()`), rows newer than 30 days
   are not.

- [ ] **Step 5: Write the purge functions and register the scheduled
  jobs**

Create `supabase/migrations/20260950100000_ai_assistant_purge_jobs.sql`.
First read `supabase/migrations/20260907120000_register_scheduled_jobs.sql`
(the migration that moved Planning-adjacent cron registration out of
hand-run scripts and into versioned migrations — the AI Assistant spec's
own review history flagged the same class of "was this cron job ever
actually registered" risk that motivated that migration) to follow its
exact idempotent-unschedule-then-schedule pattern, not the older
`supabase/sql/schedule_*.sql` hand-run-script pattern. Register both purge
jobs (a reasonable cadence — hourly is sufficient given the 24-hour/
30-day thresholds; do not register a per-minute job for something this
infrequent) using `invoke_edge_function` or a direct SQL function call,
whichever the register-scheduled-jobs migration's own established helper
uses.

- [ ] **Step 6: Rebuild, run all the new/extended tests**

- [ ] **Step 7: Mutation-test the Planning-preservation contract (step
  2's contract 3) and the two purge thresholds specifically**

The Planning-preservation one matters most: temporarily make
`delete_message`'s new branch cascade-delete the linked Planning entity
(e.g. by removing the FK's `ON DELETE CASCADE` distinction or adding an
explicit delete call), confirm the contract fails, restore, confirm it
passes.

- [ ] **Step 8: Run the full existing SQL suite for regressions**

- [ ] **Step 9: Commit**

```bash
git add supabase/migrations/20260950100000_ai_assistant_purge_jobs.sql \
        supabase/migrations/20260950110000_ai_assist_message_edit_delete_split.sql \
        supabase/tests/ai_assistant_purge_contracts.sql
git commit -m "feat(ai-assistant): immutable Assist messages, Planning-preserving delete, and purge jobs"
```

(Note: the extended edit_message/delete_message test file's own `git add`
line depends on which real file Step 2 found — add that file explicitly
too.)

---

## Task 9: Telemetry scrubbing and final backend review pass

**Files:**
- No new feature files. A review-and-fix pass over Tasks 1–8's combined
  output, mirroring Planning's own Plan A Task 5, plus a telemetry-scope
  audit specific to this feature.

- [ ] **Step 1: Grep every log/analytics/Sentry call this plan's own
  commits introduced**

Run `git log --oneline` for this feature's commits, then `git show
--stat` each to enumerate every touched file, then grep each edge
function file for `console.log`, `console.error`, `Sentry`, or any
analytics-event call. For each hit, confirm it logs ONLY fields from the
spec §10.3 allowlist (request UUID, pseudonymous internal user/
relationship IDs, mode, timestamps, latency bucket, prompt/model version,
provider status class, provider-call count, token-count bucket, outcome)
and NONE of the forbidden fields (message IDs in third-party analytics,
content, prompts, output, coordinates, place query/results, partner
names, safety state, response option selected). Fix any violation found.

- [ ] **Step 2: Run every AI-Assistant SQL contract test together, twice,
  from fresh rebuilds**

Run: `scripts/local_pg_setup.sh --no-tests`, then run all of this plan's
own SQL test files in ONE psql session (not separate invocations) to
catch cross-test fixture collisions:
```bash
psql -q -d attune_test \
  -f supabase/tests/ai_assistant_schema_contracts.sql \
  -f supabase/tests/ai_processing_consent_contracts.sql \
  -f supabase/tests/ai_assistant_quota_contracts.sql \
  -f supabase/tests/message_analysis_skipped_contracts.sql \
  -f supabase/tests/ai_assist_draft_share_contracts.sql \
  -f supabase/tests/ai_assist_planning_conversion_contracts.sql \
  -f supabase/tests/ai_assistant_purge_contracts.sql
```
Then rebuild fresh and run them again to confirm they are not
order-dependent.

- [ ] **Step 3: Verify no migration silently depends on the harness's
  blanket grant**

Run, on a freshly rebuilt database:
```bash
psql -d attune_test -tAc "
select relname,
       has_table_privilege('authenticated', 'public.'||relname, 'INSERT') as can_insert,
       has_table_privilege('authenticated', 'public.'||relname, 'SELECT') as can_select
from pg_class
where relname like 'ai\_%' escape '\' and relkind = 'r';"
```
Expected: `ai_assist_drafts`, `ai_assistant_usage`,
`ai_processing_consent_events` all show `can_insert = f, can_select = f`;
`ai_assist_planning_links` shows `can_insert = f, can_select = t`. Any
other result is a real security gap — fix and re-verify.

- [ ] **Step 4: Verify every `SECURITY DEFINER` function this plan added
  has a pinned `search_path`, and every service-role-only function is
  genuinely unreachable by `authenticated`**

Run:
```bash
psql -d attune_test -tAc "
select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and (proname like '%ai\_assist%' escape '\' or proname like '%ai\_processing%' escape '\' or proname like '%ai\_assistant%' escape '\')
  and (p.proconfig is null or not (p.proconfig::text like '%search_path%'));"
```
Expected: empty. Then:
```bash
psql -d attune_test -tAc "
select has_function_privilege('authenticated', 'public.insert_ai_assist_draft(uuid,uuid,uuid,uuid,text,jsonb)', 'EXECUTE') as insert_draft_exec;"
```
Expected: `f`.

- [ ] **Step 5: Verify `gemini_port.test.ts` includes both new functions
  and passes, and that neither edge function imports a Claude/Anthropic
  client**

Run whatever this repo's Deno test invocation is for
`_shared/gemini_port.test.ts`. Separately grep both `ai-assist/index.ts`
and `ai-understand/index.ts` for `anthropic`/`Claude`/`ANTHROPIC` — expect
zero matches.

- [ ] **Step 6: Confirm the full existing SQL and Deno test suites are
  still green**

- [ ] **Step 7: Write the backend completion note**

If Steps 1–6 surfaced any fix, commit it now with a message describing
exactly what was wrong and which step caught it, then re-run Steps 1–6 in
full before considering this task done. If nothing needed fixing, no
commit is required beyond what Tasks 1–8 already committed.
</content>

# AI Sessions — Plan A: Cross-Mode Quota/Lease Repair

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the quota ledger's remaining ad-hoc outcome bookkeeping
with the exclusive-lease model the Sessions spec requires — a
provider-start marker that makes "was a provider actually contacted"
queryable, exactly-once quota release for reservations that never reached
a provider, and permanent quota consumption for every reservation that
did — across all three modes (`assist`, `understand`, `session`), before
Plan B/C add any Sessions-specific caller.

**Architecture:** One more migration on top of the already-shipped
`ai_assistant_usage` ledger (see "Starting state" below). Adds a
`provider_started_at timestamptz` column that only a trusted RPC may set,
tightens `reserve_ai_assistant_quota`'s admission and
`mark_ai_assistant_usage_outcome`'s transition rules to the "release
before start, never after" contract, and adds one new RPC —
`release_ai_assistant_quota_reservation` — for the "admitted then rejected
before any provider call" path that Plan B's Sessions admission RPC and a
corrected `ai-assist`/`ai-understand` will call instead of silently
falling through to `mark_ai_assistant_usage_outcome`. `mode` grows a third
value, `'session'`, so Plan B's tables can reuse this exact ledger rather
than inventing a second one.

**Tech Stack:** PostgreSQL migrations (Supabase), SQL contract tests via
`scripts/local_pg_setup.sh`'s `attune_test` database (see
`supabase/tests/ai_assistant_quota_contracts.sql` for the existing
pattern), Deno edge-function tests via
`supabase/functions/_shared/test_support/pg_rls_client.ts`'s
`makeServiceRoleClient()`.

**Spec:** `docs/superpowers/specs/2026-09-22-ai-sessions-design.md` §5.2
(limits), §6.2 (admission/lease protocol — this plan implements only the
quota/outcome half; Plan B implements session admission itself), §7.3
(shared quota repair — this plan's primary source), §8.2.2 (compensation
table), §13 (cross-mode prerequisite). Also read
`docs/superpowers/specs/2026-09-22-ai-sessions-review.md` finding F08 (the
defect this plan's starting-state migration already partially fixed) and
`docs/superpowers/specs/2026-09-15-ai-assistant-design.md` §7.3 (the
original quota design this ledger implements).

## Starting state — read this before Task 1

A prior session already fixed the two live vulnerabilities the review's
F08 finding identified, in
`supabase/migrations/20260951030000_ai_assistant_quota_lease_hardening.sql`:

- `reserve_ai_assistant_quota(p_actor_id, p_request_id, p_relationship_id, p_mode)`
  now returns `'already_reserved'` (not a second `'reserved'`) when
  `p_request_id` already exists, so a replayed request can never drive a
  second provider call off one quota slot.
- `mark_ai_assistant_usage_outcome(p_actor_id, p_request_id, p_outcome, p_provider_calls)`
  is `service_role`-only (no `authenticated` grant) and only transitions a
  row whose current `outcome = 'reserved'` — a terminal row can never be
  rewritten.
- Both functions take an explicit `p_actor_id` instead of reading
  `auth.uid()`, because they are called via `serviceRoleClient()` (a
  service-role connection has no user JWT, so `auth.uid()` is `NULL`
  under it) — safe only because the edge functions' own `p_actor_id`
  argument is `user.id` from `requireUser(req)`'s verified
  `auth.getUser()` call, never client input.
- `ai-assist/index.ts` and `ai-understand/index.ts` were updated to call
  both RPCs via a service-role client, threading it through
  `handleIdeas`/`handleNearby`/`handleUnderstand`.
- `supabase/tests/ai_assistant_quota_contracts.sql` was rewritten for the
  new signatures and outcomes (8 contracts, including one proving
  `authenticated` has no grant on either function).

**What that fix does NOT do**, and what this plan adds: it has no concept
of "did a provider call actually happen." `mark_ai_assistant_usage_outcome`
still lets the caller move a `'reserved'` row straight to `'cancelled'`
(which the rolling-window `COUNT` excludes) with no check that a Gemini/
Mapbox call ever started — so a client that admits, then immediately
marks itself `'cancelled'` before any real work, self-releases a quota
slot it never needed released, and nothing here yet enforces §8.2.2's
row: *"Admission committed, no provider-start marker → releases exactly
once; provider-start marker set → attempt counted even if result
absent."* This plan adds that marker and rewrites both mutation paths
around it.

## Global Constraints

- **`auth.uid()` is unusable in every function this plan touches or
  adds.** All are `service_role`-only; take the actor as an explicit
  `p_actor_id uuid` parameter, exactly like the starting-state migration
  already does. Never add a client-callable RPC in this plan — Plan B's
  session admission RPC is the only new client-facing surface, and it
  lives in Plan B, not here.
- **A provider-start marker, once set, can never be unset or moved
  backward.** This is the single invariant the whole plan exists to
  enforce. Every task's tests must include an attempt to violate it.
- **Reservations count immediately at INSERT time**, not at some later
  "confirmed" step — this is already true in the starting-state migration
  (the row is inserted with `outcome = 'reserved'` before any provider
  work) and must not change. (Spec §7.3: "Reservations count immediately
  to prevent races.")
- **A release is a new, explicit, single-purpose transaction — never a
  rollback of an already-committed reservation, and never implicit
  inside `mark_ai_assistant_usage_outcome`.** (Spec §7.3: "Atomic release
  is a new trusted transaction, not a claimed rollback of an already
  committed reservation.")
- **Once `provider_started_at` is set, no outcome value may cause the row
  to be excluded from the rolling-window `COUNT`.** Concretely: the
  `COUNT` predicate in `reserve_ai_assistant_quota` currently reads
  `outcome NOT IN ('rejected', 'cancelled')`. After this plan, a row with
  `provider_started_at IS NOT NULL` must count regardless of its
  `outcome` value — the exclusion applies only to
  `provider_started_at IS NULL` rows.
- **`mode` gains `'session'` as a legal value everywhere it currently
  enumerates `'assist' | 'understand'`** — the CHECK constraint on
  `ai_assistant_usage.mode`, and the `p_mode NOT IN (...)` guard inside
  `reserve_ai_assistant_quota`. This plan does not create session rows;
  it only makes the ledger able to accept them once Plan B's admission
  RPC starts calling `reserve_ai_assistant_quota` with `p_mode = 'session'`.
- **Every new/changed RPC keeps the existing `SECURITY DEFINER`,
  `SET search_path = public` discipline** every function in
  `20260950050000_ai_assistant_quota_rpcs.sql` and
  `20260951030000_ai_assistant_quota_lease_hardening.sql` already uses.
  Do not introduce a function without both.
- **30-day idempotency retention is unchanged by this plan.** Do not
  touch `ai_assistant_usage`'s purge job
  (`20260950100000_ai_assistant_purge_jobs.sql`) — Plan B may need to
  extend it for session-specific tables, but this plan's own rows purge
  exactly as today's do.

---

### Task 1: Add the provider-start marker column and widen `mode`

**Files:**
- Create: `supabase/migrations/20260952010000_ai_assistant_provider_start_marker.sql`
- Test: `supabase/tests/ai_assistant_provider_start_marker_contracts.sql`

**Interfaces:**
- Produces: `ai_assistant_usage.provider_started_at timestamptz NULL` — the
  column every later task in this plan reads and writes. `NULL` means "no
  provider call has ever been attempted for this reservation"; any
  non-NULL value is permanent (enforced in Task 2, not by a constraint
  here — Postgres has no native "write-once" column constraint, so the
  write-once guarantee lives in the RPC that sets it).
- Produces: `mode` CHECK constraint now allows `'assist' | 'understand' | 'session'`.
- Consumes: nothing new; extends the `ai_assistant_usage` table from
  `20260950010000_ai_assistant_schema.sql`.

- [ ] **Step 1: Write the failing contract test**

Create `supabase/tests/ai_assistant_provider_start_marker_contracts.sql`:

```sql
-- Provider-start marker column and widened mode CHECK.
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_provider_start_marker_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a5000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a5000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a5000000-0000-0000-0000-00000000000b';
  v_req_1 uuid := 'a5000000-0000-0000-0000-000000000101';
  v_row record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'marker_a@t.test'), (v_user_b, 'marker_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550005001', 'A'), (v_user_b, '+15550005002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: provider_started_at exists, defaults NULL, and is
  -- writable directly by this fixture setup (proving the column itself
  -- is correctly typed and nullable before any RPC touches it).
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_user_a, v_req_1, v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: setup reservation failed, got %', v_row.outcome;
  END IF;
  PERFORM provider_started_at FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF (SELECT provider_started_at FROM public.ai_assistant_usage WHERE request_id = v_req_1) IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: provider_started_at was non-NULL on a fresh reservation';
  END IF;

  -- Contract 2: 'session' is now a legal mode value.
  PERFORM public.reserve_ai_assistant_quota(v_user_b, gen_random_uuid(), v_rel, 'session');

  RAISE NOTICE 'provider-start marker contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_assistant_provider_start_marker_contracts.sql
```

Expected: fails with `column "provider_started_at" does not exist` (Contract 1)
or, if that somehow passed on an unrelated column, `new row for relation
"ai_assistant_usage" violates check constraint "ai_assistant_usage_mode_check"`
(Contract 2). Either failure proves the test exercises something not yet
built.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260952010000_ai_assistant_provider_start_marker.sql`:

```sql
-- Adds the provider-start marker this plan's Tasks 2-4 build the
-- exclusive-lease model on top of, and widens `mode` to accept
-- Sessions (Plan B). Spec §7.3, §8.2.2.
--
-- provider_started_at is NULL until a trusted RPC (Task 2's
-- claim_ai_assistant_provider_start) sets it, and is permanent from
-- then on -- Task 2 enforces the write-once rule in application logic
-- (an UPDATE ... WHERE provider_started_at IS NULL guard), since
-- Postgres has no native write-once column constraint.
ALTER TABLE public.ai_assistant_usage
  ADD COLUMN provider_started_at timestamptz;

ALTER TABLE public.ai_assistant_usage
  DROP CONSTRAINT ai_assistant_usage_mode_check;
ALTER TABLE public.ai_assistant_usage
  ADD CONSTRAINT ai_assistant_usage_mode_check
    CHECK (mode IN ('assist', 'understand', 'session'));
```

- [ ] **Step 4: Run the migration, then re-run the contract test**

```bash
psql -q -d attune_test -f supabase/migrations/20260952010000_ai_assistant_provider_start_marker.sql
psql -q -d attune_test -f supabase/tests/ai_assistant_provider_start_marker_contracts.sql
```

Expected: `NOTICE: provider-start marker contracts: all held`

- [ ] **Step 5: Run the full existing quota contract suite to confirm no regression**

```bash
psql -q -d attune_test -f supabase/tests/ai_assistant_quota_contracts.sql
```

Expected: `NOTICE: ai assistant quota contracts: all held` (unchanged —
this task added a nullable column and widened a CHECK, neither of which
existing rows or existing function bodies reference yet).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260952010000_ai_assistant_provider_start_marker.sql \
        supabase/tests/ai_assistant_provider_start_marker_contracts.sql
git commit -m "feat(ai-quota): add provider-start marker column, widen mode to include session"
```

---

### Task 2: `claim_ai_assistant_provider_start` — the write-once marker RPC

**Files:**
- Modify: `supabase/migrations/20260952010000_ai_assistant_provider_start_marker.sql`
  (append; this is the same file Task 1 created — the marker column and
  its own claiming RPC belong in one migration so a `psql -f` of just
  this file leaves the ledger in a fully consistent state)
- Test: `supabase/tests/ai_assistant_provider_start_marker_contracts.sql` (append)

**Interfaces:**
- Consumes: `ai_assistant_usage.provider_started_at` (Task 1).
- Produces: `claim_ai_assistant_provider_start(p_actor_id uuid, p_request_id uuid) RETURNS boolean`
  — `true` if this call set the marker (i.e. it was previously NULL and
  this call is the one that claimed it), `false` if it was already set
  (by this call or an earlier one — the caller cannot tell which, and
  must not need to: "already started" means "do not call the provider
  again either way"). Raises if the row does not exist, belongs to a
  different actor, or is not in `outcome = 'reserved'` state (a
  terminal row can never gain a fresh start marker). Called by
  `ai-assist`/`ai-understand` (Task 3) and, later, Plan B's session
  dispatch RPC, immediately before their respective Gemini/Mapbox
  `fetch()` call — never after.

- [ ] **Step 1: Write the failing test**

Append to `supabase/tests/ai_assistant_provider_start_marker_contracts.sql`,
inside the same `DO $$ ... END $$` block, before `RAISE NOTICE`:

```sql
  -- Contract 3: the first claim succeeds and sets the marker.
  IF public.claim_ai_assistant_provider_start(v_user_a, v_req_1) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: first provider-start claim did not return true';
  END IF;
  IF (SELECT provider_started_at FROM public.ai_assistant_usage WHERE request_id = v_req_1) IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: provider_started_at is still NULL after a successful claim';
  END IF;

  -- Contract 4: a second claim on the SAME request_id returns false and
  -- does NOT move provider_started_at forward in time (write-once).
  DECLARE
    v_first_marker timestamptz;
    v_second_claim boolean;
  BEGIN
    SELECT provider_started_at INTO v_first_marker
    FROM public.ai_assistant_usage WHERE request_id = v_req_1;
    PERFORM pg_sleep(0.01);
    v_second_claim := public.claim_ai_assistant_provider_start(v_user_a, v_req_1);
    IF v_second_claim IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'EXPLOIT: second provider-start claim on the same request did not return false';
    END IF;
    IF (SELECT provider_started_at FROM public.ai_assistant_usage WHERE request_id = v_req_1)
        IS DISTINCT FROM v_first_marker THEN
      RAISE EXCEPTION 'EXPLOIT: provider_started_at moved forward on a second claim -- write-once violated';
    END IF;
  END;

  -- Contract 5: a different actor cannot claim someone else's request.
  BEGIN
    PERFORM public.claim_ai_assistant_provider_start(v_user_b, v_req_1);
    RAISE EXCEPTION 'EXPLOIT: user_b claimed user_a''s own request row';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 6: a terminal row can never gain a start marker after the
  -- fact -- claiming on an already-succeeded row must raise, not
  -- silently set the marker (which would let a completed reservation
  -- retroactively look like it had started a provider call it never
  -- made, corrupting the compensation table's own invariant).
  PERFORM public.mark_ai_assistant_usage_outcome(v_user_a, v_req_1, 'succeeded', 1::smallint);
  BEGIN
    PERFORM public.claim_ai_assistant_provider_start(v_user_a, v_req_1);
    RAISE EXCEPTION 'EXPLOIT: provider-start claim succeeded on an already-terminal row';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_assistant_provider_start_marker_contracts.sql
```

Expected: `function public.claim_ai_assistant_provider_start(uuid, uuid) does not exist`

- [ ] **Step 3: Write the RPC**

Append to `supabase/migrations/20260952010000_ai_assistant_provider_start_marker.sql`:

```sql
-- The single write point for provider_started_at. "true" means THIS
-- call is the one that claimed it -- the caller proceeds to contact the
-- provider. "false" means it was already claimed (by a retry of the
-- same request, or a concurrent duplicate) -- the caller must NOT
-- contact the provider again; per spec §6.2, "Never retry uncertain
-- external calls, even with the same request ID; expose terminal
-- failure instead."
CREATE OR REPLACE FUNCTION public.claim_ai_assistant_provider_start(
  p_actor_id uuid, p_request_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claimed boolean;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.ai_assistant_usage
    WHERE request_id = p_request_id AND user_id = p_actor_id
  ) THEN
    RAISE EXCEPTION 'Reservation not found for this actor';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.ai_assistant_usage
    WHERE request_id = p_request_id AND user_id = p_actor_id
      AND outcome != 'reserved'
  ) THEN
    RAISE EXCEPTION 'Cannot claim provider start on a terminal reservation';
  END IF;

  UPDATE public.ai_assistant_usage
  SET provider_started_at = now()
  WHERE request_id = p_request_id AND user_id = p_actor_id
    AND provider_started_at IS NULL;
  v_claimed := FOUND;

  RETURN v_claimed;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_ai_assistant_provider_start(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ai_assistant_provider_start(uuid, uuid)
  TO service_role;
```

- [ ] **Step 4: Run the migration file fresh and the test**

Since Task 1 already applied the `ALTER TABLE` portion of this file to
`attune_test`, re-running the whole file would fail on
`column "provider_started_at" already exists`. Apply only the new
`CREATE OR REPLACE FUNCTION` block directly:

```bash
psql -q -d attune_test -c "$(sed -n '/^CREATE OR REPLACE FUNCTION public.claim_ai_assistant_provider_start/,/^  TO service_role;$/p' supabase/migrations/20260952010000_ai_assistant_provider_start_marker.sql)"
psql -q -d attune_test -f supabase/tests/ai_assistant_provider_start_marker_contracts.sql
```

Expected: `NOTICE: provider-start marker contracts: all held`

Before moving on, reset `attune_test` from scratch and apply the whole
migration file in one pass (this is what CI/a fresh environment actually
does — the split-apply above was only to avoid re-running Task 1's
already-applied `ALTER TABLE` twice in this one development session):

```bash
bash scripts/local_pg_setup.sh   # rebuilds attune_test from migrations 0..N in order
psql -q -d attune_test -f supabase/tests/ai_assistant_provider_start_marker_contracts.sql
psql -q -d attune_test -f supabase/tests/ai_assistant_quota_contracts.sql
```

Expected: both print their `all held` NOTICE with no exception.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260952010000_ai_assistant_provider_start_marker.sql \
        supabase/tests/ai_assistant_provider_start_marker_contracts.sql
git commit -m "feat(ai-quota): add claim_ai_assistant_provider_start, the write-once lease marker"
```

---

### Task 3: Wire `ai-assist` and `ai-understand` to claim the marker before every provider call

**Files:**
- Modify: `supabase/functions/ai-assist/index.ts` (the `deps.callGemini`/
  `deps.searchMapbox` call sites inside `handleIdeas` and `handleNearby`)
- Modify: `supabase/functions/ai-understand/index.ts` (the `deps.callGemini`
  call site inside `handleUnderstand`)
- Modify: `supabase/functions/ai-assist/index.test.ts`
- Modify: `supabase/functions/ai-understand/index.test.ts`

**Interfaces:**
- Consumes: `claim_ai_assistant_provider_start(p_actor_id, p_request_id) RETURNS boolean`
  (Task 2).
- Produces: nothing new for later tasks — this task only changes call
  ordering inside the two existing functions so the marker is set
  correctly. Plan C's Sessions edge function follows the identical
  ordering it establishes here.

**Why this task exists:** today, `handleIdeas`/`handleNearby`/
`handleUnderstand` call `deps.callGemini` (and, for Nearby,
`deps.searchMapbox`) directly after quota reservation, with no
provider-start marker at all. Without this task, Task 1/2's new column
and RPC exist but nothing ever sets them, and the compensation table in
spec §8.2.2 ("provider-start marker set → attempt counted even if result
absent") stays unenforced for the two modes that ship today.

- [ ] **Step 1: Write the failing test — a claimed marker blocks a second dispatch on retry**

In `supabase/functions/ai-assist/index.test.ts`, add (near the existing
rate-limit test, using the same `makeRlsClientForUser`/
`makeServiceRoleClient` fixtures already imported in that file):

```typescript
Deno.test({
  name: "a request whose provider-start marker is already set is never dispatched to Gemini again",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T6_A);
    const serviceClient = await makeServiceRoleClient();
    const requestId = crypto.randomUUID();

    // Reserve, then claim the marker directly -- standing in for "the
    // first attempt already dispatched to Gemini, and this is a retry
    // of the same request_id arriving after a lost HTTP response."
    await serviceClient.rpc("reserve_ai_assistant_quota", {
      p_actor_id: USER_T6_A,
      p_request_id: requestId,
      p_relationship_id: REL_T6,
      p_mode: "assist",
    });
    const claimed = await serviceClient.rpc("claim_ai_assistant_provider_start", {
      p_actor_id: USER_T6_A,
      p_request_id: requestId,
    });
    assertEquals(claimed.data?.[0]?.claim_ai_assistant_provider_start ?? claimed.data?.[0], true);

    let geminiCalls = 0;
    const countingGemini = () => {
      geminiCalls++;
      return Promise.resolve(null);
    };

    const response = await processAssistRequest(
      makeReq({ ...validIdeasBody(), request_id: requestId }),
      { client: client as never, user: { id: USER_T6_A } },
      {
        callGemini: countingGemini as never,
        searchMapbox: neverCalledMapbox(),
        serviceClient: serviceClient as never,
      },
    );

    // The handler must recognize the marker is already set and refuse
    // to dispatch, rather than calling Gemini a second time for a
    // request that may already be in flight or already billed.
    assertEquals(geminiCalls, 0);
    assertEquals(response.status >= 400, true);
  },
});
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd supabase/functions/ai-assist && deno test index.test.ts --allow-net --allow-env --allow-read \
  --filter "provider-start marker is already set"
```

Expected: FAIL — `geminiCalls` is `1`, because nothing today checks the
marker before calling `deps.callGemini`.

- [ ] **Step 3: Add the claim-before-dispatch guard**

In `supabase/functions/ai-assist/index.ts`, `handleIdeas` currently reads:

```typescript
  const parsed = await deps.callGemini({
    promptId: "ai_assist_ideas_v1",
    systemPrompt: system,
    userPrompt,
    maxOutputTokens: 600,
  });
```

Change the start of `handleIdeas` to claim the marker first, and use a
shared helper (added in this same step) so `handleNearby` and
`ai-understand`'s `handleUnderstand` use identical logic rather than
three copies of the same check:

Add to `supabase/functions/_shared/attune_auth.ts`:

```typescript
/// Claims this request's provider-start marker via the trusted RPC, and
/// returns whether THIS call is the one that claimed it. `false` means
/// the marker was already set (a retry, a duplicate, or a concurrent
/// call for the same request_id) -- the caller must not dispatch to any
/// provider in that case. See migration 20260952010000 and spec §6.2/
/// §8.2.2 for why this check happens once, immediately before the FIRST
/// external call a request makes, never repeated per-provider within
/// one request (Nearby's Gemini-then-Mapbox pair shares one claim).
export async function claimProviderStart(
  service: SupabaseClient,
  actorId: string,
  requestId: string,
): Promise<boolean> {
  const result = await service.rpc("claim_ai_assistant_provider_start", {
    p_actor_id: actorId,
    p_request_id: requestId,
  });
  if (result.error) {
    throw new Error(`claim_ai_assistant_provider_start failed: ${result.error.message}`);
  }
  // RETURNS boolean (not TABLE) -- supabase-js/PostgREST wraps a scalar
  // RPC return in [{ <function_name>: value }], and this test suite's
  // pg_rls_client.ts RpcCaller mirrors that exact shape (see its own
  // doc comment on why RPC results are always an array of rows).
  const row = result.data?.[0] as Record<string, unknown> | undefined;
  return row?.claim_ai_assistant_provider_start === true;
}
```

Import it in `ai-assist/index.ts`:

```typescript
import { jsonResponse, serviceRoleClient, claimProviderStart } from "../_shared/attune_auth.ts";
```

Then, in `handleIdeas`, before the `deps.callGemini` call:

```typescript
async function handleIdeas(
  client: SupabaseClient,
  service: SupabaseClient,
  userId: string,
  target: LoadedTarget,
  request: AssistRequest,
  deps: AssistDeps,
): Promise<Response> {
  const canDispatch = await claimProviderStart(service, userId, request.requestId);
  if (!canDispatch) {
    return errorResponse(assistantError("REQUEST_FAILED"));
  }

  const context = await loadBoundedContext(client, target, "assist", userId);
```

(the rest of `handleIdeas` is unchanged — `deps.callGemini` now runs only
after a successful claim).

In `handleNearby`, apply the identical guard immediately after
`const context = await loadBoundedContext(...)` and before the first
`deps.callGemini` call (Nearby's Gemini-then-Mapbox pair shares ONE
claim, not two — the marker means "a provider call for this request has
started," not "which provider"):

```typescript
async function handleNearby(
  client: SupabaseClient,
  service: SupabaseClient,
  userId: string,
  target: LoadedTarget,
  request: AssistRequest,
  deps: AssistDeps,
): Promise<Response> {
  const canDispatch = await claimProviderStart(service, userId, request.requestId);
  if (!canDispatch) {
    return errorResponse(assistantError("REQUEST_FAILED"));
  }

  const context = await loadBoundedContext(client, target, "assist", userId);
```

- [ ] **Step 4: Apply the identical guard to `ai-understand`**

In `supabase/functions/ai-understand/index.ts`, import
`claimProviderStart` the same way, then add the guard at the start of
`handleUnderstand`, before its `deps.callGemini` call:

```typescript
async function handleUnderstand(
  client: SupabaseClient,
  service: SupabaseClient,
  userId: string,
  target: LoadedTarget,
  request: UnderstandRequest,
  deps: UnderstandDeps,
): Promise<Response> {
  const canDispatch = await claimProviderStart(service, userId, request.requestId);
  if (!canDispatch) {
    return errorResponse(assistantError("REQUEST_FAILED"));
  }

  const context = await loadBoundedContext(
```

- [ ] **Step 5: Run the new test to confirm it passes**

```bash
cd supabase/functions/ai-assist && deno test index.test.ts --allow-net --allow-env --allow-read \
  --filter "provider-start marker is already set"
```

Expected: PASS (`geminiCalls` stays `0`)

- [ ] **Step 6: Run both functions' full existing suites to confirm no regression**

```bash
cd supabase/functions/ai-assist && deno test index.test.ts --allow-net --allow-env --allow-read
cd ../ai-understand && deno test index.test.ts --allow-net --allow-env --allow-read
```

Expected: all existing tests still pass — every real success-path test in
both files exercises a request that has never been claimed before, so
`claimProviderStart` returns `true` for it and the call proceeds exactly
as before. If any existing test now fails with `REQUEST_FAILED`, it means
that test's fixture reused a `request_id` across two calls in a way that
used to be tolerated silently; fix the fixture to use a fresh
`crypto.randomUUID()` per call rather than loosening this task's guard.

- [ ] **Step 7: Type-check and lint**

```bash
deno check supabase/functions/ai-assist/index.ts supabase/functions/ai-understand/index.ts \
  supabase/functions/_shared/attune_auth.ts
deno lint supabase/functions/ai-assist/index.ts supabase/functions/ai-understand/index.ts \
  supabase/functions/_shared/attune_auth.ts
```

Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/ai-assist/index.ts supabase/functions/ai-assist/index.test.ts \
        supabase/functions/ai-understand/index.ts supabase/functions/ai-understand/index.test.ts \
        supabase/functions/_shared/attune_auth.ts
git commit -m "feat(ai-quota): claim the provider-start marker before every Gemini/Mapbox call"
```

---

### Task 4: `release_ai_assistant_quota_reservation` — the pre-start release path

**Files:**
- Create: `supabase/migrations/20260952020000_ai_assistant_quota_release_rpc.sql`
- Test: `supabase/tests/ai_assistant_quota_release_contracts.sql`

**Interfaces:**
- Consumes: `ai_assistant_usage.provider_started_at` (Task 1).
- Produces: `release_ai_assistant_quota_reservation(p_actor_id uuid, p_request_id uuid) RETURNS void`
  — the ONLY way a reservation may be excluded from the rolling-window
  count after admission. Raises if the row does not exist, belongs to a
  different actor, or has a non-NULL `provider_started_at` (a started
  reservation is permanently counted — see Global Constraints). Calling
  it on an already-released row is a no-op (idempotent), matching every
  other terminal-transition RPC in this ledger. This is what Plan B's
  session admission RPC calls when a check AFTER quota reservation but
  BEFORE any provider work fails (e.g. the session turned out to be
  closed by a concurrent End between reservation and dispatch) — see
  spec §8.2.2's row "Admission committed, no provider-start marker →
  releases exactly once."

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/ai_assistant_quota_release_contracts.sql`:

```sql
-- release_ai_assistant_quota_reservation: the exclusive "pre-start
-- release" path. Spec §7.3, §8.2.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_quota_release_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a5000000-0000-0000-0000-000000000002';
  v_user_a uuid := 'a5000000-0000-0000-0000-00000000010a';
  v_user_b uuid := 'a5000000-0000-0000-0000-00000000010b';
  v_req_release uuid := 'a5000000-0000-0000-0000-000000000201';
  v_req_started uuid := 'a5000000-0000-0000-0000-000000000202';
  v_row record;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'release_a@t.test'), (v_user_b, 'release_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550006001', 'A'), (v_user_b, '+15550006002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: releasing a never-started reservation excludes it from
  -- the rolling-window count.
  PERFORM public.reserve_ai_assistant_quota(v_user_a, v_req_release, v_rel, 'assist');
  PERFORM public.release_ai_assistant_quota_reservation(v_user_a, v_req_release);
  SELECT count(*) INTO v_count FROM public.ai_assistant_usage u
  WHERE u.user_id = v_user_a AND u.created_at >= now() - interval '24 hours'
    AND (u.provider_started_at IS NOT NULL OR u.outcome NOT IN ('rejected', 'cancelled'));
  IF v_count != 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a released never-started reservation still counts toward quota';
  END IF;

  -- Contract 2: releasing is idempotent -- calling it twice on the same
  -- row does not raise.
  PERFORM public.release_ai_assistant_quota_reservation(v_user_a, v_req_release);

  -- Contract 3: a STARTED reservation can never be released -- this is
  -- the core invariant. Attempting it must raise, and the row must
  -- remain counted afterward.
  PERFORM public.reserve_ai_assistant_quota(v_user_a, v_req_started, v_rel, 'assist');
  PERFORM public.claim_ai_assistant_provider_start(v_user_a, v_req_started);
  BEGIN
    PERFORM public.release_ai_assistant_quota_reservation(v_user_a, v_req_started);
    RAISE EXCEPTION 'EXPLOIT: a started reservation was released -- quota can be evaded post-dispatch';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
  SELECT * INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_started;
  IF v_row.outcome != 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: the rejected release attempt still mutated outcome, got %', v_row.outcome;
  END IF;

  -- Contract 4: a non-owner cannot release someone else's reservation.
  BEGIN
    PERFORM public.release_ai_assistant_quota_reservation(v_user_b, v_req_release);
    RAISE EXCEPTION 'EXPLOIT: user_b released user_a''s own reservation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 5: not `authenticated`-callable.
  IF EXISTS (
    SELECT 1 FROM information_schema.role_routine_grants g
    WHERE g.routine_name = 'release_ai_assistant_quota_reservation'
      AND g.grantee = 'authenticated'
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has EXECUTE on release_ai_assistant_quota_reservation';
  END IF;

  RAISE NOTICE 'quota release contracts: all held';
END $$;
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
psql -q -d attune_test -f supabase/tests/ai_assistant_quota_release_contracts.sql
```

Expected: `function public.release_ai_assistant_quota_reservation(uuid, uuid) does not exist`

- [ ] **Step 3: Write the RPC**

Create `supabase/migrations/20260952020000_ai_assistant_quota_release_rpc.sql`:

```sql
-- The exclusive "admitted, then rejected before any provider call"
-- release path. Spec §7.3: "A terminal failure proven to have no
-- provider-start marker may release global quota once; once either
-- provider is marked started, outcome changes never refund it." Spec
-- §8.2.2's compensation table, row "Admission committed, no provider-
-- start marker": "Terminal cancel/fail releases global reservation
-- exactly once, retains session attempt; no prompt to partner."
--
-- Marks the row 'cancelled' (already excluded from the rolling-window
-- COUNT by reserve_ai_assistant_quota's own predicate) but ONLY when
-- provider_started_at IS NULL -- the WHERE clause below is the entire
-- enforcement of "never after a start marker is set." Idempotent: a
-- second call finds no row still matching
-- (outcome = 'reserved' AND provider_started_at IS NULL) and is a no-op,
-- exactly like mark_ai_assistant_usage_outcome's own silent-no-match
-- convention.
CREATE OR REPLACE FUNCTION public.release_ai_assistant_quota_reservation(
  p_actor_id uuid, p_request_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.ai_assistant_usage
    WHERE request_id = p_request_id AND user_id = p_actor_id
  ) THEN
    RAISE EXCEPTION 'Reservation not found for this actor';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.ai_assistant_usage
    WHERE request_id = p_request_id AND user_id = p_actor_id
      AND provider_started_at IS NOT NULL
      AND outcome = 'reserved'
  ) THEN
    RAISE EXCEPTION 'Cannot release a reservation whose provider call has started';
  END IF;

  UPDATE public.ai_assistant_usage
  SET outcome = 'cancelled', updated_at = now()
  WHERE request_id = p_request_id AND user_id = p_actor_id
    AND outcome = 'reserved'
    AND provider_started_at IS NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.release_ai_assistant_quota_reservation(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_ai_assistant_quota_reservation(uuid, uuid)
  TO service_role;
```

- [ ] **Step 4: Run the migration, then the test**

```bash
psql -q -d attune_test -f supabase/migrations/20260952020000_ai_assistant_quota_release_rpc.sql
psql -q -d attune_test -f supabase/tests/ai_assistant_quota_release_contracts.sql
```

Expected: `NOTICE: quota release contracts: all held`

- [ ] **Step 5: Rebuild `attune_test` from scratch and run every SQL contract test in this feature area**

```bash
bash scripts/local_pg_setup.sh
for f in supabase/tests/ai_assistant_quota_contracts.sql \
         supabase/tests/ai_assistant_provider_start_marker_contracts.sql \
         supabase/tests/ai_assistant_quota_release_contracts.sql; do
  echo "=== $f ==="
  psql -q -d attune_test -f "$f"
done
```

Expected: all three print their `all held` NOTICE, in a database built
from migrations 0 through this task's latest, in order — proving the
migrations apply cleanly on top of each other, not just against a
hand-patched database from earlier steps in this plan.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260952020000_ai_assistant_quota_release_rpc.sql \
        supabase/tests/ai_assistant_quota_release_contracts.sql
git commit -m "feat(ai-quota): add release_ai_assistant_quota_reservation for the pre-start release path"
```

---

### Task 5: Concurrent-claim mutation test — prove the write-once guarantee under a real race

**Files:**
- Test: `supabase/tests/ai_assistant_provider_start_concurrent_test.sh` (new
  shell script driving two concurrent `psql` sessions — the existing SQL
  contract tests run single-connection and cannot exercise a genuine race)

**Interfaces:**
- Consumes: `claim_ai_assistant_provider_start` (Task 2).
- Produces: nothing for later tasks — this is pure verification evidence
  for spec §11 item 2 ("Concurrent same-key calls across endpoints/
  workers; one dispatch grant").

**Why a shell script instead of another `DO $$ ... END $$` block:** every
existing contract test in this codebase runs as one sequential session,
which can prove the RPC's own logic but cannot prove the `UPDATE ...
WHERE provider_started_at IS NULL` guard is race-free under two
Postgres backends actually contending for the same row at the same
instant. `pg_advisory_xact_lock` is not used inside
`claim_ai_assistant_provider_start` (a plain row-level `UPDATE` already
serializes correctly against itself under MVCC — Postgres guarantees
exactly one of two concurrent `UPDATE ... WHERE` statements on the same
row sees the post-update state), so this task proves that guarantee
empirically rather than asserting it works by inspection.

- [ ] **Step 1: Write the failing (not-yet-existing) concurrency script**

Create `supabase/tests/ai_assistant_provider_start_concurrent_test.sh`:

```bash
#!/usr/bin/env bash
# Proves claim_ai_assistant_provider_start grants exactly one "true"
# claim under genuine concurrent contention on the same request_id.
# Spec §11 item 2.
set -euo pipefail

REL="a5000000-0000-0000-0000-000000000003"
USER_A="a5000000-0000-0000-0000-00000000020a"
USER_B="a5000000-0000-0000-0000-00000000020b"
REQ="a5000000-0000-0000-0000-000000000301"

psql -q -d attune_test <<SQL
INSERT INTO auth.users (id, email) VALUES ('$USER_A', 'race_a@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$USER_A', '+15550007001', 'A') ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id, email) VALUES ('$USER_B', 'race_b@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$USER_B', '+15550007002', 'B') ON CONFLICT DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ('$REL', '$USER_A', '$USER_B', 'active') ON CONFLICT DO NOTHING;
SELECT public.reserve_ai_assistant_quota('$USER_A', '$REQ', '$REL', 'assist');
SQL

# Fire 20 concurrent claim attempts on the SAME request_id from
# separate psql processes (separate Postgres backends -- this is what
# makes the race real, unlike sequential calls in one session).
RESULTS_DIR=$(mktemp -d)
for i in $(seq 1 20); do
  psql -q -d attune_test -t -A -c \
    "SELECT public.claim_ai_assistant_provider_start('$USER_A', '$REQ');" \
    > "$RESULTS_DIR/result_$i.txt" &
done
wait

TRUE_COUNT=$(grep -l '^t$' "$RESULTS_DIR"/result_*.txt | wc -l | tr -d ' ')
rm -rf "$RESULTS_DIR"

if [ "$TRUE_COUNT" != "1" ]; then
  echo "EXPLOIT: expected exactly 1 of 20 concurrent claims to return true, got $TRUE_COUNT"
  exit 1
fi

echo "concurrent provider-start claim: exactly one grant out of 20 racing attempts"
```

- [ ] **Step 2: Run it to confirm it currently fails (or doesn't exist)**

```bash
chmod +x supabase/tests/ai_assistant_provider_start_concurrent_test.sh
bash scripts/local_pg_setup.sh   # fresh database so the fixed REL/USER UUIDs are free
./supabase/tests/ai_assistant_provider_start_concurrent_test.sh
```

Expected: PASS already, since Task 2's RPC is already correct — this
step is really "run it once to make sure the script itself works and
the fixed UUIDs don't collide with an earlier task's leftover data,"
not a red/green cycle on the RPC (that was Task 2's own Steps 1-2). If
it fails with a UUID collision, change the UUIDs above to a fresh,
unused prefix and retry.

- [ ] **Step 3: Run it 5 times in a row to rule out a flaky pass**

```bash
for i in 1 2 3 4 5; do
  bash scripts/local_pg_setup.sh
  ./supabase/tests/ai_assistant_provider_start_concurrent_test.sh || echo "FAILED on run $i"
done
```

Expected: 5 consecutive passes, each printing "exactly one grant out of
20 racing attempts". If any run shows `TRUE_COUNT` other than 1, this is
a real race condition in Task 2's RPC — stop and re-examine
`claim_ai_assistant_provider_start`'s `UPDATE` before continuing; do not
add a `pg_advisory_xact_lock` as a first reflex without first confirming
with `EXPLAIN (ANALYZE, BUFFERS)` on the `UPDATE` that this table's
primary key index is actually being used for the row lookup (an
unindexed `UPDATE ... WHERE` can, in rare Postgres versions/plans,
behave less atomically than expected under certain isolation levels —
confirm the plan before reaching for a bigger lock than the row itself
already provides).

- [ ] **Step 4: Commit**

```bash
git add supabase/tests/ai_assistant_provider_start_concurrent_test.sh
git commit -m "test(ai-quota): prove exactly-one-grant under concurrent provider-start claims"
```

---

## Plan A self-review

**Spec coverage against §7.3 and §8.2.2:**

- "Twenty accepted reservations per rolling [now-24h,now) across all
  modes" — already true in the starting-state migration; Task 1's `mode`
  widening extends it to `'session'` without touching the COUNT logic. ✓
- "Reservations count immediately to prevent races" — unchanged from
  starting state. ✓
- "A terminal failure proven to have no provider-start marker may
  release global quota once" — Task 4. ✓
- "once either provider is marked started, outcome changes never refund
  it" — Task 2's write-once marker plus Task 4's `provider_started_at IS
  NOT NULL` guard together enforce this: Task 2 makes the marker
  permanent, Task 4 refuses to release a marked row at all (regardless
  of what `mark_ai_assistant_usage_outcome` later sets `outcome` to). ✓
- "Atomic release is a new trusted transaction, not a claimed rollback
  of an already committed reservation" — Task 4 is exactly this: a
  fresh, separate RPC call, not a rollback. ✓
- "Duplicate keys are checked before quota limits and never restart
  work" — already true in the starting-state migration
  (`already_reserved` short-circuits before the `COUNT` check runs). ✓
- Spec §8.2.2's row "Provider-start marker set, timeout/abort/invalid
  output/crash → Attempt counted even if result absent" — this is now
  mechanically true: once `claim_ai_assistant_provider_start` returns
  `true`, Task 4's release RPC refuses to touch the row, so no later
  code path can exclude it from the count no matter what outcome value
  eventually lands. ✓

**What this plan deliberately does NOT do** (out of scope, owned by
later plans):

- It does not add a `mode = 'session'` **caller** — Plan B's session
  admission RPC is the first thing that reserves quota with that mode
  value. This plan only makes the ledger accept it.
- It does not implement §6.2's full admission transaction (relationship
  lock, session row lock, ordinal assignment, worker token/epoch/
  deadline) — that is Plan B's Task set, built on top of this plan's
  ledger.
- It does not touch `_shared/attune_auth.ts`'s `serviceRoleClient()`
  itself, `requireUser`, or any RLS policy — this plan's only new
  surface is two new RPCs and one new column, all `service_role`-only.
- It does not change the 30-day idempotency retention or the existing
  purge job (`20260950100000_ai_assistant_purge_jobs.sql`) — a purged
  row's `provider_started_at` value is purged along with the whole row,
  which is correct and needs no new logic.

**Placeholder scan:** no TBD/TODO; every SQL block above is complete and
runnable, not a description of what to write.

**Type consistency check:** `claim_ai_assistant_provider_start` and
`release_ai_assistant_quota_reservation` both take
`(p_actor_id uuid, p_request_id uuid)` in that exact order, matching
`mark_ai_assistant_usage_outcome`'s existing `p_actor_id`-first
convention from the starting-state migration. `claimProviderStart`
(the new Deno/TypeScript helper in Task 3) calls the RPC with named
arguments (`p_actor_id`, `p_request_id`), matching how every other RPC
call in `ai-assist/index.ts`/`ai-understand/index.ts` already invokes
`.rpc(name, { p_x: ... })`.

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-09-22-ai-sessions-plan-a-quota-repair.md`.
Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per
task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using
executing-plans, batch execution with checkpoints

**Which approach?**

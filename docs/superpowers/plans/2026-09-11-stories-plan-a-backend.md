# Stories — Plan A: Backend Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete server side of Stories — tables, RLS, RPCs,
storage policies, and the image-archival worker — behind the `stories`
feature flag, with nothing user-visible.

**Architecture:** Clients get `SELECT` only on `story_items`; every write
goes through a `SECURITY DEFINER` RPC that owns the server-side fields.
Expiry is structural (`expires_at` gates the reel query, no job).
Deletion is a tombstone plus an enqueued storage key. Realtime is a
refetch signal, not a second source of truth.

**Tech Stack:** Postgres 15 (Supabase), pg_cron, Deno edge functions,
`psql` contract tests under `supabase/tests/`.

**Spec:** `docs/superpowers/specs/2026-09-11-stories-design.md`

**Scope:** Spec steps 1, 2 and the image-archival half of 11. Plan B
(camera + posting) and Plan C (surfaces) follow separately.

## Global Constraints

Copied verbatim from the spec. Every task's requirements include these.

- Clients receive **`SELECT` only** on `story_items`; **no** `UPDATE` or
  `DELETE` grant exists, and `story_views` is **not readable by clients**
  at all. (§3.3, §3.4)
- Every definer function: fixed `search_path`, actor derived from
  `auth.uid()`, `REVOKE ALL ... FROM PUBLIC, anon`, granted only to the
  role that needs it. (§3.3)
- "Missing", "not a member", "ended relationship" and "deleted" return
  the **same** unavailable result — never an existence oracle. (§3.3)
- Reads require the relationship to be **ACTIVE and unarchived**
  (`status = 'active' AND chat_archived_at IS NULL`). Deletion does
  **not** — an author never loses the right to remove their own retained
  media. (§3.3, §8)
- `expires_at = created_at + interval '24 hours'`, enforced by CHECK.
  Nothing deletes a row when it passes. (§3.2)
- Storage: private bucket `story-media`, **keys not URLs**, signed URL
  TTL **600 seconds**. (§4.1)
- Physical deletion goes through the **Storage API worker**
  (`process-media-deletion-queue`), never `DELETE FROM storage.objects`.
  (§4.2)
- Read RPCs are `SECURITY INVOKER` so RLS stays the single authority; the
  server caps `p_limit` at **50**. (§5.5)
- Object limits: image JPEG ≤ **5MB** / 2560px long edge; video MP4
  ≤ **25MB**, declared duration **500ms–60000ms**; thumbnail JPEG
  ≤ **800KB** / 400px. (§4.2)
- Intent abuse limits: ≤ **120** intent calls per user per rolling hour;
  refuse when the user holds ≥ **20** unconsumed, unexpired intents.
  (§4.2)
- `stories` feature flag gates new upload intents. Finalization of an
  already-issued intent, reads, and author deletion stay enabled so a
  rollout change strands nothing. (§8)

## Migration numbering

Existing migrations run to `20260937140000`. This plan uses
`20260938010000` upward, one file per task, so a task can be reverted
without disturbing its neighbours.

## File structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260938010000_stories_schema.sql` | Tables, constraints, indexes, flag row |
| `supabase/migrations/20260938020000_stories_rls.sql` | Membership helper, RLS policies, grants |
| `supabase/migrations/20260938030000_stories_storage.sql` | Bucket, intents table, storage policies |
| `supabase/migrations/20260938040000_stories_intent_rpc.sql` | `create_story_upload_intent` + rate limits |
| `supabase/migrations/20260938050000_stories_finalize_rpc.sql` | `create_story_item` |
| `supabase/migrations/20260938060000_stories_view_rpc.sql` | `mark_story_viewed`, change signals |
| `supabase/migrations/20260938070000_stories_delete_rpc.sql` | `delete_story_item`, queue `not_before`, cascades |
| `supabase/migrations/20260938080000_stories_read_rpcs.sql` | The four `SECURITY INVOKER` read RPCs |
| `supabase/migrations/20260938090000_stories_maintenance.sql` | Intent cleanup, archival claim/swap, cron |
| `supabase/functions/process-story-archival/index.ts` | Image downscale worker |
| `supabase/tests/story_schema_contracts.sql` | Constraint and index contracts |
| `supabase/tests/story_security_contracts.sql` | Grants, RLS, and the attack suite |
| `supabase/tests/story_rpc_contracts.sql` | Mutation RPC behaviour |
| `supabase/tests/story_read_contracts.sql` | Read RPCs, paging, caps |
| `supabase/tests/story_maintenance_contracts.sql` | Cleanup, archival, races |
| `scripts/concurrency/story_races.sh` | Two-connection races |

## How to run tests

```bash
# Apply one migration
psql -q -d attune_test -f supabase/migrations/<file>.sql

# Run one contract file (wraps in BEGIN/ROLLBACK, RAISEs on violation)
psql -q -d attune_test -f supabase/tests/<file>.sql
# Clean exit + the file's final NOTICE = every contract held.
```

Every contract file follows the house pattern in
`supabase/tests/game_invite_contracts.sql`: `BEGIN`, fixtures, a `DO
$$...$$` block that `RAISE EXCEPTION`s on any violated contract, then
`ROLLBACK`.

**Two house rules that have already caught real bugs here:**

1. **Never compare a `SELECT ... INTO` variable with `<>` or `=`.** A
   NULL makes the comparison NULL and the `IF` never fires, so the test
   passes while asserting nothing. Always `IS DISTINCT FROM`.
2. **Mutation-test every contract file.** Break the thing it guards,
   confirm the test fails, restore. A contract that passes against a
   deliberately broken build is not a contract.

---

### Task 1: Schema, constraints and the feature flag

**Files:**
- Create: `supabase/migrations/20260938010000_stories_schema.sql`
- Create: `supabase/tests/story_schema_contracts.sql`

**Interfaces:**
- Produces: tables `public.story_items`, `public.story_views`,
  `public.story_change_signals`; feature flag key `stories`.

- [ ] **Step 1: Write the failing contract test**

Create `supabase/tests/story_schema_contracts.sql`:

```sql
-- The story row's shape is a security boundary, not just a schema.
-- expires_at must be exactly 24h from creation (a client-controlled
-- window would let a story live forever); a video must carry a duration
-- and an image must not; and the two storage keys must differ, or
-- deleting a story would remove its own thumbnail twice and its media
-- never.
BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-0000000051a1'::uuid),
  ('00000000-0000-0000-0000-0000000051a2'::uuid) ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000051a1'::uuid,'+15550510001','S1'),
  ('00000000-0000-0000-0000-0000000051a2'::uuid,'+15550510002','S2')
  ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_rel uuid;
  v_now timestamptz := now();
  v_ok  boolean;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-0000000051a1'::uuid,
          '00000000-0000-0000-0000-0000000051a2'::uuid, 'active')
  RETURNING id INTO v_rel;

  -- A 48-hour window must be refused.
  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height,
      occurred_on, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
            'k/a', 'k/b', 100, 100, current_date, v_now,
            v_now + interval '48 hours');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'EXPLOIT: a story set its own 48h expiry';
  END IF;

  -- An image carrying a duration must be refused.
  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height, duration_ms,
      occurred_on, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
            'k/c', 'k/d', 100, 100, 5000, current_date, v_now,
            v_now + interval '24 hours');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'an image row accepted a duration';
  END IF;

  -- A video outside 500ms-60s must be refused.
  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height, duration_ms,
      occurred_on, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'video',
            'k/e', 'k/f', 100, 100, 90000, current_date, v_now,
            v_now + interval '24 hours');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'a 90s video was accepted';
  END IF;

  -- Identical media and thumbnail keys must be refused.
  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height,
      occurred_on, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
            'k/same', 'k/same', 100, 100, current_date, v_now,
            v_now + interval '24 hours');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'media_key and thumbnail_key were allowed to match';
  END IF;

  -- A valid row is accepted, and the same (author, client_story_id)
  -- twice is refused -- this is what makes finalize retries safe.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at)
  VALUES ('00000000-0000-0000-0000-00000000c1d1'::uuid, v_rel,
          '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
          'k/good', 'k/goodthumb', 1080, 1920, current_date, v_now,
          v_now + interval '24 hours');

  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height,
      occurred_on, created_at, expires_at)
    VALUES ('00000000-0000-0000-0000-00000000c1d1'::uuid, v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
            'k/good2', 'k/goodthumb2', 1080, 1920, current_date, v_now,
            v_now + interval '24 hours');
    v_ok := true;
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'a replayed client_story_id posted twice';
  END IF;

  -- has_been_viewed starts false: nothing is seen before it is sent.
  PERFORM 1 FROM public.story_items
   WHERE client_story_id = '00000000-0000-0000-0000-00000000c1d1'::uuid
     AND has_been_viewed IS FALSE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'has_been_viewed did not default to false';
  END IF;

  RAISE NOTICE 'story schema contracts: all held';
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -q -d attune_test -f supabase/tests/story_schema_contracts.sql`
Expected: `ERROR: relation "public.story_items" does not exist`

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260938010000_stories_schema.sql` with the
three tables exactly as given in spec §3.1 and §5.5 (`story_items` with
all CHECK constraints and both partial indexes, `story_views`,
`story_change_signals`), plus:

```sql
INSERT INTO public.feature_flags(key, enabled, description)
VALUES ('stories', false,
        'Stories: 24h partner-audience reel, permanent in the calendar')
ON CONFLICT (key) DO NOTHING;
```

Copy the DDL verbatim from the spec — it is the authority, and retyping
it from memory is how a constraint goes missing.

- [ ] **Step 4: Apply and re-run**

```bash
psql -q -d attune_test -f supabase/migrations/20260938010000_stories_schema.sql
psql -q -d attune_test -f supabase/tests/story_schema_contracts.sql
```
Expected: `NOTICE: story schema contracts: all held`

- [ ] **Step 5: Mutation-test the contracts**

Drop the `story_expires_in_24h` CHECK, re-run, confirm the test FAILS,
then restore. Repeat for `story_duration_matches_type` and the
`UNIQUE (author_id, client_story_id)`. A contract that survives its
mutant is asserting nothing.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260938010000_stories_schema.sql \
        supabase/tests/story_schema_contracts.sql
git commit -m "feat(stories): schema, constraints and the stories flag"
```

---

### Task 2: RLS, grants and the membership helper

**Files:**
- Create: `supabase/migrations/20260938020000_stories_rls.sql`
- Create: `supabase/tests/story_security_contracts.sql`

**Interfaces:**
- Consumes: tables from Task 1.
- Produces: `public.story_relationship_is_open(p_relationship_id uuid,
  p_user uuid) RETURNS boolean` — `SECURITY DEFINER`, true only for a
  member of an ACTIVE, unarchived relationship.

- [ ] **Step 1: Write the failing contract test**

Create `supabase/tests/story_security_contracts.sql`. This is the most
important file in the plan, so it is written as attacks that must fail.
Include, at minimum:

```sql
-- Grants: authenticated gets SELECT on story_items and NOTHING on
-- story_views. An UPDATE grant would let an author rewrite expires_at,
-- occurred_on or media_key; a DELETE grant would bypass the soft-delete
-- contract and strand the storage object forever.
RESET ROLE;
DO $$ BEGIN
  IF has_table_privilege('authenticated','public.story_items','UPDATE') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can UPDATE story_items';
  END IF;
  IF has_table_privilege('authenticated','public.story_items','DELETE') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can DELETE story_items';
  END IF;
  IF has_table_privilege('authenticated','public.story_items','INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can INSERT story_items directly';
  END IF;
  IF NOT has_table_privilege('authenticated','public.story_items','SELECT') THEN
    RAISE EXCEPTION 'authenticated cannot read story_items';
  END IF;
  IF has_table_privilege('authenticated','public.story_views','SELECT') THEN
    RAISE EXCEPTION
      'EXPLOIT: authenticated can read story_views -- viewed_at leaks '
      'a partner''s activity pattern';
  END IF;
END $$;
```

Then, in a `DO` block with three users (two partners, one outsider) and
two relationships:

1. **An outsider selects a story** → zero rows.
2. **A member selects a soft-deleted story** → zero rows.
3. **A member of an ENDED relationship selects** → zero rows
   (`status <> 'active'`).
4. **A member of an ARCHIVED chat selects** → zero rows
   (`chat_archived_at IS NOT NULL`).
5. **A member selects a live story** → exactly one row.
6. **An outsider selects `story_change_signals`** → zero rows.

Use `IS DISTINCT FROM` for every comparison of a `SELECT ... INTO`
variable.

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -q -d attune_test -f supabase/tests/story_security_contracts.sql`
Expected: FAIL — with no policies yet, RLS is not even enabled.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260938020000_stories_rls.sql`:

```sql
-- Membership, in one place.
--
-- SECURITY DEFINER so a storage policy can call it without granting
-- clients SELECT on the tables it reads. ACTIVE and unarchived, matching
-- the chat-media precedent rather than the laxer timeline one: stories
-- are personal media, and access ends when the relationship does.
CREATE OR REPLACE FUNCTION public.story_relationship_is_open(
  p_relationship_id uuid,
  p_user uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
     WHERE r.id = p_relationship_id
       AND r.status = 'active'
       AND r.chat_archived_at IS NULL
       AND (r.user_a = p_user OR r.user_b = p_user)
  );
$$;

REVOKE ALL ON FUNCTION public.story_relationship_is_open(uuid, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.story_relationship_is_open(uuid, uuid)
  TO authenticated;

ALTER TABLE public.story_items          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_views          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_change_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY story_items_read_members ON public.story_items
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    AND public.story_relationship_is_open(relationship_id, auth.uid())
  );

-- No INSERT, UPDATE or DELETE policy exists, by design (§3.3).

CREATE POLICY story_signals_read_members ON public.story_change_signals
  FOR SELECT TO authenticated
  USING (public.story_relationship_is_open(relationship_id, auth.uid()));

-- story_views gets NO policy at all: RLS on with no policy denies
-- everything, which is exactly the contract (§3.4).

REVOKE ALL ON public.story_items          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.story_views          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.story_change_signals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.story_items          TO authenticated;
GRANT SELECT ON public.story_change_signals TO authenticated;
```

- [ ] **Step 4: Apply and re-run**

```bash
psql -q -d attune_test -f supabase/migrations/20260938020000_stories_rls.sql
psql -q -d attune_test -f supabase/tests/story_security_contracts.sql
```
Expected: `NOTICE: story security contracts: all held`

- [ ] **Step 5: Mutation-test**

Run each, confirm a FAILURE, then restore:

| Mutant | Must fail |
|---|---|
| `GRANT UPDATE ON story_items TO authenticated` | the UPDATE grant check |
| Drop `deleted_at IS NULL` from the read policy | the soft-delete check |
| Drop `AND r.status = 'active'` from the helper | the ended-relationship check |
| Drop `AND r.chat_archived_at IS NULL` | the archived check |
| `GRANT SELECT ON story_views TO authenticated` | the views-privacy check |

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260938020000_stories_rls.sql \
        supabase/tests/story_security_contracts.sql
git commit -m "feat(stories): read-only RLS, and no write grants at all"
```

---

### Task 3: Private bucket, intents table and storage policies

**Files:**
- Create: `supabase/migrations/20260938030000_stories_storage.sql`

**Interfaces:**
- Consumes: `story_relationship_is_open` from Task 2.
- Produces: bucket `story-media`; table
  `public.story_media_upload_intents(id, relationship_id, requested_by,
  media_role, storage_key, mime_type, max_bytes, expires_at, used_at,
  cleanup_queued_at, created_at)` where `media_role IN ('media','thumbnail')`.

- [ ] **Step 1: Write the failing contract test**

Append to `supabase/tests/story_security_contracts.sql`:

```sql
-- The bucket must be PRIVATE. A public bucket makes every storage key a
-- permanent unauthenticated URL, which defeats deletion entirely.
RESET ROLE;
DO $$
DECLARE v_public boolean;
BEGIN
  SELECT public INTO v_public FROM storage.buckets WHERE id = 'story-media';
  IF v_public IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: story-media bucket is public or missing';
  END IF;
END $$;
```

- [ ] **Step 2: Run it to verify it fails**

Expected: `EXPLOIT: story-media bucket is public or missing`

- [ ] **Step 3: Write the migration**

Create the bucket with `public = false`, the intents table, and storage
policies per spec §4.2:

- **INSERT** permits exactly the unconsumed, unexpired key owned by
  `auth.uid()`; `upsert: false`.
- **SELECT** requires the key to belong to a `story_items` row with
  `deleted_at IS NULL` whose relationship passes
  `story_relationship_is_open`, OR to an unconsumed intent owned by the
  caller (so the client can verify its own upload before finalizing).
- No UPDATE or DELETE policy — physical deletion is the worker's job.

- [ ] **Step 4: Apply and re-run**

Expected: the bucket contract passes.

- [ ] **Step 5: Mutation-test**

Set the bucket `public = true`, confirm FAIL, restore.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260938030000_stories_storage.sql \
        supabase/tests/story_security_contracts.sql
git commit -m "feat(stories): private bucket, upload intents, storage policies"
```

---

### Task 4: `create_story_upload_intent` with abuse limits

**Files:**
- Create: `supabase/migrations/20260938040000_stories_intent_rpc.sql`
- Create: `supabase/tests/story_rpc_contracts.sql`

**Interfaces:**
- Produces: `create_story_upload_intent(p_relationship_id uuid,
  p_media_role text, p_mime_type text) RETURNS jsonb` —
  `{intent_id, storage_key, bucket, expires_at}` or
  `{error:true, code, message}`.

- [ ] **Step 1: Write the failing contract test**

Create `supabase/tests/story_rpc_contracts.sql` asserting:

1. An outsider requesting an intent for someone else's relationship gets
   `FORBIDDEN` and **no row is written**.
2. A member with the `stories` flag OFF gets a refusal (§8 gates new
   intents only).
3. A member with the flag ON gets a key under `story-media/`.
4. Holding 20 unconsumed unexpired intents → `rate_limited`.
5. 121 calls in one hour → `rate_limited`.
6. An unlisted `p_media_role` or a MIME outside the allowlist →
   `INVALID_INPUT`.

- [ ] **Step 2: Run to verify it fails** — function does not exist.

- [ ] **Step 3: Write the migration**

`SECURITY DEFINER`, fixed `search_path`, derives `requested_by` from
`auth.uid()`, validates membership via `story_relationship_is_open`,
enforces both limits from the Global Constraints, and stores
`max_bytes` per role (5MB media-image / 25MB media-video / 800KB
thumbnail) so finalization can check it without re-deriving.

- [ ] **Step 4: Apply and re-run** — all six contracts hold.

- [ ] **Step 5: Mutation-test**

Remove the membership check → contract 1 fails. Remove the 20-intent
ceiling → contract 4 fails. Remove the hourly cap → contract 5 fails.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260938040000_stories_intent_rpc.sql \
        supabase/tests/story_rpc_contracts.sql
git commit -m "feat(stories): upload intents, with abuse limits"
```

---

### Task 5: `create_story_item` — idempotent finalization

**Files:**
- Create: `supabase/migrations/20260938050000_stories_finalize_rpc.sql`
- Modify: `supabase/tests/story_rpc_contracts.sql`

**Interfaces:**
- Consumes: intents from Task 4.
- Produces: `create_story_item(p_relationship_id uuid,
  p_client_story_id uuid, p_media_intent_id uuid,
  p_thumbnail_intent_id uuid, p_media_width int, p_media_height int,
  p_duration_ms int, p_utc_offset_minutes int) RETURNS jsonb` —
  `{story_id, existing}`.

- [ ] **Step 1: Write the failing contract test**

Assert:

1. **A replayed `(author, client_story_id)` returns the SAME story id
   with `existing = true`, and posts no second row.** This is the whole
   reason the column exists.
2. A client-supplied `expires_at` is impossible — the signature has no
   such parameter, and the stored value is exactly `created_at + 24h`.
3. `occurred_on` follows `p_utc_offset_minutes`: at offset `+780`
   (Auckland) a `now()` near 12:00 UTC files the NEXT civil date.
   Offsets outside `[-840, 840]` are clamped, not trusted.
4. An intent belonging to another user → unavailable.
5. A consumed intent → unavailable, and no second row.
6. Both intents must be consumed in the same transaction; failing the
   second leaves the first unconsumed.
7. An object exceeding its intent's `max_bytes` → refused.

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Write the migration**

Per spec §3.3 and §4.2: `SECURITY DEFINER`, locks both intents `FOR
UPDATE`, verifies requester and relationship match, checks object
existence, MIME and size from `storage.objects`, captures one `v_now`
for `created_at`/`expires_at`/`occurred_on`, derives `media_type` from
the intent, bumps `story_change_signals`, and returns the existing row
on a `(author_id, client_story_id)` conflict rather than raising.

- [ ] **Step 4: Apply and re-run** — all seven hold.

- [ ] **Step 5: Mutation-test**

Remove the `ON CONFLICT` idempotency branch → contract 1 fails. Ignore
`p_utc_offset_minutes` and use `current_date` → contract 3 fails. Drop
the size check → contract 7 fails.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260938050000_stories_finalize_rpc.sql \
        supabase/tests/story_rpc_contracts.sql
git commit -m "feat(stories): idempotent finalization"
```

---

### Task 6: `mark_story_viewed` and change signals

**Files:**
- Create: `supabase/migrations/20260938060000_stories_view_rpc.sql`
- Modify: `supabase/tests/story_rpc_contracts.sql`

**Interfaces:**
- Produces: `mark_story_viewed(p_story_item_id uuid) RETURNS jsonb`;
  `public.bump_story_signal(p_relationship_id uuid)` (internal).

- [ ] **Step 1: Write the failing contract test**

Assert:

1. **The author marking their own story does NOT set
   `has_been_viewed`.** Otherwise reviewing your own reel marks it seen
   and the author's indicator becomes meaningless.
2. The partner marking it sets `has_been_viewed = true` and writes
   exactly one `story_views` row.
3. A second call by the same viewer does not move `viewed_at`
   (`ON CONFLICT DO NOTHING`).
4. An outsider is refused and writes nothing.
5. A deleted story is refused.
6. **An EXPIRED story is refused** — calendar views must not flip a
   long-settled indicator (§3.4).
7. A successful first view bumps `story_change_signals.version`.

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Write the migration.**

- [ ] **Step 4: Apply and re-run** — all seven hold.

- [ ] **Step 5: Mutation-test**

Remove the author check → contract 1 fails. Remove the expiry check →
contract 6 fails. Drop the signal bump → contract 7 fails.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260938060000_stories_view_rpc.sql \
        supabase/tests/story_rpc_contracts.sql
git commit -m "feat(stories): view marking, private timestamp, public boolean"
```

---

### Task 7: `delete_story_item`, queue `not_before`, and cascades

**Files:**
- Create: `supabase/migrations/20260938070000_stories_delete_rpc.sql`
- Modify: `supabase/tests/story_rpc_contracts.sql`

**Interfaces:**
- Modifies: `public.media_deletion_queue` gains
  `not_before timestamptz NOT NULL DEFAULT now()`.
- Produces: `delete_story_item(p_story_item_id uuid) RETURNS jsonb`.

- [ ] **Step 1: Write the failing contract test**

Assert:

1. A non-author is refused and the row is untouched.
2. The author stamps `deleted_at` AND enqueues **three** keys — media,
   thumbnail, and the deterministic archive key — in one transaction.
3. **Deleting from an ENDED relationship succeeds.** An author never
   loses the right to remove their own retained media (§3.3).
4. Deleting twice returns success and **re-arms** an already-completed
   queue entry (sets `deleted_at = NULL` on the queue row) rather than
   silently doing nothing.
5. The archive key's queue entry carries `not_before >= now() + 600s`,
   so a live player holding a fresh signed URL is not broken (§4.4).
6. Relationship deletion cascades every story and enqueues each one's
   keys.

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Write the migration**

Add `not_before` to `media_deletion_queue` (and teach
`process-media-deletion-queue` to respect it — see Task 10), then the
RPC per §4.5, plus a cascade trigger on `relationships`.

- [ ] **Step 4: Apply and re-run** — all six hold.

- [ ] **Step 5: Mutation-test**

Drop the archive-key enqueue → contract 2 fails. Require an active
relationship → contract 3 fails. Remove the re-arm → contract 4 fails.
Set `not_before = now()` → contract 5 fails.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260938070000_stories_delete_rpc.sql \
        supabase/tests/story_rpc_contracts.sql
git commit -m "feat(stories): deletion tombstones and enqueues in one transaction"
```

---

### Task 8: The four read RPCs

**Files:**
- Create: `supabase/migrations/20260938080000_stories_read_rpcs.sql`
- Create: `supabase/tests/story_read_contracts.sql`

**Interfaces:**
- Produces, all `SECURITY INVOKER`:
  `get_story_ring_summary(p_relationship_id uuid)`;
  `list_active_story_items(p_relationship_id, p_author_id, p_after_created_at, p_after_id, p_limit)`;
  `list_story_day_counts(p_relationship_id, p_start_on, p_end_on)`;
  `list_story_day_items(p_relationship_id, p_occurred_on, p_after_created_at, p_after_id, p_limit)`.

- [ ] **Step 1: Write the failing contract test**

Assert:

1. **`p_limit = 1000` returns at most 50.** A modified client must not
   be able to ask for an unbounded page.
2. `list_active_story_items` excludes `expires_at <= now()` but
   `list_story_day_items` includes them — the same row, two surfaces.
3. Keyset paging with an insert between pages **appends** rather than
   duplicating or skipping (this is why it is not offset paging).
4. Ordering is oldest-first for both playback reads.
5. An outsider gets zero rows from all four — RLS is the authority, not
   a re-implemented predicate.
6. `get_story_ring_summary` returns the newest thumbnail per author and
   an unviewed count that excludes the caller's own stories.

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Write the migration.**

- [ ] **Step 4: Apply and re-run** — all six hold.

- [ ] **Step 5: Mutation-test**

Remove the `LEAST(p_limit, 50)` cap → contract 1 fails. Switch
`list_active_story_items` to include expired → contract 2 fails. Make
one RPC `SECURITY DEFINER` without re-checking membership → contract 5
fails.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260938080000_stories_read_rpcs.sql \
        supabase/tests/story_read_contracts.sql
git commit -m "feat(stories): four capped, keyset-paged read RPCs"
```

---

### Task 9: Maintenance — intent cleanup and image archival claim

**Files:**
- Create: `supabase/migrations/20260938090000_stories_maintenance.sql`
- Create: `supabase/tests/story_maintenance_contracts.sql`

**Interfaces:**
- Produces: `cleanup_expired_story_media_intents()`;
  `claim_story_archival_batch(p_limit int)`;
  `complete_story_archival(p_story_id uuid, p_new_key text)`.

- [ ] **Step 1: Write the failing contract test**

Assert:

1. Cleanup enqueues an expired unused intent's key and stamps
   `cleanup_queued_at`; a second run does **not** re-arm the same key
   (that is what the stamp is for).
2. Cleanup **never** touches a used intent's finalized object.
3. `claim_story_archival_batch` leases rows so two concurrent runs
   cannot claim the same story.
4. A stale lease is reclaimable after its timeout — a crashed worker
   must not park a row forever.
5. **`complete_story_archival` on a story deleted mid-flight enqueues
   the newly produced object** rather than leaving it orphaned (§4.5
   race).
6. A successful swap enqueues the OLD key with
   `not_before >= now() + 600s` and bumps the change signal.

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Write the migration**

Per §4.4: lease columns, deterministic archive keys, and the ordering
**create rendition → conditionally swap → enqueue old key**. Register
two pg_cron jobs (hourly cleanup, hourly archival invoke) following
`supabase/migrations/20260936160000_arcade_expiry_jobs.sql`.

- [ ] **Step 4: Apply and re-run** — all six hold.

- [ ] **Step 5: Mutation-test**

Drop the `cleanup_queued_at` stamp → contract 1 fails. Remove the lease
→ contract 3 fails. Make `complete_story_archival` skip deleted stories
without enqueueing → contract 5 fails.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260938090000_stories_maintenance.sql \
        supabase/tests/story_maintenance_contracts.sql
git commit -m "feat(stories): intent cleanup and leased image archival"
```

---

### Task 10: The archival worker, and teaching the deletion worker `not_before`

**Files:**
- Create: `supabase/functions/process-story-archival/index.ts`
- Modify: `supabase/functions/process-media-deletion-queue/index.ts`

**Interfaces:**
- Consumes: `claim_story_archival_batch`, `complete_story_archival`.

- [ ] **Step 1: Read the existing workers**

```bash
cat supabase/functions/process-chat-media/index.ts
cat supabase/functions/process-media-deletion-queue/index.ts
```

`process-chat-media` shows the Storage image transform this worker
reuses (§4.4: 1600px long edge, quality 80). `process-media-deletion-queue`
is the physical deleter and must now skip rows whose `not_before` is in
the future.

- [ ] **Step 2: Modify the deletion worker**

Add `.lte('not_before', new Date().toISOString())` to its pending query.
Without this, Task 7's delayed archive deletion is ignored and a live
player can break mid-playback.

- [ ] **Step 3: Write the archival worker**

Claim a batch, download with `transform: { width: 1600, resize: 'contain',
quality: 80 }`, upload under the deterministic archive key with
`upsert: false`, call `complete_story_archival`. **Images only** — a
video row is marked `downscaled_at` without re-encoding, per §4.4.

- [ ] **Step 4: Verify**

```bash
deno check supabase/functions/process-story-archival/index.ts
deno check supabase/functions/process-media-deletion-queue/index.ts
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/process-story-archival/index.ts \
        supabase/functions/process-media-deletion-queue/index.ts
git commit -m "feat(stories): image archival worker; deletion respects not_before"
```

---

### Task 11: Concurrency races

**Files:**
- Create: `scripts/concurrency/story_races.sh`

**Interfaces:**
- Consumes: every RPC above.

- [ ] **Step 1: Read the existing race harness**

```bash
cat scripts/concurrency/game_invite_races.sh
```

Single-transaction contract files cannot show a race. This one uses two
connections, following that file's shape.

- [ ] **Step 2: Write the races**

1. **Two concurrent finalizes of the same `client_story_id`** → one
   story, one row, both callers get the same id.
2. **Two concurrent `mark_story_viewed`** → one `story_views` row, one
   signal bump.
3. **Delete racing archival completion** → the story is deleted AND
   every produced object is enqueued; nothing leaks.
4. **Two concurrent archival claims** → the same story is processed
   once.

- [ ] **Step 3: Run it**

```bash
bash scripts/concurrency/story_races.sh
```
Expected: all four report the single-outcome result.

- [ ] **Step 4: Prove the harness works**

Drop the `FOR UPDATE` from `create_story_item`, re-run, confirm race 1
produces TWO stories, then restore. A race test that has never failed is
not a test.

- [ ] **Step 5: Commit**

```bash
git add scripts/concurrency/story_races.sh
git commit -m "test(stories): two-connection races for finalize, view, delete, archival"
```

---

### Task 12: Full-suite verification

**Files:** none — this task only runs things.

- [ ] **Step 1: Reset and replay every migration**

```bash
scripts/local_pg_setup.sh
```
Expected: clean exit. This proves the migrations apply in order from
scratch, not just against the database they were developed on.

- [ ] **Step 2: Run every story contract file**

```bash
for f in supabase/tests/story_*.sql; do
  echo "--- $f"; psql -q -d attune_test -f "$f"
done
```
Expected: each ends with its `all held` NOTICE and no `ERROR`.

- [ ] **Step 3: Run the pre-existing suites**

```bash
for f in supabase/tests/game_message_contracts.sql \
         supabase/tests/games_contracts.sql \
         supabase/tests/session_games_contracts.sql \
         supabase/tests/chat_system_contracts.sql; do
  echo "--- $f"; psql -q -d attune_test -f "$f"
done
```
Expected: unchanged. Task 7 altered a **shared** table
(`media_deletion_queue`), so this is the check that it broke nothing.

- [ ] **Step 4: Confirm nothing is user-visible yet**

```bash
psql -q -d attune_test -c \
  "select enabled from public.feature_flags where key='stories';"
```
Expected: `f`. Plan A ships dark.

- [ ] **Step 5: Commit**

```bash
git commit --allow-empty -m "test(stories): backend suite green from a clean database"
```

---

## Plan A completion criteria

From spec §12, the subset this plan owns:

- [ ] New stories are visible only to members of an ACTIVE, unarchived
      relationship; access ends immediately when that relationship ends
      or the author deletes the story.
- [ ] No caller can retrieve the exact view timestamp, and the author
      cannot mark their own story seen.
- [ ] The reel expires from server time with no job, while the same row
      remains readable from its calendar day.
- [ ] Deletion hides every surface synchronously and queues every object,
      including on a relationship cascade.
- [ ] A failed maintenance job affects cost only — never reel expiry, and
      never logical deletion.
- [ ] Every contract file has been mutation-tested.
- [ ] The `stories` flag is OFF.

**Not in this plan:** the camera, the outbox, the rings, the reel, the
calendar and replies are Plans B and C.

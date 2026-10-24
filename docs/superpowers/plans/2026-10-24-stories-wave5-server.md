# Stories Wave 5: Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the stories robustness program on the server:
- stories come first in "Download my data", with real file extensions;
- archival downsizes portrait photos, checks every rendition before the swap and keeps up with volume;
- a story is filed on the day it was taken, whatever the session time zone;
- the bucket, the service-role check, the membership helper and the intent limits are hardened;
- the ring and day reads carry what the Wave 4 client already waits for;
- an author can find and delete their own stories after an ending;
- the harness runs every story contract green as shipped;
- one handoff doc covers all five waves.

**Architecture:** Twelve idempotent migrations in the range `20261024100000`–`20261024109999`, each test-first against a SQL contract run on the local scratch database `attune_spec3a`. Two edge functions change: `process-story-archival` is split into a testable `archival.ts` plus a thin `index.ts`, and `build-data-exports` changes only its README and left-out note. `_shared/attune_auth.ts` gains a constant-time compare. Each server change carries the small client change it needs, and the client stays tolerant of an older server (`PGRST202` fallbacks, nullable new fields).

**Tech Stack:**
- Postgres 17 (Homebrew `postgresql@17`), plpgsql/sql functions, RLS, pg_cron/pg_net stubs locally.
- Supabase Storage (bucket limits, image transform).
- Deno 2.8 (`deno test`, std 0.224 assert), supabase-js 2.39 on esm.sh.
- Flutter 3.29, Riverpod 2.6, `package:clock`, `flutter_test`; `package:http/testing` `MockClient` for the repository tests.

**Spec:** `docs/reviews/2026-10-23-stories-robustness-review.md` (Wave 5), with:
- `docs/reviews/2026-10-23-stories-review/04_lifecycle_memories.md` #1, #3, #7–#14, #17, #19, #20;
- `05_security_privacy.md` #3, #4, #5, #8, #9;
- `06_standards_checklist.md` #22, #23, #26;
- `07b_verification_server.md` V8/G8 (export order), V10/G10 (constant-time compare), checklist P0-U 2.3 and 2.5;
- `01_posting.md` #17, #18;
- the Wave 2 and Wave 4 ledgers: `.superpowers/sdd/2026-10-23-stories-wave2-posting/progress.md` (final review I2: longer video intents) and `.superpowers/sdd/2026-10-23-stories-wave4-rings-calendar/progress.md` (L7 index, `next_expires_at`/`server_now`, `p_author_id`, per-author unviewed counts, M-6, batch signing deferred).

Binding product spec: `lib/architecture/STORIES.md`. Task 16 amends it.

## Global Constraints

- **Where to work.** The main working tree, on `main`. It holds the user's own uncommitted edits plus the uncommitted Waves 1–4. Never revert, stage, stash, check out or reformat any of them. Edit shared files surgically.
- **No commits. No deploys. No `supabase db push`.** Every "Commit" step in this plan is a **Checkpoint**: run the task's tests and `flutter analyze <touched Dart files>` filtered with `grep -E '^\s*(error|warning) '`; nothing is staged. The owner commits and deploys.
- **SQL only against `attune_spec3a`.** Apply a migration with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/<file>.sql`. Run a contract with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/<file>.sql`; every contract is `BEGIN … ROLLBACK`. **Never** use `attune_test`, never run `scripts/local_pg_setup.sh`, never re-run `scripts/local_pg_grants.sql` against `attune_spec3a` (its blanket grant would undo the replayed revokes there).
- **Migrations.**
  - New files only, never edit an existing migration; timestamps `20261024100000`–`20261024109999`.
  - Idempotent: `CREATE OR REPLACE`, `DROP … IF EXISTS` then `CREATE`, `IF NOT EXISTS`, guarded `DO` blocks, unschedule-then-schedule.
  - Every new or redefined `SECURITY DEFINER` function has `SET search_path = ''` and schema-qualifies every name (`public.`, `storage.`, `auth.`, `extensions.`, `cron.`).
  - A migration that needs a transaction (a `DROP` + `CREATE` pair, a policy swap, a job restart) contains its own `BEGIN;` … `COMMIT;`. Supabase CLI 2.75 does not wrap files.
  - Function grants: client functions `REVOKE ALL … FROM PUBLIC, anon` then `GRANT EXECUTE … TO authenticated`; worker functions `REVOKE ALL … FROM PUBLIC, anon, authenticated` then `GRANT EXECUTE … TO service_role`. A `DROP` loses grants, so re-grant after every re-create.
- **Contracts.** House style: `RAISE EXCEPTION 'CONTRACT VIOLATED: …'`, jsonb comparisons with `IS [NOT] DISTINCT FROM`. Fixture phones must be unused on `attune_spec3a`; this plan reserves `+1555093xxxx` (verified free: `select count(*) from public.users where phone like '+1555093%'` → 0). Each new contract file is named `story_*_contracts.sql` so the shared run command below picks it up.
- **Tests first.** Write the test, run it, see it fail for the stated reason, then implement. Update an existing test only where it pins the behaviour this plan changes, and say so in the step.
- **Formatting.** Never run `dart format` on a file that existed before this plan (older formatter; reflowing is a regression). `dart format <path>` only on files this plan creates. Deno files: no `deno fmt` on existing files.
- **UI standards.** Design tokens (`Spacing`, `Theme.of(context).colorScheme`), `MyDateFormat` for every displayed date (`MyDateFormat.join` for date + info), 48 dp targets, semantics on every control. Owner-visible copy is plain and warm.
- **Libraries.** Riverpod, Supabase, existing dependencies only. No new packages.
- **End state.** The whole Flutter suite (`flutter test`) passes; every story SQL contract and the related contracts pass on `attune_spec3a`; the Deno suites listed in Task 2 are no worse than their baseline.

### Shared commands (used by every task)

```bash
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
SCRATCH=$(mktemp -d)   # any scratch dir outside the repo

# STORY CONTRACTS: every story contract, one line each.
story_contracts() {
  for t in supabase/tests/story_*_contracts.sql supabase/tests/together_story_contracts.sql; do
    if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$t" >/dev/null 2>"$SCRATCH/c.err"
    then echo "PASS $(basename "$t")"
    else echo "FAIL $(basename "$t"): $(grep -m1 -o 'ERROR:.*' "$SCRATCH/c.err")"; fi
  done
}
# RELATED CONTRACTS: the non-story files that touch stories.
related_contracts() {
  for t in data_export sync_fixes account_deletion relationship_purge chapter_canary; do
    f=supabase/tests/${t}_contracts.sql
    if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>"$SCRATCH/c.err"
    then echo "PASS $t"; else echo "FAIL $t: $(grep -m1 -o 'ERROR:.*' "$SCRATCH/c.err")"; fi
  done
}
# MUTATE: apply a mutated copy of a migration and run a contract in ONE
# transaction that always rolls back. A detected mutation exits non-zero with
# CONTRACT VIOLATED; exit 0 means the contract missed it.
mutate() {  # mutate <migration.sql> <sed expression> <contract.sql>
  sed -e '/^BEGIN;$/d' -e '/^COMMIT;$/d' -e "$2" "$1" > "$SCRATCH/mut_mig.sql"
  sed -e '/^BEGIN;$/d' -e '/^ROLLBACK;$/d' "$3" > "$SCRATCH/mut_test.sql"
  printf 'ROLLBACK;\n' > "$SCRATCH/rb.sql"
  psql -X -q -v ON_ERROR_STOP=1 -1 -d attune_spec3a \
    -f "$SCRATCH/mut_mig.sql" -f "$SCRATCH/mut_test.sql" -f "$SCRATCH/rb.sql"
}
```

Baseline on 2026-10-24 (before this plan): 7 of 10 story contracts pass; `story_places` fails ("clients can write story_places directly"), `story_read` and `story_security` fail (`users_phone_key`); all five related contracts pass.

Plan check (2026-10-24, rolled-back transactions on `attune_spec3a`, nothing left behind): every new contract fails first with the error its task states; with all twelve migrations applied, all 8 new contracts and all 15 existing ones (with the edits Tasks 1, 5, 7 and 11 make) pass; the mutations in Tasks 5, 7, 9, 11 and 13 are caught. The Dart and Deno code has not been compiled: read each touched file before editing.

## Rulings made in this plan (owner may override)

1. **Capture date (04 #3).** `occurred_on` comes from the capture instant the client sends (`p_captured_at`), clamped to `[now() − 7 days, now()]`. The 24-hour reel window still starts at posting (`expires_at = created_at + 24h`, which a CHECK constraint pins), so a story posted after a long offline wait still gets its full day in the ring. The review's own fix design says this; the brief's "24 h window from capture time" is read as the clamp. Cost if wrong: a one-line change to `created_at`/`expires_at` plus the CHECK.
2. **Intent lifetimes (Wave 2 I2).** Video media intents **and every thumbnail intent** last 60 minutes; image media stays 15. The thumbnail intent cannot say it belongs to a video (`story_rpc_contracts` pins `thumbnail` + `video` as `INVALID_INPUT`), and the client judges a pair by its sooner expiry, so image pairs behave exactly as today. The client's `media_link_too_slow` heuristic now uses the pair's own lifetime, not a fixed 13 minutes. Cost: an abandoned thumbnail slot holds an object up to 60 minutes instead of 15 (cost only; the bucket ceiling bounds it).
3. **Intent serialization (01 #18).** A per-person `pg_advisory_xact_lock` taken after input validation and before the membership check. It is keyed on the caller only, so it reveals nothing about any relationship.
4. **Membership helper (05 #4).** New `story_relationship_is_open_for_me(uuid)` (uses `auth.uid()`); the four policies move to it; the two-argument helper loses client `EXECUTE`. Definer functions keep calling the two-argument one.
5. **Archival.**
   - The original's deletion delay stays at the signed-URL TTL (600 s). The review's 7-day delay would keep a *deleted* story's original for a week; validating the rendition before the swap removes the reason for it.
   - The worker re-uploads with `upsert: true`, so a stale object left by an earlier, unvalidated attempt is overwritten by a validated one instead of being swapped in.
   - An image whose long edge is already ≤ 1600 px is marked considered (`downscaled_at`) and left alone.
   - Cadence: every 5 minutes, only while work waits; per run up to 60 s of claiming, batches of 20, 4 at a time, 20 s per Storage call.
6. **Export (04 #1, 07b G8).**
   - Story media is ranked first in the media walk; the cursor stays `(bucket, name)` because the rank is a function of the bucket.
   - Chat pages still come before media (no phase reorder). A chat over roughly 200,000 messages could still crowd stories out of the 12-part cap; accepted.
   - A job already walking media in the old order is replaced by a fresh queued job (the old one fails with `restarted`, its parts are dropped). Jobs live at most 6 hours, so this touches only what is in flight at deploy.
   - The left-out count lives in `media_not_included.txt` in the last part, where it is known; `README.txt` (part 1, written before anything is left out) says stories come first and where that count is. Moving README to the last part would always make two ZIPs.
7. **Place pins (04 #19).** Pins are kept until the space is **archived** (the 30-day window closes), not deleted at the ending. While ended they are unreadable to both partners (RLS still requires an open relationship) and reach only the author's own export. Judged safe: no reader path changes. This reverses sync audit C-2's "pins go at an ending"; the two contracts that pin it are updated.
8. **After an ending (05 #3).** The list covers every space that is closed for stories (paused, ended or archived), shows date and kind only (no thumbnails: Storage stays closed at an ending), and deletes in batches of 200 per call. The entry point is on Download my data.
9. **Day counts (04 #4).** `list_story_day_counts` returns a per-author `unviewed_count`; the day sheet uses it when present (so it no longer waits for page one of the day's items), and a view in the day reel re-reads that month's counts. An old server still gets today's behaviour.
10. **Deferred, said so:** batch signing of a month's thumbnails (04 #6); story ops alerts and the bytes/day metric (04 #10, STORIES.md corrected instead); the view grace window just after expiry (04 #16); CI dependency and secret scanners (checklist 7.1/7.3, project-wide).

## Review Focus

1. **Mixed versions during the rollout.** A new client on an old server, or an old client on a new one, must keep posting and reading: no `PGRST202`/`PGRST203`, no lost story. Tests: Task 5 (`p_captured_at` fallback), Task 7 (`p_author_id` fallback, old 5-argument call shape), Task 6 (rows without `server_now`).
2. **A migration landing while an export is mid-media.** An in-flight job must not skip every story or repeat other media. Test: Task 11, contract E4.
3. **A phone clock far off.** A capture time years back or in the future, and a phone clock behind the server, must not misfile a story or keep an expired one on the ring. Tests: Task 5 (clamps), Task 6 (server-clock offset).
4. **The transform service returning the wrong thing** (WebP, empty, truncated, upscaled or rotated) must never be swapped in. Tests: Task 10 validation cases.
5. **Deleting a big chapter, or naming someone else's.** More than 200 stories, a stranger's relationship id, an open relationship. Tests: Task 13, contracts A4–A7.

## File map

| File | Task | Responsibility |
|---|---|---|
| `supabase/migrations/20261024100000_story_places_grants.sql` | 1 | story_places table privileges, replayable |
| `supabase/migrations/20261024100100_story_media_bucket_limits.sql` | 3 | bucket size + MIME ceiling |
| `supabase/migrations/20261024100110_story_intent_hardening.sql` | 3 | serialized limits, intent lifetimes |
| `supabase/migrations/20261024100200_story_membership_for_me.sql` | 4 | membership helper lockdown |
| `supabase/migrations/20261024100300_story_capture_date.sql` | 5 | `p_captured_at`, time-zone-safe date |
| `supabase/migrations/20261024100400_story_ring_index.sql` | 6 | ring query index |
| `supabase/migrations/20261024100410_story_ring_summary_expiry.sql` | 6 | `next_expires_at`, `server_now` |
| `supabase/migrations/20261024100500_story_day_reads_by_author.sql` | 7 | `p_author_id`, per-author `unviewed_count` |
| `supabase/migrations/20261024100600_story_archival_v2.sql` | 9 | claim/fail/skip, cadence |
| `supabase/migrations/20261024100700_story_export_order.sql` | 11 | stories first, extensions, job restart |
| `supabase/migrations/20261024100710_story_places_keep_until_archive.sql` | 11 | pins kept to archive |
| `supabase/migrations/20261024100800_my_closed_story_items.sql` | 13 | list/delete my stories after an ending |
| `supabase/tests/story_*_contracts.sql` (8 new) | 3–13 | contracts |
| `scripts/local_pg_grants.sql` | 1 | replay the story_places grants |
| `supabase/functions/_shared/attune_auth.ts` (+ `.test.ts`) | 2 | constant-time service-role check |
| `supabase/functions/process-story-archival/archival.ts` (+ `.test.ts`), `index.ts` | 10 | worker |
| `supabase/functions/build-data-exports/bundle.ts`, `bundle.test.ts` | 12 | README + left-out note |
| `lib/features/stories/data/story_repository.dart` | 5 | send `p_captured_at` |
| `lib/features/stories/presentation/state/story_outbox_controller.dart` | 3, 5 | pair lifetime; pass capture time |
| `lib/features/stories/data/story_read_repository.dart` | 6, 7 | `serverNow`, `authorId`, `unviewedCount` |
| `lib/features/stories/presentation/state/story_ring_refresh.dart` | 6 | server clock offset |
| `lib/features/stories/presentation/providers/story_providers.dart` | 6, 7 | offset wiring, `StoryDayKey.authorId` |
| `lib/features/stories/presentation/screens/story_reel_screen.dart` | 8 | day key with author; counts re-read after a view |
| `lib/features/stories/domain/story_day_rings.dart`, `lib/features/timeline/presentation/widgets/calendar_day_sheet.dart` | 8 | server unviewed counts |
| `lib/features/stories/data/past_story_chapters_repository.dart` (new) | 14 | gateway + providers |
| `lib/features/stories/presentation/screens/past_chapter_stories_screen.dart` (new) | 14 | screen + entry tile |
| `lib/features/data_export/presentation/data_export_screen.dart` | 14 | entry tile |
| `lib/features/relationships/presentation/widgets/{pause,end}_relationship_action.dart`, `lib/app/documentations/user_manual/data/relationship_lifecycle_docs.dart` | 15 | copy |
| `lib/architecture/STORIES.md`, `docs/reviews/2026-10-24-stories-handoff.md` (new) | 16 | spec drift, handoff |

Files here that already carry uncommitted Wave 1–4 edits (edit surgically, keep every change): `story_reel_screen.dart`, `story_providers.dart`, `story_outbox_controller.dart`, `story_read_repository.dart`, `story_repository.dart`, `story_ring_refresh.dart`, `story_day_rings.dart`, `calendar_day_sheet.dart`, `lib/architecture/STORIES.md`, and the test kits under `test/features/stories/support/`. Check `git status --porcelain <file>` before each edit and re-read the file; never rely on line numbers from this plan.

---

### Task 1: Every story contract passes locally as shipped (05 #8, #9; 06 #26; 04 #18)

**Files:**
- Create: `supabase/migrations/20261024100000_story_places_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (one `\i` line plus a comment)
- Modify: `supabase/tests/story_read_contracts.sql` (fixture phones only)
- Modify: `supabase/tests/story_security_contracts.sql` (fixture phones only)

**Interfaces:**
- Consumes: nothing.
- Produces: a green `story_contracts` baseline every later task builds on.

- [ ] **Step 1: See the three failures**

Run: `story_contracts`
Expected: `FAIL story_places_contracts.sql: ERROR:  CONTRACT VIOLATED: clients can write story_places directly`, and `FAIL story_read_contracts.sql` / `FAIL story_security_contracts.sql` with `duplicate key value violates unique constraint "users_phone_key"`. The other seven pass.

- [ ] **Step 2: Give the two security contracts their own phones**

`+15559990001…3` already belong to `b2000000-…000a/b/c` on `attune_spec3a`, and `game_message_contracts.sql` uses `+15559990001` too. In `supabase/tests/story_read_contracts.sql` change only the three phone literals in the `INSERT INTO public.users` fixture:

```sql
  ('00000000-0000-0000-0000-00000000d501'::uuid, '+15550931001', 'RR1'),
  ('00000000-0000-0000-0000-00000000d502'::uuid, '+15550931002', 'RR2'),
  ('00000000-0000-0000-0000-00000000d503'::uuid, '+15550931003', 'RR3')
```

In `supabase/tests/story_security_contracts.sql`:

```sql
  ('00000000-0000-0000-0000-00000000b201'::uuid, '+15550932001', 'SI1'),
  ('00000000-0000-0000-0000-00000000b202'::uuid, '+15550932002', 'SI2'),
  ('00000000-0000-0000-0000-00000000b203'::uuid, '+15550932003', 'SI3')
```

Check no other line in either file mentions `+1555999`: `grep -n "+1555999" supabase/tests/story_read_contracts.sql supabase/tests/story_security_contracts.sql` → no output.

- [ ] **Step 3: Run the two contracts**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_read_contracts.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_security_contracts.sql`
Expected: both end in `ROLLBACK`, exit 0. If an assertion now fires, it is a real finding: stop and report it (the review's substituted copies passed).

- [ ] **Step 4: Write the story_places grants migration**

```sql
-- supabase/migrations/20261024100000_story_places_grants.sql
--
-- Stories Wave 5 (review 05 #8, 06 #26): story_places' table privileges in
-- their own file, so scripts/local_pg_grants.sql can replay them after its
-- blanket grant, as it already does for 20260938100000_stories_table_grants
-- and 20260939020000_story_reply_grants. The statements are the ones
-- 20261017100000_story_places.sql:19-20 made; production is unchanged.
-- Idempotent.
REVOKE ALL ON public.story_places FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.story_places TO authenticated;
```

- [ ] **Step 5: Replay it in the harness**

In `scripts/local_pg_grants.sql`, directly after the line `\i supabase/migrations/20261017140100_story_items_column_grants.sql`, add:

```sql

-- Stories Wave 5 (05 #8): story_places is SELECT-only for clients. Replayed
-- after the blanket grant above, which would otherwise hand authenticated
-- INSERT/UPDATE/DELETE and anon SELECT, and turn story_places_contracts red.
\i supabase/migrations/20261024100000_story_places_grants.sql
```

- [ ] **Step 6: Apply to attune_spec3a and see all ten pass**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100000_story_places_grants.sql`
Expected: `REVOKE`, `GRANT`.
Verify: `psql -X -d attune_spec3a -Atc "select has_table_privilege('authenticated','public.story_places','INSERT'), has_table_privilege('anon','public.story_places','SELECT'), has_table_privilege('authenticated','public.story_places','SELECT')"` → `f|f|t`.
Run: `story_contracts && related_contracts`
Expected: ten `PASS` lines and five `PASS` lines.

- [ ] **Step 7: Mutation check**

Run in one session: `psql -X -d attune_spec3a -c "BEGIN; GRANT INSERT ON public.story_places TO authenticated; SELECT has_table_privilege('authenticated','public.story_places','INSERT'); ROLLBACK;"` → `t` inside the transaction, proving the contract's check is live. (The contract itself detects it: copy `supabase/tests/story_places_contracts.sql` to `$SCRATCH`, insert `GRANT INSERT ON public.story_places TO authenticated;` after its `BEGIN;`, run the copy, expect `CONTRACT VIOLATED: clients can write story_places directly`.)

- [ ] **Step 8: Checkpoint**

`story_contracts` all PASS. No commit.

---

### Task 2: The service-role check compares in constant time (06 #22, 07b V10; checklist P0-U 2.3)

**Files:**
- Modify: `supabase/functions/_shared/attune_auth.ts` (`requireServiceRole`; new `constantTimeEqual`)
- Create: `supabase/functions/_shared/attune_auth.test.ts`

**Interfaces:**
- Produces: `export function constantTimeEqual(presented: string, expected: string): boolean` in `_shared/attune_auth.ts`. `requireServiceRole(req: Request): void` keeps its synchronous signature, so none of its 16 callers changes.

Shared by every service-role worker: `activate-topics`, `analyse-message`, `analyse-session`, `build-data-exports`, `evaluate-ask2-eligibility`, `forum-quiet-check`, `process-chat-media`, `process-chat-notification-outbox`, `process-chat-safety-outbox`, `process-dating-photo`, `process-media-deletion-queue`, `process-relationship-avatar`, `process-scheduled-notifications`, `process-story-archival`, `process-truth-answer-safety`, `send-notification`. Regression risk: a wrong compare locks every cron worker out (403). The tests below pin both directions.

- [ ] **Step 1: Record the Deno baseline**

Run from `supabase/functions`:

```bash
for d in $(find . -name "*.test.ts" -not -path "./_shared/*" | sed 's|/[^/]*$||' | sort -u); do
  deno test --allow-read --allow-env --allow-net --allow-sys "$d" > "$SCRATCH/deno_$(basename "$d").log" 2>&1
  echo "$d exit=$? $(grep -o '[0-9]* passed | [0-9]* failed' "$SCRATCH/deno_$(basename "$d").log" | tail -1)"
done
```

Expected (baseline 2026-10-24): `analyse-message 19 passed | 3 failed`, `analyse-session 7 passed | 2 failed`, `ai-assist 25 | 1`, `translate-conflict 4 | 5`, `ai-sessions` fails type-checking; every other directory passes (`build-data-exports 20`, `process-chat-notification-outbox 17`, `process-scheduled-notifications 16`, `send-notification 1`, …). Save the output to `$SCRATCH/deno_baseline.txt`. These pre-existing failures are not this task's to fix.

- [ ] **Step 2: Write the failing test**

```ts
// supabase/functions/_shared/attune_auth.test.ts
// Stories Wave 5 (06 #22, 07b V10; checklist P0-U 2.3): the service-role
// bearer is compared in time that does not depend on where it differs.
import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { constantTimeEqual, HttpError, requireServiceRole } from "./attune_auth.ts";

const KEY = "service-role-key-0123456789abcdef";

function req(authorization?: string): Request {
  return new Request("http://worker/", {
    headers: authorization === undefined ? {} : { Authorization: authorization },
  });
}

Deno.test("constantTimeEqual: only the identical string matches", () => {
  assert(constantTimeEqual(KEY, KEY));
  assert(!constantTimeEqual(KEY.slice(0, -1) + "X", KEY), "last byte differs");
  assert(!constantTimeEqual("X" + KEY.slice(1), KEY), "first byte differs");
  assert(!constantTimeEqual(KEY.slice(0, 5), KEY), "a prefix");
  assert(!constantTimeEqual(KEY + "extra", KEY), "longer");
  assert(!constantTimeEqual("", KEY), "empty");
  assert(!constantTimeEqual("é", "e"), "multi-byte");
});

Deno.test("requireServiceRole accepts exactly the service-role bearer", () => {
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", KEY);
  requireServiceRole(req(`Bearer ${KEY}`));
  requireServiceRole(req(`bearer   ${KEY}  `));
  for (const bad of [undefined, "", "Bearer", `Bearer ${KEY}x`, `Bearer ${KEY.slice(1)}`, `Bearer ${KEY.toUpperCase()}`]) {
    const e = assertThrows(() => requireServiceRole(req(bad)), HttpError);
    assertEquals(e.status, 403, String(bad));
  }
});

Deno.test("the check never compares the secret with === or !==", async () => {
  const src = await Deno.readTextFile(new URL("./attune_auth.ts", import.meta.url));
  const start = src.indexOf("export function requireServiceRole");
  const fn = src.slice(start, src.indexOf("\n}\n", start));
  assert(fn.includes("constantTimeEqual("), fn);
  assert(!/[!=]==/.test(fn), `plain comparison left in:\n${fn}`);
});
```

- [ ] **Step 3: Run it to see it fail**

Run (from `supabase/functions`): `deno test --allow-env --allow-read _shared/attune_auth.test.ts`
Expected: type-check error `Module '"./attune_auth.ts"' has no exported member 'constantTimeEqual'`.

- [ ] **Step 4: Implement**

In `_shared/attune_auth.ts`, add above `requireServiceRole`:

```ts
/**
 * Whether [presented] equals [expected], in time that depends only on
 * [expected]'s length, never on where the two differ (checklist 2.3; stories
 * review 06 #22, 07b V10). Lengths are compared too, so a prefix never
 * matches.
 */
export function constantTimeEqual(presented: string, expected: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(presented);
  const b = encoder.encode(expected);
  let diff = a.length ^ b.length;
  for (let i = 0; i < b.length; i++) {
    diff |= (i < a.length ? a[i] : 0) ^ b[i];
  }
  return diff === 0;
}
```

and change the body of `requireServiceRole` to:

```ts
export function requireServiceRole(req: Request): void {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token || !constantTimeEqual(token, requireEnv("SUPABASE_SERVICE_ROLE_KEY"))) {
    throw new HttpError("Forbidden", 403);
  }
}
```

- [ ] **Step 5: Run it to see it pass**

Run: `deno test --allow-env --allow-read _shared/attune_auth.test.ts`
Expected: `3 passed | 0 failed`.

- [ ] **Step 6: Re-run every worker's tests**

Re-run the Step 1 loop. Expected: every line identical to `$SCRATCH/deno_baseline.txt` (same pass/fail counts). `diff` the two outputs; any new failure is a regression from this task. Also type-check every service-role entry point that has no tests:

```bash
deno check activate-topics/index.ts evaluate-ask2-eligibility/index.ts forum-quiet-check/index.ts \
  process-chat-media/index.ts process-chat-safety-outbox/index.ts process-dating-photo/index.ts \
  process-media-deletion-queue/index.ts process-relationship-avatar/index.ts \
  process-truth-answer-safety/index.ts process-story-archival/index.ts
```

Expected: no errors.

- [ ] **Step 7: Checkpoint**

No commit. Note for the handoff (Task 16): every function in the list above must be redeployed to pick up the shared change.

---
### Task 3: Bucket ceiling, serialized intent limits, hour-long video intents (05 #5, 01 #17, 01 #18, Wave 2 I2; checklist P0-U 2.5)

**Files:**
- Create: `supabase/migrations/20261024100100_story_media_bucket_limits.sql`
- Create: `supabase/migrations/20261024100110_story_intent_hardening.sql`
- Create: `supabase/tests/story_hardening_contracts.sql`
- Modify: `lib/features/stories/presentation/state/story_outbox_controller.dart` (`_pairFresh`, the `slowAtFinalize` test, `remintMargin`/`intentLifetime` docs; new `_pairLifetime`)
- Modify: `test/features/stories/story_outbox_policy_test.dart` (two new tests in the slow-link group)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `create_story_upload_intent(uuid, text, text, text)` unchanged signature; `expires_at` is `now() + 15 min` for media/image, `now() + 60 min` for media/video and every thumbnail.
  - Bucket `story-media`: `file_size_limit = 26214400`, `allowed_mime_types = {image/jpeg, video/mp4}` (hosted only; the local harness has no such columns). Storage now answers 413/415 at upload; the Wave 2 classifier already maps them (`mediaRejected`).
  - Dart: `Duration _pairLifetime(StoryOutboxRecord record, DateTime mintedAt)` (private) in `StoryOutboxController`.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/story_hardening_contracts.sql
--
-- Stories Wave 5, Task 3: the story-media bucket refuses oversize and
-- foreign objects itself (05 #5, 01 #17); the two intent limits are
-- serialized per person (01 #18); video and thumbnail intents last an hour,
-- image media 15 minutes (Wave 2 final review I2).
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000930a1'), ('00000000-0000-0000-0000-0000000930b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000930a1', '+15550930001', 'HA'),
  ('00000000-0000-0000-0000-0000000930b2', '+15550930002', 'HB')
ON CONFLICT (id) DO NOTHING;
UPDATE public.feature_flags SET enabled = true WHERE key = 'stories';

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- H1. The bucket ceiling, against a storage.buckets shaped like the hosted
-- one (the local harness's has no limit columns; add them only if missing).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'file_size_limit') THEN
    ALTER TABLE storage.buckets ADD COLUMN file_size_limit bigint, ADD COLUMN allowed_mime_types text[];
  END IF;
END $$;
\ir ../migrations/20261024100100_story_media_bucket_limits.sql
DO $$
DECLARE v_public boolean; v_limit bigint; v_types text[];
BEGIN
  EXECUTE 'SELECT public, file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = ''story-media'''
    INTO v_public, v_limit, v_types;
  IF v_public IS DISTINCT FROM false THEN RAISE EXCEPTION 'CONTRACT VIOLATED: story-media is public'; END IF;
  IF v_limit IS DISTINCT FROM 26214400 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story-media size limit is % (want 25 MB)', v_limit;
  END IF;
  IF v_types IS DISTINCT FROM ARRAY['image/jpeg', 'video/mp4'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story-media accepts %', v_types;
  END IF;
END $$;

-- H2. Lifetimes: image media 15 minutes; video media and thumbnails an hour.
DO $$
DECLARE v_rel uuid; v_res jsonb; v_left interval;
BEGIN
  INSERT INTO public.relationships (user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-0000000930a1', '00000000-0000-0000-0000-0000000930b2', 'active')
  RETURNING id INTO v_rel;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000930a1');
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_left := (v_res->>'expires_at')::timestamptz - now();
  IF v_left NOT BETWEEN interval '14 minutes 55 seconds' AND interval '15 minutes 5 seconds' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an image intent lasts % (want 15 min)', v_left;
  END IF;
  v_res := public.create_story_upload_intent(v_rel, 'media', 'video', 'video/mp4');
  v_left := (v_res->>'expires_at')::timestamptz - now();
  IF v_left NOT BETWEEN interval '59 minutes 55 seconds' AND interval '60 minutes 5 seconds' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a video intent lasts % (want 60 min)', v_left;
  END IF;
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_left := (v_res->>'expires_at')::timestamptz - now();
  IF v_left NOT BETWEEN interval '59 minutes 55 seconds' AND interval '60 minutes 5 seconds' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a thumbnail intent lasts % (want 60 min)', v_left;
  END IF;
  -- Still refused as before: a thumbnail cannot claim to be a video.
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'video', 'image/jpeg');
  IF v_res->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: thumbnail/video accepted: %', v_res;
  END IF;
  RESET ROLE;
END $$;

-- H3. The limits are counted under a per-person lock, taken before any
-- count; the function pins search_path to ''.
DO $$
DECLARE v_def text; v_lock int; v_count int; v_cfg text[];
BEGIN
  v_def := pg_get_functiondef('public.create_story_upload_intent(uuid,text,text,text)'::regprocedure);
  v_lock := position('pg_advisory_xact_lock' IN v_def);
  v_count := position('FROM public.story_media_upload_intents' IN v_def);
  IF v_lock = 0 OR v_count = 0 OR v_lock > v_count THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the intent limits are not serialized before counting (lock at %, count at %)', v_lock, v_count;
  END IF;
  SELECT proconfig INTO v_cfg FROM pg_proc WHERE oid = 'public.create_story_upload_intent(uuid,text,text,text)'::regprocedure;
  IF NOT ('search_path=""' = ANY (coalesce(v_cfg, '{}'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: create_story_upload_intent search_path is %', v_cfg;
  END IF;
  IF has_function_privilege('anon', 'public.create_story_upload_intent(uuid,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.create_story_upload_intent(uuid,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: create_story_upload_intent grants changed';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to see it fail**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_hardening_contracts.sql`
Expected: `psql:…: …/20261024100100_story_media_bucket_limits.sql: No such file or directory` (the `\ir` target does not exist yet). After Step 3 creates it, a second run fails at H2: `CONTRACT VIOLATED: a video intent lasts 00:15:00 (want 60 min)`.

- [ ] **Step 3: Write the bucket migration**

No `BEGIN`/`COMMIT` in this file: the contract `\ir`s it inside its own transaction.

```sql
-- supabase/migrations/20261024100100_story_media_bucket_limits.sql
--
-- Stories Wave 5 (review 05 #5, 01 #17; checklist P0-U 2.5): a size and type
-- ceiling on the story-media bucket itself, so Storage refuses an oversize
-- or foreign object at upload instead of holding it until the hourly intent
-- sweep. 25 MB is the largest per-intent ceiling (media/video in
-- story_intent_max_bytes); create_story_item_core still enforces the 5 MB
-- and 800 KB tiers. The archival worker's renditions are image/jpeg.
-- Guarded like 20261014200000_journal_media_bucket.sql: the local harness's
-- storage.buckets has no limit columns. Idempotent; no transaction needed.
INSERT INTO storage.buckets (id, name, public) VALUES ('story-media', 'story-media', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'file_size_limit') THEN
    EXECUTE $q$UPDATE storage.buckets
               SET file_size_limit = 26214400,
                   allowed_mime_types = ARRAY['image/jpeg', 'video/mp4']
               WHERE id = 'story-media'$q$;
  END IF;
END $$;
```

- [ ] **Step 4: Write the intent migration**

```sql
-- supabase/migrations/20261024100110_story_intent_hardening.sql
--
-- Stories Wave 5:
--   * 01 #18: the two abuse limits count and then insert, so two calls at
--     once could both pass. A per-person transaction lock now serializes
--     them. It is taken after input validation and before the membership
--     check, keyed on the caller only, so it says nothing about any
--     relationship.
--   * Wave 2 final review I2: a video on a slow link could not finish inside
--     a 15-minute intent. Video media intents and every thumbnail intent now
--     last 60 minutes; image media keeps 15. A thumbnail intent cannot say it
--     belongs to a video (thumbnail + 'video' stays INVALID_INPUT), and the
--     client judges a pair by its sooner expiry, so image pairs are unchanged.
--   * search_path pinned to '' (house rule); every name schema-qualified.
-- Otherwise identical to 20260938040000. CREATE OR REPLACE keeps the grants;
-- they are re-stated.
CREATE OR REPLACE FUNCTION public.create_story_upload_intent(
  p_relationship_id uuid,
  p_object_kind text,
  p_media_type text,
  p_mime_type text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_storage_key text;
  v_max_bytes bigint;
  v_open_intents int;
  v_recent_calls int;
  v_intent_id uuid;
  v_expires_at timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  IF p_relationship_id IS NULL OR p_object_kind IS NULL OR p_media_type IS NULL
     OR p_mime_type IS NULL
     OR p_object_kind NOT IN ('media', 'thumbnail')
     OR p_media_type NOT IN ('image', 'video')
  THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  IF p_object_kind = 'thumbnail' THEN
    IF p_media_type <> 'image' OR p_mime_type <> 'image/jpeg' THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  ELSE
    IF p_media_type = 'image' AND p_mime_type <> 'image/jpeg' THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
    IF p_media_type = 'video' AND p_mime_type <> 'video/mp4' THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  END IF;

  v_max_bytes := public.story_intent_max_bytes(p_object_kind, p_media_type);
  IF v_max_bytes IS NULL THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  -- 01 #18: one call per person at a time from here to commit.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('story_intent:' || v_user::text));

  IF NOT public.story_relationship_is_open(p_relationship_id, v_user) THEN
    RETURN public.story_intent_error('FORBIDDEN');
  END IF;

  IF COALESCE(
    (SELECT f.enabled FROM public.feature_flags f WHERE f.key = 'stories'),
    false
  ) = false THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  SELECT count(*) INTO v_open_intents
    FROM public.story_media_upload_intents i
   WHERE i.requester_id = v_user
     AND i.used_at IS NULL
     AND i.expires_at > now();
  IF v_open_intents >= 20 THEN
    RETURN public.story_intent_error('RATE_LIMITED');
  END IF;

  SELECT count(*) INTO v_recent_calls
    FROM public.story_media_upload_intents i
   WHERE i.requester_id = v_user
     AND i.created_at > now() - interval '1 hour';
  IF v_recent_calls >= 120 THEN
    RETURN public.story_intent_error('RATE_LIMITED');
  END IF;

  v_storage_key := 'story-media/' || p_relationship_id::text || '/'
    || v_user::text || '/' || encode(extensions.gen_random_bytes(16), 'hex')
    || '-' || p_object_kind;
  v_expires_at := now() + CASE
    WHEN p_object_kind = 'media' AND p_media_type = 'image' THEN interval '15 minutes'
    ELSE interval '60 minutes'
  END;

  INSERT INTO public.story_media_upload_intents (
    relationship_id, requester_id, object_kind, media_type, mime_type,
    storage_key, max_bytes, expires_at
  ) VALUES (
    p_relationship_id, v_user, p_object_kind, p_media_type, p_mime_type,
    v_storage_key, v_max_bytes, v_expires_at
  ) RETURNING id INTO v_intent_id;

  RETURN jsonb_build_object(
    'intent_id', v_intent_id,
    'storage_key', v_storage_key,
    'bucket', 'story-media',
    'expires_at', v_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_story_upload_intent(uuid, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story_upload_intent(uuid, text, text, text)
  TO authenticated;
```

- [ ] **Step 5: Apply and run**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100100_story_media_bucket_limits.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100110_story_intent_hardening.sql`
Then: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_hardening_contracts.sql` → ends in `ROLLBACK`, exit 0.
Then: `story_contracts` → all PASS (`story_rpc_contracts`' 15-minute assertion is for media/image and still holds).

- [ ] **Step 6: Prove the lock serializes (two connections, nothing committed)**

```bash
U=00000000-0000-0000-0000-0000000930ff
AS="SET ROLE authenticated; SELECT set_config('request.jwt.claims', '{\"sub\":\"$U\",\"role\":\"authenticated\"}', false);"
psql -X -q -d attune_spec3a -c "BEGIN; $AS SELECT public.create_story_upload_intent(gen_random_uuid(), 'media', 'image', 'image/jpeg'); SELECT pg_sleep(3); ROLLBACK;" &
sleep 1
psql -X -d attune_spec3a -c "$AS SET lock_timeout = '500ms'; SELECT public.create_story_upload_intent(gen_random_uuid(), 'media', 'image', 'image/jpeg');"
wait
```

Expected: the second call prints `ERROR:  canceling statement due to lock timeout` (it waited on the first call's per-person lock). Both calls answer `FORBIDDEN` otherwise, and nothing is written: the relationship ids are random.

- [ ] **Step 7: Write the failing Dart tests**

In `test/features/stories/story_outbox_policy_test.dart`, inside the group that holds `'Retry after media_link_too_slow starts a fresh run (on Wi-Fi it posts)'` (it owns `dir`), add after that test:

```dart
    test('Wave 5: a 20-minute upload under an hour-long pair posts on the '
        'first pass', () async {
      final t = _SlowClock();
      final g = _ExpiringGateway(t, mediaUploadTakes: const Duration(minutes: 20))
        ..intentLifetime = const Duration(minutes: 60);
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      await withClock(t.clock, () => h.controller().enqueue(outboxRecord(dir)));
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(g.finalizes, hasLength(1));
      expect(g.intentCalls, ['media', 'thumbnail']);
    });

    test('Wave 5: finalize UNAVAILABLE 14 minutes into an hour-long pair is '
        'not read as a slow link', () async {
      final t = _SlowClock();
      final g = _ExpiringGateway(t, mediaUploadTakes: const Duration(minutes: 14))
        ..intentLifetime = const Duration(minutes: 60);
      g.finalizeScript.add(
        const StoryApiError(
          code: 'UNAVAILABLE',
          message: 'Unavailable.',
          retryable: false,
        ),
      );
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      await withClock(t.clock, () => h.controller().enqueue(outboxRecord(dir)));
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.slowUploads, 0);
      expect(row.lastErrorCode, isNot(StoryErrorCodes.mediaLinkTooSlow));
    });
```

- [ ] **Step 8: Run them to see the second fail**

Run: `flutter test test/features/stories/story_outbox_policy_test.dart --plain-name "Wave 5"`
Expected: the first passes (`_pairFresh` already reads the lifetime at the mint; it is a regression guard); the second fails with `Expected: <0> Actual: <1>` on `slowUploads`, because `slowAtFinalize` compares against the fixed `intentLifetime - remintMargin` (13 minutes).

- [ ] **Step 9: Implement**

In `story_outbox_controller.dart`:

1. Add next to `_pairFresh`:

```dart
  /// The pair's lifetime as seen at the mint: its sooner expiry minus
  /// [mintedAt], never shorter than [intentLifetime] (Review Focus 1: a
  /// skewed device clock cannot shorten it). Since Wave 5 the server gives
  /// video media and thumbnails an hour and image media 15 minutes, so a
  /// video pair lasts an hour and an image pair 15 minutes.
  Duration _pairLifetime(StoryOutboxRecord record, DateTime mintedAt) {
    final media = record.mediaIntent;
    final thumb = record.thumbnailIntent;
    if (media == null || thumb == null) return intentLifetime;
    final expires =
        media.expiresAt.isBefore(thumb.expiresAt)
            ? media.expiresAt
            : thumb.expiresAt;
    final lifetime = expires.difference(mintedAt);
    return lifetime < intentLifetime ? intentLifetime : lifetime;
  }
```

2. In `_pairFresh`, replace the four lines from `final expires =` to `if (lifetime < intentLifetime) lifetime = intentLifetime;` with `final lifetime = _pairLifetime(record, mintedAt);` (keep the early returns above and the final `return lifetime - clock.now().difference(mintedAt) >= remintMargin;`).

3. In the `catch` block's `slowAtFinalize`, replace `clock.now().difference(mintedAt) >= intentLifetime - remintMargin` with `clock.now().difference(mintedAt) >= _pairLifetime(current, mintedAt) - remintMargin`.

4. Doc comments: on `remintMargin` change `(spec §4.2: 15-minute intents)` to `(spec §4.2: 15-minute image intents; video and thumbnail intents last an hour since Wave 5)`; on `intentLifetime` change the doc to `/// The shortest intent lifetime the server issues (image media, spec §4.2; stories_intent_rpc.sql, story_intent_hardening.sql). A pair's own lifetime is read at the mint ([_pairLifetime]).`

- [ ] **Step 10: Run the outbox suites**

Run: `flutter test test/features/stories/story_outbox_policy_test.dart test/features/stories/story_outbox_controller_test.dart test/features/stories/story_orphaned_posts_test.dart`
Expected: all pass, including both Wave 5 tests and the existing `media_link_too_slow` cases (15-minute pairs: `_pairLifetime` returns 15 minutes there).

- [ ] **Step 11: Checkpoint**

`flutter analyze lib/features/stories/presentation/state/story_outbox_controller.dart` → no errors or warnings. No commit.

---

### Task 4: The membership helper is no longer an oracle (05 #4)

**Files:**
- Create: `supabase/migrations/20261024100200_story_membership_for_me.sql`
- Create: `supabase/tests/story_membership_contracts.sql`

**Interfaces:**
- Produces: `public.story_relationship_is_open_for_me(p_relationship_id uuid) RETURNS boolean` (SECURITY DEFINER, `EXECUTE` to `authenticated` only). `public.story_relationship_is_open(uuid, uuid)` keeps its body, gains `search_path = ''`, and loses `EXECUTE` for `PUBLIC`, `anon`, `authenticated`; every definer function that calls it runs as the owner and is unaffected (live callers on `attune_spec3a`: `list_active_story_items`, `list_story_day_items`, `create_story_upload_intent`, `get_story_ring_summary`, `create_story_item_core`, `mark_story_viewed`, `delete_story_item`, all `prosecdef = t`).
- Policies moved: `story_items_read_members`, `story_signals_read_members` (realtime evaluates it as the subscriber), `story_places_read_members`, `storage.objects` `story_media_select_authorized`.

Regression risk: these four policies gate every story read, signal and signed URL. The existing `story_read`, `story_security`, `story_seen_state`, `story_storage_policy_isolation` and `story_places` contracts exercise them; all must stay green.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/story_membership_contracts.sql
--
-- Stories Wave 5, Task 4 (review 05 #4): nobody can ask the server whether
-- some other pair of people is an open couple. Policies use a helper that
-- only ever answers for the caller; the two-argument helper is server-only.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000937a1'), ('00000000-0000-0000-0000-0000000937b2'),
  ('00000000-0000-0000-0000-0000000937c3'), ('00000000-0000-0000-0000-0000000937d4')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000937a1', '+15550937001', 'MA'),
  ('00000000-0000-0000-0000-0000000937b2', '+15550937002', 'MB'),
  ('00000000-0000-0000-0000-0000000937c3', '+15550937003', 'MC'),
  ('00000000-0000-0000-0000-0000000937d4', '+15550937004', 'MD')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
  ('00000000-0000-0000-0000-0000000937e1', '00000000-0000-0000-0000-0000000937a1', '00000000-0000-0000-0000-0000000937b2', 'active'),
  ('00000000-0000-0000-0000-0000000937e2', '00000000-0000-0000-0000-0000000937c3', '00000000-0000-0000-0000-0000000937d4', 'active');
INSERT INTO public.story_items (client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
VALUES (gen_random_uuid(), '00000000-0000-0000-0000-0000000937e1', '00000000-0000-0000-0000-0000000937b2',
  'image', 'story-media/m937/b-media', 'story-media/m937/b-thumbnail', 100, 100, CURRENT_DATE, now(), now() + interval '24 hours');

-- M1. Privileges.
DO $$
BEGIN
  IF has_function_privilege('authenticated', 'public.story_relationship_is_open(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.story_relationship_is_open(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can ask about any user (05 #4)';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.story_relationship_is_open_for_me(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.story_relationship_is_open_for_me(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story_relationship_is_open_for_me grants are wrong';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE oid IN ('public.story_relationship_is_open(uuid,uuid)'::regprocedure,
                                                  'public.story_relationship_is_open_for_me(uuid)'::regprocedure)
             AND NOT ('search_path=""' = ANY (coalesce(proconfig, '{}')))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a membership helper does not pin search_path';
  END IF;
END $$;

-- M2. No policy calls the two-argument helper; the four story policies use the new one.
DO $$
DECLARE v record; v_n int;
BEGIN
  FOR v IN SELECT schemaname, tablename, policyname FROM pg_policies
           WHERE coalesce(qual, '') ~ 'story_relationship_is_open\('
              OR coalesce(with_check, '') ~ 'story_relationship_is_open\(' LOOP
    RAISE EXCEPTION 'CONTRACT VIOLATED: %.%.% still calls the two-argument helper', v.schemaname, v.tablename, v.policyname;
  END LOOP;
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE policyname IN ('story_items_read_members', 'story_signals_read_members',
                        'story_places_read_members', 'story_media_select_authorized')
     AND qual LIKE '%story_relationship_is_open_for_me(%';
  IF v_n <> 4 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % of 4 story policies use the caller-only helper', v_n; END IF;
END $$;

-- M3. The helper answers only for the caller; the old one refuses clients.
DO $$
DECLARE v_ok boolean; v_n int;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000937c3');
  IF public.story_relationship_is_open_for_me('00000000-0000-0000-0000-0000000937e1') THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider is told another couple is open';
  END IF;
  BEGIN
    v_ok := public.story_relationship_is_open('00000000-0000-0000-0000-0000000937e1', '00000000-0000-0000-0000-0000000937a1');
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: the two-argument oracle answered a client';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  SELECT count(*) INTO v_n FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000937e1';
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider reads % stories', v_n; END IF;
  RESET ROLE;

  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000937a1');
  IF NOT public.story_relationship_is_open_for_me('00000000-0000-0000-0000-0000000937e1') THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a member is told their own couple is closed';
  END IF;
  SELECT count(*) INTO v_n FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000937e1';
  IF v_n <> 1 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a member reads % of 1 stories', v_n; END IF;
  RESET ROLE;

  UPDATE public.relationships SET status = 'paused' WHERE id = '00000000-0000-0000-0000-0000000937e1';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000937a1');
  SELECT count(*) INTO v_n FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000937e1';
  IF v_n <> 0 OR public.story_relationship_is_open_for_me('00000000-0000-0000-0000-0000000937e1') THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a paused couple''s stories are readable';
  END IF;
  RESET ROLE;
END $$;

ROLLBACK;
```

If the direct `UPDATE … SET status = 'paused'` is refused by a lifecycle trigger, use `PERFORM pg_temp.as_user(<A>); PERFORM public.pause_relationship('<rel>'); RESET ROLE;` instead, as `sync_fixes_contracts.sql` does.

- [ ] **Step 2: Run it to see it fail**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_membership_contracts.sql`
Expected: `CONTRACT VIOLATED: clients can ask about any user (05 #4)`.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261024100200_story_membership_for_me.sql
--
-- Stories Wave 5 (review 05 #4): story_relationship_is_open(rel, user) was
-- granted to authenticated for its RLS callers, so anyone holding two uuids
-- could ask whether that pairing is open. The policies now call a helper
-- that answers only for auth.uid(); the two-argument helper becomes
-- server-only (every function calling it is SECURITY DEFINER and runs as the
-- owner). One transaction, so no policy is ever missing.
BEGIN;

CREATE OR REPLACE FUNCTION public.story_relationship_is_open(
  p_relationship_id uuid,
  p_user uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
     WHERE r.id = p_relationship_id
       AND r.status = 'active'
       AND r.chat_archived_at IS NULL
       AND (r.user_a = p_user OR r.user_b = p_user)
  );
$$;

CREATE OR REPLACE FUNCTION public.story_relationship_is_open_for_me(
  p_relationship_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.story_relationship_is_open(p_relationship_id, auth.uid());
$$;

REVOKE ALL ON FUNCTION public.story_relationship_is_open_for_me(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.story_relationship_is_open_for_me(uuid) TO authenticated;

DROP POLICY IF EXISTS story_items_read_members ON public.story_items;
CREATE POLICY story_items_read_members ON public.story_items
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    AND public.story_relationship_is_open_for_me(relationship_id)
  );

DROP POLICY IF EXISTS story_signals_read_members ON public.story_change_signals;
CREATE POLICY story_signals_read_members ON public.story_change_signals
  FOR SELECT TO authenticated
  USING (public.story_relationship_is_open_for_me(relationship_id));

DROP POLICY IF EXISTS story_places_read_members ON public.story_places;
CREATE POLICY story_places_read_members ON public.story_places
  FOR SELECT TO authenticated
  USING (public.story_relationship_is_open_for_me(relationship_id));

-- Same predicate as 20260940120000, helper swapped.
DROP POLICY IF EXISTS story_media_select_authorized ON storage.objects;
CREATE POLICY story_media_select_authorized
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'story-media'
  AND (
    EXISTS (
      SELECT 1
        FROM public.story_items si
       WHERE (si.media_key = name OR si.thumbnail_key = name)
         AND si.deleted_at IS NULL
         AND public.story_relationship_is_open_for_me(si.relationship_id)
    )
    OR public.story_media_intent_is_active(name)
  )
);

REVOKE EXECUTE ON FUNCTION public.story_relationship_is_open(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

COMMIT;
```

- [ ] **Step 4: Apply and run everything that reads stories**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100200_story_membership_for_me.sql`
Then: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_membership_contracts.sql` → `ROLLBACK`, exit 0.
Then: `story_contracts && related_contracts` → all PASS (`chapter_canary`'s `NOT LIKE '%story_relationship_is_open%'` still matches the `_for_me` name; `story_rpc_contracts`' one direct call runs after `RESET ROLE`).

- [ ] **Step 5: Mutation check**

Copy the contract to `$SCRATCH/m.sql`, insert `GRANT EXECUTE ON FUNCTION public.story_relationship_is_open(uuid, uuid) TO authenticated;` right after its `BEGIN;`, run the copy → `CONTRACT VIOLATED: clients can ask about any user (05 #4)`.

- [ ] **Step 6: Checkpoint**

No commit. The client never calls either helper (`grep -rn story_relationship_is_open lib` → nothing).

---

### Task 5: A story is filed on the day it was taken, in any session time zone (04 #3, #13)

**Files:**
- Create: `supabase/migrations/20261024100300_story_capture_date.sql`
- Create: `supabase/tests/story_capture_date_contracts.sql`
- Modify: `supabase/tests/story_rpc_contracts.sql` and `supabase/tests/story_places_contracts.sql` (signature literals only; they pin the old signature)
- Modify: `lib/features/stories/data/story_repository.dart` (`StoryGateway.finalizeStory`, `StoryRepository.finalizeStory`)
- Modify: `lib/features/stories/presentation/state/story_outbox_controller.dart` (the `finalizeStory` call and the "posting time" comments)
- Modify (signature only, `DateTime? capturedAt,` added to each `finalizeStory` override): `test/features/stories/story_camera_test.dart`, `story_calendar_test.dart`, `story_outbox_controller_test.dart`, `story_outbox_policy_test.dart` (two overrides, forwarding to `super`), `story_rings_test.dart`, `support/outbox_fakes.dart`, `support/ring_test_kit.dart`
- Modify: `test/features/stories/story_repository_test.dart` (new group), `test/features/stories/support/outbox_fakes.dart` (records `capturedAts`), `test/features/stories/story_outbox_controller_test.dart` (one test)

**Interfaces:**
- Produces:
  - SQL: `public.create_story_item(p_relationship_id uuid, p_client_story_id uuid, p_media_intent_id uuid, p_thumbnail_intent_id uuid, p_media_width int, p_media_height int, p_duration_ms int, p_utc_offset_minutes int, p_place jsonb DEFAULT NULL, p_captured_at timestamptz DEFAULT NULL)`; the 9-argument version is dropped. Core: `public.create_story_item_core(uuid, uuid, uuid, uuid, int, int, int, int, timestamptz)` (no client grant); the 8-argument core is dropped.
  - `occurred_on = ((clamp(p_captured_at) AT TIME ZONE 'UTC') + offset)::date`, `clamp(x) = least(now(), greatest(now() − 7 days, coalesce(x, now())))`; `created_at = now()`, `expires_at = now() + 24h` unchanged.
  - Dart: `StoryGateway.finalizeStory({…, Map<String, dynamic>? place, DateTime? capturedAt})`. The repository sends `p_captured_at` (UTC ISO-8601) when non-null and, on `PGRST202`, retries once without it and stops sending it for the session.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/story_capture_date_contracts.sql
--
-- Stories Wave 5, Task 5 (review 04 #3, #13): occurred_on is the poster's
-- civil date at CAPTURE time (clamped to the last 7 days, never the future),
-- computed without the session time zone. The reel window still runs 24h
-- from posting.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000935a1'), ('00000000-0000-0000-0000-0000000935b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000935a1', '+15550935001', 'CA'),
  ('00000000-0000-0000-0000-0000000935b2', '+15550935002', 'CB')
ON CONFLICT (id) DO NOTHING;
UPDATE public.feature_flags SET enabled = true WHERE key = 'stories';
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
  ('00000000-0000-0000-0000-0000000935e1', '00000000-0000-0000-0000-0000000935a1', '00000000-0000-0000-0000-0000000935b2', 'active');

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- Posts one image story for A through the real RPCs; returns the row.
CREATE FUNCTION pg_temp.post(p_offset int, p_captured timestamptz, p_client uuid DEFAULT gen_random_uuid())
RETURNS public.story_items LANGUAGE plpgsql AS $$
DECLARE r jsonb; mid uuid; mkey text; tid uuid; tkey text; v public.story_items;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000935a1');
  r := public.create_story_upload_intent('00000000-0000-0000-0000-0000000935e1', 'media', 'image', 'image/jpeg');
  mid := (r->>'intent_id')::uuid; mkey := r->>'storage_key';
  r := public.create_story_upload_intent('00000000-0000-0000-0000-0000000935e1', 'thumbnail', 'image', 'image/jpeg');
  tid := (r->>'intent_id')::uuid; tkey := r->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', mkey, jsonb_build_object('size', 1000, 'mimetype', 'image/jpeg')),
    ('story-media', tkey, jsonb_build_object('size', 100, 'mimetype', 'image/jpeg'));
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000935a1');
  r := public.create_story_item('00000000-0000-0000-0000-0000000935e1', p_client, mid, tid,
                                1080, 1920, NULL, p_offset, NULL, p_captured);
  RESET ROLE;
  IF (r->>'error') IS NOT DISTINCT FROM 'true' THEN RAISE EXCEPTION 'setup: finalize refused: %', r; END IF;
  SELECT * INTO v FROM public.story_items WHERE id = (r->>'story_id')::uuid;
  RETURN v;
END $$;

-- Dates the test expects, computed in UTC on purpose.
CREATE FUNCTION pg_temp.utc_today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'UTC')::date $$;
-- 23:59 UTC yesterday: always between 1 minute and 24 hours ago.
CREATE FUNCTION pg_temp.late_yesterday() RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT ((now() AT TIME ZONE 'UTC')::date::timestamp - interval '1 minute') AT TIME ZONE 'UTC' $$;

-- C1. The capture's date, not the posting's; the window still runs from posting.
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, pg_temp.late_yesterday());
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() - 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: captured yesterday 23:59, filed on % (want %)', v.occurred_on, pg_temp.utc_today() - 1;
  END IF;
  IF v.created_at IS DISTINCT FROM now() OR v.expires_at IS DISTINCT FROM now() + interval '24 hours' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reel window moved: created % expires %', v.created_at, v.expires_at;
  END IF;
END $$;

-- C2. Clamps: a month back files 7 days back; the future files today; NULL is now.
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, now() - interval '30 days');
  IF v.occurred_on IS DISTINCT FROM ((now() - interval '7 days') AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 30-day-old capture filed on %', v.occurred_on;
  END IF;
  v := pg_temp.post(0, now() + interval '2 days');
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a future capture filed on %', v.occurred_on;
  END IF;
  v := pg_temp.post(0, NULL);
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an old client (no capture time) filed on %', v.occurred_on;
  END IF;
END $$;

-- C3. The offset still applies, to the capture instant: +60 at 23:59 UTC is tomorrow-of-that-day.
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(60, pg_temp.late_yesterday());
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: +60 min at 23:59 UTC filed on % (want %)', v.occurred_on, pg_temp.utc_today();
  END IF;
END $$;

-- C4. The session time zone changes nothing (04 #13).
SET LOCAL timezone = 'Asia/Tokyo';
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, pg_temp.late_yesterday());
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() - 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under Asia/Tokyo the same capture filed on %', v.occurred_on;
  END IF;
  v := pg_temp.post(0, NULL);
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under Asia/Tokyo "now" at offset 0 filed on %', v.occurred_on;
  END IF;
END $$;
SET LOCAL timezone = 'America/Los_Angeles';
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, pg_temp.late_yesterday());
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() - 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under America/Los_Angeles the same capture filed on %', v.occurred_on;
  END IF;
END $$;
RESET timezone;

-- C5. A replay with a different capture time returns the first story unchanged.
DO $$
DECLARE v1 public.story_items; v2 public.story_items; c uuid := gen_random_uuid();
BEGIN
  v1 := pg_temp.post(0, pg_temp.late_yesterday(), c);
  v2 := pg_temp.post(0, now(), c);
  IF v2.id IS DISTINCT FROM v1.id OR v2.occurred_on IS DISTINCT FROM v1.occurred_on THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay moved the story (% -> %)', v1.occurred_on, v2.occurred_on;
  END IF;
END $$;

-- C6. Signatures and grants: one finalize, no overload (PGRST203), core server-only.
DO $$
BEGIN
  IF to_regprocedure('public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb)') IS NOT NULL
     OR to_regprocedure('public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int)') IS NOT NULL
     OR to_regprocedure('public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an older finalize overload is still there';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb,timestamptz)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb,timestamptz)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finalize grants are wrong';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE oid IN (
               'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb,timestamptz)'::regprocedure,
               'public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int,timestamptz)'::regprocedure)
             AND NOT ('search_path=""' = ANY (coalesce(proconfig, '{}')))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finalize does not pin search_path';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to see it fail**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_capture_date_contracts.sql`
Expected: `ERROR:  function public.create_story_item(unknown, uuid, uuid, uuid, integer, integer, unknown, integer, unknown, timestamp with time zone) does not exist` (or similar), from C1's `pg_temp.post`.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261024100300_story_capture_date.sql
--
-- Stories Wave 5 (review 04 #3, #13):
--   * occurred_on was the poster's date at FINALIZE; an offline or slow post
--     near midnight landed on the next day. The client now sends the capture
--     instant (p_captured_at). It is clamped to the last 7 days and never the
--     future, so a client cannot back-date a story into the distant past.
--     created_at / expires_at stay at posting: the reel still gets 24 hours
--     (story_expires_in_24h pins expires_at = created_at + 24h).
--   * The date math no longer depends on the session TimeZone:
--     (timestamptz AT TIME ZONE 'UTC') + offset, then ::date.
--   * The wrapper and core move to search_path = ''.
-- The 9-argument wrapper and 8-argument core are DROPPED, not overloaded,
-- so PostgREST never sees two candidates (PGRST203); an old client's call
-- without p_captured_at still resolves to the new one (DEFAULT NULL).
-- Body otherwise identical to 20260938120000 (core) and 20261017100000
-- (wrapper). One transaction: there is never a moment without a finalize.
BEGIN;

DROP FUNCTION IF EXISTS public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb);
DROP FUNCTION IF EXISTS public.create_story_item_core(uuid, uuid, uuid, uuid, int, int, int, int);

CREATE OR REPLACE FUNCTION public.create_story_item_core(
  p_relationship_id     uuid,
  p_client_story_id     uuid,
  p_media_intent_id     uuid,
  p_thumbnail_intent_id uuid,
  p_media_width         int,
  p_media_height        int,
  p_duration_ms         int,
  p_utc_offset_minutes  int,
  p_captured_at         timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user          uuid := auth.uid();
  v_existing_id   uuid;
  v_media_intent  public.story_media_upload_intents%ROWTYPE;
  v_thumb_intent  public.story_media_upload_intents%ROWTYPE;
  v_media_object  storage.objects%ROWTYPE;
  v_thumb_object  storage.objects%ROWTYPE;
  v_media_size    bigint;
  v_media_mime    text;
  v_thumb_size    bigint;
  v_thumb_mime    text;
  v_offset        int;
  v_now           timestamptz;
  v_captured      timestamptz;
  v_occurred_on   date;
  v_story_id      uuid;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  IF p_relationship_id IS NULL
     OR p_client_story_id IS NULL
     OR p_media_intent_id IS NULL
     OR p_thumbnail_intent_id IS NULL
     OR p_media_width IS NULL OR p_media_width <= 0
     OR p_media_height IS NULL OR p_media_height <= 0
  THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  -- Idempotency first (sequential replay).
  SELECT si.id INTO v_existing_id
    FROM public.story_items si
   WHERE si.author_id = v_user
     AND si.client_story_id = p_client_story_id;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('story_id', v_existing_id, 'existing', true);
  END IF;

  IF NOT public.story_relationship_is_open(p_relationship_id, v_user) THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- Lock both intents before validating them; a consumed intent re-checks
  -- idempotency (the 20260938120000 race fix).
  SELECT * INTO v_media_intent
    FROM public.story_media_upload_intents i
   WHERE i.id = p_media_intent_id
   FOR UPDATE;
  IF v_media_intent.id IS NULL
     OR v_media_intent.requester_id IS DISTINCT FROM v_user
     OR v_media_intent.relationship_id IS DISTINCT FROM p_relationship_id
     OR v_media_intent.object_kind IS DISTINCT FROM 'media'
     OR v_media_intent.used_at IS NOT NULL
     OR v_media_intent.expires_at <= now()
  THEN
    IF v_media_intent.used_at IS NOT NULL THEN
      SELECT si.id INTO v_existing_id
        FROM public.story_items si
       WHERE si.author_id = v_user AND si.client_story_id = p_client_story_id;
      IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('story_id', v_existing_id, 'existing', true);
      END IF;
    END IF;
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  SELECT * INTO v_thumb_intent
    FROM public.story_media_upload_intents i
   WHERE i.id = p_thumbnail_intent_id
   FOR UPDATE;
  IF v_thumb_intent.id IS NULL
     OR v_thumb_intent.requester_id IS DISTINCT FROM v_user
     OR v_thumb_intent.relationship_id IS DISTINCT FROM p_relationship_id
     OR v_thumb_intent.object_kind IS DISTINCT FROM 'thumbnail'
     OR v_thumb_intent.used_at IS NOT NULL
     OR v_thumb_intent.expires_at <= now()
  THEN
    IF v_thumb_intent.used_at IS NOT NULL THEN
      SELECT si.id INTO v_existing_id
        FROM public.story_items si
       WHERE si.author_id = v_user AND si.client_story_id = p_client_story_id;
      IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('story_id', v_existing_id, 'existing', true);
      END IF;
    END IF;
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  IF v_media_intent.media_type = 'video' THEN
    IF p_duration_ms IS NULL OR p_duration_ms < 500 OR p_duration_ms > 60000 THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  ELSE
    IF p_duration_ms IS NOT NULL THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  END IF;

  SELECT * INTO v_media_object
    FROM storage.objects o
   WHERE o.bucket_id = 'story-media' AND o.name = v_media_intent.storage_key;
  IF v_media_object.id IS NULL THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;
  v_media_size := COALESCE((v_media_object.metadata->>'size')::bigint, 0);
  v_media_mime := COALESCE(v_media_object.metadata->>'mimetype',
                           v_media_object.metadata->>'contentType');
  IF v_media_size <= 0
     OR v_media_size > v_media_intent.max_bytes
     OR v_media_mime IS DISTINCT FROM v_media_intent.mime_type
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  SELECT * INTO v_thumb_object
    FROM storage.objects o
   WHERE o.bucket_id = 'story-media' AND o.name = v_thumb_intent.storage_key;
  IF v_thumb_object.id IS NULL THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;
  v_thumb_size := COALESCE((v_thumb_object.metadata->>'size')::bigint, 0);
  v_thumb_mime := COALESCE(v_thumb_object.metadata->>'mimetype',
                           v_thumb_object.metadata->>'contentType');
  IF v_thumb_size <= 0
     OR v_thumb_size > v_thumb_intent.max_bytes
     OR v_thumb_mime IS DISTINCT FROM v_thumb_intent.mime_type
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- One captured now() for created_at and expires_at (posting). The date is
  -- the capture's, clamped to [now - 7 days, now], at the device offset
  -- (clamped to [-840, 840]), with no session time zone involved.
  v_offset := greatest(-840, least(840, coalesce(p_utc_offset_minutes, 0)));
  v_now := now();
  v_captured := least(v_now, greatest(v_now - interval '7 days', coalesce(p_captured_at, v_now)));
  v_occurred_on := ((v_captured AT TIME ZONE 'UTC') + make_interval(mins => v_offset))::date;

  INSERT INTO public.story_items (
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height, duration_ms,
    occurred_on, created_at, expires_at
  ) VALUES (
    p_client_story_id, p_relationship_id, v_user, v_media_intent.media_type,
    v_media_intent.storage_key, v_thumb_intent.storage_key,
    p_media_width, p_media_height, p_duration_ms,
    v_occurred_on, v_now, v_now + interval '24 hours'
  )
  ON CONFLICT (author_id, client_story_id) DO NOTHING
  RETURNING id INTO v_story_id;

  IF v_story_id IS NULL THEN
    SELECT si.id INTO v_story_id
      FROM public.story_items si
     WHERE si.author_id = v_user AND si.client_story_id = p_client_story_id;
    RETURN jsonb_build_object('story_id', v_story_id, 'existing', true);
  END IF;

  UPDATE public.story_media_upload_intents SET used_at = v_now WHERE id = v_media_intent.id;
  UPDATE public.story_media_upload_intents SET used_at = v_now WHERE id = v_thumb_intent.id;

  PERFORM public.bump_story_signal(p_relationship_id);

  RETURN jsonb_build_object('story_id', v_story_id, 'existing', false);
END;
$$;

REVOKE ALL ON FUNCTION public.create_story_item_core(uuid, uuid, uuid, uuid, int, int, int, int, timestamptz)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_story_item(
  p_relationship_id     uuid,
  p_client_story_id     uuid,
  p_media_intent_id     uuid,
  p_thumbnail_intent_id uuid,
  p_media_width         int,
  p_media_height        int,
  p_duration_ms         int,
  p_utc_offset_minutes  int,
  p_place               jsonb DEFAULT NULL,
  p_captured_at         timestamptz DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_res jsonb; v_place record;
BEGIN
  v_res := public.create_story_item_core(
    p_relationship_id, p_client_story_id, p_media_intent_id, p_thumbnail_intent_id,
    p_media_width, p_media_height, p_duration_ms, p_utc_offset_minutes, p_captured_at);
  -- A place only on a FRESH insert: a replay never adds one (no backfill).
  IF p_place IS NULL
     OR (v_res->>'error') IS NOT DISTINCT FROM 'true'
     OR (v_res->>'existing')::boolean IS DISTINCT FROM false THEN
    RETURN v_res;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.feature_flags f WHERE f.key = 'couple_map_enabled' AND f.enabled) THEN
    RETURN v_res;
  END IF;
  SELECT * INTO v_place FROM public.story_place_parse(p_place);
  IF v_place.lat IS NULL THEN
    RETURN v_res;
  END IF;
  BEGIN
    INSERT INTO public.story_places (story_item_id, relationship_id, author_id, lat, lng, label)
    VALUES ((v_res->>'story_id')::uuid, p_relationship_id, auth.uid(),
            v_place.lat, v_place.lng, v_place.label);
  EXCEPTION WHEN others THEN
    NULL; -- never fatal to the story
  END;
  RETURN v_res;
END $$;

REVOKE ALL ON FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb, timestamptz)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb, timestamptz)
  TO authenticated;

COMMIT;
```

`public.story_place_parse` has no `SET search_path`; it is `IMMUTABLE` plpgsql that references no table, so the empty caller path is fine (Step 5 proves it through `story_places_contracts`).

- [ ] **Step 4: Update the two contracts that pin the old signatures**

These lines encode the 9-argument wrapper and 8-argument core; the behaviour they guard (anon refused, no ambiguous overload, core not client-callable) is unchanged.

In `supabase/tests/story_rpc_contracts.sql`, replace both occurrences of `'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb)'` with `'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb,timestamptz)'`.

In `supabase/tests/story_places_contracts.sql`:
- replace `'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb)'` with `'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb,timestamptz)'`;
- replace `IF to_regprocedure('public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int)') IS NOT NULL THEN` with `IF to_regprocedure('public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int)') IS NOT NULL OR to_regprocedure('public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb)') IS NOT NULL THEN` and its message with `'CONTRACT VIOLATED: an older finalize overload still exists (PGRST203 ambiguity)'`;
- replace `'public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int)'` with `'public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int,timestamptz)'`.

- [ ] **Step 5: Apply and run**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100300_story_capture_date.sql`
Then: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_capture_date_contracts.sql` → `ROLLBACK`, exit 0.
Then: `story_contracts && related_contracts` → all PASS. `story_rpc_contracts`' Contract 3 still computes its expectation with `(now() ± interval)::date` under the database's own zone (`Africa/Accra`, UTC+0), so it agrees with the UTC math.

- [ ] **Step 6: Mutation check**

Put the old, session-zone date math back in a rolled-back copy and watch C4 catch it:

```bash
mutate supabase/migrations/20261024100300_story_capture_date.sql \
  "s/((v_captured AT TIME ZONE 'UTC') + make_interval(mins => v_offset))::date/(v_captured + make_interval(mins => v_offset))::date/" \
  supabase/tests/story_capture_date_contracts.sql
```

Expected: non-zero exit with `CONTRACT VIOLATED: under Asia/Tokyo the same capture filed on …` (Tokyo is always on the next date at 23:59 UTC). Then drop the clamp the same way (`s/greatest(v_now - interval '7 days', coalesce(p_captured_at, v_now))/coalesce(p_captured_at, v_now)/`) → `CONTRACT VIOLATED: a 30-day-old capture filed on …`.

- [ ] **Step 7: Write the failing Dart tests**

a) Repository wire shape, in `test/features/stories/story_repository_test.dart` (it already imports `package:http/http.dart as http`, `package:http/testing.dart`, `dart:convert`, `supabase_flutter`). Add a group at the end of `main()`:

```dart
  group('finalize sends the capture time (Wave 5, 04 #3)', () {
    late List<Map<String, dynamic>> bodies;

    StoryRepository repoAnswering(List<http.Response> answers) {
      bodies = [];
      final queue = [...answers];
      final supabase = SupabaseClient(
        'https://x.supabase.co',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/rpc/create_story_item')) {
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return queue.removeAt(0);
          }
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }),
      );
      addTearDown(supabase.dispose);
      return StoryRepository(supabase);
    }

    http.Response ok() => http.Response(
      jsonEncode({'story_id': 's1', 'existing': false}),
      200,
      headers: {'content-type': 'application/json'},
    );

    Future<StoryFinalizeResult> finalize(StoryRepository repo) => repo.finalizeStory(
      relationshipId: 'r1',
      clientStoryId: 'c1',
      mediaIntentId: 'm1',
      thumbnailIntentId: 't1',
      mediaWidth: 1080,
      mediaHeight: 1920,
      utcOffsetMinutes: 60,
      capturedAt: DateTime.utc(2026, 10, 23, 22, 59),
    );

    test('p_captured_at is the capture instant in UTC', () async {
      final repo = repoAnswering([ok()]);
      final result = await finalize(repo);
      expect(result.storyId, 's1');
      expect(bodies.single['p_captured_at'], '2026-10-23T22:59:00.000Z');
      expect(bodies.single['p_utc_offset_minutes'], 60);
    });

    test('an older server (PGRST202) is asked again without it, once', () async {
      final repo = repoAnswering([
        http.Response(
          jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function public.create_story_item', 'details': null, 'hint': null}),
          404,
          headers: {'content-type': 'application/json'},
        ),
        ok(),
        ok(),
      ]);
      expect((await finalize(repo)).storyId, 's1');
      expect(bodies, hasLength(2));
      expect(bodies[1].containsKey('p_captured_at'), isFalse);
      await finalize(repo);
      expect(bodies, hasLength(3));
      expect(bodies[2].containsKey('p_captured_at'), isFalse, reason: 'remembered for the session');
    });
  });
```

b) The controller passes the record's capture time. In `test/features/stories/support/outbox_fakes.dart`, `ScriptedStoryGateway` gains `final capturedAts = <DateTime?>[];` and its `finalizeStory` override gains `DateTime? capturedAt,` and records `capturedAts.add(capturedAt);` next to `finalizes.add(…)`. In `test/features/stories/story_outbox_controller_test.dart` (or the policy test, whichever already uses `ScriptedStoryGateway` with `outboxHarness`), add:

```dart
  test('finalize carries the capture time (Wave 5, 04 #3)', () async {
    final g = ScriptedStoryGateway();
    final h = outboxHarness(gateway: g);
    addTearDown(h.container.dispose);
    final record = outboxRecord(dir);
    await h.controller().enqueue(record);
    expect(g.capturedAts.single, record.createdAt);
  });
```

(`dir` is that file's temp directory from `setUp`; reuse the group that already has one.)

- [ ] **Step 8: Run them to see them fail**

Run: `flutter test test/features/stories/story_repository_test.dart test/features/stories/story_outbox_controller_test.dart`
Expected: compile errors `No named parameter with the name 'capturedAt'`.

- [ ] **Step 9: Implement**

1. `story_repository.dart`, abstract `StoryGateway.finalizeStory`: add after `place`:

```dart
    /// When the media was captured (Wave 5, 04 #3): the server files the
    /// story on this instant's date (clamped to the last 7 days). Null on
    /// a record from before this field existed.
    DateTime? capturedAt,
```

2. `StoryRepository`: add a field `bool _finalizeWithoutCapture = false;` with the doc `/// Set when the server predates p_captured_at (PGRST202); the date then falls back to posting time.` Replace the body of `finalizeStory` with:

```dart
  }) => _guard(() async {
    Future<dynamic> call({required bool withCapture}) => _supabase.rpc(
      'create_story_item',
      params: {
        'p_relationship_id': relationshipId,
        'p_client_story_id': clientStoryId,
        'p_media_intent_id': mediaIntentId,
        'p_thumbnail_intent_id': thumbnailIntentId,
        'p_media_width': mediaWidth,
        'p_media_height': mediaHeight,
        'p_duration_ms': durationMs,
        'p_utc_offset_minutes': utcOffsetMinutes,
        // Only when pinned: a client shipped before the migration
        // deploys must still finalize.
        if (place != null) 'p_place': place,
        if (withCapture && capturedAt != null)
          'p_captured_at': capturedAt.toUtc().toIso8601String(),
      },
    );
    dynamic response;
    final withCapture = capturedAt != null && !_finalizeWithoutCapture;
    try {
      response = await call(withCapture: withCapture);
    } on PostgrestException catch (e) {
      // PGRST202: the function was never called, so asking again cannot
      // post twice.
      if (!withCapture || e.code != 'PGRST202') rethrow;
      _finalizeWithoutCapture = true;
      response = await call(withCapture: false);
    }
    final data = _unwrap(response);
    return StoryFinalizeResult(
      storyId: '${data['story_id']}',
      existing: data['existing'] == true,
    );
  });
```

and add `DateTime? capturedAt,` to its parameter list. Keep `_unwrap`/`_guard` as they are (read them first: if `_unwrap` takes `Object?`, pass `response` unchanged).

3. `story_outbox_controller.dart`: in the `finalizeStory(…)` call add `capturedAt: current.createdAt,`. Replace the comment above it (`// Finalization time is posting time (spec §6.1): utcOffsetMinutes travels from the record as captured, sent now, never recomputed.`) with:

```dart
        // The date is the capture's (Wave 5, spec §3.5/§6.1): createdAt and
        // utcOffsetMinutes travel from the record as captured. The server
        // clamps the instant to the last 7 days; the 24-hour reel window
        // still starts when this call lands.
```

In the class doc, replace the paragraph that starts `**Finalization time is posting time** (spec §6.1)` with:

```dart
/// **The capture's date, the posting's window** (spec §3.5, §6.1, Wave 5):
/// `createdAt` (capture) and `utcOffsetMinutes` are sent with finalize; the
/// server files the story on that day (clamped to the last 7 days) and
/// starts the 24-hour reel window when finalize lands.
```

4. Every other `finalizeStory` override listed in **Files** gains `DateTime? capturedAt,` after `Map<String, dynamic>? place,`; the two in `story_outbox_policy_test.dart` (`_ExpiringGateway`, `_CountingGateway`) also pass `capturedAt: capturedAt,` to `super.finalizeStory(…)`. Find them with `grep -rn "finalizeStory({" test`.

- [ ] **Step 10: Run the story suites**

Run: `flutter test test/features/stories test/features/timeline test/features/together`
Expected: all pass.

- [ ] **Step 11: Checkpoint**

`flutter analyze lib/features/stories test/features/stories` filtered → no errors or warnings. No commit.

---
### Task 6: The ring query has its index and tells the client when to look again (03 L7, M2; Wave 4 M-6)

**Files:**
- Create: `supabase/migrations/20261024100400_story_ring_index.sql`
- Create: `supabase/migrations/20261024100410_story_ring_summary_expiry.sql`
- Create: `supabase/tests/story_ring_summary_contracts.sql`
- Modify: `lib/features/stories/data/story_read_repository.dart` (`StoryRingSummary`: `serverNow`)
- Modify: `lib/features/stories/presentation/state/story_ring_refresh.dart` (new `storyServerClockOffset`)
- Modify: `lib/features/stories/presentation/providers/story_providers.dart` (`storyRingSummaryProvider`: the expiry delay uses the offset)
- Modify: `test/features/stories/support/ring_test_kit.dart` (`ringRow` gains `serverNow`)
- Modify: `test/features/stories/story_ring_refresh_test.dart` (new tests)

**Interfaces:**
- Produces:
  - Index `idx_story_items_active ON public.story_items (relationship_id, expires_at) WHERE deleted_at IS NULL`.
  - `get_story_ring_summary(uuid)` returns `(author_id uuid, active_count bigint, unviewed_count bigint, newest_thumbnail_key text, newest_created_at timestamptz, next_expires_at timestamptz, server_now timestamptz)`; `next_expires_at = min(expires_at)` of that author's active stories; `server_now = now()` (same on every row).
  - Dart: `StoryRingSummary.serverNow` (`DateTime?`, parsed from `server_now`, **not** written by `toRow()`, so a snapshot never differs only by clock); `Duration storyServerClockOffset({required DateTime serverNow, required DateTime startedAt, required DateTime receivedAt})` in `story_ring_refresh.dart`, clamped to ±1 day.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/story_ring_summary_contracts.sql
--
-- Stories Wave 5, Task 6 (review 03 L7, M2; Wave 4 M-6): the ring query
-- reads only active rows through its own index, and returns each author's
-- soonest expiry plus the server's clock.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000939a1'), ('00000000-0000-0000-0000-0000000939b2'),
  ('00000000-0000-0000-0000-0000000939c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000939a1', '+15550939001', 'GA'),
  ('00000000-0000-0000-0000-0000000939b2', '+15550939002', 'GB'),
  ('00000000-0000-0000-0000-0000000939c3', '+15550939003', 'GC')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
  ('00000000-0000-0000-0000-0000000939e1', '00000000-0000-0000-0000-0000000939a1', '00000000-0000-0000-0000-0000000939b2', 'active');

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- Two years of history (expired) plus three active stories.
SET LOCAL session_replication_role = replica;
INSERT INTO public.story_items (client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000939e1',
       CASE WHEN g % 2 = 0 THEN '00000000-0000-0000-0000-0000000939a1'::uuid ELSE '00000000-0000-0000-0000-0000000939b2'::uuid END,
       'image', 'story-media/g939/old-' || g || '-media', 'story-media/g939/old-' || g || '-thumbnail', 100, 100,
       (now() - make_interval(hours => 5 + g))::date, now() - make_interval(hours => 5 + g),
       now() - make_interval(hours => 5 + g) + interval '24 hours'
FROM generate_series(30, 3600) g;
INSERT INTO public.story_items (client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at, has_been_viewed)
VALUES
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000939e1', '00000000-0000-0000-0000-0000000939b2', 'image',
   'story-media/g939/b1-media', 'story-media/g939/b1-thumbnail', 100, 100, CURRENT_DATE,
   now() - interval '20 hours', now() + interval '4 hours', false),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000939e1', '00000000-0000-0000-0000-0000000939b2', 'image',
   'story-media/g939/b2-media', 'story-media/g939/b2-thumbnail', 100, 100, CURRENT_DATE,
   now() - interval '2 hours', now() + interval '22 hours', true),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000939e1', '00000000-0000-0000-0000-0000000939a1', 'image',
   'story-media/g939/a1-media', 'story-media/g939/a1-thumbnail', 100, 100, CURRENT_DATE,
   now() - interval '1 hour', now() + interval '23 hours', false);
SET LOCAL session_replication_role = origin;
ANALYZE public.story_items;

-- R1. The index exists and the ring's own predicate uses it at volume.
DO $$
DECLARE v_plan text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_story_items_active'
                 AND indexdef LIKE '%(relationship_id, expires_at)%' AND indexdef LIKE '%deleted_at IS NULL%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no (relationship_id, expires_at) partial index for the ring (03 L7)';
  END IF;
  EXECUTE $q$EXPLAIN (FORMAT JSON)
    SELECT si.author_id, count(*) FROM public.story_items si
     WHERE si.relationship_id = '00000000-0000-0000-0000-0000000939e1'
       AND si.deleted_at IS NULL AND si.expires_at > now()
     GROUP BY si.author_id$q$ INTO v_plan;
  IF v_plan NOT LIKE '%idx_story_items_active%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ring query does not use idx_story_items_active: %', v_plan;
  END IF;
END $$;

-- R2. The summary's new columns.
DO $$
DECLARE v record; v_n int := 0;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000939a1');
  FOR v IN SELECT * FROM public.get_story_ring_summary('00000000-0000-0000-0000-0000000939e1') LOOP
    v_n := v_n + 1;
    IF v.server_now IS DISTINCT FROM now() THEN
      RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: server_now is %', v.server_now;
    END IF;
    IF v.author_id = '00000000-0000-0000-0000-0000000939b2' THEN
      IF v.active_count <> 2 OR v.unviewed_count <> 1 OR v.next_expires_at IS DISTINCT FROM now() + interval '4 hours'
         OR v.newest_thumbnail_key IS DISTINCT FROM 'story-media/g939/b2-thumbnail' THEN
        RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: partner row is %', row_to_json(v);
      END IF;
    ELSIF v.author_id = '00000000-0000-0000-0000-0000000939a1' THEN
      IF v.active_count <> 1 OR v.unviewed_count <> 0 OR v.next_expires_at IS DISTINCT FROM now() + interval '23 hours' THEN
        RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: my row is %', row_to_json(v);
      END IF;
    END IF;
  END LOOP;
  RESET ROLE;
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % ring rows (want 2)', v_n; END IF;

  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000939c3');
  SELECT count(*) INTO v_n FROM public.get_story_ring_summary('00000000-0000-0000-0000-0000000939e1');
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider sees % ring rows', v_n; END IF;
END $$;

-- R3. Grants and search_path.
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.get_story_ring_summary(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_story_ring_summary(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_story_ring_summary grants are wrong';
  END IF;
  IF NOT ('search_path=""' = ANY (coalesce((SELECT proconfig FROM pg_proc
         WHERE oid = 'public.get_story_ring_summary(uuid)'::regprocedure), '{}'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_story_ring_summary does not pin search_path';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to see it fail**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_ring_summary_contracts.sql`
Expected: `CONTRACT VIOLATED: no (relationship_id, expires_at) partial index for the ring (03 L7)`.

- [ ] **Step 3: Write the two migrations**

```sql
-- supabase/migrations/20261024100400_story_ring_index.sql
--
-- Stories Wave 5 (review 03 L7): get_story_ring_summary filters
-- expires_at > now(), but no index led on (relationship_id, expires_at), so
-- every ring refresh range-scanned the relationship's whole history. Plain
-- CREATE INDEX (story_items is small enough that the lock is brief);
-- IF NOT EXISTS keeps it idempotent.
CREATE INDEX IF NOT EXISTS idx_story_items_active
  ON public.story_items (relationship_id, expires_at)
  WHERE deleted_at IS NULL;
```

```sql
-- supabase/migrations/20261024100410_story_ring_summary_expiry.sql
--
-- Stories Wave 5 (review 03 M2; Wave 4 M-6): the ring summary returns each
-- author's soonest expiry (next_expires_at) and the server's clock
-- (server_now), so the client re-reads exactly when a story leaves the ring,
-- on the server's clock rather than the phone's. The Wave 4 client already
-- parses next_expires_at; it reads server_now from this release.
-- The RETURNS TABLE shape changes, so DROP + CREATE in one transaction, and
-- the grants are re-applied. Otherwise identical to 20261017140000, with
-- search_path pinned to ''.
BEGIN;

DROP FUNCTION IF EXISTS public.get_story_ring_summary(uuid);

CREATE FUNCTION public.get_story_ring_summary(
  p_relationship_id uuid
)
RETURNS TABLE (
  author_id             uuid,
  active_count          bigint,
  unviewed_count        bigint,
  newest_thumbnail_key  text,
  newest_created_at     timestamptz,
  next_expires_at       timestamptz,
  server_now            timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    si.author_id,
    count(*) AS active_count,
    count(*) FILTER (
      WHERE si.author_id <> auth.uid() AND NOT si.has_been_viewed
    ) AS unviewed_count,
    (array_agg(si.thumbnail_key ORDER BY si.created_at DESC, si.id DESC))[1]
      AS newest_thumbnail_key,
    max(si.created_at) AS newest_created_at,
    min(si.expires_at) AS next_expires_at,
    now() AS server_now
  FROM public.story_items si
 WHERE si.relationship_id = p_relationship_id
   AND si.deleted_at IS NULL
   AND public.story_relationship_is_open(p_relationship_id, auth.uid())
   AND si.expires_at > now()
 GROUP BY si.author_id
$$;

REVOKE ALL ON FUNCTION public.get_story_ring_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_story_ring_summary(uuid) TO authenticated;

COMMIT;
```

- [ ] **Step 4: Apply and run**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100400_story_ring_index.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100410_story_ring_summary_expiry.sql`
Then: the contract → `ROLLBACK`, exit 0. Then `story_contracts` → all PASS (`story_seen_state` and `story_read` read the summary).
If R1's plan check fails although the index exists (the planner chose `idx_story_reel`), print the plan with `RAISE NOTICE` and report it: do not weaken the check, the review asked for an `EXPLAIN` at volume.

- [ ] **Step 5: Write the failing Dart tests**

a) `test/features/stories/support/ring_test_kit.dart`: `ringRow` gains `DateTime? serverNow,` and passes `serverNow: serverNow,` to `StoryRingSummary`.

b) In `test/features/stories/story_ring_refresh_test.dart`, add a group after `storyRingExpiryDelay`:

```dart
  group('storyServerClockOffset (Wave 5, Wave 4 M-6)', () {
    final start = DateTime.utc(2026, 10, 24, 12);

    test('the server ahead of the phone by 5 minutes, read in 2 s', () {
      expect(
        storyServerClockOffset(
          serverNow: start.add(const Duration(minutes: 5, seconds: 1)),
          startedAt: start,
          receivedAt: start.add(const Duration(seconds: 2)),
        ),
        const Duration(minutes: 5),
      );
    });

    test('behind the phone is negative; a wild value is capped at a day', () {
      expect(
        storyServerClockOffset(
          serverNow: start.subtract(const Duration(minutes: 3)),
          startedAt: start,
          receivedAt: start,
        ),
        const Duration(minutes: -3),
      );
      expect(
        storyServerClockOffset(
          serverNow: start.add(const Duration(days: 400)),
          startedAt: start,
          receivedAt: start,
        ),
        const Duration(days: 1),
      );
    });
  });
```

and, inside `group('storyRingSummaryProvider', …)`:

```dart
    testWidgets("a phone clock 5 minutes behind re-reads at the server's "
        'expiry, not 5 minutes late (Wave 5, Wave 4 M-6)', (tester) async {
      final server = clock.now().add(const Duration(minutes: 5));
      final gateway = RingGateway(
        summary: [
          ringRow(
            newest: server.subtract(const Duration(hours: 23, minutes: 59)),
            nextExpiresAt: server.add(const Duration(seconds: 30)),
            serverNow: server,
          ),
        ],
      );
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 1);
      gateway.summary = [];
      await tester.pump(const Duration(seconds: 33));
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 2);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });
```

and next to `'next_expires_at is read when the server sends it'`:

```dart
  test('server_now is read but never stored in the snapshot row', () {
    final row = StoryRingSummary.fromRow({
      'author_id': 'a',
      'active_count': 1,
      'unviewed_count': 0,
      'newest_thumbnail_key': 'k',
      'newest_created_at': '2026-10-24T10:00:00Z',
      'server_now': '2026-10-24T10:05:00Z',
    });
    expect(row.serverNow, DateTime.utc(2026, 10, 24, 10, 5));
    expect(row.toRow().containsKey('server_now'), isFalse);
    final later = StoryRingSummary.fromRow({...row.toRow(), 'server_now': '2026-10-24T11:00:00Z'});
    expect(
      storyRingRowsDiffer({'a': row}, {'a': later}),
      isFalse,
      reason: 'a new clock alone does not rewrite the last-known snapshot',
    );
  });
```

- [ ] **Step 6: Run them to see them fail**

Run: `flutter test test/features/stories/story_ring_refresh_test.dart`
Expected: compile errors (`storyServerClockOffset` undefined; no named parameter `serverNow`).

- [ ] **Step 7: Implement**

1. `story_read_repository.dart`, `StoryRingSummary`: add `this.serverNow,` to the constructor; in `fromRow` add `serverNow: row['server_now'] == null ? null : DateTime.parse('${row['server_now']}'),`; add the field:

```dart
  /// The server's clock when this summary was read (Wave 5; null from an
  /// older server). Used only to correct the expiry timer for a phone clock
  /// that is off (Wave 4 M-6); never stored by [toRow], so the last-known
  /// snapshot is not rewritten by a clock change alone.
  final DateTime? serverNow;
```

`toRow()` is unchanged.

2. `story_ring_refresh.dart`, after `storyRingExpiryDelay`:

```dart
/// How far the server's clock runs ahead of this phone's (negative: behind),
/// from one ring read: `server_now` against the middle of the request
/// (Wave 5, Wave 4 M-6). Capped at a day either way, so one bad value cannot
/// park the expiry timer for ever.
Duration storyServerClockOffset({
  required DateTime serverNow,
  required DateTime startedAt,
  required DateTime receivedAt,
}) {
  final middle = startedAt.add(receivedAt.difference(startedAt) ~/ 2);
  final offset = serverNow.difference(middle);
  const cap = Duration(days: 1);
  if (offset > cap) return cap;
  if (offset < -cap) return -cap;
  return offset;
}
```

3. `story_providers.dart`, in `storyRingSummaryProvider` replace `final expiry = storyRingExpiryDelay(fetch.rows, now);` with:

```dart
      // Wave 5 (Wave 4 M-6): judge expiry on the server's clock when it
      // sends one, so a phone clock behind it never keeps an expired story
      // on the ring.
      DateTime? serverNow;
      for (final row in fetch.rows) {
        if (row.serverNow != null) {
          serverNow = row.serverNow;
          break;
        }
      }
      final skew =
          serverNow == null
              ? Duration.zero
              : storyServerClockOffset(
                serverNow: serverNow,
                startedAt: fetch.startedAt,
                receivedAt: now,
              );
      final expiry = storyRingExpiryDelay(fetch.rows, now.add(skew));
```

Nothing else in the provider changes (`now` still feeds the snapshot and the dropped-key logic).

- [ ] **Step 8: Run the ring suites**

Run: `flutter test test/features/stories/story_ring_refresh_test.dart test/features/stories/story_rings_test.dart test/features/stories/story_ring_last_known_test.dart test/features/stories/story_read_repository_test.dart`
Expected: all pass, including the existing skew test (`a phone clock ahead of the server re-checks each minute`): its rows carry no `server_now`, so the offset is zero there.

- [ ] **Step 9: Checkpoint**

`flutter analyze` on the three lib files → clean. No commit.

---

### Task 7: Day reads by author, with per-author unviewed counts: server and data layer (04 #4; Wave 4 B5)

**Files:**
- Create: `supabase/migrations/20261024100500_story_day_reads_by_author.sql`
- Create: `supabase/tests/story_day_reads_contracts.sql`
- Modify: `supabase/tests/story_read_contracts.sql` (two signature literals; they pin the dropped 5-argument function)
- Modify: `lib/features/stories/data/story_read_repository.dart` (`StoryDayCount.unviewedCount`; `StoryReadGateway.listDayItems` + `StoryReadRepository.listDayItems` take `String? authorId`)
- Modify: `lib/features/stories/presentation/providers/story_providers.dart` (`StoryDayKey.authorId`; `StoryDayItemsNotifier.fetchPage` passes it)
- Modify (signature only, `String? authorId,` added to each `listDayItems` override): `test/features/together/timeline_together_events_test.dart`, `test/features/stories/story_read_repository_test.dart` (two), `story_rings_test.dart`, `story_reply_test.dart`, `story_reel_test.dart`, `story_calendar_test.dart` (two), `support/fake_story_read_gateway.dart`, `support/reel_test_kit.dart`, `support/ring_test_kit.dart`, `test/features/timeline/calendar_day_sheet_empty_test.dart`, `calendar_day_indicators_test.dart`, `calendar_all_months_test.dart` (find them with `grep -rn "Future<StoryItemPage> listDayItems({" test`)
- Modify: `test/features/stories/story_read_repository_test.dart` (new group)

**Interfaces:**
- Produces:
  - SQL: `list_story_day_items(p_relationship_id uuid, p_occurred_on date, p_after_created_at timestamptz DEFAULT NULL, p_after_id uuid DEFAULT NULL, p_limit int DEFAULT 50, p_author_id uuid DEFAULT NULL) RETURNS SETOF public.story_items` (the 5-argument version is dropped). `list_story_day_counts(uuid, date, date)` returns its six columns plus `unviewed_count bigint` (the caller's unviewed count of that author's stories that day; `0` on the caller's own rows), and becomes SECURITY DEFINER with the read predicate inline (it must read `has_been_viewed`, which clients cannot select).
  - Dart: `StoryDayCount.unviewedCount` (`int?`, null from an older server); `StoryReadGateway.listDayItems({required String relationshipId, required DateTime occurredOn, StoryPageCursor? after, int limit = 50, String? authorId})`; `StoryDayKey({required String relationshipId, required DateTime occurredOn, String? authorId})` (author part of `==`/`hashCode`). The repository sends `p_author_id` only when given and, on `PGRST202`, asks again without it and stops sending it for the session; callers keep their own author filter, so either server is correct.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/story_day_reads_contracts.sql
--
-- Stories Wave 5, Task 7 (review 04 #4): one author's stories on a day are
-- read by the server, paged by keyset; the month counts carry each author's
-- unviewed count, so a day ring is right beyond the first page.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000938a1'), ('00000000-0000-0000-0000-0000000938b2'),
  ('00000000-0000-0000-0000-0000000938c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000938a1', '+15550938001', 'DA'),
  ('00000000-0000-0000-0000-0000000938b2', '+15550938002', 'DB'),
  ('00000000-0000-0000-0000-0000000938c3', '+15550938003', 'DC')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
  ('00000000-0000-0000-0000-0000000938e1', '00000000-0000-0000-0000-0000000938a1', '00000000-0000-0000-0000-0000000938b2', 'active');

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- A day three days ago: A posted a1..a3, B posted b1..b3 (b1 seen by A), plus a deleted b4.
SET LOCAL session_replication_role = replica;
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at, has_been_viewed, deleted_at)
SELECT ('00000000-0000-0000-0000-00000093800' || n)::uuid, gen_random_uuid(), '00000000-0000-0000-0000-0000000938e1',
       CASE WHEN n <= 3 THEN '00000000-0000-0000-0000-0000000938a1'::uuid ELSE '00000000-0000-0000-0000-0000000938b2'::uuid END,
       'image', 'story-media/d938/' || n || '-media', 'story-media/d938/' || n || '-thumbnail', 100, 100,
       CURRENT_DATE - 3, now() - interval '3 days' + make_interval(mins => n),
       now() - interval '3 days' + make_interval(mins => n) + interval '24 hours',
       n = 4, CASE WHEN n = 7 THEN now() END
FROM generate_series(1, 7) n;
SET LOCAL session_replication_role = origin;
-- ids: 1..3 = A's, 4..6 = B's (4 seen), 7 = B's deleted.

-- D1. Only B's, paged.
DO $$
DECLARE v_ids uuid[]; v_last public.story_items;
BEGIN
  SELECT * INTO v_last FROM public.story_items WHERE id = '00000000-0000-0000-0000-000000938005';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  SELECT array_agg(i.id ORDER BY i.created_at) INTO v_ids
    FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3,
           p_limit => 2, p_author_id => '00000000-0000-0000-0000-0000000938b2') i;
  IF v_ids IS DISTINCT FROM ARRAY['00000000-0000-0000-0000-000000938004', '00000000-0000-0000-0000-000000938005']::uuid[] THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: page 1 of B''s day is %', v_ids;
  END IF;
  SELECT array_agg(i.id) INTO v_ids
    FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3,
           v_last.created_at, v_last.id, 2, '00000000-0000-0000-0000-0000000938b2') i;
  IF v_ids IS DISTINCT FROM ARRAY['00000000-0000-0000-0000-000000938006']::uuid[] THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: page 2 of B''s day is %', v_ids;
  END IF;
  RESET ROLE;
END $$;

-- D2. The old call shape (no p_author_id) still reads the whole day; one function only.
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  SELECT count(*) INTO v_n FROM public.list_story_day_items(
    p_relationship_id => '00000000-0000-0000-0000-0000000938e1', p_occurred_on => CURRENT_DATE - 3,
    p_after_created_at => NULL, p_after_id => NULL, p_limit => 50);
  RESET ROLE;
  IF v_n <> 6 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the whole day returns % (want 6)', v_n; END IF;
  IF to_regprocedure('public.list_story_day_items(uuid,date,timestamptz,uuid,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 5-argument overload is still there (PGRST203)';
  END IF;
END $$;

-- D3. Per-author unviewed counts.
DO $$
DECLARE v record; v_seen int := 0;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  FOR v IN SELECT * FROM public.list_story_day_counts('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 7, CURRENT_DATE) LOOP
    v_seen := v_seen + 1;
    IF v.author_id = '00000000-0000-0000-0000-0000000938b2' AND (v.item_count <> 3 OR v.unviewed_count <> 2 OR v.day_item_count <> 6) THEN
      RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: B''s day row is %', row_to_json(v);
    END IF;
    IF v.author_id = '00000000-0000-0000-0000-0000000938a1' AND (v.item_count <> 3 OR v.unviewed_count <> 0) THEN
      RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: my own day row is %', row_to_json(v);
    END IF;
    IF v.author_id = '00000000-0000-0000-0000-0000000938b2' AND v.newest_thumbnail_key IS DISTINCT FROM 'story-media/d938/6-thumbnail' THEN
      RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted story supplies the thumbnail: %', v.newest_thumbnail_key;
    END IF;
  END LOOP;
  RESET ROLE;
  IF v_seen <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % day-count rows (want 2)', v_seen; END IF;

  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938c3');
  SELECT count(*) INTO v_seen FROM public.list_story_day_counts('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 7, CURRENT_DATE);
  RESET ROLE;
  IF v_seen <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider sees % day-count rows', v_seen; END IF;
  UPDATE public.relationships SET status = 'paused' WHERE id = '00000000-0000-0000-0000-0000000938e1';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  SELECT count(*) INTO v_seen FROM public.list_story_day_counts('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 7, CURRENT_DATE);
  RESET ROLE;
  IF v_seen <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a paused couple''s calendar shows % rows', v_seen; END IF;
  UPDATE public.relationships SET status = 'active' WHERE id = '00000000-0000-0000-0000-0000000938e1';
END $$;

-- D4. Grants and search_path.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.list_story_day_items(uuid,date,timestamptz,uuid,integer,uuid)',
                              'public.list_story_day_counts(uuid,date,date)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % grants are wrong', v_fn;
    END IF;
    IF NOT (SELECT prosecdef AND 'search_path=""' = ANY (coalesce(proconfig, '{}')) FROM pg_proc WHERE oid = v_fn::regprocedure) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not a definer with search_path ''''', v_fn;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
```

If a lifecycle trigger refuses the direct `status` updates, use `pause_relationship`/`resume_relationship` as in Task 4.

- [ ] **Step 2: Run it to see it fail**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_day_reads_contracts.sql`
Expected: `ERROR:  function public.list_story_day_items(…, p_limit => integer, p_author_id => uuid) does not exist`.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261024100500_story_day_reads_by_author.sql
--
-- Stories Wave 5 (review 04 #4; Wave 4 deps):
--   * list_story_day_items takes p_author_id, so one author's calendar ring
--     reads only that author's stories instead of paging the whole day. It
--     is LAST with DEFAULT NULL; the 5-argument version is DROPPED (not
--     overloaded) so an old client's call still resolves and PostgREST never
--     sees two candidates (PGRST203).
--   * list_story_day_counts returns unviewed_count per (day, author): the
--     caller's unviewed stories of that author (0 on the caller's own rows),
--     so a day ring is right on a day with more than 50 stories. It reads
--     has_been_viewed, which clients cannot select (20261017140100), so it
--     becomes SECURITY DEFINER with story_items_read_members' predicate inline
--     (deleted_at IS NULL, open relationship), like the other story reads.
-- Both pin search_path to ''. Shape changes, so DROP + CREATE in one
-- transaction; grants re-applied.
BEGIN;

DROP FUNCTION IF EXISTS public.list_story_day_items(uuid, date, timestamptz, uuid, int);

CREATE FUNCTION public.list_story_day_items(
  p_relationship_id   uuid,
  p_occurred_on       date,
  p_after_created_at  timestamptz DEFAULT NULL,
  p_after_id          uuid DEFAULT NULL,
  p_limit             int DEFAULT 50,
  p_author_id         uuid DEFAULT NULL
)
RETURNS SETOF public.story_items
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (jsonb_populate_record(si, jsonb_build_object(
            'has_been_viewed',
              CASE WHEN si.author_id = auth.uid() THEN (s.v_on AND si.seen_shown)
                   ELSE si.has_been_viewed END,
            'seen_shown', false))).*
    FROM public.story_items si
   CROSS JOIN (SELECT public.seen_receipts_effective(p_relationship_id) AS v_on) s
   WHERE si.relationship_id = p_relationship_id
     AND si.occurred_on = p_occurred_on
     AND (p_author_id IS NULL OR si.author_id = p_author_id)
     AND si.deleted_at IS NULL
     AND public.story_relationship_is_open(si.relationship_id, auth.uid())
     AND (
       p_after_created_at IS NULL
       OR (si.created_at, si.id) > (p_after_created_at, p_after_id)
     )
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

REVOKE ALL ON FUNCTION public.list_story_day_items(uuid, date, timestamptz, uuid, int, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_story_day_items(uuid, date, timestamptz, uuid, int, uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.list_story_day_counts(uuid, date, date);

CREATE FUNCTION public.list_story_day_counts(
  p_relationship_id uuid,
  p_start_on        date,
  p_end_on          date
)
RETURNS TABLE (
  occurred_on          date,
  author_id            uuid,
  item_count           bigint,
  day_item_count       bigint,
  newest_thumbnail_key text,
  newest_created_at    timestamptz,
  unviewed_count       bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH visible AS (
    SELECT si.id, si.occurred_on, si.author_id, si.created_at, si.thumbnail_key, si.has_been_viewed
      FROM public.story_items si
     WHERE si.relationship_id = p_relationship_id
       AND si.occurred_on BETWEEN p_start_on AND p_end_on
       AND si.deleted_at IS NULL
       AND public.story_relationship_is_open(p_relationship_id, auth.uid())
  ),
  per_author AS (
    SELECT v.occurred_on,
           v.author_id,
           count(*) AS item_count,
           max(v.created_at) AS newest_created_at,
           count(*) FILTER (WHERE v.author_id <> auth.uid() AND NOT v.has_been_viewed) AS unviewed_count
      FROM visible v
     GROUP BY v.occurred_on, v.author_id
  )
  SELECT pa.occurred_on,
         pa.author_id,
         pa.item_count,
         (sum(pa.item_count) OVER (PARTITION BY pa.occurred_on))::bigint AS day_item_count,
         newest.thumbnail_key AS newest_thumbnail_key,
         pa.newest_created_at,
         pa.unviewed_count
    FROM per_author pa
    LEFT JOIN LATERAL (
      SELECT v2.thumbnail_key
        FROM visible v2
       WHERE v2.occurred_on = pa.occurred_on
         AND v2.author_id = pa.author_id
       ORDER BY v2.created_at DESC, v2.id DESC
       LIMIT 1
    ) AS newest ON true
   ORDER BY pa.occurred_on, pa.newest_created_at DESC, pa.author_id
$$;

REVOKE ALL ON FUNCTION public.list_story_day_counts(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_story_day_counts(uuid, date, date) TO authenticated;

COMMIT;
```

- [ ] **Step 4: Update the contract that pins the old signature, then apply and run**

In `supabase/tests/story_read_contracts.sql`, replace both occurrences of `'public.list_story_day_items(uuid,date,timestamptz,uuid,int)'` with `'public.list_story_day_items(uuid,date,timestamptz,uuid,int,uuid)'` (its grant checks; the behaviour they guard is unchanged). Without this it fails with `function "public.list_story_day_items(uuid,date,timestamptz,uuid,int)" does not exist`.

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100500_story_day_reads_by_author.sql`
Then: the contract → `ROLLBACK`, exit 0. Then `story_contracts && related_contracts` → all PASS (`story_read_contracts` and `story_seen_state_contracts` read both functions).

- [ ] **Step 5: Mutation check**

`mutate supabase/migrations/20261024100500_story_day_reads_by_author.sql "s/AND (p_author_id IS NULL OR si.author_id = p_author_id)//" supabase/tests/story_day_reads_contracts.sql` → `CONTRACT VIOLATED: page 1 of B's day is …`.
`mutate … "s/WHERE v.author_id <> auth.uid() AND NOT v.has_been_viewed/WHERE NOT v.has_been_viewed/" …` → `CONTRACT VIOLATED: my own day row is …`.

- [ ] **Step 6: Write the failing Dart tests**

In `test/features/stories/story_read_repository_test.dart`, add imports `import 'dart:convert';`, `import 'package:http/http.dart' as http;`, `import 'package:http/testing.dart';` if missing, and a group:

```dart
  group('day reads by author (Wave 5, 04 #4)', () {
    late List<Map<String, dynamic>> bodies;

    StoryReadRepository repoAnswering(List<http.Response> answers) {
      bodies = [];
      final queue = [...answers];
      final supabase = SupabaseClient(
        'https://x.supabase.co',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return queue.removeAt(0);
        }),
      );
      addTearDown(supabase.dispose);
      return StoryReadRepository(supabase);
    }

    http.Response empty() =>
        http.Response('[]', 200, headers: {'content-type': 'application/json'});
    http.Response missing() => http.Response(
      jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function', 'details': null, 'hint': null}),
      404,
      headers: {'content-type': 'application/json'},
    );

    test('p_author_id is sent only when an author is asked for', () async {
      final repo = repoAnswering([empty(), empty()]);
      final day = DateTime(2026, 10, 21);
      await repo.listDayItems(relationshipId: 'r1', occurredOn: day, authorId: 'b');
      await repo.listDayItems(relationshipId: 'r1', occurredOn: day);
      expect(bodies[0]['p_author_id'], 'b');
      expect(bodies[0]['p_occurred_on'], '2026-10-21');
      expect(bodies[1].containsKey('p_author_id'), isFalse);
    });

    test('an older server (PGRST202) is asked again without it, and the '
        'session remembers', () async {
      final repo = repoAnswering([missing(), empty(), empty()]);
      final day = DateTime(2026, 10, 21);
      final page = await repo.listDayItems(relationshipId: 'r1', occurredOn: day, authorId: 'b');
      expect(page.items, isEmpty);
      expect(bodies, hasLength(2));
      expect(bodies[1].containsKey('p_author_id'), isFalse);
      await repo.listDayItems(relationshipId: 'r1', occurredOn: day, authorId: 'b');
      expect(bodies, hasLength(3));
      expect(bodies[2].containsKey('p_author_id'), isFalse);
    });

    test('day counts read unviewed_count, null from an older server', () {
      final now = StoryDayCount.fromRow({
        'occurred_on': '2026-10-21', 'author_id': 'b', 'item_count': 70,
        'day_item_count': 70, 'newest_thumbnail_key': 'k',
        'newest_created_at': '2026-10-21T20:00:00Z', 'unviewed_count': 61,
      });
      expect(now.unviewedCount, 61);
      final old = StoryDayCount.fromRow({
        'occurred_on': '2026-10-21', 'author_id': 'b', 'item_count': 70,
      });
      expect(old.unviewedCount, isNull);
    });

    test('a day key with an author is a different key', () {
      final day = DateTime(2026, 10, 21);
      final whole = StoryDayKey(relationshipId: 'r1', occurredOn: day);
      final mine = StoryDayKey(relationshipId: 'r1', occurredOn: day, authorId: 'a');
      expect(whole == mine, isFalse);
      expect(mine, StoryDayKey(relationshipId: 'r1', occurredOn: DateTime(2026, 10, 21, 13), authorId: 'a'));
      expect(mine.hashCode, StoryDayKey(relationshipId: 'r1', occurredOn: day, authorId: 'a').hashCode);
    });

    test('the day pager passes its author to the gateway', () async {
      final gateway = FakeStoryReadGateway();
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(_signedInUser),
        storyReadGatewayProvider.overrideWithValue(gateway),
      ]);
      addTearDown(container.dispose);
      final key = StoryDayKey(relationshipId: 'rel-1', occurredOn: DateTime(2026, 10, 21), authorId: 'author-2');
      final sub = container.listen(storyDayItemsProvider(key), (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      expect(gateway.dayAuthorIds, ['author-2']);
    });
  });
```

`FakeStoryReadGateway` here is this file's own fake (the class defined at the top of the file, not `support/fake_story_read_gateway.dart`; check which one the file's other provider tests use and add the field there): it gains `final dayAuthorIds = <String?>[];` and records `dayAuthorIds.add(authorId);` in `listDayItems`. If its `listDayItems` waits on a completer before recording, record before the wait.

- [ ] **Step 7: Run them to see them fail**

Run: `flutter test test/features/stories/story_read_repository_test.dart --plain-name "day reads by author"`
Expected: compile errors (`No named parameter with the name 'authorId'`, `unviewedCount` undefined).

- [ ] **Step 8: Implement**

1. `StoryDayCount`: add `this.unviewedCount,` to the constructor; in `fromRow` add `unviewedCount: (row['unviewed_count'] as num?)?.toInt(),`; field:

```dart
  /// The caller's unviewed stories of [authorId] on [occurredOn] (Wave 5;
  /// always 0 on the caller's own rows). Null from an older server: the day
  /// sheet then counts the loaded items instead.
  final int? unviewedCount;
```

2. `StoryReadGateway.listDayItems`: add `String? authorId,` with the doc `/// Only this author's stories (Wave 5); null is the whole day. An older server ignores it, so callers keep their own author filter.`

3. `StoryReadRepository`: add the field `bool _dayItemsWithoutAuthor = false;` (`/// Set when the server predates p_author_id (PGRST202).`) and replace the `listDayItems` body:

```dart
  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
    String? authorId,
  }) => _guard(() async {
    String dateOnly(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    Future<dynamic> call({required bool withAuthor}) => _supabase.rpc(
      'list_story_day_items',
      params: {
        'p_relationship_id': relationshipId,
        'p_occurred_on': dateOnly(occurredOn),
        'p_after_created_at': after?.createdAt.toIso8601String(),
        'p_after_id': after?.id,
        'p_limit': limit,
        if (withAuthor) 'p_author_id': authorId,
      },
    );
    final withAuthor = authorId != null && !_dayItemsWithoutAuthor;
    dynamic rows;
    try {
      rows = await call(withAuthor: withAuthor);
    } on PostgrestException catch (e) {
      if (!withAuthor || e.code != 'PGRST202') rethrow;
      _dayItemsWithoutAuthor = true;
      rows = await call(withAuthor: false);
    }
    final items = (rows as List)
        .map((row) => StoryItem.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    return StoryItemPage(
      items: items,
      nextCursor: _nextCursorFor(items, limit),
    );
  });
```

`_nextCursorFor` stays: a short page from the old server (whole day) or the new one (one author) both mean "no more".

4. `story_providers.dart`, `StoryDayKey`:

```dart
@immutable
class StoryDayKey {
  const StoryDayKey({
    required this.relationshipId,
    required this.occurredOn,
    this.authorId,
  });

  final String relationshipId;
  final DateTime occurredOn;

  /// One author's stories on the day (a calendar ring, Wave 5); null is the
  /// whole day.
  final String? authorId;

  @override
  bool operator ==(Object other) =>
      other is StoryDayKey &&
      other.relationshipId == relationshipId &&
      other.authorId == authorId &&
      other.occurredOn.year == occurredOn.year &&
      other.occurredOn.month == occurredOn.month &&
      other.occurredOn.day == occurredOn.day;

  @override
  int get hashCode => Object.hash(
    relationshipId,
    authorId,
    occurredOn.year,
    occurredOn.month,
    occurredOn.day,
  );
}
```

and in `StoryDayItemsNotifier.fetchPage` pass `authorId: _key.authorId,`.

5. Add `String? authorId,` to every fake's `listDayItems` override (Files list). `ScriptedReelGateway` (`support/reel_test_kit.dart`) also gains `final dayAuthorIds = <String?>[];` (recorded) and `bool serverFiltersAuthor = false;` (when true, `_page(day.where((i) => authorId == null || i.authorId == authorId).toList(), after)`); Task 8 uses both.

- [ ] **Step 9: Run the story and calendar suites**

Run: `flutter test test/features/stories test/features/timeline test/features/together`
Expected: all pass. Nothing calls `StoryDayKey` with an author yet, so behaviour is unchanged.

- [ ] **Step 10: Checkpoint**

`flutter analyze lib/features/stories test/features` filtered → clean. No commit.

---

### Task 8: Day rings and the filtered day reel use the server's reads (04 #4; Wave 4 B5 carry)

**Files:**
- Modify: `lib/features/stories/presentation/screens/story_reel_screen.dart` (a `_dayKey` getter used by the five `StoryDayKey(…)` constructions; a counts re-read after a view; the `dayAuthorId` doc)
- Modify: `lib/features/stories/domain/story_day_rings.dart` (`storyDayAuthorRings` prefers the server's unviewed count)
- Modify: `lib/features/timeline/presentation/widgets/calendar_day_sheet.dart` (`_StoriesSection`: no hold-place when the counts carry unviewed)
- Modify: `test/features/stories/story_day_rings_test.dart`, `test/features/stories/story_reel_day_author_test.dart`, `test/features/timeline/calendar_day_sheet_stories_test.dart`; Create: `test/features/stories/story_reel_day_view_counts_test.dart`

**Interfaces:**
- Consumes: Task 7's `StoryDayKey.authorId`, `StoryDayCount.unviewedCount`, `ScriptedReelGateway.dayAuthorIds` / `serverFiltersAuthor`.
- Produces: no new public API. Behaviour: the day reel for one author's ring reads `StoryDayKey(…, authorId: dayAuthorId)`; the client-side `_visible` author filter and the multi-page search stay (an older server returns the whole day, and they cost nothing when the server already filtered). After a successful view of an unviewed story in day or places mode, the reel invalidates `storyDayCountsProvider(StoryDayRangeKey.month(relationshipId, day: item.occurredOn))`.

What this task deliberately does not change: the reel's paging, seek and delete logic (Wave 1/4, heavily tested). With the new server those paths simply see fewer rows.

- [ ] **Step 1: Write the failing tests**

a) `test/features/stories/story_reel_day_author_test.dart`, add:

```dart
  testWidgets("a partner's ring asks the server for the partner's stories "
      '(Wave 5)', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
      ]),
    )..serverFiltersAuthor = true;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    expect(gateway.dayAuthorIds, everyElement(kitPartner));
    expect(shownItemId(tester), 'p1');
    expect(bars(tester), (index: 0, count: 2));
  });

  testWidgets('the whole-day reel asks for the whole day', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([('m1', kitMe, false), ('p1', kitPartner, false)]),
    );
    await pumpReel(tester, gateway: gateway, mode: KitMode.day, hold: const Duration(seconds: 30));
    expect(gateway.dayAuthorIds, everyElement(isNull));
  });
```

The existing tests in this file run with `serverFiltersAuthor = false`: they are the older-server path and must keep passing unchanged.

b) `test/features/stories/story_day_rings_test.dart`, add:

```dart
  test("the server's unviewed count wins over a partial first page (Wave 5)", () {
    final day = DateTime(2026, 10, 21);
    final counts = [
      StoryDayCount(occurredOn: day, authorId: 'partner', itemCount: 70, dayItemCount: 70, unviewedCount: 61),
    ];
    final loaded = [
      for (var i = 0; i < 50; i++)
        StoryItem(
          id: 'p$i', clientStoryId: 'c$i', relationshipId: 'r', authorId: 'partner',
          mediaType: 'image', mediaKey: 'k$i', thumbnailKey: 't$i', mediaWidth: 1, mediaHeight: 1,
          occurredOn: day, createdAt: DateTime.utc(2026, 10, 21, 8).add(Duration(minutes: i)),
          expiresAt: DateTime.utc(2026, 10, 22, 8).add(Duration(minutes: i)), hasBeenViewed: i < 20,
        ),
    ];
    final result = storyDayAuthorRings(day: day, counts: counts, items: loaded, myId: 'me');
    expect(result.rings.single.count, 70);
    expect(result.rings.single.unviewed, 61, reason: 'not the 30 unseen on page one');
    final old = storyDayAuthorRings(
      day: day,
      counts: [StoryDayCount(occurredOn: day, authorId: 'partner', itemCount: 70, dayItemCount: 70)],
      items: loaded,
      myId: 'me',
    );
    expect(old.rings.single.unviewed, 30, reason: 'an older server: the loaded items decide');
  });
```

c) `test/features/timeline/calendar_day_sheet_stories_test.dart`, add after `"the partner's ring never flashes all-seen while the day loads"` (that test keeps passing: its counts carry no unviewed number, so the hold still applies):

```dart
  testWidgets("with the server's unviewed counts the partner's ring draws "
      'before the day loads (Wave 5)', (tester) async {
    final gateway =
        RingGateway()
          ..dayCounts = [
            StoryDayCount(
              occurredOn: _day,
              authorId: ringPartner,
              itemCount: 3,
              dayItemCount: 3,
              newestThumbnailKey: 'story-media/$ringPartner-newest.jpg',
              newestCreatedAt: _day,
              unviewedCount: 2,
            ),
          ]
          ..dayItemsGate = Completer<void>();
    await _openSheet(tester, gateway);
    final ring = find.descendant(
      of: find.byKey(const ValueKey('day-story-ring-$ringPartner')),
      matching: find.byType(StoryRing),
    );
    expect(ring, findsOneWidget);
    expect(tester.widget<StoryRing>(ring).unviewedCount, 2);
    gateway.dayItemsGate!.complete();
    await tester.pump();
  });
```

d) Create `test/features/stories/story_reel_day_view_counts_test.dart`. The first story is marked while `pumpReel` settles, before a listener can attach, so each test listens first and then advances to the second story:

```dart
// Wave 5 (04 #4): the day ring's brightness now comes from the month's
// counts, so watching a partner's story from a day re-reads that month.
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

Future<({ScriptedReelGateway gateway, ProviderSubscription<Object?> sub})> _open(
  WidgetTester tester,
  String author,
) async {
  final gateway = ScriptedReelGateway(day: kitItems(['s1', 's2'], author: author));
  await pumpReel(
    tester,
    gateway: gateway,
    mode: KitMode.day,
    dayAuthorId: author,
    hold: const Duration(seconds: 30),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(StoryReelScreen)),
  );
  final month = StoryDayRangeKey.month(relationshipId: kitRel, day: kitDay);
  final sub = container.listen(storyDayCountsProvider(month), (_, __) {});
  await settle(tester);
  return (gateway: gateway, sub: sub);
}

void main() {
  testWidgets("watching a partner's unseen story from a day re-reads its "
      'month', (tester) async {
    final rig = await _open(tester, kitPartner);
    final before = rig.gateway.dayCountCalls;
    await tapRight(tester);
    await settle(tester);
    expect(rig.gateway.marked, contains('s2'));
    expect(rig.gateway.dayCountCalls, before + 1);
    rig.sub.close();
  });

  testWidgets('my own day ring never re-reads the month on view', (tester) async {
    final rig = await _open(tester, kitMe);
    final before = rig.gateway.dayCountCalls;
    await tapRight(tester);
    await settle(tester);
    expect(rig.gateway.marked, isEmpty);
    expect(rig.gateway.dayCountCalls, before);
    rig.sub.close();
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/stories/story_reel_day_author_test.dart test/features/stories/story_day_rings_test.dart test/features/stories/story_reel_day_view_counts_test.dart test/features/timeline/calendar_day_sheet_stories_test.dart`
Expected: the author test fails (`dayAuthorIds` holds `null`); the rings test fails (`unviewed` 30, want 61); the view-counts test fails (`dayCountCalls` unchanged); the day-sheet test fails (the loading placeholder is shown).

- [ ] **Step 3: Implement**

1. `story_reel_screen.dart`:
   - Add to the state class:

```dart
  /// This screen's day pager key: one author's stories when opened from a
  /// calendar ring (Wave 5 asks the server for them), else the whole day.
  StoryDayKey get _dayKey => StoryDayKey(
    relationshipId: widget.relationshipId,
    occurredOn: widget.occurredOn!,
    authorId: widget.dayAuthorId,
  );
```

   - Replace each of the five `StoryDayKey(relationshipId: widget.relationshipId, occurredOn: occurredOn,)` constructions (in `_itemsProvider` and the four pager helpers; `grep -n "StoryDayKey(" lib/features/stories/presentation/screens/story_reel_screen.dart`) with `_dayKey`. Each sits inside an `if (occurredOn != null)` branch, so `widget.occurredOn!` is safe.
   - In the view-marking method, after `if (mounted) ref.invalidate(storyRingSummaryProvider(widget.relationshipId));`, add:

```dart
      // Wave 5: a day ring's brightness comes from the month's counts, so a
      // first view from a day or a map pin re-reads that month (the change
      // signal does not fire while seen receipts are off).
      if (mounted && !item.hasBeenViewed && (widget.occurredOn != null || _placesMode)) {
        ref.invalidate(
          storyDayCountsProvider(
            StoryDayRangeKey.month(
              relationshipId: widget.relationshipId,
              day: item.occurredOn,
            ),
          ),
        );
      }
```

   - Update the `dayAuthorId` doc: `/// Day mode for one author's ring on the calendar (04 #4): only that author's stories play. The server reads them (Wave 5, p_author_id); the filter here stays for an older server.`

2. `story_day_rings.dart`, in `storyDayAuthorRings` replace the `unviewed` computation with:

```dart
        // My own "viewed" means my partner saw it: my ring is all bright.
        // The partner's: the server's whole-day count when it sends one
        // (Wave 5), else what the loaded items say.
        final serverUnviewed = row?.unviewedCount;
        final unviewed =
            author == myId
                ? count
                : (serverUnviewed ??
                        theirs.where((i) => !i.hasBeenViewed).length)
                    .clamp(0, count);
```

   and update the library doc's last two sentences to: `The loaded items fill in when the counts are missing, and supply the partner's unviewed count only when an older server does not. The larger count per author wins.`

3. `calendar_day_sheet.dart`, `_StoriesSection.build`: replace the hold-place guard

```dart
    if (!itemsAsync.hasValue && !itemsAsync.hasError) {
      return const _StoriesLoading();
    }
```

with

```dart
    // Wave 5: counts that carry the partner's unviewed number need no items
    // to draw the rings right; an older server's still do (fix round 1, M-3).
    final countsKnowUnviewed = day.rings.isNotEmpty &&
        (countsAsync.valueOrNull ?? const <StoryDayCount>[])
            .where((c) =>
                c.occurredOn.year == date.year &&
                c.occurredOn.month == date.month &&
                c.occurredOn.day == date.day &&
                c.authorId != myId)
            .every((c) => c.unviewedCount != null);
    if (!itemsAsync.hasValue && !itemsAsync.hasError && !countsKnowUnviewed) {
      return const _StoriesLoading();
    }
```

Import `StoryDayCount` if the file does not already (`package:attune/features/stories/data/story_read_repository.dart`). Update the comment above the old guard accordingly.

- [ ] **Step 4: Run them to see them pass, then the regression set**

Run the Step 2 command → all pass.
Run: `flutter test test/features/stories test/features/timeline test/features/couple_map test/features/together`
Expected: all pass, in particular `story_reel_day_author_test` (old-server path), `story_reel_delete_coherence_test`, `story_calendar_test`, `calendar_day_sheet_stories_test` (M-3 hold still applies when counts lack unviewed), and the couple-map places reel.

- [ ] **Step 5: Checkpoint**

`flutter analyze` on the three lib files → clean. No commit.

---
### Task 9: Archival bookkeeping: sizes on claim, gone stories closed, failures guarded, small images skipped, a cadence that keeps up (04 #7, #9, #14)

**Files:**
- Create: `supabase/migrations/20261024100600_story_archival_v2.sql`
- Create: `supabase/tests/story_archival_contracts.sql`

**Interfaces:**
- Produces (all `service_role` only, `search_path = ''`):
  - `claim_story_archival_batch(p_limit int) RETURNS TABLE (story_id uuid, media_key text, media_width int, media_height int)`. Before claiming it closes (`state = 'done'`) every `pending`/`processing` job whose story is soft-deleted (`last_error_code = 'story_deleted'`) or already considered (`downscaled_at` set); it claims only jobs whose story is live and not yet considered. Videos are closed out as before.
  - `fail_story_archival(p_story_id uuid, p_error_code text) RETURNS jsonb` acts only on a `processing` job; anything else returns `{"error": false, "found": false}`.
  - `skip_story_archival(p_story_id uuid) RETURNS jsonb`: marks a live, not-yet-considered story `downscaled_at = now()` with its key unchanged, closes its `processing` job as `done` (`last_error_code = 'already_small'`), queues nothing; returns `{"error": false, "skipped": <bool>}`.
  - Index `idx_story_items_video_closeout ON public.story_items (expires_at) WHERE media_type = 'video' AND downscaled_at IS NULL AND deleted_at IS NULL`.
  - Cron `invoke-story-archival` every 5 minutes, calling the worker only while a job or a video close-out is due.
- Consumed by: Task 10's worker (`media_width`, `media_height`, `skip_story_archival`).

`complete_story_archival` is unchanged (ruling 5: the old key's 600 s delay stays).

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/story_archival_contracts.sql
--
-- Stories Wave 5, Task 9 (review 04 #7, #9, #14): the claim hands the worker
-- each image's size, never hands it a deleted story, and a failure cannot
-- reopen a job that a delete already closed. Small images are considered and
-- left alone. The worker runs every 5 minutes, only while work waits.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000936a1'), ('00000000-0000-0000-0000-0000000936b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000936a1', '+15550936001', 'AA'),
  ('00000000-0000-0000-0000-0000000936b2', '+15550936002', 'AB')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
  ('00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1', '00000000-0000-0000-0000-0000000936b2', 'active');

-- Three image stories past their 24 hours (the insert trigger seeds their jobs
-- with available_at = expires_at): s1 portrait 1440x2560, s2 soon deleted,
-- s3 already small (1080x1600).
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
VALUES
  ('00000000-0000-0000-0000-000000936001', gen_random_uuid(), '00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1',
   'image', 'story-media/a936/1-media', 'story-media/a936/1-thumbnail', 1440, 2560, CURRENT_DATE - 2, now() - interval '30 hours', now() - interval '6 hours'),
  ('00000000-0000-0000-0000-000000936002', gen_random_uuid(), '00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1',
   'image', 'story-media/a936/2-media', 'story-media/a936/2-thumbnail', 1440, 2560, CURRENT_DATE - 2, now() - interval '29 hours', now() - interval '5 hours'),
  ('00000000-0000-0000-0000-000000936003', gen_random_uuid(), '00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1',
   'image', 'story-media/a936/3-media', 'story-media/a936/3-thumbnail', 1080, 1600, CURRENT_DATE - 2, now() - interval '28 hours', now() - interval '4 hours');
-- s2 is deleted by a path that did not close its job (a row from before
-- 20260938140000, or any future path): the job is still pending.
UPDATE public.story_items SET deleted_at = now() WHERE id = '00000000-0000-0000-0000-000000936002';

-- A1. The claim returns sizes, skips and closes the deleted story's job.
DO $$
DECLARE v record; v_ids uuid[] := '{}'; v_job record;
BEGIN
  FOR v IN SELECT * FROM public.claim_story_archival_batch(10) LOOP
    v_ids := v_ids || v.story_id;
    IF v.story_id = '00000000-0000-0000-0000-000000936001'
       AND (v.media_width <> 1440 OR v.media_height <> 2560 OR v.media_key <> 'story-media/a936/1-media') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the claim row is %', row_to_json(v);
    END IF;
  END LOOP;
  IF NOT (v_ids @> ARRAY['00000000-0000-0000-0000-000000936001', '00000000-0000-0000-0000-000000936003']::uuid[]) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: claimed %', v_ids;
  END IF;
  IF '00000000-0000-0000-0000-000000936002'::uuid = ANY (v_ids) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted story was handed to the worker (04 #14)';
  END IF;
  SELECT * INTO v_job FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936002';
  IF v_job.state IS DISTINCT FROM 'done' OR v_job.last_error_code IS DISTINCT FROM 'story_deleted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deleted story''s job is % / %', v_job.state, v_job.last_error_code;
  END IF;
END $$;

-- A2. A failure after a delete closed the job does not reopen it.
DO $$
DECLARE v_res jsonb; v_job record;
BEGIN
  v_res := public.fail_story_archival('00000000-0000-0000-0000-000000936002', 'TRANSFORM_FAILED');
  SELECT * INTO v_job FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936002';
  IF v_job.state IS DISTINCT FROM 'done' OR (v_res->>'found') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fail reopened a closed job: % %', v_job.state, v_res;
  END IF;
  -- A processing job still fails back to pending, as before.
  v_res := public.fail_story_archival('00000000-0000-0000-0000-000000936001', 'TRANSFORM_FAILED');
  SELECT * INTO v_job FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936001';
  IF v_job.state IS DISTINCT FROM 'pending' OR v_job.attempts <> 1 OR v_job.last_error_code IS DISTINCT FROM 'TRANSFORM_FAILED' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a processing failure is % / % / %', v_job.state, v_job.attempts, v_job.last_error_code;
  END IF;
END $$;

-- A3. A small image is considered, its key kept, nothing queued for deletion.
DO $$
DECLARE v_res jsonb; v_story record; v_job record;
BEGIN
  v_res := public.skip_story_archival('00000000-0000-0000-0000-000000936003');
  SELECT * INTO v_story FROM public.story_items WHERE id = '00000000-0000-0000-0000-000000936003';
  SELECT * INTO v_job FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936003';
  IF (v_res->>'skipped') IS DISTINCT FROM 'true' OR v_story.downscaled_at IS NULL
     OR v_story.media_key IS DISTINCT FROM 'story-media/a936/3-media'
     OR v_job.state IS DISTINCT FROM 'done' OR v_job.last_error_code IS DISTINCT FROM 'already_small' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: skip left % / % / %', v_res, v_story.downscaled_at, v_job.state;
  END IF;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'story-media/a936/3-media') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: skipping queued the original for deletion';
  END IF;
  -- Skipping a deleted story changes nothing.
  v_res := public.skip_story_archival('00000000-0000-0000-0000-000000936002');
  IF (v_res->>'skipped') IS DISTINCT FROM 'false'
     OR (SELECT downscaled_at FROM public.story_items WHERE id = '00000000-0000-0000-0000-000000936002') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted story was marked considered: %', v_res;
  END IF;
  -- A considered story is never claimed again, and its stray job is closed.
  UPDATE public.story_media_processing_outbox SET state = 'pending' WHERE story_item_id = '00000000-0000-0000-0000-000000936003';
  IF EXISTS (SELECT 1 FROM public.claim_story_archival_batch(10) c WHERE c.story_id = '00000000-0000-0000-0000-000000936003') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a considered story was claimed again';
  END IF;
  IF (SELECT state FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936003') <> 'done' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a considered story''s stray job stays open (the cron would never idle)';
  END IF;
END $$;

-- A4. Grants, search_path, index, cron.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.claim_story_archival_batch(integer)', 'public.fail_story_archival(uuid,text)',
                              'public.skip_story_archival(uuid)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % grants are wrong', v_fn;
    END IF;
    IF NOT ('search_path=""' = ANY (coalesce((SELECT proconfig FROM pg_proc WHERE oid = v_fn::regprocedure), '{}'))) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % does not pin search_path', v_fn;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_story_items_video_closeout') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the video close-out has no index';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'invoke-story-archival' AND schedule = '*/5 * * * *'
                 AND command LIKE '%process-story-archival%' AND command LIKE '%EXISTS%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the archival worker is not on its 5-minute, only-when-due schedule';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to see it fail**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_archival_contracts.sql`
Expected: `ERROR:  record "v" has no field "media_width"` (or `CONTRACT VIOLATED: a deleted story was handed to the worker (04 #14)`).

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261024100600_story_archival_v2.sql
--
-- Stories Wave 5 (review 04 #7, #9, #14):
--   * claim_story_archival_batch returns each image's width and height, so
--     the worker resizes by the LONG edge (portrait stories never reached the
--     1600 px target). It closes, and never claims, a job whose story is
--     soft-deleted or already considered.
--   * fail_story_archival acts only on a job that is being processed: a
--     failure that lands after delete_story_item closed the job no longer
--     reopens it into a spurious dead letter.
--   * skip_story_archival: an image already within 1600 px is considered and
--     left alone (no re-encode, no swap, nothing deleted).
--   * The video close-out UPDATE gets a partial index; the worker runs every
--     5 minutes, and only while something is due (it was 20 images an hour).
-- complete_story_archival is unchanged. All three functions pin search_path
-- to ''. claim's RETURNS TABLE changes, so DROP + CREATE; one transaction.
BEGIN;

DROP FUNCTION IF EXISTS public.claim_story_archival_batch(int);

CREATE FUNCTION public.claim_story_archival_batch(p_limit int)
RETURNS TABLE (
  story_id     uuid,
  media_key    text,
  media_width  int,
  media_height int
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_limit int := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 200);
BEGIN
  -- Video: considered and left alone (no transcoding runtime, §4.4).
  UPDATE public.story_items si
     SET downscaled_at = now()
   WHERE si.media_type = 'video'
     AND si.deleted_at IS NULL
     AND si.downscaled_at IS NULL
     AND si.expires_at <= now();

  -- 04 #14: a job whose story is gone, or already considered, is closed.
  UPDATE public.story_media_processing_outbox o
     SET state = 'done',
         completed_at = now(),
         updated_at = now(),
         last_error_code = CASE WHEN si.deleted_at IS NOT NULL THEN 'story_deleted' ELSE o.last_error_code END
    FROM public.story_items si
   WHERE si.id = o.story_item_id
     AND o.state IN ('pending', 'processing')
     AND (si.deleted_at IS NOT NULL OR si.downscaled_at IS NOT NULL);

  RETURN QUERY
  UPDATE public.story_media_processing_outbox o
     SET state                 = 'processing',
         attempts              = o.attempts + 1,
         processing_started_at = now(),
         updated_at            = now()
    FROM public.story_items si
   WHERE si.id = o.story_item_id
     AND o.story_item_id IN (
           SELECT j.story_item_id
             FROM public.story_media_processing_outbox j
             JOIN public.story_items s2 ON s2.id = j.story_item_id
            WHERE j.available_at <= now()
              AND s2.deleted_at IS NULL
              AND s2.downscaled_at IS NULL
              AND (
                    j.state = 'pending'
                    OR (
                         j.state = 'processing'
                         AND j.processing_started_at
                             <= now() - public.story_archival_lease_timeout()
                       )
                  )
            ORDER BY j.available_at, j.created_at
            LIMIT v_limit
              FOR UPDATE OF j SKIP LOCKED
         )
  RETURNING o.story_item_id, o.source_key, si.media_width, si.media_height;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_story_archival_batch(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_story_archival_batch(int) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_story_archival(
  p_story_id uuid,
  p_error_code text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_attempts int;
  v_dead_lettered boolean := false;
BEGIN
  IF p_story_id IS NULL THEN
    RETURN jsonb_build_object('error', true, 'code', 'INVALID_INPUT');
  END IF;

  UPDATE public.story_media_processing_outbox o
     SET last_error_code = left(p_error_code, 120),
         state = CASE
                   WHEN o.attempts >= public.story_archival_max_attempts() THEN 'dead_letter'
                   ELSE 'pending'
                 END,
         updated_at = now()
   WHERE o.story_item_id = p_story_id
     AND o.state = 'processing'
  RETURNING o.attempts, (o.state = 'dead_letter') INTO v_attempts, v_dead_lettered;

  IF v_attempts IS NULL THEN
    -- No job being processed: deleted mid-flight (closed by
    -- delete_story_item), cascaded away, or never existed. A zero-row finish
    -- is cancellation, not worker failure (§4.4).
    RETURN jsonb_build_object('error', false, 'found', false);
  END IF;

  RETURN jsonb_build_object(
    'error', false, 'found', true,
    'attempts', v_attempts, 'dead_letter', v_dead_lettered
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fail_story_archival(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_story_archival(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.skip_story_archival(p_story_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_skipped boolean;
BEGIN
  IF p_story_id IS NULL THEN
    RETURN jsonb_build_object('error', true, 'code', 'INVALID_INPUT');
  END IF;
  PERFORM 1 FROM public.story_items si WHERE si.id = p_story_id FOR UPDATE;
  UPDATE public.story_items si
     SET downscaled_at = now()
   WHERE si.id = p_story_id
     AND si.deleted_at IS NULL
     AND si.downscaled_at IS NULL;
  v_skipped := FOUND;
  IF v_skipped THEN
    UPDATE public.story_media_processing_outbox o
       SET state = 'done', completed_at = now(), updated_at = now(), last_error_code = 'already_small'
     WHERE o.story_item_id = p_story_id
       AND o.state IN ('pending', 'processing');
  END IF;
  RETURN jsonb_build_object('error', false, 'skipped', v_skipped);
END;
$$;

REVOKE ALL ON FUNCTION public.skip_story_archival(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.skip_story_archival(uuid) TO service_role;

CREATE INDEX IF NOT EXISTS idx_story_items_video_closeout
  ON public.story_items (expires_at)
  WHERE media_type = 'video' AND downscaled_at IS NULL AND deleted_at IS NULL;

DO $$
BEGIN
  PERFORM cron.unschedule('invoke-story-archival');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- Every 5 minutes, only while a job or a video close-out is due, through the
-- vault-backed helper (20260931120000), like build-data-exports.
SELECT cron.schedule(
  'invoke-story-archival',
  '*/5 * * * *',
  $cron$
  SELECT public.invoke_edge_function('process-story-archival')
   WHERE EXISTS (
           SELECT 1 FROM public.story_media_processing_outbox o
            WHERE o.available_at <= now()
              AND (o.state = 'pending'
                   OR (o.state = 'processing' AND o.processing_started_at <= now() - interval '5 minutes')))
      OR EXISTS (
           SELECT 1 FROM public.story_items si
            WHERE si.media_type = 'video' AND si.deleted_at IS NULL
              AND si.downscaled_at IS NULL AND si.expires_at <= now());
  $cron$
);

COMMIT;
```

- [ ] **Step 4: Apply and run**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100600_story_archival_v2.sql`
Then: the contract → `ROLLBACK`, exit 0. Then `story_contracts` → all PASS. `story_maintenance_contracts` exercises claim → fail ×5 → dead letter and the delete-during-archival race; it must stay green (its fails all follow a claim, so the job is `processing`).
Check the schedule replaced the old one: `psql -X -d attune_spec3a -Atc "select schedule from cron.job where jobname='invoke-story-archival'"` → `*/5 * * * *` (one row).

- [ ] **Step 5: Mutation check**

`mutate supabase/migrations/20261024100600_story_archival_v2.sql "s/     AND o.state = 'processing'//" supabase/tests/story_archival_contracts.sql` → `CONTRACT VIOLATED: fail reopened a closed job`.
`mutate … "s/              AND s2.deleted_at IS NULL//" …` → `CONTRACT VIOLATED: a deleted story was handed to the worker (04 #14)` (the close-out `UPDATE` runs first, so also drop it to see the claim guard alone: the contract's A1 still catches either).

- [ ] **Step 6: Checkpoint**

No commit. Deploy order note for Task 16: this migration before the Task 10 worker (the worker calls `skip_story_archival` and reads `media_width`).

---

### Task 10: The archival worker resizes by the long edge, validates every rendition, and keeps up (04 #7, #8, #9; 06 #23)

**Files:**
- Create: `supabase/functions/process-story-archival/archival.ts`
- Create: `supabase/functions/process-story-archival/archival.test.ts`
- Modify (rewrite): `supabase/functions/process-story-archival/index.ts`

**Interfaces:**
- Consumes: Task 9's `claim_story_archival_batch` rows `{story_id, media_key, media_width, media_height}` and `skip_story_archival`; unchanged `story_archive_key(p_story_item_id)`, `complete_story_archival(p_story_id, p_new_key)`, `fail_story_archival(p_story_id, p_error_code)`; Task 2's `requireServiceRole`.
- Produces (in `archival.ts`):

```ts
export const LONG_EDGE = 1600;
export type ArchivalJob = { story_id: string; media_key: string; media_width: number; media_height: number };
export type RenditionTransform = { width?: number; height?: number; resize: "contain"; quality: 80; format: "origin" };
export function renditionTransform(width: number, height: number): RenditionTransform | null;
export function jpegDimensions(bytes: Uint8Array): { width: number; height: number } | null;
export function validateRendition(bytes: Uint8Array, contentType: string, job: ArchivalJob): string | null;
export type ArchivalOptions = { batch: number; concurrency: number; budgetMs: number; now?: () => number; log?: (line: string) => void };
export const ARCHIVAL_DEFAULTS: ArchivalOptions; // { batch: 20, concurrency: 4, budgetMs: 60_000 }
export type RunSummary = { claimed: number; processed: number; skipped: number; failed: number; codes: Record<string, number>; ms: number };
export function runArchival(supabase: any, options?: ArchivalOptions): Promise<RunSummary>;
export function timedFetch(ms: number, base?: typeof fetch): typeof fetch;
```

Decisions (ruling 5): transform `{width: 1600}` when width ≥ height, else `{height: 1600}`, `resize: "contain"`, `quality: 80`, `format: "origin"` (keeps JPEG; without it the transform may answer WebP). A rendition is swapped in only if it is non-empty, typed `image/jpeg` (or untyped), a whole JPEG (SOI … EOI) whose frame header gives a long edge in `[1, 1601]` and an aspect within 2% of the original's. Upload with `upsert: true`, so a stale object from an earlier, unvalidated attempt is replaced, never trusted. Logs: one JSON line per run with counts and error codes only (no ids, no keys).

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/process-story-archival/archival.test.ts
// Stories Wave 5 (04 #7, #8, #9; 06 #23): long-edge resize, a validated
// rendition before any swap, batches within a time budget, timeouts, logs.
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type ArchivalJob,
  jpegDimensions,
  renditionTransform,
  runArchival,
  timedFetch,
  validateRendition,
} from "./archival.ts";

/** A minimal, structurally whole JPEG: SOI, APP0, SOF0 (w x h), SOS, EOI. */
function fakeJpeg(width: number, height: number, { truncated = false } = {}): Uint8Array {
  const app0 = [0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00];
  const sof0 = [0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03,
    0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01];
  const sos = [0xff, 0xda, 0x00, 0x0c, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3f, 0x00, 0x12, 0x34];
  const bytes = [0xff, 0xd8, ...app0, ...sof0, ...sos, ...(truncated ? [] : [0xff, 0xd9])];
  return new Uint8Array(bytes);
}

const portrait: ArchivalJob = { story_id: "s1", media_key: "story-media/r/u/1-media", media_width: 1440, media_height: 2560 };

Deno.test("long edge: portrait by height, landscape and square by width, small left alone", () => {
  assertEquals(renditionTransform(1440, 2560), { height: 1600, resize: "contain", quality: 80, format: "origin" });
  assertEquals(renditionTransform(2560, 1440), { width: 1600, resize: "contain", quality: 80, format: "origin" });
  assertEquals(renditionTransform(2000, 2000), { width: 1600, resize: "contain", quality: 80, format: "origin" });
  assertEquals(renditionTransform(1080, 1600), null);
  assertEquals(renditionTransform(900, 1200), null);
});

Deno.test("jpegDimensions reads the frame header and refuses anything else", () => {
  assertEquals(jpegDimensions(fakeJpeg(900, 1600)), { width: 900, height: 1600 });
  assertEquals(jpegDimensions(fakeJpeg(900, 1600, { truncated: true })), null, "no EOI: truncated");
  assertEquals(jpegDimensions(new Uint8Array()), null);
  assertEquals(jpegDimensions(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), null, "PNG");
  assertEquals(jpegDimensions(new Uint8Array([0xff, 0xd8, 0xff, 0xd9])), null, "no frame header");
});

Deno.test("validateRendition: only a whole, right-sized, right-shaped JPEG passes", () => {
  assertEquals(validateRendition(fakeJpeg(900, 1600), "image/jpeg", portrait), null);
  assertEquals(validateRendition(fakeJpeg(900, 1600), "", portrait), null, "untyped but a JPEG");
  assertEquals(validateRendition(new Uint8Array(), "image/jpeg", portrait), "empty_rendition");
  assertEquals(validateRendition(fakeJpeg(900, 1600), "image/webp", portrait), "not_jpeg");
  assertEquals(validateRendition(fakeJpeg(900, 1600, { truncated: true }), "image/jpeg", portrait), "undecodable");
  assertEquals(validateRendition(fakeJpeg(1440, 2560), "image/jpeg", portrait), "wrong_size", "not downscaled");
  assertEquals(validateRendition(fakeJpeg(1600, 900), "image/jpeg", portrait), "wrong_aspect", "rotated");
  assertEquals(validateRendition(fakeJpeg(1200, 1600), "image/jpeg", portrait), "wrong_aspect", "stretched");
});

type Call = { fn: string; params: Record<string, unknown> };

// deno-lint-ignore no-explicit-any
function fakeClient(opts: { batches: ArchivalJob[][]; rendition?: (job: string) => { bytes: Uint8Array; type: string } | null }) {
  const calls: Call[] = [];
  const downloads: { key: string; transform: unknown }[] = [];
  const uploads: { key: string; size: number; upsert: boolean; contentType: string }[] = [];
  let inFlight = 0;
  let maxInFlight = 0;
  const batches = [...opts.batches];
  const client = {
    rpc: (fn: string, params: Record<string, unknown> = {}) => {
      calls.push({ fn, params });
      if (fn === "claim_story_archival_batch") return Promise.resolve({ data: batches.shift() ?? [], error: null });
      if (fn === "story_archive_key") return Promise.resolve({ data: `story-archive/${params.p_story_item_id}.jpg`, error: null });
      if (fn === "complete_story_archival") return Promise.resolve({ data: { error: false, swapped: true }, error: null });
      return Promise.resolve({ data: { error: false }, error: null });
    },
    storage: {
      from: (_bucket: string) => ({
        download: async (key: string, o: { transform: unknown }) => {
          downloads.push({ key, transform: o?.transform });
          inFlight++;
          maxInFlight = Math.max(maxInFlight, inFlight);
          await new Promise((r) => setTimeout(r, 1));
          inFlight--;
          const r = opts.rendition ? opts.rendition(key) : { bytes: fakeJpeg(900, 1600), type: "image/jpeg" };
          if (!r) return { data: null, error: { status: 500, message: "transform failed" } };
          return { data: new Blob([r.bytes as BlobPart], { type: r.type }), error: null };
        },
        upload: (key: string, body: Uint8Array, o: { upsert: boolean; contentType: string }) => {
          uploads.push({ key, size: body.byteLength, upsert: o.upsert, contentType: o.contentType });
          return Promise.resolve({ error: null });
        },
      }),
    },
  };
  return { client, calls, downloads, uploads, maxInFlight: () => maxInFlight };
}

const job = (id: string, w = 1440, h = 2560): ArchivalJob => ({ story_id: id, media_key: `story-media/r/u/${id}-media`, media_width: w, media_height: h });
const quiet = { batch: 20, concurrency: 4, budgetMs: 60_000, log: () => {} };

Deno.test("a portrait story: height-1600 transform, validated upload (upsert), then the swap", async () => {
  const f = fakeClient({ batches: [[job("s1")]] });
  const s = await runArchival(f.client, quiet);
  assertEquals(f.downloads[0].transform, { height: 1600, resize: "contain", quality: 80, format: "origin" });
  assertEquals(f.uploads, [{ key: "story-archive/s1.jpg", size: fakeJpeg(900, 1600).byteLength, upsert: true, contentType: "image/jpeg" }]);
  const order = f.calls.map((c) => c.fn).filter((fn) => fn !== "claim_story_archival_batch");
  assertEquals(order, ["story_archive_key", "complete_story_archival"]);
  assertEquals([s.processed, s.failed, s.skipped], [1, 0, 0]);
});

Deno.test("a small image is skipped: no download, no upload, no swap", async () => {
  const f = fakeClient({ batches: [[job("s2", 1080, 1600)]] });
  const s = await runArchival(f.client, quiet);
  assertEquals(f.downloads.length, 0);
  assertEquals(f.uploads.length, 0);
  assert(f.calls.some((c) => c.fn === "skip_story_archival" && c.params.p_story_id === "s2"));
  assert(!f.calls.some((c) => c.fn === "complete_story_archival"));
  assertEquals(s.skipped, 1);
});

Deno.test("an invalid rendition is never uploaded or swapped; the job fails with its code", async () => {
  for (const [bytes, type, code] of [
    [new Uint8Array(), "image/jpeg", "empty_rendition"],
    [fakeJpeg(900, 1600), "image/webp", "not_jpeg"],
    [fakeJpeg(900, 1600, { truncated: true }), "image/jpeg", "undecodable"],
    [fakeJpeg(1440, 2560), "image/jpeg", "wrong_size"],
  ] as const) {
    const f = fakeClient({ batches: [[job("s3")]], rendition: () => ({ bytes, type }) });
    const s = await runArchival(f.client, quiet);
    assertEquals(f.uploads.length, 0, code);
    assert(!f.calls.some((c) => c.fn === "complete_story_archival"), code);
    const fail = f.calls.find((c) => c.fn === "fail_story_archival")!;
    assertEquals(fail.params, { p_story_id: "s3", p_error_code: code });
    assertEquals(s.codes[code], 1);
  }
});

Deno.test("throughput: batches are claimed until a short one, at most 4 at a time", async () => {
  const many = Array.from({ length: 20 }, (_, i) => job(`a${i}`));
  const f = fakeClient({ batches: [many, [job("b1"), job("b2")]] });
  const s = await runArchival(f.client, quiet);
  assertEquals(f.calls.filter((c) => c.fn === "claim_story_archival_batch").length, 2);
  assertEquals(s.processed, 22);
  assert(f.maxInFlight() <= 4 && f.maxInFlight() > 1, `in flight ${f.maxInFlight()}`);
});

Deno.test("the time budget stops further claims (each claimed batch is finished)", async () => {
  let t = 0;
  const f = fakeClient({ batches: [[job("c1")], [job("c2")], [job("c3")]] });
  const s = await runArchival(f.client, {
    batch: 1, concurrency: 1, budgetMs: 100, log: () => {},
    now: () => (t += 60),
  });
  assert(s.claimed < 3, `claimed ${s.claimed}`);
  assertEquals(s.processed, s.claimed);
});

Deno.test("one log line per run: counts and codes, never an id or a key", async () => {
  const lines: string[] = [];
  const f = fakeClient({ batches: [[job("secret-story-id"), job("small", 800, 600)]] });
  await runArchival(f.client, { ...quiet, log: (l) => lines.push(l) });
  assertEquals(lines.length, 1);
  const parsed = JSON.parse(lines[0]);
  assertEquals(parsed.fn, "process-story-archival");
  assertEquals([parsed.processed, parsed.skipped], [1, 1]);
  assert(!lines[0].includes("secret-story-id") && !lines[0].includes("story-media/"), lines[0]);
});

Deno.test("timedFetch aborts a call that hangs", async () => {
  const hanging: typeof fetch = (_input, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(init.signal!.reason));
    });
  const started = Date.now();
  await assertRejects(() => timedFetch(30, hanging)("https://x.invalid/"));
  assert(Date.now() - started < 2000);
});

Deno.test("index.ts: service role first, background run, timed client", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const auth = src.indexOf("requireServiceRole(req)");
  const run = src.indexOf("runArchival(");
  assert(auth > -1 && run > auth, "auth before work");
  assert(src.includes("waitUntil"), "the cron's call returns at once");
  assert(src.includes("timedFetch("), "every Storage/RPC call is bounded");
});
```

- [ ] **Step 2: Run them to see them fail**

Run (from `supabase/functions`): `deno test --allow-read --allow-env --allow-net process-story-archival`
Expected: `Module not found "…/process-story-archival/archival.ts"`.

- [ ] **Step 3: Write `archival.ts`**

```ts
// deno-lint-ignore-file no-explicit-any
// supabase/functions/process-story-archival/archival.ts
//
// Stories Wave 5 (review 04 #7, #8, #9; 06 #23). The archival worker's logic,
// apart from Deno.serve so it can be tested with a fake client.
//
// Ordering is load-bearing (STORIES.md §4.4): make the new rendition, check
// it, store it at the deterministic archive key, THEN conditionally swap the
// key (complete_story_archival, which also queues the old key behind the
// signed-URL TTL). A rendition that fails any check is never stored or
// swapped; the job fails with a code and is retried (5 attempts, then dead
// letter), and the original stays.

export const LONG_EDGE = 1600;
const BUCKET = "story-media";

export type ArchivalJob = { story_id: string; media_key: string; media_width: number; media_height: number };
export type RenditionTransform = { width?: number; height?: number; resize: "contain"; quality: 80; format: "origin" };

/** The transform that brings the long edge to 1600 px, or null if it already is (04 #7). */
export function renditionTransform(width: number, height: number): RenditionTransform | null {
  if (Math.max(width, height) <= LONG_EDGE) return null;
  return width >= height
    ? { width: LONG_EDGE, resize: "contain", quality: 80, format: "origin" }
    : { height: LONG_EDGE, resize: "contain", quality: 80, format: "origin" };
}

/** Width and height from a whole JPEG's first frame header; null if it is not one. */
export function jpegDimensions(b: Uint8Array): { width: number; height: number } | null {
  if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return null;
  if (b[b.length - 2] !== 0xff || b[b.length - 1] !== 0xd9) return null; // truncated
  let i = 2;
  while (i + 3 < b.length) {
    if (b[i] !== 0xff) return null;
    const marker = b[i + 1];
    if (marker === 0xff) { i += 1; continue; } // fill byte
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) { i += 2; continue; }
    if (marker === 0xd9 || marker === 0xda) return null; // end, or scan before any frame header
    const length = (b[i + 2] << 8) | b[i + 3];
    if (length < 2) return null;
    const isFrame = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isFrame) {
      if (i + 8 >= b.length) return null;
      const height = (b[i + 5] << 8) | b[i + 6];
      const width = (b[i + 7] << 8) | b[i + 8];
      return width > 0 && height > 0 ? { width, height } : null;
    }
    i += 2 + length;
  }
  return null;
}

/** Null if [bytes] may replace the original of [job]; else why not (04 #8). */
export function validateRendition(bytes: Uint8Array, contentType: string, job: ArchivalJob): string | null {
  if (bytes.byteLength === 0) return "empty_rendition";
  const type = (contentType ?? "").toLowerCase();
  if (type !== "" && !type.startsWith("image/jpeg")) return "not_jpeg";
  const dims = jpegDimensions(bytes);
  if (!dims) return "undecodable";
  if (Math.max(dims.width, dims.height) > LONG_EDGE + 1) return "wrong_size";
  const want = job.media_width / job.media_height;
  const got = dims.width / dims.height;
  if (Math.abs(got - want) / want > 0.02) return "wrong_aspect";
  return null;
}

export type ArchivalOptions = {
  batch: number;
  concurrency: number;
  budgetMs: number;
  now?: () => number;
  log?: (line: string) => void;
};

/** Per run: claim for up to 60 s, 20 at a time, 4 in parallel (04 #9). */
export const ARCHIVAL_DEFAULTS: ArchivalOptions = { batch: 20, concurrency: 4, budgetMs: 60_000 };

export type RunSummary = {
  claimed: number;
  processed: number;
  skipped: number;
  failed: number;
  codes: Record<string, number>;
  ms: number;
};

class ArchivalError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

function codeOf(error: unknown): string {
  if (error instanceof ArchivalError) return error.code;
  if (error instanceof Error && error.name && error.name !== "Error") return error.name.slice(0, 60);
  return "unexpected";
}

type Outcome = { outcome: "processed" | "skipped" | "failed"; code?: string };

async function archiveOne(supabase: any, job: ArchivalJob): Promise<Outcome> {
  const storyId = String(job.story_id);
  try {
    const transform = renditionTransform(Number(job.media_width), Number(job.media_height));
    if (!transform) {
      const { error } = await supabase.rpc("skip_story_archival", { p_story_id: storyId });
      if (error) throw new ArchivalError("skip_failed");
      return { outcome: "skipped", code: "already_small" };
    }
    // The archive key comes from the same SQL function complete and delete use.
    const { data: keyResult, error: keyError } = await supabase.rpc("story_archive_key", { p_story_item_id: storyId });
    if (keyError) throw new ArchivalError("key_failed");
    const archiveKey = String(keyResult);

    const { data: image, error: downloadError } = await supabase.storage
      .from(BUCKET)
      .download(String(job.media_key), { transform });
    if (downloadError || !image) throw new ArchivalError("download_failed");
    const bytes = new Uint8Array(await image.arrayBuffer());
    const invalid = validateRendition(bytes, image.type ?? "", job);
    if (invalid) throw new ArchivalError(invalid);

    // upsert: an object left by an earlier attempt was never validated.
    const upload = await supabase.storage.from(BUCKET).upload(archiveKey, bytes, {
      contentType: "image/jpeg",
      upsert: true,
    });
    if (upload.error) throw new ArchivalError("upload_failed");

    const { data: completion, error: completeError } = await supabase.rpc("complete_story_archival", {
      p_story_id: storyId,
      p_new_key: archiveKey,
    });
    if (completeError) throw new ArchivalError("complete_failed");
    if (completion && typeof completion === "object" && (completion as Record<string, unknown>).error === true) {
      throw new ArchivalError(String((completion as Record<string, unknown>).code ?? "complete_failed"));
    }
    return { outcome: "processed" };
  } catch (error) {
    const code = codeOf(error);
    const { error: failError } = await supabase.rpc("fail_story_archival", { p_story_id: storyId, p_error_code: code });
    // A failure to record the failure is surfaced, not swallowed.
    if (failError) throw new ArchivalError("fail_record_failed");
    return { outcome: "failed", code };
  }
}

/** Claims and archives until a short batch or the time budget; one log line. */
export async function runArchival(supabase: any, options: ArchivalOptions = ARCHIVAL_DEFAULTS): Promise<RunSummary> {
  const now = options.now ?? Date.now;
  const started = now();
  const summary: RunSummary = { claimed: 0, processed: 0, skipped: 0, failed: 0, codes: {}, ms: 0 };
  while (now() - started < options.budgetMs) {
    const { data, error } = await supabase.rpc("claim_story_archival_batch", { p_limit: options.batch });
    if (error) throw new ArchivalError("claim_failed");
    const jobs = (data ?? []) as ArchivalJob[];
    if (jobs.length === 0) break;
    summary.claimed += jobs.length;
    for (let i = 0; i < jobs.length; i += options.concurrency) {
      const results = await Promise.all(jobs.slice(i, i + options.concurrency).map((job) => archiveOne(supabase, job)));
      for (const r of results) {
        summary[r.outcome] += 1;
        if (r.code) summary.codes[r.code] = (summary.codes[r.code] ?? 0) + 1;
      }
    }
    if (jobs.length < options.batch) break;
  }
  summary.ms = now() - started;
  (options.log ?? console.log)(JSON.stringify({ fn: "process-story-archival", ...summary }));
  return summary;
}

/** A fetch that gives up after [ms] (06 #23): a hung transform no longer holds the run. */
export function timedFetch(ms: number, base: typeof fetch = fetch): typeof fetch {
  return (input, init) => {
    const timeout = AbortSignal.timeout(ms);
    const signal = init?.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
    return base(input, { ...init, signal });
  };
}
```

- [ ] **Step 4: Rewrite `index.ts`**

```ts
// supabase/functions/process-story-archival/index.ts
//
// The story archival worker (STORIES.md §4.4): every 5 minutes while work
// waits (20261024100600), service role only. Downsizes expired photo
// stories to a 1600 px long edge, checks each rendition before the swap,
// and logs one line of counts per run. The logic is in archival.ts.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { jsonResponse, requireEnv, requireServiceRole } from "../_shared/attune_auth.ts";
import { ARCHIVAL_DEFAULTS, runArchival, timedFetch } from "./archival.ts";

serve((req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
  } catch {
    return jsonResponse({ success: false, error: "Forbidden" }, 403);
  }
  const supabase = createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
    // 20 s per Storage or RPC call (06 #23).
    global: { fetch: timedFetch(20_000) },
  });
  const work = runArchival(supabase, ARCHIVAL_DEFAULTS).catch((error) =>
    console.error(JSON.stringify({ fn: "process-story-archival", error: error instanceof Error ? error.message : typeof error }))
  );
  // pg_net's call returns at once; the run continues in the background, as
  // build-data-exports does.
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(work);
    return jsonResponse({ accepted: true }, 202);
  }
  return work.then(() => jsonResponse({ ok: true }));
});
```

(`error.message` here is only ever an `ArchivalError` code or a platform error name: no ids or keys reach it.)

- [ ] **Step 5: Run the tests to see them pass**

Run: `deno test --allow-read --allow-env --allow-net process-story-archival` → all pass.
Run: `deno check process-story-archival/index.ts` → clean (`AbortSignal.any` needs a recent runtime; Deno 2.8 has it, and so does the Supabase edge runtime).
Re-run the Task 2 baseline loop: unchanged except the new directory now reports its passes.

- [ ] **Step 6: Checkpoint**

No commit. For the handoff: deploy `process-story-archival` after migration `20261024100600`, and check in the function logs that each run prints one `{"fn":"process-story-archival",…}` line (device/staging check).

---
### Task 11: Stories come first in the export, with real extensions; pins last until the window closes (04 #1, #12, #19; 07b V8/G8)

**Files:**
- Create: `supabase/migrations/20261024100700_story_export_order.sql`
- Create: `supabase/migrations/20261024100710_story_places_keep_until_archive.sql`
- Create: `supabase/tests/story_export_contracts.sql`
- Modify: `supabase/tests/story_places_contracts.sql` (P12) and `supabase/tests/sync_fixes_contracts.sql` (the "C-2 again" check): both pin "pins go at an ending", which ruling 7 changes.

**Interfaces:**
- Produces:
  - `public.export_media_rank(p_bucket text) RETURNS int` (IMMUTABLE; `story-media` → 0, else 1) and `public.export_story_file_name(p_media_key text, p_media_type text) RETURNS text` (IMMUTABLE; `my_stories/<16 hex of md5(key)>.mp4` for video, `.jpg` otherwise). Neither is client-executable.
  - `export_media_manifest(uuid, uuid[], text, text, integer)` same signature and columns; rows ordered `(export_media_rank(bucket), bucket, object_name)`; the cursor stays `(p_after_bucket, p_after_name)`. Story rows' `zip_path` = `'media/' || export_story_file_name(...)`.
  - `export_relationship(uuid, uuid)`: `my_stories[].media_file` uses the same name, so data.json and the ZIP agree.
  - `data_export_jobs.media_order smallint NOT NULL` (1 = the old walk, 2 = stories first; new rows default 2).
  - `public.export_restart_old_order_jobs() RETURNS int` (service role only): fails every queued/building job that is part-way through the media walk in the old order (`error = 'restarted'`, parts dropped), queues a fresh job for the same person and relationships, and marks the rest of the in-flight old-order jobs order 2. Idempotent. Called once by the migration.
  - `presence_purge_on_relationship_close()` deletes story pins only at **archive** (status `archived`, or `chat_archived_at` newly set); live presence still goes at any non-active status.
- Consumed by: Task 12 (the README counts `my_stories`; the left-out note recognises `media/my_stories/`).

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/story_export_contracts.sql
--
-- Stories Wave 5, Task 11 (review 04 #1, #12, #19; 07b V8): a person's own
-- stories come first in the media walk, so the part cap can no longer leave
-- them out behind chat media; every story file has an extension; a job that
-- was mid-walk at deploy starts again; place pins survive the ending until
-- the export window closes, unreadable to both.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000933a1'), ('00000000-0000-0000-0000-0000000933b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000933a1', '+15550933001', 'Esi'),
  ('00000000-0000-0000-0000-0000000933b2', '+15550933002', 'Yaw')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1', '00000000-0000-0000-0000-0000000933b2',
   'active', CURRENT_DATE - 100, now() - interval '100 days', now());

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

SET LOCAL session_replication_role = replica;
-- Esi: a video story and a fresh photo story (keys end in -media), an
-- archived photo (story-archive/<id>.jpg), and two chat photos whose bucket
-- sorts first by name.
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, duration_ms, occurred_on, created_at, expires_at)
VALUES
  ('00000000-0000-0000-0000-000000933001', gen_random_uuid(), '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1',
   'video', 'story-media/e933/v-media', 'story-media/e933/v-thumbnail', 1080, 1920, 5000, CURRENT_DATE, now(), now() + interval '24 hours'),
  ('00000000-0000-0000-0000-000000933002', gen_random_uuid(), '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1',
   'image', 'story-media/e933/p-media', 'story-media/e933/p-thumbnail', 1080, 1920, NULL, CURRENT_DATE, now(), now() + interval '24 hours'),
  ('00000000-0000-0000-0000-000000933003', gen_random_uuid(), '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1',
   'image', 'story-archive/00000000-0000-0000-0000-000000933003.jpg', 'story-media/e933/a-thumbnail', 1080, 1920, NULL,
   CURRENT_DATE - 5, now() - interval '5 days', now() - interval '4 days');
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, created_at, media_url, media_type, is_view_once)
VALUES
  ('00000000-0000-0000-0000-000000933101', '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1',
   gen_random_uuid(), NULL, now() - interval '2 days', 'chat-media/e933-1.jpg', 'image', false),
  ('00000000-0000-0000-0000-000000933102', '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933b2',
   gen_random_uuid(), NULL, now() - interval '1 day', 'chat-media/e933-2.jpg', 'image', false);
INSERT INTO public.story_places (story_item_id, relationship_id, author_id, lat, lng, label)
VALUES ('00000000-0000-0000-0000-000000933002', '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1', 5.6, -0.18, 'Osu');
SET LOCAL session_replication_role = origin;

-- E1. Story file names carry the right extension.
DO $$
BEGIN
  IF public.export_story_file_name('story-media/r/u/abc-media', 'video') !~ '^my_stories/[0-9a-f]{16}\.mp4$'
     OR public.export_story_file_name('story-media/r/u/abc-media', 'image') !~ '^my_stories/[0-9a-f]{16}\.jpg$'
     OR public.export_story_file_name('story-archive/x.jpg', 'image') !~ '^my_stories/[0-9a-f]{16}\.jpg$' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story file names are %, %, %',
      public.export_story_file_name('story-media/r/u/abc-media', 'video'),
      public.export_story_file_name('story-media/r/u/abc-media', 'image'),
      public.export_story_file_name('story-archive/x.jpg', 'image');
  END IF;
END $$;

-- E2. data.json and the ZIP name each story's file the same way.
DO $$
DECLARE v_json text[]; v_zip text[];
BEGIN
  SELECT array_agg(x->>'media_file' ORDER BY x->>'media_file') INTO v_json
    FROM jsonb_array_elements(public.export_relationship('00000000-0000-0000-0000-0000000933a1',
                                                         '00000000-0000-0000-0000-0000000933e1')->'my_stories') x;
  SELECT array_agg(m.zip_path ORDER BY m.zip_path) INTO v_zip
    FROM public.export_media_manifest('00000000-0000-0000-0000-0000000933a1') m WHERE m.bucket = 'story-media';
  IF v_json IS DISTINCT FROM v_zip OR cardinality(v_zip) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: data.json names % but the ZIP holds %', v_json, v_zip;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM unnest(v_zip) z WHERE z LIKE 'media/my_stories/%.mp4') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the video story has no .mp4: %', v_zip;
  END IF;
END $$;

-- E3. Stories first, and the cursor walks every file exactly once, in order.
DO $$
DECLARE v record; v_ranks int[] := '{}'; v_seen text[] := '{}'; v_bucket text; v_name text; v_all int; v_guard int := 0;
BEGIN
  SELECT count(*) INTO v_all FROM public.export_media_manifest('00000000-0000-0000-0000-0000000933a1');
  LOOP
    SELECT * INTO v FROM public.export_media_manifest('00000000-0000-0000-0000-0000000933a1', NULL, v_bucket, v_name, 1);
    EXIT WHEN v.bucket IS NULL;
    v_guard := v_guard + 1;
    IF v_guard > v_all + 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the cursor loops'; END IF;
    IF (v.bucket || '/' || v.object_name) = ANY (v_seen) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % was walked twice', v.object_name;
    END IF;
    v_seen := v_seen || (v.bucket || '/' || v.object_name);
    v_ranks := v_ranks || public.export_media_rank(v.bucket);
    v_bucket := v.bucket; v_name := v.object_name;
  END LOOP;
  IF cardinality(v_seen) <> v_all OR v_all < 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: walked % of % files', cardinality(v_seen), v_all;
  END IF;
  IF v_ranks <> (SELECT array_agg(r ORDER BY r) FROM unnest(v_ranks) r) OR v_ranks[1] <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stories are not walked first: %', v_ranks;
  END IF;
END $$;

-- E4. A job walking media in the old order at deploy is replaced; others are re-labelled.
DO $$
DECLARE v_mid uuid; v_chat uuid; v_done uuid; v_new record; v_n int;
BEGIN
  INSERT INTO public.data_export_jobs (user_id, status, phase, relationship_ids, media_after_bucket, media_after_name,
                                       storage_keys, media_order, requested_at)
  VALUES ('00000000-0000-0000-0000-0000000933a1', 'queued', 'media', ARRAY['00000000-0000-0000-0000-0000000933e1']::uuid[],
          'message-media', 'chat-media/e933-1.jpg', '{}', 1, now() - interval '1 hour')
  RETURNING id INTO v_mid;
  INSERT INTO public.media_deletion_queue (bucket_id, object_name, not_before)
  VALUES ('data-exports', v_mid::text || '/attune-export-1.zip', now() + interval '1 day');
  UPDATE public.data_export_jobs SET storage_keys = ARRAY[v_mid::text || '/attune-export-1.zip'] WHERE id = v_mid;
  INSERT INTO public.data_export_jobs (user_id, status, phase, media_order, requested_at)
  VALUES ('00000000-0000-0000-0000-0000000933b2', 'queued', 'chat', 1, now() - interval '30 minutes') RETURNING id INTO v_chat;
  INSERT INTO public.data_export_jobs (user_id, status, phase, media_order, requested_at, ready_at, expires_at)
  VALUES ('00000000-0000-0000-0000-0000000933b2', 'ready', 'done', 1, now() - interval '3 days', now() - interval '3 days', now() + interval '4 days')
  RETURNING id INTO v_done;

  v_n := public.export_restart_old_order_jobs();
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % jobs restarted (want 1)', v_n; END IF;
  IF (SELECT status || '/' || coalesce(error, '') FROM public.data_export_jobs WHERE id = v_mid) <> 'failed/restarted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the mid-walk job is %', (SELECT status FROM public.data_export_jobs WHERE id = v_mid);
  END IF;
  IF (SELECT not_before FROM public.media_deletion_queue WHERE object_name = v_mid::text || '/attune-export-1.zip') > now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restarted job''s part is kept';
  END IF;
  SELECT * INTO v_new FROM public.data_export_jobs
   WHERE user_id = '00000000-0000-0000-0000-0000000933a1' AND id <> v_mid ORDER BY requested_at DESC LIMIT 1;
  IF v_new.id IS NULL OR v_new.status <> 'queued' OR v_new.phase <> 'data' OR v_new.media_order <> 2
     OR v_new.relationship_ids IS DISTINCT FROM ARRAY['00000000-0000-0000-0000-0000000933e1']::uuid[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the replacement job is %', row_to_json(v_new);
  END IF;
  IF (SELECT media_order FROM public.data_export_jobs WHERE id = v_chat) <> 2
     OR (SELECT status FROM public.data_export_jobs WHERE id = v_chat) <> 'queued' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job still in chat was not simply re-labelled';
  END IF;
  IF (SELECT media_order FROM public.data_export_jobs WHERE id = v_done) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a finished job was touched';
  END IF;
  IF public.export_restart_old_order_jobs() <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restart is not idempotent';
  END IF;
  IF (SELECT column_default FROM information_schema.columns WHERE table_schema = 'public'
        AND table_name = 'data_export_jobs' AND column_name = 'media_order') NOT LIKE '2%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new jobs do not default to the stories-first walk';
  END IF;
END $$;

-- E5. Pins survive the ending, unreadable to both and exported to the author; archive purges them.
DO $$
DECLARE v_n int; v_place jsonb;
BEGIN
  UPDATE public.relationships SET status = 'ended', ended_at = now() WHERE id = '00000000-0000-0000-0000-0000000933e1';
  IF NOT EXISTS (SELECT 1 FROM public.story_places WHERE story_item_id = '00000000-0000-0000-0000-000000933002') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ending dropped the pins before the export window closed (04 #19)';
  END IF;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000933a1');
  SELECT count(*) INTO v_n FROM public.story_places WHERE relationship_id = '00000000-0000-0000-0000-0000000933e1';
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the author reads % pins after the ending', v_n; END IF;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000933b2');
  SELECT count(*) INTO v_n FROM public.story_places WHERE relationship_id = '00000000-0000-0000-0000-0000000933e1';
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner reads % pins after the ending', v_n; END IF;
  SELECT x->'place' INTO v_place
    FROM jsonb_array_elements(public.export_relationship('00000000-0000-0000-0000-0000000933a1',
                                                         '00000000-0000-0000-0000-0000000933e1')->'my_stories') x
   WHERE x->>'type' = 'image' AND x->>'on' = CURRENT_DATE::text;
  IF v_place->>'label' IS DISTINCT FROM 'Osu' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ending author''s export lost the place: %', v_place;
  END IF;
  UPDATE public.relationships SET status = 'archived', chat_archived_at = now(), chat_archived_reason = 'window_closed'
   WHERE id = '00000000-0000-0000-0000-0000000933e1';
  IF EXISTS (SELECT 1 FROM public.story_places WHERE relationship_id = '00000000-0000-0000-0000-0000000933e1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: archiving kept the pins';
  END IF;
END $$;

-- E6. The new helpers are not client functions.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.export_media_rank(text)', 'public.export_story_file_name(text,text)',
                              'public.export_restart_old_order_jobs()'] LOOP
    IF has_function_privilege('authenticated', v_fn, 'EXECUTE') OR has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can execute %', v_fn;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
```

Notes before running: the `messages` insert copies `data_export_contracts.sql`'s column set; if the schema needs more NOT NULL columns, copy them from that file's message fixture. If the direct `UPDATE … status = 'ended'` is refused by a lifecycle trigger, end it as `sync_fixes_contracts.sql` does (`pg_temp.as_user(<Esi>); PERFORM public.end_relationship(<rel>); RESET ROLE;`) and archive with `UPDATE … SET status = 'archived', chat_archived_at = now()` as `data_export_contracts.sql` does.

- [ ] **Step 2: Run it to see it fail**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_export_contracts.sql`
Expected: E1 fails with `ERROR:  function public.export_story_file_name(unknown, unknown) does not exist`.

- [ ] **Step 3: Write the export migration**

Build it in three parts.

(a) Header, helpers, column and restart function:

```sql
-- supabase/migrations/20261024100700_story_export_order.sql
--
-- Stories Wave 5 (review 04 #1, #12; 07b V8/G8):
--   * The media walk sorted by bucket name, so story-media came after
--     journal, message and planning media, behind a 12-part cap. Stories are
--     the one class with no copy on the phone, and after an ending export is
--     their only way out. They now come first: the walk is ordered by
--     (export_media_rank(bucket), bucket, name). The rank is a function of the
--     bucket, so the job's (bucket, name) cursor still marks a unique place.
--   * Story videos and photos under 24 hours had no extension (keys end in
--     -media). Their names now come from media_type: .mp4 or .jpg, in
--     data.json and in the ZIP alike.
--   * A job already part-way through the media walk in the old order would
--     skip every story under the new one. Such jobs are replaced by a fresh
--     job (the old one fails 'restarted' and its parts are dropped); jobs not
--     yet in the media walk are re-labelled. data_export_jobs.media_order
--     records which walk a job uses, which keeps this idempotent.
-- One transaction, so no job is claimed between the new order and the restart.
BEGIN;

CREATE OR REPLACE FUNCTION public.export_media_rank(p_bucket text)
RETURNS int LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE WHEN p_bucket = 'story-media' THEN 0 ELSE 1 END;
$$;

CREATE OR REPLACE FUNCTION public.export_story_file_name(p_media_key text, p_media_type text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT 'my_stories/' || left(md5(p_media_key), 16)
         || CASE WHEN p_media_type = 'video' THEN '.mp4' ELSE '.jpg' END;
$$;

REVOKE ALL ON FUNCTION public.export_media_rank(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_story_file_name(text, text) FROM PUBLIC, anon, authenticated;

ALTER TABLE public.data_export_jobs ADD COLUMN IF NOT EXISTS media_order smallint NOT NULL DEFAULT 1;
ALTER TABLE public.data_export_jobs ALTER COLUMN media_order SET DEFAULT 2;
```

(b) `export_relationship`: copy lines 25–230 of `supabase/migrations/20261018120000_data_export.sql` (from `CREATE OR REPLACE FUNCTION public.export_relationship(p_user_id uuid, p_relationship_id uuid)` to its closing `$$;`) verbatim, then change exactly one line, the `my_stories` `media_file`:

```sql
        'media_file', 'media/' || public.export_story_file_name(s.media_key, s.media_type),
```

(was `'media_file', 'media/' || public.export_file_name('my_stories', s.media_key),`). Prove nothing else moved:

```bash
diff <(sed -n '25,230p' supabase/migrations/20261018120000_data_export.sql) \
     <(sed -n '/^CREATE OR REPLACE FUNCTION public.export_relationship/,/^\$\$;/p' supabase/migrations/20261024100700_story_export_order.sql)
```

Expected: exactly one changed line (the `media_file` one). `grep -n "export_relationship" supabase/migrations/*.sql` must show no later redefinition than `20261018120000` before this file (checked 2026-10-24: none).

(c) The manifest, the restart and the end of the transaction:

```sql
CREATE OR REPLACE FUNCTION public.export_media_manifest(
  p_user_id uuid, p_relationship_ids uuid[] DEFAULT NULL,
  p_after_bucket text DEFAULT NULL, p_after_name text DEFAULT NULL, p_limit integer DEFAULT NULL
)
RETURNS TABLE (bucket text, object_name text, zip_path text, size_bytes bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH rels AS (
    SELECT r.id
    FROM unnest(coalesce(p_relationship_ids, public.export_open_relationships(p_user_id))) AS x(id)
    JOIN public.relationships r ON r.id = x.id AND p_user_id IN (r.user_a, r.user_b)
  ),
  wanted (bucket, object_name, zip_path) AS (
    SELECT 'message-media', m.media_url, 'media/' || public.export_file_name('chat', m.media_url)
    FROM public.messages m JOIN rels ON rels.id = m.relationship_id
    WHERE m.media_url IS NOT NULL AND m.deleted_at IS NULL AND NOT m.is_view_once
      AND m.media_type IN ('image', 'audio', 'video')
    UNION ALL
    SELECT 'story-media', s.media_key, 'media/' || public.export_story_file_name(s.media_key, s.media_type)
    FROM public.story_items s JOIN rels ON rels.id = s.relationship_id
    WHERE s.author_id = p_user_id AND s.deleted_at IS NULL AND s.media_key IS NOT NULL
    UNION ALL
    SELECT 'planning-media', x.path, 'media/' || public.export_file_name('planning', x.path)
    FROM public.planning_blocks b
    JOIN rels ON rels.id = b.relationship_id
    JOIN public.planning_entries e ON e.id = b.entry_id AND e.deleted_at IS NULL AND NOT e.is_template
    CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(b.payload->'paths', '[]'::jsonb)) AS x(path)
    WHERE b.block_type = 'photo' AND b.deleted_at IS NULL
    UNION ALL
    SELECT 'journal-media', b.payload->>'path', 'media/' || public.export_file_name('journal', b.payload->>'path')
    FROM public.reflection_journal_blocks b
    JOIN public.reflection_journal_entries e ON e.id = b.entry_id AND e.deleted_at IS NULL
    WHERE b.user_id = p_user_id AND b.kind = 'photo' AND b.payload->>'path' IS NOT NULL
  )
  -- Stories first (Wave 5); sizes from storage, so the worker can plan the
  -- download before fetching.
  SELECT d.bucket, d.object_name, d.zip_path, d.size_bytes FROM (
    SELECT DISTINCT ON (w.bucket, w.object_name) w.bucket, w.object_name, w.zip_path,
           nullif(o.metadata->>'size', '')::bigint AS size_bytes
    FROM wanted w
    LEFT JOIN storage.objects o ON o.bucket_id = w.bucket AND o.name = w.object_name
    WHERE p_after_bucket IS NULL
       OR (public.export_media_rank(w.bucket), w.bucket, w.object_name)
          > (public.export_media_rank(p_after_bucket), p_after_bucket, p_after_name)
    ORDER BY w.bucket, w.object_name
  ) d
  ORDER BY public.export_media_rank(d.bucket), d.bucket, d.object_name
  LIMIT p_limit;
$$;

-- Jobs mid-way through the old walk start again; others take the new walk.
CREATE OR REPLACE FUNCTION public.export_restart_old_order_jobs()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v record;
  v_n int := 0;
BEGIN
  FOR v IN
    SELECT j.id, j.user_id, j.relationship_ids
      FROM public.data_export_jobs j
     WHERE j.media_order = 1
       AND j.status IN ('queued', 'building')
       AND j.phase = 'media'
       AND j.media_after_bucket IS NOT NULL
     ORDER BY j.requested_at
       FOR UPDATE
  LOOP
    UPDATE public.data_export_jobs SET status = 'failed', error = 'restarted' WHERE id = v.id;
    PERFORM public.export_drop_files(v.id);
    INSERT INTO public.data_export_jobs (user_id, relationship_ids, media_order)
    VALUES (v.user_id, v.relationship_ids, 2);
    v_n := v_n + 1;
  END LOOP;
  UPDATE public.data_export_jobs j SET media_order = 2
   WHERE j.media_order = 1 AND j.status IN ('queued', 'building');
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.export_restart_old_order_jobs() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.export_restart_old_order_jobs() TO service_role;

SELECT public.export_restart_old_order_jobs();

COMMIT;
```

`export_media_manifest` and `export_relationship` keep their signatures, so `CREATE OR REPLACE` keeps their grants (`20261018120100`: service role only). The worker's `export_finish_part` on a restarted job finds it no longer `building` and drops that part's file itself (its `NOT FOUND` branch).

- [ ] **Step 4: Write the pins migration**

```sql
-- supabase/migrations/20261024100710_story_places_keep_until_archive.sql
--
-- Stories Wave 5 (review 04 #19): story pins were deleted at an ending,
-- before the 30-day export window, so an ending author's exported stories
-- never carried their place. Pins now go at ARCHIVE (the window closing).
-- While ended they stay unreadable to both partners: story_places_read_members
-- still requires an open relationship. Live presence still goes at any
-- non-active status (it is live location). Restates 20261018160000 with
-- search_path pinned to ''. CREATE OR REPLACE keeps the trigger.
CREATE OR REPLACE FUNCTION public.presence_purge_on_relationship_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF (NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.partner_presence WHERE relationship_id = NEW.id;
  END IF;
  IF (NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'archived')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.story_places WHERE relationship_id = NEW.id;
  END IF;
  RETURN NULL;
END $$;
```

Check the function's grants survive: `sync_fixes_contracts`' M-15 block asserts clients cannot call it (unchanged by `CREATE OR REPLACE`).

- [ ] **Step 5: Update the two contracts that pin "pins go at an ending"**

`supabase/tests/story_places_contracts.sql`, block P12: replace the comment and body with

```sql
-- P12. An ending keeps the pins, unreadable, until the archive purges them
-- (Wave 5, 04 #19: the export window).
DO $$
DECLARE n int;
BEGIN
  PERFORM pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', '{"lat": 10, "lng": 10, "label": "Before"}');
  UPDATE public.relationships SET status = 'ended' WHERE id = '5c100000-0000-0000-0000-000000000001';
  SELECT count(*) INTO n FROM public.story_places WHERE relationship_id = '5c100000-0000-0000-0000-000000000001';
  IF n = 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the ending dropped the pins before the export window closed'; END IF;
  UPDATE public.relationships SET status = 'archived', chat_archived_at = now() WHERE id = '5c100000-0000-0000-0000-000000000001';
  SELECT count(*) INTO n FROM public.story_places WHERE relationship_id = '5c100000-0000-0000-0000-000000000001';
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % places survived the archive', n; END IF;
END $$;
```

`supabase/tests/sync_fixes_contracts.sql`: replace

```sql
  -- C-2 again: the ending clears the pins.
  IF EXISTS (SELECT 1 FROM public.story_places WHERE story_item_id = v_item) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ending kept the story pins';
  END IF;
```

with

```sql
  -- C-2, as amended by stories Wave 5 (04 #19): an ending keeps the pins
  -- (unreadable) until the archive; the archive purge is pinned in
  -- story_export_contracts.sql E5.
  IF NOT EXISTS (SELECT 1 FROM public.story_places WHERE story_item_id = v_item) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ending dropped the story pins before the export window closed';
  END IF;
```

- [ ] **Step 6: Apply and run**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100700_story_export_order.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100710_story_places_keep_until_archive.sql`
Expected: the first prints `export_restart_old_order_jobs` → `0` (no jobs in flight locally) and `COMMIT`.
Then: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_export_contracts.sql` → `ROLLBACK`, exit 0.
Then: `story_contracts && related_contracts` → all PASS. `data_export_contracts`' M5 cursor check (first row, then everything after it) holds under the new order.
Re-apply both migrations once more (idempotency): both succeed; the restart returns 0.

- [ ] **Step 7: Mutation check**

`mutate supabase/migrations/20261024100700_story_export_order.sql "s/ORDER BY public.export_media_rank(d.bucket), d.bucket, d.object_name/ORDER BY d.bucket, d.object_name/" supabase/tests/story_export_contracts.sql` → `CONTRACT VIOLATED: stories are not walked first` (or `walked twice`/`walked … of …`: the cursor and the order now disagree).

- [ ] **Step 8: Checkpoint**

No commit.

---

### Task 12: The export README and left-out note talk about stories (04 #1; 07b G8)

**Files:**
- Modify: `supabase/functions/build-data-exports/bundle.ts` (`readme`, `leftOutNote`)
- Modify: `supabase/functions/build-data-exports/bundle.test.ts`

**Interfaces:**
- Consumes: Task 11's file names (`media/my_stories/…`) and `bundle.relationships[].my_stories`.
- Produces: `readme(bundle)` lists `media/my_stories/` and the number of stories in the download, and says where the left-out count is; `leftOutNote(items)` starts with `"N of your stories are not in this download."` when any `media/my_stories/` file was left out.

Ruling 6: the README is written in part 1, before anything can be left out; the count is in `media_not_included.txt` in the last part.

- [ ] **Step 1: Write the failing tests**

Append to `bundle.test.ts`:

```ts
Deno.test("the README counts the stories and says where a shortfall is listed (Wave 5)", () => {
  const text = readme({ relationships: [{ my_stories: [{}, {}, {}] }, { my_stories: [{}] }] });
  assert(text.includes("media/my_stories/"), text);
  assert(text.includes("Your stories in this download: 4."), text);
  assert(text.includes("media_not_included.txt"), text);
  assert(readme({ relationships: [] }).includes("Your stories in this download: 0."));
});

Deno.test("the left-out note says how many stories did not fit (Wave 5)", () => {
  const note = leftOutNote([
    { file: "media/my_stories/a.mp4", reason: "over_limit" },
    { file: "media/my_stories/b.jpg", reason: "over_limit" },
    { file: "media/chat/c.jpg", reason: "over_limit" },
  ]);
  assert(note.startsWith("Some media is not in this download:\n\n2 of your stories are not in this download.\n"), note);
  assert(note.includes("3 files were over this download's size limit."), note);
  const one = leftOutNote([{ file: "media/my_stories/a.jpg", reason: "unavailable" }]);
  assert(one.includes("1 of your stories is not in this download."), one);
  const none = leftOutNote([{ file: "media/chat/c.jpg", reason: "too_large" }]);
  assert(!none.includes("your stories"), none);
});
```

- [ ] **Step 2: Run them to see them fail**

Run (from `supabase/functions`): `deno test --allow-read --allow-env --allow-net build-data-exports`
Expected: the two new tests fail (`assert` on the missing text); the other 20 pass.

- [ ] **Step 3: Implement**

In `bundle.ts`, `readme`:

```ts
// deno-lint-ignore no-explicit-any
export function readme(bundle: any): string {
  // deno-lint-ignore no-explicit-any
  const stories = (bundle.relationships ?? []).reduce((n: number, r: any) => n + (r?.my_stories?.length ?? 0), 0);
  return [
    "Your Attune download",
    "",
    "A copy of what's yours: your messages and the photos you shared, plans,",
    "calendar, stories, check-ins, journal, quiz answers, and the insights and",
    "readouts Attune showed you. Never anything about safety, never anyone's",
    "private items, and never the behind-the-scenes analysis of your chats.",
    "",
    "If it came in parts (attune-export-1.zip, attune-export-2.zip and so on),",
    "unzip them all into one folder.",
    "",
    "data.json                 everything as data",
    "calendar.ics              your calendar, to open in any calendar app",
    "relationship-N/chat/      your conversations, a page per file",
    "media/my_stories/         your stories, photos and videos",
    "media/                    the other photos, voice notes and videos",
    "",
    `Shared spaces in this download: ${(bundle.relationships ?? []).length}.`,
    `Your stories in this download: ${stories}. They come first among the media.`,
    "If anything didn't fit, media_not_included.txt (in the last part) says",
    "what, and how many of your stories were left out.",
  ].join("\n") + "\n";
}
```

`leftOutNote`, after `const lines = ["Some media is not in this download:", ""];`:

```ts
  const stories = items.filter((i) => i.file.startsWith("media/my_stories/")).length;
  if (stories) {
    lines.push(`${stories} of your stories ${stories === 1 ? "is" : "are"} not in this download.`);
  }
```

The README test from before (`"the README says what is inside…"`) still passes: its wording checks are unchanged.

- [ ] **Step 4: Run them to see them pass**

Run: `deno test --allow-read --allow-env --allow-net build-data-exports` → `22 passed | 0 failed`.

- [ ] **Step 5: Checkpoint**

No commit. Handoff: redeploy `build-data-exports` (it also carries Task 2's shared change).

---
### Task 13: After an ending, an author can list and delete their own stories: server (05 #3; spec §3.3)

**Files:**
- Create: `supabase/migrations/20261024100800_my_closed_story_items.sql`
- Create: `supabase/tests/story_after_ending_contracts.sql`

**Interfaces:**
- Produces (all `authenticated` only, SECURITY DEFINER, `search_path = ''`, author = `auth.uid()`, only relationships where `story_relationship_is_open(rel, me)` is false, i.e. paused, ended or archived):
  - `list_my_closed_story_chapters() RETURNS TABLE (relationship_id uuid, status text, ended_at timestamptz, story_count bigint, first_on date, last_on date)`, newest ending first.
  - `list_my_closed_story_items(p_relationship_id uuid, p_after_created_at timestamptz DEFAULT NULL, p_after_id uuid DEFAULT NULL, p_limit int DEFAULT 50) RETURNS TABLE (id uuid, media_type text, occurred_on date, created_at timestamptz)`, keyset `(created_at, id)` ascending, at most 50.
  - `delete_my_closed_story_items(p_relationship_id uuid) RETURNS jsonb`: deletes up to 200 of my live stories there through `delete_story_item` (same tombstone and three-key enqueue), returns `{"error": false, "deleted": n, "remaining": m}`; `UNAVAILABLE` on an open relationship; `UNAUTHORIZED` / `INVALID_INPUT` as usual. A relationship I am not in, or that does not exist, deletes 0 and leaves 0: no oracle.
  - Single deletes keep using `delete_story_item(uuid)`, which already works after an ending.
- Consumed by: Task 14.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/story_after_ending_contracts.sql
--
-- Stories Wave 5, Task 13 (review 05 #3; STORIES.md §3.3 "an author never
-- loses the right to remove their own retained media"): after an ending
-- the author can list and delete their own stories, and only their own.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000934a1'), ('00000000-0000-0000-0000-0000000934b2'),
  ('00000000-0000-0000-0000-0000000934c3'), ('00000000-0000-0000-0000-0000000934d4')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000934a1', '+15550934001', 'Ama'),
  ('00000000-0000-0000-0000-0000000934b2', '+15550934002', 'Kojo'),
  ('00000000-0000-0000-0000-0000000934c3', '+15550934003', 'Efua'),
  ('00000000-0000-0000-0000-0000000934d4', '+15550934004', 'Kwame')
ON CONFLICT (id) DO NOTHING;
-- R1: Ama and Kojo, ended. R2: Efua and Kwame, active (and Ama is not in it).
INSERT INTO public.relationships (id, user_a, user_b, status, ended_at) VALUES
  ('00000000-0000-0000-0000-0000000934e1', '00000000-0000-0000-0000-0000000934a1', '00000000-0000-0000-0000-0000000934b2', 'ended', now() - interval '3 days'),
  ('00000000-0000-0000-0000-0000000934e2', '00000000-0000-0000-0000-0000000934c3', '00000000-0000-0000-0000-0000000934d4', 'active', NULL);

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.story(p_rel uuid, p_author uuid, p_n int, p_days int) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.story_items (client_story_id, relationship_id, author_id, media_type, media_key,
    thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
  SELECT gen_random_uuid(), p_rel, p_author, CASE WHEN g % 3 = 0 THEN 'video' ELSE 'image' END,
         'story-media/' || p_rel || '/' || p_author || '/' || p_days || '-' || g || '-media',
         'story-media/' || p_rel || '/' || p_author || '/' || p_days || '-' || g || '-thumbnail', 100, 100,
         CURRENT_DATE - p_days, now() - make_interval(days => p_days, mins => g),
         now() - make_interval(days => p_days, mins => g) + interval '24 hours'
  FROM generate_series(1, p_n) g;
$$;

SET LOCAL session_replication_role = replica;  -- no outbox rows, no signals: fixtures only
SELECT pg_temp.story('00000000-0000-0000-0000-0000000934e1', '00000000-0000-0000-0000-0000000934a1', 3, 10);
SELECT pg_temp.story('00000000-0000-0000-0000-0000000934e1', '00000000-0000-0000-0000-0000000934b2', 2, 9);
SELECT pg_temp.story('00000000-0000-0000-0000-0000000934e2', '00000000-0000-0000-0000-0000000934c3', 2, 1);
-- Video rows need a duration (story_duration_matches_type).
UPDATE public.story_items SET duration_ms = 5000 WHERE media_type = 'video';
SET LOCAL session_replication_role = origin;

-- A1. Ama sees her one closed chapter and only her own stories in it.
DO $$
DECLARE v record; v_n int; v_ids uuid[];
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_chapters();
  SELECT * INTO v FROM public.list_my_closed_story_chapters();
  RESET ROLE;
  IF v_n <> 1 OR v.relationship_id <> '00000000-0000-0000-0000-0000000934e1' OR v.story_count <> 3
     OR v.status <> 'ended' OR v.ended_at IS NULL OR v.first_on <> CURRENT_DATE - 10 OR v.last_on <> CURRENT_DATE - 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ama''s chapters are % rows, first %', v_n, row_to_json(v);
  END IF;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT array_agg(i.id) INTO v_ids FROM public.list_my_closed_story_items('00000000-0000-0000-0000-0000000934e1') i;
  RESET ROLE;
  IF cardinality(v_ids) <> 3 OR EXISTS (SELECT 1 FROM public.story_items s WHERE s.id = ANY (v_ids)
                                         AND s.author_id <> '00000000-0000-0000-0000-0000000934a1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ama lists %', v_ids;
  END IF;
END $$;

-- A2. Paged by keyset.
DO $$
DECLARE v_first record; v_n int;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT * INTO v_first FROM public.list_my_closed_story_items('00000000-0000-0000-0000-0000000934e1', NULL, NULL, 1);
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_items('00000000-0000-0000-0000-0000000934e1', v_first.created_at, v_first.id, 50);
  RESET ROLE;
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the page after the first has % rows (want 2)', v_n; END IF;
END $$;

-- A3. An open space is not "past": nothing listed, delete refused.
DO $$
DECLARE v_n int; v_res jsonb;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934c3');
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_chapters();
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an open space is listed as past'; END IF;
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_items('00000000-0000-0000-0000-0000000934e2');
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an open space''s stories are listed here'; END IF;
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e2');
  RESET ROLE;
  IF v_res->>'code' IS DISTINCT FROM 'UNAVAILABLE'
     OR (SELECT count(*) FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000934e2' AND deleted_at IS NULL) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: delete-all on an open space: %', v_res;
  END IF;
END $$;

-- A4. Someone else's space, or one that does not exist: nothing, and the same answer.
DO $$
DECLARE v_res jsonb; v_res2 jsonb;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934c3');
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  v_res2 := public.delete_my_closed_story_items(gen_random_uuid());
  RESET ROLE;
  IF v_res IS DISTINCT FROM v_res2 OR (v_res->>'deleted')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider''s delete-all says % vs %', v_res, v_res2;
  END IF;
  IF (SELECT count(*) FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000934e1' AND deleted_at IS NULL) <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider deleted stories';
  END IF;
END $$;

-- A5. Ama deletes all of hers: tombstoned, three keys each queued, Kojo's untouched.
DO $$
DECLARE v_res jsonb; v_n int;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  RESET ROLE;
  IF (v_res->>'error') IS DISTINCT FROM 'false' OR (v_res->>'deleted')::int <> 3 OR (v_res->>'remaining')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: delete-all said %', v_res;
  END IF;
  SELECT count(*) INTO v_n FROM public.story_items
   WHERE relationship_id = '00000000-0000-0000-0000-0000000934e1' AND author_id = '00000000-0000-0000-0000-0000000934a1' AND deleted_at IS NULL;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % of Ama''s stories remain', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.media_deletion_queue q
   WHERE q.bucket_id = 'story-media' AND q.deleted_at IS NULL
     AND (q.object_name LIKE 'story-media/00000000-0000-0000-0000-0000000934e1/00000000-0000-0000-0000-0000000934a1/%'
          OR q.object_name IN (SELECT public.story_archive_key(s.id) FROM public.story_items s
                                WHERE s.author_id = '00000000-0000-0000-0000-0000000934a1'));
  IF v_n <> 9 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % of 9 objects queued for deletion', v_n; END IF;
  IF (SELECT count(*) FROM public.story_items WHERE author_id = '00000000-0000-0000-0000-0000000934b2' AND deleted_at IS NULL) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Kojo''s stories were touched';
  END IF;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_chapters();
  RESET ROLE;
  IF (v_res->>'deleted')::int <> 0 OR v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after deleting all, % deleted again and % chapters listed', v_res, v_n;
  END IF;
END $$;

-- A6. Big chapters go in batches of 200.
DO $$
DECLARE v_res jsonb;
BEGIN
  SET LOCAL session_replication_role = replica;
  PERFORM pg_temp.story('00000000-0000-0000-0000-0000000934e1', '00000000-0000-0000-0000-0000000934b2', 205, 20);
  UPDATE public.story_items SET duration_ms = 5000 WHERE media_type = 'video' AND duration_ms IS NULL;
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934b2');
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  IF (v_res->>'deleted')::int <> 200 OR (v_res->>'remaining')::int <> 7 THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: the first batch said % (want 200 deleted, 7 left)', v_res;
  END IF;
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  RESET ROLE;
  IF (v_res->>'deleted')::int <> 7 OR (v_res->>'remaining')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second batch said %', v_res;
  END IF;
END $$;

-- A7. Grants and search_path.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.list_my_closed_story_chapters()',
                              'public.list_my_closed_story_items(uuid,timestamptz,uuid,integer)',
                              'public.delete_my_closed_story_items(uuid)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % grants are wrong', v_fn;
    END IF;
    IF NOT (SELECT prosecdef AND 'search_path=""' = ANY (coalesce(proconfig, '{}')) FROM pg_proc WHERE oid = v_fn::regprocedure) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not a definer with search_path ''''', v_fn;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
```

(`media_deletion_queue` has a `deleted_at` stamp column per `20260938070000`; if its name differs, read `queue_story_media_deletion` and match it.)

- [ ] **Step 2: Run it to see it fail**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/story_after_ending_contracts.sql`
Expected: `ERROR:  function public.list_my_closed_story_chapters() does not exist`.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261024100800_my_closed_story_items.sql
--
-- Stories Wave 5 (review 05 #3; STORIES.md §3.3, §8): delete_story_item has
-- always let an author delete after an ending, but every reader requires an
-- open relationship, so after an ending nobody could find their own stories
-- to delete them. These three functions show an author their OWN stories in
-- spaces that are closed for stories (paused, ended, archived) and delete
-- them, in batches, through delete_story_item (same tombstone, same
-- three-key Storage enqueue). Dates and kinds only: Storage stays closed at
-- an ending, so there are no thumbnails. A space the caller is not in, or
-- that does not exist, lists nothing and deletes nothing.
CREATE OR REPLACE FUNCTION public.list_my_closed_story_chapters()
RETURNS TABLE (
  relationship_id uuid,
  status          text,
  ended_at        timestamptz,
  story_count     bigint,
  first_on        date,
  last_on         date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT r.id, r.status, r.ended_at, count(*), min(si.occurred_on), max(si.occurred_on)
    FROM public.story_items si
    JOIN public.relationships r ON r.id = si.relationship_id
   WHERE auth.uid() IS NOT NULL
     AND si.author_id = auth.uid()
     AND si.deleted_at IS NULL
     AND NOT public.story_relationship_is_open(r.id, auth.uid())
   GROUP BY r.id, r.status, r.ended_at
   ORDER BY r.ended_at DESC NULLS FIRST, r.id
$$;

CREATE OR REPLACE FUNCTION public.list_my_closed_story_items(
  p_relationship_id  uuid,
  p_after_created_at timestamptz DEFAULT NULL,
  p_after_id         uuid DEFAULT NULL,
  p_limit            int DEFAULT 50
)
RETURNS TABLE (
  id          uuid,
  media_type  text,
  occurred_on date,
  created_at  timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT si.id, si.media_type, si.occurred_on, si.created_at
    FROM public.story_items si
   WHERE auth.uid() IS NOT NULL
     AND si.relationship_id = p_relationship_id
     AND si.author_id = auth.uid()
     AND si.deleted_at IS NULL
     AND NOT public.story_relationship_is_open(p_relationship_id, auth.uid())
     AND (p_after_created_at IS NULL OR (si.created_at, si.id) > (p_after_created_at, p_after_id))
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

CREATE OR REPLACE FUNCTION public.delete_my_closed_story_items(p_relationship_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_id uuid;
  v_res jsonb;
  v_deleted int := 0;
  v_left bigint;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;
  IF p_relationship_id IS NULL THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;
  -- An open space's stories are deleted from the calendar, one by one.
  IF public.story_relationship_is_open(p_relationship_id, v_user) THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  FOR v_id IN
    SELECT si.id
      FROM public.story_items si
     WHERE si.relationship_id = p_relationship_id
       AND si.author_id = v_user
       AND si.deleted_at IS NULL
     ORDER BY si.created_at, si.id
     LIMIT 200
  LOOP
    v_res := public.delete_story_item(v_id);
    IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
      v_deleted := v_deleted + 1;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_left
    FROM public.story_items si
   WHERE si.relationship_id = p_relationship_id
     AND si.author_id = v_user
     AND si.deleted_at IS NULL;

  RETURN jsonb_build_object('error', false, 'deleted', v_deleted, 'remaining', v_left);
END;
$$;

REVOKE ALL ON FUNCTION public.list_my_closed_story_chapters() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_my_closed_story_items(uuid, timestamptz, uuid, int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_my_closed_story_items(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_closed_story_chapters() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_closed_story_items(uuid, timestamptz, uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_closed_story_items(uuid) TO authenticated;
```

`delete_story_item` still reads `auth.uid()` from the request's claims when called from inside this definer function, so its author check holds.

- [ ] **Step 4: Apply and run**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261024100800_my_closed_story_items.sql`
Then: the contract → `ROLLBACK`, exit 0. Then `story_contracts && related_contracts` → all PASS (`chapter_canary`'s "every new client function is gated" checks, if any, see the `NOT story_relationship_is_open` author-only gate).

- [ ] **Step 5: Mutation check**

`mutate supabase/migrations/20261024100800_my_closed_story_items.sql "s/     AND si.author_id = auth.uid()//" supabase/tests/story_after_ending_contracts.sql` → `CONTRACT VIOLATED: Ama's chapters are 2 rows, …` (another person's space shows up).
`mutate … "s/  IF public.story_relationship_is_open(p_relationship_id, v_user) THEN/  IF false THEN/" …` → `CONTRACT VIOLATED: delete-all on an open space`.

- [ ] **Step 6: Checkpoint**

No commit.

---

### Task 14: After an ending, an author can list and delete their own stories: Download my data entry and screen (05 #3)

**Files:**
- Create: `lib/features/stories/data/past_story_chapters_repository.dart`
- Create: `lib/features/stories/presentation/screens/past_chapter_stories_screen.dart`
- Modify: `lib/features/data_export/presentation/data_export_screen.dart` (one widget appended to the list)
- Create: `test/features/stories/past_chapter_stories_test.dart`

**Interfaces:**
- Consumes: Task 13's three RPCs and `delete_story_item`.
- Produces:

```dart
// past_story_chapters_repository.dart
class PastStoryChapter { String relationshipId; String status; DateTime? endedAt; int storyCount; DateTime firstOn; DateTime lastOn; bool get paused; factory PastStoryChapter.fromRow(Map<String, dynamic>); }
class PastStoryItem { String id; String mediaType; DateTime occurredOn; DateTime createdAt; bool get isVideo; factory PastStoryItem.fromRow(Map<String, dynamic>); }
abstract class PastStoryChaptersGateway {
  Future<List<PastStoryChapter>> listChapters();
  Future<List<PastStoryItem>> listItems(String relationshipId, {PastStoryItem? after, int limit = 50});
  Future<int> deleteAllOnce(String relationshipId); // returns how many remain
  Future<void> deleteOne(String storyItemId);
}
class SupabasePastStoryChaptersGateway implements PastStoryChaptersGateway { SupabasePastStoryChaptersGateway(SupabaseClient); }
final pastStoryChaptersGatewayProvider = Provider<PastStoryChaptersGateway>(...);
final pastStoryChaptersProvider = FutureProvider.autoDispose<List<PastStoryChapter>>(...);
final pastStoryItemsProvider = FutureProvider.autoDispose.family<List<PastStoryItem>, String>(...);
Future<void> deleteAllMyPastStories(PastStoryChaptersGateway gateway, String relationshipId);
String pastStoryChapterTitle(PastStoryChapter chapter);
// past_chapter_stories_screen.dart
class PastChapterStoriesEntry extends ConsumerWidget { const PastChapterStoriesEntry({super.key}); }
class PastChapterStoriesScreen extends ConsumerWidget { const PastChapterStoriesScreen({super.key}); }
```

UI: the entry renders nothing while loading, on error (including no Supabase in tests) or when there are no past stories, so Download my data looks exactly as before for most people. Copy is plain; dates go through `MyDateFormat`. Regression risk: `data_export_screen.dart` is shared with the export flow; the entry is appended after everything else and its tests pump the screen with the real export fake.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/stories/past_chapter_stories_test.dart
// Stories Wave 5 (05 #3): after an ending, an author finds their own stories
// on Download my data and can delete them, all at once or one by one.
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/data_export/data/data_export_service.dart';
import 'package:attune/features/data_export/presentation/data_export_screen.dart';
import 'package:attune/features/stories/data/past_story_chapters_repository.dart';
import 'package:attune/features/stories/presentation/screens/past_chapter_stories_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

final _ended = DateTime(2026, 9, 12);

class _Gateway implements PastStoryChaptersGateway {
  _Gateway(this.items);
  List<PastStoryItem> items;
  final deletedOne = <String>[];
  final remainingScript = <int>[];
  int deleteAllCalls = 0;

  @override
  Future<List<PastStoryChapter>> listChapters() async => items.isEmpty
      ? const []
      : [
          PastStoryChapter(
            relationshipId: 'r-old',
            status: 'ended',
            endedAt: _ended,
            storyCount: items.length,
            firstOn: items.first.occurredOn,
            lastOn: items.last.occurredOn,
          ),
        ];

  @override
  Future<List<PastStoryItem>> listItems(String relationshipId, {PastStoryItem? after, int limit = 50}) async =>
      after == null ? List.of(items) : const [];

  @override
  Future<int> deleteAllOnce(String relationshipId) async {
    deleteAllCalls++;
    final left = remainingScript.isEmpty ? 0 : remainingScript.removeAt(0);
    if (left == 0) items = [];
    return left;
  }

  @override
  Future<void> deleteOne(String storyItemId) async {
    deletedOne.add(storyItemId);
    items = items.where((i) => i.id != storyItemId).toList();
  }
}

PastStoryItem _item(String id, String type, DateTime on) =>
    PastStoryItem(id: id, mediaType: type, occurredOn: on, createdAt: on);

class _NoExport extends DataExportService {
  @override
  Future<DataExportStatus?> latest() async => null;
}

Future<void> _pump(WidgetTester t, Widget home, {PastStoryChaptersGateway? gateway}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        dataExportServiceProvider.overrideWithValue(_NoExport()),
        if (gateway != null) pastStoryChaptersGatewayProvider.overrideWithValue(gateway),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: home),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  final photo = _item('s1', 'image', DateTime(2026, 3, 1));
  final video = _item('s2', 'video', DateTime(2026, 8, 30));

  testWidgets('Download my data shows the entry only when there are past stories', (t) async {
    await _pump(t, DataExportScreen(confirmPin: (_) async => true), gateway: _Gateway([]));
    expect(find.text('Your stories from past chapters'), findsNothing);
    await _pump(t, DataExportScreen(confirmPin: (_) async => true), gateway: _Gateway([photo, video]));
    expect(find.text('Your stories from past chapters'), findsOneWidget);
    expect(find.text('2 stories only you can see and delete'), findsOneWidget);
  });

  testWidgets('with no backend the entry stays out of the way', (t) async {
    await _pump(t, DataExportScreen(confirmPin: (_) async => true));
    expect(find.text('Your stories from past chapters'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('the screen names the chapter and lists each story by date and kind', (t) async {
    await _pump(t, const PastChapterStoriesScreen(), gateway: _Gateway([photo, video]));
    expect(find.text(pastStoryChapterTitle(PastStoryChapter(
      relationshipId: 'r-old', status: 'ended', endedAt: _ended, storyCount: 2,
      firstOn: photo.occurredOn, lastOn: video.occurredOn))), findsOneWidget);
    expect(find.textContaining(MyDateFormat.toDate(_ended)), findsOneWidget);
    await t.tap(find.text('See them'));
    await t.pumpAndSettle();
    expect(find.text(MyDateFormat.join([MyDateFormat.toDate(photo.occurredOn), 'Photo'])), findsOneWidget);
    expect(find.text(MyDateFormat.join([MyDateFormat.toDate(video.occurredOn), 'Video'])), findsOneWidget);
  });

  testWidgets('Delete all asks first, then deletes in batches until none is left', (t) async {
    final g = _Gateway([photo, video])..remainingScript.addAll([1, 0]);
    await _pump(t, const PastChapterStoriesScreen(), gateway: g);
    await t.tap(find.text('Delete all 2'));
    await t.pumpAndSettle();
    expect(find.text('Delete these stories?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(g.deleteAllCalls, 0);
    await t.tap(find.text('Delete all 2'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(g.deleteAllCalls, 2);
    expect(find.text('Deleted.'), findsOneWidget);
    expect(find.text('Delete all 2'), findsNothing);
  });

  testWidgets('one story can be deleted on its own', (t) async {
    final g = _Gateway([photo, video]);
    await _pump(t, const PastChapterStoriesScreen(), gateway: g);
    await t.tap(find.text('See them'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Delete this story').first);
    await t.pumpAndSettle();
    expect(find.text('Delete this story?'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(g.deletedOne, ['s1']);
    expect(find.text(MyDateFormat.join([MyDateFormat.toDate(photo.occurredOn), 'Photo'])), findsNothing);
  });

  testWidgets('every control is a 48 dp target with a label', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, const PastChapterStoriesScreen(), gateway: _Gateway([photo]));
    await t.tap(find.text('See them'));
    await t.pumpAndSettle();
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

Before writing, read `lib/features/data_export/data/data_export_service.dart`: if `DataExportService` has a required constructor argument or `latest()` has a different signature, adapt `_NoExport` (it only needs `latest()` to answer `null`). If the confirmation dialog's buttons read differently from `'Cancel'` / the confirm text, use what `ConfirmationDialog` renders.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/stories/past_chapter_stories_test.dart`
Expected: compile errors (the two new files do not exist).

- [ ] **Step 3: Write the repository**

```dart
// lib/features/stories/data/past_story_chapters_repository.dart
/// After an ending (stories Wave 5, review 05 #3; STORIES.md §3.3): the
/// author's OWN stories in spaces that are closed for stories (paused,
/// ended or archived), and deleting them. Nobody else can read these.
/// Storage stays closed at an ending, so there are dates and kinds here,
/// never thumbnails.
library;

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class PastStoryChapter {
  const PastStoryChapter({
    required this.relationshipId,
    required this.status,
    required this.endedAt,
    required this.storyCount,
    required this.firstOn,
    required this.lastOn,
  });

  factory PastStoryChapter.fromRow(Map<String, dynamic> row) => PastStoryChapter(
    relationshipId: '${row['relationship_id']}',
    status: '${row['status']}',
    endedAt: row['ended_at'] == null ? null : DateTime.parse('${row['ended_at']}').toLocal(),
    storyCount: (row['story_count'] as num).toInt(),
    firstOn: DateTime.parse('${row['first_on']}'),
    lastOn: DateTime.parse('${row['last_on']}'),
  );

  final String relationshipId;
  final String status;
  final DateTime? endedAt;
  final int storyCount;
  final DateTime firstOn;
  final DateTime lastOn;

  bool get paused => status == 'paused';
}

@immutable
class PastStoryItem {
  const PastStoryItem({
    required this.id,
    required this.mediaType,
    required this.occurredOn,
    required this.createdAt,
  });

  factory PastStoryItem.fromRow(Map<String, dynamic> row) => PastStoryItem(
    id: '${row['id']}',
    mediaType: '${row['media_type']}',
    occurredOn: DateTime.parse('${row['occurred_on']}'),
    createdAt: DateTime.parse('${row['created_at']}'),
  );

  final String id;
  final String mediaType;
  final DateTime occurredOn;
  final DateTime createdAt;

  bool get isVideo => mediaType == 'video';
}

abstract class PastStoryChaptersGateway {
  /// `list_my_closed_story_chapters`.
  Future<List<PastStoryChapter>> listChapters();

  /// `list_my_closed_story_items`, oldest first, keyset after [after].
  Future<List<PastStoryItem>> listItems(String relationshipId, {PastStoryItem? after, int limit = 50});

  /// `delete_my_closed_story_items`: up to 200 per call; returns how many remain.
  Future<int> deleteAllOnce(String relationshipId);

  /// `delete_story_item`.
  Future<void> deleteOne(String storyItemId);
}

class SupabasePastStoryChaptersGateway implements PastStoryChaptersGateway {
  SupabasePastStoryChaptersGateway(this._supabase);

  final SupabaseClient _supabase;
  static const _timeout = Duration(seconds: 30);

  Map<String, dynamic> _unwrap(Object? response) {
    final data = Map<String, dynamic>.from(response! as Map);
    if (data['error'] == true) throw StoryApiError.fromJson(data);
    return data;
  }

  @override
  Future<List<PastStoryChapter>> listChapters() async {
    final rows = await _supabase.rpc('list_my_closed_story_chapters').timeout(_timeout);
    return (rows as List)
        .map((r) => PastStoryChapter.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  @override
  Future<List<PastStoryItem>> listItems(String relationshipId, {PastStoryItem? after, int limit = 50}) async {
    final rows = await _supabase
        .rpc('list_my_closed_story_items', params: {
          'p_relationship_id': relationshipId,
          'p_after_created_at': after?.createdAt.toUtc().toIso8601String(),
          'p_after_id': after?.id,
          'p_limit': limit,
        })
        .timeout(_timeout);
    return (rows as List)
        .map((r) => PastStoryItem.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  @override
  Future<int> deleteAllOnce(String relationshipId) async {
    final data = _unwrap(
      await _supabase
          .rpc('delete_my_closed_story_items', params: {'p_relationship_id': relationshipId})
          .timeout(_timeout),
    );
    return (data['remaining'] as num).toInt();
  }

  @override
  Future<void> deleteOne(String storyItemId) async {
    _unwrap(
      await _supabase
          .rpc('delete_story_item', params: {'p_story_item_id': storyItemId})
          .timeout(_timeout),
    );
  }
}

final pastStoryChaptersGatewayProvider = Provider<PastStoryChaptersGateway>(
  (ref) => SupabasePastStoryChaptersGateway(Supabase.instance.client),
);

/// My past chapters with stories in them; a new read per account.
final pastStoryChaptersProvider = FutureProvider.autoDispose<List<PastStoryChapter>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(pastStoryChaptersGatewayProvider).listChapters();
});

/// One chapter's stories, oldest first, up to 1,000 (20 pages).
final pastStoryItemsProvider = FutureProvider.autoDispose.family<List<PastStoryItem>, String>((
  ref,
  relationshipId,
) async {
  final gateway = ref.watch(pastStoryChaptersGatewayProvider);
  final all = <PastStoryItem>[];
  PastStoryItem? after;
  for (var page = 0; page < 20; page++) {
    final items = await gateway.listItems(relationshipId, after: after);
    all.addAll(items);
    if (items.length < 50) break;
    after = items.last;
  }
  return all;
});

/// Deletes every one of my stories in [relationshipId], 200 at a time.
Future<void> deleteAllMyPastStories(PastStoryChaptersGateway gateway, String relationshipId) async {
  for (var batch = 0; batch < 100; batch++) {
    if (await gateway.deleteAllOnce(relationshipId) <= 0) return;
  }
}

/// "A space that ended on 12 Sep 2026", "A paused space", "A space that closed".
String pastStoryChapterTitle(PastStoryChapter chapter) {
  if (chapter.paused) return 'A paused space';
  final ended = chapter.endedAt;
  if (ended == null) return 'A space that closed';
  return 'A space that ended on ${MyDateFormat.toDate(ended)}';
}
```

- [ ] **Step 4: Write the screen and entry**

```dart
// lib/features/stories/presentation/screens/past_chapter_stories_screen.dart
/// Download my data → "Your stories from past chapters" (stories Wave 5,
/// review 05 #3): an author's own stories from spaces that are paused or
/// have ended, with Delete all and per-story delete.
library;

import 'dart:async';

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/feedback/confirmation_dialog.dart';
import 'package:attune/features/stories/data/past_story_chapters_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The row on Download my data. Nothing at all while loading, on error, or
/// when there is nothing to show.
class PastChapterStoriesEntry extends ConsumerWidget {
  const PastChapterStoriesEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(pastStoryChaptersProvider).valueOrNull;
    if (chapters == null || chapters.isEmpty) return const SizedBox.shrink();
    final total = chapters.fold<int>(0, (n, c) => n + c.storyCount);
    return Padding(
      padding: EdgeInsets.only(top: Spacing.lg.h),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          minVerticalPadding: Spacing.sm,
          leading: const Icon(Icons.auto_stories_outlined),
          title: const Text('Your stories from past chapters'),
          subtitle: Text('$total ${total == 1 ? 'story' : 'stories'} only you can see and delete'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PastChapterStoriesScreen()),
          ),
        ),
      ),
    );
  }
}

class PastChapterStoriesScreen extends ConsumerWidget {
  const PastChapterStoriesScreen({super.key});

  static const intro =
      "Stories you posted in a shared space that's paused or has ended. "
      "Nobody can see them now. They stay until you delete them; a space "
      'that has ended is deleted, with its stories, 12 months after it closes.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(pastStoryChaptersProvider);
    final children = <Widget>[
      Text(intro, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      Gap(Spacing.lg.h),
    ];
    async.when(
      loading: () => children.add(const Center(child: CircularProgressIndicator())),
      error: (_, __) => children.addAll([
        Text("Couldn't load your stories.", style: text.bodyLarge),
        Gap(Spacing.sm.h),
        OutlinedButton(
          onPressed: () => ref.invalidate(pastStoryChaptersProvider),
          child: const Text('Try again'),
        ),
      ]),
      data: (chapters) {
        if (chapters.isEmpty) {
          children.add(Text('Nothing left here.', style: text.bodyLarge));
          return;
        }
        for (final chapter in chapters) {
          children
            ..add(_ChapterCard(chapter: chapter))
            ..add(Gap(Spacing.md.h));
        }
      },
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Stories from past chapters')),
      body: ListView(padding: EdgeInsets.all(Spacing.lg.w), children: children),
    );
  }
}

class _ChapterCard extends ConsumerStatefulWidget {
  const _ChapterCard({required this.chapter});
  final PastStoryChapter chapter;

  @override
  ConsumerState<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends ConsumerState<_ChapterCard> {
  bool _open = false;
  bool _busy = false;

  PastStoryChaptersGateway get _gateway => ref.read(pastStoryChaptersGatewayProvider);

  void _refresh() {
    ref.invalidate(pastStoryChaptersProvider);
    ref.invalidate(pastStoryItemsProvider(widget.chapter.relationshipId));
  }

  Future<void> _deleteAll() async {
    final n = widget.chapter.storyCount;
    final ok = await ConfirmationDialog.show(
      context: context,
      type: ConfirmationType.destructive,
      title: 'Delete these stories?',
      message:
          'Your $n ${n == 1 ? 'story' : 'stories'} from this space will be deleted for good. '
          'If you want a copy, download your data first.',
      confirmText: 'Delete',
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await deleteAllMyPastStories(_gateway, widget.chapter.relationshipId);
      if (mounted) context.showSuccessSnackbar('Deleted.');
    } catch (_) {
      if (mounted) context.showErrorSnackbar("Couldn't delete. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _deleteOne(PastStoryItem item) async {
    final ok = await ConfirmationDialog.show(
      context: context,
      type: ConfirmationType.destructive,
      title: 'Delete this story?',
      message: 'It will be deleted for good.',
      confirmText: 'Delete',
    );
    if (ok != true || !mounted) return;
    try {
      await _gateway.deleteOne(item.id);
    } catch (_) {
      if (mounted) context.showErrorSnackbar("Couldn't delete. Please try again.");
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = widget.chapter;
    final count = '${c.storyCount} ${c.storyCount == 1 ? 'story' : 'stories'}';
    final range =
        c.firstOn == c.lastOn
            ? MyDateFormat.toDateShort(c.firstOn)
            : '${MyDateFormat.toDateShort(c.firstOn)} to ${MyDateFormat.toDateShort(c.lastOn)}';
    final items =
        _open ? ref.watch(pastStoryItemsProvider(c.relationshipId)) : null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pastStoryChapterTitle(c), style: text.titleMedium),
            Gap(Spacing.xs.h),
            Text(MyDateFormat.join([count, range]), style: text.bodyMedium),
            Gap(Spacing.md.h),
            Wrap(
              spacing: Spacing.sm.w,
              runSpacing: Spacing.sm.h,
              children: [
                FilledButton(
                  onPressed: _busy ? null : _deleteAll,
                  child: Text('Delete all ${c.storyCount}'),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _open = !_open),
                  child: Text(_open ? 'Hide them' : 'See them'),
                ),
              ],
            ),
            if (items != null) ...[
              Gap(Spacing.sm.h),
              items.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Spacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Text("Couldn't load them.", style: text.bodyMedium),
                data: (list) => Column(
                  children: [
                    for (final item in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(item.isVideo ? Icons.videocam_outlined : Icons.photo_outlined),
                        title: Text(
                          MyDateFormat.join([MyDateFormat.toDate(item.occurredOn), item.isVideo ? 'Video' : 'Photo']),
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete this story',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => unawaited(_deleteOne(item)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

Check the barrel `export_screens.dart` provides `Gap`, `Spacing`, `.h`/`.w` and the snackbar extensions (`data_export_screen.dart` and `pause_relationship_action.dart` use them through it); if `showSuccessSnackbar` is not exported there, import `package:attune/core/widgets/feedback/export_extensions.dart`. Use `Spacing.xs` only if it exists in `design_tokens.dart`; otherwise `Spacing.sm`. Then `dart format` both new files.

- [ ] **Step 5: Wire the entry into Download my data**

In `data_export_screen.dart`, add `import 'package:attune/features/stories/presentation/screens/past_chapter_stories_screen.dart';`, and directly before `return Scaffold(` add:

```dart
    // Stories Wave 5 (05 #3): after an ending, an author's own stories can
    // be deleted from here. Draws nothing for most people.
    children.add(const PastChapterStoriesEntry());
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/stories/past_chapter_stories_test.dart test/features/data_export`
Expected: all pass (the existing export tests do not override the new gateway: the entry reads an error and draws nothing).

- [ ] **Step 7: Checkpoint**

`flutter analyze` on the three lib files → clean. No commit.

---

### Task 15: Pause and End say that stories close too (owner ruling 4; 04 #11)

**Files:**
- Modify: `lib/features/relationships/presentation/widgets/pause_relationship_action.dart` (message, sheet height)
- Modify: `lib/features/relationships/presentation/widgets/end_relationship_action.dart` (message, sheet height)
- Modify: `lib/app/documentations/user_manual/data/relationship_lifecycle_docs.dart` (one bullet, one content item)
- Modify: `test/features/relationships/relationship_lifecycle_card_test.dart` (the two copy assertions pin the old text)

**Interfaces:** none. Copy only; behaviour unchanged (owner ruling 4 keeps the hide-on-pause behaviour).

- [ ] **Step 1: Change the tests to the new copy (they fail first)**

In `relationship_lifecycle_card_test.dart`, the pause test's expected message becomes:

```dart
        'Chat becomes read-only for both of you and nothing new is shared. '
        'Stories and the story calendar are hidden for both of you until you resume. '
        'Either of you can resume or end it within 30 days. '
        // Only the live games end on a pause (their relationship-change
        // triggers); the rest wait until you resume.
        'Paint Ball, Word Hunt and Snakes and Ladders end; other games '
        'wait. '
        "Your partner won't get a notification.",
```

and the end test's:

```dart
        "You'll both be able to read your chat for 30 days, then it closes. "
        'Stories close for both of you now. You can download yours, or '
        'delete them, from Download my data. '
        'Closed chats are deleted after 12 months. '
        "Your partner won't get a notification; they'll see it the next time "
        'they open Attune.',
```

Add to both tests, after the `pumpAndSettle` that opens the sheet: `expect(t.takeException(), isNull);` (the longer text must not overflow the sheet).

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/relationships/relationship_lifecycle_card_test.dart`
Expected: the two copy tests fail (`findsOneWidget` finds nothing).

- [ ] **Step 3: Change the copy**

`pause_relationship_action.dart`: insert `'Stories and the story calendar are hidden for both of you until you resume. '` after the first sentence of `message`, and raise `maxHeight: 460.h` to `maxHeight: 500.h`.

`end_relationship_action.dart`: insert `'Stories close for both of you now. You can download yours, or delete them, from Download my data. '` after the first sentence, and raise `maxHeight: 420.h` to `maxHeight: 480.h`. Update the comment above `title:` to `// Spec 3a (F1 (1), (2)): no one is notified, and the chat stays readable for both for 30 days. Stories close at once (Wave 5 copy, owner ruling 4).`

`relationship_lifecycle_docs.dart`: in `lifecycle_pause_what`'s `bulletPoints`, after the chat bullet add `'Stories and the story calendar are hidden for both of you until you resume.',`; in the Ending section, after `lifecycle_end_window`, add:

```dart
        ManualContent(
          id: 'lifecycle_end_stories',
          title: 'Your stories',
          numberPrefix: '3',
          content:
              'Stories close for both of you when the space ends. You can still download your own stories, or delete them, from Settings → Download my data.',
        ),
```

and renumber the following `lifecycle_end_seal` item's `numberPrefix` from `'3'` to `'4'`.

- [ ] **Step 4: Run them, and the manual's guard test**

Run: `flutter test test/features/relationships test/app/documentations test/features/chat/chat_settings_seen_receipts_toggle_test.dart`
Expected: all pass (the manual's id-uniqueness and registry guards included; find them with `grep -rln "DocumentationRegistry\|manual_documentation_registry" test`).

- [ ] **Step 5: Checkpoint**

`flutter analyze` on the three lib files → clean. No commit.

---

### Task 16: STORIES.md says what was built; one handoff for all five waves; everything green

**Files:**
- Modify: `lib/architecture/STORIES.md` (§2, §3.5, §4.2, §4.4, §4.5, §5.5/§8 rows, §6.1, §7, §8 "Former partners", §9, §12, §13)
- Create: `docs/reviews/2026-10-24-stories-handoff.md`

**Interfaces:** none.

- [ ] **Step 1: Amend STORIES.md (surgically; the file carries Wave 1–4 edits)**

Make each change below; quote the exact current line before replacing it (`grep -n` first):

1. §2 table: replace the row `| Retention is forever unless the author deletes | No sweep job, no expiry of the calendar copy |` with `| Kept while the space is open, unless the author deletes | No expiry sweep. After an ending nothing is visible to either partner; the author can still list and delete their own stories (Download my data → Your stories from past chapters, Wave 5). A closed space, stories included, is purged 12 months after it is archived (Spec 3b, 20261018110000) |`.
2. §3.5: replace the decision paragraph with: **Decision: `create_story_item` takes `p_utc_offset_minutes` and `p_captured_at`; `occurred_on` is the poster's civil date at the capture instant, clamped to the last 7 days and never the future — midnight to midnight, no cutoff, computed in UTC plus the offset so the session time zone never matters (Wave 5, 04 #3, #13). The 24-hour reel window still starts at posting.** Keep the paragraphs about the clamp range and the dropped night-before idea.
3. §4.2: replace `returns an intent id, a storage key, the \`story-media\` bucket and a\n15-minute expiry.` with `returns an intent id, a storage key, the \`story-media\` bucket and an expiry: 15 minutes for image media, 60 minutes for video media and every thumbnail (Wave 5; a video pair gets the hour, an image pair is unchanged). Calls are serialized per person (a transaction advisory lock) before the two abuse limits are counted. The bucket itself refuses objects over 25 MB or of any type but image/jpeg and video/mp4.`
4. §4.4: replace `- **Images**: the existing transform handles this — 1600px long edge,\n  quality 80.` with `- **Images**: the existing transform handles this — 1600px long edge (width or height, whichever is longer), quality 80, JPEG kept. A rendition is swapped in only after it is checked: non-empty, a whole JPEG, long edge ≤ 1600, aspect within 2% of the original. An image already within 1600 px is marked considered and left alone. The worker runs every 5 minutes while work waits, claiming in batches of 20, 4 at a time, for up to 60 s, with a 20 s timeout per call and one JSON log line per run (Wave 5).` Replace `five failed attempts dead-letter the job\nand raise an operational alert.` with `five failed attempts dead-letter the job. **No alert is wired yet** (04 #10): dead letters, queue age and the bytes/day metric are an owner follow-up.` In the same section replace `The hourly worker claims` with `The worker claims`.
5. §4.5: replace `Monitoring alerts when\nthe oldest pending row is more than 30 minutes old.` with `A queue-age alert (oldest pending row over 30 minutes) is specified but not built (04 #10).`
6. §6.1: replace `Finalization time is posting time:\nit sets the 24-hour window and \`occurred_on\`, even if an offline capture\nwaited in the queue.` with `The capture time travels with the record: finalize sends it as \`p_captured_at\`, so \`occurred_on\` is the day it was taken (clamped to the last 7 days); the 24-hour window starts when finalize lands. A video pair's intents last an hour, so \`media_link_too_slow\` is judged against the pair's own lifetime.`
7. §7: replace `**No posting limit, no retention cap.** Retention is forever unless the\nauthor deletes. This is a promise that is easy to make now and\nimpossible to retract later, so it is stated explicitly rather than\ndefaulted into.` with `**No posting limit, no retention cap while the space is open.** Stories stay until the author deletes them. After an ending they are hidden from both partners, the author can still delete their own, and the closed space is purged 12 months after it is archived (Spec 3b).`
8. §8: replace the `Former partners` row's last sentence (`The author-only delete RPC remains available so ending a relationship never removes the right to erase one's own media`) with `After an ending the author lists and deletes their own stories from Download my data → Your stories from past chapters (\`list_my_closed_story_chapters\`, \`list_my_closed_story_items\`, \`delete_my_closed_story_items\`, Wave 5). Place pins are kept, unreadable, until the space is archived, so the author's export carries them`.
9. §8 Wave 4 rows: in `Ring expiry (Wave 4)` append ` Since Wave 5 the server sends \`next_expires_at\` and \`server_now\`; the timer runs on the server's clock.`; in `Calendar day rings (Wave 4)` replace `The day reel filters by author on the client until \`list_story_day_items\` takes \`p_author_id\`.` with `The day reel asks the server for one author's stories (\`p_author_id\`, Wave 5) and keeps its own filter for an older server.`; in `Day sheet counts (Wave 4)` replace `Unviewed counts come from the loaded items only` with `Unviewed counts come from \`list_story_day_counts.unviewed_count\` (Wave 5), else from the loaded items`; in `Signed URLs on the rings and calendar (Wave 4)` keep `Batch-signing a month's keys is not done` and add ` (deferred, 04 #6)`.
10. §9: the `Storage grows without bound` row: replace `aggregate bytes/day and backlog are monitored` with `aggregate bytes/day and backlog are not yet monitored (04 #10, owner follow-up)`.
11. §12 / §13: wherever acceptance criteria or open questions claim monitoring, say it is not built. In §13 replace the whole `**Wave 5 server dependencies (from Wave 4, not built yet).**` bullet with: `**Built in Wave 5:** the ring index, \`next_expires_at\`/\`server_now\`, \`p_author_id\` and per-author unviewed counts. **Still deferred:** batch signing a month's thumbnails (04 #6); story ops alerts (04 #10); a short view grace window just after expiry (04 #16).` Also remove the stale `story_change_signals was never added to the supabase_realtime publication` bullet's "likely never fired" claim by appending: ` Fixed by 20261018130500_story_signals_realtime.sql.`
12. Add §4.6 `Export` (or, if numbering would shift links, a paragraph at the end of §4.5): `Download my data walks the person's own story media first, then chat, planning and journal media, inside the 12-part cap; story files are named \`my_stories/<hash>.mp4\` or \`.jpg\` by media type, in data.json and the ZIP alike; \`media_not_included.txt\` says how many stories did not fit (Wave 5, 04 #1, #12).`

Run: `grep -n "forever unless\|Finalization time is posting time\|hourly worker\|Monitoring alerts when" lib/architecture/STORIES.md` → no output.

- [ ] **Step 2: Write the handoff**

Create `docs/reviews/2026-10-24-stories-handoff.md`. Gather first:
- what each wave changed: `docs/superpowers/plans/2026-10-23-stories-wave{1-reel,2-posting,3-app-shell,4-rings-calendar}.md` (Goal/Architecture) and each ledger's last lines (`.superpowers/sdd/2026-10-23-stories-wave*/progress.md`, `final-fix-report.md`);
- device checklists: `.superpowers/sdd/2026-10-23-stories-wave1-reel/{batch-6-report,final-fix-report}.md`, `…wave2-posting/{batch-5,batch-6,batch-7,batch-8}-report.md` and `final-review.md`, `…wave3-app-shell/{batch-1,batch-2,batch-3,batch-5}-report.md` and `final-fix-report.md`, `…wave4-rings-calendar/batch-6-report.md` (its "Merged device checklist") and `final-review.md`; plus this plan's device checks below;
- deferred minors: every `Final: minor (deferred)` line in the four ledgers.

Structure (plain language, short sentences, no ids beyond file names):

```markdown
# Stories: handoff after the five-wave robustness program (2026-10-24)

Review: docs/reviews/2026-10-23-stories-robustness-review.md. Plans: docs/superpowers/plans/2026-10-23-stories-wave1-reel.md … 2026-10-24-stories-wave5-server.md. Nothing is committed or deployed; the owner does both.

## What changed
### Wave 1 — Reel
### Wave 2 — Posting
### Wave 3 — App shell
### Wave 4 — Rings and calendar
### Wave 5 — Server
(Each: 5–10 bullets of what a person notices, then the files that changed.)

## Deploy, in this order
1. Migrations (supabase db push applies them in filename order; all idempotent):
   20261024100000_story_places_grants.sql
   20261024100100_story_media_bucket_limits.sql
   20261024100110_story_intent_hardening.sql
   20261024100200_story_membership_for_me.sql
   20261024100300_story_capture_date.sql
   20261024100400_story_ring_index.sql
   20261024100410_story_ring_summary_expiry.sql
   20261024100500_story_day_reads_by_author.sql
   20261024100600_story_archival_v2.sql
   20261024100700_story_export_order.sql   (restarts any export mid-way through its media; expect 0–few)
   20261024100710_story_places_keep_until_archive.sql
   20261024100800_my_closed_story_items.sql
2. Edge functions, after the migrations: process-story-archival, build-data-exports, and every function that bundles _shared/attune_auth.ts (the constant-time check): activate-topics, analyse-message, analyse-session, evaluate-ask2-eligibility, forum-quiet-check, process-chat-media, process-chat-notification-outbox, process-chat-safety-outbox, process-dating-photo, process-media-deletion-queue, process-relationship-avatar, process-scheduled-notifications, process-truth-answer-safety, send-notification (and, to keep bundles identical, the other importers: accept-invite, ai-assist, ai-sessions, ai-together, ai-understand, calendar-feed, create-relationship-invite, delete-account, end-relationship, generate-thirty-six-reflection, get-export-url, planning-link-preview, upload-dating-photo, verify-dating-profile).
3. Client build (Waves 1–5) after both. An older client keeps working against the new server (every new parameter has a default; new columns are ignored), and the new client falls back on PGRST202 against an older server.
4. No data backfill. Existing stories keep their dates. Pending archival jobs pick up the new worker on its next 5-minute run.
5. After deploy: check `select schedule from cron.job where jobname = 'invoke-story-archival'` is `*/5 * * * *`; check the bucket in the dashboard shows 25 MB and image/jpeg, video/mp4; watch one archival run's log line.

## Owner decisions pending
- iOS video_compress ignores a trim when audio is included (SwiftVideoCompressPlugin): trimmed chat videos with sound export whole on iOS. Needs a plugin fork/override or another trim path. (Wave 2.)
- ChatError checks the PostgREST message before the code, so a refusal whose message contains "rate" reads as rate-limited and never strikes. The fix belongs in chat. (Wave 2.)
- Wave 5 rulings to confirm: the 24-hour window from posting, not capture; the 7-day capture clamp; hour-long thumbnail intents; place pins kept until archive; no thumbnails in "past chapters"; the left-out story count in media_not_included.txt rather than README. (List each with its one-line cost if reversed, from the plan's Rulings.)
- Not built, owner call: story ops alerts and metrics (04 #10); batch signing (04 #6); CI dependency and secret scanners (checklist 7.1/7.3); the Later list in the review (gallery upload, captions, flash/zoom, save to phone, mute, quick emoji replies).

## Device checklist (all five waves, merged)
(One table: Check | Wave | How | Expected. De-duplicate overlapping checks; keep every distinct one.)
Wave 5 adds:
- A video story on a slow link (Network Link Conditioner, 3G) posts within an hour, not "too slow" at 13 minutes.
- An oversize file (a 30 MB mp4 pushed by a debug build) is refused at upload (413) and the post shows the "too large" reason.
- A portrait photo story, 24 hours later, plays sharp from the calendar; its archived file is 1600 px tall (Storage dashboard).
- A photo taken at 23:55 offline and posted at 00:10 shows on the day it was taken, for both partners.
- With the phone clock set 5 minutes behind, a partner's story leaves the ring when it expires, not 5 minutes later.
- On a day with more than 50 stories, the partner's day ring is bright for unseen ones beyond the first 50.
- End a space; Download my data shows "Your stories from past chapters"; Delete all removes them; a new download no longer holds them.
- Download my data on an account with lots of chat media: story files come first and open as photos and videos (.jpg/.mp4); media_not_included.txt says how many stories were left out, if any.
- Pause and End confirm sheets show the new stories sentence without clipping at the largest text size.

## Deferred minors (from the ledgers)
(Every "Final: minor (deferred)" line, grouped by wave, one line each.)
```

Fill every section from the sources; no section may be left as a heading only.

- [ ] **Step 3: Final verification**

```bash
story_contracts        # every line PASS (18 files: 10 existing + 8 new)
related_contracts      # 5 PASS
cd supabase/functions && for d in $(find . -name "*.test.ts" -not -path "./_shared/*" | sed 's|/[^/]*$||' | sort -u); do
  deno test --allow-read --allow-env --allow-net --allow-sys "$d" 2>&1 | grep -o '[0-9]* passed | [0-9]* failed' | tail -1 | sed "s|^|$d |"
done; deno test --allow-env --allow-read _shared/attune_auth.test.ts; cd ../..
flutter test           # the whole suite
flutter analyze 2>&1 | grep -E "error •|error -"   # no output
git status --porcelain | grep -v '^ M\|^??'          # nothing staged
```

Expected: all story and related contracts PASS; Deno directories match `$SCRATCH/deno_baseline.txt` plus the new `process-story-archival` (all pass) and `build-data-exports` at 22; `flutter test` ends `All tests passed!`; analyzer prints no errors; nothing staged. Also confirm no pre-existing Dart file was reformatted: `git diff --stat` shows only the files this plan lists plus the earlier waves' files.

- [ ] **Step 4: Checkpoint**

No commit. Report: task list, migrations in order, functions to deploy, rulings, and the owner decisions above.

---

## Self-review (done while writing)

- **Scope coverage.** 1 Export → Tasks 11, 12 (stories first, cursor-compatible, in-flight restart, README/left-out count, extensions, pins to archive). 2 Archival → Tasks 9, 10. 3 Story date → Task 5. 4 Hardening → Tasks 2, 3, 4 (bucket, constant-time, oracle, serialization, video intents). 5 Ring/day → Tasks 6, 7, 8 (index, `next_expires_at`/`server_now` with client offset for M-6, `p_author_id`, per-author unviewed counts, old-server tolerance; batch signing deferred). 6 After an ending → Tasks 13, 14. 7 Copy → Task 15. 8 Harness → Task 1. 9 Spec drift + handoff → Task 16.
- **Names used across tasks.** `story_relationship_is_open_for_me(uuid)`; `create_story_item(…, jsonb, timestamptz)`; `create_story_item_core(…, timestamptz)`; `list_story_day_items(…, p_author_id uuid)`; `StoryDayKey.authorId`; `StoryDayCount.unviewedCount`; `StoryRingSummary.serverNow`; `storyServerClockOffset`; `ScriptedReelGateway.dayAuthorIds` / `serverFiltersAuthor`; `skip_story_archival(uuid)`; `export_story_file_name(text, text)`; `export_media_rank(text)`; `export_restart_old_order_jobs()`; `data_export_jobs.media_order`; `list_my_closed_story_chapters()`, `list_my_closed_story_items(uuid, timestamptz, uuid, int)`, `delete_my_closed_story_items(uuid)`; `PastStoryChaptersGateway`, `pastStoryChaptersProvider`, `pastStoryItemsProvider`, `deleteAllMyPastStories`, `pastStoryChapterTitle`, `PastChapterStoriesEntry`, `PastChapterStoriesScreen`.
- **Review Focus → tests.** Mixed versions: Task 5 Step 7a, Task 7 Step 6, Task 7 D2, Task 6 skew test. In-flight export: Task 11 E4. Clock: Task 5 C2/C4, Task 6 offset tests. Transform output: Task 10 validation tests. Big/foreign chapters: Task 13 A4, A6.

# Spec 1a — Privacy and Security Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three privacy floors from the couples research, server-enforced and tested:
1. **Relationships write lockdown.** A member can no longer rewrite any `relationships` column from the client; every legitimate write already goes through a SECURITY DEFINER RPC or the service role.
2. **"Show when we've seen things" (F4).** One per-couple setting covers chat read ticks and story seen-state. Effective only when both are on; either turns it off for both, silently; default off for couples linked on/after the ship cutoff. The sender's client cannot read a receipt that happened while it was off; the poster cannot learn a view that happened while it was off.
3. **Pulse privacy (F5).** Private weekly check-in answers never feed any shared dimension, delta or confidence. Emotional safety leaves the shared score and is shown only to its author. compute-pulse authenticates its caller, enforces a 24 h force-recompute limit per relationship, diffs against the previous week, and agrees with Dart on the week ending. Pulse is hidden while the relationship is paused.

**Architecture:**
- **SQL first.** Nine migrations (five behaviour, four `*_grants.sql` replayed by the local harness). Every privacy rule is enforced in Postgres: column grants on `messages` and `story_items`, SECURITY DEFINER RPCs that mask or gate, RLS on the new self-only tables.
- **One predicate.** `seen_receipts_effective(relationship_id)` (both members on) is the only place the F4 rule lives; `mark_conversation_read`, `mark_story_viewed` and the story list RPCs call it.
- **Two columns, two jobs.** `messages.read_at` stays as the recipient's private unread marker (no client can select it). `messages.read_receipt_at` is the sender's tick, written only while the setting is on. Stories get the same split: `has_been_viewed` (viewer's own state) and `seen_shown` (author-facing, written only while on; masked back to false while off).
- **Pulse.** compute-pulse computes the four shared dimensions from shared moments, chat aggregates and games only, and writes each member's private Emotional safety to `pulse_private_scores` under `auth.uid()` RLS. The Dart side reads four dimensions from one `sharedPulseDimensions` list, shows the weights, and adds a private "Your week" card.

**Tech Stack:** Postgres 17 (local harness `scripts/local_pg_setup.sh`), Supabase RLS/column grants/SECURITY DEFINER, Deno 2 edge functions (`compute-pulse`, `generate-verdict`), Flutter 3.29 + Riverpod 2 (`flutter_riverpod ^2.4.9`), `supabase_flutter` (`FunctionException`), `flutter_test`.

**Spec:** `docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md` §3 rows F4 and F5, §10 Q2, §11 Spec 1; `lib/architecture/attune/ATTUNE_SOUL.md` §8 ("NEVER: Read receipts, seen-state … as defaults … or re-enableable by one partner alone") and §9 Pulse; `lib/architecture/attune/ATTUNE_MASTER_SPEC.md` §11 constraints 10–15 (constraint 12 is this plan's rule). Code maps: `.superpowers/sdd/spec1-map-f4.md`, `.superpowers/sdd/spec1-map-f5.md`, `.superpowers/sdd/spec1-map-f8.md` (harness facts). Read them alongside this plan. Plan 1b (quiet hours, streak deletion, Mirror flag, device titles, push copy) is separate and **out of scope here**.

---

## RULING REQUIRING OWNER CONFIRMATION AT PLAN REVIEW

**F5 as written in the roadmap says:** "(1) Shared dimensions recompute only when both have checked in that week; otherwise hold with a 'waiting for both' confidence state. (2) Refresh does not recompute check-in-driven dimensions."

**This plan implements a stronger rule instead:** *private weekly check-in answers never feed any shared dimension, delta or confidence. They appear only in a private, self-facing "Your week" view.* Emotional safety leaves the shared score entirely.

**Reason (spec1-map-f5.md §3 "leaks", items 3 and 4):** gating on "both checked in" does **not** stop inference. With both rows, `communication = round(avg * 10)` where `avg = (A + B) / 2`, so `avg * 10` is a multiple of 5, the rounding is lossless, and B recovers `A = 2·avg − B` exactly. Connection, alignment and safety have the form `round((T + 5A + 5B) / 2)` and give A to within ±1. Confidence points (`min(checkins, 2) * 2` per dimension) also move when the partner checks in, which is "Jordan ✓" by another name. The only algebra-proof rule is: shared numbers contain no private answers. SOUL §9 (amended) already states "No dimension can be used to infer the other partner's private answers", which the roadmap's own wording cannot satisfy.

**Consequences the owner is accepting:** the weekly check-in becomes a private reflection (plus the private Emotional safety score); the shared score moves on moments, chat aggregates and games only; "Pulse is strongest when both partners submit the weekly check-in" copy goes; PULSE.md §4.1/§6/§10 are amended with this ruling; the dead "recompute when both checked in" path is removed. If the owner rejects this ruling, Task 7 and Task 8 must be re-planned — do not start them before confirmation.

**Two smaller rulings to confirm at the same review:**
- **R-A (view-once media stays outside the toggle).** `messages.viewed_at` (view-once video, streaks) and `streak_views_remaining` remain sender-visible ("Viewed" in Message info, replay counts) whatever "Show when we've seen things" says. They are the mechanics of view-once media (the sender chose a format whose whole point is a single viewing), not an ambient receipt; the toggle governs ordinary read ticks and story seen-state only. If the owner wants them under the toggle too, that is a follow-up, not this plan.
- **R-B (the toggle shows my own vote and the effective state).** `get_seen_receipts` returns `{mine, effective}` to the caller only. With two people, "my vote is on and it is not effective" lets me infer my partner's vote; that inference is inherent to any both-required rule and exists whatever the UI shows (a toggle that flips back to off says the same thing, worse). What is never returned: the partner's row, a timestamp, an event, a notification. SPEC §11.12's "silently" is honoured: turning off writes nothing the partner is told about.

---

## Global Constraints

**How we work**
- Work directly on `main`. **No commits or pushes**: each task ends with a ledger line in `$WS/progress.md` instead of a commit.
- Write each test first and watch it fail before writing code. For SQL, "fail" means the contract file errors on the scratch database built **without** the task's migration (or with the mutant prepended — see Task 0's `mutant.sh`).
- **Never `dart format` a pre-existing file or directory.** Format only files this plan creates (each task's analyzer step lists them).
- **Snapshot-diff every shared file.** Before editing one, `cp <file> "$WS/snapshots/<flattened-name>"`. After editing, `diff -u "$WS/snapshots/<flattened-name>" <file>` and check it shows only the intended lines. `git diff --numstat` is blind here: `lib/features/planning/**` and the three architecture docs carry the owner's uncommitted edits, `docs/superpowers/research/` is untracked, and the couple-map work was only partly committed.
- Analyzer gate: `flutter analyze <files> 2>&1 | grep -E "^\s*(error|warning) "` prints nothing (the leading-anchor pattern matters; `" error "` matches nothing).
- SQL contracts are plain-SQL `DO` blocks that assert the **specific** error (`EXCEPTION WHEN insufficient_privilege`, or `GET STACKED DIAGNOSTICS` + exact message text), never `WHEN OTHERS`. They run on the local Postgres 17 harness: `ATTUNE_TEST_DB=attune_spec1a scripts/local_pg_setup.sh --no-tests` to (re)build, then `psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/<file>.sql`. **Never use `attune_test`** (a parallel session may own it). Expected output of a green contract run: nothing but `NOTICE` lines; a red one prints `ERROR:  CONTRACT VIOLATED: …` (or the test's own message).
- Every `REVOKE`/column-grant lives in its own `*_grants.sql` migration **and** gets an `\i` line appended to `scripts/local_pg_grants.sql`: the harness blanket-grants every table to `authenticated` after migrations, so an inline revoke is silently undone locally (memory `sdd_verification_lessons.md`).
- Migration timestamps follow the latest existing one (`20261017100000_story_places.sql`): this plan uses `20261017110000` … `20261017150100`, in the order the tasks apply them.
- Deno tests: `deno test --allow-read --allow-env --allow-net supabase/functions/compute-pulse` and `deno test --allow-read --allow-env --allow-net supabase/functions/generate-verdict` (`index.ts` calls `serve()` at import, hence `--allow-net`). Baseline today: compute-pulse 60 passed.
- **Never log message content**, check-in answers, or receipt timestamps. compute-pulse keeps logging only `error.name`.
- Fixture hygiene: every new SQL fixture uses the uuid prefixes and phone ranges listed in its task (`+233599…`); `grep -rn "+233599" supabase/tests` must be empty before Task 1 creates the first one. `users.phone` is UNIQUE and `ON CONFLICT DO NOTHING` hides a collision.
- Shared files touched (each a surgical edit; flag regression risk in the ledger): `scripts/local_pg_grants.sql`, `supabase/tests/chat_system_contracts.sql`, `supabase/tests/story_rpc_contracts.sql`, `supabase/tests/story_security_contracts.sql`, `lib/features/chat/data/repositories/supabase_chat_repository.dart`, `lib/features/chat/domain/entities/message.dart`, `lib/features/chat/presentation/state/chat_state.dart`, `lib/features/chat/presentation/widgets/chat_settings_static_rows.dart`, `lib/features/onboarding/presentation/widgets/couples_joined_step.dart`, `lib/features/stories/presentation/screens/story_reel_screen.dart`, `test/features/chat/support/chat_test_harness.dart`, `test/features/chat/chat_controller_test.dart`, `test/features/stories/story_reel_test.dart`, `test/features/pulse/pulse_screen_test.dart`, `supabase/functions/compute-pulse/index.ts`, `supabase/functions/compute-pulse/index.test.ts`, `supabase/functions/generate-verdict/index.ts`, `lib/features/pulse/**` (providers, repository, model, screen, radar, number view, banner, complete screen), `lib/app/documentations/user_manual/data/pulse_docs.dart`, `lib/architecture/PULSE.md`. **Do not touch** `ATTUNE_MASTER_SPEC.md`, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md` (owner's uncommitted edits).

**Privacy rules (copied from the spec)**
- SOUL §8: "NEVER: Read receipts, seen-state, last-seen, typing indicators or location as defaults, as trust framings, or re-enableable by one partner alone."
- SOUL §8: "NEVER: Asymmetric behavioural data shown about a partner to the other partner." (This is why the per-message analysis columns leave the client grant in Task 3.)
- SPEC §11.12: "Read receipts, seen-state, presence and availability are off until both enable them; either can turn them off alone and silently; turning them on again requires both."
- SPEC §11.10: "No surface, RPC, export or analytics event shows one partner a count, ratio, trend or label about the other partner's behaviour." (No "You ✓ Jordan ✗"; confidence must not count check-ins.)
- SOUL §9 Pulse: "Shared dimensions are shown to both partners … Emotional safety is shown to its author only. No dimension can be used to infer the other partner's private answers."

**Copy (verbatim)**
- Toggle title: "Show when we've seen things"
- Toggle subtitle, effective on: "On for both of you. Read ticks and story seen marks show. Either of you can turn this off."
- Toggle subtitle, mine on but not effective: "Turns on once you've both turned it on."
- Toggle subtitle, mine off: "Off. Read ticks and story seen marks stay hidden for both of you. Turn it on together whenever you like."
- Toggle failure snackbar: "Couldn't update this setting. Try again."
- Ask 1 line (CouplesJoinedStep): "Read receipts are off to start. Turn them on together whenever you like."
- Pulse paused state: title "Pulse is paused", subtitle "Nothing is computed or shown while your relationship is paused."
- Your week card: title "Your week", subtitle "Only you can see this.", empty line "No check-in this week yet.", score label "Emotional safety"
- Dimension tooltip weight line: "Counts for {n}% of the shared score."
- Dimension tooltip footer: "Emotional safety is not part of the shared score. Each of you sees your own in Your week."
- Refresh rate-limited: "You can refresh again in about {n} hours." / "You can refresh again in under an hour."
- Refresh other failure: "Couldn't refresh Pulse. Try again."
- Check-in banner: "A private weekly check-in, just for you. It takes about 60 seconds."
- Check-in complete: "Your weekly reflection has been saved. Only you can see your answers; they show in Your week on Pulse."

**Constants**

| Name | Where | Value |
|---|---|---|
| Ship cutoff (link date on/after → receipts off) | `seen_receipts_backfill_defaults(p_cutoff timestamptz DEFAULT now())` | `now()` at `db push` time: every couple active or paused at deploy is ON; anyone linking after deploy is OFF. Contracts pass an explicit value. |
| Force-recompute claim key | `pulse_recompute_limits (relationship_id, user_id)` | per member, so one partner's refusal never reveals the other's refresh |
| Force-recompute minimum interval | `claim_pulse_recompute(p_min_interval DEFAULT …)` | `interval '24 hours'` |
| Shared weights (raw) | `SHARED_WEIGHTS` (TS) / `sharedPulseDimensions` (Dart) | Communication 22, Connection 22, Conflict health 20, Alignment 18 (total 82) |
| Shared weights (disclosed, rounded) | tooltip + user manual | 27 % / 27 % / 24 % / 22 % |
| Week ending | `getWeekEnding` (TS) / `pulseWeekEnding` (Dart) | the UTC Sunday on or after the UTC date of `now` (a Sunday is its own week ending) |

## Review Focus

1. **Receipts turned off mid-conversation, then back on.** A message read while off must never show "Read", even after both turn it on again. Pinned in Task 3 (`chat_system_contracts.sql` sender-side block: "turning receipts on revealed a read made while off").
2. **The recipient's unread badge and read gate while receipts are off.** The badge must still clear and the client must not call `mark_conversation_read` on every sync. Pinned in Task 3 (`read_receipt_contracts.sql` "count_unread_messages") and Task 5 (`chat_controller_test.dart` "does not re-mark messages already marked").
3. **Two refresh taps, or two devices, inside 24 h.** The second gets a 429 with a retry time and the client says so in plain words. Pinned in Task 7 (`pulse_privacy_contracts.sql` claim block) and Task 8 (`pulse_refresh_copy_test.dart`).
4. **Sunday near midnight UTC.** Saturday 23:59 UTC and Sunday 00:01 UTC must land on the same week ending; Sunday is its own week ending on both server and client. Pinned in Task 7 (`index.test.ts` getWeekEnding Sunday/Saturday) and Task 8 (`pulse_week_test.dart`).
5. **A paused couple opens Pulse from a notification deep link.** No score, no "Start check-in", no refresh. Pinned in Task 8 (`pulse_screen_test.dart` "paused hides everything").
6. **The realtime UPDATE event itself.** `messages` is in `supabase_realtime`; column privileges strip a payload but not the event, so a read while off must change **no row** of `messages` (the private marker lives in `message_reads`). Pinned in Task 3 (`read_receipt_contracts.sql` "no messages row changes while off": `xmin` + row hash before/after).
7. **A paused couple and the switch-off.** A paused member must still be able to turn receipts off, and receipts must not flow while paused even if both votes are on. Pinned in Task 2 (`seen_receipts_contracts.sql` block 6).
8. **The cached recompute provider.** A second refresh tap must reach the server (and show the 429 copy), not resolve from Riverpod's cache. Pinned in Task 8 (`pulse_screen_test.dart` "a second refresh reaches the server and shows the limit").
9. **The Sunday cron after a forced mid-week refresh.** The week's row already exists, so a "skip if exists" guard would make the cron a no-op; service-role runs always recompute. Pinned in Task 7 (`index.test.ts` `shouldComputeShared`).

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20261017110000_relationships_write_lockdown_grants.sql` (new, replayed) | Drop the open UPDATE policy; revoke UPDATE/DELETE on `relationships` |
| `supabase/migrations/20261017120000_seen_receipts.sql` (new) | `seen_receipt_prefs`, `seen_receipts_effective`, `get/set_seen_receipts`, `seen_receipts_backfill_defaults` |
| `supabase/migrations/20261017120100_seen_receipts_table_grants.sql` (new, replayed) | No client grant on `seen_receipt_prefs` |
| `supabase/migrations/20261017130000_read_receipts_split.sql` (new) | `messages.read_receipt_at`, backfill, `mark_conversation_read`, `count_unread_messages` |
| `supabase/migrations/20261017130100_messages_column_grants.sql` (new, replayed) | `messages` SELECT allowlist (no `read_at`, no analysis columns); no UPDATE/DELETE |
| `supabase/migrations/20261017140000_story_seen_state.sql` (new) | `story_items.seen_shown`, masked list RPCs, definer ring summary, `mark_story_viewed` |
| `supabase/migrations/20261017140100_story_items_column_grants.sql` (new, replayed) | `story_items` SELECT allowlist (no `has_been_viewed`, no `seen_shown`) |
| `supabase/migrations/20261017150000_pulse_privacy.sql` (new) | `pulse_scores.emotional_safety` nullable, `pulse_private_scores`, `pulse_recompute_limits`, `claim_pulse_recompute` |
| `supabase/migrations/20261017150100_pulse_privacy_table_grants.sql` (new, replayed) | Grants for the two new Pulse tables |
| `scripts/local_pg_grants.sql` (shared) | Five `\i` lines appended |
| `supabase/tests/relationships_lockdown_contracts.sql` (new) | Task 1 contracts |
| `supabase/tests/seen_receipts_contracts.sql` (new) | Task 2 contracts |
| `supabase/tests/read_receipt_contracts.sql` (new) + `chat_system_contracts.sql` (shared) | Task 3 contracts |
| `supabase/tests/story_seen_state_contracts.sql` (new) + `story_rpc_contracts.sql`, `story_security_contracts.sql` (shared) | Task 4 contracts |
| `supabase/tests/pulse_privacy_contracts.sql` (new) | Task 7 contracts |
| `lib/features/chat/domain/services/unread_count.dart` (new) | `parseUnreadCount` |
| `lib/features/chat/domain/seen_receipts.dart` (new) | `SeenReceipts` model and all copy |
| `lib/features/chat/data/seen_receipts_repository.dart` (new) | Repository and providers |
| `lib/features/chat/...` shared files (see constraints) | Columns, model, read gate, toggle row |
| `lib/features/onboarding/presentation/widgets/couples_joined_step.dart` (shared) | Ask 1 line |
| `lib/features/stories/presentation/screens/story_reel_screen.dart` (shared) | Viewer refreshes own ring after a view |
| `supabase/functions/compute-pulse/index.ts` (shared), `index.test.ts` (shared), `privacy.test.ts` (new) | Caller auth, rate limit, four shared dims, private safety, week ending |
| `supabase/functions/generate-verdict/index.ts` (shared), `emotional_safety.test.ts` (new) | No `emotional_safety` evidence |
| `lib/features/pulse/domain/pulse_dimensions.dart` (new) | The four shared dimensions, weights, copy |
| `lib/features/pulse/domain/pulse_week.dart` (new) | `pulseWeekEnding`, `pulseWeekEndingKey` |
| `lib/features/pulse/domain/pulse_refresh_copy.dart` (new) | `pulseRefreshMessage` |
| `lib/features/pulse/data/models/your_week.dart` (new) | `YourWeek`, `WeeklyCheckinAnswers` |
| `lib/features/pulse/presentation/widgets/your_week_card.dart` (new) | Private card |
| `lib/features/pulse/presentation/widgets/pulse_paused_state.dart` (new) | Paused state |
| `lib/features/pulse/**` shared files | Model, providers, repository, screen, radar, number view, banner, complete screen |
| `lib/app/documentations/user_manual/data/pulse_docs.dart`, `lib/architecture/PULSE.md` (shared) | Disclosure and ruling |

Tests live in `test/features/chat/`, `test/features/onboarding/`, `test/features/stories/`, `test/features/pulse/` next to their existing neighbours.

---

### Task 0: Workspace, baseline and scratch database

**Files:**
- Create: `.superpowers/sdd/2026-10-17-spec1a-privacy-defaults/progress.md` (the ledger)
- Create: `.superpowers/sdd/2026-10-17-spec1a-privacy-defaults/mutant.sh`

- [ ] **Step 1: Create the workspace and the ledger**

```bash
export WS=/Users/user/attune/.superpowers/sdd/2026-10-17-spec1a-privacy-defaults
mkdir -p "$WS/snapshots"
cat > "$WS/progress.md" <<'LEDGER'
# Spec 1a — Privacy and security defaults — ledger

Plan: docs/superpowers/plans/2026-10-17-spec1a-privacy-defaults.md
Branch: main (no commits). Scratch DB: attune_spec1a.

## Baseline
- flutter test: (fill in)
- deno test compute-pulse: 60 passed (2026-10-16 map); re-measured: (fill in)
- supabase/tests on attune_spec1a: (fill in PASS/FAIL count)

## Tasks
LEDGER
```

- [ ] **Step 2: Write the mutant runner**

The contract files begin with `BEGIN;` and end with `ROLLBACK;`. The runner prepends a mutation inside that same transaction, so nothing persists and a green run against a mutant is a vacuous test.

```bash
cat > "$WS/mutant.sh" <<'SH'
#!/usr/bin/env bash
# usage: mutant.sh "<sql to prepend>" supabase/tests/<file>.sql
# Expected: prints MUTANT KILLED (the contract tripped). Exit 1 otherwise.
set -u
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
cd /Users/user/attune
out=$({ echo "BEGIN;"; echo "$1"; sed -e '0,/^BEGIN;$/{/^BEGIN;$/d;}' "$2"; } \
  | psql -q -d "${ATTUNE_TEST_DB:-attune_spec1a}" -v ON_ERROR_STOP=1 2>&1)
echo "$out" | grep -E "ERROR|VIOLATED|EXPLOIT" | head -3
# Red evidence counts only when the CONTRACT tripped. A mutation that itself
# errors (e.g. "cannot change name of input parameter") proves nothing.
if echo "$out" | grep -qE "CONTRACT VIOLATED|EXPLOIT"; then
  echo "MUTANT KILLED"
else
  echo "MUTANT NOT KILLED (vacuous or broken mutation)"; exit 1
fi
SH
chmod +x "$WS/mutant.sh"
```

- [ ] **Step 3: Measure the baselines**

Run:
```bash
cd /Users/user/attune
grep -rn "+233599" supabase/tests ; echo "phones: $? (1 = none, good)"
flutter test > "$WS/baseline-flutter.txt" 2>&1; tail -3 "$WS/baseline-flutter.txt"
deno test --allow-read --allow-env --allow-net supabase/functions/compute-pulse 2>&1 | tail -3
ATTUNE_TEST_DB=attune_spec1a scripts/local_pg_setup.sh > "$WS/baseline-sql.txt" 2>&1; grep -cE "^\s+PASS" "$WS/baseline-sql.txt"; grep -E "^\s+FAIL|FAILED:" "$WS/baseline-sql.txt"
```
Expected: no `+233599` phones; `All tests passed!` (record the count); `60 passed`; every contract `PASS`, no migration `FAILED:`. The runner skips the `*.sh` concurrency contracts for a non-default DB name — that is expected. Write the three numbers into the ledger's Baseline block. If a pre-existing contract fails before any change, record it as a ruling and do not try to fix it in this plan.

- [ ] **Step 4: Ledger**

Append `Task 0: complete (baseline flutter N, deno 60, sql PASS M)`.

---

### Task 1: Relationships write lockdown

**Files:**
- Create: `supabase/migrations/20261017110000_relationships_write_lockdown_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (append two lines at the end)
- Test: `supabase/tests/relationships_lockdown_contracts.sql`

**Interfaces:**
- Consumes: policy `"relationship members update limited"` (`20260606120000_attune_core_schema.sql:124-128`), grant `20260724120000_grant_missing_core_table_privileges.sql:16`, RPCs `set_relationship_chat_name(uuid, text)` (`20260826130000:240`) and `end_relationship(uuid)` (`20260931130000:93`, SECURITY DEFINER).
- Produces: `relationships` has no UPDATE policy and `authenticated` holds neither UPDATE nor DELETE on it. Task 2 relies on `invite_accepted_at` being client-unwritable.

Verified before writing (repeat the grep, it is cheap): `perl -0ne 'print "$ARGV: $&\n" while /from\(.relationships.\)\s*\.\s*(update|upsert|insert|delete)\(/g' $(grep -rl "from('relationships')" lib)` prints nothing — no client code writes the table. Every migration-side `UPDATE public.relationships` sits inside a SECURITY DEFINER function (`enqueue_message_downstream_work`, the chat-import functions, `bump_relationship_total_sessions`, `set_relationship_avatar`, `set_relationship_chat_name`, `end_relationship`), and `accept-invite` / `create-relationship-invite` use `serviceRoleClient()`.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/relationships_lockdown_contracts.sql
-- Relationships write lockdown (Spec 1a Task 1). Every check RAISEs on violation.
--
-- Before 20261017110000 either member could UPDATE any column of their row:
-- "relationship members update limited" tested only membership, and
-- 20260724120000 granted table-level UPDATE. Status, user_a/user_b,
-- invite_accepted_at, ended_at, chat_archived_at were all client-writable.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5a100000-0000-0000-0000-0000000000a1'),
  ('5a100000-0000-0000-0000-0000000000b2'),
  ('5a100000-0000-0000-0000-0000000000c3'),
  ('5a100000-0000-0000-0000-0000000000d4')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5a100000-0000-0000-0000-0000000000a1', '+233599100001', 'Lock A'),
  ('5a100000-0000-0000-0000-0000000000b2', '+233599100002', 'Lock B'),
  ('5a100000-0000-0000-0000-0000000000c3', '+233599100003', 'Lock C'),
  ('5a100000-0000-0000-0000-0000000000d4', '+233599100004', 'Lock D')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5a200000-0000-0000-0000-000000000001', '5a100000-0000-0000-0000-0000000000a1',
   '5a100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-10-01T00:00:00Z'),
  ('5a200000-0000-0000-0000-000000000002', '5a100000-0000-0000-0000-0000000000c3',
   '5a100000-0000-0000-0000-0000000000d4', 'active', CURRENT_DATE, now(), '2026-10-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- 1. The open UPDATE policy is gone and the privileges with it. SELECT and
--    INSERT (the inviter's pending row) stay.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy
             WHERE polrelid = 'public.relationships'::regclass AND polcmd IN ('w', '*')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an UPDATE policy still exists on relationships';
  END IF;
  IF has_table_privilege('authenticated', 'public.relationships', 'UPDATE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds UPDATE on relationships';
  END IF;
  IF has_table_privilege('authenticated', 'public.relationships', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds DELETE on relationships';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.relationships', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: members can no longer read relationships';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.relationships', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the inviter can no longer insert a pending row';
  END IF;
END $$;

-- 2. A member cannot rewrite any column from the client. Each statement must
--    fail with 42501 specifically; a different error (or success) is a hole.
DO $$
DECLARE v_sql text;
BEGIN
  PERFORM pg_temp.as_user('5a100000-0000-0000-0000-0000000000a1');
  FOREACH v_sql IN ARRAY ARRAY[
    $q$UPDATE public.relationships SET status = 'ended' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET status = 'paused' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET user_b = '5a100000-0000-0000-0000-0000000000c3' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET user_a = '5a100000-0000-0000-0000-0000000000b2', user_b = '5a100000-0000-0000-0000-0000000000a1' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET invite_accepted_at = now() WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET ended_at = now(), ended_by = '5a100000-0000-0000-0000-0000000000a1' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET chat_archived_at = now(), chat_archived_reason = 'manual_end' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET chat_name = 'Hijacked' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET last_overall_pulse = 99 WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$DELETE FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000001'$q$
  ] LOOP
    BEGIN
      EXECUTE v_sql;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a member ran: %', v_sql;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL; -- expected
    END;
  END LOOP;
  RESET ROLE;
  IF (SELECT status FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000001') <> 'active'
     OR (SELECT chat_name FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client write reached the row';
  END IF;
END $$;

-- 3. The RPC paths still write.
DO $$
BEGIN
  PERFORM pg_temp.as_user('5a100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_relationship_chat_name('5a200000-0000-0000-0000-000000000001', 'Us Two');
  RESET ROLE;
  IF (SELECT chat_name FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000001')
     IS DISTINCT FROM 'Us Two' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_relationship_chat_name no longer writes';
  END IF;

  PERFORM pg_temp.as_user('5a100000-0000-0000-0000-0000000000c3');
  PERFORM public.end_relationship('5a200000-0000-0000-0000-000000000002');
  RESET ROLE;
  IF (SELECT status FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000002')
     IS DISTINCT FROM 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: end_relationship no longer writes';
  END IF;
  RAISE NOTICE 'relationships_lockdown_contracts: all held';
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails on today's schema**

Run: `psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/relationships_lockdown_contracts.sql`
Expected: `ERROR:  CONTRACT VIOLATED: an UPDATE policy still exists on relationships`.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261017110000_relationships_write_lockdown_grants.sql
--
-- Relationships: no client UPDATE at all (Spec 1a Task 1; research 06 §3;
-- SPEC §11 constraints 11-12 depend on status and invite_accepted_at being
-- server-owned).
--
-- "relationship members update limited" (20260606120000:124-128) was never
-- limited: its USING / WITH CHECK test membership only, so either member could
-- rewrite status, user_a / user_b, invite_accepted_at, ended_at,
-- chat_archived_at or any later column from the client, and
-- 20260724120000:16 granted the table-level UPDATE that made the policy
-- reachable. Every legitimate write is already a SECURITY DEFINER RPC
-- (set_relationship_chat_name, set_relationship_avatar, end_relationship, the
-- chat-import and message-count functions) or a service-role worker
-- (accept-invite, create-relationship-invite), and lib/ holds no
-- .from('relationships').update/upsert/delete (grep, 2026-10-17). Dropping the
-- policy and the privilege changes no shipped behaviour.
--
-- Named *_grants.sql and replayed from scripts/local_pg_grants.sql: the local
-- harness blanket-grants every table to authenticated AFTER migrations, so
-- this REVOKE would otherwise be silently undone there.
DROP POLICY IF EXISTS "relationship members update limited" ON public.relationships;
REVOKE UPDATE, DELETE ON public.relationships FROM PUBLIC, anon, authenticated;
```

- [ ] **Step 4: Register the replay**

Snapshot first: `cp scripts/local_pg_grants.sql "$WS/snapshots/local_pg_grants.sql"`. Append to the end of `scripts/local_pg_grants.sql`:

```sql

-- Spec 1a (Task 1): relationships are read/insert only for clients; every
-- write is an RPC or the service role. Replayed so the blanket grant above
-- cannot hand UPDATE back locally.
\i supabase/migrations/20261017110000_relationships_write_lockdown_grants.sql
```

`diff -u "$WS/snapshots/local_pg_grants.sql" scripts/local_pg_grants.sql` shows exactly five added lines.

- [ ] **Step 5: Rebuild and run the contract**

Run:
```bash
ATTUNE_TEST_DB=attune_spec1a scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/relationships_lockdown_contracts.sql
```
Expected: `applied N, failed 0`; the contract prints only `NOTICE:  relationships_lockdown_contracts: all held`.

- [ ] **Step 6: Mutation-test the contract**

Run: `"$WS/mutant.sh" "GRANT UPDATE ON public.relationships TO authenticated; CREATE POLICY mutant_open ON public.relationships FOR UPDATE TO authenticated USING (true) WITH CHECK (true);" supabase/tests/relationships_lockdown_contracts.sql`
Expected: `ERROR:  CONTRACT VIOLATED: an UPDATE policy still exists on relationships` and `MUTANT KILLED`.

- [ ] **Step 7: Run the whole SQL suite once**

Run: `for t in supabase/tests/*.sql; do psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f "$t" >/dev/null 2>"$WS/err.txt" || { echo "FAIL $t"; head -2 "$WS/err.txt"; }; done`
Expected: no `FAIL` lines (no existing contract relied on client UPDATE of `relationships`; the fixtures that `UPDATE public.relationships` do so as the table owner).

- [ ] **Step 8: Ledger**

Append `Task 1: complete (relationships_lockdown_contracts green; mutant red). Regression risk: none found — no client write path existed.`

---

### Task 2: The "Show when we've seen things" setting (server)

**Files:**
- Create: `supabase/migrations/20261017120000_seen_receipts.sql`
- Create: `supabase/migrations/20261017120100_seen_receipts_table_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (append)
- Test: `supabase/tests/seen_receipts_contracts.sql`

**Interfaces:**
- Consumes: `relationships.invite_accepted_at` (now server-owned, Task 1); the `together_member_prefs` pattern (`20261014130000_together_daily.sql:5-38`).
- Produces (all `SET search_path = public`, SECURITY DEFINER):
  - table `public.seen_receipt_prefs(relationship_id uuid, user_id uuid, seen_on boolean NOT NULL DEFAULT false, updated_at timestamptz, PRIMARY KEY (relationship_id, user_id))` — no client grant.
  - `seen_receipts_effective(p_relationship_id uuid) RETURNS boolean` — internal (revoked from authenticated): the relationship is **active** and both members have a row and both are on. Paused or ended ⇒ false whatever the votes say.
  - `seen_receipts_member(p_relationship_id uuid) RETURNS uuid` — internal: `auth.uid()` if a member of an **active or paused**, unarchived relationship (a paused member must still be able to turn receipts off); raises `seen_receipts:unauthenticated` / `seen_receipts:not_found` (ERRCODE P0001).
  - `get_seen_receipts(p_relationship_id uuid) RETURNS jsonb` → `{"mine": bool, "effective": bool}` — authenticated.
  - `set_seen_receipts(p_relationship_id uuid, p_on boolean) RETURNS jsonb` → same shape; raises `seen_receipts:invalid_input` on NULL — authenticated.
  - `seen_receipts_backfill_defaults(p_cutoff timestamptz DEFAULT now()) RETURNS integer` — internal, idempotent; inserts `seen_on = true` for both members of every active/paused couple whose `invite_accepted_at` is NULL or before `p_cutoff`. The migration calls it with the default, so the cutoff **is the `db push` moment**: no constant to keep in step with a deploy date. Contracts pass an explicit cutoff.

**Design note (why `mine` + `effective`, and why the subtitle never names anyone):** with two people, "both required" means that whoever turned theirs on can infer the partner's state from the effective result; that inference is inherent to the rule, not a leak. What the RPC must never return is the partner's row itself, a timestamp, or an event — and it does not. Turning off writes no notification and no signal.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/seen_receipts_contracts.sql
-- "Show when we've seen things" (Spec 1a Task 2; research 06 §3 F4; SOUL §8;
-- SPEC §11.12). Every check RAISEs on violation.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5b100000-0000-0000-0000-000000000001'), ('5b100000-0000-0000-0000-000000000002'),
  ('5b100000-0000-0000-0000-000000000003'), ('5b100000-0000-0000-0000-000000000004'),
  ('5b100000-0000-0000-0000-000000000005'), ('5b100000-0000-0000-0000-000000000006'),
  ('5b100000-0000-0000-0000-000000000007')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5b100000-0000-0000-0000-000000000001', '+233599200001', 'Seen 1'),
  ('5b100000-0000-0000-0000-000000000002', '+233599200002', 'Seen 2'),
  ('5b100000-0000-0000-0000-000000000003', '+233599200003', 'Seen 3'),
  ('5b100000-0000-0000-0000-000000000004', '+233599200004', 'Seen 4'),
  ('5b100000-0000-0000-0000-000000000005', '+233599200005', 'Seen 5'),
  ('5b100000-0000-0000-0000-000000000006', '+233599200006', 'Seen 6'),
  ('5b100000-0000-0000-0000-000000000007', '+233599200007', 'Seen 7')
ON CONFLICT (id) DO NOTHING;
-- R1 linked before the cutoff, R2 linked exactly at it, R3 has no link time
-- (a legacy row). u7 is in no relationship.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5b200000-0000-0000-0000-000000000001', '5b100000-0000-0000-0000-000000000001',
   '5b100000-0000-0000-0000-000000000002', 'active', CURRENT_DATE, now(), '2026-10-01T00:00:00Z'),
  ('5b200000-0000-0000-0000-000000000002', '5b100000-0000-0000-0000-000000000003',
   '5b100000-0000-0000-0000-000000000004', 'active', CURRENT_DATE, now(), '2026-10-24T00:00:00Z'),
  ('5b200000-0000-0000-0000-000000000003', '5b100000-0000-0000-0000-000000000005',
   '5b100000-0000-0000-0000-000000000006', 'active', CURRENT_DATE, now(), NULL)
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
CREATE FUNCTION pg_temp.as_nobody() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;
CREATE FUNCTION pg_temp.expect_fail(p_sql text, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'CONTRACT VIOLATED: % succeeded (expected %)', p_sql, p_msg;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
    IF v_msg <> p_msg THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % raised "%" (expected "%")', p_sql, v_msg, p_msg;
    END IF;
  END;
END $$;

-- 1. The table is RPC-only.
DO $$
DECLARE v int;
BEGIN
  IF has_table_privilege('authenticated', 'public.seen_receipt_prefs', 'SELECT')
     OR has_table_privilege('authenticated', 'public.seen_receipt_prefs', 'INSERT')
     OR has_table_privilege('authenticated', 'public.seen_receipt_prefs', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.seen_receipt_prefs', 'DELETE')
     OR has_table_privilege('anon', 'public.seen_receipt_prefs', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client role holds a privilege on seen_receipt_prefs';
  END IF;
  IF has_function_privilege('authenticated', 'public.seen_receipts_effective(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.seen_receipts_member(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.seen_receipts_backfill_defaults(timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an internal seen_receipts function is client-executable';
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  BEGIN
    SELECT count(*) INTO v FROM public.seen_receipt_prefs;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member read seen_receipt_prefs directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO public.seen_receipt_prefs (relationship_id, user_id, seen_on)
    VALUES ('5b200000-0000-0000-0000-000000000001', '5b100000-0000-0000-0000-000000000001', true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member wrote seen_receipt_prefs directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
END $$;

-- 2. Default by link date: before the cutoff (or no link time) is on for both;
--    on/after the cutoff is off. The backfill is idempotent. (In production
--    the cutoff is the deploy moment itself: the migration calls the
--    function with its DEFAULT now().)
DO $$
DECLARE v_n int; v jsonb;
BEGIN
  -- Explicit cutoff: the migration used now() at deploy; the fixtures sit
  -- either side of this date on purpose.
  v_n := public.seen_receipts_backfill_defaults('2026-10-24T00:00:00Z');
  IF v_n < 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: backfill inserted % rows, expected at least 4 (R1 and R3)', v_n;
  END IF;
  IF (SELECT count(*) FROM public.seen_receipt_prefs
      WHERE relationship_id IN ('5b200000-0000-0000-0000-000000000001', '5b200000-0000-0000-0000-000000000003')
        AND seen_on) <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pre-cutoff couples were not defaulted on';
  END IF;
  IF EXISTS (SELECT 1 FROM public.seen_receipt_prefs WHERE relationship_id = '5b200000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a couple linked at the cutoff got default rows';
  END IF;
  IF public.seen_receipts_backfill_defaults('2026-10-24T00:00:00Z') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill is not idempotent';
  END IF;

  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000001');
  IF (v->>'mine') IS DISTINCT FROM 'true' OR (v->>'effective') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an older couple is not on by default: %', v;
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000003');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000002');
  IF (v->>'mine') IS DISTINCT FROM 'false' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new couple is not off by default: %', v;
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000005');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000003');
  IF (v->>'effective') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a legacy couple without a link time is not on: %', v;
  END IF;
  RESET ROLE;
END $$;

-- 3. Either off disables for both; the partner sees only the effective state.
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000001', false);
  IF (v->>'mine') IS DISTINCT FROM 'false' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one partner turning off did not turn it off: %', v;
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000002');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000001');
  IF (v->>'mine') IS DISTINCT FROM 'true' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner does not see effective off (own vote intact): %', v;
  END IF;
  IF v ? 'partner' OR v ? 'user_a' OR v ? 'user_b' OR v ? 'updated_at' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_seen_receipts exposes more than mine/effective: %', v;
  END IF;
  RESET ROLE;
END $$;

-- 4. Turning on requires both.
DO $$
DECLARE v jsonb;
BEGIN
  -- R1: u2 is still on, so u1 alone brings it back.
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000001', true);
  IF (v->>'effective') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: both on did not become effective: %', v;
  END IF;
  -- R2: the first vote alone changes nothing visible.
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000003');
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000002', true);
  IF (v->>'mine') IS DISTINCT FROM 'true' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one partner turned it on alone: %', v;
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000004');
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000002', true);
  IF (v->>'effective') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second vote did not turn it on: %', v;
  END IF;
  RESET ROLE;
END $$;

-- 5. Outsiders, the unauthenticated, ended couples and bad input.
DO $$
BEGIN
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000007');
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.get_seen_receipts('5b200000-0000-0000-0000-000000000001')$q$, 'seen_receipts:not_found');
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.set_seen_receipts('5b200000-0000-0000-0000-000000000001', true)$q$, 'seen_receipts:not_found');
  PERFORM pg_temp.as_nobody();
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.get_seen_receipts('5b200000-0000-0000-0000-000000000001')$q$, 'seen_receipts:unauthenticated');
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.set_seen_receipts('5b200000-0000-0000-0000-000000000001', NULL)$q$, 'seen_receipts:invalid_input');
  RESET ROLE;
  UPDATE public.relationships SET status = 'ended', ended_at = now(), chat_archived_at = now(), chat_archived_reason = 'manual_end'
   WHERE id = '5b200000-0000-0000-0000-000000000003';
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000005');
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.get_seen_receipts('5b200000-0000-0000-0000-000000000003')$q$, 'seen_receipts:not_found');
  RESET ROLE;
END $$;

-- 6. Paused (Review Focus 7): receipts stop flowing even with both votes on,
--    and a paused member can still turn theirs off (and back on).
DO $$
DECLARE v jsonb;
BEGIN
  -- R2 is on for both after block 4.
  UPDATE public.relationships SET status = 'paused' WHERE id = '5b200000-0000-0000-0000-000000000002';
  IF public.seen_receipts_effective('5b200000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: receipts stay effective while paused';
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000003');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000002');
  IF (v->>'mine') IS DISTINCT FROM 'true' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member sees the wrong state: %', v;
  END IF;
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000002', false);
  IF (v->>'mine') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member could not turn receipts off: %', v;
  END IF;
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000002', true);
  IF (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning on while paused became effective: %', v;
  END IF;
  RESET ROLE;
  UPDATE public.relationships SET status = 'active' WHERE id = '5b200000-0000-0000-0000-000000000002';
  IF NOT public.seen_receipts_effective('5b200000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: receipts did not resume on unpause with both votes on';
  END IF;
  RAISE NOTICE 'seen_receipts_contracts: all held';
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/seen_receipts_contracts.sql`
Expected: `ERROR:  relation "public.seen_receipt_prefs" does not exist` (from the first `has_table_privilege`).

- [ ] **Step 3: Write the behaviour migration**

```sql
-- supabase/migrations/20261017120000_seen_receipts.sql
--
-- "Show when we've seen things": one per-couple setting for chat read ticks
-- and story seen-state (Spec 1a Task 2; research 06 §3 F4; SOUL §8 "NEVER:
-- read receipts ... as defaults ... or re-enableable by one partner alone";
-- SPEC §11 constraint 12).
--
-- Storage: one row per (relationship, member), RPC-only, the same shape as
-- together_member_prefs. Effective = both rows present and both on. No row
-- means off, so a couple linked on or after the ship cutoff is off until both
-- turn it on. Either member's off is effective at once and the partner is
-- told nothing: no push, no signal, no event. The RPCs return the caller's
-- own vote and the effective state, never the partner's row.
--
-- The setting is NOT stored on relationships: until 20261017110000 members
-- could UPDATE that table from the client, and it is in the realtime
-- publication.

CREATE TABLE public.seen_receipt_prefs (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seen_on boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, user_id)
);
ALTER TABLE public.seen_receipt_prefs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.seen_receipt_prefs FROM PUBLIC, anon, authenticated;

-- The one place the rule lives. Internal: mark_conversation_read,
-- mark_story_viewed and the story list RPCs (all SECURITY DEFINER) call it.
-- Active only: a paused or ended couple shares nothing, whatever the votes.
CREATE FUNCTION public.seen_receipts_effective(p_relationship_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.relationships r
    JOIN public.seen_receipt_prefs a ON a.relationship_id = r.id AND a.user_id = r.user_a
    JOIN public.seen_receipt_prefs b ON b.relationship_id = r.id AND b.user_id = r.user_b
    WHERE r.id = p_relationship_id
      AND r.status = 'active'
      AND r.chat_archived_at IS NULL
      AND a.seen_on AND b.seen_on
  )
$$;
REVOKE ALL ON FUNCTION public.seen_receipts_effective(uuid) FROM PUBLIC, anon, authenticated;

-- The caller, if a member of this active OR PAUSED, unarchived relationship.
-- Paused is allowed so a paused member can still withdraw (SPEC §11.12 --
-- revocable alone, always); seen_receipts_effective is what keeps receipts
-- from flowing while paused.
CREATE FUNCTION public.seen_receipts_member(p_relationship_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'seen_receipts:unauthenticated' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status IN ('active', 'paused')
      AND r.chat_archived_at IS NULL
      AND (r.user_a = v_uid OR r.user_b = v_uid)
  ) THEN
    RAISE EXCEPTION 'seen_receipts:not_found' USING ERRCODE = 'P0001';
  END IF;
  RETURN v_uid;
END $$;
REVOKE ALL ON FUNCTION public.seen_receipts_member(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.get_seen_receipts(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.seen_receipts_member(p_relationship_id);
BEGIN
  RETURN jsonb_build_object(
    'mine', coalesce((SELECT p.seen_on FROM public.seen_receipt_prefs p
                       WHERE p.relationship_id = p_relationship_id AND p.user_id = v_me), false),
    'effective', public.seen_receipts_effective(p_relationship_id));
END $$;

CREATE FUNCTION public.set_seen_receipts(p_relationship_id uuid, p_on boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.seen_receipts_member(p_relationship_id);
BEGIN
  IF p_on IS NULL THEN
    RAISE EXCEPTION 'seen_receipts:invalid_input' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO public.seen_receipt_prefs (relationship_id, user_id, seen_on, updated_at)
  VALUES (p_relationship_id, v_me, p_on, now())
  ON CONFLICT (relationship_id, user_id)
  DO UPDATE SET seen_on = EXCLUDED.seen_on, updated_at = now();
  RETURN jsonb_build_object('mine', p_on, 'effective', public.seen_receipts_effective(p_relationship_id));
END $$;

REVOKE ALL ON FUNCTION public.get_seen_receipts(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_seen_receipts(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_seen_receipts(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_seen_receipts(uuid, boolean) TO authenticated;

-- Default by link date (research 06 §10 Q2: default off wins). Couples linked
-- before the cutoff keep today's behaviour, on for both until either turns it
-- off; couples linked on or after it get no rows, i.e. off. The DEFAULT is
-- now(): the migration's own call below makes the cutoff the deploy moment,
-- so there is no date constant to keep in step with a release. The contract
-- test passes an explicit cutoff. invite_accepted_at is trusted only because
-- 20261017110000 made it unwritable from the client. Idempotent.
CREATE FUNCTION public.seen_receipts_backfill_defaults(
  p_cutoff timestamptz DEFAULT now()
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  WITH ins AS (
    INSERT INTO public.seen_receipt_prefs (relationship_id, user_id, seen_on)
    SELECT r.id, m.user_id, true
    FROM public.relationships r
    CROSS JOIN LATERAL (VALUES (r.user_a), (r.user_b)) AS m(user_id)
    WHERE r.user_b IS NOT NULL
      AND r.status IN ('active', 'paused')
      AND (r.invite_accepted_at IS NULL OR r.invite_accepted_at < p_cutoff)
    ON CONFLICT (relationship_id, user_id) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM ins;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.seen_receipts_backfill_defaults(timestamptz) FROM PUBLIC, anon, authenticated;

DO $$ BEGIN PERFORM public.seen_receipts_backfill_defaults(); END $$;
```

- [ ] **Step 4: Write the grants migration and register the replay**

```sql
-- supabase/migrations/20261017120100_seen_receipts_table_grants.sql
-- seen_receipt_prefs is RPC-only. Repeated here so scripts/local_pg_grants.sql
-- can replay it after its blanket grant (same pattern as together/planning).
REVOKE ALL ON public.seen_receipt_prefs FROM PUBLIC, anon, authenticated;
```

Append to `scripts/local_pg_grants.sql`:
```sql

-- Spec 1a (Task 2): the seen-receipts votes are RPC-only.
\i supabase/migrations/20261017120100_seen_receipts_table_grants.sql
```

- [ ] **Step 5: Rebuild and run the contract**

Run:
```bash
ATTUNE_TEST_DB=attune_spec1a scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/seen_receipts_contracts.sql
```
Expected: `failed 0`; only `NOTICE:  seen_receipts_contracts: all held`.

- [ ] **Step 6: Mutation-test**

Run both; each must print a `CONTRACT VIOLATED` line and `MUTANT KILLED`:
```bash
"$WS/mutant.sh" "CREATE OR REPLACE FUNCTION public.seen_receipts_effective(p_relationship_id uuid) RETURNS boolean LANGUAGE sql AS \$\$ SELECT true \$\$;" supabase/tests/seen_receipts_contracts.sql
"$WS/mutant.sh" "GRANT SELECT ON public.seen_receipt_prefs TO authenticated;" supabase/tests/seen_receipts_contracts.sql
```
Expected: first → `CONTRACT VIOLATED: a new couple is not off by default` (block 2 trips before block 3's "one partner turning off" can); second → `CONTRACT VIOLATED: a client role holds a privilege on seen_receipt_prefs`.

- [ ] **Step 7: Ledger**

Append `Task 2: complete (seen_receipts_contracts green incl. paused block; 2 mutants killed; cutoff = deploy time via DEFAULT now()).`

---

### Task 3: Chat read receipts — private marker off the published table, column grants, unread count

**Files:**
- Create: `supabase/migrations/20261017130000_read_receipts_split.sql`
- Create: `supabase/migrations/20261017130100_messages_column_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (append)
- Modify: `supabase/tests/chat_system_contracts.sql` (two blocks: the replay block starting at the comment `-- Receipt RPC replay is monotonic` (today line 416) and the sender-side block starting at `-- The receipt round trip, from the SENDER's side.` (today line 605))
- Test: `supabase/tests/read_receipt_contracts.sql`

**Interfaces:**
- Consumes: `seen_receipts_effective(uuid)` (Task 2); `mark_conversation_read(uuid)` as defined in `20260705120000_chat_system_v1_2.sql:319-355`; `messages` columns (41 today, listed below); the `supabase_realtime` publication (`20260931210000`, `messages` is in it).
- Produces:
  - `public.message_reads(message_id uuid PRIMARY KEY REFERENCES messages ON DELETE CASCADE, reader_id uuid NOT NULL, read_at timestamptz NOT NULL DEFAULT now())` — the recipient's private read marker, **off the published table**, no client grant, never in the publication.
  - `messages.read_receipt_at timestamptz` — the sender-visible tick; written by `mark_conversation_read` **only while effective**, together with `delivered_at = COALESCE(delivered_at, now())` (a read tick implies delivery; while off, `delivered_at` is set only by the delivery RPCs the recipient's device already calls on fetch).
  - `messages.read_at` is **legacy only**: still written by the WhatsApp import worker (`v1_3:399-406`, history both already saw), never by `mark_conversation_read` again; counted as "read" by the unread count; not selectable by clients.
  - `mark_conversation_read(p_relationship_id uuid) RETURNS TABLE (id uuid, delivered_at timestamptz, read_at timestamptz)` — same signature; inserts `message_reads` rows for unread partner messages; while off it changes **no row of `messages`** (so the sender's realtime channel sees no UPDATE event at the read moment — Review Focus 6).
  - `count_unread_messages(p_relationship_id uuid) RETURNS integer` — SECURITY DEFINER, authenticated; partner messages with no `message_reads` row and `read_at IS NULL`, member, not archived.
  - `backfill_read_receipts(p_batch int DEFAULT 2000) RETURNS integer` — internal; copies `read_at → read_receipt_at` for couples that are effective-on, `p_batch` rows per call (M5: a published table is rewritten in slices, at a quiet time, see the hand-off). The migration runs it to completion only when fewer than 20 000 rows qualify.
  - `authenticated` SELECT on `messages` is exactly this allowlist (Task 5's `_messageColumns` must equal it): `id, relationship_id, sender_id, client_message_id, content, created_at, sort_at, game_session_id, delivered_at, read_receipt_at, media_url, media_thumbnail_url, media_type, media_duration_ms, media_waveform, media_width, media_height, source, reply_to_message_id, quoted_text, deleted_at, edited_at, is_view_once, viewed_at, is_system_notice, streak_views_remaining, story_item_id, message_origin, assistant_payload`.
  - Not selectable by clients: `read_at, tone_score, nvc_violations, bid_type, sentiment, message_analysis_done, message_analysis_skipped, included_in_session_id, safety_processed_at, safety_error_at, safety_error_code, import_job_id, source_line_number`.
  - `authenticated` holds no table-level UPDATE/DELETE on `messages` (no RLS policy ever allowed them; the grant from `20260914130000_streak_grants.sql:19` goes).

**Why a separate table (C1).** `messages` is in `supabase_realtime`. Column privileges strip a column from a change payload, but the UPDATE event still reaches every subscriber who passes RLS — the sender's chat channel (`supabase_chat_repository.dart:561-572`) and inbox channel (`:673-686`) would learn the exact read moment from the event alone. So while receipts are off, a read must write **nothing** to `messages`. `viewed_at` / `streak_views_remaining` (view-once media) stay as they are: ruling R-A.

Verified: the only RLS policies that read `messages` from another table (`message_media_select_relationship_members`, `message_edit_history_select`, `streak_clips_members_read`) reference `id, relationship_id, media_url, media_thumbnail_url` — all in the allowlist. The one SECURITY INVOKER trigger on `messages` (`messages_default_sort_at`) only touches `NEW`.

- [ ] **Step 1: Write the failing contract (new file)**

```sql
-- supabase/tests/read_receipt_contracts.sql
-- Chat receipts (Spec 1a Task 3): the recipient's read marker lives in
-- message_reads (not published, not client-readable); read_receipt_at is the
-- sender's tick and is written only while "Show when we've seen things" is
-- on; while off a read changes NO row of messages (realtime emits no event);
-- analysis columns are never client-readable (SOUL §8). Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5c100000-0000-0000-0000-0000000000a1'),
  ('5c100000-0000-0000-0000-0000000000b2'),
  ('5c100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5c100000-0000-0000-0000-0000000000a1', '+233599300001', 'Tick A'),
  ('5c100000-0000-0000-0000-0000000000b2', '+233599300002', 'Tick B'),
  ('5c100000-0000-0000-0000-0000000000c3', '+233599300003', 'Tick C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5c200000-0000-0000-0000-000000000001', '5c100000-0000-0000-0000-0000000000a1',
   '5c100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-11-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;
-- Two unread from A, one from B, and one legacy imported row from A that
-- carries read_at (the import worker's shape) and must count as read.
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, delivered_at, read_at, message_analysis_done, safety_processed_at) VALUES
  ('5c300000-0000-0000-0000-000000000001', '5c200000-0000-0000-0000-000000000001',
   '5c100000-0000-0000-0000-0000000000a1', '5c400000-0000-0000-0000-000000000001', 'one from A', now(), NULL, true, now()),
  ('5c300000-0000-0000-0000-000000000002', '5c200000-0000-0000-0000-000000000001',
   '5c100000-0000-0000-0000-0000000000a1', '5c400000-0000-0000-0000-000000000002', 'two from A', NULL, NULL, true, now()),
  ('5c300000-0000-0000-0000-000000000003', '5c200000-0000-0000-0000-000000000001',
   '5c100000-0000-0000-0000-0000000000b2', '5c400000-0000-0000-0000-000000000003', 'one from B', now(), NULL, true, now()),
  ('5c300000-0000-0000-0000-000000000004', '5c200000-0000-0000-0000-000000000001',
   '5c100000-0000-0000-0000-0000000000a1', '5c400000-0000-0000-0000-000000000004', 'imported from A', now(), now(), true, now())
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
-- A fingerprint of every messages row of the fixture couple: system column
-- xmin (changes on ANY update, even one that writes the same values) plus
-- the row contents.
CREATE FUNCTION pg_temp.messages_fingerprint() RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(m.xmin::text || ':' || md5(m::text), '|' ORDER BY m.id)
  FROM public.messages m WHERE m.relationship_id = '5c200000-0000-0000-0000-000000000001' $$;

-- 1. The client SELECT allowlist is exactly the Dart _messageColumns plus
--    nothing; message_reads has no client grant and is not published.
DO $$
DECLARE
  v_allow text[] := ARRAY[
    'id','relationship_id','sender_id','client_message_id','content','created_at',
    'sort_at','game_session_id','delivered_at','read_receipt_at','media_url',
    'media_thumbnail_url','media_type','media_duration_ms','media_waveform',
    'media_width','media_height','source','reply_to_message_id','quoted_text',
    'deleted_at','edited_at','is_view_once','viewed_at','is_system_notice',
    'streak_views_remaining','story_item_id','message_origin','assistant_payload'];
  v_private text[] := ARRAY[
    'read_at','tone_score','nvc_violations','bid_type','sentiment',
    'message_analysis_done','message_analysis_skipped','included_in_session_id',
    'safety_processed_at','safety_error_at','safety_error_code',
    'import_job_id','source_line_number'];
  v_actual text[];
  v_col text;
BEGIN
  IF has_table_privilege('authenticated', 'public.messages', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds table-level SELECT on messages (20260914130000 shape)';
  END IF;
  IF has_table_privilege('authenticated', 'public.messages', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.messages', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds UPDATE or DELETE on messages';
  END IF;
  IF NOT has_any_column_privilege('authenticated', 'public.messages', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the INSERT column allowlist (20260939020000) is gone';
  END IF;
  FOREACH v_col IN ARRAY v_private LOOP
    IF has_column_privilege('authenticated', 'public.messages', v_col, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated can select messages.%', v_col;
    END IF;
  END LOOP;
  SELECT array_agg(column_name::text ORDER BY column_name) INTO v_actual
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'messages'
    AND has_column_privilege('authenticated', 'public.messages', column_name::text, 'SELECT');
  IF v_actual IS DISTINCT FROM (SELECT array_agg(c ORDER BY c) FROM unnest(v_allow) AS c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: selectable columns % differ from the allowlist', v_actual;
  END IF;
  IF has_column_privilege('anon', 'public.messages', 'content', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can select messages.content';
  END IF;
  IF has_table_privilege('authenticated', 'public.message_reads', 'SELECT')
     OR has_any_column_privilege('authenticated', 'public.message_reads', 'SELECT')
     OR has_table_privilege('authenticated', 'public.message_reads', 'INSERT')
     OR has_table_privilege('anon', 'public.message_reads', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client role can reach message_reads';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_publication_tables
             WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'message_reads') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: message_reads is published (the read moment would stream)';
  END IF;
END $$;

-- 2. A member selecting read_at or an analysis column is refused with 42501,
--    even on their own message; the allowlist shape still works.
DO $$
DECLARE v_sql text; v_dummy text;
BEGIN
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  FOREACH v_sql IN ARRAY ARRAY[
    $q$SELECT read_at::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000001'$q$,
    $q$SELECT tone_score::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000003'$q$,
    $q$SELECT nvc_violations::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000003'$q$,
    $q$SELECT bid_type::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000003'$q$,
    $q$SELECT sentiment::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000003'$q$,
    $q$SELECT count(*)::text FROM public.messages WHERE relationship_id = '5c200000-0000-0000-0000-000000000001' AND read_at IS NULL$q$,
    $q$SELECT count(*)::text FROM public.message_reads$q$
  ] LOOP
    BEGIN
      EXECUTE v_sql INTO v_dummy;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a member ran: %', v_sql;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
  PERFORM id, relationship_id, sender_id, client_message_id, content, created_at,
          sort_at, game_session_id, delivered_at, read_receipt_at, media_url,
          media_thumbnail_url, media_type, media_duration_ms, media_waveform,
          media_width, media_height, source, reply_to_message_id, quoted_text,
          deleted_at, edited_at, is_view_once, viewed_at, is_system_notice,
          streak_views_remaining, story_item_id, message_origin, assistant_payload
  FROM public.messages WHERE relationship_id = '5c200000-0000-0000-0000-000000000001';
  RESET ROLE;
END $$;

-- 3. While receipts are off (no prefs rows for this couple): the badge
--    counts and clears, the legacy imported row counts as read, and a read
--    changes NO row of messages -- no realtime event (Review Focus 6).
DO $$
DECLARE v int; v_before text; v_after text; v_marked int;
BEGIN
  IF NOT has_function_privilege('authenticated', 'public.count_unread_messages(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot execute count_unread_messages';
  END IF;
  IF has_function_privilege('anon', 'public.count_unread_messages(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can execute count_unread_messages';
  END IF;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000b2');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B expected 2 unread (imported row excluded), got %', v; END IF;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: A expected 1 unread, got %', v; END IF;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000c3');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider counted % unread', v; END IF;

  RESET ROLE;
  v_before := pg_temp.messages_fingerprint();
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_marked FROM public.mark_conversation_read('5c200000-0000-0000-0000-000000000001');
  IF v_marked <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: mark_conversation_read marked % rows, expected 2', v_marked; END IF;
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B still has % unread after reading (receipts off)', v; END IF;
  -- Replay marks nothing more.
  SELECT count(*) INTO v_marked FROM public.mark_conversation_read('5c200000-0000-0000-0000-000000000001');
  IF v_marked <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed read marked % rows', v_marked; END IF;
  RESET ROLE;
  v_after := pg_temp.messages_fingerprint();
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read while receipts were off changed a messages row (realtime would have fired)';
  END IF;
  IF (SELECT count(*) FROM public.message_reads
      WHERE reader_id = '5c100000-0000-0000-0000-0000000000b2') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the private marker was not written';
  END IF;
  IF EXISTS (SELECT 1 FROM public.messages
             WHERE relationship_id = '5c200000-0000-0000-0000-000000000001' AND read_receipt_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: read_receipt_at was written while receipts were off';
  END IF;
  -- The undelivered row stays undelivered: a read while off is not a
  -- delivery either (that comes from the device's own delivery RPCs).
  IF (SELECT delivered_at FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000002') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read while off produced a delivery tick';
  END IF;
END $$;

-- 4. While on: the tick is written (and implies delivery); the recipient's
--    count is unaffected by the setting; archived chats count nothing.
DO $$
DECLARE v int; v_fp text;
BEGIN
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, message_analysis_done, safety_processed_at)
  VALUES ('5c300000-0000-0000-0000-000000000005', '5c200000-0000-0000-0000-000000000001',
          '5c100000-0000-0000-0000-0000000000a1', '5c400000-0000-0000-0000-000000000005', 'three from A', true, now())
  ON CONFLICT (id) DO NOTHING;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_seen_receipts('5c200000-0000-0000-0000-000000000001', true);
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000b2');
  PERFORM public.set_seen_receipts('5c200000-0000-0000-0000-000000000001', true);
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B expected 1 unread, got %', v; END IF;
  PERFORM public.mark_conversation_read('5c200000-0000-0000-0000-000000000001');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B still has % unread after reading (receipts on)', v; END IF;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  IF (SELECT read_receipt_at IS NULL OR delivered_at IS NULL FROM public.messages
      WHERE id = '5c300000-0000-0000-0000-000000000005') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read while on did not produce a receipt that implies delivery';
  END IF;
  -- The two messages read while off stay without a tick, now and forever.
  IF EXISTS (SELECT 1 FROM public.messages WHERE id IN
             ('5c300000-0000-0000-0000-000000000001', '5c300000-0000-0000-0000-000000000002')
             AND read_receipt_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning receipts on revealed reads made while off';
  END IF;
  RESET ROLE;
  UPDATE public.relationships SET chat_archived_at = now(), chat_archived_reason = 'manual_end'
   WHERE id = '5c200000-0000-0000-0000-000000000001';
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an archived chat still counts % unread', v; END IF;
  RESET ROLE;
  RAISE NOTICE 'read_receipt_contracts: all held';
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/read_receipt_contracts.sql`
Expected: `ERROR:  CONTRACT VIOLATED: authenticated holds table-level SELECT on messages (20260914130000 shape)`.

- [ ] **Step 3: Write the behaviour migration**

```sql
-- supabase/migrations/20261017130000_read_receipts_split.sql
--
-- Chat read receipts (Spec 1a Task 3; research 06 §3 F4 (5)).
--
-- messages.read_at did two jobs: the recipient's own unread marker and the
-- sender's "Read" tick. Both leave it:
--
--   * The recipient's marker moves to message_reads, a table with no client
--     grant that is NOT in the realtime publication. messages IS published,
--     and a column privilege strips a column from a change payload but not
--     the UPDATE event itself -- the sender's chat/inbox channels would
--     learn the read moment from the event alone. So while receipts are
--     off, a read must change no row of messages at all.
--   * The sender's tick becomes read_receipt_at, written by
--     mark_conversation_read only while the couple's "Show when we've seen
--     things" is on (together with delivered_at, since a read tick implies
--     delivery). A read made while off is never written there, so it can
--     never be shown later, including after both turn it back on.
--   * read_at stays only as the WhatsApp import worker's legacy marker
--     (v1_3:399-406 writes read_at = created_at; both already saw that
--     history). It is not client-selectable (20261017130100) and counts as
--     "read" for the badge.
CREATE TABLE public.message_reads (
  message_id uuid PRIMARY KEY REFERENCES public.messages(id) ON DELETE CASCADE,
  reader_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.message_reads FROM PUBLIC, anon, authenticated;

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read_receipt_at timestamptz;

CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_relationship_id uuid)
RETURNS TABLE (
  id uuid,
  delivered_at timestamptz,
  read_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_on boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.chat_archived_at IS NULL
      AND (r.user_a = v_uid OR r.user_b = v_uid)
  ) THEN
    RETURN;
  END IF;
  v_on := public.seen_receipts_effective(p_relationship_id);

  RETURN QUERY
  WITH marked (mid, rat) AS (
    -- The private marker. Never touches messages.
    INSERT INTO public.message_reads (message_id, reader_id)
    SELECT m.id, v_uid
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.sender_id <> v_uid
      AND m.read_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.message_reads x WHERE x.message_id = m.id)
    ON CONFLICT (message_id) DO NOTHING
    RETURNING message_reads.message_id, message_reads.read_at
  ),
  ticked (tid) AS (
    -- The sender-visible tick, only while on. With v_on false this UPDATE
    -- matches no row, so nothing is written and nothing streams.
    UPDATE public.messages m
    SET read_receipt_at = now(),
        delivered_at = COALESCE(m.delivered_at, now())
    FROM marked
    WHERE v_on AND m.id = marked.mid
    RETURNING m.id
  )
  SELECT marked.mid, m.delivered_at, marked.rat
  FROM marked
  JOIN public.messages m ON m.id = marked.mid
  LEFT JOIN ticked ON ticked.tid = marked.mid;
END;
$$;

-- The recipient's badge. Mirrors the former client query
-- (supabase_chat_repository._fetchUnreadCount): partner messages not yet
-- read by me, member, not archived. A legacy imported row (read_at set)
-- counts as read. Deleted rows count exactly as before.
CREATE OR REPLACE FUNCTION public.count_unread_messages(p_relationship_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::integer
  FROM public.messages m
  JOIN public.relationships r ON r.id = m.relationship_id
  WHERE m.relationship_id = p_relationship_id
    AND auth.uid() IS NOT NULL
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    AND r.chat_archived_at IS NULL
    AND m.sender_id <> auth.uid()
    AND m.read_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.message_reads x WHERE x.message_id = m.id)
$$;
REVOKE ALL ON FUNCTION public.count_unread_messages(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.count_unread_messages(uuid) TO authenticated;

-- Couples that keep today's behaviour (both on after 20261017120000's
-- backfill) keep their existing ticks: copy read_at -> read_receipt_at.
-- messages is a published table, so this rewrites rows in slices
-- (p_batch per call) rather than in one statement; each call is its own
-- small burst of WAL and realtime events. The migration runs it to
-- completion only for a small table; otherwise the owner loops it at a
-- quiet time (hand-off, Task 9).
CREATE OR REPLACE FUNCTION public.backfill_read_receipts(p_batch int DEFAULT 2000)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer;
BEGIN
  WITH todo AS (
    SELECT m.id
    FROM public.messages m
    WHERE m.read_at IS NOT NULL
      AND m.read_receipt_at IS NULL
      AND public.seen_receipts_effective(m.relationship_id)
    ORDER BY m.id
    LIMIT GREATEST(1, p_batch)
  ),
  done AS (
    UPDATE public.messages m
    SET read_receipt_at = m.read_at
    FROM todo
    WHERE m.id = todo.id
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM done;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.backfill_read_receipts(int) FROM PUBLIC, anon, authenticated;

DO $$
DECLARE v_total bigint; v_n integer;
BEGIN
  SELECT count(*) INTO v_total FROM public.messages WHERE read_at IS NOT NULL AND read_receipt_at IS NULL;
  IF v_total <= 20000 THEN
    LOOP
      v_n := public.backfill_read_receipts(2000);
      EXIT WHEN v_n = 0;
    END LOOP;
  ELSE
    RAISE NOTICE 'read receipts: % rows to backfill -- run SELECT public.backfill_read_receipts(2000) in a loop at a quiet time', v_total;
  END IF;
END $$;
```

- [ ] **Step 4: Write the grants migration and register the replay**

```sql
-- supabase/migrations/20261017130100_messages_column_grants.sql
--
-- messages: the client SELECT allowlist (Spec 1a Task 3); message_reads:
-- no client grant at all.
--
-- 20260914130000_streak_grants.sql:19 re-granted table-level SELECT, INSERT,
-- UPDATE on messages to authenticated, cancelling the column allowlist from
-- 20260705190000:35-47. Since then both partners could read read_at AND the
-- per-message analysis columns (tone_score, nvc_violations, bid_type,
-- sentiment ...), which SOUL §8 forbids showing to a partner. Table-level
-- REVOKE does not remove column grants, so every private column is revoked
-- by name as well, then the allowlist is granted. The allowlist is exactly
-- what the Dart client selects (supabase_chat_repository._messageColumns) --
-- read_receipt_at in, read_at out -- and read_receipt_contracts.sql asserts
-- the two sets are equal, so a new column is private until added here.
--
-- Replayed from scripts/local_pg_grants.sql after its blanket grant.
REVOKE SELECT, UPDATE, DELETE ON public.messages FROM PUBLIC, anon, authenticated;
REVOKE SELECT (
  read_at, tone_score, nvc_violations, bid_type, sentiment,
  message_analysis_done, message_analysis_skipped, included_in_session_id,
  safety_processed_at, safety_error_at, safety_error_code,
  import_job_id, source_line_number
) ON public.messages FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id, relationship_id, sender_id, client_message_id, content, created_at,
  sort_at, game_session_id, delivered_at, read_receipt_at, media_url,
  media_thumbnail_url, media_type, media_duration_ms, media_waveform,
  media_width, media_height, source, reply_to_message_id, quoted_text,
  deleted_at, edited_at, is_view_once, viewed_at, is_system_notice,
  streak_views_remaining, story_item_id, message_origin, assistant_payload
) ON public.messages TO authenticated;
REVOKE ALL ON public.message_reads FROM PUBLIC, anon, authenticated;
```

Append to `scripts/local_pg_grants.sql`:
```sql

-- Spec 1a (Task 3): messages SELECT allowlist (no read_at, no analysis
-- columns), no UPDATE/DELETE; message_reads RPC-only. Must come after the
-- story-reply replay above, which only touches INSERT.
\i supabase/migrations/20261017130100_messages_column_grants.sql
```

- [ ] **Step 5: Update the two blocks in `chat_system_contracts.sql`**

Snapshot: `cp supabase/tests/chat_system_contracts.sql "$WS/snapshots/chat_system_contracts.sql"`.

(a) Replace the replay block — from the comment line `-- Receipt RPC replay is monotonic: a second mark_conversation_read does not` through that `DO $$ … $$;` block's closing `$$;` — with:

```sql
-- Receipt RPC replay is monotonic: a second mark_conversation_read does not
-- change the already-set marker, and re-marking delivered is a no-op once read
-- (Spec 16 "Receipt RPC replay -> timestamp remains monotonic and unchanged").
-- The recipient's marker lives in message_reads since Spec 1a (not
-- client-readable), so it is read here as the table owner.
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE
  v_first_read timestamptz;
  v_second_read timestamptz;
  v_replayed int;
  v_redelivered int;
BEGIN
  RESET ROLE;
  SELECT read_at INTO v_first_read
  FROM public.message_reads
  WHERE message_id = '20000000-0000-0000-0000-000000000002';
  IF v_first_read IS NULL THEN
    RAISE EXCEPTION 'the first read left no message_reads row';
  END IF;
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000a1');

  -- Replay read: nothing left to mark, so the RPC returns no row for it.
  SELECT count(*) INTO v_replayed
  FROM public.mark_conversation_read('10000000-0000-0000-0000-000000000001')
  WHERE id = '20000000-0000-0000-0000-000000000002';
  IF v_replayed <> 0 THEN
    RAISE EXCEPTION 'mark_conversation_read replay re-marked an already-read message';
  END IF;

  RESET ROLE;
  SELECT read_at INTO v_second_read
  FROM public.message_reads
  WHERE message_id = '20000000-0000-0000-0000-000000000002';
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
  IF v_second_read IS DISTINCT FROM v_first_read THEN
    RAISE EXCEPTION 'read marker changed on replay (% -> %)', v_first_read, v_second_read;
  END IF;

  -- Replay delivered on an already-delivered message returns no rows.
  SELECT count(*) INTO v_redelivered
  FROM public.mark_delivered(ARRAY['20000000-0000-0000-0000-000000000002'::uuid]);
  IF v_redelivered <> 0 THEN
    RAISE EXCEPTION 'mark_delivered replay unexpectedly updated an already-delivered message';
  END IF;
END
$$;
```

(b) Replace the sender-side block — from the comment line `-- The receipt round trip, from the SENDER's side.` through its `DO $$ … $$;` — with:

```sql
-- The receipt round trip, from the SENDER's side (Spec 1a: gated by the
-- couple's "Show when we've seen things").
--
-- The fixture couple has no seen_receipt_prefs rows, so the setting is off:
-- B reading must leave A a delivery tick (from mark_delivered) and NO read
-- tick, A must not be able to select read_at, and the read must not change
-- any messages row (realtime). Once both turn it on, a NEW read shows; the
-- read that happened while off never does; one partner turning it off again
-- stops new receipts at once.
DO $$
DECLARE v_delivered boolean; v_receipt boolean; v_leak boolean; v_before text; v_after text;
BEGIN
  -- B marks A's message delivered (the device's own delivery RPC), then
  -- reads the conversation while off.
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000b2');
  PERFORM public.mark_delivered(ARRAY['20000000-0000-0000-0000-000000000001'::uuid]);
  RESET ROLE;
  SELECT string_agg(m.xmin::text || ':' || md5(m::text), '|' ORDER BY m.id) INTO v_before
  FROM public.messages m WHERE m.relationship_id = '10000000-0000-0000-0000-000000000001';
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000b2');
  PERFORM public.mark_conversation_read('10000000-0000-0000-0000-000000000001');
  RESET ROLE;
  SELECT string_agg(m.xmin::text || ':' || md5(m::text), '|' ORDER BY m.id) INTO v_after
  FROM public.messages m WHERE m.relationship_id = '10000000-0000-0000-0000-000000000001';
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read while receipts were off changed a messages row';
  END IF;

  -- A sees delivered, and no receipt.
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
  SELECT delivered_at IS NOT NULL, read_receipt_at IS NOT NULL
    INTO v_delivered, v_receipt
  FROM public.messages WHERE id = '20000000-0000-0000-0000-000000000001';
  IF NOT v_delivered THEN
    RAISE EXCEPTION 'the sender cannot see their own delivery receipt';
  END IF;
  IF v_receipt THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read while receipts were off produced a receipt';
  END IF;

  -- A cannot read the legacy private marker either.
  BEGIN
    SELECT read_at IS NOT NULL INTO v_leak
    FROM public.messages WHERE id = '20000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sender can select messages.read_at';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  -- Both turn it on.
  PERFORM public.set_seen_receipts('10000000-0000-0000-0000-000000000001', true);
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000b2');
  PERFORM public.set_seen_receipts('10000000-0000-0000-0000-000000000001', true);

  -- The earlier read stays hidden.
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
  SELECT read_receipt_at IS NOT NULL INTO v_receipt
  FROM public.messages WHERE id = '20000000-0000-0000-0000-000000000001';
  IF v_receipt THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning receipts on revealed a read made while off';
  END IF;

  -- A new message from A, read by B while on: A sees the receipt, and the
  -- receipt implies delivered (spec 5.2).
  RESET ROLE;
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, message_analysis_done, safety_processed_at)
  VALUES ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001',
          '00000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-000000000003',
          'second from A', true, now())
  ON CONFLICT (id) DO NOTHING;
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000b2');
  PERFORM public.mark_conversation_read('10000000-0000-0000-0000-000000000001');
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
  SELECT delivered_at IS NOT NULL, read_receipt_at IS NOT NULL
    INTO v_delivered, v_receipt
  FROM public.messages WHERE id = '20000000-0000-0000-0000-000000000003';
  IF NOT v_receipt THEN
    RAISE EXCEPTION 'the sender cannot see their read receipt while the setting is on';
  END IF;
  IF NOT v_delivered THEN
    RAISE EXCEPTION 'read_receipt_at is set but delivered_at is not (spec 5.2)';
  END IF;

  -- B turns it off alone: a further read shows nothing new to A.
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000b2');
  PERFORM public.set_seen_receipts('10000000-0000-0000-0000-000000000001', false);
  RESET ROLE;
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, message_analysis_done, safety_processed_at)
  VALUES ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001',
          '00000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-000000000004',
          'third from A', true, now())
  ON CONFLICT (id) DO NOTHING;
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000b2');
  PERFORM public.mark_conversation_read('10000000-0000-0000-0000-000000000001');
  PERFORM public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
  SELECT read_receipt_at IS NOT NULL INTO v_receipt
  FROM public.messages WHERE id = '20000000-0000-0000-0000-000000000004';
  IF v_receipt THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one partner turning receipts off did not stop them';
  END IF;
END
$$;
```

The earlier block `-- mark_conversation_read: recipient reads partner messages; read_at implies delivered_at` (today lines 394-414) needs no change: it reads the RPC's RETURNING (`read_at` now comes from `message_reads`, `delivered_at` from the fixture's already-delivered row). `diff -u "$WS/snapshots/chat_system_contracts.sql" supabase/tests/chat_system_contracts.sql` must show changes in the two blocks above only.

- [ ] **Step 6: Rebuild and run**

Run:
```bash
ATTUNE_TEST_DB=attune_spec1a scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/read_receipt_contracts.sql
psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/chat_system_contracts.sql
for t in supabase/tests/*.sql; do psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f "$t" >/dev/null 2>"$WS/err.txt" || { echo "FAIL $t"; head -2 "$WS/err.txt"; }; done
```
Expected: `failed 0`; both files green; the loop prints no `FAIL`. If a pre-existing contract selects a now-private column as `authenticated`, read its failing line: the fix is to `RESET ROLE` around that read (as in Step 5a), never to widen the grant. Record each such edit in the ledger.

- [ ] **Step 7: Mutation-test**

```bash
"$WS/mutant.sh" "GRANT SELECT (read_at) ON public.messages TO authenticated;" supabase/tests/read_receipt_contracts.sql
"$WS/mutant.sh" "CREATE OR REPLACE FUNCTION public.seen_receipts_effective(p_relationship_id uuid) RETURNS boolean LANGUAGE sql AS \$\$ SELECT true \$\$;" supabase/tests/read_receipt_contracts.sql
"$WS/mutant.sh" "CREATE OR REPLACE FUNCTION public.seen_receipts_effective(p_relationship_id uuid) RETURNS boolean LANGUAGE sql AS \$\$ SELECT true \$\$;" supabase/tests/chat_system_contracts.sql
```
Expected: `CONTRACT VIOLATED: authenticated can select messages.read_at`; `CONTRACT VIOLATED: a read while receipts were off changed a messages row (realtime would have fired)`; `CONTRACT VIOLATED: a read while receipts were off changed a messages row`. All three `MUTANT KILLED`.

- [ ] **Step 8: Ledger**

Append `Task 3: complete (read_receipt_contracts + chat_system_contracts green; 3 mutants killed; message_reads off the published table). Regression risk: any client select of a column outside the allowlist now fails with 42501 — Task 5 changes _messageColumns to match; no other lib/ query selects from messages. A read while off no longer produces a delivery tick (delivery comes from the device's own delivery RPCs, as before for fetched rows).`

---
### Task 4: Story seen-state — mask the author, keep the viewer, no timing bump

**Files:**
- Create: `supabase/migrations/20261017140000_story_seen_state.sql`
- Create: `supabase/migrations/20261017140100_story_items_column_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (append)
- Modify: `supabase/tests/story_rpc_contracts.sql` (Task 6 block: two inserted lines after the fresh relationship insert, today line 886-889)
- Modify: `supabase/tests/story_security_contracts.sql:51-53` (`has_table_privilege` → `has_any_column_privilege`)
- Modify: `lib/features/stories/presentation/screens/story_reel_screen.dart:673` (one added line)
- Modify: `test/features/stories/story_reel_test.dart` (`_FakeReelGateway.getRingSummary` counts calls; one new test)
- Test: `supabase/tests/story_seen_state_contracts.sql`

**Interfaces:**
- Consumes: `seen_receipts_effective(uuid)`; `mark_story_viewed(uuid)` (`20260938060000`), `list_active_story_items`, `list_story_day_items`, `get_story_ring_summary` (`20260938080000`), `bump_story_signal(uuid)`, `story_relationship_is_open(uuid, uuid)`.
- Produces:
  - `story_items.seen_shown boolean NOT NULL DEFAULT false` — set by `mark_story_viewed` on the first view **only while effective**; never selectable by clients.
  - `list_active_story_items(...)` and `list_story_day_items(...)` keep their signatures and `RETURNS SETOF public.story_items` but become SECURITY DEFINER with the RLS predicate inlined, and return `has_been_viewed` as: viewer's own state on a partner's item; `seen_receipts_effective AND seen_shown` on the caller's own item; `seen_shown` always `false` in the output.
  - `get_story_ring_summary(uuid)` becomes SECURITY DEFINER with the same membership/deleted predicate; output unchanged.
  - `mark_story_viewed(uuid)` bumps `story_change_signals` only while effective. The viewer's own client refreshes its ring locally instead (Dart change below).
  - `authenticated` SELECT on `story_items` is the column list minus `has_been_viewed, seen_shown`.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/story_seen_state_contracts.sql
-- Story seen-state under "Show when we've seen things" (Spec 1a Task 4).
-- The viewer always sees their own state; the author sees a view only while
-- the setting is on AND the view happened while it was on; a view while off
-- bumps no author-visible signal. Every check RAISEs on violation.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5d100000-0000-0000-0000-0000000000a1'),
  ('5d100000-0000-0000-0000-0000000000b2'),
  ('5d100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5d100000-0000-0000-0000-0000000000a1', '+233599400001', 'Story A'),
  ('5d100000-0000-0000-0000-0000000000b2', '+233599400002', 'Story B'),
  ('5d100000-0000-0000-0000-0000000000c3', '+233599400003', 'Story C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1',
   '5d100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-11-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;
-- Three stories by A, inserted as the owner (the finalize RPC is covered by
-- story_rpc_contracts; this file is about reads).
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type,
  media_key, thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
SELECT s.id, s.id, '5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1', 'image',
  'story-media/5d/' || s.n || '/media', 'story-media/5d/' || s.n || '/thumb', 1080, 1920,
  CURRENT_DATE, now() - interval '1 minute' + (s.n || ' second')::interval,
  now() - interval '1 minute' + (s.n || ' second')::interval + interval '24 hours'
FROM (VALUES ('5d300000-0000-0000-0000-000000000001'::uuid, 1),
             ('5d300000-0000-0000-0000-000000000002'::uuid, 2),
             ('5d300000-0000-0000-0000-000000000003'::uuid, 3)) AS s(id, n)
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
-- has_been_viewed as the CURRENT caller sees it through the reel RPC.
CREATE FUNCTION pg_temp.reel_seen(p_story uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT has_been_viewed FROM public.list_active_story_items(
    '5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1')
  WHERE id = p_story $$;
CREATE FUNCTION pg_temp.day_seen(p_story uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT has_been_viewed FROM public.list_story_day_items(
    '5d200000-0000-0000-0000-000000000001', CURRENT_DATE)
  WHERE id = p_story $$;
CREATE FUNCTION pg_temp.signal() RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT version FROM public.story_change_signals
                   WHERE relationship_id = '5d200000-0000-0000-0000-000000000001'), 0) $$;

-- 1. Grants: the two seen columns are never client-selectable; the rest are.
DO $$
DECLARE v int;
BEGIN
  IF has_table_privilege('authenticated', 'public.story_items', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds table-level SELECT on story_items';
  END IF;
  IF NOT has_any_column_privilege('authenticated', 'public.story_items', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot read story_items at all';
  END IF;
  IF has_column_privilege('authenticated', 'public.story_items', 'has_been_viewed', 'SELECT')
     OR has_column_privilege('authenticated', 'public.story_items', 'seen_shown', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a seen column is client-selectable';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.story_items', 'media_key', 'SELECT')
     OR NOT has_column_privilege('authenticated', 'public.story_items', 'thumbnail_key', 'SELECT')
     OR NOT has_column_privilege('authenticated', 'public.story_items', 'occurred_on', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a needed story_items column is not selectable';
  END IF;
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  BEGIN
    SELECT count(*) INTO v FROM public.story_items WHERE has_been_viewed;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author selected has_been_viewed directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  SELECT count(*) INTO v FROM public.story_items WHERE relationship_id = '5d200000-0000-0000-0000-000000000001';
  IF v <> 3 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the allowlisted read returned % rows', v; END IF;
  RESET ROLE;
END $$;

-- 2. Off (no prefs rows): the partner's view is recorded for the partner,
--    hidden from the author, and bumps no signal.
DO $$
DECLARE v_before bigint; v jsonb; v_row public.story_items%ROWTYPE; v_ring record;
BEGIN
  v_before := pg_temp.signal();
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  v := public.mark_story_viewed('5d300000-0000-0000-0000-000000000001');
  IF (v->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'setup: the partner''s view was refused: %', v;
  END IF;
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the viewer does not see their own view';
  END IF;
  SELECT * INTO v_ring FROM public.get_story_ring_summary('5d200000-0000-0000-0000-000000000001')
   WHERE author_id = '5d100000-0000-0000-0000-0000000000a1';
  IF v_ring.unviewed_count <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: viewer ring expected 2 unviewed, got %', v_ring.unviewed_count;
  END IF;

  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author learned of a view while receipts were off (reel)';
  END IF;
  IF pg_temp.day_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author learned of a view while receipts were off (day)';
  END IF;
  RESET ROLE;
  IF pg_temp.signal() <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view while off bumped story_change_signals';
  END IF;
  SELECT * INTO v_row FROM public.story_items WHERE id = '5d300000-0000-0000-0000-000000000001';
  IF v_row.has_been_viewed IS DISTINCT FROM true OR v_row.seen_shown IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stored state wrong after an off view (% / %)', v_row.has_been_viewed, v_row.seen_shown;
  END IF;
END $$;

-- 3. On (both): a NEW view shows to the author and bumps the signal once; the
--    earlier off-view stays hidden.
DO $$
DECLARE v_before bigint; v jsonb;
BEGIN
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_seen_receipts('5d200000-0000-0000-0000-000000000001', true);
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  PERFORM public.set_seen_receipts('5d200000-0000-0000-0000-000000000001', true);
  RESET ROLE;
  v_before := pg_temp.signal();
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  v := public.mark_story_viewed('5d300000-0000-0000-0000-000000000002');
  IF (v->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'setup: the partner''s second view was refused: %', v;
  END IF;
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000002') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author does not see a view made while on';
  END IF;
  IF pg_temp.day_seen('5d300000-0000-0000-0000-000000000002') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the day list hides a view made while on';
  END IF;
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning receipts on revealed a view made while off';
  END IF;
  RESET ROLE;
  IF pg_temp.signal() <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view while on did not bump the signal exactly once';
  END IF;
END $$;

-- 4. Off again by one partner: hidden again at once; a further view is hidden
--    for good; on again shows only views made while on.
DO $$
DECLARE v_before bigint; v jsonb;
BEGIN
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_seen_receipts('5d200000-0000-0000-0000-000000000001', false);
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000002') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one partner turning off did not hide seen-state';
  END IF;
  RESET ROLE;
  v_before := pg_temp.signal();
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  v := public.mark_story_viewed('5d300000-0000-0000-0000-000000000003');
  RESET ROLE;
  IF pg_temp.signal() <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view after turning off bumped the signal';
  END IF;
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_seen_receipts('5d200000-0000-0000-0000-000000000001', true);
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000002') IS DISTINCT FROM true
     OR pg_temp.reel_seen('5d300000-0000-0000-0000-000000000003') IS DISTINCT FROM false
     OR pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after re-enabling, only views made while on may show';
  END IF;
  -- The viewer's own view of their state never changed through any of this.
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM true
     OR pg_temp.reel_seen('5d300000-0000-0000-0000-000000000003') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the viewer lost their own seen state';
  END IF;
  -- seen_shown itself is never returned as true to anyone.
  IF EXISTS (SELECT 1 FROM public.list_active_story_items(
               '5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1')
             WHERE seen_shown) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: seen_shown leaked through the list RPC';
  END IF;
  RESET ROLE;
END $$;

-- 5. Outsiders get nothing from the definer RPCs.
DO $$
DECLARE v int;
BEGIN
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000c3');
  SELECT count(*) INTO v FROM public.list_active_story_items(
    '5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider listed % reel items', v; END IF;
  SELECT count(*) INTO v FROM public.list_story_day_items('5d200000-0000-0000-0000-000000000001', CURRENT_DATE);
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider listed % day items', v; END IF;
  SELECT count(*) INTO v FROM public.get_story_ring_summary('5d200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider got % ring rows', v; END IF;
  RESET ROLE;
  RAISE NOTICE 'story_seen_state_contracts: all held';
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/story_seen_state_contracts.sql`
Expected: `ERROR:  CONTRACT VIOLATED: authenticated holds table-level SELECT on story_items`.

- [ ] **Step 3: Write the behaviour migration**

```sql
-- supabase/migrations/20261017140000_story_seen_state.sql
--
-- Story seen-state under "Show when we've seen things" (Spec 1a Task 4;
-- research 06 §3 F4 (1)).
--
-- story_items.has_been_viewed did two jobs (the viewer's own "new/seen" ring
-- and the author's "my partner saw it"), and the list RPCs were SECURITY
-- INVOKER returning si.*, so the author read it on their own rows. The
-- first view also bumped story_change_signals, which the author's client
-- subscribes to -- the moment of the view leaked even with the column hidden.
--
-- Now:
--   * has_been_viewed stays the viewer's state. A new seen_shown is the
--     author-facing boolean, set on the first view ONLY while the couple's
--     setting is on. Neither column is client-selectable (20261017140100);
--     the list RPCs become SECURITY DEFINER, inline the former RLS predicate,
--     and return has_been_viewed = (effective AND seen_shown) on the caller's
--     own items, has_been_viewed as stored on the partner's, and seen_shown
--     = false always.
--   * mark_story_viewed bumps the signal only while on. The viewer's own
--     client refreshes its ring locally after a view (story_reel_screen).
ALTER TABLE public.story_items ADD COLUMN IF NOT EXISTS seen_shown boolean NOT NULL DEFAULT false;

-- Couples that keep today's behaviour keep today's seen marks.
UPDATE public.story_items si
   SET seen_shown = true
 WHERE si.has_been_viewed
   AND NOT si.seen_shown
   AND public.seen_receipts_effective(si.relationship_id);

CREATE OR REPLACE FUNCTION public.list_active_story_items(
  p_relationship_id   uuid,
  p_author_id         uuid,
  p_after_created_at  timestamptz DEFAULT NULL,
  p_after_id          uuid DEFAULT NULL,
  p_limit             int DEFAULT 50
)
RETURNS SETOF public.story_items
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (jsonb_populate_record(si, jsonb_build_object(
            'has_been_viewed',
              CASE WHEN si.author_id = auth.uid() THEN (s.v_on AND si.seen_shown)
                   ELSE si.has_been_viewed END,
            'seen_shown', false))).*
    FROM public.story_items si
   CROSS JOIN (SELECT public.seen_receipts_effective(p_relationship_id) AS v_on) s
   WHERE si.relationship_id = p_relationship_id
     AND si.author_id = p_author_id
     AND si.deleted_at IS NULL
     AND public.story_relationship_is_open(si.relationship_id, auth.uid())
     AND si.expires_at > now()
     AND (
       p_after_created_at IS NULL
       OR (si.created_at, si.id) > (p_after_created_at, p_after_id)
     )
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

CREATE OR REPLACE FUNCTION public.list_story_day_items(
  p_relationship_id   uuid,
  p_occurred_on       date,
  p_after_created_at  timestamptz DEFAULT NULL,
  p_after_id          uuid DEFAULT NULL,
  p_limit             int DEFAULT 50
)
RETURNS SETOF public.story_items
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
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
     AND si.deleted_at IS NULL
     AND public.story_relationship_is_open(si.relationship_id, auth.uid())
     AND (
       p_after_created_at IS NULL
       OR (si.created_at, si.id) > (p_after_created_at, p_after_id)
     )
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

-- Viewer-side only (unviewed_count already excludes the caller's own items),
-- but it reads has_been_viewed, which the client role can no longer select.
CREATE OR REPLACE FUNCTION public.get_story_ring_summary(
  p_relationship_id uuid
)
RETURNS TABLE (
  author_id             uuid,
  active_count          bigint,
  unviewed_count        bigint,
  newest_thumbnail_key  text,
  newest_created_at     timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    si.author_id,
    count(*) AS active_count,
    count(*) FILTER (
      WHERE si.author_id <> auth.uid() AND NOT si.has_been_viewed
    ) AS unviewed_count,
    (array_agg(si.thumbnail_key ORDER BY si.created_at DESC))[1]
      AS newest_thumbnail_key,
    max(si.created_at) AS newest_created_at
  FROM public.story_items si
 WHERE si.relationship_id = p_relationship_id
   AND si.deleted_at IS NULL
   AND public.story_relationship_is_open(p_relationship_id, auth.uid())
   AND si.expires_at > now()
 GROUP BY si.author_id
$$;

CREATE OR REPLACE FUNCTION public.mark_story_viewed(
  p_story_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user  uuid := auth.uid();
  v_story public.story_items%ROWTYPE;
  v_inserted boolean;
  v_on boolean;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  IF p_story_item_id IS NULL THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  SELECT * INTO v_story
    FROM public.story_items
   WHERE id = p_story_item_id
   FOR UPDATE;

  IF v_story.id IS NULL
     OR v_story.deleted_at IS NOT NULL
     OR v_story.author_id IS NOT DISTINCT FROM v_user
     OR v_story.expires_at <= now()
     OR NOT public.story_relationship_is_open(v_story.relationship_id, v_user)
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  INSERT INTO public.story_views (story_item_id, viewer_id)
  VALUES (p_story_item_id, v_user)
  ON CONFLICT (story_item_id, viewer_id) DO NOTHING;
  v_inserted := FOUND;

  IF v_inserted THEN
    v_on := public.seen_receipts_effective(v_story.relationship_id);
    -- The viewer's own state always; the author-facing mark only while on.
    UPDATE public.story_items
       SET has_been_viewed = true,
           seen_shown = seen_shown OR v_on
     WHERE id = p_story_item_id;
    -- The author's client listens to this signal, so while off a view must
    -- not move it (Spec 1a; spec1-map-f4 §0.4).
    IF v_on THEN
      PERFORM public.bump_story_signal(v_story.relationship_id);
    END IF;
  END IF;

  RETURN jsonb_build_object('error', false, 'viewed', true);
END;
$$;
```

(`REVOKE`/`GRANT` on these four functions are unchanged: `CREATE OR REPLACE` keeps existing privileges.)

- [ ] **Step 4: Write the grants migration and register the replay**

```sql
-- supabase/migrations/20261017140100_story_items_column_grants.sql
--
-- story_items: the client SELECT allowlist (Spec 1a Task 4). has_been_viewed
-- and seen_shown are read only through the SECURITY DEFINER list RPCs, which
-- mask them. Every other column stays readable (the reel, the calendar, the
-- reply-target lookup and the storage policy need them).
--
-- Replayed from scripts/local_pg_grants.sql AFTER the stories replay there,
-- which grants table-level SELECT.
REVOKE SELECT ON public.story_items FROM PUBLIC, anon, authenticated;
REVOKE SELECT (has_been_viewed, seen_shown) ON public.story_items FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, duration_ms, occurred_on,
  created_at, expires_at, deleted_at, downscaled_at
) ON public.story_items TO authenticated;
```

Append to `scripts/local_pg_grants.sql`:
```sql

-- Spec 1a (Task 4): story_items SELECT allowlist (no has_been_viewed, no
-- seen_shown). After the stories replay above, which grants the whole table.
\i supabase/migrations/20261017140100_story_items_column_grants.sql
```

- [ ] **Step 5: Update the two existing story contracts**

Snapshot both: `cp supabase/tests/story_rpc_contracts.sql supabase/tests/story_security_contracts.sql "$WS/snapshots/"`.

(a) `story_security_contracts.sql` lines 51-53: replace
```sql
  IF NOT has_table_privilege('authenticated','public.story_items','SELECT') THEN
    RAISE EXCEPTION 'authenticated cannot read story_items';
  END IF;
```
with
```sql
  -- Column-level since Spec 1a (has_been_viewed/seen_shown are RPC-only).
  IF NOT has_any_column_privilege('authenticated','public.story_items','SELECT') THEN
    RAISE EXCEPTION 'authenticated cannot read story_items';
  END IF;
```

(b) `story_rpc_contracts.sql`, Task 6 block: directly after the statement that creates the fresh relationship (`INSERT INTO public.relationships(user_a, user_b, status) VALUES (… c401 …, … c402 …, 'active') RETURNING id INTO v_rel;`), insert:
```sql
  -- Spec 1a: this block's "seen" and "signal bumps once" contracts describe a
  -- couple with "Show when we've seen things" ON. Turn it on for both.
  INSERT INTO public.seen_receipt_prefs (relationship_id, user_id, seen_on)
  VALUES (v_rel, '00000000-0000-0000-0000-00000000c401'::uuid, true),
         (v_rel, '00000000-0000-0000-0000-00000000c402'::uuid, true);
```
Diff each against its snapshot: exactly those lines.

- [ ] **Step 6: The viewer refreshes its own ring locally (Dart)**

Snapshot `lib/features/stories/presentation/screens/story_reel_screen.dart` and `test/features/stories/story_reel_test.dart`.

First the failing test. In `_FakeReelGateway`, change `getRingSummary` to count:
```dart
  int ringSummaryCalls = 0;

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async {
    ringSummaryCalls++;
    return const [];
  }
```
and add this test inside `main()` (after the existing groups):
```dart
  testWidgets(
    'a partner view refreshes my own ring locally (Spec 1a: the server bumps '
    'no signal while receipts are off)',
    (tester) async {
      final gateway = _FakeReelGateway(
        items: [_item(id: 'a', createdAt: DateTime.utc(2026, 9, 1))],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_signedInUser),
            storyReadGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Column(
              children: [
                // Keeps the autoDispose ring provider alive, as the rings row
                // under the reel does in the app.
                Consumer(
                  builder: (_, ref, __) {
                    ref.watch(storyRingSummaryProvider(_relationshipId));
                    return const SizedBox.shrink();
                  },
                ),
                Expanded(
                  child: StoryReelScreen(
                    relationshipId: _relationshipId,
                    authorId: _partnerId,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      // The ring provider fetched once when the Consumer first built --
      // before any item rendered or _maybeMarkViewed (unawaited) ran.
      expect(gateway.ringSummaryCalls, 1, reason: 'one initial fetch');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(gateway.markViewedCalls, ['a']);
      // markViewed is awaited inside _maybeMarkViewed, which nobody awaits;
      // give the invalidate a few frames to land.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        gateway.ringSummaryCalls,
        greaterThanOrEqualTo(2),
        reason: 'at least one more fetch after the view',
      );
    },
  );
```
(`storyRingSummaryProvider` comes from `package:attune/features/stories/presentation/providers/story_providers.dart`; add the import if the file does not already import it.)

Run: `flutter test test/features/stories/story_reel_test.dart --plain-name "refreshes my own ring"`
Expected: FAIL at the final `greaterThanOrEqualTo(2)` (actual 1).

Then in `story_reel_screen.dart`, inside `_maybeMarkViewed`, change
```dart
      await ref.read(storyReadGatewayProvider).markViewed(storyItemId: item.id);
```
to
```dart
      await ref.read(storyReadGatewayProvider).markViewed(storyItemId: item.id);
      // Spec 1a: the server bumps story_change_signals only while the couple
      // shows seen-state, so my own ring refreshes from here instead.
      if (mounted) ref.invalidate(storyRingSummaryProvider(widget.relationshipId));
```
Run the test again. Expected: PASS. Then `flutter test test/features/stories` → all pass. Diff both files against their snapshots.

- [ ] **Step 7: Rebuild and run the SQL**

Run:
```bash
ATTUNE_TEST_DB=attune_spec1a scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
for f in story_seen_state_contracts story_rpc_contracts story_security_contracts story_read_contracts story_schema_contracts story_storage_policy_isolation_contracts story_places_contracts seen_receipts_contracts; do psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/$f.sql >/dev/null 2>"$WS/err.txt" && echo "PASS $f" || { echo "FAIL $f"; head -2 "$WS/err.txt"; }; done
```
Expected: all `PASS`.

- [ ] **Step 8: Mutation-test**

```bash
"$WS/mutant.sh" "CREATE OR REPLACE FUNCTION public.seen_receipts_effective(p_relationship_id uuid) RETURNS boolean LANGUAGE sql AS \$\$ SELECT true \$\$;" supabase/tests/story_seen_state_contracts.sql
"$WS/mutant.sh" "GRANT SELECT (has_been_viewed) ON public.story_items TO authenticated;" supabase/tests/story_seen_state_contracts.sql
```
Expected: `CONTRACT VIOLATED: the author learned of a view while receipts were off (reel)` and `CONTRACT VIOLATED: a seen column is client-selectable`; both `MUTANT KILLED`.

- [ ] **Step 9: Analyzer and ledger**

Run: `flutter analyze lib/features/stories/presentation/screens/story_reel_screen.dart test/features/stories/story_reel_test.dart 2>&1 | grep -E "^\s*(error|warning) "` → nothing.
Append `Task 4: complete (story_seen_state_contracts green; 2 mutants red; reel refreshes ring locally). Regression risk: list RPCs now definer — outsider test (block 5) covers the inlined RLS.`

---

### Task 5: Dart chat client — receipt column, unread RPC, read gate

**Files:**
- Create: `lib/features/chat/domain/services/unread_count.dart`
- Modify: `lib/features/chat/domain/entities/message.dart:189` (`readAt` from `read_receipt_at`)
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart:35-42` (`_messageColumns`) and `:899-910` (`_fetchUnreadCount`)
- Modify: `lib/features/chat/presentation/state/chat_state.dart:309` (new field) and `:2294-2314` (`markAsRead`)
- Modify: `test/features/chat/support/chat_test_harness.dart:170-172` (row key)
- Test: `test/features/chat/message_model_test.dart` (new group), `test/features/chat/unread_count_test.dart` (new), `test/features/chat/chat_controller_test.dart` (new test in `receipts + presence`)

**Interfaces:**
- Consumes: `read_receipt_at`, `count_unread_messages(uuid)` (Task 3).
- Produces:
  - `Message.readAt` now means "the receipt the viewer may see" (null on a partner message read while receipts are off; set on my own message only when the partner read it while on).
  - `int parseUnreadCount(Object? raw)` — tolerant of a bare number, a list, or a map (PostgREST scalar RPC shape).
  - `ChatController.markAsRead()` calls the RPC at most once per set of visible partner messages while receipts are off (`_markedReadIds`).

- [ ] **Step 1: Write the failing tests**

Append to `test/features/chat/message_model_test.dart` (inside `main()`, after the existing groups):
```dart
  group('read receipts (Spec 1a)', () {
    Map<String, dynamic> row({String? readAt, String? receiptAt}) => {
      'id': 'm1',
      'relationship_id': 'r1',
      'sender_id': 'me',
      'client_message_id': 'c1',
      'content': 'hi',
      'created_at': '2026-10-17T10:00:00Z',
      'delivered_at': '2026-10-17T10:01:00Z',
      'read_at': readAt,
      'read_receipt_at': receiptAt,
      'media_url': null,
      'media_thumbnail_url': null,
      'media_type': null,
      'source': 'native',
    };

    test('the tick comes from read_receipt_at only', () {
      final m = Message.fromRow(
        row(receiptAt: '2026-10-17T10:05:00Z'),
        currentUserId: 'me',
      );
      expect(m.status, MessageStatus.read);
      expect(m.readAt, DateTime.utc(2026, 10, 17, 10, 5).toLocal());
    });

    test('a private read_at alone never becomes a tick', () {
      // read_at is not selectable by clients any more; if a stale cache or a
      // misconfigured grant ever hands it over, it still must not render.
      final m = Message.fromRow(
        row(readAt: '2026-10-17T10:05:00Z'),
        currentUserId: 'me',
      );
      expect(m.readAt, isNull);
      expect(m.status, MessageStatus.delivered);
    });
  });
```

New `test/features/chat/unread_count_test.dart`:
```dart
import 'package:attune/features/chat/domain/services/unread_count.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a bare number is the count', () {
    expect(parseUnreadCount(3), 3);
    expect(parseUnreadCount(3.0), 3);
  });

  test('wrapped shapes are unwrapped', () {
    expect(parseUnreadCount([2]), 2);
    expect(parseUnreadCount({'count_unread_messages': 4}), 4);
    expect(
      parseUnreadCount([
        {'count_unread_messages': 5},
      ]),
      5,
    );
  });

  test('anything else is zero, never a throw', () {
    expect(parseUnreadCount(null), 0);
    expect(parseUnreadCount('x'), 0);
    expect(parseUnreadCount(const []), 0);
    expect(parseUnreadCount(-1), 0);
  });
}
```

In `test/features/chat/chat_controller_test.dart`, inside `group('receipts + presence', …)` after the test `'marking read is suppressed until the view is active'`, add:
```dart
    test('receipts off: a message already marked is not re-marked on the '
        'next sync (Spec 1a)', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'hi from partner',
        createdAt: DateTime.now(),
      );
      final b = await boot(repo);

      b.controller.setViewActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(repo.markReadCalls, hasLength(1));

      // The fake, like the server while receipts are off, leaves readAt null
      // on the partner's message. Another visible sync must not call again.
      await b.controller.markAsRead();
      await b.controller.markAsRead();
      expect(repo.markReadCalls, hasLength(1));
    });
```

- [ ] **Step 2: Run them to verify they fail**

Run:
```bash
flutter test test/features/chat/message_model_test.dart --plain-name "read receipts"
flutter test test/features/chat/unread_count_test.dart
flutter test test/features/chat/chat_controller_test.dart --plain-name "not re-marked"
```
Expected: model test FAILS ("a private read_at alone never becomes a tick": status read, readAt not null); unread test FAILS to compile (`unread_count.dart` missing); controller test FAILS (`markReadCalls` has length 3).

- [ ] **Step 3: Implement**

Snapshot the four shared files first:
```bash
cp lib/features/chat/domain/entities/message.dart "$WS/snapshots/message.dart"
cp lib/features/chat/data/repositories/supabase_chat_repository.dart "$WS/snapshots/supabase_chat_repository.dart"
cp lib/features/chat/presentation/state/chat_state.dart "$WS/snapshots/chat_state.dart"
cp test/features/chat/support/chat_test_harness.dart "$WS/snapshots/chat_test_harness.dart"
```

`message.dart`, in `Message.fromRow`, replace
```dart
    final readAt = _parseDateTime(row['read_at']);
```
with
```dart
    // The receipt the viewer may see (Spec 1a): written by the server only
    // while the couple shows seen-state. read_at itself is the recipient's
    // private marker and is not selectable by clients.
    final readAt = _parseDateTime(row['read_receipt_at']);
```

New `lib/features/chat/domain/services/unread_count.dart`:
```dart
/// Parses the result of the `count_unread_messages` RPC.
///
/// PostgREST returns a scalar function's value bare; some wrappers hand it
/// back as `[{"count_unread_messages": n}]`. A badge must never throw, so
/// anything unrecognised (or negative) is 0.
int parseUnreadCount(Object? raw) {
  if (raw is num) return raw < 0 ? 0 : raw.toInt();
  if (raw is List) return raw.isEmpty ? 0 : parseUnreadCount(raw.first);
  if (raw is Map) return raw.isEmpty ? 0 : parseUnreadCount(raw.values.first);
  return 0;
}
```

`supabase_chat_repository.dart`: in `_messageColumns` replace the line
```dart
      'delivered_at,read_at,media_url,media_thumbnail_url,media_type,'
```
with
```dart
      'delivered_at,read_receipt_at,media_url,media_thumbnail_url,media_type,'
```
and replace `_fetchUnreadCount` with
```dart
  Future<int> _fetchUnreadCount(
    String relationshipId,
    String currentUserId,
  ) async {
    // read_at is the recipient's private marker and is not selectable by
    // clients (Spec 1a); the count comes from a SECURITY DEFINER reader.
    final raw = await _supabase.rpc(
      'count_unread_messages',
      params: {'p_relationship_id': relationshipId},
    );
    return parseUnreadCount(raw);
  }
```
with `import 'package:attune/features/chat/domain/services/unread_count.dart';` added to the file's imports (keep the existing import order style: package imports alphabetical).

`chat_state.dart`: after the line `Timer? _readDebounce;` add
```dart

  /// Partner messages already reported read in this session. While the
  /// couple's seen-state is off the server never sets a receipt on them, so
  /// without this every visible sync would call mark_conversation_read again
  /// (Spec 1a). Pruned to the loaded window after each call.
  final Set<String> _markedReadIds = <String>{};
```
and replace the body of `markAsRead()` from `if (!_isViewActive) return;` to the end of the method with
```dart
    if (!_isViewActive) return;
    final pending = state.messages
        .where(
          (message) =>
              !message.isMine &&
              message.readAt == null &&
              !_markedReadIds.contains(message.id),
        )
        .map((message) => message.id)
        .toList();
    if (pending.isEmpty) return;
    try {
      await ref
          .read(chatRepositoryProvider)
          .markConversationRead(relationshipId);
      _markedReadIds
        ..addAll(pending)
        ..retainAll(state.messages.map((message) => message.id).toSet());
    } catch (_) {
      // Idempotent; a later visible sync retries.
    }
```

`chat_test_harness.dart`, in `seedIncoming`'s row map, replace
```dart
      'read_at': readAt?.toUtc().toIso8601String(),
```
with
```dart
      'read_receipt_at': readAt?.toUtc().toIso8601String(),
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/chat`
Expected: all pass (the harness rename keeps every existing "Read" assertion green because `seedIncoming(readAt:)` now feeds the column the model reads).

- [ ] **Step 5: Diff, format the new file, analyze**

```bash
for f in message.dart supabase_chat_repository.dart chat_state.dart chat_test_harness.dart; do echo "== $f"; diff -u "$WS/snapshots/$f" "$(find lib test -name $f | head -1)"; done
dart format lib/features/chat/domain/services/unread_count.dart test/features/chat/unread_count_test.dart
flutter analyze lib/features/chat/domain/entities/message.dart lib/features/chat/data/repositories/supabase_chat_repository.dart lib/features/chat/presentation/state/chat_state.dart lib/features/chat/domain/services/unread_count.dart test/features/chat/support/chat_test_harness.dart test/features/chat/message_model_test.dart test/features/chat/unread_count_test.dart test/features/chat/chat_controller_test.dart 2>&1 | grep -E "^\s*(error|warning) "
```
Expected: each diff shows only the lines above; the grep prints nothing.

- [ ] **Step 6: Ledger**

Append `Task 5: complete (chat suite green; model/unread/controller tests added). Regression risk: _messageColumns must stay equal to the SQL allowlist (read_receipt_contracts asserts the SQL side; the Dart list is the mirror). Local encrypted cache keeps old readAt values until the next fetch (pre-cutoff couples were backfilled so nothing visibly changes).`

---

### Task 6: The toggle, its provider, and the Ask 1 line

**Files:**
- Create: `lib/features/chat/domain/seen_receipts.dart` (the `SeenReceipts` model and the copy)
- Create: `lib/features/chat/data/seen_receipts_repository.dart` (repository and providers)
- Modify: `lib/features/chat/presentation/widgets/chat_settings_static_rows.dart` (first `CardInkWell`, between "Share my location" and "End relationship")
- Modify: `lib/features/onboarding/presentation/widgets/couples_joined_step.dart` (one line under the tiles)
- Test: `test/features/chat/seen_receipts_repository_test.dart`, `test/features/chat/chat_settings_seen_receipts_toggle_test.dart`, `test/features/onboarding/couples_joined_step_test.dart`

**Interfaces:**
- Consumes: `get_seen_receipts(uuid)`, `set_seen_receipts(uuid, boolean)` (Task 2); `supabaseClientProvider` from `lib/features/games/presentation/providers/games_hub_providers.dart`; `InfoRowWidget(isToggleItem: true, toggleValue:, onToggleChanged:)`; `OnboardingInfoTile`.
- Produces:
  - `typedef SeenReceiptsRpc = Future<dynamic> Function(String fn, Map<String, dynamic> params);`
  - `class SeenReceipts { final bool mine; final bool effective; static const off; factory fromJson(Object? raw); }`
  - `class SeenReceiptsRepository { SeenReceiptsRepository(SeenReceiptsRpc rpc); Future<SeenReceipts> get(String relationshipId); Future<SeenReceipts> set(String relationshipId, bool on); }`
  - `seenReceiptsRepositoryProvider`, `seenReceiptsProvider` (`FutureProvider.autoDispose.family<SeenReceipts, String>`).
  - Copy: `seenReceiptsTitle`, `seenReceiptsAsk1Line`, `seenReceiptsFailureCopy`, `String seenReceiptsSubtitle(SeenReceipts s)`.

- [ ] **Step 1: Write the failing tests**

`test/features/chat/seen_receipts_repository_test.dart`:
```dart
import 'package:attune/features/chat/data/seen_receipts_repository.dart';
import 'package:attune/features/chat/domain/seen_receipts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson reads mine/effective and defaults to off', () {
    expect(
      SeenReceipts.fromJson({'mine': true, 'effective': false}),
      const SeenReceipts(mine: true, effective: false),
    );
    expect(SeenReceipts.fromJson(null), SeenReceipts.off);
    expect(SeenReceipts.fromJson({'effective': 'yes'}), SeenReceipts.off);
  });

  test('get and set call the two RPCs with the relationship id', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    final repo = SeenReceiptsRepository((fn, params) async {
      calls.add((fn, params));
      return {'mine': params['p_on'] ?? false, 'effective': false};
    });
    await repo.get('r1');
    final after = await repo.set('r1', true);
    expect(calls, [
      ('get_seen_receipts', {'p_relationship_id': 'r1'}),
      ('set_seen_receipts', {'p_relationship_id': 'r1', 'p_on': true}),
    ]);
    expect(after, const SeenReceipts(mine: true, effective: false));
  });

  test('the subtitle is honest about each state and never names anyone', () {
    expect(
      seenReceiptsSubtitle(const SeenReceipts(mine: true, effective: true)),
      'On for both of you. Read ticks and story seen marks show. Either of you can turn this off.',
    );
    expect(
      seenReceiptsSubtitle(const SeenReceipts(mine: true, effective: false)),
      "Turns on once you've both turned it on.",
    );
    expect(
      seenReceiptsSubtitle(SeenReceipts.off),
      'Off. Read ticks and story seen marks stay hidden for both of you. Turn it on together whenever you like.',
    );
    expect(seenReceiptsTitle, "Show when we've seen things");
    expect(
      seenReceiptsAsk1Line,
      'Read receipts are off to start. Turn them on together whenever you like.',
    );
  });
}
```

`test/features/chat/chat_settings_seen_receipts_toggle_test.dart`:
```dart
// test/features/chat/chat_settings_seen_receipts_toggle_test.dart
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/chat/data/seen_receipts_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/seen_receipts.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/widgets/chat_settings_static_rows.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../location/presence_repository_test.dart'
    show FakePresenceGateway, FakeSampler;

Conversation _conversation() => Conversation(
  id: 'c1',
  relationshipId: 'r1',
  partnerId: 'p1',
  name: 'Partner',
  updatedAt: DateTime.utc(2026, 10, 1),
  relationshipStatus: 'active',
  availability: ConversationAvailability.active,
  unreadCount: 0,
);

/// A server double: holds each member's vote; `effective` is both on.
class _FakeSeenServer {
  _FakeSeenServer({this.mine = false, this.partner = false, this.failSet = false});
  bool mine;
  bool partner;
  bool failSet;
  final calls = <(String, Map<String, dynamic>)>[];

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    calls.add((fn, params));
    if (fn == 'set_seen_receipts') {
      if (failSet) throw Exception('offline');
      mine = params['p_on'] as bool;
    }
    return {'mine': mine, 'effective': mine && partner};
  }
}

Future<_FakeSeenServer> _pump(
  WidgetTester t,
  Conversation? c, {
  _FakeSeenServer? server,
}) async {
  final s = server ?? _FakeSeenServer();
  final g = FakePresenceGateway({'couple_map_presence': (_) => const []});
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        presenceGatewayProvider.overrideWithValue(g),
        presenceSamplerProvider.overrideWithValue(
          FakeSampler(
            next: const PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40),
          ),
        ),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        chatHistoricalImportEnabledProvider.overrideWith((ref) async => false),
        seenReceiptsRepositoryProvider.overrideWithValue(
          SeenReceiptsRepository(s.call),
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ChatSettingsStaticRows(conversation: c),
                ),
              ),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return s;
}

InfoRowWidget _toggle(WidgetTester t) => t.widget<InfoRowWidget>(
  find.widgetWithText(InfoRowWidget, seenReceiptsTitle),
);

void main() {
  testWidgets('a new couple reads off, with the off subtitle', (t) async {
    await _pump(t, _conversation());
    expect(_toggle(t).toggleValue, isFalse);
    expect(find.text(seenReceiptsSubtitle(SeenReceipts.off)), findsOneWidget);
  });

  testWidgets('turning on alone shows my vote and the waiting line', (t) async {
    final s = await _pump(t, _conversation());
    _toggle(t).onToggleChanged!(true);
    await t.pumpAndSettle();
    expect(s.calls.map((c) => c.$1), contains('set_seen_receipts'));
    expect(s.calls.last.$2, {'p_relationship_id': 'r1', 'p_on': true});
    expect(_toggle(t).toggleValue, isTrue);
    expect(find.text("Turns on once you've both turned it on."), findsOneWidget);
  });

  testWidgets('both on reads on; turning off calls set false', (t) async {
    final s = await _pump(
      t,
      _conversation(),
      server: _FakeSeenServer(mine: true, partner: true),
    );
    expect(_toggle(t).toggleValue, isTrue);
    expect(
      find.text(seenReceiptsSubtitle(const SeenReceipts(mine: true, effective: true))),
      findsOneWidget,
    );
    _toggle(t).onToggleChanged!(false);
    await t.pumpAndSettle();
    expect(s.calls.last, ('set_seen_receipts', {'p_relationship_id': 'r1', 'p_on': false}));
    expect(_toggle(t).toggleValue, isFalse);
  });

  testWidgets('the row never names who turned it off', (t) async {
    await _pump(
      t,
      _conversation(),
      server: _FakeSeenServer(mine: true, partner: false),
    );
    expect(find.textContaining('partner turned'), findsNothing);
    expect(find.textContaining('Partner'), findsNothing);
  });

  testWidgets('a failed switch says so and re-reads the real state', (t) async {
    final s = await _pump(
      t,
      _conversation(),
      server: _FakeSeenServer(failSet: true),
    );
    final reads = s.calls.where((c) => c.$1 == 'get_seen_receipts').length;
    _toggle(t).onToggleChanged!(true);
    await t.pumpAndSettle();
    expect(find.text(seenReceiptsFailureCopy), findsOneWidget);
    expect(
      s.calls.where((c) => c.$1 == 'get_seen_receipts').length,
      greaterThan(reads),
    );
    expect(_toggle(t).toggleValue, isFalse);
  });

  testWidgets('with no conversation the toggle is off and calls nothing', (t) async {
    final s = await _pump(t, null);
    _toggle(t).onToggleChanged!(true);
    await t.pumpAndSettle();
    expect(_toggle(t).toggleValue, isFalse);
    expect(s.calls, isEmpty);
  });
}
```

`test/features/onboarding/couples_joined_step_test.dart`:
```dart
import 'package:attune/features/chat/domain/seen_receipts.dart';
import 'package:attune/features/onboarding/presentation/widgets/couples_joined_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Ask 1 tells a new couple receipts are off to start (F4 (4))', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => Scaffold(
                  body: OnboardingDeckScope(
                    cardKey: 0,
                    accent: OnboardingDeckAccent.neutral,
                    enableDeck: false,
                    child: CouplesJoinedStep(onFinish: () {}),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You are connected'), findsOneWidget);
    expect(find.text(seenReceiptsAsk1Line), findsOneWidget);
    // Ask 1 copy carries no intelligence vocabulary (AUTH_ONBOARDING_ENGINE §).
    for (final banned in ['AI', 'intelligence', 'insight', 'analysis']) {
      expect(find.textContaining(banned), findsNothing, reason: banned);
    }
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/chat/seen_receipts_repository_test.dart test/features/chat/chat_settings_seen_receipts_toggle_test.dart test/features/onboarding/couples_joined_step_test.dart`
Expected: all three FAIL to compile (`seen_receipts.dart` and `seen_receipts_repository.dart` do not exist).

- [ ] **Step 3: Write the copy and the repository**

```dart
// lib/features/chat/domain/seen_receipts.dart
import 'package:flutter/foundation.dart';

/// What `get_seen_receipts` / `set_seen_receipts` return: my own vote and
/// the couple's effective state. Never the partner's row (Spec 1a Task 2).
@immutable
class SeenReceipts {
  const SeenReceipts({required this.mine, required this.effective});

  static const off = SeenReceipts(mine: false, effective: false);

  factory SeenReceipts.fromJson(Object? raw) {
    if (raw is! Map) return off;
    return SeenReceipts(
      mine: raw['mine'] == true,
      effective: raw['effective'] == true,
    );
  }

  final bool mine;
  final bool effective;

  @override
  bool operator ==(Object other) =>
      other is SeenReceipts &&
      other.mine == mine &&
      other.effective == effective;

  @override
  int get hashCode => Object.hash(mine, effective);

  @override
  String toString() => 'SeenReceipts(mine: $mine, effective: $effective)';
}

/// Copy for "Show when we've seen things" (Spec 1a; research 06 §3 F4).
/// Verbatim strings; the subtitle never says who turned it off.
const seenReceiptsTitle = "Show when we've seen things";

const seenReceiptsAsk1Line =
    'Read receipts are off to start. Turn them on together whenever you like.';

const seenReceiptsFailureCopy = "Couldn't update this setting. Try again.";

String seenReceiptsSubtitle(SeenReceipts s) {
  if (s.effective) {
    return 'On for both of you. Read ticks and story seen marks show. '
        'Either of you can turn this off.';
  }
  if (s.mine) return "Turns on once you've both turned it on.";
  return 'Off. Read ticks and story seen marks stay hidden for both of you. '
      'Turn it on together whenever you like.';
}
```

```dart
// lib/features/chat/data/seen_receipts_repository.dart
import 'package:attune/features/chat/domain/seen_receipts.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    show supabaseClientProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One RPC call. The production value is `SupabaseClient.rpc`; tests pass a
/// recording function.
typedef SeenReceiptsRpc =
    Future<dynamic> Function(String fn, Map<String, dynamic> params);

class SeenReceiptsRepository {
  SeenReceiptsRepository(this._rpc);

  final SeenReceiptsRpc _rpc;

  Future<SeenReceipts> get(String relationshipId) async =>
      SeenReceipts.fromJson(
        await _rpc('get_seen_receipts', {'p_relationship_id': relationshipId}),
      );

  Future<SeenReceipts> set(String relationshipId, bool on) async =>
      SeenReceipts.fromJson(
        await _rpc('set_seen_receipts', {
          'p_relationship_id': relationshipId,
          'p_on': on,
        }),
      );
}

final seenReceiptsRepositoryProvider = Provider<SeenReceiptsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SeenReceiptsRepository((fn, params) => client.rpc(fn, params: params));
});

/// The couple's setting as the server reports it. Off while loading or on
/// error: a privacy toggle must never show "on" for a state it has not
/// confirmed.
final seenReceiptsProvider = FutureProvider.autoDispose
    .family<SeenReceipts, String>(
      (ref, relationshipId) =>
          ref.watch(seenReceiptsRepositoryProvider).get(relationshipId),
    );
```

- [ ] **Step 4: Add the row and the Ask 1 line**

Snapshot both shared files:
```bash
cp lib/features/chat/presentation/widgets/chat_settings_static_rows.dart "$WS/snapshots/chat_settings_static_rows.dart"
cp lib/features/onboarding/presentation/widgets/couples_joined_step.dart "$WS/snapshots/couples_joined_step.dart"
```

`chat_settings_static_rows.dart`: add the imports
```dart
import 'package:attune/features/chat/data/seen_receipts_repository.dart';
import 'package:attune/features/chat/domain/seen_receipts.dart';
```
In `build`, after `final allowStreakReplays = ref.watch(streakReplayPreferenceProvider);` add
```dart
    // Off while loading or on error, like the location toggle above it.
    final seenReceipts =
        relationshipId == null
            ? SeenReceipts.off
            : ref.watch(seenReceiptsProvider(relationshipId)).valueOrNull ??
                SeenReceipts.off;
```
Then, in the first `CardInkWell`, change the "Share my location" row's `showDivider: true,` (it already is) and insert this row between it and the "End relationship" row:
```dart
                // One setting for chat read ticks and story seen marks
                // (Spec 1a). Shows my own vote; the subtitle says whether it
                // is on for both. Either partner's off is immediate and
                // silent; on needs both (SPEC §11 constraint 12).
                InfoRowWidget(
                  key: const ValueKey('seen_receipts_toggle'),
                  title: seenReceiptsTitle,
                  subtitle: seenReceiptsSubtitle(seenReceipts),
                  icon: Icons.done_all_rounded,
                  isToggleItem: true,
                  showAvatar: false,
                  showTrailingArrow: false,
                  showDivider: true,
                  toggleValue: seenReceipts.mine,
                  iconColor: Colors.grey,
                  onToggleChanged:
                      relationshipId == null
                          ? (_) {}
                          : (value) async {
                            final repository = ref.read(
                              seenReceiptsRepositoryProvider,
                            );
                            try {
                              await repository.set(relationshipId, value);
                            } catch (_) {
                              if (context.mounted) {
                                context.showErrorSnackbar(
                                  seenReceiptsFailureCopy,
                                );
                              }
                            } finally {
                              ref.invalidate(
                                seenReceiptsProvider(relationshipId),
                              );
                            }
                          },
                ),
```

`couples_joined_step.dart`: add `import 'package:attune/features/chat/domain/seen_receipts.dart';` and, directly after the second `OnboardingInfoTile` (before `Gap(Spacing.xl.h)`), insert
```dart
          // F4 (4): new couples start with seen-state off; say so once, here.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.xs.w),
            child: Text(
              seenReceiptsAsk1Line,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
```

- [ ] **Step 5: Run the tests, diff, format, analyze**

```bash
flutter test test/features/chat/seen_receipts_repository_test.dart test/features/chat/chat_settings_seen_receipts_toggle_test.dart test/features/chat/chat_settings_location_toggle_test.dart test/features/onboarding/couples_joined_step_test.dart
diff -u "$WS/snapshots/chat_settings_static_rows.dart" lib/features/chat/presentation/widgets/chat_settings_static_rows.dart
diff -u "$WS/snapshots/couples_joined_step.dart" lib/features/onboarding/presentation/widgets/couples_joined_step.dart
dart format lib/features/chat/domain/seen_receipts.dart lib/features/chat/data/seen_receipts_repository.dart test/features/chat/seen_receipts_repository_test.dart test/features/chat/chat_settings_seen_receipts_toggle_test.dart test/features/onboarding/couples_joined_step_test.dart
flutter analyze lib/features/chat/domain/seen_receipts.dart lib/features/chat/data/seen_receipts_repository.dart lib/features/chat/presentation/widgets/chat_settings_static_rows.dart lib/features/onboarding/presentation/widgets/couples_joined_step.dart test/features/chat/seen_receipts_repository_test.dart test/features/chat/chat_settings_seen_receipts_toggle_test.dart test/features/onboarding/couples_joined_step_test.dart 2>&1 | grep -E "^\s*(error|warning) "
```
Expected: all pass (the location-toggle test still passes with the new row present); diffs show only the additions; the grep prints nothing. If `pulse_tab_test.dart` renders `ChatSettingsStaticRows` without a `seenReceiptsRepositoryProvider` override, it now reads `Supabase.instance` inside the provider → `AsyncError` → `SeenReceipts.off`; run `flutter test test/features/pulse` to confirm it stays green.

- [ ] **Step 6: Ledger**

Append `Task 6: complete (toggle + Ask 1 line; 3 test files). Regression risk: ChatSettingsStaticRows gains one provider watch; defaults to off on error.`

---

### Task 7: Pulse server — private check-ins, self-only Emotional safety, caller auth, rate limit, week ending

> Starts only after the owner has confirmed the ruling at the top of this plan.

**Files:**
- Create: `supabase/migrations/20261017150000_pulse_privacy.sql`
- Create: `supabase/migrations/20261017150100_pulse_privacy_table_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (append)
- Modify: `supabase/functions/compute-pulse/index.ts` (whole file replaced; pure helpers kept)
- Modify: `supabase/functions/compute-pulse/index.test.ts` (one existing test adjusted, new tests appended)
- Create: `supabase/functions/compute-pulse/privacy.test.ts`
- Modify: `supabase/functions/generate-verdict/index.ts:451-460` (drop `"emotional_safety"` from the metric list)
- Create: `supabase/functions/generate-verdict/emotional_safety.test.ts`
- Test: `supabase/tests/pulse_privacy_contracts.sql`

**Interfaces:**
- Consumes: `pulse_scores` (`20260717120000:32-47`), `weekly_checkins` (`:49-61`, RLS `checkins_private`), `pulse_score_diagnostics`, RPCs `compute_relationship_chat_signals`, `compute_relationship_game_signals`; cron `invoke_edge_function` sends `Authorization: Bearer <service key>` and body `{}`.
- Produces:
  - `pulse_scores.emotional_safety` nullable; new rows carry `NULL`.
  - `public.pulse_private_scores(relationship_id, user_id, week_ending, emotional_safety int 0..100, computed_at, PRIMARY KEY (user_id, week_ending))` — RLS `user_id = auth.uid()` SELECT only; service_role writes.
  - `public.pulse_recompute_limits(relationship_id, user_id, last_forced_at, PRIMARY KEY (relationship_id, user_id))` — service_role only. **Per member** (M2): one partner's refusal never tells them the other refreshed.
  - `claim_pulse_recompute(p_relationship_id uuid, p_user_id uuid, p_min_interval interval DEFAULT interval '24 hours') RETURNS TABLE (granted boolean, retry_after_seconds int)` — SECURITY DEFINER, service_role EXECUTE only; atomic (one `INSERT … ON CONFLICT DO UPDATE … WHERE`).
  - compute-pulse HTTP contract: service-role bearer → all active relationships (or one), and the shared row is **always** recomputed (the cron must not be a no-op after a forced mid-week refresh — Review Focus 9; note the cron is unscheduled in the repo, `20260931150000_pause_ai_jobs.sql:23`); user bearer → `relationship_id` required (400), caller must be a member of an **active** relationship (else 404 "Not found" — one answer for missing/paused/not mine); `force_recompute: true` claims the caller's limit (429 `{error:'rate_limited', retry_after_seconds}`) and rewrites this week's shared row; `force_recompute: false` (what the check-in submit sends) never rewrites an existing shared row and never touches the claim, but always runs the private pass so "Your week" fills in.
  - Exported pure helpers: `getWeekEnding(date): Date` (UTC Sunday on/after), `weekEndingKey(date): string`, `SHARED_WEIGHTS`, `overallFromShared(d): number`, `callerMayRecompute(callerId, rel): boolean`, `shouldComputeShared(isService, force, exists): boolean`, `privateEmotionalSafety({moodBase, safetyRating, signals, chatWeight}): number | null`, `rollupConfidence` (fraction-based), plus the existing `clamp`, `weightedMean`, `computeChatWeight`, `applyChatSignals`, `applyGameSignals`, `confidenceFrom`.

- [ ] **Step 1: Write the failing SQL contract**

```sql
-- supabase/tests/pulse_privacy_contracts.sql
-- Pulse privacy (Spec 1a Task 7): Emotional safety is self-only, check-in
-- rows stay private, the forced-recompute limit is server-side and atomic.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5e100000-0000-0000-0000-0000000000a1'),
  ('5e100000-0000-0000-0000-0000000000b2'),
  ('5e100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5e100000-0000-0000-0000-0000000000a1', '+233599500001', 'Pulse A'),
  ('5e100000-0000-0000-0000-0000000000b2', '+233599500002', 'Pulse B'),
  ('5e100000-0000-0000-0000-0000000000c3', '+233599500003', 'Pulse C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1',
   '5e100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-10-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- 1. The shared row no longer needs emotional_safety.
DO $$
BEGIN
  IF (SELECT is_nullable FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'pulse_scores' AND column_name = 'emotional_safety') <> 'YES' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pulse_scores.emotional_safety is still NOT NULL';
  END IF;
  INSERT INTO public.pulse_scores (relationship_id, week_ending, overall_score, communication, connection,
                                   conflict_health, alignment, emotional_safety, data_confidence)
  VALUES ('5e200000-0000-0000-0000-000000000001', '2026-10-18', 60, 60, 60, 60, 60, NULL, 'low');
END $$;

-- 2. Private scores: each member reads only their own row; clients cannot write.
DO $$
DECLARE v int;
BEGIN
  INSERT INTO public.pulse_private_scores (relationship_id, user_id, week_ending, emotional_safety) VALUES
    ('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1', '2026-10-18', 71),
    ('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000b2', '2026-10-18', 43);
  IF has_table_privilege('authenticated', 'public.pulse_private_scores', 'INSERT')
     OR has_table_privilege('authenticated', 'public.pulse_private_scores', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.pulse_private_scores', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can write pulse_private_scores';
  END IF;
  PERFORM pg_temp.as_user('5e100000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v FROM public.pulse_private_scores;
  IF v <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: A sees % private rows (expected only their own)', v; END IF;
  IF (SELECT emotional_safety FROM public.pulse_private_scores) <> 71 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: A sees a row that is not theirs';
  END IF;
  PERFORM pg_temp.as_user('5e100000-0000-0000-0000-0000000000b2');
  IF (SELECT count(*) FROM public.pulse_private_scores WHERE user_id = '5e100000-0000-0000-0000-0000000000a1') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: B can read A''s private Emotional safety';
  END IF;
  BEGIN
    INSERT INTO public.pulse_private_scores (relationship_id, user_id, week_ending, emotional_safety)
    VALUES ('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000b2', '2026-10-25', 99);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member inserted a private score';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM pg_temp.as_user('5e100000-0000-0000-0000-0000000000c3');
  SELECT count(*) INTO v FROM public.pulse_private_scores;
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider sees % private rows', v; END IF;
  RESET ROLE;
END $$;

-- 3. Check-in rows stay private to their author (the RLS this whole feature
--    stands on had no contract until now).
DO $$
DECLARE v int;
BEGIN
  INSERT INTO public.weekly_checkins (user_id, relationship_id, week_ending, communication_rating, connection_rating,
                                      conflict_health_rating, conflict_health_na, alignment_rating, safety_rating)
  VALUES ('5e100000-0000-0000-0000-0000000000a1', '5e200000-0000-0000-0000-000000000001', '2026-10-18', 8, 7, NULL, true, 9, 6)
  ON CONFLICT (user_id, week_ending) DO NOTHING;
  PERFORM pg_temp.as_user('5e100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v FROM public.weekly_checkins WHERE relationship_id = '5e200000-0000-0000-0000-000000000001';
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner can read % check-in rows', v; END IF;
  RESET ROLE;
END $$;

-- 4. The forced-recompute limit: service-role only, per member, granted once
--    per window, atomic, with an honest retry time. A's refusal must not
--    depend on B's refresh (M2: a 429 would otherwise say "your partner
--    refreshed recently").
DO $$
DECLARE v_granted boolean; v_retry int;
BEGIN
  IF has_function_privilege('authenticated', 'public.claim_pulse_recompute(uuid, uuid, interval)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.claim_pulse_recompute(uuid, uuid, interval)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client role can execute claim_pulse_recompute';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.claim_pulse_recompute(uuid, uuid, interval)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: service_role cannot execute claim_pulse_recompute';
  END IF;
  IF has_table_privilege('authenticated', 'public.pulse_recompute_limits', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can read pulse_recompute_limits';
  END IF;

  SELECT granted, retry_after_seconds INTO v_granted, v_retry
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1');
  IF NOT v_granted OR v_retry <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first claim was not granted (% / %)', v_granted, v_retry;
  END IF;
  SELECT granted, retry_after_seconds INTO v_granted, v_retry
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1');
  IF v_granted OR v_retry NOT BETWEEN 1 AND 86400 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second claim inside 24h was granted or mis-timed (% / %)', v_granted, v_retry;
  END IF;
  -- B's own first refresh is untouched by A's.
  SELECT granted INTO v_granted
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000b2');
  IF NOT v_granted THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: B was refused because A refreshed (the limit leaks across partners)';
  END IF;
  UPDATE public.pulse_recompute_limits SET last_forced_at = now() - interval '25 hours'
   WHERE relationship_id = '5e200000-0000-0000-0000-000000000001'
     AND user_id = '5e100000-0000-0000-0000-0000000000a1';
  SELECT granted INTO v_granted
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1');
  IF NOT v_granted THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a claim after the window was refused';
  END IF;
  -- A short window proves the interval is honoured, not a hard-coded day.
  SELECT granted INTO v_granted
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1', interval '0 seconds');
  IF NOT v_granted THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a zero-length window still refused';
  END IF;
  RAISE NOTICE 'pulse_privacy_contracts: all held';
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/pulse_privacy_contracts.sql`
Expected: `ERROR:  CONTRACT VIOLATED: pulse_scores.emotional_safety is still NOT NULL`.

- [ ] **Step 3: Write the migrations and register the replay**

```sql
-- supabase/migrations/20261017150000_pulse_privacy.sql
--
-- Pulse privacy (Spec 1a Task 7; research 06 §3 F5 with the stronger ruling
-- recorded in PULSE.md §11; SOUL §9 Pulse).
--
-- 1. Emotional safety leaves the shared row. compute-pulse writes it per
--    member into pulse_private_scores (auth.uid()-only RLS); the shared
--    column becomes nullable and is written as NULL from now on.
-- 2. The on-demand refresh limit moves server-side: claim_pulse_recompute is
--    an atomic claim (one INSERT ... ON CONFLICT DO UPDATE ... WHERE) that
--    only the service role (the edge function) may call.
ALTER TABLE public.pulse_scores ALTER COLUMN emotional_safety DROP NOT NULL;

CREATE TABLE public.pulse_private_scores (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  week_ending date NOT NULL,
  emotional_safety int NOT NULL CHECK (emotional_safety BETWEEN 0 AND 100),
  computed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, week_ending)
);
CREATE INDEX idx_pulse_private_scores_rel ON public.pulse_private_scores (relationship_id, week_ending DESC);
ALTER TABLE public.pulse_private_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY pulse_private_scores_self ON public.pulse_private_scores
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE ALL ON public.pulse_private_scores FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.pulse_private_scores TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.pulse_private_scores TO service_role;

-- Per (relationship, member): keyed per couple, one partner's 429 would say
-- "your partner refreshed in the last day" (SPEC §11 constraint 10).
CREATE TABLE public.pulse_recompute_limits (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_forced_at timestamptz NOT NULL,
  PRIMARY KEY (relationship_id, user_id)
);
ALTER TABLE public.pulse_recompute_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pulse_recompute_limits FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.pulse_recompute_limits TO service_role;

CREATE FUNCTION public.claim_pulse_recompute(
  p_relationship_id uuid,
  p_user_id uuid,
  p_min_interval interval DEFAULT interval '24 hours'
)
RETURNS TABLE (granted boolean, retry_after_seconds int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_last timestamptz;
BEGIN
  INSERT INTO public.pulse_recompute_limits (relationship_id, user_id, last_forced_at)
  VALUES (p_relationship_id, p_user_id, now())
  ON CONFLICT (relationship_id, user_id) DO UPDATE
    SET last_forced_at = now()
    WHERE public.pulse_recompute_limits.last_forced_at <= now() - p_min_interval
  RETURNING last_forced_at INTO v_last;
  IF FOUND THEN
    granted := true;
    retry_after_seconds := 0;
    RETURN NEXT;
    RETURN;
  END IF;
  SELECT l.last_forced_at INTO v_last
    FROM public.pulse_recompute_limits l
   WHERE l.relationship_id = p_relationship_id AND l.user_id = p_user_id;
  granted := false;
  retry_after_seconds := GREATEST(1, ceil(extract(epoch FROM (v_last + p_min_interval - now())))::int);
  RETURN NEXT;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_pulse_recompute(uuid, uuid, interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_pulse_recompute(uuid, uuid, interval) TO service_role;
```

```sql
-- supabase/migrations/20261017150100_pulse_privacy_table_grants.sql
-- Replayed by scripts/local_pg_grants.sql after its blanket grant.
REVOKE ALL ON public.pulse_private_scores FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.pulse_private_scores TO authenticated;
REVOKE ALL ON public.pulse_recompute_limits FROM PUBLIC, anon, authenticated;
```

Append to `scripts/local_pg_grants.sql`:
```sql

-- Spec 1a (Task 7): private Pulse scores are SELECT-only for their author;
-- the recompute limit table is server-only.
\i supabase/migrations/20261017150100_pulse_privacy_table_grants.sql
```

Rebuild and run: `ATTUNE_TEST_DB=attune_spec1a scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"; psql -q -d attune_spec1a -v ON_ERROR_STOP=1 -f supabase/tests/pulse_privacy_contracts.sql`
Expected: `failed 0`; `NOTICE:  pulse_privacy_contracts: all held`.

Mutant: `"$WS/mutant.sh" "DROP POLICY pulse_private_scores_self ON public.pulse_private_scores; CREATE POLICY pulse_private_scores_self ON public.pulse_private_scores FOR SELECT TO authenticated USING (true);" supabase/tests/pulse_privacy_contracts.sql` → `CONTRACT VIOLATED: A sees 2 private rows`, `MUTANT KILLED`.

- [ ] **Step 4: Write the failing Deno tests**

Snapshot: `cp supabase/functions/compute-pulse/index.test.ts "$WS/snapshots/compute-pulse-index.test.ts"; cp supabase/functions/compute-pulse/index.ts "$WS/snapshots/compute-pulse-index.ts"; cp supabase/functions/generate-verdict/index.ts "$WS/snapshots/generate-verdict-index.ts"`.

In `index.test.ts`, change the import lines at the top to
```ts
import { clamp, getWeekEnding, weekEndingKey, confidenceFrom, rollupConfidence } from "./index.ts";
import {
  computeChatWeight, applyChatSignals, weightedMean, type DimensionState, type ChatSignals,
  SHARED_WEIGHTS, overallFromShared, callerMayRecompute, privateEmotionalSafety, shouldComputeShared,
} from "./index.ts";
```
replace the existing `getWeekEnding` test with
```ts
Deno.test("getWeekEnding: a Wednesday rolls forward to the next Sunday (UTC)", () => {
  const wed = new Date("2026-08-12T10:00:00Z");
  assertEquals(weekEndingKey(wed), "2026-08-16");
  assertEquals(getWeekEnding(wed).getUTCDay(), 0);
});

Deno.test("getWeekEnding: a Sunday is its own week ending, matching Dart", () => {
  assertEquals(weekEndingKey(new Date("2026-08-16T10:00:00Z")), "2026-08-16");
  assertEquals(weekEndingKey(new Date("2026-08-16T23:59:59Z")), "2026-08-16");
});

Deno.test("getWeekEnding: Saturday 23:59 UTC and Sunday 00:01 UTC share a week ending", () => {
  assertEquals(weekEndingKey(new Date("2026-08-15T23:59:00Z")), "2026-08-16");
  assertEquals(weekEndingKey(new Date("2026-08-16T00:01:00Z")), "2026-08-16");
  // Monday 00:01 UTC is the next week, whatever the phone's zone says.
  assertEquals(weekEndingKey(new Date("2026-08-17T00:01:00Z")), "2026-08-23");
});
```
and append at the end of the file:
```ts
Deno.test("overallFromShared: four weights, normalised from 22/22/20/18", () => {
  assertEquals(SHARED_WEIGHTS.communication + SHARED_WEIGHTS.connection + SHARED_WEIGHTS.conflictHealth + SHARED_WEIGHTS.alignment, 82);
  assertEquals(overallFromShared({ communication: 100, connection: 100, conflictHealth: 100, alignment: 100 }), 100);
  assertEquals(overallFromShared({ communication: 0, connection: 0, conflictHealth: 0, alignment: 100 }), 22);
  assertEquals(overallFromShared({ communication: 100, connection: 100, conflictHealth: 0, alignment: 0 }), 54);
  // The disclosed percentages (tooltip + manual) are these, and they sum to 100.
  const pct = [SHARED_WEIGHTS.communication, SHARED_WEIGHTS.connection, SHARED_WEIGHTS.conflictHealth, SHARED_WEIGHTS.alignment]
    .map((w) => Math.round((w * 100) / 82));
  assertEquals(pct, [27, 27, 24, 22]);
});

Deno.test("rollupConfidence: four dimensions — 3 high is high, 2 medium is medium, 1 medium is low", () => {
  assertEquals(rollupConfidence(["high", "high", "high", "medium"]), "high");
  assertEquals(rollupConfidence(["medium", "medium", "low", "low"]), "medium");
  assertEquals(rollupConfidence(["medium", "low", "low", "none"]), "low");
  assertEquals(rollupConfidence(["low", "low", "low", "low"]), "none");
});

Deno.test("shouldComputeShared: the cron always writes; a user's non-forced call never rewrites an existing week", () => {
  assertEquals(shouldComputeShared(true, false, true), true);
  assertEquals(shouldComputeShared(true, false, false), true);
  assertEquals(shouldComputeShared(false, true, true), true);
  assertEquals(shouldComputeShared(false, false, false), true);
  assertEquals(shouldComputeShared(false, false, true), false);
});

Deno.test("callerMayRecompute: members of an ACTIVE relationship only", () => {
  const rel = { id: "r", user_a: "a", user_b: "b", status: "active" };
  assertEquals(callerMayRecompute("a", rel), true);
  assertEquals(callerMayRecompute("b", rel), true);
  assertEquals(callerMayRecompute("c", rel), false);
  assertEquals(callerMayRecompute("a", { ...rel, status: "paused" }), false);
  assertEquals(callerMayRecompute("a", { ...rel, status: "ended" }), false);
  assertEquals(callerMayRecompute("a", null), false);
  assertEquals(callerMayRecompute("a", undefined), false);
});

const noChat: ChatSignals = {
  analysedCount: 0, avgTone: null, violationRate: null, severeRate: null, bidTurnRate: null,
  bidsTotal: 0, sessionCount: 0, conflictSessionCount: 0, avgEscalation: null, repairRate: null,
  attemptRate: null, stonewallRate: null, pursueWithdrawRate: null,
};

Deno.test("privateEmotionalSafety: nothing without the member's own check-in", () => {
  assertEquals(privateEmotionalSafety({ moodBase: 70, safetyRating: null, signals: noChat, chatWeight: 1 }), null);
});

Deno.test("privateEmotionalSafety: blends the shared mood base with my own rating", () => {
  assertEquals(privateEmotionalSafety({ moodBase: null, safetyRating: 8, signals: noChat, chatWeight: 0 }), 65);
  assertEquals(privateEmotionalSafety({ moodBase: 70, safetyRating: 9, signals: noChat, chatWeight: 0 }), 80);
  assertEquals(privateEmotionalSafety({ moodBase: 20, safetyRating: 1, signals: noChat, chatWeight: 1 }), 15);
});

Deno.test("privateEmotionalSafety: chat severity still lowers it, within 0..100", () => {
  const severe = { ...noChat, analysedCount: 20, severeRate: 0.5 };
  assertEquals(privateEmotionalSafety({ moodBase: 70, safetyRating: 9, signals: severe, chatWeight: 1 }), 68);
  assertEquals(privateEmotionalSafety({ moodBase: 0, safetyRating: 1, signals: severe, chatWeight: 1 }), 0);
});
```

New `supabase/functions/compute-pulse/privacy.test.ts`:
```ts
// Spec 1a: the shared Pulse row may not contain any private check-in answer,
// in any dimension, delta or confidence; Emotional safety is self-only; the
// caller is authenticated and rate-limited. Source-text guards, same pattern
// as private_conflicts.test.ts, so a refactor cannot quietly reintroduce a
// check-in read into the shared path.
import { assert, assertMatch, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const sharedStart = source.indexOf("async function _computePulseScore");
const privateStart = source.indexOf("async function _computePrivateScores");
const handler = source.slice(0, sharedStart);
const shared = source.slice(sharedStart, privateStart);
const priv = source.slice(privateStart);

Deno.test("the shared computation never reads weekly_checkins or a rating", () => {
  assert(sharedStart > 0 && privateStart > sharedStart, "both functions exist, shared first");
  assert(!shared.includes("weekly_checkins"));
  assert(!/safety_rating|communication_rating|connection_rating|alignment_rating|conflict_health_rating/.test(shared));
  assert(!/checkins\b/.test(shared));
});

Deno.test("the shared row writes emotional_safety as null and no per-dimension safety confidence", () => {
  assertMatch(shared, /emotional_safety: null/);
  assert(!/emotional_safety: emotionalSafety/.test(shared));
  assert(!/emotional_safety: safetyConfidence/.test(shared));
});

Deno.test("deltas compare against the previous week's row", () => {
  const from = shared.indexOf("from('pulse_scores')", shared.indexOf("previousPulse"));
  const statement = shared.slice(from, shared.indexOf(".maybeSingle()", from));
  assertMatch(statement, /\.lt\('week_ending', weekKey\)/);
});

Deno.test("the handler authenticates the caller, checks membership and claims the limit", () => {
  assertStringIncludes(handler, "auth.getUser(token)");
  assertStringIncludes(handler, "callerMayRecompute(");
  assertStringIncludes(handler, "rpc('claim_pulse_recompute'");
  assertStringIncludes(handler, "p_user_id: auth.user.id");
  assertStringIncludes(handler, "status: 429");
});

Deno.test("the private pass runs whether or not the shared row is recomputed", () => {
  const calls = shared.match(/await _computePrivateScores\(/g) ?? [];
  assertEquals(calls.length, 2, "once on the early return, once after the shared upsert");
  assert(shared.indexOf("await _computePrivateScores(") < shared.indexOf("// 3. Attachment quiz"));
  assertStringIncludes(shared, "shouldComputeShared(opts.isService, opts.force");
});

Deno.test("private scores go only to pulse_private_scores", () => {
  assertStringIncludes(priv, "from('weekly_checkins')");
  assertStringIncludes(priv, "from('pulse_private_scores')");
  assert(!priv.includes("from('pulse_scores')"));
});

Deno.test("compute-pulse still reads only shared moments", () => {
  const query = shared.slice(shared.indexOf(".from('timeline_events')"));
  assertMatch(query.slice(0, query.indexOf("// 2.")), /\.eq\('visibility', 'shared'\)/);
});
```

New `supabase/functions/generate-verdict/emotional_safety.test.ts`:
```ts
// Spec 1a: Emotional safety is self-facing; a shared verdict may not carry it
// forward as evidence.
import { assert } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("generate-verdict builds no emotional_safety evidence", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const fn = source.slice(source.indexOf("function buildEvidence"));
  const pulseLoop = fn.slice(0, fn.indexOf("for (const pattern of"));
  assert(pulseLoop.length > 0, "buildEvidence's pulse loop exists");
  assert(!pulseLoop.includes("emotional_safety"));
});
```

Run: `deno test --allow-read --allow-env --allow-net supabase/functions/compute-pulse; deno test --allow-read --allow-env --allow-net supabase/functions/generate-verdict`
Expected: compute-pulse fails to type-check (`weekEndingKey`, `SHARED_WEIGHTS`, … not exported) — the whole file errors; generate-verdict: the new test FAILS (`emotional_safety` present).

- [ ] **Step 5: Replace `compute-pulse/index.ts`**

Delete `private_conflicts.test.ts`'s concern? No — keep it; the new file duplicates its guard on purpose (the `// 2.` marker must survive). Replace the whole of `index.ts` with:

```ts
// supabase/functions/compute-pulse/index.ts
//
// Pulse (Spec 1a Task 7; PULSE.md §11 ruling). The four SHARED dimensions
// come from shared moments, chat aggregates and games only; private check-in
// answers never enter them, their deltas or their confidence. Emotional
// safety is computed per member into pulse_private_scores (auth.uid()-only
// RLS). The caller must be a member of an ACTIVE relationship (or the
// service role, which the weekly cron uses); a forced recompute is limited
// to one per relationship per 24 h by claim_pulse_recompute.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

export interface RelationshipRow {
  id: string
  user_a: string | null
  user_b: string | null
  status: string
}

interface ClaimRow {
  granted: boolean
  retry_after_seconds: number
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function bearerToken(req: Request): string {
  return (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
}

/// A user may recompute only a relationship they belong to and that is
/// active. Paused/ended/missing/not-mine all read the same to the caller.
export function callerMayRecompute(
  callerId: string,
  rel: RelationshipRow | null | undefined,
): boolean {
  if (!rel || rel.status !== 'active') return false
  return rel.user_a === callerId || rel.user_b === callerId
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey)

    const body = await req.json().catch(() => ({}))
    const relationshipId =
      typeof body?.relationship_id === 'string' ? body.relationship_id : null
    const forceRecompute = body?.force_recompute === true

    const token = bearerToken(req)
    const isService = token !== '' && token === serviceKey

    let relationships: RelationshipRow[]
    if (isService) {
      // The weekly cron (invoke_edge_function) and operators: one or all.
      let query = supabase
        .from('relationships')
        .select('id, user_a, user_b, status')
        .eq('status', 'active')
      if (relationshipId) query = query.eq('id', relationshipId)
      const { data } = await query
      relationships = (data ?? []) as RelationshipRow[]
    } else {
      if (!token) return json({ error: 'Not authenticated' }, 401)
      const { data: auth, error: authError } = await supabase.auth.getUser(token)
      if (authError || !auth?.user) return json({ error: 'Not authenticated' }, 401)
      if (!relationshipId) return json({ error: 'relationship_id is required' }, 400)

      const { data: rel } = await supabase
        .from('relationships')
        .select('id, user_a, user_b, status')
        .eq('id', relationshipId)
        .maybeSingle()
      if (!callerMayRecompute(auth.user.id, rel as RelationshipRow | null)) {
        // One answer for "not yours", "paused" and "does not exist".
        return json({ error: 'Not found' }, 404)
      }
      if (forceRecompute) {
        const { data: claim, error: claimError } = await supabase.rpc('claim_pulse_recompute', {
          p_relationship_id: relationshipId,
          p_user_id: auth.user.id,
        })
        if (claimError) throw claimError
        const row = (claim as ClaimRow[] | null)?.[0]
        if (!row?.granted) {
          return new Response(
            JSON.stringify({
              error: 'rate_limited',
              retry_after_seconds: row?.retry_after_seconds ?? 86400,
            }),
            { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
          )
        }
      }
      relationships = [rel as RelationshipRow]
    }

    const weekEnding = getWeekEnding(new Date())
    const results = []
    for (const relationship of relationships) {
      const pulseScore = await _computePulseScore(supabase, relationship, weekEnding, {
        isService,
        force: forceRecompute,
      })
      if (pulseScore) results.push({ ...pulseScore })
    }

    return json({ success: true, computed: results.length, results })
  } catch (error) {
    // Only the error's name: a Postgrest message can quote row contents
    // (checklist 4.4 / 5.5).
    console.error('compute-pulse failed:', error instanceof Error ? error.name : typeof error)
    return json({ error: 'Could not compute pulse scores' }, 500)
  }
})

/// Service-role runs (the weekly cron) always write the shared row: a forced
/// mid-week refresh creates this week's row early, and a "skip if it exists"
/// guard would turn the Sunday run into a no-op (Review Focus 9). A user's
/// non-forced call never rewrites an existing shared row (that is what the
/// claim protects) but still refreshes the private pass.
export function shouldComputeShared(isService: boolean, force: boolean, exists: boolean): boolean {
  return isService || force || !exists
}

async function _computePulseScore(
  supabase: any,
  relationship: RelationshipRow,
  weekEnding: Date,
  opts: { isService: boolean; force: boolean },
) {
  const relationshipId = relationship.id
  const weekKey = weekEndingKey(weekEnding)

  // ──────────────────────────────────────────────────────────
  // FETCH THE SHARED DATA SOURCES (no private answers in here)
  // ──────────────────────────────────────────────────────────

  // 1. Timeline events (last 30 days for scoring)
  const thirtyDaysAgo = new Date()
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)

  const { data: timelineEvents }: { data: any[] | null } = await supabase
    .from('timeline_events')
    .select('*')
    .eq('relationship_id', relationshipId)
    // A private conflict never feeds the couple's shared score (Phase 4 R1).
    .eq('visibility', 'shared')
    .gte('occurred_at', thirtyDaysAgo.toISOString().split('T')[0])
    .is('deleted_at', null)

  // The shared mood base, reused by the private pass.
  const allEventsWithMood = timelineEvents?.filter(e => e.mood_score) || []
  const moodBase = allEventsWithMood.length > 0
    ? Math.round(
        (allEventsWithMood.reduce((sum, e) => sum + e.mood_score, 0) / allEventsWithMood.length) * 10,
      )
    : null

  // 2. Chat signal aggregates (last 30 days), via the pre-aggregating RPC
  // — never select(*) raw messages/sessions rows into this function
  // (Algorithm Quality Review Checklist v3.1 item 2.14).
  const { data: chatSignalRows } = await supabase
    .rpc('compute_relationship_chat_signals', {
      p_relationship_id: relationshipId,
      p_window_start: thirtyDaysAgo.toISOString(),
    })
  const chatRow = chatSignalRows?.[0] ?? null

  const chatSignals: ChatSignals = {
    analysedCount: chatRow?.analysed_count ?? 0,
    avgTone: chatRow?.avg_tone ?? null,
    violationRate: chatRow?.violation_rate ?? null,
    severeRate: chatRow?.severe_rate ?? null,
    bidTurnRate: chatRow?.bid_turn_rate ?? null,
    bidsTotal: chatRow?.bids_total ?? 0,
    sessionCount: chatRow?.session_count ?? 0,
    conflictSessionCount: chatRow?.conflict_session_count ?? 0,
    avgEscalation: chatRow?.avg_escalation ?? null,
    repairRate: chatRow?.repair_rate ?? null,
    attemptRate: chatRow?.attempt_rate ?? null,
    stonewallRate: chatRow?.stonewall_rate ?? null,
    pursueWithdrawRate: chatRow?.pursue_withdraw_rate ?? null,
  }

  const { data: gameSignalRows } = await supabase
    .rpc('compute_relationship_game_signals', {
      p_relationship_id: relationshipId,
      p_window_start: thirtyDaysAgo.toISOString(),
    })
  const gameRow = gameSignalRows?.[0] ?? null

  const gameSignals: GameSignals = {
    sessionsCompleted: gameRow?.sessions_completed ?? 0,
    slidingScalePairs: gameRow?.sliding_scale_pairs ?? 0,
    slidingScaleAvgGap: gameRow?.sliding_scale_avg_gap ?? null,
    mirrorRoundsScored: gameRow?.mirror_rounds_scored ?? 0,
  }

  const pendingBacklog = chatRow?.pending_backlog_count ?? 0
  const coverageDays = chatRow?.first_analysed_at
    ? Math.min(30, (Date.now() - new Date(chatRow.first_analysed_at).getTime()) / 86_400_000)
    : 0

  // Backlog gate: if the session-analysis sweep is more than 50 messages
  // behind, treat chat as having zero weight this run rather than score
  // on a known-incomplete picture.
  const chatWeight = pendingBacklog > 50 ? 0 : computeChatWeight(coverageDays)
  const hasChatSignal = chatWeight > 0.5

  // Already computed this week? Then only the private pass runs: a check-in
  // submit calls this non-forced so "Your week" fills in without touching
  // the shared row or the caller's claim. The cron (service role) and a
  // granted force both fall through and rewrite the shared row.
  const { data: existing } = await supabase
    .from('pulse_scores')
    .select('id')
    .eq('relationship_id', relationshipId)
    .eq('week_ending', weekKey)
    .maybeSingle()
  if (!shouldComputeShared(opts.isService, opts.force, Boolean(existing))) {
    await _computePrivateScores(supabase, relationship, weekKey, moodBase, chatSignals, chatWeight)
    return null
  }

  // 3. Attachment quiz completion status
  const { data: userAProfile } = await supabase
    .from('psych_profiles')
    .select('attachment_style')
    .eq('user_id', relationship.user_a)
    .maybeSingle()

  const { data: userBProfile } = await supabase
    .from('psych_profiles')
    .select('attachment_style')
    .eq('user_id', relationship.user_b)
    .maybeSingle()

  // != null: a missing profile row used to read as "completed" (undefined !== null).
  const bothCompletedAttachment =
    userAProfile?.attachment_style != null && userBProfile?.attachment_style != null

  // 4. Previous WEEK's score for deltas. A forced recompute of the current
  // week must diff against last week, never against its own earlier run
  // (spec1-map-f5 §3.2).
  const { data: previousPulse } = await supabase
    .from('pulse_scores')
    .select('*')
    .eq('relationship_id', relationshipId)
    .lt('week_ending', weekKey)
    .order('week_ending', { ascending: false })
    .limit(1)
    .maybeSingle()

  // ──────────────────────────────────────────────────────────
  // COMPUTE THE FOUR SHARED DIMENSIONS
  // ──────────────────────────────────────────────────────────

  // COMMUNICATION
  let communication = 50 // baseline

  const conflicts = timelineEvents?.filter(e => e.event_type === 'conflict') || []
  const conflictPenalty = conflicts.length * 3
  communication = clamp(communication - conflictPenalty, 0, 100)

  // Resolved conflicts (mood_score >= 7) give bonus
  const resolvedConflicts = conflicts.filter(c => c.mood_score && c.mood_score >= 7)
  const resolutionBonus = resolvedConflicts.length * 5
  communication = clamp(communication + resolutionBonus, 0, 100)

  // CONNECTION
  const positiveEvents = timelineEvents?.filter(e =>
    e.event_type === 'milestone' || e.event_type === 'highlight'
  ) || []
  let connection = clamp(50 + (positiveEvents.length * 8), 0, 100)

  const anniversaryEvents = timelineEvents?.filter(e => e.event_type === 'anniversary') || []
  if (anniversaryEvents.length > 0) {
    connection = clamp(connection + 15, 0, 100)
  }

  // CONFLICT HEALTH: an explicit weighted blend of the shared sources. Chat
  // sources sit at 0.8 weight, subordinate to the human-logged mood at 1.0.
  const conflictMoods = conflicts.filter(c => c.mood_score).map(c => c.mood_score)
  const avgConflictMood = conflictMoods.length
    ? conflictMoods.reduce((a: number, b: number) => a + b, 0) / conflictMoods.length
    : null

  const conflictSources: { v: number; w: number }[] = []
  if (avgConflictMood != null) conflictSources.push({ v: avgConflictMood * 10, w: 1.0 })
  if (
    chatSignals.repairRate != null &&
    chatSignals.attemptRate != null &&
    chatSignals.conflictSessionCount >= 2
  ) {
    const repairBonus =
      chatSignals.repairRate * 12 + (chatSignals.attemptRate - chatSignals.repairRate) * 3
    conflictSources.push({ v: 70 + repairBonus, w: 0.8 * chatWeight })
  }
  if (chatSignals.avgEscalation != null && chatSignals.sessionCount >= 3) {
    // Centered at 0.4, not 0 — some escalation is normal; Conflict Health
    // measures repair quality, not conflict absence (PULSE.md §4.1).
    conflictSources.push({ v: 70 - (chatSignals.avgEscalation - 0.4) * 50, w: 0.8 * chatWeight })
  }
  const conflictHealth = conflictSources.length
    ? clamp(Math.round(weightedMean(conflictSources)), 0, 100)
    : 70 // optimistic baseline

  // ALIGNMENT
  let alignment = 50
  if (bothCompletedAttachment) {
    alignment = clamp(alignment + 20, 0, 100)
  }

  // Chat adjustments (coverage-ramped). applyChatSignals also carries the
  // Emotional-safety penalties; here only the two shared outputs are used.
  const chatAdjusted = applyChatSignals(
    { communication, connection, emotionalSafety: 0 },
    chatSignals,
    chatWeight
  )
  communication = chatAdjusted.communication
  connection = chatAdjusted.connection

  // Game signals (§7: Connection <- engagement, Alignment <- values overlap).
  const gameAdjusted = applyGameSignals({ connection, alignment }, gameSignals)
  connection = gameAdjusted.connection
  alignment = gameAdjusted.alignment

  // ──────────────────────────────────────────────────────────
  // PER-DIMENSION CONFIDENCE (evidence-points model, shared sources only:
  // counting a partner's private answer here would publish that they
  // answered — SPEC §11 constraint 10)
  // ──────────────────────────────────────────────────────────
  const communicationPoints =
    Math.min(conflicts.length, 4) * 1 +
    Math.min(Math.floor(chatSignals.analysedCount / 10), 3) * 1.5
  const communicationConfidence = confidenceFrom(communicationPoints, hasChatSignal)

  const connectionPoints =
    Math.min(positiveEvents.length, 4) * 1 +
    Math.min(chatSignals.bidsTotal >= 5 ? 1 : 0, 1) * 4.5 +
    Math.min(gameSignals.sessionsCompleted, 3) * 1
  const connectionConfidence = confidenceFrom(connectionPoints, hasChatSignal)

  const conflictHealthPoints =
    Math.min(conflicts.length, 4) * 1 +
    Math.min(chatSignals.sessionCount, 4) * 1.5
  const conflictHealthConfidence = confidenceFrom(conflictHealthPoints, hasChatSignal)

  const alignmentPoints =
    (bothCompletedAttachment ? 3 : 0) +
    (gameSignals.slidingScalePairs >= 4 ? 2 : 0)
  const alignmentConfidence = confidenceFrom(alignmentPoints, hasChatSignal)

  // OVERALL SCORE (four shared dimensions, weights normalised from 22/22/20/18)
  const overall = overallFromShared({ communication, connection, conflictHealth, alignment })

  const confidences: Confidence[] = [
    communicationConfidence,
    connectionConfidence,
    conflictHealthConfidence,
    alignmentConfidence,
  ]
  const overallConfidence = rollupConfidence(confidences)

  // DELTAS vs the previous week
  let deltas = null
  if (previousPulse) {
    deltas = {
      overall: overall - previousPulse.overall_score,
      communication: communication - previousPulse.communication,
      connection: connection - previousPulse.connection,
      conflict_health: conflictHealth - previousPulse.conflict_health,
      alignment: alignment - previousPulse.alignment,
    }
  }

  // SAVE THE SHARED ROW
  const pulseData = {
    relationship_id: relationshipId,
    week_ending: weekKey,
    overall_score: overall,
    communication,
    connection,
    conflict_health: conflictHealth,
    alignment,
    // Self-facing since Spec 1a: never in the shared row.
    emotional_safety: null,
    data_confidence: overallConfidence,
    dimension_confidence: {
      communication: communicationConfidence,
      connection: connectionConfidence,
      conflict_health: conflictHealthConfidence,
      alignment: alignmentConfidence,
    },
    delta_vs_previous: deltas,
  }

  const { error: upsertError } = await supabase
    .from('pulse_scores')
    .upsert(pulseData, { onConflict: 'relationship_id,week_ending' })

  if (upsertError) {
    console.error('Failed to save pulse score:', upsertError.code ?? 'error')
    throw new Error(`Failed to save pulse score for relationship ${relationshipId}`)
  }

  // Each member's private Emotional safety (self-only table). Also runs on
  // the early-return path above, so it never depends on a shared recompute.
  await _computePrivateScores(supabase, relationship, weekKey, moodBase, chatSignals, chatWeight)

  // Diagnostics: raw chat aggregates for tuning/observability, written to
  // a service-role-only table never exposed to clients. Best-effort.
  const { error: diagnosticsError } = await supabase
    .from('pulse_score_diagnostics')
    .upsert(
      {
        relationship_id: relationshipId,
        week_ending: weekKey,
        chat_weight: chatWeight,
        raw_signals: chatSignals,
      },
      { onConflict: 'relationship_id,week_ending' }
    )
  if (diagnosticsError) {
    console.error('Failed to write pulse score diagnostics (non-fatal):', diagnosticsError.code ?? 'error')
  }

  return pulseData
}

/// The only reader of the check-in table in this function. One row per member
/// who checked in this week, into pulse_private_scores (auth.uid()-only).
async function _computePrivateScores(
  supabase: any,
  relationship: RelationshipRow,
  weekKey: string,
  moodBase: number | null,
  chatSignals: ChatSignals,
  chatWeight: number,
) {
  const { data: checkins }: { data: any[] | null } = await supabase
    .from('weekly_checkins')
    .select('user_id, safety_rating')
    .eq('relationship_id', relationship.id)
    .eq('week_ending', weekKey)

  for (const checkin of checkins ?? []) {
    const score = privateEmotionalSafety({
      moodBase,
      safetyRating: checkin.safety_rating ?? null,
      signals: chatSignals,
      chatWeight,
    })
    if (score == null) continue
    const { error } = await supabase
      .from('pulse_private_scores')
      .upsert(
        {
          relationship_id: relationship.id,
          user_id: checkin.user_id,
          week_ending: weekKey,
          emotional_safety: score,
          computed_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,week_ending' },
      )
    if (error) {
      console.error('Failed to save private pulse score:', error.code ?? 'error')
    }
  }
}

/// The UTC Sunday on or after the UTC date of `date`. A Sunday is its own
/// week ending — the same rule as Dart's pulseWeekEnding, and the one the
/// Sunday 00:07 UTC cron needs (the old `7 - getDay()` made a Sunday roll a
/// whole week forward).
export function getWeekEnding(date: Date): Date {
  const day = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()))
  const daysToSunday = (7 - day.getUTCDay()) % 7
  day.setUTCDate(day.getUTCDate() + daysToSunday)
  return day
}

export function weekEndingKey(date: Date): string {
  return getWeekEnding(date).toISOString().split('T')[0]
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max)
}

/// The shared weights (PULSE.md §4.1 minus Emotional safety), normalised at
/// use: 22/82, 22/82, 20/82, 18/82 ≈ 27 %, 27 %, 24 %, 22 %.
export const SHARED_WEIGHTS = {
  communication: 22,
  connection: 22,
  conflictHealth: 20,
  alignment: 18,
} as const

export interface SharedDimensions {
  communication: number
  connection: number
  conflictHealth: number
  alignment: number
}

export function overallFromShared(d: SharedDimensions): number {
  const total =
    SHARED_WEIGHTS.communication + SHARED_WEIGHTS.connection +
    SHARED_WEIGHTS.conflictHealth + SHARED_WEIGHTS.alignment
  return Math.round(
    (d.communication * SHARED_WEIGHTS.communication +
      d.connection * SHARED_WEIGHTS.connection +
      d.conflictHealth * SHARED_WEIGHTS.conflictHealth +
      d.alignment * SHARED_WEIGHTS.alignment) / total,
  )
}

/// One member's private Emotional safety: the shared mood base (or 50)
/// blended with their own rating, then the chat safety penalties. Null when
/// they have not checked in — there is nothing private to show.
export function privateEmotionalSafety(input: {
  moodBase: number | null
  safetyRating: number | null
  signals: ChatSignals
  chatWeight: number
}): number | null {
  if (input.safetyRating == null) return null
  const base = input.moodBase ?? 50
  const blended = Math.round((base + input.safetyRating * 10) / 2)
  const adjusted = applyChatSignals(
    { communication: 0, connection: 0, emotionalSafety: blended },
    input.signals,
    input.chatWeight,
  )
  return clamp(Math.round(adjusted.emotionalSafety), 0, 100)
}

/**
 * Weighted mean of independent score sources, each `{ v: value, w: weight }`.
 * Zero-weight sources fall out naturally. Returns the 70 optimistic baseline
 * when total weight is zero.
 */
export function weightedMean(sources: { v: number; w: number }[]): number {
  const totalWeight = sources.reduce((sum, s) => sum + s.w, 0)
  if (totalWeight === 0) return 70
  return sources.reduce((sum, s) => sum + s.v * s.w, 0) / totalWeight
}

export function computeChatWeight(coverageDays: number): number {
  const coverage = Math.min(coverageDays, 30) / 30
  if (coverage < 0.25) return 0
  return Math.min((coverage - 0.25) / 0.5, 1)
}

export interface ChatSignals {
  analysedCount: number
  avgTone: number | null
  violationRate: number | null
  severeRate: number | null
  bidTurnRate: number | null
  bidsTotal: number
  sessionCount: number
  conflictSessionCount: number
  avgEscalation: number | null
  repairRate: number | null
  attemptRate: number | null
  stonewallRate: number | null
  pursueWithdrawRate: number | null
}

/**
 * The dimensions adjusted by chat signal as relative deltas on an
 * already-computed baseline. emotionalSafety stays in this shape because
 * privateEmotionalSafety reuses the same penalties; the shared path ignores
 * that output.
 */
export interface DimensionState {
  communication: number
  connection: number
  emotionalSafety: number
}

export function applyChatSignals(
  dimensions: DimensionState,
  signals: ChatSignals,
  chatWeight: number
): DimensionState {
  let { communication, connection, emotionalSafety } = dimensions

  if (chatWeight > 0) {
    // COMMUNICATION
    if (signals.avgTone != null && signals.analysedCount >= 10) {
      communication = clamp(communication + signals.avgTone * 10 * chatWeight, 0, 100)
    }
    if (signals.violationRate != null && signals.analysedCount >= 10) {
      const nvcPenalty = Math.min(signals.violationRate / 0.2, 1) * 12
      communication = clamp(communication - nvcPenalty * chatWeight, 0, 100)
    }
    if (signals.stonewallRate != null && signals.sessionCount >= 3) {
      communication = clamp(communication - signals.stonewallRate * 10 * chatWeight, 0, 100)
    }

    // CONNECTION
    if (signals.bidTurnRate != null && signals.bidsTotal >= 5) {
      connection = clamp(connection + (signals.bidTurnRate - 0.5) * 24 * chatWeight, 0, 100)
    }

    // EMOTIONAL SAFETY (private path only)
    if (signals.severeRate != null && signals.analysedCount >= 10) {
      const safetyPenalty = Math.min(signals.severeRate / 0.1, 1) * 12
      emotionalSafety = clamp(emotionalSafety - safetyPenalty * chatWeight, 0, 100)
    }
    if (signals.pursueWithdrawRate != null && signals.sessionCount >= 3) {
      emotionalSafety = clamp(emotionalSafety - signals.pursueWithdrawRate * 8 * chatWeight, 0, 100)
    }
  }

  return { communication, connection, emotionalSafety }
}

export interface GameSignals {
  sessionsCompleted: number
  slidingScalePairs: number
  slidingScaleAvgGap: number | null
  mirrorRoundsScored: number
}

export interface GameDimensionState {
  connection: number
  alignment: number
}

/// Blends game signals into the two dimensions §7 says they belong to.
/// Deliberately does NOT consume mirrorRoundsScored (per-person, §11.1).
export function applyGameSignals(
  dimensions: GameDimensionState,
  signals: GameSignals
): GameDimensionState {
  let { connection, alignment } = dimensions

  if (signals.sessionsCompleted > 0) {
    connection = clamp(connection + Math.min(signals.sessionsCompleted * 2, 10), 0, 100)
  }

  if (signals.slidingScalePairs >= 4 && signals.slidingScaleAvgGap != null) {
    const maxGap = 9
    const clampedGap = Math.max(0, Math.min(maxGap, signals.slidingScaleAvgGap))
    const delta = ((maxGap / 2 - clampedGap) / (maxGap / 2)) * 15
    alignment = clamp(alignment + delta, 0, 100)
  }

  return { connection, alignment }
}

export type Confidence = 'none' | 'low' | 'medium' | 'high'

export function confidenceFrom(points: number, hasChatSignal: boolean): Confidence {
  if (points < 2) return 'none'
  if (points < 5) return 'low'
  if (points < 9) return 'medium'
  // 'high' requires chat signal per PULSE.md §7.
  return hasChatSignal ? 'high' : 'medium'
}

/// Fraction-based so it reads the same for four shared dimensions as it did
/// for five: ≥ 3/4 high → high; ≥ 1/2 medium → medium; any medium → low.
export function rollupConfidence(confidences: Confidence[]): Confidence {
  const n = confidences.length
  if (n === 0) return 'none'
  const highCount = confidences.filter((c) => c === 'high').length
  const mediumCount = confidences.filter((c) => c === 'medium').length
  if (highCount / n >= 0.75) return 'high'
  if (mediumCount / n >= 0.5) return 'medium'
  if (mediumCount >= 1) return 'low'
  return 'none'
}
```

- [ ] **Step 6: Trim generate-verdict**

In `supabase/functions/generate-verdict/index.ts`, inside `buildEvidence`, change the metric array
```ts
        "alignment",
        "emotional_safety",
      ]
```
to
```ts
        "alignment",
        // emotional_safety is self-facing since Spec 1a and never evidence.
      ]
```

- [ ] **Step 7: Run the Deno tests**

Run:
```bash
deno test --allow-read --allow-env --allow-net supabase/functions/compute-pulse
deno test --allow-read --allow-env --allow-net supabase/functions/generate-verdict
deno check supabase/functions/compute-pulse/index.ts supabase/functions/generate-verdict/index.ts
```
Expected: compute-pulse `76 passed` (60 − 1 replaced + 3 week-ending + 7 appended + 7 privacy = 76; record the actual number), generate-verdict all passed, `deno check` clean. Diff `index.test.ts` against its snapshot: only the import block, the one replaced test and the appended tests.

- [ ] **Step 8: Ledger**

Append `Task 7: complete (pulse_privacy_contracts green + mutant red; deno compute-pulse N passed, generate-verdict M passed). Owner must redeploy compute-pulse and generate-verdict (final task).`

---

### Task 8: Pulse Dart — four shared dimensions, weights, "Your week", paused, week ending, refresh copy

**Files:**
- Create: `lib/features/pulse/domain/pulse_dimensions.dart`
- Create: `lib/features/pulse/domain/pulse_week.dart`
- Create: `lib/features/pulse/domain/pulse_refresh_copy.dart`
- Create: `lib/features/pulse/data/models/your_week.dart`
- Create: `lib/features/pulse/presentation/widgets/your_week_card.dart`
- Create: `lib/features/pulse/presentation/widgets/pulse_paused_state.dart`
- Modify: `lib/features/pulse/data/models/pulse_score.dart` (nullable `emotionalSafety`, `scoreFor`)
- Modify: `lib/features/pulse/data/repositories/pulse_repository.dart` (whole file: dead paths removed, `fetchYourWeek` added)
- Modify: `lib/features/pulse/providers/pulse_providers.dart` (whole file: status provider, `pulseRecomputeInvokerProvider` seam, no client rate limit, no both-check, `yourWeekProvider`)
- Modify: `lib/features/pulse/presentation/screens/pulse_screen.dart` (imports, `_refreshPulse` catch, paused branch, dimension maps, Your week card, `_getDimensionKey`, `_showDimensionTooltip`)
- Modify: `lib/features/pulse/presentation/widgets/radar_chart.dart` (`_order`, tooltip, short labels)
- Modify: `lib/features/pulse/presentation/widgets/number_view.dart` (`dimOrder`)
- Modify: `lib/features/pulse/presentation/widgets/checkin_banner.dart`, `lib/features/pulse/presentation/screens/checkin_complete_screen.dart` (copy)
- Modify: `test/features/pulse/pulse_screen_test.dart` (two overrides in the harness; four new tests)
- Test: `test/features/pulse/pulse_dimensions_test.dart`, `pulse_week_test.dart`, `pulse_refresh_copy_test.dart`, `your_week_card_test.dart`

**Interfaces:**
- Consumes: `pulse_private_scores`, nullable `pulse_scores.emotional_safety`, compute-pulse's 429 body (Task 7); `FunctionException(status, details)` from `supabase_flutter`; `EmptyStateWidget(icon:, title:, subtitle:)`, `CardInkWell`, `InfoRowWidget`, `Spacing`, `Gap` from `export_screens.dart`.
- Produces:
  - `class PulseDimension { label, key, shortLabel, description, weight }`, `const sharedPulseDimensions` (4), `const sharedPulseWeightTotal = 82`, `int sharedWeightPercent(PulseDimension)`, `String sharedWeightLine(PulseDimension)`, `const emotionalSafetyPrivateNote`, `PulseDimension? pulseDimensionByLabel(String)`.
  - `DateTime pulseWeekEnding(DateTime now)` (UTC Sunday on/after), `String pulseWeekEndingKey(DateTime now)` (`yyyy-MM-dd`).
  - `String pulseRefreshMessage(Object error)`.
  - `class WeeklyCheckinAnswers { communication, connection, conflictHealth (int?), conflictHealthNA, alignment, safety; fromJson }`, `class YourWeek { checkin, emotionalSafety, weekEnding; hasCheckin }`.
  - `PulseScore.emotionalSafety` is `int?`; `int scoreFor(String key)`.
  - Providers: `typedef PulseRelationship = ({String id, String status})`, `currentRelationshipStatusProvider` (`FutureProvider<PulseRelationship?>`), `yourWeekProvider` (`FutureProvider<YourWeek>`); `typedef PulseRecomputeInvoker = Future<void> Function(String relationshipId, {required bool force})` and `pulseRecomputeInvokerProvider` (the one call to the edge function; tests override it); `recomputePulseProvider` is `FutureProvider.autoDispose.family<bool, String>`, calls the invoker with `force: true` and rethrows the server's `FunctionException`; the screen **invalidates it before every read** (I1) so a second tap always reaches the server; `submitWeeklyCheckinProvider` calls the invoker with `force: false` (private pass only; no claim, no shared rewrite) and then invalidates `yourWeekProvider`.
  - `PulseRepository.fetchYourWeek({required String userId, required String weekEndingKey}) → Future<YourWeek>` — both reads are for **that week only** (`week_ending = weekEndingKey`); a stale earlier week never shows as this week's score.
  - Widgets `YourWeekCard()` (ConsumerWidget), `PulsePausedState()`.

- [ ] **Step 1: Write the failing unit tests (domain)**

```dart
// test/features/pulse/pulse_dimensions_test.dart
import 'package:attune/features/pulse/domain/pulse_dimensions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('four shared dimensions, in the server order, no Emotional safety', () {
    expect(sharedPulseDimensions.map((d) => d.label), [
      'Communication',
      'Connection',
      'Conflict Health',
      'Alignment',
    ]);
    expect(sharedPulseDimensions.map((d) => d.key), [
      'communication',
      'connection',
      'conflict_health',
      'alignment',
    ]);
    expect(sharedPulseDimensions.any((d) => d.label.contains('Safety')), isFalse);
  });

  test('weights are 22/22/20/18, disclosed as 27/27/24/22 and sum to 100', () {
    expect(sharedPulseDimensions.map((d) => d.weight), [22, 22, 20, 18]);
    expect(sharedPulseWeightTotal, 82);
    final pct = sharedPulseDimensions.map(sharedWeightPercent).toList();
    expect(pct, [27, 27, 24, 22]);
    expect(pct.fold<int>(0, (a, b) => a + b), 100);
    expect(
      sharedWeightLine(sharedPulseDimensions.first),
      'Counts for 27% of the shared score.',
    );
  });

  test('lookup by label, and the private note', () {
    expect(pulseDimensionByLabel('Alignment')?.key, 'alignment');
    expect(pulseDimensionByLabel('Emotional Safety'), isNull);
    expect(
      emotionalSafetyPrivateNote,
      'Emotional safety is not part of the shared score. Each of you sees your own in Your week.',
    );
  });
}
```

```dart
// test/features/pulse/pulse_week_test.dart
import 'package:attune/features/pulse/domain/pulse_week.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Sunday is its own week ending (matches the server)', () {
    expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 16, 10)), '2026-08-16');
    expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 16, 23, 59, 59)), '2026-08-16');
  });

  test('a Wednesday rolls forward to the coming Sunday', () {
    expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 12, 10)), '2026-08-16');
    expect(pulseWeekEnding(DateTime.utc(2026, 8, 12, 10)).weekday, DateTime.sunday);
  });

  test('Saturday 23:59 UTC and Sunday 00:01 UTC share a week; Monday 00:01 UTC does not', () {
    expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 15, 23, 59)), '2026-08-16');
    expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 16, 0, 1)), '2026-08-16');
    expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 17, 0, 1)), '2026-08-23');
  });

  test('local times are converted to UTC first', () {
    // The same instant, expressed with a non-UTC offset, lands on the same key.
    final local = DateTime.utc(2026, 8, 17, 0, 1).toLocal();
    expect(pulseWeekEndingKey(local), '2026-08-23');
  });
}
```

```dart
// test/features/pulse/pulse_refresh_copy_test.dart
import 'package:attune/features/pulse/domain/pulse_refresh_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

void main() {
  test('a 429 with a retry time is worded in hours', () {
    expect(
      pulseRefreshMessage(
        const FunctionException(status: 429, details: {'retry_after_seconds': 7200}),
      ),
      'You can refresh again in about 2 hours.',
    );
    expect(
      pulseRefreshMessage(
        const FunctionException(status: 429, details: {'retry_after_seconds': 7201}),
      ),
      'You can refresh again in about 3 hours.',
    );
  });

  test('under an hour says so', () {
    expect(
      pulseRefreshMessage(
        const FunctionException(status: 429, details: {'retry_after_seconds': 1800}),
      ),
      'You can refresh again in under an hour.',
    );
  });

  test('a 429 without details assumes the full day', () {
    expect(
      pulseRefreshMessage(const FunctionException(status: 429)),
      'You can refresh again in about 24 hours.',
    );
  });

  test('anything else is a plain retry line, never the raw error', () {
    expect(
      pulseRefreshMessage(const FunctionException(status: 500, details: 'boom')),
      "Couldn't refresh Pulse. Try again.",
    );
    expect(pulseRefreshMessage(Exception('x')), "Couldn't refresh Pulse. Try again.");
  });
}
```

```dart
// test/features/pulse/your_week_card_test.dart
import 'package:attune/features/pulse/data/models/your_week.dart';
import 'package:attune/features/pulse/presentation/widgets/your_week_card.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart' show yourWeekProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, YourWeek week) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [yourWeekProvider.overrideWith((ref) async => week)],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => const MaterialApp(
              home: Scaffold(body: SingleChildScrollView(child: YourWeekCard())),
            ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

const _answers = WeeklyCheckinAnswers(
  communication: 8,
  connection: 7,
  conflictHealth: null,
  conflictHealthNA: true,
  alignment: 9,
  safety: 6,
);

void main() {
  testWidgets('no check-in yet: the card says so and shows no number', (t) async {
    await _pump(t, const YourWeek());
    expect(find.text('Your week'), findsOneWidget);
    expect(find.text('Only you can see this.'), findsOneWidget);
    expect(find.text('No check-in this week yet.'), findsOneWidget);
    expect(find.text('Emotional safety'), findsNothing);
  });

  testWidgets('with a check-in: my private score and my answers', (t) async {
    await _pump(t, YourWeek(checkin: _answers, emotionalSafety: 71, weekEnding: DateTime.utc(2026, 10, 18)));
    expect(find.text('Emotional safety'), findsOneWidget);
    expect(find.text('71'), findsOneWidget);
    expect(find.text('8/10'), findsOneWidget);
    expect(find.text('Not this week'), findsOneWidget);
    expect(find.text('6/10'), findsOneWidget);
  });

  testWidgets('a check-in whose score is not computed yet shows a dash', (t) async {
    await _pump(t, const YourWeek(checkin: _answers));
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('fromJson reads the check-in row', (t) async {
    final a = WeeklyCheckinAnswers.fromJson({
      'communication_rating': 8,
      'connection_rating': 7,
      'conflict_health_rating': null,
      'conflict_health_na': true,
      'alignment_rating': 9,
      'safety_rating': 6,
    });
    expect(a, _answers);
  });
}
```

Run: `flutter test test/features/pulse/pulse_dimensions_test.dart test/features/pulse/pulse_week_test.dart test/features/pulse/pulse_refresh_copy_test.dart test/features/pulse/your_week_card_test.dart`
Expected: all four FAIL to compile (missing files).

- [ ] **Step 2: Write the domain, model and widget files**

```dart
// lib/features/pulse/domain/pulse_dimensions.dart
import 'package:flutter/foundation.dart';

/// One shared Pulse dimension (PULSE.md §4.1 as amended by §11, Spec 1a).
@immutable
class PulseDimension {
  const PulseDimension({
    required this.label,
    required this.key,
    required this.shortLabel,
    required this.description,
    required this.weight,
  });

  /// Display label, also the map key the screen and charts use.
  final String label;

  /// The `pulse_scores` column / `delta_vs_previous` key.
  final String key;
  final String shortLabel;
  final String description;

  /// Raw weight (22/22/20/18); normalised against [sharedPulseWeightTotal].
  final int weight;
}

/// The four dimensions both partners see. Emotional safety is deliberately
/// absent: it is computed per partner and shown only to its author.
const sharedPulseDimensions = <PulseDimension>[
  PulseDimension(
    label: 'Communication',
    key: 'communication',
    shortLabel: 'Comm',
    description: 'How clearly and kindly you express yourselves',
    weight: 22,
  ),
  PulseDimension(
    label: 'Connection',
    key: 'connection',
    shortLabel: 'Conn',
    description: 'Emotional closeness and warmth',
    weight: 22,
  ),
  PulseDimension(
    label: 'Conflict Health',
    key: 'conflict_health',
    shortLabel: 'Conflict',
    description: 'How well you navigate disagreements',
    weight: 20,
  ),
  PulseDimension(
    label: 'Alignment',
    key: 'alignment',
    shortLabel: 'Align',
    description: 'Shared values and direction',
    weight: 18,
  ),
];

const sharedPulseWeightTotal = 82;

int sharedWeightPercent(PulseDimension d) =>
    (d.weight * 100 / sharedPulseWeightTotal).round();

String sharedWeightLine(PulseDimension d) =>
    'Counts for ${sharedWeightPercent(d)}% of the shared score.';

const emotionalSafetyPrivateNote =
    'Emotional safety is not part of the shared score. '
    'Each of you sees your own in Your week.';

PulseDimension? pulseDimensionByLabel(String label) {
  for (final d in sharedPulseDimensions) {
    if (d.label == label) return d;
  }
  return null;
}
```

```dart
// lib/features/pulse/domain/pulse_week.dart

/// The UTC Sunday on or after the UTC date of [now]; a Sunday is its own
/// week ending. Mirrors compute-pulse's getWeekEnding exactly, so a check-in
/// is filed under the week the server computes.
DateTime pulseWeekEnding(DateTime now) {
  final u = now.toUtc();
  final day = DateTime.utc(u.year, u.month, u.day);
  return day.add(Duration(days: (DateTime.sunday - day.weekday) % 7));
}

/// `yyyy-MM-dd`, the `week_ending` key.
String pulseWeekEndingKey(DateTime now) =>
    pulseWeekEnding(now).toIso8601String().split('T').first;
```

```dart
// lib/features/pulse/domain/pulse_refresh_copy.dart
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

/// What the Pulse screen says when a refresh fails. The server enforces the
/// 24 h limit (429 with `retry_after_seconds`); nothing else about the error
/// is ever shown.
String pulseRefreshMessage(Object error) {
  if (error is FunctionException && error.status == 429) {
    final details = error.details;
    final seconds =
        details is Map ? (details['retry_after_seconds'] as num?)?.toInt() : null;
    final s = seconds ?? 86400;
    if (s <= 3600) return 'You can refresh again in under an hour.';
    return 'You can refresh again in about ${(s / 3600).ceil()} hours.';
  }
  return "Couldn't refresh Pulse. Try again.";
}
```

```dart
// lib/features/pulse/data/models/your_week.dart
import 'package:flutter/foundation.dart';

/// My own weekly check-in answers. Read only from my own weekly_checkins row
/// (auth.uid()-only RLS); never rendered to anyone else.
@immutable
class WeeklyCheckinAnswers {
  const WeeklyCheckinAnswers({
    required this.communication,
    required this.connection,
    required this.conflictHealth,
    required this.conflictHealthNA,
    required this.alignment,
    required this.safety,
  });

  factory WeeklyCheckinAnswers.fromJson(Map<String, dynamic> json) =>
      WeeklyCheckinAnswers(
        communication: (json['communication_rating'] as num?)?.toInt() ?? 0,
        connection: (json['connection_rating'] as num?)?.toInt() ?? 0,
        conflictHealth: (json['conflict_health_rating'] as num?)?.toInt(),
        conflictHealthNA: json['conflict_health_na'] == true,
        alignment: (json['alignment_rating'] as num?)?.toInt() ?? 0,
        safety: (json['safety_rating'] as num?)?.toInt() ?? 0,
      );

  final int communication;
  final int connection;
  final int? conflictHealth;
  final bool conflictHealthNA;
  final int alignment;
  final int safety;

  @override
  bool operator ==(Object other) =>
      other is WeeklyCheckinAnswers &&
      other.communication == communication &&
      other.connection == connection &&
      other.conflictHealth == conflictHealth &&
      other.conflictHealthNA == conflictHealthNA &&
      other.alignment == alignment &&
      other.safety == safety;

  @override
  int get hashCode => Object.hash(
    communication,
    connection,
    conflictHealth,
    conflictHealthNA,
    alignment,
    safety,
  );
}

/// The private "Your week" view: my check-in for the current week and my
/// latest private Emotional safety (pulse_private_scores).
@immutable
class YourWeek {
  const YourWeek({this.checkin, this.emotionalSafety, this.weekEnding});

  final WeeklyCheckinAnswers? checkin;
  final int? emotionalSafety;
  final DateTime? weekEnding;

  bool get hasCheckin => checkin != null;
}
```

```dart
// lib/features/pulse/presentation/widgets/pulse_paused_state.dart
import 'package:attune/core/utils/exports/export_screens.dart';

/// Pulse while the relationship is paused (F5 (5)): nothing is computed or
/// shown — no score, no check-in, no refresh.
class PulsePausedState extends StatelessWidget {
  const PulsePausedState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(Spacing.lg.w),
      child: const EmptyStateWidget(
        icon: Icons.pause_circle_outline,
        title: 'Pulse is paused',
        subtitle:
            'Nothing is computed or shown while your relationship is paused.',
      ),
    );
  }
}
```

```dart
// lib/features/pulse/presentation/widgets/your_week_card.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/pulse/data/models/your_week.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The self-facing half of Pulse (Spec 1a; SOUL §9): my private Emotional
/// safety and my own check-in answers. Rendered from auth.uid()-only data;
/// the partner has their own.
class YourWeekCard extends ConsumerWidget {
  const YourWeekCard({super.key});

  static const _rows = <(String, int? Function(WeeklyCheckinAnswers))>[
    ('Communication', _communication),
    ('Connection', _connection),
    ('Conflict health', _conflictHealth),
    ('Alignment', _alignment),
    ('Emotional safety answer', _safety),
  ];

  static int? _communication(WeeklyCheckinAnswers a) => a.communication;
  static int? _connection(WeeklyCheckinAnswers a) => a.connection;
  static int? _conflictHealth(WeeklyCheckinAnswers a) =>
      a.conflictHealthNA ? null : a.conflictHealth;
  static int? _alignment(WeeklyCheckinAnswers a) => a.alignment;
  static int? _safety(WeeklyCheckinAnswers a) => a.safety;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final weekAsync = ref.watch(yourWeekProvider);

    return weekAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (week) {
        final checkin = week.checkin;
        return CardInkWell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your week',
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              Gap(Spacing.xs.h),
              Text(
                'Only you can see this.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Gap(Spacing.md.h),
              if (checkin == null)
                Text('No check-in this week yet.', style: textTheme.bodyMedium)
              else ...[
                Row(
                  children: [
                    Text('Emotional safety', style: textTheme.bodyMedium),
                    const Spacer(),
                    Text(
                      week.emotionalSafety?.toString() ?? '—',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Gap(Spacing.xs.h),
                Text(
                  'From your check-in and the moments you both logged.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Gap(Spacing.md.h),
                Text(
                  'Your answers',
                  style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                Gap(Spacing.xs.h),
                for (final (label, read) in _rows)
                  Padding(
                    padding: EdgeInsets.only(bottom: Spacing.xs.h),
                    child: Row(
                      children: [
                        Text(label, style: textTheme.bodyMedium),
                        const Spacer(),
                        Text(
                          switch (read(checkin)) {
                            null => 'Not this week',
                            final v => '$v/10',
                          },
                          style: textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 3: Replace the repository and the providers**

Snapshot every pulse file first:
```bash
for f in lib/features/pulse/data/models/pulse_score.dart lib/features/pulse/data/repositories/pulse_repository.dart lib/features/pulse/providers/pulse_providers.dart lib/features/pulse/presentation/screens/pulse_screen.dart lib/features/pulse/presentation/widgets/radar_chart.dart lib/features/pulse/presentation/widgets/number_view.dart lib/features/pulse/presentation/widgets/checkin_banner.dart lib/features/pulse/presentation/screens/checkin_complete_screen.dart test/features/pulse/pulse_screen_test.dart; do cp "$f" "$WS/snapshots/pulse-$(basename $f)"; done
```

`pulse_score.dart`: change `final int emotionalSafety;` to
```dart
  /// Self-facing since Spec 1a: null on every new row. Kept nullable for
  /// history; never rendered on a shared surface.
  final int? emotionalSafety;
```
and `emotionalSafety: json['emotional_safety'],` to `emotionalSafety: json['emotional_safety'] as int?,`, and add after `getConfidenceForDimension`:
```dart
  /// A shared dimension's score by its server key; 0 for anything else.
  int scoreFor(String key) => switch (key) {
    'communication' => communication,
    'connection' => connection,
    'conflict_health' => conflictHealth,
    'alignment' => alignment,
    _ => 0,
  };
```

`pulse_repository.dart`, whole file:
```dart
// lib/features/pulse/data/repositories/pulse_repository.dart

import 'package:attune/features/pulse/data/models/your_week.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PulseRepository {
  final SupabaseClient _supabase;

  PulseRepository(this._supabase);

  Future<void> submitCheckin({
    required String userId,
    required String relationshipId,
    required DateTime weekEnding,
    required int communicationRating,
    required int connectionRating,
    required int? conflictHealthRating,
    required bool conflictHealthNA,
    required int alignmentRating,
    required int safetyRating,
  }) async {
    await _supabase.from('weekly_checkins').upsert({
      'user_id': userId,
      'relationship_id': relationshipId,
      'week_ending': weekEnding.toIso8601String().split('T')[0],
      'communication_rating': communicationRating,
      'connection_rating': connectionRating,
      'conflict_health_rating': conflictHealthRating,
      'conflict_health_na': conflictHealthNA,
      'alignment_rating': alignmentRating,
      'safety_rating': safetyRating,
    }, onConflict: 'user_id,week_ending');
  }

  /// My own check-in and my private Emotional safety, both for
  /// [weekEndingKey]. Both tables are auth.uid()-only on the server, so this
  /// can never read the partner's rows (Spec 1a).
  ///
  /// The former haveBothCompletedCheckin / triggerPulseRecompute /
  /// notification paths are gone: RLS made the first always false, and no
  /// shared number moves on a check-in any more.
  Future<YourWeek> fetchYourWeek({
    required String userId,
    required String weekEndingKey,
  }) async {
    final checkinRow =
        await _supabase
            .from('weekly_checkins')
            .select(
              'communication_rating,connection_rating,conflict_health_rating,'
              'conflict_health_na,alignment_rating,safety_rating',
            )
            .eq('user_id', userId)
            .eq('week_ending', weekEndingKey)
            .maybeSingle();
    // This week only: last week's private score must not read as this
    // week's (I5).
    final scoreRow =
        await _supabase
            .from('pulse_private_scores')
            .select('emotional_safety,week_ending')
            .eq('user_id', userId)
            .eq('week_ending', weekEndingKey)
            .maybeSingle();
    return YourWeek(
      checkin:
          checkinRow == null ? null : WeeklyCheckinAnswers.fromJson(checkinRow),
      emotionalSafety: (scoreRow?['emotional_safety'] as num?)?.toInt(),
      weekEnding:
          scoreRow == null
              ? null
              : DateTime.parse(scoreRow['week_ending'] as String),
    );
  }
}
```

`pulse_providers.dart`, whole file:
```dart
// lib/features/pulse/providers/pulse_providers.dart

import 'package:attune/features/auth/providers/auth_provider.dart'
    show authStateProvider;
import 'package:attune/features/pulse/data/models/pulse_score.dart';
import 'package:attune/features/pulse/data/models/your_week.dart';
import 'package:attune/features/pulse/data/repositories/pulse_repository.dart';
import 'package:attune/features/pulse/domain/pulse_week.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final pulseRepositoryProvider = Provider<PulseRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return PulseRepository(supabase);
});

// Current user ID — derives from authStateProvider (auth_provider.dart), NOT
// an imperative supabase.auth.currentUser read: see opinion_providers.dart's
// currentUserIdProvider for the full writeup of the caching bug this fixes.
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.id;
});

// Current ACTIVE relationship ID (null while paused). ref.watch on
// currentUserIdProvider so a sign-in/sign-out re-fetches.
final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final response =
      await supabase
          .from('relationships')
          .select('id')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .eq('status', 'active')
          .maybeSingle();

  return response?['id'] as String?;
});

typedef PulseRelationship = ({String id, String status});

/// The current relationship with its status. Unlike
/// [currentRelationshipIdProvider] it keeps 'paused' visible, so Pulse can
/// hide itself (F5 (5)) instead of showing a brand-new no-data state.
final currentRelationshipStatusProvider = FutureProvider<PulseRelationship?>((
  ref,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final row =
      await supabase
          .from('relationships')
          .select('id,status')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .inFilter('status', ['active', 'paused'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
  if (row == null) return null;
  return (id: row['id'] as String, status: row['status'] as String);
});

/// The one call to the compute-pulse edge function. `force: true` asks the
/// server to rewrite this week's shared row (and claims the caller's 24 h
/// limit); `force: false` only refreshes my private pass. A Provider so a
/// widget test can replace it without a Supabase client.
typedef PulseRecomputeInvoker =
    Future<void> Function(String relationshipId, {required bool force});

final pulseRecomputeInvokerProvider = Provider<PulseRecomputeInvoker>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return (relationshipId, {required force}) async {
    await supabase.functions.invoke(
      'compute-pulse',
      body: {'relationship_id': relationshipId, 'force_recompute': force},
    );
  };
});

// Submit weekly check-in. Private since Spec 1a: it feeds "Your week" and
// nothing shared. The non-forced call asks the server for the private pass
// only (no claim, no shared rewrite) so "Your week" fills in even when the
// weekly cron is off.
final submitWeeklyCheckinProvider = FutureProvider.family<
  void,
  ({
    int communicationRating,
    int connectionRating,
    int? conflictHealthRating,
    bool conflictHealthNA,
    int alignmentRating,
    int safetyRating,
  })
>((ref, params) async {
  final repository = ref.read(pulseRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);

  if (userId == null) throw Exception('Not authenticated');
  if (relationshipId == null) throw Exception('No active relationship');

  await repository.submitCheckin(
    userId: userId,
    relationshipId: relationshipId,
    weekEnding: pulseWeekEnding(DateTime.now()),
    communicationRating: params.communicationRating,
    connectionRating: params.connectionRating,
    conflictHealthRating: params.conflictHealthRating,
    conflictHealthNA: params.conflictHealthNA,
    alignmentRating: params.alignmentRating,
    safetyRating: params.safetyRating,
  );

  // Best effort: the answers are saved either way; a failed private pass
  // just leaves "Your week" showing a dash until the next refresh.
  try {
    await ref.read(pulseRecomputeInvokerProvider)(relationshipId, force: false);
  } catch (_) {}

  // After the awaits, so this never runs during the provider's own
  // initialization (see recomputePulseProvider's note below).
  ref.invalidate(yourWeekProvider);
});

// On-demand pulse recompute. The 24 h limit is enforced by the server
// (claim_pulse_recompute): a refusal arrives as a FunctionException with
// status 429 and `retry_after_seconds`, rethrown for the screen to word
// (pulseRefreshMessage). No client-side bookkeeping — it reset on restart
// and protected nothing. autoDispose, and the screen invalidates it before
// each read: a FutureProvider caches its result, and a second tap served
// from cache would never reach the server (Review Focus 8).
final recomputePulseProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  relationshipId,
) async {
  await ref.read(pulseRecomputeInvokerProvider)(relationshipId, force: true);

  // Deferred until after the await above — Riverpod treats a provider's
  // synchronous pre-await code as still part of its own initialization,
  // and mutating another provider's state in that window trips "Providers
  // are not allowed to modify other providers during their initialization".
  ref.invalidate(currentPulseScoreProvider);
  ref.invalidate(pulseHistoryProvider);
  ref.invalidate(yourWeekProvider);

  return true;
});

// Get current pulse score
final currentPulseScoreProvider = FutureProvider<PulseScore?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return null;

  final response =
      await supabase
          .from('pulse_scores')
          .select('*')
          .eq('relationship_id', relationshipId)
          .order('week_ending', ascending: false)
          .limit(1)
          .maybeSingle();

  if (response == null) return null;

  return PulseScore.fromJson(response);
});

// Get pulse history (last 4 weeks for trend chart)
final pulseHistoryProvider = FutureProvider<List<PulseScore>>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return [];

  final response = await supabase
      .from('pulse_scores')
      .select('*')
      .eq('relationship_id', relationshipId)
      .order('week_ending', ascending: false)
      .limit(4);

  return response.map((json) => PulseScore.fromJson(json)).toList();
});

/// My private "Your week": own check-in for the current week plus my latest
/// private Emotional safety. Self-only by RLS.
final yourWeekProvider = FutureProvider<YourWeek>((ref) async {
  final repository = ref.read(pulseRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const YourWeek();
  return repository.fetchYourWeek(
    userId: userId,
    weekEndingKey: pulseWeekEndingKey(DateTime.now()),
  );
});
```

- [ ] **Step 4: Edit the screen, the two charts and the two copy strings**

`pulse_screen.dart`:

(a) Add imports (keep alphabetical within the `package:attune` block):
```dart
import 'package:attune/features/pulse/domain/pulse_dimensions.dart';
import 'package:attune/features/pulse/domain/pulse_refresh_copy.dart';
import 'package:attune/features/pulse/presentation/widgets/pulse_paused_state.dart';
import 'package:attune/features/pulse/presentation/widgets/your_week_card.dart';
```

(b) In `_refreshPulse`, replace
```dart
      if (relationshipId != null) {
        await ref.read(recomputePulseProvider(relationshipId).future);
```
with
```dart
      if (relationshipId != null) {
        // A FutureProvider caches its last result; without this a second
        // tap would resolve from cache and never reach the server.
        ref.invalidate(recomputePulseProvider(relationshipId));
        await ref.read(recomputePulseProvider(relationshipId).future);
```
and replace `).showSnackBar(SnackBar(content: Text(e.toString())));` with `).showSnackBar(SnackBar(content: Text(pulseRefreshMessage(e))));`.

(c) In `build`, directly after `final historyAsync = ref.watch(pulseHistoryProvider);` insert:
```dart
    // Hidden while paused (F5 (5)): no score, no check-in, no refresh.
    final relationship =
        ref.watch(currentRelationshipStatusProvider).valueOrNull;
    if (relationship?.status == 'paused') {
      return CustomScrollView(
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: PulsePausedState(),
          ),
        ],
      );
    }
```

(d) Replace the two literal maps
```dart
                      // Build dimension map for visualisations
                      final dimensions = {
                        'Communication': pulse.communication,
                        'Connection': pulse.connection,
                        'Conflict Health': pulse.conflictHealth,
                        'Alignment': pulse.alignment,
                        'Emotional Safety': pulse.emotionalSafety,
                      };

                      final deltas = {
                        'Communication': pulse.getDeltaForDimension(
                          'communication',
                        ),
                        'Connection': pulse.getDeltaForDimension('connection'),
                        'Conflict Health': pulse.getDeltaForDimension(
                          'conflict_health',
                        ),
                        'Alignment': pulse.getDeltaForDimension('alignment'),
                        'Emotional Safety': pulse.getDeltaForDimension(
                          'emotional_safety',
                        ),
                      };
```
with
```dart
                      // The four shared dimensions (Spec 1a). Emotional
                      // safety is self-facing: see YourWeekCard below.
                      final dimensions = <String, int>{
                        for (final d in sharedPulseDimensions)
                          d.label: pulse.scoreFor(d.key),
                      };

                      final deltas = <String, int?>{
                        for (final d in sharedPulseDimensions)
                          d.label: pulse.getDeltaForDimension(d.key),
                      };
```

(e) After
```dart
                          const _RelationshipCenterPanel(),
                          Gap(Spacing.md.h),
```
insert
```dart
                          const YourWeekCard(),
                          Gap(Spacing.md.h),
```

(f) Replace the whole `_getDimensionKey` method with
```dart
  String _getDimensionKey(String label) =>
      pulseDimensionByLabel(label)?.key ?? '';
```

(g) Replace the whole `_showDimensionTooltip` method with
```dart
  void _showDimensionTooltip(String label, int score, String confidence) {
    final dimension = pulseDimensionByLabel(label);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(label),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Score: $score/100',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(dimension?.description ?? ''),
                if (dimension != null) ...[
                  const SizedBox(height: 8),
                  // F5 (3): the re-weighting is disclosed where the number is.
                  Text(sharedWeightLine(dimension)),
                ],
                if (confidence == 'low')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Limited data — this will improve with more logged moments and time as we learn from your conversations.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  emotionalSafetyPrivateNote,
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
```

`radar_chart.dart`: add `import 'package:attune/features/pulse/domain/pulse_dimensions.dart';`; replace the `descriptions` map and its use in `_showTooltip` so the content column reads
```dart
            Text('Score: $score/100', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(pulseDimensionByLabel(label)?.description ?? ''),
            if (pulseDimensionByLabel(label) case final d?) ...[
              const SizedBox(height: 8),
              Text(sharedWeightLine(d)),
            ],
```
(delete the local `descriptions` map); replace the whole `_getShortLabel` with
```dart
  String _getShortLabel(String label) =>
      pulseDimensionByLabel(label)?.shortLabel ?? label;
```
and replace `_RadarPainter`'s
```dart
  final List<String> _order = [
    'Communication',
    'Connection',
    'Conflict Health',
    'Alignment',
    'Emotional Safety',
  ];
```
with
```dart
  // Four axes since Spec 1a; the painter already draws any n-gon.
  final List<String> _order = [
    for (final d in sharedPulseDimensions) d.label,
  ];
```

`number_view.dart`: add the same import and replace the `dimOrder` literal with
```dart
    final dimOrder = [
      for (final d in sharedPulseDimensions)
        (d.label, dimensions[d.label] ?? 50),
    ];
```

`checkin_banner.dart`: replace the `content:` string with
```dart
          'A private weekly check-in, just for you. It takes about 60 seconds.',
```

`checkin_complete_screen.dart`: replace the `content:` string with
```dart
                  'Your weekly reflection has been saved. Only you can see your answers; they show in Your week on Pulse.',
```

- [ ] **Step 5: Update `pulse_screen_test.dart` and add the three screen tests**

Extend the `show` list of the providers import to
```dart
import 'package:attune/features/pulse/providers/pulse_providers.dart'
    show
        currentPulseScoreProvider,
        currentRelationshipIdProvider,
        currentRelationshipStatusProvider,
        pulseHistoryProvider,
        pulseRecomputeInvokerProvider,
        yourWeekProvider;
```
add imports
```dart
import 'package:attune/features/pulse/data/models/your_week.dart';
import 'package:attune/features/pulse/domain/pulse_dimensions.dart';
import 'package:attune/features/pulse/presentation/widgets/dimension_row.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
```
In `pumpWithPulse`, add to the overrides list:
```dart
        currentRelationshipStatusProvider.overrideWith(
          (ref) async => (id: 'r1', status: 'active'),
        ),
        yourWeekProvider.overrideWith((ref) async => const YourWeek()),
```
Append inside `main()`:
```dart
  testWidgets('paused hides everything: no score, no check-in, no refresh '
      '(F5 (5))', (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentPulseScoreProvider.overrideWith((ref) async => pulseScore(overall: 72)),
        pulseHistoryProvider.overrideWith((ref) async => const []),
        bothPartnersSharedProvider.overrideWith((ref) async => false),
        currentRelationshipIdProvider.overrideWith((ref) async => null),
        currentRelationshipStatusProvider.overrideWith(
          (ref) async => (id: 'r1', status: 'paused'),
        ),
        yourWeekProvider.overrideWith((ref) async => const YourWeek()),
        coupleNameProvider.overrideWith((ref, id) async => null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(buildHarness(container));
    await tester.pump();
    await tester.pump();

    expect(find.text('Pulse is paused'), findsOneWidget);
    expect(find.text('Score'), findsNothing);
    expect(find.text('72'), findsNothing);
    expect(find.text('Start check-in'), findsNothing);
    expect(find.text('Weekly check-in'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('four shared dimensions, never Emotional Safety', (tester) async {
    await pumpWithPulse(tester, pulse: pulseScore(overall: 72));
    for (final d in sharedPulseDimensions) {
      expect(
        find.widgetWithText(DimensionRow, d.label, skipOffstage: false),
        findsOneWidget,
        reason: d.label,
      );
    }
    expect(find.byType(DimensionRow, skipOffstage: false), findsNWidgets(4));
    expect(find.text('Emotional Safety', skipOffstage: false), findsNothing);
  });

  testWidgets('the dimension explainer discloses the weight and the private '
      'note (F5 (3))', (tester) async {
    useTallPhoneSurface(tester);
    await pumpWithPulse(tester, pulse: pulseScore(overall: 72));
    final row = find.widgetWithText(DimensionRow, 'Communication');
    await tester.dragUntilVisible(
      row,
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Counts for 27% of the shared score.'), findsOneWidget);
    expect(find.text(emotionalSafetyPrivateNote), findsOneWidget);
  });

  testWidgets('a second refresh reaches the server and shows the limit '
      '(Review Focus 8)', (tester) async {
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        currentPulseScoreProvider.overrideWith((ref) async => pulseScore(overall: 72)),
        pulseHistoryProvider.overrideWith((ref) async => const []),
        bothPartnersSharedProvider.overrideWith((ref) async => false),
        currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
        currentRelationshipStatusProvider.overrideWith(
          (ref) async => (id: 'r1', status: 'active'),
        ),
        yourWeekProvider.overrideWith((ref) async => const YourWeek()),
        coupleNameProvider.overrideWith((ref, id) async => null),
        pulseRecomputeInvokerProvider.overrideWithValue((
          relationshipId, {
          required force,
        }) async {
          calls++;
          expect(force, isTrue, reason: 'the refresh button forces');
          if (calls >= 2) {
            throw const FunctionException(
              status: 429,
              details: {'retry_after_seconds': 7200},
            );
          }
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(buildHarness(container));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(calls, 2, reason: 'a cached provider result must not swallow the tap');
    expect(find.text('You can refresh again in about 2 hours.'), findsOneWidget);
  });
```

- [ ] **Step 6: Run the Pulse suite, diff, format, analyze**

```bash
flutter test test/features/pulse
flutter test test/features/chat/chat_screen_header_test.dart
for f in pulse_score.dart pulse_repository.dart pulse_providers.dart pulse_screen.dart radar_chart.dart number_view.dart checkin_banner.dart checkin_complete_screen.dart pulse_screen_test.dart; do echo "== $f"; diff -u "$WS/snapshots/pulse-$f" "$(find lib/features/pulse test/features/pulse -name $f | head -1)" | head -80; done
dart format lib/features/pulse/domain lib/features/pulse/data/models/your_week.dart lib/features/pulse/presentation/widgets/your_week_card.dart lib/features/pulse/presentation/widgets/pulse_paused_state.dart test/features/pulse/pulse_dimensions_test.dart test/features/pulse/pulse_week_test.dart test/features/pulse/pulse_refresh_copy_test.dart test/features/pulse/your_week_card_test.dart
flutter analyze lib/features/pulse test/features/pulse 2>&1 | grep -E "^\s*(error|warning) "
```
Expected: every Pulse test passes (the existing ones still construct `PulseScore(... emotionalSafety: 70 ...)`, which stays valid for an `int?`); the chat header test (reads `overall_score` only) still passes; the analyzer grep prints nothing. The `pulse_repository.dart` and `pulse_providers.dart` diffs are whole-file rewrites by design; the others show only the listed edits.

- [ ] **Step 7: Ledger**

Append `Task 8: complete (pulse suite green; 4 new test files; 4 screen tests incl. double refresh). Regression risk: pulse_tab_test etc. render PulseScreen without the two new providers overridden — they resolve to AsyncError and the screen treats that as "not paused / no card", so they stay green (confirmed by running test/features/pulse).`

---

### Task 9: Documentation, evidence, full suite, owner hand-off

**Files:**
- Modify: `lib/app/documentations/user_manual/data/pulse_docs.dart` (section 1 subtitle/bullets, check-in section, FAQ)
- Modify: `lib/architecture/PULSE.md` (§4.1 note, §10 closure, new §11)
- Modify: the ledger `$WS/progress.md`

- [ ] **Step 1: User manual**

Snapshot `pulse_docs.dart`. Then:

(a) `subtitle: 'Five dimensions, one weekly picture',` → `subtitle: 'Four shared dimensions, one weekly picture',`. In `pulse_intro`, replace the `content:` string
```dart
              'Your Pulse Score is a weekly snapshot of your relationship, built from things that actually happened — moments you\'ve logged, check-ins you\'ve completed, and (over time) more sources as you use the app. It\'s recalculated every week, so it reflects where things stand now, not a permanent grade.',
```
with
```dart
              'Your Pulse Score is a weekly snapshot of your relationship, built from things that actually happened together — the moments you\'ve both logged, how your conversations are going, and the games you play. Your private weekly check-in never feeds it. It\'s recalculated every week, so it reflects where things stand now, not a permanent grade.',
```

(b) Replace the `pulse_dimensions` bullet block (`title: 'The five dimensions'` … `bulletPoints: [...]`) with
```dart
        ManualContent(
          id: 'pulse_dimensions',
          title: 'The four shared dimensions',
          content: '',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Communication (27% of the shared score)** — how clearly and kindly you express things and respond to each other.',
            '**Connection (27%)** — emotional closeness and active investment in the relationship.',
            '**Conflict Health (24%)** — not whether you disagree, but how well disagreements get handled.',
            '**Alignment (22%)** — whether you feel like you\'re moving in the same direction.',
          ],
        ),
        ManualContent(
          id: 'pulse_emotional_safety_private',
          title: 'Emotional safety is yours alone',
          numberPrefix: '3',
          content:
              'Emotional safety is not part of the shared score. Each of you gets your own, in Your week on the Pulse screen, built from your own check-in and the moments you both logged. Your partner never sees it, and you never see theirs.',
          type: ManualContentType.text,
        ),
```

(c) In the check-in section, replace `checkin_what`'s `content:` with
```dart
              'A short weekly check-in that only you can see. Your answers never feed the shared score or move it, so nothing you say can be worked out from a number your partner sees. They show in Your week, with your private Emotional safety.',
```
and `checkin_optional`'s `content:` with
```dart
              'The check-in is entirely optional. Skipping it changes nothing on the shared score and is not shown to your partner.',
```

(d) Replace `faq_pulse_when_computed`'s `answer:` with
```dart
            'It recalculates weekly. You can also tap refresh to recompute on demand, once every 24 hours for your relationship — if either of you has refreshed recently, the app tells you when it can run again.',
```

Run: `flutter analyze lib/app/documentations/user_manual/data/pulse_docs.dart 2>&1 | grep -E "^\s*(error|warning) "` → nothing; `flutter test test/app 2>/dev/null || true` (if a manual test exists, it must stay green). Diff against the snapshot.

- [ ] **Step 2: PULSE.md**

Snapshot `lib/architecture/PULSE.md`. Then:

(a) Directly under the heading `### 4.1 The five dimensions`, insert:
```
> **Amended 2026-10-17 (Spec 1a; see §11):** the SHARED score has four
> dimensions — Communication, Connection, Conflict Health, Alignment — with
> the weights below normalised to 27 % / 27 % / 24 % / 22 % (22/82, 22/82,
> 20/82, 18/82). Emotional safety is computed per partner and shown only to
> its author (`pulse_private_scores`). Weekly check-in answers feed no shared
> dimension, delta or confidence. "Weekly check-in response" in the data
> sources below is therefore historical for the four shared dimensions.
```

(b) In §10, replace the block from `[OPEN] Check-in — both partners required?` through `  Confirm before Step 18.` with:
```
[CLOSED 2026-10-17 — NO] Check-in — both partners required?
  Decision: no completion indicator of any kind. "You ✓  Jordan ✗" is a
  partner-facing status about the other person (ATTUNE_MASTER_SPEC §11
  constraint 10), and the confidence model no longer counts check-ins
  for the same reason. Beyond that, no shared dimension reads a check-in
  at all (see §11), so "both partners required" has no shared number
  left to gate.
```

(c) Append at the end of the file (after the closing italics):
```

---

## 11. RULINGS — 2026-10-17 (Spec 1a, privacy defaults)

Source: `docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md`
§3 F5 and `.superpowers/sdd/spec1-map-f5.md` §3. Plan:
`docs/superpowers/plans/2026-10-17-spec1a-privacy-defaults.md`.

1. **Private check-in answers never feed any shared dimension, delta or
   confidence.** The roadmap's "recompute only when both have checked in"
   is insufficient: with both rows, `avg*10` is a multiple of 5, the
   rounding is lossless, and a partner recovers the other's answer as
   `2·avg − own`; confidence points that count check-ins publish who
   answered. The weekly check-in is private; it appears only in "Your
   week" on the Pulse screen.
2. **Emotional safety is self-facing.** Computed per member in
   `compute-pulse` (shared mood base blended with the member's own
   rating, then the chat safety penalties) into `pulse_private_scores`
   under `auth.uid()`-only RLS. `pulse_scores.emotional_safety` is
   nullable and written as NULL. `generate-verdict` no longer reads it.
3. **Shared overall = (comm·22 + conn·22 + conflict·20 + align·18) / 82**,
   disclosed as 27 % / 27 % / 24 % / 22 % in the dimension explainer and
   the user manual. Radar is a four-axis polygon.
4. **compute-pulse requires the caller to be a member of an active
   relationship, or the service role.** A user request without
   `relationship_id` is 400; non-member, paused, ended and missing all
   answer 404 "Not found". `force_recompute: true` claims
   `claim_pulse_recompute(relationship, caller)` — one per 24 h **per
   member** (a per-couple key would let one partner's 429 reveal the
   other's refresh), atomic, server-side — else 429
   `{retry_after_seconds}`, and rewrites this week's shared row.
   `force_recompute: false` (sent by the check-in submit) never rewrites an
   existing shared row and never touches the claim; it runs only the
   private pass. Service-role runs (the cron) always rewrite the shared
   row. The former client-side timer is gone.
5. **Deltas compare against the previous week's row** (`week_ending <`
   current), never against the same week's earlier run.
6. **Week ending = the UTC Sunday on or after the UTC date**, identical in
   TypeScript (`getWeekEnding`) and Dart (`pulseWeekEnding`). A Sunday is
   its own week ending; the Sunday 00:07 UTC cron therefore scores the
   week that just ended.
7. **Pulse is hidden while `relationships.status = 'paused'`** (no score,
   no check-in, no refresh). The pause RPC itself ships with Spec 3.
8. **§6 "If BOTH partners have completed… recomputed immediately / both
   notified" and §9 Step 23 are withdrawn**; the client's
   `haveBothCompletedCheckin` (always false under RLS) and its recompute
   and notification paths are deleted. §9 Step 25 is a four-axis radar;
   Step 28 is four dimension rows.
9. **"Show when we've seen things" (Spec 1a Tasks 2–6), for the record
   here because Pulse's screen hosts Chat Settings:** one per-couple
   setting, effective only while the relationship is active and both
   members are on; either member's off is immediate and silent; a read
   or a story view made while off is never surfaced later; the
   recipient's read marker lives in `message_reads`, off the published
   `messages` table, so a read while off emits no realtime event.
   Outside the toggle, by ruling R-A: view-once media (`viewed_at`,
   `streak_views_remaining`) stays sender-visible — it is the mechanic of
   a format the sender chose, not an ambient receipt. By ruling R-B the
   RPC returns the caller's own vote and the effective state only; the
   inference "mine on, not effective ⇒ partner off" is inherent to a
   both-required rule and nothing about the partner's row, timing or an
   event is ever returned.
```

Diff against the snapshot: only these three regions.

- [ ] **Step 3: Run everything**

```bash
flutter test > "$WS/full.txt" 2>&1; tail -3 "$WS/full.txt"
flutter analyze lib/features/chat lib/features/pulse lib/features/stories lib/features/onboarding lib/app/documentations test/features/chat test/features/pulse test/features/stories test/features/onboarding 2>&1 | grep -E "^\s*(error|warning) "
deno test --allow-read --allow-env --allow-net supabase/functions/compute-pulse 2>&1 | tail -2
deno test --allow-read --allow-env --allow-net supabase/functions/generate-verdict 2>&1 | tail -2
ATTUNE_TEST_DB=attune_spec1a scripts/local_pg_setup.sh > "$WS/final-sql.txt" 2>&1; grep -cE "^\s+PASS" "$WS/final-sql.txt"; grep -E "^\s+FAIL|FAILED:" "$WS/final-sql.txt"
```
Expected: `All tests passed!` with the baseline count plus this plan's new tests (record both numbers); the analyzer grep prints nothing (the repo has pre-existing warnings outside these folders — do not fix them); Deno green; SQL: baseline PASS count + 5 new files, no FAIL, no migration FAILED.

- [ ] **Step 4: Privacy greps (checklist 4.4)**

```bash
grep -nE "console\.(log|error)\(" supabase/functions/compute-pulse/index.ts | grep -vE "error\.name|\.code \?\? 'error'|typeof error"
grep -rnE "print\(|debugPrint\(|log\(" lib/features/pulse lib/features/chat/data/seen_receipts_repository.dart lib/features/chat/domain/services/unread_count.dart
grep -rn "read_at" lib/ --include=*.dart | grep -v "read_receipt_at"
```
Expected: all three print nothing. (The third proves no Dart code selects the private marker any more.)

- [ ] **Step 5: Write the checklist v3.1 evidence map into the ledger**

| Item | Evidence |
|---|---|
| 1.4 Authorization at every access | `callerMayRecompute` + membership queries in every new RPC (`seen_receipts_member`, `count_unread_messages`, list RPC predicates); contracts: outsider blocks in Tasks 2, 3, 4; Deno `callerMayRecompute` cases |
| 1.5 Authentication verified | compute-pulse `auth.getUser(token)` / service key equality; `privacy.test.ts` handler guard |
| 1.6 Concurrency | `claim_pulse_recompute` single `INSERT … ON CONFLICT DO UPDATE … WHERE`; contract block 4; `mark_story_viewed` row lock kept |
| 1.11 Privacy impact | Column grants on `messages`/`story_items` (contracts Task 3 §1, Task 4 §1); `pulse_private_scores` RLS (Task 7 §2); SOUL §8 analysis columns revoked |
| 2.1 Input validation | `set_seen_receipts` NULL → `invalid_input`; compute-pulse `relationship_id` type check (400) |
| 2.4 No oracle | compute-pulse 404 for missing/paused/not-mine; `seen_receipts:not_found` for outsider and ended alike |
| 2.18 Idempotency | `seen_receipts_backfill_defaults` second call = 0; `mark_conversation_read` replay block; `mark_story_viewed` ON CONFLICT |
| 3.8 Rate limiting | 429 path; contract block 4 (granted/refused/retry window); `pulse_refresh_copy_test` |
| 4.4 No sensitive logs | Step 4 greps; compute-pulse logs only `error.name` / `code` |
| 6.x Tests first | Every task's Step 1/2 shows the red run; mutants recorded per task |
| 8.1 Flags/rollout | **No feature flag.** The rollout is migration-gated: the deploy moment is the cutoff (`seen_receipts_backfill_defaults` DEFAULT now(); `seen_receipts_contracts` block 2 with an explicit cutoff). There is no kill switch short of another migration; stated honestly rather than claimed. |

- [ ] **Step 6: Owner hand-off (write into the ledger and tell the owner)**

The owner must run, in order:
1. `supabase db push` — applies nine migrations: `20261017110000`, `120000`, `120100`, `130000`, `130100`, `140000`, `140100`, `150000`, `150100`. **Run it at a quiet time.** The `20261017120000` migration backfills default-ON rows for every couple that is active or paused at that moment (the push time is the cutoff; anyone who links afterwards starts off). The `20261017130000` migration copies existing read ticks (`read_at → read_receipt_at`) for those couples in 2 000-row slices of the published `messages` table; if it prints `read receipts: N rows to backfill`, run `select public.backfill_read_receipts(2000);` repeatedly until it returns 0, pausing a few seconds between calls (each call is one burst of WAL and realtime events).
2. `supabase functions deploy compute-pulse` and `supabase functions deploy generate-verdict`.
3. Remote checks (record in the ledger):
   - Realtime: with a test couple whose setting is off, read a message as the partner while the sender's device has the chat open (a temporary debug log in `supabase_chat_repository.dart`'s postgres_changes callback): the sender must receive **no `messages` UPDATE event at all** (the private marker is in `message_reads`, which is not published). Then turn the setting on for both, read a new message: exactly one UPDATE event, whose record carries `read_receipt_at` and no `read_at` (walrus applies column privileges). Also confirm `message_reads` is not in Database → Publications.
   - Dashboard → Database → Publications: `story_items` must not be in `supabase_realtime` (it is not in the repo's migration; confirm it was not added by hand).
   - `select jobname, active from cron.job where jobname = 'compute-pulse-weekly';` — the repo unscheduled it in `20260931150000_pause_ai_jobs.sql:23`; note the prod state. If/when it is re-enabled, the next Sunday 00:07 UTC run computes the week that just ended (ruling 6) and **always** rewrites that week's shared row even if a forced refresh created it earlier (ruling 4). Until then, shared rows change only on a forced refresh; private "Your week" scores refresh on every check-in submit regardless.
   - From the app: tap Pulse refresh twice; the second shows "You can refresh again in about 24 hours."; Chat Settings shows the new toggle; a fresh test couple's Ask 1 shows the receipts line; Pulse on a manually paused relationship (`update relationships set status='paused'` on the test couple, as the owner) shows "Pulse is paused".
4. Plan 1b (quiet hours, streak deletion, Mirror flag, device titles, push copy) is next and separate.

- [ ] **Step 7: Final review**

Generate the review package (diffs of every snapshot against its file, plus the new files) and dispatch the final Fable review with: this plan, the research spec rows F4/F5, this plan's Review Focus verbatim, and the ledger's `Ruling:` lines. Do one fix pass; each fix is proved by a test that failed first. Append `Task 9: complete` with the final numbers.

---

## Self-review (done while writing)

**Spec coverage**

| Requirement | Task |
|---|---|
| Relationships lockdown; SQL proves no member can change status/user_a/user_b/ended_at…; RPC writes keep working | 1 |
| F4 (1) one setting covering chat `read_at` and story seen-state | 2, 3, 4 |
| F4 (2) either off disables for both, UI never shows who | 2 (block 3), 6 (subtitle test) |
| F4 (3) on requires both | 2 (block 4), 6 |
| F4 (4) default off for couples linked after ship cutoff; Ask 1 line | 2 (block 2, cutoff constant), 6 (`couples_joined_step_test`) |
| F4 (5) server-enforced; partner's client cannot read receipt data while off | 3 (`chat_system_contracts` sender block, `read_receipt_contracts` §1-2), 4 (story §1-2) |
| Analysis columns not client-readable | 3 (`read_receipt_contracts` §1-2) |
| Unread badge and read gate survive hiding `read_at` | 3 (`count_unread_messages`), 5 |
| Story timing bump | 4 (`mark_story_viewed`, §2 "bumped story_change_signals") + viewer local refresh |
| Dart tests: ticks / info screen / unread badge / toggle | 5 (model, controller, unread parser; info screen keeps its existing tests on `Message.readAt`), 6 |
| F5 ruling: check-ins never feed shared dims/deltas/confidence | 7 (`privacy.test.ts`, confidence points) |
| Emotional safety self-only; nullable column; new table; generate-verdict | 7 |
| Re-weighting across four dims, disclosed in tooltip and manual | 7 (`overallFromShared`), 8 (tooltip test), 9 (manual) |
| Radar/number/ring handle four | 8 |
| compute-pulse caller auth + 24 h server limit | 7 |
| Deltas vs previous week | 7 (`privacy.test.ts`) |
| Sunday week ending, server and client, tested on a Sunday | 7, 8 |
| Confidence no longer counts check-ins | 7 (points) ; SPEC §11.10 |
| Pulse hidden while paused (explicit, tested) | 8 |
| PULSE.md §10 closed as no; ruling recorded | 9 |
| Dead `haveBothCompletedCheckin` path removed | 8 |
| Migrations after latest; grants replayed; no commits; snapshots; analyzer gate; deno command; checklist evidence; owner deploy list | Global constraints, 0, 9 |

**Type consistency**
- `seen_receipts_effective(uuid)` is the name used in Tasks 2, 3, 4 (migrations, contracts, mutants).
- `read_receipt_at` is the column name in Task 3 SQL, the allowlist, Task 5 `_messageColumns`, `Message.fromRow` and the harness.
- `count_unread_messages(uuid)` returns `integer`; Dart parses with `parseUnreadCount`.
- `SeenReceipts(mine:, effective:)`, `seenReceiptsRepositoryProvider`, `seenReceiptsProvider`, `seenReceiptsSubtitle`, `seenReceiptsTitle`, `seenReceiptsAsk1Line`, `seenReceiptsFailureCopy` are spelled the same in Task 6's three files and tests.
- `sharedPulseDimensions`, `pulseDimensionByLabel`, `sharedWeightLine`, `emotionalSafetyPrivateNote` are used identically in screen, radar, number view and tests; `PulseScore.scoreFor(String)`; `currentRelationshipStatusProvider` returns `({String id, String status})?`; `yourWeekProvider` returns `YourWeek`.
- TS: `getWeekEnding`, `weekEndingKey`, `SHARED_WEIGHTS`, `overallFromShared`, `callerMayRecompute`, `privateEmotionalSafety`, `rollupConfidence` exported from `index.ts` and imported by `index.test.ts`; `privacy.test.ts` reads source text only.

**Placeholders**
- None: every migration, contract, Dart file, Deno file and test carries its full text; every step has a command and an expected result.

**Recorded design decisions (for the reviewer)**
- The setting's RPC returns `mine` + `effective`, not `effective` alone (ruling R-B at the top): the inference "my on + effective off ⇒ partner off" is inherent to a both-required rule, and the alternative (a toggle that flips back) reads as broken. Nothing about the partner's row or timing is returned.
- View-once media (`viewed_at`, `streak_views_remaining`) stays outside the toggle (ruling R-A at the top).
- The recipient's read marker lives in `message_reads`, not on `messages`, because `messages` is published and a column privilege hides a payload but not the UPDATE event (C1).
- The forced-refresh claim is keyed per (relationship, member) so a 429 never tells one partner the other refreshed (M2).
- A read or a view made while the setting is off is never surfaced later (`read_receipt_at` not written; `seen_shown` not set); receipts made while on stay visible after a switch-off (history is not rewritten, so a switch-off does not announce itself through disappearing ticks).
- The chat import worker still writes `read_at = created_at` only; imported rows show "Delivered". The import flag is off (Q16).
- `rollupConfidence` is fraction-based so the existing five-element tests and the new four-element reality agree.
- `applyChatSignals` keeps `emotionalSafety` in its shape; the shared path passes 0 and ignores it, the private path reuses the penalties.
- `MASTER_SPEC` §8/§11 weight table is not edited (owner's uncommitted file); PULSE.md §11 carries the ruling.

## Plan review (Fable, 2026-10-17) — all applied

**Critical**
- **C1 (realtime UPDATE event).** The recipient's read marker moved off the published `messages` table into `message_reads` (no client grant, not published). `mark_conversation_read` now writes `messages` only while receipts are on (`read_receipt_at` + `delivered_at`, a read tick implies delivery); while off it touches only `message_reads`, so no UPDATE event streams. `count_unread_messages` anti-joins `message_reads` and treats the import worker's legacy `read_at` as read. New contracts: `xmin` + row-hash fingerprint of every `messages` row before/after a read while off (both `read_receipt_contracts.sql` §3 and the `chat_system_contracts.sql` sender block), `message_reads` unreachable by clients and absent from `pg_publication_tables`, and "a read while off is not a delivery either" (the `delivered_at = COALESCE(…)` first-touch tick is gone from the off path; delivery comes only from the device's delivery RPCs). Review Focus 6 added.

**Important**
- **I1 (cached recompute provider).** `recomputePulseProvider` is `autoDispose` and `_refreshPulse` invalidates it before every read; the edge-function call moved behind `pulseRecomputeInvokerProvider` so a widget test can fake it. New screen test "a second refresh reaches the server and shows the limit": the fake returns 429 on the second call and the snackbar reads "You can refresh again in about 2 hours." Review Focus 8 added.
- **I2 (vacuous mutants).** Every `seen_receipts_effective` mutant now uses the real parameter name `p_relationship_id`; `mutant.sh` prints `MUTANT KILLED` only when the output contains `CONTRACT VIOLATED`/`EXPLOIT` and exits 1 otherwise. Every Expected line updated.
- **I3 (paused couple).** `seen_receipts_member` accepts `status IN ('active','paused')` so a paused member can still withdraw; `seen_receipts_effective` requires `status = 'active'` (and unarchived), so nothing flows while paused. New `seen_receipts_contracts.sql` block 6 (paused: effective false with both on; set off/on works; resumes on unpause). Review Focus 7 added.
- **I4 (cron after a forced week).** `shouldComputeShared(isService, force, exists)` — service-role runs always rewrite the shared row; unit-tested in `index.test.ts`; PULSE.md ruling 4 and the hand-off note that the cron is unscheduled (`20260931150000_pause_ai_jobs.sql:23`). Review Focus 9 added.
- **I5 (private pass starvation).** `_computePulseScore` fetches the shared inputs first and runs `_computePrivateScores` on the "shared row exists" early return too; the check-in submit calls the invoker with `force: false` (private pass only, no claim); `fetchYourWeek` filters `pulse_private_scores` by the current `week_ending`. `privacy.test.ts` asserts the private pass is called on both paths.
- **I6 (cutoff constant).** `seen_receipts_backfill_defaults(p_cutoff timestamptz DEFAULT now())`: the push moment is the cutoff. Contracts pass an explicit cutoff. Constants table, migration comments, ledger line and hand-off updated; no date to keep in step with a release.

**Minor**
- **M1.** Reel test asserts `ringSummaryCalls == 1` right after `pumpWidget` (before any render pump) and `>= 2` after the view and three more pumps.
- **M2.** `pulse_recompute_limits` keyed `(relationship_id, user_id)`; `claim_pulse_recompute(p_relationship_id, p_user_id, p_min_interval)`; the handler passes `auth.user.id`; contract block 4 proves B's claim is untouched by A's; copy stays neutral.
- **M3.** Ruling R-A (view-once `viewed_at` / `streak_views_remaining` stay sender-visible, outside the toggle) added to the owner-confirmation box, Task 3's design note, PULSE.md §11 item 9 and the self-review.
- **M4.** `pulse_intro` copy no longer says the score uses check-ins.
- **M5.** The `read_at → read_receipt_at` copy is `backfill_read_receipts(p_batch)` in 2 000-row slices; the migration completes it only under 20 000 rows, otherwise prints the loop to run at a quiet time; hand-off says so.
- **M6.** Ruling R-B (`mine` + `effective`, the inherent inference, what is never returned) added to the owner-confirmation box, PULSE.md §11 item 9 and the self-review.
- **M7.** Checklist 8.1 now reads "No feature flag; migration-gated; no kill switch short of another migration".
- **M8.** Review Focus items 6–9 added (realtime UPDATE event, paused switch-off, cached recompute provider, cron after a forced week), each pinned to its test.

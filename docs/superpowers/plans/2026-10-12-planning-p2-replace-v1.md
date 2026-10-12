# Planning P2 — Replace v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline) — the user chose inline execution for P1 and asked for P2 to start immediately. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the new Planning the only Planning: drop every v1 table, RPC and screen, remove the preview flag and the "v2" naming, and move Ask Attune, the calendar and the Conversations card onto the new model.

**Architecture:** One additive-then-destructive migration (`20261012200700_planning_replace_v1.sql`) rewrites the three v1 RPCs that other features call onto v2 tables and then drops v1. Flutter deletes `lib/features/planning/{data,presentation}`, moves `lib/features/planning/v2/*` up one level, renames `PlanningV2*` identifiers, and repoints the router, timeline, Conversations card and Ask Attune.

**Spec:** `docs/superpowers/specs/2026-10-12-planning-v2-design.md` §16 (supersedes §9).

## Global Constraints

- Branch `feat/planning-replace-v1`, worktree `.worktrees/planning-replace`. SQL runs use `ATTUNE_TEST_DB=attune_planning`, passed inline on every command. Never touch `attune_test`.
- Do not edit any existing migration. All SQL changes go into `20261012200700_planning_replace_v1.sql`.
- Keep `planning_change_signals` and `bump_planning_signal` (v2 uses them). Drop only v1 objects.
- Every rewritten RPC is SECURITY DEFINER, sets `search_path = public`, checks membership through `planning_v2_actor` (or an equivalent explicit membership check), and is granted to `authenticated` only.
- The UI keeps using the app design system (lib/core/widgets, AppColors), as P1 did.
- TDD: each task's test is written and seen failing before its code.

## Review Focus

1. **The Ask Attune double tap.** "Add to Planning" pressed twice on the same message must create one plan, not two (the link row is the idempotency key).
2. **Calendar windows.** A trip whose date range crosses the window edges shows only on the days inside the window, and never outside the 42-day bound.
3. **Deleted things stay off the feeds.** An item in a deleted block or plan must never appear in the calendar or the summary (P1 review M9).
4. **No leftover v1.** After the change, nothing references the v1 tables, the v1 RPCs or the v1 Dart files: grep is clean and the full SQL harness rebuilds.
5. **The Calendar tab survives.** The Planning screen still has its Calendar tab.

---

### Task 1: SQL — rewrite dependents onto v2, drop v1

**Files:**
- Create `supabase/migrations/20261012200700_planning_replace_v1.sql`
- Create `supabase/tests/planning_feeds_contracts.sql`
- Rewrite `supabase/tests/ai_assist_planning_conversion_contracts.sql`
- Update `supabase/tests/ai_assistant_schema_contracts.sql` and `supabase/tests/message_edit_delete_contracts.sql` (their v1 fixtures)
- Delete `supabase/tests/planning_{schema,item,event_note,read}_contracts.sql`
- Modify `scripts/local_pg_grants.sql`: remove the `\i …20260941030000_planning_table_grants.sql` line (those tables no longer exist)

**Produces:**
- `create_planning_from_assist_message(uuid, text, date) RETURNS TABLE (planning_entry_id uuid)`
- `list_planning_calendar_entries(uuid, date, date) RETURNS TABLE (entry_kind text, entry_id uuid, item_id uuid, entry_date date, title text, is_complete boolean)`
- `get_planning_summary(uuid, date) RETURNS TABLE (kind text, entry_id uuid, title text, context_date date)`
- `ai_assist_planning_links(message_id, relationship_id, planning_entry_id NOT NULL, created_by, created_at)`

**Contracts (write first, watch them fail):**
- **AI task:** creates an Everyday plan with one checklist item due on the date. **AI event:** creates an Everyday plan with a Date block.
- **AI idempotency:** a second call returns the same `planning_entry_id` and creates nothing. Non-members and non-Attune messages are refused.
- **Calendar:** the date range is clipped to the window. Items are on their due date. Templates and deleted items, blocks and plans are excluded. A range over 42 days is refused. Strangers get `not_found`.
- **Summary order:** overdue item, then upcoming, then most recent plan, then no row. Ticked and deleted items are ignored.
- **No v1 left:** the v1 tables and RPCs no longer exist, the links table has its FK to `planning_entries`, and grants are correct.

### Task 2: Flutter — delete v1, promote v2, drop the "v2" naming

**Move first:** `PlanningRpcGateway` / `SupabasePlanningRpcGateway`, `planningChangeSignalProvider` and `currentRelationshipIdProvider` move out of the v1 files into the new data/presentation files.

**Then:**
- Delete the v1 `lib/features/planning/{data,presentation}` and its tests.
- `git mv lib/features/planning/v2/* lib/features/planning/`, and the same for `test/features/planning/v2/*`.
- Rename mechanically: `PlanningV2` → `Planning`, `planningV2` → `planning`, and `planning_v2_` → `planning_` in Dart file names and imports.

**Test:** the full planning suite passes under the new names, analyze is clean, and `grep -rn "PlanningV2\|planning/v2\|PLANNING_V2_PREVIEW" lib test` is empty.

### Task 3: Router and Planning home tabs

- `/planning` opens `PlanningHomeScreen` (the former v2 home). It gains the Planning / Calendar tabs (`TabsWithContent`, with `TimelineScreen(showAppBar: true, showOwnAppBar: false)`), as v1 had.
- The preview button and define are gone.

**Test:** the route builds the new home; both tabs are present; the Calendar tab shows `TimelineScreen`.

### Task 4: Calendar on the new model

- New `PlanningCalendarEntry` model and `planningCalendarEntriesProvider(range)` in planning data/providers.
- `timeline_screen.dart`, `calendar_day_sheet.dart` and `planning_day_section.dart` use them.
- Tapping a row opens `PlanningEntryScreen(relationshipId, entryId)`.

**Tests:** rows render per day; a ticked item shows as complete; a tap opens the plan (rewrites `test/features/timeline/planning_calendar_integration_test.dart`).

### Task 5: Conversations summary card on the new model

- New `PlanningSummary` model and provider. `_PlanningSummaryRow` shows overdue, upcoming or recent, or "Start planning together", and opens Planning.

**Test:** rewrites `test/features/chat/planning_entry_row_wiring_test.dart` for the new shapes.

### Task 6: Ask Attune "Add to Planning" on the new model

- `AddToPlanningResult(entryId)`.
- The repository reads `planning_entry_id` from the RPC result and from the link select.
- The bubble's "Added" state opens `PlanningEntryScreen` for that plan.

**Tests:** update `ai_assistant_repository_test.dart` and `attune_assist_bubble_test.dart`.

### Task 7: Verify and review

- Run `flutter analyze`, the full `flutter test`, the full SQL harness, and concurrency ×3.
- Grep for v1 leftovers (Review Focus 4).
- Get a fresh whole-branch review, fix Critical and Important findings test-first, then merge.

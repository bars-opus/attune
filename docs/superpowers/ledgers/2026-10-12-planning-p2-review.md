# Planning P2 (replace v1) — final review (7a5f6e66..501b8d1a)

Status: COMPLETE

## Baseline checks run
- SQL contracts on attune_planning: planning_feeds_contracts PASS, ai_assist_planning_conversion_contracts PASS, message_edit_delete_contracts PASS, ai_assistant_schema_contracts PASS.
- Live catalog sweep (attune_planning): no function body, view, policy, trigger or publication references a dropped v1 table/column/function (only delete_message, in a comment). Realtime publication holds only planning_change_signals. Cron: planning_v2_purge only.
- Migration replay (BEGIN..ROLLBACK, attune_planning): rewound to the exact pre-P2 shape (v1 migrations 20260941010000..060000 + 20260950090000 replayed, links table back on planning_item_id/planning_event_id with its CHECK and composite FKs), created REAL v1 data incl. two link rows (task + event) and a note via the v1 RPCs, then ran 20261012200700 + 200710 verbatim. Result: applies cleanly; links 2 -> 0; columns = message_id,relationship_id,created_by,created_at,planning_entry_id; v1 tables/functions gone; re-converting a pre-migration message creates a v2 plan and is idempotent (same id twice); delete_message on a pre-migration Assist message still works.
- generate_series over date bounds resolves to timestamptz; checked across the US DST change (America/New_York, Oct 31 -> Nov 3): one row per calendar day, no duplicates/gaps.

## Working notes (findings as found)
- flutter analyze lib test: 0 errors; no new warnings in touched files.
- flutter test test/features/{planning,ai_assistant,timeline,chat}: 1288 passed.
- Scratch widget tests (outside the checkout, against the real PlanningHomeScreen + fakes): horizontal fling on a category row switches to Calendar with no move call; long-press + vertical drag calls move_planning_category(c0 after c3) and stays on the Planning tab; pull-down refetches get_planning_home (1 -> 2 calls). No gesture conflict between TabBarView swipe, ReorderableDelayedDragStartListener and RefreshIndicator.
- Stale-link repro (BEGIN..ROLLBACK): convert -> delete_planning_entry -> convert again returns the SAME deleted id (t); get_planning_entry on it raises planning:not_found; plan currency = USD.

## Strengths
- Migration is small, ordered correctly (links columns dropped before the tables their FKs point at; DROP without CASCADE so any unknown dependent fails the migration instead of being silently dropped) and applies cleanly on a DB with real v1 data and link rows (replayed).
- create_planning_from_assist_message keeps v1's proven concurrency shape: messages row FOR UPDATE before the link check, plus message_id PRIMARY KEY as a backstop, and builds the plan through the public Planning RPCs so membership/title/limit rules are not re-implemented.
- Feeds: SECURITY DEFINER + planning_v2_actor (not_found for strangers, inactive for ended couples), every block/item join re-checks the plan and block are live (M9), templates excluded, 42-day bound kept, anon revoked. Contract file covers window edges, deleted block/plan, stranger, ordering.
- Rename is mechanical (word-diff of category/entry screens vs the v2 originals shows identifier changes only); copied planningChangeSignalProvider / currentRelationshipIdProvider are line-for-line v1 apart from reading Supabase.instance.client instead of a private provider. Outbox SharedPreferences key deliberately kept, so queued ticks survive the rename.
- Chat changes are additive only (see Chat impact).

## Issues
### Critical
None.

### Important
None.

### Minor
1. Link to a deleted plan is a dead end. supabase/migrations/20261012200700_planning_replace_v1.sql:59-64 returns the existing link without checking the plan is live; lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart:237-240 opens it. Scenario: Add to Planning -> delete that plan -> tap "Added to Planning" -> entry screen shows "That was removed by your partner." (even if you deleted it) and the message cannot be re-added until the 30-day purge cascades the link. Reproduced (stale_link repro above). Fix: in the RPC, if the linked entry is soft-deleted, delete the link and fall through to create (or restore); or have the chip fall back to "Add" when the plan is gone.
2. Assist-created plans are always USD (20261012200700:79,83) while the category screen uses the device currency (planning_category_screen.dart _deviceCurrency); update_planning_entry cannot change currency. Invisible in P1 (no money blocks); will show once expenses/budget land. Reproduced (currency = USD).
3. Lock-order deviation, unverified: the RPC calls planning_v2_ensure_starters (advisory lock + FOR UPDATE on all six starter template entries) before create_planning_entry takes the Everyday category FOR SHARE, i.e. entry -> category, against the declared category -> entry order. The only cycle partner found is pin_planning_entry(<Everyday template id>) (category FOR UPDATE -> template FOR UPDATE, then rejects); the UI never pins templates, and Postgres would abort one side with a deadlock error. Cheaper and order-safe: look up the Everyday category first and call ensure_starters only when it is missing. Not reproduced (needs two committed sessions; the rules allow only rolled-back experiments).
4. get_planning_summary's "recent" branch (20261012200700:186-190) has no e.status = 'active' filter while overdue/upcoming do, so a done/archived plan can be the card's line. Spec §16 does not say either way; flagging the inconsistency.
5. Stale docs/comments: lib/architecture/PLANNING.md still documents v1 end to end (tables, RPCs, screens); lib/features/ai_assistant/presentation/screens/ai_session_sheet.dart:227 cites the deleted create_planning_goal_screen.dart.
6. Ops (before `supabase db push`, irreversible): take a pg_dump of planning_items/planning_events/planning_event_tasks/planning_notes/ai_assist_planning_links from the real project and run a dependency check (pg_depend / function bodies mentioning the v1 names) there; the repo-side sweep is clean but cannot see dashboard-made objects. Costs a minute and makes "irreversible" recoverable.
7. Race on create_planning_from_assist_message not executed end-to-end (needs committed rows in two sessions). By construction it is safe: both callers serialize on the messages row lock; under READ COMMITTED the second's link SELECT is a new statement and sees the first's committed link; the message_id PK rejects any second insert. Contract 5 covers the sequential double tap; the bubble also disables the button while in flight.

## Chat impact
- attune_assist_bubble.dart: YES, additive. "Added to Planning" becomes tappable and opens the plan; the Add button, its in-flight disable and error behaviour are unchanged.
- ai_assistant_repository.dart: YES, Add-to-Planning path only. AddToPlanningResult is now {entryId}; the link SELECT reads planning_entry_id. No other chat or Assist call changed.
- ai_assistant_providers.dart, assistant_error.dart: NO behaviour change (doc comments only).
- conversations_screen.dart: YES, Planning summary row only. New text ("X was due Nov 8", "X · Nov 14", plan title, or "Start planning together"); tap target unchanged (/planning).
- delete_message (20260950110000): NO change, works with the new links table (contract passes; replay deleted a pre-migration Assist message fine). It deletes only the link row, never the plan. Deleting or purging a plan cascades only the link row (FK from links), never a message. Converting holds the message row FOR UPDATE for the length of the call, same as v1.
- Messages, send/edit/reactions, Realtime chat channels, edge functions: NOT touched (ai-assist proposal schema unchanged).
- Outside chat: the Timeline day sheet and day section rows now open their plan (additive).

## Declined to judge
- Full SQL harness rebuild (scripts/local_pg_setup.sh and attune_test are off-limits); I relied on the ledger's 292-migration run plus my replay on attune_planning.
- Whether the real project's migration runner wraps each file in a transaction, and drift between the real project and this migration history.
- On-device visuals of the Calendar tab and chip (no device run).

## Verdict
Ready to merge: yes (with fixes optional). No Critical or Important issues, the migration replays cleanly on real v1 data, and chat changes are limited to the Planning card and the Add-to-Planning chip. Minor 1 and the ops backup (6) are worth doing before the production push.

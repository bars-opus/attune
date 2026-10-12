# Final whole-branch review: Planning v2 P1 Foundation (c7a41343..450bfbeb)

Reviewer method: read the spec, the plan's constraints and rulings, the ledger, all 8 migrations, and every v2 Dart file. Every experiment ran in rolled-back transactions on attune_planning, or in a scratch copy under the scratchpad (symlinked lib plus copied v2 test support). The working tree is unchanged. Re-ran: all 6 v2 SQL contract files PASS; `flutter test test/features/planning/v2` 88/88 PASS.

### Strengths
- **Authorization is uniform and fails closed.** Each RPC resolves the row, then calls `planning_v2_actor`, then takes its locks. A non-member gets `not_found` before any lock is taken, so locking leaks nothing. `inactive` is reserved for actual members. Verified against the live catalog: no v2 table has any grant to anon or authenticated; no v2 function is executable by anon; no internal helper is executable by authenticated; every SECURITY DEFINER function pins search_path.
- **Review Focus 1 (first-open race) holds.** An advisory lock serializes seeding, and `UNIQUE(relationship_id, seed_key)` backs it up. The concurrency script asserts that both sessions succeed, not just that the end count is right.
- **Review Focus 2 (save after a partner's delete) holds.** Within one entry, every block and item write locks the entry first, then the block, then the item, which also makes the limit counts exact. Saving a deleted block returns `not_found` and never resurrects it. The editor maps that result to `TextGone`, which pops the editor, drops the block and shows a snackbar.
- **Review Focus 3 holds as specified.** `planning_applied_ops` dedupes replays by op id, and the outbox reuses the op id across retries.
- **Explicit locks where the FK alone would be too weak.** `create_planning_entry` and `duplicate_planning_entry` take FOR SHARE on top of the FK's KEY SHARE, with a comment explaining why. That is exactly the right reflex.
- **Review Focus 4 holds.** The sanitizer mirrors the server whitelist, runs before every save and every render, and tells the user when it removed something. The toolbar hides every control that could produce a non-whitelisted attribute (the header dropdown defaults to H1–H3 only).
- **The ledger is honest.** It reports line coverage rather than claiming branch coverage, records the shared ConfirmationDialog bug without fixing a core widget, and explains why each design-system swap was made.
- **The v1 touch is minimal and compile-time gated.** An empty `actions` list renders identically to null.

### Issues

#### Critical (Must Fix)
None found.

#### Important (Should Fix)

**I1. `delete_planning_category` takes row locks bottom-up (items, then blocks, then entries), and `duplicate_planning_entry` locks the entry before the category. Both deadlock with ordinary edits. (VERIFIED)**
- Where:
  - `supabase/migrations/20261012200200_planning_v2_categories.sql:393-407` takes the category FOR UPDATE, then UPDATEs items, then blocks, then entries. It never locks the entries first.
  - Every block and item RPC locks the entry FOR UPDATE first (`20261012200400:32-43, 165-176`).
  - `duplicate_planning_entry` takes the entry FOR SHARE, then the category FOR SHARE (`20261012200300:106-109`). That is the reverse of the declared category → entry order.
  - The header comment in 20261012200400 claims "no cycles", which is not true.
- Scenario: one partner deletes a custom category while the other saves a text block, ticks an item, or taps "Start next one" on a plan in it. Postgres aborts one side with 40P01. The client maps that to `PlanningV2Network`, so the user sees "Could not reach Attune" (or the tick is queued). The window spans the whole category delete, which grows with the number of entries and items.
- Repro 1 (BEGIN/ROLLBACK, fixture rel 2f…):
  - Session B emulates lines 393-406 statement-for-statement on category 84004bcc… and sleeps 2s between the blocks UPDATE and the entries UPDATE.
  - Session A calls the real `update_planning_block('…b002', 2, …)`.
  - Result: `ERROR: deadlock detected … while locking tuple (0,14) in relation "planning_entries"`.
- Repro 2:
  - B locks the category and sleeps.
  - A calls the real `duplicate_planning_entry('…e001', gen_random_uuid(), 'Next run')`.
  - Result: `ERROR: deadlock detected … SQL statement "SELECT 1 FROM public.planning_categories … FOR SHARE" PL/pgSQL function duplicate_planning_entry line 15`.
- Fix:
  - In `delete_planning_category`, lock the category's entries FOR UPDATE (ORDER BY id) before touching blocks or items.
  - In `duplicate_planning_entry`, lock the category FOR SHARE before the source entry.
  - Add a concurrency case for each.

**I2. Ops sent directly to the server race older queued ops: a newer online action can be overwritten by an older offline one. The queue also replays only from an open entry, and dropped ops are never shown. (VERIFIED)**
- Where (`lib/features/planning/v2/presentation/planning_v2_providers.dart`):
  - `setChecked` and `addItem` (lines 203-249) call the RPC directly even when the queue holds older ops for the same item or block.
  - `_overlay` (lines 158-180) re-applies queued ops on every refetch.
  - `replay()` has a single caller (line 51), reached only through `planningV2EntryProvider`.
- Repro A (`scratchpad/proj/test/features/planning/v2/review_outbox_order_test.dart`, using the real controller, outbox and repository over a stateful fake gateway):
  1. Offline: tick Milk. The tick is queued.
  2. Back online: untick Milk. This goes straight to the server, which now has it unticked.
  3. Refetch: the overlay shows `checked=true`.
  4. Replay: `sent=1`; the server's `checked_at` becomes `2026-10-12T09:00:00Z`.
  - Outcome: the item ends up ticked although the user's last action was untick. `flutter test` → `Expected: null, Actual: '2026-10-12T09:00:00Z'`.
- Repro B (`review_outbox_add_then_tick_test.dart`):
  1. Offline: add "Bread". The add is queued.
  2. Back online: tick Bread before any replay. The tick reaches the server ahead of the add.
  - Outcome: `PlanningV2NotFound`, the tick reverts, and the user is told "That was removed by your partner."
- Also:
  - A tick queued in a shop syncs only when the user next opens some entry while online. That falls short of spec §14 acceptance criterion 5 ("sync after reconnect").
  - Spec §10 and checklist 4.14 ("Couldn't sync n items" with Retry; permanent drops shown) are not implemented. `OutboxReplayResult.dropped` only triggers `invalidateSelf()`, so a dropped tick silently reverts. The hero chip shows a global pending count with no Retry.
- Related: two rapid taps on the same checkbox are two independent requests with no per-item serialization, so responses can land out of order.
- Fix: when the queue is non-empty for the affected item, or for the block in the case of adds, enqueue the new op behind it instead of sending it directly (or collapse queued ops per item). Trigger replay at app or connectivity level, not only from the entry provider. Surface the dropped and remaining ops with a Retry.

**I3. Length limits disagree between client and server, and the payload byte cap makes the text limit byte-based. Review Focus 5 is not actually tested. (VERIFIED)**
- **Characters are counted differently.**
  - Flutter `maxLength` counts grapheme clusters (`flutter/lib/src/services/text_formatter.dart:439-470`).
  - It is set on the title (`planning_v2_entry_screen.dart:41`, `planning_v2_category_screen.dart:263`), the category name (`category_editor_sheet.dart:51`), the item (`checklist_block_view.dart:163,212`) and the section (`checklist_block_view.dart:216`).
  - The server counts code points (`char_length`).
- **Repro: name rejected while the counter says it fits** (BEGIN/ROLLBACK):
  - `create_planning_category(gen_random_uuid(), '2f…01', repeat('🇬🇭',21), 'flag','rose')` → `planning:invalid_input {"field":"name"}`.
  - The counter showed 21/40, and the message says "up to 40 characters".
  - The same applies to ZWJ and skin-tone emoji, Indic conjuncts and decomposed accents: exactly the cases Focus 5 names.
  - Because every sheet pops before its RPC, the typed text is also lost.
- **Repro: text limit is effectively a byte limit:**
  - An 8,200-character Cyrillic note passes the editor's `runes.length <= 10000` check, then fails `planning_v2_validate_block` with `planning:limit_reached {"limit":"payload_bytes"}` (payload 16,429 bytes).
  - The user sees the generic "That is over the limit. Make it shorter and try again."
  - Emoji text hits this at about 4,000 characters.
- **Test gap:**
  - helpers Contract 10's "combining" section is `repeat('é',40)` using precomposed U+00E9 (bytes `c3 a9`), so no combining mark is exercised.
  - Contract 9's 10,000-emoji pass calls `planning_validate_delta` directly, below the payload cap, so it proves a limit no RPC can reach.
- Fix:
  - Enforce code points on the client (a rune-counting `TextInputFormatter`, and a counter that shows code points), so client and server agree.
  - Check the UTF-8 byte size of the payload in the editor and give a specific message.
  - Keep sheets open until the RPC succeeds.
  - Add real combining-mark (e + U+0301) and multi-code-point emoji cases.

#### Minor (Nice to Have)
- **M1. Every home read takes write locks.** `get_planning_home` → `planning_v2_ensure_starters` (`20261012200200:223-245`) takes the per-couple advisory lock and FOR UPDATE on all 6 template rows on every call. Home reads serialize with each other and with template edits, and each read writes tuple locks. Check `seed_version < version` without a lock first and lock only when an upgrade is due.
- **M2. A seventh starter would break every home read (VERIFIED, latent).** `ensure_starters` hard-codes `planning_even_keys(6)` and indexes it by `rank`. With a rank-7 starter row, `get_planning_home` fails with `null value in column "sort_key" … violates not-null constraint`. That would hit every couple that does not yet have the new starter, the moment a later phase adds one (repro rolled back). Size the keys from `count(*)` of the starter table.
- **M3. Delete-then-Undo misbehaves when the delete fails.** `_deleteBlock` (`planning_v2_entry_screen.dart:72-81`) and `_delete` (`checklist_block_view.dart:51-60`) show "Removed … / Undo" even when the delete failed and was rolled back. Tapping Undo then reports "That was removed by your partner."
- **M4. Typed text is lost on server rejection.** The item editor, category editor and new-plan sheets pop before the RPC. The "Add item" field clears before its RPC.
- **M5. "Done & archived" never paginates.** `_ClosedEntries` shows only the first 30 entries, with no loadMore. A weekly Groceries category loses older runs from view after about 7 months.
- **M6. Category reorder snaps back.** Reorder is not optimistic, so the dragged tile returns to its old place until the refetch lands.
- **M7. The delete-category confirmation can show a stale count.** It uses `_category.entryCount` from the home list the category screen was opened with.
- **M8. Undo can resurrect reset template blocks.** `restore_planning_block` restores any soft-deleted block of a live entry, including blocks that `reset_planning_template` or a starter upgrade soft-deleted.
- **M9. Items in a deleted block still look live.** Items under a block deleted with `delete_planning_block` keep `deleted_at NULL` (by design, so they come back on restore). The calendar index `idx_planning_block_items_calendar` and P2's Timeline must join block and entry liveness, or deleted blocks' due items will show for up to 30 days.
- **M10. Very old queued ops can re-apply.** `planning_applied_ops` is pruned after 7 days, but queued outbox ops never expire. An op whose first send committed (the response was lost) and that is replayed more than 7 days later re-applies over the partner's later state. Expire outbox ops before the server's dedupe window does.
- **M11. New native plugins ship to every user.** `flutter_quill` 11.5.0 adds native plugins (`quill_native_bridge_android/ios`, `flutter_keyboard_visibility_temp_fork`), which register in every build, flag or not. The tracked `ios/Podfile.lock` was not updated on the branch.
- **M12. Colour tokens are hard to tell apart.**
  - The 'amber' (#FFB74D) and 'orange' (#FF9800) category seeds give nearly identical tones.
  - The 'yellow' highlight is seeded from amber and renders peach.
  - The 'rose' category is tinted with the app's error red.
- **M13. New plans always default to USD.** `_deviceCurrency()` uses the Intl default locale rather than the device locale.
- **M14. `inactive` lands on the wrong screen.** An `inactive` error pops back to v1 Planning home rather than Conversations (spec §5, the v1 rule).
- **M15. The client-chosen id is an existence oracle, and a P2 hazard.** `add_planning_block`, `add_planning_block_item`, `create_planning_entry` and `create_planning_category` return `invalid_input{field:id}` when the id exists in any relationship. That is harmless without knowing someone else's UUID. But once these RPCs are live in production, P2's plan to "reuse v1 ids with ON CONFLICT (id) DO NOTHING" must detect pre-existing ids rather than silently skip them.
- **M16. The link button accepts URLs without a scheme.** Such a link is then silently stripped on save, behind the generic "formatting removed" snackbar. A delta of more than 2000 ops is rejected with the generic "could not be saved".
- **M17. Every v2 mutation bumps v1's change signal.** Any live v1 provider (summary, calendar) refetches on every grocery tick.

### Declined to judge
- **Spinner instead of the spec's skeleton (§5):** the ledger rules the app standard under the user's design-system directive; this is a design call, not a defect.
- **Arrival-order last-writer-wins between partners' ticks:** Review Focus 3 accepts it explicitly.
- **P1 starter templates differ from §4.1:** P3/P4 add the missing block types under ruling R5.
- **No lock on `relationships` when an RPC checks membership** (a relationship ending mid-RPC is a TOCTOU): this matches v1's `planning_is_active_member` semantics.
- **Dart `\s` vs Postgres `[:space:]` in the link regex:** they differ only on exotic code points (e.g. U+0085), and mostly in the safe direction (the client is stricter).
- **No `deleted_at` index for the nightly purge:** it is irrelevant at P1 volumes.

### Verdict
Ready to merge: with fixes. Nothing is unsafe or leaks data, and v2 stays unreachable without the define. Fix I1 in this branch first, because the migrations go live on merge and the fix is a small lock-order change. Fix I2 and I3 before v2 is exposed beyond the preview, since they silently undo ticks and reject input the UI said was valid.

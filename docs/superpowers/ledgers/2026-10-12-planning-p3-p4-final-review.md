# Final review: Planning P3 + P4 (be269494..4a85a3ef)

Reviewer: fresh-context final reviewer, read-only. One pass over the SQL (both migrations plus the P1 functions they replace or call), a second over the edge function, a third over the Flutter data, controller and widgets. I did not run the test suites; I relied on the ledger's reported results.

## Strengths

- **SSRF guard (guard.ts) is solid.**
  - Each hostname is resolved once, and every A/AAAA answer must be public. A mixed answer is rejected.
  - The connection goes to the validated IP, while the Host header and SNI/cert check use the original name. This defeats rebinding.
  - Every redirect hop goes through `validateUrl` and the resolver again, with at most 3 hops.
  - Covered address forms: IPv4-mapped, NAT64 (64:ff9b::/96 and /48), 6to4, Teredo, ULA, link-local, documentation ranges and 0/8. The WHATWG URL parser normalises numeric hosts before the checks.
  - Only default ports are allowed and credentials are rejected. A 3 s total deadline applies, with byte caps on headers and body.
  - Logs carry the host only.
- **Membership checks.** Every new RPC granted to `authenticated` resolves its row, then calls `planning_v2_actor` (through `planning_v2_lock_entry`/`lock_block`). Strangers get `not_found`. Every new internal helper is revoked from PUBLIC/anon/authenticated.
- **Server-owned payload keys** (`paths`, `preview`, `poll_history`) are stripped on create and carried over on update. A changed link URL queues the old preview image.
- **Copies do not share files.** They drop photo paths and the preview `image_path`, so `purge`/`remove` can't delete a file out from under another plan.
- **Poll lock.** `lock_planning_poll` counts only member votes, under the entry lock. Votes and locks serialise on that same lock.
- **Celebration fires at most once.** The insert into chat runs under the entry lock and is guarded by `celebrated_at`.
- **Pushes are idempotent.** Poll and countdown pushes use the unique `scheduled_notifications.source_key`, the same pattern as the reminders feature.
- **Money.** Integer minor units throughout. The odd-unit rule is deterministic (bigint `/ 2` truncates, and amounts are non-negative), and balances are computed on the server.
- **Purge** queues the files of every block it is about to hard-delete, including blocks deleted with their plan or category.

## Issues

### Critical

None.

### Important

**I1. "Start next one" / "new from template" carry over per-occasion state: ticked table cells and Progress contributions.**
- **Where:** `supabase/migrations/20261012200900_planning_couple_blocks.sql:870-874` (`planning_v2_copy_blocks` copies `cells`, `amount_minor` and `text` for every item type).
- **What goes wrong:**
  - Spec D11: "Start next one copies an entry with ticks and paid flags cleared."
  - In Home & bills, the "Paid ✓" column is a `check` cell. "Start next one" for next month's bills arrives with last month's Paid ticks still on.
  - In Diet, last week's "Cook at home" contributions are copied, so the new week opens at "5 of 5 Reached 🎉".
  - In a Goals plan, a copied numeric goal starts complete. The next contribution posts "🎉 Goal reached" to chat immediately.
- **Fix:**
  - Don't copy items of `progress` blocks.
  - For table rows, null out cells whose column type is `check`.
  - Keep date-poll options but reset votes (already done).
  - Add a contract assertion for both cases.

**I2. A comma decimal separator is read as a thousands separator, so amounts can silently come out 100× too large.**
- **Where:** `lib/features/planning/domain/planning_money.dart:26` (`replaceAll(',', '')`). It is used by the expense editor, Budget, Progress and Table money cells.
- **What goes wrong:**
  - The app ships de/fr/es/it/pt (`AppLocalizations.supportedLocales`). On iOS/Android in those regions, the decimal key on `numberWithOptions(decimal: true)` types `,`.
  - "12,50" becomes 125000 minor units, i.e. €1,250.00. "12,5" becomes €125.00.
  - Nothing flags it: the input parses, Save is enabled, and the wrong figure flows into the budget and the split balance.
- **Fix:**
  - Treat the device locale's decimal separator as the decimal point (`NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP`), or accept a single `,` followed by 1–2 digits as a decimal.
  - Only strip the locale's grouping separator.
  - Add tests for "12,50", "1.234,50" and "1,234.50".

**I3. Changing a table column's type, or adding a column after removing one, can crash the table for both partners.**
- **Where:**
  - `lib/features/planning/presentation/widgets/table_block_view.dart:88-89`: `(v as num)` and `DateTime.parse(v as String)` in `_cell`.
  - `table_block_view.dart:187-188`: `_initial` casts money values.
  - `table_block_view.dart:311-317`: `_nextKey` reuses the lowest free key.
  - `table_block_view.dart:352`: a column's type can be changed in place.
  - Server side, `update_planning_block` never reconciles existing `cells` with new column types. `save_planning_rich_item` merges cells (`...00900.sql:659`), so stale keys persist.
- **What goes wrong:**
  - A couple changes "Cost" from Text to Money while rows hold "about 50". `_cell` throws a TypeError in build, so the table becomes an error box for both phones, and tapping a row throws inside the row editor.
  - Example in Home & bills: remove the "Paid by" column (c4), later add a column. It gets key `c4` again and shows the old "Ama"/"Kofi" values. Set it to Money and it crashes the same way.
  - Text→Date crashes in `DateTime.parse`.
  - Rows saved after a type change are rejected (`invalid_input`), because the editor resubmits the stale `_values` for date/check columns.
- **Fix:**
  - Allocate new column keys as max(existing ever-used)+1, or a random suffix. Never reuse a key.
  - Render defensively: check the runtime type and show the raw text, or "–", when it doesn't match.
  - On a column type change or removal, either null the affected cells server-side in `update_planning_block` (table branch), or have the row editor drop values that don't fit the column type.

**I4. Numeric Progress contributions can't be seen, corrected or removed.**
- **Where:** `lib/features/planning/presentation/widgets/progress_block_view.dart:58-94`. The view shows only a summary, "Add to it" and "Set target".
- **What goes wrong:**
  - Spec §6.9 describes contribution items ("+₦50k", optional note). The UI never lists them, so there is no swipe-to-delete or edit.
  - A mistyped "+50000" instead of "+500" (or an I2 comma error) is permanent. On a Goals plan it can also fire the irreversible "🎉 Goal reached" chat message.
- **Fix:** List the contributions under the bar (amount, note, initials). Reuse the expenses Dismissible plus Undo, i.e. `deleteItem`/`restoreItem`, which already refresh `computed`.

**I5. After "Mark settled", lines created earlier never count again, even when they are filled in or corrected later.**
- **Where:** `supabase/migrations/20261012200800_planning_rich_blocks.sql:319-323` (`i.created_at > e.split_settled_at`).
- **What goes wrong:**
  - A Trips plan is created from the template, which seeds the "Flights" and "Stay" lines with no amount and no payer.
  - The couple splits costs, enters the flights, and settles mid-trip.
  - Kofi then fills in "Stay: GHS 4,000, paid by Kofi". The line was created before the settle, so it is excluded. The card says "All even" while Ama owes GHS 2,000.
  - The same happens when an old line's amount or payer is corrected after settling.
- **Note:** This follows spec §6.7 to the letter ("Lines created after split_settled_at count"). A reasonable person expects any money they enter after settling to count.
- **Fix:** Record the per-currency net in the `settle` event (already captured in `before`). Compute the balance as net(all live lines) − net at the last settle. Alternatively, stamp counted lines with a `settled_at` and treat later money-field edits as new deltas. Add a contract case: fill a pre-settle template line after settling.

**I6. Adding an expense can create a duplicate line when the network is flaky.**
- **Where:**
  - `lib/features/planning/presentation/planning_providers.dart:621-640`: a new UUID on every call, and `await _refreshComputed()` inside the save's try.
  - `lib/features/planning/presentation/widgets/expenses_block_view.dart:25-49`: the sheet pops before saving, and entered data is lost on error.
- **What goes wrong:**
  - If the save RPC commits but the response is lost, or the follow-up `get_planning_entry` fails, the user sees "Could not reach Attune" and the typed entry is gone. They re-enter it, a new UUID is created, and a second line appears once the signal refetch lands. That doubles spend in the Budget and the split balance.
  - The same refresh-after-success pattern makes `deleteItem` (`:528`) report a failure for a delete that happened, without offering Undo.
  - This breaks checklist 2.18/2.20: idempotency for [FIN] mutations, with the same key reused across retries.
- **Fix:**
  - Generate the item id once per editor session and keep the sheet open until the save succeeds, so a retry reuses the id and hits the server's idempotent create path.
  - Make the post-save `_refreshComputed()` best effort: `unawaited`, errors swallowed, with the signal refetch as backstop. Do the same in `deleteItem`/`restoreItem`.

**I7. The money history (expense audit) has gaps outside block delete/restore.**
- **Where:**
  - `delete_planning_entry` (`20261012200300_planning_v2_entries.sql:168-185`) and `restore_planning_entry` (`20261012200600_planning_v2_notes_and_pins.sql:237-268`) soft-delete and restore expense lines.
  - `delete_planning_category` (`20261012200200_planning_v2_categories.sql:385-415`) does the same.
  - `planning_v2_copy_blocks` (`...00900.sql:870-874`) inserts expense lines with amounts.
  - None of these write `planning_expense_events`.
- **What goes wrong:**
  - Spec §6.7 says every expense mutation writes an event. The plan's Review Focus 2 asks for every path.
  - The most likely real dispute — "who deleted the Bali plan with all our costs" — leaves no audit trail.
  - There is no UI on the audit today, so the user impact is indirect, but this is an explicit invariant.
- **Fix:** Write one `delete`/`restore` event per live expense line in those three functions, and a `create` event per copied line in `copy_blocks`, when the source block is `expenses`. Extend the rich contract test to assert counts.

### Minor

- **M1. Undo can appear for a delete that failed.** `date_poll_block_view.dart:33-42`: `_delete` swallows the error in `_guard` and then always shows "Dates removed / Undo". Return early on failure, as the expenses and table views do.
- **M2. Undo after a lock can bring a poll option back.** `restore_planning_block_item` (`...00900.sql:677-699`) has no block-type check. If an option is deleted and the poll is then locked, Undo resurrects the option as an item under the new Date block, where it is invisible but counted. Refuse the restore when the item's block type no longer takes items (date).
- **M3. Signed URLs live longer than the spec allows.** TTL is 1 h (`planning_media.dart:25`); spec §3.9 says 10 minutes. Use 10 minutes and keep-alive for about 8.
- **M4. Bucket limits are missing and orphaned uploads are never cleaned.**
  - The bucket lacks `file_size_limit` and `allowed_mime_types` (spec §3.9). A member can upload any file type up to the project limit into the couple's folder.
  - Uploads whose `add_planning_photo` fails are never cleaned: a network drop, or a partner filling the 10 slots first.
  - The same applies when the edge function's second `set_planning_link_preview` call throws after the image upload.
  - Fix: set the bucket limits in the migration. Have `addPhoto` call a remove-orphan path, or add a sweeper for unreferenced objects older than a day.
- **M5. Image decompression bomb.** `index.ts:68-77` decodes an untrusted image with imagescript and no pixel cap. A 2 MB PNG declaring 20000×20000 can OOM the function. Read the dimensions from the header first and refuse anything over roughly 40 MP.
- **M6. The audit table is not fully protected from `service_role`.** Under Supabase default privileges, `service_role` keeps UPDATE/DELETE/TRUNCATE on `planning_expense_events`. The row trigger stops UPDATE/DELETE, but not TRUNCATE. Revoke from `service_role` and add a `BEFORE TRUNCATE` statement trigger. Also, the `pg_trigger_depth() < 2` exemption admits writes from any trigger context, not only foreign-key cascades; worth a comment, or a check on the session variable used by RI.
- **M7. The item validator accepts missing or non-numeric amounts.** In `planning_v2_rich_item_fields` (`...00900.sql:225-233, 280-285`), a missing `amount_minor` makes `NOT planning_v2_is_int(NULL)` evaluate to NULL, so the IF never fails. An expense line or progress contribution with no amount is accepted through the RPC. A string amount may raise a raw `22P02` instead of `planning:invalid_input`, because SQL does not guarantee the AND short-circuits. Use `coalesce(planning_v2_is_int(...), false)` and a CASE-guarded cast.
- **M8. A photo can be dropped silently, and some controller methods write state after dispose.**
  - `photo_block_view.dart:52-54` calls `ref.read` after two awaits with no `mounted` check. Leaving the plan while a photo is being prepared throws, the error is swallowed, and the photo is silently not added. Read the notifier before the first await.
  - The new controller methods (`addPhoto`, `removePhoto`, `vote`, `lockPoll`, `setSplit`, `settleSplit`, `updateBlockPayload`) call `_set` after an await without `_alive` (the P1 pattern). Guard them.
- **M9. The server's own preview write can make the user's next link edit fail.** `set_planning_link_preview` bumps the block version (`...00800.sql:819-821`). If the user edits the link before the signal refetch lands (seconds after adding it), they get `stale_version`, their edit is discarded, and they see a generic error (`link_block_view.dart:30-37`). Don't bump `version` for the server-only preview key, or retry once in `updateBlockPayload` for link blocks.
- **M10. Rapid ticks can flicker back.** `_refreshProgress` does a full refetch after every tick in a plan with a Progress block. That snapshot can briefly overwrite a later optimistic tick until its own response or the signal refetch lands.
- **M11. The push fallback screen has no way back.** `app_router.dart:650-653` shows "Planning unavailable" in a `Scaffold` with no AppBar or back button, so a user who arrives without `extra` (process death, restoration) has no visible way out. This matches the existing `/planning` route, so it is low priority.

## Review Focus checklist

1. **Link previews and SSRF: passes.** No path reaches a private, loopback or metadata address, including through redirects or rebinding. The SQL rate limit is serialised per user by an advisory lock. `set_planning_link_preview` is service-role only, validates `image_path` against the block's own folder, and queues a replaced image.
2. **Money: partly passes.** Odd-unit rounding is deterministic, and settling resets the balance for new lines (but see I5). Audit rows can't be updated or deleted by any API role (see M6 for TRUNCATE). Coverage of mutation paths fails: see I7.
3. **Photos: passes.** Only the couple can read or write, and removal, link-preview replacement and purge all queue the file. Copies don't share files. Orphans: see M4.
4. **Date poll: passes.** It locks only with both members' votes on that option, and pushes are debounced per poll, recipient and hour.
5. **Countdown push: passes.** One push per (block, partner, local date) via `source_key`, in each partner's zone from 08:00 local, with catch-up after a missed run.

**Also checked:**
- Every new SECURITY DEFINER RPC resolves the row, then checks membership. Strangers get `not_found`.
- Lock order: entry → block → item everywhere. The exception is `set_planning_link_preview`, which locks only the block row before bumping the signal; I traced it and found no deadlock cycle.
- The chat celebration fires at most once.
- Stale versions are handled in `updateBlockPayload`, `setTarget` and `saveRichItem` (adopt theirs, rethrow).
- The router and notification-config additions are additive and use a unique route name (`planning_flow`). I found no regression to existing routes.

## Declined to judge

- **Edge runtime support.** I can't tell whether Supabase Edge Runtime supports `Deno.resolveDns`, `Deno.connect` and `Deno.startTls` in production. The Deno tests stub the resolver and connector. If unsupported, every preview ends as `failed`, a plain card. This needs a deploy smoke test.
- **Relationship hard-delete leaves `planning-media` objects un-queued.** It is part of the relationship lifecycle, outside this plan.
- **Countdown falls back to the plan's first Date block when its named block is deleted.** Spec §6.6 says "Pick a date" and cancel the push; overridden by a ledger ruling (Task 5).
- **Poll debounce uses the UTC clock hour,** so two pushes are possible across an hour boundary. The spec names `hour_bucket`.
- **A partner who never opened Planning gets the countdown push at 08:00 UTC.** Spec §8.2 says "else UTC".
- **Rulings accepted as written:**
  - Place search uses the app's location service instead of Mapbox.
  - Photos reuse the chat image preparer (1600 px / 800 KB).
  - Diet's weekly reset and "Add to Groceries" are deferred.
  - Rich items are online-only.
  - `source_key` replaces new notification tables.
- **Swipe direction** (startToEnd vs the spec's swipe-left) is a P1 convention.
- **Expense amounts carried by copies.** That can be a useful estimate; only the audit side is flagged (I7).
- **Countdown sweep performance** at large scale (per-row `planning_v2_countdown_target` subqueries). It is fine at current volume.
- **Test results.** I did not run the suites (read-only); I relied on the ledger's reported results.

## Assessment

**Ready to merge?** With fixes.

**Reasoning:** The security-critical parts are well built and I found no Critical issues: the SSRF guard, the membership checks, the storage policies, and the idempotency of the poll lock, celebration and pushes. But four Important issues are user-visible on day one, and three affect money or its audit:
- Copies carry "Paid" ticks and progress (I1).
- Comma-decimal amounts can be 100× too large (I2).
- Changing a column type can crash a table (I3).
- Contributions can't be corrected (I4).
- Settle misses later-filled lines (I5).
- Retries can duplicate expenses (I6).
- The expense audit has gaps (I7).

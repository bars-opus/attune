# Planning P3 + P4 — Rich and couple blocks

> Inline execution (superpowers:executing-plans). The user asked to build P3 and P4 and merge.

**Goal:** Add the remaining ten block types from the spec, the gallery templates, notifications, and the full starter templates.
- **P3 (rich):** Table, Photo, Link (with server-side previews), Place, Expenses (with optional split and settle) and Budget.
- **P4 (couple):** Date poll, Countdown, Progress and Dual clock.

**Spec:** `docs/superpowers/specs/2026-10-12-planning-v2-design.md` §3.4–3.6, §3.9, §4.1, §6.3–6.13, §7.1 and §8. §16 still applies: there is no v1 and no flag.

## Global Constraints
- **Migrations** use the `20261012200800`+ range, and no existing migration is edited.
- **SQL runs** use `ATTUNE_TEST_DB=attune_planning`, passed inline on every command.
- **RPC conventions are as in P1:** SECURITY DEFINER; `search_path = public`; resolve the row, then `planning_v2_actor`; lock in the order category → entry → block → item; typed `planning:*` errors; touch the entry and bump the signal.
- **Money is integer minor units plus an ISO 4217 code** (checklist 2.19). Every expense mutation writes `planning_expense_events` in the same transaction (checklist 2.22). No balance is ever summed per partner outside a plan that has split turned on (spec D6/D13).
- **The UI uses the app design system** (lib/core/widgets, AppColors), as P1 did.
- **Photos** are re-encoded to JPEG on the device (which strips EXIF and GPS), with the long edge at most 2048px and the file at most 10 MB. The bucket is private and only the couple can read or upload; display uses signed URLs.
- **Link previews** fetch on the server only, through `planning-link-preview`, with the SSRF guard from spec §7.1. The client never fetches arbitrary pages.

## Tasks

### P3
1. **SQL: rich blocks.** Per-type validation for table, photo, link, place, expenses and budget. A generic `save_planning_rich_item(p_id, p_block_id, p_version, p_fields jsonb, p_after_id)` handles table rows and expense lines. Split on/off and settle, with the append-only `planning_expense_events` audit. Photos: add/remove RPCs, the `planning-media` bucket, policies, and deletion through `queue_media_deletion`. A link preview cache plus a service-role RPC to write a preview. Computed `spent` and `split` in the plan detail. Starter templates get their full block lists.
2. **Edge function `planning-link-preview`,** with Deno tests covering every SSRF case in §7.1. Add `entry_id` to the deep-link allowlist in `process-scheduled-notifications`.
3. **Flutter data:** models, repository and controller for the six block types.
4. **Flutter UI:** the tool tray, and a view and editor for each of the six types. Split on/off and "Mark settled" in the plan menu.

### P4
5. **SQL: couple blocks.**
   - Date poll: options, votes, and "lock it in", which turns the poll into a Date block.
   - Countdown and Dual clock validation.
   - Progress: numeric or checklist, celebrating once in chat on reaching 100% (Goals only).
   - `planning_member_settings` time zones.
   - Notifications through `scheduled_notifications`:
     - a debounced push when a poll gets new options;
     - an hourly cron for countdown day-of pushes at 08:00 local, idempotent per (countdown, user, local date).
   - Gallery templates and `create_planning_category_from_gallery`.
6. **Flutter UI** for the poll, countdown, progress and dual clock (which reuses `partnerDistanceProvider`). The gallery in New category. The device time zone is reported when Planning opens. Notification type `planning_entry` opens the plan.

### Verify
7. Run analyze, the full Flutter suite, the full SQL harness, concurrency, and the Deno tests. Then a fresh whole-branch review; fix Critical and Important findings test-first; merge.

## Review Focus
1. Link previews never fetch a private, loopback or metadata address, including through a redirect or DNS rebinding.
2. Money: an odd-minor-unit split rounds the same way every time, and settling resets the balance. An audit row can never be updated or deleted.
3. Only the couple can read or write photos, and a removed photo's file is queued for deletion.
4. The date poll locks only when both partners have voted for the same option, and the push is debounced.
5. A countdown push is sent exactly once per partner per day, in that partner's time zone.

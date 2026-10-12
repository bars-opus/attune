# Planning v2 — Couples Planning Space: Design

**Status:** design approved in conversation (2026-10-12); awaiting written-spec review
**Supersedes:** `2026-09-14-planning-design.md` (v1). v1's invariants that survive are restated here; anything not restated is replaced.
**Quality bar:** every sub-project must pass *Algorithm Quality Review Checklist v3.1* (`lib/architecture/algorithms/algorithm_quality_review_checklist.md`). §12 is the conformance table.

---

## 1. What this is

Planning becomes a couples planning space rather than a task list. The home
screen is a list of **categories** (Goals, Trips, Date nights, Home & bills,
Groceries, plus any the couple creates). A category holds unlimited
**entries** (one trip, one month of bills, one Saturday shop). An entry is a
page of **blocks**: formatted text, checklists, tables, dates, date polls,
countdowns, expenses, budgets, progress, photos, links, places, and a dual
clock for long-distance couples. Each category has **exactly one template**,
an editable starter page that new entries copy.

What makes it couples-specific rather than a generic planner:

- **Agreeing**: date polls with "works for me" from each partner and a shared "Lock it in".
- **Sharing the work**: checklist items assigned to *Ama*, *Kofi* or *Either*.
- **Distance**: a dual clock and a visit countdown that pushes to both partners on the day.
- **Money without a scoreboard**: expenses are a shared pot by default. Splitting is opt-in **per entry**, and balances never aggregate across entries.
- **Live together**: two partners ticking the same grocery list in different aisles never overwrite each other.

### 1.1 Simulated couples (design inputs)

| Couple | Situation | What it forced into the design |
|---|---|---|
| Ama & Kofi | Live together, Accra | Item-level rows for checklists; "Start next one" instead of a recurrence engine; offline outbox for ticks |
| Lena & Marco | Long distance, Berlin–Toronto, 6h apart | Date poll; countdown push in each recipient's time zone; dual clock; per-expense currency |
| Priya & Sam | 10-day Bali trip | Link previews; shortlist via links block; itinerary table; budget vs spent |
| Dan & Joy | Shared diet | Meal table; "Add to Groceries"; **no body-metric block** (see §2) |
| Tobi & Ruth | Couple goals | Numeric progress ("₦2M for a car") as well as checklist progress |

## 2. Decisions

| # | Decision | Consequence |
|---|---|---|
| D1 | **Fold v1 in** (not layer, not replace-with-shim-forever) | v1 Goals/Tasks/Events/Notes migrate into v2 once (§9). One mental model for users. |
| D2 | Fully shared, as v1 | Either active partner may mutate anything; `created_by` is audit metadata only, nullable on account deletion. |
| D3 | Category → Entry → Block → Item hierarchy | Each layer has one purpose; blocks are reorderable; items make concurrent edits row-disjoint. |
| D4 | Exactly one template per category, enforced by a partial unique index | "Edit template" affects future entries only; entries are free-form after creation. |
| D5 | Five starters seeded: Goals, Trips, Date nights, Home & bills, Groceries. A sixth, **Everyday**, exists for migrated/AI content and is shown only when non-empty | Starters can be renamed or hidden, **never deleted** (AI and migration target them by `seed_key`). Custom categories can be deleted. |
| D6 | Expenses: shared pot by default; split per entry, opt-in | No cross-entry or category-level partner balance exists anywhere. Upholds the product's no-scorecard rule. |
| D7 | Pushes only for: date poll awaiting you; countdown day-of (to both); goal completion (chat celebration, as v1) | Edits, ticks and new entries are silent; they show as a "new" dot. No activity feed. |
| D8 | Hero header + block stack + "+" tool tray | No slash commands; no fixed forms. |
| D9 | Rich text via `flutter_quill` (Delta JSON), server-validated whitelist | Bold, italic, underline, strike, highlight, text colour, H1–H3, alignment, lists, quote, links. Colours stored as **token names**. |
| D10 | No currency conversion | Totals are grouped per currency. No FX dependency. |
| D11 | No recurrence engine | "Start next one" copies an entry with ticks and paid flags cleared. |
| D12 | No body-measurement block, anywhere | In a shared space one partner's weight becomes something the other watches. Progress stays neutral ("meals cooked together"). |
| D13 | Totals only, never per-person totals | Progress and budgets show couple totals; `paid_by` is per line, never summed per partner (except inside an opted-in split entry, §6.7). |
| D14 | Money in integer minor units + ISO 4217 code | Never float (checklist 2.19). |

## 3. Data model

All tables: `relationship_id` (FK → `relationships` ON DELETE CASCADE),
`created_by uuid NULL` (FK → `auth.users` ON DELETE SET NULL),
`created_at`, `updated_at`, `deleted_at` (soft delete is the app boundary;
relationship/account cascades are hard deletes, as v1). Every table has
`UNIQUE (id, relationship_id)` so children can use **composite FKs** that make
cross-couple references impossible at the schema level.

Clients generate UUIDs for every new row (idempotent create, v1 pattern): a
retry with the same ID and the same normalized payload returns the existing
row. The same ID with a different payload is rejected with `invalid_input`.

### 3.1 `planning_categories`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `seed_key` | text NULL | `goals` · `trips` · `date_nights` · `home_bills` · `groceries` · `everyday`. `UNIQUE (relationship_id, seed_key)` |
| `name` | text | 1–40 chars, trimmed, not blank |
| `icon` | text | Key into a curated icon set (validated against an allow-list) |
| `color` | text | Design-token key (validated against an allow-list) |
| `position` | text | Fractional index (§3.7) |
| `hidden_at` | timestamptz NULL | |

`CHECK (seed_key IS NULL OR deleted_at IS NULL)`: a starter can never be soft-deleted.

### 3.2 `planning_entries`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `category_id` | uuid | Composite FK `(category_id, relationship_id)` |
| `is_template` | bool | Partial unique index `(category_id) WHERE is_template AND deleted_at IS NULL` |
| `title` | text | 1–120 chars |
| `cover_path` | text NULL | Object path in `planning-media` |
| `status` | text | `active` · `done` · `archived` |
| `currency` | char(3) | Entry default; ISO 4217 allow-list |
| `split_enabled` | bool | Default false. Templates may not enable it |
| `split_settled_at` | timestamptz NULL | Balance counts lines created after this |
| `celebrated_at` | timestamptz NULL | Server-owned; never cleared (one celebration per entry, v1 rule carried over) |
| `position` | text | Fractional index within category |

Index: `(relationship_id, category_id, is_template, status, updated_at DESC, id) WHERE deleted_at IS NULL` for the cursor-paginated entry list.

### 3.3 `planning_blocks`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `entry_id` | uuid | Composite FK `(entry_id, relationship_id)` |
| `block_type` | text | CHECK in the 13 types of §6 |
| `position` | text | Fractional index within entry |
| `payload` | jsonb | Validated per type in the RPC; `pg_column_size(payload) <= 16384` CHECK |
| `plain_text` | text NULL | Server-derived projection of rich text (§6.1); read by AI, summary, notifications |
| `date_start` / `date_end` | date NULL | Date block; `date_end >= date_start` |
| `target_minor` | bigint NULL | Budget/Progress; `>= 0` |
| `target_currency` | char(3) NULL | |
| `version` | int | Optimistic concurrency; incremented on every update |

Index for Timeline: `(relationship_id, date_start, id) WHERE deleted_at IS NULL AND block_type = 'date'`.

### 3.4 `planning_block_items`

One row per checklist item, expense line, table row, poll option or progress contribution.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `block_id` | uuid | Composite FK `(block_id, relationship_id)` |
| `position` | text | Fractional index |
| `text` | text NULL | ≤ 500 chars |
| `section` | text NULL | Checklist section label, ≤ 40 |
| `checked_at`, `checked_by` | NULL | Checklist |
| `assigned_to` | uuid NULL | Must be one of the two members (RPC-validated) |
| `due_date` | date NULL | Checklist; read by Timeline |
| `amount_minor` | bigint NULL | `>= 0` |
| `currency` | char(3) NULL | |
| `paid_by` | uuid NULL | Member or NULL |
| `split_share_minor` | bigint NULL | Custom split: the non-payer's share. NULL = equal |
| `date_start`/`date_end` | date NULL | Poll option |
| `cells` | jsonb NULL | Table row; ≤ 12 keys, each value ≤ 200 chars |
| `version` | int | |

Indexes: `(block_id, position, id) WHERE deleted_at IS NULL`; Timeline: `(relationship_id, due_date, id) WHERE deleted_at IS NULL AND due_date IS NOT NULL`.

### 3.5 `planning_poll_votes`

`(item_id, user_id)` PK, composite FK to the item, `created_at`. A vote row exists = "works for me". Unvoting deletes the row; votes are not soft-deleted (they carry no content).

### 3.6 `planning_expense_events` (audit, checklist 2.22)

Append-only. Columns: `id`, `relationship_id`, `entry_id`, `item_id NULL`,
`actor_id NULL`, `action` (`create`·`update`·`delete`·`split_on`·`split_off`·`settle`),
`before jsonb NULL`, `after jsonb NULL`, `created_at`. Written only by the
expense/split RPCs, in the same transaction as the change. **No UPDATE or
DELETE grant to any role but the table owner**, plus a trigger that raises on
UPDATE/DELETE outside a relationship cascade. Retained for the life of the
relationship; deleted only by relationship cascade.

### 3.7 Ordering

`position` is a base-62 fractional index string (between any two keys a key
exists). Reorder = one row update. A server-side `rebalance_positions(entry)`
runs if a key exceeds 64 chars (amortized O(1), worst O(n) for n ≤ 200 blocks).

### 3.8 Change signal (reused, unchanged)

v1's `planning_change_signals` (one row per relationship, `version` bump,
already in the Realtime publication) is reused as is. Every v2 mutation calls
the existing `bump_planning_signal`. Clients refetch only the providers
currently on screen (open entry, visible category list). No per-entry signal
table is added.

### 3.9 Storage

Bucket `planning-media`, private. Path: `{relationship_id}/{entry_id}/{uuid}.jpg`.
`file_size_limit = 10 MB`, `allowed_mime_types = image/jpeg, image/png, image/webp, image/heic`.
Policies: an active member of `relationship_id` (first path segment) may insert/select.
Delete only through the media deletion queue (§3.10). Display via signed URLs, 10-minute TTL.

### 3.10 Retention

Nightly `pg_cron` job: rows soft-deleted more than **30 days** ago are hard-deleted
(children first). Their storage objects are enqueued on the existing
`process-media-deletion-queue`. The audit table is excluded.

### 3.11 Limits (checklist 2.5, 2.14, 4.11)

Defined once in `planning_limits()` (an IMMUTABLE SQL function returning a JSON object) and mirrored in a Dart constants file, with a contract test asserting they agree.

| Limit | Value |
|---|---|
| Categories per relationship (live) | 50 |
| Blocks per entry | 200 |
| Items per block | 500 |
| Block payload | 16 KB |
| Table columns × rows | 12 × 50 |
| Photos per Photo block | 10 |
| Image size | 10 MB |
| Text block plain length | 10,000 chars |
| Entries per category | unlimited, cursor-paginated (page 30, max 100) |

## 4. Categories and templates

- **Seeding** is lazy and idempotent: `ensure_planning_categories()` is called by the home read RPC; it inserts missing starters `ON CONFLICT (relationship_id, seed_key) DO NOTHING`, each with its template entry (§4.1). `everyday` is seeded but hidden from the home list while it has no non-template entries.
- **Custom category**: name, icon, colour; template starts blank or copied from a gallery template.
- **Delete custom category**: confirmation names the number of entries; soft-deletes the category and its entries (recoverable 30 days via support; no restore UI in v2).
- **Edit template**: opens the normal editor with a banner. Starters offer "Reset to Attune's version" (replaces the template's blocks with the seeded version in one transaction).
- **New entry**: sheet with "Use template" (default) / "Start blank". `create_planning_entry_from_template(entry_id, category_id, title)` copies the template's blocks and items **server-side in one transaction** (checklist 1.10). Copied items reset `checked_*`, `paid_by`, votes.
- **Start next one**: `duplicate_planning_entry(source_id, new_id, title)`. Same copy semantics; the source is untouched.

### 4.1 Starter templates

| Category | Blocks in order |
|---|---|
| Goals | Progress (checklist mode) · Date "Target date" · Text "Why this matters to us" · Checklist "Steps" |
| Trips | Photo (cover) · Date poll "Pick dates" · Countdown · Place "Destination" · Budget · Expenses (lines: Flights, Stay) · Link "Places to stay" · Table "Itinerary" (Day · Plan · Where · Cost) · Checklist "Packing" · Text "Notes" |
| Date nights | Date · Place · Text "The plan" · Budget · Link "Ideas" · Text "What we loved" |
| Home & bills | Table "Bills" (Bill · Amount · Due day · Paid ✓ · Paid by), rows Rent, Electricity, Water, Internet, TV · Budget · Text "Notes" |
| Groceries | Checklist with sections Produce, Dairy, Meat & fish, Pantry, Household · Budget "Estimated total" |
| Everyday | Text |

Gallery templates (behind "+ New category"): **Next visit** (Countdown, Date poll, Dual clock, Expenses with two flight lines, Checklist "Things to do together", Checklist "Packing"), **Diet** (Table 7 × Breakfast/Lunch/Dinner, Checklist "Shopping" with "Add to Groceries", Progress numeric "Cook at home" weekly), **Wishlist**, **Moving house**, **Wedding**, **Baby**. Gallery definitions are versioned JSON in a migration, not client code.

## 5. Screens

- **Planning home**: category list (icon, name, entry count, "new" dot). "+ New category" at the bottom; a "Hidden" row when any are hidden. Long-press to reorder.
- **Category**: entry list (cursor-paginated), active first, then a collapsed "Done & archived". "+" opens the new-entry sheet. ⋯ menu: Edit template · Rename · Hide · Delete (custom only).
- **Entry**: hero header (optional cover, title, key-facts strip derived from the entry's Date/Countdown/Budget/Progress blocks) over a block stack. Tap = edit in place; long-press-drag = reorder; swipe-left = delete with Undo snackbar. Floating "+" opens the tool tray (13 blocks, §6).
- **States** (each screen): first-load skeleton; retained content during refresh; empty state with one clear action; inline error with retry; `inactive` closes Planning and returns to Conversations (v1 rule).
- **Accessibility**: all actions reachable without drag (reorder also via ⋯ "Move up/down"); semantic labels on tick, vote, settle; 44pt targets; text scales to 200% without clipping; colour never the only signal (votes show initials, ticks show a check glyph).
- The Calendar tab on Planning home (shipped `c520405d`) is unchanged.

## 6. Blocks

### 6.1 Text (rich)
- Editor: `flutter_quill`, exact version pinned in the plan. Toolbar above the keyboard.
- Allowed Delta attributes (whitelist): `bold`, `italic`, `underline`, `strike`, `background` and `color` ∈ the palette token set (`yellow`, `green`, `blue`, `pink`, `purple`), `header` ∈ {1,2,3}, `align` ∈ {left, center, right, justify}, `list` ∈ {bullet, ordered}, `blockquote`, `link` (http/https only, ≤ 2,048 chars). **No embeds.**
- Server validation (`planning_validate_delta(jsonb)`): rejects unknown ops, unknown attributes, non-whitelisted values, embeds, non-string inserts, > 16 KB, plain length > 10,000. Derives `plain_text`.
- Rendering maps palette tokens to theme colours, so dark mode works.

### 6.2 Checklist
Items with text, optional section, assignee (Ama / Kofi / Either), optional due date. Tick/untick = `set_planning_item_checked(item_id, checked, op_id)`; idempotent by `op_id`. Ticked items fold into "n done ▾".

### 6.3 Table
Payload: `columns: [{key, label, type}]`, type ∈ text · number · money · date · check. Rows are items with `cells`. Cell edit opens a sheet. Horizontal scroll inside the block.

### 6.4 Date
Single date or range, all-day. Feeds Timeline and the header strip.

### 6.5 Date poll
Options are items with `date_start`/`date_end`. Votes in §3.5. When both members have voted for the same option, "Lock it in" (either partner) calls `lock_planning_poll(block_id, item_id)`. In one transaction, this converts the poll block into a Date block with that range and keeps the options as history in the payload. Push (§8) when a partner adds options, debounced to at most one per poll per hour.

### 6.6 Countdown
Payload references a Date block in the same entry. It shows "n days", "Tomorrow", "Today". If the target block is deleted, the countdown shows "Pick a date" and the push is cancelled.

### 6.7 Expenses
- Lines are items: label, amount, currency (defaults to the entry's), optional `paid_by`.
- **Split** (entry-level `split_enabled`): equal by default or custom (`split_share_minor`). Lines created after `split_settled_at` count.
- "To even out" is computed server-side in integer minor units, per currency. For an equal split of an odd amount, the extra minor unit stays with the payer, so the rule is deterministic.
- "Mark settled" (`settle_planning_split(entry_id)`) sets `split_settled_at` and writes an audit event.
- Lines with `paid_by` NULL are excluded from the balance.
- Every expense mutation writes `planning_expense_events` in the same transaction.

### 6.8 Budget
Target (`target_minor`, `target_currency`). Spent = sum of the entry's expense lines in that currency, computed in the read RPC. Lines in other currencies are listed as separate totals, never converted.

### 6.9 Progress
Two modes:
- **Numeric**: a target plus contribution items ("+₦50k", optional note).
- **Checklist**: derived from a referenced Checklist block in the same entry.

It shows the couple total only. Reaching 100% for the first time triggers the celebration (§8.3).

### 6.10 Photo
Up to 10 images.
- **Client**: resize to max 2048px, re-encode JPEG quality 85 (strips EXIF including GPS), upload, then `add_planning_photo(block_id, path)`.
- **Server**: verifies that the path sits under the caller's relationship and entry and that the object exists.

### 6.11 Link
Payload: `url`, `title`, `description`, `image_path`, `host`, `fetched_at`, `preview_status`.
- Accepted schemes: `http` and `https` only, validated at write and again before `url_launcher`.
- The preview is filled by the edge function (§7.1).
- If the preview fails, the block still shows the host plus the URL and is still tappable.

### 6.12 Place
Mapbox Geocoding search (existing dependency) → name, address, lat/lng. Tap opens the platform maps app. If Mapbox is unreachable: free-text name with no coordinates (degradation, 1.3).

### 6.13 Dual clock
Stores nothing. It reads `get_partner_distance` (existing; returns the partner's coarse city and time zone only when the partner shares location presence) and the device time zone. It is hidden when either value is unavailable.

## 7. Server functions

### 7.1 Edge function `planning-link-preview`

| Concern | Rule |
|---|---|
| Auth | Valid user JWT; caller must be an active member of the block's relationship (checked via RPC before fetching) |
| Rate limit | 30 requests/min/user; 429 with `Retry-After` |
| SSRF | Resolve DNS once; reject loopback, RFC1918, link-local (incl. 169.254.169.254), CGNAT, multicast, unspecified, IPv6 ULA/link-local/loopback and IPv4-mapped forms. **Connect to the validated IP**, sending the original Host header/SNI (defeats DNS rebinding). |
| Redirects | Max 3, each re-validated as above |
| Timeouts | connect 1s, total 3s |
| Size | Read at most 512 KB of HTML; preview image at most 2 MB |
| Parsing | `og:title` (≤ 200), `og:description` (≤ 500), `og:image`; text only, HTML entities decoded, control chars stripped |
| Image | Downloaded through the same guard, re-encoded to JPEG, stored at `planning-media/{rel}/{entry}/preview-{uuid}.jpg` |
| Cache | `planning_link_previews(url_hash PK, …, fetched_at)`, 7-day TTL, no client grants. Images are copied per relationship (no cross-couple object sharing) |
| Logging | JSON, `request_id`, outcome code, latency, **host only** (never the full URL) |
| Failure | Writes `preview_status = 'failed'`. Never fails the block save. |

### 7.2 RPCs

All `SECURITY DEFINER`, `SET search_path = public`, `REVOKE ALL FROM PUBLIC, anon`, `GRANT EXECUTE TO authenticated`. Each RPC:
1. resolves the target row and its `relationship_id`;
2. checks `planning_is_active_member(relationship_id)` (existing v1 helper);
3. locks the row(s) it mutates (`FOR UPDATE`) in a fixed order (category → entry → block → item) to avoid deadlocks;
4. enforces limits;
5. bumps the change signal.

Errors: `not_found` (also returned for forbidden; no existence leak), `stale_version` (with the current row), `limit_reached` (with which limit), `invalid_input` (with field), `inactive`.

Read: `get_planning_home()`, `list_planning_entries(category_id, cursor, limit)`, `get_planning_entry(entry_id)` (entry + blocks + items + votes + computed totals in **one** call).

Write (names indicative; the plan fixes them): category create/update/hide/delete/reorder; entry create-from-template/blank/duplicate/update/status/delete/reorder; block add/update(version)/delete/reorder; item add/update(version)/check/delete/reorder; poll vote/unvote/lock; split enable/disable/settle; photo add/remove; template reset.

## 8. Notifications

Delivered through the existing `send-notification` / `process-scheduled-notifications` pipeline. The plan's first task confirms its enqueue contract.

1. **Date poll awaiting you.** Sent to the partner who did not add the options. Debounced via `planning_poll_notified(block_id, recipient, hour_bucket)` unique. Body: "{name} suggested dates for {entry title}".
2. **Countdown day-of.** An hourly `pg_cron` job selects countdowns whose date is today in the recipient's time zone, sent at 08:00 local. Time zone: the IANA zone the device reports, written by the client to a new `planning_member_settings(relationship_id, user_id, timezone)` row whenever Planning opens (validated against `pg_timezone_names`), else UTC. Location presence is not used: it is opt-in and must not become a requirement for a reminder. Idempotent via `UNIQUE (countdown_block_id, user_id, local_date)`. Sent to both partners.
3. **Celebration.** First time a Goals entry's Progress reaches 100%: a chat system notice through the native chat pipeline (v1 behaviour), guarded by `celebrated_at`.

Notification bodies use `plain_text` and titles only, length-capped.

## 9. Migration of v1 (sub-project 2)

### 9.1 Mapping (old UUIDs reused as new IDs)

| v1 | v2 |
|---|---|
| Goal + child Tasks | Goals entry (id = goal id) · Progress (checklist mode) · Checklist "Steps" whose items are the child tasks (id = task id; assignee, due date, completion carried) · `celebrated_at` carried |
| Top-level Task | Item in the "Our to-dos" checklist entry in Everyday |
| Task linked to exactly one Event | Item in that Event entry's checklist |
| Task linked to ≥ 2 Events, or none | Stays in "Our to-dos" |
| Event | Everyday entry (id = event id) · Date block · Text block (note) |
| Note | **Notes** entry (id = note id) · Text block (plain text → single-insert Delta). Amended 2026-10-12: v1 notes go to the Notes starter, not Everyday (§15). |
| Soft-deleted v1 rows | Migrated as soft-deleted (retention clock starts at the original `deleted_at`) |

### 9.2 Contracts preserved
- `create_planning_from_assist_message`: same signature and return shape; body writes v2 (task → item in "Our to-dos"; event → Everyday entry). AI client code unchanged.
- `list_planning_calendar_entries`, `get_planning_summary`: same output shape; read v2 Date blocks and dated checklist items. Timeline and Conversations Flutter code unchanged.
- v1 write RPCs (`create_planning_task`, `create_planning_goal`, `add_planning_goal_task`, `update_planning_item`, `set_planning_task_completion`, `delete_planning_item`, `upsert_planning_event`, `delete_planning_event`, `link_planning_event_task`, `unlink_planning_event_task`, `upsert_planning_note`, `delete_planning_note`) become a **compatibility shim** writing v2 for one release, so installed old app versions keep working. v1 list RPCs read v2 and return v1 shapes.

### 9.3 Procedure
1. One migration, one transaction: copy v1 → v2 (idempotent `ON CONFLICT (id) DO NOTHING`), swap RPC bodies, revoke writes on the v1 tables.
2. Reconciliation query inside the migration test: every live and soft-deleted v1 row maps to exactly one v2 row; zero unmapped; counts per relationship equal.
3. v1 tables stay (read-only) for one release; a later migration drops them.

### 9.4 Rollback (checklist 8.1, Tier 2)
Runbook in `docs/superpowers/planning-v2-rollback.md`: restore v1 RPC bodies (statements checked in), re-grant v1 writes, and copy back v2 rows created since the migration by the reverse mapping script. The script is tested locally against the migration fixture.

## 10. Client architecture

- `lib/features/planning/` restructured into `data/` (models, repository, error mapping), `domain/` (pure logic: split arithmetic, position keys, Delta whitelist mirror, outbox), `presentation/`.
- Riverpod: `planningHomeProvider`, `planningEntriesProvider(categoryId)` (paginated `AsyncNotifier`), `planningEntryProvider(entryId)`. The change signal invalidates whichever are alive.
- Optimistic updates where the inverse is unambiguous (tick, vote, reorder, delete); replaced by the authoritative result; rollback on failure.
- **Offline outbox** (checklist ticks and item adds only): persisted, capped at 200 ops, each with an op UUID. Replay uses exponential backoff with full jitter (base 500ms, max 30s, 6 attempts), then surfaces "Couldn't sync n items" with Retry. Permanent errors (`not_found`, `invalid_input`, `inactive`) drop the op and show it, without retrying.
- **Conflict sheet** on `stale_version`: "Kofi just changed this" with Keep mine / Use theirs / Copy mine. The local draft is retained until resolved.
- No change to `main.dart`. Router: new routes for category and entry under the existing Planning branch only. Shared widgets: none modified.

## 11. Delivery

| Sub-project | Scope | Gate |
|---|---|---|
| **P1 Foundation** | Tables, RLS, storage, limits, categories, templates, entries, Text (rich) / Checklist / Date blocks, editor shell, tool tray, outbox, conflict sheet | v1 untouched and still serving; v2 behind route only reachable in debug builds |
| **P2 Migration** | §9 complete; v2 becomes the Planning UI | Golden test: Timeline / summary / AI outputs identical pre/post |
| **P3 Rich blocks** | Table, Photo, Link (+ edge function), Place, Expenses, Budget, audit table | SSRF suite green; money mutation tests |
| **P4 Couple blocks** | Date poll, Countdown, Progress, Dual clock, notifications, gallery templates | Notification idempotency tests |

Each sub-project: its own plan, subagent-driven execution, per-task review, and a **whole-branch review before merge**. Migrations use the `20261012200000+` range. Games uses `20261012100000+`.

## 12. Algorithm Quality Review Checklist v3.1 — conformance

Context: **[MUTATION] [UI] [MOBILE] [SERVICE] (edge function + RPCs) [ASYNC] (pg_cron jobs) [FIN] (expense records only; no money movement) [BATCH] (P2 migration)**. Note: the checklist's summary says 84 checks; it numbers 96. All 96 are covered below.

### Phase 1 — Design
| # | Status | Where / evidence |
|---|---|---|
| 1.1 | Met | Client UUIDs; op_id on ticks; `version` on updates (§3, §6.2) |
| 1.2 | Met | Link preview 1s/3s; Mapbox and storage calls get explicit client timeouts in the plan (§7.1) |
| 1.3 | Met | Link → plain card; Mapbox → free text; dual clock → hidden; offline → outbox (§6, §10) |
| 1.4 | Met | Membership checked per RPC on the resolved row; composite FKs (§3, §7.2) |
| 1.5 | Met | Supabase JWT; edge function verifies the user (§7.1) |
| 1.6 | Met | Item-level rows; fixed lock order; template unique index; version checks (§3, §7.2) |
| 1.7 | Met | Stateless RPCs and edge function; state in Postgres |
| 1.8 | Met | Entry read O(b + i) with b ≤ 200, i ≤ 200×500 bounded; reorder O(1) amortized (§3.7) |
| 1.9 | Met | Server-authoritative; eventual across partners; read-your-writes locally (§3.8, §10) |
| 1.10 | Met | Template copy, duplicate, poll lock, settle: each one transaction (§4, §6) |
| 1.11 | Met | PII: photos (EXIF stripped), places, notes. Retention 30 days post-delete. URLs host-only in logs (§3.10, §6.10) |
| 1.12 | Met | Estimate in plan P1 task 1: rows per active couple, storage per couple |

### Phase 2 — Implementation
| # | Status | Where / evidence |
|---|---|---|
| 2.1 | Met | Per-type payload validation; Delta whitelist; length/range CHECKs; magic-byte-safe re-encode |
| 2.2 | Met | PL/pgSQL with bound parameters; no dynamic SQL; grep gate for `EXECUTE format` in plan |
| 2.3 | Skip | No secret comparison in this feature |
| 2.4 | Met | Typed codes only; `not_found` for forbidden |
| 2.5 | Met | §3.11 limits; HTML/image read caps |
| 2.6 | Met | Scheme allow-list; og text stripped; Delta whitelist; no HTML rendering |
| 2.7–2.9 | Met | Mapbox token via existing env config; no new secrets |
| 2.10 | Met | Edge function: `try/finally` on fetch body readers and abort controllers; Flutter: editors and controllers disposed |
| 2.11 | Met | Supabase client pooling (existing) |
| 2.12 | Met | Outbox replay serial; preview function single fetch per request |
| 2.13 | Met | AbortController on timeout; Dart cancellation on dispose |
| 2.14 | Met | Outbox ≤ 200; signed-URL cache LRU 200; preview cache TTL 7d |
| 2.15 | Met | No unbounded loops; server loops bounded by limits |
| 2.16 | Met | Row locks; disjoint item rows |
| 2.17 | Met | `domain/` pure Dart (split, positions, outbox, Delta mirror) |
| 2.18 | Met | See 1.1 |
| 2.19 | Met | bigint minor units; grep gate for `double`/`/ 100` in money paths |
| 2.20 | Skip | No payment provider |
| 2.21 | Skip | No webhooks |
| 2.22 | Met | `planning_expense_events` append-only (§3.6) |
| 2.23 | Skip | Nothing external to reconcile |

### Phase 3 — Performance
| # | Status | Where / evidence |
|---|---|---|
| 3.1 | Met | Entries cursor-paginated (§3.11) |
| 3.2 | Met | `get_planning_entry` single call |
| 3.3 | Met | Indexes §3; EXPLAIN captured in P1/P2 plans |
| 3.4 | Met | Provider cache invalidated by change signal; preview cache TTL |
| 3.5 | P3 backlog | — |
| 3.6 | Met | Outbox replays in batches of ≤ 20 |
| 3.7 | Met | Bounded outbox; rate-limited previews |
| 3.8 | Met | 30/min on previews; RPC writes bounded by limits (no new public endpoint) |
| 3.9 | Met | Outbox backoff + jitter (§10) |
| 3.10 | Met | Permanent codes not retried |
| 3.11 | P3 backlog | — |
| 3.12 | Met | Edge runtime handles shutdown; requests are short and idempotent |
| 3.13 | P3 backlog | — |

### Phase 4 — Observability
| # | Status | Where / evidence |
|---|---|---|
| 4.1 | Met | Edge function JSON logs at entry/exit/decision |
| 4.2 | Met | `request_id` per request, echoed in error body |
| 4.3 | P3 backlog | — |
| 4.4 | Met | No note text, URLs (host only), names, coordinates in logs |
| 4.5 | Met | ERROR only for unexpected failures; SSRF rejections WARN |
| 4.6–4.10 | Partial | Follows repo practice: Supabase function metrics and logs. A dashboard and alert definitions are a separate ops task, recorded as a gap, not claimed |
| 4.11 | Met | `planning_limits()` + Dart mirror |
| 4.12–4.13 | Skip | Managed Supabase runtime; no custom health endpoint in repo practice |
| 4.14 | Met | Outbox ops that exhaust retries are kept and surfaced, not dropped silently |

### Phase 5 — UX
| # | Status | Where / evidence |
|---|---|---|
| 5.1 | Met | Code → actionable message table in plan |
| 5.2 | Met | Single-RPC entry read; optimistic ticks; benchmark in P1 |
| 5.3 | Met | Skeleton on first load; retained content on refresh |
| 5.4 | Met | Outbox and conflict sheet state when retry is safe |
| 5.5 | Met | See 2.4 |
| 5.6 | Met | §5 accessibility rules |

### Phase 6 — Testing
| # | Status | Where / evidence |
|---|---|---|
| 6.1 | Met | Empty / max limits, Unicode titles, odd-minor-unit splits, date ranges across DST and year end, time zones |
| 6.2 | Met | Preview timeout / private IP / oversized; Mapbox down; offline replay; relationship ended mid-edit |
| 6.3 | Met | Concurrency scripts: simultaneous ticks; template race; reorder race; settle vs add expense |
| 6.4 | Met | No audit row on failed expense write; no partial template copy; no double push |
| 6.5 | Met | Property tests: position keys always sort between neighbours; split sums equal total |
| 6.6 | Met | Deterministic rounding rule; seeded tests |
| 6.7 | Met | Branch coverage ≥ 90% `domain/`, ≥ 70% adapters |
| 6.8 | Met | Mutation testing on split arithmetic, Delta validator, position keys |
| 6.9 | Met | Entry read benchmark at max limits |
| 6.10–6.12 | Partial | No soak/load/chaos infrastructure in repo; recorded as a gap. Bounded limits are the mitigation |
| 6.13 | Met | This spec + inline intent comments |
| 6.14 | Partial | Rollback runbook (§9.4); alert runbooks follow when 4.9 lands |

### Phase 7 — Security
| # | Status | Where / evidence |
|---|---|---|
| 7.1 | Met | `flutter pub outdated`/advisory check for `flutter_quill` before adding |
| 7.2 | Met | `flutter analyze` 0 errors; `deno lint`/`deno check` |
| 7.3 | Met | Secret scan on branch before merge |
| 7.4 | Met | RPC grants to `authenticated` only; service role only for cron jobs |
| 7.5 | Met | Supabase TLS; preview fetches https-preferred, http allowed for preview only |
| 7.6 | Skip | Native mobile only |
| 7.7 | Partial | Repo CI practice; no new scanner added |

### Phase 8–9 — Post-deployment and improvement
| # | Status | Where / evidence |
|---|---|---|
| 8.1 | Met | Tier 2 runbook (§9.4) |
| 8.2 | Met | Manual smoke script per sub-project (create entry from each template, tick offline, split settle) |
| 8.3 | Partial | Supabase logs reviewed for 24h; no metrics dashboard (see 4.6) |
| 8.4, 9.1–9.3 | Process | Owned by the repo maintainer |

## 13. Out of scope (v2)

Event times and durations; external calendar sync; currency conversion; recurrence engine; presence/live cursors; per-character merging of text; restore UI; per-person totals outside a split entry; body metrics; AI-generated plans (a later feature can write blocks through the same RPCs).

## 14. Acceptance criteria

1. A couple sees five starters on first open; Everyday appears only when non-empty.
2. Every starter and gallery template creates an entry whose blocks match §4.1.
3. Two devices ticking different items of one checklist simultaneously both persist.
4. Editing the same text block on two devices never loses text; the second save shows the conflict sheet.
5. Ticks made offline sync after reconnect, exactly once.
6. An odd-amount equal split rounds deterministically; settling resets the balance; every expense change has an audit row that cannot be updated.
7. A link to a private IP, a metadata address, or a host that rebinds to one is never fetched.
8. After P2, Timeline, the Conversations summary and AI-created items behave identically for migrated data.
9. Date poll and countdown pushes are delivered once per rule.
10. No screen shows a per-partner money total outside an entry with split enabled.

## 15. Amendment (2026-10-12): Notes and pins

Approved in conversation after P1 merged. Implemented on `feat/planning-notes-pins` with migration `20261012200600_planning_v2_notes_and_pins.sql`.

- **Notes starter:** a seventh starter category (`seed_key = 'notes'`, rank 0), always first on the home screen. Like the other starters it can be renamed or hidden but not deleted. Its template is one empty text block: a blank sheet. The Notes category has no template UI (no "Edit template" / "Reset template"). **+ New note** skips the template choice, creates the note titled "New note", and opens the editor at once. On the first save, a note still titled "New note" takes its first non-empty line as its title.
- **Seeding fix (final review M2):** a starter missing for a couple is placed relative to that couple's existing categories. One ranked before all of their starters goes to the top; otherwise it goes after the last category. Couples seeded before Notes existed get it at the top.
- **Pins:** `planning_entries.pinned_at`, shared by both partners, at most 20 per category (`pinned_per_category` in `planning_limits()`), counted under the category row lock. `list_planning_entries` returns pinned plans in a separate `pinned` group on the first page only (by `pinned_at DESC`, within the requested status group) and never in the keyset-paged `entries`. Templates cannot be pinned.
- **Swipe gestures, consistent across Planning:** swiping **right deletes** (with Undo) for plans, blocks and checklist items. Swiping **left** on a plan pins or unpins it and leaves it on screen. Long-press and screen-reader custom actions offer Pin/Delete too.
- **Undo for a deleted plan:** `restore_planning_entry` restores the plan and exactly the blocks and items that delete removed (matched on its `deleted_at`). It never restores ones deleted earlier on their own, and it refuses to restore into a deleted category.

## 16. Amendment (2026-10-12): P2 replaces v1 outright

Decided by the user after P1 and Notes & pins merged: the app is in development, the user is its only tester, and there is no v1 data worth keeping. This supersedes §9's data copy, compatibility shim and preview stage.

- **No data copy and no compatibility layer.** The v1 tables (`planning_items`, `planning_events`, `planning_event_tasks`, `planning_notes`) and every v1 RPC are dropped. `planning_change_signals` and `bump_planning_signal` stay, because v2 uses them.
- **No flag or gate.** The `PLANNING_V2_PREVIEW` define and the v1 screens are deleted. The `/planning` route opens the new Planning home, which keeps the Planning / Calendar tabs.
- **No "v2" naming in the app.** `lib/features/planning/v2/*` becomes `lib/features/planning/*`, and Dart identifiers drop the `V2` (`PlanningV2Repository` becomes `PlanningRepository`, and so on). SQL helper names (`planning_v2_*`) are internal and keep their names.
- **Ask Attune → Planning.**
  - `ai_assist_planning_links` points at one v2 plan (`planning_entry_id`, FK to `planning_entries`). Existing link rows point at v1 data, so they are deleted.
  - `create_planning_from_assist_message(p_message_id, p_edited_title, p_edited_date)` keeps its checks: auth, Attune-Assist origin, active membership, idempotency via the link. It returns `TABLE (planning_entry_id uuid)`:
    - a suggested **task** becomes an Everyday plan titled with the task, holding a "To do" checklist whose single item carries the date as its due date;
    - a suggested **event** becomes an Everyday plan with a Date block.
  - Either way, "Add to Planning" can open the plan.
- **Calendar feed.**
  - `list_planning_calendar_entries(p_relationship_id, p_start_date, p_end_date)` keeps its 42-day bound. It becomes SECURITY DEFINER with the v2 membership check, since v2 tables have no client grants.
  - It returns `entry_kind` (`date` | `item`), `entry_id` (the plan to open), `item_id`, `entry_date`, `title` and `is_complete`.
  - Date blocks appear on every day of their range inside the window; dated checklist items appear on their due date.
- **Conversations summary.** `get_planning_summary(p_relationship_id, p_today)` returns `kind` (`overdue` | `upcoming` | `recent`), `entry_id`, `title` and `context_date`. The order of preference is:
  1. the oldest overdue unticked item;
  2. otherwise the soonest upcoming dated item or date;
  3. otherwise the most recently active plan;
  4. otherwise no row, and the card reads "Start planning together".


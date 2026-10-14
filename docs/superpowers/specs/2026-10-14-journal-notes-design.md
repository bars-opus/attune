# Reflection Journal as notes — design

**Status:** approved in conversation 2026-10-14 (sections 1–3); awaiting written-spec review.
**Builds on:** `docs/superpowers/specs/2026-08-02-reflection-journal-design.md` (the journal's purpose and §3 non-negotiables, which all still hold) and Planning v2's notes (`PlanningCategoryScreen`, `PlanningEntryScreen`).

## 1. What changes, in one paragraph

A journal entry stops being a single plain-text field. It becomes a note: a title, then an ordered list of blocks. A block is either text (formatted like Planning notes) or a private photo. Text is edited in place with the notes ribbon and saved automatically. The Entries tab is grouped like the notes list: Pinned, Today, Yesterday, Previous 7 Days, Previous 30 Days, months, then years. Each group is a card of rows. Everything stays private to the writer. The AI observation and the Patterns tab keep working from the entry's plain text.

## 2. Owner decisions (2026-10-14)

- **Structure:** like notes. Grouped list, editor opens straight from `+`, title, formatting ribbon, autosave, and an empty entry is discarded.
- **Scope:** rich text **plus photos**. No other note blocks: no tables, dates, links, places, expenses, budgets, polls, countdowns, progress or clocks.
- **Approach:** share the note editor's generic parts, not a copy. Planning's tests guard Planning.

## 3. Non-negotiables (inherited, unchanged)

All of the 2026-08-02 spec's §3 still applies:
- no streaks, badges or counts;
- no re-engagement notifications;
- banned words;
- every AI claim sourced to the writer's own words, with confidence capped at medium;
- **never shared with a partner, never in a couple-level view, never used as evidence**;
- fully editable and permanently deletable;
- the "wise, attentive friend" voice;
- no paywall.

Added by this design:

- **Owner-only storage.** New tables, server functions and the photo bucket carry no `relationship_id` and give no partner path. A contract test pins this.
- **The AI never sees photos or titles,** only the plain text of the writing.
- **Delete is real.** After the Undo window, the entry, its observation and its photos are removed. That honours the existing "permanently removed" copy, which the current soft delete does not.

## 4. Data model

### 4.1 Entries: `reflection_journal_entries` (existing table, extended)

- Add `title text NULL` (at most 120 characters), `pinned_at timestamptz NULL`, and `version int NOT NULL DEFAULT 1` (bumped on every structural change).
- `content` stays and becomes **server-derived**. It holds the plain text of the text blocks, in order, joined by blank lines. Every block write recomputes it, so `analyse-journal-entry`, the Patterns tab and the Conversations "latest reflection" line keep reading `content` unchanged. Its `CHECK (char_length(content) > 0)` is relaxed to allow `''`, because a new entry is empty until written.
- `prompt_used`, `tone` and the timestamps are unchanged. `created_at` is the date the entry was written.

### 4.2 Blocks: `reflection_journal_blocks` (new)

| column | notes |
|---|---|
| `id uuid PK` | |
| `entry_id uuid` | FK → entries, `ON DELETE CASCADE` |
| `user_id uuid` | FK → users, `ON DELETE CASCADE`; equals the entry's owner |
| `position int` | order within the entry |
| `kind text` | `text` or `photo` |
| `payload jsonb` | text: `{"delta": [...]}`, validated by the same whitelist as Planning (`planning_validate_delta`), ≤ 16 384 bytes. Photo: `{"path": "<user_id>/<entry_id>/<uuid>.jpg", "w": int, "h": int}` |
| `plain_text text` | text blocks only, server-computed, ≤ 10 000 characters |
| `version int` | optimistic concurrency per block (multi-device) |
| `created_at`, `updated_at` | |

Limits per entry: at most 50 blocks and at most 10 photos.

### 4.3 Access

- RLS is on. `authenticated` gets SELECT only, on rows where `user_id = auth.uid()`; nothing else is granted.
- All writes go through `SECURITY DEFINER` functions that check `auth.uid()` owns the entry:
  - `create_journal_entry_v2(p_prompt_used)`: creates the entry with one empty text block and returns the entry.
  - `get_journal_entry(p_entry_id)`: returns the entry plus its blocks.
  - `list_journal_entries(p_before, p_limit)`: returns summaries (title, first ~80 characters, `has_photo`, dates, pinned, tone), paged by `created_at`, with pinned entries separate on the first page.
  - `rename_journal_entry`.
  - `save_journal_text(p_block_id, p_version, p_delta)`: validates the delta, recomputes the block's `plain_text` and the entry's `content`, bumps the version, and raises a `conflict` error on a stale version.
  - `insert_journal_block(p_entry_id, p_after, p_kind, p_payload)`: also splits a text block when inserting mid-paragraph, as notes do.
  - `delete_journal_block`, `move_journal_block`, `set_journal_pin`.
  - `delete_journal_entry`: a soft delete with `deleted_at`, used for the Undo window.
  - `restore_journal_entry`.
  - `purge_journal_entry`: a hard delete; blocks and analysis cascade.
  - `purge_my_deleted_journal_entries()`: hard-deletes the caller's entries soft-deleted more than 10 minutes ago, so nothing lingers if the app was closed mid-Undo.
- The old `create_journal_entry` and `update_journal_entry` stay working for one release (older app builds). `update_journal_entry` rewrites the entry as a single text block.

### 4.4 Photos

- New private bucket `journal-media`. Storage policies allow read and write only where the first path segment equals `auth.uid()`.
- The app shows photos through short-lived signed URLs, and compresses before upload as Planning photos do.
- A `BEFORE DELETE` trigger on photo blocks calls the existing `queue_media_deletion('journal-media', path)`, which the scheduled `process-media-deletion-queue` drains. Cascades fire it too, so purging an entry and **deleting the account** both remove the files.

### 4.5 Existing entries

The migration backfills one text block per existing entry, with delta `[{"insert": content + "\n"}]`, and leaves `title` null. Existing analysis rows stay valid, because `content` is unchanged.

## 5. Shared editor parts (refactor)

These move from `lib/features/planning/` to a shared place, `lib/core/notes/`. Behaviour is unchanged, and Planning imports them from there:

- the Quill config and scope (`planning_quill.dart`), the delta sanitizer and `deltaPlainText`;
- the doc controller and scope (active block, selection, block motion);
- the ribbon (Home tab plus an Insert tab given its tool list);
- the date sections (`planningDateSections` and `planningRowDate`, generalised over a date and a key);
- the grouped section card (`_Section`: header, `CardInkWell`, rows);
- the conflict sheet.

The text block saves through a small interface:

```dart
abstract class NoteTextSaver {
  Future<NoteSaveResult> saveText(String blockId, int version, List ops);
  // ok(newVersion) | conflict(theirOps, theirVersion) | failed
}
```

Planning supplies an implementation backed by `planningEntryProvider`, and the journal supplies one backed by its repository. Planning's existing tests must pass **without edits**; any change to them is a red flag to raise, not to make.

## 6. Screens

### 6.1 Entries tab

- Groups are Pinned, Today, Yesterday, Previous 7 Days, Previous 30 Days, month names (this year) and years, keyed by **`created_at`** (the day it was written), not the last edit.
- Each group is a header over a `CardInkWell` of `InfoRowWidget` rows, with dividers between rows.
- Each row shows:
  - **title:** the entry's title, or for an untitled entry its date (e.g. "Tuesday, 14 October");
  - **subtitle:** the row date (the time for today, "Yesterday", the weekday within 7 days, otherwise the date), two spaces, then the first words;
  - **photo marker:** a small trailing photo icon when the entry has a photo.
- Gestures are as in notes: swipe right deletes with an Undo snackbar, swipe left pins or unpins, long-press opens Pin, Delete. Each also has a semantics action.
- Loading shows a skeleton list. Pages load on scroll. Errors show the existing error state with retry. The empty state keeps today's copy ("…Nothing here is ever shared with anyone.").
- The FAB `+` creates an entry and opens the editor, focused on the first block. Leaving a new entry that is still empty (no title, no text, no photo) deletes it outright.

### 6.2 Entry screen (replaces compose and detail)

- **Title:** an in-place title at the top, at most 120 characters, saved when focus leaves it. An untitled entry takes its first line when first saved, as notes do. The placeholder is the entry's date.
- **Prompt:** a new entry shows the random prompt card above the text, with a working dismiss. The shown prompt is stored as `prompt_used`.
- **Blocks:** text blocks use the notes editor and ribbon. Home has headings, sizes, bold, italic, underline, strike, highlight, colour, bullet and numbered lists, checklists, quotes and alignment. Insert has only **Text** and **Photo**. Blocks are reorderable by drag, and a photo block can be removed.
- **Autosave:** one second after the last keystroke, when focus leaves, and when the screen closes. A stale version opens the existing conflict sheet (keep mine, use theirs).
- **Reflection card:** under the blocks, when an observation exists, a quiet card shows the tone and "A reflection". Opening an entry only **reads** the stored analysis; it never calls the AI.
- **Menu:** Pin or Unpin, and Delete (with the existing confirmation copy, then purge).

### 6.3 Analysis trigger

When the entry screen closes, if any text changed during the visit, the app calls `analyse-journal-entry` once, without waiting. The function's `input_hash` dedupe and 15-word minimum stay as they are. The edge function is unchanged, apart from reading `content`, which it already does.

### 6.4 Other consumers

- **Conversations "latest reflection" row:** shows the title when present, otherwise the first words of `content`.
- **Local cache:** now stores list summaries only (title, first words, dates, flags), never full text. It is still cleared at sign-out.

## 7. Error handling

- **Offline:** a save failure keeps the text, shows the sync chip, and retries on the next change or focus loss, as Planning text blocks do.
- **Photo upload failure:** the block shows "Couldn't add this photo — try again" with retry and remove, and nothing half-saved remains. The block row is created only after the upload succeeds.
- **Over a limit** (block size, 50 blocks, 10 photos): the action is refused with a plain message, and nothing is lost.
- **Purge failure:** the next visit's `purge_my_deleted_journal_entries()` retries it.

## 8. Testing

- **TDD throughout:** each behaviour gets a failing test first.
- **SQL contracts** (local PG17 harness):
  - another user, including the partner, can't read, write, insert, rename, pin or purge;
  - `content` is recomputed from blocks;
  - limits are enforced;
  - the backfill gives one block per entry with identical `content`;
  - the photo trigger queues deletion, including through an account cascade;
  - the legacy RPCs still work;
  - no `relationship_id` column exists in the journal tables.
- **Dart:**
  - date grouping keyed by `created_at`;
  - rows and gestures;
  - empty-entry discard;
  - title from the first line;
  - autosave, version handling and conflict through `NoteTextSaver`;
  - adding a photo (upload then block) and the failure state;
  - removing a photo;
  - analysis called exactly once on close and only after a change;
  - opening an entry never calls the AI;
  - the delete, Undo and purge flow;
  - the cache holds no full text.
- **Regression guard:** the whole Planning suite passes unchanged after the shared-parts refactor.

## 9. Out of scope

Search, export, sharing, streaks or counts of any kind, other note blocks (tables, polls and the rest), AI reading photos or titles, and reminders to write.

## 10. Plan rulings (plan `2026-10-14-journal-notes.md`)
- R1: The shared editor pieces keep their Planning paths (Planning's tests import them there); only the date grouping and the section card moved to `lib/core/notes/`. The text block is `NoteTextBlock` (with `InlineTextBlock` a thin Planning subclass).
- R2: No entry-level version; per-block versions cover text from two devices, structural changes reload.
- R3: A photo block stores only its path; photos show in a 4:3 frame and open full size.
- R4: A failed photo upload is a snackbar with Retry; the block is created only after the upload.
- R5: An entry's only block can't be deleted.
- R6: The backfill splits text over 3,000 characters into several blocks — at a paragraph break, else a line break, else a space (never mid-word); content is unchanged, and a later save rebuilds the same text.
- R7: One `journalEntry` route replaces compose and detail.

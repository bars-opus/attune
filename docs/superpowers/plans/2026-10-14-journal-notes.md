# Reflection Journal as notes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A journal entry becomes a note, with a title plus text and photo blocks edited with the notes editor. The Entries tab is grouped like Planning's notes list. Everything stays owner-only.

**Architecture:**
- **Database:** an owner-only `reflection_journal_blocks` table, with writes through `SECURITY DEFINER` RPCs. `content` stays the server-derived plain text that the AI reads.
- **Shared text block:** Planning's text block becomes a generic `NoteTextBlock` behind a `NoteTextSaver` interface. Planning and the journal each supply a saver.
- **Shared list parts:** the date grouping and the grouped section card move to `lib/core/notes/`.
- **Journal app layer:** a new paged list notifier and a per-entry controller, with photos in a private `journal-media` bucket.

**Tech Stack:** Flutter 3.29 / Riverpod 2 / GoRouter, flutter_quill 11.5, Supabase Postgres 17 (plpgsql, RLS), the local PG17 contract harness.

**Spec:** `docs/superpowers/specs/2026-10-14-journal-notes-design.md`. The journal's original non-negotiables are in `docs/superpowers/specs/2026-08-02-reflection-journal-design.md` §3.

## Global Constraints

- The journal is **never shared with a partner, never in a couple-level view, never evidence**. It has no `relationship_id` anywhere and no partner path in any RPC, policy or bucket.
- **No streaks, badges or counts**, and no reminders to write.
- **Delete is real:** after the Undo window, the entry, its analysis and its photos are removed.
- **The AI reads only `content`,** the plain text of the text blocks. It never reads titles or photos.
- **Limits:**
  - a text block: 10 000 characters of plain text and a 16 384-byte payload;
  - an entry: at most 50 blocks and 10 photos;
  - a title: at most 120 characters.
- **Planning's tests must pass without edits.** If one would need changing, stop and report it.
- Owner rules: work on main, write each test first and watch it fail, make no commits. Re-read a file before editing it, because the owner edits by hand. Flag regression risk in shared files.

### Rulings (record them in the spec as §10 in Task 6)

- **R1: shared pieces keep their Planning paths.** Planning's tests import `inline_text_block.dart`, `planning_ribbon.dart`, `delta_sanitizer.dart` and `planning_ui.dart`. So the Quill config, sanitizer, doc controller, ribbon and conflict sheet stay in Planning's folders, and the journal imports them from there.
  - Only the date grouping (`noteDateSections`) and the section card (`NoteSection`) move to `lib/core/notes/`.
  - The text block becomes `NoteTextBlock`, kept in Planning's widgets folder beside its dependencies. `InlineTextBlock` becomes a thin subclass, plus a `typedef InlineTextBlockState`.
  - *Cost if wrong:* a later move into a shared folder.
- **R2: no entry-level `version`** (spec §4.1). Per-block versions cover text from two devices, and structural changes reload the entry. *Cost if wrong:* one column.
- **R3: a photo block's payload is `{"path": …}` only.** Photos show in a 4:3 frame and open full size. *Cost if wrong:* adding w/h later.
- **R4: a failed photo upload is a snackbar with Retry.** The block row is only created after the upload succeeds, so nothing is ever half-saved. *Cost if wrong:* an in-place error block later.
- **R5: deleting an entry's only block is refused (`journal:last_block`).** *Cost if wrong:* none.
- **R6: the backfill splits text over 3 000 characters into several blocks,** to stay under the server limits. The entry's `content` is unchanged.
- **R7: one route, `journalEntry`, replaces `journalEntryCompose` and `journalEntryDetail`.**

## Review Focus

1. **Typing and leaving within the 1-second debounce.** The text is saved, and the AI runs once *after* that save lands, not on the old text. Pinned in Task 5: "leaving right after typing saves, then reflects once".
2. **Opening an old (backfilled) entry and leaving without changes.** No rename, no save and no AI call. Pinned in Task 5: "reading an entry never calls the AI".
3. **The same entry edited on two devices.** The second save meets the conflict sheet titled for this person, never a silent overwrite. Pinned in Task 5: "a stale save asks before overwriting".
4. **A photo while offline or failing.** No photo block appears, and Retry works. Pinned in Task 5: "a failed upload adds nothing and offers Retry".
5. **Delete, Undo window, app closed.** The entry is gone on the next visit, and its photos are queued for deletion. Pinned by Task 1's SQL purge, sweep and cascade checks, and Task 4's "opening the journal sweeps old deletions".

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `supabase/migrations/20261014190000_journal_notes.sql` | Create | Columns, blocks table, RLS, helpers, RPCs, photo trigger, legacy RPCs, backfill |
| `supabase/migrations/20261014200000_journal_media_bucket.sql` | Create | Private `journal-media` bucket and owner-only storage policies |
| `supabase/tests/journal_notes_contracts.sql` | Create | SQL contracts |
| `<scratchpad>/pg/stubs.sql`, `<scratchpad>/pg/run.sh` | Modify (not committed) | Harness: a `set_updated_at` stub; apply the journal, media-queue and planning-helper migrations |
| `lib/core/notes/note_date_sections.dart` | Create | `noteDateSections<T>`, `noteRowDate` |
| `lib/core/notes/note_section.dart` | Create | `NoteSection` (title plus a CardInkWell of rows) |
| `lib/features/planning/presentation/planning_ui.dart` | Modify | `planningDateSections` and `planningRowDate` delegate |
| `lib/features/planning/presentation/screens/planning_category_screen.dart` | Modify | `_Section` → `NoteSection` |
| `lib/features/planning/presentation/widgets/note_text_block.dart` | Create | `NoteTextBlock`, `NoteTextSaver`, `NoteSaveResult` |
| `lib/features/planning/presentation/widgets/inline_text_block.dart` | Rewrite | `InlineTextBlock` subclass, `PlanningTextSaver` |
| `lib/features/planning/presentation/widgets/planning_ribbon.dart` | Modify | Optional `tools` |
| `lib/features/planning/presentation/widgets/conflict_sheet.dart` | Modify | Optional `title` |
| `lib/features/reflection_journal/data/models/journal_entry.dart` | Modify | `title`, `pinnedAt`, `copyWith`, `journalSnippet`, `journalRowTitle` |
| `lib/features/reflection_journal/data/models/journal_note.dart` | Create | `JournalBlock`, `JournalEntryDetail`, `JournalEntrySummary`, `JournalListPage` |
| `lib/features/reflection_journal/data/repositories/reflection_journal_repository.dart` | Modify | v2 RPCs and error mapping |
| `lib/features/reflection_journal/data/journal_media.dart` | Create | `JournalMediaGateway` |
| `lib/features/reflection_journal/data/cache/reflection_journal_cache.dart` | Modify | Summaries only (schema 2) |
| `lib/features/reflection_journal/presentation/providers/reflection_journal_providers.dart` | Modify | List notifier, entry controller, media providers; drop compose/detail providers |
| `lib/features/reflection_journal/presentation/widgets/journal_text_saver.dart` | Create | `JournalTextSaver`, `JournalVisit` |
| `lib/features/reflection_journal/presentation/widgets/journal_photo_block.dart` | Create | Photo block view |
| `lib/features/reflection_journal/presentation/widgets/journal_entry_row.dart` | Create | List row with gestures |
| `lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart` | Modify | Grouped Entries tab; FAB creates and opens |
| `lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart` | Create | The entry (note) screen |
| `lib/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart`, `journal_entry_detail_screen.dart`, `widgets/journal_entry_card.dart` | Delete | Replaced |
| `lib/app/routing/app_router.dart` | Modify (shared) | `journalEntry` route replaces two |
| `lib/features/chat/presentation/screens/conversations_screen.dart` | Modify (shared) | Latest-reflection row uses `journalRowTitle` |
| Tests | Create/modify | `test/core/notes/…`, `test/features/reflection_journal/…` |

**Regression risk to flag:**
- **Planning's text block, ribbon, conflict sheet, date sections and category list are refactored.** The whole Planning suite is the guard and must pass with no test edits.
- **`app_router.dart` loses two routes and gains one.** Nothing else navigates to the two removed routes; Task 5 greps to confirm.
- **`conversations_screen.dart`:** only the row title changes.

---

### Task 1: Database — blocks, RPCs, photos, backfill

**Files:**
- Create: `supabase/migrations/20261014190000_journal_notes.sql`
- Create: `supabase/migrations/20261014200000_journal_media_bucket.sql`
- Create: `supabase/tests/journal_notes_contracts.sql`
- Modify (harness, not committed): `<scratchpad>/pg/stubs.sql`, `<scratchpad>/pg/run.sh`

**Interfaces:**
- Produces these RPCs (all owner-only, errors `journal:<code>`):
  - `create_journal_entry_v2(p_prompt_used text) → jsonb {entry, blocks, analysis}`
  - `get_journal_entry(p_entry_id uuid) → jsonb {entry, blocks, analysis}`
  - `list_journal_entries(p_before timestamptz, p_limit int) → jsonb {pinned:[summary], entries:[summary], has_more}`. A summary is `{id, title, snippet, has_photo, pinned, tone, created_at, updated_at}`.
  - `rename_journal_entry(p_entry_id, p_title) → jsonb entry`
  - `set_journal_pin(p_entry_id, p_pinned boolean) → void`
  - `save_journal_text(p_block_id, p_version int, p_delta jsonb) → jsonb {status:'saved'|'conflict', block}`
  - `insert_journal_block(p_entry_id, p_after uuid, p_kind text, p_payload jsonb) → jsonb block`
  - `delete_journal_block(p_block_id) → void`
  - `move_journal_block(p_block_id, p_to int) → void`
  - `restore_journal_entry(p_entry_id) → void`
  - `purge_journal_entry(p_entry_id) → void`
  - `purge_my_deleted_journal_entries() → int`
- A block's JSON is `{id, entry_id, position, kind, payload, plain_text, version, created_at, updated_at}`.
- The legacy `create_journal_entry`, `update_journal_entry` and `delete_journal_entry` keep their signatures.

- [ ] **Step 1: Prepare the harness**

Add this at the end of `<scratchpad>/pg/stubs.sql`:

```sql
CREATE OR REPLACE FUNCTION public.set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
```

In `<scratchpad>/pg/run.sh`, add these names to the front of the first `for m in …` list. They then apply before the `202610141[1-9]*` glob, which picks up `20261014190000_journal_notes`:

```
20260813120000_reflection_journal 20260930120000_media_deletion_queue 20261012200100_planning_v2_helpers
```

The bucket migration, `20261014200000_…`, is outside that glob on purpose, because the harness has no `storage` schema.

- [ ] **Step 2: Write the failing contracts**

`supabase/tests/journal_notes_contracts.sql`:

```sql
-- Journal as notes contracts (spec 2026-10-14-journal-notes-design.md). Every check RAISEs on violation.
BEGIN;
INSERT INTO auth.users (id) VALUES ('8a100000-0000-0000-0000-0000000000a1'), ('8a100000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8a100000-0000-0000-0000-0000000000a1', '+233350000001', 'Ama'),
  ('8a100000-0000-0000-0000-0000000000b2', '+233350000002', 'Kofi') ON CONFLICT (id) DO NOTHING;
-- They are a couple: the partner must still see nothing.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('8a200000-0000-0000-0000-000000000001', '8a100000-0000-0000-0000-0000000000a1', '8a100000-0000-0000-0000-0000000000b2', 'active', now())
  ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.expect_fail(p_sql text, p_code text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_ok boolean := false;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%' || p_code || '%' THEN v_ok := true;
    ELSE RAISE EXCEPTION 'CONTRACT VIOLATED: % raised "%" (wanted %)', p_sql, SQLERRM, p_code; END IF;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % did not fail with %', p_sql, p_code; END IF;
END $$;

-- The whole flow, as Ama, inside one DO so values carry over.
DO $$
DECLARE
  a uuid := '8a100000-0000-0000-0000-0000000000a1';
  k uuid := '8a100000-0000-0000-0000-0000000000b2';
  d jsonb; r jsonb; e uuid; e2 uuid; e3 uuid; b1 uuid; b2 uuid; ph uuid; n int; i int; v_content text;
BEGIN
  PERFORM pg_temp.as_user(a);

  -- A new entry: one empty text block, empty content, the prompt kept.
  d := public.create_journal_entry_v2('What surprised you today?');
  e := (d->'entry'->>'id')::uuid;
  b1 := (d->'blocks'->0->>'id')::uuid;
  IF jsonb_array_length(d->'blocks') <> 1 OR d->'blocks'->0->>'kind' <> 'text' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new entry is one text block, got %', d->'blocks'; END IF;
  IF d->'entry'->>'content' <> '' OR d->'entry'->>'prompt_used' <> 'What surprised you today?' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new entry content/prompt %', d->'entry'; END IF;

  -- Saving text recomputes content and bumps the version; a stale version is a conflict.
  UPDATE public.reflection_journal_entries SET tone = 'settled' WHERE id = e;
  r := public.save_journal_text(b1, 1, '[{"insert":"Morning walk\n"}]'::jsonb);
  IF r->>'status' <> 'saved' OR (r->'block'->>'version')::int <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: save %', r; END IF;
  IF (SELECT tone FROM public.reflection_journal_entries WHERE id = e) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: changed text keeps a stale tone'; END IF;
  r := public.save_journal_text(b1, 1, '[{"insert":"Stale\n"}]'::jsonb);
  IF r->>'status' <> 'conflict' OR r->'block'->>'plain_text' NOT LIKE 'Morning walk%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stale save was not a conflict: %', r; END IF;

  -- A second text block: content is the text blocks in order, blank-line joined.
  b2 := (public.insert_journal_block(e, b1, 'text', '{"delta":[{"insert":"Felt calm\n"}]}'::jsonb)->>'id')::uuid;
  SELECT content INTO v_content FROM public.reflection_journal_entries WHERE id = e;
  IF v_content <> E'Morning walk\n\nFelt calm' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: content %', v_content; END IF;
  PERFORM public.move_journal_block(b2, 0);
  SELECT content INTO v_content FROM public.reflection_journal_entries WHERE id = e;
  IF v_content <> E'Felt calm\n\nMorning walk' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: content after move %', v_content; END IF;

  -- Photos: only inside the owner's own entry folder; at most 10.
  PERFORM pg_temp.expect_fail(format(
    $q$SELECT public.insert_journal_block(%L, NULL, 'photo', %L::jsonb)$q$,
    e, jsonb_build_object('path', k || '/' || e || '/x.jpg')), 'journal:invalid_input');
  ph := (public.insert_journal_block(e, NULL, 'photo', jsonb_build_object('path', a || '/' || e || '/p0.jpg'))->>'id')::uuid;
  FOR i IN 1..9 LOOP
    PERFORM public.insert_journal_block(e, NULL, 'photo', jsonb_build_object('path', a || '/' || e || '/p' || i || '.jpg'));
  END LOOP;
  PERFORM pg_temp.expect_fail(format(
    $q$SELECT public.insert_journal_block(%L, NULL, 'photo', %L::jsonb)$q$,
    e, jsonb_build_object('path', a || '/' || e || '/p10.jpg')), 'journal:limit');
  SELECT content INTO v_content FROM public.reflection_journal_entries WHERE id = e;
  IF v_content <> E'Felt calm\n\nMorning walk' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos changed content %', v_content; END IF;

  -- Removing a photo queues its file for deletion.
  PERFORM public.delete_journal_block(ph);
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'journal-media' AND object_name = a || '/' || e || '/p0.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a removed photo is not queued for deletion'; END IF;

  -- The only block can't be deleted.
  d := public.create_journal_entry_v2(NULL);
  e2 := (d->'entry'->>'id')::uuid;
  PERFORM pg_temp.expect_fail(format('SELECT public.delete_journal_block(%L)', d->'blocks'->0->>'id'), 'journal:last_block');

  -- Titles: blank clears, too long fails.
  r := public.rename_journal_entry(e, '  Tuesday  ');
  IF r->>'title' <> 'Tuesday' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: rename %', r; END IF;
  r := public.rename_journal_entry(e2, '   ');
  IF r->>'title' IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: blank title kept %', r; END IF;
  PERFORM pg_temp.expect_fail(format('SELECT public.rename_journal_entry(%L, %L)', e, repeat('x', 121)), 'journal:too_long');

  -- The list: pinned apart; snippets short; photos flagged.
  PERFORM public.set_journal_pin(e, true);
  r := public.list_journal_entries(NULL, 30);
  IF jsonb_array_length(r->'pinned') <> 1 OR r->'pinned'->0->>'id' <> e::text OR NOT (r->'pinned'->0->>'has_photo')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pinned %', r->'pinned'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'entries') x WHERE x->>'id' = e::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pinned entry also listed by date'; END IF;
  PERFORM public.save_journal_text(b2, 1, jsonb_build_array(jsonb_build_object('insert', repeat('word ', 60) || E'\n')));
  r := public.list_journal_entries(NULL, 30);
  IF char_length(r->'pinned'->0->>'snippet') > 80 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: snippet longer than 80'; END IF;

  -- Soft delete hides; restore brings back; the sweep purges only old deletions.
  PERFORM public.delete_journal_entry(e2);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(public.list_journal_entries(NULL, 30)->'entries') x WHERE x->>'id' = e2::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted entry is listed'; END IF;
  PERFORM public.restore_journal_entry(e2);
  d := public.create_journal_entry_v2(NULL);
  e3 := (d->'entry'->>'id')::uuid;
  PERFORM public.delete_journal_entry(e2);
  PERFORM public.delete_journal_entry(e3);
  UPDATE public.reflection_journal_entries SET deleted_at = now() - interval '11 minutes' WHERE id = e2;
  n := public.purge_my_deleted_journal_entries();
  IF n <> 1 OR EXISTS (SELECT 1 FROM public.reflection_journal_entries WHERE id = e2)
     OR NOT EXISTS (SELECT 1 FROM public.reflection_journal_entries WHERE id = e3) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sweep purged % (wanted only the old one)', n; END IF;

  -- Legacy RPCs (older app builds) still work and keep blocks in step.
  e2 := public.create_journal_entry('Legacy words here');
  IF (SELECT plain_text FROM public.reflection_journal_blocks WHERE entry_id = e2) <> 'Legacy words here' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: legacy create made no text block'; END IF;
  PERFORM public.insert_journal_block(e2, NULL, 'photo', jsonb_build_object('path', a || '/' || e2 || '/old.jpg'));
  PERFORM public.update_journal_entry(e2, 'Rewritten');
  IF (SELECT count(*) FROM public.reflection_journal_blocks WHERE entry_id = e2 AND kind = 'photo') <> 1
     OR (SELECT plain_text FROM public.reflection_journal_blocks WHERE entry_id = e2 AND kind = 'text') <> 'Rewritten'
     OR (SELECT position FROM public.reflection_journal_blocks WHERE entry_id = e2 AND kind = 'text') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: legacy update lost the photo or the text order'; END IF;

  -- The partner (Kofi) can do nothing to Ama's journal.
  PERFORM pg_temp.as_user(k);
  PERFORM pg_temp.expect_fail(format('SELECT public.get_journal_entry(%L)', e), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format($q$SELECT public.save_journal_text(%L, 2, '[{"insert":"x\n"}]'::jsonb)$q$, b1), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format($q$SELECT public.insert_journal_block(%L, NULL, 'text', '{"delta":[{"insert":"x\n"}]}'::jsonb)$q$, e), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.rename_journal_entry(%L, %L)', e, 'mine'), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.set_journal_pin(%L, false)', e), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.delete_journal_block(%L)', b1), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.move_journal_block(%L, 0)', b1), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.purge_journal_entry(%L)', e), 'journal:not_found');
  IF jsonb_array_length(public.list_journal_entries(NULL, 30)->'entries') <> 0
     OR jsonb_array_length(public.list_journal_entries(NULL, 30)->'pinned') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner lists Ama''s entries'; END IF;

  -- Backfill: an entry written before blocks gets them, its content untouched.
  INSERT INTO public.reflection_journal_entries (id, user_id, content)
  VALUES ('8a300000-0000-0000-0000-000000000001', k, repeat('a', 7000));
  PERFORM public.journal_backfill_blocks();
  IF (SELECT count(*) FROM public.reflection_journal_blocks WHERE entry_id = '8a300000-0000-0000-0000-000000000001') <> 3
     OR (SELECT string_agg(plain_text, '' ORDER BY position) FROM public.reflection_journal_blocks WHERE entry_id = '8a300000-0000-0000-0000-000000000001') <> repeat('a', 7000)
     OR (SELECT content FROM public.reflection_journal_entries WHERE id = '8a300000-0000-0000-0000-000000000001') <> repeat('a', 7000) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: backfill'; END IF;

  -- Deleting the account queues every remaining photo.
  DELETE FROM public.media_deletion_queue;
  DELETE FROM auth.users WHERE id = a;
  SELECT count(*) INTO n FROM public.media_deletion_queue WHERE bucket_id = 'journal-media';
  IF n <> 10 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: account deletion queued % photos (wanted 10)', n; END IF;

  -- No relationship link exists anywhere in the journal.
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND column_name = 'relationship_id'
               AND table_name IN ('reflection_journal_entries', 'reflection_journal_blocks', 'reflection_journal_analysis')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a journal table has relationship_id'; END IF;
END $$;

-- Row-level security: as the partner, through the API role, nothing is readable or writable.
SELECT pg_temp.as_user('8a100000-0000-0000-0000-0000000000b2');
INSERT INTO auth.users (id) VALUES ('8a100000-0000-0000-0000-0000000000c3') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('8a100000-0000-0000-0000-0000000000c3', '+233350000003', 'Esi') ON CONFLICT DO NOTHING;
SELECT pg_temp.as_user('8a100000-0000-0000-0000-0000000000c3');
SELECT public.create_journal_entry_v2(NULL);
SELECT pg_temp.as_user('8a100000-0000-0000-0000-0000000000b2');
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.reflection_journal_blocks WHERE user_id = '8a100000-0000-0000-0000-0000000000c3')
     OR EXISTS (SELECT 1 FROM public.reflection_journal_entries WHERE user_id = '8a100000-0000-0000-0000-0000000000c3') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another user''s journal is readable'; END IF;
  BEGIN
    INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload)
    SELECT id, user_id, 9, 'text', '{"delta":[]}' FROM public.reflection_journal_entries LIMIT 1;
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated can insert blocks directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
ROLLBACK;
```

- [ ] **Step 3: Run it and watch it fail**

Start PG if needed:
`pg_ctl -D <scratchpad>/pg/data -o "-p 55432 -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" start`

Run: `bash <scratchpad>/pg/run.sh /Users/user/attune/supabase/tests/journal_notes_contracts.sql`

Expected: `FAIL …journal_notes_contracts.sql`, with `function public.create_journal_entry_v2(unknown) does not exist`. If one of the three newly listed migrations fails to apply on the stubs, add the smallest stub that lets it apply, and ledger it.

- [ ] **Step 4: Write the migration**

`supabase/migrations/20261014190000_journal_notes.sql`:

```sql
-- Reflection Journal as notes (spec docs/superpowers/specs/2026-10-14-journal-notes-design.md).
-- An entry becomes a title plus ordered text/photo blocks. Owner-only: no
-- relationship_id anywhere, no partner path. `content` stays the entry's
-- plain text (server-derived), so analysis keeps reading it unchanged.

ALTER TABLE public.reflection_journal_entries
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS pinned_at timestamptz;
ALTER TABLE public.reflection_journal_entries DROP CONSTRAINT IF EXISTS reflection_journal_entries_title_check;
ALTER TABLE public.reflection_journal_entries ADD CONSTRAINT reflection_journal_entries_title_check
  CHECK (title IS NULL OR char_length(title) BETWEEN 1 AND 120);
-- A new entry is empty until written.
ALTER TABLE public.reflection_journal_entries DROP CONSTRAINT IF EXISTS reflection_journal_entries_content_check;
ALTER TABLE public.reflection_journal_entries ALTER COLUMN content SET DEFAULT '';
CREATE INDEX IF NOT EXISTS reflection_journal_entries_pinned_idx
  ON public.reflection_journal_entries(user_id, pinned_at DESC)
  WHERE pinned_at IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.reflection_journal_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id uuid NOT NULL REFERENCES public.reflection_journal_entries(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  position int NOT NULL,
  kind text NOT NULL CHECK (kind IN ('text', 'photo')),
  payload jsonb NOT NULL CHECK (octet_length(payload::text) <= 16384),
  plain_text text CHECK (plain_text IS NULL OR char_length(plain_text) <= 10000),
  version int NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS reflection_journal_blocks_entry_idx
  ON public.reflection_journal_blocks(entry_id, position);

DROP TRIGGER IF EXISTS set_reflection_journal_blocks_updated_at ON public.reflection_journal_blocks;
CREATE TRIGGER set_reflection_journal_blocks_updated_at
BEFORE UPDATE ON public.reflection_journal_blocks
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.reflection_journal_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reflection_journal_blocks FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.reflection_journal_blocks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reflection_journal_blocks TO service_role;
DROP POLICY IF EXISTS reflection_journal_blocks_select_own ON public.reflection_journal_blocks;
CREATE POLICY reflection_journal_blocks_select_own ON public.reflection_journal_blocks
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- ---- helpers (not callable by clients) ------------------------------------

CREATE OR REPLACE FUNCTION public.journal_fail(p_code text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'journal:%', p_code USING ERRCODE = 'P0001';
END $$;

-- The caller's live entry, locked; not_found for anything else (no
-- existence oracle for other people's entries).
CREATE OR REPLACE FUNCTION public.journal_lock_entry(p_entry_id uuid)
RETURNS public.reflection_journal_entries
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); e public.reflection_journal_entries;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO e FROM public.reflection_journal_entries
   WHERE id = p_entry_id AND user_id = v_uid AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  RETURN e;
END $$;

-- content = the text blocks' plain text, in order, blank-line joined. A
-- changed text makes the last tone stale (as update_journal_entry did).
CREATE OR REPLACE FUNCTION public.journal_refresh_content(p_entry_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_new text;
BEGIN
  SELECT coalesce(string_agg(rtrim(b.plain_text, E' \n\t'), E'\n\n' ORDER BY b.position), '')
    INTO v_new
    FROM public.reflection_journal_blocks b
   WHERE b.entry_id = p_entry_id AND b.kind = 'text' AND btrim(coalesce(b.plain_text, ''), E' \n\t') <> '';
  UPDATE public.reflection_journal_entries
     SET content = v_new,
         tone = CASE WHEN content IS DISTINCT FROM v_new THEN NULL ELSE tone END
   WHERE id = p_entry_id;
END $$;

CREATE OR REPLACE FUNCTION public.journal_summary(e public.reflection_journal_entries) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', e.id,
    'title', e.title,
    'snippet', left(btrim(regexp_replace(e.content, '\s+', ' ', 'g')), 80),
    'has_photo', EXISTS (SELECT 1 FROM public.reflection_journal_blocks b WHERE b.entry_id = e.id AND b.kind = 'photo'),
    'pinned', e.pinned_at IS NOT NULL,
    'tone', e.tone,
    'created_at', e.created_at,
    'updated_at', e.updated_at)
$$;

-- Validates and cleans a block payload; returns (payload, plain_text).
CREATE OR REPLACE FUNCTION public.journal_clean_payload(
  e public.reflection_journal_entries, p_kind text, p_payload jsonb,
  OUT payload jsonb, OUT plain_text text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF p_kind = 'text' THEN
    plain_text := public.planning_validate_delta(p_payload->'delta');
    payload := jsonb_build_object('delta', p_payload->'delta');
    IF char_length(plain_text) > 10000 OR octet_length(payload::text) > 16384 THEN
      PERFORM public.journal_fail('too_long');
    END IF;
  ELSIF p_kind = 'photo' THEN
    IF coalesce(p_payload->>'path', '') !~ ('^' || e.user_id || '/' || e.id || '/[A-Za-z0-9._-]{1,100}$') THEN
      PERFORM public.journal_fail('invalid_input');
    END IF;
    payload := jsonb_build_object('path', p_payload->>'path');
    plain_text := NULL;
  ELSE
    PERFORM public.journal_fail('invalid_input');
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.journal_fail(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.journal_lock_entry(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.journal_refresh_content(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.journal_summary(public.reflection_journal_entries) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.journal_clean_payload(public.reflection_journal_entries, text, jsonb) FROM PUBLIC, anon, authenticated;

-- ---- reads ------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_journal_entry(p_entry_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); e public.reflection_journal_entries;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO e FROM public.reflection_journal_entries
   WHERE id = p_entry_id AND user_id = v_uid AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  RETURN jsonb_build_object(
    'entry', to_jsonb(e) - 'deleted_at',
    'blocks', coalesce((SELECT jsonb_agg(to_jsonb(b) - 'user_id' ORDER BY b.position)
                          FROM public.reflection_journal_blocks b WHERE b.entry_id = e.id), '[]'::jsonb),
    'analysis', (SELECT jsonb_build_object('status', a.status, 'tone', a.tone,
                                           'observation', a.observation, 'confidence', a.confidence)
                   FROM public.reflection_journal_analysis a
                  WHERE a.entry_id = e.id ORDER BY a.updated_at DESC LIMIT 1));
END $$;

-- Pinned entries come apart, on the first page only; the rest are paged by
-- the day they were written.
CREATE OR REPLACE FUNCTION public.list_journal_entries(p_before timestamptz DEFAULT NULL, p_limit int DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_limit int := least(greatest(coalesce(p_limit, 30), 1), 100);
  v_rows jsonb;
  v_pinned jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  -- The subquery hands back whole table rows (s.x), so journal_summary gets
  -- the table's row type, not an anonymous record.
  SELECT coalesce(jsonb_agg(public.journal_summary(s.x) ORDER BY (s.x).created_at DESC), '[]'::jsonb) INTO v_rows
    FROM (SELECT e AS x FROM public.reflection_journal_entries e
           WHERE e.user_id = v_uid AND e.deleted_at IS NULL AND e.pinned_at IS NULL
             AND e.created_at < coalesce(p_before, 'infinity'::timestamptz)
           ORDER BY e.created_at DESC LIMIT v_limit) s;
  IF p_before IS NULL THEN
    SELECT coalesce(jsonb_agg(public.journal_summary(x) ORDER BY x.pinned_at DESC), '[]'::jsonb) INTO v_pinned
      FROM public.reflection_journal_entries x
     WHERE x.user_id = v_uid AND x.deleted_at IS NULL AND x.pinned_at IS NOT NULL;
  END IF;
  RETURN jsonb_build_object('pinned', v_pinned, 'entries', v_rows,
                            'has_more', jsonb_array_length(v_rows) = v_limit);
END $$;

-- ---- writes -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_journal_entry_v2(p_prompt_used text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  INSERT INTO public.reflection_journal_entries (user_id, content, prompt_used)
  VALUES (v_uid, '', nullif(btrim(p_prompt_used), ''))
  RETURNING id INTO v_id;
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  VALUES (v_id, v_uid, 0, 'text', '{"delta":[{"insert":"\n"}]}'::jsonb, '');
  RETURN public.get_journal_entry(v_id);
END $$;

CREATE OR REPLACE FUNCTION public.rename_journal_entry(p_entry_id uuid, p_title text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_title text := nullif(btrim(p_title), ''); e public.reflection_journal_entries;
BEGIN
  e := public.journal_lock_entry(p_entry_id);
  IF char_length(v_title) > 120 THEN PERFORM public.journal_fail('too_long'); END IF;
  UPDATE public.reflection_journal_entries SET title = v_title WHERE id = e.id RETURNING * INTO e;
  RETURN to_jsonb(e) - 'deleted_at';
END $$;

CREATE OR REPLACE FUNCTION public.set_journal_pin(p_entry_id uuid, p_pinned boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE e public.reflection_journal_entries;
BEGIN
  e := public.journal_lock_entry(p_entry_id);
  UPDATE public.reflection_journal_entries
     SET pinned_at = CASE WHEN p_pinned THEN coalesce(pinned_at, now()) ELSE NULL END
   WHERE id = e.id;
END $$;

-- A stale version is returned as a conflict (with the stored block), never
-- an overwrite: the client asks the person which to keep.
CREATE OR REPLACE FUNCTION public.save_journal_text(p_block_id uuid, p_version int, p_delta jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); b public.reflection_journal_blocks; e public.reflection_journal_entries; c record;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO b FROM public.reflection_journal_blocks
   WHERE id = p_block_id AND user_id = v_uid AND kind = 'text';
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  e := public.journal_lock_entry(b.entry_id);
  SELECT * INTO b FROM public.reflection_journal_blocks WHERE id = p_block_id FOR UPDATE;
  IF b.version <> p_version THEN
    RETURN jsonb_build_object('status', 'conflict', 'block', to_jsonb(b) - 'user_id');
  END IF;
  c := public.journal_clean_payload(e, 'text', jsonb_build_object('delta', p_delta));
  UPDATE public.reflection_journal_blocks
     SET payload = c.payload, plain_text = c.plain_text, version = version + 1
   WHERE id = b.id RETURNING * INTO b;
  PERFORM public.journal_refresh_content(e.id);
  RETURN jsonb_build_object('status', 'saved', 'block', to_jsonb(b) - 'user_id');
END $$;

CREATE OR REPLACE FUNCTION public.insert_journal_block(
  p_entry_id uuid, p_after uuid, p_kind text, p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE e public.reflection_journal_entries; b public.reflection_journal_blocks; c record; v_pos int;
BEGIN
  e := public.journal_lock_entry(p_entry_id);
  IF (SELECT count(*) FROM public.reflection_journal_blocks WHERE entry_id = e.id) >= 50 THEN
    PERFORM public.journal_fail('limit');
  END IF;
  IF p_kind = 'photo' AND (SELECT count(*) FROM public.reflection_journal_blocks
                            WHERE entry_id = e.id AND kind = 'photo') >= 10 THEN
    PERFORM public.journal_fail('limit');
  END IF;
  c := public.journal_clean_payload(e, p_kind, p_payload);
  IF p_after IS NULL THEN
    SELECT coalesce(max(position) + 1, 0) INTO v_pos FROM public.reflection_journal_blocks WHERE entry_id = e.id;
  ELSE
    SELECT position + 1 INTO v_pos FROM public.reflection_journal_blocks WHERE id = p_after AND entry_id = e.id;
    IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
    UPDATE public.reflection_journal_blocks SET position = position + 1 WHERE entry_id = e.id AND position >= v_pos;
  END IF;
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  VALUES (e.id, e.user_id, v_pos, p_kind, c.payload, c.plain_text)
  RETURNING * INTO b;
  IF p_kind = 'text' THEN PERFORM public.journal_refresh_content(e.id); END IF;
  RETURN to_jsonb(b) - 'user_id';
END $$;

CREATE OR REPLACE FUNCTION public.delete_journal_block(p_block_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); b public.reflection_journal_blocks; e public.reflection_journal_entries;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO b FROM public.reflection_journal_blocks WHERE id = p_block_id AND user_id = v_uid;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  e := public.journal_lock_entry(b.entry_id);
  IF (SELECT count(*) FROM public.reflection_journal_blocks WHERE entry_id = e.id) <= 1 THEN
    PERFORM public.journal_fail('last_block');
  END IF;
  DELETE FROM public.reflection_journal_blocks WHERE id = b.id;
  IF b.kind = 'text' THEN PERFORM public.journal_refresh_content(e.id); END IF;
END $$;

CREATE OR REPLACE FUNCTION public.move_journal_block(p_block_id uuid, p_to int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); b public.reflection_journal_blocks; e public.reflection_journal_entries; v_n int; v_to int;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  SELECT * INTO b FROM public.reflection_journal_blocks WHERE id = p_block_id AND user_id = v_uid;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
  e := public.journal_lock_entry(b.entry_id);
  SELECT count(*) INTO v_n FROM public.reflection_journal_blocks WHERE entry_id = e.id;
  v_to := least(greatest(coalesce(p_to, 0), 0), v_n - 1);
  WITH ordered AS (
    SELECT id, row_number() OVER (ORDER BY position, created_at) - 1 AS i
      FROM public.reflection_journal_blocks WHERE entry_id = e.id AND id <> b.id)
  UPDATE public.reflection_journal_blocks x
     SET position = CASE WHEN o.i < v_to THEN o.i ELSE o.i + 1 END
    FROM ordered o WHERE x.id = o.id;
  UPDATE public.reflection_journal_blocks SET position = v_to WHERE id = b.id;
  PERFORM public.journal_refresh_content(e.id);
END $$;

CREATE OR REPLACE FUNCTION public.restore_journal_entry(p_entry_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  UPDATE public.reflection_journal_entries SET deleted_at = NULL
   WHERE id = p_entry_id AND user_id = v_uid AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
END $$;

-- Real deletion: blocks and analysis cascade; photo files are queued by the
-- block trigger below.
CREATE OR REPLACE FUNCTION public.purge_journal_entry(p_entry_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  DELETE FROM public.reflection_journal_entries WHERE id = p_entry_id AND user_id = v_uid;
  IF NOT FOUND THEN PERFORM public.journal_fail('not_found'); END IF;
END $$;

-- Deletions left past their Undo window (the app closed mid-Undo) go for good.
CREATE OR REPLACE FUNCTION public.purge_my_deleted_journal_entries() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_n int;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.journal_fail('unauthenticated'); END IF;
  DELETE FROM public.reflection_journal_entries
   WHERE user_id = v_uid AND deleted_at IS NOT NULL AND deleted_at < now() - interval '10 minutes';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

-- ---- photo files follow their blocks ------------------------------------------

CREATE OR REPLACE FUNCTION public.journal_block_queue_photo() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF OLD.kind = 'photo' THEN
    PERFORM public.queue_media_deletion('journal-media', OLD.payload->>'path');
  END IF;
  RETURN OLD;
END $$;
DROP TRIGGER IF EXISTS journal_block_queue_photo ON public.reflection_journal_blocks;
CREATE TRIGGER journal_block_queue_photo
BEFORE DELETE ON public.reflection_journal_blocks
FOR EACH ROW EXECUTE FUNCTION public.journal_block_queue_photo();

-- ---- legacy RPCs (older app builds) keep blocks in step -----------------------

CREATE OR REPLACE FUNCTION public.create_journal_entry(p_content text, p_prompt_used text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_user_id uuid := auth.uid(); v_entry_id uuid;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000'; END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) = 0 THEN
    RAISE EXCEPTION 'content_required' USING ERRCODE = '22023';
  END IF;
  IF char_length(p_content) > 10000 THEN PERFORM public.journal_fail('too_long'); END IF;
  INSERT INTO public.reflection_journal_entries (user_id, content, prompt_used)
  VALUES (v_user_id, p_content, p_prompt_used) RETURNING id INTO v_entry_id;
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  VALUES (v_entry_id, v_user_id, 0, 'text',
          jsonb_build_object('delta', jsonb_build_array(jsonb_build_object('insert', p_content || E'\n'))),
          p_content);
  RETURN v_entry_id;
END $$;

-- The whole text becomes one block at the top; photos stay.
CREATE OR REPLACE FUNCTION public.update_journal_entry(p_entry_id uuid, p_content text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000'; END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) = 0 THEN
    RAISE EXCEPTION 'content_required' USING ERRCODE = '22023';
  END IF;
  IF char_length(p_content) > 10000 THEN PERFORM public.journal_fail('too_long'); END IF;
  UPDATE public.reflection_journal_entries SET content = p_content, tone = NULL
   WHERE id = p_entry_id AND user_id = v_user_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'entry_not_found' USING ERRCODE = '22023'; END IF;
  DELETE FROM public.reflection_journal_blocks WHERE entry_id = p_entry_id AND kind = 'text';
  UPDATE public.reflection_journal_blocks SET position = position + 1 WHERE entry_id = p_entry_id;
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  VALUES (p_entry_id, v_user_id, 0, 'text',
          jsonb_build_object('delta', jsonb_build_array(jsonb_build_object('insert', p_content || E'\n'))),
          p_content);
END $$;

-- ---- grants ----------------------------------------------------------------------

DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.get_journal_entry(uuid)', 'public.list_journal_entries(timestamptz, int)',
    'public.create_journal_entry_v2(text)', 'public.rename_journal_entry(uuid, text)',
    'public.set_journal_pin(uuid, boolean)', 'public.save_journal_text(uuid, int, jsonb)',
    'public.insert_journal_block(uuid, uuid, text, jsonb)', 'public.delete_journal_block(uuid)',
    'public.move_journal_block(uuid, int)', 'public.restore_journal_entry(uuid)',
    'public.purge_journal_entry(uuid)', 'public.purge_my_deleted_journal_entries()'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.journal_block_queue_photo() FROM PUBLIC, anon, authenticated;

-- ---- backfill: every existing entry becomes text blocks (≤ 3 000 characters each) ----

CREATE OR REPLACE FUNCTION public.journal_backfill_blocks() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload, plain_text)
  SELECT e.id, e.user_id, c.i, 'text',
         jsonb_build_object('delta', jsonb_build_array(jsonb_build_object('insert', c.chunk || E'\n'))),
         c.chunk
    FROM public.reflection_journal_entries e
    CROSS JOIN LATERAL (
      SELECT g.i, substr(e.content, g.i * 3000 + 1, 3000) AS chunk
        FROM generate_series(0, greatest(ceil(char_length(e.content) / 3000.0)::int - 1, 0)) AS g(i)) c
   WHERE NOT EXISTS (SELECT 1 FROM public.reflection_journal_blocks b WHERE b.entry_id = e.id);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.journal_backfill_blocks() FROM PUBLIC, anon, authenticated;
SELECT public.journal_backfill_blocks();
```

- [ ] **Step 5: Write the bucket migration**

The harness doesn't apply this one; the device checklist covers it. `supabase/migrations/20261014200000_journal_media_bucket.sql`:

```sql
-- Private photos for the Reflection Journal (spec 2026-10-14 §4.4).
-- Paths are "<user_id>/<entry_id>/<file>.jpg": only the owner may write,
-- only into one of their own live entries; only the owner may read.
INSERT INTO storage.buckets (id, name, public) VALUES ('journal-media', 'journal-media', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'file_size_limit') THEN
    EXECUTE $q$UPDATE storage.buckets SET file_size_limit = 10485760, allowed_mime_types = ARRAY['image/jpeg']
               WHERE id = 'journal-media'$q$;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.journal_storage_can_write(p_name text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_name IS NULL OR p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,100}$' THEN RETURN false; END IF;
  RETURN split_part(p_name, '/', 1) = auth.uid()::text
     AND EXISTS (SELECT 1 FROM public.reflection_journal_entries
                  WHERE id = split_part(p_name, '/', 2)::uuid AND user_id = auth.uid() AND deleted_at IS NULL);
END $$;

CREATE OR REPLACE FUNCTION public.journal_storage_can_read(p_name text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_name IS NOT NULL AND split_part(p_name, '/', 1) = auth.uid()::text
$$;

REVOKE ALL ON FUNCTION public.journal_storage_can_write(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.journal_storage_can_read(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.journal_storage_can_write(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.journal_storage_can_read(text) TO authenticated;

DROP POLICY IF EXISTS journal_media_insert ON storage.objects;
CREATE POLICY journal_media_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'journal-media' AND public.journal_storage_can_write(name));
DROP POLICY IF EXISTS journal_media_select ON storage.objects;
CREATE POLICY journal_media_select ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'journal-media' AND public.journal_storage_can_read(name));
```

- [ ] **Step 6: Run the contracts and watch them pass**

Run: `bash <scratchpad>/pg/run.sh /Users/user/attune/supabase/tests/journal_notes_contracts.sql`
Expected: `PASS …journal_notes_contracts.sql`. The earlier Together contracts still pass, checked with `bash <scratchpad>/pg/run.sh /Users/user/attune/supabase/tests/together_*_contracts.sql`.

---

### Task 2: Shared note pieces (Planning refactor, behaviour unchanged)

**Files:**
- Create: `lib/core/notes/note_date_sections.dart`, `lib/core/notes/note_section.dart`, `lib/features/planning/presentation/widgets/note_text_block.dart`
- Rewrite: `lib/features/planning/presentation/widgets/inline_text_block.dart`
- Modify: `lib/features/planning/presentation/planning_ui.dart` (`planningDateSections`, `planningRowDate`), `lib/features/planning/presentation/screens/planning_category_screen.dart` (`_Section`), `lib/features/planning/presentation/widgets/planning_ribbon.dart` (`tools`), `lib/features/planning/presentation/widgets/conflict_sheet.dart` (`title`)
- Test: `test/core/notes/note_date_sections_test.dart`, `test/core/notes/note_text_block_test.dart`

**Interfaces:**
- Produces:
  - `List<({String title, List<T> items})> noteDateSections<T>(List<T> items, DateTime Function(T) at, DateTime now)` and `String noteRowDate(DateTime at, DateTime now)`;
  - `class NoteSection({required String title, required List<Widget> children})`;
  - `sealed class NoteSaveResult` with `NoteSaved({required int version, String? plainText})`, `NoteGone()` and `NoteConflict({required List<Map<String,dynamic>> ops, required int version, required String plainText})`;
  - `abstract class NoteTextSaver` with `maxPlainChars`, `maxPayloadBytes`, `goneMessage`, `conflictTitle`, `watch(WidgetRef)`, `save(blockId, version, ops)`, `saveOnLeave(blockId, version, ops)`, `afterSave(String? plainText)` and `showError(BuildContext, Object)`;
  - `class NoteTextBlock({required String blockId, required List<Map<String,dynamic>> delta, required int version, required NoteTextSaver Function(WidgetRef) saverFor, bool autofocus = false, String placeholder = 'Write something…'})`, with `static const debounce = Duration(seconds: 1)` and `NoteTextBlockState.controller`;
  - `PlanningRibbon({required onInsert, List<(PlanningBlockType, IconData, String)> tools = planningBlockTools})`;
  - `showConflictSheet(context, {required String theirs, String title = 'Your partner just changed this'})`.

- [ ] **Step 1: Write the failing tests**

`test/core/notes/note_date_sections_test.dart`:

```dart
import 'package:attune/core/notes/note_date_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 20, 15);

  test('groups any item by the date it is given, newest group first', () {
    final items = [
      (name: 'today', at: DateTime(2026, 11, 20, 8)),
      (name: 'old', at: DateTime(2025, 3, 1)),
      (name: 'yesterday', at: DateTime(2026, 11, 19, 22)),
      (name: 'week', at: DateTime(2026, 11, 15)),
      (name: 'month', at: DateTime(2026, 11, 1)),
      (name: 'june', at: DateTime(2026, 6, 4)),
    ];
    final s = noteDateSections(items, (i) => i.at, now);
    expect(s.map((g) => g.title), ['Today', 'Yesterday', 'Previous 7 Days', 'Previous 30 Days', 'June', '2025']);
    expect(s.first.items.single.name, 'today');
  });

  test('row dates: time today, Yesterday, weekday this week, else the date', () {
    expect(noteRowDate(DateTime(2026, 11, 20, 9, 5), now), contains('9:05'));
    expect(noteRowDate(DateTime(2026, 11, 19, 9), now), 'Yesterday');
    expect(noteRowDate(DateTime(2026, 11, 16, 9), now), 'Monday');
    expect(noteRowDate(DateTime(2026, 10, 2, 9), now), '10/2/2026');
  });
}
```

`test/core/notes/note_text_block_test.dart`:

```dart
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/planning/presentation/widgets/planning_doc_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Saver extends NoteTextSaver {
  final saves = <List<Map<String, dynamic>>>[];
  final leaves = <List<Map<String, dynamic>>>[];
  final afters = <String?>[];
  NoteSaveResult next = const NoteSaved(version: 2, plainText: 'Hello');
  @override
  int get maxPlainChars => 10000;
  @override
  int get maxPayloadBytes => 16384;
  @override
  String get goneMessage => 'Gone.';
  @override
  String get conflictTitle => 'You changed this on another device';
  @override
  Future<NoteSaveResult> save(String blockId, int version, List<Map<String, dynamic>> ops) async {
    saves.add(ops);
    return next;
  }

  @override
  void saveOnLeave(String blockId, int version, List<Map<String, dynamic>> ops) => leaves.add(ops);
  @override
  Future<void> afterSave(String? plainText) async => afters.add(plainText);
  @override
  void showError(BuildContext context, Object error) {}
}

Future<_Saver> _pump(WidgetTester t, {bool showSecond = true}) async {
  final saver = _Saver();
  final doc = PlanningDocController();
  addTearDown(doc.dispose);
  await t.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: PlanningDocScope(
          controller: doc,
          child: showSecond
              ? NoteTextBlock(blockId: 'b1', delta: const [{'insert': '\n'}], version: 1, saverFor: (_) => saver)
              : const SizedBox(),
        ),
      ),
    ),
  ));
  return saver;
}

void main() {
  testWidgets('typing saves through the saver a second after the last key', (t) async {
    final saver = await _pump(t);
    t.state<NoteTextBlockState>(find.byType(NoteTextBlock)).controller.replaceText(
        0, 0, 'Hello', const TextSelection.collapsed(offset: 5));
    await t.pump(const Duration(milliseconds: 500));
    expect(saver.saves, isEmpty);
    await t.pump(NoteTextBlock.debounce);
    expect(saver.saves.single.first['insert'], startsWith('Hello'));
    expect(saver.afters, ['Hello']);
  });

  testWidgets('a conflict asks with the saver\'s own title', (t) async {
    final saver = await _pump(t);
    saver.next = const NoteConflict(ops: [{'insert': 'Theirs\n'}], version: 5, plainText: 'Theirs');
    t.state<NoteTextBlockState>(find.byType(NoteTextBlock)).controller.replaceText(
        0, 0, 'Mine', const TextSelection.collapsed(offset: 4));
    await t.pump(NoteTextBlock.debounce);
    await t.pumpAndSettle();
    expect(find.text('You changed this on another device'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/core/notes/`
Expected: FAIL; `note_date_sections.dart` and `note_text_block.dart` don't exist.

- [ ] **Step 3: The shared list pieces**

`lib/core/notes/note_date_sections.dart`:

```dart
import 'package:flutter/material.dart' show DateUtils;
import 'package:intl/intl.dart';

/// Apple Notes-style groups: Today, Yesterday, Previous 7 Days, Previous 30
/// Days, then month names this year, then years. Groups come out newest
/// first; items keep their order within a group. [at] is the date an item
/// is grouped by (Planning: its last activity; the journal: when written).
List<({String title, List<T> items})> noteDateSections<T>(
  List<T> items,
  DateTime Function(T) at,
  DateTime now,
) {
  final today = DateUtils.dateOnly(now);
  String bucket(DateTime when) {
    final day = DateUtils.dateOnly(when.toLocal());
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days <= 7) return 'Previous 7 Days';
    if (days <= 30) return 'Previous 30 Days';
    if (day.year == today.year) return DateFormat.MMMM().format(day);
    return '${day.year}';
  }

  final groups = <String, List<T>>{};
  final newest = <String, DateTime>{};
  for (final item in items) {
    final when = at(item);
    final key = bucket(when);
    (groups[key] ??= []).add(item);
    if (newest[key] == null || when.isAfter(newest[key]!)) newest[key] = when;
  }
  final keys = groups.keys.toList()..sort((a, b) => newest[b]!.compareTo(newest[a]!));
  return [for (final k in keys) (title: k, items: groups[k]!)];
}

/// The date on a row: the time today, "Yesterday", the weekday this week,
/// else the short date.
String noteRowDate(DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = DateUtils.dateOnly(now).difference(DateUtils.dateOnly(local)).inDays;
  if (days <= 0) return DateFormat.jm().format(local);
  if (days == 1) return 'Yesterday';
  if (days <= 7) return DateFormat.EEEE().format(local);
  return DateFormat.yMd().format(local);
}
```

`lib/core/notes/note_section.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:flutter/material.dart';

/// A section title with its rows in one CardInkWell, as in Settings and
/// the notes lists. Rows bring their own dividers.
class NoteSection extends StatelessWidget {
  const NoteSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        Padding(
          padding: Spacing.allMd,
          child: CardInkWell(margin: EdgeInsets.zero, child: Column(children: children)),
        ),
      ],
    );
  }
}
```

In `planning_ui.dart`, re-read the file first. Replace the bodies of `planningDateSections` and `planningRowDate`, keeping their doc comments and signatures, and add `import 'package:attune/core/notes/note_date_sections.dart';`:

```dart
List<({String title, List<PlanningEntrySummary> entries})> planningDateSections(
  List<PlanningEntrySummary> entries,
  DateTime now,
) => [
  for (final g in noteDateSections(entries, (e) => e.lastActivityAt, now))
    (title: g.title, entries: g.items),
];

String planningRowDate(DateTime at, DateTime now) => noteRowDate(at, now);
```

In `planning_category_screen.dart`, re-read it first. Delete the private `_Section` class, replace `_Section(` with `NoteSection(`, and add `import 'package:attune/core/notes/note_section.dart';`. Remove the `card_inkwell.dart` import only if the analyzer then reports it unused.

- [ ] **Step 4: The shared text block**

`lib/features/planning/presentation/widgets/note_text_block.dart`. This is the body of today's `InlineTextBlock`, with every Planning call routed through `NoteTextSaver`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/delta_sanitizer.dart';
import 'conflict_sheet.dart';
import 'planning_doc_scope.dart';
import 'planning_quill.dart';

/// What a save came to.
sealed class NoteSaveResult {
  const NoteSaveResult();
}

final class NoteSaved extends NoteSaveResult {
  const NoteSaved({required this.version, this.plainText});
  final int version;
  final String? plainText;
}

/// The block was removed elsewhere.
final class NoteGone extends NoteSaveResult {
  const NoteGone();
}

/// Someone (a partner, or this person on another device) saved first.
final class NoteConflict extends NoteSaveResult {
  const NoteConflict({required this.ops, required this.version, required this.plainText});
  final List<Map<String, dynamic>> ops;
  final int version;
  final String plainText;
}

/// Where a text block's words go — a couple's plan, or a private journal.
/// The block itself only edits, debounces and resolves conflicts.
abstract class NoteTextSaver {
  int get maxPlainChars;
  int get maxPayloadBytes;

  /// Said when the block turns out to be gone.
  String get goneMessage;

  /// The conflict sheet's title.
  String get conflictTitle;

  /// Called from the block's build: watch whatever the saver needs.
  void watch(WidgetRef ref) {}

  Future<NoteSaveResult> save(String blockId, int version, List<Map<String, dynamic>> ops);

  /// The page is closing: save without the page's (closing) state.
  void saveOnLeave(String blockId, int version, List<Map<String, dynamic>> ops);

  /// After a save went through (e.g. title a new note from its first line).
  Future<void> afterSave(String? plainText) async {}

  void showError(BuildContext context, Object error);
}

/// A text block edited in place, like a paragraph in a document. Typing
/// saves itself a second after you stop, when the cursor leaves the block,
/// and when the page closes. A newer save from elsewhere meets the
/// conflict sheet: keep mine, copy mine, or use theirs.
class NoteTextBlock extends ConsumerStatefulWidget {
  const NoteTextBlock({
    super.key,
    required this.blockId,
    required this.delta,
    required this.version,
    required this.saverFor,
    this.autofocus = false,
    this.placeholder = 'Write something…',
  });
  final String blockId;
  final List<Map<String, dynamic>> delta;
  final int version;
  final NoteTextSaver Function(WidgetRef ref) saverFor;
  final bool autofocus;
  final String placeholder;

  static const debounce = Duration(seconds: 1);

  @override
  ConsumerState<NoteTextBlock> createState() => NoteTextBlockState();
}

class NoteTextBlockState extends ConsumerState<NoteTextBlock> {
  late QuillController _controller = _load(widget.delta);
  late int _baseVersion = widget.version;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final NoteTextSaver _saver;
  PlanningDocController? _doc;
  StreamSubscription<DocChange>? _changes;
  Timer? _debounce;
  bool _dirty = false;
  Future<bool>? _saving;

  @visibleForTesting
  QuillController get controller => _controller;

  QuillController _load(List<Map<String, dynamic>> ops) {
    _changes?.cancel();
    final c = QuillController(
      document: Document.fromJson(sanitizeDelta(ops).ops),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _changes = c.document.changes.listen((_) => _onTyped());
    return c;
  }

  @override
  void initState() {
    super.initState();
    _saver = widget.saverFor(ref);
    _focus.addListener(_onFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final first = _doc == null;
    _doc = PlanningDocScope.read(context);
    _doc?.reportText(widget.blockId, _controller.document.toPlainText().trim().isNotEmpty);
    if (first && (widget.autofocus || (_doc?.takeFocus(widget.blockId) ?? false))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        _controller.moveCursorToEnd();
      });
    }
  }

  /// A newer version from elsewhere (or a split) arrives: show it, unless
  /// there is typing here not yet saved — that meets the conflict sheet on
  /// its next save instead of vanishing.
  @override
  void didUpdateWidget(NoteTextBlock old) {
    super.didUpdateWidget(old);
    if (widget.version != _baseVersion && !_dirty && _saving == null) {
      final previous = _controller;
      _controller = _load(widget.delta);
      _baseVersion = widget.version;
      _register();
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_dirty) _saveOnLeave(); // closing the page saves what was typed
    _doc?.forget(widget.blockId);
    _focus.dispose();
    _scroll.dispose();
    _changes?.cancel();
    final c = _controller;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }

  void _register() {
    if (_doc?.active?.blockId == widget.blockId || _focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _doc?.activate(PlanningActiveText(
            blockId: widget.blockId, controller: _controller, version: () => _baseVersion, flush: flush));
      });
    }
  }

  bool _tooBig(SanitizedDelta clean) {
    final bytes = utf8.encode(jsonEncode({'delta': clean.ops})).length;
    return deltaPlainText(clean.ops).runes.length > _saver.maxPlainChars || bytes > _saver.maxPayloadBytes;
  }

  void _saveOnLeave() {
    final clean = sanitizeDelta(_controller.document.toDelta().toJson());
    if (_tooBig(clean)) return;
    _saver.saveOnLeave(widget.blockId, _baseVersion, clean.ops);
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _doc?.activate(PlanningActiveText(
          blockId: widget.blockId, controller: _controller, version: () => _baseVersion, flush: flush));
    } else if (_dirty) {
      _debounce?.cancel();
      unawaited(_save());
    }
  }

  void _onTyped() {
    _dirty = true;
    _doc?.reportText(widget.blockId, _controller.document.toPlainText().trim().isNotEmpty);
    _debounce?.cancel();
    _debounce = Timer(NoteTextBlock.debounce, () => unawaited(_save()));
  }

  /// Saves now if anything is waiting. True when the text on screen is saved.
  Future<bool> flush() async {
    _debounce?.cancel();
    if (_saving != null) await _saving;
    return _dirty ? _save() : true;
  }

  void _snack(String message) {
    if (mounted) context.showInfoSnackbar(message);
  }

  Future<bool> _save({bool quiet = false}) {
    final running = _saving;
    if (running != null) return running.then((_) => _dirty ? _save(quiet: quiet) : true);
    final f = _saveOnce(quiet: quiet);
    _saving = f;
    return f.whenComplete(() => _saving = null);
  }

  Future<bool> _saveOnce({required bool quiet}) async {
    final clean = sanitizeDelta(_controller.document.toDelta().toJson());
    // Two server limits apply: characters of text AND payload bytes. Non-Latin
    // text and emoji reach the byte cap first.
    if (_tooBig(clean)) {
      if (!quiet && mounted) context.showWarningSnackbar('That text is too long to save. Split it into two blocks.');
      return false;
    }
    if (clean.changed && !quiet) _snack('Some formatting is not supported here and was removed.');
    _dirty = false;
    try {
      final result = await _saver.save(widget.blockId, _baseVersion, clean.ops);
      switch (result) {
        case NoteSaved(:final version, :final plainText):
          _baseVersion = version;
          await _saver.afterSave(plainText);
          return true;
        case NoteGone():
          if (!quiet) _snack(_saver.goneMessage);
          return false;
        case NoteConflict():
          _dirty = true;
          if (quiet || !mounted) return false;
          return _resolve(result, clean.ops);
      }
    } catch (e) {
      _dirty = true; // the draft stays on screen and saves on the next pause
      if (!quiet && mounted) _saver.showError(context, e);
      return false;
    }
  }

  Future<bool> _resolve(NoteConflict theirs, List<Map<String, dynamic>> mine) async {
    final choice = await showConflictSheet(context, theirs: theirs.plainText, title: _saver.conflictTitle);
    if (!mounted || choice == null) return false;
    switch (choice) {
      case ConflictChoice.keepMine:
        _baseVersion = theirs.version;
        _saving = null;
        return _saveOnce(quiet: false);
      case ConflictChoice.copyMine:
        await Clipboard.setData(ClipboardData(text: deltaPlainText(mine)));
        _snack('Your text is copied.');
        _useTheirs(theirs);
        return true;
      case ConflictChoice.useTheirs:
        _useTheirs(theirs);
        return true;
    }
  }

  void _useTheirs(NoteConflict theirs) {
    final old = _controller;
    setState(() {
      _controller = _load(theirs.ops);
      _baseVersion = theirs.version;
      _dirty = false;
    });
    _register();
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    _saver.watch(ref);
    return planningQuillScope(
      context,
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: QuillEditor(
          controller: _controller,
          focusNode: _focus,
          scrollController: _scroll,
          config: planningQuillEditorConfig(context, placeholder: widget.placeholder, editable: true),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Planning's block becomes a thin subclass**

Re-read it first, then replace the whole file. `lib/features/planning/presentation/widgets/inline_text_block.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_models.dart';
import '../../data/planning_repository.dart';
import '../../domain/code_point_limit.dart';
import '../../domain/planning_limits.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import 'note_text_block.dart';

/// A text block edited in place on the plan's page, like a paragraph in a
/// document. A partner's newer save is handled as before: keep mine, copy
/// mine, or use theirs. (The editing itself is [NoteTextBlock].)
class InlineTextBlock extends NoteTextBlock {
  InlineTextBlock({super.key, required this.args, required this.block, super.autofocus})
    : super(
        blockId: block.id,
        delta: block.delta,
        version: block.version,
        saverFor: (ref) => PlanningTextSaver(ref, args),
      );
  final PlanningEntryArgs args;
  final PlanningBlock block;

  static const debounce = NoteTextBlock.debounce;
}

/// The state's old name, kept for the Planning tests that reach into it.
typedef InlineTextBlockState = NoteTextBlockState;

class PlanningTextSaver extends NoteTextSaver {
  PlanningTextSaver(this._ref, this._args)
    : _ctl = _ref.read(planningEntryProvider(_args).notifier),
      _repo = _ref.read(planningRepositoryProvider);

  final WidgetRef _ref;
  final PlanningEntryArgs _args;
  final PlanningEntryController _ctl;

  // Captured up front: leaving the plan disposes its controller before this
  // block's last save runs, so that save goes straight to the repository.
  final PlanningRepository _repo;
  PlanningEntry? _entry;

  @override
  int get maxPlainChars => PlanningLimits.textPlainChars;
  @override
  int get maxPayloadBytes => PlanningLimits.payloadBytes;
  @override
  String get goneMessage => 'Your partner removed this block.';
  @override
  String get conflictTitle => 'Your partner just changed this';

  @override
  void watch(WidgetRef ref) {
    _entry = ref.watch(planningEntryProvider(_args).select((a) => a.valueOrNull?.entry));
  }

  @override
  Future<NoteSaveResult> save(String blockId, int version, List<Map<String, dynamic>> ops) async {
    final result = await _ctl.saveText(blockId, version, ops);
    return switch (result) {
      TextSaved(:final block) => NoteSaved(version: block.version, plainText: block.plainText),
      TextGone() => const NoteGone(),
      TextConflict(:final theirs) =>
        NoteConflict(ops: theirs.delta, version: theirs.version, plainText: theirs.plainText ?? ''),
    };
  }

  /// The plan is closing: save what was typed directly, and title a new
  /// note from its first line, without the plan's (closing) controller.
  @override
  void saveOnLeave(String blockId, int version, List<Map<String, dynamic>> ops) {
    final entry = _entry;
    unawaited(_repo.updateBlock(id: blockId, version: version, payload: {'delta': ops}).then((saved) async {
      final title = firstLine(saved.plainText);
      if (entry != null && entry.categorySeedKey == 'notes' && entry.title == planningNewNoteTitle && title != null) {
        await _repo.updateEntry(id: entry.id, title: title, status: entry.status);
      }
    }).then((_) {}, onError: (Object _) {})); // a partner's newer save wins; nothing to show on a closed page
  }

  /// A note still called "New note" takes its first non-empty line as its
  /// title. A failed rename never blocks the save; the default title stays.
  @override
  Future<void> afterSave(String? plainText) async {
    final entry = _ref.read(planningEntryProvider(_args)).valueOrNull?.entry;
    if (entry == null || entry.categorySeedKey != 'notes' || entry.title != planningNewNoteTitle) return;
    final title = firstLine(plainText);
    if (title == null) return;
    try {
      await _ctl.rename(title);
    } catch (_) {}
  }

  @override
  void showError(BuildContext context, Object error) => showPlanningError(context, error);

  static String? firstLine(String? text) {
    final line = (text ?? '').split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return line.isEmpty ? null : truncateCodePoints(line, PlanningLimits.titleChars);
  }
}
```

Check the sealed result type of `saveText` (`TextSaved`, `TextGone`, `TextConflict`) in `planning_providers.dart`. If the switch expression isn't exhaustive there, use the same three-case `switch` statement the old file used, and ledger it. Grep `lib/` for `InlineTextBlockState` and `InlineTextBlock(`, and make sure every call site still compiles (the constructor is no longer `const`).

- [ ] **Step 6: Ribbon tools and conflict title**

In `planning_ribbon.dart`, re-read it first. Change the constructor and the insert loop:

```dart
  const PlanningRibbon({super.key, required this.onInsert, this.tools = planningBlockTools});
  final ValueChanged<PlanningBlockType> onInsert;

  /// What Insert offers (Planning: every block; the journal: text and photo).
  final List<(PlanningBlockType, IconData, String)> tools;
```

In `_inserts`, change `for (final (type, icon, label) in planningBlockTools)` to `for (final (type, icon, label) in widget.tools)`.

In `conflict_sheet.dart`, change the signature to `Future<ConflictChoice?> showConflictSheet(BuildContext context, {required String theirs, String title = 'Your partner just changed this'})`, and change the first `Text('Your partner just changed this', …)` to `Text(title, …)`.

- [ ] **Step 7: Run the new tests and the whole Planning suite**

Run: `flutter test test/core/notes/ test/features/planning/`
Expected: PASS for the 4 new tests, plus **every Planning test, unedited**. If any Planning test fails, fix the refactor, not the test.

---

### Task 3: Journal data — models, repository, media, cache, providers

**Files:**
- Modify: `lib/features/reflection_journal/data/models/journal_entry.dart`
- Create: `lib/features/reflection_journal/data/models/journal_note.dart`
- Modify: `lib/features/reflection_journal/data/repositories/reflection_journal_repository.dart`
- Create: `lib/features/reflection_journal/data/journal_media.dart`
- Modify: `lib/features/reflection_journal/data/cache/reflection_journal_cache.dart`
- Modify: `lib/features/reflection_journal/presentation/providers/reflection_journal_providers.dart`
- Test: `test/features/reflection_journal/support/fake_journal.dart` (new), `test/features/reflection_journal/journal_notes_data_test.dart` (new), and `reflection_journal_cache_test.dart` (gains one test)

**Interfaces:**
- Consumes: Task 1's RPC JSON; Task 2's `NoteSaveResult`; Planning's `deltaPlainText` (`domain/delta_sanitizer.dart`).
- Produces:
  - `JournalEntry` gains `String? title` and `DateTime? pinnedAt`, plus `copyWith`.
  - `String journalSnippet(String text)` (at most 80 characters, whitespace collapsed) and `String journalRowTitle(JournalEntry? latest)`.
  - `JournalBlock`, with `isText`, `isPhoto`, `delta` and `photoPath`.
  - `JournalEntryDetail`, with `isUntouched` and `copyWith`.
  - `JournalEntrySummary`, with `displayTitle(DateFormat)`.
  - `JournalListPage`.
  - Repository: `listEntries`, `createEntryV2`, `getEntryDetail`, `rename`, `setPinned`, `saveText` (returning `({String status, JournalBlock block})`), `insertBlock`, `deleteBlock`, `moveBlock`, `restoreEntry`, `purgeEntry` and `purgeMyDeleted`, plus the existing `getEntries`, `deleteEntry`, `analyseEntry` and `getPatterns`. Errors are `JournalNotFound`, `JournalLimitReached` and `JournalTooLong`.
  - `JournalMediaGateway` (`uploadJpeg`, `signedUrl`).
  - Providers:
    - `journalMediaGatewayProvider` and `journalPhotoUrlProvider(path)`;
    - `journalListProvider` (`JournalListNotifier`: `loadMore`, `togglePin`, `delete`, `restore`, `purge`, `forget`, `refresh`);
    - `journalEntryDetailProvider(entryId)` (`JournalEntryController`: `saveText`, `rename`, `setPinned`, `addBlock`, `insertAtCursor`, `deleteBlock`, `moveBlock`, `newPhotoPath`).
    - `journalEntriesProvider` and `journalPatternsProvider` are kept.
    - Removed: `journalEntryProvider`, `createJournalEntryProvider`, `updateJournalEntryProvider`, `deleteJournalEntryProvider` and `analyseJournalEntryProvider`.
  - Test support: `FakeJournalRepository` and `FakeJournalMedia`.

- [ ] **Step 1: Write the test support**

`test/features/reflection_journal/support/fake_journal.dart`:

```dart
import 'dart:typed_data';

import 'package:attune/features/planning/domain/delta_sanitizer.dart';
import 'package:attune/features/reflection_journal/data/journal_media.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/data/models/journal_note.dart';
import 'package:attune/features/reflection_journal/data/repositories/reflection_journal_repository.dart';

const fakeJournalUser = 'user-ama';

/// An in-memory journal with the server's rules (owner-only by
/// construction: there is only one person here).
class FakeJournalRepository implements ReflectionJournalRepository {
  FakeJournalRepository({DateTime? now}) : now = now ?? DateTime(2026, 11, 20, 15);
  final DateTime now;
  final entries = <String, JournalEntry>{};
  final blocks = <String, List<JournalBlock>>{};
  final softDeleted = <String>{};
  final purged = <String>[];
  final analysed = <String>[];
  final saves = <String>[];
  int sweeps = 0;
  bool conflictNext = false;
  JournalAnalysis? analysisFor;
  var _n = 0;
  String _id(String p) => '$p-${++_n}';

  JournalEntry addEntry({String? title, required String text, DateTime? createdAt, bool pinned = false, bool photo = false}) {
    final id = _id('e');
    final at = createdAt ?? now;
    entries[id] = JournalEntry(
      id: id, userId: fakeJournalUser, content: text.trim(), createdAt: at, updatedAt: at,
      title: title, pinnedAt: pinned ? at : null,
    );
    blocks[id] = [
      _text(id, 0, [{'insert': '$text\n'}]),
      if (photo) JournalBlock(id: _id('b'), entryId: id, position: 1, kind: 'photo',
          payload: {'path': '$fakeJournalUser/$id/p.jpg'}, version: 1),
    ];
    return entries[id]!;
  }

  JournalBlock _text(String entryId, int position, List<Map<String, dynamic>> ops, {int version = 1}) =>
      JournalBlock(id: _id('b'), entryId: entryId, position: position, kind: 'text',
          payload: {'delta': ops}, plainText: deltaPlainText(ops), version: version);

  void _renumber(String entryId) {
    final list = blocks[entryId]!;
    blocks[entryId] = [for (var i = 0; i < list.length; i++) list[i].withPosition(i)];
    final text = [
      for (final b in blocks[entryId]!)
        if (b.isText && (b.plainText ?? '').trim().isNotEmpty) b.plainText!.trimRight(),
    ].join('\n\n');
    entries[entryId] = entries[entryId]!.copyWith(content: text);
  }

  JournalEntrySummary _summary(JournalEntry e) => JournalEntrySummary(
    id: e.id, title: e.title, snippet: journalSnippet(e.content),
    hasPhoto: blocks[e.id]!.any((b) => b.isPhoto), pinned: e.pinnedAt != null, tone: e.tone,
    createdAt: e.createdAt, updatedAt: e.updatedAt,
  );

  Iterable<JournalEntry> get _live => entries.values.where((e) => !softDeleted.contains(e.id));

  @override
  Future<JournalListPage> listEntries({DateTime? before, int limit = 30}) async {
    final rows = _live.where((e) => e.pinnedAt == null && (before == null || e.createdAt.isBefore(before))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return JournalListPage(
      pinned: before != null ? const [] : [for (final e in _live.where((e) => e.pinnedAt != null)) _summary(e)],
      entries: [for (final e in rows.take(limit)) _summary(e)],
      hasMore: rows.length > limit,
    );
  }

  @override
  Future<JournalEntryDetail> createEntryV2({String? promptUsed}) async {
    final id = _id('e');
    entries[id] = JournalEntry(id: id, userId: fakeJournalUser, content: '', promptUsed: promptUsed, createdAt: now, updatedAt: now);
    blocks[id] = [_text(id, 0, [{'insert': '\n'}])];
    return getEntryDetail(id);
  }

  @override
  Future<JournalEntryDetail> getEntryDetail(String entryId) async {
    if (!entries.containsKey(entryId) || softDeleted.contains(entryId)) throw const JournalNotFound();
    return JournalEntryDetail(entry: entries[entryId]!, blocks: List.of(blocks[entryId]!), analysis: analysisFor);
  }

  @override
  Future<JournalEntry> rename(String entryId, String? title) async {
    final t = title?.trim();
    entries[entryId] = entries[entryId]!.copyWith(title: t, clearTitle: t == null || t.isEmpty);
    return entries[entryId]!;
  }

  @override
  Future<void> setPinned(String entryId, bool pinned) async {
    entries[entryId] = entries[entryId]!.copyWith(pinnedAt: pinned ? now : null, clearPinned: !pinned);
  }

  @override
  Future<({String status, JournalBlock block})> saveText(String blockId, int version, List<Map<String, dynamic>> ops) async {
    final entryId = blocks.entries.firstWhere((x) => x.value.any((b) => b.id == blockId), orElse: () => throw const JournalNotFound()).key;
    final list = blocks[entryId]!;
    final i = list.indexWhere((b) => b.id == blockId);
    if (conflictNext) {
      conflictNext = false;
      final theirs = _text(entryId, i, [{'insert': 'From my other phone\n'}], version: list[i].version + 1);
      list[i] = JournalBlock(id: blockId, entryId: entryId, position: i, kind: 'text', payload: theirs.payload,
          plainText: theirs.plainText, version: theirs.version);
      return (status: 'conflict', block: list[i]);
    }
    list[i] = JournalBlock(id: blockId, entryId: entryId, position: i, kind: 'text', payload: {'delta': ops},
        plainText: deltaPlainText(ops), version: version + 1);
    saves.add(deltaPlainText(ops).trim());
    _renumber(entryId);
    return (status: 'saved', block: blocks[entryId]![i]);
  }

  @override
  Future<JournalBlock> insertBlock(String entryId, {String? afterId, required String kind, required Map<String, dynamic> payload}) async {
    final list = blocks[entryId]!;
    if (list.length >= 50 || (kind == 'photo' && list.where((b) => b.isPhoto).length >= 10)) throw const JournalLimitReached();
    final at = afterId == null ? list.length : list.indexWhere((b) => b.id == afterId) + 1;
    final b = kind == 'text'
        ? _text(entryId, at, [for (final op in payload['delta'] as List) Map<String, dynamic>.from(op as Map)])
        : JournalBlock(id: _id('b'), entryId: entryId, position: at, kind: 'photo', payload: payload, version: 1);
    list.insert(at, b);
    _renumber(entryId);
    return b;
  }

  @override
  Future<void> deleteBlock(String blockId) async {
    for (final e in blocks.entries) {
      e.value.removeWhere((b) => b.id == blockId);
      _renumber(e.key);
    }
  }

  @override
  Future<void> moveBlock(String blockId, int to) async {
    for (final e in blocks.entries) {
      final i = e.value.indexWhere((b) => b.id == blockId);
      if (i < 0) continue;
      final b = e.value.removeAt(i);
      e.value.insert(to.clamp(0, e.value.length), b);
      _renumber(e.key);
    }
  }

  @override
  Future<void> deleteEntry(String entryId) async => softDeleted.add(entryId);
  @override
  Future<void> restoreEntry(String entryId) async => softDeleted.remove(entryId);
  @override
  Future<void> purgeEntry(String entryId) async {
    purged.add(entryId);
    entries.remove(entryId);
    blocks.remove(entryId);
    softDeleted.remove(entryId);
  }

  @override
  Future<int> purgeMyDeleted() async {
    sweeps++;
    return 0;
  }

  @override
  Future<JournalAnalysis> analyseEntry(String entryId) async {
    analysed.add(entryId);
    return JournalAnalysis.fromJson(const {'status': 'pending'});
  }

  @override
  Future<List<JournalEntry>> getEntries() async => _live.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<({String status, String? summary, int entryCount})> getPatterns() async =>
      (status: 'insufficient_evidence', summary: null, entryCount: entries.length);
}

class FakeJournalMedia implements JournalMediaGateway {
  final uploads = <String>[];
  bool fail = false;
  @override
  Future<void> uploadJpeg(String path, Uint8List bytes) async {
    if (fail) throw Exception('offline');
    uploads.add(path);
  }

  @override
  Future<String> signedUrl(String path) async => 'https://example.invalid/$path';
}
```

- [ ] **Step 2: Write the failing data tests**

`test/features/reflection_journal/journal_notes_data_test.dart`:

```dart
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_journal.dart';

ProviderContainer _container(FakeJournalRepository repo, {FakeJournalMedia? media}) {
  final c = ProviderContainer(overrides: [
    reflectionJournalRepositoryProvider.overrideWithValue(repo),
    journalMediaGatewayProvider.overrideWithValue(media ?? FakeJournalMedia()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('the list loads pinned apart, and sweeps old deletions once', () async {
    final repo = FakeJournalRepository();
    repo.addEntry(text: 'Pinned one', pinned: true);
    repo.addEntry(text: 'Plain one');
    final c = _container(repo);
    final s = await c.read(journalListProvider.future);
    expect(s.pinned.single.snippet, 'Pinned one');
    expect(s.entries.single.snippet, 'Plain one');
    expect(repo.sweeps, 1);
  });

  test('delete hides at once; Undo restores; a discarded entry never comes back on refresh', () async {
    final repo = FakeJournalRepository();
    final e = repo.addEntry(text: 'Gone soon');
    final keep = repo.addEntry(text: 'Stays');
    final c = _container(repo);
    final row = (await c.read(journalListProvider.future)).entries.firstWhere((x) => x.id == e.id);
    await c.read(journalListProvider.notifier).delete(row);
    expect(c.read(journalListProvider).value!.entries.map((x) => x.id), [keep.id]);
    await c.read(journalListProvider.notifier).restore(e.id);
    expect(c.read(journalListProvider).value!.entries.map((x) => x.id), contains(e.id));
    c.read(journalListProvider.notifier).forget(e.id);
    await c.read(journalListProvider.notifier).refresh();
    expect(c.read(journalListProvider).value!.entries.map((x) => x.id), [keep.id]);
  });

  test('a stale text save is a conflict, not an overwrite', () async {
    final repo = FakeJournalRepository();
    final e = repo.addEntry(text: 'Hello');
    final c = _container(repo);
    final d = await c.read(journalEntryDetailProvider(e.id).future);
    repo.conflictNext = true;
    final r = await c.read(journalEntryDetailProvider(e.id).notifier)
        .saveText(d.blocks.first.id, 1, const [{'insert': 'Mine\n'}]);
    expect(r, isA<NoteConflict>());
    expect((r as NoteConflict).plainText.trim(), 'From my other phone');
  });

  test('inserting mid-paragraph splits the text around the new block', () async {
    final repo = FakeJournalRepository();
    final e = repo.addEntry(text: 'Before after');
    final c = _container(repo);
    final d = await c.read(journalEntryDetailProvider(e.id).future);
    await c.read(journalEntryDetailProvider(e.id).notifier).insertAtCursor(
      'photo',
      textBlockId: d.blocks.first.id,
      version: d.blocks.first.version,
      before: const [{'insert': 'Before\n'}],
      after: const [{'insert': 'after\n'}],
      payload: {'path': '$fakeJournalUser/${e.id}/p.jpg'},
    );
    final kinds = c.read(journalEntryDetailProvider(e.id)).value!.blocks.map((b) => b.kind);
    expect(kinds, ['text', 'photo', 'text']);
    expect(repo.entries[e.id]!.content, 'Before\n\nafter');
  });

  test('photo paths live in the owner\'s own entry folder', () async {
    final repo = FakeJournalRepository();
    final e = repo.addEntry(text: 'x');
    final c = _container(repo);
    await c.read(journalEntryDetailProvider(e.id).future);
    final path = c.read(journalEntryDetailProvider(e.id).notifier).newPhotoPath();
    expect(path, matches(RegExp('^$fakeJournalUser/${e.id}/[0-9a-f-]{36}\\.jpg\$')));
  });

  test('snippets and row titles never carry more than 80 characters', () {
    expect(journalSnippet('a  b\n\nc'), 'a b c');
    expect(journalSnippet('x' * 200).length, 80);
    expect(journalRowTitle(null), 'Start your first reflection');
    final e = JournalEntry(id: '1', userId: 'u', content: 'Body text', createdAt: DateTime(2026), updatedAt: DateTime(2026));
    expect(journalRowTitle(e), 'Body text');
    expect(journalRowTitle(e.copyWith(title: 'My title')), 'My title');
  });
}
```

Add to `reflection_journal_cache_test.dart`, matching its existing setup (`SharedPreferences.setMockInitialValues` and a cache instance):

```dart
  test('the cache keeps list summaries, never the full text', () async {
    final long = 'word ' * 100;
    await cache.writeEntries('u1', [
      JournalEntry(id: '1', userId: 'u1', content: long, createdAt: DateTime(2026), updatedAt: DateTime(2026)),
    ]);
    final read = cache.readEntries('u1').single;
    expect(read.content.length, lessThanOrEqualTo(80));
    expect(long.startsWith(read.content.substring(0, 20)), isTrue);
  });
```

Use the test file's own variable name for the cache, as its other tests do.

- [ ] **Step 3: Run them and watch them fail**

Run: `flutter test test/features/reflection_journal/`
Expected: compile errors. `journal_note.dart`, `journal_media.dart`, `journalListProvider`, `copyWith` and `journalSnippet` don't exist.

- [ ] **Step 4: Models**

In `journal_entry.dart`, re-read it first:
- add `final String? title;` and `final DateTime? pinnedAt;` as optional constructor parameters;
- read `title: json['title'] as String?` and `pinnedAt: json['pinned_at'] == null ? null : DateTime.parse(json['pinned_at'] as String)` in `fromJson`;
- write `'title': title` and `'pinned_at': pinnedAt?.toIso8601String()` in `toJson`;
- add `title` and `pinnedAt` to `props`.

Then add these:

```dart
  JournalEntry copyWith({
    String? content,
    String? title,
    bool clearTitle = false,
    DateTime? pinnedAt,
    bool clearPinned = false,
  }) => JournalEntry(
    id: id,
    userId: userId,
    content: content ?? this.content,
    promptUsed: promptUsed,
    tone: tone,
    createdAt: createdAt,
    updatedAt: updatedAt,
    title: clearTitle ? null : (title ?? this.title),
    pinnedAt: clearPinned ? null : (pinnedAt ?? this.pinnedAt),
  );
}

/// The first words of an entry, for lists and the cache: whitespace
/// collapsed, at most 80 characters (never the full text).
String journalSnippet(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = flat.runes.toList();
  return runes.length <= 80 ? flat : String.fromCharCodes(runes.take(80));
}

/// The Conversations "latest reflection" line.
String journalRowTitle(JournalEntry? latest) {
  if (latest == null) return 'Start your first reflection';
  final title = latest.title?.trim() ?? '';
  return title.isNotEmpty ? title : journalSnippet(latest.content);
```

The closing `}` of the class moves to just before `journalSnippet`, as shown. Keep the existing constructor's required fields as they are, and the new two optional.

`lib/features/reflection_journal/data/models/journal_note.dart`:

```dart
import 'package:intl/intl.dart';

import 'journal_analysis.dart';
import 'journal_entry.dart';

/// One part of an entry: formatted text, or a private photo.
class JournalBlock {
  const JournalBlock({
    required this.id,
    required this.entryId,
    required this.position,
    required this.kind,
    required this.payload,
    this.plainText,
    required this.version,
  });

  factory JournalBlock.fromJson(Map<String, dynamic> j) => JournalBlock(
    id: j['id'] as String,
    entryId: j['entry_id'] as String,
    position: (j['position'] as num).toInt(),
    kind: j['kind'] as String,
    payload: Map<String, dynamic>.from(j['payload'] as Map),
    plainText: j['plain_text'] as String?,
    version: (j['version'] as num).toInt(),
  );

  final String id;
  final String entryId;
  final int position;
  final String kind;
  final Map<String, dynamic> payload;
  final String? plainText;
  final int version;

  bool get isText => kind == 'text';
  bool get isPhoto => kind == 'photo';
  String? get photoPath => payload['path'] as String?;
  List<Map<String, dynamic>> get delta => [
    for (final op in (payload['delta'] as List? ?? const [])) Map<String, dynamic>.from(op as Map),
  ];

  JournalBlock withPosition(int p) => JournalBlock(
    id: id, entryId: entryId, position: p, kind: kind, payload: payload, plainText: plainText, version: version);
}

class JournalEntryDetail {
  const JournalEntryDetail({required this.entry, required this.blocks, this.analysis});

  factory JournalEntryDetail.fromJson(Map<String, dynamic> j) => JournalEntryDetail(
    entry: JournalEntry.fromJson(Map<String, dynamic>.from(j['entry'] as Map)),
    blocks: [for (final b in (j['blocks'] as List? ?? const [])) JournalBlock.fromJson(Map<String, dynamic>.from(b as Map))],
    analysis: j['analysis'] == null ? null : JournalAnalysis.fromJson(Map<String, dynamic>.from(j['analysis'] as Map)),
  );

  final JournalEntry entry;
  final List<JournalBlock> blocks;
  final JournalAnalysis? analysis;

  JournalEntryDetail copyWith({JournalEntry? entry, List<JournalBlock>? blocks}) =>
      JournalEntryDetail(entry: entry ?? this.entry, blocks: blocks ?? this.blocks, analysis: analysis);

  /// Nothing written, titled or added (a new entry like this is discarded).
  bool get isUntouched =>
      (entry.title ?? '').trim().isEmpty && blocks.every((b) => b.isText && (b.plainText ?? '').trim().isEmpty);
}

/// A row in the Entries list.
class JournalEntrySummary {
  const JournalEntrySummary({
    required this.id,
    this.title,
    required this.snippet,
    required this.hasPhoto,
    required this.pinned,
    this.tone,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JournalEntrySummary.fromJson(Map<String, dynamic> j) => JournalEntrySummary(
    id: j['id'] as String,
    title: j['title'] as String?,
    snippet: j['snippet'] as String? ?? '',
    hasPhoto: j['has_photo'] as bool? ?? false,
    pinned: j['pinned'] as bool? ?? false,
    tone: j['tone'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: DateTime.parse(j['updated_at'] as String),
  );

  final String id;
  final String? title;
  final String snippet;
  final bool hasPhoto;
  final bool pinned;
  final String? tone;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// An untitled entry is called by the day it was written.
  String displayTitle([DateFormat? format]) {
    final t = title?.trim() ?? '';
    return t.isNotEmpty ? t : (format ?? DateFormat('EEEE, d MMMM')).format(createdAt.toLocal());
  }

  JournalEntrySummary withPinned(bool p) => JournalEntrySummary(
    id: id, title: title, snippet: snippet, hasPhoto: hasPhoto, pinned: p, tone: tone,
    createdAt: createdAt, updatedAt: updatedAt);
}

class JournalListPage {
  const JournalListPage({required this.pinned, required this.entries, required this.hasMore});

  factory JournalListPage.fromJson(Map<String, dynamic> j) => JournalListPage(
    pinned: [for (final x in (j['pinned'] as List? ?? const [])) JournalEntrySummary.fromJson(Map<String, dynamic>.from(x as Map))],
    entries: [for (final x in (j['entries'] as List? ?? const [])) JournalEntrySummary.fromJson(Map<String, dynamic>.from(x as Map))],
    hasMore: j['has_more'] as bool? ?? false,
  );

  final List<JournalEntrySummary> pinned;
  final List<JournalEntrySummary> entries;
  final bool hasMore;
}
```

Check `JournalAnalysis.fromJson` against the `analysis` object `{status, tone, observation, confidence}`. If it needs fields that `get_journal_entry` doesn't send, make them nullable there and ledger it.

- [ ] **Step 5: Repository, media and cache**

In `reflection_journal_repository.dart`, re-read it first:
- **Keep:** `getEntries`, `deleteEntry`, `analyseEntry` and `getPatterns`.
- **Remove:** `getEntry`, `createEntry` and `updateEntry`.
- **Add:** everything below.

```dart
class JournalNotFound implements Exception {
  const JournalNotFound();
}

class JournalLimitReached implements Exception {
  const JournalLimitReached();
}

class JournalTooLong implements Exception {
  const JournalTooLong();
}
```

These methods go inside `ReflectionJournalRepository`:

```dart
  Future<dynamic> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      return await _supabase.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      final m = e.message;
      if (m.contains('journal:not_found')) throw const JournalNotFound();
      if (m.contains('journal:limit')) throw const JournalLimitReached();
      if (m.contains('journal:too_long')) throw const JournalTooLong();
      rethrow;
    }
  }

  Map<String, dynamic> _map(dynamic v) => Map<String, dynamic>.from(v as Map);

  Future<JournalListPage> listEntries({DateTime? before, int limit = 30}) async => JournalListPage.fromJson(
    _map(await _rpc('list_journal_entries', {'p_before': before?.toUtc().toIso8601String(), 'p_limit': limit})),
  );

  Future<JournalEntryDetail> createEntryV2({String? promptUsed}) async =>
      JournalEntryDetail.fromJson(_map(await _rpc('create_journal_entry_v2', {'p_prompt_used': promptUsed})));

  Future<JournalEntryDetail> getEntryDetail(String entryId) async =>
      JournalEntryDetail.fromJson(_map(await _rpc('get_journal_entry', {'p_entry_id': entryId})));

  Future<JournalEntry> rename(String entryId, String? title) async =>
      JournalEntry.fromJson(_map(await _rpc('rename_journal_entry', {'p_entry_id': entryId, 'p_title': title})));

  Future<void> setPinned(String entryId, bool pinned) =>
      _rpc('set_journal_pin', {'p_entry_id': entryId, 'p_pinned': pinned});

  Future<({String status, JournalBlock block})> saveText(
    String blockId,
    int version,
    List<Map<String, dynamic>> ops,
  ) async {
    final r = _map(await _rpc('save_journal_text', {'p_block_id': blockId, 'p_version': version, 'p_delta': ops}));
    return (status: r['status'] as String, block: JournalBlock.fromJson(_map(r['block'])));
  }

  Future<JournalBlock> insertBlock(
    String entryId, {
    String? afterId,
    required String kind,
    required Map<String, dynamic> payload,
  }) async => JournalBlock.fromJson(_map(await _rpc('insert_journal_block', {
    'p_entry_id': entryId,
    'p_after': afterId,
    'p_kind': kind,
    'p_payload': payload,
  })));

  Future<void> deleteBlock(String blockId) => _rpc('delete_journal_block', {'p_block_id': blockId});

  Future<void> moveBlock(String blockId, int to) => _rpc('move_journal_block', {'p_block_id': blockId, 'p_to': to});

  Future<void> restoreEntry(String entryId) => _rpc('restore_journal_entry', {'p_entry_id': entryId});

  Future<void> purgeEntry(String entryId) => _rpc('purge_journal_entry', {'p_entry_id': entryId});

  Future<int> purgeMyDeleted() async => (await _rpc('purge_my_deleted_journal_entries', const {}) as num).toInt();
```

Add `import 'package:attune/features/reflection_journal/data/models/journal_note.dart';`. Change `deleteEntry` to use `_rpc` as well, so its errors map the same way.

`lib/features/reflection_journal/data/journal_media.dart`:

```dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The journal's private photos, behind one seam so tests fake them.
abstract class JournalMediaGateway {
  /// Uploads a prepared JPEG. Storage policies admit only the owner's own
  /// `{user}/{entry}/` folder.
  Future<void> uploadJpeg(String path, Uint8List bytes);

  /// A short-lived URL for showing a stored photo.
  Future<String> signedUrl(String path);
}

class SupabaseJournalMediaGateway implements JournalMediaGateway {
  const SupabaseJournalMediaGateway(this._supabase);
  final SupabaseClient _supabase;
  static const bucket = 'journal-media';
  static const signedUrlTtl = Duration(minutes: 10);

  @override
  Future<void> uploadJpeg(String path, Uint8List bytes) => _supabase.storage
      .from(bucket)
      .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false))
      .timeout(const Duration(seconds: 60));

  @override
  Future<String> signedUrl(String path) =>
      _supabase.storage.from(bucket).createSignedUrl(path, signedUrlTtl.inSeconds).timeout(const Duration(seconds: 10));
}
```

In `reflection_journal_cache.dart`, change `schemaVersion` to `2` (older full-text caches then read as a miss), and change `encode`:

```dart
  /// List summaries only: the first words, never the full text (spec §6.4).
  @override
  Map<String, dynamic> encode(JournalEntry item) =>
      {...item.toJson(), 'content': journalSnippet(item.content)};
```

- [ ] **Step 6: Providers**

In `reflection_journal_providers.dart`, re-read it first:
- delete `journalEntryProvider`, `createJournalEntryProvider`, `updateJournalEntryProvider`, `deleteJournalEntryProvider` and `analyseJournalEntryProvider`;
- keep `reflectionJournalRepositoryProvider`, `journalEntriesProvider` (and its notifier) and `journalPatternsProvider`;
- add the imports `dart:typed_data`, `package:uuid/uuid.dart`, `journal_media.dart`, `models/journal_note.dart` and `package:attune/features/planning/presentation/widgets/note_text_block.dart`;
- then add the following:

```dart
final journalMediaGatewayProvider = Provider<JournalMediaGateway>(
  (ref) => SupabaseJournalMediaGateway(ref.read(supabaseClientProvider)),
);

/// A stored photo's short-lived link (10 minutes), fetched while the photo
/// is on screen; the image itself is cached by its path.
final journalPhotoUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref.watch(journalMediaGatewayProvider).signedUrl(path),
);

class JournalListState {
  const JournalListState({required this.pinned, required this.entries, required this.hasMore});
  final List<JournalEntrySummary> pinned;
  final List<JournalEntrySummary> entries;
  final bool hasMore;

  JournalListState copyWith({List<JournalEntrySummary>? pinned, List<JournalEntrySummary>? entries, bool? hasMore}) =>
      JournalListState(pinned: pinned ?? this.pinned, entries: entries ?? this.entries, hasMore: hasMore ?? this.hasMore);
}

/// The Entries tab: pinned first, then pages by the day written. Opening
/// it sweeps deletions left past their Undo window (the app closed mid-Undo).
class JournalListNotifier extends AsyncNotifier<JournalListState> {
  final Set<String> _discarded = {};
  bool _swept = false;

  ReflectionJournalRepository get _repo => ref.read(reflectionJournalRepositoryProvider);

  @override
  Future<JournalListState> build() async {
    if (!_swept) {
      _swept = true;
      unawaited(_repo.purgeMyDeleted().then((_) {}, onError: (Object _) {}));
    }
    final page = await _repo.listEntries();
    return JournalListState(pinned: _keep(page.pinned), entries: _keep(page.entries), hasMore: page.hasMore);
  }

  List<JournalEntrySummary> _keep(List<JournalEntrySummary> rows) =>
      [for (final r in rows) if (!_discarded.contains(r.id)) r];

  Future<void> refresh() async {
    try {
      final page = await _repo.listEntries();
      state = AsyncData(JournalListState(pinned: _keep(page.pinned), entries: _keep(page.entries), hasMore: page.hasMore));
    } catch (_) {} // keep what's on screen; the next visit retries
  }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || !s.hasMore || s.entries.isEmpty) return;
    final page = await _repo.listEntries(before: s.entries.last.createdAt);
    state = AsyncData(s.copyWith(entries: [...s.entries, ..._keep(page.entries)], hasMore: page.hasMore));
  }

  /// A new entry left empty: gone from the list now, whatever a refresh says.
  void forget(String entryId) {
    _discarded.add(entryId);
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(
      pinned: [for (final r in s.pinned) if (r.id != entryId) r],
      entries: [for (final r in s.entries) if (r.id != entryId) r],
    ));
  }

  Future<void> togglePin(JournalEntrySummary e) async {
    final before = state.valueOrNull;
    if (before == null) return;
    final moved = e.withPinned(!e.pinned);
    state = AsyncData(before.copyWith(
      pinned: e.pinned ? [for (final r in before.pinned) if (r.id != e.id) r] : [moved, ...before.pinned],
      entries: e.pinned
          ? ([...before.entries, moved]..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
          : [for (final r in before.entries) if (r.id != e.id) r],
    ));
    try {
      await _repo.setPinned(e.id, !e.pinned);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Hidden now (soft delete) so Undo can bring it back.
  Future<void> delete(JournalEntrySummary e) async {
    final before = state.valueOrNull;
    if (before == null) return;
    state = AsyncData(before.copyWith(
      pinned: [for (final r in before.pinned) if (r.id != e.id) r],
      entries: [for (final r in before.entries) if (r.id != e.id) r],
    ));
    try {
      await _repo.deleteEntry(e.id);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> restore(String entryId) async {
    await _repo.restoreEntry(entryId);
    _discarded.remove(entryId);
    await refresh();
  }

  /// After the Undo window: for good (best effort; the sweep retries).
  Future<void> purge(String entryId) async {
    try {
      await _repo.purgeEntry(entryId);
    } catch (_) {}
  }
}

final journalListProvider = AsyncNotifierProvider<JournalListNotifier, JournalListState>(JournalListNotifier.new);

/// One entry, as a note: its title and blocks.
class JournalEntryController extends AutoDisposeFamilyAsyncNotifier<JournalEntryDetail, String> {
  ReflectionJournalRepository get _repo => ref.read(reflectionJournalRepositoryProvider);
  JournalEntryDetail get _current => state.requireValue;

  @override
  Future<JournalEntryDetail> build(String entryId) => _repo.getEntryDetail(entryId);

  void _put(JournalEntryDetail d) {
    if (state.hasValue) state = AsyncData(d);
  }

  Future<void> _reload() async => _put(await _repo.getEntryDetail(arg));

  Future<NoteSaveResult> saveText(String blockId, int version, List<Map<String, dynamic>> ops) async {
    try {
      final r = await _repo.saveText(blockId, version, ops);
      if (r.status == 'conflict') {
        return NoteConflict(ops: r.block.delta, version: r.block.version, plainText: r.block.plainText ?? '');
      }
      if (state.hasValue) {
        _put(_current.copyWith(blocks: [for (final b in _current.blocks) b.id == blockId ? r.block : b]));
      }
      return NoteSaved(version: r.block.version, plainText: r.block.plainText);
    } on JournalNotFound {
      return const NoteGone();
    }
  }

  Future<void> rename(String? title) async {
    final e = await _repo.rename(arg, title);
    _put(_current.copyWith(entry: e));
  }

  Future<void> setPinned(bool pinned) async {
    await _repo.setPinned(arg, pinned);
    await _reload();
  }

  static const _emptyText = {
    'delta': [
      {'insert': '\n'},
    ],
  };

  Future<JournalBlock> addBlock(String kind, {Map<String, dynamic>? payload, String? afterId}) async {
    final b = await _repo.insertBlock(arg, afterId: afterId, kind: kind, payload: payload ?? _emptyText);
    await _reload();
    return b;
  }

  /// Mid-paragraph, as a word processor does: the text keeps what came
  /// before the cursor, the new block goes next, the rest follows it.
  Future<JournalBlock> insertAtCursor(
    String kind, {
    required String textBlockId,
    required int version,
    required List<Map<String, dynamic>> before,
    required List<Map<String, dynamic>> after,
    Map<String, dynamic>? payload,
  }) async {
    final cut = await saveText(textBlockId, version, before);
    if (cut is! NoteSaved) throw const JournalNotFound();
    final inserted = await _repo.insertBlock(arg, afterId: textBlockId, kind: kind, payload: payload ?? _emptyText);
    await _repo.insertBlock(arg, afterId: inserted.id, kind: 'text', payload: {'delta': after});
    await _reload();
    return inserted;
  }

  Future<void> deleteBlock(String blockId) async {
    await _repo.deleteBlock(blockId);
    await _reload();
  }

  Future<void> moveBlock(String blockId, int to) async {
    final blocks = List.of(_current.blocks);
    final i = blocks.indexWhere((b) => b.id == blockId);
    if (i >= 0) {
      final b = blocks.removeAt(i);
      blocks.insert(to.clamp(0, blocks.length), b);
      _put(_current.copyWith(blocks: blocks));
    }
    try {
      await _repo.moveBlock(blockId, to);
    } finally {
      await _reload();
    }
  }

  /// Where a new photo goes: inside the owner's own entry folder.
  String newPhotoPath() => '${_current.entry.userId}/$arg/${const Uuid().v4()}.jpg';

  Future<JournalBlock> addPhoto(Uint8List jpeg, {String? afterId}) async {
    final path = newPhotoPath();
    await ref.read(journalMediaGatewayProvider).uploadJpeg(path, jpeg); // nothing saved if this fails
    return addBlock('photo', payload: {'path': path}, afterId: afterId);
  }
}

final journalEntryDetailProvider =
    AsyncNotifierProvider.autoDispose.family<JournalEntryController, JournalEntryDetail, String>(
      JournalEntryController.new,
    );
```

- [ ] **Step 7: Run the tests and watch them pass**

Run: `flutter test test/features/reflection_journal/journal_notes_data_test.dart test/features/reflection_journal/reflection_journal_cache_test.dart test/features/reflection_journal/journal_entry_model_test.dart`
Expected: PASS. Compile errors elsewhere (the compose and detail screens use removed providers) are expected until Task 5. Run only these files now.

---

### Task 4: The Entries tab, grouped like notes

**Files:**
- Create: `lib/features/reflection_journal/presentation/widgets/journal_entry_row.dart`
- Modify: `lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart` (`_EntriesTab` and the FAB)
- Modify (shared): `lib/features/chat/presentation/screens/conversations_screen.dart` (`_LatestReflectionRow` title)
- Test: `test/features/reflection_journal/support/journal_test_app.dart` (new), and `test/features/reflection_journal/reflection_journal_screen_test.dart` (rewritten)

**Interfaces:**
- Consumes:
  - Task 3: `journalListProvider`, `JournalEntrySummary`, `FakeJournalRepository`, `FakeJournalMedia`.
  - Task 2: `noteDateSections`, `noteRowDate`, `NoteSection`.
  - Task 5: the `journalEntry` route with `JournalEntryArgs`. This task adds the route stub described in Step 3.
- Produces:
  - `class JournalEntryArgs { final String entryId; final bool isNew; final String? prompt; }`, in `journal_entry_screen.dart`, created here as a stub;
  - `Future<void> openNewJournalEntry(BuildContext context, WidgetRef ref)`;
  - `journalTestApp(...)`.

- [ ] **Step 1: The test app**

`test/features/reflection_journal/support/journal_test_app.dart`:

```dart
import 'package:attune/features/planning/presentation/widgets/photo_block_view.dart' show planningPhotoPickerProvider;
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/screens/reflection_journal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'fake_journal.dart';

/// The journal with its two routes, on fakes. [photos]: what the picker
/// returns (each a JPEG's bytes).
Future<GoRouter> pumpJournal(
  WidgetTester t, {
  required FakeJournalRepository repo,
  FakeJournalMedia? media,
  List<List<int>> photos = const [],
  String initial = '/reflectionJournal',
  Object? extra,
}) async {
  final router = GoRouter(
    initialLocation: initial,
    initialExtra: extra,
    routes: [
      GoRoute(path: '/reflectionJournal', name: 'reflectionJournal', builder: (_, __) => const ReflectionJournalScreen()),
      GoRoute(
        path: '/journalEntry',
        name: 'journalEntry',
        builder: (_, s) {
          final a = s.extra! as JournalEntryArgs;
          return JournalEntryScreen(entryId: a.entryId, isNew: a.isNew, prompt: a.prompt);
        },
      ),
    ],
  );
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      reflectionJournalRepositoryProvider.overrideWithValue(repo),
      journalMediaGatewayProvider.overrideWithValue(media ?? FakeJournalMedia()),
      // No network in tests: photos show their placeholder.
      journalPhotoUrlProvider.overrideWith((ref, path) => Future<String>.error('no network in tests')),
      planningPhotoPickerProvider.overrideWithValue(
        (ImageSource source, int limit) async => (photos: [for (final p in photos) Uint8List.fromList(p)], rejected: 0),
      ),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp.router(routerConfig: router),
    ),
  ));
  await t.pumpAndSettle();
  return router;
}
```

Add `import 'dart:typed_data';` at the top. Before using it, check `planningPhotoPickerProvider`'s typedef in `photo_block_view.dart` (`PlanningPhotoPicker`), and match its exact return record.

- [ ] **Step 2: Write the failing list tests**

Replace `test/features/reflection_journal/reflection_journal_screen_test.dart` with:

```dart
import 'package:attune/core/notes/note_section.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_entry_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_journal.dart';
import 'support/journal_test_app.dart';

void main() {
  testWidgets('entries are grouped by the day written, each group a card of rows', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final now = DateTime.now();
    repo.addEntry(title: 'Evening', text: 'Long day, good talk', createdAt: now.subtract(const Duration(minutes: 5)));
    repo.addEntry(text: 'Untitled thoughts', createdAt: now.subtract(const Duration(days: 1)));
    repo.addEntry(title: 'Pinned', text: 'Keep this', pinned: true, createdAt: now.subtract(const Duration(days: 40)));
    await pumpJournal(t, repo: repo);
    expect(find.text('Pinned'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsWidgets);
    expect(find.byType(NoteSection), findsNWidgets(3));
    expect(find.byType(InfoRowWidget), findsNWidgets(3));
    expect(find.textContaining('Long day, good talk'), findsOneWidget); // the first words, in the row
  });

  testWidgets('an untitled entry is called by its day', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    repo.addEntry(text: 'No title here', createdAt: DateTime(2026, 3, 3, 10));
    await pumpJournal(t, repo: repo);
    expect(find.text('Tuesday, 3 March'), findsOneWidget);
  });

  testWidgets('swipe right deletes with Undo; swipe left pins', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Swipe me', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.drag(find.text('Swipe me'), const Offset(500, 0));
    await t.pumpAndSettle();
    expect(find.text('Swipe me'), findsNothing);
    expect(repo.softDeleted, {e.id});
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(find.text('Swipe me'), findsOneWidget);
    await t.drag(find.text('Swipe me'), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(repo.entries[e.id]!.pinnedAt, isNotNull);
    expect(find.text('Pinned'), findsOneWidget);
    await t.pump(JournalEntryRow.undoWindow); // the purge timer runs out (Undo was used: nothing purged)
    expect(repo.purged, isEmpty);
  });

  testWidgets('opening the journal sweeps old deletions once', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    await pumpJournal(t, repo: repo);
    expect(repo.sweeps, 1);
  });

  testWidgets('+ creates an entry and opens it, ready to write', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    await pumpJournal(t, repo: repo);
    await t.tap(find.byTooltip('New entry'));
    await t.pumpAndSettle();
    expect(find.byType(JournalEntryScreen), findsOneWidget);
    expect(repo.entries, hasLength(1));
  });

  testWidgets('the empty journal says nothing is shared', (t) async {
    await pumpJournal(t, repo: FakeJournalRepository(now: DateTime.now()));
    expect(find.textContaining('Nothing here is ever shared with anyone.'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run them and watch them fail**

Create a minimal stub at `lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart`, so that the tests compile:

```dart
import 'package:flutter/material.dart';

class JournalEntryArgs {
  const JournalEntryArgs({required this.entryId, this.isNew = false, this.prompt});
  final String entryId;
  final bool isNew;
  final String? prompt;
}

class JournalEntryScreen extends StatelessWidget {
  const JournalEntryScreen({super.key, required this.entryId, this.isNew = false, this.prompt});
  final String entryId;
  final bool isNew;
  final String? prompt;

  @override
  Widget build(BuildContext context) => const Scaffold();
}
```

Also **delete** `journal_entry_compose_screen.dart`, `journal_entry_detail_screen.dart` and `widgets/journal_entry_card.dart`. In `app_router.dart` (shared; re-read it first):
- replace their two imports with `journal_entry_screen.dart`;
- replace the constants `journalEntryCompose` and `journalEntryDetail` with `static const String journalEntry = '/journalEntry';`;
- replace their two `GoRoute`s with:

```dart
      GoRoute(
        path: RouteNames.journalEntry,
        name: 'journalEntry',
        builder: (context, state) {
          final args = state.extra! as JournalEntryArgs;
          return JournalEntryScreen(entryId: args.entryId, isNew: args.isNew, prompt: args.prompt);
        },
      ),
```

Grep `lib/` and `test/` for `journalEntryCompose`, `journalEntryDetail`, `JournalEntryCard`, `JournalEntryComposeScreen` and `JournalEntryDetailScreen`. Only `reflection_journal_screen.dart` may still mention them, and the next step rewrites it.

Run: `flutter test test/features/reflection_journal/reflection_journal_screen_test.dart`
Expected: FAIL. There are no `NoteSection`s, no "Today" header and no `New entry` tooltip.

- [ ] **Step 4: The row**

`lib/features/reflection_journal/presentation/widgets/journal_entry_row.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notes/note_date_sections.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../data/models/journal_note.dart';
import '../providers/reflection_journal_providers.dart';

enum _RowAction { pin, delete }

/// One entry in the list, as a notes row. Swipe RIGHT deletes (with Undo);
/// swipe LEFT pins or unpins. Long-press and screen-reader actions offer the
/// same, since swipes are neither discoverable nor available to assistive
/// technology.
class JournalEntryRow extends ConsumerWidget {
  const JournalEntryRow({super.key, required this.entry, required this.now, required this.last, required this.onTap});
  final JournalEntrySummary entry;
  final DateTime now;
  final bool last;
  final VoidCallback onTap;

  /// How long Undo is offered before the entry is gone for good.
  static const undoWindow = Duration(seconds: 6);

  String get _pinLabel => entry.pinned ? 'Unpin' : 'Pin';

  Future<void> _togglePin(BuildContext context, WidgetRef ref) async {
    final host = Navigator.of(context).context;
    try {
      await ref.read(journalListProvider.notifier).togglePin(entry);
    } catch (_) {
      host.showErrorSnackbar("Couldn't do that. Please try again.");
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final list = ref.read(journalListProvider.notifier);
    final host = Navigator.of(context).context;
    try {
      await list.delete(entry);
    } catch (_) {
      host.showErrorSnackbar("Couldn't delete that. Please try again.");
      return;
    }
    var undone = false;
    host.showInfoSnackbar('Entry deleted', actionLabel: 'Undo', onAction: () async {
      undone = true;
      try {
        await list.restore(entry.id);
      } catch (_) {
        host.showErrorSnackbar("Couldn't bring it back.");
      }
    });
    // After the Undo window it goes for good; if the app closes first, the
    // next visit's sweep finishes it.
    Future.delayed(undoWindow, () {
      if (!undone) list.purge(entry.id);
    });
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_RowAction>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(entry.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(_pinLabel),
            onTap: () => Navigator.pop(c, _RowAction.pin),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Theme.of(c).colorScheme.error),
            title: const Text('Delete'),
            onTap: () => Navigator.pop(c, _RowAction.delete),
          ),
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _RowAction.pin:
        await _togglePin(context, ref);
      case _RowAction.delete:
        await _delete(context, ref);
    }
  }

  Widget _swipeBackground(BuildContext context, {required bool delete}) {
    final scheme = Theme.of(context).colorScheme;
    final fg = delete ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    return Container(
      padding: Spacing.horizontalMd,
      color: delete ? scheme.errorContainer : scheme.primaryContainer,
      alignment: delete ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(delete ? Icons.delete_outline_rounded : (entry.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded), color: fg),
        const Gap(Spacing.xs),
        Text(delete ? 'Delete' : _pinLabel, style: TextStyle(color: fg)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = [noteRowDate(entry.createdAt, now), if (entry.snippet.isNotEmpty) entry.snippet].join('  ');
    return Dismissible(
      key: ValueKey('journal-${entry.id}'),
      background: _swipeBackground(context, delete: true),
      secondaryBackground: _swipeBackground(context, delete: false),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          await _togglePin(context, ref);
        } else {
          await _delete(context, ref);
        }
        return false; // the list itself removes or moves the row
      },
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: _pinLabel): () => _togglePin(context, ref),
          const CustomSemanticsAction(label: 'Delete'): () => _delete(context, ref),
        },
        child: GestureDetector(
          onLongPress: () => _menu(context, ref),
          child: InfoRowWidget(
            leadingWidget: const SizedBox.shrink(),
            avatarRadius: 0,
            iconSize: 0,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
            title: entry.displayTitle(),
            subtitle: subtitle,
            titleMaxLines: 1,
            subTitleMaxLines: 1,
            showDivider: !last,
            disableTrailing: !entry.hasPhoto,
            trailingWidget: entry.hasPhoto
                ? Semantics(label: 'Has a photo', child: Icon(Icons.photo_outlined, size: 18, color: Theme.of(context).colorScheme.outline))
                : null,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
```

Check `InfoRowWidget` for a trailing-widget parameter. If it's called something other than `trailingWidget`, use its real name; if it has none, append " · photo" to the subtitle instead. Ledger whichever you do.

- [ ] **Step 5: The Entries tab and the FAB**

In `reflection_journal_screen.dart`, re-read it first:
- replace `_EntriesTab` with the version below;
- change the FAB to `AppFab(icon: Icons.edit_outlined, heroTag: 'journal-new', onPressed: () => openNewJournalEntry(context, ref))`, wrapped in a `Tooltip(message: 'New entry', …)` if `AppFab` has no `tooltip` parameter;
- change `_ReflectionJournalScreenState` to `ConsumerState` usage of `ref`;
- remove the imports of the deleted files;
- add the imports for `journal_entry_row.dart`, `journal_entry_screen.dart`, `note_date_sections.dart`, `note_section.dart`, `journal_prompts.dart`, and `planning_skeletons.dart` (`PlanningEntriesSkeleton`).

```dart
/// Creates an entry and opens it, ready to write. The list refreshes when
/// it closes (an empty one is discarded there).
Future<void> openNewJournalEntry(BuildContext context, WidgetRef ref) async {
  final prompt = randomJournalPrompt();
  try {
    final d = await ref.read(reflectionJournalRepositoryProvider).createEntryV2(promptUsed: prompt);
    if (!context.mounted) return;
    await context.pushNamed('journalEntry', extra: JournalEntryArgs(entryId: d.entry.id, isNew: true, prompt: prompt));
    await ref.read(journalListProvider.notifier).refresh();
  } catch (_) {
    if (context.mounted) context.showErrorSnackbar("Couldn't start a new entry. Please try again.");
  }
}

class _EntriesTab extends ConsumerWidget {
  const _EntriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(journalListProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const PlanningEntriesSkeleton(label: 'Loading entries'),
      error: (error, _) => Center(
        child: ErrorStateWidget(
          title: 'Something went wrong',
          subtitle: "We couldn't load your entries right now.",
          primaryActionLabel: 'Try again',
          onPrimaryAction: () => ref.invalidate(journalListProvider),
        ),
      ),
      data: (s) {
        if (s.pinned.isEmpty && s.entries.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.book_outlined,
            title: 'Your journal is empty',
            subtitle: "Write your first entry whenever you're ready. Nothing here is ever shared with anyone.",
            actionLabel: 'Write an entry',
            onAction: () => openNewJournalEntry(context, ref),
          );
        }
        final now = DateTime.now();
        Future<void> open(String id) async {
          await context.pushNamed('journalEntry', extra: JournalEntryArgs(entryId: id));
          await ref.read(journalListProvider.notifier).refresh();
        }

        Widget section(String title, List<JournalEntrySummary> rows) => NoteSection(
          title: title,
          children: [
            for (var i = 0; i < rows.length; i++)
              JournalEntryRow(entry: rows[i], now: now, last: i == rows.length - 1, onTap: () => open(rows[i].id)),
          ],
        );
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 400) ref.read(journalListProvider.notifier).loadMore();
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () => ref.read(journalListProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (s.pinned.isNotEmpty) section('Pinned', s.pinned),
                for (final g in noteDateSections(s.entries, (e) => e.createdAt, now)) section(g.title, g.items),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

`loadMore` can run more than once while a page is in flight. Guard it inside `JournalListNotifier.loadMore` with a `bool _loadingMore` flag that returns early, and set or clear it around the fetch. Add that flag in this step.

- [ ] **Step 6: The Conversations line** (shared; re-read the file first)

In `_LatestReflectionRow`, change `title: latest?.content ?? 'Start your first reflection',` to `title: journalRowTitle(latest),` and import `journal_entry.dart`. Nothing else changes.

- [ ] **Step 7: Run the tests and watch them pass**

Run: `flutter test test/features/reflection_journal/reflection_journal_screen_test.dart test/features/chat/conversations_screen_test.dart test/features/stories/story_calendar_test.dart`
Expected: PASS, with the 6 new list tests and the existing Conversations and Stories tests unchanged.

---

### Task 5: The entry screen (a note)

**Files:**
- Rewrite: `lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart` (replaces the Task 4 stub)
- Create: `lib/features/reflection_journal/presentation/widgets/journal_text_saver.dart`, `lib/features/reflection_journal/presentation/widgets/journal_photo_block.dart`
- Test: `test/features/reflection_journal/journal_entry_screen_test.dart`

**Interfaces:**
- Consumes:
  - Task 2: `NoteTextBlock`, `NoteTextSaver`, `NoteSaveResult`, `PlanningRibbon(tools:)`, `PlanningDocController`/`PlanningDocScope`, `sanitizeDelta`.
  - Task 3: `journalEntryDetailProvider`, `journalListProvider`, `reflectionJournalRepositoryProvider`, `journalPhotoUrlProvider`, `JournalLimitReached`.
  - Planning's `planningPhotoPickerProvider`.
- Produces:
  - `JournalEntryScreen({required String entryId, bool isNew = false, String? prompt})`;
  - `JournalVisit`;
  - `JournalTextSaver`;
  - `JournalPhotoBlock({required String path, VoidCallback? onRemove})`;
  - `const journalBlockTools`.

- [ ] **Step 1: Write the failing screen tests**

`test/features/reflection_journal/journal_entry_screen_test.dart`:

```dart
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/planning/presentation/widgets/planning_ribbon.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_photo_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_journal.dart';
import 'support/journal_test_app.dart';

Future<void> _type(WidgetTester t, String text, {int block = 0}) async {
  t.state<NoteTextBlockState>(find.byType(NoteTextBlock).at(block)).controller.replaceText(
      0, 0, text, TextSelection.collapsed(offset: text.length));
  await t.pump();
}

Future<void> _back(WidgetTester t) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.pop();
  await t.pumpAndSettle();
}

Finder _ribbon(String label) => find.descendant(of: find.byType(PlanningRibbon), matching: find.text(label));

void main() {
  testWidgets('a new entry opens ready to write, with a prompt that can be dismissed', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    await pumpJournal(t, repo: repo);
    await t.tap(find.byTooltip('New entry'));
    await t.pumpAndSettle();
    expect(find.byType(NoteTextBlock), findsOneWidget);
    final prompt = repo.entries.values.single.promptUsed!;
    expect(find.text(prompt), findsOneWidget);
    await t.tap(find.byTooltip('Dismiss prompt'));
    await t.pumpAndSettle();
    expect(find.text(prompt), findsNothing);
  });

  testWidgets('typing saves itself and titles an untitled entry from its first line', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(text: '');
    await pumpJournal(t, repo: repo, initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    await _type(t, 'Quiet morning\nThen a long walk');
    await t.pump(NoteTextBlock.debounce);
    await t.pumpAndSettle();
    expect(repo.saves.last, 'Quiet morning\nThen a long walk');
    expect(repo.entries[e.id]!.title, 'Quiet morning');
  });

  testWidgets('a new entry left empty is discarded', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    await pumpJournal(t, repo: repo);
    await t.tap(find.byTooltip('New entry'));
    await t.pumpAndSettle();
    final id = repo.entries.keys.single;
    await _back(t);
    expect(repo.purged, [id]);
    expect(find.byType(JournalEntryScreen), findsNothing);
  });

  testWidgets('leaving right after typing saves, then reflects once', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Day', text: '');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Day'));
    await t.pumpAndSettle();
    await _type(t, 'Something to think about');
    await _back(t); // within the debounce
    await t.pumpAndSettle();
    expect(repo.saves, ['Something to think about']);
    expect(repo.analysed, [e.id]);
  });

  testWidgets('reading an entry never calls the AI', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    repo.addEntry(title: 'Old one', text: 'Written before notes');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Old one'));
    await t.pumpAndSettle();
    await _back(t);
    expect(repo.analysed, isEmpty);
    expect(repo.saves, isEmpty);
  });

  testWidgets('a stale save asks before overwriting', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Two phones', text: 'Start');
    await pumpJournal(t, repo: repo, initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    repo.conflictNext = true;
    await _type(t, 'Mine ');
    await t.pump(NoteTextBlock.debounce);
    await t.pumpAndSettle();
    expect(find.text('You changed this on another device'), findsOneWidget);
  });

  testWidgets('Insert offers only Text and Photo; a photo lands in the owner\'s folder', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final media = FakeJournalMedia();
    final e = repo.addEntry(title: 'With a photo', text: 'Look');
    await pumpJournal(t, repo: repo, media: media, photos: [[1, 2, 3]],
        initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    await t.tap(_ribbon('Insert'));
    await t.pumpAndSettle();
    expect(_ribbon('Checklist'), findsNothing);
    await t.tap(_ribbon('Photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    expect(media.uploads.single, startsWith('$fakeJournalUser/${e.id}/'));
    expect(find.byType(JournalPhotoBlock), findsOneWidget);
  });

  testWidgets('a failed upload adds nothing and offers Retry', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final media = FakeJournalMedia()..fail = true;
    final e = repo.addEntry(title: 'Offline', text: 'x');
    await pumpJournal(t, repo: repo, media: media, photos: [[1, 2, 3]],
        initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    await t.tap(_ribbon('Insert'));
    await t.pumpAndSettle();
    await t.tap(_ribbon('Photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    expect(find.byType(JournalPhotoBlock), findsNothing);
    expect(repo.blocks[e.id]!.where((b) => b.isPhoto), isEmpty);
    expect(find.textContaining("Couldn't add this photo"), findsOneWidget);
    media.fail = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.byType(JournalPhotoBlock), findsOneWidget);
  });

  testWidgets('a photo can be removed', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Pics', text: 'x', photo: true);
    await pumpJournal(t, repo: repo, initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    await t.tap(find.byTooltip('Options for photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(find.byType(JournalPhotoBlock), findsNothing);
  });

  testWidgets('a finished reflection shows under the writing', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now())
      ..analysisFor = JournalAnalysis.fromJson(const {
        'status': 'completed', 'tone': 'hopeful', 'observation': 'Based on what you wrote, rest mattered today.',
        'confidence': 'medium',
      });
    final e = repo.addEntry(title: 'Reflected', text: 'x');
    await pumpJournal(t, repo: repo, initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    expect(find.text('A reflection'), findsOneWidget);
    expect(find.textContaining('rest mattered today'), findsOneWidget);
  });

  testWidgets('delete from the menu removes the entry for good', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Bye', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Bye'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Entry options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last); // the confirmation's button
    await t.pumpAndSettle();
    expect(repo.purged, [e.id]);
    expect(find.text('Bye'), findsNothing);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/reflection_journal/journal_entry_screen_test.dart`
Expected: FAIL, because the stub screen is an empty `Scaffold`.

- [ ] **Step 3: The saver and the visit**

`lib/features/reflection_journal/presentation/widgets/journal_text_saver.dart`:

```dart
import 'dart:async';

import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/reflection_journal_repository.dart';
import '../providers/reflection_journal_providers.dart';

/// One visit to an entry: the saves still landing as the page closes, and
/// whether any text changed (the reflection runs once, after, if so).
class JournalVisit {
  final List<Future<void>> _pending = [];
  bool textChanged = false;

  void track(Future<void> f) => _pending.add(f.then((_) {}, onError: (Object _) {}));

  Future<void> settled() => Future.wait(List.of(_pending));
}

/// A journal text block's words go to the owner's own entry.
class JournalTextSaver extends NoteTextSaver {
  JournalTextSaver(WidgetRef ref, this._entryId, {required this.visit, required this.titleFromFirstLine})
    : _ctl = ref.read(journalEntryDetailProvider(_entryId).notifier),
      _repo = ref.read(reflectionJournalRepositoryProvider);

  final String _entryId;
  final JournalVisit visit;

  /// True for the entry's first text block while the entry has no title.
  final bool Function() titleFromFirstLine;
  final JournalEntryController _ctl;

  // Captured up front: closing the entry disposes its controller before the
  // last save runs, so that save goes straight to the repository.
  final ReflectionJournalRepository _repo;

  @override
  int get maxPlainChars => 10000;
  @override
  int get maxPayloadBytes => 16384;
  @override
  String get goneMessage => 'This part was removed on another device.';
  @override
  String get conflictTitle => 'You changed this on another device';

  @override
  Future<NoteSaveResult> save(String blockId, int version, List<Map<String, dynamic>> ops) async {
    final r = await _ctl.saveText(blockId, version, ops);
    if (r is NoteSaved) visit.textChanged = true;
    return r;
  }

  @override
  void saveOnLeave(String blockId, int version, List<Map<String, dynamic>> ops) {
    final titleIt = titleFromFirstLine();
    visit.track(_repo.saveText(blockId, version, ops).then((r) async {
      if (r.status != 'saved') return;
      visit.textChanged = true;
      final title = firstLine(r.block.plainText);
      if (titleIt && title != null) await _repo.rename(_entryId, title);
    }));
  }

  @override
  Future<void> afterSave(String? plainText) async {
    if (!titleFromFirstLine()) return;
    final title = firstLine(plainText);
    if (title == null) return;
    try {
      await _ctl.rename(title);
    } catch (_) {}
  }

  @override
  void showError(BuildContext context, Object error) =>
      context.showErrorSnackbar(error is JournalTooLong ? 'That text is too long to save.' : "Couldn't save. We'll try again.");

  static String? firstLine(String? text) {
    final line = (text ?? '').split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (line.isEmpty) return null;
    final runes = line.runes.toList();
    return runes.length <= 120 ? line : String.fromCharCodes(runes.take(120));
  }
}
```

- [ ] **Step 4: The photo block**

`lib/features/reflection_journal/presentation/widgets/journal_photo_block.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/reflection_journal_providers.dart';

/// A private photo in an entry: a 4:3 frame that opens full size.
class JournalPhotoBlock extends ConsumerWidget {
  const JournalPhotoBlock({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final url = ref.watch(journalPhotoUrlProvider(path));
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(child: Icon(Icons.photo_outlined, color: scheme.outline)),
    );
    final image = url.when(
      data: (u) => CachedNetworkImage(imageUrl: u, cacheKey: path, fit: BoxFit.cover, errorWidget: (_, __, ___) => fallback),
      loading: () => ColoredBox(color: scheme.surfaceContainerHigh),
      error: (_, __) => fallback,
    );
    return Semantics(
      image: true,
      label: 'Photo',
      button: true,
      child: GestureDetector(
        onTap: url.hasValue
            ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                    body: Center(
                      child: InteractiveViewer(
                        child: CachedNetworkImage(imageUrl: url.requireValue, cacheKey: path, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: ClipRRect(
            borderRadius: BorderRadiusTokens.mdAll,
            child: AspectRatio(aspectRatio: 4 / 3, child: image),
          ),
        ),
      ),
    );
  }
}
```

If `BorderRadiusTokens.mdAll` doesn't exist, use the radius token Planning's photo cards use (grep `BorderRadiusTokens.` in `photo_block_view.dart`).

- [ ] **Step 5: The screen**

Replace the stub. `lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart`:

```dart
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/planning/domain/code_point_limit.dart';
import 'package:attune/features/planning/domain/delta_sanitizer.dart';
import 'package:attune/features/planning/data/planning_models.dart' show PlanningBlockType;
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/planning/presentation/widgets/photo_block_view.dart' show planningPhotoPickerProvider;
import 'package:attune/features/planning/presentation/widgets/planning_doc_scope.dart';
import 'package:attune/features/planning/presentation/widgets/planning_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../data/models/journal_note.dart';
import '../../data/repositories/reflection_journal_repository.dart';
import '../providers/reflection_journal_providers.dart';
import '../widgets/journal_photo_block.dart';
import '../widgets/journal_text_saver.dart';

class JournalEntryArgs {
  const JournalEntryArgs({required this.entryId, this.isNew = false, this.prompt});
  final String entryId;
  final bool isNew;
  final String? prompt;
}

/// What Insert offers in a journal entry.
const journalBlockTools = <(PlanningBlockType, IconData, String)>[
  (PlanningBlockType.text, Icons.notes_rounded, 'Text'),
  (PlanningBlockType.photo, Icons.photo_library_outlined, 'Photo'),
];

enum _EntryMenu { pin, unpin, delete }

enum _BlockMenu { up, down, remove }

/// A journal entry, written like a note: a title, then text and photos.
/// Private to its writer; nothing here reaches a partner.
class JournalEntryScreen extends ConsumerStatefulWidget {
  const JournalEntryScreen({super.key, required this.entryId, this.isNew = false, this.prompt});
  final String entryId;
  final bool isNew;
  final String? prompt;

  @override
  ConsumerState<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends ConsumerState<JournalEntryScreen> {
  final _doc = PlanningDocController();
  final _visit = JournalVisit();
  // Captured while ref is usable: dispose (and the work it schedules) runs
  // after the widget is gone.
  late final ReflectionJournalRepository _repo;
  late final JournalListNotifier _list;
  JournalEntryDetail? _last;
  bool _promptDismissed = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(reflectionJournalRepositoryProvider);
    _list = ref.read(journalListProvider.notifier);
  }

  @override
  void dispose() {
    _doc.dispose();
    // The blocks (children) have already queued their last saves. Once those
    // land: one reflection if any text changed, then a fresher list.
    final visit = _visit;
    final repo = _repo;
    final list = _list;
    final id = widget.entryId;
    scheduleMicrotask(() async {
      await visit.settled();
      if (visit.textChanged) unawaited(repo.analyseEntry(id).then((_) {}, onError: (Object _) {}));
      unawaited(list.refresh());
    });
    super.dispose();
  }

  /// A new entry closed with nothing written, titled or added is removed.
  void _onPop(bool didPop) {
    if (!didPop || !widget.isNew) return;
    final d = _last;
    if (d == null || _doc.anyText || !d.isUntouched) return;
    _list.forget(widget.entryId);
    unawaited(_repo.purgeEntry(widget.entryId).then((_) {}, onError: (Object _) {}));
  }

  JournalEntryController get _ctl => ref.read(journalEntryDetailProvider(widget.entryId).notifier);

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on JournalLimitReached {
      if (mounted) context.showWarningSnackbar('This entry is full (50 parts, 10 photos).');
    } catch (_) {
      if (mounted) context.showErrorSnackbar("Couldn't do that. Please try again.");
    }
  }

  Future<ImageSource?> _askSource() => showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Camera'),
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Photo library'),
            onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );

  /// Insert, as in a word processor: where the cursor is (splitting the
  /// paragraph mid-way), else after the block last tapped, else at the end.
  Future<void> _insert(PlanningBlockType type) async {
    Map<String, dynamic>? payload;
    if (type == PlanningBlockType.photo) {
      final source = await _askSource();
      if (source == null || !mounted) return;
      final picked = await ref.read(planningPhotoPickerProvider)(source, 1);
      if (!mounted) return;
      if (picked.photos.isEmpty) {
        if (picked.rejected > 0) context.showWarningSnackbar("That photo couldn't be used.");
        return;
      }
      final path = await _upload(picked.photos.first);
      if (path == null) return;
      payload = {'path': path};
    }
    await _place(type == PlanningBlockType.photo ? 'photo' : 'text', payload);
  }

  /// The photo goes up first; only then is its block made (nothing is ever
  /// half-saved). A failure offers Retry.
  Future<String?> _upload(Uint8List jpeg) async {
    final path = _ctl.newPhotoPath();
    try {
      await ref.read(journalMediaGatewayProvider).uploadJpeg(path, jpeg);
      return path;
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar("Couldn't add this photo — try again.", actionLabel: 'Retry', onAction: () async {
          final retried = await _upload(jpeg);
          if (retried != null) await _place('photo', {'path': retried});
        });
      }
      return null;
    }
  }

  Future<void> _place(String kind, Map<String, dynamic>? payload) => _guard(() async {
    final blocks = ref.read(journalEntryDetailProvider(widget.entryId)).valueOrNull?.blocks ?? const <JournalBlock>[];
    final active = _doc.active;
    if (active != null && blocks.any((b) => b.id == active.blockId)) {
      if (!await active.flush()) return;
      final c = active.controller;
      final plain = c.document.toPlainText();
      final at = c.selection.baseOffset.clamp(0, plain.length);
      final added = plain.substring(0, at).trim().isNotEmpty && plain.substring(at).trim().isNotEmpty
          ? await _ctl.insertAtCursor(kind,
              textBlockId: active.blockId,
              version: active.version(),
              before: sanitizeDelta(c.document.toDelta().slice(0, at).toJson()).ops,
              after: sanitizeDelta(c.document.toDelta().slice(at).toJson()).ops,
              payload: payload)
          : await _ctl.addBlock(kind, payload: payload, afterId: active.blockId);
      if (kind == 'text') _doc.focusWhenShown(added.id);
      return;
    }
    final selected = _doc.selectedBlockId;
    final after = blocks.any((b) => b.id == selected) ? selected : null;
    final added = await _ctl.addBlock(kind, payload: payload, afterId: after);
    if (after == null) _doc.revealEnd();
    if (kind == 'text') _doc.focusWhenShown(added.id);
  });

  Future<void> _confirmDelete() async {
    await BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 400.h,
      context: context,
      widget: ConfirmationDialog(
        type: ConfirmationType.warning,
        icon: Icons.delete,
        title: 'Delete this entry?',
        message: "This can't be undone. The entry, its photos and its reflection will be permanently removed.",
        confirmText: 'Delete',
        onConfirm: () async {
          try {
            await _repo.purgeEntry(widget.entryId);
          } catch (_) {
            if (mounted) context.showErrorSnackbar("Couldn't delete it. Please try again.");
            return;
          }
          _list.forget(widget.entryId);
          if (mounted) context.pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalEntryDetailProvider(widget.entryId));
    _last = async.valueOrNull ?? _last;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop),
      child: PlanningDocScope(
        controller: _doc,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(), // hides the keyboard, which saves
          child: Scaffold(
            appBar: AppBar(
              centerTitle: false,
              actions: [
                if (async.valueOrNull case final d?)
                  PopupMenuButton<_EntryMenu>(
                    tooltip: 'Entry options',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (m) => switch (m) {
                      _EntryMenu.pin => _guard(() => _ctl.setPinned(true)),
                      _EntryMenu.unpin => _guard(() => _ctl.setPinned(false)),
                      _EntryMenu.delete => _confirmDelete(),
                    },
                    itemBuilder: (_) => [
                      if (d.entry.pinnedAt == null)
                        const PopupMenuItem(value: _EntryMenu.pin, child: Text('Pin'))
                      else
                        const PopupMenuItem(value: _EntryMenu.unpin, child: Text('Unpin')),
                      const PopupMenuItem(value: _EntryMenu.delete, child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            body: Column(children: [
              Expanded(
                child: async.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: ErrorStateWidget(
                      title: "Couldn't open this entry",
                      primaryActionLabel: 'Try again',
                      onPrimaryAction: () => ref.invalidate(journalEntryDetailProvider(widget.entryId)),
                    ),
                  ),
                  data: _page,
                ),
              ),
              if (async.hasValue)
                PlanningRibbon(tools: journalBlockTools, onInsert: (t) => _insert(t)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _page(JournalEntryDetail d) {
    _doc.seed(d.blocks.map((b) => b.id));
    final firstText = d.blocks.where((b) => b.isText).firstOrNull?.id;
    final showPrompt = widget.isNew && widget.prompt != null && !_promptDismissed;
    return ReorderableListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      scrollController: _doc.scroll,
      buildDefaultDragHandles: false,
      padding: Spacing.horizontalMd,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _TitleField(entryId: widget.entryId, detail: d),
        if (showPrompt)
          _PromptCard(prompt: widget.prompt!, onDismiss: () => setState(() => _promptDismissed = true)),
      ]),
      footer: Column(children: [
        if (d.analysis case final a? when a.status == 'completed' && (a.observation ?? '').isNotEmpty)
          _ReflectionCard(tone: a.tone, observation: a.observation!),
        const SizedBox(height: Spacing.xxl * 2),
      ]),
      itemCount: d.blocks.length,
      onReorder: (from, to) => _guard(() => _ctl.moveBlock(d.blocks[from].id, to > from ? to - 1 : to)),
      itemBuilder: (context, i) {
        final b = d.blocks[i];
        final name = b.isPhoto ? 'photo' : 'text';
        final menu = PopupMenuButton<_BlockMenu>(
          tooltip: 'Options for $name',
          onSelected: (m) => switch (m) {
            _BlockMenu.up => _guard(() => _ctl.moveBlock(b.id, i - 1)),
            _BlockMenu.down => _guard(() => _ctl.moveBlock(b.id, i + 1)),
            _BlockMenu.remove => _guard(() => _ctl.deleteBlock(b.id)),
          },
          itemBuilder: (_) => [
            if (i > 0) const PopupMenuItem(value: _BlockMenu.up, child: Text('Move up')),
            if (i < d.blocks.length - 1) const PopupMenuItem(value: _BlockMenu.down, child: Text('Move down')),
            if (d.blocks.length > 1) const PopupMenuItem(value: _BlockMenu.remove, child: Text('Remove')),
          ],
        );
        final body = b.isText
            ? NoteTextBlock(
                key: ValueKey('text-${b.id}'),
                blockId: b.id,
                delta: b.delta,
                version: b.version,
                autofocus: widget.isNew && b.id == firstText,
                placeholder: 'Write what’s on your mind…',
                saverFor: (ref) => JournalTextSaver(
                  ref,
                  widget.entryId,
                  visit: _visit,
                  titleFromFirstLine: () =>
                      b.id == firstText && (_last?.entry.title ?? '').trim().isEmpty,
                ),
              )
            : JournalPhotoBlock(path: b.photoPath ?? '');
        return ReorderableDelayedDragStartListener(
          key: ValueKey('block-${b.id}'),
          index: i,
          child: GestureDetector(
            onTap: b.isPhoto ? () => _doc.select(b.id) : null,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: body), menu]),
          ),
        );
      },
    );
  }
}

class _TitleField extends ConsumerStatefulWidget {
  const _TitleField({required this.entryId, required this.detail});
  final String entryId;
  final JournalEntryDetail detail;

  @override
  ConsumerState<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends ConsumerState<_TitleField> {
  late final _c = TextEditingController(text: widget.detail.entry.title ?? '');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_TitleField old) {
    super.didUpdateWidget(old);
    // Titled from the first line, or renamed on another device.
    final t = widget.detail.entry.title ?? '';
    if (!_focus.hasFocus && t != _c.text) _c.text = t;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _c.text.trim();
    if (t == (widget.detail.entry.title ?? '')) return;
    try {
      await ref.read(journalEntryDetailProvider(widget.entryId).notifier).rename(t.isEmpty ? null : t);
    } catch (_) {
      if (mounted) {
        _c.text = widget.detail.entry.title ?? '';
        context.showErrorSnackbar("Couldn't rename it. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: TextField(
      controller: _c,
      focusNode: _focus,
      style: Theme.of(context).textTheme.headlineSmall,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      inputFormatters: [CodePointLengthFormatter(120)],
      maxLines: null,
      decoration: InputDecoration(
        hintText: DateFormat('EEEE, d MMMM').format(widget.detail.entry.createdAt.toLocal()),
        filled: false,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      ),
      onSubmitted: (_) => _focus.unfocus(),
    ),
  );
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, required this.onDismiss});
  final String prompt;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.xs, Spacing.sm),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadiusTokens.mdAll),
      child: Row(children: [
        Icon(Icons.lightbulb_outline_rounded, color: scheme.primary, size: 20),
        const SizedBox(width: Spacing.sm),
        Expanded(child: Text(prompt, style: Theme.of(context).textTheme.bodyMedium)),
        IconButton(tooltip: 'Dismiss prompt', icon: const Icon(Icons.close_rounded), onPressed: onDismiss),
      ]),
    );
  }
}

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({required this.tone, required this.observation});
  final String? tone;
  final String observation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: Spacing.md),
      padding: Spacing.allMd,
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadiusTokens.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('A reflection', style: text.titleSmall),
          if (tone != null) ...[
            const SizedBox(width: Spacing.sm),
            Chip(label: Text(tone!), visualDensity: VisualDensity.compact),
          ],
        ]),
        const SizedBox(height: Spacing.xs),
        Text(observation, style: text.bodyMedium),
      ]),
    );
  }
}
```

Add `import 'dart:typed_data';` for `_upload`'s `Uint8List`. Check that the following exist under these names, and use the real names if any differ:
- the import paths of `CodePointLengthFormatter` and `truncateCodePoints` (`domain/code_point_limit.dart`);
- `Spacing.xxl`;
- `BorderRadiusTokens.mdAll`;
- `ConfirmationDialog`'s parameters (copy the deleted detail screen's `_confirmDelete`, which used `type`, `icon`, `title`, `message`, `confirmText` and `onConfirm`);
- `context.pop` (go_router, exported by `export_screens.dart`).

Ledger any renames.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `flutter test test/features/reflection_journal/`
Expected: PASS, with the 11 screen tests plus the earlier data and list tests.

---

### Task 6: Spec rulings, full verification, device checklist

- [ ] **Step 1: Append §10 to the spec** (`docs/superpowers/specs/2026-10-14-journal-notes-design.md`)

```markdown
## 10. Plan rulings (plan `2026-10-14-journal-notes.md`)
- R1: The shared editor pieces keep their Planning paths (Planning's tests import them there); only the date grouping and the section card moved to `lib/core/notes/`. The text block is `NoteTextBlock` (with `InlineTextBlock` a thin Planning subclass).
- R2: No entry-level version; per-block versions cover text from two devices, structural changes reload.
- R3: A photo block stores only its path; photos show in a 4:3 frame and open full size.
- R4: A failed photo upload is a snackbar with Retry; the block is created only after the upload.
- R5: An entry's only block can't be deleted.
- R6: The backfill splits text over 3,000 characters into several blocks; content is unchanged.
- R7: One `journalEntry` route replaces compose and detail.
```

- [ ] **Step 2: Full verification**

Run, in order:
- `bash <scratchpad>/pg/run.sh /Users/user/attune/supabase/tests/journal_notes_contracts.sql`, which should PASS;
- `flutter test`, where every test should pass;
- `flutter analyze lib`, with no errors and no new warnings in the touched files;
- `flutter build apk --debug --target-platform android-arm64`;
- `flutter build ios --simulator --debug`.

Expected: all green. Report the suite count.

- [ ] **Step 3: Deploy notes and the owner device checklist (for the final report)**

**Deploy:** `supabase db push` applies `20261014190000_journal_notes.sql` (with the backfill) and `20261014200000_journal_media_bucket.sql`. Nothing else is deployed, because `analyse-journal-entry` is unchanged.

**Device checks:**
1. The Entries tab shows Pinned, Today, Yesterday and so on, as cards of rows. Old entries are there, titled by their date.
2. Tapping `+` opens a ready-to-write entry with a prompt. Type, use formatting, add a photo from the camera and from the library, then leave. Reopen it: everything is there. A minute later, "A reflection" appears.
3. An empty new entry, when you leave it, does not appear in the list.
4. Swipe to delete, then Undo; swipe to pin.
5. Open the entry on a second phone, edit it on both, and see the conflict sheet.
6. Your partner's account sees nothing of your journal anywhere.
7. Delete an entry that has photos. In the Supabase storage browser, the files are gone after the media-deletion drain runs.

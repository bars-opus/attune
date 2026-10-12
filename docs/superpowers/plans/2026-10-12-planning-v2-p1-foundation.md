# Planning v2 — P1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Planning v2 data model (categories → entries → blocks → items), its server RPCs, and a preview-only Flutter UI with Text (rich), Checklist and Date blocks — alongside v1, which keeps serving users untouched.

**Architecture:** New Postgres tables with no client grants; every read and write goes through `SECURITY DEFINER` RPCs that resolve the target row, check membership, lock in a fixed order (category → entry → block → item), enforce limits, and bump v1's existing `planning_change_signals`. Flutter code lives under `lib/features/planning/v2/` (data / domain / presentation), reuses v1's RPC gateway, relationship-id provider, change-signal provider and keyset pager by import only, and is reachable only in builds made with `--dart-define=PLANNING_V2_PREVIEW=true`.

**Tech Stack:** Postgres 17 (PL/pgSQL), Supabase RPC, Flutter 3.29.1 / Dart 3.7, Riverpod 2, `flutter_quill` 11.x (new), `shared_preferences`, `uuid`.

**Spec:** `docs/superpowers/specs/2026-10-12-planning-v2-design.md` (sections cited per task as §n).

## Global Constraints

- Work only in the worktree `/Users/user/attune/.worktrees/planning-v2`, branch `feat/planning-advance`. Never `cd` to `/Users/user/attune`.
- Migration filenames use the range `20261012200000`–`20261012299999` only. The Games session owns `20261012100000`+.
- **v1 must keep working unchanged.** Do not modify any v1 migration, v1 table, v1 RPC, or any file under `lib/features/planning/` outside `lib/features/planning/v2/`, with exactly one exception: Task 14 adds one guarded button to `planning_home_screen.dart`.
- **Do not modify** `lib/main.dart`, `lib/app/app.dart`, `lib/app/routing/app_router.dart`, or any widget under `lib/core/`. v2 navigation uses `Navigator.push` in P1.
- New RPC names must not collide with v1 names (`update_planning_item`, `delete_planning_item`, … are v1). v2 item RPCs use the `_block_item` suffix.
- Every public RPC: `SECURITY DEFINER`, `SET search_path = public`, `REVOKE ALL … FROM PUBLIC, anon`, `GRANT EXECUTE … TO authenticated`. Every internal helper: `REVOKE ALL … FROM PUBLIC, anon, authenticated`.
- v2 tables: RLS enabled, **no policies, no grants** to `anon`/`authenticated`. Revocations live in dedicated `*_table_grants.sql` migrations that `scripts/local_pg_grants.sql` re-applies (the repo convention): the local harness — like Supabase itself — grants every table to `authenticated` after migrations run, so an inline `REVOKE` alone is overridden locally. The only shared file this plan touches outside `lib/features/planning/` is `scripts/local_pg_grants.sql` (two appended `\i` lines, Tasks 1 and 3).
- No dynamic SQL (`EXECUTE format(...)`) anywhere in v2 migrations.
- Errors are raised only through `planning_v2_fail(code, detail)`, producing SQLSTATE `P0001`, message `planning:<code>`, and a JSON `HINT`. Codes: `unauthenticated`, `not_found`, `inactive`, `stale_version`, `limit_reached`, `invalid_input`. Forbidden and missing both produce `not_found`.
- Limits (spec §3.11), verbatim: categories 50 · blocks per entry 200 · items per block 500 · block payload 16384 bytes · table 12 columns × 50 rows · photos per block 10 · image 10485760 bytes · text plain 10000 chars · entries page default 30, max 100 · entry title 120 · category name 40 · item text 500 · section 40.
- Rich-text whitelist (spec §6.1), verbatim: `bold`, `italic`, `underline`, `strike` (true) · `background`, `color` ∈ {`yellow`,`green`,`blue`,`pink`,`purple`} · `header` ∈ {1,2,3} · `align` ∈ {`center`,`right`,`justify`} · `list` ∈ {`bullet`,`ordered`} · `blockquote` (true) · `link` (http/https, ≤ 2048). No embeds.
- Money is never `double` (spec D14). P1 stores no money, but no `double` may appear in any v2 model field that later carries money.
- UI: spacing from `Spacing`, radii from `BorderRadiusTokens`, durations from `AnimationDurations` (`lib/app/theme/design_tokens.dart`). Colours from the `ColorScheme`. Touch targets ≥ 44pt. Every screen has a first-load, retained-on-refresh, empty, and error state.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Plan-level rulings (deviations from the spec, each deliberate)

| # | Ruling | Why | Cost if wrong |
|---|---|---|---|
| R1 | Storage bucket `planning-media` is created in P3, not P1 | Nothing in P1 uploads | None; P3 adds it |
| R2 | Entries are ordered by `last_activity_at DESC, id DESC`; no manual entry reorder; `planning_entries` has no sort key | Entries are unlimited; fractional keys grow without bound under repeated top inserts | Users wanting manual entry order; additive later |
| R3 | Sort keys are generated **server-side only** (`planning_key_between`); Dart never computes keys | One authority; no client/server drift | None |
| R4 | No table grants, not even SELECT (spec §4 said RLS-read) | Least privilege (checklist 7.4); all reads are RPCs | None |
| R5 | `planning_starter_templates` stores versioned starter definitions; `planning_entries.seed_version` marks an unedited seeded template, which auto-upgrades when a newer version ships | P2 ships before P3/P4 add block types to starters | An edited template never upgrades (by design; "Reset" exists) |
| R6 | `planning_entries.last_activity_at/by` and `planning_category_seen` added | Needed for the "new" dot (spec D7) to exclude your own edits | None |
| R7 | `planning_applied_ops(op_id)` dedupes outbox ticks | Spec §6.2 requires op-id idempotency | None |
| R8 | Byte limit uses `octet_length(payload::text)`, not `pg_column_size` | Deterministic regardless of TOAST compression | None |
| R9 | Preview gate is `--dart-define=PLANNING_V2_PREVIEW=true` plus one guarded button in v1 home | Keeps router and shared files untouched until P2 | None |

## Review Focus

1. **Both partners open Planning for the first time at the same moment** → exactly six starter categories and six templates exist, never twelve. Test: Task 3 Step 1, contract `seed_race` (advisory lock), plus `planning_v2_concurrency.sh` case 1 (Task 5).
2. **A partner deletes a block or item while the other is editing it** → the editor's save gets `not_found` (not a crash, not a resurrection); UI drops the block with a snackbar. Test: Task 5 contract `update_after_delete`; Task 13 widget test `save after the partner deleted the block`.
3. **A tick made offline is replayed after the partner already unticked it** → the replay does not double-apply (same op id is a no-op), and a *new* op applies last-writer-wins. Test: Task 5 contract `op_replay`; Task 8 outbox test `replay is idempotent`.
4. **Pasting rich text from another app (Word/Notes) brings attributes outside the whitelist** (font, size, `#hex` colour, checklist list) → the client strips them before save so the user never sees a server rejection for something they didn't type. Test: Task 8 `sanitizeDelta` tests; Task 13 widget test `pasted foreign attributes are stripped`.
5. **Emoji, RTL and combining characters in titles, items and text** → length limits count characters, not bytes; round-trip unchanged. Test: Task 2 contract `unicode_lengths`; Task 7 model round-trip test.

---

## File map

**Migrations** (`supabase/migrations/`)
| File | Responsibility |
|---|---|
| `20261012200000_planning_v2_schema.sql` | Tables, indexes, constraints, triggers, RLS-on/no-grants |
| `20261012200010_planning_v2_table_grants.sql` | Re-appliable revocations (harness convention) |
| `20261012200100_planning_v2_helpers.sql` | Limits, error raiser, actor resolution, sort keys, Delta + block + item validation |
| `20261012200200_planning_v2_categories.sql` | Starter definitions, seeding/upgrade, block instantiate/copy, touch, category RPCs, `get_planning_home` |
| `20261012200210_planning_v2_starter_template_grants.sql` | Re-appliable revocation for starter definitions |
| `20261012200300_planning_v2_entries.sql` | Entry RPCs, `list_planning_entries`, `get_planning_entry`, template reset |
| `20261012200400_planning_v2_blocks_items.sql` | Block and item RPCs incl. checked-with-op-id |
| `20261012200500_planning_v2_retention.sql` | `planning_v2_purge()` + daily cron |

**SQL tests** (`supabase/tests/`): `planning_v2_schema_contracts.sql`, `planning_v2_helpers_contracts.sql`, `planning_v2_category_contracts.sql`, `planning_v2_entry_contracts.sql`, `planning_v2_block_item_contracts.sql`, `planning_v2_retention_contracts.sql`, `planning_v2_concurrency.sh`.

**Flutter** (`lib/features/planning/v2/`)
| File | Responsibility |
|---|---|
| `data/planning_v2_error.dart` | Sealed error type + mapping from `PostgrestException` |
| `data/planning_v2_models.dart` | Category, entry summary/detail, block, item, member, page |
| `data/planning_v2_repository.dart` | One method per RPC |
| `domain/planning_v2_limits.dart` | Dart mirror of `planning_limits()` |
| `domain/delta_sanitizer.dart` | Whitelist mirror: strip foreign attributes, validate |
| `domain/planning_outbox.dart` | Persisted bounded outbox with backoff replay |
| `presentation/planning_v2_providers.dart` | Repository, home, entries pager, entry controller, outbox |
| `presentation/planning_v2_ui.dart` | Icon/colour tokens, highlight palette, route helper, error/empty states, date formatting |
| `presentation/screens/planning_v2_home_screen.dart` | Category list |
| `presentation/screens/planning_v2_category_screen.dart` | Entry list + new-entry sheet |
| `presentation/screens/planning_v2_entry_screen.dart` | Hero header + block stack + tool tray |
| `presentation/screens/planning_v2_text_editor_screen.dart` | Full-screen Quill editor |
| `presentation/widgets/category_editor_sheet.dart` | Create/edit category |
| `presentation/widgets/block_tool_tray.dart` | "+" tray |
| `presentation/widgets/checklist_block_view.dart` | Checklist block |
| `presentation/widgets/date_block_view.dart` | Date block |
| `presentation/widgets/text_block_view.dart` | Read-only rich text render |
| `presentation/widgets/planning_quill.dart` | Quill localization scope and token-aware editor config |
| `presentation/widgets/conflict_sheet.dart` | Keep mine / Use theirs / Copy mine |

**Flutter tests** (`test/features/planning/v2/`): one file per unit above.

---

### Task 1: Schema

**Files:**
- Create: `supabase/migrations/20261012200000_planning_v2_schema.sql`
- Create: `supabase/migrations/20261012200010_planning_v2_table_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (append one `\i` line)
- Test: `supabase/tests/planning_v2_schema_contracts.sql`

**Interfaces:**
- Produces tables: `planning_categories`, `planning_entries`, `planning_blocks`, `planning_block_items`, `planning_applied_ops`, `planning_category_seen` with the exact columns below. Later tasks reference these column names verbatim. Ordering column is `sort_key text COLLATE "C"` (not `position`).

- [ ] **Step 1: Write the failing contract test**

`supabase/tests/planning_v2_schema_contracts.sql`:

```sql
-- Planning v2 schema contracts (P1 Task 1).
-- Run: psql -q -d attune_test -f supabase/tests/planning_v2_schema_contracts.sql
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel  uuid := '2a000000-0000-0000-0000-000000000001';
  v_rel2 uuid := '2a000000-0000-0000-0000-000000000002';
  v_a uuid := '2a000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2a000000-0000-0000-0000-0000000000b1';
  v_c uuid := '2a000000-0000-0000-0000-0000000000c1';
  v_d uuid := '2a000000-0000-0000-0000-0000000000d1';
  v_cat uuid := '2a000000-0000-0000-0000-00000000ca01';
  v_cat2 uuid := '2a000000-0000-0000-0000-00000000ca02';
  v_ent uuid := '2a000000-0000-0000-0000-00000000e001';
  v_blk uuid := '2a000000-0000-0000-0000-00000000b001';
  v_n int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_a,'v2s_a@t.test'),(v_b,'v2s_b@t.test'),(v_c,'v2s_c@t.test'),(v_d,'v2s_d@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12000000001','A'),(v_b,'+12000000002','B'),(v_c,'+12000000003','C'),(v_d,'+12000000004','D')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
    (v_rel, v_a, v_b, 'active'), (v_rel2, v_c, v_d, 'active')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.planning_categories (id, relationship_id, seed_key, name, icon, color, sort_key)
  VALUES (v_cat, v_rel, 'goals', 'Goals', 'flag', 'rose', 'V');
  INSERT INTO public.planning_categories (id, relationship_id, name, icon, color, sort_key)
  VALUES (v_cat2, v_rel2, 'Theirs', 'star', 'teal', 'V');

  -- Contract 1: a starter category can never be soft-deleted.
  BEGIN
    UPDATE public.planning_categories SET deleted_at = now() WHERE id = v_cat;
    RAISE EXCEPTION 'EXPLOIT: starter category was soft-deleted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 2: one seed_key per relationship.
  BEGIN
    INSERT INTO public.planning_categories (id, relationship_id, seed_key, name, icon, color, sort_key)
    VALUES (gen_random_uuid(), v_rel, 'goals', 'Goals 2', 'flag', 'rose', 'k');
    RAISE EXCEPTION 'EXPLOIT: duplicate seed_key accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Contract 3: an entry cannot point at another couple's category.
  BEGIN
    INSERT INTO public.planning_entries (id, relationship_id, category_id, title)
    VALUES (gen_random_uuid(), v_rel, v_cat2, 'cross-couple');
    RAISE EXCEPTION 'EXPLOIT: cross-relationship entry accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Contract 4: exactly one live template per category.
  INSERT INTO public.planning_entries (id, relationship_id, category_id, title, is_template)
  VALUES (v_ent, v_rel, v_cat, 'Template', true);
  BEGIN
    INSERT INTO public.planning_entries (id, relationship_id, category_id, title, is_template)
    VALUES (gen_random_uuid(), v_rel, v_cat, 'Template 2', true);
    RAISE EXCEPTION 'EXPLOIT: second live template accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Contract 5: a template can never enable split.
  BEGIN
    UPDATE public.planning_entries SET split_enabled = true WHERE id = v_ent;
    RAISE EXCEPTION 'EXPLOIT: template split enabled';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 6: payload over 16384 bytes is rejected by the table itself.
  BEGIN
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, block_type, sort_key, payload)
    VALUES (gen_random_uuid(), v_rel, v_ent, 'text', 'V',
            jsonb_build_object('delta', repeat('x', 16400)));
    RAISE EXCEPTION 'EXPLOIT: oversized payload accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 7: unknown block type rejected.
  BEGIN
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, block_type, sort_key)
    VALUES (gen_random_uuid(), v_rel, v_ent, 'video', 'V');
    RAISE EXCEPTION 'EXPLOIT: unknown block type accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 8: date_end before date_start rejected.
  BEGIN
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, block_type, sort_key, date_start, date_end)
    VALUES (gen_random_uuid(), v_rel, v_ent, 'date', 'V', '2026-11-10', '2026-11-01');
    RAISE EXCEPTION 'EXPLOIT: inverted date range accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 9: sort keys compare bytewise ('Z' < 'a'), not by locale.
  INSERT INTO public.planning_blocks (id, relationship_id, entry_id, block_type, sort_key)
  VALUES (v_blk, v_rel, v_ent, 'checklist', 'a'),
         (gen_random_uuid(), v_rel, v_ent, 'checklist', 'Z');
  SELECT count(*) INTO v_n FROM (
    SELECT sort_key, row_number() OVER (ORDER BY sort_key) rn
    FROM public.planning_blocks WHERE entry_id = v_ent) s
  WHERE (rn = 1 AND sort_key = 'Z') OR (rn = 2 AND sort_key = 'a');
  IF v_n <> 2 THEN RAISE EXCEPTION 'EXPLOIT: sort_key is not byte-ordered'; END IF;

  -- Contract 10: an item cannot point at another couple's block.
  BEGIN
    INSERT INTO public.planning_block_items (id, relationship_id, block_id, sort_key, text)
    VALUES (gen_random_uuid(), v_rel2, v_blk, 'V', 'cross');
    RAISE EXCEPTION 'EXPLOIT: cross-relationship item accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Contract 11: clients have no table privileges at all.
  SELECT count(*) INTO v_n
  FROM information_schema.role_table_grants
  WHERE grantee IN ('anon','authenticated','PUBLIC')
    AND table_schema = 'public'
    AND table_name IN ('planning_categories','planning_entries','planning_blocks',
                       'planning_block_items','planning_applied_ops','planning_category_seen');
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: v2 table granted to a client role (% grants)', v_n; END IF;

  -- Contract 12: RLS is on for every v2 table.
  SELECT count(*) INTO v_n FROM pg_class
  WHERE relnamespace = 'public'::regnamespace
    AND relname IN ('planning_categories','planning_entries','planning_blocks',
                    'planning_block_items','planning_applied_ops','planning_category_seen')
    AND relrowsecurity;
  IF v_n <> 6 THEN RAISE EXCEPTION 'EXPLOIT: RLS missing on % v2 tables', 6 - v_n; END IF;

  -- Contract 13: updated_at is maintained by trigger.
  UPDATE public.planning_entries SET title = 'Template renamed' WHERE id = v_ent
    RETURNING (updated_at > created_at)::int INTO v_n;
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: updated_at not touched'; END IF;

  -- Contract 14: relationship hard delete cascades all v2 rows.
  DELETE FROM public.relationships WHERE id = v_rel;
  SELECT (SELECT count(*) FROM public.planning_categories WHERE relationship_id = v_rel)
       + (SELECT count(*) FROM public.planning_entries    WHERE relationship_id = v_rel)
       + (SELECT count(*) FROM public.planning_blocks     WHERE relationship_id = v_rel)
    INTO v_n;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: relationship delete left % v2 rows', v_n; END IF;

  RAISE NOTICE 'planning_v2_schema_contracts: PASS';
END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/local_pg_setup.sh --no-tests && psql -q -d attune_test -f supabase/tests/planning_v2_schema_contracts.sql`
Expected: FAIL with `relation "public.planning_categories" does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/20261012200000_planning_v2_schema.sql`:

```sql
-- Planning v2 schema (P1 Foundation).
-- Spec: docs/superpowers/specs/2026-10-12-planning-v2-design.md §3.
-- v1 tables (planning_items/events/event_tasks/notes) are untouched;
-- v1's planning_change_signals is reused by v2 RPCs (spec §3.8).
--
-- No client grants, not even SELECT (plan ruling R4): every v2 read
-- and write is a SECURITY DEFINER RPC.
--
-- Ordering columns are `sort_key text COLLATE "C"`: fractional base-62
-- keys must compare bytewise ('0'<'9'<'A'<'Z'<'a'<'z'), never by locale.

CREATE OR REPLACE FUNCTION public.planning_v2_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_touch_updated_at() FROM PUBLIC, anon, authenticated;

CREATE TABLE public.planning_categories (
  id              uuid PRIMARY KEY,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  created_by      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  seed_key        text CHECK (seed_key IN ('goals','trips','date_nights','home_bills','groceries','everyday')),
  name            text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40 AND name = btrim(name)),
  icon            text NOT NULL CHECK (char_length(icon) BETWEEN 1 AND 32),
  color           text NOT NULL CHECK (char_length(color) BETWEEN 1 AND 32),
  sort_key        text COLLATE "C" NOT NULL CHECK (char_length(sort_key) BETWEEN 1 AND 64),
  hidden_at       timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (id, relationship_id),
  CONSTRAINT planning_categories_seed_unique UNIQUE (relationship_id, seed_key),
  CONSTRAINT planning_category_starter_never_deleted CHECK (seed_key IS NULL OR deleted_at IS NULL)
);
CREATE INDEX idx_planning_categories_home
  ON public.planning_categories (relationship_id, sort_key, id) WHERE deleted_at IS NULL;

CREATE TABLE public.planning_entries (
  id               uuid PRIMARY KEY,
  relationship_id  uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  category_id      uuid NOT NULL,
  created_by       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  is_template      boolean NOT NULL DEFAULT false,
  seed_version     int,
  title            text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120 AND title = btrim(title)),
  cover_path       text CHECK (cover_path IS NULL OR char_length(cover_path) <= 300),
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active','done','archived')),
  currency         char(3) NOT NULL DEFAULT 'USD' CHECK (currency ~ '^[A-Z]{3}$'),
  split_enabled    boolean NOT NULL DEFAULT false,
  split_settled_at timestamptz,
  celebrated_at    timestamptz,
  last_activity_at timestamptz NOT NULL DEFAULT now(),
  last_activity_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,
  UNIQUE (id, relationship_id),
  CONSTRAINT planning_entry_category_same_relationship
    FOREIGN KEY (category_id, relationship_id)
    REFERENCES public.planning_categories(id, relationship_id) ON DELETE CASCADE,
  CONSTRAINT planning_template_never_split CHECK (NOT (is_template AND split_enabled)),
  CONSTRAINT planning_seed_version_template_only CHECK (seed_version IS NULL OR is_template),
  CONSTRAINT planning_template_always_active CHECK (NOT is_template OR status = 'active')
);
CREATE UNIQUE INDEX planning_entries_one_template
  ON public.planning_entries (category_id) WHERE is_template AND deleted_at IS NULL;
CREATE INDEX idx_planning_entries_list
  ON public.planning_entries (category_id, last_activity_at DESC, id DESC)
  WHERE deleted_at IS NULL AND NOT is_template;

CREATE TABLE public.planning_blocks (
  id              uuid PRIMARY KEY,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  entry_id        uuid NOT NULL,
  created_by      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  block_type      text NOT NULL CHECK (block_type IN (
                    'text','checklist','table','date','date_poll','countdown','expenses',
                    'budget','progress','photo','link','place','dual_clock')),
  sort_key        text COLLATE "C" NOT NULL CHECK (char_length(sort_key) BETWEEN 1 AND 64),
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb
                    CHECK (jsonb_typeof(payload) = 'object' AND octet_length(payload::text) <= 16384),
  plain_text      text CHECK (plain_text IS NULL OR char_length(plain_text) <= 10000),
  date_start      date,
  date_end        date,
  target_minor    bigint CHECK (target_minor IS NULL OR target_minor >= 0),
  target_currency char(3) CHECK (target_currency IS NULL OR target_currency ~ '^[A-Z]{3}$'),
  version         int NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (id, relationship_id),
  CONSTRAINT planning_block_entry_same_relationship
    FOREIGN KEY (entry_id, relationship_id)
    REFERENCES public.planning_entries(id, relationship_id) ON DELETE CASCADE,
  CONSTRAINT planning_block_date_range
    CHECK (date_end IS NULL OR (date_start IS NOT NULL AND date_end >= date_start))
);
CREATE INDEX idx_planning_blocks_entry
  ON public.planning_blocks (entry_id, sort_key, id) WHERE deleted_at IS NULL;
CREATE INDEX idx_planning_blocks_calendar
  ON public.planning_blocks (relationship_id, date_start, id)
  WHERE deleted_at IS NULL AND block_type = 'date' AND date_start IS NOT NULL;

CREATE TABLE public.planning_block_items (
  id                uuid PRIMARY KEY,
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  block_id          uuid NOT NULL,
  created_by        uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  sort_key          text COLLATE "C" NOT NULL CHECK (char_length(sort_key) BETWEEN 1 AND 64),
  text              text CHECK (text IS NULL OR char_length(text) <= 500),
  section           text CHECK (section IS NULL OR char_length(section) BETWEEN 1 AND 40),
  checked_at        timestamptz,
  checked_by        uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  assigned_to       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  due_date          date,
  amount_minor      bigint CHECK (amount_minor IS NULL OR amount_minor >= 0),
  currency          char(3) CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
  paid_by           uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  split_share_minor bigint CHECK (split_share_minor IS NULL OR split_share_minor >= 0),
  date_start        date,
  date_end          date,
  cells             jsonb CHECK (cells IS NULL OR (jsonb_typeof(cells) = 'object' AND octet_length(cells::text) <= 4096)),
  version           int NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,
  UNIQUE (id, relationship_id),
  CONSTRAINT planning_item_block_same_relationship
    FOREIGN KEY (block_id, relationship_id)
    REFERENCES public.planning_blocks(id, relationship_id) ON DELETE CASCADE,
  CONSTRAINT planning_item_checked_shape CHECK (checked_by IS NULL OR checked_at IS NOT NULL),
  CONSTRAINT planning_item_date_range
    CHECK (date_end IS NULL OR (date_start IS NOT NULL AND date_end >= date_start))
);
CREATE INDEX idx_planning_block_items_block
  ON public.planning_block_items (block_id, sort_key, id) WHERE deleted_at IS NULL;
CREATE INDEX idx_planning_block_items_calendar
  ON public.planning_block_items (relationship_id, due_date, id)
  WHERE deleted_at IS NULL AND due_date IS NOT NULL;

-- Outbox replay dedupe (plan ruling R7). Pruned after 7 days by Task 6.
CREATE TABLE public.planning_applied_ops (
  op_id           uuid PRIMARY KEY,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  applied_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_planning_applied_ops_age ON public.planning_applied_ops (applied_at);

-- Per-user "seen" marker for the category "new" dot (plan ruling R6).
CREATE TABLE public.planning_category_seen (
  category_id     uuid NOT NULL,
  relationship_id uuid NOT NULL,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seen_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (category_id, user_id),
  CONSTRAINT planning_seen_category_same_relationship
    FOREIGN KEY (category_id, relationship_id)
    REFERENCES public.planning_categories(id, relationship_id) ON DELETE CASCADE
);

CREATE TRIGGER planning_categories_touch BEFORE UPDATE ON public.planning_categories
  FOR EACH ROW EXECUTE FUNCTION public.planning_v2_touch_updated_at();
CREATE TRIGGER planning_entries_touch BEFORE UPDATE ON public.planning_entries
  FOR EACH ROW EXECUTE FUNCTION public.planning_v2_touch_updated_at();
CREATE TRIGGER planning_blocks_touch BEFORE UPDATE ON public.planning_blocks
  FOR EACH ROW EXECUTE FUNCTION public.planning_v2_touch_updated_at();
CREATE TRIGGER planning_block_items_touch BEFORE UPDATE ON public.planning_block_items
  FOR EACH ROW EXECUTE FUNCTION public.planning_v2_touch_updated_at();

ALTER TABLE public.planning_categories    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_entries       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_blocks        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_block_items   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_applied_ops   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_category_seen ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.planning_categories    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_entries       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_blocks        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_block_items   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_applied_ops   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_category_seen FROM PUBLIC, anon, authenticated;
```

Note on Contract 13: `planning_v2_touch_updated_at` uses `clock_timestamp()`, so `updated_at > created_at` holds even inside one transaction (where `now()` is fixed).

- [ ] **Step 3b: Write the grants migration and register it with the harness**

Why a separate file: `scripts/local_pg_setup.sh` runs `scripts/local_pg_grants.sql` **after** all migrations, and that script grants SELECT/INSERT/UPDATE/DELETE on every public table to `authenticated` (mirroring Supabase's platform default), then re-applies each feature's `*_table_grants.sql`. Without this file, Contract 11 fails with `30 grants` — verified while writing this plan.

`supabase/migrations/20261012200010_planning_v2_table_grants.sql`:

```sql
-- Planning v2 table grants (P1 Task 1). Plan ruling R4: no client
-- privileges at all; every read and write is a SECURITY DEFINER RPC.
-- Re-applied by scripts/local_pg_grants.sql after the harness's blanket
-- platform grant, exactly like 20260941030000_planning_table_grants.sql.
REVOKE ALL ON public.planning_categories    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_entries       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_blocks        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_block_items   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_applied_ops   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_category_seen FROM PUBLIC, anon, authenticated;
```

Append this line to the end of `scripts/local_pg_grants.sql` (after the existing `\i …feature_flags_table_grants.sql` line):

```sql
\i supabase/migrations/20261012200010_planning_v2_table_grants.sql
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/local_pg_setup.sh --no-tests && psql -q -d attune_test -f supabase/tests/planning_v2_schema_contracts.sql`
Expected: `NOTICE:  planning_v2_schema_contracts: PASS`. Also confirm the migration count line from `local_pg_setup.sh` reports 0 failed.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261012200000_planning_v2_schema.sql supabase/migrations/20261012200010_planning_v2_table_grants.sql scripts/local_pg_grants.sql supabase/tests/planning_v2_schema_contracts.sql
git commit -m "feat(planning-v2): schema for categories, entries, blocks and items

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Helpers — limits, errors, actor, sort keys, validation

**Files:**
- Create: `supabase/migrations/20261012200100_planning_v2_helpers.sql`
- Test: `supabase/tests/planning_v2_helpers_contracts.sql`

**Interfaces:**
- Consumes: Task 1 tables.
- Produces (all internal unless noted):
  - `planning_limits() RETURNS jsonb` — granted to `authenticated` (read-only constants).
  - `planning_v2_fail(p_code text, p_detail jsonb DEFAULT '{}') RETURNS void` — raises.
  - `planning_v2_actor(p_relationship_id uuid) RETURNS uuid` — `auth.uid()` if active member; else raises `unauthenticated` / `not_found` / `inactive`.
  - `planning_v2_is_member(p_relationship_id uuid, p_user uuid) RETURNS boolean`.
  - `planning_key_between(p_a text, p_b text) RETURNS text` — `p_a` NULL = start, `p_b` NULL = end.
  - `planning_even_keys(p_n int) RETURNS text[]` — n ≤ 700 evenly spaced 2-char keys.
  - `planning_v2_icons() RETURNS text[]`, `planning_v2_colors() RETURNS text[]`.
  - `planning_validate_delta(p_delta jsonb) RETURNS text` — plain-text projection.
  - `planning_v2_validate_block(p_type text, p_payload jsonb, p_date_start date, p_date_end date) RETURNS text` — plain text or NULL.
  - `planning_v2_validate_item(p_block_type text, p_relationship_id uuid, p_text text, p_section text, p_assigned_to uuid) RETURNS void`.

- [ ] **Step 1: Write the failing contract test**

`supabase/tests/planning_v2_helpers_contracts.sql`:

```sql
-- Planning v2 helper contracts (P1 Task 2).
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2b000000-0000-0000-0000-000000000001';
  v_ended uuid := '2b000000-0000-0000-0000-000000000002';
  v_a uuid := '2b000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2b000000-0000-0000-0000-0000000000b1';
  v_x uuid := '2b000000-0000-0000-0000-0000000000e1';
  v_keys text[];
  v_k text;
  v_lo text;
  v_hi text;
  v_i int;
  v_plain text;
  v_msg text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2h_a@t.test'),(v_b,'v2h_b@t.test'),(v_x,'v2h_x@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12100000001','A'),(v_b,'+12100000002','B'),(v_x,'+12100000003','X')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
    (v_rel, v_a, v_b, 'active'), (v_ended, v_a, v_x, 'ended')
  ON CONFLICT DO NOTHING;

  -- Contract 1: limits are exactly the spec's values.
  IF public.planning_limits() <> '{"categories":50,"blocks_per_entry":200,"items_per_block":500,
      "payload_bytes":16384,"table_columns":12,"table_rows":50,"photos_per_block":10,
      "image_bytes":10485760,"text_plain_chars":10000,"entries_page_default":30,
      "entries_page_max":100,"title_chars":120,"category_name_chars":40,
      "item_text_chars":500,"section_chars":40}'::jsonb THEN
    RAISE EXCEPTION 'EXPLOIT: planning_limits drifted from spec';
  END IF;

  -- Contract 2: actor resolution. Unauthenticated, stranger, ended, member.
  PERFORM set_config('request.jwt.claims', '{}', true);
  BEGIN PERFORM public.planning_v2_actor(v_rel); RAISE EXCEPTION 'EXPLOIT: anon resolved';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:unauthenticated' THEN RAISE EXCEPTION 'EXPLOIT: wrong code %', SQLERRM; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.planning_v2_actor(v_rel); RAISE EXCEPTION 'EXPLOIT: stranger resolved';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:not_found' THEN RAISE EXCEPTION 'EXPLOIT: stranger got %', SQLERRM; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  BEGIN PERFORM public.planning_v2_actor(v_ended); RAISE EXCEPTION 'EXPLOIT: ended resolved';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:inactive' THEN RAISE EXCEPTION 'EXPLOIT: ended got %', SQLERRM; END IF;
  END;
  IF public.planning_v2_actor(v_rel) <> v_a THEN RAISE EXCEPTION 'EXPLOIT: member not resolved'; END IF;

  -- Contract 3: the HINT carries the detail as JSON.
  BEGIN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"blocks_per_entry"}');
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = PG_EXCEPTION_HINT;
    IF v_msg::jsonb ->> 'limit' IS DISTINCT FROM 'blocks_per_entry' THEN
      RAISE EXCEPTION 'EXPLOIT: hint lost detail: %', v_msg;
    END IF;
  END;

  -- Contract 4 (property, checklist 6.5): 1000 random insertions always
  -- produce a key strictly between its neighbours, never ending in '0',
  -- never longer than 64.
  v_keys := ARRAY[public.planning_key_between(NULL, NULL)];
  FOR v_i IN 1..1000 LOOP
    DECLARE v_pos int := floor(random() * (array_length(v_keys,1) + 1))::int; BEGIN
      v_lo := CASE WHEN v_pos = 0 THEN NULL ELSE v_keys[v_pos] END;
      v_hi := CASE WHEN v_pos = array_length(v_keys,1) THEN NULL ELSE v_keys[v_pos+1] END;
      v_k := public.planning_key_between(v_lo, v_hi);
      IF (v_lo IS NOT NULL AND NOT (v_k COLLATE "C" > v_lo COLLATE "C"))
         OR (v_hi IS NOT NULL AND NOT (v_k COLLATE "C" < v_hi COLLATE "C"))
         OR right(v_k, 1) = '0' OR char_length(v_k) > 64 THEN
        RAISE EXCEPTION 'EXPLOIT: key % not between % and %', v_k, v_lo, v_hi;
      END IF;
      v_keys := v_keys[1:v_pos] || v_k || v_keys[v_pos+1:];
    END;
  END LOOP;

  -- Contract 5: worst case, 500 inserts always at the top stay ≤ 64 chars
  -- only with rebalancing; key_between alone must at least stay valid.
  v_k := public.planning_key_between(NULL, NULL);
  FOR v_i IN 1..60 LOOP v_k := public.planning_key_between(NULL, v_k); END LOOP;
  IF char_length(v_k) > 20 THEN RAISE EXCEPTION 'EXPLOIT: top-insert growth too fast: %', char_length(v_k); END IF;

  -- Contract 6: even keys are strictly increasing, 2 chars, none ends in '0'.
  v_keys := public.planning_even_keys(700);
  FOR v_i IN 2..700 LOOP
    IF NOT (v_keys[v_i] COLLATE "C" > v_keys[v_i-1] COLLATE "C")
       OR char_length(v_keys[v_i]) <> 2 OR right(v_keys[v_i],1) = '0' THEN
      RAISE EXCEPTION 'EXPLOIT: even key % invalid at %', v_keys[v_i], v_i;
    END IF;
  END LOOP;

  -- Contract 7: valid Delta → plain text; trailing newline trimmed.
  v_plain := public.planning_validate_delta(
    '[{"insert":"Bali "},{"insert":"trip","attributes":{"bold":true,"background":"yellow"}},
      {"insert":"\n","attributes":{"header":2,"align":"center"}}]');
  IF v_plain <> 'Bali trip' THEN RAISE EXCEPTION 'EXPLOIT: plain projection wrong: %', v_plain; END IF;

  -- Contract 8: every forbidden shape is rejected as invalid_input.
  FOREACH v_k IN ARRAY ARRAY[
    '[{"insert":{"image":"x.png"}},{"insert":"\n"}]',                    -- embed
    '[{"insert":"a","attributes":{"font":"serif"}},{"insert":"\n"}]',    -- unknown attribute
    '[{"insert":"a","attributes":{"background":"#ff0000"}},{"insert":"\n"}]', -- hex colour
    '[{"insert":"a","attributes":{"link":"javascript:alert(1)"}},{"insert":"\n"}]',
    '[{"insert":"a","attributes":{"list":"checked"}},{"insert":"\n"}]',
    '[{"insert":"a","attributes":{"header":4}},{"insert":"\n"}]',
    '[{"insert":"no trailing newline"}]',
    '[{"insert":"a","retain":1},{"insert":"\n"}]',
    '{"ops":[]}',
    '[]'
  ] LOOP
    BEGIN
      PERFORM public.planning_validate_delta(v_k::jsonb);
      RAISE EXCEPTION 'EXPLOIT: delta accepted: %', v_k;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM NOT IN ('planning:invalid_input') THEN RAISE; END IF;
    END;
  END LOOP;

  -- Contract 9: plain length limit counts characters (emoji = 1 char each).
  v_plain := public.planning_validate_delta(jsonb_build_array(
    jsonb_build_object('insert', repeat('😀', 10000) || E'\n')));
  IF char_length(v_plain) <> 10000 THEN RAISE EXCEPTION 'EXPLOIT: emoji counted as bytes'; END IF;
  BEGIN
    PERFORM public.planning_validate_delta(jsonb_build_array(
      jsonb_build_object('insert', repeat('a', 10001) || E'\n')));
    RAISE EXCEPTION 'EXPLOIT: 10001 chars accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF;
  END;

  -- Contract 10 (unicode_lengths): an RTL + combining-mark section of 40
  -- characters is accepted by item validation.
  PERFORM public.planning_v2_validate_item('checklist', v_rel,
    'שלום עולם', repeat('é', 40), v_b);

  -- Contract 11: item validation rejects a non-member assignee and blank text.
  BEGIN PERFORM public.planning_v2_validate_item('checklist', v_rel, 'x', NULL, v_x);
    RAISE EXCEPTION 'EXPLOIT: stranger assignee accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.planning_v2_validate_item('checklist', v_rel, '   ', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: blank item accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 12: block validation: P1 types accepted, P3/P4 types refused.
  PERFORM public.planning_v2_validate_block('checklist', '{"title":"Packing"}', NULL, NULL);
  PERFORM public.planning_v2_validate_block('date', '{}', '2026-11-01', '2026-11-05');
  BEGIN PERFORM public.planning_v2_validate_block('budget', '{}', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: P3 block type accepted in P1';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.planning_v2_validate_block('checklist', '{"title":"x","extra":1}', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: unknown payload key accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 13: helpers are not callable by clients; limits is.
  IF has_function_privilege('authenticated', 'public.planning_v2_actor(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.planning_validate_delta(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.planning_limits()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.planning_limits()', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: helper grants wrong';
  END IF;

  RAISE NOTICE 'planning_v2_helpers_contracts: PASS';
END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/local_pg_setup.sh --no-tests && psql -q -d attune_test -f supabase/tests/planning_v2_helpers_contracts.sql`
Expected: FAIL with `function public.planning_limits() does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/20261012200100_planning_v2_helpers.sql`:

```sql
-- Planning v2 internal helpers (P1 Task 2).
-- Spec §3.7 (ordering), §3.11 (limits), §6.1 (rich-text whitelist), §7.2 (errors).

-- Limits: the single source of truth. lib/features/planning/v2/domain/
-- planning_v2_limits.dart mirrors this literal; a Dart test parses this
-- file and asserts equality, so neither can drift alone.
CREATE OR REPLACE FUNCTION public.planning_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"categories":50,"blocks_per_entry":200,"items_per_block":500,"payload_bytes":16384,"table_columns":12,"table_rows":50,"photos_per_block":10,"image_bytes":10485760,"text_plain_chars":10000,"entries_page_default":30,"entries_page_max":100,"title_chars":120,"category_name_chars":40,"item_text_chars":500,"section_chars":40}'::jsonb;
$$;
REVOKE ALL ON FUNCTION public.planning_limits() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.planning_limits() TO authenticated;

-- The only way a v2 RPC fails. Message is a stable machine code; HINT
-- is JSON detail. The Dart repository maps on the message, never on
-- free text (planning_v2_error.dart).
CREATE OR REPLACE FUNCTION public.planning_v2_fail(p_code text, p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = 'P0001',
    MESSAGE = 'planning:' || p_code,
    HINT = coalesce(p_detail, '{}'::jsonb)::text;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_fail(text, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_v2_is_member(p_relationship_id uuid, p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id AND (r.user_a = p_user OR r.user_b = p_user));
$$;
REVOKE ALL ON FUNCTION public.planning_v2_is_member(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Resolves the caller. not_found for "not yours" (no existence oracle);
-- inactive only when the caller IS a member of an ended/archived couple.
CREATE OR REPLACE FUNCTION public.planning_v2_actor(p_relationship_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_rel public.relationships;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.planning_v2_fail('unauthenticated'); END IF;
  SELECT * INTO v_rel FROM public.relationships
  WHERE id = p_relationship_id AND (user_a = v_uid OR user_b = v_uid);
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_rel.status <> 'active' OR v_rel.chat_archived_at IS NOT NULL THEN
    PERFORM public.planning_v2_fail('inactive');
  END IF;
  RETURN v_uid;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_actor(uuid) FROM PUBLIC, anon, authenticated;

-- Fractional base-62 keys (spec §3.7). Keys never end in '0', so there
-- is always room below. Returns a key strictly between p_a and p_b.
CREATE OR REPLACE FUNCTION public.planning_key_between(p_a text, p_b text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  c_digits constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  v_a  text := coalesce(p_a, '');
  v_n  int := 0;
  v_da int;
  v_db int;
BEGIN
  IF p_b IS NOT NULL AND v_a COLLATE "C" >= p_b COLLATE "C" THEN
    RAISE EXCEPTION 'planning_key_between: % >= %', p_a, p_b;
  END IF;
  IF p_b IS NOT NULL THEN
    WHILE v_n < char_length(p_b)
      AND coalesce(nullif(substr(v_a, v_n + 1, 1), ''), '0') = substr(p_b, v_n + 1, 1) LOOP
      v_n := v_n + 1;
    END LOOP;
    IF v_n > 0 THEN
      RETURN substr(p_b, 1, v_n)
        || public.planning_key_between(substr(v_a, v_n + 1), substr(p_b, v_n + 1));
    END IF;
  END IF;
  v_da := CASE WHEN v_a = '' THEN 0 ELSE strpos(c_digits, substr(v_a, 1, 1)) - 1 END;
  v_db := CASE WHEN p_b IS NULL THEN 62 ELSE strpos(c_digits, substr(p_b, 1, 1)) - 1 END;
  IF v_db - v_da > 1 THEN
    RETURN substr(c_digits, ((v_da + v_db + 1) / 2) + 1, 1);
  END IF;
  IF p_b IS NOT NULL AND char_length(p_b) > 1 THEN
    RETURN substr(p_b, 1, 1);
  END IF;
  RETURN substr(c_digits, v_da + 1, 1) || public.planning_key_between(substr(v_a, 2), NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.planning_key_between(text, text) FROM PUBLIC, anon, authenticated;

-- n evenly spaced 2-char keys (3844 slots). Used for seeding and for
-- rebalancing a sibling set whose keys grew past 32 chars.
CREATE OR REPLACE FUNCTION public.planning_even_keys(p_n int)
RETURNS text[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  c_digits constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  v_out text[] := '{}';
  v_val int;
  v_i int;
BEGIN
  IF p_n < 0 OR p_n > 700 THEN RAISE EXCEPTION 'planning_even_keys: n=% out of range', p_n; END IF;
  FOR v_i IN 1..p_n LOOP
    v_val := (v_i * 3844) / (p_n + 1);
    IF v_val % 62 = 0 THEN v_val := v_val + 1; END IF;
    v_out := v_out || (substr(c_digits, (v_val / 62) + 1, 1) || substr(c_digits, (v_val % 62) + 1, 1));
  END LOOP;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_even_keys(int) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_v2_icons()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['flag','plane','heart','home','cart','sun','star','gift','book',
               'dumbbell','utensils','baby','ring','box','music','paw'];
$$;
CREATE OR REPLACE FUNCTION public.planning_v2_colors()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['rose','amber','teal','indigo','green','slate','violet','orange'];
$$;
REVOKE ALL ON FUNCTION public.planning_v2_icons() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_colors() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_delta_attribute_ok(p_key text, p_val jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_key
    WHEN 'bold'       THEN p_val = 'true'::jsonb
    WHEN 'italic'     THEN p_val = 'true'::jsonb
    WHEN 'underline'  THEN p_val = 'true'::jsonb
    WHEN 'strike'     THEN p_val = 'true'::jsonb
    WHEN 'blockquote' THEN p_val = 'true'::jsonb
    WHEN 'background' THEN p_val IN ('"yellow"','"green"','"blue"','"pink"','"purple"')
    WHEN 'color'      THEN p_val IN ('"yellow"','"green"','"blue"','"pink"','"purple"')
    WHEN 'header'     THEN p_val IN ('1','2','3')
    WHEN 'align'      THEN p_val IN ('"center"','"right"','"justify"')
    WHEN 'list'       THEN p_val IN ('"bullet"','"ordered"')
    WHEN 'link'       THEN jsonb_typeof(p_val) = 'string'
                           AND char_length(p_val #>> '{}') <= 2048
                           AND (p_val #>> '{}') ~* '^https?://[^[:space:]]+$'
    ELSE false
  END;
$$;
REVOKE ALL ON FUNCTION public.planning_delta_attribute_ok(text, jsonb) FROM PUBLIC, anon, authenticated;

-- Validates a Quill Delta against the spec §6.1 whitelist and returns
-- its plain-text projection (trailing newlines trimmed).
CREATE OR REPLACE FUNCTION public.planning_validate_delta(p_delta jsonb)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_op    jsonb;
  v_key   text;
  v_val   jsonb;
  v_plain text := '';
  v_last  text := '';
BEGIN
  IF p_delta IS NULL OR jsonb_typeof(p_delta) <> 'array'
     OR jsonb_array_length(p_delta) = 0 OR jsonb_array_length(p_delta) > 2000 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"delta"}');
  END IF;
  FOR v_op IN SELECT value FROM jsonb_array_elements(p_delta) LOOP
    IF jsonb_typeof(v_op) <> 'object' THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"delta"}');
    END IF;
    FOR v_key IN SELECT jsonb_object_keys(v_op) LOOP
      IF v_key NOT IN ('insert', 'attributes') THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"delta"}');
      END IF;
    END LOOP;
    IF jsonb_typeof(v_op -> 'insert') IS DISTINCT FROM 'string' THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"embed"}');
    END IF;
    IF v_op ? 'attributes' THEN
      IF jsonb_typeof(v_op -> 'attributes') <> 'object' THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"attribute"}');
      END IF;
      FOR v_key, v_val IN SELECT key, value FROM jsonb_each(v_op -> 'attributes') LOOP
        IF NOT public.planning_delta_attribute_ok(v_key, v_val) THEN
          PERFORM public.planning_v2_fail('invalid_input',
            jsonb_build_object('field', 'attribute', 'attribute', v_key));
        END IF;
      END LOOP;
    END IF;
    v_last := v_op ->> 'insert';
    v_plain := v_plain || v_last;
  END LOOP;
  IF right(v_last, 1) <> E'\n' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"delta"}');
  END IF;
  v_plain := regexp_replace(v_plain, E'\n+$', '');
  IF char_length(v_plain) > 10000 THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"text_plain_chars"}');
  END IF;
  RETURN v_plain;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_validate_delta(jsonb) FROM PUBLIC, anon, authenticated;

-- Per-type block validation. P1 accepts text / checklist / date only;
-- P3 and P4 extend this function (CREATE OR REPLACE) for their types.
CREATE OR REPLACE FUNCTION public.planning_v2_validate_block(
  p_type text, p_payload jsonb, p_date_start date, p_date_end date
) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_key text;
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
  END IF;
  IF octet_length(p_payload::text) > 16384 THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"payload_bytes"}');
  END IF;

  IF p_type = 'text' THEN
    FOR v_key IN SELECT jsonb_object_keys(p_payload) LOOP
      IF v_key <> 'delta' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}'); END IF;
    END LOOP;
    IF p_date_start IS NOT NULL OR p_date_end IS NOT NULL THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    RETURN public.planning_validate_delta(p_payload -> 'delta');
  ELSIF p_type IN ('checklist', 'date') THEN
    FOR v_key IN SELECT jsonb_object_keys(p_payload) LOOP
      IF v_key <> 'title' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}'); END IF;
    END LOOP;
    IF p_payload ? 'title' AND (
         jsonb_typeof(p_payload -> 'title') <> 'string'
         OR char_length(btrim(p_payload ->> 'title')) NOT BETWEEN 1 AND 80) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
    END IF;
    IF p_type = 'checklist' AND (p_date_start IS NOT NULL OR p_date_end IS NOT NULL) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    IF p_type = 'date' AND p_date_end IS NOT NULL
       AND (p_date_start IS NULL OR p_date_end < p_date_start) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    RETURN NULL;
  END IF;

  PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_validate_block(text, jsonb, date, date) FROM PUBLIC, anon, authenticated;

-- Per-block-type item validation. P1: checklist items only.
CREATE OR REPLACE FUNCTION public.planning_v2_validate_item(
  p_block_type text, p_relationship_id uuid, p_text text, p_section text, p_assigned_to uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_block_type <> 'checklist' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  END IF;
  IF p_text IS NULL OR char_length(btrim(p_text)) NOT BETWEEN 1 AND 500 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"text"}');
  END IF;
  IF p_section IS NOT NULL AND char_length(btrim(p_section)) NOT BETWEEN 1 AND 40 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"section"}');
  END IF;
  IF p_assigned_to IS NOT NULL AND NOT public.planning_v2_is_member(p_relationship_id, p_assigned_to) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"assigned_to"}');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_validate_item(text, uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/local_pg_setup.sh --no-tests && for f in supabase/tests/planning_v2_*_contracts.sql; do psql -q -d attune_test -f "$f" || exit 1; done`
Expected: both `…: PASS` notices.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261012200100_planning_v2_helpers.sql supabase/tests/planning_v2_helpers_contracts.sql
git commit -m "feat(planning-v2): limits, typed errors, sort keys and rich-text validation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Starters, seeding, ordering helpers, category RPCs, home read

**Files:**
- Create: `supabase/migrations/20261012200200_planning_v2_categories.sql`
- Create: `supabase/migrations/20261012200210_planning_v2_starter_template_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (append one `\i` line)
- Test: `supabase/tests/planning_v2_category_contracts.sql`

**Interfaces:**
- Consumes: Task 1 tables; Task 2 helpers; v1's `bump_planning_signal(uuid)` (unchanged, internal).
- Produces:
  - Table `planning_starter_templates(seed_key PK, version, name, icon, color, rank, template_title, blocks jsonb)`.
  - Internal: `planning_v2_instantiate_blocks(p_rel uuid, p_entry_id uuid, p_actor uuid, p_blocks jsonb)`, `planning_v2_copy_blocks(p_rel uuid, p_src uuid, p_dst uuid, p_actor uuid)`, `planning_v2_touch_entry(p_entry_id uuid, p_actor uuid)`, `planning_v2_ensure_starters(p_rel uuid)`, `planning_v2_key_after_category(p_rel uuid, p_after_id uuid, p_exclude uuid) RETURNS text`, `planning_v2_key_after_block(p_entry uuid, p_after_id uuid, p_exclude uuid) RETURNS text`, `planning_v2_key_after_item(p_block uuid, p_after_id uuid, p_exclude uuid) RETURNS text`, `planning_v2_rebalance_categories(p_rel uuid)`, `planning_v2_rebalance_blocks(p_entry uuid)`, `planning_v2_rebalance_items(p_block uuid)`.
  - Public RPCs (all return `jsonb`):
    - `get_planning_home(p_relationship_id uuid)` → `{"categories":[{id, seed_key, name, icon, color, sort_key, hidden, template_entry_id, entry_count, has_new}]}`
    - `create_planning_category(p_id uuid, p_relationship_id uuid, p_name text, p_icon text, p_color text)` → category row
    - `update_planning_category(p_id uuid, p_name text, p_icon text, p_color text)` → category row
    - `set_planning_category_hidden(p_id uuid, p_hidden boolean)` → category row
    - `delete_planning_category(p_id uuid)` → `{"deleted_entries": n}`
    - `move_planning_category(p_id uuid, p_after_id uuid)` → category row (`p_after_id` NULL = first)
    - `mark_planning_category_seen(p_id uuid)` → `{"seen_at": ts}`

- [ ] **Step 1: Write the failing contract test**

`supabase/tests/planning_v2_category_contracts.sql`:

```sql
-- Planning v2 category contracts (P1 Task 3).
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2c000000-0000-0000-0000-000000000001';
  v_a uuid := '2c000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2c000000-0000-0000-0000-0000000000b1';
  v_x uuid := '2c000000-0000-0000-0000-0000000000e1';
  v_custom uuid := '2c000000-0000-0000-0000-00000000c001';
  v_home jsonb;
  v_cat jsonb;
  v_goals uuid;
  v_tpl uuid;
  v_n int;
  v_i int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2c_a@t.test'),(v_b,'v2c_b@t.test'),(v_x,'v2c_x@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12200000001','Ama'),(v_b,'+12200000002','Kofi'),(v_x,'+12200000003','X')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 1: first home read seeds five visible starters in order;
  -- Everyday exists but is hidden while empty.
  v_home := public.get_planning_home(v_rel);
  IF (SELECT array_agg(c ->> 'seed_key' ORDER BY ord)
        FROM jsonb_array_elements(v_home -> 'categories') WITH ORDINALITY t(c, ord))
     IS DISTINCT FROM ARRAY['goals','trips','date_nights','home_bills','groceries'] THEN
    RAISE EXCEPTION 'EXPLOIT: starters wrong: %', v_home;
  END IF;
  SELECT count(*) INTO v_n FROM public.planning_categories WHERE relationship_id = v_rel;
  IF v_n <> 6 THEN RAISE EXCEPTION 'EXPLOIT: expected 6 seeded categories, got %', v_n; END IF;

  -- Contract 2: every starter has exactly one template with blocks.
  SELECT count(*) INTO v_n FROM public.planning_categories c
  WHERE c.relationship_id = v_rel AND (
    SELECT count(*) FROM public.planning_entries e
    WHERE e.category_id = c.id AND e.is_template AND e.deleted_at IS NULL) <> 1;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: % starters without exactly one template', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.planning_block_items i
  JOIN public.planning_blocks b ON b.id = i.block_id
  JOIN public.planning_entries e ON e.id = b.entry_id
  JOIN public.planning_categories c ON c.id = e.category_id
  WHERE c.relationship_id = v_rel AND c.seed_key = 'home_bills';
  IF v_n <> 5 THEN RAISE EXCEPTION 'EXPLOIT: Home & bills template should have 5 bill items, got %', v_n; END IF;

  -- Contract 3: re-reading home never re-seeds.
  PERFORM public.get_planning_home(v_rel);
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_b), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT count(*) INTO v_n FROM public.planning_categories WHERE relationship_id = v_rel;
  IF v_n <> 6 THEN RAISE EXCEPTION 'EXPLOIT: re-read reseeded (% categories)', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.planning_entries WHERE relationship_id = v_rel AND is_template;
  IF v_n <> 6 THEN RAISE EXCEPTION 'EXPLOIT: re-read duplicated templates (%)', v_n; END IF;

  -- Contract 4: a stranger gets not_found, never a seed.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.get_planning_home(v_rel); RAISE EXCEPTION 'EXPLOIT: stranger read home';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'Sneak', 'star', 'teal');
    RAISE EXCEPTION 'EXPLOIT: stranger created category';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 5: create a custom category; it appends last, gets a blank template.
  v_cat := public.create_planning_category(v_custom, v_rel, '  Wedding  ', 'ring', 'violet');
  IF v_cat ->> 'name' <> 'Wedding' THEN RAISE EXCEPTION 'EXPLOIT: name not trimmed'; END IF;
  v_home := public.get_planning_home(v_rel);
  IF (v_home -> 'categories' -> -1 ->> 'id')::uuid <> v_custom THEN
    RAISE EXCEPTION 'EXPLOIT: custom category not last';
  END IF;
  SELECT count(*) INTO v_n FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id WHERE e.category_id = v_custom;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: custom template not blank'; END IF;

  -- Contract 6: idempotent create; conflicting reuse rejected.
  v_cat := public.create_planning_category(v_custom, v_rel, 'Wedding', 'ring', 'violet');
  BEGIN PERFORM public.create_planning_category(v_custom, v_rel, 'Baby', 'baby', 'rose');
    RAISE EXCEPTION 'EXPLOIT: id reuse with different payload accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 7: icon and colour must be from the allow-lists.
  BEGIN PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'X', 'skull', 'teal');
    RAISE EXCEPTION 'EXPLOIT: unknown icon accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'X', 'star', '#ff0000');
    RAISE EXCEPTION 'EXPLOIT: hex colour accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 8: move to first; hide; rename.
  v_cat := public.move_planning_category(v_custom, NULL);
  v_home := public.get_planning_home(v_rel);
  IF (v_home -> 'categories' -> 0 ->> 'id')::uuid <> v_custom THEN RAISE EXCEPTION 'EXPLOIT: move to first failed'; END IF;
  v_cat := public.set_planning_category_hidden(v_custom, true);
  v_home := public.get_planning_home(v_rel);
  IF NOT (v_home -> 'categories' -> 0 ->> 'hidden')::boolean THEN RAISE EXCEPTION 'EXPLOIT: hidden flag not reported'; END IF;
  v_cat := public.update_planning_category(v_custom, 'Our wedding', 'ring', 'rose');
  IF v_cat ->> 'name' <> 'Our wedding' OR v_cat ->> 'color' <> 'rose' THEN RAISE EXCEPTION 'EXPLOIT: rename failed'; END IF;

  -- Contract 9: starters cannot be deleted; custom can, taking entries with it.
  SELECT id INTO v_goals FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'goals';
  BEGIN PERFORM public.delete_planning_category(v_goals);
    RAISE EXCEPTION 'EXPLOIT: starter deleted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  INSERT INTO public.planning_entries (id, relationship_id, category_id, title, created_by)
  VALUES (gen_random_uuid(), v_rel, v_custom, 'Venue', v_a);
  v_cat := public.delete_planning_category(v_custom);
  IF (v_cat ->> 'deleted_entries')::int <> 1 THEN RAISE EXCEPTION 'EXPLOIT: delete count wrong: %', v_cat; END IF;
  SELECT count(*) INTO v_n FROM public.planning_entries WHERE category_id = v_custom AND deleted_at IS NULL;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: entries survived category delete'; END IF;
  BEGIN PERFORM public.update_planning_category(v_custom, 'Back', 'ring', 'rose');
    RAISE EXCEPTION 'EXPLOIT: deleted category updated';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;

  -- Contract 10: limit of 50 live categories.
  FOR v_i IN 1..44 LOOP
    PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'C' || v_i, 'star', 'teal');
  END LOOP;
  BEGIN PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'C51', 'star', 'teal');
    RAISE EXCEPTION 'EXPLOIT: 51st category accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF; END;

  -- Contract 11: "new" dot = partner activity after my last seen; never my own.
  UPDATE public.planning_entries SET last_activity_at = clock_timestamp(), last_activity_by = v_a
  WHERE category_id = v_goals AND is_template;  -- templates never count
  INSERT INTO public.planning_entries (id, relationship_id, category_id, title, created_by, last_activity_by)
  VALUES (gen_random_uuid(), v_rel, v_goals, 'Save for a car', v_b, v_b);
  v_home := public.get_planning_home(v_rel);
  IF NOT (SELECT (c ->> 'has_new')::boolean FROM jsonb_array_elements(v_home -> 'categories') c
          WHERE c ->> 'seed_key' = 'goals') THEN
    RAISE EXCEPTION 'EXPLOIT: partner activity not flagged new';
  END IF;
  PERFORM public.mark_planning_category_seen(v_goals);
  v_home := public.get_planning_home(v_rel);
  IF (SELECT (c ->> 'has_new')::boolean FROM jsonb_array_elements(v_home -> 'categories') c
      WHERE c ->> 'seed_key' = 'goals') THEN
    RAISE EXCEPTION 'EXPLOIT: seen category still new';
  END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_b), true);
  v_home := public.get_planning_home(v_rel);
  IF (SELECT (c ->> 'has_new')::boolean FROM jsonb_array_elements(v_home -> 'categories') c
      WHERE c ->> 'seed_key' = 'goals') THEN
    RAISE EXCEPTION 'EXPLOIT: own activity flagged new';
  END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 12: Everyday appears once it has an entry.
  INSERT INTO public.planning_entries (id, relationship_id, category_id, title)
  SELECT gen_random_uuid(), v_rel, id, 'Note' FROM public.planning_categories
  WHERE relationship_id = v_rel AND seed_key = 'everyday';
  v_home := public.get_planning_home(v_rel);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_home -> 'categories') c WHERE c ->> 'seed_key' = 'everyday') THEN
    RAISE EXCEPTION 'EXPLOIT: non-empty Everyday hidden';
  END IF;

  -- Contract 13: an unedited template auto-upgrades; an edited one does not.
  SELECT e.id INTO v_tpl FROM public.planning_entries e
  JOIN public.planning_categories c ON c.id = e.category_id
  WHERE c.relationship_id = v_rel AND c.seed_key = 'trips' AND e.is_template;
  UPDATE public.planning_entries SET seed_version = NULL
  FROM public.planning_categories c
  WHERE planning_entries.category_id = c.id AND c.relationship_id = v_rel AND c.seed_key = 'groceries'
    AND planning_entries.is_template;                                  -- groceries "edited"
  UPDATE public.planning_starter_templates
     SET version = version + 1,
         blocks = '[{"type":"text","payload":{"delta":[{"insert":"Upgraded\n"}]}}]'
   WHERE seed_key IN ('trips','groceries');
  PERFORM public.get_planning_home(v_rel);
  SELECT count(*) INTO v_n FROM public.planning_blocks WHERE entry_id = v_tpl AND deleted_at IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: unedited template not upgraded (% blocks)', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id
  JOIN public.planning_categories c ON c.id = e.category_id
  WHERE c.relationship_id = v_rel AND c.seed_key = 'groceries' AND e.is_template
    AND b.deleted_at IS NULL AND b.plain_text = 'Upgraded';
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: edited template was overwritten'; END IF;

  -- Contract 14: inactive relationship fails closed with inactive.
  UPDATE public.relationships SET status = 'ended' WHERE id = v_rel;
  BEGIN PERFORM public.get_planning_home(v_rel); RAISE EXCEPTION 'EXPLOIT: ended couple read home';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:inactive' THEN RAISE; END IF; END;

  -- Contract 15: grants (functions, and the starter-definitions table).
  IF EXISTS (SELECT 1 FROM information_schema.role_table_grants
             WHERE grantee IN ('anon','authenticated','PUBLIC') AND table_schema = 'public'
               AND table_name = 'planning_starter_templates') THEN
    RAISE EXCEPTION 'EXPLOIT: starter templates table granted to a client';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.get_planning_home(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_planning_home(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.planning_v2_ensure_starters(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: category RPC grants wrong';
  END IF;

  RAISE NOTICE 'planning_v2_category_contracts: PASS';
END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/local_pg_setup.sh --no-tests && psql -q -d attune_test -f supabase/tests/planning_v2_category_contracts.sql`
Expected: FAIL with `function public.get_planning_home(uuid) does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/20261012200200_planning_v2_categories.sql`:

```sql
-- Planning v2 categories, starters, ordering helpers (P1 Task 3).
-- Spec §4, §4.1, §5; plan rulings R3, R5, R6.

-- Versioned starter definitions (plan ruling R5). P1 uses only text /
-- checklist / date blocks; P3 and P4 bump `version` with richer blocks,
-- and unedited seeded templates upgrade on the next home read.
CREATE TABLE public.planning_starter_templates (
  seed_key       text PRIMARY KEY,
  version        int  NOT NULL CHECK (version >= 1),
  name           text NOT NULL,
  icon           text NOT NULL,
  color          text NOT NULL,
  rank           int  NOT NULL UNIQUE,
  template_title text NOT NULL,
  blocks         jsonb NOT NULL CHECK (jsonb_typeof(blocks) = 'array')
);
ALTER TABLE public.planning_starter_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.planning_starter_templates FROM PUBLIC, anon, authenticated;

INSERT INTO public.planning_starter_templates (seed_key, version, name, icon, color, rank, template_title, blocks) VALUES
('goals', 1, 'Goals', 'flag', 'rose', 1, 'New goal', $j$[
  {"type":"date","payload":{"title":"Target date"}},
  {"type":"text","payload":{"delta":[{"insert":"Why this matters to us"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}},
  {"type":"checklist","payload":{"title":"Steps"}}
]$j$),
('trips', 1, 'Trips', 'plane', 'teal', 2, 'New trip', $j$[
  {"type":"date","payload":{"title":"Trip dates"}},
  {"type":"text","payload":{"delta":[{"insert":"Destination & ideas"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}},
  {"type":"checklist","payload":{"title":"Packing"},"items":[{"text":"Passports"},{"text":"Chargers"},{"text":"Toiletries"}]},
  {"type":"text","payload":{"delta":[{"insert":"Notes"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}}
]$j$),
('date_nights', 1, 'Date nights', 'heart', 'violet', 3, 'New date night', $j$[
  {"type":"date","payload":{"title":"When"}},
  {"type":"text","payload":{"delta":[{"insert":"The plan"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}},
  {"type":"text","payload":{"delta":[{"insert":"What we loved"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}}
]$j$),
('home_bills', 1, 'Home & bills', 'home', 'amber', 4, 'This month', $j$[
  {"type":"checklist","payload":{"title":"Bills"},"items":[{"text":"Rent"},{"text":"Electricity"},{"text":"Water"},{"text":"Internet"},{"text":"TV"}]},
  {"type":"text","payload":{"delta":[{"insert":"Notes"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}}
]$j$),
('groceries', 1, 'Groceries', 'cart', 'green', 5, 'Shopping run', $j$[
  {"type":"checklist","payload":{"title":"Shopping list"},"items":[
    {"text":"Tomatoes","section":"Produce"},{"text":"Onions","section":"Produce"},
    {"text":"Milk","section":"Dairy"},{"text":"Eggs","section":"Dairy"},
    {"text":"Chicken","section":"Meat & fish"},
    {"text":"Rice","section":"Pantry"},
    {"text":"Soap","section":"Household"}]}
]$j$),
('everyday', 1, 'Everyday', 'sun', 'slate', 6, 'New note', $j$[
  {"type":"text","payload":{"delta":[{"insert":"\n"}]}}
]$j$);

-- ---- ordering helpers --------------------------------------------------

CREATE OR REPLACE FUNCTION public.planning_v2_key_after_category(p_rel uuid, p_after_id uuid, p_exclude uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lo text; v_hi text;
BEGIN
  IF p_after_id IS NOT NULL THEN
    IF p_after_id = p_exclude THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
    SELECT sort_key INTO v_lo FROM public.planning_categories
    WHERE id = p_after_id AND relationship_id = p_rel AND deleted_at IS NULL;
    IF NOT FOUND THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
  END IF;
  SELECT min(sort_key) INTO v_hi FROM public.planning_categories
  WHERE relationship_id = p_rel AND deleted_at IS NULL AND id IS DISTINCT FROM p_exclude
    AND (v_lo IS NULL OR sort_key > v_lo);
  RETURN public.planning_key_between(v_lo, v_hi);
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_key_after_block(p_entry uuid, p_after_id uuid, p_exclude uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lo text; v_hi text;
BEGIN
  IF p_after_id IS NOT NULL THEN
    IF p_after_id = p_exclude THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
    SELECT sort_key INTO v_lo FROM public.planning_blocks
    WHERE id = p_after_id AND entry_id = p_entry AND deleted_at IS NULL;
    IF NOT FOUND THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
  END IF;
  SELECT min(sort_key) INTO v_hi FROM public.planning_blocks
  WHERE entry_id = p_entry AND deleted_at IS NULL AND id IS DISTINCT FROM p_exclude
    AND (v_lo IS NULL OR sort_key > v_lo);
  RETURN public.planning_key_between(v_lo, v_hi);
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_key_after_item(p_block uuid, p_after_id uuid, p_exclude uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lo text; v_hi text;
BEGIN
  IF p_after_id IS NOT NULL THEN
    IF p_after_id = p_exclude THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
    SELECT sort_key INTO v_lo FROM public.planning_block_items
    WHERE id = p_after_id AND block_id = p_block AND deleted_at IS NULL;
    IF NOT FOUND THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
  END IF;
  SELECT min(sort_key) INTO v_hi FROM public.planning_block_items
  WHERE block_id = p_block AND deleted_at IS NULL AND id IS DISTINCT FROM p_exclude
    AND (v_lo IS NULL OR sort_key > v_lo);
  RETURN public.planning_key_between(v_lo, v_hi);
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_rebalance_categories(p_rel uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_keys text[];
BEGIN
  v_keys := public.planning_even_keys((SELECT count(*)::int FROM public.planning_categories
                                       WHERE relationship_id = p_rel AND deleted_at IS NULL));
  UPDATE public.planning_categories c SET sort_key = v_keys[o.rn]
  FROM (SELECT id, row_number() OVER (ORDER BY sort_key, id) AS rn
        FROM public.planning_categories WHERE relationship_id = p_rel AND deleted_at IS NULL) o
  WHERE c.id = o.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_rebalance_blocks(p_entry uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_keys text[];
BEGIN
  v_keys := public.planning_even_keys((SELECT count(*)::int FROM public.planning_blocks
                                       WHERE entry_id = p_entry AND deleted_at IS NULL));
  UPDATE public.planning_blocks b SET sort_key = v_keys[o.rn]
  FROM (SELECT id, row_number() OVER (ORDER BY sort_key, id) AS rn
        FROM public.planning_blocks WHERE entry_id = p_entry AND deleted_at IS NULL) o
  WHERE b.id = o.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_rebalance_items(p_block uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_keys text[];
BEGIN
  v_keys := public.planning_even_keys((SELECT count(*)::int FROM public.planning_block_items
                                       WHERE block_id = p_block AND deleted_at IS NULL));
  UPDATE public.planning_block_items i SET sort_key = v_keys[o.rn]
  FROM (SELECT id, row_number() OVER (ORDER BY sort_key, id) AS rn
        FROM public.planning_block_items WHERE block_id = p_block AND deleted_at IS NULL) o
  WHERE i.id = o.id;
END;
$$;

-- ---- block instantiation / copy / touch ---------------------------------

CREATE OR REPLACE FUNCTION public.planning_v2_instantiate_blocks(
  p_rel uuid, p_entry_id uuid, p_actor uuid, p_blocks jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_def   jsonb;
  v_ord   bigint;
  v_keys  text[];
  v_ikeys text[];
  v_block uuid;
  v_item  jsonb;
  v_iord  bigint;
  v_plain text;
BEGIN
  v_keys := public.planning_even_keys(jsonb_array_length(p_blocks));
  FOR v_def, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(p_blocks) WITH ORDINALITY LOOP
    v_block := gen_random_uuid();
    v_plain := public.planning_v2_validate_block(v_def ->> 'type', coalesce(v_def -> 'payload', '{}'::jsonb), NULL, NULL);
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key, payload, plain_text)
    VALUES (v_block, p_rel, p_entry_id, p_actor, v_def ->> 'type', v_keys[v_ord],
            coalesce(v_def -> 'payload', '{}'::jsonb), v_plain);
    IF jsonb_array_length(coalesce(v_def -> 'items', '[]'::jsonb)) > 0 THEN
      v_ikeys := public.planning_even_keys(jsonb_array_length(v_def -> 'items'));
      FOR v_item, v_iord IN SELECT value, ordinality FROM jsonb_array_elements(v_def -> 'items') WITH ORDINALITY LOOP
        INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, text, section)
        VALUES (gen_random_uuid(), p_rel, v_block, p_actor, v_ikeys[v_iord], v_item ->> 'text', v_item ->> 'section');
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

-- Copies an entry's live blocks and items. Per spec §4, copies reset
-- per-occasion state: checked_at/checked_by and paid_by are not copied.
CREATE OR REPLACE FUNCTION public.planning_v2_copy_blocks(p_rel uuid, p_src uuid, p_dst uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_b public.planning_blocks; v_new uuid;
BEGIN
  FOR v_b IN SELECT * FROM public.planning_blocks
             WHERE entry_id = p_src AND deleted_at IS NULL ORDER BY sort_key, id LOOP
    v_new := gen_random_uuid();
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key,
      payload, plain_text, date_start, date_end, target_minor, target_currency)
    VALUES (v_new, p_rel, p_dst, p_actor, v_b.block_type, v_b.sort_key,
      v_b.payload, v_b.plain_text, v_b.date_start, v_b.date_end, v_b.target_minor, v_b.target_currency);
    INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, text, section,
      assigned_to, due_date, amount_minor, currency, split_share_minor, date_start, date_end, cells)
    SELECT gen_random_uuid(), p_rel, v_new, p_actor, sort_key, text, section,
      assigned_to, due_date, amount_minor, currency, split_share_minor, date_start, date_end, cells
    FROM public.planning_block_items WHERE block_id = v_b.id AND deleted_at IS NULL;
  END LOOP;
END;
$$;

-- Records activity for the "new" dot, and marks a template as edited
-- (seed_version NULL) so it never auto-upgrades over the couple's edits.
CREATE OR REPLACE FUNCTION public.planning_v2_touch_entry(p_entry_id uuid, p_actor uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.planning_entries
     SET last_activity_at = clock_timestamp(),
         last_activity_by = p_actor,
         seed_version = CASE WHEN is_template THEN NULL ELSE seed_version END
   WHERE id = p_entry_id;
$$;

-- Lazily seeds the six starters and upgrades unedited templates.
-- Serialized per couple, so two partners opening Planning at the same
-- moment produce one set (Review Focus 1).
CREATE OR REPLACE FUNCTION public.planning_v2_ensure_starters(p_rel uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s      public.planning_starter_templates;
  v_cat  uuid;
  v_tpl  public.planning_entries;
  v_new  uuid;
  v_keys text[] := public.planning_even_keys(6);
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('planning_v2_categories'), hashtext(p_rel::text));
  FOR s IN SELECT * FROM public.planning_starter_templates ORDER BY rank LOOP
    SELECT id INTO v_cat FROM public.planning_categories
    WHERE relationship_id = p_rel AND seed_key = s.seed_key;
    IF NOT FOUND THEN
      v_cat := gen_random_uuid();
      INSERT INTO public.planning_categories (id, relationship_id, seed_key, name, icon, color, sort_key)
      VALUES (v_cat, p_rel, s.seed_key, s.name, s.icon, s.color, v_keys[s.rank]);
      v_new := gen_random_uuid();
      INSERT INTO public.planning_entries (id, relationship_id, category_id, is_template, seed_version, title)
      VALUES (v_new, p_rel, v_cat, true, s.version, s.template_title);
      PERFORM public.planning_v2_instantiate_blocks(p_rel, v_new, NULL, s.blocks);
    ELSE
      SELECT * INTO v_tpl FROM public.planning_entries
      WHERE category_id = v_cat AND is_template AND deleted_at IS NULL FOR UPDATE;
      IF FOUND AND v_tpl.seed_version IS NOT NULL AND v_tpl.seed_version < s.version THEN
        UPDATE public.planning_blocks SET deleted_at = now()
        WHERE entry_id = v_tpl.id AND deleted_at IS NULL;
        PERFORM public.planning_v2_instantiate_blocks(p_rel, v_tpl.id, NULL, s.blocks);
        UPDATE public.planning_entries SET seed_version = s.version, title = s.template_title
        WHERE id = v_tpl.id;
      END IF;
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.planning_v2_key_after_category(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_key_after_block(uuid, uuid, uuid)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_key_after_item(uuid, uuid, uuid)     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_rebalance_categories(uuid)           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_rebalance_blocks(uuid)               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_rebalance_items(uuid)                FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_instantiate_blocks(uuid, uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_copy_blocks(uuid, uuid, uuid, uuid)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_touch_entry(uuid, uuid)              FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_ensure_starters(uuid)                FROM PUBLIC, anon, authenticated;

-- ---- public RPCs --------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_planning_home(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor  uuid := public.planning_v2_actor(p_relationship_id);
  v_result jsonb;
BEGIN
  PERFORM public.planning_v2_ensure_starters(p_relationship_id);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'seed_key', c.seed_key, 'name', c.name, 'icon', c.icon,
           'color', c.color, 'sort_key', c.sort_key, 'hidden', c.hidden_at IS NOT NULL,
           'template_entry_id', t.id,
           'entry_count', coalesce(e.cnt, 0),
           'has_new', coalesce(e.partner_at > coalesce(s.seen_at, '-infinity'::timestamptz), false)
         ) ORDER BY c.sort_key, c.id), '[]'::jsonb)
    INTO v_result
  FROM public.planning_categories c
  LEFT JOIN public.planning_entries t
         ON t.category_id = c.id AND t.is_template AND t.deleted_at IS NULL
  LEFT JOIN LATERAL (
    SELECT count(*) AS cnt,
           max(x.last_activity_at) FILTER (
             WHERE x.last_activity_by IS NOT NULL AND x.last_activity_by <> v_actor) AS partner_at
    FROM public.planning_entries x
    WHERE x.category_id = c.id AND NOT x.is_template AND x.deleted_at IS NULL
  ) e ON true
  LEFT JOIN public.planning_category_seen s ON s.category_id = c.id AND s.user_id = v_actor
  WHERE c.relationship_id = p_relationship_id AND c.deleted_at IS NULL
    AND (c.seed_key IS DISTINCT FROM 'everyday' OR coalesce(e.cnt, 0) > 0);
  RETURN jsonb_build_object('categories', v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_planning_category(
  p_id uuid, p_relationship_id uuid, p_name text, p_icon text, p_color text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := public.planning_v2_actor(p_relationship_id);
  v_name  text := btrim(p_name);
  v_row   public.planning_categories;
  v_count int;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('planning_v2_categories'), hashtext(p_relationship_id::text));
  SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id;
  IF FOUND THEN
    IF v_row.relationship_id = p_relationship_id AND v_row.deleted_at IS NULL
       AND v_row.name = v_name AND v_row.icon = p_icon AND v_row.color = p_color THEN
      RETURN to_jsonb(v_row);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 1 AND 40 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"name"}');
  END IF;
  IF p_icon IS NULL OR NOT (p_icon = ANY (public.planning_v2_icons())) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"icon"}');
  END IF;
  IF p_color IS NULL OR NOT (p_color = ANY (public.planning_v2_colors())) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"color"}');
  END IF;
  SELECT count(*) INTO v_count FROM public.planning_categories
  WHERE relationship_id = p_relationship_id AND deleted_at IS NULL;
  IF v_count >= 50 THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"categories"}');
  END IF;

  INSERT INTO public.planning_categories (id, relationship_id, created_by, name, icon, color, sort_key)
  VALUES (p_id, p_relationship_id, v_actor, v_name, p_icon, p_color,
          public.planning_key_between(
            (SELECT max(sort_key) FROM public.planning_categories
             WHERE relationship_id = p_relationship_id AND deleted_at IS NULL), NULL))
  RETURNING * INTO v_row;
  INSERT INTO public.planning_entries (id, relationship_id, category_id, created_by, is_template, title, last_activity_by)
  VALUES (gen_random_uuid(), p_relationship_id, p_id, v_actor, true, v_name, v_actor);
  IF char_length(v_row.sort_key) > 32 THEN
    PERFORM public.planning_v2_rebalance_categories(p_relationship_id);
    SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id;
  END IF;
  PERFORM public.bump_planning_signal(p_relationship_id);
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_planning_category(p_id uuid, p_name text, p_icon text, p_color text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_categories; v_name text := btrim(p_name);
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 1 AND 40 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"name"}');
  END IF;
  IF p_icon IS NULL OR NOT (p_icon = ANY (public.planning_v2_icons())) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"icon"}');
  END IF;
  IF p_color IS NULL OR NOT (p_color = ANY (public.planning_v2_colors())) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"color"}');
  END IF;
  UPDATE public.planning_categories SET name = v_name, icon = p_icon, color = p_color
  WHERE id = p_id RETURNING * INTO v_row;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_planning_category_hidden(p_id uuid, p_hidden boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_categories;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  UPDATE public.planning_categories
     SET hidden_at = CASE WHEN p_hidden THEN coalesce(hidden_at, now()) ELSE NULL END
   WHERE id = p_id AND deleted_at IS NULL RETURNING * INTO v_row;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_planning_category(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_categories; v_n int; v_now timestamptz := now();
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_row.seed_key IS NOT NULL THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"starter"}');
  END IF;
  SELECT count(*) INTO v_n FROM public.planning_entries
  WHERE category_id = p_id AND NOT is_template AND deleted_at IS NULL;
  UPDATE public.planning_block_items SET deleted_at = v_now
  WHERE deleted_at IS NULL AND block_id IN (
    SELECT b.id FROM public.planning_blocks b JOIN public.planning_entries e ON e.id = b.entry_id
    WHERE e.category_id = p_id);
  UPDATE public.planning_blocks SET deleted_at = v_now
  WHERE deleted_at IS NULL AND entry_id IN (SELECT id FROM public.planning_entries WHERE category_id = p_id);
  UPDATE public.planning_entries SET deleted_at = v_now WHERE category_id = p_id AND deleted_at IS NULL;
  UPDATE public.planning_categories SET deleted_at = v_now WHERE id = p_id;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN jsonb_build_object('deleted_entries', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.move_planning_category(p_id uuid, p_after_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_categories;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  PERFORM pg_advisory_xact_lock(hashtext('planning_v2_categories'), hashtext(v_rel::text));
  UPDATE public.planning_categories
     SET sort_key = public.planning_v2_key_after_category(v_rel, p_after_id, p_id)
   WHERE id = p_id AND deleted_at IS NULL RETURNING * INTO v_row;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF char_length(v_row.sort_key) > 32 THEN
    PERFORM public.planning_v2_rebalance_categories(v_rel);
    SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id;
  END IF;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_planning_category_seen(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_actor uuid; v_at timestamptz := clock_timestamp();
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  INSERT INTO public.planning_category_seen (category_id, relationship_id, user_id, seen_at)
  VALUES (p_id, v_rel, v_actor, v_at)
  ON CONFLICT (category_id, user_id) DO UPDATE SET seen_at = EXCLUDED.seen_at;
  RETURN jsonb_build_object('seen_at', v_at);
END;
$$;

REVOKE ALL ON FUNCTION public.get_planning_home(uuid)                               FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_planning_category(uuid, uuid, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_planning_category(uuid, text, text, text)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_planning_category_hidden(uuid, boolean)            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_planning_category(uuid)                         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.move_planning_category(uuid, uuid)                     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_planning_category_seen(uuid)                      FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_planning_home(uuid)                               TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_planning_category(uuid, uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planning_category(uuid, text, text, text)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_planning_category_hidden(uuid, boolean)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_planning_category(uuid)                         TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_planning_category(uuid, uuid)                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_planning_category_seen(uuid)                      TO authenticated;
```

`supabase/migrations/20261012200210_planning_v2_starter_template_grants.sql` (same reason as Task 1 Step 3b):

```sql
-- Planning v2 starter definitions: server-only. Re-applied by
-- scripts/local_pg_grants.sql after the harness's blanket grant.
REVOKE ALL ON public.planning_starter_templates FROM PUBLIC, anon, authenticated;
```

Append to the end of `scripts/local_pg_grants.sql`:

```sql
\i supabase/migrations/20261012200210_planning_v2_starter_template_grants.sql
```

Implementer notes:
- `mark_planning_category_seen` deliberately does not bump the change signal: it is per-user state the partner never sees.
- Contract 13 edits `planning_starter_templates` inside the test transaction; the `ROLLBACK` restores it.

- [ ] **Step 4: Run the tests**

Run: `bash scripts/local_pg_setup.sh --no-tests && for f in supabase/tests/planning_v2_*_contracts.sql; do psql -q -d attune_test -f "$f" || exit 1; done`
Expected: three `PASS` notices.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261012200200_planning_v2_categories.sql supabase/migrations/20261012200210_planning_v2_starter_template_grants.sql scripts/local_pg_grants.sql supabase/tests/planning_v2_category_contracts.sql
git commit -m "feat(planning-v2): starter categories, templates and category RPCs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Entry RPCs and reads

**Files:**
- Create: `supabase/migrations/20261012200300_planning_v2_entries.sql`
- Test: `supabase/tests/planning_v2_entry_contracts.sql`

**Interfaces:**
- Consumes: Tasks 1–3 (`planning_v2_copy_blocks`, `planning_v2_instantiate_blocks`, `planning_v2_touch_entry`, `planning_v2_actor`, `planning_v2_fail`, `bump_planning_signal`).
- Produces:
  - Internal `planning_v2_entry_detail(p_entry_id uuid) RETURNS jsonb` with exactly this shape (Dart models in Task 7 parse it):
    ```json
    {"entry": {"id","category_id","category_name","category_seed_key","is_template","title","status",
               "currency","cover_path","last_activity_at","created_at","updated_at"},
     "members": [{"id","display_name"}, {"id","display_name"}],
     "blocks": [{"id","block_type","sort_key","payload","plain_text","date_start","date_end","version","updated_at",
                 "items": [{"id","sort_key","text","section","checked_at","checked_by","assigned_to","due_date","version"}]}]}
    ```
  - Internal `planning_v2_entry_object(p_entry_id uuid) RETURNS jsonb`: the `"entry"` object above.
  - Public RPCs:
    - `create_planning_entry(p_id uuid, p_category_id uuid, p_title text, p_use_template boolean, p_currency text)` → detail
    - `duplicate_planning_entry(p_source_id uuid, p_new_id uuid, p_title text)` → detail
    - `update_planning_entry(p_id uuid, p_title text, p_status text)` → `{"entry": {...}}`
    - `delete_planning_entry(p_id uuid)` → `{"deleted": true}`
    - `get_planning_entry(p_id uuid)` → detail
    - `list_planning_entries(p_category_id uuid, p_group text, p_cursor_at timestamptz, p_cursor_id uuid, p_limit int)` → `{"entries":[{"id","title","status","last_activity_at","date_start","date_end","checklist_done","checklist_total"}], "next_cursor": {"at","id"} | null}`. `p_group` ∈ `open` (status `active`) / `closed` (`done`, `archived`).
    - `reset_planning_template(p_category_id uuid)` → detail of the template

- [ ] **Step 1: Write the failing contract test**

`supabase/tests/planning_v2_entry_contracts.sql`:

```sql
-- Planning v2 entry contracts (P1 Task 4).
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2d000000-0000-0000-0000-000000000001';
  v_a uuid := '2d000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2d000000-0000-0000-0000-0000000000b1';
  v_x uuid := '2d000000-0000-0000-0000-0000000000e1';
  v_trips uuid;
  v_goals uuid;
  v_custom uuid := '2d000000-0000-0000-0000-00000000c001';
  v_e1 uuid := '2d000000-0000-0000-0000-00000000e001';
  v_e2 uuid := '2d000000-0000-0000-0000-00000000e002';
  v_dup uuid := '2d000000-0000-0000-0000-00000000e003';
  v_d jsonb;
  v_page jsonb;
  v_tpl uuid;
  v_n int;
  v_i int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2e_a@t.test'),(v_b,'v2e_b@t.test'),(v_x,'v2e_x@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12300000001','Priya'),(v_b,'+12300000002','Sam'),(v_x,'+12300000003','X')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_trips FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  SELECT id INTO v_goals FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'goals';

  -- Contract 1: create from template copies blocks + items, resetting checks.
  UPDATE public.planning_block_items i SET checked_at = now(), checked_by = v_b
  FROM public.planning_blocks b JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE i.block_id = b.id AND e.category_id = v_trips AND e.is_template;
  v_d := public.create_planning_entry(v_e1, v_trips, 'Bali, 10 days', true, 'IDR');
  IF jsonb_array_length(v_d -> 'blocks') <> 4 THEN RAISE EXCEPTION 'EXPLOIT: template copy block count %', jsonb_array_length(v_d -> 'blocks'); END IF;
  IF (v_d -> 'blocks' -> 2 ->> 'block_type') <> 'checklist'
     OR jsonb_array_length(v_d -> 'blocks' -> 2 -> 'items') <> 3 THEN
    RAISE EXCEPTION 'EXPLOIT: packing list not copied: %', v_d -> 'blocks' -> 2;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_d -> 'blocks' -> 2 -> 'items') i WHERE i ->> 'checked_at' IS NOT NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: copied items kept their ticks';
  END IF;
  IF v_d -> 'entry' ->> 'currency' <> 'IDR' OR (v_d -> 'entry' ->> 'is_template')::boolean THEN
    RAISE EXCEPTION 'EXPLOIT: entry fields wrong: %', v_d -> 'entry';
  END IF;
  IF jsonb_array_length(v_d -> 'members') <> 2 THEN RAISE EXCEPTION 'EXPLOIT: members missing'; END IF;

  -- Contract 2: blank create has no blocks.
  v_d := public.create_planning_entry(v_e2, v_trips, 'Weekend away', false, 'USD');
  IF jsonb_array_length(v_d -> 'blocks') <> 0 THEN RAISE EXCEPTION 'EXPLOIT: blank entry has blocks'; END IF;

  -- Contract 3: idempotent create; conflicting reuse rejected.
  v_d := public.create_planning_entry(v_e1, v_trips, 'Bali, 10 days', true, 'IDR');
  SELECT count(*) INTO v_n FROM public.planning_blocks WHERE entry_id = v_e1 AND deleted_at IS NULL;
  IF v_n <> 4 THEN RAISE EXCEPTION 'EXPLOIT: retry re-copied blocks (%)', v_n; END IF;
  BEGIN PERFORM public.create_planning_entry(v_e1, v_goals, 'Other', true, 'USD');
    RAISE EXCEPTION 'EXPLOIT: id reuse accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 4: stranger is refused everywhere with not_found.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.get_planning_entry(v_e1); RAISE EXCEPTION 'EXPLOIT: stranger read entry';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.list_planning_entries(v_trips, 'open', NULL, NULL, 30); RAISE EXCEPTION 'EXPLOIT: stranger listed';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, 'x', false, 'USD'); RAISE EXCEPTION 'EXPLOIT: stranger created';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.delete_planning_entry(v_e1); RAISE EXCEPTION 'EXPLOIT: stranger deleted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 5: title validation, counted in characters.
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, '   ', false, 'USD'); RAISE EXCEPTION 'EXPLOIT: blank title';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, repeat('a', 121), false, 'USD'); RAISE EXCEPTION 'EXPLOIT: 121 chars';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, 'x', false, 'usd'); RAISE EXCEPTION 'EXPLOIT: bad currency';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  v_d := public.create_planning_entry(gen_random_uuid(), v_goals, repeat('🌴', 120), false, 'USD');
  IF char_length(v_d -> 'entry' ->> 'title') <> 120 THEN RAISE EXCEPTION 'EXPLOIT: emoji title mangled'; END IF;

  -- Contract 6: keyset pagination over 35 entries; newest activity first.
  FOR v_i IN 1..33 LOOP
    PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, 'Trip ' || v_i, false, 'USD');
  END LOOP;
  v_page := public.list_planning_entries(v_trips, 'open', NULL, NULL, 30);
  IF jsonb_array_length(v_page -> 'entries') <> 30 OR v_page -> 'next_cursor' = 'null'::jsonb THEN
    RAISE EXCEPTION 'EXPLOIT: page 1 wrong: % entries, cursor %', jsonb_array_length(v_page -> 'entries'), v_page -> 'next_cursor';
  END IF;
  IF v_page -> 'entries' -> 0 ->> 'title' <> 'Trip 33' THEN RAISE EXCEPTION 'EXPLOIT: not newest first'; END IF;
  v_page := public.list_planning_entries(v_trips, 'open',
    (v_page -> 'next_cursor' ->> 'at')::timestamptz, (v_page -> 'next_cursor' ->> 'id')::uuid, 30);
  IF jsonb_array_length(v_page -> 'entries') <> 5 OR v_page -> 'next_cursor' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'EXPLOIT: page 2 wrong: %', v_page;
  END IF;
  -- template never listed
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_page -> 'entries') x WHERE x ->> 'title' = 'New trip') THEN
    RAISE EXCEPTION 'EXPLOIT: template listed as entry';
  END IF;
  -- limit is clamped to 100
  v_page := public.list_planning_entries(v_trips, 'open', NULL, NULL, 100000);
  IF jsonb_array_length(v_page -> 'entries') <> 35 THEN RAISE EXCEPTION 'EXPLOIT: clamp broke listing'; END IF;
  -- summary fields
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_page -> 'entries') x
                 WHERE x ->> 'id' = v_e1::text AND (x ->> 'checklist_total')::int = 3
                   AND (x ->> 'checklist_done')::int = 0) THEN
    RAISE EXCEPTION 'EXPLOIT: checklist summary wrong';
  END IF;

  -- Contract 7: status moves an entry between groups; template status is fixed.
  PERFORM public.update_planning_entry(v_e2, 'Weekend away', 'done');
  v_page := public.list_planning_entries(v_trips, 'closed', NULL, NULL, 30);
  IF jsonb_array_length(v_page -> 'entries') <> 1 THEN RAISE EXCEPTION 'EXPLOIT: closed group wrong'; END IF;
  SELECT id INTO v_tpl FROM public.planning_entries WHERE category_id = v_goals AND is_template;
  BEGIN PERFORM public.update_planning_entry(v_tpl, 'New goal', 'done'); RAISE EXCEPTION 'EXPLOIT: template closed';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.update_planning_entry(v_e2, 'x', 'deleted'); RAISE EXCEPTION 'EXPLOIT: bad status';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 8: renaming a template marks it edited (no auto-upgrade).
  PERFORM public.update_planning_entry(v_tpl, 'Our goal', 'active');
  IF (SELECT seed_version FROM public.planning_entries WHERE id = v_tpl) IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: edited template still upgradeable';
  END IF;

  -- Contract 9: reset restores the starter version.
  v_d := public.reset_planning_template(v_goals);
  IF jsonb_array_length(v_d -> 'blocks') <> 3 OR v_d -> 'entry' ->> 'title' <> 'New goal' THEN
    RAISE EXCEPTION 'EXPLOIT: reset wrong: %', v_d -> 'entry';
  END IF;
  IF (SELECT seed_version FROM public.planning_entries WHERE id = v_tpl) IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: reset did not restore seed_version';
  END IF;

  -- Contract 10: duplicate copies blocks, resets ticks, leaves source intact.
  UPDATE public.planning_block_items SET checked_at = now(), checked_by = v_a
  WHERE block_id IN (SELECT id FROM public.planning_blocks WHERE entry_id = v_e1);
  v_d := public.duplicate_planning_entry(v_e1, v_dup, 'Bali again');
  IF jsonb_array_length(v_d -> 'blocks') <> 4 THEN RAISE EXCEPTION 'EXPLOIT: duplicate lost blocks'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_d -> 'blocks') b, jsonb_array_elements(b -> 'items') i
             WHERE i ->> 'checked_at' IS NOT NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: duplicate kept ticks';
  END IF;
  SELECT count(*) INTO v_n FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
  WHERE b.entry_id = v_e1 AND i.checked_at IS NOT NULL;
  IF v_n <> 3 THEN RAISE EXCEPTION 'EXPLOIT: duplicate changed the source'; END IF;
  BEGIN PERFORM public.duplicate_planning_entry(v_tpl, gen_random_uuid(), 'x'); RAISE EXCEPTION 'EXPLOIT: template duplicated';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 11: delete; template delete refused; deleted entry is not_found.
  PERFORM public.delete_planning_entry(v_dup);
  BEGIN PERFORM public.get_planning_entry(v_dup); RAISE EXCEPTION 'EXPLOIT: deleted entry readable';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.delete_planning_entry(v_tpl); RAISE EXCEPTION 'EXPLOIT: template deleted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 12: cannot create inside a deleted category.
  PERFORM public.create_planning_category(v_custom, v_rel, 'Moving', 'box', 'orange');
  PERFORM public.delete_planning_category(v_custom);
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_custom, 'x', false, 'USD'); RAISE EXCEPTION 'EXPLOIT: entry in deleted category';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;

  -- Contract 13: grants.
  IF has_function_privilege('anon', 'public.get_planning_entry(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_planning_entry(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.planning_v2_entry_detail(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: entry RPC grants wrong';
  END IF;

  RAISE NOTICE 'planning_v2_entry_contracts: PASS';
END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/local_pg_setup.sh --no-tests && psql -q -d attune_test -f supabase/tests/planning_v2_entry_contracts.sql`
Expected: FAIL with `function public.create_planning_entry(...) does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/20261012200300_planning_v2_entries.sql`:

```sql
-- Planning v2 entries (P1 Task 4). Spec §4, §5; plan ruling R2.

CREATE OR REPLACE FUNCTION public.planning_v2_entry_object(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'category_id', e.category_id, 'category_name', c.name,
    'category_seed_key', c.seed_key, 'is_template', e.is_template, 'title', e.title,
    'status', e.status, 'currency', e.currency, 'cover_path', e.cover_path,
    'last_activity_at', e.last_activity_at, 'created_at', e.created_at, 'updated_at', e.updated_at)
  FROM public.planning_entries e JOIN public.planning_categories c ON c.id = e.category_id
  WHERE e.id = p_entry_id;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_entry_detail(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'entry', public.planning_v2_entry_object(e.id),
    'members', (
      SELECT jsonb_agg(jsonb_build_object('id', u.id, 'display_name', u.display_name) ORDER BY u.id)
      FROM public.relationships r JOIN public.users u ON u.id IN (r.user_a, r.user_b)
      WHERE r.id = e.relationship_id),
    'blocks', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', b.id, 'block_type', b.block_type, 'sort_key', b.sort_key,
               'payload', b.payload, 'plain_text', b.plain_text,
               'date_start', b.date_start, 'date_end', b.date_end,
               'version', b.version, 'updated_at', b.updated_at,
               'items', coalesce((
                 SELECT jsonb_agg(jsonb_build_object(
                          'id', i.id, 'sort_key', i.sort_key, 'text', i.text, 'section', i.section,
                          'checked_at', i.checked_at, 'checked_by', i.checked_by,
                          'assigned_to', i.assigned_to, 'due_date', i.due_date, 'version', i.version)
                        ORDER BY i.sort_key, i.id)
                 FROM public.planning_block_items i
                 WHERE i.block_id = b.id AND i.deleted_at IS NULL), '[]'::jsonb))
             ORDER BY b.sort_key, b.id)
      FROM public.planning_blocks b
      WHERE b.entry_id = e.id AND b.deleted_at IS NULL), '[]'::jsonb))
  FROM public.planning_entries e WHERE e.id = p_entry_id;
$$;

REVOKE ALL ON FUNCTION public.planning_v2_entry_object(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_entry_detail(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_planning_entry(
  p_id uuid, p_category_id uuid, p_title text, p_use_template boolean, p_currency text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel   uuid;
  v_actor uuid;
  v_cat   public.planning_categories;
  v_row   public.planning_entries;
  v_tpl   uuid;
  v_title text := btrim(p_title);
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_category_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  -- FOR SHARE, not just the FK's implicit KEY SHARE: delete_planning_category
  -- updates a non-key column (deleted_at), which KEY SHARE does not block.
  SELECT * INTO v_cat FROM public.planning_categories WHERE id = p_category_id FOR SHARE;
  IF v_cat.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;

  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_id;
  IF FOUND THEN
    IF v_row.relationship_id = v_rel AND v_row.category_id = p_category_id
       AND v_row.title = v_title AND v_row.deleted_at IS NULL AND NOT v_row.is_template THEN
      RETURN public.planning_v2_entry_detail(p_id);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  IF v_title IS NULL OR char_length(v_title) NOT BETWEEN 1 AND 120 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
  END IF;
  IF p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"currency"}');
  END IF;

  INSERT INTO public.planning_entries (id, relationship_id, category_id, created_by, title, currency,
                                       last_activity_at, last_activity_by)
  VALUES (p_id, v_rel, p_category_id, v_actor, v_title, p_currency, clock_timestamp(), v_actor);
  IF coalesce(p_use_template, false) THEN
    SELECT id INTO v_tpl FROM public.planning_entries
    WHERE category_id = p_category_id AND is_template AND deleted_at IS NULL;
    IF v_tpl IS NOT NULL THEN
      PERFORM public.planning_v2_copy_blocks(v_rel, v_tpl, p_id, v_actor);
    END IF;
  END IF;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN public.planning_v2_entry_detail(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.duplicate_planning_entry(p_source_id uuid, p_new_id uuid, p_title text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel   uuid;
  v_actor uuid;
  v_src   public.planning_entries;
  v_row   public.planning_entries;
  v_title text := btrim(p_title);
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_source_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  SELECT * INTO v_src FROM public.planning_entries WHERE id = p_source_id FOR SHARE;
  IF v_src.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_src.is_template THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"template"}'); END IF;
  PERFORM 1 FROM public.planning_categories WHERE id = v_src.category_id AND deleted_at IS NULL FOR SHARE;

  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_new_id;
  IF FOUND THEN
    IF v_row.relationship_id = v_rel AND v_row.category_id = v_src.category_id
       AND v_row.title = v_title AND v_row.deleted_at IS NULL THEN
      RETURN public.planning_v2_entry_detail(p_new_id);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  IF v_title IS NULL OR char_length(v_title) NOT BETWEEN 1 AND 120 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
  END IF;

  INSERT INTO public.planning_entries (id, relationship_id, category_id, created_by, title, currency,
                                       cover_path, last_activity_at, last_activity_by)
  VALUES (p_new_id, v_rel, v_src.category_id, v_actor, v_title, v_src.currency,
          v_src.cover_path, clock_timestamp(), v_actor);
  PERFORM public.planning_v2_copy_blocks(v_rel, p_source_id, p_new_id, v_actor);
  PERFORM public.bump_planning_signal(v_rel);
  RETURN public.planning_v2_entry_detail(p_new_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_planning_entry(p_id uuid, p_title text, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel   uuid;
  v_actor uuid;
  v_row   public.planning_entries;
  v_title text := btrim(p_title);
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_title IS NULL OR char_length(v_title) NOT BETWEEN 1 AND 120 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('active','done','archived')
     OR (v_row.is_template AND p_status <> 'active') THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"status"}');
  END IF;
  UPDATE public.planning_entries SET title = v_title, status = p_status WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(p_id, v_actor);
  PERFORM public.bump_planning_signal(v_rel);
  RETURN jsonb_build_object('entry', public.planning_v2_entry_object(p_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_planning_entry(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_entries; v_now timestamptz := now();
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_row.is_template THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"template"}'); END IF;
  UPDATE public.planning_block_items SET deleted_at = v_now
  WHERE deleted_at IS NULL AND block_id IN (SELECT id FROM public.planning_blocks WHERE entry_id = p_id);
  UPDATE public.planning_blocks SET deleted_at = v_now WHERE entry_id = p_id AND deleted_at IS NULL;
  UPDATE public.planning_entries SET deleted_at = v_now WHERE id = p_id;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN jsonb_build_object('deleted', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_planning_entry(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  RETURN public.planning_v2_entry_detail(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_planning_entries(
  p_category_id uuid, p_group text, p_cursor_at timestamptz, p_cursor_id uuid, p_limit int
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel     uuid;
  v_limit   int := greatest(1, least(coalesce(p_limit, 30), 100));
  v_entries jsonb;
  v_next    jsonb := 'null'::jsonb;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_category_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  IF p_group IS NULL OR p_group NOT IN ('open', 'closed') THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"group"}');
  END IF;
  IF (p_cursor_at IS NULL) <> (p_cursor_id IS NULL) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"cursor"}');
  END IF;

  WITH page AS (
    SELECT e.id, e.title, e.status, e.last_activity_at,
           row_number() OVER (ORDER BY e.last_activity_at DESC, e.id DESC) AS rn
    FROM public.planning_entries e
    WHERE e.category_id = p_category_id AND NOT e.is_template AND e.deleted_at IS NULL
      AND ((p_group = 'open' AND e.status = 'active')
        OR (p_group = 'closed' AND e.status IN ('done', 'archived')))
      AND (p_cursor_at IS NULL OR (e.last_activity_at, e.id) < (p_cursor_at, p_cursor_id))
    ORDER BY e.last_activity_at DESC, e.id DESC
    LIMIT v_limit + 1
  )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'title', p.title, 'status', p.status, 'last_activity_at', p.last_activity_at,
      'date_start', d.date_start, 'date_end', d.date_end,
      'checklist_done', coalesce(cl.done, 0), 'checklist_total', coalesce(cl.total, 0))
      ORDER BY p.rn) FILTER (WHERE p.rn <= v_limit), '[]'::jsonb),
    CASE WHEN max(p.rn) > v_limit THEN
      (SELECT jsonb_build_object('at', q.last_activity_at, 'id', q.id) FROM page q WHERE q.rn = v_limit)
    ELSE 'null'::jsonb END
  INTO v_entries, v_next
  FROM page p
  LEFT JOIN LATERAL (
    SELECT b.date_start, b.date_end FROM public.planning_blocks b
    WHERE b.entry_id = p.id AND b.deleted_at IS NULL AND b.block_type = 'date' AND b.date_start IS NOT NULL
    ORDER BY b.sort_key, b.id LIMIT 1) d ON true
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE i.checked_at IS NOT NULL) AS done, count(*) AS total
    FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
    WHERE b.entry_id = p.id AND b.block_type = 'checklist' AND b.deleted_at IS NULL AND i.deleted_at IS NULL) cl ON true;

  RETURN jsonb_build_object('entries', v_entries, 'next_cursor', coalesce(v_next, 'null'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_planning_template(p_category_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel   uuid;
  v_actor uuid;
  v_cat   public.planning_categories;
  v_tpl   public.planning_entries;
  s       public.planning_starter_templates;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_category_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  SELECT * INTO v_cat FROM public.planning_categories WHERE id = p_category_id FOR SHARE;
  IF v_cat.seed_key IS NULL THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"starter"}'); END IF;
  SELECT * INTO s FROM public.planning_starter_templates WHERE seed_key = v_cat.seed_key;
  SELECT * INTO v_tpl FROM public.planning_entries
  WHERE category_id = p_category_id AND is_template AND deleted_at IS NULL FOR UPDATE;
  UPDATE public.planning_block_items SET deleted_at = now()
  WHERE deleted_at IS NULL AND block_id IN (SELECT id FROM public.planning_blocks WHERE entry_id = v_tpl.id);
  UPDATE public.planning_blocks SET deleted_at = now() WHERE entry_id = v_tpl.id AND deleted_at IS NULL;
  PERFORM public.planning_v2_instantiate_blocks(v_rel, v_tpl.id, v_actor, s.blocks);
  UPDATE public.planning_entries
     SET seed_version = s.version, title = s.template_title,
         last_activity_at = clock_timestamp(), last_activity_by = v_actor
   WHERE id = v_tpl.id;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN public.planning_v2_entry_detail(v_tpl.id);
END;
$$;

REVOKE ALL ON FUNCTION public.create_planning_entry(uuid, uuid, text, boolean, text)              FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.duplicate_planning_entry(uuid, uuid, text)                         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_planning_entry(uuid, text, text)                            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_planning_entry(uuid)                                        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_planning_entry(uuid)                                           FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_planning_entries(uuid, text, timestamptz, uuid, int)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reset_planning_template(uuid)                                      FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_planning_entry(uuid, uuid, text, boolean, text)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.duplicate_planning_entry(uuid, uuid, text)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planning_entry(uuid, text, text)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_planning_entry(uuid)                               TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_planning_entry(uuid)                                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_planning_entries(uuid, text, timestamptz, uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_planning_template(uuid)                             TO authenticated;
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/local_pg_setup.sh --no-tests && for f in supabase/tests/planning_v2_*_contracts.sql; do psql -q -d attune_test -f "$f" || exit 1; done`
Expected: four `PASS` notices.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261012200300_planning_v2_entries.sql supabase/tests/planning_v2_entry_contracts.sql
git commit -m "feat(planning-v2): entry create, duplicate, list, read and template reset

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Block and item RPCs

**Files:**
- Create: `supabase/migrations/20261012200400_planning_v2_blocks_items.sql`
- Test: `supabase/tests/planning_v2_block_item_contracts.sql`, `supabase/tests/planning_v2_concurrency.sh`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces (all public, all return `jsonb`):
  - Block JSON (same object as inside `planning_v2_entry_detail` → `blocks[]`, including `items`) from: `add_planning_block(p_id uuid, p_entry_id uuid, p_block_type text, p_payload jsonb, p_date_start date, p_date_end date, p_after_id uuid)`, `update_planning_block(p_id uuid, p_version int, p_payload jsonb, p_date_start date, p_date_end date)`, `restore_planning_block(p_id uuid)`, `move_planning_block(p_id uuid, p_after_id uuid)`.
  - `delete_planning_block(p_id uuid)` → `{"deleted": true}`.
  - Item JSON (same object as `items[]`) from: `add_planning_block_item(p_id uuid, p_block_id uuid, p_text text, p_section text, p_assigned_to uuid, p_due_date date, p_after_id uuid)`, `update_planning_block_item(p_id uuid, p_version int, p_text text, p_section text, p_assigned_to uuid, p_due_date date)`, `set_planning_block_item_checked(p_id uuid, p_checked boolean, p_op_id uuid)`, `restore_planning_block_item(p_id uuid)`, `move_planning_block_item(p_id uuid, p_after_id uuid)`.
  - `delete_planning_block_item(p_id uuid)` → `{"deleted": true}`.
  - `stale_version` HINT: `{"current": <block or item JSON>}`.
  - Internal: `planning_v2_block_object(p_id uuid)`, `planning_v2_item_object(p_id uuid)`.
- `p_after_id` NULL means "first". To append, the client passes the id of the current last sibling.

Lock order in every RPC: **entry `FOR UPDATE` first**, then block, then item.

- [ ] **Step 1: Write the failing contract test**

`supabase/tests/planning_v2_block_item_contracts.sql`:

```sql
-- Planning v2 block/item contracts (P1 Task 5).
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2e000000-0000-0000-0000-000000000001';
  v_a uuid := '2e000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2e000000-0000-0000-0000-0000000000b1';
  v_x uuid := '2e000000-0000-0000-0000-0000000000e1';
  v_cat uuid;
  v_entry uuid := '2e000000-0000-0000-0000-00000000e001';
  v_text uuid := '2e000000-0000-0000-0000-00000000b001';
  v_list uuid := '2e000000-0000-0000-0000-00000000b002';
  v_date uuid := '2e000000-0000-0000-0000-00000000b003';
  v_i1 uuid := '2e000000-0000-0000-0000-0000000001a1';
  v_i2 uuid := '2e000000-0000-0000-0000-0000000001a2';
  v_op uuid := '2e000000-0000-0000-0000-00000000f001';
  v_r jsonb;
  v_hint text;
  v_n int;
  v_i int;
  v_tpl uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2b_a@t.test'),(v_b,'v2b_b@t.test'),(v_x,'v2b_x@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12400000001','Ama'),(v_b,'+12400000002','Kofi'),(v_x,'+12400000003','X')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_cat FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'groceries';
  PERFORM public.create_planning_entry(v_entry, v_cat, 'Saturday shop', false, 'GHS');

  -- Contract 1: add blocks in order; text derives plain_text.
  v_r := public.add_planning_block(v_text, v_entry, 'text',
    '{"delta":[{"insert":"Buy "},{"insert":"fresh","attributes":{"bold":true}},{"insert":"\n"}]}', NULL, NULL, NULL);
  IF v_r ->> 'plain_text' <> 'Buy fresh' OR (v_r ->> 'version')::int <> 1 THEN RAISE EXCEPTION 'EXPLOIT: text block wrong: %', v_r; END IF;
  PERFORM public.add_planning_block(v_list, v_entry, 'checklist', '{"title":"List"}', NULL, NULL, v_text);
  PERFORM public.add_planning_block(v_date, v_entry, 'date', '{}', '2026-10-17', NULL, v_list);
  SELECT array_agg(b ->> 'block_type' ORDER BY ord)::text INTO v_hint
  FROM jsonb_array_elements(public.get_planning_entry(v_entry) -> 'blocks') WITH ORDINALITY t(b, ord);
  IF v_hint <> '{text,checklist,date}' THEN RAISE EXCEPTION 'EXPLOIT: block order %', v_hint; END IF;

  -- Contract 2: idempotent add; id reuse with another type rejected.
  PERFORM public.add_planning_block(v_list, v_entry, 'checklist', '{"title":"List"}', NULL, NULL, v_text);
  SELECT count(*) INTO v_n FROM public.planning_blocks WHERE entry_id = v_entry AND deleted_at IS NULL;
  IF v_n <> 3 THEN RAISE EXCEPTION 'EXPLOIT: add retry duplicated (%)', v_n; END IF;
  BEGIN PERFORM public.add_planning_block(v_list, v_entry, 'date', '{}', NULL, NULL, NULL); RAISE EXCEPTION 'EXPLOIT: id reuse';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 3: P3/P4 block types are refused in P1.
  BEGIN PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'budget', '{}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: budget block added in P1';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 4: version check — a stale save returns the current block in HINT.
  v_r := public.update_planning_block(v_text, 1, '{"delta":[{"insert":"Kofi edit\n"}]}', NULL, NULL);
  IF (v_r ->> 'version')::int <> 2 THEN RAISE EXCEPTION 'EXPLOIT: version not bumped'; END IF;
  BEGIN
    PERFORM public.update_planning_block(v_text, 1, '{"delta":[{"insert":"Ama edit\n"}]}', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: stale save accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:stale_version' THEN RAISE; END IF;
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    IF v_hint::jsonb -> 'current' ->> 'plain_text' <> 'Kofi edit' THEN
      RAISE EXCEPTION 'EXPLOIT: stale HINT lacks current block: %', v_hint;
    END IF;
  END;

  -- Contract 5: items — add, assign, reject stranger assignee.
  PERFORM public.add_planning_block_item(v_i1, v_list, 'Tomatoes', 'Produce', v_b, NULL, NULL);
  PERFORM public.add_planning_block_item(v_i2, v_list, 'Milk', 'Dairy', NULL, '2026-10-17', v_i1);
  BEGIN PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'x', NULL, v_x, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: stranger assignee';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.add_planning_block_item(gen_random_uuid(), v_text, 'x', NULL, NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: item on a text block';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 6 (op_replay): a tick op applies once; replaying the same op
  -- after the partner unticked does NOT re-tick; a new op does.
  v_r := public.set_planning_block_item_checked(v_i1, true, v_op);
  IF v_r ->> 'checked_by' <> v_a::text THEN RAISE EXCEPTION 'EXPLOIT: tick not attributed'; END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_b), true);
  PERFORM public.set_planning_block_item_checked(v_i1, false, gen_random_uuid());
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  v_r := public.set_planning_block_item_checked(v_i1, true, v_op);
  IF v_r ->> 'checked_at' IS NOT NULL THEN RAISE EXCEPTION 'EXPLOIT: replayed op re-applied'; END IF;
  v_r := public.set_planning_block_item_checked(v_i1, true, gen_random_uuid());
  IF v_r ->> 'checked_at' IS NULL THEN RAISE EXCEPTION 'EXPLOIT: fresh op ignored'; END IF;

  -- Contract 7: ticking an already-ticked item keeps the original tick.
  v_hint := v_r ->> 'checked_at';
  v_r := public.set_planning_block_item_checked(v_i1, true, gen_random_uuid());
  IF v_r ->> 'checked_at' <> v_hint THEN RAISE EXCEPTION 'EXPLOIT: re-tick moved timestamp'; END IF;

  -- Contract 8: item update with version; stale rejected.
  v_r := public.update_planning_block_item(v_i2, 1, 'Milk (2L)', 'Dairy', v_a, NULL);
  IF v_r ->> 'text' <> 'Milk (2L)' OR (v_r ->> 'version')::int <> 2 THEN RAISE EXCEPTION 'EXPLOIT: item update wrong'; END IF;
  BEGIN PERFORM public.update_planning_block_item(v_i2, 1, 'Milk', NULL, NULL, NULL); RAISE EXCEPTION 'EXPLOIT: stale item save';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:stale_version' THEN RAISE; END IF; END;

  -- Contract 9: move item to first; move block to first.
  PERFORM public.move_planning_block_item(v_i2, NULL);
  IF (public.get_planning_entry(v_entry) -> 'blocks' -> 1 -> 'items' -> 0 ->> 'id')::uuid <> v_i2 THEN
    RAISE EXCEPTION 'EXPLOIT: item move failed';
  END IF;
  PERFORM public.move_planning_block(v_date, NULL);
  IF (public.get_planning_entry(v_entry) -> 'blocks' -> 0 ->> 'id')::uuid <> v_date THEN
    RAISE EXCEPTION 'EXPLOIT: block move failed';
  END IF;
  BEGIN PERFORM public.move_planning_block(v_date, v_date); RAISE EXCEPTION 'EXPLOIT: moved after itself';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 10 (update_after_delete): partner deletes a block; my save is not_found;
  -- restore brings it back with its items.
  PERFORM public.delete_planning_block(v_list);
  BEGIN PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'Eggs', NULL, NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: item added to deleted block';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.update_planning_block(v_list, 1, '{"title":"x"}', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: deleted block updated';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  v_r := public.restore_planning_block(v_list);
  IF jsonb_array_length(v_r -> 'items') <> 2 THEN RAISE EXCEPTION 'EXPLOIT: restore lost items'; END IF;
  PERFORM public.delete_planning_block_item(v_i1);
  v_r := public.restore_planning_block_item(v_i1);
  IF v_r ->> 'text' <> 'Tomatoes' THEN RAISE EXCEPTION 'EXPLOIT: item restore failed'; END IF;

  -- Contract 11: limits — 200 blocks, 500 items.
  FOR v_i IN 1..197 LOOP
    PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'checklist', '{}', NULL, NULL, NULL);
  END LOOP;
  BEGIN PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'checklist', '{}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: 201st block';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF;
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    IF v_hint::jsonb ->> 'limit' <> 'blocks_per_entry' THEN RAISE EXCEPTION 'EXPLOIT: wrong limit name'; END IF;
  END;
  FOR v_i IN 1..498 LOOP
    PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'i' || v_i, NULL, NULL, NULL, NULL);
  END LOOP;
  BEGIN PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'one too many', NULL, NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: 501st item';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF; END;

  -- Contract 12: 400 inserts always at the top stay ≤ 64 chars (rebalance works).
  DELETE FROM public.planning_block_items WHERE block_id = v_list;
  FOR v_i IN 1..400 LOOP
    PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'top ' || v_i, NULL, NULL, NULL, NULL);
  END LOOP;
  SELECT max(char_length(sort_key)) INTO v_n FROM public.planning_block_items WHERE block_id = v_list AND deleted_at IS NULL;
  IF v_n > 33 THEN RAISE EXCEPTION 'EXPLOIT: keys grew to %', v_n; END IF;
  IF (public.get_planning_entry(v_entry) -> 'blocks' -> 2 -> 'items' -> 0 ->> 'text') <> 'top 400' THEN
    RAISE EXCEPTION 'EXPLOIT: top inserts out of order after rebalance';
  END IF;

  -- Contract 13: editing a template block marks the template edited.
  SELECT id INTO v_tpl FROM public.planning_entries WHERE category_id = v_cat AND is_template;
  PERFORM public.add_planning_block(gen_random_uuid(), v_tpl, 'text', '{"delta":[{"insert":"Tip\n"}]}', NULL, NULL, NULL);
  IF (SELECT seed_version FROM public.planning_entries WHERE id = v_tpl) IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: template edit not recorded';
  END IF;

  -- Contract 14: stranger refused with not_found.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.set_planning_block_item_checked(v_i1, true, gen_random_uuid()); RAISE EXCEPTION 'EXPLOIT: stranger ticked';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'text', '{"delta":[{"insert":"\n"}]}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: stranger added block';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;

  RAISE NOTICE 'planning_v2_block_item_contracts: PASS';
END $$;
ROLLBACK;
```

`supabase/tests/planning_v2_concurrency.sh`:

```bash
#!/usr/bin/env bash
# Planning v2 concurrency (P1 Task 5). Review Focus 1 + spec acceptance 3.
#  Case 1: both partners open Planning for the first time simultaneously
#          -> exactly 6 categories and 6 templates.
#  Case 2: both partners tick DIFFERENT items of one checklist at the same
#          moment -> both ticks persist.
#  Case 3: both partners save the SAME text block from version 1
#          -> exactly one succeeds, the other gets planning:stale_version.
# Uses fixed UUIDs: run `bash scripts/local_pg_setup.sh --no-tests` first.
set -euo pipefail
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
DB="${ATTUNE_TEST_DB:-attune_test}"

REL="2f000000-0000-0000-0000-000000000001"
A="2f000000-0000-0000-0000-0000000000a1"
B="2f000000-0000-0000-0000-0000000000b1"
ENTRY="2f000000-0000-0000-0000-00000000e001"
LIST="2f000000-0000-0000-0000-00000000b001"
TEXT="2f000000-0000-0000-0000-00000000b002"
I1="2f000000-0000-0000-0000-0000000001a1"
I2="2f000000-0000-0000-0000-0000000001a2"

psql -q -d "$DB" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO auth.users (id, email) VALUES ('$A','v2cc_a@t.test'),('$B','v2cc_b@t.test') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('$A','+12500000001','A'),('$B','+12500000002','B') ON CONFLICT DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ('$REL','$A','$B','active') ON CONFLICT DO NOTHING;
SQL

as_user() { # $1 user, $2 sql; holds the transaction open 1s so calls overlap
  psql -q -d "$DB" -t -A -v ON_ERROR_STOP=1 <<SQL
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"$1"}', true);
$2
SELECT pg_sleep(1);
COMMIT;
SQL
}

# Case 1
as_user "$A" "SELECT public.get_planning_home('$REL') IS NOT NULL;" >/dev/null & P1=$!
as_user "$B" "SELECT public.get_planning_home('$REL') IS NOT NULL;" >/dev/null & P2=$!
# A bare `wait` ignores exit codes: without the seeding lock the second
# partner's open ERRORS on the seed_key unique constraint while the count
# still reads 6. Each session must succeed, not just the end state.
wait $P1 || { echo "FAIL case 1: partner A's first open errored"; exit 1; }
wait $P2 || { echo "FAIL case 1: partner B's first open errored"; exit 1; }
CATS=$(psql -q -d "$DB" -t -A -c "SELECT count(*) FROM public.planning_categories WHERE relationship_id='$REL'")
TPLS=$(psql -q -d "$DB" -t -A -c "SELECT count(*) FROM public.planning_entries WHERE relationship_id='$REL' AND is_template")
[ "$CATS" = "6" ] && [ "$TPLS" = "6" ] || { echo "FAIL case 1: $CATS categories, $TPLS templates"; exit 1; }

# Setup for cases 2 and 3
as_user "$A" "
SELECT public.create_planning_entry('$ENTRY', (SELECT id FROM public.planning_categories WHERE relationship_id='$REL' AND seed_key='groceries'), 'Run', false, 'GHS') IS NOT NULL;
SELECT public.add_planning_block('$LIST', '$ENTRY', 'checklist', '{}', NULL, NULL, NULL) IS NOT NULL;
SELECT public.add_planning_block_item('$I1', '$LIST', 'Tomatoes', NULL, NULL, NULL, NULL) IS NOT NULL;
SELECT public.add_planning_block_item('$I2', '$LIST', 'Milk', NULL, NULL, NULL, '$I1') IS NOT NULL;
SELECT public.add_planning_block('$TEXT', '$ENTRY', 'text', '{\"delta\":[{\"insert\":\"v1\\n\"}]}', NULL, NULL, '$LIST') IS NOT NULL;" >/dev/null

# Case 2
as_user "$A" "SELECT public.set_planning_block_item_checked('$I1', true, gen_random_uuid()) IS NOT NULL;" >/dev/null & P1=$!
as_user "$B" "SELECT public.set_planning_block_item_checked('$I2', true, gen_random_uuid()) IS NOT NULL;" >/dev/null & P2=$!
wait $P1 || { echo "FAIL case 2: partner A's tick errored"; exit 1; }
wait $P2 || { echo "FAIL case 2: partner B's tick errored"; exit 1; }
TICKED=$(psql -q -d "$DB" -t -A -c "SELECT count(*) FROM public.planning_block_items WHERE block_id='$LIST' AND checked_at IS NOT NULL")
[ "$TICKED" = "2" ] || { echo "FAIL case 2: $TICKED of 2 ticks persisted"; exit 1; }

# Case 3
OUT=$(mktemp -d)
( as_user "$A" "SELECT public.update_planning_block('$TEXT', 1, '{\"delta\":[{\"insert\":\"A\\n\"}]}', NULL, NULL) IS NOT NULL;" >"$OUT/a" 2>&1 || true ) &
( as_user "$B" "SELECT public.update_planning_block('$TEXT', 1, '{\"delta\":[{\"insert\":\"B\\n\"}]}', NULL, NULL) IS NOT NULL;" >"$OUT/b" 2>&1 || true ) &
wait
STALE=$(cat "$OUT/a" "$OUT/b" | grep -c "planning:stale_version" || true)
VERSION=$(psql -q -d "$DB" -t -A -c "SELECT version FROM public.planning_blocks WHERE id='$TEXT'")
[ "$STALE" = "1" ] && [ "$VERSION" = "2" ] || { echo "FAIL case 3: stale=$STALE version=$VERSION"; cat "$OUT/a" "$OUT/b"; exit 1; }

echo "planning_v2_concurrency: PASS"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bash scripts/local_pg_setup.sh --no-tests && psql -q -d attune_test -f supabase/tests/planning_v2_block_item_contracts.sql`
Expected: FAIL with `function public.add_planning_block(...) does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/20261012200400_planning_v2_blocks_items.sql`:

```sql
-- Planning v2 blocks and items (P1 Task 5). Spec §3.3, §3.4, §6.1, §6.2, §6.4, §7.2.
-- Every mutation locks the ENTRY row first (FOR UPDATE). That single
-- lock serializes all writes inside one entry, which (a) gives the
-- fixed category -> entry -> block -> item order with no cycles, and
-- (b) makes block/item counts for limit checks exact.

CREATE OR REPLACE FUNCTION public.planning_v2_item_object(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', i.id, 'sort_key', i.sort_key, 'text', i.text, 'section', i.section,
    'checked_at', i.checked_at, 'checked_by', i.checked_by,
    'assigned_to', i.assigned_to, 'due_date', i.due_date, 'version', i.version)
  FROM public.planning_block_items i WHERE i.id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_block_object(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', b.id, 'block_type', b.block_type, 'sort_key', b.sort_key,
    'payload', b.payload, 'plain_text', b.plain_text,
    'date_start', b.date_start, 'date_end', b.date_end,
    'version', b.version, 'updated_at', b.updated_at,
    'items', coalesce((
      SELECT jsonb_agg(public.planning_v2_item_object(i.id) ORDER BY i.sort_key, i.id)
      FROM public.planning_block_items i WHERE i.block_id = b.id AND i.deleted_at IS NULL), '[]'::jsonb))
  FROM public.planning_blocks b WHERE b.id = p_id;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_item_object(uuid)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_block_object(uuid) FROM PUBLIC, anon, authenticated;

-- Resolves an entry for writing: membership, then FOR UPDATE, then liveness.
CREATE OR REPLACE FUNCTION public.planning_v2_lock_entry(p_entry_id uuid)
RETURNS public.planning_entries LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_entries;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_entry_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_entry_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_lock_entry(uuid) FROM PUBLIC, anon, authenticated;

-- ---- blocks -------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.add_planning_block(
  p_id uuid, p_entry_id uuid, p_block_type text, p_payload jsonb,
  p_date_start date, p_date_end date, p_after_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_entry public.planning_entries := public.planning_v2_lock_entry(p_entry_id);
  v_actor uuid := auth.uid();
  v_row   public.planning_blocks;
  v_plain text;
  v_count int;
BEGIN
  SELECT * INTO v_row FROM public.planning_blocks WHERE id = p_id;
  IF FOUND THEN
    IF v_row.entry_id = p_entry_id AND v_row.block_type = p_block_type AND v_row.deleted_at IS NULL THEN
      RETURN public.planning_v2_block_object(p_id);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  v_plain := public.planning_v2_validate_block(p_block_type, coalesce(p_payload, '{}'::jsonb), p_date_start, p_date_end);
  SELECT count(*) INTO v_count FROM public.planning_blocks WHERE entry_id = p_entry_id AND deleted_at IS NULL;
  IF v_count >= 200 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"blocks_per_entry"}'); END IF;

  INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key,
                                      payload, plain_text, date_start, date_end)
  VALUES (p_id, v_entry.relationship_id, p_entry_id, v_actor, p_block_type,
          public.planning_v2_key_after_block(p_entry_id, p_after_id, p_id),
          coalesce(p_payload, '{}'::jsonb), v_plain, p_date_start, p_date_end)
  RETURNING * INTO v_row;
  IF char_length(v_row.sort_key) > 32 THEN PERFORM public.planning_v2_rebalance_blocks(p_entry_id); END IF;
  PERFORM public.planning_v2_touch_entry(p_entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_planning_block(
  p_id uuid, p_version int, p_payload jsonb, p_date_start date, p_date_end date
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_entry_id uuid;
  v_entry    public.planning_entries;
  v_row      public.planning_blocks;
  v_plain    text;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  SELECT * INTO v_row FROM public.planning_blocks WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF p_version IS DISTINCT FROM v_row.version THEN
    PERFORM public.planning_v2_fail('stale_version',
      jsonb_build_object('current', public.planning_v2_block_object(p_id)));
  END IF;
  v_plain := public.planning_v2_validate_block(v_row.block_type, coalesce(p_payload, '{}'::jsonb), p_date_start, p_date_end);
  UPDATE public.planning_blocks
     SET payload = coalesce(p_payload, '{}'::jsonb), plain_text = v_plain,
         date_start = p_date_start, date_end = p_date_end, version = version + 1
   WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_planning_block(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_entry public.planning_entries;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  -- Items keep their own deleted_at NULL: restoring the block restores
  -- them with it. Retention purges them by cascade when the block goes.
  UPDATE public.planning_blocks SET deleted_at = now() WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN jsonb_build_object('deleted', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_planning_block(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_entry public.planning_entries; v_count int;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  SELECT count(*) INTO v_count FROM public.planning_blocks WHERE entry_id = v_entry_id AND deleted_at IS NULL;
  IF v_count >= 200 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"blocks_per_entry"}'); END IF;
  UPDATE public.planning_blocks SET deleted_at = NULL, version = version + 1 WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.move_planning_block(p_id uuid, p_after_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_entry public.planning_entries; v_key text;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  v_key := public.planning_v2_key_after_block(v_entry_id, p_after_id, p_id);
  UPDATE public.planning_blocks SET sort_key = v_key WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF char_length(v_key) > 32 THEN PERFORM public.planning_v2_rebalance_blocks(v_entry_id); END IF;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

-- ---- items --------------------------------------------------------------

-- Resolves a LIVE item's block and entry, locks the entry. Returns the block.
CREATE OR REPLACE FUNCTION public.planning_v2_lock_block(p_block_id uuid)
RETURNS public.planning_blocks LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_block public.planning_blocks;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_block_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_lock_entry(v_entry_id);
  SELECT * INTO v_block FROM public.planning_blocks WHERE id = p_block_id FOR UPDATE;
  IF v_block.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  RETURN v_block;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_lock_block(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.add_planning_block_item(
  p_id uuid, p_block_id uuid, p_text text, p_section text,
  p_assigned_to uuid, p_due_date date, p_after_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_block public.planning_blocks := public.planning_v2_lock_block(p_block_id);
  v_actor uuid := auth.uid();
  v_row   public.planning_block_items;
  v_count int;
BEGIN
  SELECT * INTO v_row FROM public.planning_block_items WHERE id = p_id;
  IF FOUND THEN
    IF v_row.block_id = p_block_id AND v_row.text = btrim(p_text) AND v_row.deleted_at IS NULL THEN
      RETURN public.planning_v2_item_object(p_id);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  PERFORM public.planning_v2_validate_item(v_block.block_type, v_block.relationship_id, p_text, p_section, p_assigned_to);
  SELECT count(*) INTO v_count FROM public.planning_block_items WHERE block_id = p_block_id AND deleted_at IS NULL;
  IF v_count >= 500 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"items_per_block"}'); END IF;

  INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key,
                                           text, section, assigned_to, due_date)
  VALUES (p_id, v_block.relationship_id, p_block_id, v_actor,
          public.planning_v2_key_after_item(p_block_id, p_after_id, p_id),
          btrim(p_text), nullif(btrim(p_section), ''), p_assigned_to, p_due_date)
  RETURNING * INTO v_row;
  IF char_length(v_row.sort_key) > 32 THEN PERFORM public.planning_v2_rebalance_items(p_block_id); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_planning_block_item(
  p_id uuid, p_version int, p_text text, p_section text, p_assigned_to uuid, p_due_date date
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_row public.planning_block_items;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  SELECT * INTO v_row FROM public.planning_block_items WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF p_version IS DISTINCT FROM v_row.version THEN
    PERFORM public.planning_v2_fail('stale_version',
      jsonb_build_object('current', public.planning_v2_item_object(p_id)));
  END IF;
  PERFORM public.planning_v2_validate_item(v_block.block_type, v_block.relationship_id, p_text, p_section, p_assigned_to);
  UPDATE public.planning_block_items
     SET text = btrim(p_text), section = nullif(btrim(p_section), ''),
         assigned_to = p_assigned_to, due_date = p_due_date, version = version + 1
   WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

-- Idempotent by p_op_id (plan ruling R7): an op already applied returns
-- the item unchanged. Ticking a ticked item keeps the original tick.
CREATE OR REPLACE FUNCTION public.set_planning_block_item_checked(p_id uuid, p_checked boolean, p_op_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_actor uuid;
BEGIN
  IF p_op_id IS NULL OR p_checked IS NULL THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"op_id"}');
  END IF;
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  v_actor := auth.uid();
  INSERT INTO public.planning_applied_ops (op_id, relationship_id) VALUES (p_op_id, v_block.relationship_id)
  ON CONFLICT (op_id) DO NOTHING;
  IF NOT FOUND THEN
    RETURN public.planning_v2_item_object(p_id);
  END IF;
  UPDATE public.planning_block_items
     SET checked_at = CASE WHEN p_checked THEN coalesce(checked_at, clock_timestamp()) ELSE NULL END,
         checked_by = CASE WHEN p_checked THEN coalesce(checked_by, v_actor) ELSE NULL END,
         version = version + 1
   WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_planning_block_item(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  UPDATE public.planning_block_items SET deleted_at = now() WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN jsonb_build_object('deleted', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_planning_block_item(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_count int;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  SELECT count(*) INTO v_count FROM public.planning_block_items WHERE block_id = v_block_id AND deleted_at IS NULL;
  IF v_count >= 500 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"items_per_block"}'); END IF;
  UPDATE public.planning_block_items SET deleted_at = NULL, version = version + 1 WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.move_planning_block_item(p_id uuid, p_after_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_key text;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  v_key := public.planning_v2_key_after_item(v_block_id, p_after_id, p_id);
  UPDATE public.planning_block_items SET sort_key = v_key WHERE id = p_id AND deleted_at IS NULL;
  IF char_length(v_key) > 32 THEN PERFORM public.planning_v2_rebalance_items(v_block_id); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

REVOKE ALL ON FUNCTION public.add_planning_block(uuid, uuid, text, jsonb, date, date, uuid)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_planning_block(uuid, int, jsonb, date, date)                    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_planning_block(uuid)                                            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.restore_planning_block(uuid)                                           FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.move_planning_block(uuid, uuid)                                        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.add_planning_block_item(uuid, uuid, text, text, uuid, date, uuid)      FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_planning_block_item(uuid, int, text, text, uuid, date)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_planning_block_item_checked(uuid, boolean, uuid)                   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_planning_block_item(uuid)                                       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.restore_planning_block_item(uuid)                                      FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.move_planning_block_item(uuid, uuid)                                   FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_planning_block(uuid, uuid, text, jsonb, date, date, uuid)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planning_block(uuid, int, jsonb, date, date)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_planning_block(uuid)                                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_planning_block(uuid)                                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_planning_block(uuid, uuid)                                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_planning_block_item(uuid, uuid, text, text, uuid, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planning_block_item(uuid, int, text, text, uuid, date)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_planning_block_item_checked(uuid, boolean, uuid)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_planning_block_item(uuid)                                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_planning_block_item(uuid)                                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_planning_block_item(uuid, uuid)                              TO authenticated;
```

- [ ] **Step 4: Run the tests**

Run:
```bash
bash scripts/local_pg_setup.sh --no-tests
for f in supabase/tests/planning_v2_*_contracts.sql; do psql -q -d attune_test -f "$f" || exit 1; done
bash supabase/tests/planning_v2_concurrency.sh
```
Expected: five `PASS` notices, then `planning_v2_concurrency: PASS`. Run the concurrency script 3 times in a row (rebuild between runs); all three must pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261012200400_planning_v2_blocks_items.sql supabase/tests/planning_v2_block_item_contracts.sql supabase/tests/planning_v2_concurrency.sh
git commit -m "feat(planning-v2): block and checklist item RPCs with version checks and op dedupe

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Retention

**Files:**
- Create: `supabase/migrations/20261012200500_planning_v2_retention.sql`
- Test: `supabase/tests/planning_v2_retention_contracts.sql`

**Interfaces:**
- Produces: internal `planning_v2_purge() RETURNS jsonb` → `{"items":n,"blocks":n,"entries":n,"categories":n,"ops":n}`; cron job `planning_v2_purge` daily at `17 3 * * *`.

- [ ] **Step 1: Write the failing contract test**

`supabase/tests/planning_v2_retention_contracts.sql`:

```sql
-- Planning v2 retention contracts (P1 Task 6). Spec §3.10.
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2f100000-0000-0000-0000-000000000001';
  v_a uuid := '2f100000-0000-0000-0000-0000000000a1';
  v_b uuid := '2f100000-0000-0000-0000-0000000000b1';
  v_cat uuid;
  v_old uuid := '2f100000-0000-0000-0000-00000000e001';
  v_new uuid := '2f100000-0000-0000-0000-00000000e002';
  v_r jsonb;
  v_n int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2r_a@t.test'),(v_b,'v2r_b@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_a,'+12600000001','A'),(v_b,'+12600000002','B') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_cat FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  PERFORM public.create_planning_entry(v_old, v_cat, 'Old', true, 'USD');
  PERFORM public.create_planning_entry(v_new, v_cat, 'Recent', true, 'USD');
  PERFORM public.delete_planning_entry(v_old);
  PERFORM public.delete_planning_entry(v_new);
  UPDATE public.planning_entries SET deleted_at = now() - interval '31 days' WHERE id = v_old;
  UPDATE public.planning_blocks  SET deleted_at = now() - interval '31 days' WHERE entry_id = v_old;
  UPDATE public.planning_block_items SET deleted_at = now() - interval '31 days'
  WHERE block_id IN (SELECT id FROM public.planning_blocks WHERE entry_id = v_old);
  INSERT INTO public.planning_applied_ops (op_id, relationship_id, applied_at)
  VALUES (gen_random_uuid(), v_rel, now() - interval '8 days'), (gen_random_uuid(), v_rel, now());

  v_r := public.planning_v2_purge();

  -- Contract 1: rows deleted > 30 days ago are gone; recent soft-deletes stay.
  IF EXISTS (SELECT 1 FROM public.planning_entries WHERE id = v_old) THEN RAISE EXCEPTION 'EXPLOIT: old entry kept'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_entries WHERE id = v_new) THEN RAISE EXCEPTION 'EXPLOIT: recent entry purged'; END IF;
  SELECT count(*) INTO v_n FROM public.planning_blocks WHERE entry_id = v_old;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: old blocks kept'; END IF;
  IF (v_r ->> 'entries')::int <> 1 THEN RAISE EXCEPTION 'EXPLOIT: purge count wrong: %', v_r; END IF;

  -- Contract 2: ops older than 7 days pruned, recent ones kept.
  SELECT count(*) INTO v_n FROM public.planning_applied_ops WHERE relationship_id = v_rel;
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: ops prune wrong (% left)', v_n; END IF;

  -- Contract 3: live data and starters untouched.
  SELECT count(*) INTO v_n FROM public.planning_categories WHERE relationship_id = v_rel;
  IF v_n <> 6 THEN RAISE EXCEPTION 'EXPLOIT: purge touched categories'; END IF;

  -- Contract 4: the job is scheduled and the function is not client-callable.
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'planning_v2_purge') THEN
    RAISE EXCEPTION 'EXPLOIT: purge job not scheduled';
  END IF;
  IF has_function_privilege('authenticated', 'public.planning_v2_purge()', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: purge callable by clients';
  END IF;

  RAISE NOTICE 'planning_v2_retention_contracts: PASS';
END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/local_pg_setup.sh --no-tests && psql -q -d attune_test -f supabase/tests/planning_v2_retention_contracts.sql`
Expected: FAIL with `function public.planning_v2_purge() does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/20261012200500_planning_v2_retention.sql`:

```sql
-- Planning v2 retention (P1 Task 6). Spec §3.10.
-- Hard-deletes v2 rows soft-deleted more than 30 days ago, and applied
-- op ids older than 7 days. Bounded per run (20 batches x 5000 rows per
-- table) so one run can never hold locks for long; the next night
-- continues. Storage objects are not involved until P3 (plan ruling R1).

CREATE OR REPLACE FUNCTION public.planning_v2_purge()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cutoff timestamptz := now() - interval '30 days';
  v_items int := 0; v_blocks int := 0; v_entries int := 0; v_cats int := 0; v_ops int := 0;
  v_n int;
  v_i int;
BEGIN
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_block_items WHERE id IN (
      SELECT id FROM public.planning_block_items WHERE deleted_at < v_cutoff LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_items := v_items + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_blocks WHERE id IN (
      SELECT id FROM public.planning_blocks WHERE deleted_at < v_cutoff LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_blocks := v_blocks + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_entries WHERE id IN (
      SELECT id FROM public.planning_entries WHERE deleted_at < v_cutoff LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_entries := v_entries + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_categories WHERE id IN (
      SELECT id FROM public.planning_categories WHERE deleted_at < v_cutoff LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_cats := v_cats + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_applied_ops WHERE op_id IN (
      SELECT op_id FROM public.planning_applied_ops WHERE applied_at < now() - interval '7 days' LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_ops := v_ops + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  RETURN jsonb_build_object('items', v_items, 'blocks', v_blocks, 'entries', v_entries,
                            'categories', v_cats, 'ops', v_ops);
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_purge() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('planning_v2_purge', '17 3 * * *', $$SELECT public.planning_v2_purge()$$);
```

- [ ] **Step 4: Run all SQL tests**

Run: `bash scripts/local_pg_setup.sh --no-tests && for f in supabase/tests/planning_v2_*_contracts.sql; do psql -q -d attune_test -f "$f" || exit 1; done && bash supabase/tests/planning_v2_concurrency.sh`
Expected: six `PASS` notices and `planning_v2_concurrency: PASS`. Then run the **full** suite `bash scripts/local_pg_setup.sh` and confirm the v1 planning contracts (`planning_*_contracts.sql`, `ai_assist_planning_conversion_contracts.sql`) still pass. The only pre-existing failure allowed is `settings_accessor_test.sql` (needs local Vault).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261012200500_planning_v2_retention.sql supabase/tests/planning_v2_retention_contracts.sql
git commit -m "feat(planning-v2): nightly retention purge for soft-deleted rows and old op ids

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Dependency, errors, models, repository, limits mirror

**Files:**
- Modify: `pubspec.yaml` (add one dependency line)
- Create: `lib/features/planning/v2/data/planning_v2_error.dart`
- Create: `lib/features/planning/v2/data/planning_v2_models.dart`
- Create: `lib/features/planning/v2/data/planning_v2_repository.dart`
- Create: `lib/features/planning/v2/domain/planning_v2_limits.dart`
- Create: `test/features/planning/v2/support/fake_planning_gateway.dart`
- Test: `test/features/planning/v2/planning_v2_repository_test.dart`, `test/features/planning/v2/planning_v2_models_test.dart`, `test/features/planning/v2/planning_v2_limits_test.dart`

**Interfaces:**
- Consumes: `PlanningRpcGateway` / `SupabasePlanningRpcGateway` from `lib/features/planning/data/repositories/planning_repository.dart` (v1, import only). RPC names and JSON shapes from Tasks 3–5.
- Produces (used by Tasks 8–13, exact names):
  - `sealed class PlanningV2Error` with `PlanningV2Unauthorized({required bool inactive})`, `PlanningV2NotFound()`, `PlanningV2StaleVersion(Map<String,dynamic> current)`, `PlanningV2LimitReached(String limit)`, `PlanningV2InvalidInput(String field)`, `PlanningV2Network(Object cause)`; getter `bool isPermanent`; `PlanningV2Error mapPlanningV2Error(Object)`; `String planningV2ErrorMessage(PlanningV2Error)`.
  - Models: `PlanningBlockType {text, checklist, date, unsupported}`, `PlanningCategory`, `PlanningMember`, `PlanningItem`, `PlanningBlock`, `PlanningEntry`, `PlanningEntryDetail`, `PlanningEntrySummary`, `PlanningEntriesPage`; helper `String planningYmd(DateTime)`.
  - `class PlanningV2Repository` with the methods listed in Step 3.
  - `class PlanningV2Limits` (static consts + `Map<String,int> all`).

- [ ] **Step 1: Add the dependency and check it**

Add under `dependencies:` in `pubspec.yaml`, pinned exactly (it is the newest version that resolves against Flutter 3.29.1 / Dart 3.7 — 11.6.0 does not):

```yaml
  flutter_quill: 11.5.0
```

Run: `flutter pub get`
Expected: resolves; `pubspec.lock` gains `flutter_quill 11.5.0`.

Checklist 7.1 (dependency scan): run
`gh api "/advisories?ecosystem=pub&affects=flutter_quill" --jq 'length'`
Expected: `0`. If not 0, stop and report the advisories instead of continuing.

- [ ] **Step 2: Write the failing tests**

`test/features/planning/v2/support/fake_planning_gateway.dart`:

```dart
import 'package:attune/features/planning/data/repositories/planning_repository.dart';

typedef RpcHandler = dynamic Function(Map<String, dynamic> params);

/// Fakes the v1 RPC seam (planning_repository.dart) so v2 tests exercise
/// the real PlanningV2Repository mapping without Supabase.
class FakePlanningGateway implements PlanningRpcGateway {
  FakePlanningGateway([Map<String, RpcHandler>? handlers]) : handlers = handlers ?? {};

  final Map<String, RpcHandler> handlers;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    final p = params ?? const <String, dynamic>{};
    calls.add((function, p));
    final handler = handlers[function];
    if (handler == null) {
      throw StateError('FakePlanningGateway: no handler for $function');
    }
    return handler(p);
  }

  List<Map<String, dynamic>> callsTo(String function) =>
      [for (final c in calls) if (c.$1 == function) c.$2];
}

Map<String, dynamic> fakeItemJson({
  required String id,
  String text = 'Milk',
  String sortKey = 'V',
  String? section,
  String? checkedAt,
  String? assignedTo,
  int version = 1,
}) =>
    {
      'id': id, 'sort_key': sortKey, 'text': text, 'section': section,
      'checked_at': checkedAt, 'checked_by': checkedAt == null ? null : 'u-a',
      'assigned_to': assignedTo, 'due_date': null, 'version': version,
    };

Map<String, dynamic> fakeBlockJson({
  required String id,
  String type = 'checklist',
  Map<String, dynamic>? payload,
  String? plainText,
  String sortKey = 'V',
  String? dateStart,
  String? dateEnd,
  int version = 1,
  List<Map<String, dynamic>> items = const [],
}) =>
    {
      'id': id, 'block_type': type, 'sort_key': sortKey,
      'payload': payload ?? <String, dynamic>{}, 'plain_text': plainText,
      'date_start': dateStart, 'date_end': dateEnd, 'version': version,
      'updated_at': '2026-10-12T09:00:00Z', 'items': items,
    };

Map<String, dynamic> fakeEntryDetailJson({
  String id = 'e1',
  String title = 'Saturday shop',
  bool isTemplate = false,
  List<Map<String, dynamic>> blocks = const [],
}) =>
    {
      'entry': {
        'id': id, 'category_id': 'c1', 'category_name': 'Groceries',
        'category_seed_key': 'groceries', 'is_template': isTemplate, 'title': title,
        'status': 'active', 'currency': 'GHS', 'cover_path': null,
        'last_activity_at': '2026-10-12T09:00:00Z',
        'created_at': '2026-10-12T09:00:00Z', 'updated_at': '2026-10-12T09:00:00Z',
      },
      'members': [
        {'id': 'u-a', 'display_name': 'Ama'},
        {'id': 'u-b', 'display_name': 'Kofi'},
      ],
      'blocks': blocks,
    };

Map<String, dynamic> fakeCategoryJson({
  required String id,
  String? seedKey,
  String name = 'Groceries',
  String icon = 'cart',
  String color = 'green',
  bool hidden = false,
  int entryCount = 0,
  bool hasNew = false,
}) =>
    {
      'id': id, 'seed_key': seedKey, 'name': name, 'icon': icon, 'color': color,
      'sort_key': 'V', 'hidden': hidden, 'template_entry_id': 't-$id',
      'entry_count': entryCount, 'has_new': hasNew,
    };
```

`test/features/planning/v2/planning_v2_repository_test.dart`:

```dart
import 'package:attune/features/planning/v2/data/planning_v2_error.dart';
import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:attune/features/planning/v2/data/planning_v2_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';

PostgrestException _planning(String code, [String hint = '{}']) =>
    PostgrestException(message: 'planning:$code', code: 'P0001', hint: hint);

void main() {
  late FakePlanningGateway gateway;
  late PlanningV2Repository repo;

  setUp(() {
    gateway = FakePlanningGateway();
    repo = PlanningV2Repository(gateway);
  });

  group('error mapping', () {
    Future<PlanningV2Error> errorFor(Object thrown) async {
      gateway.handlers['get_planning_entry'] = (_) => throw thrown;
      try {
        await repo.getEntry('e1');
      } on PlanningV2Error catch (e) {
        return e;
      }
      fail('expected a PlanningV2Error');
    }

    test('not_found', () async {
      expect(await errorFor(_planning('not_found')), isA<PlanningV2NotFound>());
    });
    test('inactive is unauthorized(inactive: true)', () async {
      final e = await errorFor(_planning('inactive'));
      expect(e, isA<PlanningV2Unauthorized>());
      expect((e as PlanningV2Unauthorized).inactive, isTrue);
    });
    test('unauthenticated is unauthorized(inactive: false)', () async {
      final e = await errorFor(_planning('unauthenticated'));
      expect((e as PlanningV2Unauthorized).inactive, isFalse);
    });
    test('stale_version carries the current row from HINT', () async {
      final e = await errorFor(_planning('stale_version',
          '{"current":{"id":"b1","version":3}}'));
      expect((e as PlanningV2StaleVersion).current['version'], 3);
    });
    test('limit_reached names the limit', () async {
      final e = await errorFor(_planning('limit_reached', '{"limit":"items_per_block"}'));
      expect((e as PlanningV2LimitReached).limit, 'items_per_block');
    });
    test('invalid_input names the field', () async {
      final e = await errorFor(_planning('invalid_input', '{"field":"title"}'));
      expect((e as PlanningV2InvalidInput).field, 'title');
    });
    test('malformed HINT does not crash mapping', () async {
      final e = await errorFor(_planning('limit_reached', 'not json'));
      expect((e as PlanningV2LimitReached).limit, 'unknown');
    });
    test('42501 is unauthorized', () async {
      final e = await errorFor(const PostgrestException(message: 'denied', code: '42501'));
      expect(e, isA<PlanningV2Unauthorized>());
    });
    test('integrity violations are permanent invalid input, not network', () async {
      final e = await errorFor(const PostgrestException(message: 'check', code: '23514'));
      expect(e, isA<PlanningV2InvalidInput>());
      expect(e.isPermanent, isTrue);
    });
    test('anything else is network and retryable', () async {
      final e = await errorFor(Exception('socket closed'));
      expect(e, isA<PlanningV2Network>());
      expect(e.isPermanent, isFalse);
    });
    test('every error has a non-empty, internals-free message', () {
      const all = <PlanningV2Error>[
        PlanningV2Unauthorized(inactive: true), PlanningV2Unauthorized(inactive: false),
        PlanningV2NotFound(), PlanningV2StaleVersion({}),
        PlanningV2LimitReached('blocks_per_entry'), PlanningV2LimitReached('zzz'),
        PlanningV2InvalidInput('title'), PlanningV2InvalidInput('zzz'), PlanningV2Network('x'),
      ];
      for (final e in all) {
        final m = planningV2ErrorMessage(e);
        expect(m, isNotEmpty);
        expect(m, isNot(contains('planning:')));
        expect(m, isNot(contains('_')));
      }
    });
  });

  group('RPC names and parameters', () {
    test('getHome', () async {
      gateway.handlers['get_planning_home'] = (_) => {
            'categories': [fakeCategoryJson(id: 'c1', seedKey: 'groceries', hasNew: true)]
          };
      final cats = await repo.getHome('r1');
      expect(gateway.calls.single.$2, {'p_relationship_id': 'r1'});
      expect(cats.single.hasNew, isTrue);
      expect(cats.single.isStarter, isTrue);
    });

    test('listEntries passes group, cursor and limit', () async {
      gateway.handlers['list_planning_entries'] = (_) => {
            'entries': [
              {'id': 'e1', 'title': 'A', 'status': 'active',
               'last_activity_at': '2026-10-12T09:00:00Z', 'date_start': '2026-11-01',
               'date_end': null, 'checklist_done': 1, 'checklist_total': 4}
            ],
            'next_cursor': {'at': '2026-10-12T09:00:00Z', 'id': 'e1'},
          };
      final page = await repo.listEntries('c1',
          group: 'closed', cursorAt: DateTime.utc(2026, 10, 13), cursorId: 'e9', limit: 30);
      expect(gateway.calls.single.$2, {
        'p_category_id': 'c1', 'p_group': 'closed',
        'p_cursor_at': '2026-10-13T00:00:00.000Z', 'p_cursor_id': 'e9', 'p_limit': 30,
      });
      expect(page.hasMore, isTrue);
      expect(page.entries.single.checklistTotal, 4);
      expect(page.entries.single.dateStart, DateTime(2026, 11, 1));
    });

    test('createEntry', () async {
      gateway.handlers['create_planning_entry'] = (_) => fakeEntryDetailJson();
      await repo.createEntry(id: 'e1', categoryId: 'c1', title: 'Run', useTemplate: true, currency: 'GHS');
      expect(gateway.calls.single.$2, {
        'p_id': 'e1', 'p_category_id': 'c1', 'p_title': 'Run',
        'p_use_template': true, 'p_currency': 'GHS',
      });
    });

    test('addBlock sends wire type and ymd dates', () async {
      gateway.handlers['add_planning_block'] = (_) => fakeBlockJson(id: 'b1', type: 'date', dateStart: '2026-11-01');
      await repo.addBlock(id: 'b1', entryId: 'e1', type: PlanningBlockType.date,
          payload: const {}, dateStart: DateTime(2026, 11, 1), afterId: 'b0');
      expect(gateway.calls.single.$2, {
        'p_id': 'b1', 'p_entry_id': 'e1', 'p_block_type': 'date', 'p_payload': <String, dynamic>{},
        'p_date_start': '2026-11-01', 'p_date_end': null, 'p_after_id': 'b0',
      });
    });

    test('updateBlock sends version', () async {
      gateway.handlers['update_planning_block'] = (_) => fakeBlockJson(id: 'b1', version: 4);
      final b = await repo.updateBlock(id: 'b1', version: 3, payload: const {'title': 'x'});
      expect(gateway.calls.single.$2['p_version'], 3);
      expect(b.version, 4);
    });

    test('setItemChecked sends op id', () async {
      gateway.handlers['set_planning_block_item_checked'] = (_) => fakeItemJson(id: 'i1', checkedAt: '2026-10-12T09:00:00Z');
      final item = await repo.setItemChecked(id: 'i1', checked: true, opId: 'op1');
      expect(gateway.calls.single.$2, {'p_id': 'i1', 'p_checked': true, 'p_op_id': 'op1'});
      expect(item.isChecked, isTrue);
    });

    test('every v2 RPC name is distinct from v1 names', () {
      const v1 = {
        'create_planning_task', 'create_planning_goal', 'add_planning_goal_task',
        'update_planning_item', 'set_planning_task_completion', 'delete_planning_item',
        'upsert_planning_event', 'delete_planning_event', 'upsert_planning_note',
        'delete_planning_note', 'link_planning_event_task', 'unlink_planning_event_task',
      };
      expect(PlanningV2Repository.rpcNames.intersection(v1), isEmpty);
    });
  });
}
```

`test/features/planning/v2/planning_v2_models_test.dart`:

```dart
import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';

void main() {
  test('entry detail parses blocks, items and members in order', () {
    final d = PlanningEntryDetail.fromJson(fakeEntryDetailJson(blocks: [
      fakeBlockJson(id: 'b1', type: 'text', payload: {
        'delta': [{'insert': 'Hi\n'}]
      }, plainText: 'Hi'),
      fakeBlockJson(id: 'b2', items: [fakeItemJson(id: 'i1', section: 'Dairy')]),
      fakeBlockJson(id: 'b3', type: 'date', dateStart: '2026-11-01', dateEnd: '2026-11-05'),
    ]));
    expect(d.blocks.map((b) => b.type), [PlanningBlockType.text, PlanningBlockType.checklist, PlanningBlockType.date]);
    expect(d.blocks[1].items.single.section, 'Dairy');
    expect(d.blocks[2].dateEnd, DateTime(2026, 11, 5));
    expect(d.members.map((m) => m.displayName), ['Ama', 'Kofi']);
    expect(d.blocks[0].delta, [{'insert': 'Hi\n'}]);
  });

  test('a block type from a newer server parses as unsupported, not a crash', () {
    final b = PlanningBlock.fromJson(fakeBlockJson(id: 'b9', type: 'budget'));
    expect(b.type, PlanningBlockType.unsupported);
    expect(b.rawType, 'budget');
  });

  test('unicode titles round-trip unchanged (Review Focus 5)', () {
    const title = 'שלום 🌴 é';
    final d = PlanningEntryDetail.fromJson(fakeEntryDetailJson(title: title));
    expect(d.entry.title, title);
    expect(d.entry.title.runes.length, 8);
  });

  test('planningYmd pads', () {
    expect(planningYmd(DateTime(2026, 1, 5)), '2026-01-05');
  });
}
```

`test/features/planning/v2/planning_v2_limits_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/planning/v2/domain/planning_v2_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart limits mirror planning_limits() exactly (spec §3.11)', () {
    final sql = File('supabase/migrations/20261012200100_planning_v2_helpers.sql').readAsStringSync();
    final match = RegExp(r"SELECT '(\{[^']*\})'::jsonb").firstMatch(sql);
    expect(match, isNotNull, reason: 'planning_limits() literal not found');
    final server = (jsonDecode(match!.group(1)!) as Map<String, dynamic>).cast<String, int>();
    expect(PlanningV2Limits.all, server);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/planning/v2/`
Expected: FAIL — `planning_v2_repository.dart` etc. do not exist.

- [ ] **Step 4: Implement**

`lib/features/planning/v2/domain/planning_v2_limits.dart`:

```dart
/// Mirror of the server's `planning_limits()` (spec §3.11). A test parses
/// the migration literal and asserts equality, so neither side drifts.
class PlanningV2Limits {
  PlanningV2Limits._();

  static const categories = 50;
  static const blocksPerEntry = 200;
  static const itemsPerBlock = 500;
  static const payloadBytes = 16384;
  static const tableColumns = 12;
  static const tableRows = 50;
  static const photosPerBlock = 10;
  static const imageBytes = 10485760;
  static const textPlainChars = 10000;
  static const entriesPageDefault = 30;
  static const entriesPageMax = 100;
  static const titleChars = 120;
  static const categoryNameChars = 40;
  static const itemTextChars = 500;
  static const sectionChars = 40;

  static const Map<String, int> all = {
    'categories': categories,
    'blocks_per_entry': blocksPerEntry,
    'items_per_block': itemsPerBlock,
    'payload_bytes': payloadBytes,
    'table_columns': tableColumns,
    'table_rows': tableRows,
    'photos_per_block': photosPerBlock,
    'image_bytes': imageBytes,
    'text_plain_chars': textPlainChars,
    'entries_page_default': entriesPageDefault,
    'entries_page_max': entriesPageMax,
    'title_chars': titleChars,
    'category_name_chars': categoryNameChars,
    'item_text_chars': itemTextChars,
    'section_chars': sectionChars,
  };
}
```

`lib/features/planning/v2/data/planning_v2_error.dart`:

```dart
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Every failure the v2 repository throws. The server raises
/// `planning:<code>` with a JSON HINT (migration 20261012200100); this
/// type is the only thing the UI branches on — never message text.
sealed class PlanningV2Error implements Exception {
  const PlanningV2Error();

  /// Permanent errors must never be retried (checklist 3.10).
  bool get isPermanent => this is! PlanningV2Network;
}

/// Not signed in, or the relationship ended/archived. The UI fails
/// closed: it leaves Planning (spec §9).
class PlanningV2Unauthorized extends PlanningV2Error {
  const PlanningV2Unauthorized({required this.inactive});
  final bool inactive;
}

/// Missing or not yours — the server deliberately does not say which.
class PlanningV2NotFound extends PlanningV2Error {
  const PlanningV2NotFound();
}

/// Someone saved first. [current] is the server's row as of now.
class PlanningV2StaleVersion extends PlanningV2Error {
  const PlanningV2StaleVersion(this.current);
  final Map<String, dynamic> current;
}

class PlanningV2LimitReached extends PlanningV2Error {
  const PlanningV2LimitReached(this.limit);
  final String limit;
}

class PlanningV2InvalidInput extends PlanningV2Error {
  const PlanningV2InvalidInput(this.field);
  final String field;
}

/// Transient: offline, timeout, 5xx. Safe to retry.
class PlanningV2Network extends PlanningV2Error {
  const PlanningV2Network(this.cause);
  final Object cause;
}

PlanningV2Error mapPlanningV2Error(Object error) {
  if (error is PlanningV2Error) return error;
  if (error is PostgrestException) {
    if (error.code == '42501') return const PlanningV2Unauthorized(inactive: false);
    if (error.code == 'P0001' && error.message.startsWith('planning:')) {
      final detail = _decodeHint(error.hint);
      switch (error.message.substring('planning:'.length)) {
        case 'unauthenticated':
          return const PlanningV2Unauthorized(inactive: false);
        case 'inactive':
          return const PlanningV2Unauthorized(inactive: true);
        case 'not_found':
          return const PlanningV2NotFound();
        case 'stale_version':
          final current = detail['current'];
          return PlanningV2StaleVersion(
              current is Map ? Map<String, dynamic>.from(current) : const {});
        case 'limit_reached':
          return PlanningV2LimitReached(detail['limit'] as String? ?? 'unknown');
        case 'invalid_input':
          return PlanningV2InvalidInput(detail['field'] as String? ?? 'unknown');
      }
    }
    // SQLSTATE classes 22 (data) and 23 (integrity) can never succeed on retry.
    final code = error.code ?? '';
    if (code.startsWith('22') || code.startsWith('23')) {
      return const PlanningV2InvalidInput('unknown');
    }
  }
  return PlanningV2Network(error);
}

Map<String, dynamic> _decodeHint(String? hint) {
  if (hint == null || hint.isEmpty) return const {};
  try {
    final decoded = jsonDecode(hint);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

/// User-facing copy (checklist 5.1, 5.5): actionable, no internals.
String planningV2ErrorMessage(PlanningV2Error error) => switch (error) {
      PlanningV2Unauthorized(inactive: true) => 'Planning is closed for this relationship.',
      PlanningV2Unauthorized() => 'Please sign in again to keep planning.',
      PlanningV2NotFound() => 'That was removed by your partner.',
      PlanningV2StaleVersion() => 'Your partner just changed this.',
      PlanningV2LimitReached(limit: 'blocks_per_entry') => 'This page is full. Remove a block to add another.',
      PlanningV2LimitReached(limit: 'items_per_block') => 'This list is full. Start a new list to add more.',
      PlanningV2LimitReached(limit: 'categories') => 'You have the most categories allowed. Hide or delete one first.',
      PlanningV2LimitReached(limit: 'text_plain_chars') => 'That text is too long. Split it into two blocks.',
      PlanningV2LimitReached() => 'That is over the limit. Make it shorter and try again.',
      PlanningV2InvalidInput(field: 'title') => 'Give it a title (up to 120 characters).',
      PlanningV2InvalidInput(field: 'name') => 'Give it a name (up to 40 characters).',
      PlanningV2InvalidInput(field: 'text') => 'Write something (up to 500 characters).',
      PlanningV2InvalidInput(field: 'attribute') => 'Some formatting is not supported. Remove it and save again.',
      PlanningV2InvalidInput() => 'That could not be saved. Check it and try again.',
      PlanningV2Network() => 'Could not reach Attune. Check your connection and try again.',
    };
```

`lib/features/planning/v2/data/planning_v2_models.dart`:

```dart
/// Planning v2 models. Plain immutable classes with fromJson, matching
/// the v1 model style. JSON shapes: migrations 20261012200200..0400.
library;

enum PlanningBlockType { text, checklist, date, unsupported }

PlanningBlockType planningBlockTypeFromWire(String wire) => switch (wire) {
      'text' => PlanningBlockType.text,
      'checklist' => PlanningBlockType.checklist,
      'date' => PlanningBlockType.date,
      _ => PlanningBlockType.unsupported,
    };

String planningBlockTypeToWire(PlanningBlockType type) => switch (type) {
      PlanningBlockType.text => 'text',
      PlanningBlockType.checklist => 'checklist',
      PlanningBlockType.date => 'date',
      PlanningBlockType.unsupported => throw ArgumentError('unsupported has no wire form'),
    };

String planningYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
DateTime? _ts(Object? v) => v == null ? null : DateTime.parse(v as String);

class PlanningCategory {
  const PlanningCategory({
    required this.id,
    required this.seedKey,
    required this.name,
    required this.icon,
    required this.color,
    required this.sortKey,
    required this.hidden,
    required this.templateEntryId,
    required this.entryCount,
    required this.hasNew,
  });

  final String id;
  final String? seedKey;
  final String name;
  final String icon;
  final String color;
  final String sortKey;
  final bool hidden;
  final String? templateEntryId;
  final int entryCount;
  final bool hasNew;

  bool get isStarter => seedKey != null;

  /// Accepts both the home-read shape (`hidden`) and a raw row (`hidden_at`).
  factory PlanningCategory.fromJson(Map<String, dynamic> j) => PlanningCategory(
        id: j['id'] as String,
        seedKey: j['seed_key'] as String?,
        name: j['name'] as String,
        icon: j['icon'] as String,
        color: j['color'] as String,
        sortKey: j['sort_key'] as String,
        hidden: (j['hidden'] as bool?) ?? (j['hidden_at'] != null),
        templateEntryId: j['template_entry_id'] as String?,
        entryCount: (j['entry_count'] as num?)?.toInt() ?? 0,
        hasNew: (j['has_new'] as bool?) ?? false,
      );

  PlanningCategory copyWith({String? name, String? icon, String? color, bool? hidden, bool? hasNew}) =>
      PlanningCategory(
        id: id, seedKey: seedKey, name: name ?? this.name, icon: icon ?? this.icon,
        color: color ?? this.color, sortKey: sortKey, hidden: hidden ?? this.hidden,
        templateEntryId: templateEntryId, entryCount: entryCount, hasNew: hasNew ?? this.hasNew,
      );
}

class PlanningMember {
  const PlanningMember({required this.id, required this.displayName});
  final String id;
  final String displayName;

  factory PlanningMember.fromJson(Map<String, dynamic> j) =>
      PlanningMember(id: j['id'] as String, displayName: (j['display_name'] as String?) ?? '');

  String get initial => displayName.isEmpty ? '?' : displayName.characters0;
}

extension on String {
  /// First user-perceived character for avatars, without pulling in
  /// package:characters for one call: first rune is good enough for initials.
  String get characters0 => String.fromCharCode(runes.first).toUpperCase();
}

class PlanningItem {
  const PlanningItem({
    required this.id,
    required this.sortKey,
    required this.text,
    required this.section,
    required this.checkedAt,
    required this.checkedBy,
    required this.assignedTo,
    required this.dueDate,
    required this.version,
  });

  final String id;
  final String sortKey;
  final String text;
  final String? section;
  final DateTime? checkedAt;
  final String? checkedBy;
  final String? assignedTo;
  final DateTime? dueDate;
  final int version;

  bool get isChecked => checkedAt != null;

  factory PlanningItem.fromJson(Map<String, dynamic> j) => PlanningItem(
        id: j['id'] as String,
        sortKey: j['sort_key'] as String,
        text: (j['text'] as String?) ?? '',
        section: j['section'] as String?,
        checkedAt: _ts(j['checked_at']),
        checkedBy: j['checked_by'] as String?,
        assignedTo: j['assigned_to'] as String?,
        dueDate: _date(j['due_date']),
        version: (j['version'] as num).toInt(),
      );

  PlanningItem copyWith({
    String? text,
    String? section,
    DateTime? checkedAt,
    bool clearChecked = false,
    String? checkedBy,
    String? assignedTo,
    bool clearAssignee = false,
    int? version,
  }) =>
      PlanningItem(
        id: id,
        sortKey: sortKey,
        text: text ?? this.text,
        section: section ?? this.section,
        checkedAt: clearChecked ? null : (checkedAt ?? this.checkedAt),
        checkedBy: clearChecked ? null : (checkedBy ?? this.checkedBy),
        assignedTo: clearAssignee ? null : (assignedTo ?? this.assignedTo),
        dueDate: dueDate,
        version: version ?? this.version,
      );
}

class PlanningBlock {
  const PlanningBlock({
    required this.id,
    required this.type,
    required this.rawType,
    required this.sortKey,
    required this.payload,
    required this.plainText,
    required this.dateStart,
    required this.dateEnd,
    required this.version,
    required this.items,
  });

  final String id;
  final PlanningBlockType type;
  final String rawType;
  final String sortKey;
  final Map<String, dynamic> payload;
  final String? plainText;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final int version;
  final List<PlanningItem> items;

  String? get title => payload['title'] as String?;

  /// Quill Delta ops for a text block; a single newline when empty.
  List<Map<String, dynamic>> get delta {
    final raw = payload['delta'];
    if (raw is! List || raw.isEmpty) return const [{'insert': '\n'}];
    return [for (final op in raw) Map<String, dynamic>.from(op as Map)];
  }

  factory PlanningBlock.fromJson(Map<String, dynamic> j) => PlanningBlock(
        id: j['id'] as String,
        type: planningBlockTypeFromWire(j['block_type'] as String),
        rawType: j['block_type'] as String,
        sortKey: j['sort_key'] as String,
        payload: Map<String, dynamic>.from((j['payload'] as Map?) ?? const {}),
        plainText: j['plain_text'] as String?,
        dateStart: _date(j['date_start']),
        dateEnd: _date(j['date_end']),
        version: (j['version'] as num).toInt(),
        items: [
          for (final i in (j['items'] as List? ?? const []))
            PlanningItem.fromJson(Map<String, dynamic>.from(i as Map))
        ],
      );

  PlanningBlock copyWith({List<PlanningItem>? items, int? version}) => PlanningBlock(
        id: id, type: type, rawType: rawType, sortKey: sortKey, payload: payload,
        plainText: plainText, dateStart: dateStart, dateEnd: dateEnd,
        version: version ?? this.version, items: items ?? this.items,
      );
}

class PlanningEntry {
  const PlanningEntry({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.categorySeedKey,
    required this.isTemplate,
    required this.title,
    required this.status,
    required this.currency,
    required this.lastActivityAt,
  });

  final String id;
  final String categoryId;
  final String categoryName;
  final String? categorySeedKey;
  final bool isTemplate;
  final String title;
  final String status;
  final String currency;
  final DateTime lastActivityAt;

  factory PlanningEntry.fromJson(Map<String, dynamic> j) => PlanningEntry(
        id: j['id'] as String,
        categoryId: j['category_id'] as String,
        categoryName: j['category_name'] as String,
        categorySeedKey: j['category_seed_key'] as String?,
        isTemplate: j['is_template'] as bool,
        title: j['title'] as String,
        status: j['status'] as String,
        currency: j['currency'] as String,
        lastActivityAt: DateTime.parse(j['last_activity_at'] as String),
      );
}

class PlanningEntryDetail {
  const PlanningEntryDetail({required this.entry, required this.members, required this.blocks});

  final PlanningEntry entry;
  final List<PlanningMember> members;
  final List<PlanningBlock> blocks;

  factory PlanningEntryDetail.fromJson(Map<String, dynamic> j) => PlanningEntryDetail(
        entry: PlanningEntry.fromJson(Map<String, dynamic>.from(j['entry'] as Map)),
        members: [
          for (final m in (j['members'] as List? ?? const []))
            PlanningMember.fromJson(Map<String, dynamic>.from(m as Map))
        ],
        blocks: [
          for (final b in (j['blocks'] as List? ?? const []))
            PlanningBlock.fromJson(Map<String, dynamic>.from(b as Map))
        ],
      );

  PlanningEntryDetail copyWith({PlanningEntry? entry, List<PlanningBlock>? blocks}) =>
      PlanningEntryDetail(entry: entry ?? this.entry, members: members, blocks: blocks ?? this.blocks);

  PlanningMember? member(String? id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }
}

class PlanningEntrySummary {
  const PlanningEntrySummary({
    required this.id,
    required this.title,
    required this.status,
    required this.lastActivityAt,
    required this.dateStart,
    required this.dateEnd,
    required this.checklistDone,
    required this.checklistTotal,
  });

  final String id;
  final String title;
  final String status;
  final DateTime lastActivityAt;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final int checklistDone;
  final int checklistTotal;

  factory PlanningEntrySummary.fromJson(Map<String, dynamic> j) => PlanningEntrySummary(
        id: j['id'] as String,
        title: j['title'] as String,
        status: j['status'] as String,
        lastActivityAt: DateTime.parse(j['last_activity_at'] as String),
        dateStart: _date(j['date_start']),
        dateEnd: _date(j['date_end']),
        checklistDone: (j['checklist_done'] as num).toInt(),
        checklistTotal: (j['checklist_total'] as num).toInt(),
      );
}

class PlanningEntriesPage {
  const PlanningEntriesPage({required this.entries, required this.nextCursorAt, required this.nextCursorId});

  final List<PlanningEntrySummary> entries;
  final DateTime? nextCursorAt;
  final String? nextCursorId;

  bool get hasMore => nextCursorId != null;

  factory PlanningEntriesPage.fromJson(Map<String, dynamic> j) {
    final cursor = j['next_cursor'];
    return PlanningEntriesPage(
      entries: [
        for (final e in (j['entries'] as List? ?? const []))
          PlanningEntrySummary.fromJson(Map<String, dynamic>.from(e as Map))
      ],
      nextCursorAt: cursor is Map ? DateTime.parse(cursor['at'] as String) : null,
      nextCursorId: cursor is Map ? cursor['id'] as String : null,
    );
  }
}
```

`lib/features/planning/v2/data/planning_v2_repository.dart`:

```dart
import 'package:attune/features/planning/data/repositories/planning_repository.dart'
    show PlanningRpcGateway;

import 'planning_v2_error.dart';
import 'planning_v2_models.dart';

/// One method per v2 RPC. Every failure surfaces as [PlanningV2Error].
class PlanningV2Repository {
  const PlanningV2Repository(this._gateway);

  final PlanningRpcGateway _gateway;

  /// Every RPC this repository calls; a test asserts none collides with v1.
  static const rpcNames = {
    'get_planning_home', 'create_planning_category', 'update_planning_category',
    'set_planning_category_hidden', 'delete_planning_category', 'move_planning_category',
    'mark_planning_category_seen', 'list_planning_entries', 'create_planning_entry',
    'duplicate_planning_entry', 'update_planning_entry', 'delete_planning_entry',
    'get_planning_entry', 'reset_planning_template', 'add_planning_block',
    'update_planning_block', 'delete_planning_block', 'restore_planning_block',
    'move_planning_block', 'add_planning_block_item', 'update_planning_block_item',
    'set_planning_block_item_checked', 'delete_planning_block_item',
    'restore_planning_block_item', 'move_planning_block_item',
  };

  Future<Map<String, dynamic>> _call(String fn, Map<String, dynamic> params) async {
    assert(rpcNames.contains(fn), '$fn missing from rpcNames');
    try {
      final result = await _gateway.rpc(fn, params: params);
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      throw mapPlanningV2Error(e);
    }
  }

  // ---- categories ----

  Future<List<PlanningCategory>> getHome(String relationshipId) async {
    final r = await _call('get_planning_home', {'p_relationship_id': relationshipId});
    return [
      for (final c in (r['categories'] as List? ?? const []))
        PlanningCategory.fromJson(Map<String, dynamic>.from(c as Map))
    ];
  }

  Future<PlanningCategory> createCategory({
    required String id,
    required String relationshipId,
    required String name,
    required String icon,
    required String color,
  }) async =>
      PlanningCategory.fromJson(await _call('create_planning_category', {
        'p_id': id, 'p_relationship_id': relationshipId, 'p_name': name,
        'p_icon': icon, 'p_color': color,
      }));

  Future<PlanningCategory> updateCategory({
    required String id,
    required String name,
    required String icon,
    required String color,
  }) async =>
      PlanningCategory.fromJson(await _call('update_planning_category',
          {'p_id': id, 'p_name': name, 'p_icon': icon, 'p_color': color}));

  Future<void> setCategoryHidden(String id, {required bool hidden}) =>
      _call('set_planning_category_hidden', {'p_id': id, 'p_hidden': hidden});

  Future<int> deleteCategory(String id) async =>
      ((await _call('delete_planning_category', {'p_id': id}))['deleted_entries'] as num).toInt();

  Future<void> moveCategory(String id, {required String? afterId}) =>
      _call('move_planning_category', {'p_id': id, 'p_after_id': afterId});

  Future<void> markCategorySeen(String id) => _call('mark_planning_category_seen', {'p_id': id});

  // ---- entries ----

  Future<PlanningEntriesPage> listEntries(
    String categoryId, {
    String group = 'open',
    DateTime? cursorAt,
    String? cursorId,
    int limit = 30,
  }) async =>
      PlanningEntriesPage.fromJson(await _call('list_planning_entries', {
        'p_category_id': categoryId, 'p_group': group,
        'p_cursor_at': cursorAt?.toUtc().toIso8601String(), 'p_cursor_id': cursorId,
        'p_limit': limit,
      }));

  Future<PlanningEntryDetail> createEntry({
    required String id,
    required String categoryId,
    required String title,
    required bool useTemplate,
    required String currency,
  }) async =>
      PlanningEntryDetail.fromJson(await _call('create_planning_entry', {
        'p_id': id, 'p_category_id': categoryId, 'p_title': title,
        'p_use_template': useTemplate, 'p_currency': currency,
      }));

  Future<PlanningEntryDetail> duplicateEntry({
    required String sourceId,
    required String newId,
    required String title,
  }) async =>
      PlanningEntryDetail.fromJson(await _call('duplicate_planning_entry',
          {'p_source_id': sourceId, 'p_new_id': newId, 'p_title': title}));

  Future<PlanningEntry> updateEntry({required String id, required String title, required String status}) async {
    final r = await _call('update_planning_entry', {'p_id': id, 'p_title': title, 'p_status': status});
    return PlanningEntry.fromJson(Map<String, dynamic>.from(r['entry'] as Map));
  }

  Future<void> deleteEntry(String id) => _call('delete_planning_entry', {'p_id': id});

  Future<PlanningEntryDetail> getEntry(String id) async =>
      PlanningEntryDetail.fromJson(await _call('get_planning_entry', {'p_id': id}));

  Future<PlanningEntryDetail> resetTemplate(String categoryId) async =>
      PlanningEntryDetail.fromJson(await _call('reset_planning_template', {'p_category_id': categoryId}));

  // ---- blocks ----

  Future<PlanningBlock> addBlock({
    required String id,
    required String entryId,
    required PlanningBlockType type,
    required Map<String, dynamic> payload,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? afterId,
  }) async =>
      PlanningBlock.fromJson(await _call('add_planning_block', {
        'p_id': id, 'p_entry_id': entryId, 'p_block_type': planningBlockTypeToWire(type),
        'p_payload': payload,
        'p_date_start': dateStart == null ? null : planningYmd(dateStart),
        'p_date_end': dateEnd == null ? null : planningYmd(dateEnd),
        'p_after_id': afterId,
      }));

  Future<PlanningBlock> updateBlock({
    required String id,
    required int version,
    required Map<String, dynamic> payload,
    DateTime? dateStart,
    DateTime? dateEnd,
  }) async =>
      PlanningBlock.fromJson(await _call('update_planning_block', {
        'p_id': id, 'p_version': version, 'p_payload': payload,
        'p_date_start': dateStart == null ? null : planningYmd(dateStart),
        'p_date_end': dateEnd == null ? null : planningYmd(dateEnd),
      }));

  Future<void> deleteBlock(String id) => _call('delete_planning_block', {'p_id': id});

  Future<PlanningBlock> restoreBlock(String id) async =>
      PlanningBlock.fromJson(await _call('restore_planning_block', {'p_id': id}));

  Future<PlanningBlock> moveBlock(String id, {required String? afterId}) async =>
      PlanningBlock.fromJson(await _call('move_planning_block', {'p_id': id, 'p_after_id': afterId}));

  // ---- items ----

  Future<PlanningItem> addItem({
    required String id,
    required String blockId,
    required String text,
    String? section,
    String? assignedTo,
    DateTime? dueDate,
    String? afterId,
  }) async =>
      PlanningItem.fromJson(await _call('add_planning_block_item', {
        'p_id': id, 'p_block_id': blockId, 'p_text': text, 'p_section': section,
        'p_assigned_to': assignedTo,
        'p_due_date': dueDate == null ? null : planningYmd(dueDate),
        'p_after_id': afterId,
      }));

  Future<PlanningItem> updateItem({
    required String id,
    required int version,
    required String text,
    String? section,
    String? assignedTo,
    DateTime? dueDate,
  }) async =>
      PlanningItem.fromJson(await _call('update_planning_block_item', {
        'p_id': id, 'p_version': version, 'p_text': text, 'p_section': section,
        'p_assigned_to': assignedTo,
        'p_due_date': dueDate == null ? null : planningYmd(dueDate),
      }));

  Future<PlanningItem> setItemChecked({required String id, required bool checked, required String opId}) async =>
      PlanningItem.fromJson(await _call('set_planning_block_item_checked',
          {'p_id': id, 'p_checked': checked, 'p_op_id': opId}));

  Future<void> deleteItem(String id) => _call('delete_planning_block_item', {'p_id': id});

  Future<PlanningItem> restoreItem(String id) async =>
      PlanningItem.fromJson(await _call('restore_planning_block_item', {'p_id': id}));

  Future<PlanningItem> moveItem(String id, {required String? afterId}) async =>
      PlanningItem.fromJson(await _call('move_planning_block_item', {'p_id': id, 'p_after_id': afterId}));
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/planning/v2/ && flutter analyze lib/features/planning/v2 test/features/planning/v2`
Expected: all PASS; analyzer `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/planning/v2 test/features/planning/v2
git commit -m "feat(planning-v2): typed errors, models and repository over the v2 RPCs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Domain — Delta sanitizer and offline outbox

**Files:**
- Create: `lib/features/planning/v2/domain/delta_sanitizer.dart`
- Create: `lib/features/planning/v2/domain/planning_outbox.dart`
- Test: `test/features/planning/v2/delta_sanitizer_test.dart`, `test/features/planning/v2/planning_outbox_test.dart`

**Interfaces:**
- Consumes: `PlanningV2Error` (Task 7).
- Produces:
  - `const Set<String> planningPaletteTokens`; `SanitizedDelta sanitizeDelta(List<dynamic> ops)` with `List<Map<String,dynamic>> ops` and `bool changed`; `String deltaPlainText(List<Map<String,dynamic>> ops)`.
  - `sealed class OutboxOp` (`CheckItemOp`, `AddItemOp`) with `opId`, `relationshipId`, `entryId`, `toJson()`, `OutboxOp.fromJson`.
  - `abstract class OutboxStore` (`Future<List<Map<String,dynamic>>> read()`, `Future<void> write(List<Map<String,dynamic>>)`), `SharedPreferencesOutboxStore`, `MemoryOutboxStore`.
  - `class PlanningOutbox` (`enqueue`, `replay`, `pending`, `ValueNotifier<int> pendingCount`), `OutboxFullException`, `OutboxReplayResult(sent, dropped, remaining)`.

- [ ] **Step 1: Write the failing tests**

`test/features/planning/v2/delta_sanitizer_test.dart`:

```dart
import 'package:attune/features/planning/v2/domain/delta_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allowed formatting is kept verbatim', () {
    final ops = [
      {'insert': 'Bali', 'attributes': {'bold': true, 'background': 'yellow', 'link': 'https://x.com'}},
      {'insert': '\n', 'attributes': {'header': 2, 'align': 'center'}},
    ];
    final r = sanitizeDelta(ops);
    expect(r.changed, isFalse);
    expect(r.ops, ops);
  });

  test('pasted foreign attributes are stripped (Review Focus 4)', () {
    final r = sanitizeDelta([
      {'insert': 'Pasted', 'attributes': {'font': 'serif', 'size': 'large', 'color': '#ff0000', 'bold': true}},
      {'insert': '\n', 'attributes': {'list': 'checked'}},
    ]);
    expect(r.changed, isTrue);
    expect(r.ops, [
      {'insert': 'Pasted', 'attributes': {'bold': true}},
      {'insert': '\n'},
    ]);
  });

  test('null-valued attributes from toggling are dropped silently', () {
    final r = sanitizeDelta([
      {'insert': 'x', 'attributes': {'bold': null}},
      {'insert': '\n'},
    ]);
    expect(r.ops.first, {'insert': 'x'});
    expect(r.changed, isFalse);
  });

  test('embeds are removed; unsafe links are unlinked', () {
    final r = sanitizeDelta([
      {'insert': {'image': 'x.png'}},
      {'insert': 'click', 'attributes': {'link': 'javascript:alert(1)'}},
      {'insert': '\n'},
    ]);
    expect(r.changed, isTrue);
    expect(r.ops, [{'insert': 'click'}, {'insert': '\n'}]);
  });

  test('a missing trailing newline is added; empty input becomes one newline', () {
    expect(sanitizeDelta([{'insert': 'no newline'}]).ops.last, {'insert': '\n'});
    expect(sanitizeDelta(const []).ops, [{'insert': '\n'}]);
  });

  test('plain text mirrors the server projection', () {
    expect(deltaPlainText(const [{'insert': 'Buy '}, {'insert': 'fresh'}, {'insert': '\n\n'}]), 'Buy fresh');
  });
}
```

`test/features/planning/v2/planning_outbox_test.dart`:

```dart
import 'dart:math';

import 'package:attune/features/planning/v2/data/planning_v2_error.dart';
import 'package:attune/features/planning/v2/domain/planning_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

CheckItemOp _tick(String id, {bool checked = true}) => CheckItemOp(
    opId: 'op-$id', relationshipId: 'r1', entryId: 'e1', itemId: id, checked: checked);

void main() {
  late MemoryOutboxStore store;
  late List<OutboxOp> sent;
  late List<Duration> sleeps;
  late Object? Function(OutboxOp op) behaviour;

  PlanningOutbox make() => PlanningOutbox(
        store: store,
        send: (op) async {
          sent.add(op);
          final r = behaviour(op);
          if (r != null) throw r;
        },
        random: Random(7),
        sleep: (d) async => sleeps.add(d),
      );

  setUp(() {
    store = MemoryOutboxStore();
    sent = [];
    sleeps = [];
    behaviour = (_) => null;
  });

  test('ops persist across outbox instances (survives restart)', () async {
    await make().enqueue(_tick('i1'));
    final again = make();
    expect((await again.pending()).single.opId, 'op-i1');
    expect(again.pendingCount.value, 1);
  });

  test('enqueue is idempotent by op id', () async {
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.enqueue(_tick('i1'));
    expect(await o.pending(), hasLength(1));
  });

  test('capacity is 200', () async {
    final o = make();
    for (var i = 0; i < 200; i++) {
      await o.enqueue(_tick('i$i'));
    }
    expect(() => o.enqueue(_tick('overflow')), throwsA(isA<OutboxFullException>()));
  });

  test('replay sends in order and empties the queue', () async {
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.enqueue(AddItemOp(opId: 'i2', relationshipId: 'r1', entryId: 'e1', itemId: 'i2',
        blockId: 'b1', text: 'Milk', section: null, afterId: 'i1'));
    final r = await o.replay();
    expect(sent.map((s) => s.opId), ['op-i1', 'i2']);
    expect(r.sent, 2);
    expect(await o.pending(), isEmpty);
    expect(o.pendingCount.value, 0);
  });

  test('permanent errors drop the op and continue (checklist 3.10)', () async {
    behaviour = (op) => op.opId == 'op-i1' ? const PlanningV2NotFound() : null;
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.enqueue(_tick('i2'));
    final r = await o.replay();
    expect(r.dropped.single.opId, 'op-i1');
    expect(r.sent, 1);
    expect(sleeps, isEmpty, reason: 'permanent errors are never retried');
  });

  test('network errors back off with jitter within bounds, then stop and keep the rest', () async {
    behaviour = (_) => const PlanningV2Network('offline');
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.enqueue(_tick('i2'));
    final r = await o.replay();
    expect(sent.where((s) => s.opId == 'op-i1'), hasLength(6), reason: '6 attempts');
    expect(sent.where((s) => s.opId == 'op-i2'), isEmpty, reason: 'later ops wait behind a failing one');
    expect(sleeps, hasLength(5));
    for (var i = 0; i < sleeps.length; i++) {
      final cap = Duration(milliseconds: min(30000, 500 * (1 << i)));
      expect(sleeps[i] <= cap, isTrue, reason: 'attempt $i slept ${sleeps[i]} > $cap');
    }
    expect(r.remaining, 2);
  });

  test('replay is idempotent: every retry of an op reuses its op id (Review Focus 3)', () async {
    var calls = 0;
    behaviour = (_) => ++calls < 3 ? const PlanningV2Network('flaky') : null;
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.replay();
    expect(sent.map((s) => s.opId).toSet(), {'op-i1'});
    expect(sent, hasLength(3));
  });

  test('concurrent replay calls share one run', () async {
    final o = make();
    await o.enqueue(_tick('i1'));
    await Future.wait([o.replay(), o.replay()]);
    expect(sent, hasLength(1));
  });

  test('a corrupt stored queue is discarded, not fatal', () async {
    store.raw = [{'kind': 'nonsense'}];
    expect(await make().pending(), isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/planning/v2/delta_sanitizer_test.dart test/features/planning/v2/planning_outbox_test.dart`
Expected: FAIL — files do not exist.

- [ ] **Step 3: Implement**

`lib/features/planning/v2/domain/delta_sanitizer.dart`:

```dart
/// Client mirror of the server's rich-text whitelist (spec §6.1,
/// migration 20261012200100 `planning_delta_attribute_ok`). The server
/// stays the authority; this exists so text pasted from other apps is
/// cleaned BEFORE save and the user never sees a rejection for
/// formatting they did not choose (Review Focus 4).
library;

const Set<String> planningPaletteTokens = {'yellow', 'green', 'blue', 'pink', 'purple'};

final RegExp _httpUrl = RegExp(r'^https?://\S+$', caseSensitive: false);

class SanitizedDelta {
  const SanitizedDelta(this.ops, {required this.changed});
  final List<Map<String, dynamic>> ops;

  /// True when anything the user could see was removed.
  final bool changed;
}

bool _allowed(String key, Object? value) => switch (key) {
      'bold' || 'italic' || 'underline' || 'strike' || 'blockquote' => value == true,
      'background' || 'color' => planningPaletteTokens.contains(value),
      'header' => value == 1 || value == 2 || value == 3,
      'align' => value == 'center' || value == 'right' || value == 'justify',
      'list' => value == 'bullet' || value == 'ordered',
      'link' => value is String && value.length <= 2048 && _httpUrl.hasMatch(value),
      _ => false,
    };

SanitizedDelta sanitizeDelta(List<dynamic> input) {
  var changed = false;
  final out = <Map<String, dynamic>>[];
  for (final raw in input) {
    if (raw is! Map) {
      changed = true;
      continue;
    }
    final insert = raw['insert'];
    if (insert is! String) {
      changed = true; // embed
      continue;
    }
    final attrs = raw['attributes'];
    final kept = <String, dynamic>{};
    if (attrs is Map) {
      attrs.forEach((k, v) {
        if (v == null) return; // toggled-off attribute; invisible
        if (_allowed(k as String, v)) {
          kept[k] = v;
        } else {
          changed = true;
        }
      });
    }
    out.add({'insert': insert, if (kept.isNotEmpty) 'attributes': kept});
  }
  if (out.isEmpty || !(out.last['insert'] as String).endsWith('\n')) {
    out.add({'insert': '\n'});
  }
  return SanitizedDelta(out, changed: changed);
}

String deltaPlainText(List<Map<String, dynamic>> ops) =>
    ops.map((o) => o['insert'] as String).join().replaceFirst(RegExp(r'\n+$'), '');
```

`lib/features/planning/v2/domain/planning_outbox.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/planning_v2_error.dart';

/// Offline queue for checklist ticks and item adds (spec §10). Bounded
/// (200), persisted, replayed in order with exponential backoff + full
/// jitter (checklist 3.9: base 500ms, cap 30s, 6 attempts). Permanent
/// errors drop the op and are reported, never retried (3.10). Each op
/// carries a stable id so a replay after a lost response cannot apply
/// twice (server dedupes on it: planning_applied_ops / client item ids).
sealed class OutboxOp {
  const OutboxOp({required this.opId, required this.relationshipId, required this.entryId});

  final String opId;
  final String relationshipId;
  final String entryId;

  Map<String, dynamic> toJson();

  static OutboxOp? fromJson(Map<String, dynamic> j) {
    try {
      return switch (j['kind']) {
        'check' => CheckItemOp(
            opId: j['op_id'] as String, relationshipId: j['relationship_id'] as String,
            entryId: j['entry_id'] as String, itemId: j['item_id'] as String,
            checked: j['checked'] as bool),
        'add' => AddItemOp(
            opId: j['op_id'] as String, relationshipId: j['relationship_id'] as String,
            entryId: j['entry_id'] as String, itemId: j['item_id'] as String,
            blockId: j['block_id'] as String, text: j['text'] as String,
            section: j['section'] as String?, afterId: j['after_id'] as String?),
        _ => null,
      };
    } on TypeError {
      return null;
    }
  }
}

class CheckItemOp extends OutboxOp {
  const CheckItemOp({
    required super.opId,
    required super.relationshipId,
    required super.entryId,
    required this.itemId,
    required this.checked,
  });

  final String itemId;
  final bool checked;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'check', 'op_id': opId, 'relationship_id': relationshipId,
        'entry_id': entryId, 'item_id': itemId, 'checked': checked,
      };
}

/// The item's own client-generated id is its op id: add is idempotent
/// by item id on the server.
class AddItemOp extends OutboxOp {
  const AddItemOp({
    required super.opId,
    required super.relationshipId,
    required super.entryId,
    required this.itemId,
    required this.blockId,
    required this.text,
    required this.section,
    required this.afterId,
  });

  final String itemId;
  final String blockId;
  final String text;
  final String? section;
  final String? afterId;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'add', 'op_id': opId, 'relationship_id': relationshipId,
        'entry_id': entryId, 'item_id': itemId, 'block_id': blockId,
        'text': text, 'section': section, 'after_id': afterId,
      };
}

abstract class OutboxStore {
  Future<List<Map<String, dynamic>>> read();
  Future<void> write(List<Map<String, dynamic>> ops);
}

class MemoryOutboxStore implements OutboxStore {
  List<Map<String, dynamic>> raw = [];

  @override
  Future<List<Map<String, dynamic>>> read() async => [...raw];

  @override
  Future<void> write(List<Map<String, dynamic>> ops) async => raw = [...ops];
}

class SharedPreferencesOutboxStore implements OutboxStore {
  static const _key = 'planning_v2_outbox_v1';

  @override
  Future<List<Map<String, dynamic>>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_key);
      if (s == null) return [];
      return [for (final o in jsonDecode(s) as List) Map<String, dynamic>.from(o as Map)];
    } catch (_) {
      return []; // corrupt or unavailable storage must never block planning
    }
  }

  @override
  Future<void> write(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(ops));
  }
}

class OutboxFullException implements Exception {
  const OutboxFullException();
}

class OutboxReplayResult {
  const OutboxReplayResult({required this.sent, required this.dropped, required this.remaining});
  final int sent;
  final List<OutboxOp> dropped;
  final int remaining;
}

typedef OutboxSender = Future<void> Function(OutboxOp op);

class PlanningOutbox {
  PlanningOutbox({
    required OutboxStore store,
    required OutboxSender send,
    Random? random,
    Future<void> Function(Duration)? sleep,
    this.capacity = 200,
    this.maxAttempts = 6,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
  })  : _store = store,
        _send = send,
        _random = random ?? Random(),
        _sleep = sleep ?? Future<void>.delayed {
    unawaited(pending());
  }

  final OutboxStore _store;
  final OutboxSender _send;
  final Random _random;
  final Future<void> Function(Duration) _sleep;
  final int capacity;
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);
  Future<OutboxReplayResult>? _inFlight;

  Future<List<OutboxOp>> pending() async {
    final ops = [
      for (final j in await _store.read())
        if (OutboxOp.fromJson(j) case final op?) op
    ];
    pendingCount.value = ops.length;
    return ops;
  }

  Future<void> _save(List<OutboxOp> ops) async {
    await _store.write([for (final o in ops) o.toJson()]);
    pendingCount.value = ops.length;
  }

  Future<void> enqueue(OutboxOp op) async {
    final ops = await pending();
    if (ops.any((o) => o.opId == op.opId)) return;
    if (ops.length >= capacity) throw const OutboxFullException();
    await _save([...ops, op]);
  }

  Duration _backoff(int attempt) {
    final capMs = min(maxDelay.inMilliseconds, baseDelay.inMilliseconds * (1 << attempt));
    return Duration(milliseconds: (_random.nextDouble() * capMs).round());
  }

  /// One replay at a time; concurrent callers share the in-flight run.
  Future<OutboxReplayResult> replay() => _inFlight ??= _replay().whenComplete(() => _inFlight = null);

  Future<OutboxReplayResult> _replay() async {
    var ops = await pending();
    var sent = 0;
    final dropped = <OutboxOp>[];
    while (ops.isNotEmpty) {
      final op = ops.first;
      var delivered = false;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          await _send(op);
          delivered = true;
          sent++;
          break;
        } catch (e) {
          final error = mapPlanningV2Error(e);
          if (error.isPermanent) {
            dropped.add(op);
            delivered = true; // resolved: never retry a permanent failure
            break;
          }
          if (attempt < maxAttempts - 1) await _sleep(_backoff(attempt));
        }
      }
      if (!delivered) {
        return OutboxReplayResult(sent: sent, dropped: dropped, remaining: ops.length);
      }
      ops = ops.sublist(1);
      await _save(ops);
    }
    return OutboxReplayResult(sent: sent, dropped: dropped, remaining: 0);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/planning/v2/ && flutter analyze lib/features/planning/v2 test/features/planning/v2`
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/planning/v2/domain test/features/planning/v2
git commit -m "feat(planning-v2): rich-text sanitizer and persisted offline outbox

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Providers and the entry controller

**Files:**
- Create: `lib/features/planning/v2/presentation/planning_v2_providers.dart`
- Create: `test/features/planning/v2/support/planning_v2_test_app.dart`
- Test: `test/features/planning/v2/planning_v2_providers_test.dart`

**Interfaces:**
- Consumes: Task 7 repository/models/errors; Task 8 outbox; v1 `planningChangeSignalProvider` (import only, from `lib/features/planning/presentation/providers/planning_providers.dart`).
- Produces (exact names, used by Tasks 10–14):
  - `planningV2RepositoryProvider` (`Provider<PlanningV2Repository>`)
  - `planningV2CurrentUserIdProvider` (`Provider<String?>`)
  - `planningV2OutboxStoreProvider` (`Provider<OutboxStore>`), `planningV2OutboxSleepProvider` (`Provider<Future<void> Function(Duration)>`), `planningV2OutboxProvider` (`Provider<PlanningOutbox>`)
  - `planningV2HomeProvider` (`FutureProvider.autoDispose.family<List<PlanningCategory>, String>`; arg = relationship id)
  - `typedef PlanningEntriesArgs = ({String relationshipId, String categoryId, String group})`; `PlanningEntriesState`; `planningV2EntriesProvider` with `loadMore()`
  - `typedef PlanningEntryArgs = ({String relationshipId, String entryId})`; `planningV2EntryProvider` → `PlanningEntryController` with: `setChecked`, `addItem`, `updateItem`, `deleteItem`, `restoreItem`, `addBlock`, `deleteBlock`, `restoreBlock`, `moveBlock`, `setDate`, `saveText`, `rename`, `setStatus`
  - `enum TickOutcome { synced, queued }`; `sealed class TextSaveResult` → `TextSaved(PlanningBlock)`, `TextConflict(PlanningBlock theirs)`, `TextGone()`

- [ ] **Step 1: Write the test harness and failing tests**

`test/features/planning/v2/support/planning_v2_test_app.dart`:

```dart
import 'package:attune/features/planning/presentation/providers/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:attune/features/planning/v2/data/planning_v2_repository.dart';
import 'package:attune/features/planning/v2/domain/planning_outbox.dart';
import 'package:attune/features/planning/v2/presentation/planning_v2_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_planning_gateway.dart';

List<Override> planningV2Overrides(
  FakePlanningGateway gateway, {
  MemoryOutboxStore? store,
  String userId = 'u-a',
}) =>
    [
      planningV2RepositoryProvider.overrideWithValue(PlanningV2Repository(gateway)),
      planningChangeSignalProvider.overrideWith((ref, relationshipId) => const Stream<void>.empty()),
      planningV2OutboxStoreProvider.overrideWithValue(store ?? MemoryOutboxStore()),
      planningV2OutboxSleepProvider.overrideWithValue((_) async {}),
      planningV2CurrentUserIdProvider.overrideWithValue(userId),
    ];

Widget planningV2TestApp(
  FakePlanningGateway gateway,
  Widget home, {
  MemoryOutboxStore? store,
  ThemeMode themeMode = ThemeMode.light,
}) =>
    ProviderScope(
      overrides: planningV2Overrides(gateway, store: store),
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: themeMode,
        home: home,
      ),
    );
```

`test/features/planning/v2/planning_v2_providers_test.dart`:

```dart
import 'dart:convert';

import 'package:attune/features/planning/v2/data/planning_v2_error.dart';
import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:attune/features/planning/v2/domain/planning_outbox.dart';
import 'package:attune/features/planning/v2/presentation/planning_v2_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

const args = (relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _gatewayWithEntry() => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 'b1', items: [fakeItemJson(id: 'i1', text: 'Tomatoes')]),
            fakeBlockJson(id: 'b2', type: 'date', sortKey: 'k'),
          ]),
    });

void main() {
  late FakePlanningGateway gateway;
  late MemoryOutboxStore store;
  late ProviderContainer c;

  Future<PlanningEntryController> ready() async {
    await c.read(planningV2EntryProvider(args).future);
    return c.read(planningV2EntryProvider(args).notifier);
  }

  PlanningEntryDetail current() => c.read(planningV2EntryProvider(args)).requireValue;

  setUp(() {
    gateway = _gatewayWithEntry();
    store = MemoryOutboxStore();
    c = ProviderContainer(overrides: planningV2Overrides(gateway, store: store));
    addTearDown(c.dispose);
    // keep autoDispose providers alive for the test
    c.listen(planningV2EntryProvider(args), (_, __) {});
  });

  test('tick is optimistic, then replaced by the server row', () async {
    final ctl = await ready();
    gateway.handlers['set_planning_block_item_checked'] =
        (_) => fakeItemJson(id: 'i1', text: 'Tomatoes', checkedAt: '2026-10-12T09:00:00Z', version: 2);
    final f = ctl.setChecked('b1', current().blocks.first.items.first, true);
    expect(current().blocks.first.items.first.isChecked, isTrue, reason: 'optimistic');
    expect(await f, TickOutcome.synced);
    expect(current().blocks.first.items.first.version, 2);
  });

  test('offline tick is queued, stays ticked, and survives a refetch', () async {
    final ctl = await ready();
    gateway.handlers['set_planning_block_item_checked'] =
        (_) => throw Exception('SocketException: offline');
    expect(await ctl.setChecked('b1', current().blocks.first.items.first, true), TickOutcome.queued);
    expect(store.raw, hasLength(1));
    c.invalidate(planningV2EntryProvider(args));
    await c.read(planningV2EntryProvider(args).future);
    expect(current().blocks.first.items.first.isChecked, isTrue,
        reason: 'pending outbox ops are overlaid on fetched data');
  });

  test('a permanent tick failure reverts just that item and rethrows', () async {
    final ctl = await ready();
    gateway.handlers['set_planning_block_item_checked'] =
        (_) => throw const PostgrestException(message: 'planning:not_found', code: 'P0001');
    await expectLater(ctl.setChecked('b1', current().blocks.first.items.first, true),
        throwsA(isA<PlanningV2NotFound>()));
    expect(current().blocks.first.items.first.isChecked, isFalse);
    expect(store.raw, isEmpty);
  });

  test('addItem appends after the last item and replaces with the server row', () async {
    final ctl = await ready();
    gateway.handlers['add_planning_block_item'] =
        (p) => fakeItemJson(id: p['p_id'] as String, text: 'Milk', sortKey: 'k');
    await ctl.addItem('b1', 'Milk');
    expect(gateway.callsTo('add_planning_block_item').single['p_after_id'], 'i1');
    expect(current().blocks.first.items.map((i) => i.text), ['Tomatoes', 'Milk']);
  });

  test('delete block is optimistic and restore puts it back in place', () async {
    final ctl = await ready();
    gateway.handlers['delete_planning_block'] = (_) => {'deleted': true};
    gateway.handlers['restore_planning_block'] =
        (_) => fakeBlockJson(id: 'b1', items: [fakeItemJson(id: 'i1', text: 'Tomatoes')]);
    await ctl.deleteBlock('b1');
    expect(current().blocks.map((b) => b.id), ['b2']);
    await ctl.restoreBlock('b1', index: 0);
    expect(current().blocks.map((b) => b.id), ['b1', 'b2']);
  });

  test('moveBlock sends the id it now follows', () async {
    final ctl = await ready();
    gateway.handlers['move_planning_block'] = (_) => fakeBlockJson(id: 'b1', sortKey: 'z');
    await ctl.moveBlock('b1', 1);
    expect(current().blocks.map((b) => b.id), ['b2', 'b1']);
    expect(gateway.callsTo('move_planning_block').single['p_after_id'], 'b2');
  });

  test('saveText: conflict returns theirs; not_found removes the block', () async {
    final ctl = await ready();
    gateway.handlers['update_planning_block'] = (_) => throw PostgrestException(
          message: 'planning:stale_version',
          code: 'P0001',
          hint: jsonEncode({
            'current': fakeBlockJson(id: 'b1', type: 'text', plainText: 'Kofi', version: 5, payload: {
              'delta': [{'insert': 'Kofi\n'}]
            }),
          }),
        );
    final r = await ctl.saveText('b1', 1, const [{'insert': 'Ama\n'}]);
    expect(r, isA<TextConflict>());
    expect((r as TextConflict).theirs.version, 5);

    gateway.handlers['update_planning_block'] =
        (_) => throw const PostgrestException(message: 'planning:not_found', code: 'P0001');
    expect(await ctl.saveText('b1', 5, const [{'insert': 'Ama\n'}]), isA<TextGone>());
    expect(current().blocks.map((b) => b.id), ['b2']);
  });

  test('entries pager: second page appends; hasMore false at the end', () async {
    var page = 0;
    gateway.handlers['list_planning_entries'] = (p) {
      page++;
      return {
        'entries': [
          {'id': 'e$page', 'title': 'T$page', 'status': 'active', 'last_activity_at': '2026-10-12T09:00:00Z',
           'date_start': null, 'date_end': null, 'checklist_done': 0, 'checklist_total': 0}
        ],
        'next_cursor': page == 1 ? {'at': '2026-10-12T09:00:00Z', 'id': 'e1'} : null,
      };
    };
    const a = (relationshipId: 'r1', categoryId: 'c1', group: 'open');
    c.listen(planningV2EntriesProvider(a), (_, __) {});
    await c.read(planningV2EntriesProvider(a).future);
    await c.read(planningV2EntriesProvider(a).notifier).loadMore();
    final s = c.read(planningV2EntriesProvider(a)).requireValue;
    expect(s.entries.map((e) => e.id), ['e1', 'e2']);
    expect(s.hasMore, isFalse);
    expect(gateway.callsTo('list_planning_entries').last['p_cursor_id'], 'e1');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/planning/v2/planning_v2_providers_test.dart`
Expected: FAIL — `planning_v2_providers.dart` does not exist.

- [ ] **Step 3: Implement**

`lib/features/planning/v2/presentation/planning_v2_providers.dart`:

```dart
import 'dart:async';

import 'package:attune/features/planning/data/repositories/planning_repository.dart'
    show SupabasePlanningRpcGateway;
import 'package:attune/features/planning/presentation/providers/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/planning_v2_error.dart';
import '../data/planning_v2_models.dart';
import '../data/planning_v2_repository.dart';
import '../domain/planning_outbox.dart';

const _uuid = Uuid();

final planningV2RepositoryProvider = Provider<PlanningV2Repository>(
  (ref) => PlanningV2Repository(SupabasePlanningRpcGateway(Supabase.instance.client)),
);

final planningV2CurrentUserIdProvider =
    Provider<String?>((ref) => Supabase.instance.client.auth.currentUser?.id);

final planningV2OutboxStoreProvider = Provider<OutboxStore>((ref) => SharedPreferencesOutboxStore());

final planningV2OutboxSleepProvider =
    Provider<Future<void> Function(Duration)>((ref) => Future<void>.delayed);

/// One outbox for the app session (not autoDispose): queued ticks must
/// outlive the screen that made them.
final planningV2OutboxProvider = Provider<PlanningOutbox>((ref) {
  final repo = ref.watch(planningV2RepositoryProvider);
  return PlanningOutbox(
    store: ref.watch(planningV2OutboxStoreProvider),
    sleep: ref.watch(planningV2OutboxSleepProvider),
    send: (op) => switch (op) {
      CheckItemOp() => repo.setItemChecked(id: op.itemId, checked: op.checked, opId: op.opId),
      AddItemOp() => repo.addItem(
          id: op.itemId, blockId: op.blockId, text: op.text, section: op.section, afterId: op.afterId),
    },
  );
});

/// Change signal → refetch. The signal also fires on resubscribe and app
/// resume (v1 provider), which is when connectivity has likely returned,
/// so it is also the outbox replay trigger.
void _refetchOnSignal(Ref ref, String relationshipId, {bool replayOutbox = false}) {
  ref.listen(planningChangeSignalProvider(relationshipId), (_, __) {
    if (replayOutbox) {
      unawaited(ref.read(planningV2OutboxProvider).replay().then((r) {
        if (r.sent > 0 || r.dropped.isNotEmpty) ref.invalidateSelf();
      }));
    }
    ref.invalidateSelf();
  });
}

final planningV2HomeProvider =
    FutureProvider.autoDispose.family<List<PlanningCategory>, String>((ref, relationshipId) {
  _refetchOnSignal(ref, relationshipId);
  return ref.watch(planningV2RepositoryProvider).getHome(relationshipId);
});

// ---- entries list --------------------------------------------------------

typedef PlanningEntriesArgs = ({String relationshipId, String categoryId, String group});

class PlanningEntriesState {
  const PlanningEntriesState({
    required this.entries,
    required this.cursorAt,
    required this.cursorId,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<PlanningEntrySummary> entries;
  final DateTime? cursorAt;
  final String? cursorId;
  final bool loadingMore;
  final bool loadMoreFailed;

  bool get hasMore => cursorId != null;
}

/// Own pager rather than v1's PlanningKeysetPager: v1's refresh() resets
/// to a bare loading state, which drops visible content; spec §6.4
/// requires retained content during refresh (AsyncNotifier keeps the
/// previous value while reloading).
class PlanningEntriesController
    extends AutoDisposeFamilyAsyncNotifier<PlanningEntriesState, PlanningEntriesArgs> {
  @override
  Future<PlanningEntriesState> build(PlanningEntriesArgs arg) async {
    _refetchOnSignal(ref, arg.relationshipId);
    final page = await ref.read(planningV2RepositoryProvider).listEntries(arg.categoryId, group: arg.group);
    return PlanningEntriesState(entries: page.entries, cursorAt: page.nextCursorAt, cursorId: page.nextCursorId);
  }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || s.loadingMore || !s.hasMore) return;
    state = AsyncData(PlanningEntriesState(
        entries: s.entries, cursorAt: s.cursorAt, cursorId: s.cursorId, loadingMore: true));
    try {
      final page = await ref.read(planningV2RepositoryProvider).listEntries(
          arg.categoryId, group: arg.group, cursorAt: s.cursorAt, cursorId: s.cursorId);
      state = AsyncData(PlanningEntriesState(
          entries: [...s.entries, ...page.entries], cursorAt: page.nextCursorAt, cursorId: page.nextCursorId));
    } on PlanningV2Error {
      state = AsyncData(PlanningEntriesState(
          entries: s.entries, cursorAt: s.cursorAt, cursorId: s.cursorId, loadMoreFailed: true));
    }
  }
}

final planningV2EntriesProvider = AsyncNotifierProvider.autoDispose
    .family<PlanningEntriesController, PlanningEntriesState, PlanningEntriesArgs>(PlanningEntriesController.new);

// ---- one entry -----------------------------------------------------------

typedef PlanningEntryArgs = ({String relationshipId, String entryId});

enum TickOutcome { synced, queued }

sealed class TextSaveResult {
  const TextSaveResult();
}

class TextSaved extends TextSaveResult {
  const TextSaved(this.block);
  final PlanningBlock block;
}

class TextConflict extends TextSaveResult {
  const TextConflict(this.theirs);
  final PlanningBlock theirs;
}

class TextGone extends TextSaveResult {
  const TextGone();
}

class PlanningEntryController extends AutoDisposeFamilyAsyncNotifier<PlanningEntryDetail, PlanningEntryArgs> {
  PlanningV2Repository get _repo => ref.read(planningV2RepositoryProvider);
  PlanningOutbox get _outbox => ref.read(planningV2OutboxProvider);

  @override
  Future<PlanningEntryDetail> build(PlanningEntryArgs arg) async {
    _refetchOnSignal(ref, arg.relationshipId, replayOutbox: true);
    final detail = await _repo.getEntry(arg.entryId);
    final pending = [for (final op in await _outbox.pending()) if (op.entryId == arg.entryId) op];
    return _overlay(detail, pending);
  }

  /// Applies queued-but-unsent ops so an offline tick or add never
  /// visually reverts on refetch.
  PlanningEntryDetail _overlay(PlanningEntryDetail d, List<OutboxOp> ops) {
    var out = d;
    for (final op in ops) {
      switch (op) {
        case CheckItemOp():
          for (final b in out.blocks) {
            for (final i in b.items) {
              if (i.id == op.itemId) {
                out = _withItem(out, b.id, op.checked
                    ? i.copyWith(checkedAt: i.checkedAt ?? DateTime.now(), checkedBy: i.checkedBy)
                    : i.copyWith(clearChecked: true));
              }
            }
          }
        case AddItemOp():
          final exists = out.blocks.any((b) => b.items.any((i) => i.id == op.itemId));
          if (!exists && out.blocks.any((b) => b.id == op.blockId)) {
            out = _withBlockItems(out, op.blockId, (items) => [...items, _localItem(op.itemId, op.text, op.section)]);
          }
      }
    }
    return out;
  }

  PlanningItem _localItem(String id, String text, String? section) => PlanningItem(
      id: id, sortKey: '~', text: text, section: section, checkedAt: null, checkedBy: null,
      assignedTo: null, dueDate: null, version: 1);

  PlanningEntryDetail get _current => state.requireValue;
  void _set(PlanningEntryDetail d) => state = AsyncData(d);

  PlanningEntryDetail _withBlocks(PlanningEntryDetail d, List<PlanningBlock> blocks) => d.copyWith(blocks: blocks);

  PlanningEntryDetail _withBlock(PlanningEntryDetail d, PlanningBlock b) =>
      _withBlocks(d, [for (final x in d.blocks) x.id == b.id ? b : x]);

  PlanningEntryDetail _withBlockItems(
          PlanningEntryDetail d, String blockId, List<PlanningItem> Function(List<PlanningItem>) f) =>
      _withBlocks(d, [for (final x in d.blocks) x.id == blockId ? x.copyWith(items: f(x.items)) : x]);

  PlanningEntryDetail _withItem(PlanningEntryDetail d, String blockId, PlanningItem item) =>
      _withBlockItems(d, blockId, (items) => [for (final i in items) i.id == item.id ? item : i]);

  // ---- items ----

  Future<TickOutcome> setChecked(String blockId, PlanningItem item, bool checked) async {
    final me = ref.read(planningV2CurrentUserIdProvider);
    _set(_withItem(_current, blockId,
        checked ? item.copyWith(checkedAt: DateTime.now(), checkedBy: me) : item.copyWith(clearChecked: true)));
    final opId = _uuid.v4();
    try {
      final saved = await _repo.setItemChecked(id: item.id, checked: checked, opId: opId);
      if (state.hasValue) _set(_withItem(_current, blockId, saved));
      return TickOutcome.synced;
    } on PlanningV2Network {
      try {
        await _outbox.enqueue(CheckItemOp(
            opId: opId, relationshipId: arg.relationshipId, entryId: arg.entryId, itemId: item.id, checked: checked));
        return TickOutcome.queued;
      } on OutboxFullException {
        if (state.hasValue) _set(_withItem(_current, blockId, item));
        rethrow;
      }
    } on PlanningV2Error {
      if (state.hasValue) _set(_withItem(_current, blockId, item));
      rethrow;
    }
  }

  Future<TickOutcome> addItem(String blockId, String text, {String? section}) async {
    final id = _uuid.v4();
    final block = _current.blocks.firstWhere((b) => b.id == blockId);
    final afterId = block.items.isEmpty ? null : block.items.last.id;
    _set(_withBlockItems(_current, blockId, (items) => [...items, _localItem(id, text.trim(), section)]));
    try {
      final saved = await _repo.addItem(id: id, blockId: blockId, text: text.trim(), section: section, afterId: afterId);
      if (state.hasValue) _set(_withItem(_current, blockId, saved));
      return TickOutcome.synced;
    } on PlanningV2Network {
      try {
        await _outbox.enqueue(AddItemOp(opId: id, relationshipId: arg.relationshipId, entryId: arg.entryId,
            itemId: id, blockId: blockId, text: text.trim(), section: section, afterId: afterId));
        return TickOutcome.queued;
      } on OutboxFullException {
        if (state.hasValue) _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != id) i]));
        rethrow;
      }
    } on PlanningV2Error {
      if (state.hasValue) _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != id) i]));
      rethrow;
    }
  }

  /// Stale: the partner changed it first — adopt theirs and rethrow so the
  /// UI can say so. Not found: drop it.
  Future<void> updateItem(String blockId, PlanningItem item,
      {required String text, String? section, String? assignedTo, DateTime? dueDate}) async {
    try {
      final saved = await _repo.updateItem(
          id: item.id, version: item.version, text: text, section: section, assignedTo: assignedTo, dueDate: dueDate);
      _set(_withItem(_current, blockId, saved));
    } on PlanningV2StaleVersion catch (e) {
      _set(_withItem(_current, blockId, PlanningItem.fromJson(e.current)));
      rethrow;
    } on PlanningV2NotFound {
      _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != item.id) i]));
      rethrow;
    }
  }

  Future<void> deleteItem(String blockId, String itemId) async {
    final before = _current;
    _set(_withBlockItems(before, blockId, (items) => [for (final i in items) if (i.id != itemId) i]));
    try {
      await _repo.deleteItem(itemId);
    } on PlanningV2Error {
      _set(before);
      rethrow;
    }
  }

  Future<void> restoreItem(String blockId, String itemId, {required int index}) async {
    final restored = await _repo.restoreItem(itemId);
    _set(_withBlockItems(_current, blockId, (items) {
      final list = [for (final i in items) if (i.id != itemId) i];
      list.insert(index.clamp(0, list.length), restored);
      return list;
    }));
  }

  // ---- blocks ----

  static Map<String, dynamic> _defaultPayload(PlanningBlockType type) => switch (type) {
        PlanningBlockType.text => {
            'delta': [{'insert': '\n'}]
          },
        _ => <String, dynamic>{},
      };

  Future<PlanningBlock> addBlock(PlanningBlockType type) async {
    final blocks = _current.blocks;
    final block = await _repo.addBlock(
      id: _uuid.v4(),
      entryId: arg.entryId,
      type: type,
      payload: _defaultPayload(type),
      afterId: blocks.isEmpty ? null : blocks.last.id,
    );
    _set(_withBlocks(_current, [..._current.blocks, block]));
    return block;
  }

  Future<void> deleteBlock(String blockId) async {
    final before = _current;
    _set(_withBlocks(before, [for (final b in before.blocks) if (b.id != blockId) b]));
    try {
      await _repo.deleteBlock(blockId);
    } on PlanningV2Error {
      _set(before);
      rethrow;
    }
  }

  Future<void> restoreBlock(String blockId, {required int index}) async {
    final restored = await _repo.restoreBlock(blockId);
    final list = [for (final b in _current.blocks) if (b.id != blockId) b];
    list.insert(index.clamp(0, list.length), restored);
    _set(_withBlocks(_current, list));
  }

  /// [newIndex] is the block's index after the move.
  Future<void> moveBlock(String blockId, int newIndex) async {
    final before = _current;
    final list = [...before.blocks];
    final moving = list.firstWhere((b) => b.id == blockId);
    list.remove(moving);
    final at = newIndex.clamp(0, list.length);
    list.insert(at, moving);
    _set(_withBlocks(before, list));
    try {
      await _repo.moveBlock(blockId, afterId: at == 0 ? null : list[at - 1].id);
    } on PlanningV2Error {
      _set(before);
      rethrow;
    }
  }

  Future<void> setDate(PlanningBlock block, DateTime? start, DateTime? end) async {
    try {
      final saved = await _repo.updateBlock(
          id: block.id, version: block.version, payload: block.payload, dateStart: start, dateEnd: end);
      _set(_withBlock(_current, saved));
    } on PlanningV2StaleVersion catch (e) {
      _set(_withBlock(_current, PlanningBlock.fromJson(e.current)));
      rethrow;
    }
  }

  Future<TextSaveResult> saveText(String blockId, int version, List<Map<String, dynamic>> ops) async {
    try {
      final saved = await _repo.updateBlock(id: blockId, version: version, payload: {'delta': ops});
      _set(_withBlock(_current, saved));
      return TextSaved(saved);
    } on PlanningV2StaleVersion catch (e) {
      final theirs = PlanningBlock.fromJson(e.current);
      _set(_withBlock(_current, theirs));
      return TextConflict(theirs);
    } on PlanningV2NotFound {
      _set(_withBlocks(_current, [for (final b in _current.blocks) if (b.id != blockId) b]));
      return const TextGone();
    }
  }

  // ---- entry ----

  Future<void> rename(String title) async {
    final e = await _repo.updateEntry(id: arg.entryId, title: title, status: _current.entry.status);
    _set(_current.copyWith(entry: e));
  }

  Future<void> setStatus(String status) async {
    final e = await _repo.updateEntry(id: arg.entryId, title: _current.entry.title, status: status);
    _set(_current.copyWith(entry: e));
  }
}

final planningV2EntryProvider = AsyncNotifierProvider.autoDispose
    .family<PlanningEntryController, PlanningEntryDetail, PlanningEntryArgs>(PlanningEntryController.new);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/planning/v2/ && flutter analyze lib/features/planning/v2 test/features/planning/v2`
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/planning/v2/presentation/planning_v2_providers.dart test/features/planning/v2
git commit -m "feat(planning-v2): providers and entry controller with optimistic edits and outbox overlay

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: UI kit and the Planning home screen

**Files:**
- Create: `lib/features/planning/v2/presentation/planning_v2_ui.dart`
- Create: `lib/features/planning/v2/presentation/widgets/category_editor_sheet.dart`
- Create: `lib/features/planning/v2/presentation/screens/planning_v2_home_screen.dart`
- Test: `test/features/planning/v2/planning_v2_home_screen_test.dart`, `test/features/planning/v2/planning_v2_ui_test.dart`

**Interfaces:**
- Consumes: Task 9 providers; Task 7 models/errors.
- Produces:
  - `planning_v2_ui.dart`: `const List<String> planningV2IconKeys`, `const List<String> planningV2ColorKeys`, `IconData planningV2Icon(String key)`, `({Color container, Color onContainer}) planningV2Tone(BuildContext, String token)`, `Map<String, Color> planningV2HighlightPalette(Brightness)`, `Color planningV2TextTone(String token, Brightness)`, `const planningV2RouteName`, `Route<T> planningV2Route<T>(Widget page)`, `void showPlanningV2Error(BuildContext, Object error)`, `String formatPlanningRange(DateTime? start, DateTime? end)`, widgets `PlanningV2ErrorState`, `PlanningV2EmptyState`, `PlanningV2NewDot`.
  - `Future<CategoryDraft?> showCategoryEditorSheet(BuildContext, {CategoryDraft? initial})` with `typedef CategoryDraft = ({String name, String icon, String color})`.
  - `PlanningV2HomeScreen({required String relationshipId})`.
- Task 11 creates `PlanningV2CategoryScreen`; this task imports it. To keep this task compiling on its own, Task 10 creates a minimal `planning_v2_category_screen.dart` stub (Step 3) that Task 11 replaces.

- [ ] **Step 1: Write the failing tests**

`test/features/planning/v2/planning_v2_ui_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/planning/v2/presentation/planning_v2_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _sqlArray(String fn) {
  final sql = File('supabase/migrations/20261012200100_planning_v2_helpers.sql').readAsStringSync();
  final body = RegExp('FUNCTION public.$fn\\(\\)[\\s\\S]*?ARRAY\\[([\\s\\S]*?)\\]').firstMatch(sql)!.group(1)!;
  return RegExp(r"'([a-z]+)'").allMatches(body).map((m) => m.group(1)!).toList();
}

void main() {
  test('icon and colour keys match the server allow-lists exactly', () {
    expect(planningV2IconKeys, _sqlArray('planning_v2_icons'));
    expect(planningV2ColorKeys, _sqlArray('planning_v2_colors'));
    for (final k in planningV2IconKeys) {
      expect(planningV2Icon(k), isNot(Icons.folder_rounded), reason: 'icon $k unmapped');
    }
  });

  test('highlight palette covers every rich-text token in both themes', () {
    for (final b in Brightness.values) {
      expect(planningV2HighlightPalette(b).keys.toSet(), {'yellow', 'green', 'blue', 'pink', 'purple'});
    }
  });

  test('date ranges format for humans', () {
    expect(formatPlanningRange(null, null), 'Pick a date');
    expect(formatPlanningRange(DateTime(2026, 3, 3), null), 'Mar 3, 2026');
    expect(formatPlanningRange(DateTime(2026, 3, 3), DateTime(2026, 3, 13)), 'Mar 3 – Mar 13, 2026');
    expect(formatPlanningRange(DateTime(2026, 12, 30), DateTime(2027, 1, 2)), 'Dec 30, 2026 – Jan 2, 2027');
  });
}
```

`test/features/planning/v2/planning_v2_home_screen_test.dart`:

```dart
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

FakePlanningGateway _gateway() => FakePlanningGateway({
      'get_planning_home': (_) => {
            'categories': [
              fakeCategoryJson(id: 'c1', seedKey: 'goals', name: 'Goals', icon: 'flag', color: 'rose', entryCount: 2, hasNew: true),
              fakeCategoryJson(id: 'c2', seedKey: 'trips', name: 'Trips', icon: 'plane', color: 'teal'),
              fakeCategoryJson(id: 'c3', name: 'Wedding', icon: 'ring', color: 'violet', hidden: true),
            ]
          },
    });

void main() {
  testWidgets('shows visible categories in order with counts and a labelled new dot', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(planningV2TestApp(_gateway(), const PlanningV2HomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('2 plans'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Wedding'), findsNothing, reason: 'hidden until expanded');
    expect(find.bySemanticsLabel('New from your partner'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('hidden categories appear under the Hidden row', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(), const PlanningV2HomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hidden (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Wedding'), findsOneWidget);
  });

  testWidgets('creating a category sends trimmed name and chosen icon and colour', (tester) async {
    final semantics = tester.ensureSemantics();
    final g = _gateway();
    g.handlers['create_planning_category'] = (p) => fakeCategoryJson(id: p['p_id'] as String, name: 'Moving');
    await tester.pumpWidget(planningV2TestApp(g, const PlanningV2HomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Moving  ');
    await tester.pump(); // enterText does not pump; Save enables on rebuild
    await tester.tap(find.bySemanticsLabel('Icon box'));
    await tester.tap(find.bySemanticsLabel('Colour orange'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final call = g.callsTo('create_planning_category').single;
    expect(call['p_name'], 'Moving');
    expect(call['p_icon'], 'box');
    expect(call['p_color'], 'orange');
    expect(call['p_relationship_id'], 'r1');
    expect(g.callsTo('get_planning_home'), hasLength(2), reason: 'refetched after create');
    semantics.dispose(); // must be disposed inside the test body
  });

  testWidgets('a load error shows an actionable message and Retry', (tester) async {
    var fail = true;
    final g = _gateway();
    final ok = g.handlers['get_planning_home']!;
    g.handlers['get_planning_home'] = (p) {
      if (fail) throw Exception('offline');
      return ok(p);
    };
    await tester.pumpWidget(planningV2TestApp(g, const PlanningV2HomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Could not reach Attune. Check your connection and try again.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsOneWidget);
  });

  testWidgets('an ended relationship shows the closed message, not Retry', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_home': (_) => throw const PostgrestException(message: 'planning:inactive', code: 'P0001'),
    });
    await tester.pumpWidget(planningV2TestApp(g, const PlanningV2HomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Planning is closed for this relationship.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('renders in dark mode without errors', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(), const PlanningV2HomeScreen(relationshipId: 'r1'),
        themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/planning/v2/planning_v2_ui_test.dart test/features/planning/v2/planning_v2_home_screen_test.dart`
Expected: FAIL — files do not exist.

- [ ] **Step 3: Implement**

`lib/features/planning/v2/presentation/planning_v2_ui.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/planning_v2_error.dart';

/// Must equal `planning_v2_icons()` / `planning_v2_colors()` in migration
/// 20261012200100 (a test parses the SQL and compares).
const List<String> planningV2IconKeys = [
  'flag', 'plane', 'heart', 'home', 'cart', 'sun', 'star', 'gift', 'book',
  'dumbbell', 'utensils', 'baby', 'ring', 'box', 'music', 'paw',
];
const List<String> planningV2ColorKeys = ['rose', 'amber', 'teal', 'indigo', 'green', 'slate', 'violet', 'orange'];

const Map<String, IconData> _icons = {
  'flag': Icons.flag_rounded, 'plane': Icons.flight_rounded, 'heart': Icons.favorite_rounded,
  'home': Icons.home_rounded, 'cart': Icons.shopping_cart_rounded, 'sun': Icons.wb_sunny_rounded,
  'star': Icons.star_rounded, 'gift': Icons.card_giftcard_rounded, 'book': Icons.menu_book_rounded,
  'dumbbell': Icons.fitness_center_rounded, 'utensils': Icons.restaurant_rounded,
  'baby': Icons.child_friendly_rounded, 'ring': Icons.diamond_rounded, 'box': Icons.inventory_2_rounded,
  'music': Icons.music_note_rounded, 'paw': Icons.pets_rounded,
};

IconData planningV2Icon(String key) => _icons[key] ?? Icons.folder_rounded;

const Map<String, Color> _seeds = {
  'rose': Color(0xFFE11D48), 'amber': Color(0xFFF59E0B), 'teal': Color(0xFF14B8A6),
  'indigo': Color(0xFF6366F1), 'green': Color(0xFF22C55E), 'slate': Color(0xFF64748B),
  'violet': Color(0xFF8B5CF6), 'orange': Color(0xFFF97316),
};

final Map<(String, Brightness), ColorScheme> _schemes = {};

/// Category colours are TOKENS, resolved per theme brightness so dark
/// mode gets its own tonal pair. Cached: fromSeed is not free.
({Color container, Color onContainer}) planningV2Tone(BuildContext context, String token) {
  final brightness = Theme.of(context).brightness;
  final scheme = _schemes.putIfAbsent((token, brightness),
      () => ColorScheme.fromSeed(seedColor: _seeds[token] ?? _seeds['slate']!, brightness: brightness));
  return (container: scheme.primaryContainer, onContainer: scheme.onPrimaryContainer);
}

/// Rich-text highlight tokens (spec §6.1). Quill resolves `background`
/// through DefaultStyles.palette first, so tokens never become hex.
Map<String, Color> planningV2HighlightPalette(Brightness b) => b == Brightness.light
    ? const {
        'yellow': Color(0xFFFFF3A3), 'green': Color(0xFFC8F2D2), 'blue': Color(0xFFCDE4FF),
        'pink': Color(0xFFFFD6E7), 'purple': Color(0xFFE6DBFF),
      }
    : const {
        'yellow': Color(0xFF5C4F00), 'green': Color(0xFF1E4D2B), 'blue': Color(0xFF1C3D66),
        'pink': Color(0xFF5E2240), 'purple': Color(0xFF3F2C6B),
      };

/// Text-colour tokens: stronger tones than highlights, readable in both themes.
Color planningV2TextTone(String token, Brightness b) {
  const light = {
    'yellow': Color(0xFF8A6D00), 'green': Color(0xFF1B7A3A), 'blue': Color(0xFF1D5FBF),
    'pink': Color(0xFFB0306A), 'purple': Color(0xFF6B3FC4),
  };
  const dark = {
    'yellow': Color(0xFFFFE066), 'green': Color(0xFF7FE0A0), 'blue': Color(0xFF8CC0FF),
    'pink': Color(0xFFFF9CC6), 'purple': Color(0xFFC7AEFF),
  };
  return (b == Brightness.light ? light : dark)[token] ?? (b == Brightness.light ? Colors.black : Colors.white);
}

const planningV2RouteName = 'planning_v2';

/// Every v2 screen is pushed with this name so an `inactive` failure can
/// pop the whole v2 stack in one call (spec §9: fail closed and leave).
Route<T> planningV2Route<T>(Widget page) =>
    MaterialPageRoute<T>(builder: (_) => page, settings: const RouteSettings(name: planningV2RouteName));

void showPlanningV2Error(BuildContext context, Object error) {
  final e = mapPlanningV2Error(error);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(planningV2ErrorMessage(e))));
  if (e is PlanningV2Unauthorized) {
    Navigator.of(context).popUntil((r) => r.settings.name != planningV2RouteName);
  }
}

String formatPlanningRange(DateTime? start, DateTime? end) {
  if (start == null) return 'Pick a date';
  final full = DateFormat.yMMMd();
  if (end == null || end == start) return full.format(start);
  if (start.year == end.year) return '${DateFormat.MMMd().format(start)} – ${DateFormat.MMMd().format(end)}, ${end.year}';
  return '${full.format(start)} – ${full.format(end)}';
}

class PlanningV2ErrorState extends StatelessWidget {
  const PlanningV2ErrorState({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final e = mapPlanningV2Error(error);
    final closed = e is PlanningV2Unauthorized;
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(closed ? Icons.lock_outline_rounded : Icons.cloud_off_rounded,
              size: Spacing.xxl, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: Spacing.md),
          Text(planningV2ErrorMessage(e), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: Spacing.md),
          if (closed)
            OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Close'))
          else
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

class PlanningV2EmptyState extends StatelessWidget {
  const PlanningV2EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: Spacing.pagePadding,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: Spacing.xxl, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: Spacing.md),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (action != null) ...[const SizedBox(height: Spacing.md), action!],
        ]),
      );
}

/// Not colour-only (spec §5): carries a semantics label.
class PlanningV2NewDot extends StatelessWidget {
  const PlanningV2NewDot({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'New from your partner',
        child: Container(
          width: Spacing.sm + Spacing.xs / 2,
          height: Spacing.sm + Spacing.xs / 2,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
        ),
      );
}
```

`lib/features/planning/v2/presentation/widgets/category_editor_sheet.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

import '../planning_v2_ui.dart';

typedef CategoryDraft = ({String name, String icon, String color});

Future<CategoryDraft?> showCategoryEditorSheet(BuildContext context, {CategoryDraft? initial}) =>
    showModalBottomSheet<CategoryDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditor(initial: initial),
    );

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({this.initial});
  final CategoryDraft? initial;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');
  late String _icon = widget.initial?.icon ?? 'star';
  late String _color = widget.initial?.color ?? 'teal';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg, right: Spacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.initial == null ? 'New category' : 'Edit category',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Spacing.md),
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'Moving house'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Spacing.sm),
        Text('Icon', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Spacing.sm),
        Wrap(spacing: Spacing.xs, runSpacing: Spacing.xs, children: [
          for (final k in planningV2IconKeys)
            Semantics(
              container: true,
              label: 'Icon $k',
              selected: k == _icon,
              button: true,
              excludeSemantics: true,
              child: IconButton.filledTonal(
                isSelected: k == _icon,
                onPressed: () => setState(() => _icon = k),
                icon: Icon(planningV2Icon(k)),
              ),
            ),
        ]),
        const SizedBox(height: Spacing.md),
        Text('Colour', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Spacing.sm),
        Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
          for (final c in planningV2ColorKeys)
            Semantics(
              container: true,
              label: 'Colour $c',
              selected: c == _color,
              button: true,
              excludeSemantics: true,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _color = c),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: planningV2Tone(context, c).container,
                      child: c == _color
                          ? Icon(Icons.check_rounded, color: planningV2Tone(context, c).onContainer)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: Spacing.lg),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop((name: _name.text.trim(), icon: _icon, color: _color))
              : null,
          child: const Text('Save'),
        ),
      ]),
    );
  }
}
```

`lib/features/planning/v2/presentation/screens/planning_v2_category_screen.dart` (temporary stub; Task 11 replaces the whole file):

```dart
import 'package:flutter/material.dart';

import '../../data/planning_v2_models.dart';

class PlanningV2CategoryScreen extends StatelessWidget {
  const PlanningV2CategoryScreen({super.key, required this.relationshipId, required this.category});
  final String relationshipId;
  final PlanningCategory category;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(category.name)));
}
```

`lib/features/planning/v2/presentation/screens/planning_v2_home_screen.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../widgets/category_editor_sheet.dart';
import 'planning_v2_category_screen.dart';

class PlanningV2HomeScreen extends ConsumerStatefulWidget {
  const PlanningV2HomeScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<PlanningV2HomeScreen> createState() => _PlanningV2HomeScreenState();
}

class _PlanningV2HomeScreenState extends ConsumerState<PlanningV2HomeScreen> {
  bool _showHidden = false;

  void _refresh() => ref.invalidate(planningV2HomeProvider(widget.relationshipId));

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    } finally {
      _refresh();
    }
  }

  Future<void> _create() async {
    final draft = await showCategoryEditorSheet(context);
    if (draft == null || !mounted) return;
    await _run(() => ref.read(planningV2RepositoryProvider).createCategory(
        id: const Uuid().v4(), relationshipId: widget.relationshipId,
        name: draft.name, icon: draft.icon, color: draft.color));
  }

  Future<void> _move(List<PlanningCategory> visible, int from, int to) async {
    final list = [...visible];
    final moving = list.removeAt(from);
    list.insert(to, moving);
    await _run(() => ref.read(planningV2RepositoryProvider)
        .moveCategory(moving.id, afterId: to == 0 ? null : list[to - 1].id));
  }

  void _open(PlanningCategory c) => Navigator.of(context).push(
      planningV2Route(PlanningV2CategoryScreen(relationshipId: widget.relationshipId, category: c)));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(planningV2HomeProvider(widget.relationshipId));
    return Scaffold(
      appBar: AppBar(title: const Text('Planning')),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PlanningV2ErrorState(error: e, onRetry: _refresh),
        data: (cats) {
          final visible = [for (final c in cats) if (!c.hidden) c];
          final hidden = [for (final c in cats) if (c.hidden) c];
          return RefreshIndicator(
            onRefresh: () => ref.refresh(planningV2HomeProvider(widget.relationshipId).future),
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              itemCount: visible.length,
              onReorder: (from, to) => _move(visible, from, to > from ? to - 1 : to),
              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                key: ValueKey(visible[i].id),
                index: i,
                child: _CategoryTile(
                  category: visible[i],
                  onOpen: () => _open(visible[i]),
                  onMoveUp: i == 0 ? null : () => _move(visible, i, i - 1),
                  onMoveDown: i == visible.length - 1 ? null : () => _move(visible, i, i + 1),
                  onHide: () => _run(() => ref.read(planningV2RepositoryProvider)
                      .setCategoryHidden(visible[i].id, hidden: true)),
                ),
              ),
              footer: Column(children: [
                if (hidden.isNotEmpty) ...[
                  ListTile(
                    minTileHeight: 56,
                    leading: Icon(_showHidden ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    title: Text('Hidden (${hidden.length})'),
                    onTap: () => setState(() => _showHidden = !_showHidden),
                  ),
                  if (_showHidden)
                    for (final c in hidden)
                      _CategoryTile(
                        category: c,
                        onOpen: () => _open(c),
                        onUnhide: () => _run(() =>
                            ref.read(planningV2RepositoryProvider).setCategoryHidden(c.id, hidden: false)),
                      ),
                ],
                ListTile(
                  minTileHeight: 56,
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('New category'),
                  onTap: _create,
                ),
                const SizedBox(height: Spacing.xl),
              ]),
            ),
          );
        },
      ),
    );
  }
}

enum _CategoryAction { open, up, down, hide, unhide }

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onOpen,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.onUnhide,
  });

  final PlanningCategory category;
  final VoidCallback onOpen;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final VoidCallback? onUnhide;

  @override
  Widget build(BuildContext context) {
    final tone = planningV2Tone(context, category.color);
    final n = category.entryCount;
    return ListTile(
      minTileHeight: 64,
      leading: CircleAvatar(
        backgroundColor: tone.container,
        child: Icon(planningV2Icon(category.icon), color: tone.onContainer),
      ),
      title: Text(category.name),
      subtitle: Text(n == 1 ? '1 plan' : '$n plans'),
      onTap: onOpen,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (category.hasNew) const PlanningV2NewDot(),
        PopupMenuButton<_CategoryAction>(
          tooltip: 'More for ${category.name}',
          onSelected: (a) => switch (a) {
            _CategoryAction.open => onOpen(),
            _CategoryAction.up => onMoveUp?.call(),
            _CategoryAction.down => onMoveDown?.call(),
            _CategoryAction.hide => onHide?.call(),
            _CategoryAction.unhide => onUnhide?.call(),
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: _CategoryAction.open, child: Text('Open')),
            if (onMoveUp != null) const PopupMenuItem(value: _CategoryAction.up, child: Text('Move up')),
            if (onMoveDown != null) const PopupMenuItem(value: _CategoryAction.down, child: Text('Move down')),
            if (onHide != null) const PopupMenuItem(value: _CategoryAction.hide, child: Text('Hide')),
            if (onUnhide != null) const PopupMenuItem(value: _CategoryAction.unhide, child: Text('Show again')),
          ],
        ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/planning/v2/ && flutter analyze lib/features/planning/v2 test/features/planning/v2`
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/planning/v2/presentation test/features/planning/v2
git commit -m "feat(planning-v2): category home with create, reorder, hide and new-activity dot

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Category screen and new-entry sheet

**Files:**
- Replace: `lib/features/planning/v2/presentation/screens/planning_v2_category_screen.dart` (the Task 10 stub)
- Create: `lib/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart` (minimal stub; Task 12 replaces it)
- Test: `test/features/planning/v2/planning_v2_category_screen_test.dart`

**Interfaces:**
- Consumes: Task 9 `planningV2EntriesProvider`, `planningV2RepositoryProvider`; Task 10 UI kit and `showCategoryEditorSheet`.
- Produces: `PlanningV2CategoryScreen({required String relationshipId, required PlanningCategory category})`; stub `PlanningV2EntryScreen({required String relationshipId, required String entryId})` (Task 12 keeps this exact constructor).

- [ ] **Step 1: Write the failing test**

`test/features/planning/v2/planning_v2_category_screen_test.dart`:

```dart
import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_category_screen.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

Map<String, dynamic> _summary(String id, {String? date, int done = 0, int total = 0}) => {
      'id': id, 'title': 'Trip $id', 'status': 'active', 'last_activity_at': '2026-10-12T09:00:00Z',
      'date_start': date, 'date_end': null, 'checklist_done': done, 'checklist_total': total,
    };

FakePlanningGateway _gateway({List<Map<String, dynamic>>? open}) => FakePlanningGateway({
      'mark_planning_category_seen': (_) => {'seen_at': '2026-10-12T09:00:00Z'},
      'list_planning_entries': (p) => p['p_group'] == 'open'
          ? {'entries': open ?? [_summary('1', date: '2026-03-03', done: 2, total: 5)], 'next_cursor': null}
          : {'entries': [_summary('9')], 'next_cursor': null},
      'get_planning_entry': (p) => fakeEntryDetailJson(id: p['p_id'] as String),
    });

PlanningCategory _cat({String? seedKey = 'trips'}) => PlanningCategory.fromJson(
    fakeCategoryJson(id: 'c1', seedKey: seedKey, name: seedKey == null ? 'Wedding' : 'Trips', entryCount: 3));

void main() {
  testWidgets('lists open entries with date and checklist progress; marks the category seen', (tester) async {
    final g = _gateway();
    await tester.pumpWidget(planningV2TestApp(g, PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    expect(find.text('Trip 1'), findsOneWidget);
    expect(find.text('Mar 3, 2026 · 2 of 5 done'), findsOneWidget);
    expect(g.callsTo('mark_planning_category_seen'), hasLength(1));
    expect(find.text('Trip 9'), findsNothing, reason: 'closed entries load only when expanded');
    await tester.tap(find.text('Done & archived'));
    await tester.pumpAndSettle();
    expect(find.text('Trip 9'), findsOneWidget);
  });

  testWidgets('empty state offers to start a plan', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(open: []),
        PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    expect(find.text('No plans here yet'), findsOneWidget);
  });

  testWidgets('new plan from the template creates it and opens it', (tester) async {
    final g = _gateway();
    g.handlers['create_planning_entry'] = (p) => fakeEntryDetailJson(id: p['p_id'] as String, title: 'Bali');
    await tester.pumpWidget(planningV2TestApp(g, PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bali');
    await tester.pump(); // enterText does not pump; Create enables on rebuild
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final call = g.callsTo('create_planning_entry').single;
    expect(call['p_title'], 'Bali');
    expect(call['p_use_template'], isTrue);
    expect(call['p_currency'], matches(RegExp(r'^[A-Z]{3}$')));
    expect(find.byType(PlanningV2EntryScreen), findsOneWidget);
  });

  testWidgets('Start blank sends use_template false', (tester) async {
    final g = _gateway();
    g.handlers['create_planning_entry'] = (p) => fakeEntryDetailJson(id: p['p_id'] as String);
    await tester.pumpWidget(planningV2TestApp(g, PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Weekend');
    await tester.pump();
    await tester.tap(find.text('Start blank'));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(g.callsTo('create_planning_entry').single['p_use_template'], isFalse);
  });

  testWidgets('starters cannot be deleted, only reset', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(), PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Category options'));
    await tester.pumpAndSettle();
    expect(find.text('Delete category'), findsNothing);
    expect(find.text('Reset template'), findsOneWidget);
  });

  testWidgets('custom categories confirm deletion with the entry count', (tester) async {
    final g = _gateway();
    g.handlers['delete_planning_category'] = (_) => {'deleted_entries': 3};
    await tester.pumpWidget(planningV2TestApp(g,
        PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat(seedKey: null))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Category options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete category'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Wedding and its 3 plans?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(g.callsTo('delete_planning_category'), hasLength(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/planning/v2/planning_v2_category_screen_test.dart`
Expected: FAIL — the stub has no list, menu or FAB.

- [ ] **Step 3: Implement**

`lib/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart` (temporary stub; Task 12 replaces the whole file, keeping this constructor):

```dart
import 'package:flutter/material.dart';

class PlanningV2EntryScreen extends StatelessWidget {
  const PlanningV2EntryScreen({super.key, required this.relationshipId, required this.entryId});
  final String relationshipId;
  final String entryId;

  @override
  Widget build(BuildContext context) => const Scaffold();
}
```

`lib/features/planning/v2/presentation/screens/planning_v2_category_screen.dart`:

```dart
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../widgets/category_editor_sheet.dart';
import 'planning_v2_entry_screen.dart';

/// ISO 4217 code for the device locale; USD when the locale has none.
String _deviceCurrency() {
  final code = NumberFormat.simpleCurrency().currencyName ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : 'USD';
}

enum _Menu { editTemplate, edit, hide, reset, delete }

class PlanningV2CategoryScreen extends ConsumerStatefulWidget {
  const PlanningV2CategoryScreen({super.key, required this.relationshipId, required this.category});
  final String relationshipId;
  final PlanningCategory category;

  @override
  ConsumerState<PlanningV2CategoryScreen> createState() => _PlanningV2CategoryScreenState();
}

class _PlanningV2CategoryScreenState extends ConsumerState<PlanningV2CategoryScreen> {
  late PlanningCategory _category = widget.category;
  bool _showClosed = false;

  PlanningEntriesArgs get _open =>
      (relationshipId: widget.relationshipId, categoryId: _category.id, group: 'open');
  PlanningEntriesArgs get _closed =>
      (relationshipId: widget.relationshipId, categoryId: _category.id, group: 'closed');

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: a failed "seen" write only leaves the dot showing.
    unawaited(ref.read(planningV2RepositoryProvider).markCategorySeen(_category.id).catchError((_) {}));
  }

  void _openEntry(String entryId) => Navigator.of(context).push(
      planningV2Route(PlanningV2EntryScreen(relationshipId: widget.relationshipId, entryId: entryId)));

  Future<void> _newEntry() async {
    final draft = await showModalBottomSheet<({String title, bool useTemplate})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewEntrySheet(),
    );
    if (draft == null || !mounted) return;
    try {
      final detail = await ref.read(planningV2RepositoryProvider).createEntry(
          id: const Uuid().v4(), categoryId: _category.id, title: draft.title,
          useTemplate: draft.useTemplate, currency: _deviceCurrency());
      ref.invalidate(planningV2EntriesProvider(_open));
      if (mounted) _openEntry(detail.entry.id);
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    }
  }

  Future<void> _menu(_Menu action) async {
    final repo = ref.read(planningV2RepositoryProvider);
    try {
      switch (action) {
        case _Menu.editTemplate:
          if (_category.templateEntryId != null) _openEntry(_category.templateEntryId!);
        case _Menu.edit:
          final d = await showCategoryEditorSheet(context,
              initial: (name: _category.name, icon: _category.icon, color: _category.color));
          if (d == null) return;
          final updated = await repo.updateCategory(id: _category.id, name: d.name, icon: d.icon, color: d.color);
          setState(() => _category = _category.copyWith(name: updated.name, icon: updated.icon, color: updated.color));
        case _Menu.hide:
          await repo.setCategoryHidden(_category.id, hidden: !_category.hidden);
          setState(() => _category = _category.copyWith(hidden: !_category.hidden));
        case _Menu.reset:
          final ok = await _confirm('Reset the template?',
              'New plans will start from Attune\'s version. Plans you already made are not changed.', 'Reset');
          if (ok) await repo.resetTemplate(_category.id);
        case _Menu.delete:
          final n = _category.entryCount;
          final ok = await _confirm('Delete ${_category.name} and its $n ${n == 1 ? 'plan' : 'plans'}?',
              'You can ask support to restore it within 30 days.', 'Delete');
          if (!ok) return;
          await repo.deleteCategory(_category.id);
          if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    } finally {
      ref.invalidate(planningV2HomeProvider(widget.relationshipId));
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(planningV2EntriesProvider(_open));
    return Scaffold(
      appBar: AppBar(
        title: Text(_category.name),
        actions: [
          PopupMenuButton<_Menu>(
            tooltip: 'Category options',
            onSelected: _menu,
            itemBuilder: (_) => [
              if (_category.templateEntryId != null)
                const PopupMenuItem(value: _Menu.editTemplate, child: Text('Edit template')),
              const PopupMenuItem(value: _Menu.edit, child: Text('Rename or restyle')),
              PopupMenuItem(value: _Menu.hide, child: Text(_category.hidden ? 'Show on Planning' : 'Hide')),
              if (_category.isStarter) const PopupMenuItem(value: _Menu.reset, child: Text('Reset template')),
              if (!_category.isStarter) const PopupMenuItem(value: _Menu.delete, child: Text('Delete category')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newEntry,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New plan'),
      ),
      body: open.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PlanningV2ErrorState(error: e, onRetry: () => ref.invalidate(planningV2EntriesProvider(_open))),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(planningV2EntriesProvider(_open).future),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400) {
                unawaited(ref.read(planningV2EntriesProvider(_open).notifier).loadMore());
              }
              return false;
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: Spacing.xxl * 2),
              children: [
                if (s.entries.isEmpty)
                  PlanningV2EmptyState(
                    icon: planningV2Icon(_category.icon),
                    message: 'No plans here yet',
                    action: OutlinedButton(onPressed: _newEntry, child: const Text('Start one')),
                  ),
                for (final e in s.entries) _EntryTile(entry: e, onTap: () => _openEntry(e.id)),
                if (s.loadingMore) const Padding(padding: Spacing.allMd, child: Center(child: CircularProgressIndicator())),
                if (s.loadMoreFailed)
                  TextButton(
                    onPressed: () => ref.read(planningV2EntriesProvider(_open).notifier).loadMore(),
                    child: const Text('Could not load more. Try again'),
                  ),
                ListTile(
                  minTileHeight: 56,
                  leading: Icon(_showClosed ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                  title: const Text('Done & archived'),
                  onTap: () => setState(() => _showClosed = !_showClosed),
                ),
                if (_showClosed) _ClosedEntries(args: _closed, onOpen: _openEntry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClosedEntries extends ConsumerWidget {
  const _ClosedEntries({required this.args, required this.onOpen});
  final PlanningEntriesArgs args;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(planningV2EntriesProvider(args)).when(
        skipLoadingOnReload: true,
        loading: () => const Padding(padding: Spacing.allMd, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => PlanningV2ErrorState(error: e, onRetry: () => ref.invalidate(planningV2EntriesProvider(args))),
        data: (s) => Column(children: [
          if (s.entries.isEmpty) const Padding(padding: Spacing.allMd, child: Text('Nothing finished yet')),
          for (final e in s.entries) _EntryTile(entry: e, onTap: () => onOpen(e.id)),
        ]),
      );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});
  final PlanningEntrySummary entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (entry.dateStart != null) formatPlanningRange(entry.dateStart, entry.dateEnd),
      if (entry.checklistTotal > 0) '${entry.checklistDone} of ${entry.checklistTotal} done',
    ];
    return ListTile(
      minTileHeight: 64,
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: parts.isEmpty ? null : Text(parts.join(' · ')),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _NewEntrySheet extends StatefulWidget {
  const _NewEntrySheet();

  @override
  State<_NewEntrySheet> createState() => _NewEntrySheetState();
}

class _NewEntrySheetState extends State<_NewEntrySheet> {
  final _title = TextEditingController();
  bool _useTemplate = true;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          left: Spacing.lg, right: Spacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('New plan', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _title,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Spacing.sm),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Use template'), icon: Icon(Icons.auto_awesome_rounded)),
              ButtonSegment(value: false, label: Text('Start blank'), icon: Icon(Icons.note_add_outlined)),
            ],
            selected: {_useTemplate},
            onSelectionChanged: (s) => setState(() => _useTemplate = s.first),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _title.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop((title: _title.text.trim(), useTemplate: _useTemplate)),
            child: const Text('Create'),
          ),
        ]),
      );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/planning/v2/ && flutter analyze lib/features/planning/v2 test/features/planning/v2`
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/planning/v2/presentation test/features/planning/v2
git commit -m "feat(planning-v2): category screen with paginated plans and template-or-blank creation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Entry screen, checklist and date blocks, tool tray

**Files:**
- Replace: `lib/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart` (the Task 11 stub; same constructor)
- Create: `lib/features/planning/v2/presentation/widgets/block_tool_tray.dart`
- Create: `lib/features/planning/v2/presentation/widgets/checklist_block_view.dart`
- Create: `lib/features/planning/v2/presentation/widgets/date_block_view.dart`
- Create: `lib/features/planning/v2/presentation/widgets/text_block_view.dart` (read-only placeholder; Task 13 replaces it with the Quill renderer)
- Test: `test/features/planning/v2/planning_v2_entry_screen_test.dart`

**Interfaces:**
- Consumes: Task 9 `planningV2EntryProvider` / `PlanningEntryController`, `planningV2OutboxProvider`; Task 10 UI kit.
- Produces: `PlanningV2EntryScreen`; `Future<PlanningBlockType?> showBlockToolTray(BuildContext)`; `ChecklistBlockView({required PlanningEntryArgs args, required PlanningBlock block, required List<PlanningMember> members})`; `DateBlockView({required PlanningEntryArgs args, required PlanningBlock block})`; `TextBlockView({required PlanningEntryArgs args, required PlanningBlock block})`.

- [ ] **Step 1: Write the failing test**

`test/features/planning/v2/planning_v2_entry_screen_test.dart`:

```dart
import 'package:attune/features/planning/v2/domain/planning_outbox.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

FakePlanningGateway _gateway({bool template = false, String extraType = 'date'}) => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(isTemplate: template, blocks: [
            fakeBlockJson(id: 'b1', payload: {'title': 'Shopping list'}, items: [
              fakeItemJson(id: 'i1', text: 'Tomatoes', section: 'Produce', assignedTo: 'u-b'),
              fakeItemJson(id: 'i2', text: 'Milk', section: 'Dairy', checkedAt: '2026-10-12T09:00:00Z'),
            ]),
            fakeBlockJson(id: 'b2', type: extraType, sortKey: 'k', payload: {'title': 'Shop day'}, dateStart: '2026-10-17'),
          ]),
    });

const _screen = PlanningV2EntryScreen(relationshipId: 'r1', entryId: 'e1');

void main() {
  testWidgets('hero shows title and facts; blocks render in order; sections grouped', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(planningV2TestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(find.text('Saturday shop'), findsOneWidget);
    expect(find.text('1 of 2 done'), findsOneWidget);
    expect(find.text('Oct 17, 2026'), findsWidgets);
    expect(find.text('Produce'), findsOneWidget);
    expect(find.text('Tomatoes'), findsOneWidget);
    expect(find.text('Milk'), findsNothing, reason: 'ticked items are folded');
    expect(find.text('1 done'), findsOneWidget);
    expect(find.bySemanticsLabel('Assigned to Kofi'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('ticking calls the RPC with an op id', (tester) async {
    final semantics = tester.ensureSemantics();
    final g = _gateway();
    g.handlers['set_planning_block_item_checked'] =
        (p) => fakeItemJson(id: 'i1', text: 'Tomatoes', section: 'Produce', checkedAt: '2026-10-12T10:00:00Z', version: 2);
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Tomatoes, not done'));
    await tester.pumpAndSettle();
    final call = g.callsTo('set_planning_block_item_checked').single;
    expect(call['p_checked'], isTrue);
    expect(call['p_op_id'], isA<String>());
    expect(find.text('2 done'), findsOneWidget);
    semantics.dispose(); // must be disposed inside the test body
  });

  testWidgets('an offline tick shows the waiting-to-sync chip', (tester) async {
    final semantics = tester.ensureSemantics();
    final g = _gateway();
    g.handlers['set_planning_block_item_checked'] = (_) => throw Exception('offline');
    final store = MemoryOutboxStore();
    await tester.pumpWidget(planningV2TestApp(g, _screen, store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Tomatoes, not done'));
    await tester.pumpAndSettle();
    expect(find.text('1 change waiting to sync'), findsOneWidget);
    expect(store.raw, hasLength(1));
    semantics.dispose(); // must be disposed inside the test body
  });

  testWidgets('adding an item from the field', (tester) async {
    final g = _gateway();
    g.handlers['add_planning_block_item'] = (p) => fakeItemJson(id: p['p_id'] as String, text: 'Eggs');
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Add item'), 'Eggs');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(g.callsTo('add_planning_block_item').single['p_text'], 'Eggs');
    expect(find.text('Eggs'), findsOneWidget);
  });

  testWidgets('swipe deletes a block with Undo that restores it', (tester) async {
    final g = _gateway();
    g.handlers['delete_planning_block'] = (_) => {'deleted': true};
    g.handlers['restore_planning_block'] = (_) => fakeBlockJson(id: 'b2', type: 'date', payload: {'title': 'Shop day'}, dateStart: '2026-10-17');
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('block-b2')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Shop day'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(g.callsTo('restore_planning_block'), hasLength(1));
    expect(find.text('Shop day'), findsOneWidget);
  });

  testWidgets('Move down from the block menu (non-drag reorder for accessibility)', (tester) async {
    final g = _gateway();
    g.handlers['move_planning_block'] = (_) => fakeBlockJson(id: 'b1', sortKey: 'z');
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Shopping list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(g.callsTo('move_planning_block').single['p_after_id'], 'b2');
  });

  testWidgets('tool tray adds a checklist block at the end', (tester) async {
    final g = _gateway();
    g.handlers['add_planning_block'] = (p) => fakeBlockJson(id: p['p_id'] as String, payload: {}, sortKey: 'z');
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add a block'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist'));
    await tester.pumpAndSettle();
    final call = g.callsTo('add_planning_block').single;
    expect(call['p_block_type'], 'checklist');
    expect(call['p_after_id'], 'b2');
  });

  testWidgets('editing an item sets a due date (spec §6.2; Timeline reads it in P2)', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block_item'] = (p) =>
        {...fakeItemJson(id: 'i1', text: 'Tomatoes', section: 'Produce', version: 2), 'due_date': p['p_due_date']};
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomatoes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No due date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final ymd = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(g.callsTo('update_planning_block_item').single['p_due_date'], ymd);
    expect(find.textContaining('Due '), findsOneWidget);
  });

  testWidgets('text at 200% scale renders without overflow (spec §5)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(planningV2TestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Tomatoes'), findsOneWidget);
  });

  testWidgets('templates show the template banner', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(template: true), _screen));
    await tester.pumpAndSettle();
    expect(find.text('Template. New plans start from this.'), findsOneWidget);
  });

  testWidgets('a block type from a newer server renders a placeholder', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(extraType: 'budget'), _screen));
    await tester.pumpAndSettle();
    expect(find.text('This block needs a newer version of Attune.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/planning/v2/planning_v2_entry_screen_test.dart`
Expected: FAIL — the stub renders nothing.

- [ ] **Step 3: Implement**

`lib/features/planning/v2/presentation/widgets/block_tool_tray.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

import '../../data/planning_v2_models.dart';

/// P1 offers only the blocks that exist; P3/P4 add theirs here.
const _tools = <(PlanningBlockType, IconData, String)>[
  (PlanningBlockType.text, Icons.notes_rounded, 'Text'),
  (PlanningBlockType.checklist, Icons.checklist_rounded, 'Checklist'),
  (PlanningBlockType.date, Icons.event_rounded, 'Date'),
];

Future<PlanningBlockType?> showBlockToolTray(BuildContext context) => showModalBottomSheet<PlanningBlockType>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: Spacing.allMd,
          child: Wrap(spacing: Spacing.md, runSpacing: Spacing.md, children: [
            for (final (type, icon, label) in _tools)
              SizedBox(
                width: 96,
                child: InkWell(
                  borderRadius: BorderRadiusTokens.mdAll,
                  onTap: () => Navigator.of(c).pop(type),
                  child: Padding(
                    padding: Spacing.allSm,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircleAvatar(radius: 24, child: Icon(icon)),
                      const SizedBox(height: Spacing.xs),
                      Text(label),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
```

`lib/features/planning/v2/presentation/widgets/text_block_view.dart` (placeholder; Task 13 replaces it):

```dart
import 'package:flutter/material.dart';

import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';

class TextBlockView extends StatelessWidget {
  const TextBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  @override
  Widget build(BuildContext context) {
    final t = block.plainText ?? '';
    return Text(t.isEmpty ? 'Tap to write' : t);
  }
}
```

`lib/features/planning/v2/presentation/widgets/date_block_view.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_v2_error.dart';
import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';

class DateBlockView extends ConsumerWidget {
  const DateBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  Future<void> _set(BuildContext context, WidgetRef ref, DateTime? start, DateTime? end) async {
    try {
      await ref.read(planningV2EntryProvider(args).notifier).setDate(block, start, end);
    } on PlanningV2StaleVersion {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your partner just changed this date. Showing theirs.')));
      }
    } catch (e) {
      if (context.mounted) showPlanningV2Error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final first = DateTime(now.year - 5);
    final last = DateTime(now.year + 10);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(block.title ?? 'Date', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Spacing.xs),
      Text(formatPlanningRange(block.dateStart, block.dateEnd), style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: Spacing.sm),
      Wrap(spacing: Spacing.sm, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.today_rounded),
          label: const Text('One day'),
          onPressed: () async {
            final d = await showDatePicker(
                context: context, firstDate: first, lastDate: last, initialDate: block.dateStart ?? now);
            if (d != null && context.mounted) await _set(context, ref, d, null);
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_rounded),
          label: const Text('Range'),
          onPressed: () async {
            final r = await showDateRangePicker(context: context, firstDate: first, lastDate: last);
            if (r != null && context.mounted) {
              await _set(context, ref, r.start, r.end == r.start ? null : r.end);
            }
          },
        ),
        if (block.dateStart != null)
          TextButton(onPressed: () => _set(context, ref, null, null), child: const Text('Clear')),
      ]),
    ]);
  }
}
```

`lib/features/planning/v2/presentation/widgets/checklist_block_view.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_v2_error.dart';
import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';

class ChecklistBlockView extends ConsumerStatefulWidget {
  const ChecklistBlockView({super.key, required this.args, required this.block, required this.members});
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final List<PlanningMember> members;

  @override
  ConsumerState<ChecklistBlockView> createState() => _ChecklistBlockViewState();
}

class _ChecklistBlockViewState extends ConsumerState<ChecklistBlockView> {
  final _add = TextEditingController();
  final _addFocus = FocusNode();
  bool _showDone = false;

  PlanningEntryController get _ctl => ref.read(planningV2EntryProvider(widget.args).notifier);

  @override
  void dispose() {
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    }
  }

  Future<void> _submit() async {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    _add.clear();
    _addFocus.requestFocus();
    await _guard(() => _ctl.addItem(widget.block.id, text));
  }

  Future<void> _delete(PlanningItem item) async {
    final index = widget.block.items.indexOf(item);
    await _guard(() => _ctl.deleteItem(widget.block.id, item.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Removed ${item.text}'),
      action: SnackBarAction(
          label: 'Undo', onPressed: () => _guard(() => _ctl.restoreItem(widget.block.id, item.id, index: index))),
    ));
  }

  Future<void> _edit(PlanningItem item) async {
    final result = await showModalBottomSheet<({String text, String? section, String? assignedTo, DateTime? dueDate})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemEditor(item: item, members: widget.members),
    );
    if (result == null) return;
    try {
      await _ctl.updateItem(widget.block.id, item,
          text: result.text, section: result.section, assignedTo: result.assignedTo, dueDate: result.dueDate);
    } on PlanningV2StaleVersion {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Your partner just changed this item. Showing theirs.')));
      }
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    }
  }

  Widget _row(PlanningItem item) {
    final assignee = widget.members.where((m) => m.id == item.assignedTo).firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('item-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: Spacing.horizontalMd,
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => _delete(item),
      child: Row(children: [
        Semantics(
          container: true,
          label: '${item.text}, ${item.isChecked ? 'done' : 'not done'}',
          excludeSemantics: true,
          checked: item.isChecked,
          child: Checkbox(
            value: item.isChecked,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onChanged: (v) => _guard(() => _ctl.setChecked(widget.block.id, item, v ?? false)),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _edit(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.smMd),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  item.text,
                  style: item.isChecked
                      ? TextStyle(decoration: TextDecoration.lineThrough, color: scheme.outline)
                      : null,
                ),
                if (item.dueDate != null)
                  Text('Due ${formatPlanningRange(item.dueDate, null)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline)),
              ]),
            ),
          ),
        ),
        if (assignee != null)
          Semantics(
            container: true,
            label: 'Assigned to ${assignee.displayName}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: CircleAvatar(radius: 12, child: Text(assignee.initial, style: const TextStyle(fontSize: 12))),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = [for (final i in widget.block.items) if (!i.isChecked) i];
    final done = [for (final i in widget.block.items) if (i.isChecked) i];
    final rows = <Widget>[];
    String? section;
    for (final item in open) {
      if (item.section != null && item.section != section) {
        rows.add(Padding(
          padding: const EdgeInsets.only(top: Spacing.sm, left: Spacing.xs),
          child: Text(item.section!, style: Theme.of(context).textTheme.labelLarge),
        ));
      }
      section = item.section;
      rows.add(_row(item));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.block.title ?? 'Checklist', style: Theme.of(context).textTheme.titleMedium),
      ...rows,
      TextField(
        controller: _add,
        focusNode: _addFocus,
        maxLength: 500,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          hintText: 'Add item', prefixIcon: Icon(Icons.add_rounded), counterText: '', border: InputBorder.none),
        onSubmitted: (_) => _submit(),
      ),
      if (done.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: Icon(_showDone ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text('${done.length} done'),
            onPressed: () => setState(() => _showDone = !_showDone),
          ),
        ),
      if (_showDone) ...[for (final i in done) _row(i)],
    ]);
  }
}

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.item, required this.members});
  final PlanningItem item;
  final List<PlanningMember> members;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _text = TextEditingController(text: widget.item.text);
  late final _section = TextEditingController(text: widget.item.section ?? '');
  late String? _assignee = widget.item.assignedTo;
  late DateTime? _due = widget.item.dueDate;

  @override
  void dispose() {
    _text.dispose();
    _section.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
            left: Spacing.lg, right: Spacing.lg, bottom: MediaQuery.viewInsetsOf(context).bottom + Spacing.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _text,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Item'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(controller: _section, maxLength: 40, decoration: const InputDecoration(labelText: 'Section (optional)')),
          const SizedBox(height: Spacing.sm),
          Text("Who's on it", style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Spacing.xs),
          SegmentedButton<String>(
            segments: [
              for (final m in widget.members) ButtonSegment(value: m.id, label: Text(m.displayName)),
              const ButtonSegment(value: '', label: Text('Either')),
            ],
            selected: {_assignee ?? ''},
            onSelectionChanged: (s) => setState(() => _assignee = s.first.isEmpty ? null : s.first),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            leading: const Icon(Icons.event_rounded),
            title: Text(_due == null ? 'No due date' : 'Due ${formatPlanningRange(_due, null)}'),
            trailing: _due == null
                ? null
                : IconButton(
                    tooltip: 'Clear due date',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _due = null),
                  ),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                  context: context, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10),
                  initialDate: _due ?? now);
              if (d != null) setState(() => _due = d);
            },
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _text.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop((
                      text: _text.text.trim(),
                      section: _section.text.trim().isEmpty ? null : _section.text.trim(),
                      assignedTo: _assignee,
                      dueDate: _due,
                    )),
            child: const Text('Save'),
          ),
        ]),
      );
}
```

`lib/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../widgets/block_tool_tray.dart';
import '../widgets/checklist_block_view.dart';
import '../widgets/date_block_view.dart';
import '../widgets/text_block_view.dart';

enum _EntryMenu { rename, done, reopen, next }

enum _BlockMenu { up, down, delete }

class PlanningV2EntryScreen extends ConsumerWidget {
  const PlanningV2EntryScreen({super.key, required this.relationshipId, required this.entryId});
  final String relationshipId;
  final String entryId;

  PlanningEntryArgs get _args => (relationshipId: relationshipId, entryId: entryId);

  Future<void> _guard(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) showPlanningV2Error(context, e);
    }
  }

  Future<String?> _askTitle(BuildContext context, String current) {
    final c = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: c, autofocus: true, maxLength: 120),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    ).whenComplete(c.dispose);
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, PlanningEntryDetail d, _EntryMenu m) async {
    final ctl = ref.read(planningV2EntryProvider(_args).notifier);
    switch (m) {
      case _EntryMenu.rename:
        final t = await _askTitle(context, d.entry.title);
        if (t != null && t.isNotEmpty && context.mounted) await _guard(context, () => ctl.rename(t));
      case _EntryMenu.done:
        await _guard(context, () => ctl.setStatus('done'));
      case _EntryMenu.reopen:
        await _guard(context, () => ctl.setStatus('active'));
      case _EntryMenu.next:
        await _guard(context, () async {
          final copy = await ref.read(planningV2RepositoryProvider)
              .duplicateEntry(sourceId: entryId, newId: const Uuid().v4(), title: d.entry.title);
          if (context.mounted) {
            await Navigator.of(context).pushReplacement(planningV2Route(
                PlanningV2EntryScreen(relationshipId: relationshipId, entryId: copy.entry.id)));
          }
        });
    }
  }

  Future<void> _deleteBlock(BuildContext context, WidgetRef ref, PlanningEntryDetail d, PlanningBlock b) async {
    final index = d.blocks.indexOf(b);
    final ctl = ref.read(planningV2EntryProvider(_args).notifier);
    await _guard(context, () => ctl.deleteBlock(b.id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Block removed'),
      action: SnackBarAction(label: 'Undo', onPressed: () => _guard(context, () => ctl.restoreBlock(b.id, index: index))),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(planningV2EntryProvider(_args));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.entry.categoryName ?? ''),
        actions: [
          if (async.valueOrNull case final d?)
            PopupMenuButton<_EntryMenu>(
              tooltip: 'Plan options',
              onSelected: (m) => _menu(context, ref, d, m),
              itemBuilder: (_) => [
                const PopupMenuItem(value: _EntryMenu.rename, child: Text('Rename')),
                if (!d.entry.isTemplate && d.entry.status == 'active')
                  const PopupMenuItem(value: _EntryMenu.done, child: Text('Mark done')),
                if (!d.entry.isTemplate && d.entry.status != 'active')
                  const PopupMenuItem(value: _EntryMenu.reopen, child: Text('Reopen')),
                if (!d.entry.isTemplate) const PopupMenuItem(value: _EntryMenu.next, child: Text('Start next one')),
              ],
            ),
        ],
      ),
      floatingActionButton: async.hasValue
          ? FloatingActionButton(
              tooltip: 'Add a block',
              onPressed: () async {
                final type = await showBlockToolTray(context);
                if (type != null && context.mounted) {
                  await _guard(context, () => ref.read(planningV2EntryProvider(_args).notifier).addBlock(type));
                }
              },
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PlanningV2ErrorState(error: e, onRetry: () => ref.invalidate(planningV2EntryProvider(_args))),
        data: (d) => RefreshIndicator(
          onRefresh: () => ref.refresh(planningV2EntryProvider(_args).future),
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: Spacing.horizontalMd,
            header: _Hero(detail: d, args: _args),
            footer: const SizedBox(height: Spacing.xxl * 2),
            itemCount: d.blocks.length,
            onReorder: (from, to) => _guard(context,
                () => ref.read(planningV2EntryProvider(_args).notifier).moveBlock(d.blocks[from].id, to > from ? to - 1 : to)),
            itemBuilder: (context, i) {
              final b = d.blocks[i];
              final name = b.title ?? switch (b.type) {
                PlanningBlockType.text => 'Text',
                PlanningBlockType.checklist => 'Checklist',
                PlanningBlockType.date => 'Date',
                PlanningBlockType.unsupported => 'Block',
              };
              final ctl = ref.read(planningV2EntryProvider(_args).notifier);
              return ReorderableDelayedDragStartListener(
                key: ValueKey('block-${b.id}'),
                index: i,
                child: Dismissible(
                  key: ValueKey('dismiss-${b.id}'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _deleteBlock(context, ref, d, b),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: Spacing.horizontalMd,
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: Spacing.smMd),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, 0, Spacing.sm),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: switch (b.type) {
                            PlanningBlockType.text => TextBlockView(args: _args, block: b),
                            PlanningBlockType.checklist => ChecklistBlockView(args: _args, block: b, members: d.members),
                            PlanningBlockType.date => DateBlockView(args: _args, block: b),
                            PlanningBlockType.unsupported => const Padding(
                                padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                                child: Text('This block needs a newer version of Attune.'),
                              ),
                          },
                        ),
                        PopupMenuButton<_BlockMenu>(
                          tooltip: 'Options for $name',
                          onSelected: (m) => switch (m) {
                            _BlockMenu.up => _guard(context, () => ctl.moveBlock(b.id, i - 1)),
                            _BlockMenu.down => _guard(context, () => ctl.moveBlock(b.id, i + 1)),
                            _BlockMenu.delete => _deleteBlock(context, ref, d, b),
                          },
                          itemBuilder: (_) => [
                            if (i > 0) const PopupMenuItem(value: _BlockMenu.up, child: Text('Move up')),
                            if (i < d.blocks.length - 1) const PopupMenuItem(value: _BlockMenu.down, child: Text('Move down')),
                            const PopupMenuItem(value: _BlockMenu.delete, child: Text('Delete')),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.detail, required this.args});
  final PlanningEntryDetail detail;
  final PlanningEntryArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = detail.blocks.where((b) => b.type == PlanningBlockType.date && b.dateStart != null).firstOrNull;
    final items = [for (final b in detail.blocks) if (b.type == PlanningBlockType.checklist) ...b.items];
    final done = items.where((i) => i.isChecked).length;
    final outbox = ref.watch(planningV2OutboxProvider);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (detail.entry.isTemplate)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: Spacing.smMd),
            padding: Spacing.allSm,
            decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadiusTokens.smAll),
            child: Text('Template. New plans start from this.', style: TextStyle(color: scheme.onTertiaryContainer)),
          ),
        Text(detail.entry.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: Spacing.sm),
        Wrap(spacing: Spacing.sm, runSpacing: Spacing.xs, children: [
          if (date != null)
            Chip(avatar: const Icon(Icons.event_rounded, size: 18), label: Text(formatPlanningRange(date.dateStart, date.dateEnd))),
          if (items.isNotEmpty)
            Chip(avatar: const Icon(Icons.checklist_rounded, size: 18), label: Text('$done of ${items.length} done')),
          ValueListenableBuilder<int>(
            valueListenable: outbox.pendingCount,
            builder: (_, n, __) => n == 0
                ? const SizedBox.shrink()
                : Chip(
                    avatar: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(n == 1 ? '1 change waiting to sync' : '$n changes waiting to sync'),
                  ),
          ),
        ]),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/planning/v2/ && flutter analyze lib/features/planning/v2 test/features/planning/v2`
Expected: all PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/planning/v2/presentation test/features/planning/v2
git commit -m "feat(planning-v2): entry page with checklist and date blocks, tray, undo and reorder

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Rich-text editor, read view and conflict sheet

**Files:**
- Replace: `lib/features/planning/v2/presentation/widgets/text_block_view.dart` (Task 12 placeholder; same constructor)
- Create: `lib/features/planning/v2/presentation/screens/planning_v2_text_editor_screen.dart`
- Create: `lib/features/planning/v2/presentation/widgets/conflict_sheet.dart`
- Create: `lib/features/planning/v2/presentation/widgets/planning_quill.dart`
- Test: `test/features/planning/v2/planning_v2_text_editor_test.dart`

**Interfaces:**
- Consumes: Task 8 `sanitizeDelta`, `deltaPlainText`; Task 9 `saveText` → `TextSaved` / `TextConflict` / `TextGone`; Task 10 palettes.
- Produces: `PlanningV2TextEditorScreen({required PlanningEntryArgs args, required PlanningBlock block})` whose state class `PlanningV2TextEditorScreenState` exposes `@visibleForTesting QuillController get controller`; `enum ConflictChoice { keepMine, useTheirs, copyMine }`; `Future<ConflictChoice?> showConflictSheet(BuildContext, {required String theirs})`; `Widget planningQuillScope(Widget child)`; `QuillEditorConfig planningQuillEditorConfig(BuildContext, {String? placeholder})`.

flutter_quill 11.5.0 facts this task relies on (verified against the package source):
- `QuillEditor.basic({required QuillController controller, QuillEditorConfig config, FocusNode? focusNode, ScrollController? scrollController})`.
- `QuillController({required Document document, required TextSelection selection, bool readOnly = false})`; `readOnly` is a mutable field.
- `QuillEditorConfig(customStyles: DefaultStyles(palette: Map<String, Color>), customStyleBuilder: TextStyle Function(Attribute))`; Quill resolves `background`/`color` values through `palette` first, so token names render as theme colours.
- `QuillToolbarCustomButtonOptions` has `icon` and `onPressed` only (no tooltip), so tooltips wrap the icon.
- `FlutterQuillLocalizations.delegate` is required by Quill widgets. It is provided with `Localizations.override` **around the Quill widgets only**, so `lib/app/app.dart` is untouched.

- [ ] **Step 1: Write the failing test**

`test/features/planning/v2/planning_v2_text_editor_test.dart`:

```dart
import 'dart:convert';

import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_text_editor_screen.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

Map<String, dynamic> _textBlock({String text = 'Hello', int version = 1}) => fakeBlockJson(
    id: 'b1', type: 'text', plainText: text, version: version, payload: {
      'delta': [{'insert': '$text\n'}]
    });

FakePlanningGateway _gateway() =>
    FakePlanningGateway({'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [_textBlock()])});

Future<void> _openEditor(WidgetTester tester, FakePlanningGateway g) async {
  await tester.pumpWidget(planningV2TestApp(g, const PlanningV2EntryScreen(relationshipId: 'r1', entryId: 'e1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Edit text'));
  await tester.pumpAndSettle();
}

QuillController _controller(WidgetTester tester) =>
    tester.state<PlanningV2TextEditorScreenState>(find.byType(PlanningV2TextEditorScreen)).controller;

void main() {
  testWidgets('read view renders the rich text; Edit opens the editor with it', (tester) async {
    await _openEditor(tester, _gateway());
    expect(find.byType(PlanningV2TextEditorScreen), findsOneWidget);
    expect(_controller(tester).document.toPlainText(), 'Hello\n');
  });

  testWidgets('save sends the version and a sanitized delta, then returns', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (p) => _textBlock(text: 'Hello there', version: 2);
    await _openEditor(tester, g);
    _controller(tester).document.insert(5, ' there');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final call = g.callsTo('update_planning_block').single;
    expect(call['p_version'], 1);
    expect((call['p_payload'] as Map)['delta'], [{'insert': 'Hello there\n'}]);
    expect(find.byType(PlanningV2TextEditorScreen), findsNothing);
  });

  testWidgets('pasted foreign attributes are stripped before save and the user is told (Review Focus 4)', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (p) => _textBlock(version: 2);
    await _openEditor(tester, g);
    _controller(tester).formatText(0, 5, Attribute.fromKeyValue('size', 'large'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    // findsWidgets: during the pop transition both scaffolds show the snackbar.
    expect(find.text('Some formatting is not supported here and was removed.'), findsWidgets);
    await tester.pumpAndSettle();
    final delta = jsonEncode((g.callsTo('update_planning_block').single['p_payload'] as Map)['delta']);
    expect(delta, isNot(contains('size')));
  });

  testWidgets('conflict: Use theirs loads their text; Keep mine re-saves on their version', (tester) async {
    final g = _gateway();
    var attempt = 0;
    g.handlers['update_planning_block'] = (p) {
      attempt++;
      if (attempt == 1) {
        throw PostgrestException(
            message: 'planning:stale_version', code: 'P0001',
            hint: jsonEncode({'current': _textBlock(text: 'Kofi wrote this', version: 4)}));
      }
      return _textBlock(text: 'Mine', version: 5);
    };
    await _openEditor(tester, g);
    _controller(tester).document.insert(0, 'Mine ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Your partner just changed this'), findsOneWidget);
    expect(find.text('Kofi wrote this'), findsOneWidget);
    await tester.tap(find.text('Keep mine'));
    await tester.pumpAndSettle();
    expect(g.callsTo('update_planning_block').last['p_version'], 4);
    expect(find.byType(PlanningV2TextEditorScreen), findsNothing);
  });

  testWidgets('conflict: Use theirs replaces the editor content and keeps the editor open', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (p) => throw PostgrestException(
        message: 'planning:stale_version', code: 'P0001',
        hint: jsonEncode({'current': _textBlock(text: 'Kofi wrote this', version: 4)}));
    await _openEditor(tester, g);
    _controller(tester).document.insert(0, 'Mine ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use theirs'));
    await tester.pumpAndSettle();
    expect(_controller(tester).document.toPlainText(), 'Kofi wrote this\n');
    expect(find.byType(PlanningV2TextEditorScreen), findsOneWidget);
  });

  testWidgets('save after the partner deleted the block closes with a message (Review Focus 2)', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] =
        (_) => throw const PostgrestException(message: 'planning:not_found', code: 'P0001');
    await _openEditor(tester, g);
    _controller(tester).document.insert(0, 'x');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Your partner removed this block.'), findsOneWidget);
    expect(find.byType(PlanningV2TextEditorScreen), findsNothing);
  });

  testWidgets('a network failure keeps the draft and the editor open', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (_) => throw Exception('offline');
    await _openEditor(tester, g);
    _controller(tester).document.insert(0, 'Draft ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanningV2TextEditorScreen), findsOneWidget);
    expect(_controller(tester).document.toPlainText(), startsWith('Draft '));
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await _openEditor(tester, _gateway());
    _controller(tester).document.insert(0, 'x');
    // Document.changes is a broadcast stream: the dirty flag's setState
    // lands a frame later, as it does for a real keystroke.
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanningV2TextEditorScreen), findsNothing);
  });

  test('highlight and text-colour tokens are the only colours the toolbar can apply', () {
    expect(PlanningV2TextEditorScreenState.tokens, ['yellow', 'green', 'blue', 'pink', 'purple']);
  });

  test('PlanningBlock import is used', () => expect(PlanningBlockType.text.name, 'text'));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/planning/v2/planning_v2_text_editor_test.dart`
Expected: FAIL — editor files do not exist.

- [ ] **Step 3: Implement**

`lib/features/planning/v2/presentation/widgets/planning_quill.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../planning_v2_ui.dart';

/// Quill needs its own localizations. Scoped here so the app-wide
/// MaterialApp (lib/app/app.dart) is not touched.
Widget planningQuillScope(BuildContext context, Widget child) => Localizations.override(
      context: context,
      delegates: const [FlutterQuillLocalizations.delegate],
      child: child,
    );

/// Token colours: highlights via the palette Quill consults first;
/// text colours via customStyleBuilder (merged after Quill's own style).
QuillEditorConfig planningQuillEditorConfig(BuildContext context, {String? placeholder, bool expands = false}) {
  final brightness = Theme.of(context).brightness;
  return QuillEditorConfig(
    placeholder: placeholder,
    expands: expands,
    scrollable: expands,
    padding: expands ? Spacing.allMd : EdgeInsets.zero,
    showCursor: expands,
    customStyles: DefaultStyles(palette: planningV2HighlightPalette(brightness)),
    customStyleBuilder: (attribute) => attribute.key == Attribute.color.key && attribute.value is String
        ? TextStyle(color: planningV2TextTone(attribute.value as String, brightness))
        : const TextStyle(),
  );
}
```

`lib/features/planning/v2/presentation/widgets/conflict_sheet.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

enum ConflictChoice { keepMine, useTheirs, copyMine }

/// Spec §4 "Conflicts": the second save never silently overwrites.
Future<ConflictChoice?> showConflictSheet(BuildContext context, {required String theirs}) =>
    showModalBottomSheet<ConflictChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: Spacing.pagePadding,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Your partner just changed this', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: Spacing.sm),
            Text('Their version:', style: Theme.of(c).textTheme.labelLarge),
            const SizedBox(height: Spacing.xs),
            Container(
              padding: Spacing.allSm,
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadiusTokens.smAll,
              ),
              child: Text(theirs.isEmpty ? '(empty)' : theirs, maxLines: 8, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton(onPressed: () => Navigator.pop(c, ConflictChoice.keepMine), child: const Text('Keep mine')),
            const SizedBox(height: Spacing.sm),
            OutlinedButton(onPressed: () => Navigator.pop(c, ConflictChoice.useTheirs), child: const Text('Use theirs')),
            TextButton(
              onPressed: () => Navigator.pop(c, ConflictChoice.copyMine),
              child: const Text('Copy mine, then use theirs'),
            ),
          ]),
        ),
      ),
    );
```

`lib/features/planning/v2/presentation/widgets/text_block_view.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../data/planning_v2_models.dart';
import '../../domain/delta_sanitizer.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../screens/planning_v2_text_editor_screen.dart';
import 'planning_quill.dart';

/// Read-only render of a text block. Rebuilds its controller when the
/// block's version changes (partner edit or own save).
class TextBlockView extends StatefulWidget {
  const TextBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  @override
  State<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends State<TextBlockView> {
  late QuillController _controller = _make();

  QuillController _make() => QuillController(
        document: Document.fromJson(sanitizeDelta(widget.block.delta).ops),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );

  @override
  void didUpdateWidget(TextBlockView old) {
    super.didUpdateWidget(old);
    if (old.block.version != widget.block.version || old.block.id != widget.block.id) {
      _controller.dispose();
      _controller = _make();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _edit() => Navigator.of(context).push(planningV2Route(
      PlanningV2TextEditorScreen(args: widget.args, block: widget.block)));

  @override
  Widget build(BuildContext context) {
    final empty = (widget.block.plainText ?? '').isEmpty;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: GestureDetector(
          onTap: _edit,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: empty
                ? Text('Tap to write', style: TextStyle(color: Theme.of(context).colorScheme.outline))
                : IgnorePointer(
                    child: planningQuillScope(
                      context,
                      QuillEditor.basic(controller: _controller, config: planningQuillEditorConfig(context)),
                    ),
                  ),
          ),
        ),
      ),
      IconButton(tooltip: 'Edit text', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
    ]);
  }
}
```

`lib/features/planning/v2/presentation/screens/planning_v2_text_editor_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attune/app/theme/design_tokens.dart';

import '../../data/planning_v2_models.dart';
import '../../domain/delta_sanitizer.dart';
import '../../domain/planning_v2_limits.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../widgets/conflict_sheet.dart';
import '../widgets/planning_quill.dart';

class PlanningV2TextEditorScreen extends ConsumerStatefulWidget {
  const PlanningV2TextEditorScreen({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  @override
  ConsumerState<PlanningV2TextEditorScreen> createState() => PlanningV2TextEditorScreenState();
}

class PlanningV2TextEditorScreenState extends ConsumerState<PlanningV2TextEditorScreen> {
  static const tokens = ['yellow', 'green', 'blue', 'pink', 'purple'];

  late QuillController _controller = _load(widget.block.delta);
  late int _baseVersion = widget.block.version;
  StreamSubscription<DocChange>? _changes;
  bool _dirty = false;
  bool _saving = false;

  @visibleForTesting
  QuillController get controller => _controller;

  QuillController _load(List<Map<String, dynamic>> ops) {
    _changes?.cancel();
    final c = QuillController(
      document: Document.fromJson(sanitizeDelta(ops).ops),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _changes = c.document.changes.listen((_) {
      if (!_dirty && mounted) setState(() => _dirty = true);
    });
    return c;
  }

  @override
  void dispose() {
    _changes?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    final clean = sanitizeDelta(_controller.document.toDelta().toJson());
    if (deltaPlainText(clean.ops).runes.length > PlanningV2Limits.textPlainChars) {
      _snack('That text is too long. Split it into two blocks.');
      return;
    }
    if (clean.changed) _snack('Some formatting is not supported here and was removed.');
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(planningV2EntryProvider(widget.args).notifier)
          .saveText(widget.block.id, _baseVersion, clean.ops);
      if (!mounted) return;
      switch (result) {
        case TextSaved():
          _dirty = false;
          Navigator.of(context).pop();
        case TextGone():
          _dirty = false;
          _snack('Your partner removed this block.');
          Navigator.of(context).pop();
        case TextConflict(:final theirs):
          await _resolve(theirs, clean.ops);
      }
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e); // draft stays; _dirty unchanged
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resolve(PlanningBlock theirs, List<Map<String, dynamic>> mine) async {
    final choice = await showConflictSheet(context, theirs: theirs.plainText ?? '');
    if (!mounted || choice == null) return;
    switch (choice) {
      case ConflictChoice.keepMine:
        _baseVersion = theirs.version;
        await _save();
      case ConflictChoice.copyMine:
        await Clipboard.setData(ClipboardData(text: deltaPlainText(mine)));
        if (mounted) _snack('Your text is copied.');
        _useTheirs(theirs);
      case ConflictChoice.useTheirs:
        _useTheirs(theirs);
    }
  }

  void _useTheirs(PlanningBlock theirs) {
    final old = _controller;
    setState(() {
      _controller = _load(theirs.delta);
      _baseVersion = theirs.version;
      _dirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Future<void> _pickToken({required bool background}) async {
    final brightness = Theme.of(context).brightness;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Wrap(alignment: WrapAlignment.center, spacing: Spacing.sm, children: [
          for (final t in tokens)
            Tooltip(
              message: '${background ? 'Highlight' : 'Text'} $t',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(c, t),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: background
                          ? planningV2HighlightPalette(brightness)[t]
                          : planningV2TextTone(t, brightness),
                    ),
                  ),
                ),
              ),
            ),
          TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('None')),
        ]),
      ),
    );
    if (picked == null) return;
    final value = picked.isEmpty ? null : picked;
    _controller.formatSelection(background ? BackgroundAttribute(value) : ColorAttribute(value));
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your edits to this text are not saved.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep editing')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmDiscard() && context.mounted) {
            _dirty = false;
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Edit text'),
            actions: [
              TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
            ],
          ),
          body: planningQuillScope(
            context,
            Column(children: [
              QuillSimpleToolbar(
                controller: _controller,
                config: QuillSimpleToolbarConfig(
                  multiRowsDisplay: false,
                  showFontFamily: false,
                  showFontSize: false,
                  showSmallButton: false,
                  showLineHeightButton: false,
                  showInlineCode: false,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showListCheck: false,
                  showCodeBlock: false,
                  showIndent: false,
                  showDirection: false,
                  showSearchButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showLeftAlignment: false,
                  showClipboardCut: false,
                  showClipboardCopy: false,
                  showClipboardPaste: false,
                  customButtons: [
                    QuillToolbarCustomButtonOptions(
                      icon: const Tooltip(message: 'Highlight', child: Icon(Icons.format_color_fill_rounded)),
                      onPressed: () => _pickToken(background: true),
                    ),
                    QuillToolbarCustomButtonOptions(
                      icon: const Tooltip(message: 'Text colour', child: Icon(Icons.format_color_text_rounded)),
                      onPressed: () => _pickToken(background: false),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: QuillEditor.basic(
                  controller: _controller,
                  config: planningQuillEditorConfig(context, placeholder: 'Write something…', expands: true),
                ),
              ),
            ]),
          ),
        ),
      );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/planning/v2/ && flutter analyze lib/features/planning/v2 test/features/planning/v2`
Expected: all PASS; `No issues found!`. If a `QuillSimpleToolbarConfig` flag name is rejected by the analyzer, check `~/.pub-cache/hosted/pub.dev/flutter_quill-11.5.0/lib/src/toolbar/config/simple_toolbar_config.dart` and use the name defined there. The flags above were checked against that file while this plan was written.

- [ ] **Step 5: Commit**

```bash
git add lib/features/planning/v2/presentation test/features/planning/v2
git commit -m "feat(planning-v2): rich-text editor with token colours, sanitize-on-save and conflict sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Preview entry point, full verification, checklist evidence

**Files:**
- Modify: `lib/features/planning/presentation/screens/planning_home_screen.dart` (the AppBar only)
- Modify: `test/features/planning/planning_home_screen_test.dart` (one added test)
- Create: `docs/superpowers/planning-v2-p1-checklist-evidence.md`

**Interfaces:**
- Consumes: `PlanningV2HomeScreen`, `planningV2Route` (Task 10).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Add this test inside `main()` of `test/features/planning/planning_home_screen_test.dart`, after the first existing `testWidgets`, reusing the file's own `_FakeGateway` and `_wrap`:

```dart
  testWidgets('the Planning v2 preview button is absent in normal builds', (tester) async {
    final repository = PlanningRepository(_FakeGateway({
      'list_planning_goals': (_) async => <dynamic>[],
      'list_planning_tasks': (_) async => <dynamic>[],
      'list_planning_events': (_) async => <dynamic>[],
    }));
    await tester.pumpWidget(_wrap(const PlanningHomeScreen(relationshipId: 'r1'), repository));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Planning v2 preview'), findsNothing);
  });
```

Run: `flutter test test/features/planning/planning_home_screen_test.dart`
Expected: PASS already (the button does not exist yet). This test guards the *release* behaviour; Step 3 proves the button appears with the define.

- [ ] **Step 2: Add the guarded entry point**

In `lib/features/planning/presentation/screens/planning_home_screen.dart`:

Add imports after the existing imports:

```dart
import '../../v2/presentation/planning_v2_ui.dart' show planningV2Route;
import '../../v2/presentation/screens/planning_v2_home_screen.dart';
```

Add above `class PlanningHomeScreen`:

```dart
/// Planning v2 is preview-only in P1 (plan ruling R9). A compile-time
/// constant: in builds without `--dart-define=PLANNING_V2_PREVIEW=true`
/// the button below is tree-shaken out and v1 is byte-for-byte unchanged
/// in behaviour.
const bool _planningV2Preview = bool.fromEnvironment('PLANNING_V2_PREVIEW');
```

In `PlanningHomeScreen.build`, add `actions:` to the existing `AppBar(...)` (after `title:`), changing nothing else:

```dart
        actions: [
          if (_planningV2Preview)
            IconButton(
              tooltip: 'Planning v2 preview',
              icon: const Icon(Icons.auto_awesome_rounded),
              onPressed: () => Navigator.of(context).push(
                planningV2Route(PlanningV2HomeScreen(relationshipId: relationshipId)),
              ),
            ),
        ],
```

- [ ] **Step 3: Verify both build modes**

Run: `flutter test test/features/planning/planning_home_screen_test.dart`
Expected: PASS (button absent).

Run: `flutter test --dart-define=PLANNING_V2_PREVIEW=true test/features/planning/planning_home_screen_test.dart --plain-name 'preview button is absent'`
Expected: **FAIL** with `Found 1 widget with tooltip "Planning v2 preview"` — this proves the define flips the button on. (Do not commit anything for this step.)

- [ ] **Step 4: Full verification**

Run each and record the result in the evidence doc (Step 5):

```bash
flutter analyze                                             # expect: 0 errors; no new warnings in v2 files
flutter test                                                # expect: all pass (baseline 2243 + the new v2 tests)
bash scripts/local_pg_setup.sh                              # expect: migrations failed 0; every contract PASS except
                                                            #   the pre-existing settings_accessor_test.sql (needs Vault)
bash supabase/tests/planning_v2_concurrency.sh              # run 3 times after a fresh local_pg_setup --no-tests; all PASS
grep -rnE "double|/ 100|\* 100" lib/features/planning/v2    # checklist 2.19: expect no money-path hits
grep -rn "EXECUTE format" supabase/migrations/202610122*     # checklist 2.2: expect no output
flutter test --coverage test/features/planning/v2           # checklist 6.7: record branch/line % for lib/features/planning/v2/domain
```

Coverage target (checklist 6.7): `domain/` ≥ 90%, the rest of `v2/` ≥ 70%. If `domain/` is below 90%, add tests for the uncovered branches before continuing.

- [ ] **Step 5: Write the evidence doc**

`docs/superpowers/planning-v2-p1-checklist-evidence.md` — fill in the real numbers from Step 4:

```markdown
# Planning v2 P1 — Algorithm Quality Review Checklist v3.1 evidence

Spec: docs/superpowers/specs/2026-10-12-planning-v2-design.md §12. This file records what P1 actually proved.

| Check | Evidence |
|---|---|
| 1.4 Authorization at every access | Every RPC resolves the row then calls planning_v2_actor; "stranger" contracts in all five SQL contract files; mutant "actor check removed" caught by planning_v2_entry_contracts Contract 4 |
| 1.6 / 2.16 / 6.3 Concurrency | planning_v2_concurrency.sh: simultaneous first open (6 categories, both sessions succeed), disjoint ticks (both persist), same-block save (exactly one stale_version). Mutant "seed lock removed" caught. Runs: <n>/3 PASS |
| 1.1 / 2.18 Idempotency | Client UUIDs + version checks; op_replay contract; outbox "replay is idempotent" test |
| 1.10 Compensations | Template copy, duplicate, reset, category delete are single transactions |
| 2.1 Input validation | planning_v2_validate_block / _item / validate_delta; helpers contracts 7–12 |
| 2.4 / 5.5 No leakage | not_found for forbidden; planningV2ErrorMessage test asserts no codes/underscores |
| 2.5 / 2.14 Limits | planning_limits() mirrored in Dart (limits test); block/item/category limit contracts |
| 2.19 No float money | grep result: <paste> |
| 2.2 No dynamic SQL | grep result: <paste> |
| 3.1 Pagination | list_planning_entries keyset; entry contracts 6 |
| 3.3 Indexes | idx_planning_* in 20261012200000 |
| 3.9 / 3.10 Retry | PlanningOutbox: 6 attempts, 500ms base, 30s cap, full jitter; permanent errors dropped (tests) |
| 5.1 Actionable errors | planningV2ErrorMessage |
| 5.6 Accessibility | androidTapTargetGuideline on home + entry; semantics labels for tick, assignee, new dot; non-drag reorder via menu |
| 6.4 Negative tests | permanent tick failure reverts and queues nothing; template never listed; edited template never overwritten |
| 6.5 Property tests | 1000-insert sort-key property (helpers Contract 4) |
| 6.7 Coverage | domain: <x>% · v2 overall: <y>% |
| 7.1 Dependency scan | flutter_quill advisories: <0> |
| 7.4 Least privilege | No table grants (schema Contract 11, under the real harness grant order) |
| 8.1 Rollback | P1 is additive and unreachable without PLANNING_V2_PREVIEW; rollback = do not ship the define |

Skipped in P1 (owned by later sub-projects): 2.22 audit (P3), link-preview SSRF (P3), notifications (P4), storage (P3).
Partial, repo-wide: 4.6–4.10 metrics/alerting, 6.10–6.12 soak/load/chaos (no infrastructure in repo).
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/planning/presentation/screens/planning_home_screen.dart test/features/planning/planning_home_screen_test.dart docs/superpowers/planning-v2-p1-checklist-evidence.md
git commit -m "feat(planning-v2): preview-only entry point and P1 checklist evidence

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

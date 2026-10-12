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

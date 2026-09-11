-- Stories: schema, constraints and the feature flag.
--
-- Copied verbatim from docs/superpowers/specs/2026-09-11-stories-design.md
-- §3.1 (story_items, story_views) and §5.5 (story_change_signals).

CREATE TABLE public.story_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Stable client id makes finalize retries safe when the server committed
  -- but the response was lost.
  client_story_id   uuid NOT NULL,
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  author_id         uuid NOT NULL REFERENCES auth.users(id)
                      ON DELETE CASCADE,

  media_type        text NOT NULL CHECK (media_type IN ('image', 'video')),

  -- KEYS, not URLs. The bucket is private and reads mint a signed URL
  -- per request (§4.1). A stored URL would either expire in the row or
  -- imply a public object.
  media_key         text NOT NULL UNIQUE,

  -- NOT NULL: the rings have nothing to draw without it, so a story is
  -- not finalized until its thumbnail exists (§4.3).
  thumbnail_key     text NOT NULL UNIQUE,

  media_width       int NOT NULL CHECK (media_width > 0),
  media_height      int NOT NULL CHECK (media_height > 0),

  -- Present for video, absent for image.
  duration_ms       int,
  CONSTRAINT story_duration_matches_type CHECK (
    (media_type = 'video' AND duration_ms BETWEEN 500 AND 60000)
    OR (media_type = 'image' AND duration_ms IS NULL)
  ),

  -- The date the calendar groups by. Frozen at creation from the
  -- poster's civil date -- see §3.5. A stored date beats every reader
  -- re-deriving one from created_at and disagreeing across timezones.
  occurred_on       date NOT NULL,

  created_at        timestamptz NOT NULL DEFAULT now(),

  -- Gates the reel, and nothing else. Set server-side at insert.
  expires_at        timestamptz NOT NULL,

  -- Soft delete. Hides the item from the reel AND the calendar at once,
  -- because both read this row.
  deleted_at        timestamptz,

  -- Null until the downscale job has run. NOT sufficient as the job's
  -- idempotency mechanism on its own -- see §4.4.
  downscaled_at     timestamptz,

  -- With an audience of exactly one, one server-owned boolean is enough
  -- for realtime UI. The exact timestamp remains private in story_views.
  has_been_viewed   boolean NOT NULL DEFAULT false,

  CONSTRAINT story_distinct_media_keys CHECK (media_key <> thumbnail_key),
  CONSTRAINT story_expires_in_24h CHECK (
    expires_at = created_at + interval '24 hours'
  ),
  UNIQUE (author_id, client_story_id)
);

CREATE INDEX idx_story_reel
  ON public.story_items
    (relationship_id, author_id, created_at, id)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_story_calendar
  ON public.story_items
    (relationship_id, occurred_on DESC, created_at DESC, id DESC)
  WHERE deleted_at IS NULL;

CREATE TABLE public.story_views (
  story_item_id uuid NOT NULL REFERENCES public.story_items(id)
                  ON DELETE CASCADE,
  viewer_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  viewed_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_item_id, viewer_id)
);

CREATE TABLE public.story_change_signals (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id)
                    ON DELETE CASCADE,
  version         bigint NOT NULL DEFAULT 1,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- feature_flags is (key, enabled, updated_at) -- no description column.
INSERT INTO public.feature_flags(key, enabled)
VALUES ('stories', false)
ON CONFLICT (key) DO NOTHING;

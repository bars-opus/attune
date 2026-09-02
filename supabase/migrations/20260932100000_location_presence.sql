-- Location presence: coarse distance, and deliberate place updates.
--
-- Attune ships a discreet exit as a permanent constraint and runs
-- coercive-control detection on chat. A location feature in this product
-- has to be built so it cannot become the thing the rest of the app
-- defends against. The whole design inverts who controls disclosure: the
-- app never reveals where anyone IS, and precision only ever appears in
-- an update a person chose to send.
--
-- The load-bearing consequence for this schema: a client never receives
-- its partner's coordinates. Distance is computed server-side and
-- returned as a NUMBER. There is no query that hands one partner the
-- other's position.

CREATE TABLE IF NOT EXISTS public.partner_presence (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,

  -- Coordinates are stored at reduced precision. Three decimal places is
  -- roughly 100m: enough for "same city" and travel time, not enough to
  -- say which building. The client rounds before sending; this is the
  -- second line of defence, not the first.
  latitude numeric(8, 3),
  longitude numeric(8, 3),

  -- Coarse place, for "she's in Accra". Never a street.
  city text,
  country text,
  country_code text,

  -- Their local time is the most useful thing a long-distance partner can
  -- know -- it answers "can I call?" -- and unlike distance it changes.
  timezone text,

  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT partner_presence_coords_paired CHECK (
    (latitude IS NULL AND longitude IS NULL)
    OR (latitude IS NOT NULL AND longitude IS NOT NULL)
  )
);

ALTER TABLE public.partner_presence ENABLE ROW LEVEL SECURITY;

-- A user reads and writes ONLY their own row. The partner never selects
-- from this table at all -- they call a function that returns a distance.
DROP POLICY IF EXISTS partner_presence_self ON public.partner_presence;
CREATE POLICY partner_presence_self
ON public.partner_presence FOR ALL TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_presence TO authenticated;

-- ---------------------------------------------------------------------
-- Place updates: the deliberate ones.
-- ---------------------------------------------------------------------

-- Full precision here, because the user chose to send it. This is the
-- difference the whole feature rests on: being observed versus telling.
CREATE TABLE IF NOT EXISTS public.place_updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- The chat message carrying this update. CASCADE both ways: deleting
  -- the message must take the location with it, since a place that read
  -- one way tonight may read differently tomorrow and the exit has to be
  -- as easy as the entry.
  message_id uuid REFERENCES public.messages(id) ON DELETE CASCADE,

  label text NOT NULL,
  note text,
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  city text,
  country text,

  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT place_updates_label_length CHECK (char_length(label) BETWEEN 1 AND 120),
  CONSTRAINT place_updates_note_length CHECK (note IS NULL OR char_length(note) <= 500)
);

CREATE INDEX IF NOT EXISTS place_updates_relationship_idx
  ON public.place_updates (relationship_id, created_at DESC);

ALTER TABLE public.place_updates ENABLE ROW LEVEL SECURITY;

-- Both partners read these: the point of an update is that it was shared.
DROP POLICY IF EXISTS place_updates_members_read ON public.place_updates;
CREATE POLICY place_updates_members_read
ON public.place_updates FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = place_updates.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.chat_archived_at IS NULL
  )
);

-- Only the author writes or deletes their own.
DROP POLICY IF EXISTS place_updates_author_write ON public.place_updates;
CREATE POLICY place_updates_author_write
ON public.place_updates FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = place_updates.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.chat_archived_at IS NULL
  )
);

DROP POLICY IF EXISTS place_updates_author_delete ON public.place_updates;
CREATE POLICY place_updates_author_delete
ON public.place_updates FOR DELETE TO authenticated
USING (user_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.place_updates TO authenticated;

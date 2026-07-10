-- Phase 12 — client_notes
--
-- Per-shop / per-client sticky note. Owner-authored only; client never
-- reads it. Last-write-wins (no history). Mirrors the wallet-owner-only
-- RLS template verbatim (RESEARCH §6).
--
-- The exactly-one-of-user-or-guest CHECK is enforced both here and
-- inside the upsert RPC (defence in depth).
--
-- Unique key is (shop_id, COALESCE(user_id, guest_profile_id)) — the
-- COALESCE makes the index work for both registered and guest clients.
-- DELETE is denied via the absence of a DELETE policy; clearing a note
-- happens via upsert-with-empty-body.

CREATE TABLE IF NOT EXISTS public.client_notes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id             UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  user_id             UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  guest_profile_id    UUID REFERENCES public.guest_profiles(id) ON DELETE SET NULL,
  body                TEXT NOT NULL,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by_user_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT client_notes_exactly_one_identity
    CHECK ((user_id IS NULL) <> (guest_profile_id IS NULL)),
  CONSTRAINT client_notes_body_length
    CHECK (char_length(body) <= 2000)
);

CREATE UNIQUE INDEX IF NOT EXISTS client_notes_shop_client_uk
  ON public.client_notes (
    shop_id,
    COALESCE(user_id::text, guest_profile_id::text)
  );

CREATE INDEX IF NOT EXISTS idx_client_notes_shop
  ON public.client_notes (shop_id);

ALTER TABLE public.client_notes ENABLE ROW LEVEL SECURITY;

-- Four separate policies (SELECT / INSERT / UPDATE), no DELETE.
-- Default-deny on absent policies.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'client_notes_select_owner') THEN
    CREATE POLICY client_notes_select_owner ON public.client_notes
      FOR SELECT
      USING (shop_id IN (SELECT id FROM public.shops WHERE user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'client_notes_insert_owner') THEN
    CREATE POLICY client_notes_insert_owner ON public.client_notes
      FOR INSERT
      WITH CHECK (shop_id IN (SELECT id FROM public.shops WHERE user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'client_notes_update_owner') THEN
    CREATE POLICY client_notes_update_owner ON public.client_notes
      FOR UPDATE
      USING (shop_id IN (SELECT id FROM public.shops WHERE user_id = auth.uid()))
      WITH CHECK (shop_id IN (SELECT id FROM public.shops WHERE user_id = auth.uid()));
  END IF;
END $$;

COMMENT ON TABLE public.client_notes IS
  'Per-shop / per-client sticky note. Owner-authored only; client never sees it. Last-write-wins (no history). Square parity. Phase 12.';

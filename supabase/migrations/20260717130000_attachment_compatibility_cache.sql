-- Attachment compatibility cache.
--
-- Quiz code reads attachment_compatibility_cache and calls
-- upsert_attachment_compatibility_cache, but neither the table nor the RPC was
-- ever migrated — so the compatibility screen fails at runtime (PGRST205 /
-- undefined function). DDL + RLS are byte-faithful to ATTACHMENT_STYLE_QUIZ.md
-- §968/§1010. The cache is written only through the SECURITY DEFINER upsert RPC
-- (clients get SELECT only, per the spec's read-only policy), so the generated
-- pairing note cannot be forged by a client.

CREATE TABLE IF NOT EXISTS public.attachment_compatibility_cache (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  type_a text NOT NULL,
  type_b text NOT NULL,
  pairing_name text NOT NULL,
  pairing_description text NOT NULL,
  natural_strength text NOT NULL,
  watch_area text NOT NULL,
  generated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (relationship_id)
);

CREATE INDEX IF NOT EXISTS idx_attachment_compat_relationship
  ON public.attachment_compatibility_cache (relationship_id);

ALTER TABLE public.attachment_compatibility_cache ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.attachment_compatibility_cache FROM PUBLIC, anon;
-- Read-only to clients; the upsert RPC (SECURITY DEFINER) does the writing.
GRANT SELECT ON public.attachment_compatibility_cache TO authenticated;

-- Compatibility cache: readable by both relationship members (ATTACHMENT §1010).
DROP POLICY IF EXISTS compatibility_cache_relationship ON public.attachment_compatibility_cache;
CREATE POLICY compatibility_cache_relationship
ON public.attachment_compatibility_cache FOR SELECT TO authenticated
USING (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

-- Upsert RPC. Verifies the caller is a member of the relationship before writing,
-- so a client cannot seed a cache row for a couple it doesn't belong to. One row
-- per relationship (UNIQUE) — regenerated when either partner retakes/reshares.
CREATE OR REPLACE FUNCTION public.upsert_attachment_compatibility_cache(
  p_relationship_id uuid,
  p_type_a text,
  p_type_b text,
  p_pairing_name text,
  p_pairing_description text,
  p_natural_strength text,
  p_watch_area text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND (user_a = auth.uid() OR user_b = auth.uid())
  ) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.attachment_compatibility_cache (
    relationship_id, type_a, type_b,
    pairing_name, pairing_description, natural_strength, watch_area, generated_at
  )
  VALUES (
    p_relationship_id, p_type_a, p_type_b,
    p_pairing_name, p_pairing_description, p_natural_strength, p_watch_area, now()
  )
  ON CONFLICT (relationship_id) DO UPDATE SET
    type_a = EXCLUDED.type_a,
    type_b = EXCLUDED.type_b,
    pairing_name = EXCLUDED.pairing_name,
    pairing_description = EXCLUDED.pairing_description,
    natural_strength = EXCLUDED.natural_strength,
    watch_area = EXCLUDED.watch_area,
    generated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_attachment_compatibility_cache(uuid, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_attachment_compatibility_cache(uuid, text, text, text, text, text, text) TO authenticated;

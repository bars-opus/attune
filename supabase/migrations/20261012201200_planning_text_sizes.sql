-- Text sizes in Planning's rich text: the three named sizes Quill uses
-- (Small, Large, Huge; Normal is no attribute). Named sizes, not point
-- sizes, so a note looks the same on both partners' phones.
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
    WHEN 'size'       THEN p_val IN ('"small"','"large"','"huge"')
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

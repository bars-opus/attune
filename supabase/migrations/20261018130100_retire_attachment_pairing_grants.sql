-- Spec 5 (plan review I10): grants for 20261018130000. Nothing reads or
-- writes the pairing cache from a client any more.
REVOKE ALL ON public.attachment_compatibility_cache FROM PUBLIC, anon, authenticated;

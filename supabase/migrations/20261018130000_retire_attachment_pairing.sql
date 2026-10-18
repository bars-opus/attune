-- Spec 5 (research 06 §3 F9, plan R5-3): pairing output is removed, not
-- hidden. Attune makes no statement about how two attachment styles fit, and
-- an attachment result is about the person who took it (F9 (3)), so it is
-- never shared with a partner.
--
-- The cache table stays (empty) because purge_relationship still clears it;
-- its grants are in 20261018130100.

DROP FUNCTION IF EXISTS public.upsert_attachment_compatibility_cache(uuid, text, text, text, text, text, text);

DELETE FROM public.attachment_compatibility_cache;

-- A partner's view of an attachment share is retired with the share itself.
DELETE FROM public.quiz_shares WHERE quiz_type = 'attachment';

ALTER TABLE public.quiz_shares DROP CONSTRAINT IF EXISTS quiz_shares_no_attachment;
ALTER TABLE public.quiz_shares
  ADD CONSTRAINT quiz_shares_no_attachment CHECK (quiz_type <> 'attachment');

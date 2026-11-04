-- Spec 1 W9a: grants for 20261104100000_opinion_content_filter.sql. The
-- normaliser, the term lists, the verdict and the assert are the database's
-- own (no role is granted anything; the writers run them as definers). The
-- six writers keep exactly their live grants: signed-in only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON private.content_filter_terms FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE private.content_filter_terms_id_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.normalize_for_filter(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.match_form(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.digits_from_words(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.has_contact_info(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.mask_number_shapes(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.content_filter_verdict(text, text[]) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.assert_opinion_content_ok(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.assert_poll_options_ok(text[]) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.assert_part_content_ok(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.assert_comment_content_ok(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_opinion(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_opinion_with_poll(text, text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_opinion_with_quote(text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.edit_opinion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_opinion_comment(uuid, text, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.edit_opinion_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_opinion(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_opinion_with_poll(text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_opinion_with_quote(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.edit_opinion(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_opinion_comment(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.edit_opinion_comment(uuid, text) TO authenticated;
COMMIT;

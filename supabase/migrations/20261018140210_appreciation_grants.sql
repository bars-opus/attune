-- Spec 7: grants for 20261018140200 (edit_message keeps its own).
REVOKE ALL ON public.appreciation_jar FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.send_appreciation(uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_to_my_jar(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_from_my_jar(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_my_jar() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_appreciation(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_to_my_jar(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_from_my_jar(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_jar() TO authenticated;
REVOKE ALL ON FUNCTION public.messages_appreciation_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_my_jar_ids() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_jar_ids() TO authenticated;

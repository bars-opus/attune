-- Spec 3c: grants for 20261018120000. Clients request and read their own
-- job; the bundle, chat pages, manifest and job transitions are the worker's.
REVOKE ALL ON public.data_export_jobs FROM anon, authenticated;
GRANT SELECT ON public.data_export_jobs TO service_role;

REVOKE ALL ON FUNCTION public.request_my_export() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_export() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_my_export() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_export() TO authenticated;

REVOKE ALL ON FUNCTION public.export_who(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.export_file_name(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.export_next_allowed(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_open_relationships(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_relationship(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_bundle(uuid, uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_chat_page(uuid, uuid, timestamptz, uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_media_manifest(uuid, uuid[], text, text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_data_export() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_begin_part(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_finish_part(uuid, text, text, int, timestamptz, uuid, int, text, text, jsonb, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_drop_files(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fail_data_export(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_retry_part(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_expire_stale(uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.export_bundle(uuid, uuid[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.export_chat_page(uuid, uuid, timestamptz, uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.export_media_manifest(uuid, uuid[], text, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_data_export() TO service_role;
GRANT EXECUTE ON FUNCTION public.export_begin_part(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.export_finish_part(uuid, text, text, int, timestamptz, uuid, int, text, text, jsonb, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_data_export(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.export_retry_part(uuid, text) TO service_role;

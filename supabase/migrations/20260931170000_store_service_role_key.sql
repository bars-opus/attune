-- Lets an Edge Function write its own injected service-role key into Vault.
--
-- This project is mid-migration to Supabase's sb_secret_ API keys. Edge
-- Functions receive the NEW key as SUPABASE_SERVICE_ROLE_KEY (41 chars,
-- sb_secret_ prefix), while the dashboard still displays the LEGACY
-- service_role JWT (219 chars) -- and that legacy value is what was
-- stored in Vault.
--
-- requireServiceRole() compares the bearer token to the injected env var
-- by exact string match, so every cron-driven worker was rejected with
-- 403 before reading a single row: 89 safety messages and 4 media
-- deletions sat untouched with attempts = 0, while cron logged
-- `succeeded` (net.http_post reports success once the request is queued)
-- and the function logged clean boots.
--
-- The new key is not visible in this project's dashboard, so it cannot be
-- copied by hand. The function already holds the value; this lets it hand
-- it to Vault directly, without the secret passing through a clipboard,
-- a terminal history, or a chat log.
CREATE OR REPLACE FUNCTION public.store_service_role_key(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
BEGIN
  IF p_key IS NULL OR length(p_key) < 20 THEN
    RAISE EXCEPTION 'refusing to store an implausible service role key';
  END IF;

  DELETE FROM vault.secrets WHERE name = 'service_role_key';
  PERFORM vault.create_secret(p_key, 'service_role_key');
END;
$$;

-- service_role only: this writes the credential the whole worker layer
-- authenticates with.
REVOKE ALL ON FUNCTION public.store_service_role_key(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.store_service_role_key(text) TO service_role;

-- Spec 2 W1c, migration 6 (spec §4.9 W1c #1, part 1 of 3: fields and
-- encryption; §4.2, §4.3, §4.4):
--   * dating_require_trusted_device() as a pass-through that always allows
--     (W4b re-creates it with the real check; every Dating RPC already
--     calls it, so none is re-created then).
--   * dating_profiles: country, region, side, intention, marriage timeline,
--     attestation, children, family involvement, the visibility toggles,
--     photos after mutual interest, country_changed_at; display_name 1-30
--     for a new or changed name (the trigger dating_profiles_display_name_guard;
--     v1's 1-50 CHECK stays, so an older 31-50 character name keeps working
--     for every other write: batch-6 fix round 1, I-2); the v1
--     gender-visibility CHECK dropped (gender now lives encrypted). The v1
--     columns city_region_code, relationship_intention, bio and
--     gender_identity stay, nullable, until their last readers go (plan P-22).
--   * dating_preferences: ages 18-99; region_scope, intention_open (not
--     empty), open_abroad (upper-case codes, no NULL), want_must_match,
--     exclude_parents (the v1 arrays stay until W5a's hard filters v2, P-22).
--   * dating_profile_sensitive (identity, seeking and faith, special
--     category; marital history, not Art. 9 special category (owner ruling,
--     provisional, counsel confirms) but encrypted as defence in depth; each
--     pgp_sym_encrypt'ed with the Vault key dating_field_key; revoked from
--     service_role too, table and column grants), dating_prompts,
--     dating_settings.
--   * private.dating_field_key_present(), dating_field_encrypt(jsonb),
--     dating_field_decrypt(bytea): SECURITY INVOKER, EXECUTE for nobody
--     (definer callers only; fix round 1, M-7). In production the key is
--     read from Vault only, never a GUC (M-4).
--     Batch-6 ruling: each value is byte 0 = its key version (1 =
--     dating_field_key) then an OpenPGP message (AES-256, a random session
--     key and salt per value, the MDC integrity packet, compression off);
--     decrypt refuses (dating:field_decrypt_failed) an unknown or untagged
--     version (fix round 1, M-8), an old-format header, a packet without
--     MDC, a tampered value or another key, and never quotes the plaintext.
--     No key (or one under 32 characters) raises dating:field_key_missing:
--     never plaintext, never a default key.
--   * private.dating_consent_granted(user, purpose): granted, never
--     withdrawn since (a tie at one instant is a withdrawal).
-- Grants in 20261106150010_dating_v2_profile_fields_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.dating_require_trusted_device()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  -- W1c pass-through; W4b reads the x-attune-device header here.
  SELECT true;
$fn$;

ALTER TABLE public.dating_profiles
  ALTER COLUMN city_region_code DROP NOT NULL,
  ALTER COLUMN relationship_intention DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS country_code char(2),
  ADD COLUMN IF NOT EXISTS region_code text,
  ADD COLUMN IF NOT EXISTS side_code text,
  ADD COLUMN IF NOT EXISTS intention text,
  ADD COLUMN IF NOT EXISTS marriage_timeline text,
  ADD COLUMN IF NOT EXISTS timeline_visible boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS not_married_attested_at timestamptz,
  ADD COLUMN IF NOT EXISTS attestation_version text,
  ADD COLUMN IF NOT EXISTS children_have boolean,
  ADD COLUMN IF NOT EXISTS children_want text,
  ADD COLUMN IF NOT EXISTS family_involvement text,
  ADD COLUMN IF NOT EXISTS faith_visible boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS marital_visible boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS photos_after_mutual boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS country_changed_at timestamptz;
ALTER TABLE public.dating_profiles DROP CONSTRAINT IF EXISTS dating_profiles_gender_visibility_check;
-- Fix round 1 (I-2): a NOT VALID 1-30 CHECK still checks every new row
-- version, so any UPDATE (a restriction's or a relationship's pause, the kill
-- switch) of an older 31-50 character name would fail. v1's 1-50 CHECK stays
-- as the ceiling; 1-30 applies to a new or changed name only.
ALTER TABLE public.dating_profiles DROP CONSTRAINT IF EXISTS dating_profiles_display_name_length_check;
ALTER TABLE public.dating_profiles ADD CONSTRAINT dating_profiles_display_name_length_check
  CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 50);

CREATE OR REPLACE FUNCTION private.dating_profiles_display_name_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF (TG_OP = 'INSERT' OR NEW.display_name IS DISTINCT FROM OLD.display_name)
     AND coalesce(char_length(btrim(NEW.display_name)), 0) NOT BETWEEN 1 AND 30 THEN
    RAISE EXCEPTION 'dating:display_name_length' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS dating_profiles_display_name_guard ON public.dating_profiles;
CREATE TRIGGER dating_profiles_display_name_guard
  BEFORE INSERT OR UPDATE OF display_name ON public.dating_profiles
  FOR EACH ROW EXECUTE FUNCTION private.dating_profiles_display_name_guard();
ALTER TABLE public.dating_profiles DROP CONSTRAINT IF EXISTS dating_profiles_v2_check;
-- NULL-safe (batch-2 sweep): a timeline needs intention 'marriage', and a
-- NULL intention is not 'marriage'.
ALTER TABLE public.dating_profiles ADD CONSTRAINT dating_profiles_v2_check CHECK (
  (country_code IS NULL OR country_code ~ '^[A-Z]{2}$')
  AND (intention IS NULL OR intention IN ('marriage', 'committed', 'companionship', 'not_sure'))
  AND (marriage_timeline IS NULL OR (intention IS NOT DISTINCT FROM 'marriage'
       AND marriage_timeline IN ('within_two_years', 'few_years', 'no_set_time')))
  AND (children_want IS NULL OR children_want IN ('yes', 'no', 'open'))
  AND (family_involvement IS NULL OR family_involvement IN ('early', 'when_serious', 'our_decision'))
  AND (side_code IS NULL OR region_code IS NOT NULL)
  AND (region_code IS NULL OR country_code IS NOT NULL));

ALTER TABLE public.dating_preferences
  ADD COLUMN IF NOT EXISTS region_scope text NOT NULL DEFAULT 'region',
  ADD COLUMN IF NOT EXISTS intention_open text[],
  ADD COLUMN IF NOT EXISTS open_abroad char(2)[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS want_must_match boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS exclude_parents boolean NOT NULL DEFAULT false;
ALTER TABLE public.dating_preferences DROP CONSTRAINT IF EXISTS dating_preferences_min_age_check;
ALTER TABLE public.dating_preferences ADD CONSTRAINT dating_preferences_min_age_check CHECK (min_age BETWEEN 18 AND 99);
ALTER TABLE public.dating_preferences DROP CONSTRAINT IF EXISTS dating_preferences_max_age_check;
ALTER TABLE public.dating_preferences ADD CONSTRAINT dating_preferences_max_age_check CHECK (max_age BETWEEN 18 AND 99);
ALTER TABLE public.dating_preferences DROP CONSTRAINT IF EXISTS dating_preferences_v2_check;
ALTER TABLE public.dating_preferences ADD CONSTRAINT dating_preferences_v2_check CHECK (
  region_scope IN ('side', 'region', 'country')
  AND (intention_open IS NULL OR (intention_open <@ ARRAY['marriage', 'committed', 'companionship', 'not_sure']
                                  AND cardinality(intention_open) >= 1))
  AND array_position(open_abroad, NULL) IS NULL
  AND coalesce(array_to_string(open_abroad, ',') ~ '^([A-Z]{2}(,|$))*$', false));

CREATE TABLE IF NOT EXISTS public.dating_profile_sensitive (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  identity_enc bytea,
  seeking_enc bytea,
  faith_enc bytea,
  marital_enc bytea,
  key_version smallint NOT NULL DEFAULT 1 CHECK (key_version >= 1),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_profile_sensitive ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.dating_profile_sensitive IS
  'Spec 2 §4.2: identity, seeking and faith (special category) and marital history (not Art. 9; encrypted as defence in depth), each encrypted with the Vault key dating_field_key and tagged with its key version in byte 0. No API role reads it (table or column), the service role included; only definer functions decrypt.';

CREATE TABLE IF NOT EXISTS public.dating_prompts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  position smallint NOT NULL CHECK (position BETWEEN 1 AND 3),
  prompt_id text NOT NULL CHECK (prompt_id IN ('perfect_sunday', 'feel_at_home', 'friends_say',
    'looking_for', 'small_thing', 'win_me_over', 'learning_to', 'family_describe', 'place_love', 'ask_me_about')),
  answer text NOT NULL CHECK (char_length(answer) BETWEEN 10 AND 200),
  moderation_state text NOT NULL DEFAULT 'approved' CHECK (moderation_state IN ('approved', 'removed')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, position),
  UNIQUE (user_id, prompt_id)
);
ALTER TABLE public.dating_prompts ENABLE ROW LEVEL SECURITY;
-- Fix round 1 (M-9): an answer of spaces is no answer.
ALTER TABLE public.dating_prompts DROP CONSTRAINT IF EXISTS dating_prompts_answer_check;
ALTER TABLE public.dating_prompts ADD CONSTRAINT dating_prompts_answer_check
  CHECK (char_length(btrim(answer)) BETWEEN 10 AND 200);

CREATE TABLE IF NOT EXISTS public.dating_settings (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  drop_time time NOT NULL DEFAULT '19:00'
    CHECK (drop_time BETWEEN '07:00' AND '22:00' AND extract(second FROM drop_time) = 0
           AND extract(minute FROM drop_time) IN (0, 30)),
  data_saver boolean NOT NULL DEFAULT false,
  digest_push boolean NOT NULL DEFAULT false,
  chat_push boolean NOT NULL DEFAULT true,
  show_when_away boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_settings ENABLE ROW LEVEL SECURITY;

-- The field key. Production reads Vault only (Spec 1's strict reader): a
-- GUC would sit in plaintext in pg_db_role_setting, readable by every role.
-- Development reads Vault, then the GUC (Spec 1's app_setting). Present
-- means at least 32 characters. SECURITY INVOKER (M-7): every caller is a
-- postgres-owned definer, and a stray grant fails closed at the key read.
CREATE OR REPLACE FUNCTION private.dating_field_key_present()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $fn$
  SELECT coalesce(char_length(CASE WHEN private.attune_environment() IS NOT DISTINCT FROM 'development'
                             THEN public.app_setting('dating_field_key')
                             ELSE private.vault_setting_strict('dating_field_key') END) >= 32, false);
$fn$;

CREATE OR REPLACE FUNCTION private.dating_field_encrypt(p_plain jsonb)
RETURNS bytea
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $fn$
DECLARE
  v_key constant text := CASE WHEN private.attune_environment() IS NOT DISTINCT FROM 'development'
                             THEN public.app_setting('dating_field_key')
                             ELSE private.vault_setting_strict('dating_field_key') END;
BEGIN
  IF p_plain IS NULL THEN
    RETURN NULL;
  END IF;
  IF coalesce(char_length(v_key), 0) < 32 THEN
    RAISE EXCEPTION 'dating:field_key_missing';
  END IF;
  -- Byte 0 tags the key version (1: dating_field_key), for rotation. Then
  -- an OpenPGP message: AES-256, a random session key and salt per value,
  -- the MDC integrity packet; compression off, so the ciphertext's length
  -- says nothing about the content.
  RETURN '\x01'::bytea || extensions.pgp_sym_encrypt(p_plain::text, v_key,
    'cipher-algo=aes256, compress-algo=0, disable-mdc=0, sess-key=1, s2k-digest-algo=sha256');
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_field_decrypt(p_cipher bytea)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $fn$
DECLARE
  v_key constant text := CASE WHEN private.attune_environment() IS NOT DISTINCT FROM 'development'
                             THEN public.app_setting('dating_field_key')
                             ELSE private.vault_setting_strict('dating_field_key') END;
  v_pgp bytea;
  v_plain jsonb;
BEGIN
  IF p_cipher IS NULL THEN
    RETURN NULL;
  END IF;
  IF coalesce(char_length(v_key), 0) < 32 THEN
    RAISE EXCEPTION 'dating:field_key_missing';
  END IF;
  -- Only key version 1 exists until rotate_dating_field_key(); a value
  -- under any other version (or untagged) is unreadable here (M-8: not a
  -- missing key, which health would contradict).
  IF substring(p_cipher FROM 1 FOR 1) IS DISTINCT FROM '\x01'::bytea THEN
    RAISE EXCEPTION 'dating:field_decrypt_failed';
  END IF;
  v_pgp := substring(p_cipher FROM 2);
  BEGIN
    -- Integrity-protected only: the session-key packet (tag 3, 0xC3), then
    -- the MDC data packet (tag 18, 0xD2), never the unprotected tag 9.
    IF get_byte(v_pgp, 0) IS DISTINCT FROM 195 OR get_byte(v_pgp, 2 + get_byte(v_pgp, 1)) IS DISTINCT FROM 210 THEN
      RAISE EXCEPTION 'dating:field_decrypt_failed';
    END IF;
    v_plain := extensions.pgp_sym_decrypt(v_pgp, v_key)::jsonb;
  EXCEPTION WHEN OTHERS THEN
    -- Never the cause: a JSON or encoding error quotes the decrypted text.
    RAISE EXCEPTION 'dating:field_decrypt_failed';
  END;
  RETURN v_plain;
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_consent_granted(p_user uuid, p_purpose text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  -- The latest event decides; at one instant a withdrawal outranks a grant.
  SELECT coalesce((
    SELECT e.action = 'granted'
      FROM public.dating_consent_events AS e
     WHERE e.user_id = p_user AND e.purpose = p_purpose
     ORDER BY e.occurred_at DESC, e.created_at DESC, (e.action = 'withdrawn') DESC
     LIMIT 1), false);
$fn$;

-- REVOKE ALL on a table also revokes its column grants; the column list
-- says so explicitly for the sensitive table (fix round 1, I-1).
REVOKE ALL ON public.dating_profile_sensitive FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL (user_id, identity_enc, seeking_enc, faith_enc, marital_enc, key_version, updated_at)
  ON public.dating_profile_sensitive FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.dating_prompts, public.dating_settings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_require_trusted_device(), private.dating_field_key_present(),
  private.dating_field_encrypt(jsonb), private.dating_field_decrypt(bytea),
  private.dating_consent_granted(uuid, text), private.dating_profiles_display_name_guard()
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

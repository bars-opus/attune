-- Spec 2 W1d, migration 9 (spec §4.9 W1d #1, §3.12, §4.3, §4.4, §5.2
-- filter 13; 10 S5): "Never introduce me to these numbers" (data and RPCs;
-- the screen is W5c).
--   * dating_never_introduce: the owner's list of phone HMACs (never the
--     number), with an optional private label (<= 20) and the last two
--     digits for the list row; at most 50 per owner.
--   * add_dating_never_introduce(key, phone, label): the same "added"
--     answer whatever the number (whether anyone uses it, whether it was
--     already listed), so the list can't test who uses Attune. Adding never
--     changes what the owner can see (batch-9 fix round 1, I-1): an
--     introduction already shown stays until the owner passes or it
--     expires; filter 13 keeps the pair from ever matching or being
--     introduced again (W5a/W5b gates).
--   * remove_dating_never_introduce(id), list_dating_never_introduce().
--   * dating_never_introduce_excludes(a, b): the hard-filter helper, both
--     directions (W5a's filter 13 calls it).
--   * private.dating_typed_phone_e164(text) and its trunk-prefix table: the
--     typed number in E.164, as account phones are (fix round 1, I-2).
-- Nobody on a list is ever told. Grants in
-- 20261106180010_dating_v2_never_introduce_grants.sql.
-- Batch 9 rulings (Task 11) and fix round 1:
--   * Typed numbers are validated as E.164 here (W1 B1 M2): Unicode spaces,
--     dots, dashes and brackets go, 00 is +, and a trunk 0 typed after the
--     calling code goes where that country dials one (+233 0244 -> +233 244,
--     +44 (0)7700 -> +44 7700), as the app's sign-in parser does for account
--     phones; a 0 after the code that can't be judged is refused ("check the
--     number"), never "Added." under an HMAC that can't match. The result is
--     hashed through dating_phone_canonical, the transform consume_fresh_start
--     and dating_phone_hmac_for_user use, so the HMACs match.
--   * No phone oracle: nothing in add reads who uses a number or touches an
--     introduction; the answer and the work done are the same for a member's
--     number and a stranger's. Additions are rate-limited (60 a day; invalid
--     input and replays aren't counted).
--   * Only HMACs are stored: a label may not hold a number (5+ digits, any
--     script's digits folded by private.normalize_for_filter), control
--     characters or invisible marks; nothing logs the number.
--   * The exclusion key must be ready (set, fingerprint seeded and matching)
--     or add answers the generic feature_unavailable, counted, and writes
--     nothing (W1 B5 I-1); the helper fails closed (excludes) without it.
--   * Adding is exposure-reducing: never gated on setup eligibility or the
--     device check (W1 B8 ruling), but it needs a Dating profile in any
--     state (fix round 1, M-1). Removing raises exposure, so it keeps the
--     §4.4 device check, as does the list.
--   * An idempotency key is bound to the number (a hash of its HMAC in the
--     claim's operation): a replay answers "added" (even past the daily
--     limit), a reused key with another number is refused (M-3, M-4).
--   * Locks: the per-person setup lock first (the shared order: setup ->
--     same-gender -> rows); it also serialises the 50 cap.
--   * A listed number only stops introductions (Spec 1 O3): no eligibility,
--     standing or moderation path reads this table; Task 12's exit and W9's
--     export are its only other readers (the contract's tripwire lists them).
--   * No API role reads the table, the service role included (M-5): every
--     server reader goes through a SECURITY DEFINER function.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.dating_never_introduce (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  phone_hmac text NOT NULL CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  label text CHECK (label IS NULL OR char_length(label) BETWEEN 1 AND 20),
  last_two char(2) NOT NULL CHECK (last_two ~ '^[0-9]{2}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (owner_user_id, phone_hmac)
);
CREATE INDEX IF NOT EXISTS dating_never_introduce_hmac_idx ON public.dating_never_introduce (phone_hmac);
ALTER TABLE public.dating_never_introduce ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.dating_never_introduce IS
  'Spec 2 §3.12: numbers (as HMACs) the owner is never introduced to. Kept at exit only if the owner ticks "Keep my list" (R-2); deleted with the account. Read only through SECURITY DEFINER functions: its three RPCs, the filter helper, Task 12''s exit and W9''s export (an introduction filter only, Spec 1 O3).';

-- Where a country dials a trunk 0 before the national number (fix round 1,
-- I-2). One row per calling code; codes are prefix-free (ITU E.164), and
-- every one- and two-digit code is listed, so an unlisted code has three
-- digits. after_code_zero: 'strip' (a trunk 0 typed after the code is
-- dropped; national numbers never start with 0), 'keep' (the 0 is part of
-- the number, e.g. Italy), 'refuse' (no trunk 0 there, so a 0 after the
-- code is a mistake). Extended when a country opens (W5c, with its picker).
CREATE TABLE IF NOT EXISTS private.dating_phone_trunk_rules (
  calling_code text PRIMARY KEY CHECK (calling_code ~ '^[1-9][0-9]{0,2}$'),
  after_code_zero text NOT NULL CHECK (after_code_zero IN ('strip', 'keep', 'refuse'))
);
ALTER TABLE private.dating_phone_trunk_rules ENABLE ROW LEVEL SECURITY;
INSERT INTO private.dating_phone_trunk_rules (calling_code, after_code_zero)
SELECT c, 'strip' FROM unnest(ARRAY[
  '20', '27', '31', '32', '33', '40', '41', '43', '44', '46', '49', '51', '53', '58', '60', '61', '62', '63', '64',
  '66', '81', '82', '84', '86', '90', '91', '92', '93', '94', '95', '98',
  '211', '212', '213', '218', '231', '232', '233', '234', '249', '250', '251', '254', '255', '256', '260', '263',
  '265', '353', '358', '380', '880', '961', '962', '963', '964', '966', '967', '970', '971', '972', '977']) AS c
UNION ALL
SELECT c, 'refuse' FROM unnest(ARRAY[
  '1', '7', '30', '34', '36', '45', '47', '48', '52', '54', '55', '56', '57', '65',
  '216', '220', '221', '222', '223', '224', '226', '227', '228', '235', '237', '257', '267', '268', '269',
  '351', '352', '375', '852', '853', '965', '968', '973', '974', '993', '998']) AS c
UNION ALL
SELECT c, 'keep' FROM unnest(ARRAY['39', '225', '229', '241', '242', '378']) AS c
ON CONFLICT (calling_code) DO UPDATE SET after_code_zero = EXCLUDED.after_code_zero;

-- A typed number in E.164 ('+' and 8-15 digits), or NULL when it isn't one
-- or a 0 after its calling code can't be judged. Never logs or raises.
CREATE OR REPLACE FUNCTION private.dating_typed_phone_e164(p_text text)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v text;
  v_code text;
  v_rule text;
  v_rest text;
BEGIN
  v := pg_catalog.regexp_replace(
    pg_catalog.regexp_replace(p_text COLLATE "pg_c_utf8", '[[:space:]().-]', '', 'g'), '^00', '+');
  -- With no '+' the calling code is unknown (the final check refuses any
  -- other shape).
  IF starts_with(v, '+') IS NOT TRUE THEN
    RETURN NULL;
  END IF;
  v := substr(v, 2);
  SELECT r.calling_code, r.after_code_zero INTO v_code, v_rule
    FROM private.dating_phone_trunk_rules AS r
   WHERE starts_with(v, r.calling_code);
  IF v_code IS NULL THEN
    -- An unlisted code has three digits: a 0 straight after it can't be judged.
    IF substr(v, 4, 1) = '0' THEN
      RETURN NULL;
    END IF;
  ELSE
    v_rest := substr(v, char_length(v_code) + 1);
    IF v_rule = 'strip' AND starts_with(v_rest, '0') THEN
      v_rest := substr(v_rest, 2);
    END IF;
    IF v_rule <> 'keep' AND starts_with(v_rest, '0') THEN
      RETURN NULL;
    END IF;
    v := v_code || v_rest;
  END IF;
  IF (v ~ '^[1-9][0-9]{7,14}$') IS NOT TRUE THEN
    RETURN NULL;
  END IF;
  RETURN '+' || v;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.add_dating_never_introduce(p_idempotency_key text, p_phone_e164 text, p_label text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_phone text;
  v_label text;
  v_hmac text;
  v_op text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Exposure-reducing (W1 B8 ruling): no eligibility or device gate. The
  -- setup lock (shared order) serialises the cap and the write.
  PERFORM private.dating_lock_setup(v_user);
  -- In Dating: a profile in any state (fix round 1, M-1; §4.8 keeps the
  -- list while the owner is in Dating).
  IF NOT EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;

  -- The number in E.164, as account phones are (W1 B1 M2; fix round 1,
  -- I-2); NULL, malformed or unjudgeable is invalid ("check the number").
  v_phone := private.dating_typed_phone_e164(p_phone_e164);
  IF v_phone IS NULL THEN
    RETURN private.dating_invalid('phone');
  END IF;

  -- The label: private to the owner, at most 20 after trimming; never a
  -- number (only HMACs are kept: 5+ digits of any script, folded by the
  -- shared normaliser), a control character or an invisible mark.
  v_label := nullif(private.dating_trim(p_label), '');
  IF v_label IS NOT NULL
     AND (char_length(v_label) > 20
          OR v_label ~ '[[:cntrl:]]'
          OR private.dating_has_invisible(v_label)
          OR char_length(pg_catalog.regexp_replace(private.normalize_for_filter(v_label), '[^0-9]', '', 'g')) >= 5) THEN
    RETURN private.dating_invalid('label');
  END IF;

  -- The exclusion key must be ready (W1 B5 I-1): else the generic reason,
  -- counted, nothing claimed or written.
  v_hmac := public.dating_phone_hmac(public.dating_phone_canonical(v_phone));
  IF v_hmac IS NULL OR private.dating_exclusion_key_ready() IS NOT TRUE THEN
    PERFORM private.bump_metric_internal('dating.never_introduce.key_not_ready');
    RETURN jsonb_build_object('ok', false, 'reason', 'feature_unavailable');
  END IF;

  -- The key is bound to this number (fix round 1, M-3, M-4): each add
  -- claims it twice, unbound and under a hash of the HMAC (never the
  -- number). A replay is "added" before the rate limit; the key reused for
  -- another number is refused. Both are exact primary-key lookups, so the
  -- work never depends on the number.
  v_op := 'add_dating_never_introduce:' || left(md5(v_hmac), 12);
  IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS i
              WHERE i.user_id = v_user AND i.operation = v_op AND i.idempotency_key = p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'message', 'added');
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS i
              WHERE i.user_id = v_user AND i.operation = 'add_dating_never_introduce'
                AND i.idempotency_key = p_idempotency_key) THEN
    RETURN private.dating_invalid('idempotency_key');
  END IF;

  BEGIN
    PERFORM public.check_dating_rate_limit('never_introduce_add', 60, interval '1 day');
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
      RAISE;
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
  END;

  IF (SELECT count(*) FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_user) >= 50
     AND NOT EXISTS (SELECT 1 FROM public.dating_never_introduce AS n
                      WHERE n.owner_user_id = v_user AND n.phone_hmac = v_hmac) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'limit_reached');
  END IF;
  -- Neither claim exists (checked above, under the setup lock).
  PERFORM public.claim_dating_idempotency('add_dating_never_introduce', p_idempotency_key);
  PERFORM public.claim_dating_idempotency(v_op, p_idempotency_key);

  INSERT INTO public.dating_never_introduce AS n (owner_user_id, phone_hmac, label, last_two)
  VALUES (v_user, v_hmac, v_label, right(v_phone, 2))
  ON CONFLICT (owner_user_id, phone_hmac) DO UPDATE SET label = coalesce(EXCLUDED.label, n.label);
  -- No introduction changes here (fix round 1, I-1): ending one at once would
  -- confirm whose number it is. Filter 13 (dating_never_introduce_excludes)
  -- keeps the pair from matching; the listed person stops seeing the pair
  -- at the next run, as a pass (W5a/W5b gates).
  RETURN jsonb_build_object('ok', true, 'message', 'added');
END;
$fn$;

CREATE OR REPLACE FUNCTION public.remove_dating_never_introduce(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM private.dating_lock_setup(v_user);
  -- Removing raises exposure: the §4.4 device check applies.
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  -- The same answer whether the row was the caller's, someone else's or none.
  DELETE FROM public.dating_never_introduce AS n WHERE n.id = p_id AND n.owner_user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.list_dating_never_introduce()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  RETURN jsonb_build_object('ok', true, 'items', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', n.id, 'label', n.label, 'last_two', n.last_two)
                     ORDER BY n.created_at, n.id)
      FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_user), '[]'::jsonb));
END;
$fn$;

-- Filter 13 (§5.2), both directions. Fails closed for a pair where either
-- side has a list: without a ready exclusion key, or when the other
-- person's HMAC can't be read, the pair is excluded.
CREATE OR REPLACE FUNCTION public.dating_never_introduce_excludes(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_a_lists constant boolean := EXISTS (SELECT 1 FROM public.dating_never_introduce AS n WHERE n.owner_user_id = p_a);
  v_b_lists constant boolean := EXISTS (SELECT 1 FROM public.dating_never_introduce AS n WHERE n.owner_user_id = p_b);
  v_hmac text;
BEGIN
  IF NOT v_a_lists AND NOT v_b_lists THEN
    RETURN false;
  END IF;
  IF private.dating_exclusion_key_ready() IS NOT TRUE THEN
    RETURN true;
  END IF;
  IF v_a_lists THEN
    v_hmac := public.dating_phone_hmac_for_user(p_b);
    IF v_hmac IS NULL OR EXISTS (SELECT 1 FROM public.dating_never_introduce AS n
                                  WHERE n.owner_user_id = p_a AND n.phone_hmac = v_hmac) THEN
      RETURN true;
    END IF;
  END IF;
  IF v_b_lists THEN
    v_hmac := public.dating_phone_hmac_for_user(p_a);
    IF v_hmac IS NULL OR EXISTS (SELECT 1 FROM public.dating_never_introduce AS n
                                  WHERE n.owner_user_id = p_b AND n.phone_hmac = v_hmac) THEN
      RETURN true;
    END IF;
  END IF;
  RETURN false;
END;
$fn$;

REVOKE ALL ON public.dating_never_introduce FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL (id, owner_user_id, phone_hmac, label, last_two, created_at)
  ON public.dating_never_introduce FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON private.dating_phone_trunk_rules FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_typed_phone_e164(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_never_introduce_excludes(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.add_dating_never_introduce(text, text, text), public.remove_dating_never_introduce(uuid),
  public.list_dating_never_introduce() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.add_dating_never_introduce(text, text, text), public.remove_dating_never_introduce(uuid),
  public.list_dating_never_introduce() TO authenticated;

COMMIT;

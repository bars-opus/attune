-- supabase/migrations/20261120110000_dating_v2_chat_safety.sql
-- Spec 2 W6b (§4.9 W6b, §6.1, §5.10, §3.13, §4.6, §7.1; chat spec §3, §4.1,
-- §6, §9, §10; carry 8): the dating chat's own safety pipeline. Each
-- message is queued (its own outbox, never the couples one); the worker
-- process-dating-safety-outbox claims it, runs the deterministic engine
-- (_shared/dating_chat_safety.ts on Spec 1's normaliser) against the active
-- dating_safety_configs row and completes it with the rules that fired;
-- events go to the recipient only (never message text); tier 2 and 3
-- families open a moderation case about the sender; repeated money asks,
-- repeated sexual pressure and a duplicate opener open signal cases (never
-- an automatic ban). Delivery never waits on any of it (fail-open); a
-- config that can't be read means no detection, never the couples config.
-- Message pushes: neutral me_update, at most one per 15 minutes. The
-- lexicon v1 is seeded as a draft (the dev script activates it); its
-- threat, sexual-pressure, harassment and identity sets are [DRAFT] until
-- the cultural reviewer's. No flag changes. Grants:
-- 20261120110010_dating_v2_chat_safety_grants.sql.
-- Final server fix (W6 final server review, 2026-11-21): a push sent in the
-- last 15 minutes delays the next to the window's end instead of dropping
-- it, with one copy helper (I-6, N-7); a config once activated stays
-- frozen (M-6); the worker is called only while a message waits (M-7);
-- the cascades are indexed (M-9); this migration revokes what it creates
-- (I-2).
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Tables.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dating_message_safety_outbox (
  message_id uuid PRIMARY KEY REFERENCES public.dating_messages (id) ON DELETE CASCADE,
  state text NOT NULL DEFAULT 'pending'
    CONSTRAINT dating_message_safety_outbox_state_check CHECK (state IN ('pending', 'processing', 'done', 'dead_letter')),
  attempts smallint NOT NULL DEFAULT 0,
  last_error_code text CONSTRAINT dating_message_safety_outbox_error_check CHECK (last_error_code IS NULL OR last_error_code ~ '^[a-z0-9_]{1,40}$'),
  processing_started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS dating_message_safety_outbox_pending_idx
  ON public.dating_message_safety_outbox (created_at) WHERE state = 'pending';
-- Fix round 1 (M-10): health counts the rows not done without scanning them.
CREATE INDEX IF NOT EXISTS dating_message_safety_outbox_open_idx
  ON public.dating_message_safety_outbox (state, created_at) WHERE state IN ('pending', 'processing', 'dead_letter');
ALTER TABLE public.dating_message_safety_outbox ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.dating_safety_configs (
  version text PRIMARY KEY CONSTRAINT dating_safety_configs_version_check CHECK (version ~ '^[a-z0-9_]{1,40}$'),
  state text NOT NULL DEFAULT 'draft'
    CONSTRAINT dating_safety_configs_state_check CHECK (state IN ('draft', 'active', 'retired')),
  config jsonb NOT NULL,
  config_hash text NOT NULL,
  review_ref text,
  activated_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dating_safety_configs_active_check CHECK (state <> 'active' OR (review_ref IS NOT NULL AND activated_at IS NOT NULL))
);
-- Fix round 2 (N-3): the read guard's unread check by the high member
-- (the low member is served by dating_matches_active_pair_idx).
CREATE INDEX IF NOT EXISTS dating_matches_high_active_idx ON public.dating_matches (user_high_id) WHERE state = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS dating_safety_configs_one_active_idx ON public.dating_safety_configs ((true)) WHERE state = 'active';
ALTER TABLE public.dating_safety_configs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.dating_safety_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid REFERENCES public.dating_matches (id) ON DELETE SET NULL,
  message_id uuid REFERENCES public.dating_messages (id) ON DELETE SET NULL,
  -- Fix round 1 (M-7): a recipient's deletion keeps the evidence about the
  -- sender (no one at risk any more; §4.8 anonymises at 90 days, W6c).
  at_risk_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  sender_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  rule_id text NOT NULL CONSTRAINT dating_safety_events_rule_check CHECK (char_length(rule_id) BETWEEN 1 AND 120),
  family text NOT NULL CONSTRAINT dating_safety_events_family_check CHECK (family IN (
    'sexual_pressure', 'harassment_abuse', 'contact_migration_pressure', 'meet_private_pressure', 'threat_intimidation',
    'financial_request', 'sextortion', 'child_access', 'age_signal', 'identity_inconsistency')),
  tier smallint NOT NULL CONSTRAINT dating_safety_events_tier_check CHECK (tier BETWEEN 1 AND 3),
  config_version text NOT NULL,
  source_event_key text NOT NULL CONSTRAINT dating_safety_events_source_key UNIQUE,
  dismissed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS dating_safety_events_match_idx ON public.dating_safety_events (match_id, at_risk_user_id);
CREATE INDEX IF NOT EXISTS dating_safety_events_sender_idx ON public.dating_safety_events (sender_user_id, family, created_at);
-- Final server fix (M-9): an account's deletion sets at_risk_user_id to
-- NULL through an index.
CREATE INDEX IF NOT EXISTS dating_safety_events_at_risk_idx ON public.dating_safety_events (at_risk_user_id);
ALTER TABLE public.dating_safety_events ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.dating_opener_hashes (
  sender_user_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  match_id uuid NOT NULL REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  hash text NOT NULL CONSTRAINT dating_opener_hashes_hash_check CHECK (hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (sender_user_id, match_id)
);
CREATE INDEX IF NOT EXISTS dating_opener_hashes_hash_idx ON public.dating_opener_hashes (sender_user_id, hash, created_at);
-- Final server fix (M-9): a match's delete finds its hashes through an index.
CREATE INDEX IF NOT EXISTS dating_opener_hashes_match_idx ON public.dating_opener_hashes (match_id);
ALTER TABLE public.dating_opener_hashes ENABLE ROW LEVEL SECURITY;

-- The chat's tier 2 and 3 families open their own signal kinds (§6.1).
ALTER TABLE public.dating_moderation_cases DROP CONSTRAINT IF EXISTS dating_moderation_cases_signal_kind_check;
ALTER TABLE public.dating_moderation_cases ADD CONSTRAINT dating_moderation_cases_signal_kind_check CHECK (
  signal_kind IS NULL OR signal_kind IN ('dragnet', 'duplicate_opener', 'money_asks', 'sexual_pressure', 'location_mismatch',
    'device_accounts', 'chat_threat_intimidation', 'chat_financial_request', 'chat_sextortion', 'chat_child_access',
    'chat_age_signal', 'chat_identity_inconsistency'));

-- ---------------------------------------------------------------------
-- 2. The config: one active version; a version is never edited while
--    active (a change is a new version, W5 final M-7); in production a
--    DEV- review reference can't activate (as introductions_v2).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_safety_config_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Final server fix (M-6): frozen from its first activation for good, a
  -- retired version too (it can't be edited and brought back under the
  -- same name; a change is a new version), and its activation can't be
  -- wiped to unfreeze it.
  IF TG_OP = 'UPDATE' AND OLD.activated_at IS NOT NULL
     AND (NEW.config IS DISTINCT FROM OLD.config OR NEW.config_hash IS DISTINCT FROM OLD.config_hash
          OR NEW.version IS DISTINCT FROM OLD.version OR NEW.activated_at IS NULL) THEN
    RAISE EXCEPTION 'config:active_frozen' USING ERRCODE = '23514';
  END IF;
  IF NEW.config_hash IS DISTINCT FROM pg_catalog.encode(extensions.digest(NEW.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'config:hash_mismatch' USING ERRCODE = '23514';
  END IF;
  -- Fix round 2 (N-2): every term is stored in the form the engine emits
  -- (Spec 1's match form; the base form for a "base" family), or no hit of
  -- the version could ever be taken (complete checks rule ids against it).
  IF (TG_OP = 'INSERT' OR NEW.config IS DISTINCT FROM OLD.config)
     AND EXISTS (SELECT 1
                   FROM pg_catalog.jsonb_each(CASE WHEN pg_catalog.jsonb_typeof(NEW.config -> 'families') = 'object'
                                                   THEN NEW.config -> 'families' ELSE '{}'::jsonb END) AS f,
                        LATERAL pg_catalog.jsonb_array_elements(
                          CASE WHEN pg_catalog.jsonb_typeof(f.value -> 'terms') = 'array' THEN f.value -> 'terms' ELSE '[]'::jsonb END
                          || CASE WHEN pg_catalog.jsonb_typeof(f.value -> 'new_match_terms') = 'array'
                                  THEN f.value -> 'new_match_terms' ELSE '[]'::jsonb END) AS t(term)
                  WHERE pg_catalog.jsonb_typeof(t.term) <> 'string'
                     OR (t.term #>> '{}') IS DISTINCT FROM
                        CASE WHEN f.value ->> 'form' = 'base' THEN private.normalize_for_filter(t.term #>> '{}')
                             ELSE private.match_form(t.term #>> '{}') END) THEN
    RAISE EXCEPTION 'config:term_form' USING ERRCODE = '23514';
  END IF;
  IF NEW.state = 'active' AND private.attune_environment() IS NOT DISTINCT FROM 'production'
     AND pg_catalog.upper(pg_catalog.btrim(coalesce(NEW.review_ref, ''), E' \t\r\n')) LIKE 'DEV-%' THEN
    RAISE EXCEPTION 'config:dev_review_ref' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_safety_config_guard ON public.dating_safety_configs;
CREATE TRIGGER dating_safety_config_guard BEFORE INSERT OR UPDATE ON public.dating_safety_configs
  FOR EACH ROW EXECUTE FUNCTION private.dating_safety_config_guard();

-- The v1 lexicon (supabase/functions/_shared/dating_chat_lexicon_v1.json,
-- exactly): §6.1's terms, each stored in Spec 1's match form (age_signal
-- in its base form); "new_match_terms" fire only in a match's first 14
-- days (chat spec §3.3). A draft until activated with a review reference.
INSERT INTO public.dating_safety_configs (version, state, config, config_hash)
SELECT 'dating_chat_v1', 'draft', c.config, pg_catalog.encode(extensions.digest(c.config::text, 'sha256'), 'hex')
  FROM (SELECT $lex${"version": "dating_chat_v1", "new_match_days": 14, "families": {"financial_request": {"tier": 2, "form": "match", "terms": ["mobile money", "momo number", "send me momo", "credit me", "top me up", "recharge card", "buy me data", "send me small", "money for transport", "customs fee", "clearing fee", "release fee", "gift card", "itunes card", "steam card", "western union", "moneygram", "bitcoin", "btc", "usdt", "crypto", "forex", "investment platform", "trading account", "double your money", "i sent it by mistake", "send it back", "wrong transfer", "reverse the money", "abeg send", "dash me", "help me with small", "my account is blocked", "my card is blocked"], "new_match_terms": ["momo", "airtime", "data bundle", "small money", "transport fare", "t fare", "school fees", "hospital bill", "on admission", "sika"]}, "sextortion": {"tier": 2, "form": "match", "terms": ["video call naked", "i have your video", "i will post your pictures", "i ll send it to your family", "send to your contacts", "expose you", "make it viral", "leak your", "pay or i", "unless you pay"], "new_match_terms": []}, "contact_migration_pressure": {"tier": 1, "form": "match", "terms": ["add me on whatsapp", "my whatsapp is", "let s move to telegram", "this app is not safe", "i don t use this app much"], "new_match_terms": ["text me on", "call me on", "snap me", "dm me on ig"]}, "meet_private_pressure": {"tier": 1, "form": "match", "terms": ["come to my place", "come to my house", "i m home alone", "come over tonight", "my room", "i ll send my location", "meet me at my hotel"], "new_match_terms": []}, "child_access": {"tier": 2, "form": "match", "terms": ["send a picture of your daughter", "send a picture of your son", "how old are your kids", "what school do your children attend", "when are the kids alone", "can i meet your children alone", "do you leave them with"], "new_match_terms": []}, "age_signal": {"tier": 3, "form": "base", "terms": ["i m in form 2", "shs", "jhs", "after bece", "my wassce", "housemistress", "my class teacher", "year 10", "year 11", "gcses", "sixth form", "i m 15", "i m 16", "i m 17", "im 15", "im 16", "im 17", "i am 15", "i am 16", "i am 17"], "new_match_terms": []}, "threat_intimidation": {"tier": 2, "form": "match", "terms": ["i will hurt you", "i know where you live", "you will regret this", "i will find you", "watch your back", "i will kill you", "i go deal with you"], "new_match_terms": [], "draft": true}, "sexual_pressure": {"tier": 1, "form": "match", "terms": ["send nudes", "send me nudes", "send me a sexy picture", "show me your body", "take off your clothes", "let s have sex", "i want to sleep with you"], "new_match_terms": [], "draft": true}, "harassment_abuse": {"tier": 1, "form": "match", "terms": ["you are so stupid", "you are ugly", "useless woman", "useless man", "shut up you idiot", "nobody will ever love you"], "new_match_terms": [], "draft": true}, "identity_inconsistency": {"tier": 3, "form": "match", "terms": ["i am a us soldier", "i am on a peacekeeping mission", "i work on an oil rig", "i am a widower raising my child alone", "my late wife", "i am a un doctor"], "new_match_terms": [], "draft": true}}}$lex$::jsonb AS config) AS c
ON CONFLICT (version) DO NOTHING;

-- The active config, for the worker (the service role's): NULL when none
-- is active (no detection; never the couples config).
CREATE OR REPLACE FUNCTION public.get_dating_safety_config()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT pg_catalog.jsonb_build_object('version', c.version, 'config', c.config)
    FROM public.dating_safety_configs AS c WHERE c.state = 'active';
$$;

-- ---------------------------------------------------------------------
-- 3. The worker's three calls (the service role's).
-- ---------------------------------------------------------------------
-- Claims up to [p_limit] (1-100) pending messages: each moves to
-- processing with one more attempt. The only way a body leaves the
-- database (S-5); the match's age says whether its first days apply (the
-- active config's new_match_days, 14 when none is active or it is unset).
CREATE OR REPLACE FUNCTION public.claim_dating_safety_jobs(p_limit integer DEFAULT 50)
RETURNS TABLE (message_id uuid, body text, new_match boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_days integer;
BEGIN
  SELECT CASE WHEN c.config ->> 'new_match_days' ~ '^[0-9]{1,3}$' THEN (c.config ->> 'new_match_days')::integer END
    INTO v_days FROM public.dating_safety_configs AS c WHERE c.state = 'active';
  v_days := coalesce(v_days, 14);
  RETURN QUERY
  WITH picked AS (
    SELECT o.message_id FROM public.dating_message_safety_outbox AS o
     WHERE o.state = 'pending'
     ORDER BY o.created_at
     LIMIT least(greatest(coalesce(p_limit, 50), 1), 100)
     FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.dating_message_safety_outbox AS o
       SET state = 'processing', attempts = o.attempts + 1, processing_started_at = clock_timestamp()
      FROM picked WHERE o.message_id = picked.message_id
    RETURNING o.message_id
  )
  SELECT d.id, d.body, d.created_at < m.matched_at + make_interval(days => v_days)
    FROM claimed JOIN public.dating_messages AS d ON d.id = claimed.message_id
    JOIN public.dating_matches AS m ON m.id = d.match_id;
END;
$$;

-- Opens (or keeps) the sender's open case of [p_signal] about this match.
CREATE OR REPLACE FUNCTION private.dating_open_chat_case(p_sender uuid, p_match uuid, p_signal text, p_priority text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_opened boolean;
BEGIN
  v_opened := private.dating_open_signal_case(p_sender, p_signal, p_priority);
  IF v_opened THEN
    UPDATE public.dating_moderation_cases AS c SET match_id = p_match
     WHERE c.target_user_id = p_sender AND c.kind = 'signal' AND c.signal_kind = p_signal
       AND c.state IN ('open', 'in_review') AND c.match_id IS NULL;
  END IF;
  RETURN v_opened;
END;
$$;

-- Completes a claimed message. With [p_error] (a code), it goes back to
-- pending, or to dead_letter after its 5th attempt (counted). Otherwise
-- each hit ({rule_id, family, tier}) becomes an event for the recipient
-- only (once per message and rule; never the text); tier 2 and 3 open a
-- case about the sender (§6.1); then the sender's repeated signals
-- (§5.10, carry 8). [p_version] NULL: no config was active (no detection,
-- counted). Never raises for a message that is gone (purged meanwhile).
CREATE OR REPLACE FUNCTION public.complete_dating_safety_job(p_message_id uuid, p_version text, p_hits jsonb,
                                                            p_error text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_d public.dating_messages;
  v_m public.dating_matches;
  v_to uuid;
  v_from uuid;
  v_attempts smallint;
  h jsonb;
  v_family text;
  v_tier integer;
  v_events integer := 0;
  v_hash text;
  v_cfg jsonb;
  v_fin boolean := false;
  v_sex boolean := false;
BEGIN
  IF p_message_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT o.attempts INTO v_attempts FROM public.dating_message_safety_outbox AS o
   WHERE o.message_id = p_message_id AND o.state = 'processing' FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_claimed');
  END IF;
  IF p_error IS NOT NULL THEN
    UPDATE public.dating_message_safety_outbox AS o
       SET state = CASE WHEN v_attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
           last_error_code = CASE WHEN p_error ~ '^[a-z0-9_]{1,40}$' THEN p_error ELSE 'worker_error' END,
           processing_started_at = NULL
     WHERE o.message_id = p_message_id;
    IF v_attempts >= 5 THEN
      PERFORM private.bump_metric_internal('dating.safety.dead_letter');
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', true, 'state', CASE WHEN v_attempts >= 5 THEN 'dead_letter' ELSE 'pending' END);
  END IF;
  -- Its own IF first: an OR has no order, and the elements of a non-array raise.
  IF jsonb_typeof(coalesce(p_hits, '[]'::jsonb)) <> 'array' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- A version names a stored config, and each hit's tier is its family's
  -- tier there (a hit can't skip its case); a hit with no family is invalid
  -- (NULL NOT IN is NULL: coalesced), never a raise that holds the message.
  IF p_version IS NOT NULL THEN
    SELECT c.config INTO v_cfg FROM public.dating_safety_configs AS c WHERE c.version = p_version;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_hits, '[]'::jsonb)) AS x
              WHERE jsonb_typeof(x) <> 'object' OR coalesce(x ->> 'family', '') NOT IN ('sexual_pressure', 'harassment_abuse',
                      'contact_migration_pressure', 'meet_private_pressure', 'threat_intimidation', 'financial_request',
                      'sextortion', 'child_access', 'age_signal', 'identity_inconsistency')
                 OR coalesce(x ->> 'tier', '') NOT IN ('1', '2', '3')
                 OR (x ->> 'tier') IS DISTINCT FROM (v_cfg #>> ARRAY['families', x ->> 'family', 'tier'])
                 -- Fix round 1 (M-5): the rule is its family and one of that
                 -- version's terms, never free text (no message words).
                 OR NOT EXISTS (
                      SELECT 1 FROM jsonb_array_elements_text(
                               CASE WHEN jsonb_typeof(v_cfg #> ARRAY['families', x ->> 'family', 'terms']) = 'array'
                                    THEN v_cfg #> ARRAY['families', x ->> 'family', 'terms'] ELSE '[]'::jsonb END
                               || CASE WHEN jsonb_typeof(v_cfg #> ARRAY['families', x ->> 'family', 'new_match_terms']) = 'array'
                                       THEN v_cfg #> ARRAY['families', x ->> 'family', 'new_match_terms'] ELSE '[]'::jsonb END) AS t(term)
                       WHERE (x ->> 'family') || ':' || t.term = x ->> 'rule_id')
                 OR coalesce(pg_catalog.char_length(x ->> 'rule_id'), 0) NOT BETWEEN 1 AND 120)
     OR (p_version IS NULL AND jsonb_array_length(coalesce(p_hits, '[]'::jsonb)) > 0) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT * INTO v_d FROM public.dating_messages AS d WHERE d.id = p_message_id;
  SELECT * INTO v_m FROM public.dating_matches AS m WHERE m.id = v_d.match_id;
  v_from := v_d.sender_user_id;
  v_to := CASE WHEN v_d.sender_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
  IF p_version IS NULL THEN
    PERFORM private.bump_metric_internal('dating.safety.no_config');
  END IF;
  FOR h IN SELECT x FROM jsonb_array_elements(coalesce(p_hits, '[]'::jsonb)) AS x LOOP
    v_family := h ->> 'family';
    v_tier := (h ->> 'tier')::integer;
    -- Fix round 1 (M-7): a recipient deleted meanwhile (v_to NULL) still
    -- leaves the evidence and the case about the sender; no card.
    INSERT INTO public.dating_safety_events (match_id, message_id, at_risk_user_id, sender_user_id, rule_id, family, tier,
                                             config_version, source_event_key)
    VALUES (v_d.match_id, p_message_id, v_to, v_from, h ->> 'rule_id', v_family, v_tier, p_version,
            p_message_id::text || ':' || (h ->> 'rule_id'))
    ON CONFLICT (source_event_key) DO NOTHING;
    IF FOUND THEN
      v_events := v_events + 1;
      v_fin := v_fin OR v_family = 'financial_request';
      v_sex := v_sex OR v_family = 'sexual_pressure';
      IF v_tier <= 2 AND v_to IS NOT NULL THEN
        PERFORM private.bump_metric_internal('dating.card.' || v_family);
        -- Task 7 fix round 1: the recipient's open chat reads again and
        -- shows the card (the sender's chat learns nothing).
        PERFORM private.dating_bump_chat(v_to, v_d.match_id);
      END IF;
      IF v_tier >= 2 AND v_from IS NOT NULL THEN
        PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'chat_' || v_family,
          CASE WHEN v_family = 'identity_inconsistency' THEN 'P2' ELSE 'P1' END);
      END IF;
    END IF;
  END LOOP;
  -- §5.10 (carry 8): the sender's repeated patterns, each a signal case.
  -- Fix round 1 (I-1): each pattern is checked only when this completion
  -- added its evidence (the opener: the side's first message), so the case
  -- names the match that holds it; evidence a moderator's decision
  -- postdates never counts again (W5c's dating_signal_cleared, per item):
  -- a decision sticks, and only fresh evidence opens a new case. A deleted
  -- recipient still counts once (by match, else by event; M-7).
  IF v_from IS NOT NULL THEN
    IF v_fin AND (SELECT count(DISTINCT coalesce(e.at_risk_user_id::text, 'm:' || e.match_id::text, 'e:' || e.id::text))
                    FROM public.dating_safety_events AS e
                   WHERE e.sender_user_id = v_from AND e.family = 'financial_request' AND e.created_at > now() - interval '7 days'
                     AND NOT private.dating_signal_cleared(v_from, 'money_asks', e.created_at)) >= 2 THEN
      PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'money_asks', 'P1');
    END IF;
    IF v_sex AND (SELECT count(DISTINCT coalesce(e.at_risk_user_id::text, 'm:' || e.match_id::text, 'e:' || e.id::text))
                    FROM public.dating_safety_events AS e
                   WHERE e.sender_user_id = v_from AND e.family = 'sexual_pressure' AND e.created_at > now() - interval '7 days'
                     AND NOT private.dating_signal_cleared(v_from, 'sexual_pressure', e.created_at)) >= 2 THEN
      PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'sexual_pressure', 'P2');
    END IF;
    -- Fix round 2 (N-1): the side's first text message (send keeps that
    -- one's opener), whatever guided answers came before it.
    IF v_d.kind = 'text' AND NOT EXISTS (SELECT 1 FROM public.dating_messages AS d2
                    WHERE d2.match_id = v_d.match_id AND d2.sender_side = v_d.sender_side AND d2.kind = 'text'
                      AND (d2.created_at, d2.id) < (v_d.created_at, v_d.id)) THEN
      SELECT k.hash INTO v_hash FROM public.dating_opener_hashes AS k WHERE k.sender_user_id = v_from AND k.match_id = v_d.match_id;
      IF v_hash IS NOT NULL
         AND (SELECT count(DISTINCT k.match_id) FROM public.dating_opener_hashes AS k
               WHERE k.sender_user_id = v_from AND k.hash = v_hash AND k.created_at > now() - interval '7 days'
                 AND NOT private.dating_signal_cleared(v_from, 'duplicate_opener', k.created_at)) >= 3 THEN
        PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'duplicate_opener', 'P2');
      END IF;
    END IF;
  END IF;
  UPDATE public.dating_message_safety_outbox AS o
     SET state = 'done', completed_at = clock_timestamp(), processing_started_at = NULL, last_error_code = NULL
   WHERE o.message_id = p_message_id;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'state', 'done', 'events', v_events);
END;
$$;

-- §4.6 recover-stale-dating-workers: a message held in processing for 10
-- minutes (a worker that died) goes back to pending; one already claimed
-- 5 times goes to dead_letter (counted), so a message that never completes
-- can't cycle for ever.
CREATE OR REPLACE FUNCTION public.recover_stale_dating_safety_jobs()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_n integer;
  v_dead integer;
BEGIN
  WITH r AS (
    UPDATE public.dating_message_safety_outbox AS o
       SET state = CASE WHEN o.attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
           last_error_code = CASE WHEN o.attempts >= 5 THEN 'stale_claim' ELSE o.last_error_code END,
           processing_started_at = NULL
     WHERE o.state = 'processing' AND o.processing_started_at < now() - interval '10 minutes'
    RETURNING o.state
  )
  SELECT count(*), count(*) FILTER (WHERE r.state = 'dead_letter') INTO v_n, v_dead FROM r;
  PERFORM private.bump_metric_internal('dating.safety.dead_letter') FROM pg_catalog.generate_series(1, v_dead);
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------------
-- 4. The recipient's cards (§3.6 Safety cards, §6.1): the caller's own
--    tier 1 and 2 events in their match, not dismissed, each with the
--    resource its copy names from S1 W7a's support_resources for the
--    caller's Dating country (emergency first; sextortion); dismissing
--    hides one card and never changes detection.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_card_resource(p_country text, p_family text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT pg_catalog.jsonb_build_object('name', r.name, 'phone', r.phone, 'sms', r.sms, 'url', r.url)
    FROM public.support_resources AS r
   WHERE r.active AND r.country_code IN (p_country, 'XX')
     AND r.category = CASE p_family WHEN 'sextortion' THEN 'sextortion' ELSE 'emergency' END
   ORDER BY (r.country_code = 'XX'), r.sort_order, r.name, r.id
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_my_dating_safety_cards(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_country text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'cards', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'id', e.id, 'message_id', e.message_id, 'family', e.family,
             'resource', CASE WHEN e.family IN ('threat_intimidation', 'sextortion')
                              THEN private.dating_card_resource(v_country, e.family) END)
             ORDER BY e.created_at, e.id)
      FROM public.dating_safety_events AS e
     WHERE e.match_id = p_match_id AND e.at_risk_user_id = v_user AND e.tier <= 2 AND e.dismissed_at IS NULL
       AND EXISTS (SELECT 1 FROM public.dating_matches AS m WHERE m.id = e.match_id AND v_user IN (m.user_low_id, m.user_high_id))),
    '[]'::jsonb));
END;
$$;

-- Never device-gated (it only hides a card); one answer for any id.
CREATE OR REPLACE FUNCTION public.dismiss_dating_safety_card(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  UPDATE public.dating_safety_events AS e SET dismissed_at = coalesce(e.dismissed_at, now())
   WHERE e.id = p_event_id AND e.at_risk_user_id = auth.uid();
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------
-- 5. A message's push (§3.13): the neutral me_update, queued with the
--    unread message, at most one per 15 minutes per person (R-42): the
--    source key is keyed by the quarter hour; a push still to be sent
--    stands for this one, and one sent in the last 15 minutes delays it to
--    the end of that window (final server fix, I-6: delayed, never
--    dropped; skipped at the claim if everything is read by then); only
--    with "messages" on (dating_settings.chat_push, on by default). Quiet
--    hours fold it through the push queue. Never raises: a push that can't
--    be queued is counted and the message is delivered.
-- ---------------------------------------------------------------------
-- Final server fix (I-6, W6b N-7): the copy of Dating's me_update pushes,
-- one place: dating_queue_me_update writes it, the chat push's hold reads
-- it ('new' is the chat push's and the digest's).
CREATE OR REPLACE FUNCTION private.dating_me_update_body(p_kind text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE p_kind
    WHEN 'notify' THEN 'Something you asked about is ready in Attune.'
    WHEN 'new' THEN 'You have something new in Attune.'
  END;
$$;

-- Final server fix (I-6): a me_update push due at [p_at] (now or later);
-- its key is keyed by the day of [p_at]. The three-argument form below
-- (W3a's, every earlier caller) is this one at now().
CREATE OR REPLACE FUNCTION private.dating_queue_me_update(p_user uuid, p_purpose text, p_kind text, p_at timestamptz)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_body constant text := private.dating_me_update_body(p_kind);
  v_n integer;
BEGIN
  IF p_user IS NULL OR p_purpose IS NULL OR v_body IS NULL OR p_at IS NULL THEN
    RAISE EXCEPTION 'dating:invalid_push' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  VALUES (p_user, 'immediate', p_at, 'pending',
          pg_catalog.jsonb_build_object('type', 'me_update', 'route', 'me', 'title', 'Attune', 'body', v_body),
          private.dating_push_source_key(p_user, p_purpose, (p_at AT TIME ZONE 'UTC')::date), now(), now())
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$$;

CREATE OR REPLACE FUNCTION private.dating_queue_me_update(p_user uuid, p_purpose text, p_kind text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Spec 2 W6b (final server fix, I-6, N-7): the copy and the insert live in the four-argument form.
  RETURN private.dating_queue_me_update(p_user, p_purpose, p_kind, now()); -- Spec 2 W6b
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_queue_chat_push(p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_q constant bigint := pg_catalog.floor(extract(epoch FROM now()) / 900)::bigint;
  v_sent timestamptz;
  v_at timestamptz;
  v_k bigint;
BEGIN
  IF p_user IS NULL OR coalesce((SELECT s.chat_push FROM public.dating_settings AS s WHERE s.user_id = p_user), true) IS NOT TRUE THEN
    RETURN;
  END IF;
  -- Fix round 3 (overnight burst, R-42): a "You have something new" push
  -- still unsent (held to 08:00 by quiet hours, due, or waiting for the end
  -- of a window below) or being sent already says it: no second one. That
  -- copy is the chat push's and the digest's (fix round 4, N-6); a notify
  -- push ("Something you asked about is ready") says something else and
  -- holds nothing. A claim stuck for 15 minutes no longer holds pushes back.
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications AS n
              WHERE n.user_id = p_user AND n.metadata ->> 'type' = 'me_update'
                AND n.metadata ->> 'body' = private.dating_me_update_body('new') -- final server fix (N-7): one copy
                AND (n.status = 'pending' OR (n.status = 'processing' AND n.updated_at > now() - interval '15 minutes'))) THEN
    RETURN;
  END IF;
  -- Final server fix (I-6, R-42): one sent in the last 15 minutes (fix
  -- round 4, I-4: counted from its send, updated_at) delays this push, never
  -- drops it: one trailing push is queued for the end of that window, so a
  -- message that came inside it is still pushed if it is unread by then
  -- (the read guard skips it otherwise). Its own key, by the quarter hour it
  -- is due in (this quarter's chat key may be the sent one's); one that was
  -- skipped as read comes back.
  SELECT max(n.updated_at) INTO v_sent FROM public.scheduled_notifications AS n
   WHERE n.user_id = p_user AND n.metadata ->> 'type' = 'me_update'
     AND n.metadata ->> 'body' = private.dating_me_update_body('new')
     AND n.status = 'sent' AND n.updated_at > now() - interval '15 minutes';
  IF v_sent IS NOT NULL THEN
    v_at := v_sent + interval '15 minutes';
    v_k := pg_catalog.floor(extract(epoch FROM v_at) / 900)::bigint;
    UPDATE public.scheduled_notifications AS n
       SET status = 'pending', last_error = NULL, scheduled_for = v_at, updated_at = now(), created_at = now()
     WHERE n.source_key = private.dating_push_source_key(p_user, 'chat:' || v_k::text || ':t', (v_at AT TIME ZONE 'UTC')::date)
       AND n.status = 'skipped' AND n.last_error = 'dating_chat_read';
    IF NOT FOUND THEN
      PERFORM private.dating_queue_me_update(p_user, 'chat:' || v_k::text || ':t', 'new', v_at);
    END IF;
    RETURN;
  END IF;
  -- Fix round 2 (I-2): this quarter hour's push skipped as read comes back
  -- for the new unread message (its key is taken: a new one can't queue).
  UPDATE public.scheduled_notifications AS n
     -- Fix round 3 (I-3): its 15 minutes count from this message (R-42).
     SET status = 'pending', last_error = NULL, scheduled_for = now(), updated_at = now(), created_at = now()
   WHERE n.source_key = private.dating_push_source_key(p_user, 'chat:' || v_q::text, (now() AT TIME ZONE 'UTC')::date)
     AND n.status = 'skipped' AND n.last_error = 'dating_chat_read';
  IF FOUND THEN
    RETURN;
  END IF;
  PERFORM private.dating_queue_me_update(p_user, 'chat:' || v_q::text, 'new');
EXCEPTION WHEN OTHERS THEN
  PERFORM private.bump_metric_internal('dating.chat.push_failed');
END;
$$;

-- Fix round 1 (M-11, §3.13 "while something is unread"): at the push
-- worker's claim (pending -> processing, the hook the quiet-hours guard
-- also uses; this trigger fires first by name), a message push whose
-- person has nothing unread in any active match any more (they read it in
-- the chat, or it waited out quiet hours) is skipped. A message push is
-- known by its opaque key alone (the chat purpose of its own quarter
-- hour); every other push, Dating's other me_update pushes included, is
-- untouched. Never raises: in doubt the push goes.
CREATE OR REPLACE FUNCTION private.dating_chat_push_read_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_q bigint;
BEGIN
  -- The trigger's WHEN already limits this to a claim of a me_update push.
  IF NEW.source_key IS NULL OR NEW.created_at IS NULL THEN
    RETURN NEW;
  END IF;
  -- A message push's key: its own quarter hour's (chat:<q>), or (final
  -- server fix, I-6) a trailing push's, keyed by the quarter hour it is due
  -- in, which is the one it was queued in or the next (chat:<q>:t).
  v_q := pg_catalog.floor(extract(epoch FROM NEW.created_at) / 900)::bigint;
  IF NEW.source_key IS DISTINCT FROM private.dating_push_source_key(NEW.user_id, 'chat:' || v_q::text,
       (NEW.created_at AT TIME ZONE 'UTC')::date)
     AND NEW.source_key IS DISTINCT FROM private.dating_push_source_key(NEW.user_id, 'chat:' || v_q::text || ':t',
       (pg_catalog.to_timestamp(v_q * 900) AT TIME ZONE 'UTC')::date)
     AND NEW.source_key IS DISTINCT FROM private.dating_push_source_key(NEW.user_id, 'chat:' || (v_q + 1)::text || ':t',
       (pg_catalog.to_timestamp((v_q + 1) * 900) AT TIME ZONE 'UTC')::date) THEN
    RETURN NEW;
  END IF;
  -- Fix round 2 (N-3): one indexed lookup per side (no scan of matches).
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches AS m
                  WHERE m.user_low_id = NEW.user_id AND m.state = 'active'
                    AND EXISTS (SELECT 1 FROM public.dating_messages AS d
                                 WHERE d.match_id = m.id AND d.sender_side = 'high'
                                   AND d.created_at > coalesce(m.low_seen_at, '-infinity'::timestamptz)))
     AND NOT EXISTS (SELECT 1 FROM public.dating_matches AS m
                      WHERE m.user_high_id = NEW.user_id AND m.state = 'active'
                        AND EXISTS (SELECT 1 FROM public.dating_messages AS d
                                     WHERE d.match_id = m.id AND d.sender_side = 'low'
                                       AND d.created_at > coalesce(m.high_seen_at, '-infinity'::timestamptz))) THEN
    NEW.status := 'skipped';
    NEW.last_error := 'dating_chat_read';
    PERFORM private.bump_metric_internal('dating.chat.push_read');
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS scheduled_notifications_dating_read_guard ON public.scheduled_notifications;
-- Fix round 2 (N-3): it fires only for the worker's claim of a Dating
-- me_update push (every Dating key starts 'me_update:'); no other push
-- runs it. The chat-key test stays in the body: a WHEN function would run
-- with the worker's privileges.
CREATE TRIGGER scheduled_notifications_dating_read_guard BEFORE UPDATE OF status ON public.scheduled_notifications
  FOR EACH ROW
  WHEN (OLD.status = 'pending' AND NEW.status = 'processing' AND (NEW.metadata ->> 'type') = 'me_update'
        AND NEW.source_key LIKE 'me_update:%')
  EXECUTE FUNCTION private.dating_chat_push_read_guard();

-- §5.10: the sender's opener, keyed (the exclusion key over the match
-- form), never the words; the first message per side only.
CREATE OR REPLACE FUNCTION private.dating_opener_hash(p_body text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_key constant text := public.app_setting('dating_exclusion_key');
BEGIN
  IF coalesce(v_key, '') = '' OR p_body IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN pg_catalog.encode(extensions.hmac('dating_opener|' || private.match_form(p_body), v_key, 'sha256'), 'hex');
END;
$$;

-- The crons (§4.6): the worker every minute, the stale-job recovery every
-- five.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.unschedule(j.jobid) FROM cron.job AS j
     WHERE j.jobname IN ('process-dating-safety-outbox', 'recover-stale-dating-workers');
    -- Final server fix (M-7): the worker is called only when a message waits
    -- (none with Dating off: no empty calls, no failures before its deploy).
    PERFORM cron.schedule('process-dating-safety-outbox', '* * * * *',
                          $c$SELECT public.invoke_edge_function('process-dating-safety-outbox') WHERE EXISTS (SELECT 1 FROM public.dating_message_safety_outbox WHERE state = 'pending')$c$);
    PERFORM cron.schedule('recover-stale-dating-workers', '*/5 * * * *',
                          $c$SELECT public.recover_stale_dating_safety_jobs()$c$);
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 6. Functions re-created from their live bodies; only the lines marked
--    "-- Spec 2 W6b" change.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.send_dating_message(p_idempotency_key text, p_match_id uuid, p_body text, p_kind text DEFAULT 'text'::text, p_question_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_other uuid;
  v_msg public.dating_messages;
  v_masked text;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key)
     OR p_kind IS DISTINCT FROM 'text' OR p_question_id IS NOT NULL
     OR p_body IS NULL OR pg_catalog.btrim(p_body) = '' OR pg_catalog.char_length(p_body) > 1000 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF private.dating_body_blank(p_body) THEN -- fix round 1 (M-1): only blank or invisible characters
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
       FOR NO KEY UPDATE;
      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      v_other := CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
      -- A replay answers as the first did, whatever happened since.
      SELECT * INTO v_msg FROM public.dating_messages AS d
       WHERE d.match_id = p_match_id AND d.sender_side = v_side AND d.idempotency_key = p_idempotency_key;
      IF FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', true, 'message',
          private.dating_message_json(v_msg, v_side, v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL));
      END IF;
      IF public.dating_flag_enabled('dating_match_messaging') IS NOT TRUE THEN -- fix round 1 (I-2): the chat's flag (§4.10)
        -- Fix round 1b: messages are paused (an incident), the match has not ended.
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
      END IF;
      IF v_m.state <> 'active' OR v_other IS NULL OR public.dating_can_send(p_match_id) IS NOT TRUE THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason',
          CASE WHEN v_m.state = 'active' AND v_other IS NOT NULL AND public.dating_account_in_good_standing(v_user) IS NOT TRUE
               THEN 'restricted' ELSE 'closed' END);
      END IF;
      BEGIN
        PERFORM public.check_dating_rate_limit('dating_message', 500, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      v_masked := private.dating_mask_contacts_safe(p_body);
      INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, kind, question_id, body, body_masked,
                                          mask_version, idempotency_key)
      VALUES (p_match_id, v_side, v_user, 'text', NULL, p_body, v_masked, 1, p_idempotency_key)
      RETURNING * INTO v_msg;
      UPDATE public.dating_matches AS m
         SET chat_started_at = coalesce(m.chat_started_at, now()),
             low_seen_at = CASE WHEN v_side = 'low' THEN clock_timestamp() ELSE m.low_seen_at END,
             high_seen_at = CASE WHEN v_side = 'high' THEN clock_timestamp() ELSE m.high_seen_at END
       WHERE m.id = p_match_id;
      PERFORM private.dating_bump_chat(v_other, p_match_id);
      INSERT INTO public.dating_message_safety_outbox (message_id) VALUES (v_msg.id); -- Spec 2 W6b (§6.1)
      IF NOT EXISTS (SELECT 1 FROM public.dating_opener_hashes AS k -- Spec 2 W6b (§5.10): the side's first message
                      WHERE k.sender_user_id = v_user AND k.match_id = p_match_id) -- Spec 2 W6b
         AND private.dating_opener_hash(p_body) IS NOT NULL THEN -- Spec 2 W6b
        INSERT INTO public.dating_opener_hashes (sender_user_id, match_id, hash) -- Spec 2 W6b
        VALUES (v_user, p_match_id, private.dating_opener_hash(p_body)) ON CONFLICT DO NOTHING; -- Spec 2 W6b
      END IF; -- Spec 2 W6b
      PERFORM private.dating_queue_chat_push(v_other); -- Spec 2 W6b (§3.13)
      IF v_masked IS DISTINCT FROM p_body THEN
        PERFORM private.bump_metric_internal('dating.mask_hit');
      END IF;
      RETURN pg_catalog.jsonb_build_object('ok', true, 'message',
        private.dating_message_json(v_msg, v_side, v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL));
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'dating_enabled',public.dating_flag_enabled('dating_mode_enabled'),
    'candidate_generation_enabled',public.dating_flag_enabled('dating_candidate_generation'),
    'exclusion_key_present',public.app_setting('dating_exclusion_key') IS NOT NULL,
    'relationships_ended_without_exclusion_24h',(
      SELECT count(*) FROM public.relationships r
      WHERE r.status = 'ended'
        AND r.ended_at >= now() - interval '24 hours'
        AND NOT EXISTS (
          SELECT 1 FROM public.dating_former_partner_exclusions e
          WHERE e.relationship_id = r.id
        )
    ),
    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),
    'introductions_config',(private.dating_intro_config()).o_version, -- Spec 2 W5a (§5.5): NULL = generation refuses
    'generation_by_country',(SELECT coalesce(jsonb_object_agg(x.partition_key, jsonb_build_object( -- Spec 2 W5a (§4.4 health v2)
                               'cohort', x.cohort_window, 'state', x.state, 'attempts', x.attempts)), '{}'::jsonb) -- Spec 2 W5a
                             FROM (SELECT DISTINCT ON (r.partition_key) r.partition_key, r.cohort_window, r.state, r.attempts -- Spec 2 W5a
                                     FROM public.dating_generation_runs AS r WHERE r.created_at >= now() - interval '36 hours' -- Spec 2 W5a
                                    ORDER BY r.partition_key, r.created_at DESC) AS x), -- Spec 2 W5a
    'stuck_generation_runs',(SELECT count(*) FROM public.dating_generation_runs WHERE state='processing' AND started_at < now()-interval '30 minutes'),
    'failed_generation_runs_24h',(SELECT count(*) FROM public.dating_generation_runs WHERE state IN ('failed','dead_letter') AND created_at >= now()-interval '24 hours'),
    'expired_open_introductions',(SELECT count(*) FROM public.dating_introductions WHERE state IN ('generated','presented','interested') AND expires_at <= now()),
    'pending_bio_moderation',(SELECT count(*) FROM public.dating_profiles WHERE moderation_state='pending'),
    'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending'),
    'environment',private.attune_environment(), -- Spec 2 W1d
    'field_key_present',private.dating_field_key_present(), -- Spec 2 W1d
    -- Spec 2 W1d (§2.4): nothing can write an RPC's parameters to the log.
    'log_settings_safe',coalesce(current_setting('log_statement', true) IN ('none', 'ddl')
      AND (current_setting('log_min_duration_statement', true) = '-1'
           OR current_setting('log_parameter_max_length', true) = '0')
      AND current_setting('log_parameter_max_length_on_error', true) = '0', false),
    'enabled_countries',to_jsonb(private.dating_open_countries()), -- Spec 2 W1d
    'age_assurance_mode',private.dating_verification_mode(), -- Spec 2 W4a
    'verification_awaiting_review',(SELECT count(*) FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    'verification_oldest_waiting_hours',(SELECT floor(extract(epoch FROM now() - min(coalesce(awaiting_since, updated_at))) / 3600)::int -- Spec 2 W4a (fix round 1, M-8)
                                           FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    -- Spec 2 W1d (B2 I-5, B5 M-4, B6 M-5): each key set and its stored
    -- Spec 2 W1d fingerprint equal (read only; never the counting mismatch()).
    'exclusion_key_fingerprint_ok',private.dating_exclusion_key_ready(), -- Spec 2 W1d
    'field_key_fingerprint_ok',private.dating_field_key_ready(), -- Spec 2 W1d
    'safety_counters_7d',(SELECT jsonb_object_agg(k.key, coalesce((SELECT sum(c.count) FROM public.metric_counters c -- Spec 2 W1d
                            WHERE c.key = k.key AND c.day >= (now() AT TIME ZONE 'utc')::date - 6), 0)) -- Spec 2 W1d
      FROM unnest(ARRAY['dating.deletion.uncarried', 'dating.exclusion_key.mismatch', 'dating.exclusion_key.unseeded', -- Spec 2 W1d
                        'dating.eligibility.key_not_ready', 'dating.field_key.mismatch', 'dating.field_key.missing', -- Spec 2 W1d
                        'dating.parked_pause.failed', -- Spec 2 W1d (fix round 1, M-5)
                        'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2
                        'dating.gates.failed', 'dating.gentle_wait.undated', -- Spec 2 W2 (Task 3 carry: W2 batch 1 fix round 1, M-4 and M-3)
                        'dating.path_pause.swept', -- Spec 2 W2 (Task 3 fix round 1, I-1)
                        'dating.gentle_wait.seen', 'dating.gentle_wait.account_deleted_7d', -- Spec 2 W2 (migration 3, §6.9)
                        'dating.gentle_wait.clear_busy', 'dating.gentle_wait.seen_skipped', 'dating.home.unreadable_field', -- Spec 2 W2 (migration 3 fix round 1)
                        'dating.kill_switch.pending', 'dating.kill_switch.unreadable', -- Spec 2 W1d (migration 11)
                        'dating.verify.sweep_failed', 'dating.verify.id_review_expired', -- Spec 2 W4a (fix round 1, M-7)
                        'dating.deletion.prepare_carry_failed', 'dating.deletion.late_carry_failed', -- W1 final fix (M-4); -- Spec 2 W5a: and
                        'dating.generation.skipped', 'dating.generation.failed', 'dating.generation.unreadable', -- Spec 2 W5a
                        'dating.generation.busy', -- Spec 2 W5a (Task 2 fix round 2, N-3); -- Spec 2 W5c: and
                        'dating.signal.failed', 'dating.signal.busy', 'dating.fairness.unreadable', -- Spec 2 W5c (fix round 1, I-2, M-1, M-5); -- Spec 2 W5 final: and
                        'dating.digest.push_key_missing', 'dating.digest.failed', -- Spec 2 W5 final (M-5, M-3); Spec 2 W6b: the list goes on
                        'dating.pair_marker.unwritten', 'dating.safety.no_config', 'dating.safety.dead_letter', -- Spec 2 W6b
                        'dating.chat.push_failed', 'dating.chat.push_read']) AS k(key)), -- Spec 2 W6b (fix round 1, M-11: push_read)
    -- Spec 2 W6b (chat spec §10): the chat's safety outbox and its events.
    'chat_safety_outbox',(SELECT jsonb_build_object( -- Spec 2 W6b
                            'pending', count(*) FILTER (WHERE o.state = 'pending'), -- Spec 2 W6b
                            'processing', count(*) FILTER (WHERE o.state = 'processing'), -- Spec 2 W6b
                            'dead_letter', (SELECT count(*) FROM public.dating_message_safety_outbox AS x WHERE x.state = 'dead_letter'), -- Spec 2 W6b (fix round 1, M-10)
                            'oldest_pending_seconds', coalesce(floor(extract(epoch FROM now() - min(o.created_at) FILTER (WHERE o.state = 'pending'))), 0)) -- Spec 2 W6b
                          FROM public.dating_message_safety_outbox AS o WHERE o.state IN ('pending', 'processing')), -- Spec 2 W6b (fix round 1, M-10): done rows never read
    'chat_safety_config_active',(SELECT c.version FROM public.dating_safety_configs AS c WHERE c.state = 'active'), -- Spec 2 W6b
    'chat_safety_events_24h',(SELECT coalesce(jsonb_object_agg(x.family, x.n), '{}'::jsonb) FROM ( -- Spec 2 W6b
                                SELECT e.family, count(*) AS n FROM public.dating_safety_events AS e -- Spec 2 W6b
                                 WHERE e.created_at >= now() - interval '24 hours' GROUP BY e.family) AS x), -- Spec 2 W6b
    -- Spec 2 W5a (Task 2 fix round 2, N-3): people left out over the bound, per country, 7 days
    'generation_truncated_7d',(SELECT coalesce(jsonb_object_agg(x.country, x.n), '{}'::jsonb) FROM ( -- Spec 2 W5a
                                 SELECT substr(c.key, char_length('dating.generation.truncated.') + 1) AS country, sum(c.count) AS n -- Spec 2 W5a
                                   FROM public.metric_counters AS c -- Spec 2 W5a
                                  WHERE left(c.key, char_length('dating.generation.truncated.')) = 'dating.generation.truncated.' -- Spec 2 W5a
                                    AND c.day >= (now() AT TIME ZONE 'utc')::date - 6 -- Spec 2 W5a
                                  GROUP BY 1) AS x), -- Spec 2 W5a
    -- W1 final fix (M-4): app deletions refused for a missing exclusion key
    -- W1 final fix (delete-account records prepare's message) in 7 days.
    'deletions_refused_key_missing_7d',(SELECT count(*) FROM public.account_deletion_requests AS r -- W1 final fix (M-4)
                                         WHERE r.completed_at IS NULL AND r.requested_at >= now() - interval '7 days' -- W1 final fix (M-4)
                                           AND r.failure_reason LIKE '%deletion:enforcement_key_missing%'), -- W1 final fix (M-4)
    -- Spec 2 W1d (fix round 1, I-1): every purge still pending, until a switch clears it.
    'kill_switch_pending',(SELECT coalesce(jsonb_agg(jsonb_build_object('scope', k.scope, 'since', k.first_failed_at, -- Spec 2 W1d
                             'sqlstate', k.last_sqlstate, 'attempts', k.attempts) ORDER BY k.scope), '[]'::jsonb) -- Spec 2 W1d
                           FROM private.dating_kill_switch_pending k) -- Spec 2 W1d
  );
$function$;

-- ---------------------------------------------------------------------
-- 7. Final server fix (I-2): a split push fails closed. Every object this
--    migration creates is revoked here, in its own transaction, from
--    PUBLIC, anon, authenticated and the service role; its twin
--    (20261120110010) then grants the worker's calls to the service role
--    and the cards to the app. Re-created functions keep their grants.
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE public.dating_message_safety_outbox, public.dating_safety_configs, public.dating_safety_events,
  public.dating_opener_hashes FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  private.dating_safety_config_guard(), public.get_dating_safety_config(), public.claim_dating_safety_jobs(integer),
  private.dating_open_chat_case(uuid, uuid, text, text), public.complete_dating_safety_job(uuid, text, jsonb, text),
  public.recover_stale_dating_safety_jobs(), private.dating_card_resource(text, text),
  public.get_my_dating_safety_cards(uuid), public.dismiss_dating_safety_card(uuid), private.dating_me_update_body(text),
  private.dating_queue_me_update(uuid, text, text, timestamptz), private.dating_queue_chat_push(uuid),
  private.dating_chat_push_read_guard(), private.dating_opener_hash(text)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

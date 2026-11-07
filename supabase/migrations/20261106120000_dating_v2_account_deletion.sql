-- Spec 2 W1a, migration 3 (spec §4.9 W1a #3, §6.3, R5; S-2; batch-3 fix
-- round 1: I-1, I-2, M-2, M-3, M-7):
--   * private.dating_restriction_hmacs: each Dating restriction's phone HMAC,
--     stamped when the restriction is placed (AFTER INSERT trigger, from
--     dating_phone_hmac_for_user: auth.users, or the pre-park HMAC). The
--     carry-over writes a restriction's enforcement record under THAT HMAC,
--     never the number the account holds at deletion: that number is the
--     account's to change (one OTP on someone else's SIM), and a restriction
--     must never land on an uninvolved person's number (I-1, coordinator
--     ruling; cost: a person who changes number after being restricted is
--     not followed onto the new number). A restriction placed while
--     dating_exclusion_key was missing has no stamp until
--     private.dating_stamp_restriction_hmacs() runs (this migration runs it
--     when the key is set; owner checklist: run it after setting the key);
--     an unstamped restriction carries nothing and the deletion counts
--     dating.deletion.uncarried (PF-F6).
--   * private.dating_deletion_carry(user, final): steps 1, 2 and 4 of §6.3
--     (enforcement records, block pairs, report HMACs), idempotent. Blocks
--     and reports still use the number held at deletion (no stamp exists for
--     them yet; W7a stamps report targets at filing). Former-partner
--     exclusions are not re-recorded: the rows written when the relationship
--     ended stand (I-1).
--   * prepare_account_deletion re-created from its live body
--     (20261018110000_chapters_deletion.sql; identical to pg_get_functiondef
--     on attune_spec3a) with only the lines marked "Spec 2 W1a": a missing
--     key with a live restriction refuses ('deletion:enforcement_key_missing',
--     PF-F6); then the carry runs: any other failure in it is caught,
--     warned and counted dating.deletion.prepare_carry_failed, and the
--     deletion goes on (W1 final fix, M-4: only the owner-controlled key
--     state may refuse a deletion; this replaces batch 3's M-3 refusal, and
--     the auth.users trigger carries again at the delete); then the matches close and seal (a
--     failure there warns and counts: the cascade trigger
--     dating_matches_close_on_member_delete seals them anyway).
--   * dating_carry_on_auth_user_delete: BEFORE DELETE ON auth.users runs the
--     same carry again (final), so anything written between prepare and
--     deleteUser still carries (I-2). It never raises (a failure counts
--     dating.deletion.late_carry_failed); new rows written there count
--     dating.deletion.late_carry. Only this final pass counts
--     dating.deletion.uncarried (once per deleted account, M-2) and, for an
--     account with a Dating footprint, dating.exclusion_key.mismatch or
--     dating.exclusion_key.unseeded. It reads the stored fingerprint and
--     never stores one (M-7).
--   * The restriction's category and the reports' state are read by name
--     (to_jsonb), so W7a's new columns fill confirmed_report_count and
--     category with no change here; until then they are 0 and NULL.
--   * The server metric prefix 'dating.' (owner spec2); no client key.
--   * W1 final fix (M-8): a restriction's user_id never changes
--     (dating_account_restrictions_user_immutable, BEFORE UPDATE OF user_id;
--     raises dating:restriction_user_immutable, 55000).
-- Grants in 20261106120010_dating_v2_account_deletion_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- I-1: the HMAC each restriction was placed under. No API role reads or
-- writes it (revoked here and in the twin); only definer functions do.
CREATE TABLE IF NOT EXISTS private.dating_restriction_hmacs (
  restriction_id uuid PRIMARY KEY REFERENCES public.dating_account_restrictions (id) ON DELETE CASCADE,
  phone_hmac text NOT NULL CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  stamped_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.dating_restriction_hmacs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.dating_restriction_hmacs FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON TABLE private.dating_restriction_hmacs IS
  'Spec 2 W1a (I-1): the phone HMAC of the number a Dating restriction was placed under. prepare_account_deletion carries the restriction under it, never under the number held at deletion.';

CREATE OR REPLACE FUNCTION private.dating_stamp_restriction_on_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_hmac constant text := public.dating_phone_hmac_for_user(NEW.user_id);
BEGIN
  -- No key (or a parked account without its pre-park HMAC): no stamp; the
  -- restriction carries nothing at deletion unless stamped later.
  IF v_hmac IS NOT NULL THEN
    INSERT INTO private.dating_restriction_hmacs (restriction_id, phone_hmac)
    VALUES (NEW.id, v_hmac)
    ON CONFLICT (restriction_id) DO NOTHING;
  END IF;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS dating_account_restrictions_stamp_hmac ON public.dating_account_restrictions;
CREATE TRIGGER dating_account_restrictions_stamp_hmac
  AFTER INSERT ON public.dating_account_restrictions
  FOR EACH ROW EXECUTE FUNCTION private.dating_stamp_restriction_on_insert();

-- Spec 2 W1 final fix (M-8, batch 3 N-M3): a restriction never moves to
-- another account (its stamp is the first account's number, so a moved
-- restriction would carry onto the wrong person). Place a new one instead.
CREATE OR REPLACE FUNCTION private.dating_restriction_user_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'dating:restriction_user_immutable' USING ERRCODE = '55000';
END;
$function$;

DROP TRIGGER IF EXISTS dating_account_restrictions_user_immutable ON public.dating_account_restrictions;
CREATE TRIGGER dating_account_restrictions_user_immutable
  BEFORE UPDATE OF user_id ON public.dating_account_restrictions
  FOR EACH ROW
  WHEN (OLD.user_id IS DISTINCT FROM NEW.user_id)
  EXECUTE FUNCTION private.dating_restriction_user_immutable();

-- Stamps the restrictions placed while the key was missing, from the number
-- each account holds now (run once the key is in Vault, before Dating opens).
-- -1 without the key; otherwise the number stamped. Idempotent.
CREATE OR REPLACE FUNCTION private.dating_stamp_restriction_hmacs()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_n integer;
BEGIN
  IF public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN
    RAISE NOTICE 'dating_exclusion_key is not set: no restriction stamped';
    RETURN -1;
  END IF;
  INSERT INTO private.dating_restriction_hmacs (restriction_id, phone_hmac)
  SELECT x.id, x.hmac
    FROM (SELECT dar.id, public.dating_phone_hmac_for_user(dar.user_id) AS hmac
            FROM public.dating_account_restrictions AS dar
           WHERE NOT EXISTS (SELECT 1 FROM private.dating_restriction_hmacs AS s WHERE s.restriction_id = dar.id)) AS x
   WHERE x.hmac IS NOT NULL
  ON CONFLICT (restriction_id) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- §6.3 steps 1, 2 and 4 for [p_user]; idempotent (every write is ON CONFLICT
-- DO NOTHING or fills only what is unset, except purge_after, which is reset
-- to deletion + 2 years as §6.3 step 2 says). Returns the number of new rows
-- (records, pairs, pairs given a purge date, report HMACs). Raises on any
-- failure; the auth.users trigger catches that. [p_final]: the trigger's
-- pass at the actual deletion, which alone counts.
CREATE OR REPLACE FUNCTION private.dating_deletion_carry(p_user uuid, p_final boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_hmac constant text := public.dating_phone_hmac_for_user(p_user);
  v_n integer := 0;
  v_rows integer;
  v_live_fp text;
  v_stored_fp text;
BEGIN
  IF p_user IS NULL THEN
    RETURN 0;
  END IF;
  -- 1. Each live restriction becomes an enforcement record (once), under the
  --    HMAC stamped when it was placed (I-1).
  INSERT INTO public.enforcement_records (phone_hmac, scope, source_restriction_id, restriction_type,
                                          category, confirmed_report_count, effect_until, purge_after)
  SELECT s.phone_hmac, 'dating', dar.id, dar.restriction_type, to_jsonb(dar) ->> 'category',
         (SELECT count(*) FROM public.dating_reports AS r
           WHERE r.target_user_id = p_user AND to_jsonb(r) ->> 'state' = 'upheld')::int,
         dar.ends_at, now() + interval '2 years'
    FROM public.dating_account_restrictions AS dar
    JOIN private.dating_restriction_hmacs AS s ON s.restriction_id = dar.id
   WHERE dar.user_id = p_user AND dar.lifted_at IS NULL
     AND (dar.ends_at IS NULL OR dar.ends_at > now())
  ON CONFLICT (source_restriction_id) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_n := v_n + v_rows;
  IF v_hmac IS NOT NULL THEN
    -- 2. Block pairs by number, kept 2 years from now.
    INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
    SELECT h.blocker, h.blocked
      FROM (SELECT public.dating_phone_hmac_for_user(b.blocker_user_id) AS blocker,
                   public.dating_phone_hmac_for_user(b.blocked_user_id) AS blocked
              FROM public.dating_blocks AS b
             WHERE p_user IN (b.blocker_user_id, b.blocked_user_id)) AS h
     WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
    ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_n := v_n + v_rows;
    v_n := v_n + (SELECT count(*)::int FROM public.dating_block_hmacs AS p
                   WHERE v_hmac IN (p.blocker_hmac, p.blocked_hmac) AND p.purge_after IS NULL);
    UPDATE public.dating_block_hmacs
       SET purge_after = now() + interval '2 years'
     WHERE v_hmac IN (blocker_hmac, blocked_hmac);
    -- 4. Reports about the person keep the number's HMAC (the cascade sets
    --    reporter and target ids to NULL); an HMAC already there is kept.
    UPDATE public.dating_reports AS r
       SET target_phone_hmac = v_hmac
     WHERE r.target_user_id = p_user AND r.target_phone_hmac IS NULL;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_n := v_n + v_rows;
  END IF;

  IF p_final THEN
    -- A live restriction with no stamp could not carry (PF-F6): counted
    -- once, at the deletion itself.
    IF EXISTS (SELECT 1 FROM public.dating_account_restrictions AS dar
                WHERE dar.user_id = p_user AND dar.lifted_at IS NULL
                  AND (dar.ends_at IS NULL OR dar.ends_at > now())
                  AND NOT EXISTS (SELECT 1 FROM private.dating_restriction_hmacs AS s
                                   WHERE s.restriction_id = dar.id)) THEN
      PERFORM private.bump_metric_internal('dating.deletion.uncarried');
    END IF;
    -- The key the survivors were written under, for an account with a
    -- Dating footprint: read, never stored (M-7).
    v_live_fp := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1');
    IF v_live_fp IS NOT NULL AND (
         EXISTS (SELECT 1 FROM public.dating_account_restrictions AS dar WHERE dar.user_id = p_user)
         OR EXISTS (SELECT 1 FROM public.dating_blocks AS b WHERE p_user IN (b.blocker_user_id, b.blocked_user_id))
         OR EXISTS (SELECT 1 FROM public.dating_reports AS r WHERE r.target_user_id = p_user)) THEN
      SELECT k.fingerprint INTO v_stored_fp
        FROM private.dating_key_fingerprints AS k WHERE k.name = 'dating_exclusion_key';
      IF v_stored_fp IS NULL THEN
        PERFORM private.bump_metric_internal('dating.exclusion_key.unseeded');
      ELSIF v_stored_fp IS DISTINCT FROM v_live_fp THEN
        PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch');
      END IF;
    END IF;
  END IF;
  RETURN v_n;
END;
$function$;

-- I-2: the carry again at the deletion itself (the auth row and everything
-- below it are still there in a BEFORE ROW trigger). Never raises.
CREATE OR REPLACE FUNCTION private.dating_carry_on_auth_user_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  BEGIN
    IF private.dating_deletion_carry(OLD.id, true) > 0 THEN
      PERFORM private.bump_metric_internal('dating.deletion.late_carry');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.deletion.late_carry_failed');
  END;
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS dating_carry_on_auth_user_delete ON auth.users;
CREATE TRIGGER dating_carry_on_auth_user_delete
  BEFORE DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION private.dating_carry_on_auth_user_delete();

CREATE OR REPLACE FUNCTION public.prepare_account_deletion(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_rel record;
  v_key_set boolean; -- Spec 2 W1a (PF-F6)
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'deletion:no_user';
  END IF;

  -- Spec 2 W1a (§6.3, R5): Dating carry-over, before anything is deleted.
  -- A missing key with a live restriction refuses (retried once the key is
  -- in Vault, PF-F6). The carry (records under each restriction's stamped
  -- HMAC, block pairs, report HMACs) runs; a failure there is counted and
  -- never refuses (W1 final fix, M-4). The auth.users trigger runs it again
  -- at the delete.
  v_key_set := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NOT NULL;
  IF NOT v_key_set AND EXISTS (
       SELECT 1 FROM public.dating_account_restrictions AS dar
        WHERE dar.user_id = p_user_id AND dar.lifted_at IS NULL
          AND (dar.ends_at IS NULL OR dar.ends_at > now())) THEN
    RAISE EXCEPTION 'deletion:enforcement_key_missing';
  END IF;
  -- Spec 2 W1 final fix (M-4, PF-F6): only the missing key refuses; any
  -- Spec 2 W1 final fix other carry failure is counted and the deletion goes
  -- Spec 2 W1 final fix on (the auth.users trigger carries again at the
  -- Spec 2 W1 final fix delete, counting late_carry_failed if that fails too).
  BEGIN -- Spec 2 W1 final fix (M-4)
    PERFORM private.dating_deletion_carry(p_user_id, false);
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W1 final fix (M-4)
    RAISE WARNING 'dating_deletion:carry:%', SQLSTATE; -- Spec 2 W1 final fix (M-4)
    PERFORM private.bump_metric_internal('dating.deletion.prepare_carry_failed'); -- Spec 2 W1 final fix (M-4)
  END; -- Spec 2 W1 final fix (M-4)
  -- 3. Matches close (account_deleted) and stay sealed for 30 days; the
  --    cascade sets their member ids to NULL (and its trigger seals any
  --    match this step missed, so a failure here warns and counts).
  BEGIN
    UPDATE public.dating_matches AS m
       SET state = CASE WHEN m.state = 'active' THEN 'closed' ELSE m.state END,
           closed_reason = CASE WHEN m.state = 'active' THEN 'account_deleted' ELSE m.closed_reason END,
           closed_at = coalesce(m.closed_at, now()),
           evidence_until = CASE WHEN m.state = 'active' OR m.evidence_until IS NULL
                                 THEN now() + interval '30 days' ELSE m.evidence_until END
     WHERE p_user_id IN (m.user_low_id, m.user_high_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'dating_deletion:matches:%', SQLSTATE;
    PERFORM private.bump_metric_internal('dating.deletion.step_failed.matches');
  END;
  -- 5. The cascade removes everything else (profile, photos via the media
  --    queue below, introductions, the never-introduce list, ...).

  FOR v_rel IN
    SELECT r.id, r.status FROM public.relationships r
    WHERE p_user_id IN (r.user_a, r.user_b)
    FOR UPDATE
  LOOP
    IF v_rel.status IN ('active', 'paused') THEN
      PERFORM public.relationship_end_internal(v_rel.id, p_user_id);
    ELSIF v_rel.status = 'pending' THEN
      DELETE FROM public.relationships WHERE id = v_rel.id;
      CONTINUE;
    END IF;

    -- What carries the person's answers or profile and cannot be split by
    -- person: games (positional answer_a/answer_b; rounds, per-user answers,
    -- Love map rounds and mirror truth go with them), 36-question journeys
    -- (AI text about the pair), the analysis sessions' role attribution, the
    -- profile-derived compatibility card. The partner's own game answers go
    -- with the shared sessions (D.3 #1 over D.2; review I1). Pulse,
    -- verdicts and patterns stay: role-free, both already saw them, the
    -- partner may export them in the window; the 12-month purge removes them.
    DELETE FROM public.game_sessions WHERE relationship_id = v_rel.id;
    DELETE FROM public.game_session_rounds WHERE relationship_id = v_rel.id;
    DELETE FROM public.thirty_six_question_journeys WHERE relationship_id = v_rel.id;
    DELETE FROM public.thirty_six_questions_seen WHERE relationship_id = v_rel.id;
    DELETE FROM public.game_questions_seen WHERE relationship_id = v_rel.id;
    DELETE FROM public.analysis_sessions WHERE relationship_id = v_rel.id;
    DELETE FROM public.attachment_compatibility_cache WHERE relationship_id = v_rel.id;
    DELETE FROM public.ask2_state WHERE relationship_id = v_rel.id;
  END LOOP;

  -- The person's own media. Their messages, clips and dating photos go in
  -- the cascade; queue now so nothing depends on trigger order there.
  PERFORM public.queue_media_deletion('message-media', m.media_url),
          public.queue_media_deletion('message-media', m.media_thumbnail_url)
  FROM public.messages m WHERE m.sender_id = p_user_id;
  PERFORM public.queue_media_deletion('message-media', c.media_url)
  FROM public.streak_clips c JOIN public.messages m ON m.id = c.message_id
  WHERE m.sender_id = p_user_id;
  PERFORM public.queue_media_deletion('dating-profile-photos', p.storage_key)
  FROM public.dating_profile_photos p WHERE p.user_id = p_user_id;
  -- Uploads never attached to anything: no row names them (review I5).
  PERFORM public.queue_media_deletion('message-media', i.storage_key)
  FROM public.message_media_upload_intents i WHERE i.requester_id = p_user_id;
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
  FROM public.dating_photo_upload_intents i WHERE i.user_id = p_user_id;
  PERFORM public.queue_media_deletion('story-media', i.storage_key)
  FROM public.story_media_upload_intents i WHERE i.requester_id = p_user_id;
  PERFORM public.queue_media_deletion('relationship-avatars', i.storage_key)
  FROM public.relationship_avatar_upload_intents i WHERE i.requester_id = p_user_id;
  -- Their downloads (Spec 3c; data_export_jobs is created in 20261018120000,
  -- resolved when this runs): every part of every job goes now, then the jobs.
  IF to_regclass('public.data_export_jobs') IS NOT NULL THEN
    EXECUTE $q$
      UPDATE public.media_deletion_queue q SET not_before = now(), deleted_at = NULL
      FROM public.data_export_jobs j
      WHERE j.user_id = $1 AND q.bucket_id = 'data-exports' AND q.object_name LIKE j.id::text || '/%'
    $q$ USING p_user_id;
    EXECUTE 'DELETE FROM public.data_export_jobs WHERE user_id = $1' USING p_user_id;
  END IF;
END;
$function$;

INSERT INTO public.metric_key_prefixes (prefix, owner_spec) VALUES ('dating.', 'spec2')
ON CONFLICT (prefix) DO NOTHING;

REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.dating_stamp_restriction_on_insert() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_stamp_restriction_hmacs() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_deletion_carry(uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_carry_on_auth_user_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_restriction_user_immutable() FROM PUBLIC, anon, authenticated, service_role; -- W1 final fix (M-8)

-- Restrictions placed before this migration (or while the key was missing):
-- stamped now if the key is set, else by the owner after setting it.
DO $$ BEGIN PERFORM private.dating_stamp_restriction_hmacs(); END $$;

COMMIT;

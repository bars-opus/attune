-- Spec 1 W9d, migration 1 (spec §10 O4, owner approval O4; review I-16;
-- Spec 2 §4.2 enforcement_records, §6.3): an Opinions strike count or live
-- ban survives account deletion, carried in enforcement_records (scope
-- 'opinions'), keyed by phone HMAC. Restored at sign-up by migration 2.
--   * private.opinion_enforcement_stamps: per account and phone HMAC, the
--     strikes and the latest ban placed while the account held that number.
--     admin_confirm_content_removal stamps each confirmed removal with
--     dating_phone_hmac_for_user at that moment, so a deletion carries a
--     strike under the number it was earned on, never a number the account
--     changes to later (S2 W1 B3 I-1, the phone-change attack). No HMAC
--     (key missing, no phone): no stamp, counted
--     opinions.enforcement.unstamped. A parked account (Spec 1 O3) is never
--     stamped, counted opinions.enforcement.parked_unstamped (batch-1
--     review M-3). A key whose fingerprint isn't ready still stamps under
--     the live key, counted opinions.enforcement.key_not_ready. A stamp
--     never fails the removal.
--   * private.opinion_stamp_backfill(): owner-run after every deploy of this
--     migration and again once the key is set (it also runs here): stamps
--     strikes and live bans no stamp covers (placed before W9d or while the
--     key was missing) under the number the account holds when it runs,
--     ONLY when the account's number provably hasn't changed since its
--     earliest removed post (coordinator ruling on batch-1 review M-1: a
--     victim's number never inherits a strike from before W9d). The proof
--     (final review M-2 ruling: Auth-side evidence only, never
--     public.users.updated_at, which W1's reconcile in the same push
--     rewrites for everyone): auth.users.phone_confirmed_at (Auth sets it
--     on every confirmed number change) no later than that removal, no
--     phone change requested since (auth.users.phone_change_sent_at, where
--     Auth has it), and at least as many removed posts as strikes (a
--     hard-deleted struck post hides when it was placed). An admin change
--     of number made without confirming it leaves no Auth evidence: the
--     owner checklist says never to make one before the backfill.
--     Anything else, a NULL included: not stamped, counted
--     opinions.enforcement.backfill_phone_unverified; the strike then
--     carries nothing (counted again at deletion: uncarried). Idempotent.
--   * private.opinion_deletion_carry(user, final): only a live ban or a
--     count above 0 carries (O4). The stamps give each record's HMAC; its
--     values are the account's CURRENT standing, capped by what was placed
--     under that number (batch-1 review I-1: a pardon or a lifted ban lowers
--     or removes what is carried): confirmed_report_count =
--     least(stamp strikes, current count), effect_until = least(stamp ban,
--     current live ban) when both are live (NULL: no ban; for scope
--     'opinions' NULL never means permanent). One enforcement_records row
--     per stamp (source_restriction_id = the stamp's id); each pass
--     rewrites it to the standing at that moment, and removes the rows of
--     stamps that no longer carry (a pardon between prepare and the delete).
--     restriction_type 'opinions_standing', category NULL, purge_after =
--     now() + private.opinion_carry_window() (30 days; owner decision
--     W9d-1), or the carried ban end if later, capped at 2 years. A parked
--     account (Spec 1 O3: its number is presumed someone else's; owner
--     decision W9d-2) carries nothing, counted
--     opinions.deletion.parked_not_carried. The final pass counts
--     opinions.deletion.uncarried when the stamps don't cover the count or
--     the live ban (PF-F6: nothing refuses, ever), and
--     opinions.deletion.key_not_ready when the key is set but its
--     fingerprint isn't ready (carried under the stamps anyway). It locks
--     the profile row only (no Dating lock), so a removal confirmed during
--     the deletion is either seen or waits.
--   * opinions_carry_on_auth_user_delete: BEFORE DELETE ON auth.users runs
--     the carry again (final), so a strike placed between prepare and
--     deleteUser, or a deletion that skips prepare, still carries (as
--     Dating's S2 W1 B3 I-2). It never raises.
--   * private.opinion_enforcement_purge(), daily cron
--     opinion-enforcement-purge (19 3 * * *; batch-1 review I-2): deletes
--     scope 'opinions' records past purge_after (30 days after the
--     deletion, or the ban end if later), counted
--     opinions.enforcement.purged per row. Dating's rows are never touched.
--     The same job keeps migration 2's restore log (private.opinion_restores)
--     90 days after each restore, counted opinions.restore.log_purged.
--   * enforcement_records.restriction_type also allows 'opinions_standing';
--     Dating's readers filter scope = 'dating' and are unchanged.
--   * admin_confirm_content_removal re-created from its LIVE body (Spec 1
--     W9b, 20261104120000; pg_get_functiondef on attune_spec3a) and
--     prepare_account_deletion from its LIVE body (Spec 2 W1 final fix,
--     20261106120000), changing only the lines marked "Spec 1 W9d".
--   * The server metric prefix 'opinions.' (owner spec1); no client key.
-- Grants in 20261107100010_opinion_enforcement_records_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

INSERT INTO public.metric_key_prefixes (prefix, owner_spec) VALUES ('opinions.', 'spec1')
ON CONFLICT (prefix) DO NOTHING;

ALTER TABLE public.enforcement_records DROP CONSTRAINT IF EXISTS enforcement_records_restriction_type_check;
ALTER TABLE public.enforcement_records ADD CONSTRAINT enforcement_records_restriction_type_check
  CHECK (restriction_type IN ('suspended', 'under_review', 'age_review', 'moderation_hold', 'opinions_standing'));
COMMENT ON TABLE public.enforcement_records IS
  'Spec 2 W1a (Q5, §6.3): a Dating restriction carried past account deletion, keyed by the number''s HMAC (dating_phone_hmac_for_user), kept 2 years. Spec 1 W9d (O4): scope opinions rows carry an Opinions strike count (confirmed_report_count) and live ban end (effect_until; NULL = no ban) under the HMAC stamped at the strike, restriction_type opinions_standing, kept private.opinion_carry_window() (or to the ban end) and purged daily by private.opinion_enforcement_purge(); complete_sign_up restores and removes them.';

CREATE TABLE IF NOT EXISTS private.opinion_enforcement_stamps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  phone_hmac text NOT NULL CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  strikes integer NOT NULL DEFAULT 0 CHECK (strikes >= 0),
  ban_until timestamptz,
  stamped_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, phone_hmac)
);
ALTER TABLE private.opinion_enforcement_stamps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.opinion_enforcement_stamps FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON TABLE private.opinion_enforcement_stamps IS
  'Spec 1 W9d (O4, S2 W1 B3 I-1): the Opinions strikes and latest ban an account received while holding each phone HMAC. Read only by the deletion carry; goes with the account.';

-- Owner decision W9d-1 (the recycled-number rule): how long a carried
-- Opinions record can be restored. One place to change it.
CREATE OR REPLACE FUNCTION private.opinion_carry_window()
 RETURNS interval
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT interval '30 days';
$function$;

CREATE OR REPLACE FUNCTION private.opinion_stamp_enforcement(p_user uuid, p_strikes integer, p_ban_until timestamptz)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_hmac text;
BEGIN
  IF p_user IS NULL OR (coalesce(p_strikes, 0) <= 0 AND p_ban_until IS NULL) THEN
    RETURN false;
  END IF;
  BEGIN
    IF EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user AND u.phone_released_at IS NOT NULL) THEN
      -- Parked (Spec 1 O3): the number is presumed someone else's (M-3).
      PERFORM private.bump_metric_internal('opinions.enforcement.parked_unstamped');
      RETURN false;
    END IF;
    v_hmac := public.dating_phone_hmac_for_user(p_user);
    IF v_hmac IS NULL THEN
      PERFORM private.bump_metric_internal('opinions.enforcement.unstamped');
      RETURN false;
    END IF;
    IF NOT private.dating_exclusion_key_ready() THEN
      -- Stamped under the live key anyway (S2 W1 B2: never block, count).
      PERFORM private.bump_metric_internal('opinions.enforcement.key_not_ready');
    END IF;
    INSERT INTO private.opinion_enforcement_stamps AS s (user_id, phone_hmac, strikes, ban_until)
    VALUES (p_user, v_hmac, greatest(coalesce(p_strikes, 0), 0), p_ban_until)
    ON CONFLICT (user_id, phone_hmac) DO UPDATE
      SET strikes = s.strikes + EXCLUDED.strikes,
          ban_until = greatest(s.ban_until, EXCLUDED.ban_until),
          stamped_at = now();
    RETURN true;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'opinion_stamp:%', SQLSTATE;
    PERFORM private.bump_metric_internal('opinions.enforcement.stamp_failed');
    RETURN false;
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION private.opinion_stamp_backfill()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Owner-run (owner checklist): strikes and live bans no stamp covers, under
-- the number each account holds now, only when that number provably hasn't
-- changed since the account's earliest removed post (M-1 ruling). -1 while
-- the key is missing.
DECLARE
  r record;
  v_n integer := 0;
  v_first timestamptz;
  v_removed integer;
BEGIN
  IF public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN
    RAISE NOTICE 'dating_exclusion_key is not set: no Opinions strike stamped';
    RETURN -1;
  END IF;
  FOR r IN
    SELECT p.id, p.confirmed_violation_count AS strikes,
           CASE WHEN p.banned_until > now() THEN p.banned_until END AS ban,
           coalesce((SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s
                      WHERE s.user_id = p.id), 0)::integer AS stamped,
           (SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
             WHERE s.user_id = p.id) AS stamped_ban,
           (SELECT a.phone_confirmed_at FROM auth.users AS a WHERE a.id = p.id) AS confirmed_at,
           (SELECT (to_jsonb(a) ->> 'phone_change_sent_at')::timestamptz FROM auth.users AS a
             WHERE a.id = p.id) AS change_sent_at
      FROM public.profiles AS p
     WHERE p.confirmed_violation_count > 0 OR p.banned_until > now()
  LOOP
    IF r.strikes > r.stamped OR (r.ban IS NOT NULL AND (r.stamped_ban IS NULL OR r.stamped_ban < r.ban)) THEN
      SELECT min(x.removed_at), count(*)::integer INTO v_first, v_removed
        FROM (SELECT o.removed_at FROM public.opinions AS o WHERE o.user_id = r.id AND o.removed_at IS NOT NULL
              UNION ALL
              SELECT c.removed_at FROM public.opinion_comments AS c WHERE c.user_id = r.id AND c.removed_at IS NOT NULL
              UNION ALL
              SELECT f.removed_at FROM public.forum_posts AS f WHERE f.user_id = r.id AND f.removed_at IS NOT NULL) AS x;
      -- The number held now provably held since the earliest removal, or
      -- nothing is stamped (a NULL anywhere is "not shown").
      IF NOT coalesce(v_removed >= r.strikes
                      AND r.confirmed_at <= v_first
                      AND (r.change_sent_at IS NULL OR r.change_sent_at <= v_first), false) THEN
        PERFORM private.bump_metric_internal('opinions.enforcement.backfill_phone_unverified');
        CONTINUE;
      END IF;
      IF private.opinion_stamp_enforcement(r.id, greatest(r.strikes - r.stamped, 0), r.ban) THEN
        v_n := v_n + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION private.opinion_deletion_carry(p_user uuid, p_final boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_count integer;
  v_ban timestamptz;
  v_released timestamptz;
  v_n integer := 0;
  v_stamped integer;
  v_stamped_ban timestamptz;
BEGIN
  IF p_user IS NULL THEN
    RETURN 0;
  END IF;
  SELECT p.confirmed_violation_count, CASE WHEN p.banned_until > now() THEN p.banned_until END
    INTO v_count, v_ban
    FROM public.profiles AS p WHERE p.id = p_user
    FOR UPDATE;
  v_count := greatest(coalesce(v_count, 0), 0);
  SELECT u.phone_released_at INTO v_released FROM public.users AS u WHERE u.id = p_user;
  -- Only a live ban or a count above 0 carries (O4), and never from a parked
  -- account (Spec 1 O3). Either way, an earlier pass's rows go (a pardon or
  -- a park between prepare and the delete).
  IF (v_count <= 0 AND v_ban IS NULL) OR v_released IS NOT NULL THEN
    DELETE FROM public.enforcement_records AS er
     USING private.opinion_enforcement_stamps AS s
     WHERE s.user_id = p_user AND er.source_restriction_id = s.id AND er.scope = 'opinions';
    IF v_released IS NOT NULL AND (v_count > 0 OR v_ban IS NOT NULL) AND p_final THEN
      PERFORM private.bump_metric_internal('opinions.deletion.parked_not_carried');
    END IF;
    RETURN 0;
  END IF;
  -- The stamp gives the HMAC; the values are the standing now, capped by
  -- what was placed under that number (I-1).
  INSERT INTO public.enforcement_records AS er (phone_hmac, scope, source_restriction_id, restriction_type,
                                                category, confirmed_report_count, effect_until, purge_after)
  SELECT c.phone_hmac, 'opinions', c.id, 'opinions_standing', NULL, c.strikes, c.ban,
         least(greatest(now() + private.opinion_carry_window(), coalesce(c.ban, now())),
               now() + interval '2 years')
    FROM (SELECT s.phone_hmac, s.id, least(s.strikes, v_count) AS strikes,
                 CASE WHEN s.ban_until > now() AND v_ban IS NOT NULL THEN least(s.ban_until, v_ban) END AS ban
            FROM private.opinion_enforcement_stamps AS s
           WHERE s.user_id = p_user) AS c
   WHERE c.strikes > 0 OR c.ban IS NOT NULL
  ON CONFLICT (source_restriction_id) DO UPDATE
    SET confirmed_report_count = EXCLUDED.confirmed_report_count,
        effect_until = EXCLUDED.effect_until,
        purge_after = least(EXCLUDED.purge_after, er.created_at + interval '2 years')
    WHERE er.scope = 'opinions';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  -- A stamp that no longer carries keeps no row from an earlier pass.
  DELETE FROM public.enforcement_records AS er
   USING private.opinion_enforcement_stamps AS s
   WHERE s.user_id = p_user AND er.source_restriction_id = s.id AND er.scope = 'opinions'
     AND least(s.strikes, v_count) <= 0
     AND NOT coalesce(s.ban_until > now() AND v_ban IS NOT NULL, false);
  IF p_final THEN
    SELECT coalesce(sum(s.strikes), 0)::integer, max(s.ban_until) INTO v_stamped, v_stamped_ban
      FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = p_user;
    IF v_count > v_stamped OR (v_ban IS NOT NULL AND (v_stamped_ban IS NULL OR v_stamped_ban < v_ban)) THEN
      PERFORM private.bump_metric_internal('opinions.deletion.uncarried');
    END IF;
    IF v_n > 0 AND NOT private.dating_exclusion_key_ready() THEN
      PERFORM private.bump_metric_internal('opinions.deletion.key_not_ready');
    END IF;
  END IF;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION private.opinion_carry_on_auth_user_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  BEGIN
    PERFORM private.opinion_deletion_carry(OLD.id, true);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'opinion_carry_on_auth_user_delete:%', SQLSTATE;
    PERFORM private.bump_metric_internal('opinions.deletion.late_carry_failed');
  END;
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS opinions_carry_on_auth_user_delete ON auth.users;
CREATE TRIGGER opinions_carry_on_auth_user_delete
  BEFORE DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION private.opinion_carry_on_auth_user_delete();

-- Batch-1 review I-2 (owner W9d-1: kept 30 days after the deletion, or to
-- the ban end if later): the expired Opinions records go, daily. Dating's
-- rows (scope 'dating', 2 years) are never touched here.
CREATE OR REPLACE FUNCTION private.opinion_enforcement_purge()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_n integer := 0;
  v_logs integer := 0;
BEGIN
  DELETE FROM public.enforcement_records AS er
   WHERE er.scope = 'opinions' AND er.purge_after <= now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  FOR i IN 1..v_n LOOP
    PERFORM private.bump_metric_internal('opinions.enforcement.purged');
  END LOOP;
  -- The restore log (migration 2) is kept 90 days after each restore
  -- (coordinator ruling on the batch-2 fix); only that table is touched.
  IF to_regclass('private.opinion_restores') IS NOT NULL THEN
    DELETE FROM private.opinion_restores AS o
     WHERE o.restored_at <= now() - interval '90 days';
    GET DIAGNOSTICS v_logs = ROW_COUNT;
    FOR i IN 1..v_logs LOOP
      PERFORM private.bump_metric_internal('opinions.restore.log_purged');
    END LOOP;
  END IF;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_confirm_content_removal(p_content_type text, p_content_id uuid)
 RETURNS TABLE(violation_count integer, banned_until timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_author_id uuid;
  v_new_count int;
  v_ban_until timestamptz;
  v_prev_ban timestamptz; -- Spec 1 W9b
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_content_type = 'opinion' THEN
    UPDATE public.opinions SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSIF p_content_type = 'comment' THEN
    UPDATE public.opinion_comments SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSIF p_content_type = 'forum_post' THEN
    UPDATE public.forum_posts SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSE
    RAISE EXCEPTION 'invalid_content_type' USING ERRCODE = '22023';
  END IF;

  IF v_author_id IS NULL THEN
    RETURN QUERY SELECT 0, NULL::timestamptz;
    RETURN;
  END IF;

  UPDATE public.profiles
  SET confirmed_violation_count = confirmed_violation_count + 1
  WHERE id = v_author_id
  RETURNING confirmed_violation_count INTO v_new_count;

  -- Spec 1 W9b (D17): the removal notice, to the author only.
  PERFORM private.enqueue_forum_notification(
    p_user_id    => v_author_id,
    p_title      => 'Post removed',
    p_body       => 'One of your posts was removed for breaking the Opinions guidelines.',
    p_type       => 'forum_content_removed',
    p_opinion_id => CASE WHEN p_content_type = 'opinion' THEN p_content_id END,
    p_comment_id => CASE WHEN p_content_type = 'comment' THEN p_content_id END
  );

  IF v_new_count >= 3 THEN
    -- Never move the ban backward: a moderator confirming several
    -- violations in one sitting extends the ban past whichever is later
    -- (now, or an existing future banned_until), and never re-shortens or
    -- re-applies a ban that already ran its course before this confirmation.
    SELECT GREATEST(COALESCE(p.banned_until, now()), now()) + interval '7 days', p.banned_until -- Spec 1 W9b: OPN-BAN-42702
    INTO v_ban_until, v_prev_ban
    FROM public.profiles AS p WHERE p.id = v_author_id;

    UPDATE public.profiles
    SET banned_until = v_ban_until
    WHERE id = v_author_id;

    -- Spec 1 W9b (D17): the ban notice, new or extended.
    PERFORM private.enqueue_forum_notification(
      p_user_id => v_author_id,
      p_title   => 'Posting paused',
      p_body    => CASE WHEN v_prev_ban > now()
                        THEN 'Your pause on posting in Opinions has been extended.'
                        ELSE 'You can''t post in Opinions for 7 days.' END,
      p_type    => 'forum_posting_banned'
    );
  END IF;

  -- Spec 1 W9d (O4; S2 W1 B3 I-1): this strike, and the ban it set, are
  -- Spec 1 W9d stamped with the number the author holds now; never raises.
  IF v_new_count IS NOT NULL THEN -- Spec 1 W9d
    PERFORM private.opinion_stamp_enforcement(v_author_id, 1, v_ban_until); -- Spec 1 W9d
  END IF; -- Spec 1 W9d
  RETURN QUERY SELECT v_new_count, v_ban_until;
END;
$function$;

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
  -- Spec 1 W9d (O4): the Opinions strike count and live ban carry under
  -- Spec 1 W9d the HMACs stamped when they were placed. Never refuses
  -- Spec 1 W9d (PF-F6); the auth.users trigger carries again at the delete.
  BEGIN -- Spec 1 W9d
    PERFORM private.opinion_deletion_carry(p_user_id, false); -- Spec 1 W9d
  EXCEPTION WHEN OTHERS THEN -- Spec 1 W9d
    RAISE WARNING 'opinion_deletion:carry:%', SQLSTATE; -- Spec 1 W9d
    PERFORM private.bump_metric_internal('opinions.deletion.prepare_carry_failed'); -- Spec 1 W9d
  END; -- Spec 1 W9d
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

REVOKE ALL ON FUNCTION private.opinion_carry_window() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_enforcement(uuid, integer, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_backfill() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_deletion_carry(uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_carry_on_auth_user_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_enforcement_purge() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion(uuid) TO service_role;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'opinion-enforcement-purge';
END;
$$;
SELECT cron.schedule('opinion-enforcement-purge', '19 3 * * *', $cron$SELECT private.opinion_enforcement_purge()$cron$);

-- Strikes and bans placed before this migration, when the key is set now
-- (the owner runs it again after every deploy of this migration and after
-- setting the key: checklist item 2).
DO $$
BEGIN
  PERFORM private.opinion_stamp_backfill();
END $$;

COMMIT;

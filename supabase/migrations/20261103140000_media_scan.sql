-- Spec 1 W7b, migration 15a (spec §4.7 #15, as two files, plan P-15):
-- image safety, the queue and the one match path.
--   * private.media_scan_queue (spec §4.2): one row per object to match,
--     UNIQUE (bucket, object_name); source 'queue' or 'inline' (a match a
--     synchronous pipeline recorded, review I-10). Status 'skipped' (plan
--     P-19) is a video or an object gone before its scan: never 'clear'.
--   * public.safety_escalations (spec §4.2): csam_match and scan_failed,
--     read by the named child-safety contact (service role). Also records
--     the vendor and its reference (spec §9: "the escalation records the
--     vendor reference"), whether the evidence was copied to quarantine
--     (plan P-18) and the exact safety-quarantine path of that copy
--     (quarantine_path, NULL when it was not copied; B5 fix I-4), and
--     alerted_at for the webhook post (plan P-21). No foreign key on
--     user_id: evidence outlives the account.
--   * storage bucket safety-quarantine: private, no storage.objects policy.
--   * private.media_scan_state: the enqueue path (trigger or sweep, set by
--     20261103140100 and shown by identity health, plan P-16), the sweep's
--     watermark, and how many uploads the enqueue failed to queue.
--   * private.media_scan_buckets(): what is scanned. Never
--     dating-profile-photos (Spec 2 matches those inline, review I-10).
--     Plus the profile-picture bucket 'avatars' (plan P-17).
--   * private.enqueue_media_object(): the one queue writer, used by the
--     trigger, the sweep and the daily reconcile: only with
--     csam_hash_matching on, only listed buckets, but EVERY object in them
--     whatever its declared mime (B4 fix I-3: the client sets the
--     Content-Type, so scan-media decides image / video / other from the
--     bytes); the mime is recorded as given. A changed object (an avatar
--     written over in place) is queued again, with its lease cleared,
--     unless it matched and that match is not yet closed (new bytes after a
--     closed match are scanned, PF-M2).
--   * private.handle_csam_match(): THE match path, shared by
--     complete_media_scan and record_inline_csam_match: one csam_match
--     escalation per object, a safety_review hold on the uploader
--     (place_account_hold, reason_ref = the escalation id; an uploader
--     already held keeps the hold and its reference, and the new escalation
--     says so, B4 fix m3), the original queued for deletion (the repo's
--     deletion upsert, B4 fix m2) once it was quarantined; when it was NOT
--     quarantined every pending deletion of the original waits
--     (not_before = 'infinity', B4 fix I-2).
--     A repeat for the same object while its escalation is not closed
--     returns that escalation and does nothing else (a reviewer's resolved
--     hold stays resolved); after a person closed it, a match (of new bytes
--     at the same path) is a new escalation and a new hold (PF-M2). Nothing
--     tells anyone: the uploader learns only H1 at the next token refresh
--     (W6a's hook), the partner nothing.
--   * claim_media_scan_jobs, complete_media_scan, record_inline_csam_match
--     (service role; spec §4.3 W7b). Each claim gives the job a fresh
--     lease_id; a clear, skipped or unavailable answer is taken only with
--     the lease of the claim it answers (B4 fix I-1), a match always.
--   * The evidence guard (B4 fix I-2): a trigger on media_deletion_queue
--     holds back (not_before = 'infinity') the deletion of an object whose
--     csam_match is not closed and not quarantined, whichever pipeline
--     queued it; when a person marks the escalation quarantined or closed,
--     those deletions are released.
--   * The hold guard (B4 fix m3): a safety_review hold can't be resolved
--     while another csam_match of that user is not closed.
--   * public.mark_escalation_quarantined() (final review I-2, service role
--     only): the reviewer's step after copying unquarantined evidence by
--     hand. It refuses until the copy is in safety-quarantine at
--     <bucket>/<object_name>/..., then records the path and marks the
--     escalation quarantined, which releases the held deletion.
--   * Server thumbnails (final review M-5): process-chat-media and
--     process-relationship-avatar write thumbnails as the service role, so
--     they have no owner. A match of an original queues the deletion of its
--     thumbnails too; a match of a thumbnail names its original's uploader
--     (held) and the original.
--   * Enqueue failures are never silent (final review M-1): every failure,
--     one object or a whole failed read of storage.objects by the sweep or
--     the reconcile, is counted (identity health) and alerted once through
--     media_scan_enqueue_alerts_due / mark_media_scan_enqueue_alerted.
--   * The alert pair for the webhook, expiry (24 h unscanned -> failed +
--     scan_failed), retention (clear and skipped rows after 7 days; expiry
--     only while csam_hash_matching is on, B4 fix m4), identity health, the
--     two crons.
-- Grants in 20261103140010_media_scan_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS private.media_scan_queue (
  id bigserial PRIMARY KEY,
  bucket text NOT NULL,
  object_name text NOT NULL,
  owner_user_id uuid,
  mime text,
  source text NOT NULL DEFAULT 'queue'
    CONSTRAINT media_scan_queue_source_check CHECK (source IN ('queue', 'inline')),
  status text NOT NULL DEFAULT 'pending'
    CONSTRAINT media_scan_queue_status_check
    CHECK (status IN ('pending', 'scanning', 'clear', 'match', 'failed', 'skipped')),
  attempts int NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  enqueued_at timestamptz NOT NULL DEFAULT now(),
  scanned_at timestamptz,
  vendor text,
  vendor_ref text,
  lease_id uuid,
  CONSTRAINT media_scan_queue_object_key UNIQUE (bucket, object_name)
);
-- (a database that ran an earlier draft of this file converges)
ALTER TABLE private.media_scan_queue ADD COLUMN IF NOT EXISTS lease_id uuid;
CREATE INDEX IF NOT EXISTS media_scan_queue_due_idx
  ON private.media_scan_queue (next_attempt_at) WHERE status IN ('pending', 'scanning');
CREATE INDEX IF NOT EXISTS media_scan_queue_done_idx
  ON private.media_scan_queue (scanned_at) WHERE status IN ('clear', 'skipped');

CREATE TABLE IF NOT EXISTS public.safety_escalations (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind text NOT NULL CONSTRAINT safety_escalations_kind_check CHECK (kind IN ('csam_match', 'scan_failed')),
  user_id uuid,
  bucket text NOT NULL,
  object_name text NOT NULL,
  status text NOT NULL DEFAULT 'open'
    CONSTRAINT safety_escalations_status_check CHECK (status IN ('open', 'reported', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  vendor text,
  vendor_ref text,
  quarantined boolean,
  quarantine_path text,
  alerted_at timestamptz
);
-- (a database that ran an earlier draft of this file converges)
ALTER TABLE public.safety_escalations ADD COLUMN IF NOT EXISTS quarantine_path text;
-- One csam_match per object until a person closes it (PF-M2: new bytes at
-- the same path that match again are a new escalation); one open
-- scan_failed per object. An index left by an earlier shape is rebuilt.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_indexes AS i
              WHERE i.schemaname = 'public' AND i.indexname = 'safety_escalations_match_once'
                AND i.indexdef !~ 'status <> ''closed''') THEN
    DROP INDEX public.safety_escalations_match_once;
  END IF;
END;
$$;
CREATE UNIQUE INDEX IF NOT EXISTS safety_escalations_match_once
  ON public.safety_escalations (bucket, object_name) WHERE kind = 'csam_match' AND status <> 'closed';
CREATE UNIQUE INDEX IF NOT EXISTS safety_escalations_failed_open
  ON public.safety_escalations (bucket, object_name) WHERE kind = 'scan_failed' AND status = 'open';
CREATE INDEX IF NOT EXISTS safety_escalations_unalerted_idx
  ON public.safety_escalations (created_at) WHERE alerted_at IS NULL;
ALTER TABLE public.safety_escalations ENABLE ROW LEVEL SECURITY;

INSERT INTO storage.buckets (id, name, public)
VALUES ('safety-quarantine', 'safety-quarantine', false)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS private.media_scan_state (
  id boolean PRIMARY KEY DEFAULT true CONSTRAINT media_scan_state_one_row CHECK (id),
  enqueue_path text CONSTRAINT media_scan_state_path_check CHECK (enqueue_path IN ('trigger', 'sweep')),
  path_recorded_at timestamptz,
  sweep_watermark timestamptz,
  enqueue_failures bigint NOT NULL DEFAULT 0,
  last_enqueue_failure_at timestamptz,
  last_failed_bucket text,
  last_failed_object text
);
ALTER TABLE private.media_scan_state ADD COLUMN IF NOT EXISTS last_failed_bucket text;
ALTER TABLE private.media_scan_state ADD COLUMN IF NOT EXISTS last_failed_object text;
-- M-1: whole reads of storage.objects that failed (the sweep's or the
-- reconcile's), and how many failures the webhook was told of.
ALTER TABLE private.media_scan_state ADD COLUMN IF NOT EXISTS enqueue_read_failures bigint NOT NULL DEFAULT 0;
ALTER TABLE private.media_scan_state ADD COLUMN IF NOT EXISTS enqueue_failures_alerted bigint NOT NULL DEFAULT 0;
ALTER TABLE private.media_scan_state ADD COLUMN IF NOT EXISTS first_unalerted_failure_at timestamptz;
INSERT INTO private.media_scan_state (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION private.media_scan_buckets()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT ARRAY['message-media', 'story-media', 'relationship-avatars', 'journal-media',
               'planning-media', 'avatars']::text[];
$$;

-- The one queue writer (trigger, sweep, reconcile). [p_changed_at] is when the
-- object's bytes last changed: an existing row is queued again only when
-- it was queued before that, and never while it matched and that match's
-- escalation is not closed (PF-M2).
CREATE OR REPLACE FUNCTION private.enqueue_media_object(
  p_bucket text, p_object_name text, p_owner uuid, p_mime text, p_changed_at timestamptz)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_bucket IS NULL OR p_object_name IS NULL
     OR NOT (p_bucket = ANY (private.media_scan_buckets()))
     OR NOT private.spec1_flag_on('csam_hash_matching') THEN
    RETURN;
  END IF;
  INSERT INTO private.media_scan_queue AS q (bucket, object_name, owner_user_id, mime)
  VALUES (p_bucket, p_object_name, p_owner, p_mime)
  ON CONFLICT (bucket, object_name) DO UPDATE
    SET status = 'pending', attempts = 0, next_attempt_at = now(), enqueued_at = now(),
        scanned_at = NULL, vendor = NULL, vendor_ref = NULL, source = 'queue', lease_id = NULL,
        owner_user_id = EXCLUDED.owner_user_id, mime = EXCLUDED.mime
    WHERE q.enqueued_at < p_changed_at
      AND (q.status <> 'match'
           OR NOT EXISTS (SELECT 1 FROM public.safety_escalations AS e
                           WHERE e.kind = 'csam_match' AND e.bucket = q.bucket
                             AND e.object_name = q.object_name AND e.status <> 'closed'));
END;
$$;

-- Counts one enqueue failure (M-1): an object the trigger, the sweep or the
-- reconcile could not queue, or ([p_read]) a whole read of storage.objects
-- that failed, so nothing was queued at all. Shown by identity health and
-- alerted once (media_scan_enqueue_alerts_due).
CREATE OR REPLACE FUNCTION private.note_media_scan_enqueue_failure(
  p_bucket text, p_object_name text, p_read boolean DEFAULT false)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE private.media_scan_state AS s
     SET enqueue_failures = s.enqueue_failures + 1,
         enqueue_read_failures = s.enqueue_read_failures + CASE WHEN coalesce(p_read, false) THEN 1 ELSE 0 END,
         last_enqueue_failure_at = now(),
         first_unalerted_failure_at = coalesce(s.first_unalerted_failure_at, now()),
         last_failed_bucket = CASE WHEN coalesce(p_read, false) THEN s.last_failed_bucket ELSE p_bucket END,
         last_failed_object = CASE WHEN coalesce(p_read, false) THEN s.last_failed_object ELSE p_object_name END;
$$;

-- Server thumbnails (M-5). The thumbnails made from an original:
-- process-chat-media's (messages.media_thumbnail_url, found through the
-- message's upload intent or its sender, both indexed) and
-- process-relationship-avatar's (relationships.chat_avatar_thumbnail_url).
-- Read only.
CREATE OR REPLACE FUNCTION private.media_derived_objects(p_bucket text, p_object_name text, p_owner uuid)
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT DISTINCT x.name
    FROM (SELECT m.media_thumbnail_url AS name
            FROM public.message_media_upload_intents AS i
            JOIN public.messages AS m ON m.relationship_id = i.relationship_id AND m.media_url = i.storage_key
           WHERE p_bucket = 'message-media' AND i.storage_key = p_object_name
          UNION ALL
          SELECT m.media_thumbnail_url
            FROM public.messages AS m
           WHERE p_bucket = 'message-media' AND p_owner IS NOT NULL
             AND m.sender_id = p_owner AND m.media_url = p_object_name
          UNION ALL
          SELECT r.chat_avatar_thumbnail_url
            FROM public.relationships AS r
           WHERE p_bucket = 'relationship-avatars' AND r.chat_avatar_url = p_object_name) AS x
   WHERE x.name IS NOT NULL AND x.name <> p_object_name;
$$;

-- The original a server thumbnail was made from, and that original's
-- uploader: its queue row's owner, else its storage owner, else the
-- message's sender. A chat thumbnail is found by a scan of messages, run
-- only when a thumbnail under chat-thumbnails/ matched (rare). Read only.
CREATE OR REPLACE FUNCTION private.media_derived_from(p_bucket text, p_object_name text)
RETURNS TABLE (original text, owner_user_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT x.original,
         coalesce(
           (SELECT q.owner_user_id FROM private.media_scan_queue AS q
             WHERE q.bucket = p_bucket AND q.object_name = x.original),
           (SELECT CASE WHEN o.owner_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                        THEN o.owner_text::uuid END
              FROM (SELECT coalesce(to_jsonb(so) ->> 'owner', to_jsonb(so) ->> 'owner_id') AS owner_text
                      FROM storage.objects AS so
                     WHERE so.bucket_id = p_bucket AND so.name = x.original) AS o
             LIMIT 1),
           x.uploader)
    FROM (SELECT m.media_url AS original, m.sender_id AS uploader, 1 AS rank
            FROM public.messages AS m
           WHERE p_bucket = 'message-media' AND left(p_object_name, 16) = 'chat-thumbnails/'
             AND m.media_thumbnail_url = p_object_name AND m.media_url IS NOT NULL
          UNION ALL
          SELECT r.chat_avatar_url, NULL::uuid, 2
            FROM public.relationships AS r
           WHERE p_bucket = 'relationship-avatars' AND r.chat_avatar_thumbnail_url = p_object_name
             AND r.chat_avatar_url IS NOT NULL) AS x
   ORDER BY x.rank
   LIMIT 1;
$$;

-- Queues the deletion of an original's server thumbnails (M-5), the
-- repo's upsert; a deletion already done stays done. The evidence guard
-- still holds one that is itself unquarantined evidence.
CREATE OR REPLACE FUNCTION private.queue_derived_media_deletions(p_bucket text, p_object_name text, p_owner uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_name text;
  v_count int := 0;
BEGIN
  FOR v_name IN SELECT d.n FROM private.media_derived_objects(p_bucket, p_object_name, p_owner) AS d(n) LOOP
    INSERT INTO public.media_deletion_queue AS d (bucket_id, object_name, requested_at, not_before)
    VALUES (p_bucket, v_name, now(), now())
    ON CONFLICT (bucket_id, object_name) DO UPDATE
      SET not_before = LEAST(d.not_before, now())
      WHERE d.deleted_at IS NULL;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- THE match path (review I-10). The caller has already copied the object
-- to safety-quarantine when [p_quarantined], at [p_quarantine_path] (the
-- exact object it wrote, B5 fix I-4); otherwise the original is the only
-- copy of the evidence and is NOT queued for deletion (plan P-18), and no
-- path is recorded. The draft without the path is dropped.
DROP FUNCTION IF EXISTS private.handle_csam_match(text, text, uuid, text, text, boolean);
CREATE OR REPLACE FUNCTION private.handle_csam_match(
  p_bucket text, p_object_name text, p_owner uuid, p_vendor text, p_vendor_ref text,
  p_quarantined boolean DEFAULT true, p_quarantine_path text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id bigint;
  v_held text;
  v_owner uuid := p_owner;
  v_from text;
  v_derived int;
BEGIN
  IF p_bucket IS NULL OR p_object_name IS NULL THEN
    RAISE EXCEPTION 'media_scan:invalid_object';
  END IF;
  -- One escalation per object, under one lock, so the queue and an inline
  -- pipeline racing on the same object still make one.
  PERFORM pg_advisory_xact_lock(hashtextextended('csam-match:' || p_bucket || '/' || p_object_name, 0));
  SELECT e.id INTO v_id FROM public.safety_escalations AS e
   WHERE e.kind = 'csam_match' AND e.bucket = p_bucket AND e.object_name = p_object_name
     AND e.status <> 'closed';
  IF v_id IS NOT NULL THEN
    -- A repeat keeps the escalation. A copy it made is recorded when the
    -- escalation has none yet (the first copy stays the evidence, B5 fix
    -- I-4). quarantined is not changed here: a person checks the copy and
    -- marks it, which releases the held deletions.
    IF coalesce(p_quarantined, false) AND p_quarantine_path IS NOT NULL THEN
      UPDATE public.safety_escalations AS e
         SET quarantine_path = p_quarantine_path,
             notes = CASE WHEN e.quarantined IS TRUE THEN e.notes
                          ELSE e.notes || ' A later scan copied it to safety-quarantine (quarantine_path): check the copy, then SELECT public.mark_escalation_quarantined(id, quarantine_path) to release the held deletion.'
                     END
       WHERE e.id = v_id AND e.quarantine_path IS NULL;
    END IF;
    -- A server thumbnail made since the first match goes too (M-5).
    PERFORM private.queue_derived_media_deletions(p_bucket, p_object_name, v_owner);
    RETURN v_id;
  END IF;

  -- A server thumbnail has no owner (M-5): it names its original's uploader.
  IF v_owner IS NULL THEN
    SELECT d.original, d.owner_user_id INTO v_from, v_owner
      FROM private.media_derived_from(p_bucket, p_object_name) AS d;
  END IF;

  INSERT INTO public.safety_escalations
    (kind, user_id, bucket, object_name, vendor, vendor_ref, quarantined, quarantine_path, notes)
  VALUES ('csam_match', v_owner, p_bucket, p_object_name, p_vendor, p_vendor_ref,
          coalesce(p_quarantined, false),
          CASE WHEN coalesce(p_quarantined, false) THEN p_quarantine_path END,
          CASE WHEN coalesce(p_quarantined, false)
               THEN 'Copied to safety-quarantine; the original is queued for deletion. A person reviews before any report.'
               -- Final review I-2: the guard holds every deletion of the
               -- original until the escalation is marked quarantined.
               ELSE 'Quarantine copy FAILED: the original is still in place and is the evidence; every deletion of it is held. '
                    || 'Copy it by hand to safety-quarantine at <bucket>/<object_name>/<id>, '
                    || 'then SELECT public.mark_escalation_quarantined(<this id>, ''<that path>'') (it releases the held deletion), '
                    || 'then queue its deletion: SELECT public.queue_media_deletion(''<bucket>'', ''<object_name>''). '
                    || 'A person reviews before any report.'
          END
          || CASE WHEN v_from IS NOT NULL
                  THEN ' A server thumbnail of ' || p_bucket || '/' || v_from
                       || CASE WHEN v_owner IS NULL THEN ', whose uploader is unknown.' ELSE ': the user is that original''s uploader.' END
                  ELSE '' END)
  RETURNING id INTO v_id;

  -- The uploader's account is held (reversible; W6a's hook refuses its
  -- tokens). An object with no owner, or an owner with no account row, is
  -- escalated without a hold. An uploader already held keeps that hold and
  -- its reference (B4 fix m3): the new escalation names it, and the hold
  -- guard below keeps the hold until every match of theirs is closed.
  IF v_owner IS NOT NULL AND EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = v_owner) THEN
    SELECT coalesce(h.reason_ref, 'no reference') INTO v_held FROM public.account_holds AS h
     WHERE h.user_id = v_owner AND h.kind = 'safety_review' AND h.resolved_at IS NULL;
    IF FOUND THEN
      UPDATE public.safety_escalations AS e
         SET notes = e.notes || ' The uploader was already held (' || v_held || ').'
       WHERE e.id = v_id;
    ELSE
      PERFORM public.place_account_hold(v_owner, 'safety_review', 'safety_escalation:' || v_id);
    END IF;
  END IF;

  IF coalesce(p_quarantined, false) THEN
    -- The repo's deletion upsert (as queue_story_media_deletion): a done row
    -- (a path deleted after an earlier, closed match, PF-M2) is queued
    -- again, and a later not_before (a story's archive time) is brought
    -- forward (B4 fix m2).
    INSERT INTO public.media_deletion_queue AS d (bucket_id, object_name, requested_at, not_before)
    VALUES (p_bucket, p_object_name, now(), now())
    ON CONFLICT (bucket_id, object_name) DO UPDATE
      SET deleted_at = NULL, requested_at = now(), not_before = LEAST(d.not_before, now());
  ELSE
    -- The original is the evidence: a deletion some other pipeline already
    -- queued waits too (the guard trigger sets not_before; B4 fix I-2).
    UPDATE public.media_deletion_queue AS d
       SET not_before = 'infinity'
     WHERE d.bucket_id = p_bucket AND d.object_name = p_object_name AND d.deleted_at IS NULL;
  END IF;

  -- Its server thumbnails go either way (M-5): the original (or its copy)
  -- is the evidence, and the partner would still see the thumbnail.
  v_derived := private.queue_derived_media_deletions(p_bucket, p_object_name, v_owner);
  IF v_derived > 0 THEN
    UPDATE public.safety_escalations AS e
       SET notes = e.notes || ' ' || v_derived || ' server thumbnail(s) of it queued for deletion.'
     WHERE e.id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

-- Due jobs, oldest first: pending and due, or scanning with a lapsed lease
-- (a scan-media run that died). Each claim adds an attempt and a 10-minute
-- lease with a fresh lease_id, which the answer must carry (B4 fix I-1).
-- Nothing while csam_hash_matching is off. (FOR UPDATE SKIP LOCKED keeps
-- overlapping runs apart; the contract can't show two sessions.)
-- An earlier draft returned no lease_id: its result type differs, so it is
-- dropped first (CREATE OR REPLACE can't change it).
DO $$
BEGIN
  -- (Spec 2 W1 final fix, N-I2: to_regprocedure, never a ::regprocedure
  -- literal, which is resolved when the statement is planned and fails on a
  -- fresh database where the function doesn't exist yet.)
  IF to_regprocedure('public.claim_media_scan_jobs(integer)') IS NOT NULL
     AND pg_catalog.pg_get_function_result(to_regprocedure('public.claim_media_scan_jobs(integer)')) !~ 'lease_id' THEN
    DROP FUNCTION public.claim_media_scan_jobs(integer);
  END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.claim_media_scan_jobs(p_limit int)
RETURNS TABLE (id bigint, bucket text, object_name text, owner_user_id uuid, mime text, attempts int,
               lease_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.spec1_flag_on('csam_hash_matching') THEN
    RETURN;
  END IF;
  PERFORM private.expire_media_scan_jobs();
  RETURN QUERY
  WITH due AS (
    SELECT q.id FROM private.media_scan_queue AS q
     WHERE q.status IN ('pending', 'scanning') AND q.next_attempt_at <= now()
     ORDER BY q.next_attempt_at, q.id
     LIMIT least(greatest(coalesce(p_limit, 1), 1), 50)
     FOR UPDATE SKIP LOCKED
  )
  UPDATE private.media_scan_queue AS q
     SET status = 'scanning', attempts = q.attempts + 1, next_attempt_at = now() + interval '10 minutes',
         lease_id = gen_random_uuid()
    FROM due
   WHERE q.id = due.id
  RETURNING q.id, q.bucket, q.object_name, q.owner_user_id, q.mime, q.attempts, q.lease_id;
END;
$$;

-- 24 hours without a result: failed, and a person is told (scan_failed).
-- Returns how many scan_failed escalations it opened (B4 fix m11).
CREATE OR REPLACE FUNCTION private.expire_media_scan_jobs()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job record;
  v_count int := 0;
BEGIN
  FOR v_job IN
    UPDATE private.media_scan_queue AS q
       SET status = 'failed', scanned_at = now()
     WHERE q.status IN ('pending', 'scanning') AND q.enqueued_at < now() - interval '24 hours'
    RETURNING q.bucket, q.object_name, q.owner_user_id, q.vendor, q.vendor_ref
  LOOP
    INSERT INTO public.safety_escalations (kind, user_id, bucket, object_name, vendor, vendor_ref, notes)
    VALUES ('scan_failed', v_job.owner_user_id, v_job.bucket, v_job.object_name, v_job.vendor, v_job.vendor_ref,
            'Not scanned within 24 hours. Check the matcher (CSAM_MATCHER, its keys) and scan-media''s logs, then scan it by hand.')
    ON CONFLICT DO NOTHING;
    IF FOUND THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RETURN v_count;
END;
$$;

-- [p_lease_id] is the lease of the claim this answers (B4 fix I-1): a
-- clear, skipped or unavailable answer with any other lease (an earlier
-- claim's, before the object was written over and queued again) changes
-- nothing. A match needs none. [p_quarantine_path] is where a 'match' was
-- copied (B5 fix I-4). The drafts without them are dropped.
DROP FUNCTION IF EXISTS public.complete_media_scan(bigint, text, text, text);
DROP FUNCTION IF EXISTS public.complete_media_scan(bigint, text, text, text, uuid);
CREATE OR REPLACE FUNCTION public.complete_media_scan(
  p_job_id bigint, p_result text, p_vendor text, p_vendor_ref text, p_lease_id uuid DEFAULT NULL,
  p_quarantine_path text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job private.media_scan_queue%ROWTYPE;
BEGIN
  IF p_result IS NULL OR p_result NOT IN ('clear', 'match', 'match_unquarantined', 'unavailable', 'skipped') THEN
    RAISE EXCEPTION 'media_scan:invalid_result';
  END IF;
  SELECT * INTO v_job FROM private.media_scan_queue AS q WHERE q.id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'media_scan:no_job';
  END IF;

  -- A match is never dropped, whatever the row's state (plan P-20).
  IF p_result IN ('match', 'match_unquarantined') THEN
    UPDATE private.media_scan_queue AS q
       SET status = 'match', scanned_at = now(), vendor = p_vendor, vendor_ref = p_vendor_ref, lease_id = NULL
     WHERE q.id = p_job_id;
    PERFORM private.handle_csam_match(v_job.bucket, v_job.object_name, v_job.owner_user_id,
                                      p_vendor, p_vendor_ref, p_result = 'match',
                                      CASE WHEN p_result = 'match' THEN p_quarantine_path END);
    RETURN;
  END IF;

  -- Anything else only answers the claim it belongs to: still scanning,
  -- under the same lease.
  IF v_job.status <> 'scanning' THEN
    RETURN;
  END IF;
  IF v_job.lease_id IS DISTINCT FROM p_lease_id OR p_lease_id IS NULL THEN
    RETURN;
  END IF;
  IF p_result IN ('clear', 'skipped') THEN
    UPDATE private.media_scan_queue AS q
       SET status = p_result, scanned_at = now(), vendor = p_vendor, vendor_ref = p_vendor_ref, lease_id = NULL
     WHERE q.id = p_job_id;
    RETURN;
  END IF;

  -- unavailable: back off 1, 5, 15, 60 minutes, then hourly; 24 hours
  -- after it was queued, failed and escalated.
  IF v_job.enqueued_at < now() - interval '24 hours' THEN
    UPDATE private.media_scan_queue AS q
       SET status = 'failed', scanned_at = now(), vendor = p_vendor, vendor_ref = p_vendor_ref, lease_id = NULL
     WHERE q.id = p_job_id;
    INSERT INTO public.safety_escalations (kind, user_id, bucket, object_name, vendor, vendor_ref, notes)
    VALUES ('scan_failed', v_job.owner_user_id, v_job.bucket, v_job.object_name, p_vendor, p_vendor_ref,
            'Not scanned within 24 hours. Check the matcher (CSAM_MATCHER, its keys) and scan-media''s logs, then scan it by hand.')
    ON CONFLICT DO NOTHING;
    RETURN;
  END IF;
  UPDATE private.media_scan_queue AS q
     SET status = 'pending', vendor = p_vendor, vendor_ref = p_vendor_ref, lease_id = NULL,
         next_attempt_at = now() + CASE
           WHEN v_job.attempts <= 1 THEN interval '1 minute'
           WHEN v_job.attempts = 2 THEN interval '5 minutes'
           WHEN v_job.attempts = 3 THEN interval '15 minutes'
           ELSE interval '60 minutes' END
   WHERE q.id = p_job_id;
END;
$$;

-- For synchronous pipelines (Spec 2's process-dating-photo): the same
-- path as a queued match. Idempotent per object while its escalation is
-- not closed; a match after a closed one (new bytes) records its own time
-- and vendor reference (B4 fix m11). [p_quarantine_path] is where the
-- caller copied it (B5 fix I-4); the draft without it is dropped.
DROP FUNCTION IF EXISTS public.record_inline_csam_match(text, text, uuid, text, text, boolean);
CREATE OR REPLACE FUNCTION public.record_inline_csam_match(
  p_bucket text, p_object_name text, p_owner uuid, p_vendor text, p_vendor_ref text,
  p_quarantined boolean DEFAULT true, p_quarantine_path text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_open boolean;
BEGIN
  IF p_bucket IS NULL OR p_object_name IS NULL THEN
    RAISE EXCEPTION 'media_scan:invalid_object';
  END IF;
  v_open := EXISTS (SELECT 1 FROM public.safety_escalations AS e
                     WHERE e.kind = 'csam_match' AND e.bucket = p_bucket
                       AND e.object_name = p_object_name AND e.status <> 'closed');
  INSERT INTO private.media_scan_queue AS q
    (bucket, object_name, owner_user_id, source, status, scanned_at, vendor, vendor_ref)
  VALUES (p_bucket, p_object_name, p_owner, 'inline', 'match', now(), p_vendor, p_vendor_ref)
  ON CONFLICT (bucket, object_name) DO UPDATE
    SET status = 'match', lease_id = NULL,
        scanned_at = CASE WHEN v_open THEN coalesce(q.scanned_at, now()) ELSE now() END,
        vendor = CASE WHEN v_open THEN coalesce(q.vendor, EXCLUDED.vendor) ELSE EXCLUDED.vendor END,
        vendor_ref = CASE WHEN v_open THEN coalesce(q.vendor_ref, EXCLUDED.vendor_ref) ELSE EXCLUDED.vendor_ref END;
  RETURN private.handle_csam_match(p_bucket, p_object_name, p_owner, p_vendor, p_vendor_ref,
                                   coalesce(p_quarantined, false), p_quarantine_path);
END;
$$;

-- The webhook's two sources (identity-health-alert every 15 minutes, and
-- scan-media straight after a run that escalated): ids, a count and times.
CREATE OR REPLACE FUNCTION private.safety_escalations_due(p_kind text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  -- count and times over everything due; ids (what gets marked) at most
  -- 500 per post (B4 fix m5).
  SELECT jsonb_build_object(
    'ids', (SELECT coalesce(jsonb_agg(x.id ORDER BY x.created_at, x.id), '[]'::jsonb)
              FROM (SELECT y.id, y.created_at FROM public.safety_escalations AS y
                     WHERE y.kind = p_kind AND y.alerted_at IS NULL
                     ORDER BY y.created_at, y.id LIMIT 500) AS x),
    'count', count(*),
    'first_at', min(e.created_at),
    'last_at', max(e.created_at))
    FROM public.safety_escalations AS e
   WHERE e.kind = p_kind AND e.alerted_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION public.csam_escalations_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.safety_escalations_due('csam_match');
$$;

CREATE OR REPLACE FUNCTION public.scan_failed_escalations_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.safety_escalations_due('scan_failed');
$$;

CREATE OR REPLACE FUNCTION public.mark_safety_escalations_alerted(p_ids bigint[])
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.safety_escalations AS e
     SET alerted_at = now()
   WHERE e.id = ANY (coalesce(p_ids, ARRAY[]::bigint[])) AND e.alerted_at IS NULL;
$$;

-- Final review I-2: the reviewer's step after copying unquarantined
-- evidence by hand. Refuses until the copy is in safety-quarantine at
-- <bucket>/<object_name>/<something>; records that path (the first copy
-- recorded stays the evidence) and marks the escalation quarantined, which
-- releases the held deletion (release_guarded_evidence). Returns how many
-- held deletions it released.
CREATE OR REPLACE FUNCTION public.mark_escalation_quarantined(p_escalation_id bigint, p_path text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_esc public.safety_escalations%ROWTYPE;
  v_prefix text;
  v_held int;
BEGIN
  SELECT * INTO v_esc FROM public.safety_escalations AS e
   WHERE e.id = p_escalation_id AND e.kind = 'csam_match'
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'media_scan:no_escalation';
  END IF;
  IF v_esc.status = 'closed' THEN
    RAISE EXCEPTION 'media_scan:escalation_closed';
  END IF;
  v_prefix := v_esc.bucket || '/' || v_esc.object_name || '/';
  IF p_path IS NULL OR left(p_path, length(v_prefix)) <> v_prefix OR length(p_path) <= length(v_prefix) THEN
    RAISE EXCEPTION 'media_scan:invalid_quarantine_path'
      USING HINT = 'Pass the path inside safety-quarantine: <bucket>/<object_name>/<id>.';
  END IF;
  IF v_esc.quarantine_path IS NOT NULL AND v_esc.quarantine_path <> p_path THEN
    RAISE EXCEPTION 'media_scan:other_quarantine_path'
      USING HINT = 'This escalation already records a copy (quarantine_path): pass that path.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects AS o WHERE o.bucket_id = 'safety-quarantine' AND o.name = p_path) THEN
    RAISE EXCEPTION 'media_scan:quarantine_copy_missing'
      USING HINT = 'Copy the original to safety-quarantine at that path first.';
  END IF;
  SELECT count(*) INTO v_held FROM public.media_deletion_queue AS d
   WHERE d.bucket_id = v_esc.bucket AND d.object_name = v_esc.object_name
     AND d.deleted_at IS NULL AND d.not_before = 'infinity';
  UPDATE public.safety_escalations AS e
     SET quarantined = true,
         quarantine_path = p_path,
         notes = CASE WHEN e.quarantined IS TRUE THEN e.notes
                      ELSE e.notes || ' Marked quarantined by hand at ' || p_path || '.' END
   WHERE e.id = p_escalation_id;
  RETURN jsonb_build_object('escalation_id', p_escalation_id, 'quarantine_path', p_path, 'released', v_held);
END;
$$;

-- M-1: enqueue failures for the webhook (identity-health-alert). The one
-- id is the failure count at the read; marking it covers that many, so a
-- failure after the read stays due. Counts and times only.
CREATE OR REPLACE FUNCTION public.media_scan_enqueue_alerts_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'ids', CASE WHEN s.enqueue_failures > s.enqueue_failures_alerted
                THEN jsonb_build_array(s.enqueue_failures) ELSE '[]'::jsonb END,
    'count', greatest(s.enqueue_failures - s.enqueue_failures_alerted, 0),
    'first_at', CASE WHEN s.enqueue_failures > s.enqueue_failures_alerted THEN s.first_unalerted_failure_at END,
    'last_at', CASE WHEN s.enqueue_failures > s.enqueue_failures_alerted THEN s.last_enqueue_failure_at END)
    FROM private.media_scan_state AS s;
$$;

CREATE OR REPLACE FUNCTION public.mark_media_scan_enqueue_alerted(p_ids bigint[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_upto bigint;
BEGIN
  SELECT max(x) INTO v_upto FROM unnest(coalesce(p_ids, ARRAY[]::bigint[])) AS x;
  IF v_upto IS NULL THEN
    RETURN;
  END IF;
  UPDATE private.media_scan_state AS s
     SET enqueue_failures_alerted = greatest(s.enqueue_failures_alerted, least(v_upto, s.enqueue_failures)),
         first_unalerted_failure_at = CASE WHEN s.enqueue_failures > greatest(s.enqueue_failures_alerted, least(v_upto, s.enqueue_failures))
                                           THEN s.last_enqueue_failure_at END;
END;
$$;

-- media-scan-retention (spec §4.6, §4.8): clear and skipped rows after 7
-- days; matches and failures stay with their escalation. Also expires any
-- job left 24 hours (so a dead scan-media cron still reaches a person),
-- but only while csam_hash_matching is on: an owner who turns matching off
-- doesn't get a scan_failed per queued object (B4 fix m4).
CREATE OR REPLACE FUNCTION private.media_scan_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF private.spec1_flag_on('csam_hash_matching') THEN
    PERFORM private.expire_media_scan_jobs();
  END IF;
  DELETE FROM private.media_scan_queue AS q
   WHERE q.status IN ('clear', 'skipped') AND q.scanned_at < now() - interval '7 days';
END;
$$;

-- The evidence guard (B4 fix I-2): while an object's csam_match is not
-- closed and its copy is not in safety-quarantine, the original is the
-- only evidence, so any deletion of it (story expiry, a deleted message,
-- a chapter's deletion, ...) waits: not_before = 'infinity'.
CREATE OR REPLACE FUNCTION private.guard_unquarantined_evidence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.deleted_at IS NULL
     AND EXISTS (SELECT 1 FROM public.safety_escalations AS e
                  WHERE e.kind = 'csam_match' AND e.bucket = NEW.bucket_id
                    AND e.object_name = NEW.object_name
                    AND e.status <> 'closed' AND e.quarantined IS NOT TRUE) THEN
    NEW.not_before := 'infinity';
  END IF;
  RETURN NEW;
END;
$$;
CREATE OR REPLACE TRIGGER guard_unquarantined_evidence
  BEFORE INSERT OR UPDATE ON public.media_deletion_queue
  FOR EACH ROW EXECUTE FUNCTION private.guard_unquarantined_evidence();

-- When a person marks the escalation quarantined (copied by hand) or
-- closes it, the held-back deletions go ahead (the guard keeps any that
-- another open, unquarantined match still needs).
CREATE OR REPLACE FUNCTION private.release_guarded_evidence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.kind = 'csam_match' AND (NEW.status = 'closed' OR NEW.quarantined IS TRUE) THEN
    UPDATE public.media_deletion_queue AS d
       SET not_before = now()
     WHERE d.bucket_id = NEW.bucket AND d.object_name = NEW.object_name
       AND d.deleted_at IS NULL AND d.not_before = 'infinity';
  END IF;
  RETURN NULL;
END;
$$;
CREATE OR REPLACE TRIGGER release_guarded_evidence
  AFTER UPDATE OF status, quarantined ON public.safety_escalations
  FOR EACH ROW EXECUTE FUNCTION private.release_guarded_evidence();

-- The hold guard (B4 fix m3): one safety_review hold per user, so it is
-- not resolved while a csam_match of theirs other than the one it names
-- is not closed. (A reviewer may resolve the hold of the match it names
-- while that escalation is still open: a false match.)
CREATE OR REPLACE FUNCTION private.guard_safety_hold_release()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_other bigint;
BEGIN
  IF NEW.kind = 'safety_review' AND OLD.resolved_at IS NULL AND NEW.resolved_at IS NOT NULL THEN
    SELECT e.id INTO v_other FROM public.safety_escalations AS e
     WHERE e.kind = 'csam_match' AND e.user_id = NEW.user_id AND e.status <> 'closed'
       AND 'safety_escalation:' || e.id IS DISTINCT FROM OLD.reason_ref
     ORDER BY e.id LIMIT 1;
    IF v_other IS NOT NULL THEN
      RAISE EXCEPTION 'hold:still_needed (safety_escalation:%)', v_other
        USING HINT = 'Another match of this account is not closed: close it, or keep the hold.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE OR REPLACE TRIGGER guard_safety_hold_release
  BEFORE UPDATE OF resolved_at ON public.account_holds
  FOR EACH ROW EXECUTE FUNCTION private.guard_safety_hold_release();

-- Identity health (plan P-22): W7b's lines live here, so get_identity_health
-- names no W7 table itself (the W6 split, dormancy contract F).
CREATE OR REPLACE FUNCTION private.identity_health_w7b()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'media_scan_enqueue_path', (SELECT s.enqueue_path FROM private.media_scan_state AS s),
    'media_scan_enqueue_failures', coalesce((SELECT s.enqueue_failures FROM private.media_scan_state AS s), 0),
    'media_scan_last_enqueue_failure_at', (SELECT s.last_enqueue_failure_at FROM private.media_scan_state AS s),
    'media_scan_enqueue_read_failures', coalesce((SELECT s.enqueue_read_failures FROM private.media_scan_state AS s), 0),
    'media_scan_pending', (SELECT count(*) FROM private.media_scan_queue AS q
                            WHERE q.status IN ('pending', 'scanning')),
    'media_scan_oldest_pending_minutes', (
      SELECT coalesce(floor(extract(epoch FROM now() - min(q.enqueued_at)) / 60)::int, 0)
        FROM private.media_scan_queue AS q WHERE q.status IN ('pending', 'scanning')),
    'media_scan_skipped_7d', (SELECT count(*) FROM private.media_scan_queue AS q
                               WHERE q.status = 'skipped' AND q.scanned_at > now() - interval '7 days'),
    'safety_escalations_open', (SELECT count(*) FROM public.safety_escalations AS e WHERE e.status = 'open'),
    'safety_escalations_unalerted', (SELECT count(*) FROM public.safety_escalations AS e
                                      WHERE e.alerted_at IS NULL
                                        AND e.created_at < now() - interval '15 minutes'));
$$;

-- get_identity_health re-created from its live body
-- (20261103100200_fresh_start.sql), with one addition: || identity_health_w7b().
CREATE OR REPLACE FUNCTION public.get_identity_health()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'accounts_without_birth_date', (
      SELECT count(*) FROM public.users AS u
       WHERE NOT EXISTS (SELECT 1 FROM public.account_birthdates AS b WHERE b.user_id = u.id)),
    'accounts_without_path', (SELECT count(*) FROM public.users AS u WHERE u.path IS NULL),
    'holds', jsonb_build_object(
      'age_review', (SELECT count(*) FROM public.account_holds AS h
                      WHERE h.kind = 'age_review' AND h.resolved_at IS NULL),
      'recovery_hold', (SELECT count(*) FROM public.account_holds AS h
                         WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL),
      'safety_review', (SELECT count(*) FROM public.account_holds AS h
                         WHERE h.kind = 'safety_review' AND h.resolved_at IS NULL)),
    'unfinished_signups_awaiting_purge', (SELECT count(*) FROM private.unfinished_signups AS s))
    || private.identity_health_w6a()
    || private.identity_health_w7b();
$$;

-- Server-only objects revoked here as well as in the twin.
REVOKE ALL ON private.media_scan_queue FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE private.media_scan_queue_id_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON private.media_scan_state FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.safety_escalations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.safety_escalations_id_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.media_scan_buckets() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enqueue_media_object(text, text, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.handle_csam_match(text, text, uuid, text, text, boolean, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.expire_media_scan_jobs() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.safety_escalations_due(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.media_scan_retention() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.identity_health_w7b() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_unquarantined_evidence() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.release_guarded_evidence() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_safety_hold_release() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.note_media_scan_enqueue_failure(text, text, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.media_derived_objects(text, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.media_derived_from(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.queue_derived_media_deletions(text, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.mark_escalation_quarantined(bigint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.media_scan_enqueue_alerts_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_media_scan_enqueue_alerted(bigint[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_media_scan_jobs(int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_media_scan(bigint, text, text, text, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_inline_csam_match(text, text, uuid, text, text, boolean, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.csam_escalations_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.scan_failed_escalations_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_safety_escalations_alerted(bigint[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_identity_health() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname IN ('scan-media', 'media-scan-retention');
END;
$$;
-- scan-media is only called while csam_hash_matching is on (PF-L10).
SELECT cron.schedule('scan-media', '* * * * *',
                     $cron$SELECT public.invoke_edge_function('scan-media') WHERE private.spec1_flag_on('csam_hash_matching')$cron$);
SELECT cron.schedule('media-scan-retention', '27 4 * * *', $cron$SELECT private.media_scan_retention()$cron$);

COMMIT;

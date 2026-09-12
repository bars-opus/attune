-- A reply cannot quote another couple's story. The trigger is the only
-- gate: messages are inserted directly, so there is no RPC to check it.
-- Also: quoted_text is SERVER-SET from the media type, so a client
-- cannot write arbitrary text into a story quote.
--
-- Contracts (spec §5.4, task-1-brief.md):
--   1. A member replying to their own couple's live story succeeds, and
--      quoted_text is overwritten to 'Photo story' or 'Video story'.
--   2. Quoting a story from a DIFFERENT relationship is refused.
--   3. Quoting a deleted (soft-deleted) story is refused.
--   4. Quoting from an ENDED or archived relationship is refused.
--   5. Soft-deleting the story afterwards leaves the message intact with
--      its quoted_text (the reply must still read sensibly).
--   6. A HARD delete sets story_item_id to NULL and keeps quoted_text.
BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-0000000071a1'::uuid),
  ('00000000-0000-0000-0000-0000000071a2'::uuid),
  ('00000000-0000-0000-0000-0000000071b1'::uuid),
  ('00000000-0000-0000-0000-0000000071b2'::uuid)
  ON CONFLICT DO NOTHING;

INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000071a1'::uuid, '+15550710001', 'R1'),
  ('00000000-0000-0000-0000-0000000071a2'::uuid, '+15550710002', 'R2'),
  ('00000000-0000-0000-0000-0000000071b1'::uuid, '+15550710003', 'R3'),
  ('00000000-0000-0000-0000-0000000071b2'::uuid, '+15550710004', 'R4')
  ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_rel_a       uuid;  -- active, unarchived: a1 <-> a2
  v_rel_b       uuid;  -- a SEPARATE couple's active relationship: b1 <-> b2
  v_rel_a_b1    uuid;  -- a1's OTHER active relationship: a1 <-> b1
  v_rel_ended   uuid;  -- a1 <-> a2, but ended
  v_rel_arch    uuid;  -- a1 <-> a2, active but chat_archived_at set
  v_story_live  uuid;  -- image story, in v_rel_a
  v_story_video uuid;  -- video story, in v_rel_a
  v_story_other uuid;  -- story in v_rel_b (the other couple's)
  v_story_a_b1  uuid;  -- story in v_rel_a_b1 (a1 IS a member of this one too)
  v_story_del   uuid;  -- already soft-deleted story, in v_rel_a
  v_story_ended uuid;  -- live story whose OWN relationship is v_rel_ended
  v_story_arch  uuid;  -- live story whose OWN relationship is v_rel_arch
  v_now         timestamptz := now();
  v_msg         uuid;
  v_msg2        uuid;
  v_ok          boolean;
  v_quoted      text;
  v_story_ref   uuid;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-0000000071a1'::uuid,
          '00000000-0000-0000-0000-0000000071a2'::uuid, 'active')
  RETURNING id INTO v_rel_a;

  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-0000000071b1'::uuid,
          '00000000-0000-0000-0000-0000000071b2'::uuid, 'active')
  RETURNING id INTO v_rel_b;

  -- a1's SECOND active relationship, with b1. The schema does not forbid
  -- a user from being a member of two simultaneously-active
  -- relationships, so this is what makes contract 2 a pure test of the
  -- relationship-MATCH check rather than an accidental retest of
  -- membership: a1 legitimately belongs to both v_rel_a and
  -- v_rel_a_b1, so quoting a v_rel_a_b1 story while sending in v_rel_a
  -- can only be caught by requiring the story's relationship_id to
  -- equal the message's OWN relationship_id.
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-0000000071a1'::uuid,
          '00000000-0000-0000-0000-0000000071b1'::uuid, 'active')
  RETURNING id INTO v_rel_a_b1;

  INSERT INTO public.relationships(user_a, user_b, status, ended_at)
  VALUES ('00000000-0000-0000-0000-0000000071a1'::uuid,
          '00000000-0000-0000-0000-0000000071a2'::uuid, 'ended', v_now)
  RETURNING id INTO v_rel_ended;

  INSERT INTO public.relationships(user_a, user_b, status, chat_archived_at)
  VALUES ('00000000-0000-0000-0000-0000000071a1'::uuid,
          '00000000-0000-0000-0000-0000000071a2'::uuid, 'active', v_now)
  RETURNING id INTO v_rel_arch;

  -- A live image story and a live video story, both in v_rel_a.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at)
  VALUES (gen_random_uuid(), v_rel_a,
          '00000000-0000-0000-0000-0000000071a1'::uuid, 'image',
          'stories/r1-media', 'stories/r1-thumb', 1080, 1920,
          current_date, v_now, v_now + interval '24 hours')
  RETURNING id INTO v_story_live;

  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height, duration_ms,
    occurred_on, created_at, expires_at)
  VALUES (gen_random_uuid(), v_rel_a,
          '00000000-0000-0000-0000-0000000071a2'::uuid, 'video',
          'stories/r2-media', 'stories/r2-thumb', 1080, 1920, 5000,
          current_date, v_now, v_now + interval '24 hours')
  RETURNING id INTO v_story_video;

  -- A live story that belongs to the OTHER couple entirely.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at)
  VALUES (gen_random_uuid(), v_rel_b,
          '00000000-0000-0000-0000-0000000071b1'::uuid, 'image',
          'stories/other-media', 'stories/other-thumb', 1080, 1920,
          current_date, v_now, v_now + interval '24 hours')
  RETURNING id INTO v_story_other;

  -- A live story in v_rel_a_b1 -- a relationship a1 legitimately
  -- belongs to, just not the one the message is being sent in.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at)
  VALUES (gen_random_uuid(), v_rel_a_b1,
          '00000000-0000-0000-0000-0000000071b1'::uuid, 'image',
          'stories/a-b1-media', 'stories/a-b1-thumb', 1080, 1920,
          current_date, v_now, v_now + interval '24 hours')
  RETURNING id INTO v_story_a_b1;

  -- A live story whose OWN relationship_id is v_rel_ended -- this is
  -- what makes contract 4 a pure test of the relationship's
  -- active/unarchived state rather than a retest of the relationship-
  -- MATCH check: NEW.relationship_id will equal this story's own
  -- relationship_id exactly, so only requiring that relationship to be
  -- ACTIVE and unarchived can catch it. (A real story cannot be created
  -- in an ended relationship going forward -- create_story_upload_intent
  -- gates on an open relationship -- but a story legitimately posted
  -- while active must still be refusable as a quote once the
  -- relationship later ends, which is exactly this fixture.)
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at)
  VALUES (gen_random_uuid(), v_rel_ended,
          '00000000-0000-0000-0000-0000000071a1'::uuid, 'image',
          'stories/ended-media', 'stories/ended-thumb', 1080, 1920,
          current_date, v_now, v_now + interval '24 hours')
  RETURNING id INTO v_story_ended;

  -- Same idea, for the chat-archived relationship.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at)
  VALUES (gen_random_uuid(), v_rel_arch,
          '00000000-0000-0000-0000-0000000071a1'::uuid, 'image',
          'stories/arch-media', 'stories/arch-thumb', 1080, 1920,
          current_date, v_now, v_now + interval '24 hours')
  RETURNING id INTO v_story_arch;

  -- A story in v_rel_a that is ALREADY soft-deleted.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at, deleted_at)
  VALUES (gen_random_uuid(), v_rel_a,
          '00000000-0000-0000-0000-0000000071a1'::uuid, 'image',
          'stories/deleted-media', 'stories/deleted-thumb', 1080, 1920,
          current_date, v_now, v_now + interval '24 hours', v_now)
  RETURNING id INTO v_story_del;

  -- =================================================================
  -- Contract 1: a member replying to their own couple's live story
  -- succeeds, and quoted_text is overwritten -- from client-supplied
  -- junk, proving the trigger does not just fill in a NULL.
  -- =================================================================
  INSERT INTO public.messages(
    relationship_id, sender_id, client_message_id, content,
    story_item_id, quoted_text)
  VALUES (v_rel_a, '00000000-0000-0000-0000-0000000071a2'::uuid,
          gen_random_uuid(), 'love this',
          v_story_live, 'client-supplied junk that must be overwritten')
  RETURNING id INTO v_msg;

  SELECT quoted_text, story_item_id INTO v_quoted, v_story_ref
  FROM public.messages WHERE id = v_msg;

  IF v_quoted IS DISTINCT FROM 'Photo story' THEN
    RAISE EXCEPTION
      'contract 1 failed: quoted_text was %, expected Photo story', v_quoted;
  END IF;
  IF v_story_ref IS DISTINCT FROM v_story_live THEN
    RAISE EXCEPTION 'contract 1 failed: story_item_id was not preserved';
  END IF;

  -- Same contract, video media type -> 'Video story'.
  INSERT INTO public.messages(
    relationship_id, sender_id, client_message_id, content, story_item_id)
  VALUES (v_rel_a, '00000000-0000-0000-0000-0000000071a1'::uuid,
          gen_random_uuid(), 'nice clip', v_story_video)
  RETURNING id INTO v_msg2;

  SELECT quoted_text INTO v_quoted FROM public.messages WHERE id = v_msg2;
  IF v_quoted IS DISTINCT FROM 'Video story' THEN
    RAISE EXCEPTION
      'contract 1 failed (video): quoted_text was %, expected Video story',
      v_quoted;
  END IF;

  -- =================================================================
  -- Contract 2: quoting a story from a DIFFERENT relationship is
  -- refused, even though the sender IS a real member of v_rel_a and
  -- v_rel_a itself is perfectly valid.
  -- =================================================================
  v_ok := false;
  BEGIN
    INSERT INTO public.messages(
      relationship_id, sender_id, client_message_id, content, story_item_id)
    VALUES (v_rel_a, '00000000-0000-0000-0000-0000000071a1'::uuid,
            gen_random_uuid(), 'sneaky quote', v_story_other);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION
      'EXPLOIT: contract 2 failed -- quoted a story from another couple''s relationship';
  END IF;

  -- Same contract, but the sender (a1) IS a genuine member of the
  -- story's relationship (v_rel_a_b1) -- just not of v_rel_a, the
  -- relationship the message itself is being sent in. This isolates the
  -- relationship-MATCH check from the membership check: a version of the
  -- trigger that only verified "sender belongs to the story's
  -- relationship" (and dropped the match against NEW.relationship_id)
  -- would wrongly accept this insert.
  v_ok := false;
  BEGIN
    INSERT INTO public.messages(
      relationship_id, sender_id, client_message_id, content, story_item_id)
    VALUES (v_rel_a, '00000000-0000-0000-0000-0000000071a1'::uuid,
            gen_random_uuid(), 'cross-relationship quote', v_story_a_b1);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION
      'EXPLOIT: contract 2 failed -- quoted a story from a relationship the sender belongs to, but not the one the message was sent in';
  END IF;

  -- =================================================================
  -- Contract 3: quoting a deleted (soft-deleted) story is refused.
  -- =================================================================
  v_ok := false;
  BEGIN
    INSERT INTO public.messages(
      relationship_id, sender_id, client_message_id, content, story_item_id)
    VALUES (v_rel_a, '00000000-0000-0000-0000-0000000071a1'::uuid,
            gen_random_uuid(), 'quoting gone story', v_story_del);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'contract 3 failed -- quoted an already-deleted story';
  END IF;

  -- =================================================================
  -- Contract 4: quoting from an ENDED or archived relationship is
  -- refused.
  --
  -- Two variants. First, the story is really v_rel_a's (live, active)
  -- but the message's OWN relationship_id names the ended/archived row
  -- instead -- already caught by the relationship-MATCH check, but
  -- still a real client-reachable shape (relationship_id and
  -- story_item_id independently client-supplied) so it stays covered.
  -- =================================================================
  v_ok := false;
  BEGIN
    INSERT INTO public.messages(
      relationship_id, sender_id, client_message_id, content, story_item_id)
    VALUES (v_rel_ended, '00000000-0000-0000-0000-0000000071a1'::uuid,
            gen_random_uuid(), 'ended relationship quote', v_story_live);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION
      'contract 4 failed (ended, cross-match) -- quoted a story via an ended relationship row';
  END IF;

  v_ok := false;
  BEGIN
    INSERT INTO public.messages(
      relationship_id, sender_id, client_message_id, content, story_item_id)
    VALUES (v_rel_arch, '00000000-0000-0000-0000-0000000071a1'::uuid,
            gen_random_uuid(), 'archived relationship quote', v_story_live);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION
      'contract 4 failed (archived, cross-match) -- quoted a story via a chat-archived relationship row';
  END IF;

  -- Second variant: the story's OWN relationship_id IS the ended/
  -- archived row (v_story_ended lives in v_rel_ended; v_story_arch
  -- lives in v_rel_arch), and NEW.relationship_id matches it exactly.
  -- This isolates the active/unarchived check from the relationship-
  -- MATCH check: a trigger that only compared the two relationship ids
  -- for equality (and dropped checking that relationship's status/
  -- chat_archived_at) would wrongly accept both of these.
  v_ok := false;
  BEGIN
    INSERT INTO public.messages(
      relationship_id, sender_id, client_message_id, content, story_item_id)
    VALUES (v_rel_ended, '00000000-0000-0000-0000-0000000071a1'::uuid,
            gen_random_uuid(), 'ended relationship, own story', v_story_ended);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION
      'EXPLOIT: contract 4 failed (ended, same-relationship) -- quoted a story whose own relationship had ended';
  END IF;

  v_ok := false;
  BEGIN
    INSERT INTO public.messages(
      relationship_id, sender_id, client_message_id, content, story_item_id)
    VALUES (v_rel_arch, '00000000-0000-0000-0000-0000000071a1'::uuid,
            gen_random_uuid(), 'archived relationship, own story', v_story_arch);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION
      'EXPLOIT: contract 4 failed (archived, same-relationship) -- quoted a story whose own relationship had its chat archived';
  END IF;

  -- =================================================================
  -- Contract 5: soft-deleting the story afterwards leaves the message
  -- intact with its quoted_text (the reply must still read sensibly).
  -- =================================================================
  UPDATE public.story_items SET deleted_at = now() WHERE id = v_story_live;

  SELECT quoted_text, story_item_id INTO v_quoted, v_story_ref
  FROM public.messages WHERE id = v_msg;

  IF v_quoted IS DISTINCT FROM 'Photo story' THEN
    RAISE EXCEPTION
      'contract 5 failed: quoted_text changed after soft delete (got %)',
      v_quoted;
  END IF;
  IF v_story_ref IS DISTINCT FROM v_story_live THEN
    RAISE EXCEPTION
      'contract 5 failed: story_item_id was cleared by a soft delete';
  END IF;

  -- =================================================================
  -- Contract 6: a HARD delete sets story_item_id to NULL and keeps
  -- quoted_text. Simulates the relationship-cascade path
  -- (stories_enqueue_media_on_hard_delete fires BEFORE DELETE on
  -- story_items; ON DELETE SET NULL on messages.story_item_id is what
  -- this contract is actually about).
  -- =================================================================
  DELETE FROM public.story_items WHERE id = v_story_live;

  SELECT quoted_text, story_item_id INTO v_quoted, v_story_ref
  FROM public.messages WHERE id = v_msg;

  IF v_story_ref IS NOT NULL THEN
    RAISE EXCEPTION
      'contract 6 failed: story_item_id survived a hard delete (got %)',
      v_story_ref;
  END IF;
  IF v_quoted IS DISTINCT FROM 'Photo story' THEN
    RAISE EXCEPTION
      'contract 6 failed: quoted_text was lost on hard delete (got %)',
      v_quoted;
  END IF;

  RAISE NOTICE 'story reply contracts: all held';
END $$;

ROLLBACK;

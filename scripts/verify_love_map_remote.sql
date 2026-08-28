SELECT 'owner_check' AS what,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
         WHERE t.relname='game_session_rounds'
           AND c.conname='game_session_rounds_owner_check'
       ) THEN 'PRESENT' ELSE 'MISSING' END AS status
UNION ALL
SELECT 'relationship_id col',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
         WHERE table_name='game_session_rounds' AND column_name='relationship_id')
       THEN 'PRESENT' ELSE 'MISSING' END
UNION ALL
SELECT 'session_id nullable',
       (SELECT is_nullable FROM information_schema.columns
        WHERE table_name='game_session_rounds' AND column_name='session_id')
UNION ALL
SELECT 'love_map questions', (SELECT count(*)::text FROM public.game_questions
        WHERE game_type='love_map' AND active)
UNION ALL
SELECT 'preview column',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
         WHERE table_name='notification_settings'
           AND column_name='chat_message_preview_enabled')
       THEN 'PRESENT' ELSE 'MISSING' END
UNION ALL
SELECT 'mark_delivered guard',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname='mark_delivered')
            LIKE '%delivered_at IS NULL%'
       THEN 'PRESENT' ELSE 'MISSING' END
UNION ALL
SELECT 'cron job', COALESCE((SELECT schedule FROM cron.job
        WHERE jobname='refresh-love-map-weekly'), 'MISSING');

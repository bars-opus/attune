-- Run against REMOTE to see which grants are actually missing.
SELECT 'messages INSERT (table)' AS what,
       has_table_privilege('authenticated','public.messages','INSERT')::text AS granted
UNION ALL
SELECT 'messages.streak_views_remaining INSERT',
       has_column_privilege('authenticated','public.messages','streak_views_remaining','INSERT')::text
UNION ALL
SELECT 'streak_clips INSERT',
       has_table_privilege('authenticated','public.streak_clips','INSERT')::text
UNION ALL
SELECT 'streak_clips SELECT',
       has_table_privilege('authenticated','public.streak_clips','SELECT')::text;

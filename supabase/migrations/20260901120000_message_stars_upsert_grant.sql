-- 20260831120000_message_actions.sql granted SELECT, INSERT, DELETE on
-- message_stars, but starMessage() upserts (INSERT ... ON CONFLICT DO
-- UPDATE) — Postgres requires UPDATE privilege on the table for the
-- conflict branch regardless of whether a row actually conflicts, and
-- checks it before RLS is evaluated. Missing it made every star attempt
-- fail with "permission denied for table message_stars" (42501). RLS
-- (message_stars_owner, FOR ALL) already scopes rows to their owner; this
-- only adds the missing base-table grant alongside it.
GRANT UPDATE ON public.message_stars TO authenticated;

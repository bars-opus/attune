-- Task 1's migration (20260814120000_couples_calendar_reminders.sql) deliberately
-- excluded linked_timeline_event_id from the column-level GRANT UPDATE list on
-- public.reminders, since that column didn't exist as an app-writable field until
-- Task 7 introduced the optional Timeline link for anniversary reminders. Grant it
-- here as a small addendum rather than editing the already-committed Task 1 file.
GRANT UPDATE (linked_timeline_event_id) ON public.reminders TO authenticated;

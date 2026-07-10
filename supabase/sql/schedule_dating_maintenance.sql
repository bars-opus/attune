-- Install only after Dating Mode deployment. These jobs do not enable Dating.
SELECT cron.schedule(
  'expire-dating-introductions',
  '17 * * * *',
  $$ SELECT public.expire_dating_introductions(); $$
);

SELECT cron.schedule(
  'revalidate-dating-lifecycle-gates',
  '*/15 * * * *',
  $$ SELECT public.enforce_dating_lifecycle_gates(); $$
);

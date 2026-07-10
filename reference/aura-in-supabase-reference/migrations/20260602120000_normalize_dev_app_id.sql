-- One-off data fix: short_links created from a debug build before the dev
-- config was unified with production had app_id='aurain_dev'. The mobile
-- app's resolveSlug filters by app_id, so Universal Links tapping those
-- slugs would resolve via the web (resolve-link ignores app_id) but
-- fall through to the home screen on mobile because the deep-link
-- resolver couldn't find the row.
--
-- Now that dev and production share app_id='aurain', normalize the
-- pre-existing rows so Universal Links work everywhere.

UPDATE short_links
   SET app_id = 'aurain'
 WHERE app_id = 'aurain_dev';

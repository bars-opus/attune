-- DEV / MANUAL TESTING ONLY (spec §4.2, plan P-5). Never a migration.
-- Loads the [DRAFT] English filter terms into private.content_filter_terms
-- on the development project only. The guard and the insert are one
-- statement, so when private.assert_development_project() raises
-- env:not_development nothing is loaded. Safe to re-run: a re-run does not
-- turn a deliberately deactivated term back on. Draft terms never
-- match outside development (private.content_filter_verdict), whatever is
-- loaded.
--
-- [DRAFT] This list is a placeholder for testing, written by the developer,
-- NOT reviewed. Production holds only the cultural reviewer's signed lists
-- (slur and explicit terms in English, Twi, Ga, Ewe, Hausa and Pidgin, and
-- local number words), loaded with source = 'reviewed' and their review
-- reference: the W9a gate (owner deploy checklist). Terms are stored in the
-- match form (private.match_form), so write them as typed.
--
-- Run (SQL editor, or psql against the development project):
--   psql -X -v ON_ERROR_STOP=1 -f supabase/sql/load_content_filter_terms.sql
-- Check locally without keeping anything:
--   psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' \
--     -f supabase/sql/load_content_filter_terms.sql \
--     -c 'SELECT family, count(*) FROM private.content_filter_terms GROUP BY 1 ORDER BY 1' -c 'ROLLBACK'
DO $$
BEGIN
  PERFORM private.assert_development_project();

  INSERT INTO private.content_filter_terms (family, term, match_mode, locale, source)
  SELECT d.family, private.match_form(d.term), d.match_mode, 'en', 'draft'
    FROM (VALUES
      -- [DRAFT] slurs (English): a minimal set to exercise the filter.
      ('slur', 'nigger', 'squashed'),
      ('slur', 'faggot', 'squashed'),
      ('slur', 'retard', 'token'),
      ('slur', 'tranny', 'token'),
      -- [DRAFT] explicit sexual terms (English).
      ('explicit', 'porn', 'token'),
      ('explicit', 'nudes', 'token'),
      ('explicit', 'blowjob', 'squashed'),
      ('explicit', 'handjob', 'squashed'),
      ('explicit', 'cumshot', 'squashed')
    ) AS d(family, term, match_mode)
  ON CONFLICT (family, term, locale) DO UPDATE
    SET match_mode = EXCLUDED.match_mode;
END $$;

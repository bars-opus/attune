-- Applied AFTER all migrations. ALTER DEFAULT PRIVILEGES only covers tables
-- created afterwards by the same role, so a blanket grant is what actually
-- reproduces Supabase's platform-side privileges across the whole schema.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
  TO authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public
  TO authenticated, service_role, anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;

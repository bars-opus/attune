#!/usr/bin/env bash
# Turn the six AI Sessions capability flags on or off in the LOCAL test database.
#
# WHY THIS EXISTS. `scripts/local_pg_setup.sh` drops and recreates attune_test,
# so the flags return to their migration default of `false` on every rebuild.
# A local flip therefore has to happen AFTER a rebuild, not before — which is
# easy to forget and presents as "the feature is dead again".
#
# This touches ONLY the local database. Production is a separate, deliberate
# act: the flags are not client-writable (`authenticated` has no UPDATE on
# public.feature_flags), so flipping them for real is a service_role write
# against the live database.
#
# Usage:  bash scripts/local_ai_flags.sh on
#         bash scripts/local_ai_flags.sh off
#         bash scripts/local_ai_flags.sh status
set -euo pipefail

DB="${ATTUNE_TEST_DB:-attune_test}"
ACTION="${1:-status}"

show() {
  echo "-- $DB --"
  psql -d "$DB" -tAc \
    "select key || ' = ' || enabled::text
       from public.feature_flags
      where key like 'ai\_%' order by 1;"
  echo "-- as a client sees it, through the RPC --"
  psql -d "$DB" -tA <<'SQL'
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
                  json_build_object('sub', gen_random_uuid())::text, true);
SELECT public.get_ai_session_capabilities()::text;
ROLLBACK;
SQL
}

case "$ACTION" in
  on|off)
    want=$([ "$ACTION" = on ] && echo true || echo false)
    psql -d "$DB" -qc \
      "update public.feature_flags set enabled = $want where key like 'ai\_%';"
    show
    ;;
  status) show ;;
  *) echo "usage: $0 {on|off|status}" >&2; exit 2 ;;
esac

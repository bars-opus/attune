#!/usr/bin/env bash
#
# Builds a throwaway Postgres database from Attune's migrations so the SQL
# contract tests can run without Docker or the Supabase stack.
#
# This is NOT a Supabase emulator. It provides just enough of the platform
# (roles, the auth schema, auth.uid(), stubs for pg_cron/pg_net, and the
# table grants Supabase applies platform-side) for the schema to build and
# for RLS and RPC authorization to be exercised honestly.
#
# Usage:
#   scripts/local_pg_setup.sh              # rebuild attune_test, run tests
#   scripts/local_pg_setup.sh --no-tests   # rebuild only
#
# Requires: postgresql@17 (brew install postgresql@17 && brew services start postgresql@17)

set -euo pipefail
cd "$(dirname "$0")/.."

DB="${ATTUNE_TEST_DB:-attune_test}"
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"

if ! command -v psql >/dev/null 2>&1; then
  echo "error: psql not found. brew install postgresql@17" >&2
  exit 127
fi

echo "==> Rebuilding $DB"
dropdb --if-exists "$DB"
createdb "$DB"

echo "==> Bootstrapping the Supabase-shaped surface"
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f scripts/local_pg_bootstrap.sql

echo "==> Applying migrations"
ok=0; fail=0
for f in $(ls supabase/migrations/*.sql | sort); do
  if psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$f" >/tmp/attune_mig.log 2>&1; then
    ok=$((ok+1))
  else
    fail=$((fail+1))
    echo "    FAILED: $(basename "$f")"
    grep -oE 'ERROR:.*' /tmp/attune_mig.log | head -1 | sed 's/^/      /'
  fi
done
echo "    applied $ok, failed $fail"

echo "==> Applying platform-side grants"
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f scripts/local_pg_grants.sql

if [ "${1:-}" = "--no-tests" ]; then
  echo "==> Ready: postgresql://$(whoami)@localhost:5432/$DB"
  exit 0
fi

echo "==> Running contract tests"
status=0
for t in supabase/tests/*.sql; do
  n=$(basename "$t")
  if psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$t" >/tmp/attune_test.log 2>&1; then
    echo "    PASS  $n"
  else
    echo "    FAIL  $n"
    grep -oE 'ERROR:.*' /tmp/attune_test.log | head -1 | sed 's/^/      /'
    status=1
  fi
done
exit $status

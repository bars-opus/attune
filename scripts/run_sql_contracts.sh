#!/usr/bin/env bash
#
# Runs Attune's SQL contract tests against a local Supabase Postgres.
#
# Each file under supabase/tests/*.sql wraps its assertions in a single
# transaction and RAISE EXCEPTION on any violated contract, then ROLLBACK, so a
# clean exit code 0 means every contract held and nothing was persisted.
#
# Usage:
#   scripts/run_sql_contracts.sh                 # applies migrations, runs all
#   scripts/run_sql_contracts.sh --no-reset      # skip db reset (faster reruns)
#   scripts/run_sql_contracts.sh chat_system     # run only files matching a name
#
# Requirements: the Supabase CLI and a running local stack (`supabase start`).

set -euo pipefail

cd "$(dirname "$0")/.."

RESET=1
FILTER=""
for arg in "$@"; do
  case "$arg" in
    --no-reset) RESET=0 ;;
    *) FILTER="$arg" ;;
  esac
done

if ! command -v supabase >/dev/null 2>&1; then
  echo "error: supabase CLI not found. Install it: https://supabase.com/docs/guides/cli" >&2
  exit 127
fi

# Resolve the database URL. Precedence: explicit $DB_URL env (CI) > the running
# stack's reported URL > the CLI default local connection string.
if [ -z "${DB_URL:-}" ]; then
  DB_URL="$(supabase status -o env 2>/dev/null | sed -n 's/^DB_URL="\{0,1\}\([^"]*\)"\{0,1\}/\1/p' || true)"
fi
if [ -z "${DB_URL:-}" ]; then
  DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
fi

echo "Using database: ${DB_URL%%@*}@…"

if [ "$RESET" -eq 1 ]; then
  echo "==> Applying migrations (supabase db reset)…"
  supabase db reset --local >/dev/null
fi

# Prefer a local psql; otherwise exec psql inside the Supabase Postgres
# container (the CLI names it supabase_db_<project>).
DB_CONTAINER="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -m1 '^supabase_db_' || true)"

run_sql() {
  local file="$1"
  if command -v psql >/dev/null 2>&1; then
    psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$file"
  elif [ -n "$DB_CONTAINER" ]; then
    docker exec -i "$DB_CONTAINER" \
      psql "postgresql://postgres:postgres@127.0.0.1:5432/postgres" \
      -v ON_ERROR_STOP=1 -q < "$file"
  else
    echo "error: no local psql and no supabase_db_* container running." >&2
    echo "Start the stack with 'supabase start', or install psql." >&2
    return 2
  fi
}

status=0
shopt -s nullglob
for file in supabase/tests/*.sql; do
  name="$(basename "$file" .sql)"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
    continue
  fi
  printf '==> %-32s ' "$name"
  if run_sql "$file" >/tmp/attune_sql_contract.out 2>&1; then
    echo "PASS"
  else
    echo "FAIL"
    echo "---- output ----"
    sed 's/^/    /' /tmp/attune_sql_contract.out
    echo "----------------"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "All SQL contracts passed."
else
  echo "One or more SQL contracts FAILED." >&2
fi
exit "$status"

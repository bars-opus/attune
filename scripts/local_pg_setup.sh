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

# Concurrency contracts run separately because they need MORE THAN ONE
# CONNECTION -- a lock race cannot be expressed inside the single
# transaction the suite above uses. Every case in there exists because a
# review found a defect that a single-connection test could not catch:
# a lock-order deadlock between gameplay and expiry, and a session left
# half-closed when a player started during a sweep.
if [ -x scripts/concurrency/word_hunt_races.sh ]; then
  echo "==> Running concurrency contracts"
  if scripts/concurrency/word_hunt_races.sh "$DB" 2>&1 | sed 's/^/    /'; then
    :
  else
    status=1
  fi
fi

# The AI-session / AI-assistant concurrency contracts under
# supabase/tests/*.sh. These were committed by Tasks 5, 6 and 9 but were
# never invoked by this runner, so they only ever ran when someone
# remembered to run them by hand -- and Task 9's migration header cites
# its own script as the PROOF of its lock-order correctness. Task 9's
# review (finding F5) caught both that gap and the fact that its script
# had been committed non-executable (mode 644), so it would not even run
# via `./`. Wired in here so the claim and the check live together.
#
# They each hardcode `-d attune_test` internally (unlike
# word_hunt_races.sh, which takes the db name as $1), so they are skipped
# with a loud notice when the runner was pointed at a different database
# via ATTUNE_TEST_DB rather than silently testing the wrong one.
#
# ai_session_end_admit_concurrent_test.sh is run TWICE on purpose: with
# no argument it runs the unbiased race (which lands on outcome A -- end
# wins the lock), and with "admit" it gives the admission a head start to
# deterministically force outcome B. Both outcomes are admissible and
# both have their own consistency conditions, so exercising only
# whichever one the scheduler happens to favour would leave half the
# contract unproven.
# ai_session_completion_concurrent_test.sh is the newest entry and the
# reason the list above was incomplete in the first place: every one of
# the four scripts that preceded it races only prepare/activate/admit/
# end -- precisely the RPCs that already followed the documented lock
# order. No test raced any COMPLETION RPC (commit/stage/publish) against
# anything, which is how a lock-order inversion that deadlocks on the
# first attempt survived eleven task reviews. It races all three
# completion RPCs against end_ai_session and against
# purge_expired_ai_sessions, in both launch orderings, and additionally
# asserts that the purger never swallows a deadlock into a WARNING
# (which would leave an expired session active with its content
# retained). Run with no argument it does 10 trials per pair per
# ordering = 120 races, which takes a couple of minutes.
CONCURRENCY_SH=(
  supabase/tests/ai_assistant_provider_start_concurrent_test.sh
  supabase/tests/ai_session_admit_concurrent_test.sh
  supabase/tests/ai_session_admit_same_request_concurrent_test.sh
  "supabase/tests/ai_session_end_admit_concurrent_test.sh"
  "supabase/tests/ai_session_end_admit_concurrent_test.sh admit"
  supabase/tests/ai_session_completion_concurrent_test.sh
)
if [ "$DB" != "attune_test" ]; then
  echo "==> SKIPPING supabase/tests/*.sh concurrency contracts (they hardcode -d attune_test; this run used $DB)"
else
  echo "==> Running AI session concurrency contracts"
  for entry in "${CONCURRENCY_SH[@]}"; do
    # shellcheck disable=SC2206  # deliberate word split: "<script> <arg>"
    parts=($entry)
    script="${parts[0]}"
    label="$(basename "$script")${parts[1]:+ ${parts[1]}}"
    if [ ! -x "$script" ]; then
      echo "    FAIL  $label (not executable -- chmod +x it)"
      status=1
      continue
    fi
    if "${parts[@]}" >/tmp/attune_conc.log 2>&1; then
      echo "    PASS  $label"
    else
      echo "    FAIL  $label"
      tail -5 /tmp/attune_conc.log | sed 's/^/      /'
      status=1
    fi
  done
fi

exit $status

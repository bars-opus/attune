# Supabase Contract Tests

These SQL files are database contract tests for Attune's security-critical
features. They are written to fail loudly with `RAISE EXCEPTION` when an
authorization, lifecycle, or RPC contract is violated.

Current coverage:

- `chat_system_contracts.sql`
  - chat message RLS
  - receipt RPC authorization
  - outbox table denial
  - translator/personal-insight visibility
  - safety resource RPC scoping
- `dating_mode_contracts.sql`
  - Dating feature flags fail closed
  - owner-only profile and enrollment reads
  - internal and raw-target RPC privilege denial
  - opaque introduction and match payload contracts
  - algorithm configuration review-gate constraints

Suggested execution flow in a local Supabase test database:

1. Reset/apply migrations.
2. Run the SQL file in a clean transaction.
3. Treat any exception as a failing contract.

The scripts intentionally use deterministic UUID fixtures and do not depend on
real production data.

## Running them

With a local Supabase stack running (`supabase start`):

```bash
scripts/run_sql_contracts.sh              # reset + apply migrations, run all
scripts/run_sql_contracts.sh --no-reset   # faster reruns against current schema
scripts/run_sql_contracts.sh chat_system  # run only matching files
```

The runner executes each file as a single transaction that `RAISE EXCEPTION`s
on any violated contract and then `ROLLBACK`s, so a green run persists nothing.
It uses a local `psql` if present, otherwise `docker exec` into the
`supabase_db_*` container.

`chat_system_contracts.sql` covers the four-account matrix: member read,
outsider read/insert denial, sender spoof denial, self-insert, sender-cannot-
receipt-own, recipient delivered/read, `read_at ⇒ delivered_at`, receipt-replay
monotonicity, outsider receipt-RPC denial, ended read-only (read allowed / send
blocked), and archived (read + receipt + insert all denied).

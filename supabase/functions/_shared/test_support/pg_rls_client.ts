// TEST-ONLY. A minimal SupabaseClient-shaped adapter backed by a real
// Postgres connection to the same throwaway database the SQL contract
// tests use (scripts/local_pg_setup.sh's attune_test), running every
// query as the `authenticated` role with `request.jwt.claims` set to a
// given user id -- i.e. real RLS, evaluated by real Postgres, exactly as
// supabase/tests/*.sql already proves RLS contracts, just driven from
// Deno instead of psql.
//
// Why this exists instead of a real supabase-js client against a real
// local Supabase stack: this environment has no Docker daemon, so
// `supabase start` (GoTrue + PostgREST) cannot run here, and no existing
// edge-function test in this repo fabricates real users via the Auth
// Admin API (grep confirms it -- user_scoped_client.test.ts explicitly
// defers that proof to this file, and no such helper exists anywhere
// else in supabase/functions/**). This adapter is the substitute: it is
// not a mock of RLS, it IS RLS -- the same Postgres engine, the same
// policies, the same `authenticated` role Supabase's PostgREST would
// run queries as, evaluated by an actual `SET LOCAL ROLE authenticated`
// plus the same request.jwt.claims GUC auth.uid() reads on the real
// platform. What it does NOT exercise is the HTTP/PostgREST layer
// itself or GoTrue token issuance -- those are Task 1's and infra's
// concerns, not this loader's.
//
// Only implements the fluent subset ai_context_loader.ts actually calls:
// .from().select().eq().maybeSingle() and
// .from().select().eq().lt/gt/gte/lt().order().order().limit().
//
// Task 5 extends this with .not()/.is() (analyse-message's and
// analyse-session's candidate queries use both) and a service-role
// constructor (makeServiceRoleClient) -- those two edge functions call
// serviceRoleClient() in production, not a per-user RLS client, so their
// test double must run as service_role (BYPASSRLS), not `authenticated`.

import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

export interface PgRow {
  [key: string]: unknown;
}

interface Filter {
  col: string;
  op: "eq" | "lt" | "gt" | "gte" | "lte" | "not_is_null" | "is_null" | "not_eq";
  value: unknown;
}

interface OrderClause {
  col: string;
  ascending: boolean;
}

class QueryBuilder {
  private filters: Filter[] = [];
  private orders: OrderClause[] = [];
  private limitCount: number | null = null;

  constructor(
    private readonly conn: RlsConnection,
    private readonly table: string,
    private readonly columns: string,
  ) {}

  eq(col: string, value: unknown): this {
    this.filters.push({ col, op: "eq", value });
    return this;
  }
  lt(col: string, value: unknown): this {
    this.filters.push({ col, op: "lt", value });
    return this;
  }
  gt(col: string, value: unknown): this {
    this.filters.push({ col, op: "gt", value });
    return this;
  }
  gte(col: string, value: unknown): this {
    this.filters.push({ col, op: "gte", value });
    return this;
  }
  lte(col: string, value: unknown): this {
    this.filters.push({ col, op: "lte", value });
    return this;
  }
  // Mirrors supabase-js's .not(col, "is", null) shape -- the only .not()
  // usage in analyse-message/index.ts and analyse-session/index.ts.
  not(col: string, op: string, value: unknown): this {
    if (op === "is" && value === null) {
      this.filters.push({ col, op: "not_is_null", value: null });
      return this;
    }
    throw new Error(`pg_rls_client test double: unsupported .not(${op}) shape`);
  }
  // Mirrors supabase-js's .is(col, null) shape.
  is(col: string, value: unknown): this {
    if (value === null) {
      this.filters.push({ col, op: "is_null", value: null });
      return this;
    }
    throw new Error(`pg_rls_client test double: .is() only supports null`);
  }
  order(col: string, opts?: { ascending?: boolean }): this {
    this.orders.push({ col, ascending: opts?.ascending ?? true });
    return this;
  }
  limit(n: number): this {
    this.limitCount = n;
    return this;
  }

  private buildSql(): { sql: string; params: unknown[] } {
    const params: unknown[] = [];
    const opSql: Record<Filter["op"], string> = {
      eq: "=",
      lt: "<",
      gt: ">",
      gte: ">=",
      lte: "<=",
      not_eq: "!=",
      is_null: "IS NULL",
      not_is_null: "IS NOT NULL",
    };
    const whereParts = this.filters.map((f) => {
      if (f.op === "is_null" || f.op === "not_is_null") {
        return `${quoteIdent(f.col)} ${opSql[f.op]}`;
      }
      params.push(f.value);
      return `${quoteIdent(f.col)} ${opSql[f.op]} $${params.length}`;
    });
    const where = whereParts.length ? `WHERE ${whereParts.join(" AND ")}` : "";
    const orderSql = this.orders.length
      ? `ORDER BY ${
        this.orders.map((o) => `${quoteIdent(o.col)} ${o.ascending ? "ASC" : "DESC"}`).join(", ")
      }`
      : "";
    const limitSql = this.limitCount != null ? `LIMIT ${this.limitCount}` : "";
    const sql = `SELECT ${translateSelectColumns(this.columns)} FROM ${
      quoteIdent(this.table)
    } ${where} ${orderSql} ${limitSql}`;
    return { sql, params };
  }

  // Thenable so `await query` (without .maybeSingle()) works like
  // supabase-js's default array-returning await.
  then<T>(
    onFulfilled: (value: { data: PgRow[] | null; error: null }) => T,
  ): Promise<T> {
    return this.exec().then(onFulfilled);
  }

  private async exec(): Promise<{ data: PgRow[] | null; error: null }> {
    const { sql, params } = this.buildSql();
    const rows = await this.conn.query(sql, params);
    return { data: rows, error: null };
  }

  async maybeSingle(): Promise<{ data: PgRow | null; error: null }> {
    const { data } = await this.exec();
    return { data: data && data.length > 0 ? data[0] : null, error: null };
  }
}

// Supports markMessageDone's shape:
// .from("messages").update(payload).eq(...).eq(...) -- awaited directly
// (no .select()), matching supabase-js's default { error } result.
class UpdateBuilder {
  private filters: Filter[] = [];

  constructor(
    private readonly conn: RlsConnection,
    private readonly table: string,
    private readonly payload: Record<string, unknown>,
  ) {}

  eq(col: string, value: unknown): this {
    this.filters.push({ col, op: "eq", value });
    return this;
  }

  then<T>(
    onFulfilled: (value: { data: null; error: null }) => T,
  ): Promise<T> {
    return this.exec().then(onFulfilled);
  }

  private async exec(): Promise<{ data: null; error: null }> {
    const params: unknown[] = [];
    const setCols = Object.entries(this.payload);
    const setSql = setCols
      .map(([col, value]) => {
        // nvc_violations is jsonb; the raw pg driver needs an explicit
        // cast for an array/object value passed as a JSON-text param
        // (mirrors what PostgREST does for a jsonb column write).
        const isJsonValue = Array.isArray(value) ||
          (typeof value === "object" && value !== null);
        params.push(isJsonValue ? JSON.stringify(value) : value);
        return isJsonValue
          ? `${quoteIdent(col)} = $${params.length}::jsonb`
          : `${quoteIdent(col)} = $${params.length}`;
      })
      .join(", ");
    const whereParts = this.filters.map((f) => {
      params.push(f.value);
      return `${quoteIdent(f.col)} = $${params.length}`;
    });
    const where = whereParts.length ? `WHERE ${whereParts.join(" AND ")}` : "";
    const sql = `UPDATE ${quoteIdent(this.table)} SET ${setSql} ${where}`;
    await this.conn.query(sql, params);
    return { data: null, error: null };
  }
}

// Rewrites PostgREST embed syntax in a .select() column string into a
// scalar-subselect JSON object, so the raw SQL adapter can execute it.
// Only handles the one embed shape actually used in this repo's
// analyse-*/index.ts files: `alias:table!fkey_name(cols)` where fkey_name
// is `<table>_<local_fk_column>_fkey` (Postgres's default constraint
// naming). This is a test double, not a PostgREST reimplementation --
// widen it only if a real query site starts using a different embed
// shape.
function translateSelectColumns(columns: string): string {
  const embedPattern = /(\w+):(\w+)!(\w+)_fkey\(([^)]*)\)/g;
  return columns.replace(embedPattern, (_match, alias, refTable, fkeyBody, innerCols) => {
    // fkeyBody is "<table>_<local_fk_column>", e.g.
    // "messages_sender_id" -> local column "sender_id".
    const localCol = fkeyBody.replace(/^\w+?_/, "");
    const cols = innerCols.split(",").map((c: string) => c.trim()).filter(Boolean);
    const jsonPairs = cols
      .map((c: string) => `'${c}', ${quoteIdent(refTable)}.${quoteIdent(c)}`)
      .join(", ");
    return `(SELECT jsonb_build_object(${jsonPairs}) FROM ${quoteIdent(refTable)} WHERE ${
      quoteIdent(refTable)
    }.id = ${quoteIdent(localCol)}) AS ${quoteIdent(alias)}`;
  });
}

function quoteIdent(ident: string): string {
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(ident)) {
    throw new Error(`refusing to quote suspicious identifier: ${ident}`);
  }
  return `"${ident}"`;
}

// Wraps a pooled connection so every statement runs inside its own
// transaction with SET LOCAL ROLE + the jwt claims GUC scoped to that
// transaction only (matching how a real PostgREST request establishes
// its Postgres session identity per-request).
class RlsConnection {
  constructor(
    private readonly client: Client,
    private readonly userId: string | null,
    // MUTATION-TESTING ONLY. When true, runs as `service_role`
    // (BYPASSRLS) instead of `authenticated` -- i.e. exactly the wrong
    // client ai_context_loader.ts must never be given. Exists solely so
    // the RLS-boundary mutation test can prove the non-member rejection
    // is really RLS's doing and not application logic, by temporarily
    // swapping the loader's client for one of these and watching the
    // negative test wrongly pass. Never set true outside that one test.
    private readonly bypassRls = false,
  ) {}

  async query(sql: string, params: unknown[]): Promise<PgRow[]> {
    await this.client.queryArray("BEGIN");
    try {
      if (this.bypassRls) {
        await this.client.queryArray("SET LOCAL ROLE service_role");
        if (this.userId) {
          await this.client.queryObject(
            `SELECT set_config('request.jwt.claims', $1, true)`,
            [JSON.stringify({ sub: this.userId, role: "service_role" })],
          );
        }
      } else if (this.userId) {
        await this.client.queryArray("SET LOCAL ROLE authenticated");
        await this.client.queryObject(
          `SELECT set_config('request.jwt.claims', $1, true)`,
          [JSON.stringify({ sub: this.userId, role: "authenticated" })],
        );
      } else {
        await this.client.queryArray("SET LOCAL ROLE anon");
      }
      const result = await this.client.queryObject<PgRow>(sql, params);
      await this.client.queryArray("COMMIT");
      // supabase-js/PostgREST serializes timestamptz columns as ISO
      // strings over JSON; the raw Deno postgres driver decodes them to
      // JS Date objects instead. Normalize back to ISO strings here so
      // this adapter's rows are shaped exactly like the real client's,
      // and ai_context_loader.ts's string-typed LoadedTarget/
      // ContextMessage fields (createdAt: string, compared with
      // .localeCompare) behave identically to production.
      return result.rows.map((row) => {
        const normalized: PgRow = {};
        for (const [key, value] of Object.entries(row)) {
          normalized[key] = value instanceof Date ? value.toISOString() : value;
        }
        return normalized;
      });
    } catch (err) {
      await this.client.queryArray("ROLLBACK");
      throw err;
    }
  }
}

// A SupabaseClient-shaped object backed by real Postgres + real RLS,
// scoped to one user id -- the same shape ai_context_loader.ts consumes
// (only `.from(table).select(cols)` is called, which then chains into
// QueryBuilder).
export class PgRlsClient {
  private readonly conn: RlsConnection;

  constructor(pgClient: Client, userId: string | null, bypassRls = false) {
    this.conn = new RlsConnection(pgClient, userId, bypassRls);
  }

  // deno-lint-ignore no-explicit-any
  from(table: string): any {
    return {
      select: (columns: string) => new QueryBuilder(this.conn, table, columns),
      update: (payload: Record<string, unknown>) =>
        new UpdateBuilder(this.conn, table, payload),
    };
  }
}

let sharedPgClient: Client | null = null;

export async function getSharedPgClient(): Promise<Client> {
  if (sharedPgClient) return sharedPgClient;
  const client = new Client({
    hostname: Deno.env.get("PGHOST") ?? "localhost",
    port: Number(Deno.env.get("PGPORT") ?? 5432),
    user: Deno.env.get("PGUSER") ?? Deno.env.get("USER") ?? "postgres",
    database: Deno.env.get("PGDATABASE") ?? "attune_test",
    password: Deno.env.get("PGPASSWORD") ?? undefined,
  });
  await client.connect();
  sharedPgClient = client;
  return client;
}

// Runs a query for TEST FIXTURE SETUP ONLY -- never used by the loader
// itself. Deliberately runs as the connecting superuser rather than
// `SET LOCAL ROLE service_role`: this harness's auth.users stub (see
// scripts/local_pg_bootstrap.sql) has no grants for service_role at all
// (real Supabase's GoTrue writes auth.users through its own internal
// path, not via service_role SQL, so no migration here ever needed to
// grant it), and granting new access to make fixture setup convenient
// would drift this throwaway harness from the real platform's grant
// shape for no proof-of-security benefit -- fixture setup is not part
// of what this test is trying to prove. RLS itself is never bypassed by
// this path in a way that matters: every actual assertion in this file
// reads through makeRlsClientForUser(), which is a real `authenticated`
// role subject to real RLS.
export async function serviceRoleQuery(
  sql: string,
  params: unknown[] = [],
): Promise<PgRow[]> {
  const client = await getSharedPgClient();
  await client.queryArray("BEGIN");
  try {
    const result = await client.queryObject<PgRow>(sql, params);
    await client.queryArray("COMMIT");
    return result.rows;
  } catch (err) {
    await client.queryArray("ROLLBACK");
    throw err;
  }
}

export async function makeRlsClientForUser(userId: string): Promise<PgRlsClient> {
  const pg = await getSharedPgClient();
  return new PgRlsClient(pg, userId);
}

// MUTATION-TESTING ONLY -- never call this from application code or
// from any test other than the RLS-boundary mutation test. Returns a
// client shaped identically to makeRlsClientForUser()'s, but backed by
// `service_role` (BYPASSRLS) instead of `authenticated`. Used to
// temporarily stand in for ai_context_loader.ts's `client` parameter to
// prove that the non-member rejection in
// "loadAiAssistantTarget returns TARGET_UNAVAILABLE for a message in a
// relationship the caller isn't in" is really RLS's doing: swap this in
// for that one code path, and the negative test should wrongly start
// passing (i.e. the non-member should be able to read the row), because
// nothing in loadAiAssistantTarget's own application logic checks
// relationship membership before the RLS-gated messages read -- RLS is
// the only thing making that read return nothing today.
export async function makeBypassRlsClientForUser(userId: string): Promise<PgRlsClient> {
  const pg = await getSharedPgClient();
  return new PgRlsClient(pg, userId, true);
}

// Task 5: analyse-message/index.ts and analyse-session/index.ts call
// serviceRoleClient() in production (a real service_role-keyed
// supabase-js client, which bypasses RLS entirely) -- not a per-user RLS
// client. This constructs the same PgRlsClient adapter running as
// `service_role` with no user id attached, matching that production
// identity for query-shape tests (candidate selection, mark-done
// exclusion) that don't need RLS to be exercised at all.
export async function makeServiceRoleClient(): Promise<PgRlsClient> {
  const pg = await getSharedPgClient();
  return new PgRlsClient(pg, null, true);
}

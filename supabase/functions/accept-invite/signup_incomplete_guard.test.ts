// Spec 1 W2 interim guard (batch 5 review I-5, until W4a): under
// flow_signin_v2 an account is created only at A5 (complete_sign_up, which
// needs a date of birth), so accept-invite and create-relationship-invite
// never create a users row: a caller with none gets 409 signup:incomplete
// and nothing is written. With the flag off, ensureUserRow runs as before.
// The guard is exercised through a fake client shaped like the supabase-js
// query chain; the two functions' wiring is checked in their source.
import { HttpError } from "../_shared/attune_auth.ts";
import { ensureInviteAccount, FLAGS_UNAVAILABLE, SIGN_IN_V2_FLAG, SIGNUP_INCOMPLETE } from "../_shared/sign_up_guard.ts";

type Result = { data: unknown; error: unknown } | Error;
type Op = { table: string; op: string; args: unknown[] };

const WRITES = ["insert", "upsert", "update", "delete", "rpc"];

function fakeClient(results: { flag: Result; users?: Result }) {
  const ops: Op[] = [];
  const client = {
    from(table: string) {
      const chain: Record<string, unknown> = {};
      for (const op of ["select", "eq", "insert", "upsert", "update", "delete", "in", "or", "is", "gt", "limit", "order"]) {
        chain[op] = (...args: unknown[]) => {
          ops.push({ table, op, args });
          return chain;
        };
      }
      chain.maybeSingle = () => {
        ops.push({ table, op: "maybeSingle", args: [] });
        const result = table === "feature_flags"
          ? results.flag
          : table === "users"
          ? results.users ?? { data: null, error: null }
          : { data: null, error: null };
        return result instanceof Error ? Promise.reject(result) : Promise.resolve(result);
      };
      return chain;
    },
    rpc(...args: unknown[]) {
      ops.push({ table: "", op: "rpc", args });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { ops, client };
}

function ensureUserRowSpy() {
  const spy = { calls: 0, run: () => Promise.resolve() };
  spy.run = () => {
    spy.calls++;
    return Promise.resolve();
  };
  return spy;
}

Deno.test("flag on, no users row: 409 signup:incomplete and nothing written", async () => {
  if (SIGN_IN_V2_FLAG !== "flow_signin_v2") throw new Error(`wrong flag key ${SIGN_IN_V2_FLAG}`);
  if (SIGNUP_INCOMPLETE !== "signup:incomplete") throw new Error(`wrong error code ${SIGNUP_INCOMPLETE}`);
  const { ops, client } = fakeClient({ flag: { data: { enabled: true }, error: null }, users: { data: null, error: null } });
  const ensureUserRow = ensureUserRowSpy();

  let refusal: unknown;
  try {
    await ensureInviteAccount(client, "u1", ensureUserRow.run);
  } catch (error) {
    refusal = error;
  }
  if (!(refusal instanceof HttpError)) throw new Error(`expected an HttpError, got ${refusal}`);
  if (refusal.status !== 409 || refusal.message !== "signup:incomplete") {
    throw new Error(`expected 409 signup:incomplete, got ${refusal.status} ${refusal.message}`);
  }
  if (ensureUserRow.calls !== 0) throw new Error("ensureUserRow ran with the flag on");
  const writes = ops.filter((o) => WRITES.includes(o.op));
  if (writes.length) throw new Error(`wrote with the flag on: ${JSON.stringify(writes)}`);
  const flagRead = ops.find((o) => o.table === "feature_flags" && o.op === "eq");
  if (flagRead?.args[1] !== "flow_signin_v2") throw new Error(`read the wrong flag: ${JSON.stringify(flagRead)}`);
  const userRead = ops.find((o) => o.table === "users" && o.op === "eq");
  if (userRead?.args[0] !== "id" || userRead?.args[1] !== "u1") {
    throw new Error(`looked up the wrong users row: ${JSON.stringify(userRead)}`);
  }
});

Deno.test("flag on, the users row exists: proceeds, still without writing", async () => {
  const { ops, client } = fakeClient({ flag: { data: { enabled: true }, error: null }, users: { data: { id: "u1" }, error: null } });
  const ensureUserRow = ensureUserRowSpy();

  await ensureInviteAccount(client, "u1", ensureUserRow.run);

  if (ensureUserRow.calls !== 0) throw new Error("ensureUserRow ran with the flag on");
  const writes = ops.filter((o) => WRITES.includes(o.op));
  if (writes.length) throw new Error(`wrote with the flag on: ${JSON.stringify(writes)}`);
});

Deno.test("flag on, the users read fails: the error, no write and no ensureUserRow", async () => {
  const readError = { message: "connection reset" };
  const { ops, client } = fakeClient({ flag: { data: { enabled: true }, error: null }, users: { data: null, error: readError } });
  const ensureUserRow = ensureUserRowSpy();

  let thrown: unknown;
  try {
    await ensureInviteAccount(client, "u1", ensureUserRow.run);
  } catch (error) {
    thrown = error;
  }
  if (thrown !== readError) throw new Error(`expected the read error, got ${thrown}`);
  if (ensureUserRow.calls !== 0) throw new Error("ensureUserRow ran with the flag on");
  if (ops.some((o) => WRITES.includes(o.op))) throw new Error("wrote after a failed read");
});

Deno.test("flag off, no users row: today's ensureUserRow runs, once, unguarded", async () => {
  for (const [label, flag] of [
    ["flag off", { data: { enabled: false }, error: null }],
    ["no flag row", { data: null, error: null }],
  ] as const) {
    const { ops, client } = fakeClient({ flag, users: { data: null, error: null } });
    const ensureUserRow = ensureUserRowSpy();

    await ensureInviteAccount(client, "u1", ensureUserRow.run);

    if (ensureUserRow.calls !== 1) throw new Error(`${label}: ensureUserRow ran ${ensureUserRow.calls} times`);
    if (ops.some((o) => o.table === "users")) throw new Error(`${label}: the guard read users itself`);
  }
});

// Fails closed (ruling after the B6 review): a flag that can't be read is
// never taken as off, which would let ensureUserRow create a row with no
// date of birth. 503 flags:unavailable, retryable; nothing read or written.
Deno.test("the flag can't be read: 503 flags:unavailable, no ensureUserRow, nothing written", async () => {
  if (FLAGS_UNAVAILABLE !== "flags:unavailable") throw new Error(`wrong error code ${FLAGS_UNAVAILABLE}`);
  for (const [label, flag] of [
    ["a read error", { data: null, error: { message: "permission denied" } }],
    ["a thrown read", new Error("network")],
  ] as const) {
    const { ops, client } = fakeClient({ flag, users: { data: null, error: null } });
    const ensureUserRow = ensureUserRowSpy();

    let refusal: unknown;
    try {
      await ensureInviteAccount(client, "u1", ensureUserRow.run);
    } catch (error) {
      refusal = error;
    }
    if (!(refusal instanceof HttpError)) throw new Error(`${label}: expected an HttpError, got ${refusal}`);
    if (refusal.status !== 503 || refusal.message !== "flags:unavailable") {
      throw new Error(`${label}: expected 503 flags:unavailable, got ${refusal.status} ${refusal.message}`);
    }
    if (ensureUserRow.calls !== 0) throw new Error(`${label}: ensureUserRow ran on an unreadable flag`);
    if (ops.some((o) => o.table === "users")) throw new Error(`${label}: read users on an unreadable flag`);
    if (ops.some((o) => WRITES.includes(o.op))) throw new Error(`${label}: wrote on an unreadable flag`);
  }
});

// The wiring: both functions call the guard, with their own unchanged
// ensureUserRow as the flag-off path, before any relationship is read or
// written, and never call ensureUserRow anywhere else.
Deno.test("both invite functions guard before any relationship read or write", async () => {
  for (const name of ["accept-invite", "create-relationship-invite"]) {
    const source = await Deno.readTextFile(new URL(`../${name}/index.ts`, import.meta.url));
    if (!source.includes('import { ensureInviteAccount } from "../_shared/sign_up_guard.ts";')) {
      throw new Error(`${name}: does not import the guard`);
    }
    const call = "await ensureInviteAccount(supabase, user.id, () => ensureUserRow(supabase, user));";
    const at = source.indexOf(call);
    if (at < 0) throw new Error(`${name}: does not call the guard with its ensureUserRow`);
    if (source.indexOf(call, at + 1) >= 0) throw new Error(`${name}: calls the guard twice`);
    const bare = source.split("\n").filter((line) => /ensureUserRow\(supabase, user\)/.test(line));
    if (bare.length !== 1) throw new Error(`${name}: ensureUserRow is called outside the guard: ${bare.join(" | ")}`);
    for (const later of ['.from("relationships")', '.from("relationship_invite_acceptances")', ".insert(", ".update("]) {
      const first = source.indexOf(later);
      if (first >= 0 && first < at) throw new Error(`${name}: ${later} comes before the guard`);
    }
    if (!source.includes("return jsonResponse({ error: error.message }, error.status);")) {
      throw new Error(`${name}: an HttpError no longer answers with its own status and message`);
    }
  }
});

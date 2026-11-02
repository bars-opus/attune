// Spec 1 W4a (§4.5, §5.6 R8, §7.2): accept-invite over
// accept_relationship_invite_v2. Every refusal code maps to today's status
// and message (the app parses them; the "You're already in a relationship"
// prefix is pinned), the code travels too, the push is queued once to the
// inviter and never on a replay, and a failed push never fails the accept.
// Since Task 1's fix rounds: every accept first spends the acceptor's
// shared attempt budget (note_invite_attempt; 429 invite:try_later past
// it), and a deadlock abort (40P01) is retried once without spending it
// again, then answers a retryable 503 invite:try_again.
import { HttpError } from "../_shared/attune_auth.ts";
import {
  ACCEPT_REFUSAL_CODES,
  acceptErrorResponse,
  acceptInvite,
  acceptRefusal,
  ALREADY_IN_RELATIONSHIP,
  InviteRefusal,
  normalizeInviteCode,
  TRY_AGAIN,
  TRY_LATER,
} from "./accept.ts";

type Answer = { data: unknown; error: unknown };

// [accept] is the accept's answer, or its answers in turn (the last one
// repeats). [attempt] is note_invite_attempt's (default: allowed); an
// Error rejects the call.
function fakeClient(
  accept: Answer | Answer[],
  opts: { eligibility?: string; pushFails?: boolean; attempt?: Answer | Error } = {},
) {
  const rpcs: { fn: string; params: Record<string, unknown> }[] = [];
  const pushes: Record<string, unknown>[] = [];
  const accepts = Array.isArray(accept) ? [...accept] : [accept];
  const client = {
    rpc(fn: string, params: Record<string, unknown>) {
      rpcs.push({ fn, params });
      if (fn === "relationship_invite_eligibility") {
        return Promise.resolve({ data: opts.eligibility ?? "ok", error: null });
      }
      if (fn === "note_invite_attempt") {
        const attempt = opts.attempt ?? { data: true, error: null };
        return attempt instanceof Error ? Promise.reject(attempt) : Promise.resolve(attempt);
      }
      if (fn !== "accept_relationship_invite_v2") throw new Error(`called ${fn}`);
      return Promise.resolve(accepts.length > 1 ? accepts.shift() : accepts[0]);
    },
    from(table: string) {
      if (table !== "scheduled_notifications") throw new Error(`read ${table}`);
      return {
        insert(row: Record<string, unknown>) {
          pushes.push(row);
          return {
            select: () =>
              Promise.resolve(
                opts.pushFails
                  ? { data: null, error: { code: "XX000" } }
                  : { data: [{ id: "n1" }], error: null },
              ),
          };
        },
      };
    },
  };
  return { rpcs, pushes, client };
}

const noRow = () => Promise.resolve();

async function refusalOf(run: () => Promise<unknown>): Promise<HttpError> {
  try {
    await run();
  } catch (error) {
    if (error instanceof HttpError) return error;
    throw error;
  }
  throw new Error("expected a refusal, got none");
}

Deno.test("every SQL refusal maps to today's status and message", () => {
  const expected: Record<string, [number, string]> = {
    "invite:invalid": [404, "Invite code is invalid"],
    "invite:own": [409, "You cannot accept your own invite"],
    "invite:expired": [410, "Invite code has expired"],
    "invite:already_accepted": [409, "Invite has already been accepted"],
    "invite:already_in_relationship": [409, ALREADY_IN_RELATIONSHIP],
    "invite:phone_required": [403, "invite:phone_required"],
    "invite:age_required": [428, "invite:age_required"],
    "invite:not_possible": [403, "invite:not_possible"],
    "account:hold": [403, "account:hold"],
  };
  if (JSON.stringify([...ACCEPT_REFUSAL_CODES].sort()) !== JSON.stringify(Object.keys(expected).sort())) {
    throw new Error(`mapped codes ${ACCEPT_REFUSAL_CODES}`);
  }
  for (const [code, [status, message]] of Object.entries(expected)) {
    const refusal = acceptRefusal(code);
    if (!(refusal instanceof InviteRefusal)) throw new Error(`${code} is not mapped`);
    if (refusal.status !== status || refusal.message !== message || refusal.code !== code) {
      throw new Error(`${code}: ${refusal.status} ${refusal.message} ${refusal.code}`);
    }
  }
  if (acceptRefusal("relationship:already_open") !== null) throw new Error("mapped a non-invite error");
  if (!ALREADY_IN_RELATIONSHIP.startsWith("You're already in a relationship")) {
    throw new Error("the prefix the app matches changed");
  }
});

Deno.test("the code: case-insensitive, spaces ignored, else 400", async () => {
  if (normalizeInviteCode(" k7p2 qm ") !== "K7P2QM") throw new Error("not normalised");
  if (normalizeInviteCode("K7") !== null || normalizeInviteCode(7) !== null) throw new Error("accepted a bad code");
  const { rpcs, client } = fakeClient({ data: null, error: null });
  const refusal = await refusalOf(() => acceptInvite(client, "u2", "K7", noRow));
  if (refusal.status !== 400) throw new Error(`got ${refusal.status}`);
  if (rpcs.length) throw new Error("asked the server about a malformed code");
});

Deno.test("an accept: one SQL call, the push to the inviter, today's answer", async () => {
  const { rpcs, pushes, client } = fakeClient({
    data: { relationship_id: "r1", status: "active", idempotent: false, inviter_id: "u1" },
    error: null,
  });
  const result = await acceptInvite(client, "u2", "k7p2qm", noRow);
  if (JSON.stringify(result) !== JSON.stringify({ relationship_id: "r1", status: "active", idempotent: false })) {
    throw new Error(`answered ${JSON.stringify(result)}`);
  }
  const accept = rpcs.find((c) => c.fn === "accept_relationship_invite_v2");
  if (JSON.stringify(accept?.params) !== JSON.stringify({ p_acceptor: "u2", p_invite_code: "K7P2QM" })) {
    throw new Error(`called ${JSON.stringify(accept)}`);
  }
  if (pushes.length !== 1 || pushes[0].user_id !== "u1" || pushes[0].source_key !== "invite_accepted:r1") {
    throw new Error(`pushed ${JSON.stringify(pushes)}`);
  }
  const meta = pushes[0].metadata as Record<string, unknown>;
  if (meta.type !== "invite_accepted" || meta.relationship_id !== "r1") {
    throw new Error(`push metadata ${JSON.stringify(meta)}`);
  }
});

Deno.test("a replay: idempotent, no second push", async () => {
  const { pushes, client } = fakeClient({
    data: { relationship_id: "r1", status: "active", idempotent: true, inviter_id: "u1" },
    error: null,
  });
  const result = await acceptInvite(client, "u2", "K7P2QM", noRow);
  if (!result.idempotent) throw new Error("not idempotent");
  if (pushes.length) throw new Error("pushed on a replay");
});

Deno.test("a failed push never fails the accept", async () => {
  const { client } = fakeClient(
    { data: { relationship_id: "r1", status: "active", idempotent: false, inviter_id: "u1" }, error: null },
    { pushFails: true },
  );
  const result = await acceptInvite(client, "u2", "K7P2QM", noRow);
  if (result.relationship_id !== "r1") throw new Error("the accept failed with the push");
});

Deno.test("a refusal answers its status, message and code, and pushes nothing", async () => {
  const { pushes, client } = fakeClient({ data: null, error: { message: "invite:already_in_relationship" } });
  const refusal = await refusalOf(() => acceptInvite(client, "u2", "K7P2QM", noRow));
  if (!(refusal instanceof InviteRefusal)) throw new Error("not an InviteRefusal");
  if (refusal.status !== 409 || !refusal.message.startsWith("You're already in a relationship")) {
    throw new Error(`got ${refusal.status} ${refusal.message}`);
  }
  if (refusal.code !== "invite:already_in_relationship") throw new Error(`code ${refusal.code}`);
  if (pushes.length) throw new Error("pushed after a refusal");
});

Deno.test("no account with the flag on: 409 signup:incomplete before the accept", async () => {
  const { rpcs, client } = fakeClient({ data: null, error: null }, { eligibility: "signup_incomplete" });
  const refusal = await refusalOf(() => acceptInvite(client, "u2", "K7P2QM", noRow));
  if (refusal.status !== 409 || refusal.message !== "signup:incomplete") {
    throw new Error(`got ${refusal.status} ${refusal.message}`);
  }
  if (rpcs.some((c) => c.fn === "accept_relationship_invite_v2")) throw new Error("accepted without an account");
});

Deno.test("an unexpected database error is not a refusal", async () => {
  const { client } = fakeClient({ data: null, error: { message: "deadlock detected" } });
  let thrown: unknown;
  try {
    await acceptInvite(client, "u2", "K7P2QM", noRow);
  } catch (error) {
    thrown = error;
  }
  if (thrown instanceof HttpError) throw new Error("a database error became a refusal");
  if (!thrown) throw new Error("no error");
});

const accepted = {
  data: { relationship_id: "r1", status: "active", idempotent: false, inviter_id: "u1" },
  error: null,
};
const deadlock = { data: null, error: { code: "40P01", message: "deadlock detected" } };
const callsTo = (rpcs: { fn: string }[], fn: string) => rpcs.filter((c) => c.fn === fn).length;

Deno.test("the attempt is spent once, for the acceptor, after the guard and before the accept", async () => {
  const { rpcs, client } = fakeClient(accepted);
  await acceptInvite(client, "u2", "K7P2QM", noRow);
  const order = rpcs.map((c) => c.fn).join(",");
  if (order !== "relationship_invite_eligibility,note_invite_attempt,accept_relationship_invite_v2") {
    throw new Error(`called ${order}`);
  }
  const attempt = rpcs.find((c) => c.fn === "note_invite_attempt");
  if (JSON.stringify(attempt?.params) !== JSON.stringify({ p_user: "u2" })) {
    throw new Error(`spent ${JSON.stringify(attempt)}`);
  }
});

Deno.test("past the attempt limit: 429 invite:try_later, and no accept", async () => {
  const { rpcs, pushes, client } = fakeClient(accepted, { attempt: { data: false, error: null } });
  const refusal = await refusalOf(() => acceptInvite(client, "u2", "K7P2QM", noRow));
  if (!(refusal instanceof InviteRefusal)) throw new Error("not an InviteRefusal");
  if (refusal.status !== 429 || refusal.message !== TRY_LATER || refusal.code !== TRY_LATER) {
    throw new Error(`got ${refusal.status} ${refusal.message} ${refusal.code}`);
  }
  if (TRY_LATER !== "invite:try_later") throw new Error(TRY_LATER);
  if (callsTo(rpcs, "accept_relationship_invite_v2")) throw new Error("accepted past the limit");
  if (pushes.length) throw new Error("pushed past the limit");
});

Deno.test("an attempt that can't be counted fails closed: no accept, not a refusal", async () => {
  for (const [label, attempt] of [
    ["an error", { data: null, error: { code: "42501", message: "permission denied" } }],
    ["a thrown call", new Error("network")],
    ["no answer", { data: null, error: null }],
    ["not a boolean", { data: "true", error: null }],
  ] as const) {
    const { rpcs, client } = fakeClient(accepted, { attempt });
    let thrown: unknown;
    try {
      await acceptInvite(client, "u2", "K7P2QM", noRow);
    } catch (error) {
      thrown = error;
    }
    if (!thrown) throw new Error(`${label}: accepted`);
    if (thrown instanceof HttpError) throw new Error(`${label}: became a refusal (${thrown.status})`);
    if (callsTo(rpcs, "accept_relationship_invite_v2")) throw new Error(`${label}: accepted uncounted`);
  }
});

Deno.test("a deadlock abort (40P01) is retried once, without spending a second attempt", async () => {
  const { rpcs, pushes, client } = fakeClient([deadlock, accepted]);
  const result = await acceptInvite(client, "u2", "K7P2QM", noRow);
  if (result.relationship_id !== "r1" || result.idempotent) throw new Error(`answered ${JSON.stringify(result)}`);
  if (callsTo(rpcs, "accept_relationship_invite_v2") !== 2) {
    throw new Error(`accepted ${callsTo(rpcs, "accept_relationship_invite_v2")} times`);
  }
  if (callsTo(rpcs, "note_invite_attempt") !== 1) {
    throw new Error(`spent ${callsTo(rpcs, "note_invite_attempt")} attempts`);
  }
  const accepts = rpcs.filter((c) => c.fn === "accept_relationship_invite_v2");
  if (JSON.stringify(accepts[0].params) !== JSON.stringify(accepts[1].params)) {
    throw new Error("the retry changed the call");
  }
  if (pushes.length !== 1) throw new Error(`pushed ${pushes.length} times`);
});

Deno.test("a second deadlock: a retryable 503 invite:try_again, no third try, no push", async () => {
  const { rpcs, pushes, client } = fakeClient([deadlock, deadlock, accepted]);
  const refusal = await refusalOf(() => acceptInvite(client, "u2", "K7P2QM", noRow));
  if (!(refusal instanceof InviteRefusal)) throw new Error("not an InviteRefusal");
  if (refusal.status !== 503 || refusal.message !== TRY_AGAIN || refusal.code !== TRY_AGAIN) {
    throw new Error(`got ${refusal.status} ${refusal.message} ${refusal.code}`);
  }
  if (TRY_AGAIN !== "invite:try_again") throw new Error(TRY_AGAIN);
  if (callsTo(rpcs, "accept_relationship_invite_v2") !== 2) {
    throw new Error(`accepted ${callsTo(rpcs, "accept_relationship_invite_v2")} times`);
  }
  if (callsTo(rpcs, "note_invite_attempt") !== 1) throw new Error("spent a second attempt");
  if (pushes.length) throw new Error("pushed after a deadlock");
});

Deno.test("a refusal on the retry is still the refusal", async () => {
  const { rpcs, client } = fakeClient([deadlock, { data: null, error: { message: "invite:already_accepted" } }]);
  const refusal = await refusalOf(() => acceptInvite(client, "u2", "K7P2QM", noRow));
  if (refusal.status !== 409 || refusal.message !== "Invite has already been accepted") {
    throw new Error(`got ${refusal.status} ${refusal.message}`);
  }
  if (callsTo(rpcs, "accept_relationship_invite_v2") !== 2) throw new Error("not retried");
});

// Fix round 1 (review m1): only 40P01 is retried. A refusal, a code-less
// error (a lost response may already have committed) and any other
// SQLSTATE are answered after one call.
Deno.test("only a deadlock is retried: anything else is one call", async () => {
  for (const [label, answer] of [
    ["a refusal", { data: null, error: { message: "invite:invalid" } }],
    ["a code-less error", { data: null, error: { message: "fetch failed" } }],
    ["another SQLSTATE", { data: null, error: { code: "57014", message: "canceling statement" } }],
  ] as const) {
    const { rpcs, client } = fakeClient([answer, accepted]);
    try {
      await acceptInvite(client, "u2", "K7P2QM", noRow);
    } catch {
      // each answers an error; only the call count matters here
    }
    const n = callsTo(rpcs, "accept_relationship_invite_v2");
    if (n !== 1) throw new Error(`${label}: accepted ${n} times`);
  }
});

// Fix round 1 (review m4): the codes come from the SQL itself, so a new
// RAISE in a later accept_relationship_invite_v2 can't silently be a 500.
Deno.test("every code the newest accept_relationship_invite_v2 raises is mapped, and only those", async () => {
  const dir = new URL("../../migrations/", import.meta.url);
  const names: string[] = [];
  for await (const entry of Deno.readDir(dir)) if (entry.name.endsWith(".sql")) names.push(entry.name);
  names.sort();
  const head = "CREATE OR REPLACE FUNCTION public.accept_relationship_invite_v2(";
  let body: string | null = null;
  let from = "";
  for (const name of names) {
    const sql = await Deno.readTextFile(new URL(name, dir));
    const at = sql.lastIndexOf(head);
    if (at < 0) continue;
    const open = sql.indexOf("AS $$", at);
    const close = sql.indexOf("$$;", open + 5);
    if (open < 0 || close < 0) throw new Error(`${name}: no body`);
    body = sql.slice(open, close);
    from = name;
  }
  if (!body) throw new Error("no migration defines accept_relationship_invite_v2");
  const raised = new Set([...body.matchAll(/RAISE EXCEPTION '([a-z_]+:[a-z_]+)'/g)].map((m) => m[1]));
  if (raised.size < 9) throw new Error(`${from}: read only ${[...raised]}`);
  const mapped = new Set(ACCEPT_REFUSAL_CODES);
  const unmapped = [...raised].filter((code) => !mapped.has(code));
  const stale = [...mapped].filter((code) => !raised.has(code));
  if (unmapped.length || stale.length) {
    throw new Error(`${from}: unmapped ${unmapped}; mapped but never raised ${stale}`);
  }
});

function captureLogs() {
  const lines: string[] = [];
  const saved = { error: console.error, warn: console.warn, log: console.log };
  const keep = (...args: unknown[]) => {
    lines.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a) ?? String(a))).join(" "));
  };
  console.error = keep;
  console.warn = keep;
  console.log = keep;
  return { lines, restore: () => Object.assign(console, saved) };
}

// Fix round 1 (review m2): the bodies, parsed, not the source text.
Deno.test("a refusal answers {error, code} with its status; a plain HttpError {error}", async () => {
  for (const refusal of [acceptRefusal("account:hold")!, new InviteRefusal(TRY_LATER, 429, TRY_LATER), new InviteRefusal(TRY_AGAIN, 503, TRY_AGAIN)]) {
    const response = acceptErrorResponse(refusal);
    const body = await response.json();
    if (response.status !== refusal.status) throw new Error(`${refusal.code}: status ${response.status}`);
    if (JSON.stringify(body) !== JSON.stringify({ error: refusal.message, code: refusal.code })) {
      throw new Error(`${refusal.code}: body ${JSON.stringify(body)}`);
    }
  }
  const plain = acceptErrorResponse(new HttpError("Invite code is required", 400));
  const body = await plain.json();
  if (plain.status !== 400 || JSON.stringify(body) !== JSON.stringify({ error: "Invite code is required" })) {
    throw new Error(`plain: ${plain.status} ${JSON.stringify(body)}`);
  }
});

// Fix round 1 (review m3): a 500 logs its step and SQLSTATE, never the
// database's text (which can carry the invite code or a phone).
Deno.test("a 500 logs the step and the SQLSTATE only", async () => {
  const leaky = {
    message: "new row violates check: Failing row contains (K7P2QM, +233201234567, Ama)",
    details: "Failing row contains (K7P2QM, +233201234567, Ama)",
    hint: "K7P2QM",
  };
  for (const [label, client, step, code] of [
    ["the accept", fakeClient({ data: null, error: { code: "23514", ...leaky } }).client, "accept", "23514"],
    ["the attempt", fakeClient(accepted, { attempt: { data: null, error: { code: "42501", ...leaky } } }).client, "attempt", "42501"],
    ["a thrown attempt", fakeClient(accepted, { attempt: new Error("connect to +233201234567 K7P2QM failed") }).client, "attempt", "none"],
    ["an odd answer", fakeClient({ data: { status: "K7P2QM" }, error: null }).client, "accept", "unexpected_answer"],
  ] as const) {
    const logs = captureLogs();
    let response: Response;
    try {
      try {
        await acceptInvite(client, "u2", "K7P2QM", noRow);
        throw new Error(`${label}: no error`);
      } catch (error) {
        response = acceptErrorResponse(error);
      }
    } finally {
      logs.restore();
    }
    const body = await response.json();
    if (response.status !== 500 || body.error !== "Could not accept invite" || "code" in body) {
      throw new Error(`${label}: ${response.status} ${JSON.stringify(body)}`);
    }
    const text = logs.lines.join("\n");
    if (!text.includes(`step=${step}`) || !text.includes(`sqlstate=${code}`)) throw new Error(`${label}: logged ${text}`);
    for (const secret of ["K7P2QM", "+233", "Ama", "Failing row"]) {
      if (text.includes(secret)) throw new Error(`${label}: logged ${secret}`);
    }
  }
});

Deno.test("an error from outside the steps (e.g. the legacy users row) logs its SQLSTATE only", async () => {
  const leaky = "Failing row contains (K7P2QM, +233201234567, Ama)";
  const error = Object.assign(new Error(`new row violates check: ${leaky}`), { code: "23514", details: leaky });
  const logs = captureLogs();
  let response: Response;
  try {
    response = acceptErrorResponse(error);
  } finally {
    logs.restore();
  }
  if (response.status !== 500) throw new Error(`status ${response.status}`);
  await response.body?.cancel();
  const text = logs.lines.join("\n");
  if (!text.includes("step=unknown") || !text.includes("sqlstate=23514")) throw new Error(`logged ${text}`);
  for (const secret of ["K7P2QM", "+233", "Ama", "Failing row", "violates"]) {
    if (text.includes(secret)) throw new Error(`logged ${secret}`);
  }
});

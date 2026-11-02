// Spec 1 W4a (§4.5; replaces the W2 interim guard's tests). Both invite
// functions ask public.relationship_invite_eligibility first: legacy runs
// today's ensureUserRow; with flow_signin_v2 on, no users row is ever made
// (D8): no account is 409 signup:incomplete; the inviter's age rule is 428
// / 403; an unreadable answer is 503 flags:unavailable, never legacy.
import { HttpError } from "../_shared/attune_auth.ts";
import {
  AGE_REQUIRED,
  ensureInviteAccount,
  FLAGS_UNAVAILABLE,
  NOT_POSSIBLE,
  requireInviterAge,
  SIGNUP_INCOMPLETE,
} from "../_shared/sign_up_guard.ts";

type Answer = { data: unknown; error: unknown } | Error;

function fakeClient(answer: Answer) {
  const calls: { fn: string; params: unknown }[] = [];
  const tables: string[] = [];
  const client = {
    rpc(fn: string, params: unknown) {
      calls.push({ fn, params });
      return answer instanceof Error ? Promise.reject(answer) : Promise.resolve(answer);
    },
    from(table: string) {
      tables.push(table);
      throw new Error(`the guard read ${table} itself`);
    },
  };
  return { calls, tables, client };
}

function ensureUserRowSpy() {
  const spy = { calls: 0, run: () => Promise.resolve() };
  spy.run = () => {
    spy.calls++;
    return Promise.resolve();
  };
  return spy;
}

async function refusalOf(run: () => Promise<unknown>): Promise<HttpError> {
  try {
    await run();
  } catch (error) {
    if (error instanceof HttpError) return error;
    throw error;
  }
  throw new Error("expected a refusal, got none");
}

Deno.test("the codes are the app's", () => {
  if (SIGNUP_INCOMPLETE !== "signup:incomplete") throw new Error(SIGNUP_INCOMPLETE);
  if (FLAGS_UNAVAILABLE !== "flags:unavailable") throw new Error(FLAGS_UNAVAILABLE);
  if (AGE_REQUIRED !== "invite:age_required") throw new Error(AGE_REQUIRED);
  if (NOT_POSSIBLE !== "invite:not_possible") throw new Error(NOT_POSSIBLE);
});

Deno.test("legacy (flag off): today's ensureUserRow runs once", async () => {
  const { calls, client } = fakeClient({ data: "legacy", error: null });
  const ensureUserRow = ensureUserRowSpy();
  const answer = await ensureInviteAccount(client, "u1", ensureUserRow.run);
  if (answer !== "legacy") throw new Error(`answered ${answer}`);
  if (ensureUserRow.calls !== 1) throw new Error(`ensureUserRow ran ${ensureUserRow.calls} times`);
  if (calls.length !== 1 || calls[0].fn !== "relationship_invite_eligibility") {
    throw new Error(`asked ${JSON.stringify(calls)}`);
  }
  if (JSON.stringify(calls[0].params) !== JSON.stringify({ p_user: "u1" })) {
    throw new Error(`asked for ${JSON.stringify(calls[0].params)}`);
  }
});

Deno.test("flag on, no account: 409 signup:incomplete and no ensureUserRow (D8)", async () => {
  const { client } = fakeClient({ data: "signup_incomplete", error: null });
  const ensureUserRow = ensureUserRowSpy();
  const refusal = await refusalOf(() => ensureInviteAccount(client, "u1", ensureUserRow.run));
  if (refusal.status !== 409 || refusal.message !== "signup:incomplete") {
    throw new Error(`got ${refusal.status} ${refusal.message}`);
  }
  if (ensureUserRow.calls !== 0) throw new Error("ensureUserRow ran with the flag on");
});

Deno.test("flag on, an account: the answer, and no ensureUserRow", async () => {
  for (const answer of ["ok", "age_required", "not_possible"] as const) {
    const { client } = fakeClient({ data: answer, error: null });
    const ensureUserRow = ensureUserRowSpy();
    const got = await ensureInviteAccount(client, "u1", ensureUserRow.run);
    if (got !== answer) throw new Error(`${answer}: answered ${got}`);
    if (ensureUserRow.calls !== 0) throw new Error(`${answer}: ensureUserRow ran`);
  }
});

Deno.test("an unreadable answer fails closed: 503 flags:unavailable, no ensureUserRow", async () => {
  for (const [label, answer] of [
    ["an error", { data: null, error: { message: "permission denied" } }],
    ["a thrown call", new Error("network")],
    ["an unknown answer", { data: "maybe", error: null }],
    ["no answer", { data: null, error: null }],
  ] as const) {
    const { client } = fakeClient(answer);
    const ensureUserRow = ensureUserRowSpy();
    const refusal = await refusalOf(() => ensureInviteAccount(client, "u1", ensureUserRow.run));
    if (refusal.status !== 503 || refusal.message !== "flags:unavailable") {
      throw new Error(`${label}: got ${refusal.status} ${refusal.message}`);
    }
    if (ensureUserRow.calls !== 0) throw new Error(`${label}: ensureUserRow ran`);
  }
});

Deno.test("the inviter's age rule: 428 without a date of birth, 403 under 18", async () => {
  const missing = await refusalOf(async () => requireInviterAge("age_required"));
  if (missing.status !== 428 || missing.message !== "invite:age_required") {
    throw new Error(`got ${missing.status} ${missing.message}`);
  }
  const minor = await refusalOf(async () => requireInviterAge("not_possible"));
  if (minor.status !== 403 || minor.message !== "invite:not_possible") {
    throw new Error(`got ${minor.status} ${minor.message}`);
  }
  requireInviterAge("ok");
  requireInviterAge("legacy");
});

// The wiring: create-relationship-invite asks first, applies the age rule
// at once, and reads or writes nothing before; accept-invite asks before
// its one SQL call. ensureUserRow is only ever the guard's flag-off path.
Deno.test("both invite functions ask before any relationship read or write", async () => {
  const create = await Deno.readTextFile(new URL("../create-relationship-invite/index.ts", import.meta.url));
  if (!create.includes('import { ensureInviteAccount, requireInviterAge } from "../_shared/sign_up_guard.ts";')) {
    throw new Error("create-relationship-invite: does not import the guard and the age rule");
  }
  const call = "const eligibility = await ensureInviteAccount(supabase, user.id, () => ensureUserRow(supabase, user));\n    requireInviterAge(eligibility);";
  const at = create.indexOf(call);
  if (at < 0) throw new Error("create-relationship-invite: does not ask, then apply the age rule");
  for (const later of ['.from("relationships")', ".insert(", ".update("]) {
    const first = create.indexOf(later);
    if (first >= 0 && first < at) throw new Error(`create-relationship-invite: ${later} comes before the guard`);
  }
  const bare = create.split("\n").filter((line) => /ensureUserRow\(supabase, user\)/.test(line));
  if (bare.length !== 1) throw new Error(`create-relationship-invite: ensureUserRow outside the guard: ${bare.join(" | ")}`);

  const accept = await Deno.readTextFile(new URL("./accept.ts", import.meta.url));
  const guard = accept.indexOf("await ensureInviteAccount(supabase, userId, ensureUserRow);");
  const rpc = accept.indexOf('supabase.rpc("accept_relationship_invite_v2"');
  if (guard < 0 || rpc < 0 || guard > rpc) throw new Error("accept-invite: the guard does not come before the accept");
  // Task 1 fix round 1: the shared attempt budget is spent after the guard
  // and before the accept (a refused accept rolls back its own count).
  const attempt = accept.indexOf('supabase.rpc("note_invite_attempt"');
  if (attempt < guard || attempt > rpc) throw new Error("accept-invite: the attempt is not spent between the guard and the accept");
  if (accept.includes('.from("relationships")') || accept.includes('.from("relationship_invite_acceptances")')) {
    throw new Error("accept-invite still reads or writes relationships itself (D7: the SQL function does)");
  }
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!index.includes("() => ensureUserRow(supabase, user),")) {
    throw new Error("accept-invite: ensureUserRow is not handed to the guard");
  }
});

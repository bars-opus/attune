// Spec 1 W4a (§4.5; replaces the W2 interim guard's tests), entry gates
// 2026-11-27. Both invite functions ask public.relationship_invite_eligibility
// first, whatever flow_signin_v2 says, and no users row is ever made here
// (D8): no account or no current consent is 409 signup:incomplete; the
// inviter's age rule is 428 / 403; an unreadable answer (the retired
// 'legacy' among them) is 503 flags:unavailable.
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

Deno.test("the retired legacy answer fails closed: 503, nothing created", async () => {
  const { calls, tables, client } = fakeClient({ data: "legacy", error: null });
  const refusal = await refusalOf(() => ensureInviteAccount(client, "u1"));
  if (refusal.status !== 503 || refusal.message !== "flags:unavailable") {
    throw new Error(`got ${refusal.status} ${refusal.message}`);
  }
  if (calls.length !== 1 || calls[0].fn !== "relationship_invite_eligibility") {
    throw new Error(`asked ${JSON.stringify(calls)}`);
  }
  if (JSON.stringify(calls[0].params) !== JSON.stringify({ p_user: "u1" })) {
    throw new Error(`asked for ${JSON.stringify(calls[0].params)}`);
  }
  if (tables.length) throw new Error(`touched ${tables}`);
});

Deno.test("no account, or no current consent: 409 signup:incomplete, nothing created (D8)", async () => {
  for (const answer of ["signup_incomplete", "consent_required"] as const) {
    const { tables, client } = fakeClient({ data: answer, error: null });
    const refusal = await refusalOf(() => ensureInviteAccount(client, "u1"));
    if (refusal.status !== 409 || refusal.message !== "signup:incomplete") {
      throw new Error(`${answer}: got ${refusal.status} ${refusal.message}`);
    }
    if (tables.length) throw new Error(`${answer}: touched ${tables}`);
  }
});

Deno.test("an account: the answer, for the caller's age rule", async () => {
  for (const answer of ["ok", "age_required", "not_possible"] as const) {
    const { tables, client } = fakeClient({ data: answer, error: null });
    const got = await ensureInviteAccount(client, "u1");
    if (got !== answer) throw new Error(`${answer}: answered ${got}`);
    if (tables.length) throw new Error(`${answer}: touched ${tables}`);
  }
});

Deno.test("an unreadable answer fails closed: 503 flags:unavailable", async () => {
  for (const [label, answer] of [
    ["an error", { data: null, error: { message: "permission denied" } }],
    ["a thrown call", new Error("network")],
    ["an unknown answer", { data: "maybe", error: null }],
    ["no answer", { data: null, error: null }],
  ] as const) {
    const { client } = fakeClient(answer);
    const refusal = await refusalOf(() => ensureInviteAccount(client, "u1"));
    if (refusal.status !== 503 || refusal.message !== "flags:unavailable") {
      throw new Error(`${label}: got ${refusal.status} ${refusal.message}`);
    }
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
});

// The wiring: create-relationship-invite asks first, applies the age rule
// at once, and reads or writes nothing before; accept-invite asks before
// its one SQL call. Neither has a users-row writer any more.
Deno.test("both invite functions ask before any relationship read or write", async () => {
  const create = await Deno.readTextFile(new URL("../create-relationship-invite/index.ts", import.meta.url));
  if (!create.includes('import { ensureInviteAccount, requireInviterAge } from "../_shared/sign_up_guard.ts";')) {
    throw new Error("create-relationship-invite: does not import the guard and the age rule");
  }
  const call = "const eligibility = await ensureInviteAccount(supabase, user.id);\n    requireInviterAge(eligibility);";
  const at = create.indexOf(call);
  if (at < 0) throw new Error("create-relationship-invite: does not ask, then apply the age rule");
  for (const later of ['.from("relationships")', ".insert(", ".update("]) {
    const first = create.indexOf(later);
    if (first >= 0 && first < at) throw new Error(`create-relationship-invite: ${later} comes before the guard`);
  }

  const accept = await Deno.readTextFile(new URL("./accept.ts", import.meta.url));
  const guard = accept.indexOf("await ensureInviteAccount(supabase, userId);");
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
  if (!index.includes("await acceptInvite(supabase, user.id, body.invite_code);")) {
    throw new Error("accept-invite: index does not hand the call to acceptInvite");
  }
});

// Sync audit I-8: nobody in an active or paused relationship accepts or
// makes an invite. Since Spec 1 W4a the accept's check is inside
// accept_relationship_invite_v2 (invite_v2_contracts.sql) and its refusal
// keeps today's readable 409 (accept.test.ts); create-relationship-invite
// still checks for itself. The database guard
// (relationship_one_open_chapter_guard, sync_fixes_contracts) stays the
// real boundary.
const accept = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const create = await Deno.readTextFile(new URL("../create-relationship-invite/index.ts", import.meta.url));

Deno.test("create-relationship-invite refuses a paused person too", () => {
  if (!create.includes('.in("status", ["active", "paused"])')) {
    throw new Error("create-relationship-invite still checks active only");
  }
});

// Entry gates 2026-11-27 (D8): the service-role safety net that created a
// missing users row (ensureUserRow, flow_signin_v2 off) is gone. Only
// complete_sign_up makes a users row; neither invite function touches the
// table at all.
Deno.test("neither invite function creates (or reads) a users row", () => {
  for (const [name, source] of [["accept-invite", accept], ["create-relationship-invite", create]]) {
    if (source.includes("ensureUserRow")) throw new Error(`${name}: ensureUserRow is back`);
    if (/\.from\(\s*["']users["']\s*\)/.test(source)) throw new Error(`${name}: touches public.users`);
    if (/\.upsert\(/.test(source)) throw new Error(`${name}: upserts something`);
  }
});

// W4 batch 2 fix round 1 (review m2, m3; the create log ruling): what an
// error answers and logs is tested on the bodies themselves
// (accept.test.ts acceptErrorResponse, create-relationship-invite/
// errors.test.ts); here, only that both functions answer through them.
Deno.test("both functions answer every error through their tested responders", () => {
  for (const [name, source, responder] of [
    ["accept-invite", accept, "return acceptErrorResponse(error);"],
    ["create-relationship-invite", create, "return createErrorResponse(error);"],
  ]) {
    if (!source.includes(responder)) throw new Error(`${name}: errors don't go through ${responder}`);
    if (/console\.(error|warn|log)\(/.test(source)) throw new Error(`${name}: logs outside its responder`);
    if (/function handleError\(/.test(source)) throw new Error(`${name}: still has its own handleError`);
  }
});

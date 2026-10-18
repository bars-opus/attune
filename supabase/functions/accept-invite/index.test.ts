// Sync audit I-8: nobody in an active or paused relationship accepts or
// makes an invite. Accepting while paused used to end and archive the
// paused space silently. The database guard
// (relationship_one_open_chapter_guard, sync_fixes_contracts) is the real
// boundary; these functions answer it with a clean 409.
const accept = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const create = await Deno.readTextFile(new URL("../create-relationship-invite/index.ts", import.meta.url));

Deno.test("accept-invite refuses someone already in an open relationship", () => {
  const guard = accept.indexOf('.in("status", ["active", "paused"])');
  if (guard < 0) throw new Error("accept-invite does not check the acceptor's relationships");
  if (guard > accept.indexOf(".update({")) throw new Error("the check comes after the update");
  if (!accept.includes("End it first to join a new one.")) throw new Error("no readable 409");
  if (!accept.includes("relationship:already_open")) throw new Error("the database guard's refusal is not mapped");
});

Deno.test("create-relationship-invite refuses a paused person too", () => {
  if (!create.includes('.in("status", ["active", "paused"])')) {
    throw new Error("create-relationship-invite still checks active only");
  }
});

// Spec 2 W3a (§3.13, R-7): the push's data allowlist carries the neutral
// Dating push's only key, {"route": "me"}, and names nothing Dating.
const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("privacySafeData keeps 'route' and no Dating-named key", () => {
  const start = src.indexOf("function privacySafeData");
  const end = src.indexOf("return Object.fromEntries", start);
  if (start < 0 || end < 0) throw new Error("privacySafeData not found");
  const list = src.slice(start, end);
  if (!/"route",/.test(list)) throw new Error("'route' is not in the allowlist");
  if (/"dating/i.test(list)) throw new Error("a Dating-named key is in the allowlist");
});

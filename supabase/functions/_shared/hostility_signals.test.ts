// Spec 8 (plan review I14): one flag, off by default, gates the stonewalling
// and contempt signals everywhere; an unreadable flag is off.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { HOSTILITY_FLAG, hostilitySignalsEnabled } from "./hostility_signals.ts";

function client(result: { data: unknown; error: unknown }) {
  const seen: unknown[] = [];
  const builder = {
    select: () => builder,
    eq: (_c: string, v: unknown) => {
      seen.push(v);
      return builder;
    },
    maybeSingle: () => Promise.resolve(result),
  };
  return { from: () => builder, seen };
}

Deno.test("on only when the flag row says so", async () => {
  const on = client({ data: { enabled: true }, error: null });
  assertEquals(await hostilitySignalsEnabled(on as never), true);
  assertEquals(on.seen, [HOSTILITY_FLAG]);
  assertEquals(await hostilitySignalsEnabled(client({ data: { enabled: false }, error: null }) as never), false);
  assertEquals(await hostilitySignalsEnabled(client({ data: null, error: null }) as never), false);
  assertEquals(await hostilitySignalsEnabled(client({ data: null, error: { message: "x" } }) as never), false);
});

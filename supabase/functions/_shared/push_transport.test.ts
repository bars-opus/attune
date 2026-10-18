// supabase/functions/_shared/push_transport.test.ts
// Spec 1b: the worker (process-scheduled-notifications) is the only OneSignal
// caller, so quiet hours and the no-titles copy guard -- both triggers on
// scheduled_notifications -- cover every push. A function that wants to
// notify someone calls enqueuePush.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const root = new URL("../", import.meta.url);

async function* sources(dir: URL): AsyncGenerator<URL> {
  for await (const e of Deno.readDir(dir)) {
    if (e.isDirectory) {
      yield* sources(new URL(`${e.name}/`, dir));
    } else if (e.name.endsWith(".ts") && !e.name.endsWith(".test.ts")) {
      yield new URL(e.name, dir);
    }
  }
}

Deno.test("only the worker sends pushes; nothing else reaches OneSignal", async () => {
  const offenders: string[] = [];
  for await (const file of sources(root)) {
    const rel = file.pathname.slice(root.pathname.length);
    if (rel === "_shared/onesignal_push.ts") continue;
    const src = await Deno.readTextFile(file);
    if (src.includes("api.onesignal.com")) offenders.push(`${rel}: calls the OneSignal API`);
    if (src.includes("sendOneSignalPush") && rel !== "process-scheduled-notifications/index.ts") {
      offenders.push(`${rel}: sendOneSignalPush`);
    }
  }
  assertEquals(offenders, []);
});

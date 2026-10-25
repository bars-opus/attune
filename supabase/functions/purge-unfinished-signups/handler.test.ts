// Spec 1 W1c: the unfinished sign-up purge, against a fake client.
import { candidateIds, type PurgeClient, purgeUnfinishedSignups } from "./handler.ts";

const A = "5f1a0000-0000-0000-0000-0000000000a1";
const B = "5f1a0000-0000-0000-0000-0000000000b2";
const C = "5f1a0000-0000-0000-0000-0000000000c3";

interface FakeOptions {
  failFor?: string[];
  rpcError?: boolean;
  recheckFalseFor?: string[];
  recheckErrorFor?: string[];
}

function fakeClient(rows: unknown, options: FakeOptions = {}) {
  const { failFor = [], rpcError = false, recheckFalseFor = [], recheckErrorFor = [] } = options;
  const deleted: string[] = [];
  const calls: string[] = [];
  const client: PurgeClient = {
    rpc(fn, args) {
      if (fn === "unfinished_signup_candidates") {
        return Promise.resolve(rpcError ? { data: null, error: { message: "boom" } } : { data: rows, error: null });
      }
      if (fn === "is_unfinished_signup") {
        const id = String(args?.p_user_id);
        calls.push(`check:${id}`);
        if (recheckErrorFor.includes(id)) return Promise.resolve({ data: null, error: { message: "boom" } });
        return Promise.resolve({ data: !recheckFalseFor.includes(id), error: null });
      }
      throw new Error(`unexpected rpc ${fn}`);
    },
    auth: {
      admin: {
        deleteUser(id) {
          calls.push(`delete:${id}`);
          if (failFor.includes(id)) return Promise.resolve({ error: { message: "nope" } });
          if (id === C) return Promise.reject(new Error("network"));
          deleted.push(id);
          return Promise.resolve({ error: null });
        },
      },
    },
  };
  return { client, deleted, calls };
}

Deno.test("every candidate is deleted once; failures are counted, never thrown", async () => {
  const { client, deleted } = fakeClient([A, B, C], { failFor: [B] });
  const result = await purgeUnfinishedSignups(client);
  if (JSON.stringify(result) !== JSON.stringify({ candidates: 3, deleted: 1, failed: 2, skipped: 0, remaining: 0 })) {
    throw new Error(`unexpected result ${JSON.stringify(result)}`);
  }
  if (deleted.join(",") !== A) throw new Error(`deleted ${deleted.join(",")}`);
});

Deno.test("both PostgREST shapes are read; anything that is not a uuid is skipped", () => {
  const ids = candidateIds([A, { unfinished_signup_candidates: B }, 42, null, "not-a-uuid", { x: 1 }]);
  if (ids.join(",") !== `${A},${B}`) throw new Error(`read ${ids.join(",")}`);
  if (candidateIds(null).length !== 0 || candidateIds({}).length !== 0) throw new Error("non-arrays must read as empty");
});

Deno.test("a failed candidate read stops the run without deleting anything", async () => {
  const { client, deleted } = fakeClient([A], { rpcError: true });
  let message = "";
  try {
    await purgeUnfinishedSignups(client);
  } catch (error) {
    message = error instanceof Error ? error.message : String(error);
  }
  if (message !== "unfinished_signup_candidates_failed") throw new Error(`threw "${message}"`);
  if (deleted.length !== 0) throw new Error("deleted after a failed read");
});

// Batch 5 review #1: an account that started signing in again after the list
// was read (its re-check is false) is skipped, never deleted.
Deno.test("each id is re-checked just before its delete; one that no longer qualifies is skipped", async () => {
  const { client, deleted, calls } = fakeClient([A, B, C], { recheckFalseFor: [B] });
  const result = await purgeUnfinishedSignups(client);
  if (JSON.stringify(result) !== JSON.stringify({ candidates: 3, deleted: 1, failed: 1, skipped: 1, remaining: 0 })) {
    throw new Error(`unexpected result ${JSON.stringify(result)}`);
  }
  if (deleted.includes(B) || calls.includes(`delete:${B}`)) throw new Error("B was deleted after its re-check said no");
  calls.forEach((call, i) => {
    if (call.startsWith("delete:") && calls[i - 1] !== `check:${call.slice(7)}`) {
      throw new Error(`${call} was not immediately preceded by its re-check (${calls.join(" ")})`);
    }
  });
});

Deno.test("a re-check that fails deletes nothing and counts as failed", async () => {
  const { client, deleted, calls } = fakeClient([A, B], { recheckErrorFor: [A] });
  const result = await purgeUnfinishedSignups(client);
  if (JSON.stringify(result) !== JSON.stringify({ candidates: 2, deleted: 1, failed: 1, skipped: 0, remaining: 0 })) {
    throw new Error(`unexpected result ${JSON.stringify(result)}`);
  }
  if (calls.includes(`delete:${A}`) || deleted.join(",") !== B) throw new Error(`deleted ${deleted.join(",")}`);
});

// Batch 5 review #8: the run starts no new delete after its time budget and
// reports what it left for the next hourly run.
Deno.test("no delete starts after the time budget; the rest is reported as remaining", async () => {
  const { client, deleted, calls } = fakeClient([A, B, C]);
  const ticks = [0, 0, 30_000, 60_000];
  let read = 0;
  const now = () => ticks[Math.min(read++, ticks.length - 1)];
  const result = await purgeUnfinishedSignups(client, { now, budgetMs: 60_000 });
  if (JSON.stringify(result) !== JSON.stringify({ candidates: 3, deleted: 2, failed: 0, skipped: 0, remaining: 1 })) {
    throw new Error(`unexpected result ${JSON.stringify(result)}`);
  }
  if (deleted.join(",") !== `${A},${B}` || calls.some((call) => call.endsWith(C))) {
    throw new Error(`touched ${calls.join(" ")}`);
  }
});

Deno.test("the endpoint is service-role only and logs counts, never ids", async () => {
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const handler = await Deno.readTextFile(new URL("./handler.ts", import.meta.url));
  const guard = index.indexOf("requireServiceRole(req);");
  if (guard < 0 || guard > index.indexOf("purgeUnfinishedSignups(")) {
    throw new Error("requireServiceRole must run before the purge");
  }
  if (/console\.(log|error|warn)\([^)]*\bid\b/.test(index + handler)) throw new Error("an id is logged");
  if (/console\./.test(handler)) throw new Error("the handler must not log");
});

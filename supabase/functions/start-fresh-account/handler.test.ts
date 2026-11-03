// Spec 1 W6a (§3.5, §4.5): start-fresh-account against a fake client.
import { type FreshStartClient, handleFreshStart, MAX_PARK_TRIES, parkedPhone } from "./handler.ts";

const OLD = "5f6a0000-0000-0000-0000-0000000000aa";
const NONCE = "ab".repeat(64);

interface Script {
  consume?: { data: unknown; error: { message: string } | null };
  phone?: string;
  takenTries?: number;
  updateError?: { message: string; status?: number; code?: string };
  markError?: { message: string };
}

function rig(script: Script = {}) {
  const calls: string[] = [];
  const logs: string[] = [];
  let taken = script.takenTries ?? 0;
  const client: FreshStartClient = {
    rpc(fn, args) {
      calls.push(`${fn}:${JSON.stringify(args)}`);
      if (fn === "consume_fresh_start") {
        return Promise.resolve(script.consume ?? { data: OLD, error: null });
      }
      return Promise.resolve({ data: null, error: script.markError ?? null });
    },
    auth: {
      admin: {
        getUserById(id) {
          calls.push(`get:${id}`);
          return Promise.resolve({ data: { user: { phone: script.phone ?? "233244123456" } }, error: null });
        },
        updateUserById(id, attributes) {
          calls.push(`update:${id}:${attributes.phone}:${attributes.phone_confirm}`);
          if (script.updateError) return Promise.resolve({ error: script.updateError });
          if (taken > 0) {
            taken--;
            return Promise.resolve({
              error: { message: "A user with this phone number has already been registered", status: 422, code: "phone_exists" },
            });
          }
          return Promise.resolve({ error: null });
        },
      },
    },
  };
  return { client, calls, logs };
}

function post(body: unknown, headers: Record<string, string> = { "cf-connecting-ip": "203.0.113.9" }) {
  return new Request("https://x/functions/v1/start-fresh-account", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function run(script: Script, body: unknown = { nonce: NONCE }, ipKey: string | null = "ip-key") {
  const r = rig(script);
  const res = await handleFreshStart(post(body), {
    client: r.client,
    ipKey: ipKey ?? undefined,
    log: (c) => r.logs.push(c),
  });
  return { ...r, status: res.status, body: await res.json() };
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("a usable nonce parks the old number on +999 and marks it, in that order", async () => {
  const r = await run({});
  assert(r.status === 200 && r.body.ok === true, `got ${r.status} ${JSON.stringify(r.body)}`);
  const parked = await parkedPhone(OLD, 1);
  assert(/^\+999\d{12}$/.test(parked), `parked ${parked}`);
  const order = r.calls.map((c) => c.split(":")[0]);
  assert(
    JSON.stringify(order) === JSON.stringify(["consume_fresh_start", "get", "update", "mark_fresh_start_parked"]),
    `order ${order.join(",")}`,
  );
  assert(r.calls[2] === `update:${OLD}:${parked}:true`, `update ${r.calls[2]}`);
  assert(r.calls[3] === `mark_fresh_start_parked:{"p_user":"${OLD}"}`, `mark ${r.calls[3]}`);
});

Deno.test("a taken +999 number is retried with the next one; too many collisions are a 503", async () => {
  const two = await run({ takenTries: 2 });
  assert(two.status === 200, `two collisions: ${two.status}`);
  assert(two.calls.filter((c) => c.startsWith("update:")).length === 3, "three tries");
  assert(two.calls[4] === `update:${OLD}:${await parkedPhone(OLD, 3)}:true`, "the third number");
  const many = await run({ takenTries: MAX_PARK_TRIES });
  assert(many.status === 503 && many.body.error === "fresh_start:unavailable", `many: ${many.status}`);
  assert(!many.calls.some((c) => c.startsWith("mark_")), "never marked without a park");
});

Deno.test("an unfinished park retried: already on +999, so only the mark runs", async () => {
  const r = await run({ phone: "999123456789012" });
  assert(r.status === 200, `status ${r.status}`);
  assert(!r.calls.some((c) => c.startsWith("update:")), "no second park");
  assert(r.calls.some((c) => c.startsWith("mark_fresh_start_parked")), "marked");
});

Deno.test("an unusable nonce is one plain 400; rubbish is sent as '' so the IP still pays", async () => {
  const invalid = await run({ consume: { data: null, error: null } });
  assert(invalid.status === 400 && invalid.body.error === "fresh_start:invalid", `got ${invalid.status}`);
  assert(!invalid.calls.some((c) => c.startsWith("get:") || c.startsWith("update:")), "nothing parked");
  const rubbish = await run({ consume: { data: null, error: null } }, { nonce: "<script>" });
  assert(rubbish.calls[0].includes('"p_nonce":""'), `sent ${rubbish.calls[0]}`);
  const notJson = await run({ consume: { data: null, error: null } }, "not json");
  assert(notJson.status === 400, `not json: ${notJson.status}`);
});

Deno.test("the IP limit is a 429; a missing key or a failing call a 503", async () => {
  const limited = await run({ consume: { data: null, error: { message: "fresh_start:try_later" } } });
  assert(limited.status === 429 && limited.body.error === "fresh_start:try_later", `limited ${limited.status}`);
  const noKey = await run({}, { nonce: NONCE }, null);
  assert(noKey.status === 503 && noKey.calls.length === 0, `no key ${noKey.status}`);
  const down = await run({ consume: { data: null, error: { message: "boom" } } });
  assert(down.status === 503, `down ${down.status}`);
  const auth = await run({ updateError: { message: "Database error", status: 500 } });
  assert(auth.status === 503 && !auth.calls.some((c) => c.startsWith("mark_")), `auth ${auth.status}`);
  const mark = await run({ markError: { message: "fresh_start:not_parked" } });
  assert(mark.status === 503, `mark ${mark.status}`);
});

Deno.test("the IP is hashed with the key, never sent or logged; nothing identifying is logged", async () => {
  const r = await run({});
  assert(!r.calls[0].includes("203.0.113.9"), "raw IP sent");
  assert(/"p_ip_hash":"[0-9a-f]{64}"/.test(r.calls[0]), `ip hash ${r.calls[0]}`);
  const logged = r.logs.join(" ");
  assert(!logged.includes(OLD) && !logged.includes(NONCE) && !logged.includes("203.0.113.9"), `logged ${logged}`);
  assert(r.logs.at(-1) === "fresh_start:parked", `last log ${r.logs.at(-1)}`);
});

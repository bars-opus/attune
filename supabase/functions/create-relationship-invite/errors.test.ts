// W4 batch 2 fix round 1 (ruling): create-relationship-invite answers an
// HttpError with its own status and message, and anything else with a
// generic 500 whose log carries only the error's code, never the database
// text (a check violation's details hold the failing row, invite code
// included) and never a phone.
import { HttpError } from "../_shared/attune_auth.ts";
import { createErrorResponse } from "./errors.ts";

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

const leakyText = "Failing row contains (K7P2QM, +233201234567, Ama)";

class FakePostgrestError extends Error {
  constructor(readonly code: string, readonly details: string, readonly hint: string) {
    super(`new row violates check constraint: ${leakyText}`);
    this.name = "PostgrestError";
  }
}

Deno.test("an HttpError answers its own status and message, and logs nothing", async () => {
  const logs = captureLogs();
  let response: Response;
  try {
    response = createErrorResponse(new HttpError("invite:age_required", 428));
  } finally {
    logs.restore();
  }
  const body = await response.json();
  if (response.status !== 428 || JSON.stringify(body) !== JSON.stringify({ error: "invite:age_required" })) {
    throw new Error(`got ${response.status} ${JSON.stringify(body)}`);
  }
  if (logs.lines.length) throw new Error(`logged ${logs.lines}`);
});

Deno.test("anything else is a generic 500 that logs the code only", async () => {
  for (const [label, error, code] of [
    ["a plain database error", { code: "23514", message: leakyText, details: leakyText, hint: "K7P2QM" }, "23514"],
    ["an Error subclass with a stack", new FakePostgrestError("23514", leakyText, "+233201234567"), "23514"],
    ["a code that isn't one", { code: "+233201234567", message: leakyText }, "none"],
    ["a thrown string", `boom ${leakyText}`, "none"],
  ] as const) {
    const logs = captureLogs();
    let response: Response;
    try {
      response = createErrorResponse(error);
    } finally {
      logs.restore();
    }
    const body = await response.json();
    if (response.status !== 500 || JSON.stringify(body) !== JSON.stringify({ error: "Could not create relationship invite" })) {
      throw new Error(`${label}: ${response.status} ${JSON.stringify(body)}`);
    }
    const text = logs.lines.join("\n");
    if (!text.includes(`code=${code}`)) throw new Error(`${label}: logged ${text}`);
    for (const secret of ["K7P2QM", "+233", "Ama", "Failing row", "violates"]) {
      if (text.includes(secret)) throw new Error(`${label}: logged ${secret}`);
    }
  }
});

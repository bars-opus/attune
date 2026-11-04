// Spec 1 W1c (D12): the Journal pause. featureFlagEnabled is exercised
// through a fake client shaped like the supabase-js query chain it calls.
import { JOURNAL_AI_FLAG, journalInsightsPaused, PAUSED_BODY } from "./journal_pause.ts";

function flagClient(result: { data: unknown; error: unknown } | Error) {
  const reads: string[] = [];
  const chain = {
    select(_columns: string) {
      return chain;
    },
    eq(_column: string, value: string) {
      reads.push(value);
      return chain;
    },
    maybeSingle() {
      return result instanceof Error ? Promise.reject(result) : Promise.resolve(result);
    },
  };
  return {
    reads,
    client: {
      from(table: string) {
        reads.push(table);
        return chain;
      },
    },
  };
}

Deno.test("journal insights are paused unless journal_ai_insights is on", async () => {
  if (JOURNAL_AI_FLAG !== "journal_ai_insights") throw new Error(`wrong flag key ${JOURNAL_AI_FLAG}`);
  if (PAUSED_BODY.status !== "paused") throw new Error("the paused answer must be {status: 'paused'}");

  const off = flagClient({ data: { enabled: false }, error: null });
  if (!(await journalInsightsPaused(off.client))) throw new Error("flag off must pause");
  if (off.reads.join(",") !== "feature_flags,journal_ai_insights") {
    throw new Error(`read the wrong flag: ${off.reads.join(",")}`);
  }
  for (const [label, result] of [
    ["a missing row", { data: null, error: null }],
    ["a read error", { data: null, error: { message: "permission denied" } }],
    ["a thrown read", new Error("network")],
  ] as const) {
    if (!(await journalInsightsPaused(flagClient(result).client))) throw new Error(`${label} must pause`);
  }

  const on = flagClient({ data: { enabled: true }, error: null });
  if (await journalInsightsPaused(on.client)) throw new Error("flag on must not pause");
});

Deno.test("the pause is checked before either action can reach the analyses or a provider", async () => {
  // Spec 1 W9 fix round 1 (ruling, spec amendment): the deterministic crisis
  // check runs before this pause, so a writer in crisis is offered support
  // whatever journal_ai_insights says. The pause is injected into each action
  // and checked right after the check, before the cache read and any provider
  // call; index.ts still answers paused for anything else.
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!index.includes("insightsPaused: () => journalInsightsPaused(adminClient),")) {
    throw new Error("index.ts does not inject the pause");
  }
  if (!index.includes("return json(PAUSED_BODY);")) throw new Error("the pause must answer PAUSED_BODY");
  const handlers = await Deno.readTextFile(new URL("./journal_handlers.ts", import.meta.url));
  for (const [action, end] of [
    ["export async function handleAnalyseEntry(", "export async function handleGetPatterns("],
    ["export async function handleGetPatterns(", "function globalConstraintHeader("],
  ]) {
    const body = handlers.slice(handlers.indexOf(action), handlers.indexOf(end));
    const pause = body.indexOf("if (await insightsPaused(deps))");
    const check = body.indexOf("disclosed(");
    if (pause < 0 || check < 0 || check > pause) throw new Error(`${action} checks the pause before the crisis check`);
    for (const later of ['.select("status, tone, observation, confidence")', '.select("entry_id, observation, tone, created_at")', "deps.model(", "maybeGenerate("]) {
      const at = body.indexOf(later);
      if (at >= 0 && at < pause) throw new Error(`${action} reaches ${later} before the pause`);
    }
  }
});

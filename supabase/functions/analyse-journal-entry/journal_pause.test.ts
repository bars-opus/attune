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

Deno.test("the pause is checked before either action can reach a provider", async () => {
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const pause = index.indexOf("if (await journalInsightsPaused(adminClient))");
  if (pause < 0) throw new Error("index.ts does not check the pause");
  for (const dispatch of ['body.action === "get_patterns"', 'body.action === "analyse_entry"']) {
    const at = index.indexOf(dispatch);
    if (at < 0 || at < pause) throw new Error(`${dispatch} is reached before the pause`);
  }
  if (!index.includes("return json(PAUSED_BODY);")) throw new Error("the pause must answer PAUSED_BODY");
});

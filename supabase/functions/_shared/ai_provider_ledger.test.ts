// Spec 8 (row 8; plan review I15, §6.4): every Gemini call leaves one
// content-free ledger row (job, prompt, couple, tokens); a ledger failure
// never fails the call; every call site says who the call was for.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { callGeminiJson } from "./gemini_json.ts";
import { type ProviderCallRow, setProviderCallRecorder } from "./ai_provider_ledger.ts";

function stubGemini(body: unknown) {
  const original = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(new Response(JSON.stringify(body), { status: 200 }))) as typeof fetch;
  return () => {
    globalThis.fetch = original;
  };
}

const okBody = {
  candidates: [{ content: { parts: [{ text: '{"ok":true}' }] } }],
  usageMetadata: { promptTokenCount: 120, candidatesTokenCount: 30 },
};

Deno.test("a call is ledgered with its attribution and token counts", async () => {
  Deno.env.set("GEMINI_API_KEY", "test-key");
  const rows: ProviderCallRow[] = [];
  setProviderCallRecorder((row) => {
    rows.push(row);
    return Promise.resolve();
  });
  const restore = stubGemini(okBody);
  try {
    const out = await callGeminiJson({
      promptId: "layer1",
      systemPrompt: "s",
      userPrompt: "u",
      maxOutputTokens: 50,
      attribution: { fn: "analyse-message", relationshipId: "r1", userId: "u1" },
    });
    assertEquals(out, { ok: true });
    assertEquals(rows.length, 1);
    assertEquals(rows[0].fn, "analyse-message");
    assertEquals(rows[0].prompt_id, "layer1");
    assertEquals(rows[0].relationship_id, "r1");
    assertEquals(rows[0].user_id, "u1");
    assertEquals(rows[0].prompt_tokens, 120);
    assertEquals(rows[0].output_tokens, 30);
    // Content-free: no prompt or output text.
    assertEquals(JSON.stringify(rows[0]).includes('"ok"'), false);
  } finally {
    restore();
    setProviderCallRecorder(null);
  }
});

Deno.test("a refused output is still ledgered (the cost was incurred)", async () => {
  Deno.env.set("GEMINI_API_KEY", "test-key");
  const rows: ProviderCallRow[] = [];
  setProviderCallRecorder((row) => {
    rows.push(row);
    return Promise.resolve();
  });
  const restore = stubGemini({
    ...okBody,
    candidates: [{ content: { parts: [{ text: '{"x":"this is toxic"}' }] } }],
  });
  try {
    const out = await callGeminiJson({
      promptId: "p",
      systemPrompt: "s",
      userPrompt: "u",
      maxOutputTokens: 50,
      attribution: { fn: "generate-verdict", relationshipId: "r2" },
    });
    assertEquals(out, null);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].user_id, null);
  } finally {
    restore();
    setProviderCallRecorder(null);
  }
});

Deno.test("a ledger failure never fails the call", async () => {
  Deno.env.set("GEMINI_API_KEY", "test-key");
  setProviderCallRecorder(() => Promise.reject(new Error("db down")));
  const restore = stubGemini(okBody);
  try {
    const out = await callGeminiJson({
      promptId: "p",
      systemPrompt: "s",
      userPrompt: "u",
      maxOutputTokens: 50,
      attribution: { fn: "analyse-session" },
    });
    assertEquals(out, { ok: true });
  } finally {
    restore();
    setProviderCallRecorder(null);
  }
});

// Sync audit M-12: a refused call (429, 5xx) is still a call; the cost
// view counts it, with no tokens.
Deno.test("a failed provider call is ledgered too, with no tokens", async () => {
  Deno.env.set("GEMINI_API_KEY", "test-key");
  const rows: ProviderCallRow[] = [];
  setProviderCallRecorder((row) => {
    rows.push(row);
    return Promise.resolve();
  });
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response("busy", { status: 429 }))) as typeof fetch;
  try {
    const out = await callGeminiJson({
      promptId: "p",
      systemPrompt: "s",
      userPrompt: "u",
      maxOutputTokens: 50,
      attribution: { fn: "analyse-message", relationshipId: "r9" },
    });
    assertEquals(out, null);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].relationship_id, "r9");
    assertEquals(rows[0].prompt_tokens, 0);
    assertEquals(rows[0].output_tokens, 0);
  } finally {
    globalThis.fetch = original;
    setProviderCallRecorder(null);
  }
});

// Final review I-2: a slow or hanging ledger never holds up the answer.
Deno.test("a hanging ledger never delays the result", async () => {
  Deno.env.set("GEMINI_API_KEY", "test-key");
  setProviderCallRecorder(() => new Promise(() => {}));
  const restore = stubGemini(okBody);
  try {
    const started = Date.now();
    const out = await callGeminiJson({
      promptId: "p",
      systemPrompt: "s",
      userPrompt: "u",
      maxOutputTokens: 50,
      attribution: { fn: "ai-understand" },
    });
    assertEquals(out, { ok: true });
    const took = Date.now() - started;
    if (took > 600) throw new Error(`the call waited ${took} ms for the ledger`);
  } finally {
    restore();
    setProviderCallRecorder(null);
  }
});

Deno.test("every callGeminiJson call site passes an attribution", async () => {
  const root = new URL("../", import.meta.url);
  const missing: string[] = [];
  for await (const dir of Deno.readDir(root)) {
    if (!dir.isDirectory) continue;
    for await (const f of Deno.readDir(new URL(`${dir.name}/`, root))) {
      if (!f.isFile || !f.name.endsWith(".ts") || f.name.endsWith(".test.ts")) continue;
      const path = `${dir.name}/${f.name}`;
      if (path === "_shared/gemini_json.ts") continue;
      const src = await Deno.readTextFile(new URL(path, root));
      for (const m of src.matchAll(/\b(callGeminiJson|callGemini|gemini)\(\{/g)) {
        const call = src.slice(m.index!, m.index! + 1200);
        const end = call.indexOf("});");
        if (!call.slice(0, end < 0 ? undefined : end).includes("attribution:")) {
          missing.push(path);
        }
      }
    }
  }
  assertEquals(missing, []);
});

// Final review I-4: couple-scoped jobs name the couple, or the cost view is
// blind to them. Only the personal features (journal, healing) attribute a
// person alone.
Deno.test("couple-scoped call sites attribute the relationship", async () => {
  const coupleScoped = [
    "ai-sessions/index.ts",
    "ai-assist/index.ts",
    "ai-understand/index.ts",
    "ai-together/handler.ts",
    "translate-conflict/handler.ts",
    "analyse-message/index.ts",
    "analyse-session/index.ts",
    "generate-verdict/index.ts",
    "generate-thirty-six-reflection/index.ts",
  ];
  const root = new URL("../", import.meta.url);
  const missing: string[] = [];
  for (const path of coupleScoped) {
    const src = await Deno.readTextFile(new URL(path, root));
    for (const m of src.matchAll(/attribution: \{[^}]*\}/g)) {
      if (!m[0].includes("relationshipId")) missing.push(`${path}: ${m[0]}`);
    }
  }
  assertEquals(missing, []);
});

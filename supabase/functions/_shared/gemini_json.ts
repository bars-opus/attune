import { type ProviderCallAttribution, recordProviderCall } from "./ai_provider_ledger.ts";

const DEFAULT_MODEL = "gemini-1.5-flash";
const GEMINI_URL_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";

export const STATIC_PROHIBITED_PATTERNS = [
  /your partner (always|never|tends to|keeps)/i,
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
  /you should (leave|stay|break up|end|tell|confront|ask)/i,
  /this relationship is/i,
  /\bviolation\b/i,
  // Spec 8 (research 06 F15 (4); 05 S11): never a negative attribution of a
  // third party — family, friends, an ex, a boss — who is not in the room.
  // Only a negative predicate counts (final review I-7): "your parents
  // always call on Sundays" and "your mother is trying to help" are not
  // blame, and the translator rewrites in-law messages like them.
  /\b(his|her|your|their)\s+(mother|mum|mom|father|dad|parents?|family|sister|brother|siblings?|friends?|aunt|uncle|cousin|in-laws?|boss|ex)\b[^.]{0,30}?\b((is|are)\s+((so|always|really|just|being)\s+)?(controlling|manipulative|selfish|jealous|toxic|the problem|to blame|against\s+(you|her|him|them|us))\b|always\s+(\w+\s+){0,2}(criticis|criticiz|undermin|interfer|disrespect|ignor|manipulat|meddl|judg|blam|control)|never\s+(\w+\s+){0,2}(respect|listen|support|accept|trust|let)\b|(is|are)\s+trying\s+to\s+(split|turn|control|break|undermine|manipulate|come between|keep)\b|hates?\s+(you|her|him|them|us)\b)/i,
];

export async function callGeminiJson(params: {
  promptId: string;
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
  runtimeProhibitedPatterns?: RegExp[];
  /** Spec 8 (plan review I15): who the call was for, for the cost ledger. */
  attribution: ProviderCallAttribution;
}): Promise<Record<string, unknown> | null> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("gemini_missing_api_key", { prompt_id: params.promptId });
    return null;
  }

  const model = Deno.env.get("GEMINI_MODEL") ?? DEFAULT_MODEL;
  const url = `${GEMINI_URL_BASE}/${model}:generateContent?key=${apiKey}`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          { role: "user", parts: [{ text: params.userPrompt }] },
        ],
        systemInstruction: {
          parts: [{ text: params.systemPrompt }],
        },
        generationConfig: {
          maxOutputTokens: params.maxOutputTokens,
          responseMimeType: "application/json",
        },
      }),
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) {
      console.error("gemini_http_error", {
        prompt_id: params.promptId,
        status: response.status,
      });
      // Still a call (sync audit M-12): ledgered with no tokens.
      await settleLedger(
        recordProviderCall({
          attribution: params.attribution,
          promptId: params.promptId,
          model,
          usage: null,
        }),
      );
      return null;
    }

    const payload = await response.json();
    // The cost is incurred whatever happens to the output next. Never on
    // the user's critical path (final review I-2).
    await settleLedger(
      recordProviderCall({
        attribution: params.attribution,
        promptId: params.promptId,
        model,
        usage: payload?.usageMetadata,
      }),
    );
    const text = payload?.candidates?.[0]?.content?.parts
      ?.map((part: { text?: string }) =>
        typeof part?.text === "string" ? part.text : ""
      )
      .join("") ?? "";

    const parsed = JSON.parse(text.replace(/```json|```/g, "").trim());
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      console.error("gemini_shape_invalid", { prompt_id: params.promptId });
      return null;
    }

    const outputText = JSON.stringify(parsed);
    for (const pattern of [
      ...STATIC_PROHIBITED_PATTERNS,
      ...(params.runtimeProhibitedPatterns ?? []),
    ]) {
      if (pattern.test(outputText)) {
        console.error("prohibited_pattern_detected", {
          prompt_id: params.promptId,
          pattern: pattern.source,
        });
        return null;
      }
    }

    return parsed as Record<string, unknown>;
  } catch {
    console.error("gemini_parse_failed", { prompt_id: params.promptId });
    return null;
  }
}

const LEDGER_WAIT_MS = 250;

/// Hands the ledger write to the runtime when it can outlive the response
/// (Supabase's EdgeRuntime.waitUntil); otherwise waits at most
/// LEDGER_WAIT_MS. recordProviderCall never rejects.
async function settleLedger(write: Promise<void>): Promise<void> {
  const runtime = (globalThis as {
    EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (typeof runtime?.waitUntil === "function") {
    runtime.waitUntil(write);
    return;
  }
  let timer: ReturnType<typeof setTimeout> | undefined;
  await Promise.race([
    write,
    new Promise<void>((resolve) => {
      timer = setTimeout(resolve, LEDGER_WAIT_MS);
    }),
  ]);
  clearTimeout(timer);
}

/// Moved here from claude_json.ts with the Gemini port: analyse-message and
/// analyse-session pass these as runtimeProhibitedPatterns, so the filter
/// had to follow the call. Blocks the model characterising a named partner
/// in absolutes ("Ada always ...") -- a pattern the static list cannot
/// catch, since it depends on names known only at request time.
export function partnerNamePatterns(names: string[]): RegExp[] {
  return names
    .map((name) => name.trim())
    .filter((name) => name.length > 0)
    .map((name) =>
      new RegExp(`${escapeRegex(name)}\\s+(always|never|tends|keeps)`, "i")
    );
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

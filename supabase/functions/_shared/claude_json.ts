const DEFAULT_MODEL = "claude-sonnet-4-20250514";
const CLAUDE_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

/// One list for every provider (Spec 8: the stale copy here had drifted).
/// Re-exported so the §6.7 eval suite still imports it from this file.
import { STATIC_PROHIBITED_PATTERNS } from "./gemini_json.ts";
export { STATIC_PROHIBITED_PATTERNS };

export async function callClaudeJson(params: {
  promptId: string;
  systemPrompt: string;
  userPrompt: string;
  maxTokens: number;
  runtimeProhibitedPatterns?: RegExp[];
}): Promise<Record<string, unknown> | null> {
  const apiKey = Deno.env.get("CLAUDE_API_KEY");
  if (!apiKey) {
    console.error("claude_missing_api_key", { prompt_id: params.promptId });
    return null;
  }

  try {
    const response = await fetch(CLAUDE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify({
        model: Deno.env.get("CLAUDE_MODEL") ?? DEFAULT_MODEL,
        max_tokens: params.maxTokens,
        system: params.systemPrompt,
        messages: [{ role: "user", content: params.userPrompt }],
      }),
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) {
      console.error("claude_http_error", {
        prompt_id: params.promptId,
        status: response.status,
      });
      return null;
    }

    const payload = await response.json();
    const text = Array.isArray(payload?.content)
      ? payload.content
        .map((block: { text?: string }) =>
          typeof block?.text === "string" ? block.text : ""
        )
        .join("")
      : "";

    const parsed = JSON.parse(text.replace(/```json|```/g, "").trim());
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      console.error("claude_shape_invalid", { prompt_id: params.promptId });
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
    console.error("claude_parse_failed", { prompt_id: params.promptId });
    return null;
  }
}

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

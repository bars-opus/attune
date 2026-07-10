const DEFAULT_MODEL = "claude-sonnet-4-20250514";
const CLAUDE_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

const STATIC_PROHIBITED_PATTERNS = [
  /your partner (always|never|tends to|keeps)/i,
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
  /you should (leave|stay|break up|end)/i,
  /this relationship is/i,
];

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

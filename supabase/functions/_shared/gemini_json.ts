const DEFAULT_MODEL = "gemini-1.5-flash";
const GEMINI_URL_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";

export const STATIC_PROHIBITED_PATTERNS = [
  /your partner (always|never|tends to|keeps)/i,
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
  /you should (leave|stay|break up|end|tell|confront|ask)/i,
  /this relationship is/i,
  /\bviolation\b/i,
];

export async function callGeminiJson(params: {
  promptId: string;
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
  runtimeProhibitedPatterns?: RegExp[];
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
      return null;
    }

    const payload = await response.json();
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

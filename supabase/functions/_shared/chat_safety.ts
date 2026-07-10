export interface SafetyRule {
  id: string;
  pattern: string;
  match: "token_phrase";
}

export interface SafetyFamilyConfig {
  tier: 1 | 2 | 3;
  minimum_occurrences: number;
  window_days?: number;
  rules: SafetyRule[];
}

export interface SafetyConfig {
  config_version: string;
  locale: string;
  normalization_version: number;
  tiers: Record<string, SafetyFamilyConfig>;
}

export interface SafetyDetectionResult {
  highestTier: number;
  family: string;
  matchedRuleIds: string[];
  minimumOccurrences: number;
  windowDays: number | null;
}

export const CHAT_SAFETY_CONFIG: SafetyConfig = {
  config_version: "1.0.0",
  locale: "en",
  normalization_version: 1,
  tiers: {
    explicit_threat: {
      tier: 1,
      minimum_occurrences: 1,
      rules: [
        { id: "explicit_threat_001", pattern: "kill you", match: "token_phrase" },
        { id: "explicit_threat_002", pattern: "hurt you", match: "token_phrase" },
        { id: "explicit_threat_003", pattern: "harm you", match: "token_phrase" },
      ],
    },
    isolation_control: {
      tier: 2,
      minimum_occurrences: 1,
      rules: [
        { id: "isolation_001", pattern: "you don't need them", match: "token_phrase" },
        { id: "isolation_002", pattern: "you only need me", match: "token_phrase" },
        { id: "isolation_003", pattern: "no one will believe you", match: "token_phrase" },
      ],
    },
    pattern_control: {
      tier: 3,
      minimum_occurrences: 3,
      window_days: 30,
      rules: [
        { id: "pattern_control_001", pattern: "if you leave", match: "token_phrase" },
        { id: "pattern_control_002", pattern: "you'll regret it", match: "token_phrase" },
        { id: "pattern_control_003", pattern: "you can't survive without me", match: "token_phrase" },
      ],
    },
  },
};

export function normalizeForTokenPhrase(input: string): string {
  return ` ${input
    .toLowerCase()
    .normalize("NFKC")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/[^a-z0-9'\s]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()} `;
}

export function detectImmediateFamilies(content: string): SafetyDetectionResult[] {
  const normalized = normalizeForTokenPhrase(content);
  if (normalized.trim().length === 0) {
    return [];
  }

  const results: SafetyDetectionResult[] = [];
  for (const [family, familyConfig] of Object.entries(CHAT_SAFETY_CONFIG.tiers)) {
    if (familyConfig.tier === 3) continue;

    const matchedRuleIds = familyConfig.rules
      .filter((rule) => normalized.includes(` ${rule.pattern} `))
      .map((rule) => rule.id);

    if (matchedRuleIds.length === 0) continue;

    results.push({
      highestTier: familyConfig.tier,
      family,
      matchedRuleIds,
      minimumOccurrences: familyConfig.minimum_occurrences,
      windowDays: familyConfig.window_days ?? null,
    });
  }

  return results.sort((a, b) => a.highestTier - b.highestTier);
}

export function detectTierThreeRuleIds(content: string): string[] {
  const normalized = normalizeForTokenPhrase(content);
  if (normalized.trim().length === 0) {
    return [];
  }

  const tierThree = CHAT_SAFETY_CONFIG.tiers.pattern_control;
  return tierThree.rules
    .filter((rule) => normalized.includes(` ${rule.pattern} `))
    .map((rule) => rule.id);
}

export async function computeSafetySourceEventKey(
  messageId: string,
  secret: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(messageId),
  );
  return toHex(new Uint8Array(signature));
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

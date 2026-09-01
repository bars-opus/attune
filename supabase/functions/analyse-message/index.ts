import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { callGeminiJson, partnerNamePatterns } from "../_shared/gemini_json.ts";

const GLOBAL_CONSTRAINTS = `
ABSOLUTE CONSTRAINTS — these override all other instructions:

1. Never generate text that attributes a negative behaviour to a named
   or implied partner.
2. Never generate a sentence of form "[partner name/pronoun] tends to X"
   where X is a negative or deficit behaviour.
3. Never use these words: toxic, narcissist, codependent, disorder, broken.
4. Never tell the user what to decide about the relationship.
5. Never diagnose. Observe patterns. Frame with agency.
6. Return ONLY valid JSON. No preamble. No markdown fences.
`;

const ALLOWED_NVC = new Set([
  "blame_language",
  "you_always_never",
  "character_attack",
  "contempt",
  "demand",
]);
const ALLOWED_BID_TYPES = new Set(["toward", "away", "against"]);
const ALLOWED_SENTIMENTS = new Set(["positive", "neutral", "negative", "charged"]);

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return jsonResponse({ ok: true });
  }

  const supabase = serviceRoleClient();
  const body = req.method === "POST"
    ? await req.json().catch((): Record<string, unknown> => ({}))
    : {};

  const limit = typeof body.limit === "number" ? body.limit : 20;
  const messageId = typeof body.message_id === "string" ? body.message_id : null;

  try {
    requireServiceRole(req);
    const jobs = await loadMessages(supabase, { messageId, limit });
    const results = [];

    for (const message of jobs) {
      results.push(await processMessage(supabase, message));
    }

    return jsonResponse({
      success: true,
      processed: results.length,
      results,
    });
  } catch (error) {
    return jsonResponse(
      { success: false, error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

async function loadMessages(
  supabase: ReturnType<typeof serviceRoleClient>,
  options: { messageId: string | null; limit: number },
) {
  let query = supabase
    .from("messages")
    .select(`
      id,
      relationship_id,
      sender_id,
      content,
      created_at,
      message_analysis_done,
      safety_processed_at
    `)
    .eq("message_analysis_done", false)
    .not("safety_processed_at", "is", null)
    .order("created_at", { ascending: true })
    .limit(Math.min(Math.max(options.limit, 1), 100));

  if (options.messageId) {
    query = query.eq("id", options.messageId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

async function processMessage(
  supabase: ReturnType<typeof serviceRoleClient>,
  message: Record<string, unknown>,
) {
  const messageId = String(message.id);

  try {
    const content = typeof message.content === "string" ? message.content.trim() : "";
    if (content.length === 0) {
      await markMessageDone(supabase, messageId, {});
      return { message_id: messageId, status: "skipped_media_only" };
    }

    const relationshipId = String(message.relationship_id);
    const senderId = String(message.sender_id);

    const [relationship, senderProfile, priorMessages] = await Promise.all([
      loadRelationshipContext(supabase, relationshipId),
      loadSenderProfile(supabase, senderId),
      loadPriorMessages(
        supabase,
        relationshipId,
        String(message.created_at),
        messageId,
      ),
    ]);

    if (!relationship || relationship.chat_archived_at) {
      await markMessageDone(supabase, messageId, {});
      return { message_id: messageId, status: "skipped_relationship_archived" };
    }

    const senderName = relationship.user_a.id === senderId
      ? relationship.user_a.display_name
      : relationship.user_b.display_name;

    const userPrompt = buildLayerOnePrompt({
      senderName,
      content,
      priorMessages,
      profile: senderProfile,
    });

    const parsed = await callGeminiJson({
      promptId: "layer1_message_analysis",
      systemPrompt: GLOBAL_CONSTRAINTS,
      userPrompt,
      maxOutputTokens: 250,
      runtimeProhibitedPatterns: partnerNamePatterns([
        relationship.user_a.display_name,
        relationship.user_b.display_name,
      ]),
    });

    const validated = validateLayerOne(parsed);
    await markMessageDone(supabase, messageId, validated ?? {});
    return {
      message_id: messageId,
      status: validated ? "completed" : "completed_without_model_output",
    };
  } catch (error) {
    await markMessageDone(supabase, messageId, {});
    return {
      message_id: messageId,
      status: "completed_with_fallback",
      error: error instanceof Error ? error.message.slice(0, 120) : "unknown_error",
    };
  }
}

async function loadRelationshipContext(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
) {
  const { data, error } = await supabase
    .from("relationships")
    .select(`
      id,
      chat_archived_at,
      user_a,
      user_b,
      users_user_a:users!relationships_user_a_fkey(id, display_name),
      users_user_b:users!relationships_user_b_fkey(id, display_name)
    `)
    .eq("id", relationshipId)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  return {
    id: data.id as string,
    chat_archived_at: data.chat_archived_at as string | null,
    user_a: normalizeJoinedUser(data.users_user_a, data.user_a as string),
    user_b: normalizeJoinedUser(data.users_user_b, data.user_b as string | null),
  };
}

async function loadSenderProfile(
  supabase: ReturnType<typeof serviceRoleClient>,
  senderId: string,
) {
  const { data, error } = await supabase
    .from("psych_profiles")
    .select("attachment_style, communication_style")
    .eq("user_id", senderId)
    .maybeSingle();
  if (error) throw error;
  return data ?? {};
}

async function loadPriorMessages(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
  createdAt: string,
  messageId: string,
) {
  const { data, error } = await supabase
    .from("messages")
    .select(`
      id,
      sender_id,
      content,
      created_at,
      users:users!messages_sender_id_fkey(display_name)
    `)
    .eq("relationship_id", relationshipId)
    .lte("created_at", createdAt)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(11);

  if (error) throw error;

  return (data ?? [])
    .filter((row: Record<string, unknown>) => row.id !== messageId)
    .slice(0, 10)
    .reverse()
    .map((row: Record<string, unknown>) => ({
      sender_name: normalizeJoinedUser(row.users, String(row.sender_id)).display_name,
      content: typeof row.content === "string" ? row.content : "",
      created_at: String(row.created_at),
    }));
}

function buildLayerOnePrompt(input: {
  senderName: string;
  content: string;
  priorMessages: Array<Record<string, unknown>>;
  profile: Record<string, unknown>;
}) {
  return `
You are a relationship intelligence system. Analyse this single message.

CONVERSATION CONTEXT (last 10 messages):
${JSON.stringify(input.priorMessages)}

NEW MESSAGE (from ${input.senderName}):
"${input.content}"

SENDER PROFILE:
- Attachment style: ${JSON.stringify(input.profile.attachment_style ?? {})}
- Communication style: ${JSON.stringify(input.profile.communication_style ?? {})}

Return ONLY valid JSON:
{
  "tone_score": float -1.0 to 1.0,
  "sentiment": "positive" | "neutral" | "negative" | "charged",
  "nvc_violations": ["blame_language"|"you_always_never"|"character_attack"|"contempt"|"demand"],
  "bid_type": "toward" | "away" | "against" | null,
  "bid_detected": boolean,
  "requires_session_analysis": boolean
}

Rules:
- Never invent violations not present in the text
- requires_session_analysis = true if sentiment is negative or charged
- A bid is a reach for connection: humour, sharing, asking a question
- Return ONLY the JSON object
  `.trim();
}

/// Exported for the §6.7 golden-transcript evals (index.test.ts). This is
/// the boundary where raw model output becomes persisted analysis, so it
/// is the meaningful thing to assert a known input/output pair against.
export function validateLayerOne(
  parsed: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (!parsed) return null;

  const result: Record<string, unknown> = {};
  const toneScore = typeof parsed.tone_score === "number"
    ? Math.max(-1, Math.min(1, parsed.tone_score))
    : null;
  const nvc = Array.isArray(parsed.nvc_violations)
    ? parsed.nvc_violations.filter((item): item is string =>
      typeof item === "string" && ALLOWED_NVC.has(item)
    )
    : [];
  const bidType = typeof parsed.bid_type === "string" && ALLOWED_BID_TYPES.has(parsed.bid_type)
    ? parsed.bid_type
    : null;
  const sentiment = typeof parsed.sentiment === "string" && ALLOWED_SENTIMENTS.has(parsed.sentiment)
    ? parsed.sentiment
    : null;

  if (toneScore != null) {
    result.tone_score = toneScore;
  }
  result.nvc_violations = nvc;
  result.bid_type = bidType;
  if (sentiment != null) {
    result.sentiment = sentiment;
  }
  return result;
}

async function markMessageDone(
  supabase: ReturnType<typeof serviceRoleClient>,
  messageId: string,
  fields: Record<string, unknown>,
) {
  const payload: Record<string, unknown> = {
    message_analysis_done: true,
    ...fields,
  };

  if (!("nvc_violations" in payload)) {
    payload.nvc_violations = [];
  }

  const { error } = await supabase
    .from("messages")
    .update(payload)
    .eq("id", messageId)
    .eq("message_analysis_done", false);
  if (error) throw error;
}

function normalizeJoinedUser(value: unknown, fallbackId: string | null) {
  const row = Array.isArray(value) ? value[0] : value;
  const candidate = row as { id?: string; display_name?: string } | null | undefined;
  return {
    id: candidate?.id ?? fallbackId ?? "",
    display_name: candidate?.display_name ?? "Partner",
  };
}

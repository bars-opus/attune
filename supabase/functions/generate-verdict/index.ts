import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const CLAUDE_API_KEY = Deno.env.get("CLAUDE_API_KEY");
const CLAUDE_URL = "https://api.anthropic.com/v1/messages";
const INPUT_SCHEMA_VERSION = "1.1.0";
const PROMPT_VERSION = "1.1.0";
const MODEL_PROVIDER = "anthropic";
const MODEL_NAME = "claude-sonnet-4-20250514";
const FIXED_DISCLAIMER =
  "This reflects patterns in your data. It is not a diagnosis or a decision.";

const BANNED_PATTERNS = [
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
  /you should/i,
  /you must/i,
  /you need to/i,
  /your relationship is/i,
  /\bstay\b/i,
  /\bleave\b/i,
  /\bhealthy\b/i,
  /\bunhealthy\b/i,
  /your partner (always|never|tends to|keeps)/i,
];

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { job_id, relationship_id } = await req.json().catch(() => ({}));
    const jobs = await loadJobs(supabase, {
      jobId: job_id,
      relationshipId: relationship_id,
    });

    const results = [];
    for (const job of jobs) {
      results.push(await processJob(supabase, job));
    }

    return new Response(
      JSON.stringify({ success: true, processed: results.length, results }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ success: false, error: message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

async function loadJobs(
  supabase: any,
  options: { jobId?: string; relationshipId?: string },
) {
  let query = supabase
    .from("verdict_generation_jobs")
    .select("*")
    .in("status", ["pending", "processing"])
    .order("created_at", { ascending: true })
    .limit(10);

  if (options.jobId) {
    query = query.eq("id", options.jobId);
  }

  if (options.relationshipId) {
    query = query.eq("relationship_id", options.relationshipId);
  }

  const { data, error } = await query;
  if (error) {
    throw error;
  }
  return data ?? [];
}

async function processJob(supabase: any, job: any) {
  const processing = await supabase
    .from("verdict_generation_jobs")
    .update({
      status: "processing",
      attempt_count: (job.attempt_count ?? 0) + 1,
      last_error: null,
    })
    .eq("id", job.id)
    .in("status", ["pending", "processing"])
    .select("*")
    .maybeSingle();

  if (processing.error) {
    return {
      job_id: job.id,
      status: "failed",
      error: processing.error.message,
    };
  }

  const lockedJob = processing.data ?? job;

  try {
    const existing = await supabase
      .from("verdicts")
      .select("id")
      .eq("relationship_id", lockedJob.relationship_id)
      .eq("period_start", lockedJob.period_start)
      .maybeSingle();

    if (existing.data) {
      await markJobComplete(supabase, lockedJob.id);
      return {
        job_id: lockedJob.id,
        status: "existing",
        verdict_id: existing.data.id,
      };
    }

    const context = await buildVerdictContext(supabase, lockedJob);
    validateEligibility(context);

    const output = await generateVerdict(context);
    const validated = validateModelOutput(output, context.evidence);
    const confidence = computeConfidence(context);

    const verdictPayload = {
      relationship_id: lockedJob.relationship_id,
      period_start: lockedJob.period_start,
      period_end: lockedJob.period_end,
      snapshot_at: context.snapshotAt,
      generated_at: new Date().toISOString(),
      status: "published",
      data_confidence: confidence.level,
      confidence_label: confidence.label,
      headline: validated.headline,
      strengths: validated.strengths,
      watch_areas: validated.watch_areas,
      one_action: validated.one_action,
      one_action_evidence_ids: validated.one_action_evidence_ids,
      patterns_referenced: validated.patterns_referenced,
      disclaimer: FIXED_DISCLAIMER,
      input_schema_version: INPUT_SCHEMA_VERSION,
      prompt_version: PROMPT_VERSION,
      model_provider: MODEL_PROVIDER,
      model_name: MODEL_NAME,
      source_updated_at_max: context.sourceUpdatedAtMax,
    };

    const { data: verdict, error: verdictError } = await supabase
      .from("verdicts")
      .insert(verdictPayload)
      .select("*")
      .single();

    if (verdictError) {
      throw verdictError;
    }

    const evidenceRows = context.evidence.map((item: any) => ({
      verdict_id: verdict.id,
      evidence_id: item.evidence_id,
      source_type: item.source_type,
      source_record_id: item.source_record_id,
      observed_at: item.observed_at,
      sample_size: item.sample_size,
      framework_confidence: item.framework_confidence,
      display_source: item.display_source,
    }));

    if (evidenceRows.length > 0) {
      const { error } = await supabase.from("verdict_evidence").insert(
        evidenceRows,
      );
      if (error) {
        throw error;
      }
    }

    const members = [context.relationship.user_a, context.relationship.user_b]
      .filter(Boolean);
    if (members.length > 0) {
      const deliveries = members.map((userId: string) => ({
        verdict_id: verdict.id,
        user_id: userId,
        notification_status: "pending",
      }));
      const outbox = members.map((userId: string) => ({
        verdict_id: verdict.id,
        user_id: userId,
        event_type: "verdict_ready",
        status: "pending",
      }));

      const deliveryInsert = await supabase.from("verdict_deliveries").insert(
        deliveries,
      );
      if (deliveryInsert.error) {
        throw deliveryInsert.error;
      }

      const outboxInsert = await supabase.from("verdict_notification_outbox")
        .insert(outbox);
      if (outboxInsert.error) {
        throw outboxInsert.error;
      }
    }

    await markJobComplete(supabase, lockedJob.id);
    return {
      job_id: lockedJob.id,
      status: "completed",
      verdict_id: verdict.id,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await supabase
      .from("verdict_generation_jobs")
      .update({
        status: (lockedJob.attempt_count ?? 0) + 1 >= 2 ? "failed" : "pending",
        last_error: message,
      })
      .eq("id", lockedJob.id);

    return { job_id: lockedJob.id, status: "failed", error: message };
  }
}

async function buildVerdictContext(supabase: any, job: any) {
  const periodStart = new Date(job.period_start);
  const periodEnd = new Date(job.period_end);
  const sixtyDaysStart = new Date(periodEnd);
  sixtyDaysStart.setUTCDate(sixtyDaysStart.getUTCDate() - 60);

  const relationshipRes = await supabase
    .from("relationships")
    .select("id, user_a, user_b, started_at, total_sessions, games_completed")
    .eq("id", job.relationship_id)
    .single();
  if (relationshipRes.error) {
    throw relationshipRes.error;
  }
  const relationship = relationshipRes.data;

  const pulseRes = await supabase
    .from("pulse_scores")
    .select("*")
    .eq("relationship_id", job.relationship_id)
    .lt("computed_at", periodEnd.toISOString())
    .order("computed_at", { ascending: false })
    .limit(4);

  const patternRes = await supabase
    .from("patterns")
    .select(
      "id, pattern_type, severity, occurrence_count, first_seen_at, last_seen_at",
    )
    .eq("relationship_id", job.relationship_id)
    .not("severity", "eq", "resolved")
    .not("severity", "eq", "safety")
    .order("last_seen_at", { ascending: false })
    .limit(15);

  const sessionRes = await supabase
    .from("analysis_sessions")
    .select(
      "id, ended_at, message_count, escalation_score, session_resolved, repair_attempted, dominant_topic, root_need_detected, suggested_insight",
    )
    .eq("relationship_id", job.relationship_id)
    .lt("ended_at", periodEnd.toISOString())
    .eq("one_sided_session", false)
    .eq("truncated", false)
    .order("ended_at", { ascending: false })
    .limit(5);

  const timelineRes = await supabase
    .from("timeline_events")
    .select("id, event_type, occurred_at, mood_score")
    .eq("relationship_id", job.relationship_id)
    .gte("occurred_at", job.period_start)
    .lt("occurred_at", job.period_end)
    .order("occurred_at", { ascending: false })
    .limit(50);

  const gameRes = await supabase
    .from("game_sessions")
    .select("id, completed_at, game_type, insights_generated")
    .eq("relationship_id", job.relationship_id)
    .gte("completed_at", sixtyDaysStart.toISOString())
    .lt("completed_at", periodEnd.toISOString())
    .not("insights_generated", "is", null)
    .order("completed_at", { ascending: false })
    .limit(20);

  const sharedProfiles = await loadSharedProfiles(supabase, relationship);

  const pulseHistory = pulseRes.data ?? [];
  const patterns = patternRes.data ?? [];
  const sessions = (sessionRes.data ?? []).slice(0, 3);
  const timeline = timelineRes.data ?? [];
  const gameInsights = gameRes.data ?? [];
  const evidence = buildEvidence({
    pulseHistory,
    patterns,
    sessions,
    timeline,
    gameInsights,
  });

  const sourceUpdatedAtMax = evidence.reduce(
    (latest: string | null, item: any) => {
      if (!latest || item.observed_at > latest) {
        return item.observed_at;
      }
      return latest;
    },
    null,
  );

  return {
    relationship,
    periodStart: job.period_start,
    periodEnd: job.period_end,
    snapshotAt: new Date().toISOString(),
    sourceUpdatedAtMax,
    pulseHistory,
    patterns,
    sessions,
    timeline,
    gameInsights,
    sharedProfiles,
    metadata: {
      days_together: relationship.started_at
        ? Math.max(
          0,
          Math.floor(
            (Date.now() - new Date(relationship.started_at).getTime()) /
              86400000,
          ),
        )
        : null,
      eligible_session_count: sessionRes.data?.length ?? 0,
      completed_game_count: relationship.games_completed ?? 0,
    },
    evidence,
  };
}

async function loadSharedProfiles(supabase: any, relationship: any) {
  const shareRes = await supabase
    .from("quiz_shares")
    .select("sharer_user_id, recipient_user_id, quiz_type")
    .or(
      `and(sharer_user_id.eq.${relationship.user_a},recipient_user_id.eq.${relationship.user_b}),and(sharer_user_id.eq.${relationship.user_b},recipient_user_id.eq.${relationship.user_a})`,
    );

  const profileRes = await supabase
    .from("psych_profiles")
    .select(
      "user_id, attachment_style, love_languages, communication_style, conflict_style",
    )
    .in("user_id", [relationship.user_a, relationship.user_b].filter(Boolean));

  const shares = shareRes.data ?? [];
  const profiles = profileRes.data ?? [];
  const shared = new Map<string, any>();

  for (const profile of profiles) {
    const entry: Record<string, unknown> = { user_id: profile.user_id };
    for (
      const quizType of [
        "attachment",
        "love_language",
        "communication",
        "conflict",
      ]
    ) {
      const hasShared = shares.some(
        (share: any) =>
          share.sharer_user_id === profile.user_id &&
          share.quiz_type === quizType,
      );
      if (!hasShared) {
        continue;
      }

      if (quizType === "attachment" && profile.attachment_style) {
        entry.attachment_style = normaliseScores(profile.attachment_style);
      }
      if (quizType === "love_language" && profile.love_languages) {
        entry.love_languages = normaliseScores(profile.love_languages);
      }
      if (quizType === "communication" && profile.communication_style) {
        entry.communication_style = normaliseScores(
          profile.communication_style,
        );
      }
      if (quizType === "conflict" && profile.conflict_style) {
        entry.conflict_style = normaliseScores(profile.conflict_style);
      }
    }
    shared.set(profile.user_id, entry);
  }

  return Array.from(shared.values());
}

function normaliseScores(input: Record<string, unknown>) {
  const result: Record<string, number | string> = {};
  for (const [key, value] of Object.entries(input)) {
    if (typeof value === "number") {
      result[key] = Math.max(0, Math.min(100, Math.round(value)));
    } else if (
      key.endsWith("_at") || key.includes("version") || key === "primary" ||
      key === "secondary"
    ) {
      result[key] = String(value);
    }
  }
  return result;
}

function buildEvidence(input: {
  pulseHistory: any[];
  patterns: any[];
  sessions: any[];
  timeline: any[];
  gameInsights: any[];
}) {
  const evidence: any[] = [];

  for (const pulse of input.pulseHistory) {
    for (
      const metric of [
        "overall_score",
        "communication",
        "connection",
        "conflict_health",
        "alignment",
        "emotional_safety",
      ]
    ) {
      evidence.push({
        evidence_id: `pulse:${pulse.id}:${metric}`,
        source_type: "pulse_dimension",
        source_record_id: pulse.id,
        observed_at: pulse.computed_at ?? new Date().toISOString(),
        metric,
        value: pulse[metric],
        delta: pulse.delta_vs_previous
          ?.[metric.replace("overall_score", "overall")] ?? null,
        sample_size: input.pulseHistory.length,
        framework_confidence: mapFrameworkConfidence(pulse.data_confidence),
        display_source:
          `Based on ${input.pulseHistory.length} weekly Pulse scores`,
      });
    }
  }

  for (const pattern of input.patterns) {
    evidence.push({
      evidence_id: `pattern:${pattern.id}`,
      source_type: "pattern",
      source_record_id: pattern.id,
      observed_at: pattern.last_seen_at,
      metric: pattern.pattern_type,
      value: pattern.occurrence_count,
      delta: null,
      sample_size: pattern.occurrence_count,
      framework_confidence: pattern.severity === "act" ? "high" : "medium",
      display_source: "Based on repeated shared patterns across sessions",
    });
  }

  for (const session of input.sessions) {
    evidence.push({
      evidence_id: `session:${session.id}`,
      source_type: "session_summary",
      source_record_id: session.id,
      observed_at: session.ended_at,
      metric: session.dominant_topic ?? "session",
      value: session.message_count ?? 0,
      delta: null,
      sample_size: 1,
      framework_confidence: "medium",
      display_source: "Based on recent shared session summaries",
    });
  }

  for (const event of input.timeline) {
    evidence.push({
      evidence_id: `timeline:${event.id}`,
      source_type: "timeline_event",
      source_record_id: event.id,
      observed_at: new Date(event.occurred_at).toISOString(),
      metric: event.event_type,
      value: 1,
      delta: null,
      sample_size: 1,
      framework_confidence: event.event_type === "conflict" ? "medium" : "high",
      display_source: "Based on shared timeline events",
    });
  }

  for (const session of input.gameInsights) {
    evidence.push({
      evidence_id: `game:${session.id}`,
      source_type: "game_insight",
      source_record_id: session.id,
      observed_at: session.completed_at,
      metric: session.game_type,
      value: 1,
      delta: null,
      sample_size: 1,
      framework_confidence: "lower",
      display_source: "Based on shared game insights",
    });
  }

  return evidence;
}

function validateEligibility(context: any) {
  if ((context.pulseHistory?.length ?? 0) < 3) {
    throw new Error("not_enough_pulse_data");
  }
  if (
    (context.sessions?.length ?? 0) < 3 &&
    (context.metadata?.eligible_session_count ?? 0) < 5
  ) {
    throw new Error("not_enough_sessions");
  }
  const hasStrength = context.evidence.some((item: any) =>
    ["connection", "communication", "milestone", "highlight", "anniversary"]
      .includes(item.metric) &&
    item.framework_confidence !== "lower"
  );
  const hasWatch = context.evidence.some((item: any) =>
    item.source_type === "pattern" ||
    item.metric === "conflict" ||
    (typeof item.delta === "number" && item.delta <= -5)
  );
  if (!hasStrength || !hasWatch) {
    throw new Error("insufficient_evidence");
  }
}

async function generateVerdict(context: any) {
  if (!CLAUDE_API_KEY) {
    throw new Error("missing_claude_api_key");
  }

  const response = await fetch(CLAUDE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": CLAUDE_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL_NAME,
      max_tokens: 500,
      system: [
        "ABSOLUTE CONSTRAINTS:",
        "1. Never attribute a negative behaviour to a named or implied partner.",
        "2. Never diagnose. Observe patterns. Frame with agency.",
        "3. Never use toxic, narcissist, codependent, disorder, broken, healthy, unhealthy.",
        "4. Never tell users what to decide.",
        "5. Return ONLY valid JSON.",
      ].join("\n"),
      messages: [
        {
          role: "user",
          content: buildPrompt(context),
        },
      ],
    }),
    signal: AbortSignal.timeout(10000),
  });

  if (response.status !== 200) {
    throw new Error(`claude_${response.status}`);
  }

  const payload = await response.json();
  const text =
    payload.content?.map((block: any) => block.text || "").join("") ?? "";
  return JSON.parse(text.replace(/```json|```/g, "").trim());
}

function buildPrompt(context: any) {
  return `
You are generating a monthly relationship verdict from structured data only.
You have NOT read raw messages. Do not reference anything not in the data below.

RELATIONSHIP CONTEXT:
${JSON.stringify(context.metadata)}

PULSE HISTORY:
${JSON.stringify(context.pulseHistory)}

ACTIVE PATTERNS:
${JSON.stringify(context.patterns)}

RECENT SESSIONS:
${JSON.stringify(context.sessions)}

PSYCHOLOGICAL PROFILES:
${JSON.stringify(context.sharedProfiles)}

TIMELINE EVENTS:
${JSON.stringify(context.timeline)}

GAME INSIGHTS:
${JSON.stringify(context.gameInsights)}

EVIDENCE REGISTRY:
${JSON.stringify(context.evidence)}

Return ONLY valid JSON:
{
  "headline": string,
  "strengths": [
    { "title": string, "body": string, "evidence_ids": [string] }
  ],
  "watch_areas": [
    { "title": string, "body": string, "evidence_ids": [string] }
  ],
  "one_action": string,
  "one_action_evidence_ids": [string],
  "patterns_referenced": [string]
}
`;
}

function validateModelOutput(output: any, evidence: any[]) {
  if (!output || typeof output !== "object") {
    throw new Error("invalid_output");
  }

  const allowedKeys = [
    "headline",
    "strengths",
    "watch_areas",
    "one_action",
    "one_action_evidence_ids",
    "patterns_referenced",
  ];
  for (const key of Object.keys(output)) {
    if (!allowedKeys.includes(key)) {
      throw new Error("invalid_output_key");
    }
  }

  if (
    typeof output.headline !== "string" || output.headline.trim().length === 0
  ) {
    throw new Error("invalid_headline");
  }
  if (
    !Array.isArray(output.strengths) || output.strengths.length < 1 ||
    output.strengths.length > 3
  ) {
    throw new Error("invalid_strengths");
  }
  if (
    !Array.isArray(output.watch_areas) || output.watch_areas.length < 1 ||
    output.watch_areas.length > 3
  ) {
    throw new Error("invalid_watch_areas");
  }
  if (
    typeof output.one_action !== "string" ||
    output.one_action.trim().length === 0
  ) {
    throw new Error("invalid_one_action");
  }

  const evidenceIds = new Set(evidence.map((item: any) => item.evidence_id));
  const allText = JSON.stringify(output);
  for (const pattern of BANNED_PATTERNS) {
    if (pattern.test(allText)) {
      throw new Error("banned_language");
    }
  }

  for (const item of [...output.strengths, ...output.watch_areas]) {
    validateItem(item, evidenceIds);
  }
  if (
    !Array.isArray(output.one_action_evidence_ids) ||
    output.one_action_evidence_ids.length === 0
  ) {
    throw new Error("invalid_one_action_evidence");
  }
  for (const id of output.one_action_evidence_ids) {
    if (!evidenceIds.has(id)) {
      throw new Error("unknown_evidence_reference");
    }
  }

  return output;
}

function validateItem(item: any, evidenceIds: Set<string>) {
  if (typeof item?.title !== "string" || typeof item?.body !== "string") {
    throw new Error("invalid_item");
  }
  if (!Array.isArray(item.evidence_ids) || item.evidence_ids.length === 0) {
    throw new Error("missing_item_evidence");
  }
  for (const id of item.evidence_ids) {
    if (!evidenceIds.has(id)) {
      throw new Error("unknown_evidence_reference");
    }
  }
}

function computeConfidence(context: any) {
  const pulseCount = context.pulseHistory.length;
  const sessionCount = context.metadata?.eligible_session_count ?? 0;
  const sourceTypes =
    new Set(context.evidence.map((item: any) => item.source_type)).size;

  if (pulseCount >= 20 && sessionCount >= 5 && sourceTypes >= 3) {
    return {
      level: "high",
      label: `Based on ${pulseCount} weeks of comprehensive data`,
    };
  }
  if (pulseCount >= 9 && sessionCount >= 5) {
    return {
      level: "medium",
      label: `Based on ${pulseCount} weeks of data`,
    };
  }
  return {
    level: "low",
    label: "Based on early data",
  };
}

function mapFrameworkConfidence(value: string | null | undefined) {
  if (value === "high" || value === "medium") {
    return value;
  }
  return "lower";
}

async function markJobComplete(supabase: any, jobId: string) {
  await supabase
    .from("verdict_generation_jobs")
    .update({
      status: "completed",
      last_error: null,
    })
    .eq("id", jobId);
}

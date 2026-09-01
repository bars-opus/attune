import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { callGeminiJson, partnerNamePatterns } from "../_shared/gemini_json.ts";

const GLOBAL_CONSTRAINTS = `
ABSOLUTE CONSTRAINTS — these override all other instructions:

1. Never generate text that attributes a negative behaviour to a named
   or implied partner.
2. Never generate a sentence of form "[partner name/pronoun] tends to X"
   where X is a negative or deficit behaviour.
3. Personal insights must be written in second person about the reader.
4. Partner name must never appear in a personal_insights row.
5. Never use these words: toxic, narcissist, codependent, disorder, broken.
6. Never tell the user what to decide about the relationship.
7. Never diagnose. Observe patterns. Frame with agency. Source every claim.
8. Return ONLY valid JSON. No preamble. No markdown fences.
`;

const SESSION_GAP_MS = 30 * 60 * 1000;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return jsonResponse({ ok: true });
  }

  const supabase = serviceRoleClient();
  const body = req.method === "POST"
    ? await req.json().catch((): Record<string, unknown> => ({}))
    : {};
  const limit = typeof body.limit === "number" ? body.limit : 20;
  const relationshipId = typeof body.relationship_id === "string"
    ? body.relationship_id
    : null;
  const sessionId = typeof body.session_id === "string" ? body.session_id : null;

  try {
    requireServiceRole(req);
    const retrySessions = await loadRetrySessions(supabase, sessionId, limit);
    const results = [];

    for (const retrySession of retrySessions) {
      results.push(await retryExistingSession(supabase, retrySession));
    }

    const relationshipIds = await loadCandidateRelationshipIds(
      supabase,
      relationshipId,
      limit,
    );

    for (const id of relationshipIds) {
      const relationshipResults = await processRelationship(supabase, id);
      results.push(...relationshipResults);
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

async function loadCandidateRelationshipIds(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string | null,
  limit: number,
) {
  let query = supabase
    .from("messages")
    .select("relationship_id")
    .eq("message_analysis_done", true)
    .is("included_in_session_id", null)
    .lt("created_at", new Date(Date.now() - SESSION_GAP_MS).toISOString())
    .order("created_at", { ascending: true })
    .limit(Math.min(Math.max(limit, 1), 100));

  if (relationshipId) {
    query = query.eq("relationship_id", relationshipId);
  }

  const { data, error } = await query;
  if (error) throw error;

  return [...new Set((data ?? []).map((row: { relationship_id: string }) => row.relationship_id))];
}

async function processRelationship(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
) {
  const relationship = await loadRelationship(supabase, relationshipId);
  if (!relationship || relationship.chat_archived_at) {
    return [];
  }

  const { data: rows, error } = await supabase
    .from("messages")
    .select(`
      id,
      relationship_id,
      sender_id,
      content,
      created_at,
      tone_score,
      nvc_violations,
      bid_type,
      source,
      import_job_id,
      users:users!messages_sender_id_fkey(display_name)
    `)
    .eq("relationship_id", relationshipId)
    .eq("message_analysis_done", true)
    .is("included_in_session_id", null)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });

  if (error) throw error;

  const messages = (rows ?? []).map((row: Record<string, unknown>) => ({
    ...row,
    sender_name: normalizeJoinedUser(row.users, String(row.sender_id)).display_name,
  }));

  const segments = splitByGap(messages, SESSION_GAP_MS);
  const results = [];

  for (const segment of segments) {
    if (segment.length === 0) continue;
    const last = segment[segment.length - 1];
    const gap = Date.now() - new Date(String(last.created_at)).getTime();
    if (gap < SESSION_GAP_MS) continue;
    results.push(await analyzeSegment(supabase, relationship, segment));
  }

  return results;
}

async function analyzeSegment(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationship: RelationshipContext,
  segment: Array<Record<string, unknown>>,
) {
  const fullMessageCount = segment.length;
  const oneSided = new Set(segment.map((message) => String(message.sender_id))).size === 1;
  const transcriptMessages = fullMessageCount > 80
    ? [...segment.slice(0, 20), ...segment.slice(-20)]
    : segment;
  const importJobIds = [...new Set(
    segment.map((message) => message.import_job_id).filter((id): id is string =>
      typeof id === "string"
    ),
  )];
  const importedCount = segment.filter((message) => message.source === "import:whatsapp").length;
  const sourceType = importedCount === 0
    ? "native"
    : importedCount === fullMessageCount
    ? "import"
    : "mixed";

  const session = await createSessionRow(supabase, {
    relationshipId: relationship.id,
    startedAt: String(segment[0].created_at),
    endedAt: String(segment[segment.length - 1].created_at),
    messageCount: fullMessageCount,
    oneSidedSession: oneSided,
    truncated: fullMessageCount > 80,
    sourceType,
    importJobIds,
  });

  await consumeMessagesIntoSession(
    supabase,
    session.id,
    segment.map((message) => String(message.id)),
  );

  const [profiles, conflictSessions30d, existingPatterns, translatorNeedCounts, totalSessions] = await Promise.all([
    loadRelationshipProfiles(supabase, relationship),
    loadConflictSessionCount(supabase, relationship.id),
    loadExistingPatterns(supabase, relationship.id),
    loadTranslatorNeedCounts(supabase, relationship.id),
    loadTotalSessions(supabase, relationship.id),
  ]);

  const layerTwo = await callGeminiJson({
    promptId: "layer2_session_analysis",
    systemPrompt: GLOBAL_CONSTRAINTS,
    userPrompt: buildLayerTwoPrompt({
      transcriptMessages,
      messageCount: fullMessageCount,
      oneSidedSession: oneSided,
      conflictSessions30d,
      profiles,
    }),
    maxOutputTokens: 500,
    runtimeProhibitedPatterns: partnerNamePatterns([
      relationship.userA.display_name,
      relationship.userB.display_name,
    ]),
  });

  const validatedLayerTwo = validateLayerTwo(layerTwo);
  if (validatedLayerTwo) {
    const updateResult = await supabase
      .from("analysis_sessions")
      .update(validatedLayerTwo)
      .eq("id", session.id);
    if (updateResult.error) {
      throw updateResult.error;
    }
  }

  if (validatedLayerTwo) {
    const layerFour = await callGeminiJson({
      promptId: "layer4_pattern_memory",
      systemPrompt: GLOBAL_CONSTRAINTS,
      userPrompt: buildLayerFourPrompt({
        sessionAnalysis: validatedLayerTwo,
        existingPatterns,
        daysTogether: relationship.daysTogether,
        totalSessions,
        conflictSessions30d,
        translatorNeedCounts,
      }),
      maxOutputTokens: 600,
      runtimeProhibitedPatterns: partnerNamePatterns([
        relationship.userA.display_name,
        relationship.userB.display_name,
      ]),
    });

    const validatedLayerFour = validateLayerFour(layerFour);
    if (validatedLayerFour) {
      await applyPatternUpdates(
        supabase,
        relationship.id,
        existingPatterns,
        validatedLayerFour,
        { sourceType, importJobIds },
      );
      await markPatternMemoryStatus(supabase, session.id, true);
    } else {
      await markPatternMemoryStatus(supabase, session.id, false);
    }
  }

  return {
    relationship_id: relationship.id,
    session_id: session.id,
    message_count: fullMessageCount,
    analyzed: validatedLayerTwo !== null,
  };
}

async function loadRetrySessions(
  supabase: ReturnType<typeof serviceRoleClient>,
  sessionId: string | null,
  limit: number,
) {
  let query = supabase
    .from("analysis_sessions")
    .select("id")
    .or("escalation_score.is.null,pattern_memory_done.eq.false")
    .order("started_at", { ascending: true })
    .limit(Math.min(Math.max(limit, 1), 100));

  if (sessionId) {
    query = query.eq("id", sessionId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

async function retryExistingSession(
  supabase: ReturnType<typeof serviceRoleClient>,
  session: { id: string },
) {
  const { data: sessionRow, error: sessionError } = await supabase
    .from("analysis_sessions")
    .select("*")
    .eq("id", session.id)
    .single();
  if (sessionError) throw sessionError;

  const relationship = await loadRelationship(
    supabase,
    String(sessionRow.relationship_id),
  );
  if (!relationship || relationship.chat_archived_at) {
    return { session_id: session.id, status: "skipped_relationship_archived" };
  }

  const { data: messages, error: messageError } = await supabase
    .from("messages")
    .select(`
      id,
      relationship_id,
      sender_id,
      content,
      created_at,
      tone_score,
      nvc_violations,
      bid_type,
      source,
      import_job_id,
      users:users!messages_sender_id_fkey(display_name)
    `)
    .eq("included_in_session_id", session.id)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });
  if (messageError) throw messageError;

  const transcriptMessages: Array<Record<string, unknown>> = (messages ?? []).map(
    (row: Record<string, unknown>) => ({
      ...row,
      sender_name: normalizeJoinedUser(row.users, String(row.sender_id)).display_name,
    }),
  );
  const retryImportJobIds = [...new Set(
    transcriptMessages.map((message) => message.import_job_id).filter((id): id is string =>
      typeof id === "string"
    ),
  )];
  const retrySourceType = String(sessionRow.source_type ?? "native");

  const [profiles, conflictSessions30d, existingPatterns, translatorNeedCounts, totalSessions] = await Promise.all([
    loadRelationshipProfiles(supabase, relationship),
    loadConflictSessionCount(supabase, relationship.id),
    loadExistingPatterns(supabase, relationship.id),
    loadTranslatorNeedCounts(supabase, relationship.id),
    loadTotalSessions(supabase, relationship.id),
  ]);

  const layerTwo = await callGeminiJson({
    promptId: "layer2_session_analysis_retry",
    systemPrompt: GLOBAL_CONSTRAINTS,
    userPrompt: buildLayerTwoPrompt({
      transcriptMessages,
      messageCount: Number(sessionRow.message_count ?? transcriptMessages.length),
      oneSidedSession: sessionRow.one_sided_session === true,
      conflictSessions30d,
      profiles,
    }),
    maxOutputTokens: 500,
    runtimeProhibitedPatterns: partnerNamePatterns([
      relationship.userA.display_name,
      relationship.userB.display_name,
    ]),
  });

  const validatedLayerTwo = validateLayerTwo(layerTwo);
  if (validatedLayerTwo) {
    const updateResult = await supabase
      .from("analysis_sessions")
      .update(validatedLayerTwo)
      .eq("id", session.id);
    if (updateResult.error) {
      throw updateResult.error;
    }
  } else {
    return { session_id: session.id, status: "retry_pending_layer2" };
  }

  const layerFour = await callGeminiJson({
    promptId: "layer4_pattern_memory_retry",
    systemPrompt: GLOBAL_CONSTRAINTS,
    userPrompt: buildLayerFourPrompt({
      sessionAnalysis: validatedLayerTwo,
      existingPatterns,
      daysTogether: relationship.daysTogether,
      totalSessions,
      conflictSessions30d,
      translatorNeedCounts,
    }),
    maxOutputTokens: 600,
    runtimeProhibitedPatterns: partnerNamePatterns([
      relationship.userA.display_name,
      relationship.userB.display_name,
    ]),
  });

  const validatedLayerFour = validateLayerFour(layerFour);
  if (validatedLayerFour) {
    await applyPatternUpdates(
      supabase,
      relationship.id,
      existingPatterns,
      validatedLayerFour,
      { sourceType: retrySourceType, importJobIds: retryImportJobIds },
    );
    await markPatternMemoryStatus(supabase, session.id, true);
    return { session_id: session.id, status: "retried_complete" };
  }

  await markPatternMemoryStatus(supabase, session.id, false);
  return { session_id: session.id, status: "retry_pending_layer4" };
}

async function loadRelationship(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
): Promise<RelationshipContext | null> {
  const { data, error } = await supabase
    .from("relationships")
    .select(`
      id,
      status,
      started_at,
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

  const startedAt = typeof data.started_at === "string" ? data.started_at : null;
  const daysTogether = startedAt
    ? Math.max(
      0,
      Math.floor(
        (Date.now() - new Date(startedAt).getTime()) / (24 * 60 * 60 * 1000),
      ),
    )
    : 0;

  return {
    id: String(data.id),
    status: String(data.status),
    chat_archived_at: data.chat_archived_at as string | null,
    daysTogether,
    userA: normalizeJoinedUser(data.users_user_a, String(data.user_a)),
    userB: normalizeJoinedUser(data.users_user_b, data.user_b as string | null),
  };
}

async function createSessionRow(
  supabase: ReturnType<typeof serviceRoleClient>,
  payload: {
    relationshipId: string;
    startedAt: string;
    endedAt: string;
    messageCount: number;
    oneSidedSession: boolean;
    truncated: boolean;
    sourceType: string;
    importJobIds: string[];
  },
) {
  const insert = await supabase
    .from("analysis_sessions")
    .insert({
      relationship_id: payload.relationshipId,
      started_at: payload.startedAt,
      ended_at: payload.endedAt,
      message_count: payload.messageCount,
      trigger_type: "inactivity",
      one_sided_session: payload.oneSidedSession,
      truncated: payload.truncated,
      source_type: payload.sourceType,
      source_import_job_ids: payload.importJobIds,
    })
    .select("id")
    .single();

  if (insert.error) throw insert.error;

  const bumpResult = await supabase.rpc("bump_relationship_total_sessions", {
    p_relationship_id: payload.relationshipId,
  });
  if (bumpResult.error) throw bumpResult.error;

  return insert.data;
}

async function consumeMessagesIntoSession(
  supabase: ReturnType<typeof serviceRoleClient>,
  sessionId: string,
  messageIds: string[],
) {
  const { error } = await supabase
    .from("messages")
    .update({ included_in_session_id: sessionId })
    .in("id", messageIds)
    .is("included_in_session_id", null);

  if (error) throw error;
}

async function loadRelationshipProfiles(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationship: RelationshipContext,
) {
  const { data, error } = await supabase
    .from("psych_profiles")
    .select("user_id, attachment_style")
    .in("user_id", [relationship.userA.id, relationship.userB.id].filter(Boolean));
  if (error) throw error;

  const byUser = new Map((data ?? []).map((row: { user_id: string; attachment_style: unknown }) => [
    row.user_id,
    row.attachment_style ?? {},
  ]));

  return {
    userAAttachment: byUser.get(relationship.userA.id) ?? {},
    userBAttachment: byUser.get(relationship.userB.id) ?? {},
  };
}

async function loadConflictSessionCount(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
) {
  const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await supabase
    .from("analysis_sessions")
    .select("id")
    .eq("relationship_id", relationshipId)
    .gte("started_at", cutoff)
    .or("escalation_score.gte.0.5,insight_worthy.eq.true");
  if (error) throw error;
  return (data ?? []).length;
}

async function loadExistingPatterns(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
) {
  const { data, error } = await supabase
    .from("patterns")
    .select("*")
    .eq("relationship_id", relationshipId)
    .neq("severity", "resolved")
    .order("last_seen_at", { ascending: false })
    .limit(15);
  if (error) throw error;
  return data ?? [];
}

async function loadTranslatorNeedCounts(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
) {
  const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await supabase
    .from("translator_logs")
    .select("core_need_identified")
    .eq("relationship_id", relationshipId)
    .gte("used_at", cutoff);
  if (error) throw error;

  const counts: Record<string, number> = {};
  for (const row of data ?? []) {
    const need = typeof row.core_need_identified === "string"
      ? row.core_need_identified
      : null;
    if (!need) continue;
    counts[need] = (counts[need] ?? 0) + 1;
  }
  return counts;
}

async function loadTotalSessions(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
) {
  const { count, error } = await supabase
    .from("analysis_sessions")
    .select("id", { count: "exact", head: true })
    .eq("relationship_id", relationshipId);
  if (error) throw error;
  return count ?? 0;
}

async function markPatternMemoryStatus(
  supabase: ReturnType<typeof serviceRoleClient>,
  sessionId: string,
  done: boolean,
) {
  const { error } = await supabase
    .from("analysis_sessions")
    .update({
      pattern_memory_done: done,
      pattern_memory_attempted_at: new Date().toISOString(),
    })
    .eq("id", sessionId);
  if (error) throw error;
}

function buildLayerTwoPrompt(input: {
  transcriptMessages: Array<Record<string, unknown>>;
  messageCount: number;
  oneSidedSession: boolean;
  conflictSessions30d: number;
  profiles: {
    userAAttachment: unknown;
    userBAttachment: unknown;
  };
}) {
  return `
You are a relationship intelligence system. Analyse this conversation session.

FULL SESSION (${input.messageCount} messages):
${JSON.stringify(input.transcriptMessages)}

RELATIONSHIP CONTEXT:
- User A attachment: ${JSON.stringify(input.profiles.userAAttachment)}
- User B attachment: ${JSON.stringify(input.profiles.userBAttachment)}
- Conflict sessions last 30 days: ${input.conflictSessions30d}
- One-sided session: ${input.oneSidedSession}

Return ONLY valid JSON:
{
  "escalation_score": float 0.0 to 1.0,
  "escalation_trajectory": "rising" | "falling" | "stable" | "peaked",
  "pursue_withdraw_detected": boolean,
  "pursuer": "user_a" | "user_b" | null,
  "stonewalling_signals": boolean,
  "repair_attempted": boolean,
  "repair_landed": boolean,
  "session_resolved": boolean,
  "dominant_topic": string,
  "root_need_detected": "respect"|"fairness"|"affection"|"security"|"autonomy"|"rest"|null,
  "insight_worthy": boolean,
  "suggested_insight": string | null
}
  `.trim();
}

function buildLayerFourPrompt(input: {
  sessionAnalysis: Record<string, unknown>;
  existingPatterns: unknown[];
  daysTogether: number;
  totalSessions: number;
  conflictSessions30d: number;
  translatorNeedCounts: Record<string, number>;
}) {
  return `
You are a relationship pattern analyst.

SESSION ANALYSIS:
${JSON.stringify(input.sessionAnalysis)}

EXISTING PATTERNS:
${JSON.stringify(input.existingPatterns)}

RELATIONSHIP HISTORY:
- Days together: ${input.daysTogether}
- Total sessions: ${input.totalSessions}
- Conflict sessions last 30 days: ${input.conflictSessions30d}
- Translator core-need counts last 30 days: ${JSON.stringify(input.translatorNeedCounts)}

Return ONLY valid JSON:
{
  "patterns_to_create": [
    {
      "pattern_type": string,
      "topic_cluster": string,
      "severity": "info" | "watch" | "act" | "safety",
      "metadata": {}
    }
  ],
  "patterns_to_update": [
    {
      "pattern_id": uuid,
      "increment_count": boolean,
      "new_severity": string | null,
      "metadata_update": {}
    }
  ],
  "alert_required": boolean,
  "alert_type": "safety" | "milestone" | "insight" | null
}
  `.trim();
}

function validateLayerTwo(parsed: Record<string, unknown> | null) {
  if (!parsed) return null;

  const result: Record<string, unknown> = {};
  if (typeof parsed.escalation_score === "number") {
    result.escalation_score = Math.max(0, Math.min(1, parsed.escalation_score));
  }
  if (
    typeof parsed.escalation_trajectory === "string" &&
    ["rising", "falling", "stable", "peaked"].includes(parsed.escalation_trajectory)
  ) {
    result.escalation_trajectory = parsed.escalation_trajectory;
  }
  result.pursue_withdraw_detected = parsed.pursue_withdraw_detected === true;
  if (
    typeof parsed.pursuer === "string" &&
    ["user_a", "user_b"].includes(parsed.pursuer)
  ) {
    result.pursuer = parsed.pursuer;
  } else {
    result.pursuer = null;
  }
  result.stonewalling_signals = parsed.stonewalling_signals === true;
  result.repair_attempted = parsed.repair_attempted === true;
  result.repair_landed = parsed.repair_landed === true;
  result.session_resolved = parsed.session_resolved === true;
  result.insight_worthy = parsed.insight_worthy === true;

  if (typeof parsed.dominant_topic === "string") {
    result.dominant_topic = parsed.dominant_topic.slice(0, 60);
  }
  if (
    typeof parsed.root_need_detected === "string" &&
    ["respect", "fairness", "affection", "security", "autonomy", "rest"].includes(
      parsed.root_need_detected,
    )
  ) {
    result.root_need_detected = parsed.root_need_detected;
  } else {
    result.root_need_detected = null;
  }
  if (typeof parsed.suggested_insight === "string") {
    result.suggested_insight = parsed.suggested_insight.slice(0, 180);
  } else {
    result.suggested_insight = null;
  }

  return result;
}

function validateLayerFour(parsed: Record<string, unknown> | null) {
  if (!parsed) return null;
  const patternsToCreate = Array.isArray(parsed.patterns_to_create)
    ? parsed.patterns_to_create.filter(isPatternCreate)
    : [];
  const patternsToUpdate = Array.isArray(parsed.patterns_to_update)
    ? parsed.patterns_to_update.filter(isPatternUpdate)
    : [];

  return {
    patternsToCreate,
    patternsToUpdate,
  };
}

async function applyPatternUpdates(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
  existingPatterns: Array<Record<string, unknown>>,
  layerFour: {
    patternsToCreate: PatternCreate[];
    patternsToUpdate: PatternUpdate[];
  },
  provenance: { sourceType: string; importJobIds: string[] },
) {
  const knownPatterns = [...existingPatterns];

  for (const update of layerFour.patternsToUpdate) {
    const current = knownPatterns.find((pattern) => pattern.id === update.pattern_id);
    if (!current) continue;

    const payload: Record<string, unknown> = {
      last_seen_at: new Date().toISOString(),
      metadata: {
        ...(typeof current.metadata === "object" && current.metadata !== null
          ? current.metadata as Record<string, unknown>
          : {}),
        ...(update.metadata_update ?? {}),
        source_type: provenance.sourceType,
        import_job_ids: provenance.importJobIds,
      },
    };

    if (update.increment_count) {
      payload.occurrence_count = Number(current.occurrence_count ?? 1) + 1;
    }
    if (update.new_severity) {
      payload.severity = update.new_severity;
    }

    const { error } = await supabase
      .from("patterns")
      .update(payload)
      .eq("id", update.pattern_id)
      .eq("relationship_id", relationshipId);
    if (error) throw error;
    Object.assign(current, payload);
  }

  for (const create of layerFour.patternsToCreate) {
    const duplicate = knownPatterns.find((pattern) =>
      pattern.pattern_type === create.pattern_type &&
      (pattern.topic_cluster ?? null) === (create.topic_cluster ?? null) &&
      pattern.severity !== "resolved"
    );

    if (duplicate) {
      const { error } = await supabase
        .from("patterns")
        .update({
          last_seen_at: new Date().toISOString(),
          occurrence_count: Number(duplicate.occurrence_count ?? 1) + 1,
          severity: create.severity,
          metadata: {
            ...(typeof duplicate.metadata === "object" && duplicate.metadata !== null
              ? duplicate.metadata as Record<string, unknown>
              : {}),
            ...(create.metadata ?? {}),
            source_type: provenance.sourceType,
            import_job_ids: provenance.importJobIds,
          },
        })
        .eq("id", String(duplicate.id));
      if (error) throw error;
      Object.assign(duplicate, {
        last_seen_at: new Date().toISOString(),
        occurrence_count: Number(duplicate.occurrence_count ?? 1) + 1,
        severity: create.severity,
        metadata: {
          ...(typeof duplicate.metadata === "object" && duplicate.metadata !== null
            ? duplicate.metadata as Record<string, unknown>
            : {}),
          ...(create.metadata ?? {}),
        },
      });
      continue;
    }

    const { data, error } = await supabase
      .from("patterns")
      .insert({
        relationship_id: relationshipId,
        pattern_type: create.pattern_type,
        severity: create.severity,
        topic_cluster: create.topic_cluster,
        metadata: {
          ...(create.metadata ?? {}),
          source_type: provenance.sourceType,
          import_job_ids: provenance.importJobIds,
        },
      })
      .select("*")
      .single();
    if (error) throw error;
    knownPatterns.push(data);
  }
}

function splitByGap(messages: Array<Record<string, unknown>>, gapMs: number) {
  if (messages.length === 0) return [];
  const segments: Array<Array<Record<string, unknown>>> = [[messages[0]]];

  for (let i = 1; i < messages.length; i += 1) {
    const gap = new Date(String(messages[i].created_at)).getTime() -
      new Date(String(messages[i - 1].created_at)).getTime();
    if (gap > gapMs) {
      segments.push([]);
    }
    segments[segments.length - 1].push(messages[i]);
  }

  return segments;
}

function normalizeJoinedUser(value: unknown, fallbackId: string | null) {
  const row = Array.isArray(value) ? value[0] : value;
  const candidate = row as { id?: string; display_name?: string } | null | undefined;
  return {
    id: candidate?.id ?? fallbackId ?? "",
    display_name: candidate?.display_name ?? "Partner",
  };
}

function isPatternCreate(value: unknown): value is PatternCreate {
  const row = value as PatternCreate | null;
  return !!row &&
    typeof row.pattern_type === "string" &&
    typeof row.severity === "string" &&
    ["info", "watch", "act", "safety"].includes(row.severity);
}

function isPatternUpdate(value: unknown): value is PatternUpdate {
  const row = value as PatternUpdate | null;
  return !!row && typeof row.pattern_id === "string";
}

type PatternCreate = {
  pattern_type: string;
  topic_cluster?: string | null;
  severity: "info" | "watch" | "act" | "safety";
  metadata?: Record<string, unknown>;
};

type PatternUpdate = {
  pattern_id: string;
  increment_count?: boolean;
  new_severity?: "info" | "watch" | "act" | "safety" | "resolved" | null;
  metadata_update?: Record<string, unknown>;
};

type RelationshipContext = {
  id: string;
  status: string;
  chat_archived_at: string | null;
  daysTogether: number;
  userA: { id: string; display_name: string };
  userB: { id: string; display_name: string };
};

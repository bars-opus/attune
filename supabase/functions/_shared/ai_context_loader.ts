// Trusted, server-side context construction for the AI Assistant. This
// is the file that makes client-supplied chat context structurally
// impossible: both ai-assist and ai-understand call ONLY these two
// functions to learn anything about a message or its surrounding
// conversation. Spec §4.2, §4.3.
//
// The `client` parameter here MUST be the client returned by
// userScopedClient() (user_scoped_client.ts) -- i.e. a client authorized
// with the caller's own JWT and subject to RLS. Never pass a
// serviceRoleClient() here: doing so would make every check below a
// no-op, since RLS -- not application logic -- is what makes a
// non-member's read of another couple's messages/relationships row
// return nothing.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

export interface LoadedTarget {
  messageId: string;
  relationshipId: string;
  senderId: string;
  createdAt: string;
  content: string;
}

export type TargetLoadResult =
  | { ok: true; target: LoadedTarget }
  | { ok: false; code: "TARGET_UNAVAILABLE" };

export interface ContextMessage {
  role: "requester" | "partner";
  createdAt: string;
  content: string;
  truncated: boolean;
}

const MAX_TARGET_CHARS = 4000;
const MAX_SURROUNDING_CHARS = 1000;
const MAX_TOTAL_CONTEXT_CHARS = 12000;
const ASSIST_ROW_CAP = 6;
const UNDERSTAND_ROW_CAP = 19;

export async function loadAiAssistantTarget(
  client: SupabaseClient,
  userId: string,
  messageId: string,
): Promise<TargetLoadResult> {
  // Query through the USER-SCOPED client (RLS-authorized), never
  // service-role -- if this row is not visible to this user under RLS,
  // the query returns nothing and we report TARGET_UNAVAILABLE, exactly
  // as if the row didn't exist. This is the load-bearing line: a
  // non-member's userScopedClient literally cannot see a row in another
  // couple's relationship, so there is no separate "check membership"
  // step to get wrong or bypass.
  const { data: message, error } = await client
    .from("messages")
    .select(
      "id, relationship_id, sender_id, created_at, content, deleted_at, is_system_notice, message_origin, media_url, game_session_id",
    )
    .eq("id", messageId)
    .maybeSingle();

  if (error || !message) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }
  if (message.deleted_at) return { ok: false, code: "TARGET_UNAVAILABLE" };
  if (message.is_system_notice) return { ok: false, code: "TARGET_UNAVAILABLE" };
  if (message.message_origin === "attune_assist") {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }
  if (message.media_url || message.game_session_id) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }
  const content = typeof message.content === "string" ? message.content : "";
  if (content.trim().length === 0) return { ok: false, code: "TARGET_UNAVAILABLE" };
  if (content.length > MAX_TARGET_CHARS) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }

  const { data: relationship, error: relError } = await client
    .from("relationships")
    .select("id, status, chat_archived_at, user_a, user_b")
    .eq("id", message.relationship_id)
    .maybeSingle();
  if (relError || !relationship) return { ok: false, code: "TARGET_UNAVAILABLE" };
  if (relationship.status !== "active" || relationship.chat_archived_at) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }
  if (relationship.user_a !== userId && relationship.user_b !== userId) {
    return { ok: false, code: "TARGET_UNAVAILABLE" };
  }

  return {
    ok: true,
    target: {
      messageId: message.id,
      relationshipId: message.relationship_id,
      senderId: message.sender_id,
      createdAt: message.created_at,
      content,
    },
  };
}

export async function loadBoundedContext(
  client: SupabaseClient,
  target: LoadedTarget,
  mode: "assist" | "understand",
  requesterId: string,
  utcOffsetMinutes?: number,
): Promise<ContextMessage[]> {
  const rowCap = mode === "assist" ? ASSIST_ROW_CAP : UNDERSTAND_ROW_CAP;
  const beforeCount = mode === "assist" ? 3 : 12;
  const afterCount = mode === "assist" ? 3 : 7;

  let dayStart: string | null = null;
  let dayEnd: string | null = null;
  if (mode === "understand") {
    const offset = utcOffsetMinutes ?? 0;
    const targetLocal = new Date(
      new Date(target.createdAt).getTime() + offset * 60_000,
    );
    const dayStartLocal = new Date(
      targetLocal.getFullYear(),
      targetLocal.getMonth(),
      targetLocal.getDate(),
    );
    dayStart = new Date(dayStartLocal.getTime() - offset * 60_000).toISOString();
    dayEnd = new Date(
      dayStartLocal.getTime() + 24 * 60 * 60_000 - offset * 60_000,
    ).toISOString();
  }

  let beforeQuery = client
    .from("messages")
    .select(
      "id, sender_id, created_at, content, deleted_at, is_system_notice, message_origin, media_url, game_session_id",
    )
    .eq("relationship_id", target.relationshipId)
    .lt("created_at", target.createdAt)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(beforeCount * 3); // overfetch before filtering; filtered client-side below
  if (dayStart) beforeQuery = beforeQuery.gte("created_at", dayStart);

  let afterQuery = client
    .from("messages")
    .select(
      "id, sender_id, created_at, content, deleted_at, is_system_notice, message_origin, media_url, game_session_id",
    )
    .eq("relationship_id", target.relationshipId)
    .gt("created_at", target.createdAt)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true })
    .limit(afterCount * 3);
  if (dayEnd) afterQuery = afterQuery.lt("created_at", dayEnd);

  const [{ data: beforeRows }, { data: afterRows }] = await Promise.all([
    beforeQuery,
    afterQuery,
  ]);

  const isEligible = (row: Record<string, unknown>) =>
    !row.deleted_at &&
    !row.is_system_notice &&
    row.message_origin !== "attune_assist" &&
    !row.media_url &&
    !row.game_session_id &&
    typeof row.content === "string" &&
    (row.content as string).trim().length > 0;

  const before = (beforeRows ?? []).filter(isEligible).slice(0, beforeCount);
  const after = (afterRows ?? []).filter(isEligible).slice(0, afterCount);

  const candidates = [...before.reverse(), ...after].slice(0, rowCap);

  const toContextMessage = (row: Record<string, unknown>): ContextMessage => {
    const content = row.content as string;
    const truncated = content.length > MAX_SURROUNDING_CHARS;
    return {
      role: row.sender_id === requesterId ? "requester" : "partner",
      createdAt: row.created_at as string,
      content: truncated
        ? `${content.slice(0, MAX_SURROUNDING_CHARS)} [truncated]`
        : content,
      truncated,
    };
  };

  const withTarget = candidates.map(toContextMessage);
  let totalChars = target.content.length;
  const result: ContextMessage[] = [];
  for (const msg of withTarget) {
    if (totalChars + msg.content.length > MAX_TOTAL_CONTEXT_CHARS) break;
    result.push(msg);
    totalChars += msg.content.length;
  }

  return result.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

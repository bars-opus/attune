// supabase/functions/process-dating-safety-outbox/handler.ts
//
// Spec 2 W6b (§6.1, §4.6, §4.7; chat spec §1.2, §6, §9): the worker. Each
// run claims queued messages, runs the deterministic engine on each and
// completes it with the rules that fired; the database writes the
// recipient's events and the cases. Fail-open: delivery never waited on
// this. No active config, or a malformed one, is no detection (each
// message is completed with none, and the database counts it), never
// another config; a config that fails to load claims nothing (fix round 1).
// One message's failure is its own: it goes back to the queue with a code
// (dead-lettered after its 5th attempt by the database) and the rest run.
// No message text, rule or person is ever logged. The database may refuse
// a completion ({ok: false, reason}): it is counted as failed and logged by
// its code only; an "invalid" one goes back once with an error code, so the
// database retries it and dead-letters it after its 5th attempt; it is
// never retried here.
import { detect, parseConfig, type Hit } from "../_shared/dating_chat_safety.ts";

export interface Job {
  message_id: string;
  body: string;
  new_match: boolean;
}

export interface Deps {
  claim(limit: number): Promise<Job[]>;
  config(): Promise<unknown>;
  /// Resolves with the database's answer ({ok, reason?}); void counts as ok.
  complete(messageId: string, version: string | null, hits: Hit[], error: string | null): Promise<unknown>;
  log?(line: string): void;
}

export const BATCH = 50;

/// The codes a refused completion is logged by (anything else is "other").
export const REFUSALS = ["invalid", "not_claimed", "other"] as const;
type Refusal = typeof REFUSALS[number];

function refusal(answer: unknown): Refusal | null {
  if (!answer || typeof answer !== "object" || (answer as { ok?: unknown }).ok !== false) return null;
  const reason = (answer as { reason?: unknown }).reason;
  return reason === "invalid" || reason === "not_claimed" ? reason : "other";
}

/// A run that did nothing, with its fixed code (index.ts answers it).
export class WorkerError extends Error {}

export interface RunResult {
  claimed: number;
  completed: number;
  failed: number;
  detection: boolean;
}

export async function runOutbox(deps: Deps, limit = BATCH): Promise<RunResult> {
  // Fix round 1 (review I-2): the config first. One that fails to load
  // claims nothing, so the messages stay queued for the next run; none
  // active (NULL) or a malformed one is no detection, each its own code.
  let raw: unknown;
  try {
    raw = await deps.config();
  } catch {
    deps.log?.("process-dating-safety-outbox: config_failed, nothing claimed");
    throw new WorkerError("config_failed");
  }
  const config = raw === null || raw === undefined ? null : parseConfig(raw);
  const noConfig = raw === null || raw === undefined ? ", no config" : config ? "" : ", config malformed";
  const jobs = await deps.claim(limit);
  let completed = 0;
  let failed = 0;
  const refused = new Map<Refusal, number>();
  for (const job of jobs) {
    let hits: Hit[] = [];
    let error: string | null = null;
    if (config) {
      try {
        hits = detect(job.body, config, { newMatch: job.new_match === true });
      } catch {
        error = "engine_error";
      }
    }
    try {
      const answer = await deps.complete(job.message_id, config?.version ?? null, error ? [] : hits, error);
      const no = refusal(answer);
      if (no) {
        failed++;
        refused.set(no, (refused.get(no) ?? 0) + 1);
        if (no === "invalid" && error === null) {
          try {
            await deps.complete(job.message_id, config?.version ?? null, [], "rejected_hits");
          } catch {
            // Its own: the claim's stale recovery returns it.
          }
        }
      } else if (error) failed++;
      else completed++;
    } catch {
      failed++;
    }
  }
  const why = REFUSALS.filter((r) => refused.has(r)).map((r) => `${r} ${refused.get(r)}`).join(", ");
  deps.log?.(`process-dating-safety-outbox: ${jobs.length} claimed, ${completed} completed, ${failed} failed${why ? ` (${why})` : ""}${noConfig}`);
  return { claimed: jobs.length, completed, failed, detection: config !== null };
}

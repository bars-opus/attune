// Spec 1 W6a (§4.5): the recovery-hold purge, against a fake client.
// Preflight F8: each delete leaves an account_deletion_requests row,
// written before the destructive step (delete-account's order).
import { candidateIds, purgeRecoveryHolds, type RecoveryPurgeClient } from "./handler.ts";

const A = "5f6a0000-0000-0000-0000-0000000000a1";
const B = "5f6a0000-0000-0000-0000-0000000000b2";
const C = "5f6a0000-0000-0000-0000-0000000000c3";

function rig(
  rows: unknown,
  o: { notDue?: string[]; prepareFails?: string[]; deleteFails?: string[]; listFails?: boolean; auditFails?: string[]; auditEmpty?: string[]; recordThrows?: boolean } = {},
) {
  const calls: string[] = [];
  const client: RecoveryPurgeClient = {
    rpc(fn, args) {
      const id = String((args as Record<string, unknown> | undefined)?.p_user ?? (args as Record<string, unknown> | undefined)?.p_user_id ?? "");
      calls.push(`${fn}:${id}`);
      if (fn === "recovery_hold_candidates") {
        return Promise.resolve(o.listFails ? { data: null, error: { message: "boom" } } : { data: rows, error: null });
      }
      if (fn === "is_recovery_hold_due") return Promise.resolve({ data: !(o.notDue ?? []).includes(id), error: null });
      return Promise.resolve({ data: null, error: (o.prepareFails ?? []).includes(id) ? { message: "nope" } : null });
    },
    from(table) {
      return {
        insert(row) {
          // Fix round 1 M-2: a purge row says so; a person's own deletion
          // (delete-account) leaves source NULL.
          calls.push(
            `${table === "account_deletion_requests" && row.source === "recovery_purge" ? "audit" : `${table}:${row.source}`}:${row.user_ref}`,
          );
          return {
            select() {
              return {
                maybeSingle() {
                  return Promise.resolve(
                    (o.auditFails ?? []).includes(row.user_ref)
                      ? { data: null, error: { message: "nope" } }
                      : (o.auditEmpty ?? []).includes(row.user_ref)
                      ? { data: null, error: null }
                      : { data: { id: `audit-${row.user_ref}` }, error: null },
                  );
                },
              };
            },
          };
        },
        update(values) {
          return {
            eq(_column, auditId) {
              const who = auditId.replace(/^audit-/, "");
              calls.push(values.completed_at ? `audit_done:${who}` : `audit_failed:${who}:${values.failure_reason}`);
              return o.recordThrows ? Promise.reject(new Error("network")) : Promise.resolve({ error: null });
            },
          };
        },
      };
    },
    auth: {
      admin: {
        deleteUser(id) {
          calls.push(`delete:${id}`);
          return Promise.resolve({ error: (o.deleteFails ?? []).includes(id) ? { message: "nope" } : null });
        },
      },
    },
  };
  return { client, calls };
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("each due account: re-checked, prepared, then deleted, in that order", async () => {
  const r = rig([A, { recovery_hold_candidates: B }]);
  const result = await purgeRecoveryHolds(r.client);
  assert(JSON.stringify(result) === JSON.stringify({ candidates: 2, deleted: 2, failed: 0, skipped: 0, remaining: 0 }), JSON.stringify(result));
  assert(
    r.calls.join(" ") ===
      `recovery_hold_candidates: is_recovery_hold_due:${A} audit:${A} prepare_account_deletion:${A} delete:${A} ` +
        `audit_done:${A} is_recovery_hold_due:${B} audit:${B} prepare_account_deletion:${B} delete:${B} audit_done:${B}`,
    r.calls.join(" "),
  );
});

Deno.test("a hold resolved since the list was read is skipped; a failed prepare never deletes", async () => {
  const r = rig([A, B, C], { notDue: [A], prepareFails: [B], deleteFails: [C] });
  const result = await purgeRecoveryHolds(r.client);
  assert(JSON.stringify(result) === JSON.stringify({ candidates: 3, deleted: 0, failed: 2, skipped: 1, remaining: 0 }), JSON.stringify(result));
  assert(!r.calls.includes(`delete:${A}`) && !r.calls.includes(`delete:${B}`), r.calls.join(" "));
  assert(!r.calls.includes(`audit:${A}`), `an audit row for a skipped hold: ${r.calls.join(" ")}`);
  assert(
    r.calls.includes(`audit_failed:${B}:recovery_purge:prepare`) && r.calls.includes(`audit_failed:${C}:recovery_purge:delete`),
    `failures not recorded as codes: ${r.calls.join(" ")}`,
  );
});

Deno.test("F8: no audit row, no delete; the row is written before anything destructive", async () => {
  const r = rig([A, B], { auditFails: [A] });
  const result = await purgeRecoveryHolds(r.client);
  assert(JSON.stringify(result) === JSON.stringify({ candidates: 2, deleted: 1, failed: 1, skipped: 0, remaining: 0 }), JSON.stringify(result));
  assert(!r.calls.includes(`prepare_account_deletion:${A}`) && !r.calls.includes(`delete:${A}`), r.calls.join(" "));
  assert(r.calls.indexOf(`audit:${B}`) < r.calls.indexOf(`prepare_account_deletion:${B}`), r.calls.join(" "));
  // Fix round 1 M-1: an insert that sends no row back is no evidence either.
  const empty = rig([A, B], { auditEmpty: [A] });
  const emptyResult = await purgeRecoveryHolds(empty.client);
  assert(emptyResult.deleted === 1 && emptyResult.failed === 1, JSON.stringify(emptyResult));
  assert(
    !empty.calls.includes(`prepare_account_deletion:${A}`) && !empty.calls.includes(`delete:${A}`),
    `deleted with no audit row back: ${empty.calls.join(" ")}`,
  );
  // The outcome update is best effort: a delete that happened is counted once.
  const thrown = await purgeRecoveryHolds(rig([A], { recordThrows: true }).client);
  assert(thrown.deleted === 1 && thrown.failed === 0, JSON.stringify(thrown));
});

Deno.test("a failed list read throws before anything is deleted; the budget leaves the rest", async () => {
  let message = "";
  try {
    await purgeRecoveryHolds(rig([A], { listFails: true }).client);
  } catch (error) {
    message = error instanceof Error ? error.message : String(error);
  }
  assert(message === "recovery_hold_candidates_failed", message);
  let t = 0;
  const r = rig([A, B, C]);
  const result = await purgeRecoveryHolds(r.client, { now: () => (t += 40), budgetMs: 60 });
  assert(result.deleted === 1 && result.remaining === 2, JSON.stringify(result));
  assert(candidateIds(null).length === 0 && candidateIds([42, "x"]).length === 0, "non-ids read as nothing");
});

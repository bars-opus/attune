// supabase/functions/build-data-exports/dating_part.ts
//
// Spec 2 W9 (§4.7, S-4, I-13): the export's own-data Dating part. One
// added step in the data phase: dating_export_for_job, with the job being
// built and nothing else (no user id: the database takes the person from
// the job, refuses a job that isn't building and allows three reads a
// job). Its answer is written as dating.json; no Dating data, no file.
// The existing parts are unchanged.

/** The one thing this needs of the part's zip. */
export type DatingZip = { add(name: string, bytes: Uint8Array): void };

/** Adds dating.json for [jobId]; false when the person has no Dating data. */
// deno-lint-ignore no-explicit-any
export async function addDatingPart(supabase: any, jobId: string, zip: DatingZip): Promise<boolean> {
  const { data, error } = await supabase.rpc("dating_export_for_job", { p_job_id: jobId });
  if (error) throw error;
  if (data === null || data === undefined) return false;
  zip.add("dating.json", new TextEncoder().encode(JSON.stringify(data)));
  return true;
}

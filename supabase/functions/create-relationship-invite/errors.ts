// What create-relationship-invite answers for an error (W4 batch 2 fix
// round 1 ruling): an HttpError its own status and message; anything else
// a generic 500, logging only the error's code (errorCode), never the
// database's text, which can hold the failing row and its invite code.
import { HttpError, jsonResponse } from "../_shared/attune_auth.ts";
import { errorCode } from "../_shared/error_code.ts";

export function createErrorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }
  console.error(`create-relationship-invite failed: code=${errorCode(error)}`);
  return jsonResponse({ error: "Could not create relationship invite" }, 500);
}

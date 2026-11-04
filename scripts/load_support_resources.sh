#!/usr/bin/env bash
# scripts/load_support_resources.sh — Spec 1 W7a (spec §4.2): loads the
# support catalogue (assets/support_resources/catalogue.json, the file the
# app bundles for offline use) into public.support_resources through the
# service-role function load_support_resources, which takes the whole file
# or nothing.
#
#   Load (owner, per project; the two values are exported by the caller,
#   this script never reads .env or any credential file):
#     SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<key> \
#       scripts/load_support_resources.sh [catalogue.json]
#   Check against a local database, rolled back (writes nothing):
#     scripts/load_support_resources.sh --check <database> [catalogue.json]
set -euo pipefail

mode=load
if [[ "${1:-}" == "--check" ]]; then
  mode=check
  db="${2:?--check needs a database name}"
  shift 2
fi
file="${1:-assets/support_resources/catalogue.json}"
if [[ ! -f "$file" ]]; then
  echo "load_support_resources: no catalogue at $file" >&2
  exit 2
fi
# Valid JSON, compacted (a broken file stops here, before any request).
catalogue=$(python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")), ensure_ascii=False, separators=(",", ":")))' "$file")

if [[ $mode == check ]]; then
  printf '%s\n' 'BEGIN;' 'SET LOCAL ROLE service_role;' \
    "SELECT public.load_support_resources(:'catalogue'::jsonb);" 'ROLLBACK;' |
    psql -X -q -v ON_ERROR_STOP=1 -At -d "$db" -v catalogue="$catalogue"
  exit 0
fi

: "${SUPABASE_URL:?export SUPABASE_URL (https://<ref>.supabase.co)}"
: "${SUPABASE_SERVICE_ROLE_KEY:?export SUPABASE_SERVICE_ROLE_KEY}"
# The service-role key never travels in clear text (batch-1 review M6).
if [[ "$SUPABASE_URL" != https://* ]]; then
  echo "load_support_resources: SUPABASE_URL must be https" >&2
  exit 2
fi
# The key goes in a header file (mode 600), never on curl's command line.
headers=$(mktemp)
trap 'rm -f "$headers"' EXIT
chmod 600 "$headers"
printf 'apikey: %s\nAuthorization: Bearer %s\nContent-Type: application/json\n' \
  "$SUPABASE_SERVICE_ROLE_KEY" "$SUPABASE_SERVICE_ROLE_KEY" > "$headers"
printf '%s' "$catalogue" | python3 -I -c 'import json, sys; print(json.dumps({"p_catalogue": json.load(sys.stdin)}))' |
  curl -sS --fail-with-body -X POST "${SUPABASE_URL%/}/rest/v1/rpc/load_support_resources" \
    -H @"$headers" --data-binary @-
echo

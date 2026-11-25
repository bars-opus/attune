#!/usr/bin/env bash
# scripts/deploy/hosted_deploy.sh — the 2026-11-24 hosted deploy (Spec 1 W1–W10
# + Spec 2 W1–W10 + Spec 3 W2–W3, demo mode), in the order of
# docs/deploy/2026-11-24-hosted-deploy.md. The owner runs it; nothing here
# runs by itself.
#
#   export SUPABASE_PROJECT_REF=<project-ref>
#   scripts/deploy/hosted_deploy.sh --dry-run    # prints every step, calls no tool
#   scripts/deploy/hosted_deploy.sh              # asks before every step
#   scripts/deploy/hosted_deploy.sh --from 3     # resume at a step
#
# Secrets are never typed on a command line: the script asks for the
# Postgres connection string (ATTUNE_DB_URL), the publishable key
# (ATTUNE_ANON_KEY) and every secret value with a hidden prompt (read -s)
# when they aren't already in its environment, and sends Vault values to
# psql on stdin. Optional overrides: ATTUNE_DEPLOY_USE_API=1 (bundle
# functions with --use-api, no Docker), DBIP_MONTH=YYYY-MM (the DB-IP file's
# month), ATTUNE_DEPLOY_STATE (state folder, default
# ~/.attune-deploy-2026-11-24), ATTUNE_DEPLOY_WORK (download folder).
#
# What it runs: git (read-only checks), the supabase CLI (--project-ref for
# functions and secrets; --db-url "$ATTUNE_DB_URL" for every database
# command, so psql and the push reach the same database), psql, and in steps
# 5-6 the IP-table build (curl, gunzip, deno) and the console's flutter
# build. It never sets attune_environment, never deploys every function at
# once, and refuses a working tree with changes. It stops at the first error.
set -Eeuo pipefail

DRY_RUN=0
FROM_STEP=0
CURRENT_STEP=0

usage() {
  sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --from)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      FROM_STEP="$2"
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
  shift
done
if ! [[ "$FROM_STEP" =~ ^[0-9]$ ]]; then
  printf -- '--from takes a step number 0-9\n' >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1
STATE_DIR="${ATTUNE_DEPLOY_STATE:-$HOME/.attune-deploy-2026-11-24}"
WORK_DIR="${ATTUNE_DEPLOY_WORK:-$HOME/attune-deploy-tmp}"
MIGRATIONS_DIR="supabase/migrations"
BASE_COMMIT="9bac1bdb"
FIRST_PENDING="20261025090000"
LAST_PENDING="20261125100050"
EXPECTED_PENDING=127
DEMO_FLAG_COUNT=27
IP_BIN="supabase/functions/dating-device-check/ip_country.bin"
IP_BUNDLE_LIMIT=$((20 * 1024 * 1024))
DBIP_MONTH="${DBIP_MONTH:-$(date -u +%Y-%m)}"
DEPLOY_EXTRA=()
if [[ "${ATTUNE_DEPLOY_USE_API:-0}" == "1" ]]; then DEPLOY_EXTRA=(--use-api); fi
DEMO_FLAGS="'flow_signin_v2','flow_paths_v2','flow_couples_v2','couple_profile','dormancy_rule','platform_age_signals','support_resources_v2','csam_hash_matching','opinions_safety_v1','journal_ai_insights','healing_ai_insights','text_scale_v2','dating_mode_enabled','dating_candidate_generation','dating_match_messaging','dating_profile_photos','dating_same_gender_matching','dating_age_assurance','dating_traveller_detection','dating_couple_link','quiz_clinical_signoff','couple_map_enabled','appreciation_notes','share_a_win','quiet_states','private_safety_check','conflict_toolkit'"
TMP_FILES=()

if [[ $DRY_RUN -eq 1 ]]; then
  REF="${SUPABASE_PROJECT_REF:-<project-ref>}"
else
  REF="${SUPABASE_PROJECT_REF:-}"
fi

cleanup() {
  local f
  for f in "${TMP_FILES[@]+"${TMP_FILES[@]}"}"; do rm -f "$f"; done
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Output and confirmation helpers. Commands are printed before they run;
# the connection string, the anon key and every secret are printed as
# variable names or not at all.
# ---------------------------------------------------------------------------
say() { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
show() { printf '   $ %s\n' "$*"; }

on_err() {
  local line="$1"
  # Only the top-level shell reports (a failing $(…) would otherwise print twice).
  if [[ "${BASH_SUBSHELL:-0}" -ne 0 ]]; then return 0; fi
  trap - ERR
  printf '\n!! Failed in step %s (line %s). Nothing after it ran.\n' "$CURRENT_STEP" "$line" >&2
  printf '!! Fix the cause (checklist step %s, "If it fails"), then: %s --from %s\n' \
    "$CURRENT_STEP" "$0" "$CURRENT_STEP" >&2
}
trap 'on_err $LINENO' ERR

die() {
  printf '\n!! %s\n' "$*" >&2
  printf '!! Stopped in step %s. Resume with: %s --from %s\n' "$CURRENT_STEP" "$0" "$CURRENT_STEP" >&2
  exit 1
}

confirm() {
  local answer
  if [[ $DRY_RUN -eq 1 ]]; then
    note "(dry run; would ask) $1 [y/N]"
    return 0
  fi
  read -r -p "   $1 [y/N] " answer || answer=""
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" ]]
}

# Default yes: only an explicit no answers no.
confirm_default_yes() {
  local answer
  if [[ $DRY_RUN -eq 1 ]]; then
    note "(dry run; would ask) $1 [Y/n]"
    return 0
  fi
  read -r -p "   $1 [Y/n] " answer || answer="n"
  [[ "$answer" != "n" && "$answer" != "N" && "$answer" != "no" ]]
}

# Asks; "no" stops the whole run cleanly with the resume line.
gate() {
  if ! confirm "$1"; then
    printf '\nStopped at your answer in step %s. Resume with: %s --from %s\n' "$CURRENT_STEP" "$0" "$CURRENT_STEP"
    exit 0
  fi
}

# A hidden prompt into the named variable (never echoed, never on a
# command line). Empty in a dry run.
read_secret() {
  local __name="$1" __prompt="$2" __value=""
  if [[ $DRY_RUN -eq 1 ]]; then
    note "(dry run; would ask, hidden) $__prompt"
    printf -v "$__name" '%s' ""
    return 0
  fi
  read -rs -p "   $__prompt (hidden; empty = skip): " __value || __value=""
  printf '\n'
  printf -v "$__name" '%s' "$__value"
}

run() {
  show "$*"
  if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
  "$@"
}

# psql helpers. $ATTUNE_DB_URL is never printed.
sql() {
  show "psql \"\$ATTUNE_DB_URL\" -X -v ON_ERROR_STOP=1 -c \"$1\""
  if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
  psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -c "$1"
}

# One value (-At), for $(...): the printed command goes to stderr so only
# the value is captured. Prints no value in a dry run.
sql_value() {
  show "psql \"\$ATTUNE_DB_URL\" -X -At -c \"$1\"" >&2
  if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
  psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -At -c "$1"
}

# A block of SQL from stdin, echoed query by query (-e).
sql_block() {
  local q
  q="$(cat)"
  show "psql \"\$ATTUNE_DB_URL\" -X -e -v ON_ERROR_STOP=1 <<'SQL'"
  printf '%s\n' "$q" | sed 's/^/     /'
  show "SQL"
  if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
  printf '%s\n' "$q" | psql "$ATTUNE_DB_URL" -X -e -v ON_ERROR_STOP=1 -P pager=off
}

sql_file() {
  show "psql \"\$ATTUNE_DB_URL\" -X -v ON_ERROR_STOP=1 -f $1"
  if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
  psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -f "$1"
}

state_write() {
  if [[ $DRY_RUN -eq 1 ]]; then
    note "(dry run; would record $1=$2 in $STATE_DIR)"
    return 0
  fi
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  printf '%s\n' "$2" > "$STATE_DIR/$1"
}

state_read() {
  if [[ -f "$STATE_DIR/$1" ]]; then cat "$STATE_DIR/$1"; fi
}

# The edge secret list (names and digests only; values never leave Supabase).
SECRET_NAMES=""
load_secret_names() {
  show "supabase secrets list --project-ref $REF   (names only are used)"
  if [[ $DRY_RUN -eq 1 ]]; then SECRET_NAMES=""; return 0; fi
  SECRET_NAMES="$(supabase secrets list --project-ref "$REF" 2>/dev/null)"
}

has_secret() {
  printf '%s\n' "$SECRET_NAMES" | grep -Eq "(^|[^A-Z0-9_])$1([^A-Z0-9_]|\$)"
}

# Sets edge secrets from NAME=value lines through a 600 file (never argv).
set_edge_secrets() {
  local lines="$1" f
  if [[ $DRY_RUN -eq 1 ]]; then
    show "supabase secrets set --env-file <600 temp file> --project-ref $REF"
    return 0
  fi
  [[ -n "$lines" ]] || return 0
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  f="$(umask 077; mktemp "$STATE_DIR/secrets.XXXXXX")"
  TMP_FILES+=("$f")
  printf '%s\n' "$lines" > "$f"
  show "supabase secrets set --env-file <600 temp file> --project-ref $REF"
  supabase secrets set --env-file "$f" --project-ref "$REF"
  rm -f "$f"
}

FUNCTION_LIST=""
load_function_list() {
  show "supabase functions list --project-ref $REF"
  if [[ $DRY_RUN -eq 1 ]]; then FUNCTION_LIST=""; return 0; fi
  FUNCTION_LIST="$(supabase functions list --project-ref "$REF")"
  printf '%s\n' "$FUNCTION_LIST"
}

function_present() {
  printf '%s\n' "$FUNCTION_LIST" | grep -Eq "(^|[[:space:]|])$1([[:space:]|]|$)"
}

deploy_fn() {
  run supabase functions deploy "$1" --project-ref "$REF" "${DEPLOY_EXTRA[@]+"${DEPLOY_EXTRA[@]}"}"
}

deploy_fn_no_jwt() {
  run supabase functions deploy "$1" --no-verify-jwt --project-ref "$REF" "${DEPLOY_EXTRA[@]+"${DEPLOY_EXTRA[@]}"}"
}

# The working tree must hold only the owner's two known local files, so
# nothing unreviewed is pushed or deployed (review I-6). Re-run before every
# push and deploy batch.
git_clean_check() {
  show "git status --porcelain   (allowed: backup-before-planning-p2.sql, supabase/.temp/)"
  if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
  local dirty
  dirty="$(git status --porcelain --untracked-files=all | grep -v -E '^.. (backup-before-planning-p2\.sql|supabase/\.temp/)' || true)"
  if [[ -n "$dirty" ]]; then
    printf '%s\n' "$dirty" | sed 's/^/     /'
    die "The working tree has changes (above). Commit (and push) or stash them first; functions and migrations deploy from the files on disk."
  fi
}

# The DB target is the ref's own database: the Vault project URL names the
# ref (a count, never the value).
db_target_check() {
  local n
  n="$(sql_value "select count(*) from vault.decrypted_secrets where name = 'supabase_url' and position('$REF' in decrypted_secret) > 0;")"
  if [[ $DRY_RUN -eq 0 && "$n" != "1" ]]; then
    die "The database behind ATTUNE_DB_URL does not hold this ref's supabase_url in Vault: wrong database, or supabase_url missing."
  fi
}

# dating-moderation goes out only once DATING_CONSOLE_ORIGIN and TOTP MFA
# are in place; steps 3 and 6 both offer it.
deploy_dating_moderation() {
  if [[ "$(state_read dating_moderation_deployed)" == "yes" ]]; then
    note "dating-moderation was already deployed by this script."
    return 0
  fi
  load_secret_names
  if [[ $DRY_RUN -eq 0 ]] && ! has_secret DATING_CONSOLE_ORIGIN; then
    note "DATING_CONSOLE_ORIGIN is not set yet: dating-moderation waits for step 6."
    return 0
  fi
  if confirm "Is TOTP MFA enabled (Dashboard -> Authentication -> Multi-Factor) and DATING_CONSOLE_ORIGIN the console's exact origin? Deploy dating-moderation now?"; then
    git_clean_check
    deploy_fn_no_jwt dating-moderation
    state_write dating_moderation_deployed yes
  else
    note "Skipped. Step 6 offers it again."
  fi
}

should_run() { [[ "$1" -ge "$FROM_STEP" ]]; }

# Spec 3 W3 pre-push probe (read-only; W3 final review I-1). W3's migration 1
# refuses the push when one of these four live bodies differs from the one W3
# was built on, or production has a forum function W3 doesn't know, but only
# after the 121 earlier files are applied. These four are live now and the
# pending set never re-creates them; the other two bodies W3 checks
# (admin_confirm_content_removal, opinion_stamp_backfill) are re-created by
# 20261107100000 in the same push. The inventory is migration 1's (a).
W3_EXPECTED_MD5S="920660396b7d4e331db2948838f98333 6154f307c3afdb76c0249c2db2ec44f6 dd3f4fc152767cd7b054c8324a46020e 3d57c8b5ca75d1edbe87192d5af837e1"
w3_probe() {
  local md5_sql inventory_sql w3_md5s w3_unknown
  md5_sql="$(cat <<'SQL'
select string_agg(coalesce(md5(p.prosrc), 'missing'), ' ' order by s.n)
  from (values (1, 'private.assert_can_post(uuid,text)'),
               (2, 'private.create_poll_for_post(uuid,uuid,uuid,text[])'),
               (3, 'public.get_post_poll(uuid,uuid)'),
               (4, 'private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)')) as s(n, sig)
  left join pg_catalog.pg_proc p on p.oid = to_regprocedure(s.sig);
SQL
)"
  inventory_sql="$(cat <<'SQL'
with known as (
  select to_regprocedure(k) as o from unnest(array[
    'public.activate_pending_topics()', 'public.expire_old_topics()', 'public.mark_quiet_topics()',
    'public.notify_quiet_topic(uuid)', 'private.queue_forum_activity_notifications(uuid,uuid)',
    'public.record_forum_topic_visit(uuid)', 'public.create_forum_post(uuid,text,text,uuid,text)',
    'public.create_forum_topic(text)', 'public.create_forum_topic_with_poll(text,text[])',
    'public.edit_forum_post(uuid,text)', 'public.attach_forum_topic_tags(uuid,text[])',
    'public.get_forum_topic_tags(uuid)', 'public.get_forum_topics_by_tag(text,integer,integer)',
    'public.get_tags_for_forum_topics(uuid[])', 'public.get_polls_for_topics(uuid[])',
    'public.get_active_forums_filtered(text[])', 'public.get_quiet_forums_filtered(text[])',
    'public.get_voting_topics_filtered(text[])', 'public.increment_topic_upvote_count(uuid)',
    'public.decrement_topic_upvote_count(uuid)', 'public.increment_topic_downvote_count(uuid)',
    'public.decrement_topic_downvote_count(uuid)', 'public.increment_topic_post_count(uuid,text)',
    'public.decrement_topic_post_count(uuid,text)', 'public.increment_topic_seen_count(uuid)',
    'public.increment_forum_post_like_count(uuid)', 'public.decrement_forum_post_like_count(uuid)',
    'public.report_forum_post(uuid,text)', 'public.report_forum_topic(uuid,text)',
    'private.assert_can_post(uuid,text)', 'public.admin_confirm_content_removal(text,uuid)',
    'private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)',
    'private.opinion_stamp_backfill()', 'private.create_poll_for_post(uuid,uuid,uuid,text[])',
    'public.get_post_poll(uuid,uuid)', 'public.forum_retirement_health()']) as k
   where to_regprocedure(k) is not null)
select coalesce(string_agg(x.sig, ', ' order by x.sig), '') from (
  select p.oid::regprocedure::text as sig
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private') and p.prokind in ('f', 'p')
     and (p.proname ~* 'forum|topic'
          or p.prosrc ~* '(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum|\mtopic_id\M|\mforum_post_id\M)')
     and p.oid not in (select o from known)
  union
  select p.oid::regprocedure::text
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('public', 'private', 'pg_catalog', 'information_schema')
     and n.nspname !~ '^pg_(temp|toast)'
     and p.prosrc ~* '(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum)'
     and not exists (select 1 from pg_catalog.pg_depend e
                      where e.classid = 'pg_catalog.pg_proc'::regclass and e.objid = p.oid and e.deptype = 'e')) as x;
SQL
)"
  # Once W3 is applied (a --from 2 re-run after the push), the bodies are W3's own: nothing to probe.
  if [[ "$(sql_value "select (to_regclass('public.forum_topics') is null)::text;")" == "true" ]]; then
    note "W3 probe: the forum tables are already dropped (W3 applied); skipped."
    return 0
  fi
  w3_md5s="$(sql_value "$md5_sql")"
  w3_unknown="$(sql_value "$inventory_sql")"
  if [[ $DRY_RUN -eq 1 ]]; then
    note "(dry run) A real run stops unless the md5s read: $W3_EXPECTED_MD5S"
    note "(dry run) and the inventory reads empty."
    return 0
  fi
  if [[ "$w3_md5s" != "$W3_EXPECTED_MD5S" ]]; then
    note "Live md5s:     $w3_md5s"
    note "Expected md5s: $W3_EXPECTED_MD5S"
    note "(order: assert_can_post, create_poll_for_post, get_post_poll, enqueue_forum_notification)"
    die "A function W3 checks is not the body W3 was built on (a hand edit in production?). W3's migration 1 would refuse the push after the 121 earlier files. Either deploy from a commit without the W3 merge (EXPECTED_PENDING 121), or re-plan W3's migrations 4-5 and migration 1's md5s from: select pg_get_functiondef('<sig>'::regprocedure);"
  fi
  if [[ -n "$w3_unknown" ]]; then
    note "Forum function(s) W3 does not know: $w3_unknown"
    die "W3's migration 1 would refuse the push (unexpected forum function) after the 121 earlier files. Either deploy from a commit without the W3 merge (EXPECTED_PENDING 121), or add them to W3's migration 2 (forum-only) or 5 (shared) first."
  fi
  note "W3 probe: the four bodies match and production has no forum function W3 does not know."
}

# ---------------------------------------------------------------------------
# Checks on every run (also on --from): tools, variables, the development
# ref, the tree, the commit, and that psql reaches the ref's database.
# ---------------------------------------------------------------------------
basic_checks() {
  say "Checks before any step (every run)"
  local tool missing=0
  for tool in git supabase psql python3 awk sed grep; do
    if ! command -v "$tool" > /dev/null 2>&1; then
      note "missing tool: $tool"
      missing=1
    fi
  done
  for tool in deno curl gunzip flutter; do
    if ! command -v "$tool" > /dev/null 2>&1; then
      note "note: $tool not found (needed for steps 5-6 only)"
    fi
  done
  if [[ $missing -eq 1 && $DRY_RUN -eq 0 ]]; then die "Install the missing tools first."; fi

  # The development guard's ref, read from the migration that defines it,
  # so this script never hard-codes a project.
  local dev_ref
  dev_ref="$(grep -oE "position\('[a-z0-9]{20}' IN v_vault_url\)" \
    "$MIGRATIONS_DIR/20261025100400_spec1_flags_and_public_config.sql" | head -1 | grep -oE "[a-z0-9]{20}" || true)"
  [[ -n "$dev_ref" ]] || die "Could not read the development ref from 20261025100400; check the repo is at $BASE_COMMIT or later."
  if [[ $DRY_RUN -eq 1 && -z "${SUPABASE_PROJECT_REF:-}" ]]; then
    note "(dry run) A real run stops unless SUPABASE_PROJECT_REF is the development guard's ref."
  elif [[ -z "$REF" ]]; then
    die "export SUPABASE_PROJECT_REF first."
  elif [[ "$REF" != "$dev_ref" ]]; then
    die "SUPABASE_PROJECT_REF is not the development ref the dev guards expect. This deploy is for the development (demo) project only: every dev flag script would refuse there."
  else
    note "Project ref matches the development guard's ref."
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    show "git rev-parse --short HEAD; git merge-base --is-ancestor $BASE_COMMIT HEAD; git branch -r --contains HEAD"
    git_clean_check
    note "(dry run) A real run asks for ATTUNE_DB_URL (hidden) if unset and checks it reaches the ref's database."
    return 0
  fi

  local head
  head="$(git rev-parse --short HEAD)"
  note "HEAD: $head (expected $BASE_COMMIT or later, on origin/main; run git fetch first)."
  git merge-base --is-ancestor "$BASE_COMMIT" HEAD || die "HEAD is not $BASE_COMMIT or a descendant of it."
  git_clean_check
  if ! git branch -r --contains HEAD 2> /dev/null | grep -q 'origin/main'; then
    note "HEAD is not on origin/main (as of your last git fetch)."
    gate "Deploy from a commit that is not on origin/main?"
  fi

  if [[ -z "${ATTUNE_DB_URL:-}" ]]; then
    read_secret ATTUNE_DB_URL "Postgres connection string for the postgres role (Dashboard -> Connect)"
    [[ -n "$ATTUNE_DB_URL" ]] || die "No connection string given."
    export ATTUNE_DB_URL
  fi
  [[ "$ATTUNE_DB_URL" == *"$REF"* ]] || die "ATTUNE_DB_URL does not name SUPABASE_PROJECT_REF: the CLI and psql would reach different projects."
  db_target_check
  note "psql reaches the database whose Vault supabase_url names $REF."
}

# ---------------------------------------------------------------------------
# Step 0: pre-flight
# ---------------------------------------------------------------------------
step0() {
  CURRENT_STEP=0
  say "Step 0: pre-flight (checklist section 0)"

  note "0.0 Testers, read first (checklist 'Testers, read first')."
  note "After the push the CURRENT STORE BUILD breaks for whoever uses it: new accounts save no name;"
  note "once flow_signin_v2 is on, invites need a birth date (pending invites too); Forums show errors;"
  note "Dating v1 is gone; Journal Patterns is blank while journal AI is paused; Opinions posts are filtered"
  note "by the [DRAFT] terms and removals count toward 7-day bans. Every tester installs the new build."
  if [[ $DRY_RUN -eq 1 ]]; then
    note "(dry run; would ask) Only the owner and testers use the store build on this project - type yes"
  else
    local answer
    read -r -p "   Only the owner and testers use the store build on this project - type yes: " answer || answer=""
    [[ "$answer" == "yes" ]] || die "Not confirmed. If anyone else uses the store build, stop: the deploy breaks it for them (checklist 'Testers, read first')."
  fi
  gate "Start the pre-flight?"

  note "0.1 Confirm the target."
  run supabase projects list
  sql "select current_database(), current_user;"

  note "0.2 Postgres 17 (20261104100000 needs pg_c_utf8)."
  local pg17
  pg17="$(sql_value "select current_setting('server_version_num')::int >= 170000;")"
  if [[ $DRY_RUN -eq 0 && "$pg17" != "t" ]]; then die "The project is not on Postgres 17: upgrade it before any push."; fi

  note "0.3 Log settings must keep no statement values, before any key is created."
  local logs_safe
  sql "select name, setting from pg_settings where name in ('log_statement','log_min_duration_statement','log_parameter_max_length','log_parameter_max_length_on_error') order by 1;"
  logs_safe="$(sql_value "select coalesce(current_setting('log_statement', true) in ('none','ddl') and (current_setting('log_min_duration_statement', true) = '-1' or current_setting('log_parameter_max_length', true) = '0') and current_setting('log_parameter_max_length_on_error', true) = '0', false);")"
  if [[ $DRY_RUN -eq 0 && "$logs_safe" != "t" ]]; then
    die "The database logs could keep statement values (a Vault key would land in them). Fix Dashboard -> Database -> Settings (checklist 0.3) and re-run."
  fi

  note "0.4 Backup / PITR: note the latest backup time (Dashboard -> Database -> Backups) or the PITR point now."
  gate "Have you noted the backup time or PITR restore point?"
  if confirm "Also take local schema and data dumps into \$HOME/attune-backups (outside the repo; they hold personal data)?"; then
    run mkdir -p "$HOME/attune-backups"
    run chmod 700 "$HOME/attune-backups"
    show "supabase db dump --db-url \"\$ATTUNE_DB_URL\" -f $HOME/attune-backups/2026-11-24-schema.sql"
    show "supabase db dump --db-url \"\$ATTUNE_DB_URL\" --data-only -f $HOME/attune-backups/2026-11-24-data.sql"
    if [[ $DRY_RUN -eq 0 ]]; then
      supabase db dump --db-url "$ATTUNE_DB_URL" -f "$HOME/attune-backups/2026-11-24-schema.sql"
      supabase db dump --db-url "$ATTUNE_DB_URL" --data-only -f "$HOME/attune-backups/2026-11-24-data.sql"
    fi
  fi

  note "0.5 What is already applied."
  show "supabase migration list --db-url \"\$ATTUNE_DB_URL\""
  if [[ $DRY_RUN -eq 0 ]]; then supabase migration list --db-url "$ATTUNE_DB_URL"; fi
  local remote local_pending pending_count first last
  remote="$(sql_value "select version from supabase_migrations.schema_migrations order by version;")"
  if [[ $DRY_RUN -eq 0 ]]; then
    local_pending="$(find "$MIGRATIONS_DIR" -maxdepth 1 -name '*.sql' -exec basename {} \; | cut -c1-14 | sort \
      | comm -23 - <(printf '%s\n' "$remote" | sort))"
    pending_count="$(printf '%s\n' "$local_pending" | grep -c . || true)"
    first="$(printf '%s\n' "$local_pending" | head -1)"
    last="$(printf '%s\n' "$local_pending" | tail -1)"
    note "Pending: $pending_count files, first $first, last $last (checklist: $EXPECTED_PENDING, $FIRST_PENDING, $LAST_PENDING)."
    state_write pending_count "$pending_count"
    if [[ "$pending_count" != "$EXPECTED_PENDING" || "$first" != "$FIRST_PENDING" || "$last" != "$LAST_PENDING" ]]; then
      note "The pending set differs from Appendix A. Read checklist 0.5 before going on."
      gate "Continue anyway (only if you know why it differs)?"
    fi
  fi

  note "0.6 Production mode must not be set."
  local env_count
  env_count="$(sql_value "select count(*) from vault.secrets where name = 'attune_environment';")"
  if [[ $DRY_RUN -eq 0 && "$env_count" != "0" ]]; then die "A Vault secret attune_environment exists: this deploy assumes development mode. Stop and decide."; fi

  note "0.7 Baselines (keep the output)."
  local n_other
  n_other="$(sql_value "select count(*) filter (where enabled) from public.feature_flags where key <> all (array[$DEMO_FLAGS]) and key <> 'dating_alignment_algorithm_v1';")"
  if [[ $DRY_RUN -eq 0 ]]; then
    note "N (other flags already on, not counting dating_alignment_algorithm_v1, which the push deletes) = $n_other"
    state_write n_other_on "$n_other"
  fi
  sql_block <<'SQL'
select key, enabled from public.feature_flags order by key;
select count(*) as names_over_40 from public.users where char_length(display_name) > 40;
select count(*) as next_removal_bans from public.profiles where confirmed_violation_count >= 2;
select (select count(*) from public.dating_introductions) as intros, (select count(*) from public.dating_matches) as matches;
-- what the push discards (v1 data that never ran in production)
select (select count(*) from public.dating_age_verifications) as v1_age_verifications_deleted,
       (select count(*) from public.dating_consent_events where purpose in ('historical_data', 'age_gate')) as consent_events_deleted,
       (select count(*) from public.dating_feature_snapshots) as feature_snapshots_dropped,
       (select count(*) from public.onboarding_profiles where mode is not null) as onboarding_mode_values_dropped;
select jobid, jobname, username, schedule, active, left(command, 120) as command from cron.job order by jobname;
SQL

  note "0.8 Spec 1 W1 phone drift baseline. STOP and look if will_be_nulled > 0 or format_drift > 0."
  sql_block <<'SQL'
select count(*) filter (where u.phone is distinct from a.phone) as drift_rows,
       count(*) filter (where u.phone is distinct from a.phone and a.phone_confirmed_at is not null
                          and nullif(btrim(a.phone), '') is not null) as will_be_restored,
       count(*) filter (where u.phone is not null and (a.id is null or a.phone_confirmed_at is null
                          or nullif(btrim(a.phone), '') is null)) as will_be_nulled,
       count(*) filter (where u.phone = '+' || a.phone) as format_drift
  from public.users u left join auth.users a on a.id = u.id;
select u.id, u.phone is not null as has_phone, a.phone_confirmed_at is not null as auth_confirmed,
       u.phone = '+' || a.phone as format_drift
  from public.users u left join auth.users a on a.id = u.id
 where u.phone is distinct from a.phone
 order by 4 desc, 3, 1;
SQL
  gate "Is every row with will_be_nulled or format_drift understood (a test account, or accepted)?"

  note "0.9 Forum retirement pre-checks."
  sql_block <<'SQL'
select current_user, (select rolbypassrls from pg_roles where rolname = current_user) as sees_all_jobs,
       has_table_privilege('cron.job', 'DELETE') as can_unschedule_others;
select jobid, jobname, username, username = current_user as owned_by_me, active, schedule
  from cron.job
 where jobname in ('activate-topics-sweep', 'forum-quiet-check', 'mark-quiet-forums')
    or command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)';
SQL
  gate "Does every forum job above show owned_by_me = t (or have you unscheduled the others in the dashboard)?"

  note "0.9b STOP: Spec 3 W3 (the forum table drop) pre-push probe, read-only (checklist 0.9b)."
  w3_probe

  note "0.10 No Database Webhooks on relationships, users, the couple tables or any dating_* table."
  sql "select event_object_schema, event_object_table, trigger_name from information_schema.triggers where action_statement ilike '%supabase_functions.http_request%' order by 2;"
  gate "No webhook on those tables (and none in Dashboard -> Database -> Webhooks)?"

  note "0.11 STOP: the purge-unfinished-signups go/no-go. GO only when the probe below reads 0."
  note "It counts rows, in every table with a foreign key to auth.users, owned by an account that has no users row"
  note "(every such account becomes a purge candidate once idle for 24 hours, and the purge runs hourly)."
  local probe_sql="select coalesce(sum((xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s t where t.%I in (select a.id from auth.users a where not exists (select 1 from public.users u where u.id = a.id))', fk.tbl, fk.col), false, true, '')))[1]::text::bigint), 0) from (select c.conrelid::regclass as tbl, a.attname as col from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1] where c.contype = 'f' and c.confrelid = 'auth.users'::regclass and c.connamespace not in ('auth'::regnamespace, 'storage'::regnamespace)) fk;"
  local probe_total
  sql "select count(*) as accounts_without_users_row, count(*) filter (where greatest(created_at, last_sign_in_at, updated_at) < now() - interval '24 hours') as idle_24h from auth.users a where not exists (select 1 from public.users u where u.id = a.id);"
  probe_total="$(sql_value "$probe_sql")"
  if [[ $DRY_RUN -eq 1 ]]; then
    note "(dry run) GO when the probe reads 0: purge-unfinished-signups is deployed in step 3. Otherwise NO-GO: step 2 unschedules its cron."
  elif [[ "$probe_total" == "0" ]]; then
    note "Probe: 0 rows tied to accounts without a users row."
    if confirm "GO for purge-unfinished-signups (deploy it in step 3)?"; then
      state_write purge_decision go
    else
      state_write purge_decision nogo
    fi
  else
    note "Probe: $probe_total rows tied to accounts without a users row: NO-GO (checklist 0.11 lists them by table)."
    state_write purge_decision nogo
  fi

  note "0.12 The purge must not already be live (it would run at the first :41 after the push)."
  load_function_list
  local purge_cron
  purge_cron="$(sql_value "select count(*) from cron.job where jobname = 'purge-unfinished-signups';")"
  if [[ $DRY_RUN -eq 0 ]] && function_present purge-unfinished-signups && [[ "$(state_read purge_decision)" != "go" ]]; then
    note "purge-unfinished-signups is already deployed, and the decision is NO-GO."
    gate "Delete the deployed purge-unfinished-signups now (before the push arms its cron)?"
    run supabase functions delete purge-unfinished-signups --project-ref "$REF"
  fi
  if [[ $DRY_RUN -eq 0 && "$purge_cron" != "0" && "$(state_read purge_decision)" != "go" ]]; then
    sql "select cron.unschedule(jobid) from cron.job where jobname = 'purge-unfinished-signups';"
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    note "(dry run) On NO-GO: a deployed purge-unfinished-signups is deleted and an armed cron unscheduled here."
  fi

  note "0.13 Acknowledgements (checklist 0.13)."
  gate "Do you accept: the W9c/W9e support card copy ships unsigned; Opinions third-strike bans are real?"
}

# ---------------------------------------------------------------------------
# Step 1: secrets and Vault keys
# ---------------------------------------------------------------------------

# Creates one Vault key from a hidden prompt, through psql's stdin (\set),
# never on a command line and never in the SQL editor's history. An existing
# key is never replaced. $3 = shape check (exclusion | field | push | fresh |
# url); $4 = required (1) or optional (0).
vault_key() {
  local name="$1" shape="$2" required="$3" have value ok=1
  have="$(sql_value "select count(*) from vault.secrets where name = '$name';")"
  if [[ "$have" == "1" ]]; then
    note "Vault $name: already set (kept; never replaced)."
    return 0
  fi
  read_secret value "Vault $name (paste from your password manager)"
  if [[ $DRY_RUN -eq 1 ]]; then
    show "psql \"\$ATTUNE_DB_URL\" -X -q <<< \"\\set v '<hidden>' select vault.create_secret(:'v', '$name');\""
    return 0
  fi
  if [[ -z "$value" ]]; then
    [[ "$required" == "0" ]] || die "Vault $name is required (checklist 1.1)."
    note "Vault $name skipped."
    return 0
  fi
  if [[ "$value" == *[[:space:]\'\\]* ]]; then ok=0; fi
  case "$shape" in
    exclusion | fresh) [[ ${#value} -ge 48 ]] || ok=0 ;;
    field) [[ ${#value} -eq 44 && "$value" =~ ^[A-Za-z0-9+/]{43}=$ ]] || ok=0 ;;
    push) [[ "$value" =~ ^[0-9a-f]{64}$ ]] || ok=0 ;;
    url) [[ "$value" == https://* ]] || ok=0 ;;
  esac
  if [[ $ok -eq 0 ]]; then
    value=""
    [[ "$required" == "0" ]] || die "Vault $name has the wrong shape (checklist 1.1); nothing was written."
    note "Vault $name has the wrong shape; skipped."
    return 0
  fi
  show "psql \"\$ATTUNE_DB_URL\" -X -q <<< \"\\set v '<hidden>' select vault.create_secret(:'v', '$name');\""
  printf "\\\\set v '%s'\nselect vault.create_secret(:'v', '%s');\n" "$value" "$name" \
    | psql "$ATTUNE_DB_URL" -X -q -v ON_ERROR_STOP=1 -At > /dev/null
  value=""
  note "Vault $name created."
}

step1() {
  CURRENT_STEP=1
  say "Step 1: secrets and Vault keys (checklist section 1)"
  gate "Start step 1?"

  note "1.1 Vault keys (hidden prompts; keep an offline copy of dating_exclusion_key and dating_field_key)."
  vault_key dating_exclusion_key exclusion 1
  vault_key dating_field_key field 1
  vault_key dating_push_key push 1
  vault_key fresh_start_key fresh 1
  vault_key moderation_alert_webhook url 0

  local vault_required vault_env
  vault_required="$(sql_value "select count(*) from vault.secrets where name in ('dating_exclusion_key','dating_field_key','dating_push_key','fresh_start_key','supabase_url','service_role_key');")"
  vault_env="$(sql_value "select count(*) from vault.secrets where name = 'attune_environment';")"
  sql "select name from vault.secrets where name in ('dating_exclusion_key','dating_field_key','dating_push_key','fresh_start_key','moderation_alert_webhook','age_assurance_mode','supabase_url','service_role_key','attune_environment') order by name;"
  if [[ $DRY_RUN -eq 0 ]]; then
    [[ "$vault_env" == "0" ]] || die "attune_environment is set in Vault; this deploy never sets it."
    [[ "$vault_required" == "6" ]] || die "Vault holds $vault_required of the 6 required names (4 new keys + supabase_url + service_role_key)."
  fi

  note "1.2 Edge secrets (hidden prompts, sent through a 600 file)."
  load_secret_names
  local lines="" v=""
  if [[ $DRY_RUN -eq 1 ]] || ! has_secret CSAM_MATCHER; then
    if confirm "Set CSAM_MATCHER=stub (development only; required before the push)?"; then lines+="CSAM_MATCHER=stub"$'\n'; fi
  fi
  if [[ $DRY_RUN -eq 1 ]] || ! has_secret OTP_HMAC_KEY; then
    read_secret v "OTP_HMAC_KEY (32+ random bytes, base64)"
    if [[ -n "$v" ]]; then lines+="OTP_HMAC_KEY=$v"$'\n'; fi
  fi
  if [[ $DRY_RUN -eq 1 ]] || ! has_secret SAFETY_ALERT_WEBHOOK; then
    read_secret v "SAFETY_ALERT_WEBHOOK (recommended; https URL)"
    if [[ "$v" == https://* ]]; then lines+="SAFETY_ALERT_WEBHOOK=$v"$'\n'; elif [[ -n "$v" ]]; then note "Not an https URL; skipped."; fi
  fi
  if [[ $DRY_RUN -eq 1 ]] || { ! has_secret GOOGLE_VISION_API_KEY && ! has_secret DATING_PHOTO_VISION; }; then
    note "No GOOGLE_VISION_API_KEY: the development stand-in approves every Dating photo that passes the CSAM scan (dev project only; refused in production)."
    if confirm "Set DATING_PHOTO_VISION=stub until the Google key exists?"; then lines+="DATING_PHOTO_VISION=stub"$'\n'; fi
  fi
  v=""
  set_edge_secrets "$lines"
  lines=""

  load_secret_names
  if [[ $DRY_RUN -eq 0 ]]; then
    local name
    for name in CSAM_MATCHER OTP_HMAC_KEY; do
      has_secret "$name" || die "Edge secret $name is not set (checklist 1.2)."
    done
    if ! has_secret GOOGLE_VISION_API_KEY; then
      has_secret DATING_PHOTO_VISION || die "Edge secret GOOGLE_VISION_API_KEY is not set, nor DATING_PHOTO_VISION=stub (checklist 1.2)."
      note "note: photos use the development stand-in until GOOGLE_VISION_API_KEY is set; DATING_PHOTO_VISION must be exactly stub (lowercase), or photos stay pending."
    fi
    has_secret SAFETY_ALERT_WEBHOOK || note "note: SAFETY_ALERT_WEBHOOK is not set (recommended)."
    has_secret DATING_CONSOLE_ORIGIN || note "note: DATING_CONSOLE_ORIGIN is set in step 6 (needed before dating-moderation)."
    note "Required edge secret names are present."
  fi
}

# ---------------------------------------------------------------------------
# Step 2: migrations
# ---------------------------------------------------------------------------
step2() {
  CURRENT_STEP=2
  say "Step 2: migrations (checklist section 2)"
  git_clean_check
  note "2.0 The W3 pre-push probe again (checklist 0.9b), in case step 0 ran in another session."
  w3_probe
  show "supabase db push --db-url \"\$ATTUNE_DB_URL\" --dry-run"
  if [[ $DRY_RUN -eq 0 ]]; then supabase db push --db-url "$ATTUNE_DB_URL" --dry-run; fi
  gate "Is the list exactly the pending set from step 0 (Appendix A)? Push now?"
  show "supabase db push --db-url \"\$ATTUNE_DB_URL\""
  if [[ $DRY_RUN -eq 0 ]]; then supabase db push --db-url "$ATTUNE_DB_URL"; fi

  note "2.2 Every migration landed; still development."
  local applied env
  applied="$(sql_value "select count(*) from supabase_migrations.schema_migrations where version >= '$FIRST_PENDING';")"
  env="$(sql_value "select public.get_attune_environment();")"
  if [[ $DRY_RUN -eq 0 ]]; then
    [[ "$applied" == "$EXPECTED_PENDING" ]] || die "$applied of $EXPECTED_PENDING migrations from $FIRST_PENDING are recorded. Re-run this step (a lock timeout: at a quiet time)."
    [[ "$env" == "development" ]] || die "get_attune_environment() reads '$env', not development."
  fi

  note "2.3 Post-push checks. Each line's expected value is in its comment."
  sql_block <<'SQL'
-- S1 W1: f | f
select has_column_privilege('authenticated','public.users','phone','UPDATE'), has_table_privilege('authenticated','public.users','INSERT');
-- S1 W1 drift again: will_be_restored = 0, will_be_nulled = 0
select count(*) filter (where u.phone is distinct from a.phone and a.phone_confirmed_at is not null and nullif(btrim(a.phone), '') is not null) as will_be_restored,
       count(*) filter (where u.phone is not null and (a.id is null or a.phone_confirmed_at is null or nullif(btrim(a.phone), '') is null)) as will_be_nulled
  from public.users u left join auth.users a on a.id = u.id;
-- S1 W4: f
select has_table_privilege('authenticated','public.relationships','INSERT');
-- S1 W5: 0 rows
select tablename from pg_publication_tables where tablename like 'couple_profile%';
-- S1 W6: t | f | f
select has_function_privilege('supabase_auth_admin','public.attune_access_token_hook(jsonb)','EXECUTE'),
       has_function_privilege('authenticated','public.attune_access_token_hook(jsonb)','EXECUTE'),
       has_function_privilege('service_role','public.attune_access_token_hook(jsonb)','EXECUTE');
-- S1 W6: activity about equal to users
select (select count(*) from public.account_activity) as activity, (select count(*) from public.users) as users;
-- S1 W6/W7: fresh_start_key_present true; media_scan_enqueue_path trigger or sweep; failures 0
select public.get_identity_health();
-- S1 W7: two rows, avatars | t and safety-quarantine | f; then 0 rows
select id, public from storage.buckets where id in ('safety-quarantine', 'avatars') order by id;
select policyname from pg_policies where schemaname = 'storage' and tablename = 'objects'
   and ((coalesce(qual,'') || coalesce(with_check,'')) ~ 'safety-quarantine' or (coalesce(qual,'') || coalesce(with_check,'')) !~ 'bucket_id = ');
-- S1 W9: kokoo bastard | contact_info | (null)
select private.match_form('K' || chr(596) || 'k' || chr(596) || chr(596) || ' B@st4rd'),
       private.content_filter_verdict('call me on 024 412 3456', null),
       private.content_filter_verdict('We met in 1999 and married in 2004.', null);
-- Spec 3 W2 + W3: 7 rows, all ok = true
select * from public.forum_retirement_health();
-- S2 W1: true | true | true | development
select h ->> 'field_key_present' as field_key, h ->> 'field_key_fingerprint_ok' as field_fp, h -> 'log_settings_safe' as logs_safe, h ->> 'environment' as env
  from (select public.get_dating_operational_health() as h) s;
-- S2 W1: t
select private.dating_exclusion_key_ready();
-- S2 W1: 8
select count(*) from private.flag_production_gates where flag_key like 'dating%';
-- S2 W2: 1 row
select tgname from pg_trigger where tgrelid = 'public.users'::regclass and tgname = 'dating_pause_on_path_change';
-- S2 W3: 2097152 | {image/jpeg,image/png,image/webp}
select file_size_limit, allowed_mime_types from storage.buckets where id = 'dating-profile-photos';
-- S2 W6: 0
select count(*) from public.dating_matches where state <> 'active' and evidence_until is null;
-- S2 W9: f | t
select has_table_privilege('service_role','public.data_export_jobs','INSERT'), has_table_privilege('service_role','public.data_export_jobs','SELECT');
SQL
  gate "Does every result match its comment (checklist 2.3)?"

  note "2.4 Key seeding and backfills (idempotent)."
  local ex_seed field_seed stamp opin
  sql "select public.backfill_dating_former_partner_exclusions();"
  ex_seed="$(sql_value "select private.seed_dating_exclusion_key_fingerprint();")"
  field_seed="$(sql_value "select private.seed_dating_field_key_fingerprint();")"
  stamp="$(sql_value "select private.dating_stamp_restriction_hmacs();")"
  opin="$(sql_value "select private.opinion_stamp_backfill();")"
  if [[ $DRY_RUN -eq 0 ]]; then
    note "exclusion seed: $ex_seed; field seed: $field_seed; restriction stamps: $stamp; opinion stamps: $opin"
    [[ "$ex_seed" == "ready" ]] || die "seed_dating_exclusion_key_fingerprint answered '$ex_seed' (checklist 2.4)."
    [[ "$field_seed" == "ready" ]] || die "seed_dating_field_key_fingerprint answered '$field_seed' (checklist 2.4)."
    [[ "$stamp" != "-1" ]] || die "dating_stamp_restriction_hmacs answered -1: the exclusion key is missing."
    [[ "$opin" != "-1" ]] || die "opinion_stamp_backfill answered -1: the exclusion key is missing."
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    note "2.5 (dry run) On NO-GO (or undecided), this unschedules the purge cron:"
    sql "select cron.unschedule(jobid) from cron.job where jobname = 'purge-unfinished-signups';"
  elif [[ "$(state_read purge_decision)" != "go" ]]; then
    note "2.5 Purge NO-GO (or not decided): unschedule its cron."
    sql "select cron.unschedule(jobid) from cron.job where jobname = 'purge-unfinished-signups';"
  fi

  note "2.6 Load the support catalogue (as service_role, all or nothing)."
  show "psql \"\$ATTUNE_DB_URL\" -X -v ON_ERROR_STOP=1 -v catalogue=<assets/support_resources/catalogue.json, compacted> <<'SQL'"
  show "  BEGIN; SET LOCAL ROLE service_role; SELECT public.load_support_resources(:'catalogue'::jsonb); COMMIT;"
  if [[ $DRY_RUN -eq 0 ]]; then
    local catalogue
    catalogue="$(python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")), ensure_ascii=False, separators=(",", ":")))' assets/support_resources/catalogue.json)"
    printf '%s\n' 'BEGIN;' 'SET LOCAL ROLE service_role;' \
      "SELECT public.load_support_resources(:'catalogue'::jsonb);" 'COMMIT;' \
      | psql "$ATTUNE_DB_URL" -X -q -v ON_ERROR_STOP=1 -At -v catalogue="$catalogue"
  fi
  sql "select public.get_support_resources('GH');"
  note "Expected: loaded 4, deactivated 0, catalogue_version 2026-11-03.1; GH lists DOVVSU and Find A Helpline."
}

# ---------------------------------------------------------------------------
# Step 3: edge functions
# ---------------------------------------------------------------------------
step3() {
  CURRENT_STEP=3
  say "Step 3: edge functions (checklist section 3)"
  gate "Start the function deletes and deploys?"
  git_clean_check
  load_function_list

  local f
  for f in upload-dating-photo verify-dating-profile activate-topics forum-quiet-check; do
    if [[ $DRY_RUN -eq 1 ]] || function_present "$f"; then
      run supabase functions delete "$f" --project-ref "$REF"
    else
      note "$f is not on the project (already deleted)."
    fi
  done

  for f in process-dating-photo scan-media identity-health-alert purge-recovery-holds \
    process-dating-safety-outbox build-data-exports accept-invite create-relationship-invite \
    analyse-journal-entry generate-healing-portrait generate-healing-post-mortem \
    process-scheduled-notifications dating-verification dating-photo-urls; do
    deploy_fn "$f"
  done
  for f in otp-delivery-intent send-sms-hook start-fresh-account; do
    deploy_fn_no_jwt "$f"
  done

  deploy_dating_moderation

  if [[ $DRY_RUN -eq 1 ]]; then
    note "(dry run) GO only:"
    deploy_fn purge-unfinished-signups
  elif [[ "$(state_read purge_decision)" == "go" ]]; then
    deploy_fn purge-unfinished-signups
  else
    note "purge-unfinished-signups not deployed (NO-GO or undecided)."
  fi
  note "dating-device-check is deployed in step 5, after the IP table."
  load_function_list
  note "Expected: every deployed name ACTIVE with today's time; none of the four deleted names."
}

# ---------------------------------------------------------------------------
# Step 4: crons
# ---------------------------------------------------------------------------
step4() {
  CURRENT_STEP=4
  say "Step 4: cron jobs (checklist section 4)"
  note "The migrations scheduled all 23 jobs. Wait about 20 minutes after the push so the */5 and */15 jobs have run."
  gate "Run the cron checks now?"
  sql_block <<'SQL'
with names(n) as (values
  ('metric-counters-retention'),('purge-unfinished-signups'),('otp-purge'),('enqueue-journal-reminders'),
  ('invite-preview-retention'),('fresh-start-retention'),('purge-recovery-holds'),('identity-health-alert'),
  ('scan-media'),('media-scan-retention'),('enqueue-new-storage-objects'),('media-scan-reconcile'),
  ('opinion-enforcement-purge'),('sweep-dating-photo-orphans'),('recover-stale-dating-photo-jobs'),
  ('dating-verification-sweep'),('dating-candidate-generation'),('dating-digest'),('dating-fairness-weekly'),
  ('process-dating-safety-outbox'),('recover-stale-dating-workers'),('purge-dating-retention'),
  ('release-dating-suspensions'),('dating-moderation-sla'))
select n.n as jobname, j.schedule, j.active, d.status, d.start_time, left(d.return_message, 80) as message
  from names n
  left join cron.job j on j.jobname = n.n
  left join lateral (select r.status, r.start_time, r.return_message from cron.job_run_details r
                      where r.jobid = j.jobid order by r.start_time desc limit 1) d on true
 order by 1;
select status_code, count(*) from net._http_response where created > now() - interval '30 minutes' group by 1 order by 1;
SQL
  local forum_jobs
  forum_jobs="$(sql_value "select count(*) from cron.job where jobname in ('activate-topics-sweep','forum-quiet-check','mark-quiet-forums');")"
  if [[ $DRY_RUN -eq 0 && "$forum_jobs" != "0" ]]; then die "$forum_jobs forum cron job(s) still scheduled (checklist 0.9)."; fi
  note "Expected: a schedule on every row (not enqueue-new-storage-objects on the trigger path, not the purge after NO-GO);"
  note "succeeded where it has run; only 2xx answers. Re-run this query tomorrow for the daily and weekly jobs."
}

# ---------------------------------------------------------------------------
# Step 5: the IP country table, then dating-device-check
# ---------------------------------------------------------------------------
step5() {
  CURRENT_STEP=5
  say "Step 5: the IP country table (checklist section 5)"
  gate "Build the DB-IP table ($DBIP_MONTH; override with DBIP_MONTH=YYYY-MM) and deploy dating-device-check?"
  local build=1
  if [[ -f "$IP_BIN" ]] && ! confirm "$IP_BIN exists. Rebuild it from the $DBIP_MONTH CSV?"; then
    build=0
  fi
  if [[ $build -eq 1 ]]; then
    run mkdir -p "$WORK_DIR"
    run curl -sSfL -o "$WORK_DIR/dbip.csv.gz" "https://download.db-ip.com/free/dbip-country-lite-$DBIP_MONTH.csv.gz"
    run gunzip -f "$WORK_DIR/dbip.csv.gz"
    run deno run --allow-read --allow-write scripts/ip_country/build_ip_country.ts "$WORK_DIR/dbip.csv" "$IP_BIN"
  fi
  if [[ $DRY_RUN -eq 0 ]]; then
    local bytes
    [[ -f "$IP_BIN" ]] || die "No $IP_BIN: the build did not write it (checklist 5)."
    bytes="$(wc -c < "$IP_BIN" | tr -d ' ')"
    note "$IP_BIN: $bytes bytes (limit for the whole bundle: $IP_BUNDLE_LIMIT)."
    [[ "$bytes" -le "$IP_BUNDLE_LIMIT" ]] || die "The IP table alone is over 20 MB."
  fi
  gate "Did the builder report 0 (or few) ranges claimed by two countries? Deploy?"
  git_clean_check
  deploy_fn dating-device-check
  note "Check the function's logs for ip_table_unavailable / ip_table_stale (none expected), and the bundle size in the deploy output (<= 20 MB)."
}

# ---------------------------------------------------------------------------
# Step 6: the moderation console build (hosting is yours)
# ---------------------------------------------------------------------------
step6() {
  CURRENT_STEP=6
  say "Step 6: moderation console (checklist section 6)"
  if confirm "Build the console web app now (needs flutter and the publishable key)?"; then
    if [[ $DRY_RUN -eq 0 ]]; then
      command -v flutter > /dev/null 2>&1 || die "flutter not found."
      if [[ -z "${ATTUNE_ANON_KEY:-}" ]]; then
        read_secret ATTUNE_ANON_KEY "Publishable (anon) key"
        [[ -n "$ATTUNE_ANON_KEY" ]] || die "No key given."
      fi
    fi
    show "flutter build web -t lib/console/main_console.dart -o build/console --pwa-strategy=none --no-web-resources-cdn --dart-define=SUPABASE_URL=https://$REF.supabase.co --dart-define=SUPABASE_ANON_KEY=\"\$ATTUNE_ANON_KEY\""
    if [[ $DRY_RUN -eq 0 ]]; then
      flutter build web -t lib/console/main_console.dart -o build/console --pwa-strategy=none --no-web-resources-cdn \
        --dart-define=SUPABASE_URL="https://$REF.supabase.co" --dart-define=SUPABASE_ANON_KEY="$ATTUNE_ANON_KEY"
    fi
  fi
  note "Host build/console/ privately behind an access gate (noindex, the headers in checklist 6), and enable TOTP MFA."
  gate "Is the console hosted?"
  load_secret_names
  if [[ $DRY_RUN -eq 1 ]] || ! has_secret DATING_CONSOLE_ORIGIN; then
    local origin=""
    if [[ $DRY_RUN -eq 1 ]]; then
      note "(dry run; would ask) The console's exact origin, https://host[:port], no path, no trailing slash"
    else
      read -r -p "   The console's exact origin (https://host[:port], no path, no trailing slash): " origin || origin=""
      [[ "$origin" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || die "Not an origin of the form https://host[:port]."
    fi
    set_edge_secrets "DATING_CONSOLE_ORIGIN=$origin"
  fi
  deploy_dating_moderation
}

# ---------------------------------------------------------------------------
# Step 7: safety-owner and moderator rows, MFA, the Auth hooks
# ---------------------------------------------------------------------------
step7() {
  CURRENT_STEP=7
  say "Step 7: moderators, MFA and the Auth hooks (checklist section 7)"
  note "In the SQL editor, with two different Attune accounts' users.id (one row each):"
  note "  insert into public.dating_moderators (user_id, role, sensitive_routing_allowed, languages)"
  note "  values ('<safety owner id>', 'safety_owner', true, '{en}'), ('<moderator id>', 'moderator', false, '{en,tw,gaa,pcm}')"
  note "  on conflict (user_id) do update set role = excluded.role, sensitive_routing_allowed = excluded.sensitive_routing_allowed, languages = excluded.languages, active = true;"
  gate "Inserted?"
  local owners mods
  owners="$(sql_value "select count(*) from public.dating_moderators where active and role = 'safety_owner';")"
  mods="$(sql_value "select count(*) from public.dating_moderators where active and role = 'moderator';")"
  if [[ $DRY_RUN -eq 0 ]]; then
    [[ "$owners" -ge 1 && "$mods" -ge 1 ]] || die "Need one active safety_owner and one active moderator (have $owners and $mods)."
    note "Active safety owners: $owners; moderators: $mods."
  fi
  gate "Dashboard: TOTP MFA on, JWT expiry <= 3600 s? (The hooks in checklist 7.4 are optional; dashboard only.)"
}

# ---------------------------------------------------------------------------
# Step 8: every flag on for demos (generation waits for step 9)
# ---------------------------------------------------------------------------
step8() {
  CURRENT_STEP=8
  say "Step 8: flags on for demos (checklist section 8)"
  if confirm "8.1 Use the fake verification providers for demos (recommended; debug/profile builds only)?"; then
    local mode_count
    mode_count="$(sql_value "select count(*) from vault.secrets where name = 'age_assurance_mode';")"
    if [[ "$mode_count" == "1" ]]; then
      sql "select vault.update_secret((select id from vault.secrets where name = 'age_assurance_mode'), 'fake');"
    else
      sql "select vault.create_secret('fake', 'age_assurance_mode', 'demo: fake verification on the development project');"
    fi
  fi

  gate "Run the dev flag scripts (Spec 1, draft filter terms, Spec 2 Dating, Spec 5, 7, 8)?"
  sql_file supabase/sql/dev_enable_spec1_flags.sql
  sql_file supabase/sql/load_content_filter_terms.sql

  show "psql \"\$ATTUNE_DB_URL\" -X -v ON_ERROR_STOP=1 -f supabase/sql/dev_enable_spec2_dating_flags.sql   (stops on any WARNING)"
  if [[ $DRY_RUN -eq 0 ]]; then
    local out
    if ! out="$(psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -P pager=off -f supabase/sql/dev_enable_spec2_dating_flags.sql 2>&1)"; then
      printf '%s\n' "$out"
      die "dev_enable_spec2_dating_flags.sql failed (above); it is one statement, so it changed nothing. Fix it (checklist 8.3) and re-run from step 8."
    fi
    printf '%s\n' "$out"
    if printf '%s\n' "$out" | grep -q 'WARNING'; then
      die "dev_enable_spec2_dating_flags.sql warned: its flags ARE on, but a key is missing. Fix the key (checklist 8.3) and re-run from step 8."
    fi
  fi

  sql_file supabase/sql/dev_enable_spec5_flags.sql
  sql_file supabase/sql/dev_enable_spec7_flags.sql
  sql_file supabase/sql/dev_enable_spec8_flags.sql

  note "8.5 Generation waits until both demo enrolments are active (step 9), so today's cohort isn't used up empty."
  sql "update public.feature_flags set enabled = false, updated_at = now() where key = 'dating_candidate_generation';"
  local expected=$((DEMO_FLAG_COUNT - 1))

  note "8.6 opinions_safety_v1 filters every Opinions post with the [DRAFT] terms; removals count toward 7-day bans."
  if confirm_default_yes "Keep opinions_safety_v1 on for demos (testers only)?"; then
    state_write opinions_safety_on yes
  else
    sql "update public.feature_flags set enabled = false, updated_at = now() where key = 'opinions_safety_v1';"
    state_write opinions_safety_on no
    expected=$((expected - 1))
  fi

  note "8.7 The count."
  local demo_on total n_other countries
  demo_on="$(sql_value "select count(*) from public.feature_flags where enabled and key = any (array[$DEMO_FLAGS]);")"
  total="$(sql_value "select count(*) filter (where enabled) from public.feature_flags;")"
  countries="$(sql_value "select public.get_public_app_config() -> 'config' -> 'dating_open_countries';")"
  if [[ $DRY_RUN -eq 0 ]]; then
    n_other="$(state_read n_other_on)"
    note "demo flags on: $demo_on (expected $expected); enabled total: $total (expected $expected + N, N = ${n_other:-?}); open countries: $countries"
    [[ "$demo_on" == "$expected" ]] || die "$demo_on demo flags are on; expected $expected."
    if [[ -n "$n_other" && "$total" != "$((expected + n_other))" ]]; then
      note "note: the total differs from $expected + N; compare with the step-0 flag list."
    fi
    [[ "$countries" == '["GB", "GH"]' ]] || note "note: expected [\"GB\", \"GH\"] open; read checklist 8.3."
  fi
  sql "select * from public.production_flag_violations();"
  note "Violations are expected in development (W10 launch step 8 handles them)."
  note "Every tester installs the W10 build now (debug/profile for Dating demos; checklist 8.8)."
}

# ---------------------------------------------------------------------------
# Step 9: generation on once both demo enrolments are active, then smoke
# ---------------------------------------------------------------------------
step9() {
  CURRENT_STEP=9
  say "Step 9: introductions and smoke checks (checklist section 9; two phones, test accounts)"
  note "9.1 When two compatible demo accounts have finished D1-D13 (active), turn generation on and run one tick."
  if confirm "Are both demo enrolments active now?"; then
    local active
    active="$(sql_value "select count(*) from public.dating_enrollments where state = 'active';")"
    if [[ $DRY_RUN -eq 0 && "$active" -lt 2 ]]; then die "Only $active active enrolment(s): finish D1-D13 on both phones, then run --from 9."; fi
    sql "update public.feature_flags set enabled = true, updated_at = now() where key = 'dating_candidate_generation';"
    sql "select public.run_dating_generation_tick();"
    sql "select count(*) as intros_today from public.dating_introductions where created_at > now() - interval '1 hour';"
    note "Expected: the tick lists GB/GH partitions run, and introductions appear in Today."
  else
    note "Generation stays off. Re-run with --from 9 when both are active."
  fi
  note "Then the table in checklist 9: sign-in, invite, Dating setup, Today, chat, report, console, CSAM stub,"
  note "couple link, export, traveller, plain icon, storage header."
  if confirm "Run the read-only helper queries now (after you have used the app)?"; then
    sql_block <<'SQL'
select moderation_state, csam_state, count(*) from public.dating_profile_photos group by 1, 2 order by 1, 2;
select state, count(*) from public.dating_enrollments group by 1 order by 1;
select count(*) as intros_24h from public.dating_introductions where created_at > now() - interval '1 day';
select count(*) filter (where ip_resolved) as resolved, count(*) as checked from public.dating_session_context where checked_at > now() - interval '1 hour';
select public.get_dating_operational_health() -> 'chat_safety_outbox' as outbox;
select public.get_identity_health();
SQL
  fi
  say "Done. Not yet (checklist 10): production mode, Database Webhooks on couple/Dating tables."
}

basic_checks
if should_run 0; then step0; fi
if should_run 1; then step1; fi
if should_run 2; then step2; fi
if should_run 3; then step3; fi
if should_run 4; then step4; fi
if should_run 5; then step5; fi
if should_run 6; then step6; fi
if should_run 7; then step7; fi
if should_run 8; then step8; fi
if should_run 9; then step9; fi

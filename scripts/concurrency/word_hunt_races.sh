#!/usr/bin/env bash
#
# Word Hunt concurrency contracts.
#
# These cannot live in supabase/tests/: that suite runs inside one
# transaction, and a lock race needs two connections. Everything here was
# written because a review found a defect that a single-connection test
# could not have caught.
#
# Run:  scripts/concurrency/word_hunt_races.sh [dbname]
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
DB="${1:-attune_test}"

psql -q -d "$DB" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<'SQL'
INSERT INTO auth.users(id) VALUES ('00000000-0000-0000-0000-0000000000f1'),('00000000-0000-0000-0000-0000000000f2') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id,phone,display_name) VALUES
 ('00000000-0000-0000-0000-0000000000f1','+15554490001','RA'),
 ('00000000-0000-0000-0000-0000000000f2','+15554490002','RB') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships(id,user_a,user_b,status) VALUES
 ('00000000-0000-0000-0000-0000000000ff','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000f2','active') ON CONFLICT DO NOTHING;
DROP TABLE IF EXISTS public.rc_ctx;
CREATE TABLE public.rc_ctx(sid uuid);
DO $$
DECLARE sid uuid;
BEGIN
  PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}',false);
  UPDATE public.game_sessions SET status='abandoned', created_at=created_at-interval '3 hours'
   WHERE relationship_id='00000000-0000-0000-0000-0000000000ff' AND game_type='word_hunt' AND status IN ('invited','active');
  DELETE FROM public.session_idempotency_keys WHERE key='rc1';
  sid := (public.word_hunt_create_session('00000000-0000-0000-0000-0000000000ff','rc1')->>'session_id')::uuid;
  PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}',false);
  PERFORM public.word_hunt_accept_session(sid);
  -- Stale by the 24h rule: active, nobody started, aged.
  UPDATE public.game_sessions SET started_at=now()-interval '25 hours', created_at=now()-interval '25 hours' WHERE id=sid;
  INSERT INTO public.rc_ctx VALUES (sid);
END $$;
SQL

# Hold the session lock, then make the session FRESH again before releasing.
# The sweep has already selected this id; only the under-lock re-check can
# save it.
psql -d "$DB" >/tmp/rc_hold.log 2>&1 <<'SQL' &
BEGIN;
SELECT 1 FROM public.game_sessions WHERE id=(SELECT sid FROM public.rc_ctx) FOR UPDATE;
SELECT pg_sleep(1.2);
UPDATE public.game_sessions
   SET started_at = now(), created_at = now()
 WHERE id=(SELECT sid FROM public.rc_ctx);
COMMIT;
SQL
sleep 0.3
psql -d "$DB" >/tmp/rc_sweep.log 2>&1 <<'SQL' &
SELECT public.expire_word_hunt_sessions() AS swept;
SQL
wait

status=$(psql -tA -d "$DB" -c "SELECT status FROM public.game_sessions WHERE id=(SELECT sid FROM public.rc_ctx);")
psql -q -d "$DB" -c "DROP TABLE IF EXISTS public.rc_ctx;" >/dev/null 2>&1
if [ "$status" = "abandoned" ]; then
  echo "FAIL: the sweep closed a session that had become fresh under the lock"
  exit 1
fi
echo "PASS: the under-lock re-check spared a session that came back to life (status=$status)"

# ---------------------------------------------------------------------
# BLOCKER 2: gameplay and expiry must not take opposite lock orders.
# ---------------------------------------------------------------------
# Reproduced before the fix as "ERROR: deadlock detected". Gameplay locks
# the session then the attempt; expiry used to write attempts first.
psql -q -d "$DB" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<'SQL'
DROP TABLE IF EXISTS public.rc_ctx;
CREATE TABLE public.rc_ctx(sid uuid);
DO $$
DECLARE sid uuid;
BEGIN
  PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}',false);
  UPDATE public.game_sessions SET status='abandoned', created_at=created_at-interval '3 hours'
   WHERE relationship_id='00000000-0000-0000-0000-0000000000ff' AND game_type='word_hunt' AND status IN ('invited','active');
  DELETE FROM public.session_idempotency_keys WHERE key='rc2';
  sid := (public.word_hunt_create_session('00000000-0000-0000-0000-0000000000ff','rc2')->>'session_id')::uuid;
  PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}',false);
  PERFORM public.word_hunt_accept_session(sid);
  PERFORM public.word_hunt_start(sid);
  UPDATE public.game_sessions SET started_at=now()-interval '25 hours', created_at=now()-interval '25 hours' WHERE id=sid;
  ALTER TABLE public.word_hunt_attempts DISABLE TRIGGER word_hunt_attempts_transition;
  UPDATE public.word_hunt_attempts SET started_at=now()-interval '25 hours' WHERE session_id=sid;
  ALTER TABLE public.word_hunt_attempts ENABLE TRIGGER word_hunt_attempts_transition;
  INSERT INTO public.rc_ctx VALUES (sid);
END $$;
SQL

# Gameplay order: session lock, pause, then the attempt.
psql -d "$DB" >/tmp/wh_dl_a.log 2>&1 <<'SQL' &
BEGIN;
SELECT 1 FROM public.game_sessions WHERE id=(SELECT sid FROM public.rc_ctx) FOR UPDATE;
SELECT pg_sleep(1.5);
SELECT 1 FROM public.word_hunt_attempts WHERE session_id=(SELECT sid FROM public.rc_ctx) FOR UPDATE;
COMMIT;
SQL
sleep 0.3
psql -d "$DB" >/tmp/wh_dl_b.log 2>&1 <<'SQL' &
SELECT public.expire_word_hunt_sessions();
SQL
wait

if grep -qi "deadlock" /tmp/wh_dl_a.log /tmp/wh_dl_b.log; then
  echo "FAIL: gameplay and expiry deadlocked -- the lock orders diverged again"
  psql -q -d "$DB" -c "DROP TABLE IF EXISTS public.rc_ctx;" >/dev/null 2>&1
  exit 1
fi
echo "PASS: gameplay and expiry share one lock order, no deadlock"

# ---------------------------------------------------------------------
# BLOCKER 3: a Start must not land under an expiring session.
# ---------------------------------------------------------------------
psql -q -d "$DB" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<'SQL'
DELETE FROM public.rc_ctx;
DO $$
DECLARE sid uuid;
BEGIN
  PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}',false);
  UPDATE public.game_sessions SET status='abandoned', created_at=created_at-interval '3 hours'
   WHERE relationship_id='00000000-0000-0000-0000-0000000000ff' AND game_type='word_hunt' AND status IN ('invited','active');
  DELETE FROM public.session_idempotency_keys WHERE key='rc3';
  sid := (public.word_hunt_create_session('00000000-0000-0000-0000-0000000000ff','rc3')->>'session_id')::uuid;
  PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}',false);
  PERFORM public.word_hunt_accept_session(sid);
  UPDATE public.game_sessions SET started_at=now()-interval '25 hours', created_at=now()-interval '25 hours' WHERE id=sid;
  INSERT INTO public.rc_ctx VALUES (sid);
END $$;
SQL

psql -d "$DB" >/dev/null 2>&1 <<'SQL' &
SELECT public.expire_word_hunt_sessions();
SQL
psql -d "$DB" >/dev/null 2>&1 <<'SQL' &
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}',false);
SELECT public.word_hunt_start((SELECT sid FROM public.rc_ctx));
SQL
wait

orphan=$(psql -tA -d "$DB" -c "
  SELECT count(*) FROM public.game_sessions s
  JOIN public.word_hunt_attempts a ON a.session_id = s.id
  WHERE s.id=(SELECT sid FROM public.rc_ctx)
    AND s.status='abandoned' AND a.status='in_progress';")
psql -q -d "$DB" -c "DROP TABLE IF EXISTS public.rc_ctx;" >/dev/null 2>&1
if [ "$orphan" != "0" ]; then
  echo "FAIL: an in-progress attempt is running under an abandoned session"
  exit 1
fi
echo "PASS: no attempt left running under an expired session"

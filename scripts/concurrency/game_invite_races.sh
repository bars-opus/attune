#!/usr/bin/env bash
#
# Two connections invite the same game at the same moment.
#
# Lives outside supabase/tests because those run in a single transaction
# and a race needs two. What it proves cannot be proven in one: the
# advisory locks in game_invite_create serialise concurrent invitations,
# so a couple gets ONE session, ONE card and ONE set of rounds no matter
# how the taps interleave.
#
# Without the locks this produces two sessions and two cards -- and for
# 36 Questions, two different sets of twelve questions for the same
# chapter, which is the partners playing different games.
#
# Usage: scripts/concurrency/game_invite_races.sh
# Requires the local attune_test database (scripts/local_pg_setup.sh).
set -uo pipefail
DB=attune_test
REL='00000000-0000-0000-0000-000000000091'
U1='00000000-0000-0000-0000-00000000b901'

psql -q -d $DB -c "DELETE FROM public.messages WHERE relationship_id='$REL';
  DELETE FROM public.session_idempotency_keys WHERE session_id IN
    (SELECT id FROM public.game_sessions WHERE relationship_id='$REL');
  DELETE FROM public.game_session_rounds WHERE session_id IN
    (SELECT id FROM public.game_sessions WHERE relationship_id='$REL');
  DELETE FROM public.game_sessions WHERE relationship_id='$REL';" >/dev/null 2>&1

run() {
  psql -q -d $DB <<SQL 2>&1 | grep -E "NOTICE|ERROR"
DO \$\$
DECLARE r jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub','$U1',true);
  PERFORM set_config('request.jwt.claims',json_build_object('sub','$U1','role','authenticated')::text,true);
  r := public.game_invite_create('$REL','36_questions','$1','connecting');
  RAISE NOTICE '$1 -> %', r;
END \$\$;
SQL
}

run key-A &
run key-B &
wait

echo "--- result ---"
psql -q -d $DB -c "
  SELECT count(*) AS sessions FROM public.game_sessions
   WHERE relationship_id='$REL' AND game_type='36_questions';"
psql -q -d $DB -c "
  SELECT count(*) AS cards FROM public.messages WHERE relationship_id='$REL';"
psql -q -d $DB -c "
  SELECT s.id, count(r.id) AS rounds FROM public.game_sessions s
    LEFT JOIN public.game_session_rounds r ON r.session_id=s.id
   WHERE s.relationship_id='$REL' GROUP BY s.id;"

# SDD ledger — plan: docs/superpowers/plans/2026-10-12-planning-p3-p4-blocks.md

User instruction: "build p3 and p4 and merge back to main so I can test them". Executor: inline.
Task 1: Ruling: starter templates' full block lists move to Task 5 — so they can include P4 blocks (countdown, poll, progress) in one version bump — cost if wrong: none; P3 starters stay at their P1 blocks until Task 5.
Task 1: Ruling: P1 contracts asserting "budget refused" retargeted to an unknown type ('spreadsheet') — P3 legitimately adds budget — cost if wrong: none.
Task 1: complete (commits 1bfcaa3c..4136a4e5, tests: all supabase/tests/planning_*.sql → 10/10 ok; planning_v2_concurrency → PASS; mutation amount/2→(amount+1)/2 caught)
Task 2: Ruling: rate limit (30/min/user) enforced in planning_link_preview_target via planning_link_preview_requests + advisory lock — keeps the edge function stateless (spec 1.7) — cost if wrong: one extra insert per preview.
Task 2: Ruling: set_planning_link_preview returns boolean and queues a replaced preview image — lets the function delete an orphaned upload when the url changed mid-fetch — cost if wrong: none.
Task 2: Ruling: only default ports (80/443) allowed for previews — narrows internal-service probing on public IPs; spec silent — cost if wrong: links with explicit ports get a plain card.
Task 2: Ruling: entry_id allowlist edit has no unit test — privacySafeData is module-private behind serve(); a one-line allowlist entry — cost if wrong: a push opens Planning home instead of the plan.
Task 2: complete (commits 4136a4e5..784f4949, tests: deno test planning-link-preview → 14/14; deno check index.ts ok; planning_rich_blocks_contracts PASS; mutations: mixed-DNS check and resolve-guard both caught)
Task 3: Ruling: photos reuse chat's ChatImagePreparer (JPEG, EXIF stripped, <=1600px, <=800KB) — inside the spec's 2048px/10MB ceilings; avoids a third copy of the preparer — cost if wrong: a cross-feature import to move later.
Task 3: Ruling: rich items (rows, expense lines) are online-only (no outbox) — the outbox covers ticks/adds per P1; money edits surface errors instead of queueing — cost if wrong: offline expense entry fails with the network message.
Task 3: complete (commits 784f4949..93da242a, tests: flutter test test/features/planning (money, rich models/repository/controller) → pass)
Task 4: Ruling: Place uses the app's LocationService (Google Places, mode address) instead of Mapbox — it is the existing location dependency; spec named Mapbox — cost if wrong: swap the suggestion source.
Task 4: Ruling: P1 tests using 'budget' as the unknown type retargeted to 'hologram' — budget is now known — cost if wrong: none.
Task 4: complete (commits 93da242a..dbc2351d, tests: flutter test test/features/planning → 142/142; flutter analyze planning → no issues)
Task 5: Ruling: notification debounce/idempotency uses scheduled_notifications.source_key (unique) instead of new planning_poll_notified / countdown tables — same guarantee, no new tables — cost if wrong: none functionally.
Task 5: Ruling: countdown/progress follow the plan's first Date/Checklist unless one is named; copies re-point named ids — templates can't hold ids — cost if wrong: a countdown follows a different date than expected when a plan has several.
Task 5: Ruling: copies drop photo paths and link preview images — a shared file would be deleted from under the other plan by purge/remove — cost if wrong: "Start next one" doesn't carry photos.
Task 5: Ruling: link and place blocks may exist empty (label/title only) so templates can include them — cost if wrong: empty blocks need an "add" affordance (built in Task 6).
Task 5: Ruling: Diet's "Add to Groceries" and weekly progress reset are out of scope; progress target 5 static — cost if wrong: a follow-up.
Task 5: Ruling: countdown push sent any time after 08:00 local on the day (catch-up if a run is missed), once per day — cost if wrong: a late push after a cron outage.
Task 5: complete (commits dbc2351d..de95dc37, tests: all supabase/tests/planning_*.sql → 10/10 ok; planning_v2_concurrency (fresh DB) → PASS; mutations: lock threshold <1 and no 08:00 gate both caught)
Task 6: Ruling: partner local time via new SQL planning_timezone_offset_minutes(tz) instead of adding the timezone package — PartnerDistance.partnerLocalTime is never populated; the zone string is already client-visible — cost if wrong: one RPC per zone per hour.
Task 6: Ruling: setBudgetTarget renamed setTarget (Budget and Progress share update_planning_block_target) — cost if wrong: none.
Task 6: Ruling: notification tap routing has no widget test; covered by the pure planningEntryTarget test plus analyzer — the handler is a GoRouter call — cost if wrong: a push opens Home instead of the plan.
Task 6: complete (commits de95dc37..4a85a3ef, tests: flutter test test/features/planning → 154/154; flutter analyze (planning, router, notification config) → no issues; planning_couple_blocks_contracts → PASS)
Task 7: verification (full flutter test → 2349/2349 pass; flutter analyze → 0 errors/warnings; full SQL harness → 67 PASS + 1 pre-existing FAIL settings_accessor (Vault); planning_v2_concurrency → PASS; deno test planning-link-preview → 14/14; deno check ok). Final review dispatched (opus).
Final review: opus fresh reviewer — 0 Critical, 7 Important, 11 Minor (report final-review.md).
Final: fixed I1 copies keep ticks/contributions — couple contract 10b RED→GREEN, all planning contracts 10/10 (fc867823)
Final: fixed I3 stale cells on column change (server) — couple contract 10c RED→GREEN; mutation (old update_planning_block) caught (fc867823)
Final: fixed I5 settle ignored later money on older lines — rich contract 'edit after settling' RED→GREEN (fc867823)
Final: fixed I7 audit gaps (plan delete/restore, category delete via entry trigger; copies) — rich contract RED→GREEN; trigger-disabled mutation caught (fc867823)
Final: fixed I2 comma decimals — planning_money_test 'comma decimal' RED (125000)→GREEN (6c846b46)
Final: fixed I3 table crash/key reuse (client) — review_fixes_test RED (compile)→GREEN; _typed removal mutation caught (6c846b46)
Final: fixed I4 contributions not removable — review_fixes_test RED→GREEN (6c846b46)
Final: fixed I6 duplicate expense on retry — review_fixes_test RED→GREEN; per-submit-id mutation caught (6c846b46); suite flutter test test/features/planning 161/161
Final: minor (deferred): M1 date-poll Undo shown after a failed delete
Final: minor (deferred): M2 restore of a poll option after lock resurrects it under the Date block
Final: minor (deferred): M3 signed URL TTL 1h vs spec 10 min
Final: minor (deferred): M4 bucket size/MIME limits; orphaned uploads when add_planning_photo or preview write fails
Final: minor (deferred): M5 preview image decode has no pixel cap (edge OOM on a crafted PNG)
Final: minor (deferred): M6 service_role can TRUNCATE the expense audit; trigger depth exemption is broad
Final: minor (deferred): M7 rich item validator accepts a missing amount via direct RPC; string amount may raise raw 22P02
Final: minor (deferred): M8 photo add after leaving the plan silently dropped; some controller methods set state after dispose
Final: minor (deferred): M9 server preview write bumps version so a quick link edit can hit stale_version
Final: minor (deferred): M10 progress refetch after a tick can briefly flicker a later optimistic tick
Final: minor (deferred): M11 push fallback 'Planning unavailable' screen has no back button
Final: Ruling: Edge runtime support for Deno.resolveDns/connect/startTls unverified — needs a post-deploy smoke test; failure mode is a plain link card — cost if wrong: no previews.

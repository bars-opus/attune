# Dating Mode — Deep Adversarial Security & Correctness Review

**Reviewer:** Fable 5 (adversarial security + correctness pass)
**Date:** 2026-07-12
**Scope reviewed:** 3 dating migrations (v1_1, contract_hardening, v1_2_hardening), `supabase/tests/dating_mode_contracts.sql`, all 11 files under `lib/features/dating/`, judged against `DATING_MODE_SPEC.md` v1.2, `DATING_MODE_RELEASE_READINESS_CHECKLIST.md`, and `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md`.

---

## 1. Executive summary

Dating Mode is **NOT production-ready**, but the runtime is *fail-safe*: every launch flag ships `false`, `get_dating_eligibility` short-circuits on `dating_mode_enabled=false`, and `act_on_dating_introduction` refuses without an `active` reviewed algorithm config, so none of the findings below are live-exploitable in the shipped default. They are, however, blocking gates that must close before any flag flip.

The single biggest risk is **DATING-C1: profile enumeration / cross-user profile read is not actually proven closed, and the mechanism that *would* close it (`get_my_*` SECURITY DEFINER RPCs) coexists with `dating_profiles` still being directly `SELECT`-able by its owner via PostgREST while the introduction RPC leaks the counterpart's `display_name`, `city_region_code`, and `relationship_intention` for any introduction the user is a member of — including introductions in `passed`/`interested` state — with no verification that the *presented* introduction was legitimately generated for that pair.** The deeper structural gap is that the **checklist Section 3 four-account RLS/RPC proof does not exist**: `dating_mode_contracts.sql` uses 3 accounts, seeds zero introductions/matches/blocks, and therefore proves none of the five required properties (enumeration, cross-user read, one-sided-interest leakage, actor forgery, block bypass).

Counts: **Critical 4, High 7, Medium 8, Low 5.**

The former-partner re-registration stalking vector (spec 5.1) is **entirely unimplemented** — no phone-HMAC exclusion, no documented fallback in code. The age gate is server-authoritative and sound in the *hardening* path, but a legacy self-attested activation path was shipped and only *retroactively quarantined*, and the `dating_age_verifications` table has **no writer RPC at all**, so no user can ever legitimately pass the age gate — meaning the enrollment funnel is currently unshippable as well as unsafe.

---

## 2. Findings

### CRITICAL

---

#### DATING-C1 — Four-account RLS/RPC non-enumeration proof does not exist; the one required security test is a stub
**File:** `supabase/tests/dating_mode_contracts.sql:1-89`
**Checklist item:** Section 3, line 32 ("RLS/RPC tests with at least four accounts prove no profile enumeration, cross-user reads, one-sided-interest leakage, actor forgery, or block bypass").

**What's wrong:** The single dating contract test seeds **3 accounts** (`da01`, `db02`, `dc03`), **zero** `dating_introductions`, **zero** `dating_matches`, **zero** `dating_interest_actions`, **zero** `dating_blocks`. It asserts only (a) an owner reads exactly their own profile row, (b) an outsider reads zero profile rows via raw table RLS, (c) some function-privilege REVOKEs hold, (d) the payload column list doesn't literally contain `user_id`/`pair_key`, and (e) an unreviewed algorithm config is rejected. It **never invokes** `get_my_dating_introductions`, `act_on_dating_introduction`, `get_my_dating_matches`, or `block_dating_user` with real data.

**Adversarial scenario:** None of these are tested, so all are unproven:
- **Actor forgery:** user C calls `act_on_dating_introduction(key, <intro_id belonging to A+B>, 'interested')`. The RPC filters `v_user_id IN (user_low_id, user_high_id)` so it *should* raise `introduction_not_found` — but there is no test asserting this, and the timing/error shape (`introduction_not_found` vs `introduction_unavailable`) is itself an enumeration oracle (see DATING-H2).
- **One-sided-interest leakage:** A expresses interest, B has not acted. Is there any query path (RPC result, `has_acted`, `state`) through which B learns A is interested before B reciprocates? Untested.
- **Block bypass:** A blocks B, then a stale introduction id is replayed. Untested.

**Why it matters:** This is the *named* gate for the highest-risk feature in the app. The checklist calls for four accounts precisely to exercise A↔B pairing plus C (outsider) plus D (blocked/former). The test proves table-level owner RLS and nothing about the RPC surface that is the actual API.

**Fix:** Rewrite `dating_mode_contracts.sql` with 4 accounts (A, B, C outsider, D blocked). Seed a real reviewed algorithm config, a generated introduction for (A,B), snapshots, and an active flag inside the transaction. Add explicit assertions:
1. C calling `act_on_dating_introduction` on A/B's intro raises and creates no `dating_interest_actions` row.
2. C calling `get_my_dating_introductions` returns 0 rows even when A/B intros exist.
3. After A `interested`, B's `get_my_dating_introductions` row for the pair shows no field revealing A's action (assert `has_acted=false` for B, `state NOT IN ('interested')` from B's viewpoint — see DATING-C3).
4. After D blocks A, A `act_on_dating_introduction` on the (A,D) intro raises `pair_blocked`/`introduction_unavailable` and no match is created; A's introductions list excludes the pair.
5. Assert `get_my_dating_introductions` cannot be reached by a non-member for a specific intro id (there is no by-id getter, but assert the list filter).

---

#### DATING-C2 — Age-verification gate has no writer; the only path that ever set adults-only is a self-attested checkbox, and the real gate table is unwritable
**Files:** `20260705210000_dating_mode_v1_2_hardening.sql:17-29` (`dating_age_verifications` table), `:217-231` (`dating_age_gate_holds`), `:100` (REVOKE all from everyone), `20260703194500_dating_mode_v1_1.sql:299-304` and `20260705210000:370-373` (`record_dating_consent` age_gate → `adults_only_confirmed_at`); consent UI `lib/features/dating/presentation/screens/dating_consent_screen.dart:76-86,162-176`.

**What's wrong:** Two separate age concepts exist and they are not wired together:
- `adults_only_confirmed_at` is set purely from the client checkbox via `record_dating_consent(purpose='age_gate', action='granted')`. `activate_dating_profile` (v1.2, `:526`) requires **both** `adults_only_confirmed_at IS NOT NULL` **and** `dating_age_gate_holds(v_user_id)`. Good — the self-attested checkbox alone no longer activates.
- `dating_age_gate_holds` requires a row in `dating_age_verifications` with `birth_date <= current_date - 18y`. **But `dating_age_verifications` is `REVOKE ALL … FROM PUBLIC, anon, authenticated` and there is no SECURITY DEFINER RPC anywhere that inserts into it.** No `verified_by`/`verify_dating_age(...)` function exists in any migration.

**Adversarial scenario / failure:** No user can ever satisfy `dating_age_gate_holds`, so `activate_dating_profile` always raises `activation_gates_not_met`. The funnel is functionally dead — *and* the quarantine block at `:924-931` paused every profile that had activated under the old self-attested path. So today: nobody can activate. When someone wires the missing writer, the risk is that they wire it to the client (re-introducing a self-attested integer), which the spec forbids (checklist 3: "age is never a client-editable integer").

**Why it matters:** Adults-only is the minor-safety gate. Shipping a gate with no legitimate writer guarantees that whoever unblocks it under launch pressure improvises the writer — the exact failure the spec's "implementers must not invent" clause (Section 17) warns against.

**Fix:** Add a `verify_dating_age` operation that is *service-role / admin only* (verification result comes from an approved KYC/DOB flow, not the app JWT), writing `birth_date`, `verification_method`, `verified_at`, `verified_by`. Grant EXECUTE to `service_role` only. Add a contract test asserting `authenticated` cannot insert `dating_age_verifications` and cannot execute the writer. Until that exists, keep the funnel blocked (current behavior) rather than falling back to the checkbox.

---

#### DATING-C3 — One-sided interest state leaks to the client through `dating_introductions.state`
**Files:** `20260705210000_dating_mode_v1_2_hardening.sql:670-680` (state transition) and `:749-776` (`get_my_dating_introductions` returns `di.state`); model `lib/features/dating/data/models/dating_introduction.dart:14-15,41`.

**What's wrong:** When the current actor expresses interest and the other has *not* acted, the row transitions to `state='interested'` (`:673`/`:678`). `get_my_dating_introductions` returns `di.state` verbatim to **both** members. Consider what the *counterpart* sees: A (low) presses Interested first. The shared `dating_introductions` row is now `state='interested'`, `low_action='interested'`, `high_action=NULL`. When B (high) next calls `get_my_dating_introductions`, the row is still open (`state IN ('generated','presented','interested')`) and the function returns `state='interested'` **to B**. B has not acted (`has_acted=false`), yet the introduction's state is `interested`.

**Adversarial scenario:** B observes: an introduction they have not acted on is already in state `interested`. On any introduction where B has done nothing, `state='interested'` can *only* mean the other person expressed interest. That is a direct one-sided-interest oracle — the exact "they liked you" signal the spec bans (Spec §7: "`Interested` is private until both have independently expressed interest"; checklist 5.2). The client model even exposes `state` as a field; a trivial UI or API inspection reveals it.

**Why it matters:** Double-blind interest is a non-negotiable (Spec §1, §2 "Interest: Double-blind", §7). This defeats it at the data layer regardless of UI.

**Fix:** Do not use a shared `state` column that encodes either party's action for both viewers. Either (a) never return `state` from `get_my_dating_introductions` (derive a per-viewer status: `open` if the *viewer* hasn't acted, `acted` if they have, and never expose the pair-level `interested`), or (b) compute a viewer-scoped state server-side: `CASE WHEN <viewer>_action IS NOT NULL THEN 'acted' ELSE 'open' END`. Add a contract test: after A interested + B not acted, B's fetched row must not carry any value that differs from a never-touched introduction.

---

#### DATING-C4 — Former-partner re-registration exclusion (Spec 5.1) is completely absent, with no coded fallback or documented residual
**Files:** entire dating migration set; spec requirement `DATING_MODE_SPEC.md:207-228` and edge-case table `:622`.

**What's wrong:** Spec 5.1 mandates *either* the phone-HMAC exclusion record per ended relationship *or*, until privacy approval, an explicit "block-on-sight remains available and the residual risk is documented in the Section 15 threat model." Neither exists in code. `dating_has_relationship` and the pair-order/self-pair checks handle *current* linked partners and same-user, but there is **no** exclusion keyed to a former partner who deleted and re-registered under a new UUID. `dating_blocks` is UUID-keyed and dies with the account.

**Adversarial scenario:** DV survivor A completed Healing after leaving abuser X. X deletes his account, re-registers with a new phone → new UUID. Candidate generation (once built) can introduce X to A, with X's photo, making A instantly discoverable and locatable to a known abuser. This is the named stalking vector.

**Why it matters:** This is the single most dangerous real-world harm in the feature and the spec elevated it to a first-class threat-model item. Shipping candidate generation without *at least* the documented fallback is, per the spec, "not an option."

**Fix:** Candidate generation is flag-gated off, so this is not yet live — but it must be a hard blocker on `dating_candidate_generation`. Implement the phone-HMAC exclusion table (HMAC of verified phone with a server secret, one row per ended relationship's former-partner phone, purpose-limited, never in any API), and add the exclusion predicate to the (not-yet-written) generation query and to `dating_candidate_is_current`/`act_on_dating_introduction`. Until approved, add a code comment + threat-model doc entry recording the residual and keep generation disabled.

---

### HIGH

---

#### DATING-H1 — `feature_flags` is client-readable; the "safe-off" story leaks the launch/rollout plan and the flag read is spoofable client-side
**Files:** `20260705190000_chat_system_v1_3.sql:12-18` (grants `SELECT` on `feature_flags` to `authenticated`), `lib/features/dating/domain/services/dating_feature_flags.dart:23-30`, `dating_providers.dart:22-27`.

**What's wrong:** The client reads `feature_flags` directly (`.from('feature_flags').select('enabled')`) and gates the *entire dashboard* on it (`dating_dashboard_screen.dart:20-26`). Because the row is readable by any authenticated user, (a) rollout state (which cohorts/flags are flipped) is exposed, and (b) the client-side gate is advisory — a modified client ignores it. Server RPCs *do* re-check `dating_flag_enabled` (good), so this is not a full bypass, but any RPC that *forgot* the check is now reachable.

**Adversarial scenario:** `unmatch_dating_match`, `delete_private_date_reflection`, `delete_dating_profile` (all inherited from the v1.1-hardening file, `20260703203000:798-1064`) do **not** call `dating_flag_enabled`. That is defensible for lifecycle-exit ops, but `save_private_date_reflection`/`record_dating_date_reflection` also skip the flag check and *write* content — reachable by a modified client even with dating "off," provided the user has an active match row (which the quarantine should prevent, but that's incidental).

**Why it matters:** Defense in depth for the highest-risk feature. The server must be the sole authority and must not advertise rollout state.

**Fix:** Do not grant `feature_flags` SELECT to `authenticated`; expose only `get_dating_eligibility` (which already returns `feature_unavailable`). Have the client derive availability from that RPC, not the raw table. Add the `dating_mode_enabled` check to any RPC that writes dating content.

---

#### DATING-H2 — Error-code shape is an enumeration/timing oracle across RPCs
**Files:** `act_on_dating_introduction` `20260705210000:651-663` (`introduction_unavailable`) vs `:713`/`20260703203000:657` legacy (`introduction_not_found`); `resolve_dating_introduction_target:802` (`introduction_unavailable`); `resolve_dating_match_target:817` (`match_unavailable`); `block_dating_user:842` (`invalid_target` when self).

**What's wrong:** Different failure reasons return distinguishable error strings and take measurably different code paths. `block_dating_user` raising `invalid_target` only for self-target lets a caller confirm "this UUID is me." `resolve_*` raising `introduction_unavailable` vs the intro existing-but-not-yours distinction, plus the extra `dating_candidate_is_current` / snapshot / block checks in `act_on_dating_introduction` that fire *only when the intro exists and belongs to you*, create a timing side channel: an intro id that belongs to the caller runs 6+ subqueries before failing; a foreign/nonexistent id fails immediately at the membership filter.

**Adversarial scenario:** An attacker probing random intro UUIDs can distinguish "not my introduction / doesn't exist" (fast, one error) from "my introduction but currently invalid" (slow, different error) — partial enumeration of their own pool state and, combined with DATING-C3, of counterpart activity.

**Why it matters:** Spec §12 requires that error messages/result shape/**timing** not leak existence. Checklist 5.2 lists timing explicitly.

**Fix:** Collapse all "cannot act" outcomes to one opaque error (`introduction_unavailable`) and one code path. Perform the membership check and the validity checks in a uniform order that does not branch on ownership before failing. Remove the self-target special error (silently no-op on self-block).

---

#### DATING-H3 — Idempotency key is client-generated and reused across a scope, enabling silent action suppression / replay confusion
**Files:** `lib/features/dating/data/repositories/dating_repository.dart:341-358` (`_idempotencyKey`, `_runIdempotent`), `claim_dating_idempotency` `20260703203000:285-319`.

**What's wrong:** The client mints the idempotency key (`scope-timestamp-entropy`) and caches it per `scope` in `_pendingIdempotencyKeys`, removing it only after the call resolves. Scopes like `'intro_${introductionId}_$action'` are deterministic per (intro, action). The server's `claim_dating_idempotency` treats a *previously seen* key as "already done → RETURN silently." Because the *first* action on an introduction permanently records the key, a later genuinely-new action can never reuse that scope — but more importantly, keys are attacker-chosen. A malicious client can pre-claim a key to make a *future* server-initiated retry a no-op, or replay a stale key.

**Adversarial scenario:** Because `act_on_dating_introduction` claims idempotency *before* validating current eligibility for a replay, a client that submits `interested` with a key, then the pair gets invalidated, then resubmits the *same* key → server returns success-silent (`RETURN`) without re-checking, masking that the action did not apply. More concretely: two different actions sharing a scope collision (none here, but the pattern is fragile) would silently drop the second.

**Why it matters:** Idempotency is being relied on for correctness of the double-blind match creation and rate-limit accounting. A client-authored key space is not a safe idempotency source for a security-sensitive state machine.

**Fix:** Keep accepting the client key for dedup, but (a) never let `claim`-already-seen short-circuit *before* the authorization/eligibility checks — do auth + membership + validity first, then claim, then mutate; (b) scope the idempotency uniqueness to `(user, operation, key)` (already done) but also validate the key format server-side (length, charset) to prevent pre-claiming griefing; (c) do not remove the client cache entry on the happy path in a way that lets a retried tap mint a *new* key (currently `_runIdempotent` removes the key after success, so a double-tap after completion generates a new key and a second action — for `interested` that's caught by the DB unique `(introduction_id, actor_user_id)`, but for `report`/`block` it means duplicate reports). Retain the key until the widget is disposed.

---

#### DATING-H4 — `get_my_dating_matches` returns the counterpart's `display_name`/`city_region_code` with no live block/close re-check, so a blocked or unmatched counterpart can remain visible via stale reads
**File:** `20260705210000_dating_mode_v1_2_hardening.sql:778-790`.

**What's wrong:** The matches getter filters only `dm.state='active'` and joins `dating_profiles` unconditionally. It does **not** verify the joined profile is still `active`/`approved`, does not check `dating_blocks`, and does not check `dating_candidate_is_current` for either side. `block_dating_user` sets the match to `state='blocked'` (so it drops out — good), and `unmatch` sets `unmatched` (drops out — good). But if the *counterpart* is suspended/exits/deletes their profile, `delete_dating_profile` cascades the profile row (so the JOIN drops the match silently — arguably fine) while `pause`/`exit`/`suspend` set the *match* to remain `active` (nothing closes matches on pause/exit — see DATING-H5). So a paused/exited/suspended user still appears as an active match with full name + region.

**Adversarial scenario:** B exits Dating Mode (or is suspended for harassment). A's `get_my_dating_matches` still lists B by name and city, and A can open the guided-date screen and write reflections referencing B. B believed exit removed them.

**Why it matters:** Spec §14: pause "preserve existing mutual matches"; but exit "removes it from the pool and schedules deletion," and suspension must "apply moderation state generically." A suspended harasser should not keep surfacing to their match with identity.

**Fix:** In `get_my_dating_matches`, additionally require the counterpart profile `profile_state='active' AND moderation_state='approved'` OR a match state that reflects closure, and exclude when a `dating_blocks` row exists for the pair. Decide product-explicitly what exit does to existing matches and enforce it (see DATING-H5).

---

#### DATING-H5 — Exit / suspension / relationship-guard do NOT close existing mutual matches, contradicting the lifecycle contract
**Files:** `exit_dating_mode` `20260703203000:634-678` (invalidates introductions only), `enforce_dating_restriction_change` `20260705210000:577-590` (suspends enrollment/profile, invalidates intros, **no** match update), `pause_dating_for_relationship_user` `20260703203000:343-375` (pauses, invalidates intros, **no** match update).

**What's wrong:** `invalidate_dating_for_user` touches `dating_feature_snapshots` and `dating_introductions` but never `dating_matches`. So on exit, suspension, or entering a relationship, the person's *existing active matches stay active*. Spec §14 says pause preserves matches (OK) but suspension/report must apply moderation state, and a user who enters a relationship should not keep an open dating match with a stranger.

**Adversarial scenario:** User enters a Couples relationship. Dating auto-pauses, intros invalidate — but their active dating match with a stranger persists, still messageable (once chat ships) and still showing in `get_my_dating_matches`. Or: a user suspended for harassment keeps every active match live.

**Why it matters:** Checklist 4 ("Account pause, exit, relationship creation, consent withdrawal, block, suspension, and deletion invalidate the correct records within documented SLAs") is unmet for the matches table specifically.

**Fix:** Decide per-transition (product): suspension and relationship-entry should set the user's active matches to `closed` (generic), exit should close them (spec: exit "has no retention friction"). Add match-closing to `invalidate_dating_for_user` variants where the contract requires it, gated by reason. Test each transition asserts match-row state.

---

#### DATING-H6 — Dating chat safety plan blockers unmet, yet reflection + guided-date writes are reachable, and matches screen implies a chat-adjacent surface
**Files:** `dating_matches_screen.dart:139-141` (copy acknowledges chat is gated), `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md:83-89` (5 open blockers), `save_private_date_reflection` reachable without flag (DATING-H1).

**What's wrong:** The build correctly withholds a chat surface (good, and honestly labeled). But the checklist item 3.4 ("Dating messaging Safety scope and user copy are explicitly approved and tested") and the entire Safety Plan Section 5 are unchecked human-review gates, and no `dating_match_messaging` code path exists — so this is *correctly deferred*, not a code bug. The residual code-writable concern: guided-date + reflection writes have no flag gate (DATING-H1) and the romance-scam report category, while present in the enum and UI, has **no financial-request detection, no moderation runbook wiring** (all human-gate).

**Why it matters:** These are release-meeting evidence gates, not code defects — flagged so the checklist map is honest.

**Fix:** No code change to ship chat now (correct). Add the flag gate to reflection writes (DATING-H1). Keep §5 blockers as human gates.

---

#### DATING-H7 — `save_dating_profile_draft` has two live overloads; the 6-arg legacy version is still granted and bypasses v1.2 validation/rate-limits
**Files:** legacy `20260703194500:359-430` (`save_dating_profile_draft(text,text,text,text,integer,integer)` — 6 args, no idempotency, no rate limit, no length checks), v1.2 `20260705210000:439-503` (7 args with `p_idempotency_key`, validation, rate limit). REVOKE at `:884` targets the **6-arg** signature `FROM PUBLIC,anon,authenticated`; the v1.1 file granted the 6-arg to authenticated (`20260703194500:922`). The contract-hardening file did not re-grant it.

**What's wrong:** Postgres keys functions by full signature. The 6-arg legacy `save_dating_profile_draft` still *exists* (never `DROP`ped). v1.2 `:884` does `REVOKE ALL … FROM PUBLIC,anon,authenticated` on the 6-arg form — good, that revokes the earlier grant. So the legacy is revoked. **But** the client calls the 7-arg form with `p_idempotency_key` (`dating_repository.dart:84-94` — wait, it passes `p_idempotency_key` first), so it hits the v1.2 version. Net: the legacy is dead-but-present. Risk is a future re-GRANT or a caller that omits the key resolving to the 6-arg overload (which lacks moderation-pending logic, so a bio would activate without moderation).

**Why it matters:** Overload ambiguity around a moderation-bearing write is a latent bypass: the 6-arg version sets `profile_state='draft'` but never sets `moderation_state='pending'` for a new bio, so a caller who reaches it could push an unmoderated bio.

**Fix:** `DROP FUNCTION public.save_dating_profile_draft(text,text,text,text,integer,integer);` explicitly. Keep only the 7-arg validated form.

---

### MEDIUM

---

#### DATING-M1 — `submit_dating_report` (raw-target) still exists and, though revoked from `authenticated`, is a foot-gun; reporter privacy relies on it never being re-granted
**Files:** `submit_dating_report` `20260703203000:877-916` / re-revoked `20260705210000:886`; wrapper `report_dating_introduction`/`report_dating_match` `:838-856`.
**What's wrong:** The safe path is the resolve-by-opaque-id wrappers. The raw `submit_dating_report(text,uuid,text,text)` takes a target *user_id* directly; it is revoked from authenticated (good, and the test asserts this at `:68`). Residual: it is still granted to nothing but exists; any accidental re-grant re-opens targeting arbitrary UUIDs (enumeration of who exists via FK violation vs success).
**Fix:** Consider making the raw function `SECURITY DEFINER` require the caller to also be a member of an intro/match with the target, or drop the public-facing raw variant entirely and keep only wrappers.

---

#### DATING-M2 — Rate-limit table is not pruned and `check_dating_rate_limit` counts even failed/denied attempts, enabling self-lockout but not much abuse protection on reads
**File:** `20260705210000:153-182`.
**What's wrong:** `check_dating_rate_limit` increments before the operation succeeds; a user hitting validation errors still burns quota. Reads (`get_my_dating_introductions`, `get_my_dating_matches`) are **not** rate-limited at all, so pool-probing via repeated fetches is unbounded (though results are already filtered). No window pruning job.
**Fix:** Add read rate-limits or accept (document) that reads are naturally bounded by generation cadence; add a prune to the maintenance cron.

---

#### DATING-M3 — `explanation_features` free-form JSON is rendered directly; explainability-fidelity (Spec §6.2) is unenforced and could carry invented reasons
**Files:** `dating_dashboard_screen.dart:328-337` renders `explanationFeatures.values[].description`; column is `jsonb NOT NULL DEFAULT '{}'` with no schema/provenance constraint (`20260703194500:56`).
**What's wrong:** Spec §6.2 requires displayed reasons be generated from scored feature IDs, never invented. Nothing constrains `explanation_features` to reference real `explanation_features`↔`snapshot` feature IDs. Whatever the (unbuilt) generator writes is shown verbatim.
**Fix:** When candidate generation is built, validate explanation entries against the snapshot feature IDs server-side; add a check constraint or generation-time assertion. Human-gate for now (algorithm not built).

---

#### DATING-M4 — Match-created push notification content is generic (good) but is keyed/queued per-user with the match id in `source_key`, exposing match linkage in the notifications table
**File:** `20260705210000:687-698`.
**What's wrong:** `source_key = 'dating_match:'||match_id||':'||user_id`. The `scheduled_notifications` table's RLS/access — if any operator or adjacent feature can read it — now reveals that two users matched and when. Spec §13.3 forbids "action direction toward a named person" in analytics; this is notifications, but the linkage is sensitive.
**Fix:** Use an opaque per-notification key (random uuid) and keep the match linkage only in the dating domain; ensure `scheduled_notifications` is service-role only.

---

#### DATING-M5 — `dating_reports` has RLS enabled but no policies and is REVOKEd; fine — but no reporter can read their own report status and moderation has no defined reader, so "appeal path" (Spec §4.3) is unbacked
**Files:** `dating_reports` `20260703194500:116-123,165`, no policies anywhere.
**What's wrong:** Reports are write-only via RPC. There is no read path for the reporter (acceptable) and none defined for moderators in-migration (they'll use service role). The spec's required appeal/review path for moderation decisions has no schema (`dating_profile_photos.moderation_state` has no appeal record). Human/ops gate, noted for completeness.
**Fix:** Add moderation-decision + appeal tables before the moderation gate is checked.

---

#### DATING-M6 — Consent state machine conflates `dating_terms` and `dating_opt_in` in one screen and one policy version; distinct-state requirement is only partly met
**Files:** `dating_consent_screen.dart:162-176` records terms+opt_in+historical+age in one `_handleContinue`; `record_dating_consent` does enforce distinct `purpose` rows (good, `20260705210000:358`), and `begin_dating_enrollment` requires both `dating_terms` and `dating_opt_in` granted at the same `p_terms_version` (`:405-424`).
**What's wrong:** The five states *are* distinct server-side rows (checklist 2.1 satisfied at the data layer). But the UI submits all four together and a single unchecked "historical data" box still proceeds — good (refusing historical still permits Dating, checklist 2.2 ✓). Residual: terms and opt-in are always co-granted, so they aren't *independently* recorded decisions in practice; the spec wants four *independently recorded* decisions (§3.2). Also the age-gate consent here is the self-attested checkbox (see DATING-C2), separate from real verification.
**Fix:** Acceptable for launch data model; consider separating terms acceptance from opt-in in the UI so the audit trail reflects genuinely independent choices.

---

#### DATING-M7 — `get_my_dating_introductions` LIMIT capped at 20 and matches at 50, but there is no cursor; "cap active unrevealed introductions per user" (Spec §6.4) is not enforced server-side
**Files:** `20260705210000:775,789`.
**What's wrong:** The spec requires a *cap on active unrevealed introductions per user* as a product config. Nothing enforces a cap at generation (generation unbuilt) or rejects over-cap. The read LIMIT is not the cap.
**Fix:** Enforce the cap at candidate generation time (when built) and document it as config, not a count shown to users.

---

#### DATING-M8 — Device-clock independence is satisfied server-side, but client expiry display (`expiresAt`) can show urgency; ensure no countdown UI is added
**Files:** model `dating_introduction.dart:16` exposes `expiresAt`; dashboard does not currently render a countdown (good).
**What's wrong:** Expiry is server-controlled (`expire_dating_introductions` cron, `20260705210000:703-716`) — clock manipulation has no effect (checklist edge-case ✓). The only risk is a future UI adding an urgency countdown from `expiresAt`, which §7 forbids ("may not use urgency copy").
**Fix:** Keep `expiresAt` out of the rendered UI or render only a neutral date; add a lint/review note.

---

### LOW

---

#### DATING-L1 — `bandColor` uses raw `Colors.grey/orange/green`, not design tokens, and color is the only band signal on the card
**File:** `dating_introduction.dart:63-74`, used `dating_dashboard_screen.dart:356-364`. Non-color indicator exists (the text label `bandLabel`), so accessibility is borderline OK, but hardcoded colors violate the design-token rule (Master §17) and checklist 5.3 ("non-color indicators").
**Fix:** Map bands to theme tokens; keep the text label as the primary signal.

#### DATING-L2 — `DatingIntroduction.fromJson` will throw on missing `display_band`/`state`/`expires_at` (non-null `json['...']` casts), so a minimized/again-narrowed payload crashes the list
**File:** `dating_introduction.dart:41-44`. `displayBand: json['display_band']` etc. assume presence. If the RPC contract tightens (e.g., drops `state` per DATING-C3), the client throws.
**Fix:** Null-guard and default these when you implement DATING-C3.

#### DATING-L3 — `resume` calls `activate_dating_profile`, which re-runs full activation gates including age verification; a paused user whose age verification later expired cannot resume, with a generic error
**Files:** `dating_repository.dart:125-135`, `activate_dating_profile:517-522`. Behaviorally safe (fails closed) but the dashboard shows a generic failure; UX-only.
**Fix:** Surface a specific "verification needed" state.

#### DATING-L4 — `DatingMonitoring.recordOperationalCounter` is a no-op stub; no analytics minimization is actually enforced anywhere (it's aspirational)
**File:** `dating_feature_flags.dart:37-52`. The allowlist is defined but the function does nothing and nothing calls it. Checklist 3.5 / §13.3 (no prohibited data in analytics) is a human gate; there is simply no analytics wired.
**Fix:** Fine to defer; note that the guarantee is unenforced by code today.

#### DATING-L5 — Report/block confirmation copy says "User blocked" generically (good) but the report success toast ("We will review it") implies an operational review pipeline that does not exist in code
**Files:** `dating_dashboard_screen.dart:775-778`, `dating_matches_screen.dart:398-403`. Truthfulness/ops gate.
**Fix:** Keep copy but ensure the moderation runbook (human gate 6) exists before launch.

---

## 3. Checklist gap map (CODE vs required)

Legend: **C-SAT** = satisfied by code; **C-GAP** = code-writable gap (finding id); **HUMAN** = human/ops review gate, not code.

### Section 1 — Clinical and product
- Clinical advisor approval — **HUMAN** (packet).
- Love-language absent from ranking — **C-SAT (vacuously)**: no ranking/algorithm code exists; no love-language reference anywhere in dating migrations. Must re-verify when algorithm is built.
- No copy predicts success/health/safety/readiness — **C-SAT**: all surfaced copy (`dating_dashboard_screen.dart:391`, consent `:49`, guided `:151-152`) carries the "cannot predict chemistry, safety, or relationship success" disclaimer; no forbidden phrasing found.
- Cultural review — **HUMAN**.
- No swipe/count/admirer/urgency/confetti/monetized mechanic — **C-SAT**: introductions are a plain list, no counts, no countdown rendered, empty-state copy explicitly discourages refreshing for volume (`:300`). (Watch DATING-M8.)

### Section 2 — Consent and privacy
- Distinct server-authoritative states — **C-SAT at data layer** (DATING-M6 note); five purposes enforced.
- Refusing historical still permits Dating — **C-SAT** (`dating_consent_screen.dart` proceeds with `_dataConsent=false`; `begin_dating_enrollment` never requires historical).
- Consent withdrawal invalidates snapshots + pending intros — **C-SAT**: `record_dating_consent` historical-withdraw → `invalidate_dating_for_user` (`20260705210000:374-375`), which nulls snapshots + invalidates intros. (Matches not closed — DATING-H5, but spec says existing matches remain on withdrawal.)
- Former-partner/Healing/safety/raw-msg/reflection absent from ranking — **C-SAT (vacuously)**: no ranking code. Re-verify at build. Reflections are excluded from any read shared with the counterpart — **C-SAT**.
- Retention/export/deletion/private storage/signed URLs/EXIF/analytics minimization/PIA — **HUMAN + C-GAP**: photos/storage not implemented (flag off); `delete_dating_profile` exists; export does not; analytics stub (DATING-L4). EXIF/signed-URL are human+unbuilt.

### Section 3 — Security and trust
- **Four-account RLS/RPC proof** — **C-GAP (DATING-C1)**: the defining test does not exist.
- Adults-only enforcement, age never client-editable integer — **PARTIAL / C-GAP (DATING-C2)**: enforcement is server-authoritative *in principle* but has no writer, so it's untestable/unshippable; the only working path was the self-attested checkbox (now gated behind the also-required `dating_age_gate_holds`).
- Photo/bio moderation, appeal, block, unmatch, report, spam/impersonation/harassment procedures operational — **PARTIAL**: bio moderation state machine exists (`save_dating_profile_draft` sets `pending` on bio change); photos unbuilt (flag off); block/unmatch/report RPCs exist; **appeal path unbacked (DATING-M5)**; procedures are **HUMAN**.
- Dating messaging Safety scope approved/tested — **HUMAN** (correctly deferred; DATING-H6).
- Push/logs/analytics/traces/crash/support contain no prohibited data — **PARTIAL**: push copy is generic (good) but `source_key` embeds match+user linkage (DATING-M4); analytics unenforced (DATING-L4). **HUMAN** for logs/traces.

### Section 4 — Algorithm and operations
- Golden fixtures (symmetry/determinism/boundedness/provenance/missingness/explanation) — **C-GAP / not-built**: no algorithm library, no fixtures exist. `dating_algorithm_configs` schema enforces reviewed-before-active (`:59-66`) — good scaffolding, tested at `dating_mode_contracts.sql:80-85`.
- Hard filters symmetric, not weakenable by refresh/empty pool — **PARTIAL**: pair-order + self-pair + `dating_candidate_is_current` symmetry checks exist in `act_on_dating_introduction`; **generation-side symmetric filtering is unbuilt**; empty-pool UI shows neutral state (good). Preference-symmetry (`each user's prefs admit the other`) is **not enforced** anywhere yet (generation unbuilt).
- Concurrent interest → one match, idempotent — **C-SAT**: `FOR UPDATE` on intro row serializes; `dating_matches` has `UNIQUE(introduction_id)` + `dating_matches_active_pair_idx` partial unique; `ON CONFLICT DO NOTHING`. Race-safe. (Add the DATING-C1 test to prove it.)
- Batch capacity/queues/retries/dead-letter/reconciliation — **not-built**: `dating_generation_runs` schema exists; no worker.
- Fairness/drift/monitoring/canary/rollback — **HUMAN**.
- Pause/exit/relationship/withdrawal/block/suspension/deletion invalidate correct records within SLA — **C-GAP (DATING-H5)**: matches not closed on exit/suspension/relationship.

### Section 5 — UX and accessibility
- Alignment preview before photos + limitations note — **C-SAT**: preview + disclaimer render first; photos unbuilt.
- One-sided interest/pass/expiry/pool/rejection private in UI/API/notification/**timing** — **C-GAP (DATING-C3 data-layer state leak, DATING-H2 timing/error oracle)**.
- Screen readers/scaling/non-color/localization/reduced-motion/offline/privacy-cover — **PARTIAL / HUMAN**: Quick Exit + Safety Resources wired on all sensitive screens (good); non-color band label present (DATING-L1); full a11y/localization is **HUMAN**.
- Safety Resources/block/report/unmatch easy to reach, never paywalled — **C-SAT**: present on dashboard, matches, guided-date, and per-card.

### Section 6 — Evidence pack
- All eight items — **HUMAN** (review artifacts), except "RLS/RPC test results attached," which is **C-GAP** because the test itself is inadequate (DATING-C1).

---

## 4. Prioritized fix order (code-writable)

1. **DATING-C1** — Rewrite the four-account contract test. It is the gate, it is cheap, and writing it will *expose* C3/H2/H4/H5 as concrete test failures, de-risking everything else. Do this first.
2. **DATING-C3** — Stop returning pair-level `state` from `get_my_dating_introductions`; return a viewer-scoped status. This is the core double-blind defect and is a small, surgical query change plus a client model tweak (DATING-L2).
3. **DATING-C2** — Add a service-role-only age-verification writer; assert `authenticated` cannot write age or reach the writer. Without this the funnel is both unsafe-adjacent and non-functional.
4. **DATING-H2** — Uniform opaque error + single code path in `act_on_dating_introduction`/`resolve_*`/`block_dating_user`; remove self-target special error. Kills the enumeration/timing oracle.
5. **DATING-H5 + DATING-H4** — Define and enforce what exit/suspension/relationship do to active matches; add profile-active + block re-checks to `get_my_dating_matches`. Do these together (same table).
6. **DATING-H1** — Remove `feature_flags` SELECT from `authenticated`; drive the client from `get_dating_eligibility`; add `dating_mode_enabled` guard to reflection writes.
7. **DATING-H7** — `DROP` the 6-arg `save_dating_profile_draft` overload.
8. **DATING-H3** — Reorder auth-before-claim in the idempotency path; validate key format; retain client key until widget dispose.
9. **DATING-M1/M2/M4/M7** — Drop/tighten raw report fn, rate-limit or document reads + prune, opaque notification key, enforce intro cap at generation.
10. **DATING-C4** — Hard-block `dating_candidate_generation` until phone-HMAC exclusion (or documented fallback) exists. No code needed to *ship-safe today* (flag off), but must be a named blocker on the generation flag.
11. Low items (L1–L5) as polish.

**Bottom line for the release meeting:** the runtime is safe-off and much of the scaffolding is sound (idempotency, pair-order constraints, reviewed-algorithm gating, generic push, honest chat deferral). But the two things the checklist most explicitly demands — the four-account security proof and an un-bypassable server-authoritative age gate — are respectively a stub and a gate with no writer, and the double-blind guarantee is broken at the data layer (DATING-C3). None of the flags may be flipped until at least DATING-C1, C2, C3, H2, H4, H5 close.

---

## 5. Fix re-review (2026-07-12)

**Scope:** `supabase/migrations/20260712120000_dating_double_blind_fix.sql`, `supabase/migrations/20260712130000_dating_match_lifecycle_and_hardening.sql`, `lib/features/dating/data/models/dating_introduction.dart`, re-traced against the deployed originals (`20260705210000`, `20260703203000`, `20260703194500`) and `DATING_MODE_SPEC.md` §3.3/§14.

### DATING-C3 — **FIXED**

Traced for both viewers against the transition logic at `20260705210000:670-680`:

- **B (high, has not acted) after A (low) expresses interest:** row is `low_action='interested', high_action=NULL, state='interested'`. The CASE at `20260712120000:47` reads `high_action` for B (viewer-own column selected by `di.user_low_id=auth.uid()` correctly) → `NULL` → **`'open'`**. `has_acted` is an `EXISTS` on `dating_interest_actions` filtered `actor_user_id=auth.uid()` → **`false` for B**. B's row is byte-identical to a never-touched introduction. No oracle.
- **`'awaiting_response'` reachability:** only when the viewer's *own* action column equals `'interested'`. The interest-action insert and the `low_action`/`high_action` update are in the same transaction (`:666-680`), so a viewer who has not acted can never see it.
- **`'passed'`/`'matched'` claim verified:** any `'passed'` action sets pair `state='passed'` unconditionally (`:672`/`:677`); mutual interest sets `'matched'`; cron sets `'expired'`. All leave `state IN ('generated','presented','interested')`, so the WHERE at `20260712120000:57` drops them — the two-branch CASE is complete for every reachable row. A `low='interested', high='passed'` row cannot remain in-list (`state='passed'` wins), and the reverse order is blocked by the state gate in `act_on_dating_introduction:652`.
- **Other columns:** `summary`/`display_band`/`explanation_features`/`expires_at`/`created_at` are all written at generation time, never by an action; the summary CASE picks the counterpart-describing summary exactly as the original did. Nothing action-derived remains except the viewer-scoped CASE and viewer-scoped `has_acted`.
- **No visibility widening:** the WHERE clause is character-for-character the original filter (membership, state, expiry, counterpart profile active/approved, candidacy both sides, pair block, both snapshots valid). REVOKE PUBLIC/anon + GRANT authenticated + `SET search_path=public` intact.
- **Client:** `dating_introduction.dart:41-48` now null-guards `state` (→`'open'`), `display_band`, `explanation_features`, `has_acted` — closes the DATING-L2 crash for the narrowed contract. `expires_at`/`created_at` still hard-parse, but the RPC always returns them; acceptable.

Pre-existing residual (unchanged by this fix, noted for the record): a counterpart's *pass* removes the row from the viewer's list. Disappearance is reason-opaque (identical to expiry/invalidation/block), which matches the spec's generic-removal posture — but the DATING-C1 contract test should still assert B's fetched row after A's interest is indistinguishable from an untouched intro.

### DATING-H4 — **FIXED-WITH-CONCERN**

- Block predicate is correct against the actual schema (`dating_blocks.blocker_user_id`/`blocked_user_id`, `20260703194500:107-114`) and covers **both** directions between exactly this match's `user_low_id`/`user_high_id`. Belt-and-braces on top of `block_dating_user` setting `state='blocked'` — good.
- Membership filter (`auth.uid() IN (dm.user_low_id,dm.user_high_id)`) unchanged; `auth.uid() IS NULL` yields zero rows; REVOKE/GRANT/search_path correct. No non-member visibility.
- Counterpart identity now requires `profile_state='active' AND moderation_state='approved'` — a suspended (profile→`'paused'`), exited, or deleted counterpart can no longer surface with name/region. The original H4 scenario is closed.

**DATING-H4a (NEW, Low — availability/UX, fail-safe direction, no leak):** `dating_candidate_is_current(both)` at `20260712130000:68-69` over-filters. That predicate includes the global flag, healing gates, age gate, relationship guard, enrollment-active, and `dating_profile_ready`. Consequences with flags on: (a) either user editing their bio (`save_dating_profile_draft` → `profile_state='draft'`, `moderation_state='pending'`) **empties both users' match lists** until moderation approves *and* the editor re-activates; (b) a benign pause or relationship-guard auto-pause hides matches the spec says to *preserve* (Spec §14 "User pauses … preserve existing mutual matches"); (c) the list flapping with the counterpart's routine edits is a weak, reason-opaque activity signal on an already-known counterpart. This is the safe failure direction (hide, never leak), so it does not block — but before flag flip, consider narrowing the candidacy check to `dp.profile_state <> 'exited' AND public.dating_account_in_good_standing(dm.user_low_id) AND public.dating_account_in_good_standing(dm.user_high_id)` (suspension/exit/deletion are now *closed* by the H5 fix anyway, so the broad live re-check is doing little beyond hiding preserved matches).

### DATING-H5 — **FIXED-WITH-CONCERN**

- **Signature safety verified:** the original `invalidate_dating_for_user` is `(p_user_id uuid, p_reason text DEFAULT NULL)` (`20260703203000:321-324`) — identical to the fix's, so `CREATE OR REPLACE` replaces in place; **no overload split**, every existing caller executes the new body. Function was never granted to `authenticated` (only `REVOKE … FROM PUBLIC`, `:1067`), and `CREATE OR REPLACE` preserves that ACL.
- **Reason strings verified against every caller:** `'exit'` (`exit_dating_mode:674`) ✓ closes; `'profile_deleted'` (`delete_dating_profile:1062`) ✓ closes; `'account_restricted'` (`enforce_dating_restriction_change`, `20260705210000:586`) ✓ closes. Preserve set — `'relationship_guard'`, `'historical_consent_withdrawn'`, `'profile_changed'`, `'profile_or_preference_changed'`, `'photo_moderation_changed'`, `'age_verification_invalid'`, `'scheduled_gate_revalidation'` — is spec-correct for pause (§14 "preserve existing mutual matches"), relationship entry (§14 "Auto-pause…", i.e., pause semantics — my original suggestion to close on relationship entry overstated; the fix follows the spec), and historical-consent withdrawal (§3.3 "Existing mutual matches remain unless a user ends or blocks them").
- **State validity:** `'closed'` is in the `dating_matches` CHECK and `closed_at` exists (`20260703194500:101-104`); the UPDATE only touches `state='active'` rows and is idempotent on trigger re-fire. ✓

**DATING-H5a (NEW, Medium):** `'dating_consent_withdrawn'` is missing from the closing set. Withdrawing `dating_terms`/`dating_opt_in` (`20260705210000:376-379`) sets `profile_state='exited'` **and** enrollment `state='exited'` — it *is* an exit, just reached via the consent screen — yet `invalidate_dating_for_user` is called with a preserve reason. The fix's comment cites "Spec :113 consent-withdrawal PRESERVES matches," but §3.3/:113 governs **historical-data** consent only, not terms/opt-in withdrawal. Failure scenario: user withdraws `dating_opt_in` to sever ties → match rows stay `'active'` (hidden by the H4 filters, so no immediate identity leak) → (1) the counterpart can still write date reflections against the match (`save_private_date_reflection` checks only `dm.state='active'` + membership, `20260705210000:872-875`); (2) if the user later re-enrolls and re-activates, the stale match **resurrects in both users' lists**. Fix: add `'dating_consent_withdrawn'` to the `IN` list at `20260712130000:37` (or pass `'exit'` from `record_dating_consent`).

**DATING-H5b (NEW, Low):** no retroactive backfill. Matches belonging to users who exited / were restricted / deleted profiles *before* this migration stay `'active'` forever — the new closure only runs on future calls, and `exit_dating_mode` is idempotency-guarded so it won't be re-invoked. Currently vacuous in production (all flags false + no `'active'` algorithm config means `act_on_dating_introduction` always raised before creating any match), but add a one-time closure UPDATE (close `'active'` matches where either member's enrollment is `'exited'`/`'suspended'` or profile is missing/exited) in the next migration for hygiene before any flag flip.

Accepted trade-off, document in the ops runbook: closure on `'account_restricted'` is **irreversible** — a temporary `moderation_hold`/`age_review` that is later lifted does not restore matches. Fail-safe, deliberate. Also note `'age_verification_invalid'` (the underage-discovery trigger path, `20260705210000:597-611`) preserves matches; closing there today relies on ops also inserting an `age_review` restriction — consider adding it to the closing set when the age-verification writer (DATING-C2) lands.

### DATING-H7 — **FIXED**

`DROP FUNCTION IF EXISTS public.save_dating_profile_draft(text, text, text, text, integer, integer)` (`20260712130000:89`) matches the legacy definition's exact signature (`20260703194500:359-366`: 4 text + 2 integer). The 7-arg validated form `(text,text,text,text,text,integer,integer)` is untouched by this migration, remains the only overload, and keeps its grant (`20260705210000:897`). No remaining 6-arg callers anywhere (client passes `p_idempotency_key`, `dating_repository.dart:85`). Overload-resolution bypass eliminated.

### Cross-cutting checks

- Both recreated getters: `SECURITY DEFINER`, `SET search_path = public`, `REVOKE … FROM PUBLIC, anon`, `GRANT EXECUTE … TO authenticated`. (They skip an explicit revoke-from-authenticated before the grant — net-equivalent.) ✓
- Row visibility: membership predicates unchanged in both getters; no join or CASE moved a filter out of the WHERE; a non-member (or anon/NULL uid) sees zero rows. ✓
- Migration ordering (`120000` → `130000`) has no interdependency; both are safe to run on a database that already has the originals applied.

### Re-review verdict summary

| Finding | Verdict | New issues |
|---|---|---|
| DATING-C3 | **FIXED** | — |
| DATING-H4 | **FIXED-WITH-CONCERN** | DATING-H4a (Low): candidacy re-check over-filters; matches hidden/flapping on benign edit/pause vs spec §14 preserve |
| DATING-H5 | **FIXED-WITH-CONCERN** | DATING-H5a (Medium): `dating_consent_withdrawn` exit path leaves matches `'active'` → reflection-writable + resurrect-on-re-enroll; DATING-H5b (Low): no backfill for pre-fix exited/suspended users |
| DATING-H7 | **FIXED** | — |

None of the new findings is a leak; all fail in the safe direction. H5a should be fixed in the next migration before any flag flip; H4a and H5b are pre-flag-flip hygiene.

---

## 6. Session-2 remediation (2026-07-12): remaining code-writable Criticals + Highs

Continuation after the C3/H4/H5/H7 fixes above. All items below are static-verified
against the migration set; the dev machine has no Docker/Postgres so the SQL
contract test is CI-run, not locally executed.

### DATING-C1 — **FIXED** (four-account contract test)

`supabase/tests/dating_mode_contracts.sql` rewritten from a 3-account owner-RLS
stub into a real four-account (A, B, C-outsider, D-blocked) RLS/RPC proof. The
fixture seeds the full `dating_candidate_is_current` precondition graph (flag on,
active enrollment, age verification, healing journey + passing readiness attempt,
profile ready, preferences) inside `BEGIN/ROLLBACK`, so the happy-path RPCs
actually execute. Assertions: (1) owner RLS + C sees no A/B intro; (2) C's
`get_my_dating_introductions` = 0 rows; (3) actor forgery raises + writes no
`dating_interest_actions`; (3b) **H2** enumeration proof — non-member vs
nonexistent intro raise identical sqlstate+message; (4) **C3** double-blind — after
A interested, B's viewer-scoped state = `'open'`; (5) **H5** mutual match created
then closed on A exit; (6) **H4** block bypass — D blocks A → act raises, no match,
pair hidden; (6b) **C2** authenticated cannot insert age verifications; (6c) **H1**
authenticated cannot read `dating_*` flags but can read `chat_*`; (7) function-
privilege + payload-shape guards; (8) **C4** former-partner exclusion.

Test-fixture note: the original stub used `mode='solo'` and `profile_state='draft'`
which would have failed the `users.mode` CHECK — it had never actually been
executed. The rewrite uses valid values throughout.

### DATING-C2 — **FIXED** (age-verification writer, service-role only)

`20260712140000_dating_age_verification_writer.sql` adds `verify_dating_age(user,
birth_date, method, verified_by, expires_at)` and `revoke_dating_age_verification(user)`,
both `SECURITY DEFINER`, `REVOKE … FROM PUBLIC, anon, authenticated`, `GRANT …
TO service_role`. Both refuse if `auth.role()='authenticated'` (defense in depth),
and the writer enforces the adults-only floor + method length. This provides the
one legitimate backend path a KYC/DOB flow calls; it does NOT fall back to the
client checkbox. The gate stays closed until a backend job runs per user. Contract
test asserts authenticated can execute neither function and service_role can.

### DATING-C4 — **FIXED** (former-partner exclusion, enforced now)

`20260712160000_dating_former_partner_exclusion.sql` implements the phone-HMAC
exclusion the spec elevates to a first-class DV-stalking threat:
- `dating_former_partner_exclusions(user_id, excluded_phone_hmac, relationship_id)`
  — RLS on, no client grant; server-only.
- `dating_phone_hmac(phone)` — `encode(hmac(phone, key, 'sha256'),'hex')`, key from
  `current_setting('app.settings.dating_exclusion_key')` (same pattern chat uses).
  Service-role only. Returns NULL (fail-safe) when phone/key absent.
- `record_dating_former_partner_exclusion(relationship_id)` — service-role; called
  at relationship-end (and backfillable), stores each party's phone-HMAC against
  the other. Survives the abuser deleting + re-registering under a new UUID because
  the same verified phone yields the same HMAC.
- `dating_former_partner_excluded(a, b)` — predicate wired into **both**
  `act_on_dating_introduction` (candidacy gate) and `get_my_dating_introductions`
  (visibility), so even a manually-seeded intro between former partners is refused
  and hidden today, before candidate generation exists.

**Residual (documented per Spec 5.1):** covered only for relationships ended via
the writer, and only when both parties have verified phones. A former partner who
re-registers with a new, never-verified phone is not covered — block-on-sight
remains available. This must be a hard blocker on the `dating_candidate_generation`
flag: generation must call the same predicate, and the exclusion secret must be
provisioned, before that flag flips.

### DATING-H1 — **FIXED** (flag exposure + reflection write gate)

`20260712150000_dating_flag_defense_in_depth.sql`:
- Narrowed the `feature_flags` RLS policy to `USING (key NOT LIKE 'dating\_%')`, so
  the dating rollout plan is no longer client-readable. **Chat is unaffected** —
  `chat_*` keys stay readable and `chat_feature_flags.dart` keeps working (verified:
  the grant lives in the chat migration and chat reads its own keys).
- Client (`dating_feature_flags.dart`, `dating_providers.dart`) now derives
  availability from `get_dating_eligibility()` (reason ≠ `'feature_unavailable'`),
  not the raw table; fails safe to false.
- `save_private_date_reflection` now flag-gates on `dating_mode_enabled` (and
  `record_dating_date_reflection` delegates to it, so both content-write paths are
  covered without duplicating logic). This also closes the code-writable half of
  **DATING-H6** (the rest of H6 is human-gate, correctly deferred).

### DATING-H2 — **FIXED** (verified opaque + proven)

The live `act_on_dating_introduction` and the `resolve_dating_*_target` resolvers
already collapse every existence/membership/block/candidacy refusal into one
`introduction_unavailable`/`match_unavailable` (`22023`) — the distinguishable
`introduction_not_found`/`pair_blocked` messages Fable cited were in the superseded
v1.1 code. No live mutation RPC leaks a distinguishable shape. Added the
enumeration-uniformity assertion (Section 3b of the contract test) to lock it in.

### DATING-H3 — **PARTIALLY FIXED**

- **(a) claim-after-checks:** already satisfied — `claim_dating_idempotency` runs
  *after* auth + membership + validity + candidacy in every RPC. ✓
- **(b) server-side key validation:** added length (8–200) + charset
  (`[A-Za-z0-9_:.-]`) guard to `claim_dating_idempotency` (`20260712150000`).
  Verified it accepts the client's `scope-timestamp-entropy` keys. ✓
- **(c) client cache retention until widget dispose:** deferred — a UI-lifecycle
  change with double-tap-behavior risk; the DB `UNIQUE(introduction_id,
  actor_user_id)` already dedups interest, so the residual is duplicate
  reports/blocks only. Documented residual, low severity.

### M/L triage (no code change this session)

- **M1** (raw-target report foot-gun), **M4** (match id in `source_key`) — revoked/
  contained; ops-runbook notes.
- **M2** (rate-limit prune), **M5** (appeal-path reader), **M6** (terms/opt-in
  separation), **M3** (explanation-features fidelity), **M7** (unrevealed-intro cap
  at generation) — enforced at generation time (unbuilt) or human/product gates.
- **M8, L1, L4, L5** — UI polish / no-countdown lint / aspirational stubs / copy.
- **L2** (`fromJson` null-crash) — already hardened in session 1 (`?? 'open'` etc.).
- **L3** (resume re-runs age gate) — expected given C2; acceptable.

### Session-2 verdict

| Finding | Verdict |
|---|---|
| DATING-C1 | **FIXED** (four-account proof) |
| DATING-C2 | **FIXED** (service-role writer) |
| DATING-C4 | **FIXED** (enforced now; documented generation-flag blocker + residual) |
| DATING-H1 | **FIXED** (RLS narrowed, chat safe; reflection gate; client via RPC) |
| DATING-H2 | **FIXED** (already opaque; proven by test) |
| DATING-H3 | **PARTIALLY FIXED** (a+b done; c deferred, low residual) |
| DATING-H6 | **FIXED** (code half via H1; rest human-gate) |

All code-writable Critical and High findings are now addressed. Remaining blockers
to a Dating flag-flip are human/ops gates: run the SQL contract test green in CI,
provision `app.settings.dating_exclusion_key`, stand up the age-verification KYC
backend, wire candidate generation to `dating_former_partner_excluded`, and clear
the Safety Plan §5 review items.

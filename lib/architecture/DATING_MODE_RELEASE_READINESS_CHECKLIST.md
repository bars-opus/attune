# Dating Mode release readiness checklist

**Status:** replaced in Spec 2 W10 (2026-11-24). Source:
`docs/superpowers/specs/2026-10-24-dating-mode-design.md` §8 (every wave's
gate line and W10's), §7.7 (the device matrix). The spec wins.

## 1. What `get_dating_launch_readiness()` checks

Run `select public.get_dating_launch_readiness();` (Ghana and the UK) or
`select public.get_dating_launch_readiness('GH');` (any one country) as the
owner, or open Launch readiness in the console (which can also check one
country). `ready` is true only when every gate is
green; it is never true while the project reads development. "Real" below
means not blank and not `DEV-` (`DATING_MODE_REVIEW_AND_GATES.md`, "What
reads as `DEV-`").

| Gate | Green when |
|---|---|
| `environment` | the project reads production (the owner set it) |
| `age_assurance_live` | `age_assurance_mode` is `live` |
| `safety_owner`, `moderator` | an active safety owner and an active moderator (any languages: the Twi, Ga and Pidgin requirement is a human gate, §2) |
| `keys` | the exclusion and field keys match their fingerprints; the push key is set |
| `introductions_config` | an introductions config is active, every active one with four real review references |
| `chat_config` | a chat safety config is active, every active one with a real review reference |
| `flag_evidence` | every launch flag (`dating_mode_enabled`, `dating_candidate_generation`, `dating_match_messaging`, `dating_profile_photos`, `dating_same_gender_matching`, `dating_age_assurance`, `dating_traveller_detection`, `dating_couple_link`, `support_resources_v2`, `csam_hash_matching`) has its gate row with real evidence |
| `no_flag_violations` | no gated flag of any spec is on without real evidence: the eight Dating flags and Spec 1's eleven (`couple_profile`, `flow_signin_v2`, `flow_paths_v2`, `dormancy_rule`, `platform_age_signals`, `opinions_safety_v1`, `journal_ai_insights`, `healing_ai_insights`, `text_scale_v2`, `csam_hash_matching`, `support_resources_v2`) |
| `no_test_verifications` | no age or identity pass from the fake providers still stands |
| `kill_switch_clear` | no same-gender switch-off is pending |
| `log_settings_safe` | the database logs keep no request values |
| `sla_alerts` | `moderation_alert_webhook` is set |
| `checklist:GH`, `checklist:GB` | the checklist holds the four baseline keys (`dpia`, `pen_test`, `safety_owner_and_moderator`, `reviewer_signoffs`), every key has a real reference, and a Tier 1 or 2 country with same-gender on has its same-gender reconsideration |
| `resources:GH`, `resources:GB` | the country's resources were verified within 90 days, and every active support resource for it too (at least one) |

The console shows each gate in words, and each red check in words too
(for example `dev_reference` reads "a DEV- reference is still in the
checklist"). While the project reads development it adds a calm note that
not being ready is expected there. In production, a country open while
any gate is red is said in red: close it from Countries.

## 2. What only people can do (record each as a reference)

- [ ] Ghana: the legal opinion on the reconsidered bill (`ghana_legal_opinion`); DPC registration (`dpc_registration`).
- [ ] UK: the OSA illegal-harms and children's-access assessments (`osa_illegal_harms_assessment`, `osa_childrens_access_assessment`); highly effective age assurance (`highly_effective_age_assurance`); a UK representative if the controller is outside the UK (add a `uk_representative` key to GB's checklist from the console if counsel says it applies).
- [ ] Both: the DPIA signed (`dpia`); the external penetration test passed with no open High or Critical (`pen_test`); the safety owner and a moderator who reads Twi, Ga and Pidgin named, trained and live, with out-of-hours P0 cover (`safety_owner_and_moderator`; the `moderator` gate checks only that one is active, not their languages); the clinician, cultural (with faith advisers), LGBTQ+ and DV reviewers' sign-offs (`reviewer_signoffs`).
- [ ] Each flag's gate line (`private.flag_production_gates.gate`) met, then `record_flag_gate_evidence`.
- [ ] The §7.7 device matrix on release builds; the runbook drills (`DATING_MODERATION_RUNBOOK.md` §14).
- [ ] The store listing and Welcome copy "Dating open in Ghana and the UK" (with Spec 1).
- [ ] Smoke tests on this project once it reads production, with test accounts: introductions, chat, report, appeal, exit, export; then those accounts exited.

## 3. Switch-on (the owner's)

**The launch project is the current hosted project** (owner, 2026-11-23):
there is no separate production project. Until launch it stays in
development mode with every Dating and traveller flag on, for testing and
demos to advisors; nothing below is done until the launch itself.

**Clean-up, while the project still reads development:**

1. Every item in §2 recorded; every deploy done.
2. Turn Dating off from the SQL editor:
   `update public.feature_flags set enabled = false where key = 'dating_mode_enabled';`
   Never a `like 'dating%'` update: switching `dating_same_gender_matching`
   off runs the same-gender purge through its trigger.
3. Close Ghana, the UK and any other open country from the console
   (Countries → Publish `{"dating_enabled": false}`).
4. Exit or delete every test and demo account.
5. Replace every `DEV-` reference with a real one: a new introductions
   config version activated with four real references, the chat config
   with the reviewers' reference, each flag's evidence
   (`select public.record_flag_gate_evidence('<flag>', '<where the signed document lives>');`),
   and each country's checklist (published from the console). After
   activating a config, check that Launch readiness reads it green (the
   configs' own triggers read `DEV-` in plain ASCII only).
6. **Every gated flag that is on, whatever spec turned it on**, has real
   evidence, or is turned off, or stays on knowing it blocks every Dating
   opening (`no_flag_violations`). The development scripts turn on more
   than Dating's: `supabase/sql/dev_enable_spec2_dating_flags.sql` the
   Dating flags, and `supabase/sql/dev_enable_spec1_flags.sql` eleven gated
   Spec 1 flags (`couple_profile`, `flow_signin_v2`, `flow_paths_v2`,
   `dormancy_rule`, `platform_age_signals`, `opinions_safety_v1`,
   `journal_ai_insights`, `healing_ai_insights`, `text_scale_v2`,
   `csam_hash_matching`, `support_resources_v2`). Turning a couples feature
   off switches it off for real couples, and in production it can't come
   back on without real evidence, so record the evidence first where you
   can. `select * from public.production_flag_violations();` lists what is
   left (it reports in development too). Never run the development
   scripts here again (they refuse in production mode anyway).
7. Age assurance live, with the vendors contracted. The development script
   put `sandbox` in Vault, and Vault wins over any setting:
   `select vault.update_secret((select id from vault.secrets where name = 'age_assurance_mode'), 'live');`
8. Revoke every verification made before the flip (sandbox passes can't be
   told from live ones), now, after step 7, so none is made in between:
   `select public.revoke_dating_age_verification(v.user_id, 'pre_launch') from public.dating_age_verifications as v where v.revoked_at is null;`
   A row can answer `busy`: run it again until
   `select count(*) from public.dating_age_verifications where revoked_at is null;`
   reads 0.
9. **Precondition for the flip:** `select public.get_dating_launch_readiness() -> 'open';`
   reads `[]` and `select enabled from public.feature_flags where key = 'dating_mode_enabled';`
   reads false. The flip itself opens nothing and runs no gate, so a
   country still open stays open in production, with whatever stood in
   development. Don't go on until both hold.

**Then:**

10. Set the project to production mode **in Vault only** (the owner's
    alone): `select vault.create_secret('production', 'attune_environment');`
    (or `vault.update_secret` on it if the secret exists). Never by
    `ALTER DATABASE … SET`: a setting reaches only new sessions, so the
    API's pooled connections could still read development and publish
    without the production checks.
11. Confirm the console's Launch readiness (it reads through the API, not
    the SQL editor) shows production: the development note is gone. Then
    `select public.get_dating_launch_readiness();` and
    `select * from public.production_flag_violations();`: fix anything red.
12. Turn the flags on (each needs its evidence).
13. Open each country from the console (Countries → Publish
    `{"dating_enabled": true}`); a red gate refuses the opening, and also a
    later same-gender switch-on or a looser tier. A publish line that says
    "(development)" means the API still reads development: close the
    country again and go back to step 10.
14. Smoke tests with test accounts (§2), then exit those accounts.
15. After launch: keep an active safety owner and moderator. The gates
    check them at every opening only; deactivating the last one leaves an
    open country open (Launch readiness turns red, nothing alerts).

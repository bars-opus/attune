# Dating Mode: data protection impact assessment (DPIA)

**Status:** started in Spec 2 W1a (2026-11-06); a working draft, not signed. Spec 2 W10 needs it signed by counsel and the owner before Dating is switched on in production. **Owner:** the safety owner. **Source:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` §6.8, §4.1-§4.3, §4.8; owner rulings Q4, Q5, Q16, Q17 (with the three exceptions for sign-off, R-2) and Q19b.

Every row below says what the built system does as of the batch named, so the assessment follows the code. A row marked **(open)** waits for the person named.

## 1. Processing

| Point | Answer |
|---|---|
| Purposes | Introductions between consenting adults; safety and enforcement; legal compliance. |
| Data subjects | Adults (18+ by Spec 1's date of birth, assured by liveness and facial age estimation from W4) who set up Dating; the people they block, report or list under "Never introduce me" (as phone HMACs only). |
| Categories | Identity and contact (phone, first name, age); profile (country, region, side, intention, children, prompts, photos); **special category**: gender identity, who you'd like to meet (reveals orientation, CJEU C-184/20), faith; **sensitive, not Art. 9**: marital history (owner ruling 2026-11-06, provisional until counsel confirms: not a GDPR Art. 9 category, so collected at D2 before the special-category consent, on the contract basis, and encrypted as defence in depth); **derived special category (S-5)**: introduction, interest-action, match and couple-link rows between two people, and a moderation case's routing (computed at read time, never stored); **biometric** at verification (transient, W4); messages (W6); safety and moderation records (W7). |
| Lawful basis | Explicit consent for special-category and biometric processing (GDPR / UK GDPR Art. 9(2)(a); Ghana Act 843 s.37 consent), recorded per purpose in `dating_consent_events` (`dating_terms`, `dating_opt_in`, `special_category_profile`, `special_category_faith`, `biometric_verification`); contract for the service; legitimate interests and legal obligation for safety and enforcement records. Withdrawing any consent is leaving Dating, except faith's: withdrawing `special_category_faith` clears only the faith answer and keeps the rest, as D8's Skip (owner ruling 2026-11-06; W1d). The consent time is the server's clock, never the app's (batch-6 M-12). **(open: counsel confirms each basis per country)** |

## 2. How it is stored (built in W1)

| Point | Answer |
|---|---|
| Encryption at rest | Gender identity, who you'd like to meet, faith and marital history are stored in `dating_profile_sensitive`, each value tagged with its key version and `pgp_sym_encrypt`ed (AES-256, a random session key per value, MDC integrity protection, compression off) with the Vault secret `dating_field_key` (W1c). In production the key is read from Vault only, never from a database setting (batch-6 fix round 1, M-4), so a dump or backup holds ciphertext and an encrypted key only. The key's fingerprint (an HMAC of a fixed label under it) is stored once by the owner; a replaced key is then refused for every write (no answers under two keys) and generation stops until the fingerprint matches (batch-6 M-5, W1d). Interim (plan P-22): until W5a, the v1 plaintext columns `dating_profiles.gender_identity` and `dating_preferences.gender_preferences` remain for the v1 hard filter (owner-only under RLS, readable by the service role); W5a drops them. |
| Who can read it | Nobody through the API: the table is revoked from `anon`, `authenticated` and `service_role`, and the two field functions are executable by no API role. Only definer functions decrypt (the own-profile reader, the setup writers, the kill switch; later generation, the export builder, the fairness job and the console's routing check). The CI canary (`dating_rls_canary.sql`) fails if any other service-role path can decrypt (S-4). |
| Pair data | `dating_introductions`, `dating_interest_actions` and `dating_matches` are revoked from `service_role` too (W1a); no edge function reads them. |
| Phone numbers | Every Dating phone HMAC comes from `auth.users.phone` (`dating_phone_hmac_for_user`, W1a), never from the client-writable mirror; a parked account uses the HMAC of its real number taken before the park (Spec 1 I-11). |
| Logs | `get_dating_operational_health().log_settings_safe` reports whether Postgres can log RPC parameters (W1d). It must read `true` on the production project (W1 gate). |
| Residual risks | A live `postgres`-level attacker can decrypt; VPNs hide travellers (W8); a real person can pass liveness and act in bad faith; third parties can relay what they see; a restriction placed while `dating_exclusion_key` was missing and never stamped afterwards (or on an account parked before the key existed) carries nothing at deletion (the deletion completes and counts `dating.deletion.uncarried` once, PF-F6); a person who changes number after being restricted is not followed onto the new number at deletion (the restriction carries under the number it was placed under, batch-3 I-1); an encrypted answer is not bound to its owner or column, so a `postgres`-level writer (or a faulty definer function) could copy or restore a value under another row and it would still decrypt (batch-6 M-6; no API role can write the table); a "Never introduce me" label (the owner's private note, at most 20 characters) can still spell about five digits in words, though labels refuse five or more digits in any script (batch-9 fix round 1, M-2), and no API role reads the list, the service role included (M-5); **`dating_exclusion_key` can't be rotated (W1 final fix, I-3):** never-introduce lists, restriction stamps and the carried records of deleted numbers hold HMACs only, so a new key would silently void every list (a person who listed an abuser's number could be introduced to them again, while the list still shows the label and the last two digits) and every restriction's stamp; it is never replaced or re-keyed, rotation waits for a verify-only secondary key (readers match either HMAC; a later wave), and a compromised key is handled as a personal-data incident, not a rotation (owner checklist item 11); **deletions refused while the key is missing (W1 final fix, M-4, PF-F6):** if `dating_exclusion_key` is missing on a project with live Dating restrictions, those people's account deletions are refused (`deletion:enforcement_key_missing`, counted in health as `deletions_refused_key_missing_7d`) until it is restored, which the owner does within days (erasure must complete within a month); any other failure to carry is counted and never refuses the deletion; **recycled numbers (W1 final fix, M-10; Spec 1 O3, Q5):** a deleted account's carried enforcement record is keyed to its number, so whoever holds that number next is refused Dating (`account_unavailable`, no reason given) by `dating_account_in_good_standing`, with no appeal until W7a turns the record into a `carried_over` restriction with one appeal; no country opens before that appeal exists (W10 gate, plan P-8). A parked account's live restrictions don't follow the number (O3: no), and never-introduce entries and exclusions keyed to a recycled number only stop introductions (§6.3 accepts that). |

## 3. Retention and what survives deletion

| Data | Kept | Then |
|---|---|---|
| Profile, preferences, sensitive answers, prompts, settings, photos (and unattached uploads, queued through the CSAM evidence guard), private reflections, introductions, session context, the country notice request | while Dating is set up | hard-deleted at exit (`exit_dating_mode`, or withdrawing a consent other than faith's, W1d) or account deletion; a suspension and the age assurance result stay |
| Conversations (matches now; messages from W6) | while active; after exit or deletion: sealed 30 days (`evidence_until`) | deleted (purge from W6c) — **Q17 exception 1 (open: counsel)** |
| "Never introduce me" list | while in Dating; at exit only if the person ticks "Keep my list" (unticked by default) | deleted with the account — **Q17 exception 2 (open: counsel)** |
| Consent events | the account's life + 1 year after exit (proof of consent and withdrawal; exit records a withdrawal of every standing consent, so coming back asks for each again, W1d) | deleted — **Q17 exception 3; the minimum is counsel's (open)** |
| Request de-duplication keys and rate-limit counters (`dating_rpc_idempotency`, `dating_rate_limits`: operation names, client keys, counts; no content) | kept at exit, so a late retry can't run twice | purged after a fixed window — **open: W6c's `purge_dating_retention` (batch-10 review M-10)** |
| Enforcement records (live restrictions at deletion), block pairs by HMAC | 2 years after the account's deletion (`purge_after`) | deleted — **Q5 (open: counsel confirms 2 years for Ghana and the UK)** |
| Reports (pseudonymised (HMAC): user ids set to NULL; the target's number kept only as its HMAC, re-identifiable with `dating_exclusion_key`; the category and the reporter's free-text details kept as evidence for a carried restriction — counsel decides whether W7a nulls details once the case closes) | 2 years | deleted |
| Former-partner exclusions (the deleted person's number as its HMAC, as recorded when the relationship ended — never the number held at deletion, batch-3 I-1 — kept against each ex who still has an account, so that ex is never introduced to the number) | while the ex's account exists (no 2-year bound) | deleted with the ex's account — **open: counsel (§7)** |
| Restriction stamps (`private.dating_restriction_hmacs`: each Dating restriction's number as its HMAC, recorded when the restriction is placed; the enforcement record is written under it, never under the number held at deletion, batch-3 I-1) | while the restriction exists | deleted with the restriction or the account; carried into the enforcement record above |
| Report evidence snapshots (W7a) | as long as an enforcement record they support | deleted with it — **(open, W7)** |
| Moderation cases and actions (W7b) | 2 years | deleted — **(open, W7)** |
| Law-enforcement request log (W7c) | 2 years | deleted — **(open, W7)** |
| Safety events | 90 days | stripped of identifiers per `SAFETY_SYSTEM_SPEC.md` §4.2 — **(open, W7)** |
| Verification sessions (W4) | 30 days | deleted — **(open, W4)** |
| Photos held for human review (W3c/W4) | at most 72 hours | deleted — **(open, W4)** |
| Introductions' actions and reasons (§6.8 minimisation) | until 30 days after the introduction is resolved | deleted (the introduction row keeps no reason) — **(open, W5)** |
| Age assurance result | while the account exists | deleted with the account |

The privacy policy must name the survivors (enforcement records, block pairs, pseudonymised (HMAC) reports with the reporter's details; 2 years; former-partner exclusions of the number recorded at the relationship's end, while the ex's account exists) — **open: counsel's wording, W1 gate**.

## 4. Minimisation

No GPS, distance or neighbourhood; region and an optional side only (others see the region, never the side). No ethnicity, tribe, income, job, education, politics, height, health or zodiac fields. Quiz, Healing and journal data are never read by Dating. Where same-gender introductions are off (Ghana and every Tier 1/2 country), the server refuses a same-gender answer without storing, counting or logging it, and the kill switch deletes such answers in one transaction when a country turns it off (W1d). No repeat-pair history is kept for deleted accounts.

## 5. Risks and controls

| Risk | Control (batch) |
|---|---|
| Outing and entrapment | same-gender off in Tier 1/2, nothing stored there, kill switch (W1b-W1d); traveller hiding (W8) |
| Compelled disclosure | minimal retention (above); law-enforcement policy (W7c) |
| Breach | field encryption, RLS and grant canaries, bucket test, secret scanning in CI (W1a), penetration test (W10) |
| Insider | no API role reads special-category data; console without sensitive fields, read-time routing and an append-only audit log (W7b) |
| Re-identification in thin pools | no side shown, no counts, metrics only at n >= 50 |
| Minors | Spec 1 DOB + age assurance (W4), holds, CSAM hash matching on every Dating photo before approval (W3c) |
| Biometric misuse | no templates, no kept videos or ID images; vendor deletion terms (W4 contracts) |
| Unfair exposure | fairness job (W5c) |

## 6. Transfers, registrations, rights

- **Transfers:** the Supabase project region; AWS Rekognition in an EU/UK region; the estimation and ID vendors' regions and retention, per contract (W4). **(open)**
- **Registrations:** Ghana DPC registration; a UK representative if the controller is outside the UK; an EU Art. 27 representative before any EU country opens. **(open: W10 gate)**
- **Rights:** export of one's own Dating data (W9); deletion (exit, account deletion); correction (DOB through Spec 1, everything else in Dating settings); withdrawal of consent = leaving Dating, except faith's, which clears only the faith answer (owner ruling 2026-11-06).
- **Rights of a recycled number's next holder (W1 final fix, M-10; Spec 1 O3):** until W7a, a person refused Dating because a carried enforcement record matches their number gets no reason and no appeal (the right to be informed and to contest). W7a turns the record into a `carried_over` restriction with its category and one appeal; Dating opens in no country before then (W10 gate). **(open: counsel, W7a)**
- **US (later):** BIPA written release, Texas CUBI consent, and a public retention and destruction schedule before any US user verifies.

## 7. Sign-off

| Who | What | Date | Reference |
|---|---|---|---|
| Counsel | retention (2 years), former-partner exclusions kept while the ex's account exists, consent minimum, Q17 exceptions, privacy-policy line | | |
| Counsel | lawful basis per country, transfers | | |
| Safety owner | risks and controls | | |
| Owner | accepts the residual risks | | |

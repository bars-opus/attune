# 10 — Risk scenarios: red-teaming the strawman flow and Dating Mode

**Researcher:** 10 (risk-scenario simulator) · **Date:** 2026-10-24 · **Programme:** Flow + Dating research (`BRIEF.md`)
**Scope:** a strawman built only from research 01–07's recommendations, attacked with 22 adversarial and high-risk scenarios. Each is walked through the real screens, RPCs and tables where they exist, and through the strawman where they don't yet. The repo was read-only: nothing was edited, formatted or committed. I wrote only this file.

---

## 0. The strawman under attack (v0, assembled from 01–07; not a decision)

1. **Welcome:** three paths, "18+, phone sign-in", guest Opinions behind a one-time 18+ self-declaration (05 §4.0 W1; 07 Impl 14).
2. **New account:** any-script name → DOB (3 fields, neutral, checked on device; under 18 → kind stop + 30-day local block) → phone (country from SIM) → code (SMS → voice → WhatsApp) → consent (EULA v2, 18+) → server writes DOB once (`set_my_birth_date`) → "What brings you to Attune?" (05 §4.0, §5.1; 06 §2.2.4 #1).
3. **Invitee:** link → same steps → DOB before `accept-invite`, which re-checks age server-side → linked, path preset to Relationship (06 Impl 1; 05 Q4).
4. **Dating setup (D1–D8):** gates disclosed first → gender → who you want to meet (country note before saving) → structured country + coarse region → 4-value intention → children yes/no → photos (system picker) + 2–3 prompts → "not married / not in a relationship" attestation → separate Art. 9 consent → liveness + facial age estimate (challenge age 25, ID fallback) + CompareFaces against every photo → "what others see" preview (05 §4.2; 01 §3.1, Impl 3–5, 12; 04 Impl 9, 13).
5. **Gentle wait** only if the person's relationship ended inside Attune: one private readiness reflection, Healing offered, optional self-set start date; the phone-HMAC ex-exclusion stays mandatory (03 Impl 13; 06 §2.4).
6. **Trust friction:** 72 h cool-off before the first introduction; same country by default; cross-border a private opt-in for verified users, with scam education (04 Impl 19–20; 02 Q6).
7. **Introductions:** a daily drop of ≤3 at a chosen time, ≤6 waiting, paused at 3 open pre-date chats; card = first name, age, region, intention, "why you two were introduced"; photos, or photos after mutual interest by choice (always, for same-gender in Tier 1/2 if ever on); Interested / Not for me with a 5 s undo; double-blind (03 Impl 1–5; 04 Impl 3; 02 Impl 8).
8. **Dating chat** (new `dating_messages`, own outbox and screen): text only; contacts masked for 72 h or until both tap "Swap contacts"; deterministic recipient-only, fail-open rule families incl. Ghana-variant `financial_request` and a sextortion card; block/report ≤2 taps; report from match history for 30 days with an evidence snapshot (`DATING_CHAT_SAFETY_SPEC.md` §3–§5; 04 Impl 21–27).
9. **Meeting:** "Plan a meet?" at day 7–10; first-meeting kit; "Share my plan" without the match's name or photo; private after-date check-in; "Close kindly" (03 §3(c); 04 Impl 28–29).
10. **Moderation:** P0–P3 SLAs; report-driven interim holds for P0 categories only; category shown + one human appeal; no auto-ban from a phrase or a single report; owner + one Twi/Ga/Pidgin moderator; minimal console (04 Impl 30; 02 Impl 4).
11. **Device:** quick exit everywhere (root `QuickExitZone`), also wiping dating caches; PIN (optionally every open); optional discreet icon; content-free pushes; `FLAG_SECURE`, no gallery saves (04 Impl 5).
12. **Leaving:** pause hides silently; exit hard-deletes preferences, gender and messages; account deletion cascades; export includes your own Dating data (04 Impl 8; 06 Q13).
13. **Becoming a couple:** both confirm after "what are we agreeing to?" → existing invite exchange → relationship guard pauses Dating for both (03 Impl 14; 06 Impl 11).
14. **Opinions:** a handle per post (unlinkable); no author pages; no dislike, reposts or quotes; pre-post filter; neutral push text; author-only crisis card; self-harm report reason (07 Impl 1–13).
15. **Countries:** versioned Tier 1/2/3 table with per-country kill switches for Dating and for same-gender matching; effective tier = highest of phone country, Dating country and session IP country (04 Impl 1, 6, 31).

**Markers used in every path:**
- ✅ the design stops it;
- ⚠️ the design slows it or stops it only partly;
- ❌ the design fails.

**Code-evidence tags:**
- **[C]** code-verified today at the cited file;
- **[D]** a spec says so;
- **[I]** inferred from code read but not executed.

External evidence keeps the brief's grades **[S] [M] [W] [A]**. **[BK]** is background knowledge not re-verified this session.

**Priority:**
- **P0:** before any real person uses Dating (including a pilot), or, for live surfaces such as Opinions and the journal, before real users are onboarded;
- **P1:** before Dating is promoted or opened beyond the pilot;
- **P2:** after launch.

---

## 1. How this was researched

- **Inputs read in full:**
  - research 04 (safety and law), 06 (code audit), 05 (sequences), 07 (Opinions);
  - 03 §2.8–§5 and 02 §2–§4;
  - 01 §2.7–§5;
  - the format reference `2026-10-16-couples-research/05-scenarios-strain-risk.md`.
- **Code read for this document,** beyond what 06 already verified:
  - `supabase/migrations/20260712160000_dating_former_partner_exclusion.sql`, `20260931130000_wire_dating_exclusion.sql`, `20260933140000_dating_health_exclusion_key.sql`;
  - `20260724120000_grant_missing_core_table_privileges.sql`, `20260606120000_attune_core_schema.sql`;
  - `20260703194500_dating_mode_v1_1.sql`, `20260703203000_dating_mode_contract_hardening.sql`, `20260705210000_dating_mode_v1_2_hardening.sql`, `20260816120001_dating_match_id_notification.sql`;
  - `20261018110000_chapters_deletion.sql`, `20261018100000_relationship_lifecycle_v2.sql`;
  - `supabase/functions/_shared/chat_safety.ts`, `_shared/self_disclosure.ts`, `analyse-journal-entry/index.ts`, `delete-account/index.ts`;
  - `lib/features/safety/domain/services/quick_exit_service.dart`, `lib/features/safety/presentation/safety_lock_controller.dart`, `lib/features/account/presentation/new_device_notice.dart`;
  - `lib/features/onboarding/data/onboarding_submission_service.dart`, `lib/features/auth/data/passwordless_auth_service.dart`;
  - the dating report-category lists in `dating_matches_screen.dart` and `dating_dashboard_screen.dart`;
  - `DATING_CHAT_SAFETY_SPEC.md` §1.2, §3–§7; `DATING_MODE_SPEC.md` §2, §8.
- **Method.**
  - Each scenario has an actor with a goal. The actor is walked step by step through the strawman, using the real RPC and table names where they exist.
  - At each step I recorded whether the design stops, slows or fails the actor.
  - Each failure gets the harm, the smallest fix, and whether the fix is code, policy or human moderation.
  - Where 01–07 disagree, I say which recommendation the scenario supports and why.
- **Limits.**
  - Nothing was executed: no app run, no SQL. Code claims are static reads.
  - No new web research. External facts come from 01–07 with their grades. A few local-practice points (Ghanaian school terms, the MoMo reversal scam, time zones, Android SIM APIs) are **[BK]** and flagged for a cultural or technical check.
  - No Ghanaian user, lawyer, clinician or LGBTQ+ advocate was consulted. Where the answer depends on them, it is marked.
  - Most of Dating is unreachable today: every flag is off, and activation needs preference arrays that nothing writes (06 §2.4 [C]). So "today" in a path means the code that would run once Dating is reachable.

---

## 2. Findings

### 2.1 Code facts this simulation surfaced (not in 01–07)

| # | Fact | Evidence | Scenarios |
|---|---|---|---|
| F-1 | **`public.users.phone` is client-writable.**<br>• `GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated` at table level, plus an own-row UPDATE policy, with no column guard or trigger.<br>• The onboarding client already upserts `phone`.<br>• The former-partner HMAC is computed from `public.users.phone`, not from `auth.users`.<br>• So a re-registered ex can rewrite the column and escape the exclusion. | `20260724120000:13`; `20260606120000:108-112`; `onboarding_submission_service.dart:42-48`; `20260712160000:139-153` [C]; the attack is [I] | S6, S14, S5 |
| F-2 | **Deleting an account erases the moderation record about it.**<br>• `dating_reports.target_user_id`, `dating_reports.reporter_user_id`, `dating_account_restrictions.user_id` and both sides of `dating_blocks` are all `ON DELETE CASCADE`.<br>• A reported or suspended user who deletes and re-registers with the same SIM starts clean.<br>• A victim who deletes her account also deletes her report. | `20260703194500:107-123`; `20260705210000:31-41` [C] | S1, S8, S10, S11, S15 |
| F-3 | **Blocks and "no repeat pair" are keyed to account IDs**, so they die when an account is deleted and recreated. | `dating_pair_key()` = `LEAST(uuid)\|\|':'\|\|GREATEST(uuid)` [C]; the exclusion migration's own comment admits it ("UUID-keyed `dating_blocks` die with the account") [C] | S10, S14 |
| F-4 | **The mutual-match push says "New mutual match"** ("Open Attune to see your new connection."). That reveals dating to anyone who sees the lock screen. | `20260816120001:89-92` [C] | S4, S5, S17, S19 |
| F-5 | **The safety normaliser deletes every non-ASCII letter** (`[^a-z0-9'\s]+` becomes a space). Twi or Ga words written with ɛ or ɔ can never match a phrase rule. Zero-width characters between words still join them ("if​you" becomes "ifyou"). | `supabase/functions/_shared/chat_safety.ts:65-72` [C] | S1, S9 |
| F-6 | **Exiting Dating keeps the orientation data.**<br>• `exit_dating_mode` only sets `profile_state='exited'`, so `dating_profiles` and `dating_preferences` (including `gender_preferences`) stay.<br>• `delete_dating_profile` deletes photos, preferences and the profile, but keeps the enrollment row (reset to `profile_draft`), consent events, introductions, matches, reflections, blocks and reports. | `20260703203000` (both functions) [C] | S15, S20 |
| F-7 | **Journal text reaches Gemini with no writer-facing safety check.** `analyse-journal-entry` imports only `gemini_json`. The `self_disclosure` corpus is wired only into `ai-assist`, `ai-understand` and `translate-conflict` (through `assistant_input.ts`). | grep of `supabase/functions` [C] | S13 |
| F-8 | **The server allows a report after unmatch, but the UI doesn't.**<br>• Server: `resolve_dating_match_target` accepts a match in any state.<br>• UI: `get_my_dating_matches` returns only `state='active'`, so the screen can't offer it.<br>• The report categories include no sextortion, entrapment, "hiding a relationship" or child-safety value. | `20260705210000:133-138, 780-803` [C] | S8, S11, S18, S22 |
| F-9 | **The former-partner exclusion is symmetric.**<br>• It is stored both ways, so it survives one side changing number or re-registering, as long as the other side's account still exists.<br>• It opens silently when the key is missing: `dating_phone_hmac` returns NULL and the predicate returns FALSE. The health check reports this, but nothing blocks generation. | `20260712160000:139-153`; `20260933140000` [C] | S6 |
| F-10 | **Sign-in reveals nothing today:** `signInWithOtp` with the default `shouldCreateUser` always sends a code. Research 05's returning-user path (`shouldCreateUser:false`, then "We couldn't find an Attune account") **would create a lookup**: anyone could test whether a number uses Attune before proving they own it. That depends on Supabase answering an unknown number with an error before any code is sent [BK]. | `passwordless_auth_service.dart:47-51` [C]; 05 §4.0 [D] | S5 |
| F-11 | **The strawman's masking rule unmasks automatically:** "72 h *or* until both swap" means a scammer only has to wait. | 04 Impl 21 [D] | S1, S8 |
| F-12 | **Account deletion records the exclusion first, which is good.** `prepare_account_deletion` calls `relationship_end_internal` for active or paused relationships, and that writes the exclusion before the cascade. | `20261018110000:205-224`; `20261018100000` [C] | S6, S15 |

### 2.2 The scenarios

#### S1 — A romance-scam crew with AI photos (West Africa, and pig-butchering)

**Actor and goal.**
- A Kumasi "sakawa" crew runs five personas aimed at diaspora women in the UK aged 50 and over.
- Separately, a Southeast Asian compound runs a slow crypto script.
- The goal is money by MoMo, gift card or crypto.
- Scale (04 §2.4.1):
  - FTC median loss $4,400 [S];
  - Action Fraud reports peak at ages 50–59 [S];
  - Ghana CSA online-fraud losses were GH¢4.4m in Q1 2025 [M].

**Path**
1. ⚠️ **Accounts.** The crew gets five numbers.
   - Ghana SIMs are linked to the Ghana Card, which makes a phone a moderate identity anchor in Ghana only (04 §2.2.3 [BK]).
   - VoIP and foreign numbers pass OTP.
   - The flow is `signInWithOtp` → `record_eula_acceptance` → a declared DOB → the Dating path.
   - SMS pumping rises with worldwide sign-up (05 §3.2.1, Twilio [M]).
2. ❌ **AI photos pass `process-dating-photo`.** Vision checks that a face is present (confidence 0.7) and runs SafeSearch. It does not check that the face is real (06 §2.4 [C]).
3. ✅ **Liveness, then CompareFaces in `verify-dating-profile`.** A generated face cannot match a live human (04 §2.4.2 [W]).
   - ⚠️ Injection attacks, such as a virtual camera, are claimed to be detected by the vendor (AWS [W]).
   - The crew's fallback is a hired real face per persona. Every photo must then be that person, so the glamorous stranger is gone, but real accomplices pass.
4. ⚠️ **Volume.** A 72 h cool-off, then at most 3 introductions a day. Five personas reach at most about 450 people a month (04 §2.6 layer 1).
5. ✅ **Same country by default** blocks the "engineer in Dubai" or "soldier abroad" script from reaching a woman in London unless both people opted in to cross-border introductions. ⚠️ The diaspora women who opt in to "open to people in Ghana" are exactly the target.
6. ⚠️ **The same opener sent to every match** is caught by a duplicate opening-message hash (04 Impl 22). Openers paraphrased by an LLM evade it [I].
7. ❌ **"Let's continue on WhatsApp."** Masking holds for 72 h and then lifts automatically (F-11). The crew waits three days.
8. ⚠️ **"My mum is on admission at Korle Bu, send small MoMo"** triggers `financial_request` (tier 2), which is more sensitive in a match's first 14 days (`DATING_CHAT_SAFETY_SPEC.md` §3.3 [D]).
   - ❌ Twi spelled with ɛ or ɔ can't match (F-5), and "m0m0" isn't folded.
   - The compound's day-30 "I'll teach you USDT trading" needs crypto and investment-platform phrases. The v1 family describes these only in general terms.
9. ❌ **She reports `romance_scam`** through `report_dating_match`. That inserts one row and nothing else: no hold, no evidence snapshot, no console (04 G8, G11 [C]).
10. ❌ **Delete to evade.** A suspended crew member deletes the account. Reports and the restriction cascade away (F-2). He re-registers with the same SIM and starts clean. A new SIM leaves no link at all (04 G13).

**Harm if it fails.** Money loss plus the "double hit" of losing the relationship (Whitty 2013 [M], 03 §2.9). Honest Ghanaian users carry the scam stigma (02 §2.3 [A]).

**Minimal fix**
- **[Code, P0]** Require liveness before the first introduction, with CompareFaces against every profile photo. CompareFaces already exists; Face Liveness goes in front of it.
- **[Code, P0]** **An enforcement record that survives deletion.**
  - At account deletion, keep `{phone_hmac from auth.users, restriction type, count of confirmed reports, expires_at}` and check it in `activate_dating_profile`.
  - Change `dating_reports.target_user_id` and `reporter_user_id` to `SET NULL`, and add a `target_phone_hmac` column.
- **[Code, P0]** Masking ends only when both people tap Swap. The 72 h mark is just the earliest that Swap is offered.
- **[Code, P0]** A Ghana lexicon:
  - MoMo, airtime, "send me small", transport fare, data bundle;
  - "I sent it by mistake, send it back" (the reversal scam) [BK, needs reviewer];
  - crypto and investment phrases;
  - a normaliser that keeps Unicode letters (`\p{L}`), folds Akan letters only by reviewed rules, and turns zero-width characters into spaces.
- **[Code, P1]** Signals that go to the queue:
  - duplicate openers and repeated money asks across matches;
  - Dating activations per device;
  - session country that doesn't match the stated country.

  None of these auto-bans. Nationality, network or name is never a risk signal (02 Impl 5).
- **[Human, P0]** A moderator who reads Twi, Ga and Pidgin scam scripts (04 §2.6).

**Residual, accepted:** real accomplices with real faces and paraphrased scripts. The daily cap is the real limit.

#### S2 — A 16-year-old enters a false date of birth to join Dating

**Actor and goal:** Esi, 16, in Takoradi, wants to join Dating.

**Path**
1. ⚠️ **Guest Opinions.** There is no age gate today [C] (07 §2.1). The strawman's 18+ self-declaration is a single tap.
2. ❌ **She types 2006 at A2.** A self-declared DOB is not "highly effective age assurance" (Ofcom [M], 04 §2.2.1).
   - ✅ If she first enters her real year, the on-device stop and the 30-day local block prevent an instant retry (FTC neutral-gate guidance [M], 05 §5.1).
   - ⚠️ Clearing app data removes a local flag.
3. ⚠️ **Platform age signals** (Apple Declared Age Range, Play Age Signals) currently apply only in Texas, Utah, Louisiana and Brazil (05 §3.5.4 [M]). Nothing applies in Ghana.
4. ✅ **Dating liveness and facial age estimation, challenge age 25.**
   - The vendor claims 99.3% of 13–17-year-olds are estimated under 21 (Yoti [W vendor]).
   - She is sent to the ID fallback (Ghana Card through a vendor such as Smile ID [W]).
   - With no ID, or a sibling's card, the document-to-face match fails.
5. ⚠️ **The cost to adults.** Every 18–24-year-old estimated under 25 is also sent to ID. Independent bias data for West African faces is thin (NIST FATE [M]).
6. ❌ **Her older sister does the selfie and supplies the photos**, and Esi does the typing.
   - Detection then rests on `age_signal` (tier 3, moderation only, `DATING_CHAT_SAFETY_SPEC.md` §3.1 [D]).
   - That family needs Ghanaian school cues: "SHS", "form 2", "after BECE", "my WASSCE", "housemistress" [BK; cultural reviewer].
7. ❌ **A match reports `underage_risk`.** Today that is only a row [C]. `age_verification_invalid` also keeps matches open (Fable H5; 04 G14).
8. ⚠️ **A declared age of 30 with an estimate of 15** is evidence about the whole account, but the strawman locks only Dating.

**Harm.** Adult–minor contact, grooming, intimate images of a minor (CSAM), offences under Ghana's Cybersecurity Act 2020 ([BK], 04 §2.2.1), and a breach of Google Play's CSAE policy (child sexual abuse and exploitation) [M].

**Minimal fix**
- **[Code, P0]** Facial age estimation, liveness and an ID fallback before activation. The sign-up DOB never writes `dating_age_verifications` (04 C3).
- **[Code, P0]** An `underage_risk` report triggers an interim `age_review`, removes the person from generation and closes their matches. Add `age_verification_invalid` to the reasons that close a match.
- **[Policy, P0]** A large gap between declared and estimated age puts the whole account into `age_review`, with a neutral screen and a route to support.
- **[Code, P0]** CSAM hash-matching on every uploaded image (04 Impl 24).
- **[Policy, P0]** A published CSAE standards page and a named child-safety contact (Google Play [M]).
- **[Code, P1]** Read the platform age signals; when they conflict with the DOB, the stricter one wins (05 §5.1).
- **[Human, P0]** Triage underage reports within 4 h in staffed hours and 24 h at most (04 §2.6).

#### S3 — A gay man in Ghana, and an entrapment gang looking for him

**3a. Kwesi, 27, in Accra, picks "Man" then "Men."** The tier table says Ghana is **Tier 1**.

- **Variant A (04 Q1: offer it with Tier 1 protections):**
  - a country note before saving;
  - photos held until mutual interest;
  - liveness;
  - a weekly cap for accounts under 30 days old;
  - dragnet detection;
  - a prompt to use the discreet icon and a PIN;
  - neutral pushes;
  - a cache wipe on quick exit.
- **Variant B (03 Q3):** same-gender introductions are off in Ghana.

**3b. The gang** (2–15 people with a shared playbook; Rightify recorded 300 cases in 2024; Guardian 2025 [W], 04 §2.1.3).
1. ✅ / ❌ **Five members pass liveness with their own faces.** Liveness ties each account to a real face that Attune does not keep (04 Q8). It does not stop real people acting in bad faith.
2. ⚠️ **They set "Men / Greater Accra / committed relationship."**
   - The cap for new accounts (for example 3 same-gender introductions a week) gives about 60 introduction events a month.
   - In a thin pool of a few hundred (02 §2.4), that enumerates the pool in months, not never.
3. ❌ **Every card is an outing event, even if Kwesi never taps Interested.** A first name, age, "Greater Accra", an intention and the overlaps are enough quasi-identifiers in a small community (Sweeney 2000 [M], 07 §2.6(i)). Double-blind protects interest, not preference (04 §2.1.8).
4. ⚠️ **They say Interested to everything,** which trips the dragnet rule and goes to the queue. Then they vary their rate.
5. ❌ **Kwesi says Interested to one of them** → match → photos unlock → "come to my place in Kasoa tonight." No rule family covers pressure to meet at a private address.
6. ❌ **Meeting:** a beating, a recording, extortion by MoMo.
   - The sextortion card and `threat_intimidation` show resources.
   - Today's resources are three hard-coded countries, with no LGBTQ-safe help that isn't the police [C]. The police themselves extort victims (04 §2.1.3 [W]).
7. ❌ **The phone is searched afterwards** (S19). The server holds a list of men in Ghana who seek men (S20).

**3c. A colleague is introduced to Kwesi.** No crime is intended. But Ghana's bill as passed reportedly carries a **duty to report** (05 §3.5.6 [M]). An honest introduction to someone who knows Kwesi turns that person into a potential informant.

**Harm.** Violence, extortion, outing, prosecution (s.104, and the bill if it becomes law), death. The owner and any Ghana-based staff may also be exposed as "promoters" under the bill's reported platform clause (04 §2.1.2 [W]).

**Verdict between 03 and 04.**
- This walk supports **03 Q3 (off in Ghana)** for launch.
- 04's protections slow enumeration but cannot stop it: steps 2, 3 and 3c are structural.
- The legal question is unresolved.
- The required protections (photo withholding, caps, dragnet detection, liveness) are all unbuilt.
- 04's counter-argument stands: switching it off pushes people to riskier channels. So "off" must come with honest copy, verified resources, and a stated path to reconsidering.

**Minimal fix**
- **[Policy + Lawyer, P0]** Same-gender introductions are off in Ghana and in every Tier 1/2 country at launch. Reconsider only after:
  - a Ghanaian legal opinion;
  - consultation with Ghanaian LGBTQ+ groups;
  - every Tier 1 protection built and tested.
- **[Code, P0]** Where it is off, show only the other gender as "Who would you like to meet?", with the line "In Ghana, Attune introduces men and women to each other for now. Why?". Choosing reveals nothing, and **nothing about orientation is sent to the server, logged or counted**. The server also refuses.
- **[Code, if ever turned on]**
  - Name and photos withheld until mutual interest; the card shows an age band, intention and overlaps only.
  - Same-gender introductions only between verified accounts at least 30 days old.
  - A dragnet throttle.
  - A `meet_private_pressure` education family, plus the LGBTQ+ block of the first-date guide (04 Impl 29).
- **[Human, P0]** An LGBTQ+ safety reviewer with West African context; country-note copy; a "suspected fake or entrapment profile" report path (02 Q10).

#### S4 — A traveller enters a high-risk country

**Actor and goal:** Kojo, 34, lives in London with a UK SIM, has Dating set to the UK and "Men," and flies to Accra in December.

**Path**
1. ✅ **Effective tier = max(phone UK T3, Dating country UK T3, session IP Ghana T1) = T1** (04 Impl 1), as long as the IP country is computed transiently.
2. ❌ **Weak signals.**
   - A VPN exiting in the UK hides it.
   - The time-zone signal (`users.timezone`, reported at launch, 06 [C]) is useless in winter: Accra and London are both UTC+0 [BK].
   - Android can read the SIM or roaming network country [BK]; iOS is more restricted [BK].
3. ✅ **On detection:**
   - a one-time in-app note, **never a push**, because the push text would itself be evidence;
   - an offer of a PIN on every open, the discreet icon, or Pause;
   - same-gender visibility auto-hidden while in the higher tier (the Tinder Traveler pattern [W]).

   His UK introductions continue.
4. ❌ **The device is the risk:**
   - the "New mutual match" push (F-4);
   - introduction photos in the image cache;
   - dating-chat cache that quick exit doesn't clear (04 G10 [C]).
5. ⚠️ **Reverse case:** Ama, with a Ghana SIM, visits London. Her tier falls. Same-gender matching and visibility must never switch on by themselves; she must opt in.
6. ✅ **A Ghanaian worker in the UAE** (Ghana SIM, UAE IP, both T1) sees Dating "not available where you are." That message is shown only on his own device.

**Harm.** Phones searched at checkpoints and arrests are the main source of evidence (HRW 2023 [M]; Rigot 2022 [M]). Family can out him.

**Minimal fix**
- **[Code, P0]** Neutral text on every Dating push ("You have something new in Attune").
- **[Code, P0]** Quick exit wipes dating caches.
- **[Code, P1]** Traveller detection from the IP and, on Android, the SIM or network country; the in-app note; auto-hide.
- **[Code, P1]** A user-controlled "Travel mode": hide me and keep no local Dating data until I turn it off.
- **[Policy]** Never copy Grindr's risk-alert *pushes* (04 §2.1.4). Attune's neutral identity is worth more than an alert.

#### S5 — A controlling partner wants to know whether the other partner is on Dating

**Actor and goal:** Kwame is together with Efua outside Attune, or she has recently left him. He suspects she is on Dating.

**Path (four routes)**
1. **Taking her phone.**
   - ⚠️ There is no PIN unless she set one. "Every open" exists (`safety_lock_controller.dart:57` [C]).
   - ❌ The second tab is labelled "Dating" (06 §2.7 recommends Chat / Dating / Me).
   - ❌ The lock screen shows "New mutual match" (F-4).
   - ✅ Quick exit works from every screen if she sees him coming (root `QuickExitZone`, 06 §2.1.1 [C]).
2. **Signing in with her SIM** (a shared handset, or he controls the line) → `signInWithOtp` → he is in.
   - ✅ `NewDeviceWatcher` shows her an in-app notice on her next open, and Spec 2 lists sessions so she can sign out other devices [C].
   - ❌ His session works until she looks.
3. **A fishing profile.** Kwame creates his own Dating account and tunes his age, region and intention to fit her filters, which he knows.
   - ❌ He is introduced to her, and her card (first name, age, region) proves she is on Dating, even if she never taps Interested.
   - Double-blind hides interest, not presence.
   - Withholding photos doesn't help, because her name and age are enough for someone who knows her.
   - The former-partner exclusion covers him only if their relationship ended inside Attune.
4. **Number test.** He types her number at sign-in.
   - ✅ No lookup exists today (F-10).
   - ❌ Research 05's returning-user screen would create one.
5. **Asking support:** "Is my wife on your app?" There is no policy today.

**Harm.** Separation is a recognised danger period for intimate partner violence (Campbell 2003 [S], 03 §2.8).

**Minimal fix**
- **[Code, P0]** **"Never introduce me to these numbers."**
  - The user enters numbers; only keyed HMACs are stored, in the exclusion-table pattern.
  - It is a symmetric hard filter, never shown to anyone.
  - Adding a number never notifies its owner.
- **[Code, P1]** An opt-in, on-device hashed contacts exclusion (03 Q10).
- **[Code, P0]** Dating re-verification on any new device: a selfie compared with her approved photos through the existing CompareFaces, before any Dating screen renders. This stops route 2 for Dating.
- **[Code, P1]** An optional Dating lock. When it's on, the second tab shows the Me home and Dating sits behind the PIN.
- **[Code, P0]** Neutral push copy (F-4).
- **[Code, P0]** Always send a code. Say "no account" only after the code proves the person owns the number.
- **[Policy, P0]** Support never confirms or denies that an account exists, except under valid legal process (04 Impl 8).

#### S6 — A former Attune partner appears in introductions

**Path**
1. ✅ **Ending writes the exclusion.** `end_relationship` → `relationship_end_internal` → `record_dating_former_partner_exclusion(rel, true)`, with rows both ways (F-9). Deleting an account while the relationship is active or paused takes the same path (F-12) [C].
2. ✅ **It is checked everywhere it matters:** `dating_pair_passes_hard_filters`, `act_on_dating_introduction` and `get_my_dating_introductions` all call `dating_former_partner_excluded` [C].
3. ⚠️ **A missing key fails open.** If the key isn't provisioned, the HMAC is NULL and the predicate returns FALSE. `end_relationship` swallows the error as a WARNING [C]. The health check shows it, but generation isn't blocked.
4. ❌ **F-1 bypass.** Kwame:
   - deletes his account, so the row protecting *him* cascades away;
   - re-registers with the same SIM, so the row protecting Efua is still keyed to his real number;
   - then sends a PATCH to `public.users.phone` with an unused value.

   `dating_former_partner_excluded` no longer matches, and they can be introduced [I].
5. ⚠️ **Documented residual:** a new number that was never verified on Attune (Fable C4). Dual-SIM handsets are common in Ghana [BK].
6. ⚠️ **Third parties** pass on what they see (S14).

**Harm.** Re-contact with an abuser in the period of highest risk.

**Minimal fix**
- **[Code, P0]** Column grants on `users`: `display_name`, `avatar_url` and `timezone` only. `phone` is written only from `auth.users`, by a SECURITY DEFINER function. Compute every HMAC from `auth.users.phone`.
- **[Code, P0]** `run_dating_candidate_generation` refuses to run when the exclusion key is missing.
- **[Code, P0]** The "never introduce me" list (S5) covers the ex's other numbers.
- **[Code, CI]** A contract test: two former partners, one deletes and re-registers, then tampers with `public.users.phone`; they are still never introduced.

#### S7 — A recycled phone number takes over someone's account

**Path**
1. ❌ **Today:** Ama's old MTN number is recycled (MTN said deactivated SIMs would be recycled; 05 §3.2.5 [M]). Yaw installs Attune, enters the number, receives the code, and is inside Ama's journal, Healing, Dating profile, matches and chats [C]. There is no dormancy rule.
2. ⚠️ **The strawman's dormancy rule** (a new device after at least 180 days → PIN or passkey, otherwise DOB, otherwise a fresh start):
   - the DOB is a weak secret, known to family and partners;
   - Ghana's actual recycling period is unknown (05 [M]), so 180 days may be too long.
3. ❌ **SIM swap** on an *active* number (common where mobile money is the target, 04 §2.3 [BK]) skips the dormancy rule entirely.
4. ❌ **In Dating, Yaw can message Ama's matches as Ama,** and can see who she matched with. If those matches are same-gender, that outs them.

**Harm.** The most intimate data in the app is exposed, and Ama is impersonated to strangers.

**Minimal fix**
- **[Code, P0]** Dating re-verification on every new-device sign-in (a selfie compared with her approved photos). This defeats both a recycled number and a SIM swap, for Dating, without storing any template.
- **[Code, P0]** Dormancy rule: the DOB alone never unlocks couples, journal or Dating content. If no PIN or passkey is set, the person gets a fresh start and the old account goes into a support-only recovery hold (05 §5.0).
- **[Code, P1]** Offer passkeys or a registration-lock PIN after the first week (05 Impl 13–14).
- ✅ Keep the existing new-device notice and "Sign out all other devices" [C].

#### S8 — Sextortion after contacts are swapped

**Path**
1. ⚠️ **Both tap "Swap contacts."** A one-time card at Swap: "On WhatsApp, Attune can't help inside the chat. Sextortion often starts with a video call." This is education only.
2. ❌ **Outside Attune:** a WhatsApp video call is recorded, then a demand for cedis by MoMo with a countdown (Ghana CSA [M]; Thorn & NCMEC: about two-thirds financially motivated, 47% tied to Nigeria and Côte d'Ivoire [S]).
3. ❌ **She comes back to report,** but he has unmatched her. The UI lists only active matches (F-8).
4. ❌ **No "sextortion" category exists,** so she picks `safety_concern` or `other`.
5. ❌ **No evidence snapshot.** Dating-chat retention is "deleted when the match closes plus the evidence window" (spec §7 [D]), so unmatching may start the deletion clock.
6. ❌ **Resources:** three hard-coded countries; no CSA 292, no sextortion entry, no StopNCII (04 G9 [C]).
7. ❌ **He deletes his account** and the reports go with it (F-2).
8. ⚠️ **If the match was same-gender in a Tier 1 country,** going to the police is itself dangerous (04 §2.1.3).

**Harm.** Payment and repeat extortion, exposure, severe distress.

**Minimal fix**
- **[Code, P0]** Report from match history for 30 days after unmatch, block or the other person's deletion (by keeping enforcement records, F-2 fix).
  - Snapshot the last N messages at report time.
  - Add a `sextortion` category: P1 SLA of 24 h or less, and immediate removal from generation (04 §2.6).
- **[Code, P0]** A deterministic, recipient-only sextortion card: "Don't pay. Keep the messages. Report here and to CSA 292 or your local line" (04 Impl 23).
- **[Code + Reviewer, P0]** Support resources v2 with CSA 292, StopNCII for adults [BK], and LGBTQ-safe help that isn't the police, each with `verified_at`.
- **[Policy, P1]** Cooperate with law enforcement on sextortion only with the victim's consent.

#### S9 — A request for money or mobile-money airtime in dating chat

**Path**
1. **Day 2 of a match:** "Pls send me small airtime, I'll pay back" / "credit me 20 cedis for transport" / "buy me data bundle."
2. ⚠️ **`financial_request`** fires in its 14-day high-sensitivity window [D]. Ghana variants are proposed but not written (04 Impl 22). ❌ Phrases in Twi spelling can't match (F-5).
3. ✅ **The recipient sees scam education** plus a one-tap `romance_scam` report. Delivery is unchanged and the sender sees nothing (spec §4.1–4.2).
4. ⚠️ **A MoMo number typed as digits** ("024 123 4567") is masked by the phone-shape rule. ❌ Written in words ("zero two four…"), it isn't.
5. ❌ **The reversal scam** ("I sent you 200 by mistake, send it back") isn't in any list [BK, reviewer to confirm].
6. ✅ **False positives cost nothing:** two people splitting a trotro fare see an education card, and triggers never restrict anyone.
7. ⚠️ **Diaspora scripts** (gift cards, Western Union, "customs fee for the parcel") are in the FTC data [S], but the v1 phrases are generic.

**Harm.** Small asks that climb the grooming ladder (Whitty 2013 [M]). Large losses for diaspora targets.

**Minimal fix**
- **[Code + Reviewer, P0]** The Ghana and diaspora lexicon, plus the Unicode-safe normaliser (S1), with golden positive and negative fixtures.
- **[Code, P1]** The same person asking several matches for money goes to the queue.
- **[Human, P0]** A Ghanaian reviewer for the phrase lists.

#### S10 — A harasser says Interested to everyone

**Path**
1. ✅ **He taps Interested on every introduction.** `act_on_dating_introduction` is limited to 30 a day [C] and he gets at most 3 a day. He matches only where the interest is mutual, and there is no browsing.
2. ⚠️ **The dragnet signal** goes to the queue (04 Impl 3e). On its own, interest is not harm.
3. ✅ **After a match he sends sexual pressure.** `sexual_pressure` (tier 1) shows the recipient resources and a report button. Dating chat is text-only, so no images (the UK cyberflashing offence [M]).
4. ✅ **She blocks him** (`block_dating_match` → `dating_blocks`). The spec requires the block to be enforced in RLS, not the UI (§4.4); a test is still needed.
5. ❌ **He deletes his account and re-registers with the same SIM.** The ID-keyed block and the "no repeat pair" rule are gone (F-3), so he can be introduced to her again.
6. **Context:** 30% of US online daters were contacted again after saying no (Pew [M], 04 §2.5).

**Harm.** Repeat harassment and stalking. He already knows her first name, age, region and photos.

**Minimal fix**
- **[Code, P0]** Blocks are also stored as phone-HMAC pairs, so they survive re-registration. Keep the enforcement records from S1.
- **[Code, P1]** The dragnet throttle shrinks his daily drop rather than suspending him.
- **[Code, P1]** `sexual_pressure` across two or more matches goes to the queue.

#### S11 — A malicious report gets someone banned, and the appeal path

**Path**
1. **Abena refuses a demand for nudes.** He reports her for `sexual_content`. This is the most-documented pattern in the review corpus: at least 44 reviews say they were banned after someone reported them (Bumble NG, Tinder GH, Taimi, Feeld) [A] (02 §2.2 P4).
2. ✅ **Today a report is just a row,** so nothing happens automatically [C].
   - ⚠️ The strawman adds interim holds for P0 categories.
   - ❌ A retaliatory "she's underage" report (`underage_risk`) would put her on hold. Trans users reported for "impersonation" are the known parallel (HER, "kicked off 5 times" [A]).
3. ✅ **The moderator reviews the evidence snapshot** and sees that *his* messages tripped `sexual_pressure`. Reports from someone whose own messages to the reported person tripped `sexual_pressure` or `financial_request` should count for less (02 Impl 4).
4. ❌ **If she is restricted:** spec §8 says "never reveal suspension… cause" [D]. A ban with no reason given is the top named pain in Ghana: 16.1% of low reviews, and 43% of all ban reviews say no reason was given [A].
5. ❌ **Appeal:** spec §2 promises an appeal path [D]. No console or appeal screen exists (04 G8).
6. ❌ **Opinions:** three confirmed removals bring a 7-day ban. The "Post removed" notice names no rule and offers no appeal [C] (07 §2.1).

**Harm.** The person who said no loses access. It also feeds the anti-fraud stigma that already bans Ghanaian users at twice the US rate [A].

**Minimal fix**
- **[Policy, P0]** Amend spec §8:
  - show the category;
  - allow one human appeal, reviewed by someone other than the first reviewer, or by the owner after 24 h if solo (Santa Clara 2.0 [V], 07 §2.8; DSA Art. 17 [M]);
  - never reveal the reporter or what they wrote.
- **[Code, P0]** An appeal button on the restricted-state screen. An `underage_risk` hold needs **corroboration**: two independent reporters, or a matching `age_signal` trigger. Otherwise it gets priority review without a hold.
- **[Policy, P0]** Reports about someone's gender identity never trigger action.
- **[Measure]** Overturned-ban rate by country (02 Impl 21).

#### S12 — An Opinion identifies the author's partner, or the partner recognises themselves

**Path**
1. ❌ **Ama posts** (`create_opinion`): "My husband, a pastor in Kumasi, still sends money to his ex…" There is no pre-post filter [C] (07 §2.1 item 1).
2. ❌ **Kofi recognises the story** in Discover and taps it. The anonymous profile shows every post, comment and repost under one permanent HMAC handle, and guests can open it too [C] (07 §2.1 items 3–4).
3. ❌ **"Identifies a real person"** auto-hides only at 10 reports [C]. In a small community that will rarely happen.
4. ❌ **Lock-screen push:** "X commented: …" with a 60-character preview [C].
5. ⚠️ **Strawman:**
   - per-post handles and no author pages;
   - a self-focused hint ("Leave out names, places and details someone could recognise");
   - a filter that blocks phone numbers and @handles.
   - A deterministic filter cannot catch "a pastor in Kumasi"; that jigsaw risk remains.
6. ⚠️ **The reverse:** Kofi writes about Ama to build a public case. "Never attribute to a partner" binds Attune's outputs, not users' posts (07 §2.7).

**Harm.** Escalation of abuse at home; defamation (Ghana [legal check]); outing, if the story is a same-gender relationship.

**Minimal fix**
- **[Code, P0 before Opinions is promoted]**
  - Per-post handles; remove author profiles and following authors (07 Impl 1).
  - Neutral push text.
  - Auto-hide at 2 distinct reporters for "Identifies a real person."
  - A contact-detail filter (Apple 1.2 [M]).
- **[Policy]** Honest privacy copy (07 Impl 11).
- **[Human]** A daily review slot.

#### S13 — A user in crisis writes in Opinions or the journal

**Path**
1. ❌ **Journal:** "I can't do this anymore, I want to die" → save → `analyse-journal-entry` sends the text to Gemini with no writer-facing check (F-7). The safety system never runs, and a model may write an "insight" on a suicidal entry.
2. ⚠️ **There is no Support resources link inside the journal** (no hit in `lib/features/reflection_journal`) [C]. ✅ Quick exit works (root shell).
3. ❌ **Opinions:** "I don't want to be here anymore."
   - There is no route.
   - Self-harm is not a report reason [C].
   - Cruel replies cluster on help-seeking posts (Yik Yak [V], 07 §2.4).
4. ✅ **The strawman respects the constraints:** detection is deterministic and author-only, never blocks posting, persists nothing, and sends no signal to a partner or anyone else.
5. ⚠️ **Lexicons miss variants** (Chancellor 2016 [M]). Copy must never imply detection is complete.

**Harm.** A missed crisis, or a harmful AI response to one.

**Minimal fix**
- **[Code, P0]** Run `self_disclosure` on journal save, before any provider call. On a match, skip the provider and show the writer card. This is the 10-16 P0-5 item for the journal.
- **[Code, P0]** A static "Need support now?" link in Opinions compose and in every post menu, and a self-harm report reason routed to the human queue (07 Q5).
- **[Code + Clinician, P1]** An author-only Opinions detector, under its own clinical spec (SAFETY §1.4).

#### S14 — A breakup inside Attune, then both people enter Dating

**Path**
1. ✅ **Kofi ends the relationship.** No push to Ama (10-16 P0-1). The exclusion is written both ways [C]. Both homes become personal (`resolveModeFromRelationshipStatus` [C]).
2. ✅ **Ama taps Turn on Dating** → the gentle wait (a private reflection, Healing offered, a self-set start date; 03 Impl 13). This replaces today's gate of a readiness score above 70, every Healing stage done and 8 weeks [C].
3. ✅ **Neither is introduced to the other**, subject to the F-1 fix.
4. ❌ **Third-party relay:** Kofi's friend Yaw is introduced to Ama and tells Kofi. The design can't stop that. ⚠️ The "never introduce me" list and the contacts exclusion reduce it.
5. ❌ **Kofi opens a second-SIM account** and passes liveness with his own face.
   - If Ama sees photos, she recognises him and blocks.
   - If she has "photos after mutual" on, his card is just a name, age and region; with a different name, she may tap Interested.
6. ✅ **Healing and gentle-wait data stay private from the ex.** ⚠️ The Opinions status label is re-synced on path change (06 Q7). That is safe only if posts can't be linked (S12).
7. ⚠️ **If Ama left because of abuse,** copy that implies she must "heal first" would wrong her. "Offered, not forced" is correct (03 §2.8: no evidence supports an imposed wait).

**Minimal fix**
- **[Code, P0]** The F-1 fix and the "never introduce me" list.
- **[Code, P1]** For an account's first 30 days, it can't hold back its photos. This cuts both catfishing and exes evading the exclusion. Tier 1 same-gender withholding would be the only exception, and that is moot at launch.
- **[Clinician, P0]** The gentle-wait copy and its length.
- **[Policy]** Neither person is ever notified of anything the other does.

#### S15 — A user wants every trace of Dating gone

**Path**
1. ✅ **Pause** (`pause_dating_mode`) hides her silently.
2. ❌ **Exit** (`exit_dating_mode`) keeps her profile and `gender_preferences` (F-6). That contradicts 04 Impl 8.
3. ⚠️ **"Delete dating profile"** removes photos, preferences and the profile. It keeps:
   - the enrollment row, reset to `profile_draft`;
   - consent events, introductions, matches, reflections, blocks and reports (F-6).

   Same-gender introduction and match history is itself orientation data (CJEU C-184/20 [M], 04 §2.3).
4. ❌ **Export:** "Download my data" asserts there is no `dating` section [C] (06 §2.4). She can't see what remains (GDPR Art. 15 [M; legal check]).
5. ❌ **Quick exit** clears Together, Map and Stories caches, not dating caches or the chat cache [C]. It is a decoy screen, not a wipe of her server data; users may think it is.
6. ✅ **Account deletion:** `delete-account` → `prepare_account_deletion` → the `deleteUser` cascade removes her dating rows [I].
   - ❌ Her reports against others go too (F-2), so the evidence is lost.
   - ✅ The rows protecting *others* from her number survive by design. This needs a line in the privacy policy.

**Harm.** Leftover orientation data becomes a target list if breached or compelled (S20). The promise to delete is broken.

**Minimal fix**
- **[Code, P0]** Exit hard-deletes the profile, preferences, gender, photos and dating messages.
  - After the evidence window, introductions and matches become records with no pair attached.
  - Keep only the consent-event minimum that counsel says is required.
- **[Code, P0]** Quick exit wipes dating and chat caches.
- **[Code, P0]** Reports survive the reporter's deletion in anonymised form.
- **[Code + Lawyer, P1]** The export includes your own Dating data (06 Q13).
- **[Policy]** The privacy policy names what survives (exclusion HMACs, enforcement records, anonymised safety events) and why.

#### S16 — A minor's partner invites them into Relationship Mode

**Path**
1. ❌ **Today:** Kwabena, 24, sends Esi, 16, an invite link.
   - `main.dart` stores the code and clears first launch → `/onboarding` → OTP → EULA v'1' (no age clause) → `OnboardingGate` accepts the invite *before* the name step → `accept-invite` has no age check → linked (06 §2.1.5 [C]).
2. ⚠️ **Strawman:** DOB before acceptance plus a server `account_age` check. That works if she is honest. ❌ She types an adult year, perhaps because he tells her to.
3. ❌ **Once linked:**
   - couples chat media, view-once, stories;
   - AI features analysing a minor's messages;
   - intimate images of a 16-year-old are CSAM on Attune's servers ([BK] 04 §2.6);
   - couples chat has no "report my partner" by design, because of the intimate-partner-violence model.

**Harm.** Grooming; CSAM storage; legal and app-store exposure.

**Minimal fix**
- **[Code, P0]** The DOB step before invite acceptance, and an age check in `accept-invite` that returns a neutral error.
- **[Code, P0]** CSAM hash-matching on every upload (couples media, stories, dating photos), with an escalation runbook for NCMEC, IWF and CSA (04 Impl 24; Google Play CSAE [M]).
- **[Code, P1]** Platform age signals.
- **[Policy, P0]** "Report a concern about a child" in Support resources, going to a human queue, never partner-facing.
- **[Policy]** An age gap is never used to profile anyone.

#### S17 — Account sharing on a family phone

**Actors:** (a) Adwoa, 26, shares an Android with her mother. (b) A parent "helps" by running a daughter's Dating profile.

**Path**
1. ❌ **The mother opens Attune.** With no PIN, she sees the Dating tab, introductions and chat. The lock screen says "New mutual match" (F-4).
2. ⚠️ **Strawman:** a PIN on every open, a neutral push and the discreet icon. These are optional, so they work only if Adwoa is asked at the right moment.
3. ❌ **Two accounts on one handset** (sign out, sign in). The proposed per-device multi-account fraud signal (04 Impl 22) would flag ordinary families.
4. ❌ **`attune.onboarding.pending_invite_code` is not scoped to a user.** An invite meant for one person on the phone can be accepted into another person's account (06 §2.1.3, R4 [C]).
5. ❌ **(b) The parent types as the daughter.** Liveness binds the face, not the typist, so this residual stays.

**Harm.** Outing to family, especially for same-gender seekers (family violence, HRW 2018 [M], 03 §2.9). Consent and impersonation problems.

**Minimal fix**
- **[Code, P0]** Neutral push text.
- **[Code, P0]** Scope the invite key per user.
- **[Code, P1]** Ask "Does anyone else use this phone?" at Dating setup, leading to a PIN on every open or the Dating lock.
- **[Code]** The device signal counts only *Dating activations* on one device within 30 days, and goes to review.
- **[Policy, P0]** One person per account in the terms. Family involvement only through a trusted contact (Share my plan). No guardian accounts in v1 (03 Q4).

#### S18 — A Dating user who is secretly in a relationship (privacy rules respected)

**Path**
1. ✅ **Kojo is linked with Akua.** `dating_has_relationship` blocks Dating on his account for pending, active or paused relationships [C]. ❌ He opens a second account on his other SIM; one person, one account isn't enforced.
2. ⚠️ **If his relationship is outside Attune,** the "not married / not in a relationship" attestation (01 Impl 12) deters but cannot verify.
3. **How Akua could find out:**
   - (i) she looks at his phone, which Attune neither helps nor blocks beyond the PIN he controls;
   - (ii) she uses a decoy profile with a friend's real face (it must pass liveness). She is introduced only if both sets of filters fit, and learns something only if he taps Interested;
   - (iii) third parties tell her;
   - (iv) she asks support, which never confirms anything.
4. ✅ **What Attune must never do** (permanent constraints and SOUL):
   - notify a linked partner of the other's Dating activity or second account;
   - offer any "is my partner on Dating" lookup;
   - produce a "trust" or "loyalty" score;
   - use one user's data against another.

   Any duplicate-account detection goes to generic enforcement (suspend the duplicate), never to a partner.
5. ✅ **A match who finds out** ("he's married") reports it. This needs a new category, "hiding a relationship" (02 Q5). Moderation suspends him with the category shown.

**Harm.** Deception harms his matches. Turning Attune into a surveillance tool would harm everyone (Freed 2018 [M], 07 §2.7).

**Minimal fix**
- **[Policy, P0]** The rule, the attestation and the report category. Dating v1 excludes anyone currently married in any form (01 Q6; 02 Q5).
- **[Code, P1]** Signals of more than one Dating account per person go to the queue.
- **[Policy, P0]** Never confirm an account to anyone.

#### S19 — The phone is searched at a checkpoint, at an arrest, or by family (research-raised)

**Path**
1. ✅ **The neutral app name.** "Attune" doesn't say dating, which is a real advantage over Grindr (04 §2.1.7).
2. ⚠️ **The app opens without a PIN** unless one is set. `AppPrivacyCover` hides the app-switcher preview [C].
3. ❌ **Notification history** shows "New mutual match" (F-4). **The image cache** holds introduction photos. **Dating-chat local cache:** its length isn't designed yet.
4. ❌ **The officer forces the PIN.** Quick exit is a way out, not a duress PIN.

**Harm.** Device evidence drives these prosecutions (Rigot 2022 [M]; HRW 2023 [M]; Article 19: "just having a dating app on your device can be enough to get arrested", 01 §2.7).

**Minimal fix**
- **[Code, P0]** Neutral pushes; quick exit wipes dating caches; no gallery saves; `FLAG_SECURE`.
- **[Code, P1]** Introductions are never cached on the device. The chat cache holds only the last N messages.
- **[Code, P1]** The discreet icon (04 Q11).
- **[Lawyer + DV reviewer, P2]** A duress PIN. It could be read as obstruction, and needs legal review first.

#### S20 — The server-side list: a state demand, a breach, or an insider (research-raised)

**Path**
1. ❌ **If same-gender matching is on in Ghana,** Attune's database holds a list of Ghanaian users seeking the same gender, with introductions and chats. That is a target list under a duty-to-report law (04 Impl 8).
2. ❌ **A Ghana-based moderator** could be compelled, or could leak (04 Q9).
3. ⚠️ **Breach precedents:**
   - Tea: verification selfies in an old open bucket;
   - M.A.D Mobile: hard-coded secrets;
   - Raw: an IDOR flaw, where changing an ID in a request exposed another user's data.

   Attune already deletes the selfie in the same call and uses RPC-only reads (04 §2.3). Its own anon-readable `analysis_sessions` incident shows RLS regressions happen here (MEMORY, 04 §2.3).

**Harm.** Mass outing and prosecution, and loss of trust in the whole app.

**Minimal fix**
- **[Policy, P0]** The S3 decision: if it is off, no such data exists. That is the strongest protection.
- **[Code, P0]**
  - Application-level encryption of the gender and preference columns.
  - Admin views exclude preference and gender.
  - A dating RLS/RPC canary in CI.
  - Secret scanning.
  - A storage-bucket policy test.
  - No ad or analytics SDK on Dating.
  - One external penetration test (04 Impl 13, 17).
- **[Lawyer, P0]** A law-enforcement request policy: valid legal process only; notify the user unless prohibited; Attune hands over only what it keeps (04 Impl 8, Q12).

#### S21 — A first meeting at a private address (research-raised)

**Path**
1. **Day 5:** "Come to mine, I'll cook." ❌ No rule covers pressure to meet at a private address.
2. ✅ **Strawman:** "Plan a meet?" at day 7–10, a first-meeting kit, "Share my plan" with time and place but no name or photo.
3. ⚠️ **The after-date check-in** ("I'm OK" / "Get help"). Any automatic alert to the trusted contact when she doesn't answer would be a safety notification to a third party. That conflicts with the constraint.

**Harm.**
- Assaults after dating-app meetings cluster at the first meeting, often at the perpetrator's home, and often with impairment (Rowse 2020 [W]).
- Strangulation occurs in about a third of cases (Valentine 2022 [M]).
- Robbery and kidnap set-ups are reported in Nigeria [A] (03 §2.9; 02 §2.2).

**Minimal fix**
- **[Code, P1]** A `meet_private_pressure` education family, recipient-only, for everyone.
- **[Code, P1]** "Get help" opens emergency numbers behind a confirmation, plus a **pre-written message the user sends herself** to her trusted contact. Nothing is sent automatically.
- **[DV reviewer]** The copy.

#### S22 — A single parent targeted for access to children (research-raised)

**Path**
1. ⚠️ **"Has children: yes"** is a yes/no field (03 Impl 17).
   - ❌ If "open to a partner with children" becomes a filter people can *seek* on, it lets predators target single parents.
   - In an Australian national survey, 12.4% of users reported requests to help sexually exploit children (AIC TI 658 [S], 03 §2.9).
2. ❌ **Early messages** such as "send a picture of your daughter" or "when can I meet the kids alone" match no rule family.

**Minimal fix**
- **[Policy, P0]** "Has children" is used as shared ground and as the *parent's* own filter, never as a filter others can seek on.
- **[Policy, P0]** Ban children's photos in moderation, and add a child-safety report category.
- **[Code, P1]** A `child_access` tier-2 family (asks for children's photos, to be alone with them, or early questions about their school or schedule): recipient education plus the queue. CSAM hash-matching as in S16.

### 2.3 Scenario summary

| # | Scenario | Decisive fix | Priority | Type |
|---|---|---|---|---|
| S1 | Scam crew, AI photos | Liveness + CompareFaces; enforcement survives deletion; mask until mutual swap; Ghana lexicon | P0 | Code + Human |
| S2 | 16-year-old, false DOB | Facial age estimation + liveness + ID fallback; underage hold closes matches; CSAM hashing | P0 | Code + Policy |
| S3 | Gay man in Ghana; entrapment gang | Same-gender off in Ghana / Tier 1–2; nothing sent or stored | P0 | Policy + Lawyer + Code |
| S4 | Traveller | Neutral pushes; cache wipe; traveller detection | P0/P1 | Code |
| S5 | Controlling partner checks | "Never introduce me to these numbers"; new-device re-verification; no lookup | P0 | Code + Policy |
| S6 | Ex in introductions | Lock `users.phone`; HMAC from `auth.users`; generation needs the key | P0 | Code |
| S7 | Recycled number | Dating re-verification on new device; dormancy without DOB-only unlock | P0 | Code |
| S8 | Sextortion | Report after unmatch + snapshot; sextortion card + category; resources v2 | P0 | Code + Reviewer |
| S9 | MoMo / airtime ask | Ghana lexicon; Unicode normaliser | P0 | Code + Reviewer |
| S10 | Interested to everyone | Phone-HMAC blocks; throttle | P0/P1 | Code |
| S11 | Malicious report, appeal | Category + human appeal; corroborated holds | P0 | Policy + Code + Human |
| S12 | Opinion identifies partner | Per-post handles; neutral push; hide at 2 | P0 (before promotion) | Code + Policy |
| S13 | Crisis in Opinions or journal | `self_disclosure` before Gemini; static support link; report reason | P0 | Code + Clinician |
| S14 | Breakup, both date | F-1 fix; never-introduce list; gentle-wait copy | P0 | Code + Clinician |
| S15 | Every trace gone | Exit = hard delete; cache wipe; export | P0/P1 | Code + Lawyer |
| S16 | Minor invited to couple | DOB before accept; server age check; CSAM hashing | P0 | Code + Policy |
| S17 | Family phone | Neutral push; per-user invite key; PIN prompt | P0/P1 | Code + Policy |
| S18 | Secretly partnered | Attestation + category; never a partner signal | P0 | Policy |
| S19 | Phone searched | Cache wipe; no intro cache; discreet icon | P0/P1 | Code |
| S20 | State demand / breach | Don't collect; encrypt; CI canary; LE policy | P0 | Policy + Code + Lawyer |
| S21 | First meeting at home | Meeting kit; user-sent help message | P1 | Code + DV reviewer |
| S22 | Single parent targeted | Children not a seeking filter; child-access family | P0/P1 | Policy + Code |

---

## 3. Implications for Attune

### 3.1 Must-have before launch (P0), ranked

Ranking weighs lethality, how many scenarios a requirement covers, and the gap between what the specs promise and what the code does.

| Rank | Requirement | Scenarios | Type | Done when |
|---|---|---|---|---|
| 1 | **Same-gender introductions off in Ghana and every Tier 1/2 country**, enforced before transmission, plus the versioned tier table and per-country kill switches for Dating and for same-gender matching | S3, S4, S19, S20 | Policy + Code + Lawyer | No RPC, log or analytics event carries a gender/preference pair from an "off" country. The server refuses it as well. Switching a country off takes effect at the next generation run. |
| 2 | **Close the identity holes:**<br>• `users` column grants;<br>• HMACs from `auth.users.phone`;<br>• enforcement records, blocks and confirmed-report counts that survive deletion, keyed by phone HMAC;<br>• reports anonymised, not deleted, when the reporter deletes;<br>• generation refuses to run without the exclusion key. | S1, S6, S8, S10, S11, S14, S15 | Code (+ Lawyer for retention) | A CI contract test passes for: delete → re-register → tamper with `public.users.phone` → still excluded, blocked and restricted. |
| 3 | **Real age assurance at Dating activation:**<br>• liveness plus facial age estimation, challenge age 25, ID fallback;<br>• DOB at sign-up and before `accept-invite`, with a server age check;<br>• an `underage_risk` hold that closes matches;<br>• CSAM hash-matching on every image upload. | S2, S16, S22, S1 | Code + Policy | No path reaches an introduction or a linked relationship without an age result. A hash-match hit leads to a hold and the escalation runbook. |
| 4 | **Reporting and enforcement that work when they're needed:**<br>• report from history for 30 days after unmatch, block or deletion;<br>• an evidence snapshot;<br>• new categories: sextortion, suspected entrapment, hiding a relationship, child safety;<br>• P0 interim holds with a corroboration rule;<br>• the category shown and one human appeal by a second reviewer;<br>• a minimal console and runbook;<br>• a named moderator who reads Twi, Ga and Pidgin. | S8, S11, S1, S2, S18, S22 | Code + Policy + Human | P0 reports reach a human within 4 h in staffed hours (24 h at most). Restricted users see the category and an appeal button. |
| 5 | **Device discretion:**<br>• neutral text on every Dating push (replace "New mutual match");<br>• quick exit wipes dating and chat caches;<br>• a PIN offered at Dating setup;<br>• `FLAG_SECURE`, no gallery saves, a minimal local Dating cache. | S4, S5, S17, S19, S3 | Code | No Dating word appears on a lock screen. A quick-exit test shows the dating caches empty. |
| 6 | **"Never introduce me to these numbers,"** a keyed-HMAC symmetric hard filter | S5, S6, S14, S17 | Code | Adding a number excludes that number's account before its next generation run and never notifies its owner. |
| 7 | **Dating chat built to spec,** plus:<br>• text only;<br>• masking ends only on mutual Swap;<br>• a Ghana and diaspora `financial_request` lexicon;<br>• a Unicode-safe normaliser;<br>• the sextortion card;<br>• blocks enforced in RLS. | S1, S8, S9 | Code + Reviewer | Golden fixtures pass in English, Pidgin and Twi spelling. A stale client cannot send after a block. |
| 8 | **Trust friction:** liveness plus CompareFaces against every photo; a 72 h cool-off; at most 3 introductions a day; same country by default; cross-border opt-in for verified users | S1, S3, S10 | Code + Policy | — |
| 9 | **Dating re-verification on every new device,** before any Dating screen renders, plus the dormancy rule with no DOB-only unlock | S7, S5 | Code | — |
| 10 | **Support resources v2:**<br>• routed by country;<br>• the emergency number first;<br>• CSA 292;<br>• sextortion and StopNCII;<br>• help that isn't the police;<br>• `verified_at` on every entry. | S8, S9, S3, S13, S21 | Code + Reviewer | — |
| 11 | **Exit and deletion that mean it:** exit hard-deletes; pair history anonymised after the evidence window; the privacy policy says what survives | S15, S20 | Code + Lawyer | — |
| 12 | **Writer-facing crisis routing on journal save before Gemini;** a static "Need support now?" link and a self-harm report reason in Opinions | S13 | Code + Clinician | A test proves journal text that matches the corpus never reaches `gemini_json.ts`. |
| 13 | **Opinions:**<br>• unlinkable posts;<br>• no guest author histories;<br>• neutral push previews;<br>• auto-hide at 2 for "identifies a real person";<br>• a pre-post contact-detail filter (Apple 1.2). | S12 | Code | — |
| 14 | **Server minimisation and breach gates:** application-level encryption of gender and preference; admin views exclude them; RLS canary in CI; secret scanning; a bucket policy test; a penetration test; no analytics SDK; a law-enforcement request policy | S20, S3 | Code + Lawyer | — |
| 15 | **Compliance for the launch countries:**<br>• Ghana DPC registration;<br>• a DPIA;<br>• the Art. 9 consent screen;<br>• the CSAE page and a child-safety contact;<br>• for the UK: Online Safety Act assessments and highly effective age assurance;<br>• for the US: BIPA/CUBI biometric consent (when enabled). | S2, S20 | Lawyer + Policy | — |
| 16 | **One-person rules:** the not-married attestation; the terms; never confirming an account to anyone; children never a seeking filter | S18, S5, S17, S22 | Policy | — |
| 17 | **Scope `pending_invite_code` per user** (06 R4) | S17, S16 | Code | — |

### 3.2 Before public launch or promotion (P1)

- Traveller detection (IP plus Android SIM/network country) and a user-controlled Travel mode (S4).
- The discreet icon for everyone (04 Q11), and an optional Dating lock (S5, S19).
- A dragnet throttle, duplicate-opener hashing, Dating activations per device, and repeated money asks (S1, S10).
- The first-meeting kit; Share my plan without name or photo; a user-sent "Get help" message; the `meet_private_pressure` and `child_access` families (S21, S22).
- An opt-in contacts exclusion (S5, S14), and the 30-day "new accounts can't hide their photos" rule (S14).
- Platform age signals (S2, S16); passkeys or a registration-lock PIN (S7).
- The author-only Opinions crisis detector under its own clinical spec (S13).
- Your own Dating data in the export (S15).
- Law-enforcement cooperation on sextortion with the victim's consent, and a quarterly transparency summary (04 Impl 30).

### 3.3 Can wait (P2)

- In-app voice and video. 03 Q5 and 02 Q7 favour early voice, but it adds a calls stack to moderate.
- Media in dating chat with blur and hash-matching (04 Q5).
- Face templates to catch banned scammers (04 Q8: no in v1).
- A duress PIN.
- Guardian or wali roles (03 Q4).
- Faith filters (a cultural decision, not a safety one).
- Apple and Google sign-in.
- The outcome panel.
- External moderation vendors.
- Cross-border expansion beyond the pilot countries.

### 3.4 Who has to sign off

| Item | Lawyer | Clinician | DV specialist | LGBTQ+ safety reviewer | Moderator / cultural reviewer |
|---|---|---|---|---|---|
| Same-gender matching in Ghana and Tier 1/2; owner and staff exposure under s.104 and the bill's platform clause; moderator exposure (S3, S20) | **Ghana** | — | — | **Yes** (West African context) | — |
| Law-enforcement request policy; transparency; duress PIN (S19, S20) | Ghana, UK | — | Yes | Yes | — |
| Retention of enforcement records and phone HMACs after deletion; what exit deletes; dating data in the export (S1, S15) | Ghana, UK/EU (Art. 15/17) | — | — | — | — |
| Highly effective age assurance, children's-access and illegal-harms assessments; cyberflashing (S2) | **UK** (OSA) | — | — | — | — |
| BIPA/CUBI biometric consent; COPPA neutral screen; Texas, Utah and Louisiana app-store laws; NCMEC reporting (S2, S16) | **US** | — | — | — | — |
| DPIA, Art. 9 consent, EU/UK representatives (S20) | EU/UK | — | — | — | — |
| Ghana DPC registration; defamation from Opinions posts (S12) | Ghana | — | — | — | — |
| Gentle-wait copy and length (S14) | — | **Yes** | Yes | — | — |
| The `self_disclosure` corpus; journal and Opinions crisis cards (S13) | — | **Yes** | Yes | — | — |
| Sextortion card; post-assault and "Get help" copy (S8, S21) | — | Yes | **Yes** | Yes | — |
| "Never introduce me" list; copy for controlling-partner situations (S5) | — | — | **Yes** | — | — |
| Twi, Ga, Ewe and Pidgin scam lexicon; school-age cues; reversal scam (S1, S2, S9) | — | — | — | — | **Yes** |
| Polygamy and married-user wording; intention options (S18) | — | — | — | — | **Yes** (faith advisers) |
| Appeals, P0 holds, SLAs (S11) | DSA/OSA check | — | — | — | **Yes** (named person) |

### 3.5 Per-country launch recommendation

**Principle:** worldwide-capable, enabled country by country (04 Q3, Impl 31). Elsewhere, Dating shows "Not in your area yet," with Just for me suggested (05 Q13).

| Country or group | Tier (04 §2.1.6) | Dating at launch | Same-gender matching | Conditions before switching on |
|---|---|---|---|---|
| **Ghana** | 1 | **On** (pilot) | **Off** (S3) | P0 list complete; DPC registration; a Ghanaian legal opinion on the whole Dating product; a Twi/Ga/Pidgin moderator; CSA 292 in resources; an age-estimation vendor with West African error data; a Ghana Card ID fallback |
| **United Kingdom** | 3 | **On**, once highly effective age assurance and the OSA assessments are done | **On** | An Ofcom-recognised age-estimation vendor; OSA children's-access and illegal-harms assessments; a UK representative; Action Fraud in resources; text-only chat covers the cyberflashing duty |
| **United States** | 3 | **Next phase** (1b) | **On** | BIPA/CUBI consent and a published retention schedule; Declared Age Range; a neutral age screen |
| Ireland, Germany, Netherlands, Italy, France (EU) | 3 | Phase 2 | On | Art. 27 representative; DPIA; Art. 9 consent; DSA notice-and-action and statements of reasons |
| Canada, South Africa | 3 | Phase 2 | On | Local privacy law (PIPEDA, POPIA); South Africa's lure-robbery note (04 §2.1.3) |
| Nigeria | 1 | Phase 2, men–women only, after the Ghana pilot measures scam volume | Off | NDPC registration; "kito" entrapment and a 14-year sentence (04 §2.1.3) |
| Kenya | 2 | Phase 2, men–women only | Off | Family Protection Bill on the watchlist; ODPC registration |
| All other Tier 1, including Senegal, Niger, Mali, Burkina Faso, Egypt, Tunisia, Morocco, Lebanon, Uganda, Gulf states, Indonesia, Malaysia, Russia, Türkiye | 1 | **Off** | Off | — |
| All other Tier 2 | 2 | **Off** | Off | — |
| Everywhere else | 3 | Off until the per-country checklist passes | — | 04 Impl 31 |

**Travellers:**
- Dating keeps working against the traveller's home pool.
- Same-gender visibility is auto-hidden while in a higher tier.
- Pushes are neutral, and a one-time in-app note is shown (S4).
- Nobody is ever introduced to people *in* a country where Dating is off.

---

## 4. Open questions for the owner

| # | Question | Recommendation |
|---|---|---|
| Q1 | Same-gender introductions in Ghana at launch? 04 Q1 says yes with protections; 03 Q3 says no. | **No.** Show only the other gender, with an honest "Why?". Nothing is stored. Reconsider after a legal opinion, consultation with LGBTQ+ groups, and every Tier 1 protection built. The S3 walk shows that enumeration and the duty-to-report risk are structural, not tunable. |
| Q2 | Which countries get Dating at launch? | **Ghana** (men–women) and the **UK** (once age assurance is in place, same-gender on), then the US. Everywhere else shows "Not in your area yet" (§3.5). |
| Q3 | Liveness plus facial age estimation for *every* Dating user, worldwide? | **Yes.** It is the only control that addresses S1, S2 and S7 together. Set the challenge age from vendor data and measure the ID-fallback rate. |
| Q4 | Keep enforcement records, blocks and report counts as phone HMACs after an account is deleted? | **Yes**, with a stated retention period (for example 2 years) and counsel's sign-off. Without it, deleting an account is a ban-evasion and evidence-destruction tool (F-2). |
| Q5 | Revise spec §8 so a restricted user sees the category and can appeal once to a human? | **Yes.** No-reason bans are the top Ghanaian pain (S11). Never show who reported or what they wrote. |
| Q6 | Interim holds on P0 reports before human review? | **Yes, with corroboration:** two independent reporters, or a matching tier-3 trigger. Otherwise priority review without a hold. That keeps `underage_risk` from being used as a weapon (S11). |
| Q7 | Build "Never introduce me to these numbers" now? | **Yes (P0).** It is cheap, reuses the exclusion pattern, and is the only answer to the fishing profile and to exes outside Attune (S5, S6). |
| Q8 | Change every Dating push to neutral text, including "New mutual match"? | **Yes.** "You have something new in Attune." |
| Q9 | Should contact masking end only on a mutual Swap, not automatically after 72 h? | **Yes** (F-11). |
| Q10 | Should exit hard-delete Dating data, rather than marking it exited? | **Yes.** Pause is the reversible option. Exit deletes the profile, preferences, gender, photos and messages. Pair history is anonymised after the evidence window (S15). |
| Q11 | Should new accounts be unable to hide their photos for their first 30 days? | **Yes,** except for any future Tier 1 same-gender protection. It blunts catfishing and exes evading the exclusion (S14). |
| Q12 | Who is the safety owner, who is the moderator, and who covers P0 reports out of hours? | **Name both before the pilot.** Size the pilot area to what one moderator can cover. Use honest "Not in your area yet" copy, not a numbered waitlist (02 Impl 13). |
| Q13 | Store face templates to catch banned scammers? | **Not in v1** (agrees with 04 Q8). Accept the residual risk; phone-HMAC records and device signals cover most of it. |
| Q14 | Use the journal's Gemini analysis before `self_disclosure` runs on it? | **No.** Wire the check first (F-7). Until then, pause the journal analysis call. |
| Q15 | Per-post handles in Opinions before it is promoted as "write without judgment"? | **Yes** (07 Q2). S12 shows the permanent handle is how a partner finds the rest of someone's posts. |

---

**Return summary for the caller:** see §3.1 (ranks 1–5) and §3.5. This file: `/Users/user/attune/docs/superpowers/research/2026-10-24-flow-dating-research/10-scenarios-risk.md`.

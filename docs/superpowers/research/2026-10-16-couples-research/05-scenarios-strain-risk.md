# 05 — Strain and risk scenarios: how Attune behaves today, where it harms, what to change

**Date:** 2026-10-16. **Scope:** fourteen clinical scenario simulations run against the app as it exists on `main` (inventory `03`, verified against code where the inventory flagged a gap), scored against the evidence review (`02`) and the market record (`01`). Read-only; no app files were changed.

**Who wrote this, and how.** Three lenses were applied to every arc: a couples clinician (EFT / Gottman / IBCT), an intimate-partner-violence safety specialist, and a product strategist. Each scenario was walked step by step through the surfaces Attune actually ships: the couple's journal (Planning, Calendar/Together, Map), chat, check-ins/Pulse, Verdict and the translator, Ask Attune and AI Sessions, Healing, the safety system and quick exit, the couple map and the home-screen distance widget. Where a claim depends on code, the file is named.

**What was verified in code for this document (beyond `03`):**

- `lib/features/safety/domain/services/quick_exit_service.dart`: `requiresSafetyUnlock()` has **zero callers** outside the service. Quick exit writes the marker and nothing reads it. `_exitApp()` calls `SystemNavigator.pop()` on Android (not `finishAndRemoveTask()`) and does nothing on iOS.
- `TripleTapDetector` is mounted in exactly two places: `lib/home/home_screen.dart` and `chat_couples_locked_screen.dart`. Settings, Support resources, Planning entry screens, the journal, Healing and the full-screen map are not covered.
- `lib/features/safety/presentation/screens/safety_resources_screen.dart`: three hard-coded helplines (Ghana DOVVSU, US NDVH, UK Refuge), **no emergency numbers** (191/911/999 are absent from the screen despite being in the spec), phone numbers and URLs rendered as plain text (not tappable, no confirmation flow), the tip "Consider creating a safety plan for leaving quickly if needed" (prohibited by `SAFETY_SYSTEM_SPEC.md` §6.4), and "Not relevant right now" that simply pops the route (no server view session).
- `supabase/functions/_shared/chat_safety.ts`: nine phrases total (three per tier), English only. `normalizeForTokenPhrase` strips U+200B–U+200D/U+FEFF with the empty string, so a zero-width character inside a phrase defeats every rule (recorded as a known evasion in `ai_session_safety.ts`).
- `supabase/functions/_shared/ai_session_safety.ts`: a separate `sessions-1.0.0` corpus with eight self-harm phrases and eight coercion/persuasion phrases. It is wired to AI Sessions; whether `ai-understand` and `ai-assist` run it was not confirmed.
- `supabase/migrations/20260815120001_end_relationship.sql`: `end_relationship()` sets `status='ended'`, `ended_by`, and **`chat_archived_at = now()` in the same statement**. There is no read-only window; `CHAT_SYSTEM_SPEC.md` §2.1 says archived means "No read, no send, purge local cache". Decision 3's "30-day soft delete" and Decision 19's "read-only after end, archived when either starts a new relationship" are not what ships.
- `supabase/functions/`: a `delete-account` function exists; **no export function exists** for any surface. `ATTUNE_SOUL.md` §7 ("A couple can export their Attune data as structured files") is currently a promise without an implementation.
- `analyse-journal-entry` sends journal text to Gemini on close and contains no safety or crisis handling of any kind.
- No read-receipt opt-out, typing indicator or last-seen exists in chat. Read receipts are always on. Stories expose seen/not-seen only.

**Status vocabulary** follows `03`: LIVE, DEPLOY-PENDING, FLAG-OFF, BUILT-UNREACHABLE, PARTIAL, SPEC-ONLY, PLANNED. "AI crons paused" refers to `20260931150000_pause_ai_jobs.sql` (Layer 1 message analysis, Layer 2 session analysis, weekly Pulse and monthly Verdict are all unscheduled).

**Priority vocabulary.** P0 = safety-critical; must land before any real couple is onboarded. P1 = iatrogenic or trust-breaking; before public launch. P2 = material gap; first two quarters after launch. Confidence is about the recommendation, not the harm: High = direct evidence in `02` plus clinical consensus; Moderate = consistent evidence with design judgement; Low = clinical judgement with thin literature.

---

## Part A — The fourteen scenarios

Each scenario follows the same structure: (a) today, step by step; (b) harms; (c) evidence and clinical guardrails; (d) design changes within the soul's hard rules; (e) priority and confidence.

### Scenario 1 — Pursue–withdraw: the recurring chores fight, flooding and stonewalling

**Couple.** Ama and Kofi, cohabiting, Accra, two years in. Ama carries the mental load and pursues; Kofi floods and goes silent. The fight is about dishes; the need underneath is fairness and, for Kofi, rest.

**(a) Today.**
1. Ama types "You never do anything around here" into chat. She taps **Help me say this** (LIVE). The translator returns "I'm feeling stretched thin and I need us to share the load more evenly," with the private framing note "Underlying need: to feel fairly treated." She sends the rewrite. Kofi never knows (constraint 4). Good.
2. Kofi reads it. Read receipts are always on, so Ama sees "read" with no reply. She sends four more messages in eight minutes. The "read" tick is the pursuer's accelerant; nothing in the product names that.
3. Kofi is flooded. There is no pause tool, no agreed time-out message, no self-soothing card. He puts the phone down. Ama reads silence as contempt. Layer 2 would classify this session as pursue–withdraw with stonewalling and feed each person a private role insight, but **the Layer 1/2 crons are paused**, so nothing is learned and no personal insight is produced.
4. Ama opens Planning → Home & bills and assigns every checklist item to Kofi with due dates. The checklist assignee field is direct, not a proposal. Kofi's "Needs you" shows up to three unowned items due within 7 days; it never tallies, but a 14-item checklist with one assignee is a ledger that a human can count without the app's help.
5. Sunday: Ama does the weekly check-in (reminder push is a `debugPrint` stub, so she only does it because she is upset). Conflict health 2, Emotional safety 4. Kofi does not check in. If he had, both partners' answers would recompute the shared Pulse immediately and both would see the drop. Because only Ama checked in, the score waits for Sunday or a manual Refresh.
6. Verdict: unreachable (no route; cron paused). The one "Ask each other" conversation starter that would reframe the fight as a pattern never arrives.
7. No chores template, no fairness conversation, no appreciation mechanic exists (`03` §3).

**(b) Harms.**
- Read receipts without an opt-out are a pursue–withdraw amplifier. "You read it and didn't answer" is the most common escalation line in demand–withdraw couples, and Attune hands it over by default.
- The translator can make pursuit more eloquent without making it less relentless; there is no counterpart tool for the withdrawer ("stepping back, not away") and no flooding break. The product currently designs for the pursuer's lowest-ability moment and ignores the withdrawer's.
- The shared Pulse becomes a scoreboard the moment both check in after a bad week: "Conflict health is 31 because of you." `PULSE.md` §10 leaves "both see the same score" open; today it is shared.
- Checklist assignment is a ledger by proxy. The hard rule forbids app-generated tallies, but a shared list with a single assignee produces the same resentment.
- When Layer 2 is resumed without abuse-context suppression and the "pattern, not verdict" co-framing (`ATTUNE_RISK_SOLUTIONS.md` §2.3, §3), the first private insight ("you tend to withdraw") risks being read aloud in the next fight.

**(c) Evidence and guardrails.**
- Demand/withdraw is reliably harmful and stronger in distressed couples (Schrodt et al. 2014, 74 studies) — `02` §2.1. The target is the cycle, not the person: EFT's "the cycle is the enemy", IBCT's unified detachment (`02` §2.2, §3.2).
- Flooding: a flooded partner needs roughly 20+ minutes of genuinely distracting time, and must name when they will return (Gottman clinical; `02` §1.1, ranked mechanism #7). Stonewalling is physiological, not a character flaw (`ATTUNE_CLINICAL.md` §4.1).
- Gentle start-up predicts outcomes; active-listening drills do not (`02` §1.1, §4.1). Awareness programmes did as well as skills training (Rogge 2013).
- Felt unfairness to oneself predicts dissatisfaction more than the partner's share (Gillespie 2019); appreciation buffers unfair housework (`02` §6.3). Cognitive labour (anticipate, decide, monitor) is the invisible half (Daminger 2019).
- Do not: chore scoreboards, horsemen labels from text, positivity ratios (`02` §1.4, C6).

**(d) Design changes.**
1. **Pause chip** (composer, always visible, pull-only). Tapping it offers three fixed messages, never AI-written: "I'm getting flooded. I'm stepping back for 30 minutes, not away from you. I'll come back." / "I need a break to calm down. Back at {time}." / "I care about this. I can't do it well right now; can we pick it up tonight?" The message sends as an ordinary message. On the sender's side only, a 20–45 minute timer starts with a self-soothing card (breathing, a walk, a specific instruction not to rehearse the argument) and a return prompt: "Ready to come back? Start with how you feel, not what they did," opening a soft start-up scaffold in the composer. The partner's side shows the message and a single optional fixed reply, "Okay. I'll be here." No "pause mode" indicator, no timer visible to the partner, no counts anywhere, no Pulse input.
2. **Read receipts: symmetric off.** A setting under Chat: "Show read ticks". Either partner can turn it off; when either does, ticks disappear for both and the UI shows only "Sent". No attribution of who turned it off. Default on (market expects it); the option must exist before launch because of Scenario 3.
3. **Soft start-up path in the translator.** The existing button grows one sheet with two options: "Help me say this" (as now) and "Help me start this conversation" (observation → feeling → need → request). Same privacy, same equal-weight buttons.
4. **Chores without a ledger.** Add a "Who's carrying what" block to Home & bills: each recurring task lists an *owner*, including the noticing and planning parts ("Notices when we're out of gas", "Plans the week's meals"). No counts, no percentages, no due-date streaks. Add a private quarterly reflection in the weekly check-in flow: "How fair does your split feel to you right now?" (1–5, self-facing, never shared) followed by "Want to talk about it? Here's a way to start," which opens the soft start-up scaffold. Nothing about this reflection reaches the partner or Pulse.
5. **Pulse inference rule.** A shared dimension score does not move between weekly recomputes unless both partners have checked in that week; when only one has, the dimension shows its last value with the confidence dot at "waiting for both". Remove on-demand Refresh for check-in-driven dimensions (keep it for chat-aggregate dimensions once crons resume). This closes the private-answer inference hole that Scenarios 3 and 5 depend on.
6. **Before resuming Layer 2:** ship the co-framing line on every shared conflict insight and the one-directional abuse-context suppression flag (`ATTUNE_RISK_SOLUTIONS.md` §2.3 item 3), and route stonewalling signals through the per-market suppression default (§4 "start from silence").

**(e) Priority / confidence.** Pause chip P1 (High). Read-receipt symmetric off P0 because of Scenario 3 (High). Pulse inference rule P0 (Moderate). Chores block and fairness reflection P2 (Moderate).

---

### Scenario 2 — After an affair: repair, transparency demands, the slide into surveillance

**Couple.** Nadia discovered Tunde's six-month affair. They are trying. Nadia wants his location, his read receipts, his calendar, and answers. Tunde agrees to everything in week one and resents it by week four.

**(a) Today.**
1. Nadia asks Tunde to turn on the couple map. It is opt-in for both, ~1 km, updated only on app open, stale after 8 hours, with a silent symmetric pause (`2026-10-16-couple-map-design.md` §2). Tunde turns it on. Week three, he pauses it for an afternoon. The server returns no row, as if stale. Nadia sees "Just you on the map right now" and asks why. The app did not reveal the pause; the absence did.
2. Nadia turns on the busy overlay at "strips" (opt-in levels: off / free windows / strips). It shows 30-minute busy blocks for 14 days. She cross-examines a Tuesday 7–9pm block.
3. Tunde writes an apology in chat. He uses **Help me say this**; the rewrite preserves his meaning and does not make him "apologise for something undecided" (translator rule), which is fine, but there is no structure for an apology (acknowledgement, impact, repair, commitment) and the result is a warmer version of "I'm sorry you feel that way."
4. Nadia long-presses his message and taps **Understand** (LIVE). The AI returns "possible ways to read this" with confidence low or medium. For a betrayed partner reading an unfaithful partner's apology, two or three charitable readings is either false reassurance or fuel; the AI cannot know which. Nothing is saved, which at least prevents a dossier.
5. Chat search, starred and pinned messages work on the whole history. Nadia stars eleven messages from the affair period. The chat is not E2EE and is discoverable in proceedings (`ATTUNE_MASTER_SPEC.md` §12). The soul's "never generate content that could be used as evidence" governs AI output, not raw history; the raw history is already evidence.
6. Story's "On this day" shows a beach trip from the affair months. The Together spec excludes conflict moments from "On this day" but not memories that have since become painful.
7. Layer 2 would measure "repair attempted/landed"; paused. Verdict unreachable.
8. If Nadia writes "if you leave me again you'll regret it" three times in 30 days, Tier 3 fires and **Tunde** receives "Some resources are available". That is correct routing and will read as absurd to both if they ever compare notes; the push is neutral enough that they will not.

**(b) Harms.**
- The product's presence features (map, busy strips, read ticks) are exactly the "transparency" an affair-recovery couple reaches for, and exactly the tools Freed et al. describe abusers using with ordinary authenticated access. Clinically, early transparency agreements are common but *time-limited, negotiated, and revocable*; an app that makes monitoring frictionless makes the sunset harder.
- Silent pause protects Tunde and inflames Nadia; the product cannot and should not fix that offline, but its copy currently gives the paused partner no language for it.
- AI readings of a partner's intent during betrayal recovery are iatrogenic in both directions. The feature's scope guard (readings only, low/medium confidence) is not sufficient for this use.
- Memory resurfacing (On this day, story pins, Planning "Date nights: what we loved") re-traumatises without consent.
- No therapist handoff exists at the point where the evidence says a clinician is indicated (infidelity crisis is on the C2 escalation ladder).

**(c) Evidence and guardrails.**
- Infidelity crises belong on the escalation ladder to couple therapy (`02` C2). Forgiveness is beneficial only when the offender signals safety and value through amends; otherwise it erodes self-respect (Luchies 2010, `02` §6.8). Apologies work through acknowledging responsibility and offering repair; the request for forgiveness is the least important component (Lewicki 2016).
- Monitoring tracks insecurity and perceived intrusion lowers satisfaction (`02` §10.1, (b) table). Location sharing is a primary coercive-control vector (§13.3 item 2).
- Clinical consensus outside `02` (noted as CC): staged affair-recovery models (impact → meaning → moving forward) treat transparency as a temporary scaffold agreed in session, not as a product feature.
- Trauma-informed resurfacing rules: no surprise resurfacing of painful content (`02` §12.8, §14.3).

**(d) Design changes.**
1. **Map copy and sunset.** Map onboarding and settings carry one line both partners see: "Sharing your area is a choice you can change without explaining. It is not a way to check on someone." When sharing has been on for 90 days, each partner gets a private, dismissible "Still want this on?" card — once, no nag, no partner visibility. Busy overlay at "strips" gains the same 90-day private check.
2. **Hide a period.** In Story and Our story, either partner can privately hide a date range from *their own* resurfacing surfaces (On this day, memories from this ritual, map pins). Nothing is deleted; the partner is not told; the range is stored per user.
3. **Apology helper.** Under the translator button: "Help me apologise". A four-field scaffold (what I did; what it cost you; what I'll do to repair; what I'll do differently), each field the user's own words; one optional AI tidy pass with the existing constraints; the output never includes a request for forgiveness and never suggests the recipient's response. Private; sends as an ordinary message. The receiving side has no "accept apology" control and no forgiveness status, ever.
4. **Understand guardrail.** Add to the Understand eval set: betrayal interrogation, "is he lying", and affair-adjacent pastes. The footer copy changes to: "These are guesses from the words alone. Only they know what they meant. If this is about trust, a trained outside perspective helps more than a reading." The link opens the handoff card below. No keyword gating; this is a fixed footer on every Understand result.
5. **"A trained outside perspective" handoff card** (stigma-aware wording from `ATTUNE_CLINICAL.md` §9.3), reachable from Pulse, Settings and the Understand footer: what couples counselling is, what to look for (IBCT, EFT, BCT, a clinician who screens each partner separately), how to find one in the user's country, and a line about individual support. No directory in v1; a reviewed outbound link list per country. **Never shown as "recommended for your relationship"**; it is a resource card, not an insight.
6. **Starred/pinned messages are per-user and private** (verify; if shared, make private).

**(e) Priority / confidence.** Hide a period P1 (Moderate). Apology helper P1 (High for structure, Moderate for app delivery). Understand footer and handoff card P1 (High). Map sunset card P2 (Moderate).

---

### Scenario 3 — Coercive control through the app; the at-risk partner wants out safely

**Couple.** Kwame set up Attune on Efua's phone and knows her unlock code. He insists the map stays on, watches read ticks, reads the shared Pulse, scrolls her Planning and calendar, and has twice taken her phone to "check who she's talking to". Efua has decided to leave and is planning it with her sister.

**(a) Today.**
1. **Map.** Both opted in, under duress on her side. Efua can pause (silent, symmetric, reads as stale) or turn off (deletes silently). The design is right: the server returns no row, resuming needs a fresh sample, nothing says why it stopped. The confrontation happens offline; the product did not add to it.
2. **Read ticks.** Always on. Kwame knows the minute she reads anything. No opt-out.
3. **Pulse.** Check-in answers are private, but the dimension scores are shared. He checks in with all 10s; she answers Emotional safety 2. If both checked in, the shared score recomputes at once and he can read her answer from the drop. "Show You ✓ Jordan ✗" is still an open suggestion in `PULSE.md` §10; if built, it tells him when she has answered.
4. **Chat safety.** If he writes "you'll regret it" and "if you leave" in separate messages across a month, Tier 3 fires on the third distinct match and Efua gets "Some resources are available" (max one push per 24 h). If he writes "ur gonna regret it", nothing. If he types "if you lea​ve", nothing. Nine phrases, English only.
5. **The push lands on the phone he checks.** Lock-screen body is neutral. If he opens it, it routes to Support resources: three countries, no emergency numbers, non-tappable text, "plan for leaving quickly" (which he now knows she has read). The quick exit button on that screen sends her to the "Daily overview" decoy; on relaunch, **the app opens straight back into Attune** because the PIN marker is never read. On Android `SystemNavigator.pop()` leaves the task in Recents.
6. **Triple-tap** works only inside the home shell and the locked-chat screen. From Settings, Support resources, a Planning entry, the journal or the full-screen map it does nothing.
7. **Account.** Phone OTP only. He has her SIM when he wants it. There is no list of active sessions, no "sign out everywhere", no login notice to the account owner, so he can keep a session on his own device indefinitely.
8. **Leaving.** `end_relationship()` ends instantly and archives chat in the same transaction. The lifecycle sync pushes the other partner. Separation is the highest-lethality window (Campbell 2003; `02` §13.1). Attune announces it.
9. **After.** Dating exclusion by phone HMAC prevents a re-introduction (good). Healing is offered; Healing screens have no safety link and no triple-tap. Account deletion takes 30 days.

**(b) Harms (ranked by severity).**
1. **Unilateral end pushes the controlling partner at the moment of separation.** This is the single most dangerous behaviour in the product today.
2. **No PIN gate after quick exit.** The decoy is cosmetic.
3. **No device/session control.** The adversary is authenticated; `02` §13.3 item 5 is unmet.
4. **Read ticks and shared Pulse leak her private state** (timing of reading; Emotional safety answer by inference).
5. **Resources are geo-blind, contain prohibited advice, and are not usable (no tappable, confirmed call path).**
6. **Keyword coverage is a placeholder**, and the normaliser has a trivial bypass.
7. Quick exit coverage is partial; Healing/journal are uncovered.

**(c) Evidence and guardrails.**
- `02` §13.3, all nine principles, especially 2 (symmetric, revocable, silent revocation), 3 (unilateral exit and data separation), 4 (quick exit and discretion), 5 (account security assuming the adversary knows the passcode), 6 (AI stops coaching when control is disclosed), 9 (no evidence logs).
- Freed et al. 2018: abusers use ordinary UIs and shared accounts; Chatterjee 2018: dual-use apps. Griffith/eSafety: stopping sharing is read as distrust and provokes anger (`01` §2.7).
- Separation and escalation are recognised danger periods; strangulation and weapon threats multiply homicide risk (`02` §13.1).
- Conjoint tools are contraindicated with coercive control; separate, private screening before any couple work (Bograd & Mederos 1999).
- Market: "Some people cannot say no to the app" (`01` §7 item 2). Exit must be safe and face-saving.

**(d) Design changes.**
1. **End relationship v2 (see Part D for the data model).** Ending never sends a push, SMS or email to the other partner. The other partner discovers it on next app open with a neutral, warm in-app screen. The ender chooses nothing about notification; there is no option to notify, because the option itself would be coerced. Optional "Pause first" path (status `paused`, which already exists in the enum): chat read-only, map off, AI off, calendar read-only, no push.
2. **Safety PIN gate, enforced.** On cold start and on resume from background, if the marker is set, show the PIN screen before any Attune UI; biometrics alone do not clear it; five failures add escalating local delay; recovery is "sign out" only (per spec until DV review approves another path). PIN setup is offered the first time a user opens Support resources and from Settings; quick exit works without a PIN (falls back to sign-out on return).
3. **Quick exit everywhere.** Mount the triple-tap target in the root shell above GoRouter, not per screen. Android: `finishAndRemoveTask()` via the audited channel. iOS: as spec §7.3.
4. **Account security.** Settings → "Where you're signed in": device list, last active (owner-only), "Sign out all other devices". New-device sign-in notice delivered in-app to the account owner only (never by SMS to a number that may be held by the partner). No partner-assisted recovery of any kind.
5. **Read ticks symmetric off** (Scenario 1 item 2) and **Pulse inference rule** (Scenario 1 item 5). In addition, **Emotional safety becomes a self-facing dimension**: each partner sees their own Emotional safety; the shared Pulse is computed from the other four. An aggregate "emotional safety" across a coercive dyad is meaningless to the safe partner and dangerous to the unsafe one.
6. **Resources v2.** Country routing from SIM/locale with a manual country picker; emergency number first; DV line; crisis line; sexual-assault line; international directory fallback for unsupported countries; tap-to-call with the monitored-device warning and confirm (spec §6.4); remove "leave quickly"; DV-authored planning copy; verification records per §6.5. Offline cache.
7. **Private safety check.** A 4-item, self-facing check adapted from HARK with clinician input ("Do you ever feel afraid of your partner?" and similar), offered privately at Ask-2 and once a quarter from Pulse, answerable "prefer not to say". Stored in a separate table with `auth.uid()`-only RLS, never in `psych_profiles`, never shown to the partner, never a Pulse input. A positive screen: shows resources once; sets a one-directional flag that suppresses conjoint conflict tools (Part C) and Layer 2 both-sides framing for that relationship; the flag is invisible to both partners and expires after 180 days unless renewed.
8. **Phrase list and normaliser.** Replace the placeholder with a DV-reviewed list including Tier 2 monitoring/control families ("send me a photo of where you are", "who are you with", "show me your phone", "you're not going", with cultural variants), fix zero-width stripping to a space, gate by language eligibility, add fuzz and golden fixtures.
9. **Journal and Healing**: Support resources entry on every screen; see Scenario 4 for the journal lock.

**(e) Priority / confidence.** Items 1–4, 6, 8: **P0 (High)**. Item 5: P0 (Moderate for the Emotional safety split, High for the inference rule). Item 7: P0 as a gate on the conflict toolkit; P1 for standalone launch (Moderate, needs clinical authorship). Item 9: P0 (High).

---

### Scenario 4 — Physical violence disclosed in the journal or in chat; the partner may read the phone

**Couple.** Adwoa was hit last night. She has not told anyone. She opens Attune's journal because it is the only private place on her phone, and later types something to her partner.

**(a) Today.**
1. Adwoa writes in the Reflection Journal: "He hit me again last night. I'm scared to go home." On close, the entry is sent to Gemini (`analyse-journal-entry`), which returns a tone and an NVC observation/feeling/need, e.g. "Tone: fearful. You may be feeling afraid and needing safety." No resource is offered; nothing else happens. The journal is private by RLS and offers no device-level lock; if her partner opens the app, he can read it. There is no triple-tap on journal screens.
2. She writes to him in chat: "You hit me. Don't ever do that again." The detector scans **incoming** messages for **recipient-directed** threats. Her disclosure matches nothing; she is the sender. He receives it normally.
3. He replies: "I'll kill you if you tell anyone." "kill you" matches Tier 1. She receives "Some resources are available", at most once in 24 hours. The push is neutral. If he has her phone, he can open it and reach the resources screen without a PIN. If he writes "ill end u", nothing fires.
4. In AI Sessions she types "my husband hit me, where can I go tonight". The sessions corpus covers self-harm and persuasion phrases, not victim disclosure. The model's scope is IDEAS/NEARBY; the system prompt turns everything else into a generic REDIRECT with the standard resources link. The response is a polite deflection at the moment she asked for help.
5. In Truth or Dare, truth answers pass through safety detection (`process-truth-answer-safety`) with the same recipient-directed phrase families; a disclosure in a truth answer is not matched.
6. Months later, "On this day" could resurface a story from the week it happened. Journal entries are not resurfaced (the journal has no memory surface); good.

**(b) Harms.**
- **A language model reflects on an assault disclosure as if it were an ordinary feeling.** This is clinically wrong (it normalises), privacy-wrong (the disclosure leaves the device for a provider whose retention terms are unverified, gate G2), and misses the one moment a resource would land.
- **Victim disclosure is invisible to the safety system by design** (`SAFETY_SYSTEM_SPEC.md` §1.4 excludes sender-authored statements and journals). The exclusion is correct for the recipient-only routing model; it is not a reason to have no model at all.
- **The journal is readable by anyone holding the unlocked phone.** The single most private surface in the product has the weakest device protection.
- **Coverage gaps** in the phrase list turn the "guardian" into a demonstration.
- **No strangulation or weapon copy anywhere**, although these are the two highest lethality markers.

**(c) Evidence and guardrails.**
- C1: detect and route; AI halts coaching on abuse, fear, strangulation, sexual coercion or threats; warm, non-judgemental response; localised crisis resources; never partner notification (`02` C1, §13.3 item 6).
- Non-fatal strangulation: OR 6.70 for attempted homicide, 7.48 for homicide (Glass 2008). Weapon threats ~20× (Campbell 2003).
- Screening: brief validated tools; support services reduce harm (USPSTF 2018). Writer-facing routing is the app analogue.
- SAMHSA trauma-informed principles: safety, trustworthiness, voice and choice; do not re-traumatise (`02` §12.8).
- Soul §8 and constraint 6: safety never LLM-dependent. The design below keeps that: the detector is deterministic; the LLM is *suppressed*, not consulted.

**(d) Design changes.**
1. **Writer-facing disclosure routing (new spec, per SAFETY §1.4's requirement for a separate routing model).** A second deterministic phrase corpus, `self_disclosure-1.0.0`, DV- and clinician-reviewed, with two families: *victimisation* ("hit me", "choked me", "strangled me", "raped me", "forced me", "threatened to kill me", "afraid of him/her", "won't let me leave", plus reviewed Ghanaian-English and Twi-in-Latin-script variants) and *self-harm* (the sessions corpus's eight phrases, extended). Routing model: **the writer is the at-risk user.** Surfaces: journal text on save, chat messages on send (sender-side evaluation on the server, result routed to the sender only), AI Sessions / Understand / Assist input before any provider call, truth answers, Healing reflections.
2. **Response when matched.** (a) The AI step for that entry/message/request is **skipped** and the text never leaves Attune's database for a provider; the journal shows no reflection card for that entry. (b) An inline, private card appears for the writer only: "If someone has hurt you or you don't feel safe, support is here," with Support resources (country-routed), and, for strangulation/weapon matches, the DV-authored line: "Being choked or strangled is a medical emergency as well as a serious danger sign. If you can, see a doctor and tell someone you trust." (c) Nothing is stored about the match: no event row, no flag, no analytics; the card is derived at render time from the server's response to the save/send call and is not persisted. (d) The partner receives nothing, and no chat UI state changes. (e) Quick exit is on the card.
3. **Journal lock.** Optional separate lock (device biometrics or a 4-digit code independent of the safety PIN) for the journal, offered once when the first entry is written and available in Settings. When locked, journal previews do not appear in "Conversations: latest reflection".
4. **Resources v2** (Scenario 3 item 6) with sexual assault and medical lines.
5. **AI Sessions redirect copy for disclosure matches** says the same thing as the journal card rather than the generic IDEAS/NEARBY redirect; because the deterministic pre-check runs before the provider call, this does not route through the model (constraint 6 intact) and the refusal is still indistinguishable to the *partner* in shared sessions (requester-only, no revision bump, as A1 requires).
6. **PIN gate and triple-tap everywhere** (Scenario 3).

**(e) Priority / confidence.** Items 1, 2, 4, 6: **P0 (High)**. Item 3: P0 (Moderate; the lock must not become a tell — the lock screen should be plain). Item 5: P0 (High).

---
### Scenario 5 — Depression and suicidal ideation in one partner; the other is overwhelmed

**Couple.** Yaw has been low for months. Akosua is exhausted, scared, and has become his only support. One night he writes, "Everyone would be better off without me."

**(a) Today.**
1. In chat, the sentence arrives at Akosua. The detector is recipient-directed; a sender's self-harm statement is excluded "while a separate self-harm protocol is designed" (`SAFETY_SYSTEM_SPEC.md` §1.4, `THESIS` §6.8). Nothing fires for either of them.
2. Akosua long-presses it and taps **Understand**. Unless `ai-understand` runs the sessions corpus (unverified), Gemini returns two or three "possible readings" of a suicidal statement and two or three reply options. This is the worst plausible output of the whole product: an AI coaching a frightened partner on how to reply to a suicide signal with "confidence: low".
3. In a private AI Session, Yaw writes "no reason to go on". The sessions corpus matches; he gets a generic redirect plus the Support resources link — which lists three domestic-violence helplines and no crisis line. There is no 988, no Samaritans, no Ghana mental-health line anywhere in the code.
4. In the journal, Yaw writes the same sentence. Gemini returns "Tone: hopeless. You may be needing rest." No resource.
5. Weekly check-in: his Connection 2, Emotional safety 3. If both check in, the shared score drops and Akosua reads the drop as "our relationship is failing" rather than "he is ill." The 08:00 daily summary continues cheerfully. A Planning Progress block hitting 100% posts a celebration in chat regardless of context (the chat spec's "nothing celebratory fires on message content" does not cover Planning-originated celebrations). First-message-of-the-day shimmer fires.
6. Care cards exist only for creator-marked big days; nothing supports the partner of someone who is unwell. No psychoeducation, no "vent or solve" templates, no referral copy.

**(b) Harms.**
- **AI engagement with a suicide signal** (Understand, journal reflection) without routing. Even a perfect "reading" is the wrong act; the right act is a resource and a human.
- **Crisis resources are DV-only.** The one link the product offers after a self-harm match points at the wrong service.
- **The supporter is unsupported.** Caregiver burden is a recognised dyadic-coping problem (`02` §6.7, §12.4), and Attune's responsiveness prompts (care cards) only cover good-stress events.
- **Celebratory surfaces fire blind.** Confetti in a painful week is the exact failure `CHAT_SYSTEM_SPEC.md` names.
- **Shared Pulse drop reads as relational blame** for what is an individual health event.

**(c) Evidence and guardrails.**
- C1 crisis routing: detect, halt coaching, warm response, localised crisis lines; minimal data; no risk scores shown (`02` C1). Escalation ladder to individual support; never conjoint-only framing (C2).
- Dyadic coping and support matching (vent vs solve) predict satisfaction; stress spillover makes partners attribute illness to character (`02` §6.7, mechanisms #9–10).
- Clinical consensus (CC, outside `02`): asking directly about suicide does not increase risk; safe-messaging guidelines (no method detail, no framing as a solution); safety planning is clinician- or line-led, an app's job is connection to it.
- Decision 28: the AI is never a companion; a crisis flow must therefore be fixed copy and resources, not a dialogue.

**(d) Design changes.**
1. **Self-harm family in the writer-facing corpus** (Scenario 4 item 1), active on chat (sender), journal, AI Sessions/Understand/Assist, truth answers, Healing. Match → provider call skipped; private card to the writer: "If you're thinking about ending your life, you deserve support right now," with the country's crisis line first, then a DV line, then "Talk to someone you trust tonight". Fixed copy, clinician-authored, reviewed by a suicide-prevention specialist. No partner notification. Nothing persisted.
2. **Recipient-facing supporter card.** When the *recipient* of a chat message is the partner of a self-harm match, show the recipient a private card: "If someone you love is talking about not wanting to be here: ask them directly, stay with them, and here is who can help." This is a second routing path that is safe precisely because there is no perpetrator; it must never label the partner, never say "the app detected", and must be reviewed by the same specialist. Both cards derive from the same deterministic match; neither is persisted.
3. **Understand/Assist deterministic pre-check.** Run the writer-facing corpus on the pasted/long-pressed text before any provider call; on a self-harm or victimisation match, return the supporter card instead of readings. This is requester-only and indistinguishable from an ordinary redirect in shared sessions.
4. **Crisis catalogue.** Extend the versioned resource model (`SAFETY_SYSTEM_SPEC.md` §6.2) with `category ∈ {emergency, dv, crisis, sexual_assault, addiction, grief}` and per-country rows: e.g. 988 (US), Samaritans 116 123 (UK), Ghana's Mental Health Authority line and Lifeline-type services — every number verified by the owner within seven days of release and quarterly, per §6.5; this document deliberately does not assert any number it cannot re-verify.
5. **"Having a hard time" private status.** A self-set, private, 14-day switch under Pulse that: silences first-message shimmer, Progress celebrations and AI-idea tone for that user; swaps the daily summary to a plain list; and offers, once, a fixed-template line the user can choose to send to the partner ("I'm in a heavy patch. I may be quieter; it isn't about you."). No partner visibility unless sent. Not a Pulse input. Not a mood tracker.
6. **Supporter content** under Conversations: a clinician-authored card "When your partner is struggling" (how to ask, how not to fix, how to look after yourself, when to involve a professional) and the vent/solve/sit-with-me request templates as fixed chat chips.
7. **Pulse rule** (Scenario 1 item 5) plus confidence copy: when one partner's check-in is markedly lower than their own baseline, the shared score shows "this week looks different for one of you" rather than a number movement. (Careful: this must not reveal *who*; phrase as "for one of you" only when both have checked in; otherwise show nothing.)

**(e) Priority / confidence.** Items 1–4: **P0 (High)**. Item 5: P1 (Moderate). Item 6: P1 (High). Item 7: P2 (Low–Moderate; the phrasing risk is real and should be clinically reviewed).

---

### Scenario 6 — Heading for breakup: one wants to try, one is done; then the breakup and co-parenting

**Couple.** Nana wants to fight for it; Kojo has already left in his head. They have a four-year-old. Three weeks later Kojo ends it in the app.

**(a) Today.**
1. Nana proposes rituals (State of the Union), 36 Questions chapter 1, date nights. Each is a proposal and lands in Kojo's "Needs you" (max three, 7-day quiet expiry). He lets them expire. The product is correctly consent-based; it also quietly documents his disengagement to her, three cards at a time.
2. Nana checks the shared Pulse every day and taps Refresh. The score is a thermometer she reads as a prognosis. The confidence dot says "medium". The verdict that might reframe it is unreachable.
3. Ask-2 anchors ("what you admire about your partner") are months old. Love map shows "34 of 60". Nothing in the product can honestly say "one of you is done"; nor should it.
4. Kojo taps End relationship (Settings). It runs `end_relationship()`: status `ended`, `chat_archived_at = now()`. **Neither can read the chat again.** Four years of messages, photos, voice notes, the Baby template with the due date, Trips, the shared calendar including the child's events, the expenses with an unsettled "To even out", story pins — gone from both phones at once. There is no export. Nana receives a push that the relationship has ended. Both are offered Healing; the "Healing from a breakup?" card appears on the locked chat screen.
5. The ICS feed and calendar mirror: the server purge removes presence; whether the per-user hashed ICS keeps serving ended events was not verified.
6. Co-parenting: nothing. Family members (name, birthday) belong to the couple; the child's birthday reminder dies with the relationship.
7. Dating: former-partner exclusion by phone HMAC. Healing Stage 2 uses a derived evidence snapshot of shared patterns, never messages. Good.

**(b) Harms.**
- **Instant archive on a unilateral end destroys shared memories and shared logistics for both people**, the two angriest failure modes in the market (Between's photos; Couple's unpair; `01` §5 items 1–2, §7 item 5). For a co-parenting pair it also removes the one shared calendar they most need next week.
- **No export, contradicting the soul** (§7) and `02` C5 ("unilateral leave-and-delete… and download it").
- **A push announces the ending.** Between's "CANCELED" email is the cited anti-pattern (`01` §2.4). For non-abusive couples it is cold; for Scenario 3 it is dangerous.
- **No pause or soft end** for the ambivalent partner (`paused` exists in the enum only).
- **The shared Pulse as a daily prognosis** during a slow ending feeds rumination; contact and re-checking slow recovery (Sbarra & Emery 2005).
- Proposals as a disengagement log: not a bug, but the copy around expired proposals should never total them.

**(c) Evidence and guardrails.**
- Graceful decoupling: data separated, archive-or-delete choice, memory resurfacing off immediately (`02` §15.2). Contact with the ex slows recovery; structured reflection helps (Sbarra; Larson & Sbarra 2015).
- Co-parenting quality is modifiable and child outcomes track interparental conflict; post-separation is a high-risk IPV period (`02` §15.1–15.3).
- Soul §7: users leave with their data. Decision 3: either can unlink; 30-day soft delete. Decision 19: read-only after end; archive when either starts a new relationship.
- Market: no app in the corpus offers a designed, compassionate, safe breakup flow (`01` §7 item 5).

**(d) Design changes.**
1. **End relationship v2** (full model in Part D). States: `active → paused` (either partner; chat read-only; map, AI and proposals off; no push; 30-day prompt to decide), `active|paused → ended` (either partner, instant, irreversible for the relationship record; **no push**; in-app discovery), `ended → archived` (per-person "seal my side now", or automatically after a 30-day read-only window, or immediately when either person starts a new relationship, whichever is first). Read-only means: read messages, view Planning/Calendar/Story, no sends, no edits, no presence, no AI, no proposals, no Pulse.
2. **Export before seal.** From the read-only screen: "Download what's yours" produces a structured bundle (JSON + media): the full chat text (both sides already possess it), the user's own media, Planning entries and blocks, calendar events, the user's own stories and moments, their own check-in answers and journal. **Excluded always:** anything AI-derived about the partner, the partner's private surfaces, safety data, translator logs. Export is also available at any time during an active relationship (soul §7).
3. **Ending copy** for the person who discovers it: "Kojo has ended your shared space. For the next 30 days you can read and download what you shared. After that it's sealed. When you're ready, a private healing journey is here." No "ended_by" framing beyond the name; no reasons field; no reply affordance.
4. **"Keep the family calendar"** at end: if `family_members` exist with `relation = child` (requires the relation type the inventory says is missing), offer both partners a separate, businesslike shared calendar and list surface for the child only: events, handovers, school dates. No chat, no map, no presence, no AI, no Pulse, no "Needs you". Either can leave it at any time. Until built, at minimum preserve child birthday reminders per user at end.
5. **Pulse during a slow ending.** Remove daily Refresh (Scenario 1 item 5). When a relationship is `paused`, Pulse is hidden entirely.
6. **Proposal expiry copy** never counts ("3 proposals expired this month" is banned); expired proposals simply disappear from both sides.

**(e) Priority / confidence.** Items 1–3: **P0** for the no-push rule and the read-only window (High); export is P0 for the data-rights promise (High). Item 4: P2 (Moderate). Items 5–6: P1 (Moderate).

---

### Scenario 7 — Grief: miscarriage; loss of a parent; partners grieve differently

**Couple.** Abena and Kwesi lost a pregnancy at 14 weeks. They had started the Baby template. Kwesi's mother died in the spring; her birthday is in the family list.

**(a) Today.**
1. The Baby gallery template holds a due date; a Countdown block pushes at 08:00 on the day. The daily summary will say "Today: due date". Nobody has archived it because archiving a plan is a logistics act and they are not thinking about logistics.
2. The family member "Mama Esi" has a birthday reminder that auto-created on entry; it will fire next spring with ordinary birthday wording.
3. Story's "On this day" will surface last year's "we're pregnant" moment next year. The Together spec excludes conflict moments from On this day; grief is not a conflict.
4. Abena journals and wants to talk; Kwesi fills his calendar (busy strips at "strips" show her exactly how full). She reads the busy blocks as avoidance. Layer 2 would call it withdraw; paused.
5. Love map's weekly refresh offers "What are they most afraid of losing right now?" Ask Attune Ideas suggests "a celebratory dinner".
6. Nothing in the product says that partners grieve differently, and no grief resource exists.

**(b) Harms.**
- **Automated celebration of a loss** (due-date countdown, birthday of the deceased, On this day). Each is a designed Peak-End moment inverted.
- **Grief-style difference read as not caring**, which predicts lower satisfaction (Büyükcan-Tetik 2017), with the busy overlay as the evidence.
- **Tone-deaf AI ideas** and prompt banks.

**(c) Evidence and guardrails.**
- Perceived similarity of grief matters more than actual congruence; psychoeducation that different pace and style is not a lack of love (`02` §12.5). No cheerful resurfacing of a deceased child, pet or parent without consent; route to grief support.
- Trauma-informed design: predictable flows, no surprise resurfacing, choice over what is shared (`02` §12.8).
- Relational savouring is helpful when chosen; forced nostalgia is harmful (`02` §14.3).

**(d) Design changes.**
1. **"Put this away gently."** On any Planning entry with a Countdown or on the Baby/Wedding templates, an action that archives the plan, cancels its pushes and removes it from Recent and On this day, with copy: "Keep this somewhere quiet. Nothing will remind you about it unless you come back." Either partner can do it; the other sees the plan move to "Put away" with no notification.
2. **Family member "has passed".** Converts the birthday reminder into an optional remembrance (default off), with remembrance wording if turned on ("Mama Esi's birthday. Thinking of her today.") and never birthday wording.
3. **Private grief setting** ("Going through a loss"): per person, no partner visibility; for a chosen period it suppresses On this day, celebratory surfaces, AI idea generation tone (Ideas adds a "quiet" constraint), Love map's fears/dreams domains, and the shimmer. Offers once a fixed-template line to send: "I'm grieving in my own way right now. If I'm quieter or busier, it isn't distance from you."
4. **Grief card** under Conversations, clinician-authored: "People grieve differently", including the busy-vs-talk difference, and localised grief/perinatal-loss resources in the catalogue (Scenario 5 item 4).
5. **Busy overlay copy** when one partner is in the grief setting is unchanged (no leak); the grief card instead teaches the reading.

**(e) Priority / confidence.** Items 1–2: P1 (High; cheap and the harm is certain). Items 3–4: P1 (Moderate). Item 5: n/a.

---

### Scenario 8 — Infertility treatment stress

**Couple.** Lydia and Femi, third IVF cycle. Appointments, injections, timed intercourse, money, and two very different ways of coping.

**(a) Today.**
1. Cycle tracking is PLANNED, not built; that absence is currently protective.
2. Clinic appointments go into the calendar. Private events are the creator's alone and surface only as "busy"; shared events show titles. Lydia makes them shared because Femi should know; the calendar becomes a treatment log both re-read.
3. Expenses: IVF costs entered per cycle; split opt-in; "To even out" per entry. The money is visible every time either opens Home & bills.
4. The Baby template sits in the gallery as an aspiration they cannot start.
5. Sliding Scale's "children" statement feeds Pulse Alignment; a 9 vs 6 reads as mismatch though both want a child and one is protecting themselves.
6. Timed intercourse: there is no sexual content in the product, so nothing schedules sex; nor is there any language for the desire collapse that treatment causes.
7. Opinions feed: tags include "anniversary", "breakup", "sex"; pregnancy content appears without a mute.
8. Femi copes by not talking; Lydia reads active avoidance as abandonment.

**(b) Harms.**
- Baby-centric templates and feeds in an infertility couple's face (`02` §12.6 names this explicitly).
- Treatment logistics in a shared, re-readable calendar when one partner wants it to be private and the other wants to be included — no per-event "busy only to you, full to me" nuance beyond private/shared.
- A values game turning protective coping into a visible mismatch.
- A future cycle feature that nudges a partner about fertile windows would convert sex into an assignment (Loewenstein 2015; `02` §8.3).

**(c) Evidence and guardrails.**
- Congruent perceptions of infertility stress predict adjustment; a partner's active-avoidance coping raises the other's distress (Peterson 2006/2008). Separate emotional check-ins; avoid baby-centric marketing, pregnancy announcements, family-planning nudges; treatment logistics in the calendar only if chosen (`02` §12.6).
- Dyadic coping and support matching (`02` §6.7).
- Assigned sexual frequency backfires (`02` §8.1).

**(d) Design changes.**
1. **Gallery personalisation.** "Hide this for us" on any gallery template (either partner; silent; reversible in Settings). Onboarding never asks about children to decide this; the control is the user's.
2. **Per-event visibility level:** private / busy-only / shared, already partly present; add "shared with the title hidden" so a clinic appointment can be known-but-unspoken.
3. **Cycle tracking hard rules** written into the future spec now: phase sharing is opt-in by the tracker only; the partner never receives a fertile-window or "good day" nudge; no intercourse logging; the feature degrades to nothing during a declared treatment period if the user chooses.
4. **Support-request chips** (vent / help me decide / just sit with me) as fixed chat chips; no AI.
5. **Resource catalogue** adds fertility counselling lines; the handoff card covers "someone trained in this".
6. **Sliding Scale**: show divergence as "you answered differently" without a direction or a Pulse penalty; review the "children" item's wording with the clinical advisor.
7. **Opinions tag mute** per user.

**(e) Priority / confidence.** Items 1, 3, 7: P1 (Moderate). Items 2, 4–6: P2 (Moderate–Low).

---

### Scenario 9 — Military deployment / FIFO work: long absence, blackout, reintegration

**Couple.** Sergeant Mensah deploys for seven months; a three-week communication blackout in month two; FIFO-style rotations after. Serwaa is home with two children.

**(a) Today.**
1. **Operational security.** The couple map shows a ~1 km area updated on app open and stale after 8 hours. For a deployed soldier who opens the app once a day from a forward base, this publishes an approximate location of a military position to a civilian phone, and the distance widget's medium size draws a region map on Serwaa's home screen. No name, no app name, but a map.
2. Blackout: the map goes stale (fine). The widget falls back to the reunion countdown (allowed; "a countdown to being together is allowed, a count of time apart is not"). The reunion date comes from a calendar reunion event; deployment dates slip.
3. Pulse: Serwaa checks in alone for three weeks; the shared score does not move (no both-check-in trigger) or recomputes on Refresh with stale aggregates and a confidence dot.
4. Stories, voice notes, streak clips, the dual clock and the free-window finder are strong here (`03` §3 LDR). The "Next visit" template exists.
5. Reintegration: he returns to a house whose routines he does not know. Proposals pile up; "Needs you" shows three. Chores reassign. There is no reintegration content.
6. The 08:00 daily summary fires in each person's local time (good).

**(b) Harms.**
- **OPSEC leak** via map granularity and widget region map; the product has no "work-sensitive" posture beyond pausing.
- **Countdown disappointment** when dates change; a hard date on a home screen is a promise the military does not make.
- **Reintegration turbulence** (Knobloch & Theiss) hits the at-home partner hardest; proposals-as-friction add to it.
- Idealisation during absence followed by reunion instability (Stafford & Merolla).

**(c) Evidence and guardrails.**
- LDR quality equals or exceeds proximal relationships; the risk is reunion transition and uncertainty, not distance (`02` §9.1). End-date certainty and a shared plan matter; a review date works when the date is unknown.
- Relational turbulence after deployment; anticipatory savouring buffers distress (Froidevaux & Borelli 2023). Army PREP with deployment content reduced divorce at the higher-risk site (Stanley 2014).
- Avoid constant-contact pressure and location as a trust feature (`02` §9.3).

**(d) Design changes.**
1. **Map: "My location is sensitive" posture.** A per-user choice at map onboarding and in settings that keeps sharing off and explains that the partner sees exactly what they see when it is stale. Widget: the region map becomes a separate opt-in from the distance text, defaulting off; for distances ≥ 800 km the medium widget shows text only unless the opt-in is set.
2. **Tentative reunion.** A reunion event can be marked "date may change"; the countdown then shows "Soon" with the month, never a day count, and no 08:00 push on the day until confirmed.
3. **"Coming home" ritual template** (Together): five fixed prompts before and after return (routines, space, roles, children, sleep), each answered privately then shared by choice; skippable; one-time, no counts. Content reviewed with a military family specialist.
4. **Blackout-aware confidence.** When one partner has had no app activity for 7+ days, Pulse shows "not enough recent data from both of you" and does not recompute shared dimensions; nothing about *who* is shown.
5. **"Our plan" card** in the LDR distance card: next visit, review date, one shared sentence. Non-judgemental when no end date exists.
6. **Anticipatory savouring prompt** in Story before a reunion: "One thing you're looking forward to together," private, optionally shared.

**(e) Priority / confidence.** Item 1: P1 (High for the leak; Moderate for the exact granularity rule). Items 2, 4: P1 (Moderate). Items 3, 5, 6: P2 (Moderate).

---
### Scenario 10 — Addiction in one partner (alcohol / gambling) with financial harm

**Couple.** Kofi's sports betting has emptied the rent twice. Adjoa found out from the landlord. He promises; she covers; the cycle repeats.

**(a) Today.**
1. Home & bills shows a Bills table with "Paid by" per row and an Expenses block with a shared pot, per-entry opt-in split, "To even out" and an append-only audit. No cross-entry totals (D6, D13). Adjoa can see that three rent entries say "Paid by: Adjoa"; she cannot see a total, but she can scroll.
2. He deletes a message admitting the loss; the tombstone remains ("message deleted"). She stars his promises.
3. She writes "I won't cover rent again if you bet." Help me say this rewrites it: the rule "never soften a legitimate concern to nothing" and "never add false warmth" protect the boundary in principle; the eval set does not include boundary-statements, so this is untested.
4. He writes "if you leave I'll have nothing" — matches nothing. "you can't survive without me" is in Tier 3; the reverse dependence is not.
5. Ask Attune refuses financial advice (correct). There is no route to gambling or alcohol help anywhere in the product; the resources screen is DV-only.
6. Pulse: Alignment's "money" statement in Sliding Scale; nothing else sees money.
7. Apology helper does not exist; his apologies are promises; her forgiveness is the doormat pattern.

**(b) Harms.**
- **No addiction resource** at the moment it is disclosed or fought about.
- **Planning money becomes the fight's exhibit** even without totals; the per-row "Paid by" is an attribution the hard rules otherwise avoid. The counter-case: the audit trail protects the financially harmed partner from gaslighting, and removing it would hurt her. Keep the audit; change the framing.
- **Financial control is undetectable** (coercive control beyond keywords is "thin by design", `03` §3). Addiction and coercive financial control co-occur; the product cannot tell them apart and should not try.
- **Forgiveness pressure** through warm defaults; a translator that over-softens a boundary is harm.

**(c) Evidence and guardrails.**
- Financial unfairness predicts relationship quality more strongly than housework (Gillespie 2019); never force financial disclosure because financial control is an abuse tactic (`02` §12.1).
- Forgiveness without amends erodes self-respect (Luchies 2010); apology components (Lewicki 2016). Substance misuse is on the escalation ladder to professional help (`02` C2).
- Behavioural couple therapy for alcohol use disorder has an RCT base (CC, outside `02`: O'Farrell & Fals-Stewart), but it is clinician-delivered and screens for violence first.

**(d) Design changes.**
1. **Resource catalogue** gains `addiction` (gambling and alcohol lines per country) and the handoff card gains a "someone trained in this" variant; both reachable from Support resources without a trigger.
2. **Money date ritual template** (Together): fixed prompts (what money meant in your family; what you're afraid of; one decision for this month), private-then-shared, no balances, no AI.
3. **Translator eval cases:** boundary statements, refusals, and "I will not" sentences must survive rewriting with their boundary intact; add to the golden set and the server-side prohibited-pattern check (no rewrite may remove a negation that expresses a limit).
4. **Apology helper** (Scenario 2 item 3) is explicit that a promise is not a repair; the scaffold's fourth field asks for one concrete, checkable action, and the copy says so.
5. **Bills "Paid by"** stays (it protects the harmed partner) but the column header becomes "Covered by" and the row never colours or badges a name; no per-person filter, no sum.
6. **Personal money notes** live in the journal (already private); surface a journal shortcut from Home & bills ("Keep private notes").

**(e) Priority / confidence.** Item 1: P1 (High). Items 3–4: P1 (Moderate). Items 2, 5, 6: P2 (Moderate).

---

### Scenario 11 — Cultural and family pressure: interfering in-laws; an arranged-marriage couple building intimacy after the wedding

**Couple A.** Esi and Kwabena, Kumasi: his mother expects weekly visits, money every month and a grandchild by next year; Esi's "boundaries" vocabulary comes from Instagram, Kwabena's obligations are non-negotiable to him.
**Couple B.** Fatima and Yusuf, married four months after a family-arranged introduction; fond, careful, not yet intimate in conversation or in bed.

**(a) Today.**
1. Family members hold a name and a birthday; no relation types; `about_member_id` has no UI. There is no in-law conversation tool, no visit planning, no holiday rotation.
2. Expenses: monthly remittance to his mother appears as a shared-pot entry; Esi's resentment has a line item.
3. Esi uses Understand on his "Maa needs 500 cedis again" and gets readings; the model's training distribution makes "set a boundary with his mother" the most likely framing. The constraint "never attribute negative behaviour to a named or implied partner" does not cover third parties; the AI may characterise his mother.
4. The translator's NVC rewrite ("I feel… I need…") is direct in a way that can read as disrespectful in a high-context register; `ATTUNE_CLINICAL.md` §9 flags NVC's cultural fit as open, and the "communal obligation" seventh need is undecided.
5. Layer 2, when resumed, may score Kwabena's respectful silence as stonewalling (`CLINICAL` §9, `RISK_SOLUTIONS` §4 "start from silence" is the stated default).
6. Couple B: 36 Questions chapter 1 and the Love map "history" domain are a good fit. This-or-That's tones include Spicy (flirting) and Intimate (emotional; both must consent; clinical sign-off pending). The default tone and the community-question bank are not reviewed for a couple at this stage. No faith layer exists; Sliding Scale has one religion item.

**(b) Harms.**
- **Western individualist scripts delivered by AI** into a collectivist conflict; "family allocentrism increases commitment, unwanted control reduces it" (Bejanyan 2015) is a distinction no generic model draws.
- **Third-party attribution** by the AI (the mother-in-law) is a gap in the prohibited-pattern set.
- **Pace mismatch** for arranged couples: prompts that assume established intimacy; a Spicy prompt landing before the couple has a shared register for it.
- **Faith absent** for a Ghana-first product (`03` §3; `01` §2.8).

**(c) Evidence and guardrails.**
- Family involvement is not inherently negative; unwanted control is the problem (`02` §12.3). Offer options ("Some couples… others…"), never universal truths (`02` §12.9). Localise with community input.
- Self-disclosure escalation generates closeness; never make the deep end mandatory (`02` §6.5). Faith as an opt-in layer per partner; interfaith guides; never religious framing that discourages leaving abuse (`02` §11).
- `ATTUNE_CLINICAL.md` §9: Ubuntu counter-frame, communal obligation, referral language.

**(d) Design changes.**
1. **Seventh need: communal obligation** adopted in the translator and Layer 2 taxonomy (closes the CLINICAL open item), so a rewrite can say "I need us to decide together what we give" rather than forcing fairness/autonomy.
2. **Extend the AI prohibited-pattern set** to negative attribution of *any named third party* ("your mother is…", "his family always…"); add Ghanaian in-law scenarios to the Understand/translator eval sets with a cultural reviewer.
3. **Family and obligations guide** under Conversations, written with Ghanaian reviewers: visits, money, grandchildren, holidays; options-framed; private-then-shared prompts; no AI.
4. **Relation types and per-event visibility** for family members; a "Family" calendar filter; an optional "This month we're giving" entry that is a shared decision record, not a tally.
5. **Pace controls for new couples:** at Ask-2, a private question "How would you like prompts to feel for now? (gentle / open / playful)" per partner; the intersection sets defaults for This-or-That tone, Love map domain order (history first, fears last) and 36Q availability (chapter 1 only until both choose more). Either partner can change their own setting at any time; the partner never sees it.
6. **Faith layer** (opt-in per partner, `02` §11.2): prayer-for-partner prompt, sacred-values conversation, tradition holidays in the calendar; secular equivalents for everyone; interfaith guide. Hard rule added: no religious copy is ever used in safety, healing or ending flows.

**(e) Priority / confidence.** Item 2: P1 (High). Items 1, 5: P1 (Moderate). Items 3, 4, 6: P2 (Moderate–Low).

---

### Scenario 12 — Sexual intimacy breakdown after trauma; consent sensitivity

**Couple.** Afua survived an assault before she met Daniel. Two years in, sex has stopped. Daniel reads it as rejection; Afua cannot say why.

**(a) Today.**
1. There is no sexual content in the product ("Spicy" is flirting; "Intimate" is emotional safety; the explicit This-or-That examples were never seeded). The absence is protective. "Weekly intimacy challenges, personalised to love language, retention mechanic" sits on the Month-4 roadmap; as written it is the exact feature `02` §8.3 says not to build.
2. Daniel starts Truth or Dare, Intimate tone (both must consent; Afua consents to avoid the conversation). Truths run through the recipient-directed safety corpus; a private skip exists (good). Community questions are user-submitted; the corpus has no sexual-assault or non-consent block (Spicer's trauma-trigger failure, `01` §2.3).
3. Love map offers "What do they avoid talking about, even with you?" to Daniel about Afua.
4. Afua journals "I can't stand being touched since what happened." Gemini returns a tone and a "need". No sexual-assault resource exists in the product.
5. Daniel pastes her "please not tonight" into Understand. Readings are generated.
6. Layer 2 root-need detection (paused) would file their conflicts under "affection".
7. Ask Attune Ideas suggests a romantic night in.

**(b) Harms.**
- **A reflection bot handling an assault disclosure** (as Scenario 4).
- **Consent-adjacent features (Intimate tone, Truth or Dare) with a partner who consents to avoid conflict**; nothing in the product models revocation mid-session beyond the private skip.
- **Unmoderated community prompt bank** for assault content.
- **AI readings of a refusal** are a pressure vector however gently worded.
- **The roadmap line** would introduce desire pressure and love-language framing the evidence rejects.

**(c) Evidence and guardrails.**
- Sexual communication, not frequency, tracks satisfaction; assigned frequency backfires; responsive desire is normal; "no" is never something to overcome; all intimacy features mutual-opt-in, private-by-default, revocable (`02` §8). Trauma-informed principles as design rules; CBCT for PTSD is conjoint but clinician-led (`02` §12.8).
- Market: survivors want content warnings and opt-outs (`01` §3.3 item 23; Spicer, Coral, Love Nudge).

**(d) Design changes.**
1. **Writer-facing routing includes a sexual-assault family** (Scenario 4 item 1) with sexual-assault lines in the catalogue; the AI reflection is skipped for that entry.
2. **Per-person topic exclusions** ("Never show me prompts about: sex and bodies / alcohol / family / pregnancy / my past"), set privately, applied to every prompt bank (This-or-That, Truth or Dare, Love map, 36Q, community questions, Ideas). The partner never sees the list; the game simply skips. This is the single control that resolves the market's representation tension (`01` §4 LGBTQ+ / faith) as well.
3. **Community question moderation**: deterministic block list for assault/non-consent/coercion terms plus human review before publication; "report this prompt" on every community card.
4. **Revocation inside sessions:** Intimate/Spicy sessions carry a persistent "Switch to Connecting" control for either partner that changes the tone for both without saying who did it.
5. **Understand pre-check** (Scenario 5 item 3) adds refusal/consent phrases ("not tonight", "I don't want to", "stop") to a *do-not-interpret* family: the response is the fixed line "A no is complete on its own. If you want to understand more, ask them when you're both calm," with no readings.
6. **Replace the roadmap line.** Delete "weekly intimacy challenges… retention mechanic". If intimacy content is ever built: clinician-authored, opt-in per partner, yes/no/maybe with mutual-match-only reveal, responsive-desire education, no completion, no frequency, no tracking (`02` §8.2).
7. **Partner-facing education** card: desire after trauma; responsive desire; what pressure looks like; where to get help as a couple (sex-therapy referral copy, stigma-aware).

**(e) Priority / confidence.** Items 1, 5: **P0 (High)**. Items 2–4: P1 (High). Items 6–7: P1 (Moderate).

---

### Scenario 13 — Jealousy and phone-checking in a young couple (18–21)

**Couple.** Ama, 19, and Kwesi, 20, university, eight months together. Kwesi checks her phone "because that's normal"; one in five of their peers agree (eSafety; `01` §2.7). He wants the map on, asks why she paused it, counts how long she takes to read.

**(a) Today.**
1. The map's silent symmetric pause means a pause reads as stale; he asks anyway. Stories' seen/not-seen tells him when she looked at her phone. Read ticks tell him the minute she read. No typing indicator or last-seen exists (good).
2. He sends "who are you with", "send me a pic of where you are" — Tier 2 has none of these. "if you leave" ×3 would be Tier 3.
3. Truth or Dare dares; streak clips (1 or 3 views); view-once video. Screenshot behaviour on view-once is not specified; a 19-year-old's view-once clip is a coercion lever if it can be captured.
4. Opinions feed labels ("taken", "single") and forum debates about jealousy are available; the Scenario game has ten situations with "no correct answer", none about phone-checking.
5. Nothing in onboarding frames location sharing as *not* a trust test.

**(b) Harms.**
- **Normalising monitoring by offering it**: the map is approximate and symmetric, which is good engineering, but the onboarding copy currently treats sharing as a neutral feature rather than a choice that must stay free.
- **Seen-state and read ticks as surveillance primitives** for an age group most likely to use them that way.
- **Coercion phrases in the monitoring register are absent from the lexicon.**
- **View-once content** with unclear capture semantics.

**(c) Evidence and guardrails.**
- Location sharing read as commitment and stopping as distrust; anger at a partner stopping sharing is a red flag (Griffith; eSafety). Surveillance tracks anxious attachment; perceived intrusion lowers satisfaction; broader scope raises it (`02` §10.1). Read receipts, last-seen and location default off and mutual (`02` §9.3, §10.3).
- Relationship-awareness content works as well as skills drills (Rogge 2013), which makes a scenario-based "what healthy looks like" card an evidence-backed, cheap intervention.

**(d) Design changes.**
1. **Map and presence onboarding copy**, shown to each partner separately before opting in: "Sharing your area is not a test of trust. Either of you can pause or stop at any time, and the other side simply sees 'just you on the map'. If you feel you *have* to share, that's worth talking about with someone you trust." Link to Support resources without a trigger.
2. **Read ticks symmetric off** (Scenario 1) and **story seen-state off** as a paired setting ("Show when we've seen things").
3. **Tier 2 expansion** with monitoring-register phrases, DV-reviewed, with youth-register variants ("send pic", "where u at", "who's that").
4. **Scenario game** adds three clinician-written situations about phone-checking, location and passwords, with the "no correct answer" framing preserved but each option followed by a one-line reflection.
5. **View-once and streak clips**: document capture semantics; on platforms where capture cannot be blocked, say so in the send sheet ("Can't stop a screenshot. Send only what you'd be okay with being kept.").
6. **Private safety check** (Scenario 3 item 7) offered at Ask-2 regardless of age.
7. **Forum**: seed a FOR/AGAINST debate room on "Is sharing your location a sign of trust?" with a pinned eSafety-style explainer; anonymous by design.

**(e) Priority / confidence.** Items 1–3: P1 (High). Items 4–7: P2 (Moderate).

---

### Scenario 14 — Separation–reconciliation cycles; data and memories after breakup

**Couple.** Efya and Kojo break up every few months and get back together. Later, Efya re-partners with Kwame. The market's two sharpest failures live here: Paired restored "deleted" quiz answers for a new partner; Lasting showed a new partner the sessions completed with an ex-wife (`01` §5 item 4).

**(a) Today.**
1. Kojo ends the relationship. Chat archived instantly; Planning, calendar, stories, pins gone from both sides. Each is offered Healing. Efya starts it; Stage 2 builds a derived evidence snapshot from shared patterns (no messages); the ex is never notified.
2. Three weeks later they reconcile. One re-invites the other; a **new** relationship row is created. `CHAT_SYSTEM_SPEC.md` §2.1: when either enters another active relationship, the old chat is archived (already archived). Everything from before is unreachable; they start at zero: Pulse confidence "not enough data", Love map 0 of 60, Ask-2 anchors re-asked. Efya's active Healing journey is archived and her dating eligibility revoked (`HEALING_MODE_SPEC.md` §2.2). Correct, and invisible.
3. Personal insights (self-facing) persist with no relationship scoping visible in the UI; an insight like "In your last 8 sessions you tended to pursue" may be displayed in the new relationship about the old one. Quiz profiles are per user and persist (fine). Whether Love map answers and 36Q answers are relationship-scoped was not verified.
4. A year later Efya pairs with Kwame. Dating exclusion only matters in Dating mode; in Couples mode, Kwame sees nothing from Kojo's chapter (archive + RLS). The compatibility preview uses each person's own profile. Her old personal insights still exist; if any surface, Kwame could glimpse "pursue" language about a relationship he was not in.
5. Account deletion: `delete-account` runs the 30-day process; whether psych profiles, quiz answers, Love map answers and translator logs are hard-deleted (rather than soft-flagged) is the Paired failure to test for.
6. Photos: Planning photo blocks and chat images were never exportable; after archive they are inaccessible; retention of archived media is "indefinite" per the privacy section.

**(b) Harms.**
- **On–off couples lose everything each cycle** because reconciliation is modelled as a new relationship and archiving is instant.
- **Insights crossing chapters** (stale role insights shown in a new relationship) are a quieter version of the Lasting failure.
- **Deletion that is not provably deletion** (the Paired failure) is untested.
- **Indefinite retention of archived media nobody can access** is a liability with no user benefit.

**(c) Evidence and guardrails.**
- Graceful decoupling; turn off resurfacing immediately; do not keep exes connected by default (`02` §15.2–15.3). Unilateral leave-and-delete with a published split policy for shared artefacts (`02` C5).
- Market: clean breakup handling is a top unmet need (`01` §3.3 item 15); old data resurfacing is a top-15 pain (`01` §3.2 item 11); losing years of memories is item 12.

**(d) Design changes.**
1. **Reopen within 90 days.** If both former partners re-invite each other within 90 days of `ended_at` and neither has started another relationship, offer "Reopen our space" instead of a new row: the relationship returns to `active`, chat and Planning become writable again, Pulse resumes with a confidence reset, map and AI require fresh opt-in. Healing journeys stay private and archived. After 90 days, or if either declines, a new chapter starts.
2. **Chapter scoping.** Every per-user derived artefact (personal insights, translator logs, Love map and game answers) carries `relationship_id`; insights from a previous chapter are never rendered inside a new one. An RLS canary test runs in CI with two former partners and one new partner (the `RISK_SOLUTIONS` continuous-verification loop).
3. **Deletion is hard deletion.** Account deletion removes psych profiles, raw and aggregate quiz data, Love map and game answers, journal, Healing data and translator logs; the only survivors are the anonymised safety events the legal policy requires. A deletion-then-reregistration test proves nothing resurfaces.
4. **Archive retention.** Archived relationship media and messages are deleted 12 months after `chat_archived_at` unless a legal hold exists; both people are told this at ending and have the export window first (Part D).
5. **Memory resurfacing stops at `ended`,** not at archive: On this day, reunion countdown, widget, Live Activity and calendar mirror clear immediately (the widget already does).

**(e) Priority / confidence.** Items 2–3: **P0 (High)**; these are trust-catastrophe prevention. Item 1: P1 (Moderate). Items 4–5: P1 (High).

---
## Part B — Safety-critical fixes (P0), ranked, with acceptance criteria

Ranking weights lethality, breadth across scenarios, and the gap between what the specs promise and what the code does. Every item below is required before any real couple is onboarded. Each is consistent with the soul's hard rules; several merely implement rules already written in `SAFETY_SYSTEM_SPEC.md`.

| # | Fix | Scenarios | Acceptance criteria (all must hold) |
|---|---|---|---|
| **P0-1** | **Ending a relationship never notifies the other partner by push, SMS or email.** Discovery is in-app on next open. Add `paused` as a real state. | 3, 6, 14 | (1) `end_relationship()` enqueues no notification work; an integration test asserts zero rows in the notification outbox for the other member after an end. (2) The lifecycle-sync client path that pushes on `ended` is removed; the other partner's next app open renders the warm in-app ending screen. (3) A `pause_relationship()` RPC sets `status='paused'`; chat becomes read-only, presence rows are purged, AI functions refuse, proposals are frozen, Pulse is hidden; no push. (4) No copy anywhere says who ended beyond the partner's first name, and no reason field exists. |
| **P0-2** | **Safety PIN gate is enforced.** | 3, 4, 5, 12 | (1) On cold start and on resume, if `safety_requires_unlock` is set, the PIN screen is the first frame; no Attune UI, widget data or notification deep link bypasses it. (2) Biometric alone does not clear the marker. (3) PIN is stored as a salted KDF hash in the OS keystore; never synced. (4) Five failed attempts → escalating local delay; no data wipe. (5) Recovery = sign out to a generic signed-out state until DV review approves another path. (6) PIN setup is offered on first visit to Support resources and in Settings; quick exit works with no PIN set (return = signed-out state). (7) Real-device tests on Android and iOS, including app kill during the decoy. |
| **P0-3** | **Quick exit from every authenticated screen; Android task removal.** | 3, 4 | (1) The triple-tap target is mounted once in the root shell above GoRouter; a widget test asserts it wraps every named route including Settings, Support resources, Planning entry, journal, Healing, full-screen map, games. (2) Android invokes `finishAndRemoveTask()` through an audited platform channel; verified on three OEMs. (3) iOS renders the local cover within 200 ms and shows the app-switcher privacy image. (4) Activation sends no network request, analytics event or log. (5) Together and map device data clear (already true) and the widget opt-in resets. |
| **P0-4** | **Support resources v2: country-routed, usable, correct.** | 3, 4, 5, 10, 12 | (1) Resources load from the versioned model (§6.2) with `country_code` and `category ∈ {emergency, dv, crisis, sexual_assault, addiction, grief}`; country from SIM/locale with a manual picker; unsupported country → international directory plus "contact local emergency services". (2) Emergency number first in every country. (3) Tap-to-call and tap-to-open require a confirmation that states monitored-device risk; never auto-dial. (4) The tip "plan for leaving quickly" is removed; all planning copy is DV-authored. (5) At least one crisis (suicide) line, one sexual-assault line and one addiction line per launch country, each with a `verified_at` within 7 days of release and 90 days thereafter; expired verification blocks release. (6) Offline cache works. (7) Screen-capture protection where supported. |
| **P0-5** | **Writer-facing disclosure routing (victimisation + self-harm), deterministic, provider-suppressing.** New routing spec per `SAFETY_SYSTEM_SPEC.md` §1.4. | 4, 5, 12 | (1) A separately versioned corpus (`self_disclosure-x.y.z`) with DV, clinical and suicide-prevention sign-off; English plus reviewed Ghanaian variants; language-gated. (2) Evaluated server-side on journal save, chat send (sender), AI Sessions/Understand/Assist input, truth answers and Healing reflections, **before** any provider call. (3) On match: the provider call for that item is skipped and a test proves the text never reaches `gemini_json.ts`; the writer sees the private resources card; strangulation/weapon matches add the medical-emergency line; nothing is persisted about the match (no row, no flag, no analytics); the partner sees no UI change and receives nothing; in shared AI sessions the refusal is indistinguishable from a redirect and does not bump `revision`. (4) The recipient-facing supporter card for self-harm matches in chat never labels the partner and is clinician-reviewed. (5) Golden fixtures include quotation, song lyrics, third-party disclosure and negation; false positives produce only the same neutral card. (6) No detector code path imports an AI SDK. |
| **P0-6** | **Pulse cannot be used to infer a private check-in; Emotional safety becomes self-facing.** | 1, 3, 5 | (1) Shared dimensions recompute only when both partners have checked in for the week; otherwise they hold with a "waiting for both" confidence state. (2) On-demand Refresh does not recompute check-in-driven dimensions. (3) Emotional safety is removed from the shared score and shown only to its author; the shared score is re-weighted across the remaining four dimensions and the change is disclosed in the Pulse explainer. (4) The "You ✓ Jordan ✗" suggestion in `PULSE.md` §10 is closed as **no**. (5) No copy ever says "this week looks different for one of you" unless both checked in and clinical review approved the phrasing. |
| **P0-7** | **Read ticks and seen-state can be turned off symmetrically by either partner.** | 1, 3, 13 | (1) A single setting "Show when we've seen things" controls chat read ticks and story seen-state. (2) Either partner turning it off disables it for both; the UI never shows who turned it off; delivered state may remain. (3) Turning it back on requires both (so a controlling partner cannot re-enable alone). (4) Server-enforced: `mark_conversation_read` stops writing `read_at` while the setting is off; a test proves the partner's client cannot read `read_at` for that period. |
| **P0-8** | **Account security for the IPV threat model.** | 3 | (1) Settings → "Where you're signed in" lists sessions/devices with last-active; "Sign out all other devices" revokes refresh tokens server-side. (2) New-device sign-in produces an in-app notice to the account owner only; no SMS/email channel. (3) No recovery path accepts a partner's phone or email. (4) Phone-number change requires the current session plus OTP to the new number and shows an in-app notice. |
| **P0-9** | **Production phrase list, normaliser fix and Tier 2 monitoring families.** | 3, 4, 13 | (1) `normalizeForTokenPhrase` replaces zero-width characters with a space; a regression test proves "if you lea​ve" matches. (2) Language eligibility gating with no-match for uncertain language. (3) DV-approved lexicon replaces the 9-phrase placeholder, including a Tier 2 monitoring/control family and youth-register variants; cultural review recorded. (4) Golden positive/negative fixtures per family; ≥ 90% branch coverage; mutation survivors reviewed. (5) Config version bump resets Tier 3 counts (already specified). |
| **P0-10** | **Journal and Healing carry Support resources and quick exit; journal lock.** | 4, 5, 12 | (1) Every Healing and journal screen shows the Support resources entry in its app bar overflow and is wrapped by the root triple-tap target. (2) An optional journal lock (device biometrics or a separate 4-digit code) is offered once at first entry and in Settings; when locked, "latest reflection" previews are hidden; the lock screen carries no Attune wording beyond "Notes". (3) Journal entries never enter On this day or any resurfacing surface. |
| **P0-11** | **AI abuse-context suppression and adversarial suites before any cron resumes; Understand/Assist pre-check.** | 1, 2, 5, 12 | (1) `…_resume_ai_jobs.sql.disabled` stays disabled until: the one-directional safety→insight suppression flag exists and is tested; the co-framing line ships on every shared conflict insight; the adversarial Verdict suite passes (never renders abuse as a neutral dynamic; never fabricates; never drifts into stay/leave language); stonewalling/contempt signals are suppressed per market. (2) Understand and Assist run the writer-facing corpus and a do-not-interpret family (refusals: "not tonight", "stop", "I don't want to") before the provider; matches return fixed cards, requester-only. (3) The Understand footer carries the fixed "only they know" line and the handoff link. |
| **P0-12** | **Chapter-scoped data and provable deletion.** | 14, 6 | (1) `personal_insights`, translator logs, Love map and game answers carry `relationship_id`; the client filters to the active relationship; a CI canary with two former partners and one new partner proves zero cross-chapter rows via SQL, RPC, realtime and Edge Functions. (2) Account deletion hard-deletes psych profiles, raw/aggregate quiz data, journal, Healing, Love map and game answers, translator logs and media within the 30-day window; a delete-then-reregister test proves nothing resurfaces. (3) Only anonymised safety events survive, per the legal policy. |
| **P0-13** | **Private safety check as the gate on any conjoint conflict tool.** | 3, 13, and all of Part C | (1) A 4-item, self-facing check adapted from HARK with clinician authorship; "prefer not to say" available; offered at Ask-2 and quarterly from Pulse. (2) Stored in its own table with `auth.uid()`-only RLS; never in `psych_profiles`; never a Pulse, Verdict, Healing or dating input; never visible to the partner. (3) A positive screen shows resources once and sets an invisible flag that: hides Part C's conjoint tools (pause chip's partner-facing reply, gridlock ritual, post-fight debrief share step) for that relationship; tightens Layer 2 framing; expires at 180 days unless renewed. (4) Negative or skipped screens change nothing. (5) No analytics on answers. |

Items that are **P1 but adjacent to safety** and should ship in the same release train: export before seal and the 30-day read-only window (Part D); the Pause chip; Hide a period; the journal/Healing writer-facing card copy review; resource verification tooling.

---

## Part C — The repair and conflict toolkit, mapped onto existing Attune features, without scorekeeping

**Design stance.** The evidence says awareness and acceptance do as much as skills drills (`02` §4.1, mechanism #25); IBCT is the most app-ready model (`02` §3.2); the flooding break, soft start-up, repair attempts and apology structure are the four pieces with the strongest clinical consensus. Decision 28 forbids a coaching dialogue, so **every tool below is fixed copy, private-then-shared prompts, or a user-edited scaffold; the AI's only role is the existing translator tidy pass under the existing constraints.** Nothing in the toolkit produces a per-person count, a Pulse input attributable to a person, a notification to the partner that the tool was used, or a stored record of who paused, repaired or apologised. The toolkit is hidden for a relationship with a positive private safety check (P0-13).

| Clinical element | Evidence | Attune surface it lives in | Behaviour | What it never does |
|---|---|---|---|---|
| **Soft start-up** | Gottman 1998; `02` mechanism #11 | Translator button → "Help me start this conversation" | Observation → feeling → need → request scaffold, user's words, optional AI tidy pass with the seven-need taxonomy (incl. communal obligation). Equal-weight Send mine / Send this / Edit. | No automatic appearance; no "you sound harsh" nudge; no record of use beyond the existing content-free log. |
| **Time-out with physiology** | Gottman flooding, ≥20 min, stated return; `02` #7 | Composer **Pause chip**; Together "Pause" is not a ritual | Sender picks one of three fixed messages that name the return; sends as an ordinary message; sender-only 20–45 min timer with a self-soothing card ("do something absorbing; don't rehearse"); return prompt opens soft start-up. Partner sees the message and one optional fixed reply, "Okay. I'll be here." | No partner-visible timer or "pause mode"; no count of pauses; no Pulse signal; cannot be triggered for the partner; no push. |
| **Repair attempts** | Gottman sequential analyses; Rusbult accommodation; `02` #12 | Composer **repair tray** (long-press the send button) | Six fixed phrases, reviewed and localised: "Can we start over?", "I see my part in this.", "That came out wrong.", "I'm on your side, even now.", "Can we slow down?", "I need a minute, then I'm back." Sent as ordinary messages. | No "repair landed" indicator; no label on the message; no suggestion to use it. |
| **Apology structure** | Lewicki 2016; Luchies 2010 doormat caveat; `02` #24 | Translator button → "Help me apologise" | Four fields: what I did; what it cost you; what I'll do to repair; one concrete thing I'll do differently. Optional tidy pass. Copy: "A promise isn't a repair; an action is." | Never includes a request for forgiveness; the recipient has no accept/forgive control; no forgiveness status, ever; never shown to the hurt partner as "they apologised". |
| **Pause before reply** | Accommodation (Rusbult 1991) | Chat | None automatic. The repair tray and Pause chip are the pull-only answer. | No "are you sure?" interstitials (push). |
| **Perpetual-problem dialogue ("dreams within the gridlock")** | IBCT acceptance (Christensen 2010; Doss 2016); Gottman CC; `02` #4 | Together **ritual template "The thing we keep coming back to"** | One-off or quarterly. Each partner answers five fixed prompts privately (what this position means to me; the story behind it; what I'm afraid of if I give it up; what's non-negotiable; where I can flex), then a side-by-side reveal only when both have finished (the market's loved blind-reveal pattern). Ends with "Some differences are features of two people, not problems to fix." | No AI synthesis of the pair; no resolution engine; no "gridlock resolved" state; skippable; never pushes the partner. |
| **Name the cycle (unified detachment)** | EFT/IBCT; `02` #5 | Verdict's "Ask each other" starter (when reachable) and a Planning Notes template "Our pattern" | Couple writes their own shared name for the cycle ("the Tuesday Spiral") and the two private halves ("When I feel ___ I tend to ___"), each half self-facing and shared only by choice. | The app never fills in a role; Layer 2 role insights stay private; the shared half is never AI-written. |
| **Acceptance and appreciation** | Gordon 2012; Algoe; appreciation buffers unfairness; `02` #3 | Chat "I noticed…" chip; Story | A low-friction specific-thanks note chip; notes save to a private appreciation jar each person can revisit. | No quotas, streaks, counts, or "you haven't thanked them" pings. |
| **Post-fight debrief (30–90 minutes after)** | `RISK_SOLUTIONS` §1 redesign; Larson & Sbarra structured reflection | Journal prompt set "Make sense of what happened?", surfaced only from the Pause return prompt or from Conversations (pull) | Three private prompts (what I felt; what I needed; what I'd do differently). Optional "share one line" that posts as an ordinary message. | No AI analysis of the fight; not a Layer 2 input; no partner notification that a debrief exists. |
| **Fairness without a ledger** | Gillespie 2019; Daminger 2019; `02` #23 | Weekly check-in (quarterly extra item); Home & bills "Who's carrying what" | Private 1–5 "How fair does your split feel to you?" leading to soft start-up; task ownership including noticing and planning. | No counts, percentages, per-person totals; never shared; not a Pulse input. |
| **When to stop and route** | `02` C1–C2 | Every tool | Writer-facing disclosure routing (P0-5) runs on every text field in the toolkit; a positive private safety check hides conjoint steps; the handoff card is reachable from each tool's overflow. | No AI decides this; no "your relationship needs therapy" message is ever generated. |
| **Check-ups (boosters)** | Córdova 2014; `02` #2 | Pulse quarterly "Check-up" (strengths first) | Each partner privately names two strengths and one thing to grow; a joint summary appears only when both consent; links to the toolkit and the handoff card. | No numbers, trends or comparisons in the summary; no AI prose; no push to the partner. |

**Sequencing.** Pause chip, repair tray and apology helper first (they are composer affordances with no new backend); then the gridlock ritual and check-up (Together templates); then "I noticed" and fairness items. Verdict's starter only when the Verdict is routed and its gates pass.

---

## Part D — Breakup and healing data model

**Goal.** Prevent the market's documented failures (Paired: deleted data restored; Lasting: ex's sessions shown to a new partner; Between: memories lost and a cold "CANCELED" email; Couple: unpair erased everything; Locket: one-sided delete) while honouring the soul (users leave with their data; never make leaving painful) and the IPV constraints (unilateral exit, no partner notification, no evidence logs).

### D.1 States and transitions

```text
active ──(either)──▶ paused ──(either)──▶ active
  │                    │
  │ (either)           │ (either, or 30 days with no decision)
  ▼                    ▼
ended ── read-only window: 30 days from ended_at, per person ──▶ archived
  │        • either person may "seal my side now" (their access ends; the other's window continues)
  │        • either person starting a new relationship archives immediately for both (Decision 19)
  │        • both re-invite within 90 days and no new relationship → "Reopen our space" → active
  ▼
archived ── 12 months ──▶ hard-deleted (messages, media, Planning, calendar, stories, pins)
                           unless legal hold; anonymised safety events persist per policy
```

Rules: no transition sends a push, SMS or email to the other person; the other person learns of `paused`, `ended` and `archived` in-app on next open with warm fixed copy. `ended_by` is stored; the UI shows only the partner's first name in the ending screen and nothing in exports. `reopen` requires both actions and creates no new relationship row.

### D.2 What happens to each data class

| Data | At `paused` | At `ended` (read-only window) | At `archived` | Export | Who decides |
|---|---|---|---|---|---|
| Chat messages and media | Read-only for both | Read-only for both; no sends, edits, reactions | Inaccessible to both; hard-deleted at 12 months | Full conversation text and the user's own media; the partner's media as viewed in the window (both already possess it). No AI-derived fields. | Either exports their copy; either seals their own side; neither can delete the other's copy |
| View-once / streak clips | Expired items stay expired | Not exportable | Deleted | Never | n/a |
| Planning entries and blocks | Read-only | Read-only | Deleted at 12 months | Entries, blocks, photos the user added or that were shared; expense ledgers as a flat list (per-entry only; no cross-entry totals, consistent with D6) | Either exports; shared artefacts become a copy for each exporter; the server copy follows the relationship |
| Calendar events and rituals | Future items frozen | Read-only; future pushes cancelled at `ended`; ICS feed stops serving; calendar mirror and Live Activity cleared | Deleted | ICS of events the user created or that were shared; private events of the partner never | Either |
| Family members and child calendar | Unchanged | Offer "Keep the family calendar" (child-only surface) to both; each keeps their own reminders | Child surface persists while either keeps it | Yes | Each person for their copy; the shared child surface by either leaving it |
| Stories, moments, map pins | Pins hidden; presence purged | Read-only; pins and presence purged immediately; On this day off | Deleted | The user's own stories and moments; the partner's stories not exportable | Author |
| Couple map presence, widget, Live Activity | Purged, cleared, opt-in reset | Same | Same | Never | Automatic |
| Pulse history, shared patterns, Verdicts | Hidden | Read-only | Frozen; used only as a derived, role-free snapshot for Healing Stage 2; deleted with the relationship at 12 months | Shared Pulse history and Verdicts (both already saw them); never role attributions | Either exports |
| Personal insights, translator logs | Unchanged, chapter-scoped | Unchanged, chapter-scoped; never rendered in a later relationship | Retained for the user | Yes, the user's own | The user; deleted with the account |
| Weekly check-in answers, private safety check | Private | Private | Private | Own answers only; the safety check is never exported | The user |
| Journal, Healing journey | Private | Private; Healing available | Private | Own | The user; Healing deletable on its own |
| Quiz / psych profiles | Unchanged | Unchanged | Unchanged | Own | The user; hard-deleted with the account; never shown to a later partner except through the explicit compatibility-preview consent that uses only each person's own current profile |
| Love map, 36Q, game answers | Read-only | Read-only | Deleted with the relationship | Own answers; the partner's answers as revealed in the window | Either exports own; chapter-scoped |
| AI session transcripts | Private sessions: user's; shared sessions: read-only | Same | Shared sessions deleted with the relationship | Own private sessions; shared sessions as text | Each for private; the relationship for shared |
| Safety events, dismissals | Untouched; never visible to the other partner | Untouched | Untouched | Never | Policy (12-month anonymisation) |
| Dating exclusion (phone HMAC) | n/a | Written at `ended` | Persists | n/a | System |

### D.3 Rules that prevent the competitor failures

1. **Deletion is deletion** (Paired). Account deletion hard-deletes the user's own data classes above; a delete-then-reregister test proves no quiz answer, insight, Love map answer or journal entry returns. Soft-delete flags are not acceptable for personal data.
2. **Chapters never leak** (Lasting). Every per-user derived artefact is `relationship_id`-scoped; a later partner can never see any text, insight, answer or pattern from a prior chapter; the RLS canary runs in CI with two former partners and one new partner.
3. **Memories are not lost and the message is warm** (Between, Couple). A 30-day read-only window plus export for both; hard deletion only at 12 months after archive, told up front; the ending screen is a sentence a friend would say, not a status.
4. **Deletes are two-sided** (Locket). Delete-for-both with tombstones already exists in chat; the same holds for Planning blocks and stories during `active`; after `ended`, nothing is editable.
5. **No retroactive loss** (Cozy Couples). The product-change covenant applies to export: nothing a user could export yesterday becomes unexportable tomorrow.
6. **No evidence packs** (soul). Exports contain no AI judgement, no role attribution, no safety data, no translator originals; raw conversation text is exported because both people already hold it, and excluding it would punish the person who lost the phone.
7. **Exit is safe** (`02` §13.3). Unilateral, instant, unannounced; `paused` exists for the ambivalent; the ender's device clears presence and widgets at once; the other person's first sight of the change is a calm screen, never a lock-screen banner.

### D.4 Healing after the data model

Healing's existing design is sound and stays private, role-free and ex-blind. Two changes: (a) Stage 2's evidence snapshot is taken at `ended` (before archive), so the 30-day window and the 12-month deletion never leave Stage 2 without evidence; (b) the "Healing from a breakup?" card on the locked chat screen is complemented by the same card on the ending screen, and both carry Support resources and quick exit (currently missing).

---

## Appendix — Scenario priority summary

| # | Scenario | Highest-priority change | Priority | Confidence |
|---|---|---|---|---|
| 1 | Pursue–withdraw, chores | Pause chip; symmetric read ticks; Pulse inference rule | P0/P1 | High |
| 2 | After an affair | Apology helper; Hide a period; Understand footer + handoff | P1 | Moderate–High |
| 3 | Coercive control via app | No-push ending; PIN gate; sessions/devices; resources v2; lexicon | P0 | High |
| 4 | IPV disclosed in journal/chat | Writer-facing disclosure routing; journal lock | P0 | High |
| 5 | Depression / SI | Self-harm routing; crisis catalogue; Understand pre-check; supporter card | P0 | High |
| 6 | Breakup and co-parenting | Read-only window; export; no-push; pause state | P0 | High |
| 7 | Grief | Put away gently; "has passed"; grief setting | P1 | High for the first two |
| 8 | Infertility | Gallery hide; cycle hard rules; tag mute | P1 | Moderate |
| 9 | Deployment / FIFO | Sensitive-location posture; tentative reunion | P1 | Moderate |
| 10 | Addiction, financial harm | Addiction resources; boundary-preserving translator evals | P1 | Moderate–High |
| 11 | Family pressure; arranged marriage | Third-party attribution ban; seventh need; pace controls | P1 | Moderate |
| 12 | Sexual intimacy after trauma | Disclosure routing; topic exclusions; do-not-interpret refusals; delete the roadmap line | P0/P1 | High |
| 13 | Jealousy, 18–21 | Presence onboarding copy; symmetric seen-state; Tier 2 monitoring family | P1 | High |
| 14 | On–off cycles; data after breakup | Chapter scoping; provable deletion; reopen path | P0/P1 | High |

**Three things the simulations kept returning to.** First, the hard rules are good and mostly hold; the harm is in the gap between spec and code (PIN never read, quick exit scoped to two screens, resources three countries, nine phrases, instant archive, no export). Second, the one routing model the safety spec deliberately excluded, the writer as the at-risk person, is the model every disclosure scenario needs; it can be built without touching the LLM-free rule. Third, the shared Pulse and read ticks are the two quiet surveillance primitives the product already ships, and both are fixable with symmetric settings and an inference rule rather than new features.

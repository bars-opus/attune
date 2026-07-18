# ATTUNE — RISK SOLUTIONS
### Mechanisms, evidence, and the honest path to product-market fit

**Version:** 2.0 (Evidence-hardened)
**Updated:** July 2026
**What changed in v2.0:** Version 1.0 was reasoned from first principles. This version has been stress-tested four ways: (1) market-evidence research on every precedent the thesis cites (Between, Paired, Lasting, Relish, dating-app cold starts, AI-companion willingness-to-pay); (2) ground-truth research on the launch market (payments, OTP, verification, regulation, distribution); (3) an adversarial red-team review that attacked every proposed mechanism, including the statistics of the proposed tests; (4) structured scenario simulations of the four make-or-break user moments with culturally grounded personas. Several v1.0 mechanisms did not survive and are explicitly retired below. Two new risks were discovered and added to the kill-list. **The framing is now global-first: Attune is a global product; Ghana is market #1, not the product's identity.** Market-specific findings are labeled as such.

**Reading order:** `ATTUNE_THESIS.md` first, this document second, then `attune/ATTUNE_MASTER_SPEC.md` for implementation.

**Nothing here overrides the governing documents.** Every mechanism must still pass Soul, Clinical, and the Principles Checklist before shipping.

---

## 0. What v2.0 Killed, Kept, and Added — the honest ledger

**Killed or demoted (v1.0 mechanisms that failed review):**

- **The mid-fight share-extension bridge — demoted from flagship to deferred.** The red-team found it self-refuting: five deliberate steps plus a second enraged partner's cooperation, demanded in exactly the arousal state where behavior narrows to the most overlearned action. The simulations independently confirmed no persona uses it mid-fight — but discovered its real moment: the **post-fight cooldown (30–90 minutes after)**, when "we're both agreeing to look at this together" reads as fairness rather than evidence-gathering. Verdict: not a pre-launch build (4–6 fragile solo-dev weeks); redesign later as a *post-fight processing* tool ("ready to make sense of what happened?"), and note the voice-note gap — couples who fight in WhatsApp voice notes have no text thread to bridge at all.
- **The two-ask invite A/B test — killed as an experiment, shipped as the design.** At beta scale the A/B is statistically hopeless (see Section 9). But the simulations validated the two-ask design itself across every persona: the threat spike is specifically at the words "AI / analyze / insights" landing before any lived trust, not at the idea of a couples app. So: ship the two-ask flow as the *only* invite flow. Don't test it against the worse version; there's no power to detect the difference and no ethical reason to send half the beta the version we believe is worse.
- **The public trust ledger — deferred until trust equity exists.** Red-team: for a pre-scale brand, the first entry doesn't read as "the system worked," it reads as the only data point the market has. Radical transparency is a strength for an established brand; for a 200-couple beta it's a standing liability. Replaced with a private responsible-disclosure channel now, public ledger revisited post-scale.
- **The bug bounty — deferred.** An ongoing triage obligation on a solo founder; an ignored bounty is worse than none. Replaced with a responsible-disclosure email and the canary system (kept, below).
- **The self-enforced "gate integrity contract" — replaced.** A Ulysses contract the sailor can silently decline is a sticky note. Replaced with an *external* commitment: the clinical advisor and lawyer get a standing veto and visibility of the launch date. A gate honored by a second party is a gate.
- **The founder-authored synthetic-transcript validation panel — redesigned.** Red-team: founder-written transcripts encode the founder's own blind spots; the panel would validate the guesses, not the model. Redesign: panel members *co-create* the scenarios and transcripts themselves; the founder supplies the format, not the content.

**Kept (survived attack):** the cost-measurement-first discipline; per-task model tiering; the RLS canary system + fire drill; the dismissal-queue calibration loop (with a survivorship-bias fix, below); the region-adjustable confidence tier for withdrawal-adjacent signals (red-team called it "the single best idea in this section"); the revenue-tied hiring trigger; the gate-status dashboard; the conflict-capture launch gate (with honest statistical caveats).

**Added (new in v2.0):** two new kill-list risks — the catastrophic wrong insight (Risk 2) and the weaponized accurate insight (Risk 3); the payment-rails problem (folded into Risk 5 with hard evidence); the regulatory perimeter (Risk 7's new scope); founder bus-factor/continuity (folded into Risk 8); a product-change covenant learned from Replika's collapse-of-trust case; and Section 10's 90-day PMF plan.

---

## 1. Ceremonial Drift — Getting the Good-Mornings, Not the Fights

**Mechanism (unchanged, confidence corrected).** Conflict is path-dependent; ceremony is not. Fights continue where they started (usually WhatsApp), because under emotional arousal behavior narrows toward the most overlearned action. **Evidence status, stated honestly:** no published research exists on couples running a dedicated app alongside WhatsApp and which conversation types migrate — this is the single most consequential *unverified* assumption in the architecture. Indirect evidence is consistent with it (multi-app research shows people deliberately segment conversation types across apps; every anecdotal description of Between usage is ritual content — stickers, day counters, good-mornings — with zero evidence of conflict migrating). The launch gate exists precisely because the question is open.

**Revised solution set:**

1. **The one-tap weekly honesty check (NEW — build now, ~1 day).** A single skippable weekly question: *"Was there a disagreement this week we didn't see?"* (yes / no / prefer not to say). This replaces the bridge's instrumentation at a fraction of the cost, gives a direct self-reported drift measure from week one, and — per the commitment-consistency mechanism — the act of answering nudges couples to notice their own avoidance. This is now the primary drift instrument.
2. **Translator-ambient entry points (kept, cheap).** Notification quick-reply routes into the composer where "Help me say this" lives; the translator remains the only feature that's *only* useful mid-conflict and only exists here.
3. **First-insight sequencing (kept, sharpened by simulation).** Hold the first surfaced insight until it can come from a real (moderate-tension) exchange — the belief "it sees the real stuff" is self-reinforcing, and the simulations confirmed the first insight's *specificity* is what converts skeptics.
4. **Post-fight bridge (deferred, redesigned).** Post-launch: a "make sense of what happened?" flow aimed at the cooldown window, dual-consent at thread granularity, marketed as processing rather than importing. Voice-note support acknowledged as a hard gap needing its own spec.

**What to watch (statistics-honest):** the weekly check's "yes, off-app disagreement" rate as a *self-reported drift index*, plus the share of couples whose early sessions ever cross moderate escalation. At n≈120 active couples, treat these as directional/qualitative — the real verdict comes from beta exit interviews asking directly: *"where did your last real disagreement happen, and why there?"*

**Fallback (unchanged and now evidence-backed):** if fights don't migrate, Attune's honest role for that segment is reflective/ceremonial plus Personal mode — the Relish case is the cautionary tale for what happens when a relationship app's premium promise quietly exceeds what users actually use it for.

---

## 2. The Catastrophic Insight — Wrong, Believed, and Acted On (NEW — ranked #2)

**Mechanism.** The red-team identified the kill-list's biggest omission: a *single high-salience bad output* — the Verdict implies an affair-pattern that isn't there; an insight validates a genuinely abusive dynamic as a neutral "reach-and-distance cycle"; a fragile user makes a real relationship decision off a hallucinated pattern despite every disclaimer. This is LLM-hallucination-meets-intimate-stakes: higher likelihood *and* higher severity than the server-breach scenario, because it requires no attacker — just one bad generation reaching one vulnerable reader. The Replika precedent shows how fast emotionally-invested users' trust converts to public fury.

**Solution set:**

1. **The adversarial Verdict suite (build before any real couple sees a Verdict — roughly a weekend of transcript-writing plus a review harness).** A curated set of synthetic adversarial histories — an abusive dynamic dressed as normal conflict, an ambiguous pattern inviting over-reach, a jealousy bait scenario, sparse data tempting fabrication — run through the full pipeline on every prompt change. Pass criteria: never fabricates a pattern without evidence IDs; never renders abuse as a neutral dynamic; never drifts into stay/leave language; degrades to "not enough data" rather than to confident invention. This extends the eval discipline the master spec already mandates (Section 6.7) from per-prompt unit tests to *whole-pipeline* adversarial scenarios.
2. **Insight retraction mechanism.** If a shipped insight is later found wrong (validator bug, prompt regression), there must be a way to withdraw it: the insight is marked retracted in both partners' views with a short honest note, rather than silently deleted (silent deletion is its own trust breach — the Replika lesson: never make something a user emotionally invested in vanish without explanation).
3. **Abuse-context suppression.** Where the safety system has fired for a relationship (any tier), the interpretive layers should tighten automatically: no conflict-pattern insights that could read as both-sidesing an abusive dynamic. The safety and insight systems stay firewalled for privacy, but a one-directional flag (safety → stricter insight validation) respects that firewall while preventing the worst single output the product could generate.

**What to watch:** adversarial-suite pass rate on every prompt version (deterministic — works at any n); "this doesn't feel right" dismissals tagged with high-severity categories; any beta interview where a user reports making a relationship decision "because the app said."

**Fallback:** if the pipeline can't reliably pass the abusive-transcript tests, the Verdict ships later, narrower, or not at all in v1 — Pulse and per-session insights carry less catastrophic-output risk than a monthly synthesized judgment, and the product survives a delayed Verdict; it does not survive a headline.

---

## 3. The Weaponized Accurate Insight (NEW — from simulation; ranked #3)

**Mechanism.** The simulations' biggest discovery, and a category the six-risk framework missed entirely: **a perfectly accurate, perfectly hedged, culturally calibrated insight is still weaponizable, purely because of who sees it first and how it gets cited.** The simulated pattern: the app says (gently, correctly) "one of you tends to step back during disagreements"; three days later, mid-argument, one partner deploys *"even the app says you shut me out."* The insight now carries neutral-third-party authority the partner's own opinion never had; the target's resentment redirects at the partner, not the app; trust is poisoned *in the relationship*, which is worse than trust poisoned in the product. Section 6's calibration machinery cannot fix this — the failure requires no miscalibration. A secondary variant: screenshotting an insight to friends for outside validation ("see what the app said about him").

**Solution set:**

1. **Describe the dance, never the dancer.** Shared-surface insights about conflict dynamics should be framed as *dyadic motion* — "this relationship shows a pattern where distance widens after disagreement before it closes" — not "one of you tends to X." The current copy anonymizes at the sentence level while the two-person context de-anonymizes it instantly; the anonymization is theatrical. The dyadic framing is a genuinely different sentence, and it removes the citable "the app said *you*" payload. (Individual-role insight already lives, correctly, in the private asymmetric layer only.)
2. **The co-framing line, built into the insight surface.** Every shared conflict-adjacent insight carries one line addressed to both readers: *"This is a pattern, not a verdict on either of you. Citing it as evidence in an argument usually backfires — if you want to talk about it, ask, don't quote."* Cheap, honest, and aimed at the exact mechanism of harm (the citation move), not at the content.
3. **"This was used against me" as its own signal.** The dismissal queue currently conflates "this is culturally wrong" (a calibration bug) with "my partner weaponized this" (a relational-harm event). Split them: the second becomes its own reviewable signal with its own response — not a prompt fix, but a gentle in-app note to *both* partners about how pattern-observations are meant to be used, and an input to deciding whether certain insight categories should move to the private layer entirely.
4. **Soft share friction.** A one-time interstitial on screenshot/share attempts of insight surfaces — "this was written for the two of you" — not a technical block (impossible and against the product's ethos), just a moment of reflection before an insight leaves the relationship.

**What to watch:** "used against me" reports (even a handful is signal — this is a severity-weighted metric, not a rate metric); beta interviews explicitly asking *"has anything the app showed you ever come up in an argument?"*

**Fallback:** if weaponization shows up despite dyadic framing, move all conflict-dynamic observation to the private asymmetric layer — each partner sees only their own side's reflection, and the shared surface keeps only strengths and neutral rhythms. That costs the product some of its shared-mirror magic but preserves the thing that matters more: Attune must never be the weapon. The permanent constraints were written for exactly this trade.

---

## 4. Dyadic Collapse — When Only One Partner Shows Up

**Mechanism (revised).** The threat response is real but *specific*: simulations across all personas located the spike at the words "AI / analysis / insights" arriving before lived trust — not at the couple-app concept itself, which read as neutral-to-charming ("basically a shared album with chat") in every persona. The red-team's counterpoint stands as the residual risk: stripping the AI language relocates some threat downstream to the AI reveal (Ask 2), where a bounce costs a *couple* plus sunk-cost resentment, not just an install. And the market evidence confirms the risk is category-wide: Paired's own reviews attest the partner-enthusiasm gap verbatim.

**Revised solution set:**

1. **Two-ask sequential invite, shipped as the design (not an experiment).** Ask 1 sells the private-space wedge only — no AI vocabulary anywhere. Ask 2 introduces intelligence *after* both partners are chatting, anchored to an already-observed positive signal ("we noticed you two have a great rhythm — want to see more?"), never to a deficit. To defuse the red-team's downstream-churn scenario, Ask 2 must be: skippable without loss of chat function, framed as opt-in curiosity, and never re-prompted aggressively (one ask, one gentle later reminder, done — consistent with the notification ethics anyway).
2. **The initiator script, with register control (upgraded by simulation).** The suggested what-to-say message must ship in multiple registers (straight English / Pidgin-inflected / plain-spoken) because the polished-English-only version simply won't be forwarded verbatim by every persona — and an unsent script is a lost guardrail. Plus one optional personal line targeting the *source-of-idea* suspicion the simulations surfaced as gendered ("I found this myself — just thought it'd be nice"), distinct from the surveillance suspicion; two different threats, two different reassurances.
3. **Personal-mode-first as strategy, not fallback (promoted).** The red-team's strongest structural point: stop optimizing a funnel that should be inverted. Personal mode is the front door for a large share of users; couples-linking is the upgrade. This means Personal mode needs its own monetization and retention story *specced before launch* — currently the acknowledged gap.

**What to watch:** invite-acceptance and day-7 both-active rates as *descriptive* metrics (no A/B pretensions at this n); Ask-2 opt-in rate and post-Ask-2 churn (the red-team's predicted failure point — watch it directly); qualitative interviews with decliner partners wherever consent allows.

**Fallback (now the co-strategy):** the inversion above *is* the fallback, promoted to plan. If couples conversion stays hard, Attune is a self-knowledge product with a couples upgrade — the architecture already supports it.

---

## 5. Unit Economics and the Payment Rail — Two Problems, Not One

**Mechanism (expanded by evidence).** v1.0 framed this as cost-vs-willingness-to-pay timing. The research added a second, harder problem for market #1: **the charging mechanism itself.** Ground truth: mobile money is ~90% of the rail (cards under 1% of adults — any card-default flow fails almost everyone), and *silent recurring MoMo auto-debit is unproven at scale* — the pre-approval/mandate mechanism has documented failure modes, and what demonstrably works in-market is pay-as-you-go manual renewal (how Showmax and the betting apps actually operate) or Google Play billing against a MoMo-linked balance (working since 2018). Meanwhile the simulations found auto-debit *distrust* is itself an adoption barrier independent of price. And the red-team caught v1.0 asserting the dominant AI cost line (per-message Layer 1) before measuring it — the Verdict/Layer-4 frontier calls may dominate instead.

**Revised solution set:**

1. **Measure before optimizing (kept, now first).** The cost-per-active-couple dashboard, broken down by pipeline stage, live from beta day one. The triage classifier is *deferred until the dashboard proves Layer 1 dominates* — build the measurement, not the guess.
2. **Per-task model tiering (kept — the one near-certain win).** Cheap models for high-volume classification, frontier models only where clinical-language nuance is load-bearing (Verdict, pattern synthesis). Days of work, no product-quality risk.
3. **Payment rails, market #1 (NEW, evidence-driven):** Google Play billing (MoMo-linked) as the primary rail; manual-renewal MoMo (Paystack/Flutterwave one-time debits with a renewal reminder flow) as the explicit second rail; **no silent auto-debit assumption anywhere**; card flows deprioritized to near-invisible for Ghana. Renewal-reminder UX is a feature, not a fallback — the simulations showed manual renewal *builds* trust in this market.
4. **Pricing, evidence-anchored:** launch-market anchor in the GH₵20–40/month band (the simulations found ~GH₵20 near-universally acceptable, 100 reliably churning two of three personas; the market's own reference points — Spotify GH₵24, Showmax GH₵23 — agree). One low anchor tier plus an optional deeper tier matches both the evidence and the existing tiering ethics. Global pricing is a separate exercise per market — do not export the Ghana number, and do not import a US one.
5. **The conversion lever is Verdict specificity, not price tactics.** Across every simulated persona, the flip-to-paid trigger was whether the Verdict said *something the couple couldn't have articulated themselves.* That's a writing bar for the Verdict prompt — make it an explicit eval criterion — and it confirms anchoring the trial boundary to the first Verdict rather than a calendar day.
6. **The category's cautionary tale, named:** Relish — differentiated at launch, couldn't sustain its cost structure, retreated to the cheapest-to-serve feature, stagnated. Attune's equivalent failure is quietly degrading insight quality to save inference cost. The tiering discipline exists so cost pressure lands on *model routing*, never on *insight honesty*.

**What to watch:** true cost per active couple weekly (continuous, low-variance — statistically sound even at small n); week-4/5 paid conversion at the anchor price; renewal completion rate on the manual rail (a number nobody has — Attune will be generating the first real data).

**Fallback (unchanged):** usage-based tiering aligning the cheap-to-serve features with the free tier. Safety, translator, and core chat stay free at every tier — permanent.

---

## 6. Cultural Misread — Systematic, One-Directional Miscalibration

**Mechanism (unchanged):** the frameworks encode "directness = health; withdrawal = dysfunction," which mis-scores high-context communication in one consistent direction — worse than noise because it's learnable and trust-eroding. (Global note: this risk *inverts* by market — the same frameworks fit WEIRD users better; the calibration machinery below is per-market infrastructure, not a Ghana patch.)

**Revised solution set:**

1. **Start from silence (upgraded from fallback to default).** Stonewalling/contempt-type signals ship *suppressed* for market #1 pending validation — don't ship the risky signal and correct on dismissals; earn the right to speak. The region-adjustable confidence tier makes this a config value, not a fork.
2. **Fix the survivorship bias in the calibration loop (red-team's key catch).** The dismissal queue only hears from users who stayed and tapped; the users most harmed churn silently and leave no signal. Pair the queue with a one-question exit survey and a standing practice of outbound interviews with churned couples. The calibration dataset must include the people it failed.
3. **Co-created validation panel (redesigned).** Panel members supply the scenarios and transcripts from their own experience; the founder supplies only the format. Cheap (weeks, modest compensation), and it tests the model rather than validating the founder's guesses.
4. **The loaded-language glossary (kept):** clinically-freighted terms mapped to culturally calibrated alternatives, enforced server-side like the banned-word list — per market, extensible as new markets open.

**What to watch:** dismissal-rate-by-insight-category — a *within-events* comparison that reaches meaningful sample sizes on insight-events rather than couples, but only after enough events accumulate; give it weeks before trusting it. Exit-survey themes from day one.

**Fallback (unchanged, already the default posture):** permanent per-market suppression of any signal that can't honestly clear the bar. Saying less, correctly, beats saying more, wrongly.

---

## 7. Trust Catastrophe and the Regulatory Perimeter

**Mechanism (expanded).** The red-team relocated the likeliest vectors: not an RLS hole (the canaries cover that) but (a) **the founder's own admin/debugging access** — the human-in-the-loop reading the wrong couple's data; (b) legal process (a subpoena in a divorce case making headlines); (c) the **Replika mechanism** — a sudden, unexplained change to something users emotionally rely on, which converted a loyal user base into a grief-and-fury news cycle and drew a €5M regulatory fine. And for a global app, the perimeter is regulatory before it's technical: intimate-message AI processing sits in the most protected data category in every serious privacy regime.

**Revised solution set:**

1. **Canaries + fire drill (kept — highest severity-times-buildability item in the doc).** Synthetic accounts continuously attempting every forbidden read pattern in production; monthly staged fire drill proving the alarm actually fires. Deterministic; sample-size-proof.
2. **The founder access log (NEW — closes the likeliest real vector).** Every admin/support read of user data is logged, dated, and reasoned — an audit trail of the founder's own access. Cheap, and it converts "trust me" into "check the log."
3. **The product-change covenant (NEW — the Replika lesson).** A standing rule: no feature that users emotionally depend on (insights, history, the sealed chat, safety behavior) is ever removed, paywalled, or materially changed without advance notice and a stated reason. Silent change to emotionally-invested surfaces is a trust breach even when contractually permitted.
4. **Private responsible-disclosure channel now; public ledger later** (per Section 0). Pre-written incident scripts for the three specific worst cases (kept), plus the standing lawyer relationship *before* any incident.
5. **Regulatory perimeter, sequenced (researched July 2026 — sourced findings, verify with counsel before relying):**
   - *Market #1 (blocking, pre-launch):* Data Protection Act registration with Ghana's DPC — mandatory before processing; the cross-border question (Supabase hosting vs. case-by-case adequacy) needs a documented legal answer, not an assumption; the pending 2025 bill adds extraterritorial reach, 72-hour breach notice, and a DPO role — build to the incoming standard, not the outgoing one.
   - *At first store submission (applies to the Ghana launch, not just later markets):* Apple's updated guideline 5.1.2(i) now requires apps to **clearly disclose sharing personal data with third-party AI and obtain explicit permission first** — Attune's server-side Claude API calls are exactly this; the disclosure/consent must exist in the first submitted build. Google Play requires **Child Safety self-certification for Social/Dating apps** and AI-generated-content disclosure. Plan for a 17+/18+ age rating once dating mode exists — comparable apps are uniformly rated mature.
   - *Before US users — the design-classification decision:* a 2026 wave of state "companion chatbot" laws (California SB 243, Oregon SB 1546 with a $1,000/violation private right of action, New York, Nebraska, Tennessee) regulates AI that "sustains a relationship across multiple interactions" and meets social needs — with disclosure, minor-protection, and crisis-referral obligations. **Attune should pre-commit, as a deliberate regulatory posture, to keeping its AI non-conversational: insights, pulses, and verdicts are reports about the couple's own data, never a chatty companion persona.** This is the difference between "likely out of scope" and "squarely regulated," and it happens to align with the Soul document's design instincts anyway. Tennessee additionally bars AI presenting as a licensed mental-health professional — Attune's existing not-therapy language already complies; keep it airtight.
   - *Before US users — the vendor audit:* every FTC intimate-data action (BetterHelp $7.8M, Flo) and the first Washington My Health My Data lawsuits share one fact pattern — **third-party SDKs/pixels leaking sensitive signals**, not first-party processing. Attune's log/analytics content bans already align, but a formal audit of every SDK (Sentry, PostHog, the model API) against "can this see message content or infer emotional state" is the concrete deliverable. Note BetterHelp's unfairness counts also punished *collecting* sensitive data without affirmative express consent — first-party AI use needs explicit consent too, not just an accurate policy. Washington MHMDA explicitly covers *inferred* mental/sexual-health signals and carries a private right of action.
   - *Before EU/UK users (hard gate):* GDPR Art. 9 explicit consent is the only realistic lawful basis — relationship/sex-life *inferences* are special-category data even when the users never typed the words, which is precisely what Italy's Garante cited in fining Replika €5M (no granular lawful basis, self-declared age only, vague notices). The practical bar: granular per-purpose consent (AI analysis, safety scanning, each separately), real age verification, purpose-specific notices, and a DPIA (Art. 35 triggers are met on their face). EU AI Act: the emotion-recognition prohibition is workplace/education + biometric-scoped, so text analysis of consenting adults is outside it (do not add voice-tone analysis without re-checking); Attune fits no high-risk Annex III category; but **Article 50 transparency (disclose AI interaction upfront, label AI-generated insights) applies from 2 August 2026** with penalties up to €15M/3% — trivial to implement, hard-deadlined. EU/UK remain gated until this stack is built.

**What to watch:** canary alerts (zero is the only pass); fire-drill catch rate; access-log review monthly; regulatory registration status on the gate dashboard.

**Fallback:** the pre-written scripts, the lawyer already on standing terms, and honest fast disclosure. Plus one addition: geography gating as a *feature* — the app simply isn't available in a region until its regulatory bar is met. Slower is recoverable; non-compliant is not.

---

## 8. Founder Capacity, Continuity, and the Meta-Work Trap

**Mechanism (expanded).** The oscillation (rigor ↔ rubber-stamping) stands — but the red-team added two things v1.0 missed. First, v1.0's own remedies summed to a part-time job of meta-work laid on the person who is already the whole company: the medicine shared an active ingredient with the disease. Second, **bus-factor**: one person holds the safety system, the keys, and the clinical relationships — for a product with a life-safety feature, literal founder unavailability silently strands at-risk users.

**Revised solution set (deliberately smaller than v1.0's):**

1. **External veto instead of self-policing.** The clinical advisor and lawyer know the launch date and hold a standing veto on their domains. Binding force lives in a second party.
2. **The gate-status dashboard (kept — hours to build)** with dated, factual review status; a stale date on a shipped interpretive feature is itself the tripwire.
3. **The revenue-tied hiring trigger (kept — the one mechanism with real binding force),** pre-defined now: when the moderation queue breaches its SLA or margin covers it, the next dollar hires part-time support. No deliberation later.
4. **Moderation floor automation (kept, scoped to days not weeks):** off-the-shelf image screening plus deterministic text pre-screens; humans see only the ambiguous minority.
5. **Continuity plan (NEW):** a sealed, access-controlled continuity document — where the keys live, how safety-system maintenance works, who (a named person) can wind things down gracefully or keep the safety net alive if the founder is suddenly unavailable. For most apps this is optional hygiene; for an app with a DV safety feature it is an ethical obligation. One afternoon to write; revisit quarterly.
6. **Dropped:** the monthly reviewer warm-check-ins as a standing calendar obligation (replaced by the veto relationship plus as-needed contact), and the self-read commitment doc (replaced by item 1).

**What to watch:** the dashboard's staleness signal; moderation SLA; and one honest self-check — if this document's own recommendations start feeling like the *reason* nothing ships, that is the meta-work trap closing, and the answer is Section 10's short list, not more process.

**Fallback (unchanged and sharpened):** slow the roadmap deliberately. A late launch with intact gates is recoverable. And the red-team's closing warning is adopted verbatim as a rule: *this document's quality is a trap if refining it substitutes for shipping against it.*

---

## 9. The PMF Math — What n≈200 Couples Can and Cannot Tell You

The red-team ran the arithmetic v1.0 skipped, and it changes how the beta must be read:

- **The real working sample is ~120 both-active couples** (200 minus dyadic-onboarding attrition), and any cohort split halves it.
- **Between-couples proportion tests are statistically hopeless at this n.** A 15% observed conflict-capture rate carries a ±6-point confidence interval; detecting a realistic 10-point lift in an invite A/B needs ~380 couples *per arm*. Any such test at beta scale returns "no significant difference" even when the mechanism works. Consequence: **no behavioral A/B tests in beta.** Ship the best-believed design, measure descriptively, learn qualitatively.
- **What actually produces signal at this scale:** deterministic tests (canaries, adversarial Verdict suite — sample size irrelevant); continuous low-variance measures (cost per couple); within-events comparisons (dismissal rates by insight category, once enough insight-events accumulate); severity-weighted rare events ("used against me" reports — even three is signal); and **structured qualitative work** — the beta's real instrument is 20–30 deep couple interviews, not dashboards.
- **The PMF instrument for this scale:** the Sean Ellis question — *"how would you feel if you could no longer use Attune?"* — asked at week 6+ of active use. The classic benchmark (≥40% "very disappointed") is one of the few PMF measures that works at double-digit sample sizes. Pair it with: week-4+ paid conversion at the anchor price, and the one-tap drift index (Section 1). Those three numbers, plus the interviews, are the honest PMF verdict. Everything else is decoration at this n.
- **All retention/conversion targets are founder hypotheses, not benchmarks** — the research confirmed no published couples-app category benchmarks exist. Write internal targets as hypotheses and let the beta set the real baseline.

---

## 10. The 90-Day Path — What Actually Gets Built and Measured

**Pre-launch (the red-team's three, plus the two the evidence forced in):**

1. **Cost dashboard + per-task model tiering** (Section 5.1–5.2) — days-to-weeks; unblocks every economic decision.
2. **RLS canaries + fire drill + founder access log** (Section 7.1–7.2) — 2–3 weeks, mostly reusing pre-launch test obligations; the highest severity-times-certainty item in the document.
3. **Adversarial Verdict suite** (Section 2.1) — a weekend of transcripts plus a harness; guards the newly-ranked #2 risk before any real couple sees a Verdict.
4. **The payment rail** (Section 5.3) — Google Play/MoMo-linked billing plus manual-renewal flow. Without a working charge mechanism there is no PMF test at all, only a retention test.
5. **The OTP fix** (from the ground-truth research, and *time-critical*): a market-#1-direct SMS provider with voice fallback — the MTN sender-ID registration enforcement deadline has already passed as of this writing, and an unregistered global-aggregator sender may already be silently blocked; verify current OTP deliverability on real MTN SIMs immediately, and never rely on Firebase phone auth alone (documented +233 reliability bug).
6. **The store-submission compliance pair** (from the regulatory research): the Apple 5.1.2(i) third-party-AI disclosure/consent must be in the *first* submitted build, and the DPC registration process should be started now (it takes time and is legally prerequisite to processing). Both are cheap; both are blocking; neither can be retrofitted after submission/launch respectively.

**Beta (12 weeks):** weeks 1–2, onboarding cohort and verify instrumentation end-to-end; weeks 3–6, watch cost-per-couple, drift index, dismissal categories, and run the first 10 couple interviews; week 6+, Sean Ellis survey wave one; weeks 7–10, first Verdicts land → paid conversion at anchor price, second interview wave (including decliners and churned couples — the survivorship-bias fix applies to research, too); weeks 11–12, the honest go/no-go: Ellis score, conversion, drift index, plus zero unresolved canary or adversarial-suite failures.

**Explicitly deferred past launch:** the post-fight bridge, the triage classifier (until the dashboard justifies it), the public trust ledger, the bug bounty, EU/UK availability, and every behavioral A/B.

---

## Appendix A — What the Evidence Did to the Thesis (corrections applied)

- **Between:** 10M+ downloads real; but the company pivoted away in 2018 and the app was sold twice more as an asset — precedent for *demand*, not for durable standalone economics; no public monetization evidence exists. Thesis language softened accordingly.
- **Paired/Lasting:** real traction (Paired ≈ $200K/mo est.; Lasting exited via acquisition) — precedent for meaningful traction and exits, not for large independent scale. Paired's reviews directly attest the dyadic-collapse complaint.
- **Depth-first dating matching:** the strongest published research (Finkel et al. 2012, *Psychological Science in the Public Interest*) finds no evidence sophisticated matching algorithms produce better relationship outcomes. Attune's dating spec already refuses outcome claims; the thesis marketing language now matches the spec's humility: better first conversations is the only promisable outcome. Positioning differentiator, not proven outcome advantage.
- **Ceremonial drift:** no direct research exists either way — flagged as the architecture's highest-stakes unverified assumption; the launch gate is the correct response; confidence language corrected; the arousal/cognitive-narrowing citation needs a specific reference check before any investor-facing use.
- **AI willingness-to-pay:** the adjacent AI-companion category shows real, fast-growing spend — but no data exists for couples'-own-relationship AI insight specifically; Attune will be generating the first.
- **Dating cold-start:** the density-first, city-by-city playbook is well-documented and validates the existing region-gated plan unchanged.
- **Scam protection (market #1):** Ghanaians are documented scam *victims* at meaningful scale, not only a reputational-origin concern — reframed as a user-facing protective feature, which is both truer and a stronger local trust story.

## Appendix B — Open Items

- ~~Global regulatory research~~ — completed July 2026 and folded into Section 7.5. Remaining regulatory to-dos: engage counsel to execute the Ghana DPC registration and cross-border assessment; formal SDK/vendor audit; the non-conversational-AI pre-commitment should be recorded in the master spec's decision log; EU/UK remain gated until the GDPR consent stack exists.
- Personal-mode standalone monetization spec — required by Section 4's strategy promotion; not yet written.
- Voice-note conflict path — acknowledged gap, needs its own design pass.
- Citation verification for the arousal/cognitive-narrowing and commitment-consistency mechanisms before external use.
- Fallback-preconditions checklist from v1.0 (runway for a slower launch; lawyer engaged pre-incident; willingness-to-pay survey) — carried forward unchanged.

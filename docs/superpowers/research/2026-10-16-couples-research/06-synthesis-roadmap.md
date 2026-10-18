# 06 — Synthesis and roadmap: making Attune the relationship app that actually helps

**Date:** 2026-10-16. **Author role:** chief scientist / product architect. **Status:** decision document for the owner. Read-only pass; no app files were changed.

**Inputs, read in full:** `01-market-reviews.md` (15,746-review corpus, 44 apps), `02-relationship-science.md` (graded evidence review, 30 ranked mechanisms, guardrails C1–C7), `03-attune-inventory.md` (what ships, what is reachable, what is paused), `04-scenarios-everyday.md` (14 everyday archetypes × 8 weeks), `05-scenarios-strain-risk.md` (14 strain/risk scenarios, P0 list, conflict toolkit, breakup data model), and the binding documents `ATTUNE_SOUL.md`, `ATTUNE_MASTER_SPEC.md`, `ATTUNE_THESIS.md`.

**Citation conventions.** `01 §3.2 #11` = document 01, section 3.2, row 11. `02 (a) #3` = the ranked-mechanism table in 02, row 3; `02 (b)` = the unsupported-ideas table; `02 C6` = guardrail C6. `04 S9` / `05 S3` = scenario 9 of 04 / scenario 3 of 05. `05 P0-4` = safety fix 4 in 05 Part B. `04 §A gap 3` = cross-scenario gap table row 3. `SOUL §8`, `SPEC §11`, `THESIS §6.8` = the binding docs. Evidence grades follow 02 §0.1 ([MA] [RCT] [LONG] [XS] [QUAL] [CC] [POP]).

**Precedence.** Where this document and the binding documents disagree, the binding documents win until the amendments in §8 are accepted. Where a recommendation requires a rule change, it is marked **[needs amendment §8.x]**.

---

## 1. Executive summary

### 1.1 The ten conclusions

1. **The hard rules are right; the harm is in the gap between spec and code.** The soul forbids surveillance, scorecards, streaks and AI judgement, and the architecture mostly enforces it (03 §1). But the safety PIN is written and never read, quick exit covers two screens, the resources screen has three countries and no emergency numbers, the phrase list is a nine-phrase placeholder, ending a relationship pushes the other partner and archives the chat in the same transaction, and there is no export function at all (05 preamble; 05 S3, S6; SOUL §7 vs code). Nothing else in this document matters until that gap is closed. §3 is the list.

2. **The theory of change is responsiveness, not insight.** The strongest predictors of relationship quality across 43 longitudinal datasets are perceptions of the partner: commitment, appreciation, sexual satisfaction, perceived partner satisfaction, and conflict (Joel et al. 2020; 02 §0.3 #1, §6.1 [pooled ML], High). The thesis bets on *pattern insight from chat* (THESIS §1). Insight is a means; the end is each partner feeling understood, valued and cared for, and acting that way back. Attune's best-evidenced levers are therefore the cheap, rule-compatible positive-affect surfaces it does not yet have: specific appreciation (02 (a) #3, High), active-constructive responses to good news (02 (a) #6), periodic strengths-first check-ups (02 (a) #2 [RCT]), and a user-initiated flooding break (02 (a) #7). The AI pipeline becomes more valuable *because* those surfaces exist, not instead of them.

3. **The intelligence layer the thesis rests on is not running, and must not be resumed as-is.** Layer 1/2, weekly Pulse and monthly Verdict crons are paused; the Verdict screen has no route; three of four quizzes are unreachable (03 §2.2, §4.1). Before resumption: abuse-context suppression, the co-framing line, the adversarial Verdict suite, and a deterministic pre-check on Understand/Assist (05 P0-11). Resumed without these, the first private "you tend to withdraw" insight gets read aloud in the next fight (05 S1 b).

4. **The shared Pulse and read receipts are the two surveillance primitives Attune already ships.** Both are fixable with symmetric settings and an inference rule, not new features (05 closing; 05 P0-6, P0-7; 04 §A gap 1, score 126, the highest in the table). Read receipts are the pursuer's accelerant in demand–withdraw (02 §2.1 [MA], 74 studies) and the controlling partner's clock (05 S3).

5. **A couple profile is the keystone feature.** Content is identical for a 3-month anxious–avoidant pairing, a 41-year marriage, a devout Muslim–secular couple and an asexual survivor (04 §A gap 2, all 14 archetypes). The market's single largest non-price request is "content for *our* relationship type" with filters that actually work (01 §3.3 #3; Evergreen and Couple Joy ignored their sex filters, 01 §2.1). The representation tension (queer couples love inclusive imagery; conservative couples ask to hide it; both ask for the same thing) is resolved only by per-couple and per-partner personalisation (01 §4). §5 specifies it.

6. **The couple's journal is a second substrate, and it is good.** Planning, Calendar and Map are the strongest recent work: per-entry money with no scoreboard, proposals not impositions, one scheduled push a day, approximate presence with silent symmetric pause, a reunion countdown without a days-apart counter (03 §2.1). Every everyday archetype found delight there first (04 S1–S3, S5, S14). What it lacks is the *relational* layer on top of logistics: no gratitude, no share-a-win, no transition conversations, no recurrence, no family relation types (03 §3; 04 §A gaps 3, 5, 10–12).

7. **Positives matter as much as conflict management, and Attune has built almost nothing for them.** Low positive affect in everyday talk predicts *later* divorce (Gottman & Levenson 2000 [LONG]; 02 §0.3 #2). How partners respond to *good* news predicts breakups better than how they respond to bad news (Gable 2006 [LONG]). Attune's only responsiveness prompt is the big-day care card, which fires for stress only (03 §3 "Celebrations"). "I noticed…" and "Share a win" are the cheapest high-evidence wins in the whole programme and violate no rule (04 §A, reading the table).

8. **Breakup handling is the market's blank space and Attune's most dangerous behaviour.** No app in the corpus offers a compassionate, safe breakup flow (01 §7 item 5). The angriest reviews in 15,746 are about lost memories and old-relationship data resurfacing (01 §3.2 #11–12, §5 items 1–4). Attune today: unilateral end → push to the other partner → instant archive for both → no export (05 S6). Separation is the highest-lethality window (Campbell 2003; 02 §13.1). 05 Part D is the fix; it also delivers the soul's unkept promise (SOUL §7: "exportable… deletable").

9. **Sex, faith, money, parenting, health and family are not peripheral; they are where couples actually live.** Religion is addressed by 1 of 38 apps in the 2025 scoping review; no Muslim or Jewish married-couple app with traction exists (01 §2.8). Sex is absent from Attune by undecided default (03 §3). Money is logistics only; parenting, health, grief and caregiving are absent (03 §3). The evidence for domain content is Moderate at best outside parenting (High: Doss 2009 [LONG]; Family Foundations [RCT]) and sexual communication (Mallory 2019 [MA]), so these ship as **opt-in, clinician-authored conversation packs behind per-partner gates**, not as AI features and not by default (02 §8.2–8.3, §11.2–11.3, §12).

10. **Honesty about evidence is a feature, and several roadmap lines fail it.** "Weekly intimacy challenges personalised to love language, retention mechanic" (SPEC §14) is the exact thing the evidence says not to build (02 §7, §8.3; Loewenstein 2015 [RCT]). "Live conflict cooldown — real-time escalation banner" (SPEC §14) violates pull-not-push (SOUL §9 translator line) and is dominated by a user-initiated pause chip (05 Part C). "Pulse score benchmarks against similar couples" (SOUL §9 Gamification) contradicts the Pulse boundary two paragraphs above it and 02 C6 #2. The attachment "pairing" card contradicts the other quiz specs' compatibility ban (03 §4.1). §8 proposes the exact text changes.

### 1.2 What Attune already does better than the market

- **Money without a scoreboard.** Per-entry split, "To even out", no cross-entry or per-partner totals (03 §2.1 Planning D6). Honeydue's 67% low-star share and "the app starts fights" (01 §2.6) is the counter-example.
- **Proposals, not impositions; declines with a note; quiet expiry; "Needs you" never tallied** (03 §2.1 Calendar). The nag dynamic is a top-20 pain (01 §3.2 #19).
- **One scheduled push a day, preview off by default, no partner name on device surfaces** (03 §1.4). Broken notifications are pain #7.
- **Presence done safely:** ~1 km, app-open only, 8-hour decay, symmetric silent pause, no arrive/leave events, no "last seen", countdown *to* togetherness but never time apart (03 §2.1 Map). Love8 and Widgetable turned location and battery into engagement bait (01 §2.5, §2.7).
- **The translator** — invisible to the recipient, equal-weight buttons, pull-only (03 §2.2). Therapists name in-the-moment conflict help the biggest gap in the category (01 §3.3 #20); every 04/05 scenario that reached a fight found it useful.
- **Understand** — charitable readings as an antidote to anxious rumination (04 S4, S9, S13).
- **Blind reveal everywhere it matters** (36Q, Love map, Sliding Scale) — the market's most-loved mechanic after prompts themselves (01 §3.1 #9).
- **No streaks, no badges, no leaderboards; skips have no consequence** (SOUL §5 P1; Together D8). Streak loss from bugs/time zones is pain #13 and an "ADHD accommodation by accident" (04 S12).
- **Safety architecture in principle:** at-risk recipient only, keyword-only, never a guarantee (SPEC §11 constraints 3, 5, 6). No competitor has any of it (01 §7).
- **Inclusive by omission:** no gender fields, chosen chat name, neutral avatar (04 S11). Coral and Love Nudge lost users at the front door (01 §5 item 7).
- **Healing mode** — private, ex-blind, role-free (03 §2.2); the market has nothing comparable (01 §7 item 5).

### 1.3 The biggest risks

1. **Trust catastrophe from the spec–code gap** (05 Part B; THESIS §9 risk 5). Likelihood today is not "designed down"; it is open.
2. **Resuming the AI layer before the suppression and adversarial gates** and producing a misread that feels like a verdict on the partner (05 S1, S11; THESIS §6.5).
3. **Ceremonial drift** (THESIS §6.2) now has a twist: the journal is so useful that couples may live in Planning and never bring a fight to chat. Conflict capture must stay the launch gate; the journal is not a substitute signal.
4. **Faith or sex content leaking to a partner who did not opt in** — a hard churn event both ways (04 S7b; 01 §2.1 representation tension). A lint-tested gate is a precondition, not a nicety.
5. **Founder capacity** (THESIS §6.9). §3 alone is weeks of work plus DV, clinical and suicide-prevention authorship that must start now.
6. **Self-harm and victim disclosure handled by a reflection bot** (05 S4, S5). This is the one failure that produces a headline and a death.

### 1.4 The theory of change, one sentence

**Attune improves relationships by making it easy, frequent and safe for each partner to be perceived as responsive by the other — through specific appreciation, well-received good news, quick repair after flooding, regular strengths-first check-ups and shared novelty — while giving each person a private, honest mirror of their own patterns and never a verdict on their partner.** (Grounded in 02 §0.3 #1–4, §6.1–6.3, §6.11, (a) #1–8; SOUL §3, §5 P4–P5.)

### 1.5 What Attune must never become

A scoreboard, a surveillance tool, a nag, a companion, a judge, a slot machine, a paywall between two people, or a product that takes away what it gave. (SOUL §2, §8, §11; SPEC §11; Decision 28; 01 §5 items 3, 6, 8; 02 C6.) Concretely, for the roadmap below: no partner-facing count of anything; no ratio, frequency or streak targets; no AI that interprets the partner, auto-sends affection in a user's name, or sustains a dialogue; no feature a partner can enable about the other; no ending that notifies; no faith, sex or health content by default or by inference; no seeing your partner's side behind a paywall.

---

## 2. Coverage matrix

**Status key** (from 03): **Strong** = live and reachable and fit for purpose; **Partial** = live but thin or missing the relational layer; **Built-unreachable** = code exists, no route or flag; **Missing** = nothing. **Evidence** = the 02 confidence for the best app-deliverable mechanism in that domain. **Market** = demand signal strength from 01 (High / Med / Low) with the row cited.

### 2.1 Planning tab (the couple's plans, lists, money, goals)

| Domain | Status in Attune | Evidence (02) | Market (01) | What's there / what's missing (source) |
|---|---|---|---|---|
| Goals, dreams & shared meaning | **Partial** | Moderate — Michelangelo / secure-base goal support (§14 [LONG+exp]); shared meaning is [CC] | High — "future/engaged/premarital" 236 mentions (§4); bucket list praised (§2.1 Flamme) | Goals template with "Why this matters to us", Progress with couple-only total (03 §2.1). No personal dreams with "how to support me", no bucket list layer (04 S14 b). |
| Money | **Partial — logistics only** | Moderate — felt fairness over shared expenses (§10.1 Gillespie [XS] n=10k); money dates [CC] | High — Honeydue praise for transparency-with-choice, 67% low-star for sync/drift (§2.6); finance underserved (§2.8 scoping review) | Expenses, budget, per-entry split, Home & bills (03 §2.1). No recurrence, no money-values conversation, no couple total per period, audit log visible (04 S13; 05 S10). |
| Chores & mental load | **Partial — tallies forbidden** | Moderate — cognitive labour (§10.1 Daminger [QUAL]); appreciation buffers unfairness (§6.3) | Med — "coworkers… this helps us" (§4); nag hated (§3.2 #19) | Checklist assignee, hand-off proposals, "Either" items (03 §3). No recurring chores, no whole-task ownership (noticing/planning), no felt-fairness reflection (04 S3; 05 S1). |
| Self-expansion / novelty / dates | **Partial** | Moderate — novel-arousing activity (§6.4 [XS+exp]) | High — play 3,530 mentions; ready-to-run date plans (§3.1 #5, #24) | Ask Attune Ideas/Nearby live, Together ideas flag-off, Date nights/Trips templates (03 §2.1–2.2). No "try something new" mechanic, no sensory/access filters (04 S12, S14). |
| Celebration / capitalisation | **Partial** | Moderate–High — active-constructive responding (§6.2 [XS+LONG]) | High — shared memories 940 mentions (§3.1 #11) | Progress celebration, countdowns, wedding template (03 §3). No "share a win" flow; care cards cover stress only (04 S3, S14). |
| Transitions (move-in, wedding, baby) | **Partial — templates without conversations** | High for parenthood (§12.2 Doss [LONG]; Family Foundations [RCT]); Moderate for sliding-vs-deciding (§4.2 [LONG]) | High — engaged/newlywed future planning (§4); parents' content mismatch (§4) | Moving house, Wedding, Baby gallery templates (03 §2.1). No conversation packs; Baby template is pregnancy-shaped (04 S2, S5, S8). |
| Parenting | **Missing** | High (§12.2) | Med — "goals for kids", kid-safe discretion (§4) | Baby template, After-bedtime ritual, one Sliding Scale item (03 §3). No newborn track, co-parenting load, grandparent-in-household, post-separation co-parenting (04 S8; 05 S6). |
| Family / in-laws | **Partial — names and birthdays** | Moderate–Low (§12.3 Bejanyan [XS]: involvement ≠ control) | Med–High for Ghana (03 §3; THESIS §5) | Family members with birthday reminders; `about_member_id` has no UI (03 §2.1). No relation/side, no family pack (04 S5; 05 S11). |
| Grief | **Missing** | Low–Moderate (§12.5 [LONG]) | Low (no corpus signal; inferred from memory-loss anger) | Nothing; countdowns and birthdays of the deceased fire blind (05 S7). |
| Memory / time capsule | **Partial** | Moderate — savouring (§14 [LONG+CC]) | High — richer memories (§3.3 #8); photo loss is the angriest failure (§5 item 2) | Timeline, Story, map pins, "On this day" (03 §2.1). Photo memories deferred; no backfill; time capsule planned only (04 S10). |

### 2.2 Calendar tab (Together hub: events, rituals, proposals, care)

| Domain | Status | Evidence | Market | Notes |
|---|---|---|---|---|
| Rituals of connection | **Strong** | [CC] for rituals; High for boosters/check-ups (§6.11 [RCT]) | High — small daily ritual 1,041 mentions (§3.1 #6) | Five templates, skip/pause with no counts (03 §2.1). Missing: gratitude, money date, devotion, reunion/departure, "the thing we keep coming back to" (03 §3; 05 Part C). |
| Bids & responsiveness | **Partial — measured, not supported** | High (§6.1) | High — "feeling closer" 713 mentions (§3.1 #2) | Big-day care cards (stress only); bid type computed, never shown (03 §2.2). No turning-toward practice, no good-news card (04 S3). |
| Appreciation / gratitude | **Missing** | High (§6.3 [LONG+diary]) | High — implied by "closer" and "see growth" (§3.3 #11) | Nothing; the journal bank avoids "grateful" by design (03 §3). The clearest rule-compatible gap in the programme. |
| Relationship check-ups | **Partial — dead loop** | High (§6.11 Córdova [RCT]) | Med — "see how we've grown" (§3.3 #11); "this app thinks every couple has issues" (§2.1 Flamme) | Weekly check-in built; reminder is a stub; Pulse cron paused; shared dimensions leak private answers (03 §2.2; 05 P0-6). No quarterly strengths-first check-up (04 S14). |
| Reunions / transitions (LDR, deployment) | **Missing** | Moderate — reunion instability (§9.1 Stafford & Merolla [LONG]); relational turbulence (Knobloch [XS]) | Med — meetup planning requests (§3.3 #19) | Countdown exists; nothing after arrival or before return (04 S1; 05 S9). |
| Health & caregiving | **Missing** | Moderate–Low (§12.4) | Low–Med — "wife has MS" location use; disability-aware requests (§2.7, §3.3 #25) | Daily reminders don't exist (yearly only); no caregiving card (04 S10). |
| Faith observances | **Missing** | Moderate — opt-in layer (§11) | Med — 12 Paired faith requests; 1/38 apps (§2.8) | Users hand-build Ramadan; AI refuses faith-adjacent care (04 S6, S7). |
| Discretion on device surfaces | **Partial** | High (§13.3 #4; §12.10 outness) | Med — no lock-screen previews, neutral icon (§3.3 #16) | No partner name or app name on widgets; but titles leak, no neutral icon, widgets deploy-pending (04 S11). |

### 2.3 Map tab (presence, distance, places)

| Domain | Status | Evidence | Market | Notes |
|---|---|---|---|---|
| LDR closeness | **Strong (recent)** | Moderate — co-presence, assurances, end-date certainty (§9 [XS/QUAL]) | High — LDR is the most enthusiastic segment, 880 mentions 89% positive (§4) | Approximate presence, distance card, dual clock, reunion countdown, story pins, widget (03 §2.1). Pending `db push` and device checks. Missing "Our plan" card, tentative reunion, sensitive-location posture (04 S1; 05 S9). |
| Trust & safety of presence | **Strong by design; copy gap** | High (§13.3 #2; §10.1 Fox & Warber [XS]) | High — eSafety, Griffith; "stopping sharing reads as distrust" (§2.7) | Symmetric opt-in, silent pause, no timestamps. Onboarding copy treats sharing as neutral rather than "not a trust test"; no 90-day sunset check (05 S2, S13). |
| Place-based memory | **Strong** | Moderate (savouring) | Med (memories) | Story pins with home-area warning (03 §2.1). Grief-safe hiding missing (05 S2 "hide a period"). |

### 2.4 App-wide (chat, AI, Pulse/Verdict, quizzes, games, safety, lifecycle, community)

| Domain | Status | Evidence | Market | Notes |
|---|---|---|---|---|
| Love maps / knowing each other | **Strong** | Moderate ([CC] + responsiveness) | High — "learning new things after years" 305 mentions (§3.1 #3) | 60 prompts, coverage not accuracy, weekly refresh (03 §2.2). Thin at 60; no stage bias; no "moments" domain (04 S4, S14). |
| Conflict & repair | **Partial** | High — gentle start-up, flooding break, apology structure, repair attempts (§1.1, §6.8, (a) #7, #11, #12) | High — conflict help "the biggest gap" (§3.3 #20) | Translator and Understand live. No pause/time-out, no repair tray, no apology helper, no withdrawer tool, no post-fight debrief (03 §3; 04 S4; 05 S1, Part C). |
| Acceptance / perpetual problems | **Missing** | High — IBCT (§3 [RCT+MA]) | Med — "neutral options so disagreement isn't a growth area" (§3.3 #12) | Nothing; Sliding Scale gaps lead nowhere (04 S2, S6; 05 Part C gridlock ritual). |
| Sex & intimacy | **Missing (by undecided default)** | High for communication and the backfire of assigned frequency (§8 [MA+RCT]); Moderate for communal strength | High and two-sided — Coral "saved my marriage" vs asexual opt-out, "too much kink", Spicer leak and survivor trigger (§2.3, §3.2 #10, #22) | "Spicy" is flirting; "Intimate" is emotional (03 §3). Games become proxies for the unspoken topic (04 S9). |
| Faith & spirituality | **Missing** | Moderate (§11; small experiments) | Med–High for Ghana; Muslim/Jewish gaps (§2.8) | One Sliding Scale item; AI refuses religion wholesale (03 §3; 04 S6–S7). |
| Self-knowledge quizzes | **Built-unreachable (3 of 4)** | Attachment Medium (ECR-R); love languages Low as typology, Moderate as responsiveness (§7) | Med — "finding out love languages is PRICELESS" vs Love Nudge nagging (§2.2) | Attachment reachable only via Pulse, with a pairing card that conflicts with the specs; the other three are orphaned widgets (03 §2.2, §4.1). |
| Pulse / Verdict (attunement) | **Partial / Built-unreachable** | Low for scores (§ (b) "relationship scores"); High for check-ups | Med — growth over time (§3.3 #11); hated when generic (§2.2 Lasting) | Pulse shared, cron paused; Verdict no route, seven gates unchecked (03 §2.2). |
| Trust & safety / IPV / coercion | **Partial — placeholder** | High (§13) | High — eSafety safety-by-design ask (§7) | 9 phrases, English only, 3 countries, no PIN, quick exit on two screens, no session control (05 preamble, S3). |
| Crisis / mental health | **Missing** | High as guidance (§ C1) | Med — implied by "trauma-blind content" (§3.2 #22) | No crisis line anywhere; self-harm by the writer excluded; journal unchecked (03 §3; 05 S4–S5). |
| Breakup & healing | **Strong for the individual; harmful for the pair** | Moderate (§15) | High — unmet need #15; pains #11–12 (§3.2–3.3) | Healing mode good; ending pushes, archives instantly, no export, no pause, no reopen (05 S6, S14, Part D). |
| Neurodivergence & access | **Missing** | Low–Moderate (§12.7); High as design guidance (§12.8) | Med — accessibility and disability-aware requests (§3.3 #25) | No Dynamic Type audit; no self-set reminders; one translator register (04 S10, S12). |
| LGBTQ+ / minority stress | **Partial — inclusive by omission** | Moderate (§12.10) | High — praise and punishment both fast (§4) | No gender fields (good); discretion incomplete; no outing resources (04 S11). |
| Community | **Strong** | [CC] perspective-taking; no outcome evidence | Med — commons as front door (THESIS §7.2); cruelty risk (04 S9) | Forums, Opinions, community prompts live (03 §2.2). Needs tag mute, moderation block list, pregnancy/sex mute (05 S8, S12). |

**Reading the matrix.** Three domains are strong (rituals, LDR closeness, community/healing for the individual). Most are partial because the *logistics* exist and the *relationship* layer does not. Four are missing where the evidence is High (appreciation, acceptance, parenting transition, crisis routing). Three are built-but-unreachable (quizzes, Verdict, the Together AI flag) and should be either routed or removed in Phase A.

---

## 3. Safety floor (P0) — consolidated, de-duplicated, ordered

**Rule:** every item below ships before any real couple is onboarded and before any growth feature in §4 Phase B. Items are consolidated from 05 Part B (P0-1 to P0-13), 04 §A gap 1 and §D step 1, and the per-scenario P0s in 04 S4, S7, S8, S10, S11. Order is by lethality, then by dependency (pure code first, clinician-dependent work started in parallel on day one). Several items only implement rules already written in `SAFETY_SYSTEM_SPEC.md` or `SOUL §7`.

| # | Fix | Source | Acceptance criteria (all must hold) | Dependency |
|---|---|---|---|---|
| **F1** | **Ending never notifies; `paused` is real; 30-day read-only window; export before seal.** | 05 P0-1, S3, S6, Part D; SOUL §7; Decisions 3/19 | (1) `end_relationship()` enqueues zero notification work (integration test asserts an empty outbox for the other member). (2) Lifecycle-sync client push on `ended` removed; the other partner sees a warm in-app screen on next open ("{Name} has ended your shared space. For 30 days you can read and download what you shared…"). No reason field; no reply affordance. (3) `pause_relationship()` sets `status='paused'`: chat read-only, presence purged, AI refuses, proposals frozen, Pulse hidden, no push; 30-day prompt to decide. (4) `ended → archived` after 30 days, or per-person "seal my side now", or immediately when either starts a new relationship. (5) `export` Edge Function produces JSON + media per 05 D.2: own media, full chat text, Planning, calendar, own stories/moments/check-ins/journal; **never** AI-derived partner data, safety data, translator originals. Available during `active` too. (6) Memory resurfacing, countdowns, widgets, Live Activity, ICS feed and calendar mirror stop at `ended`, not at archive. (7) Archived media hard-deleted at 12 months unless legal hold; told at ending. | Data model design (05 D.1); export function (new). |
| **F2** | **Safety PIN gate enforced.** | 05 P0-2; 04 S11 | (1) Cold start and resume: if `safety_requires_unlock` is set, the PIN screen is the first frame; no deep link, widget or notification bypasses it. (2) Biometrics alone do not clear it. (3) Salted KDF hash in the OS keystore, never synced. (4) Five failures → escalating local delay, no wipe. (5) Recovery = sign out to a generic state until DV review approves another path. (6) Setup offered on first visit to Support resources and in Settings; quick exit works with no PIN (return = signed-out). (7) Real-device tests both platforms, including app kill during decoy. | None. |
| **F3** | **Quick exit from every authenticated screen; Android task removal.** | 05 P0-3; 04 S11 | (1) Triple-tap target mounted once in the root shell above GoRouter; widget test asserts coverage of every named route (Settings, resources, Planning entry, journal, Healing, full-screen map, games). (2) Android `finishAndRemoveTask()` via audited channel, verified on three OEMs. (3) iOS cover within 200 ms plus switcher image. (4) Activation sends no network, analytics or log. (5) Together/map device data and widget opt-in clear. | None. |
| **F4** | **Symmetric visibility: read ticks and story seen-state off by either partner; default off for new couples; both to re-enable.** | 05 P0-7; 04 S1, S4 (default-off), S13 | (1) One setting "Show when we've seen things" covers chat `read_at` and story seen-state. (2) Either partner turning it off disables it for both; UI never shows who. (3) Turning on requires both. (4) **Default off for couples linked after this ships**, with one line at Ask 1: "Read receipts are off to start. Turn them on together whenever you like." (5) Server-enforced: `mark_conversation_read` stops writing `read_at` while off; test proves the partner's client cannot read it. **Decision taken here:** 05 proposed default-on; 04 proposed default-off for 90 days. Default-off wins: a controlling partner cannot re-enable alone (05 S3), and LDR/anxious archetypes are harmed by the default (04 S1, S4). | None. |
| **F5** | **Pulse cannot leak a private check-in; Emotional safety self-facing; no on-demand refresh of check-in dimensions.** | 05 P0-6, S1, S3, S5 | (1) Shared dimensions recompute only when both have checked in that week; otherwise hold with a "waiting for both" confidence state. (2) Refresh does not recompute check-in-driven dimensions. (3) Emotional safety removed from the shared score, shown only to its author; shared score re-weighted across four dimensions; disclosed in the Pulse explainer. (4) `PULSE.md §10` "You ✓ Jordan ✗" closed as **no**. (5) Pulse hidden while `paused`. | None (Pulse code). |
| **F6** | **Engine-level quiet hours; delete the dormant streak counter; remove Mirror's attentiveness flag.** | 04 S1 (quiet hours, streak), S3 (Mirror); PRINCIPLES §C | (1) Notification engine defers (never drops) any non-safety push falling in the recipient's local 22:00–08:00; covers date-poll, forum and reminder budgets that currently bypass it. (2) `chat_streaks` flag, migration-side computation and client fetch removed; a grep gate in CI forbids `streak` in chat providers. (3) Mirror flag removed or converted to an invitation ("Want to ask {name} how they're really doing?"). | None. |
| **F7** | **Account security for the IPV threat model.** | 05 P0-8, S3 | (1) Settings → "Where you're signed in": sessions/devices, last active (owner-only), "Sign out all other devices" revokes refresh tokens server-side. (2) New-device sign-in → in-app notice to the owner only; never SMS/email. (3) No recovery path through a partner's phone or email. (4) Phone change needs current session + OTP to the new number + in-app notice. | Supabase auth session API. |
| **F8** | **Discreet surfaces before widgets ship: titles off by default; neutral icon and name.** | 04 S11, S8; 02 §13.3 #4 | (1) Widget, Live Activity and calendar mirror show "Next plan" + time, never the title, unless the user opts into titles per surface. (2) iOS alternate icon and neutral display name ("Plans"); Android launcher alias; off by default; per user; never synced to the partner. (3) Notification sender name follows the alias. (4) Push copy audit: no event titles that could out an intimate plan. | Widget device checks (03 §4.3). |
| **F9** | **Replace the attachment pairing card; add the attachment caveat; no typology anywhere.** | 04 S4, S12; 03 §4.1; 02 §2.3, (b) | (1) Ask-2 reward becomes the two anchors reflected back plus "something for tonight" (one This-or-That or Love map prompt). (2) `attachment_compatibility_service.dart` pairing output removed from every surface. (3) Attachment result is dimensional, self-facing, with the fixed caveat ("written for a general population; if you're autistic or ADHD some items may not fit"). (4) No screen, push or export ever contains a pairing or type statement about the couple. **[needs amendment §8.9 to Decision 13]** | None. |
| **F10** | **Support resources v2: country-routed, usable, complete.** | 05 P0-4, S3–S5, S10, S12; 04 S8, S11, S13 | (1) Versioned resource model with `country_code` and `category ∈ {emergency, dv, crisis, sexual_assault, addiction, grief, perinatal, lgbtq_legal, financial_control}`; country from SIM/locale with manual picker; unsupported → international directory + "contact local emergency services". (2) Emergency number first everywhere. (3) Tap-to-call/open behind a confirmation that states monitored-device risk; never auto-dial. (4) "Plan for leaving quickly" removed; all planning copy DV-authored. (5) Per launch country: ≥1 crisis (suicide), sexual-assault, addiction and perinatal line, each `verified_at` within 7 days of release and 90 days thereafter; expired verification blocks release. (6) Offline cache. (7) Screen-capture protection where supported. (8) Sections reachable without any trigger. | DV professional + local organisation authorship (start week 1). |
| **F11** | **Writer-facing disclosure routing (victimisation, sexual assault, self-harm), deterministic, provider-suppressing; journal lock; resources on journal and Healing.** | 05 P0-5, P0-10, S4, S5, S12; 04 S8; THESIS §6.8 | (1) Separately versioned `self_disclosure-x.y.z` corpus with DV, clinical and suicide-prevention sign-off; English plus reviewed Ghanaian-English/Twi-in-Latin variants; language-gated. (2) Evaluated server-side on journal save, chat send (sender side), AI Sessions/Understand/Assist input, truth answers, Healing reflections — **before** any provider call. (3) On match: provider call skipped (test proves text never reaches `gemini_json.ts`); writer sees a private card with country-routed resources; strangulation/weapon matches add the medical-emergency line; nothing persisted (no row, flag or analytics); partner sees nothing; in shared AI sessions the refusal is indistinguishable from a redirect. (4) Recipient-facing supporter card for self-harm in chat, clinician-reviewed, never labels the partner. (5) Golden fixtures: quotation, lyrics, third-party disclosure, negation. (6) No detector path imports an AI SDK. (7) Journal: optional separate lock offered at first entry; lock screen says only "Notes"; latest-reflection previews hidden when locked; journal never resurfaces. (8) Every journal and Healing screen shows Support resources in overflow and is under the root triple-tap. | Clinician + DV + suicide-prevention authorship (start week 1). |
| **F12** | **Production lexicon, normaliser fix, Tier 2 monitoring/outing/financial families.** | 05 P0-9, S3, S13; 04 S11, S13 | (1) `normalizeForTokenPhrase` replaces zero-width characters with a space; regression test proves "if you lea​ve" matches. (2) Language eligibility gating. (3) DV-approved lexicon replaces the 9 phrases, including Tier 2 monitoring/control ("send me a photo of where you are", "show me your phone", "you're not going", "who's that"), outing threats ("I'll tell your family"), and financial control, with youth-register and Ghanaian variants. (4) Golden fixtures per family; ≥90% branch coverage; mutation survivors reviewed. (5) Config version bump resets Tier 3 counts. | DV lexicon review. |
| **F13** | **Chapter-scoped data and provable deletion.** | 05 P0-12, S14; 01 §5 item 4 | (1) `personal_insights`, translator logs, Love map and game answers carry `relationship_id`; client filters to the active relationship; CI canary with two former partners and one new partner proves zero cross-chapter rows via SQL, RPC, realtime and Edge Functions. (2) Account deletion hard-deletes psych profiles, raw/aggregate quiz data, journal, Healing, Love map/game answers, translator logs, media within 30 days; delete-then-reregister test proves nothing resurfaces. (3) Only anonymised safety events survive. | Migration. |
| **F14** | **Private safety check as the gate on any conjoint conflict tool.** | 05 P0-13, S3, S13, Part C | (1) 4-item self-facing check adapted from HARK with clinician authorship; "prefer not to say"; offered at Ask-2 and quarterly from Pulse. (2) Own table, `auth.uid()`-only RLS; never in `psych_profiles`; never a Pulse/Verdict/Healing/dating input; invisible to the partner. (3) Positive → resources once + invisible one-directional flag that hides conjoint steps (pause chip's partner reply, gridlock ritual, debrief share), tightens Layer 2 framing; expires at 180 days unless renewed. (4) Negative/skipped changes nothing. (5) No analytics on answers. | Clinician authorship; precedes Phase B conflict toolkit. |
| **F15** | **AI suppression and adversarial suites before any cron resumes; Understand/Assist deterministic pre-check and do-not-interpret refusals.** | 05 P0-11, S1, S2, S5, S12; RISK_SOLUTIONS §2.3 | (1) `…_resume_ai_jobs.sql.disabled` stays disabled until: the safety→insight suppression flag exists and is tested; the co-framing line ships on every shared conflict insight; the adversarial Verdict suite passes; stonewalling/contempt signals suppressed per market. (2) Understand and Assist run the writer-facing corpus plus a do-not-interpret family ("not tonight", "stop", "I don't want to") before the provider; matches return fixed cards, requester-only ("A no is complete on its own…"). (3) Understand footer: "These are guesses from the words alone. Only they know what they meant. If this is about trust, a trained outside perspective helps more than a reading" + handoff link. (4) Prohibited-pattern set extended to negative attribution of any named third party (05 S11). | F11 corpus; eval sets. |
| **F16** | **Accessibility gate on the three journal tabs.** | 04 S10; 01 §3.2 #23 | (1) Dynamic Type to accessibility sizes without truncation in Planning blocks, agenda, ritual cards, game cards. (2) 44 dp targets (map "Done" at 24 dp fixed). (3) Contrast ≥4.5 (map subtitle 4.42 fixed). (4) VoiceOver/TalkBack labels on all block types. (5) Reduced motion respected in the delight layer. | None. |
| **F17** | **Faith/sex gate lint (precondition for Phase C content).** | 04 S7, S9; §5 below | (1) Every faith-tagged and sex-tagged string, prompt and template carries a gate key. (2) A test renders every surface for a user with `faith_content=none` and `sexual_content=off` and asserts zero tagged strings. (3) Gates read the *viewer's* own preference only. | Couple profile schema (§5). |

**Order of implementation.** Week 1 start in parallel: F10/F11/F12/F14 authorship engagements (one DV professional, one couples clinician, one suicide-prevention reviewer, one Ghanaian cultural reviewer; batch per THESIS §6.9). Code order: F6 → F4 → F5 → F3 → F2 → F7 → F9 → F8 → F13 → F1 → F16 → F10 → F12 → F11 → F14 → F15 → F17. F1 is the deepest change and the most dangerous current behaviour; it goes as soon as the data model is agreed (§10 Q9–Q10). Nothing in Phase B starts until F1–F9 and F13 are merged; nothing AI-dependent resumes until F15.

**What the floor does *not* include, deliberately.** Automatic conflict detection, risk scores shown to users, AI in any safety path, partner notification of anything (02 C1, C3; SPEC §11 constraints 3, 6).

---

## 4. The roadmap

### 4.0 How success is measured without surveillance (applies to every feature)

The soul forbids DAU-shaped metrics (SOUL §8) and 02 C7 says measure outcomes, not engagement. The measurement kit, used for every feature below:

- **Opt-in outcome panel.** At Ask-2 and quarterly, each partner may opt into a 60-second private survey: a 4-item satisfaction scale (CSI-4 class), a 3-item perceived-partner-responsiveness scale (02 §6.1), and one "did Attune help this month? (yes / a bit / no / it made something harder)". Answers are self-facing, aggregated only above n=50, never shown to the partner, never a Pulse input, exportable and deletable. Panel membership is never required for any feature.
- **Post-use helpfulness tap.** One optional "Was this useful?" (yes/no) after a tool is used, with no follow-up and no partner visibility.
- **Harm signals** (aggregate only): safety-card display rate by surface (no content), quick-exit activations (count only, no user), uninstall within 72 h of a feature's first use, "this doesn't feel right" dismissals on AI output (RISK_SOLUTIONS calibration router), Opinions reports.
- **Conflict capture** stays the launch gate (Decision 27). The journal's activity is not a proxy for it.
- **Forbidden:** per-couple engagement dashboards, partner-facing counts, A/B tests on safety or verdict copy (03 §1.4), any metric that rewards time-in-app.

"Works if" lines below name the panel item or harm signal that would move.

### 4.1 Phase A — Safety floor and unlock what is built (weeks 1–10)

§3 is the first half of Phase A. The second half routes, resumes or removes what is already written.

| # | Item | Where | Action | Source | Effort |
|---|---|---|---|---|---|
| A1 | Ship the Map, distance widget, Stories realtime, Together device surfaces | Map, Calendar, Chat | `db push` `20261016100000`/`20261017100000`; device checks; wire Stories realtime refetch; Together widget/share sheet/Live Activity/calendar mirror **after F8** titles-off | 03 §4.3; 04 S1 | S–M |
| A2 | Route the quizzes | Profile → Know yourself | Love languages rebuilt as **"What feels loving to me right now"**: multi-select, rated, context-tagged (stressed / sad / celebrating), changeable, shared only by choice, labelled "a popular framework, not a science" (02 §7.3). Communication and conflict quizzes routed behind the existing clinical sign-off gate with "where you differ" copy, no "growth area" (01 §3.3 #12). Attachment stays dimensional with the F9 caveat. | 03 §2.2, §4.1; 04 S3, S12 | M |
| A3 | Verdict: hold and rename | — | Keep `VerdictScreen` unrouted until the §14.2 gates pass **and** B4 exists; in-app name "Monthly readout"; its role becomes the optional AI appendix to the quarterly check-up (B4), never the primary artefact. **[needs amendment §8.6]** | 03 §4.1; 05 S1, S6; SPEC §16 | S (decision) |
| A4 | Resume Layer 1/2, Pulse (chat-aggregate dimensions) and Love map refresh | Backend | Only after F15 and F5. Verdict cron stays off per A3. Cost measured per couple from day one (Decision 1). | 03 §4.1; 05 P0-11 | S |
| A5 | Flip `ai_together_enabled` | Calendar | After the `claimProviderStart` RPC smoke test in prod; ideas remain proposals; sensory/access tags added in C7. | 03 §4.1 | S |
| A6 | 48-hour gate, keep-private/share prompt, day-7 pivot | Onboarding | Implement the spec as written; pre-join reflections default private on partner join. | 03 §2.2; 04 S4 | S |
| A7 | Weekly check-in reminder | Pulse | Schedule `send-checkin-reminders` (Sunday, local, within quiet hours); answers remain private; after F5. | 03 §2.2 | S |
| A8 | Translator and AI eval additions | AI | Boundary statements survive rewriting (no negation removed); Ghanaian in-law scenarios; **seventh need "communal obligation"** adopted in translator and Layer 2 taxonomies (closes CLINICAL §12). | 05 S10, S11 | S–M |
| A9 | Celebration suppression hook | Chat, Planning | Planning Progress celebration and first-message shimmer read a per-user quiet state (used by B9); nothing celebratory fires while set. | 05 S5, S7 | S |
| A10 | Doc reconciliation | Architecture | Apply §8 amendments; mark Gemini as provider; reconcile Decisions 3/13/19; delete the two §14 roadmap lines. | 03 caveats; THESIS §6.11 | S |

### 4.2 Phase B — Highest-leverage, evidence-backed features (weeks 8–26)

Each card: tab/screen · user story · mechanism and grade · market signal · design sketch · soul check · data/privacy · effort · dependencies · works if.

**B0. Couple profile v1** — *Settings → Us; read by every surface.* Story: "Tell Attune what shape we are so it stops asking a 41-year marriage about first dates." Mechanism: personalisation is a precondition for every domain feature; content-fit complaints are pain #9 and request #3 (01 §3.2, §3.3). Market: filters that are ignored are a reliable 1★ (Evergreen, Couple Joy, 01 §2.1). Sketch: §5 in full; shared fields edited by either, silently; per-partner fields self-set, partner sees only "set". Soul: produces no type, score or compatibility statement (SOUL §2a, §5 P5); nothing inferred (02 C5). Data: special-category fields per user under `auth.uid()` RLS; excluded from AI prompts; cleared on unlink; never on device surfaces. Effort: M. Deps: F17 lint. Works if: content-mismatch complaints in panel free text fall; faith/sex gate lint stays green.

**B1. "I noticed…" appreciation note + private appreciation jar** — *Chat composer long-press; Together hub card.* Story: "I want to thank him for remembering my mother's appointment without it becoming a performance." Mechanism: specific-act gratitude → feeling appreciated → appreciating → responsiveness and commitment (Gordon 2012 [LONG]; Algoe 2010 diary; 02 (a) #3, High); appreciation removes the satisfaction penalty of unfair housework (Psych Sci 2022). Market: "feeling closer" is love #2; Evergreen's "see how we've grown" (01 §3.1, §3.3 #11). Sketch: fixed format "I noticed you {free text}. Thank you." delivered as an ordinary message with a subtle leaf motif; recipient may save to a self-facing jar; faith-on users see an optional "Thankful for you because…" phrasing (04 S7). Empty-state copy: "Specific beats sweeping." Soul: no counter, no history view, no reminder to send one, never a Pulse "gratitude rate" (SOUL §8; 02 §6.3 avoid). Data: message subtype; existing per-message tone analysis only. Effort: S. Deps: none. Works if: panel responsiveness item rises for users who sent ≥1; no uninstall spike.

**B2. "Share a win" + ask-about-it card** — *Chat action; Timeline highlight; Together card.* Story: "I got the grant and he replied 'nice!!' between meetings." Mechanism: active-constructive responding predicts trust, intimacy, commitment; responses to good news predict breakups better than responses to bad (Gable 2004, 2006; 02 (a) #6, Moderate–High). Market: celebrations and memories 940 mentions (01 §3.1 #11). Sketch: posting a win creates a highlight and an in-app card for the partner (never a push): "Ask {name} about it — what was the best part?" opening Chat with a fixed draft. Soul: no AI enthusiasm sent in anyone's name (02 C6 #8); partner's reply is theirs; nothing celebratory fires from message content (CHAT spec). Data: reuses big-day care machinery. Effort: S. Deps: A9 quiet state. Works if: helpfulness tap; panel responsiveness.

**B3. Conflict toolkit v1** — *Chat composer.* Five composer affordances, all pull-only, all fixed copy or user-edited scaffolds, hidden for a relationship with a positive private safety check (F14). (a) **Pause chip**: three fixed messages naming a return ("I'm getting flooded. I'm stepping back for 30 minutes, not away from you. I'll come back."), sender-only 20–45 min timer with a self-soothing card and a return prompt; partner sees the message and one optional fixed reply "Okay. I'll be here." (02 (a) #7 [LONG+CC]; 05 Part C; 04 S4 withdrawer card). (b) **Repair tray** (long-press send): six reviewed phrases ("Can we start over?", "I see my part in this."…) (02 (a) #12). (c) **"Help me apologise"**: four fields — what I did; what it cost you; what I'll repair; one concrete thing I'll do differently; never a request for forgiveness; no accept/forgive control for the recipient (Lewicki 2016; Luchies 2010 doormat; 02 (a) #24; 05 S2, S10). (d) **"Help me start this conversation"**: observation → feeling → need → request with the seven-need taxonomy (02 (a) #11; 04 S4 pursuer scaffold). (e) **Plain register** for the translator alongside NVC (04 S12). Market: conflict help in the moment is request #20; Ember's 24-hour windows are the anti-pattern (01 §3.2 #19). Soul: no automatic appearance, no partner-visible timer, no count of pauses or apologies, no Pulse input, no record of who used what (SOUL §9 translator; 02 §13.3 #9). Data: Pause and repair are ordinary messages; apology/start scaffolds use the translator's existing content-free log. Effort: M. Deps: F14, F15. Works if: helpfulness tap; conflict-capture rate (fights arrive *here*); no rise in safety-card displays after launch.

**B4. Quarterly strengths-first check-up** — *Pulse → "Check-up".* Story: "A check-up, not a score." Mechanism: the Marriage Checkup RCT — two annual strengths-first feedback visits improved intimacy, acceptance and satisfaction for 2+ years, most for the most distressed (Córdova 2014 [RCT]; 02 §6.11, (a) #2, High); gains fade without boosters (Christensen 2010; Kennedy 2017). Market: "see how we've grown" (01 §3.3 #11); "this app thinks every couple has issues" (01 §2.1 Flamme) — strengths-first answers both. Sketch: each partner privately answers six items (two strengths, one "more of", one "less of", one "ask each other", one private safety check item from F14); sees own answers; both may opt into a **themes-only** joint view (no numbers, deltas or attribution) followed by one "Ask each other" prompt and links to the toolkit and the handoff card. Soul: combines nothing but the two people's *chosen* themes, so it is not a couple report (SPEC §11 #2); no AI prose in v1; no push to the partner. Data: answers private under `auth.uid()`; joint view materialised only on dual consent, deletable. Effort: M. Deps: F5, F14. Works if: panel satisfaction at +90 days for check-up completers vs non-completers (opt-in, aggregate).

**B5. Conversation-pack engine + first six packs** — *Planning (as a block inside a template) and Together (as a one-off ritual).* Story: "Before he moves in, I want to know what he thinks about guests, money and phones in bed, without it being a test." Mechanism: relationship-awareness content matches skills drills (Rogge 2013 [RCT]; 02 (a) #25); sliding-vs-deciding at transitions (Stanley 2006 [LONG]); reunion instability (Stafford & Merolla [LONG]); transition-to-parenthood prevention (Doss 2009 [LONG]; Family Foundations [RCT], High); family allocentrism vs control (Bejanyan 2015 [XS]). Market: engaged/newlywed future conversations, 236 mentions; parents' content mismatch; LDR meetup planning (01 §4, §3.3 #19). Sketch: one mechanic (private answer → side-by-side reveal when both finish, the 36Q/Love map pattern) with fixed prompts, individually shareable answers, "where you differ is where the conversation is" copy, never a "growth area". Packs: **Living together** (8 prompts), **Coming home / after the visit** (reunion, 5 before + 3 after), **Our families** (5), **First year with a baby** (4 + "Who's on tonight" table), **Money values** (4), **The thing we keep coming back to** (gridlock, 5; 05 Part C). Soul: no AI synthesis of the pair; no resolution engine; skippable; never pushes the partner (SOUL §5 P4–P5; SPEC §11 #2). Data: answers per user, revealed only on mutual completion; chapter-scoped (F13). Effort: M (engine) + S per pack. Deps: B0 (stage/distance offer packs). Works if: helpfulness tap per pack; panel "did Attune help" among couples in a transition.

**B6. Recurrence** — *Planning Home & bills, new Household category; Reminders.* Story: "Rent is monthly; medication is daily; the app repeats yearly." Mechanism: logistics that reduce mental load; whole-task ownership including noticing and monitoring (Daminger 2019 [QUAL]; 02 (a) #23); self-set executive-function supports (02 §12.7). Market: shared lists/calendar inside the relationship app is request #7 (01 §3.3). Sketch: reuse the calendar's repeat engine for Checklist and Table rows (weekly/monthly) and for self-set reminders (daily/weekly); Household category items carry an owner and the fixed sub-text "owning this means noticing it needs doing, deciding, doing it, and checking it got done"; self-set reminders bypass the partner-push budget because they are not partner pushes. Soul: no completion counts, no history of who did what, hand-off remains a proposal (Together D7, D8; 02 §13.3 #9). Data: no new tables beyond repeat rules. Effort: M. Deps: none. Works if: helpfulness; "fairness" item in the quarterly check-up free text.

**B7. Family relation type, side, per-event tag, "has passed"** — *Reminders → Family; Calendar filter.* Story: "Every aunt is a name and a birthday; the calendar is a family digest I can't filter; Mama Esi's birthday will fire with balloons." Mechanism: per-event visibility for family (02 §12.3); grief-safe resurfacing (02 §12.5, §14.3). Market: Ghana relevance (THESIS §5); memory-loss anger (01 §5). Sketch: `relation`, `side` (mine / {partner}'s / ours), `lives_with_us`, `has_passed` (converts birthday to optional remembrance with remembrance wording); wires `about_member_id` into the event editor and a "Family" filter. Soul: enables logistics, not access; family members never have accounts. Data: shared, deletable by either. Effort: S–M. Deps: none. Works if: "put away gently"/remembrance use without complaints; family-pack uptake.

**B8. "Our plan" card, tentative reunion, sensitive-location posture** — *Map distance card; Calendar reunion events; Map onboarding.* Story: "Nobody can say when the distance ends; a hard date on my home screen is a promise the Army doesn't make." Mechanism: uncertainty about *whether* the distance ends is more corrosive than its length; a review date helps when the end date is unknown (02 §9.1 "Will it ever end?" [XS]; (a) #19); OPSEC and location as a coercion vector (02 §13.3 #2). Market: LDR couples' meetup planning (01 §3.3 #19). Sketch: Our plan = next visit (date or "not yet"), review date ("When will we next talk about the distance?"), one shared sentence; tentative reunion shows "Soon · November", never a day count, no 08:00 push until confirmed; "My location is sensitive" keeps sharing off and makes the widget region map a separate opt-in (text-only ≥ 800 km by default). Soul: countdown *to* togetherness allowed, elapsed time apart never (distance-widget rule). Data: a Planning entry; a per-user map flag. Effort: S. Deps: A1. Works if: helpfulness; LDR panel satisfaction.

**B9. Quiet states and gentle archiving** — *Pulse/Settings (private), Planning entries, Story.* Story: "He's depressed; the app sent confetti. We lost the pregnancy; the countdown still fires." Mechanism: dyadic coping and support matching (Falconier 2015 [MA]; 02 (a) #9); stress spillover and charitable attribution (Neff & Karney [LONG]; (a) #10); trauma-informed no-surprise-resurfacing (02 §12.8); grief-style difference read as not caring (Büyükcan-Tetik 2017 [LONG]). Sketch: (a) **"Having a hard time"** and **"Going through a loss"** private 14-day switches: silence shimmer, Progress celebrations and AI-idea tone; plain daily summary; suppress On this day and Love map fears/dreams; offer once a fixed line the user may send ("I'm in a heavy patch. I may be quieter; it isn't about you."). (b) **Support-request chips** in chat: "I need to vent", "Help me decide", "Just sit with me". (c) **"Put this away gently"** on any entry with a countdown or on Baby/Wedding templates: archives, cancels pushes, removes from Recent and On this day, no notification. (d) **"Hide a period"** per user from own resurfacing surfaces. Soul: not a mood tracker, not a Pulse input, no partner visibility unless sent (SOUL §8 privacy). Data: per-user flags; nothing shared. Effort: M. Deps: A9. Works if: harm signal — uninstall after a celebratory surface drops; helpfulness.

**B10. "A trained outside perspective" handoff card + supporter content** — *Pulse, Settings, Understand footer, every toolkit overflow.* Story: "When should we see someone, and what would we even look for?" Mechanism: escalation ladder to evidence-based couple therapy; never conjoint when a safety flag exists (02 C2); stigma-aware referral copy (CLINICAL §9.3). Market: therapists call apps "vitamins, therapy is medicine" (01 §4). Sketch: what couples counselling is; what to look for (IBCT, EFT, BCT; a clinician who screens each partner separately); how to find one per country; a line on individual support; a clinician-authored "When your partner is struggling" card. Never framed as "recommended for your relationship". Soul: a resource card, not an insight (SOUL §2 "not a therapist"). Data: static, versioned with the resource catalogue. Effort: S. Deps: F10. Works if: card opens; no complaint signal.

**B11. "Our year" — templated recap (non-AI first)** — *Calendar → Our story; shareable composed image.* Story: "Day 300 and no way to see how we've grown." Mechanism: savouring and shared meaning (02 §14, Moderate); the thesis's named breakout artefact (THESIS §7.2). Market: request #11; Evergreen (01 §3.3). Sketch: templated cards from Planning, Timeline, Stories, rituals kept, map places, Love map coverage ("34 of 60 asked"); the couple picks which cards to share as an image; no scores, no who-did-what, no comparison; AI narrative only later behind the verdict gates (D1). Soul: a story, not a score (THESIS §7.2); no counts of per-person contribution (Together D7). Data: derived from data the couple already made; nothing new stored. Effort: M. Deps: B7 (grief-safe exclusions), B9 hide-a-period. Works if: share rate (couple's own action), helpfulness.

**B12. Presence honesty copy, 90-day sunset, phone-checking scenarios** — *Map onboarding; Scenario game; Forum seed.* Story: "One in five of our friends think tracking is normal." Mechanism: location sharing read as commitment and stopping as distrust (Griffith; eSafety; 01 §2.7); perceived intrusion lowers satisfaction (02 §10.1); awareness content works (Rogge 2013). Sketch: onboarding line shown to each partner separately ("Sharing your area is not a test of trust…"); a private, once-only "Still want this on?" at 90 days for map and busy strips; three clinician-written Scenario situations on phone-checking, location and passwords; a seeded FOR/AGAINST room with an eSafety-style explainer. Soul: safety is never a gift (SOUL §6); no nag. Effort: S. Deps: A1. Works if: pause/stop without complaint; harm signals flat.

**B13. Per-person topic exclusions, community prompt moderation, tag mute** — *Settings → Content; games; Opinions.* Story: "Never show me prompts about my past / pregnancy / alcohol." Mechanism: trauma-informed choice over content (02 §12.8); content warnings and opt-outs are a named unmet need (01 §3.3 #23); the single control that resolves the representation tension (05 S12; 01 §4). Sketch: private multi-select exclusions applied to every prompt bank (This-or-That, Truth-or-Dare, Love map, 36Q, community, Ideas); the game simply skips; deterministic block list for assault/non-consent/coercion terms plus human review before any community prompt publishes; "report this prompt" everywhere; per-user Opinions tag mute. Soul: partner never sees the list. Data: per user. Effort: S–M. Deps: B0 (same preference store). Works if: survivor/asexual/faith complaints absent from panel free text.

### 4.3 Phase C — Domain expansions (months 6–12), each behind the gates in §5

**C1. Intimacy layer (triple-gated, clinician-authored)** — *Settings → Intimacy; Games → Private lists; Pulse check-in.* Story: "Neither of us has said the word in a year." Mechanism: sexual communication correlates with function, desire and orgasm (Mallory 2019 [MA], 48 studies); satisfied long-term couples set a mood, communicate, add variety (Frederick 2017 [XS] n≈39k); assigned frequency backfires (Loewenstein 2015 [RCT]); matched desire per se doesn't predict satisfaction, communal responsiveness does (Kim 2020; Day 2015) (02 §8, (a) #15–16, High/Moderate). Market: Coral normalised low desire (105 votes) but leaked privacy; Spicer's match-only reveal was loved and then leaked via "Change Answers"; a survivor found an assault prompt "appalling"; asexual users asked for an off switch (01 §2.3, §3.2 #10, #22). Sketch: Gate 1 per-partner `sexual_content` default off; Gate 2 shared surfaces only when both on; Gate 3 fresh mutual opt-in per session. Content: three desire-education screens (spontaneous vs responsive; discrepancy is common; what helps), a **yes/maybe/no mutual-match list** revealing only mutual yes (and optionally mutual maybe), no "change answers" path that exposes the grid, no third-party or assault-adjacent items in the base bank, content warnings on explicit packs, revocable (revoking hides prior matches); talk starters ("One thing I've been curious about…"); a private check-in item "How satisfied are you with physical intimacy right now?" that feeds only the user's own view; postpartum and later-life notes with "talk to a clinician" framing; persistent "Switch to Connecting" in Intimate/Spicy sessions. Soul: no frequency logs, initiation tracking, timing-window signalling or AI commentary on desire; "no" is never visible; nothing on device surfaces (02 §8.3, C6 #5; 04 S9; 05 S12). Data: answers per user; intersections computed server-side; never in AI prompts; excluded from the other partner's export; deleted on unlink. Effort: L. Deps: B0, B13, F17, clinician + sex-therapist authorship. Works if: opt-in helpfulness; panel sexual-satisfaction item (private, opt-in) for gated users; zero leak incidents in the RLS canary.

**C2. Faith layer (per-partner, tradition-respecting, never default)** — *Settings → Us; Together rituals; Calendar packs; Planning pack.* Story: "I want to pray for him every night and keep it private; he never wants scripture from an app." Mechanism: sanctification predicts quality for those who hold it (Mahoney 2003, zr≈.32 [MA+XS]); partner-focused prayer increased forgiveness and commitment in small experiments (Fincham 2010; Lambert 2010); interfaith risk runs through child-rearing and holidays (Lehrer & Chiswick [LONG]) (02 §11, (a) #29, Moderate). Market: 12 Paired faith requests; 1/38 apps; no Muslim or Jewish married-couple app; Covenant's "keep God and my husband a priority" (01 §2.8). Sketch: per-partner `faith_content` (none / christian / muslim / jewish / other / prefer not), default none; **Devotion together** ritual (time + free-text "Reading" block — the app ships no scripture); private **Pray for {name}** (faith-on) and **Hold {name} in mind** (everyone); observance calendar packs added by one partner for themselves and proposed to the other; **Interfaith pack** (five prompts) offered when preferences differ; AI scope allows care-within-a-practice the user names ("ideas to support my partner during their fast") and keeps refusing doctrine and adjudication; journal "no reflection for this one" toggle so prayer text isn't NVC-parsed. Soul and hard rule: no religious copy ever in safety, Healing or ending flows; never used to discourage leaving abuse (02 §11.3; 05 S11); gate lint (F17). Data: special-category, per user, never inferred, never in prompts except the user's own faith-tagged question, never on widgets/mirror. Effort: M. Deps: B0, F17, tradition reviewers (§6). Works if: 7a-type uptake with zero 7b-type leak reports.

**C3. Money, relational layer** — *Together ritual; Planning Budget/Goals; Safety resources.* Story: "Every 'where did the money go' ends in 'you don't trust me'." Mechanism: fairness over shared expenses predicts quality more than housework (Gillespie 2019 [XS]); money dates [CC]; approach-motivated giving, no ledgers (Impett 2005) (02 §12.1, (a) #14, #23, Moderate). Market: Honeydue's "choose what you share" loved, bank-sync drift hated (01 §2.6). Sketch: **Money date** ritual with a fixed agenda (what came in, what went out — from their own statements, one worry each, one thing to celebrate, one decision); **couple total of the shared pot per budget period** (one number for both, never per partner) **[owner decision §10 Q4]**; **Pay down** goal variant with a private balance and a shared progress bar; audit shown only on explicit History tap, no per-person filter, excluded from export; "Covered by" column with no badges; journal shortcut from Home & bills; financial-control resources (F10). Soul: no per-partner totals ever (Planning D6, D13); no bank sync (04 §E). Effort: M. Deps: B5 Money values pack, B6 recurrence. Works if: helpfulness; fairness free text.

**C4. Parenting** — *Planning Baby template → Expecting / First year; Family; end-of-relationship flow.* Story: "Nine weeks in, his mother runs the kitchen and we haven't had twenty minutes." Mechanism: sudden persistent post-birth decline (Doss 2009 [LONG]); Family Foundations improved co-parenting and reduced family violence to age 10 (Feinberg [RCT]); fathers in BBH felt more appreciated (02 §12.2, (a) #17, High); perinatal depression and IPV risk (02 §12.2). Market: parents time-poor and want discretion (01 §4). Sketch: two-phase template; "Who's on tonight" weekly table (owner per night, no history beyond the week); conversation pack (B5); grandparent as household member via B7 `lives_with_us`; perinatal lines in F10; postpartum intimacy note via C1 gate; **"Keep the family calendar"** at ending — a child-only businesslike calendar and list for both, no chat/map/presence/AI (05 S6; 02 §15.2). Soul: no counts; no partner-controlled reminders. Effort: M (+L for the co-parenting surface, see D2). Deps: B5, B7, F1. Works if: new-parent panel satisfaction; helpfulness.

**C5. Health, caregiving, later life** — *Together hub card; Reminders; Settings.* Story: "Grace manages the pills; the app repeats yearly." Mechanism: dyadic coping (Falconier [MA]); caregiver-burden check-ins and we-coping framing (02 §12.4, Moderate–Low); older couples need accessibility, health, grandparenting and later-life sexuality, not conflict drills (Carstensen 1995; Lindau 2007; 02 §12.11). Market: large-text failures; "25 years… who needs an app" (01 §4). Sketch: `health_context: caregiving` private flag → weekly private "How heavy did this week feel?" (light/okay/heavy/too much), caregiver resources, "What I can carry, what I can't, who else could help" pack; daily/weekly self-set reminders (B6); later-life intimacy note (C1 gate); "Plans" card first under Chat for couples who never opened Planning (discoverability). Soul: never shown to the partner unless shared; no scores. Effort: S–M. Deps: B6, F16. Works if: older-cohort retention without complaints; helpfulness.

**C6. LDR and transition depth** — *Together rituals; Story; Love map.* Co-presence ritual templates ("Watch together", "Cook the same thing", "Open line"); anticipatory savouring 3 days before a reunion/trip riding the daily summary; "moments" domain in Love map ("Relive one moment this month you felt close"); "Coming home" ritual reviewed with a military-family specialist; blackout-aware Pulse confidence (no recompute when one partner has had no activity for 7+ days, no "who"). Mechanism: 02 §9.2, (a) #18, #20, #21, #28 (Moderate). Market: LDR enthusiasm (01 §4). Soul: no constant-contact pressure; no last-seen. Effort: S each. Deps: B5, B8. Works if: LDR panel satisfaction.

**C7. Neurodivergence and access** — *Profile card; Together; Translator; Ideas.* "How I communicate" card (multi-select statements shown to the partner as *their words*, no diagnosis field anywhere in the schema); per-user opt-in "Tell me when a plan I'm part of changes" (in-app card, never a feed of the partner's activity, never private/partner-only items); sensory/access filters on Ideas/Nearby and date templates (quiet, low-light, step-free, no crowds, short); attachment caveat (F9); neurodivergence added to clinical review scope. Mechanism: responsiveness predicts satisfaction regardless of neurotype (Yew 2023 [XS]); reminders controlled by the other partner become monitoring (02 §12.7); trauma-informed predictability (02 §12.8). Market: "doesn't work well if one partner is disabled" (01 §2.2). Soul: differences as access needs, not character flaws; D7 no-feed kept by per-user notice. Effort: S–M. Deps: B0, B6. Works if: helpfulness; panel.

**C8. Memory lane, backfill, time capsule** — *Timeline/Story; Planning block.* Photo blocks un-deferred; "Years before Attune" dated backfill so On this day has something to say for a 41-year couple; grief-safe snooze/hide per person; **Message for later** (text or voice; unlock on a date or by the partner at any time with a confirm). Mechanism: savouring (02 §14, Moderate); forced nostalgia harms (02 §14.3). Market: richer memories #8; Between's photo loss (01 §3.3, §5). Soul: durable and exportable (SOUL §7; F1 export covers it). Effort: M. Deps: F1 export, B9 hide. Works if: helpfulness; zero data-loss incidents.

**C9. Dreams board + "try something new"** — *Planning → Dreams; Together monthly card.* Personal aspirations with a visibility choice and a support preference ("Cheer me on" / "Help me plan" / "Just know"); the partner sees only the chosen level, no progress tracking by the partner, no reminders from the partner; a monthly non-AI "Neither of you has done this" card from a curated local bank with C7 filters, proposed to both, no record of skips. Mechanism: secure-base, non-interfering support (Feeney 2004; Drigotas 1999; 02 (a) #22 [LONG+exp]); self-expansion (Aron 2000; (a) #13). Market: bucket list praised (01 §2.1 Flamme); play (01 §3.1 #5). Soul: intrusive support backfires (02 §14.3) — the partner never gets a "remind them" button. Effort: S–M. Deps: B0 `intent`. Works if: helpfulness; panel.

**C10. Premarital track, family & obligations guide, pace controls** — *Planning "Before the wedding" template; Conversations; Ask-2.* A church-compatible weekly prompt track with a free-text "Homework from our counsellor" block (the pastor is never in the app); a Ghanaian-reviewed options-framed guide on visits, money, grandchildren, holidays; a private per-partner "How would you like prompts to feel for now? (gentle / open / playful)" whose intersection sets This-or-That tone, Love map domain order and 36Q availability (05 S11). Mechanism: premarital education improves communication (Fawcett 2010 [MA]); awareness ≥ skills (Rogge 2013); never make the deep end mandatory (02 §6.5). Market: LoveTrack at bridal expos; Lasting as pre-counselling (01 §4); churches as the Ghana channel (THESIS §7.2). Effort: S–M. Deps: B5. Works if: uptake via church partners later (D4).

**C11. Gallery hide, per-event "shared with title hidden", cycle-tracking hard rules** — *Planning gallery; Calendar; future spec.* "Hide this for us" on any gallery template (either, silent, reversible); a visibility level between busy-only and shared for clinic appointments; cycle tracking, if ever built, written now with: phase sharing opt-in by the tracker only, no fertile-window or "good day" nudge to the partner, no intercourse logging, degrades to nothing during a declared treatment period, partner note is a fixed template not AI (05 S8; 02 §12.6, §8.3) **[needs amendment §8.8]**. Effort: S. Works if: infertility-cohort complaints absent.

### 4.4 Phase D — Moonshots (month 12+)

| # | Moonshot | Why it is worth it | Precondition | Evidence / market | Effort |
|---|---|---|---|---|---|
| D1 | **Our year with an AI narrative** | The thesis's breakout artefact (THESIS §7.2) as a warm, sourced story — never a score | Verdict gates §14.2 passed; adversarial suite; B11 live for two cycles | THESIS §7.2; 01 §3.3 #11 | M |
| D2 | **Co-parenting surface after separation** | Children are harmed most by ongoing interparental conflict; post-separation is a high-IPV window; separate apps serve it badly | F1 model; C4 relation=child | 02 §15.1–15.3 [RCT for co-parenting modifiability]; 01 §4 parents | L |
| D3 | **Reopen within 90 days** | On–off couples lose everything each cycle today | F1, F13 | 05 S14; 01 §5 item 4 | M |
| D4 | **B2B2C cohorts for churches and counsellors** | Ghana's premarital counselling runs through churches; "a tool your couples use between sessions" | C10; clinical and cultural review; a cohort-code model that never gives the institution access to data | THESIS §7.2; 01 §4 engaged | L |
| D5 | **Consented cross-cultural validation study** | Turn the WEIRD gap into a contribution: ECR-R calibration, NVC fit, the communal-obligation need, on Ghanaian terms | ≥2,000 active couples; ethics partner; opt-in panel (§4.0) | THESIS §5, §10; CLINICAL §12; 02 evidence gaps | L |
| D6 | **User-authored prompt packs with moderation** | "Write our own questions" is request #4; anti-repetition lever (§6) | B13 block list; human review queue | 01 §3.3 #4, #5 | M |
| D7 | **Multilingual safety and content** (Twi, Ga, Hausa, French) | The lexicon is English-only; West African expansion is the plan | F12 language gating; native reviewers | THESIS §7.1; 05 P0-9 | L |
| D8 | **Historical WhatsApp import flag flip** | Cold-start shortener for engaged couples; already dual-consented | F15 crons stable; clinical calibration of the lower confidence tier | THESIS §6.2; SPEC §16 | S (flip) + review |

---

## 5. The couple profile / personalisation model

**Purpose.** One place that lets every surface fit the couple without producing a type, a score or a compatibility statement (SOUL §2a, §5 P5), without inferring anything from messages or games (02 C5), and without ever showing a partner a preference the other did not choose to share. It replaces the owner's "four couple types" with fields: modes stay `personal | couplesPending | couples` (03 §2.2); a couple's shape is data on the relationship, not a mode **[needs amendment §8.11]**.

### 5.1 Fields

| Field | Values | Scope | Who edits | Who sees | Used by |
|---|---|---|---|---|---|
| `stage` | new (<6 mo) / established / engaged / married / parents / later-life | Shared | Either, silently | Both | Pack offers, Love map domain bias, 36Q chapter pacing, Scenario skew, "Our year" framing (04 S4, S14) |
| `distance` | together / apart / mixed; optional `distance_ends_on` | Shared | Either | Both | LDR surfaces on/off; retire countdown and Next-visit when the date passes (proposal, not imposition); offer Living-together pack (04 S2) |
| `intent` | grow / reconnect / navigating a change | Shared | Either | Both | Hub bias: grow → Dreams, challenges, savouring; reconnect → "I noticed…", rituals, check-up; change → the relevant pack (04 S14) |
| `household` | just us / with family / with children (ages banded) / with a helper | Shared | Either | Both | Newborn and family packs; "Who's on tonight" owners; discretion defaults (04 S8) |
| `prompt_pace` | gentle / open / playful | Per partner | Self | Partner never | Intersection sets This-or-That tone, Love map order, 36Q availability (05 S11) |
| `faith_content` | none / christian (sub-tradition optional) / muslim / jewish / other (free text) / prefer not to say | **Per partner, special-category** | Self | Partner sees "set / not set" only | Faith layer; observance packs; AI care-within-practice scope; "Thankful for you because…" phrasing (04 S6–S7) |
| `sexual_content` | off / on | **Per partner, special-category** | Self | Partner sees on/off only | Gate 1 of C1; postpartum/later-life notes; Intimate tone availability |
| `health_context` | none / caregiving / illness / treatment (free text optional) | **Per partner, special-category, private** | Self | Partner never (unless the user shares a card) | Caregiving card; quiet states; gallery hides (04 S10; 05 S8) |
| `communication_preferences` | multi-select statements ("I mean what I say, literally", "Tell me early when plans change"…) | Per partner | Self | Partner, **by choice**, as the user's own words | "How I communicate" card; plan-change notice opt-in (04 S12) |
| `access_needs` | sensory / motor / vision / cognitive-load tags | Per partner | Self | Partner never | Idea and date filters; reminder defaults; never a diagnosis field (04 S12) |
| `topic_exclusions` | sex and bodies / alcohol / family / pregnancy and children / my past / faith / money (extensible) | Per partner | Self | Partner never | Every prompt bank, Ideas, community (05 S12; B13) |
| `quiet_state` | none / having a hard time / going through a loss; 14-day expiry | Per partner, private | Self | Partner never unless a fixed line is sent | Celebration suppression, resurfacing, AI tone (B9) |
| `location_sensitive` | bool | Per partner | Self | Partner sees only the normal "just you on the map" | Map and widget posture (05 S9) |
| `language` | app locale; content locale | Per partner | Self | n/a | Content and lexicon eligibility |
| `accessibility` | Dynamic Type, reduced motion, screen reader (from OS) | Per device | OS | n/a | Rendering |

### 5.2 Gates

- **Viewer-gated content.** Faith- and sex-tagged content renders only for a viewer whose own gate is on. The F17 lint test is the release gate for any such content.
- **Dual-gated shared surfaces.** Shared intimacy lists, Devotion together, observance packs on the shared calendar appear only when **both** gates are on, and each shared session asks fresh mutual opt-in (the 36Q pattern). Either partner's switch to off hides the shared surface for both, silently (no "Kofi turned it off").
- **Proposal-gated shared changes.** Observance packs and retiring LDR surfaces are proposals the other accepts, never silent impositions (Together §3).
- **Safety-gated conjoint tools.** A positive private safety check (F14) hides conjoint steps regardless of any other field; the flag is invisible to both partners.
- **No inference.** No field is ever set, suggested or pre-filled from messages, games, calendar content or AI output. Onboarding never asks "what do you want to work on" (01 §2.1 Flamme complaint).

### 5.3 Storage rules

1. Special-category fields (`faith_content`, `sexual_content`, `health_context`, `access_needs`, `topic_exclusions`, `quiet_state`, the private safety check) live in a per-user table under `auth.uid()`-only RLS with no service-role bypass, separate from `psych_profiles` and from the shared `relationships` row (SPEC §11 #2 pattern; 02 C5; GDPR Art. 9).
2. **Never in AI prompts** unless the user's own request in that session carries the topic (e.g., a faith-tagged Ideas question); never as system-prompt context for the partner's requests; never in Layer 1/2/Verdict inputs.
3. **Never on device surfaces** — widgets, Live Activity, calendar mirror, notification bodies, app icon.
4. **Never inferred, never defaulted on.** `faith_content` defaults to `none`; `sexual_content` to `off`.
5. Exportable and deletable by the user alone; cleared on unlink; not part of the partner's export (05 D.2).
6. Shared fields change silently (no activity feed, Together D7); the only exception is the per-user plan-change notice the autistic partner can opt into for plans they are *in* (C7).
7. No analytics on special-category values; aggregate counts only above n=50 and only for capacity planning (how many faith packs to review).

### 5.4 How the profile resolves the archetype tensions (from 04 §C)

| Tension | Resolution through the profile |
|---|---|
| Faith content vs never-any-faith (04 S7a vs S7b; S6 internally) | Per-partner gate, default none, viewer-gated rendering, dual gate for shared rituals, lint test; AI refuses doctrine but allows care-within-practice. The atheist couple never sees the word; the Pentecostal couple gets a time slot and their own words. |
| Sexual content vs asexual / survivor / conservative / discreet households (S9, S8 vs S7a, S11) | Per-partner gate default off; triple gating; "no" never visible; topic exclusions; nothing on device surfaces; partner sees only on/off. |
| LDR presence vs surveillance (S1, S2 vs S4, S11, 05 S3, S13) | Already structural in the map; extended to chat by F4; `location_sensitive`; presence is never framed as trust (B12). |
| Silent edits vs need for change notice (S11 safety vs S12 autism) | Per-user opt-in notice about *shared plans the user is in*; never a feed of the partner's activity. |
| Family as warmth vs family as control (S5, S8, S10 vs S11; Western scripts) | Packs offer options; relation types enable logistics not access; discretion settings override family surfaces for the closeted partner; the AI may not characterise a named third party (F15). |
| Anticipation vs no counters (S1, S2) | Countdown to togetherness allowed; elapsed time never; `distance_ends_on` retires countdowns by proposal. |
| Tallies forbidden vs felt unfairness (S3, S8, S13) | Non-numeric private fairness reflection; whole-task ownership on the item; appreciation notes; never counts or history. |
| Depth for happy couples vs "this app thinks every couple has issues" (S14 vs S3, S9) | `intent` biases the hub; strengths-first check-up; onboarding never asks about problems. |
| Playful fun vs streak guilt (S4, S14 vs all) | "Welcome back" warmth, skips without consequence, Our year recaps; never a counter or lock-screen timer. |
| Low-literacy discoverability vs two-tab shell (S10) | "Plans" card first under Chat; larger type; no new tab. |

---

## 6. Content strategy

### 6.1 Libraries, by domain and stage

| Library | Current size (03) | Target at Phase C | Stage tagging | Gate |
|---|---|---|---|---|
| Love map prompts | 60 in 4 domains | 200 in 5 domains (+ "moments") | new / established / later-life bias | none; topic exclusions apply |
| 36 Questions | 120 (3 chapters) | 120, re-reviewed; chapter 3 clinically certified (not self-certified) | chapter availability by `prompt_pace` | none |
| This-or-That | 50 of 230 | 230 incl. Connecting/Romantic/Playful; Spicy = flirting; Intimate (emotional) needs sign-off | by `prompt_pace` | Intimate dual consent (existing) |
| Truth-or-Dare | 50 of 250 | 250 with block list | by `prompt_pace` | Intimate dual consent |
| Sliding Scale | 6 statements | 30+, with "neither / depends"; transitions-authored | by `stage` | none |
| Scenario | 10 | 20 incl. 3 phone-checking/location/passwords | — | none |
| Conversation packs | 0 | 12: Living together, Coming home, Our families, First year, Money values, Gridlock, Interfaith, Caregiving, Before the wedding, Family & obligations, Reunion (LDR), Later life | by `stage`, `distance`, `household` | pack-specific (interfaith by faith prefs; none otherwise) |
| Appreciation phrasing | 0 | 1 secular template + 1 faith-on variant | — | faith gate for variant |
| Repair tray phrases | 0 | 6, localised | — | safety check hides nothing here (repair is one-sided and safe) |
| Date and activity ideas | AI-generated | AI + a curated local bank of 150 (Accra, Kumasi, London diaspora) with sensory/access/cost tags | — | access tags |
| Desire education and intimacy lists | 0 | 3 screens + base list of ~80 items (no third-party, no assault-adjacent) + 2 optional explicit packs with warnings | — | triple gate |
| Faith packs | 0 | per tradition (§6.2) | — | per-partner faith gate |
| LDR packs | Next visit template | Our plan, Coming home, co-presence rituals, savouring prompts, deployment variant | by `distance` | none |
| Resource catalogue | 3 lines | per country × 9 categories, verified | — | never gated |

### 6.2 Faith packs and the secular default

- **Secular default for everyone:** "Hold {name} in mind" intention-setting, gratitude for the partner, values conversations, meaning-making rituals (02 §11.2). This is the only content a `none` user ever sees.
- **Christian (launch, Ghana):** Protestant/Pentecostal and Catholic variants; Devotion together (time slot + user's own reading; the app ships no scripture), Pray for {name}, observance pack (Advent, Lent, Easter, Christmas), premarital track compatible with church counselling. Reviewed by a pastor and a Catholic lay reviewer plus the clinical advisor.
- **Muslim (launch, Ghana):** Devotion/dua for {name}, prayer-time busy template that never names the religion on device surfaces, observance pack (Ramadan, Eid al-Fitr, Eid al-Adha), interfaith guide. Reviewed by an imam or Islamic family counsellor. The market gap is real (01 §2.8).
- **Jewish (diaspora phase):** shalom bayit framing, Shabbat ritual template, observance pack. Reviewed by a rabbi or Jewish family educator.
- **Other / traditional:** free-text ritual name and time only; no authored content until reviewed with practitioners.
- **Hard rules for every pack:** no gender-role prescriptions; no "covenant/submission/forgive seventy times seven" framing anywhere near conflict, safety, Healing or ending flows (02 §11.3; 05 S11 item 6); opt-in per partner; nothing shown to a partner who did not opt in.

### 6.3 Intimacy packs

Clinician- and sex-therapist-authored; base list monogamy-neutral with no third-party content; explicit packs behind content warnings; postpartum, later-life, illness/medication and trauma-aware notes with "talk to a clinician"; no gendered desire stereotypes; the "no" is never visible and there is no path that reveals the partner's grid (01 §2.3 Spicer leak; 02 §8.2–8.3).

### 6.4 Authorship and review process

1. **Authorship.** Fixed copy is written in-house against 02's grades; every prompt carries `domain`, `stage`, `gate`, `locale`, `evidence_note`, `version`.
2. **Clinical review** (blocking for interpretive, intimacy, conflict and crisis copy): one couples clinician engagement covering quizzes, packs, toolkit, check-up; a suicide-prevention specialist for F11 cards; a DV professional for F10/F12 and the private safety check; a sex therapist for C1 (batch per THESIS §6.9).
3. **Cultural review** (blocking per market): a Ghanaian reviewer for all packs, family content, NVC/translator register, lexicon variants; faith reviewers per tradition; "options, not doctrine" rule checked line by line (02 §12.9).
4. **Safety review ("abuser-in-the-loop")** for every pack and prompt bank: how could a controlling partner use this to pressure, monitor or gather evidence (02 C3).
5. **Accessibility and plain-language pass** (F16): Dynamic Type, short sentences in the hub.
6. **Versioning.** Content tables carry `version` and `reviewed_by`; a bump re-opens review; no prompt ships with `is_reviewed=true` set by the author (03 ⚠ 36Q chapter 3).

### 6.5 Avoiding repetition (a top market complaint)

Repetition is 22% of low-star reviews across five apps and paying couples finished Evergreen in three weeks (01 §2.1, §3.2 #8). Mechanisms:

- **Bank sizes** above (no bank below 150 for a weekly-cadence surface).
- **No-repeat windows:** a prompt answered by either partner is retired for that couple for 12 months; a skipped prompt for 90 days; chapter-scoped so a new relationship starts fresh (F13).
- **Stage and exclusion filtering** shrink the irrelevant share before the repeat window has to work.
- **Rotation by domain** (Love map's weekly bias) so the same domain is not drawn twice in a row.
- **Retire-on-fit:** a couple can mark "doesn't fit us" on any prompt; three such marks on a tag reduce that tag's draw weight for them (private; never partner-visible).
- **User-authored prompts** (D6) and community prompts after moderation extend the bank; LDR users explicitly asked for this (01 §2.1 Lovewick).
- **Quarterly content drops** announced in Our year/check-up, never as a push.

---

## 7. Business model principles

Derived from 01 §6 (what users accept vs resent), 01 §5 (failure modes), SOUL §8 (trust violations), RISK_SOLUTIONS §5 and §7.3 (product-change covenant), THESIS §7.3. These are principles, not a price list; the tier structure is an open owner decision (§10 Q8).

1. **One subscription covers both partners, priced to the relationship.** Praised wherever it exists ("$12 for both… not per person"; "one membership works for two people", 01 §6). Never a partner purchase that doesn't unlock for the other (Agapé, Couple Joy, Spicer packs on both phones, 01 §6).
2. **Never paywall seeing your partner's side.** Not answers (CoupleGrow), not the calendar beyond seven days (Cupla), not notes you already wrote (Cozy Couples) (01 §6 "resented"). The couple feature *is* the product. In Attune terms: chat, the journal tabs, proposals, reveals, Stories, check-in reveals and all safety are free at every tier, permanently (RISK_SOLUTIONS §5; SPEC §11 #5).
3. **No retroactive paywalls, no clawback of free features.** Lovewick 10→1, Paired's removed chat and store, Desire's dares, Cozy Couples' old notes: "users tolerate a paywall they meet on day one far better than one added later" (01 §5 item 3). The product-change covenant (RISK_SOLUTIONS §7.3) applies to export too: nothing exportable today becomes unexportable tomorrow (05 D.3 #5).
4. **No surprise charges.** Monthly option alongside annual; no trial that silently converts to annual; no double charging across web and store; one cancellation cancels for both; no charge after an ending or when the partner never joined (Lasting, CoupleGrow, Ember, 01 §3.2 #4). Prices in real currency, never virtual coins (SOUL §8 trust).
5. **Premium buys depth and permanence, never access, basics or safety.** Users pay for courses, extra packs, richer artefacts, backup/lifetime (01 §6 "accepted"). Candidates: expanded conversation packs and faith/intimacy packs beyond the first, Our year print/export extras, extended archive retention, Personal-mode depth, later B2B2C cohort licences (THESIS §7.3). Never: read receipts, quiet hours, export, resources, translator, check-up.
6. **No ads, no data sales, no training on user data, no mandatory data collection or friend recruitment as the price of free** (SOUL §8; Agapé's 3-connection gate and Between's porn ads, 01 §2.1, §2.4).
7. **No pay screen before value and no review nagging** (Together, Lasting, Covenant, 01 §3.2 #24). Rating prompts: at most once, after a self-reported positive moment, never from message content.
8. **No paid streak repair or loss-aversion taxes** — there are no streaks (SOUL §5 P1; Cozy Couples, 01 §6).
9. **Data portability as a product promise:** export at any time, the 30-day window at ending, hard deletion on request, told plainly up front (F1; SOUL §7; 02 C5). Avocado offered an export when it closed; Between lost 38,000 photos (01 §5). A **shutdown covenant** belongs in the ToS: 90 days' notice and export before any wind-down.
10. **Pricing that fits Ghana first.** Reviewers name $2–5/month as fair; annual-only "it's only $2.08/month" framing is resented (01 §6). Local currency, mobile money, a genuinely useful free tier.
11. **Lifetime option considered, upsell-free after purchase** (Between's red dots, 01 §6).
12. **Measure cost per active couple before pricing** (Decision 1); model-tier the AI; never degrade the free tier to sell relief (SOUL §8).

---

## 8. Proposed amendments to ATTUNE_SOUL / MASTER_SPEC / THESIS

All amendments are proposals for the owner; none is applied. Current text is quoted; replacement text follows; rationale cites the research.

### 8.1 SOUL §1 — name the journal as a surface

**Current:** "The product has a chat system, quizzes, games, a pulse score, a forum, and a dating mode. These are the surfaces through which intelligence is built and delivered."

**Replacement:** "The product has a chat system, a couple's journal (Planning, Calendar, Map), quizzes, games, a pulse score, a forum, and a dating mode. These are the surfaces through which intelligence is built and delivered. The journal is where a couple's life gets planned, remembered and shared; it is a second substrate alongside chat, and the same rules apply to it: no scoreboard, no counters, proposals not impositions."

**Rationale:** the journal is live and is where every everyday archetype found value first (04 S1–S3, S5, S14); the master spec has no Planning, Together, calendar or map (03 caveats). "Not a couples journal" in the same section stays: the intelligence is still the product.

### 8.2 SOUL §2 — add "Not a companion"

**Current:** section lists "Not a therapist… Not a judge… Not a surveillance tool… Not a game… Not a social media platform."

**Replacement (insert after "Not a therapist"):** "**Not a companion.** Attune's AI writes observations and ideas about the couple's own data. It never sustains a dialogue, never has a persona, never stands in for the partner at 02:00. The right answers to loneliness, grief or crisis in Attune are fixed resources, the commons, and the partner."

**Rationale:** Decision 28 is in the master spec but absent from the soul; 04 §E and 05 S5 both had to re-derive it; US companion-chatbot law exposure (RISK_SOLUTIONS §7.5).

### 8.3 SOUL §5 Principle 1 — no targets

**Current:** "No badges. No streaks. No leaderboards. Only accurate mirrors that show people where they actually are, where they were, and where they could go."

**Replacement:** "No badges. No streaks. No leaderboards. No targets: no positivity ratios, no frequency goals, no 'thank your partner N times'. Only accurate, self-facing mirrors that show people where they actually are, where they were, and where they could go."

**Rationale:** the 5:1 ratio is a conflict-tone heuristic, not a target, and is confused with Losada's withdrawn ratio (02 §1.1, (b)); assigned sexual frequency lowered happiness (Loewenstein 2015 [RCT]; 02 §8.1); gratitude quotas destroy the credibility of gratitude (02 §6.3).

### 8.4 SOUL §8 — new NEVER lines

**Add under "Psychological manipulation":**
```
NEVER: A partner-facing count, ratio, trend comparison or "growth area" label about the other partner or the couple
NEVER: Sex frequency targets, trackers, initiation logs or timing-window desire signalling
NEVER: A "remind my partner" control, however gentle
```
**Add under "Privacy violations":**
```
NEVER: Read receipts, seen-state, last-seen, typing indicators or location as defaults, as trust framings, or re-enableable by one partner alone
NEVER: Special-category preferences (faith, sexual-content comfort, health context, access needs) inferred from any data, sent to an AI prompt without the user's own request carrying them, or shown on any device surface
NEVER: Ending a relationship notifying the other partner by push, SMS or email
```
**Add under "Clinical overreach":**
```
NEVER: Attachment, love-language, horsemen or any typology label applied to the partner or to the pairing
NEVER: Religious framing in any safety, Healing or ending flow, or used to discourage leaving
NEVER: AI-written affection, apology or enthusiasm sent in a user's name without the user editing and choosing it
```
**Rationale:** 02 C6 #1–#8; 02 §13.3 #2–#3; 05 P0-1, P0-7; 04 S4 (attachment pairing), S7 (faith firewall); 01 §3.2 #19 (nudge as nagging); 02 §14.3 (intrusive support).

### 8.5 SOUL §9 — Pulse and Gamification boundaries

**Current (Pulse):** "Compute a relationship health picture from aggregated behavioural data across multiple sources, shown to both partners."

**Replacement:** "Compute a relationship picture from aggregated behavioural data across multiple sources. Shared dimensions are shown to both partners and move only when both have contributed that week; Emotional safety is shown to its author only. No dimension can be used to infer the other partner's private answers."

**Current (Gamification, Does):** "Apply completion drive (visible arcs), variable genuine discovery (verdicts, translator results), and hyper-local comparison (pulse score benchmarks against similar couples)."

**Replacement:** "Apply completion drive (visible arcs) and variable genuine discovery (verdicts, translator results). No comparison to other couples, named or anonymous."

**Rationale:** the Pulse boundary two paragraphs above already says "Never benchmark a couple against other named couples"; 02 C6 #2 forbids "couples like you" and percentile ranks; the inference hole is 05 P0-6 (S1, S3, S5).

**Current (Dating mode, Does):** "Generate a compatibility profile from the user's own behavioural data — attachment patterns, communication style, love language, conflict defaults…"

**Replacement:** "…attachment patterns, communication style, conflict defaults…" (delete "love language").

**Rationale:** DATING_MODE_SPEC already bans love-language similarity as compatibility evidence (03 §1.4); 02 §7 (Impett 2024).

### 8.6 MASTER_SPEC §1 — what success looks like

**Current:** "They get a clear verdict on their relationship — specific, sourced, honest — without being told what to decide."

**Replacement:** "They understand their own patterns and act on them with each other — more specific appreciation, quicker repair after a flooded moment, hard conversations started sooner and more gently, and a regular strengths-first check-up — without ever being told what to decide. The monthly readout is one artefact of that understanding, not the goal."

**Rationale:** §1.4 theory of change; Joel et al. 2020 (02 §0.3 #1); Córdova 2014 (02 §6.11); the Verdict is unreachable and its gates unchecked (03 §2.2), and 04 S14 shows a happy couple has no use for it as the primary artefact.

### 8.7 MASTER_SPEC §8.2 — love languages and quiz stance

**Current (table row):** "Love languages | 15 | Quality time/words/touch/acts/gifts spectrum | No — prompted after chat unlocks"

**Replacement:** "What feels loving to me right now | multi-select, rated, context-tagged (stressed / sad / celebrating) | Current preferences, changeable, shared only by choice; labelled 'a popular framework, not a science' | No — offered after chat unlocks. Never a typology, never a 'primary language', never a compatibility input."

**Add under "Results are spectrums, not labels":** "Attachment results are dimensional and self-facing. No pairing, type or compatibility statement about the couple is ever generated from any quiz. Every attachment result carries the caveat: 'These questions were written for a general population; if you're autistic or ADHD some items may not fit how you experience closeness.'"

**Rationale:** Impett, Park & Muise 2024 — people value all five, five factors aren't recovered, matching doesn't predict satisfaction; responsiveness to specific current preferences is the defensible core (02 §7, (b)); attachment labels become accusations (02 §2.3); the built pairing card conflicts with the other quiz specs (03 §4.1; 04 S4, S12).

### 8.8 MASTER_SPEC §8.3 — cycle tracking and reminders

**Current:** "AI note for partner: max 2 sentences, emotionally supportive framing, never clinical"

**Replacement:** "Partner note: a fixed template chosen by the tracker, never AI-written. The partner never receives a fertile-window or 'good day' nudge. No intercourse logging. The feature degrades to nothing during a declared treatment period if the user chooses."

**Current:** "AI-generated reminders: based on pattern data (e.g. 'You haven't logged a highlight in 3 weeks')"

**Replacement:** delete the line.

**Rationale:** 05 S8 (infertility); 02 §8.3 and §12.6; the deleted line is a guilt ping of the kind SOUL §8 forbids and 01 §3.2 #19 shows users hate.

### 8.9 MASTER_SPEC §14 — roadmap lines

**Current:** "Weekly intimacy challenges | Personalised to love language, retention mechanic | Month 4"

**Replacement:** "Intimacy layer | Opt-in per partner, clinician-authored; desire education, yes/maybe/no lists revealing only mutual yeses, talk starters; no frequency, no completion, no tracking | Phase C"

**Current:** "Live conflict cooldown | Real-time escalation banner — press-worthy | Month 5"

**Replacement:** "Pause chip and repair tray | User-initiated flooding break with a stated return, fixed repair phrases, apology helper; pull-only, never detected | Phase B"

**Current:** "Anniversary relationship report | Viral loop — AI-generated story of the relationship | Month 4"

**Replacement:** "Our year | Templated recap from the couple's own plans, rituals, places and prompts first; AI narrative only behind the verdict gates; shareable as a story, never a score | Phase B / D"

**Rationale:** 02 §8.3, §7 (challenges); SOUL §9 translator "pull not push" and 05 Part C (cooldown); THESIS §7.2 and 04 S14 (Our year).

### 8.10 MASTER_SPEC §11 — new permanent constraints

**Add:**
```
10. NO PARTNER-FACING COUNTS
    No surface, RPC, export or analytics event shows one partner a count,
    ratio, trend or label about the other partner's behaviour or the
    couple's performance. Couple-level totals of a shared pot are permitted;
    per-person totals are not.

11. ENDING NEVER NOTIFIES
    Pausing or ending a relationship sends no push, SMS or email to the
    other partner. Discovery is in-app, on next open, with warm fixed copy.

12. SHARED VISIBILITY IS SYMMETRIC, OFF BY DEFAULT, AND REVOCABLE SILENTLY
    Read receipts, seen-state, presence and availability are off until
    both enable them; either can turn them off alone and silently; turning
    them on again requires both.

13. SPECIAL-CATEGORY PREFERENCES ARE NEVER INFERRED
    Faith, sexual-content comfort, health context and access needs are set
    only by the user, stored under auth.uid()-only RLS, never sent to an
    AI prompt without the user's own request carrying them, and never
    rendered on a widget, lock screen, calendar mirror or notification.

14. WRITER-FACING DISCLOSURE ROUTING IS DETERMINISTIC AND PROVIDER-SUPPRESSING
    A disclosure of victimisation or self-harm by the writer skips every
    AI call for that text, shows the writer resources, persists nothing,
    and tells the partner nothing.

15. THE COUPLE PROFILE PRODUCES NO TYPE
    Stage, distance, household and preferences tune content. They never
    generate a couple type, score, label or compatibility statement.
```
**Rationale:** 05 P0-1, P0-5, P0-7; 02 §13.3; 04 §A gaps 1–2; §5 above. Constraint 6's "never routes through Claude or any other AI model" should read "any AI model" (the provider is Gemini, 03 caveats).

### 8.11 MASTER_SPEC §2 and Decision 13/3/19 — profile not types; preview; ending

**Decision 13 current:** "Compatibility preview day one, profile-based with explicit labelling, 48hr content plan"

**Replacement:** "Ask-2 reward is a non-typing preview: the two anchors reflected back plus 'something for tonight'. No pairing, type or compatibility statement from any quiz. (Revised 2026-10: 04 S4, 02 §2.3.)"

**Decision 3 current:** "Either user can unlink, 30-day soft delete, both revert to Personal mode" and **Decision 19 current:** "Read-only after relationship ends. Permanently archived when either partner starts new relationship"

**Replacement (one reconciled decision):** "Either partner can pause or end alone, instantly, with no notification to the other. Ended → 30-day read-only window per person with export → archived (or immediately when either starts a new relationship, or by 'seal my side now'). Archived media and messages hard-deleted at 12 months unless legal hold. Both re-inviting within 90 days with no new relationship reopens the same space."

**§2 add:** "Couple shape is a profile on the relationship (stage, distance, intent, household) plus per-partner preferences — not a mode and not a type. Modes remain personal / couplesPending / couples."

**Rationale:** the code archives instantly (05 preamble); THESIS §3.1 and PRINCIPLES §J disagree today (03 §4.1); 05 Part D; the owner's "four couple types" memory has no schema and would be a typology (03 §2.2).

### 8.12 THESIS §1 and §3.3 — substrate and quizzes

**§1 current:** "Attune's bet is that the raw material for relationship self-knowledge already exists — it's the couple's own conversation…"

**Replacement:** "…it's the couple's own conversation, and the life they plan, remember and share around it. The chat is the substrate for patterns; the journal is the substrate for care made visible. Both are turned into honest, specific, non-judgmental insight at consumer prices — and into easy ways to be responsive to each other, which the evidence says matters more than insight alone."

**§3.3 current:** "Quizzes — four self-knowledge instruments (attachment, love languages, communication style, conflict style), each honestly graded by its own evidence quality. Attachment is the anchor… love languages is explicitly the weakest tier and is banned from ever being used to score compatibility…"

**Replacement:** "Quizzes and preferences — attachment (dimensional, self-facing, caveated), communication style and conflict style, each graded by its own evidence quality; and 'What feels loving to me right now', a changeable preference card that replaces the love-languages typology because the matching idea does not hold (Impett, Park & Muise 2024). Nothing here ever produces a pairing or compatibility statement."

**Rationale:** 02 §0.3 #1, §7; §1.4 theory of change.

### 8.13 Explicit stances (for the record, in one place)

| Topic | Stance | Source |
|---|---|---|
| Love languages | Use the responsiveness framing ("what feels loving to me right now", current, changeable, multi-select). No typology, no primary language, no matching, labelled as a popular framework. | 02 §7, (b); 8.7 |
| Gottman ratios | 5:1 is a heuristic about conflict tone. No ratio is ever computed, displayed or targeted. | 02 §1.1, §1.4, (b); 8.3 |
| Sexual frequency | No prescriptions, trackers, targets, logs or "once a week" goals. Communication, responsive-desire education and mutual-match lists only. | 02 §8.1–8.3 [RCT]; 8.4, 8.9 |
| Attachment labels | Self-only, dimensional, caveated; never applied to the partner or the pairing; the pairing card is removed. | 02 §2.3, (b); 8.7, 8.11 |
| Faith | Opt-in per partner, tradition-respecting, never default, never inferred, never in safety/Healing/ending flows, secular equivalents for everyone. | 02 §11; 8.4, §5, §6.2 |
| Couple-type configuration | A profile of fields, not types or modes; never produces a type, score or compatibility statement. | §5; 8.10 #15; 8.11 |
| Divorce prediction | Never, in any form. | 02 §1.2, §1.4 |
| Comparison to other couples | Never, named or anonymous. | 02 C6 #2; 8.5 |

---

## 9. What NOT to build (and why)

| Do not build | Why | Sources |
|---|---|---|
| Any partner-facing count, ratio, trend comparison or "growth area" label | Becomes a weapon in every archetype that could benefit from a number; scorekeeping predicts dissatisfaction | 04 §E; 02 C6 #1–2; 01 §3.3 #12 |
| Automatic conflict detection banners ("live cooldown") | Push not pull; misfires; a user-initiated pause chip gets the value with none of the risk | SOUL §9 translator; 05 Part C; 04 §E; SPEC §14 line to delete |
| "Remind my partner" buttons | Love Nudge's "ding reminding your partner to come give you a hug"; intrusive support backfires; reminders controlled by the other partner become monitoring | 01 §2.2, §3.2 #19; 02 §14.3 Feeney; 02 §12.7 |
| Streaks, even forgiving ones; paid streak repair; lock-screen timers | Soul rule; bug/time-zone loss is a reliable 1★; the dormant counter must be deleted | SOUL §5 P1, §8; 01 §3.2 #13, §5 item 6; 04 S1 |
| Sex frequency trackers, "mood tonight" timing windows, intimacy challenges, love-language-personalised anything | Assigned frequency lowered happiness; LoveSync's windows produced "confusion and resentment"; love-language matching is unsupported | 02 §8.1–8.3, §7; 01 §2.3; 05 S12 |
| Precise location, battery, last-seen, typing indicators, "online now" | Coercive-control vectors; Love8/Widgetable bait; anxiety in LDRs | 02 §9.3, §10.3, §13.3 #2; 01 §2.5, §2.7 |
| Bank sync for money | Honeydue's 234 sync complaints; lagging data "starts fights" | 01 §2.6; 04 S13 |
| A companion-style AI, a chat-with-Attune surface, AI role-play of the partner | Decision 28; companion-chatbot regulation; the wrong act in crisis | SPEC Decision 28; RISK_SOLUTIONS §7.5; 05 S5; 02 C2 |
| AI-written affection, apologies or enthusiasm auto-sent in a user's name | Inauthentic responsiveness corrodes trust when discovered | 02 §6.2 avoid, C6 #8 |
| A couple report, a shared "cycle" diagram filled in by the AI, horsemen labels from text | Permanent constraint; iatrogenic; error-prone classification | SPEC §11 #2; 02 §1.4; 05 Part C "name the cycle" |
| Divorce or breakup prediction, relationship scores with percentiles, compatibility percentages | In-sample accuracy collapses on cross-validation; individual prediction is weak; invites comparison | 02 §1.2 Heyman & Slep, (b) |
| Faith, sex or health content by default or inferred from anything | Hard churn both ways; special-category data | 04 S7, §C; 02 C5, §11.3 |
| Multi-person / polyamory mode (for now) | Real request (36 snippets) but it multiplies every symmetric-consent and safety rule; do not exclude anyone at signup (no gender fields) and say so publicly | 01 §3.3 #17; 03 §2.2 |
| In-app video calling | Request #9, but a template ritual plus the couple's existing call app gives the co-presence value without a media stack and its moderation burden | 01 §3.3 #9; 02 §9.2 |
| Hardware, pets, gamified widgets, ads inside intimate surfaces | Subscription-on-hardware and ad resentment; "pets leave you when neglected" is a guilt mechanic | 01 §2.5, §3.2 #5, #21 |
| A cold ending email or push | Between's "CANCELED" email; separation lethality window | 01 §2.4; 02 §13.1; 05 P0-1 |
| Onboarding that asks "what do you want to work on" | "This app thinks every couple has issues" | 01 §2.1 Flamme; 04 §C |
| A single shared "Emotional safety" score | Meaningless to the safe partner, dangerous to the unsafe one | 05 S3, P0-6 |
| Forgiveness prompts, "accept apology" buttons, forgiveness status | Doormat effect; pressure to forgive without amends | 02 §6.8 Luchies; 05 Part C |
| Evidence logs: who did chores, who apologised, exportable audits, per-person expense filters | Shared features must not become evidence against a partner | 02 §13.3 #9; 05 S10, S13 |

---

## 10. Open questions only the owner can decide

> **Owner decision (2026-10-16): all 18 recommendations accepted as written.** The §8 amendments are applied to ATTUNE_SOUL.md (v2.1 log), ATTUNE_MASTER_SPEC.md (§1, §2, §8.2, §8.3, §11 constraints 10–15, §14, decisions 30–33) and ATTUNE_THESIS.md (§1, §3.3).

| # | Question | Recommendation | Why |
|---|---|---|---|
| Q1 | Is sexual intimacy in scope at all? | **Yes, narrowly, in Phase C**, clinician- and sex-therapist-authored, triple-gated, no frequency anything. Until then, keep the absence (it is protective). | 04 S9; 05 S12; 02 §8; 01 §2.3 both-sided demand |
| Q2 | Read receipts: default on (05) or default off for new couples (04)? | **Default off; either can turn off; both to turn on.** | Coercion cannot re-enable alone (05 S3); LDR/anxious harm (04 S1, S4); 02 §9.3 |
| Q3 | Route the Verdict now, or hold? | **Hold.** Rename "Monthly readout"; make the quarterly check-up (B4) the primary artefact; the readout becomes its optional AI appendix after the §14.2 gates and F15. | 03 §4.1; 05 S1, S6; 04 S14 |
| Q4 | May a Budget block show a couple total of the shared pot per period (D6 interpretation)? | **Yes.** One number for both; never per partner; copy says so. | 04 S13 b; Planning D6 intent is no scoreboard, which a couple total is not |
| Q5 | "All four couple types at launch" — types or profile fields? | **Profile fields (§5), no types.** | 03 §2.2; §8.11; typologies become labels |
| Q6 | Which faith traditions at Ghana launch? | **Christian (Protestant/Pentecostal + Catholic variants) and Muslim; Jewish for diaspora; "other" as free-text ritual only.** Secular default always. | 01 §2.8 gaps; THESIS §5 |
| Q7 | Weekly Pulse vs quarterly check-up as the primary attunement loop? | **Quarterly check-up primary; weekly check-in optional and private.** Pulse chat-aggregate dimensions resume after F15 as a tool under Chat, never the home. | 02 §6.11 [RCT]; 04 S3, S14; 05 S1 |
| Q8 | Monetisation tier structure | **One couples plan (monthly + annual + lifetime), free core as in §7 #2, premium = packs/depth/permanence; Personal-mode plan cheaper; B2B2C later.** Price after measuring cost per couple. | 01 §6; THESIS §7.3; Decision 1 |
| Q9 | Does the export include raw chat text? | **Yes.** Both already hold it; excluding it punishes the person who lost the phone. Exclude AI-derived partner data, safety data, translator originals. | 05 D.3 #6 |
| Q10 | Archive retention: hard-delete at 12 months after archive? | **Yes**, told at ending, after the 30-day export window; legal hold excepted. | 05 S14 d.4; 01 §5 item 2 |
| Q11 | Mirror attentiveness flag | **Remove.** | 04 S3; 03 §4.1 |
| Q12 | Polyamory / multi-person support | **Not now; publicly honest about it; no gender or structure fields that force a lie.** | 01 §3.3 #17; 01 §5 item 7 |
| Q13 | In-app video calling | **No.** Co-presence ritual templates instead. | 01 §3.3 #9; 02 §9.2 |
| Q14 | Home for low-literacy couples: new tab or card? | **"Plans" card first under Chat; keep the two-tab shell.** | 04 S10; Decision 11 |
| Q15 | Advisory board | **Form it now, batched:** couples clinician, DV specialist, suicide-prevention reviewer, sex therapist, Ghanaian cultural reviewer, one faith reviewer per launch tradition, a DV-experienced lawyer. | THESIS §6.9; 02 C7; SPEC §12 |
| Q16 | Historical WhatsApp import flag | **Not before Phase B is stable and F15 has run for a quarter.** | THESIS §6.2; SPEC §16 |
| Q17 | Co-parenting surface | **Commit to D2 in principle now**, because F1's data model must reserve it ("Keep the family calendar"). Build after C4. | 05 S6; 02 §15 |
| Q18 | Should the outcome panel (§4.0) exist at all, given the no-surveillance stance? | **Yes, opt-in, aggregate-only, self-facing, deletable.** Without it the product cannot know if it helps. | 02 C7; SOUL §5 P1 "measure what is real" |

---

## 11. The 90-day execution plan

Eight specs, in order, each ready for the writing-plans skill. The first four are non-negotiable before any real couple is onboarded; five to eight may slip without breaking the floor. Authorship engagements (DV, clinical, suicide-prevention, cultural) start on day 1 because Specs 4, 6 and 8 depend on them. Effort is for a solo founder with AI collaborators.

| # | Spec | Weeks | Contents | Floor items | Done when |
|---|---|---|---|---|---|
| **1** | **Safe defaults and quiet surfaces** | 1–2 | Symmetric read-ticks/seen-state setting, default off for new couples, both to enable (server-enforced); engine-level quiet hours (defer, never drop); delete the dormant chat streak (flag, migration, provider, CI grep gate); Pulse inference rule, Emotional safety self-facing, no on-demand refresh of check-in dimensions, Pulse hidden while paused; discreet surface titles off by default; Mirror flag removed. | F4, F5, F6, F8 (titles) | Tests: `read_at` unreadable while off; quiet-hour deferral; no `streak` symbol in chat; shared dims hold with one check-in. |
| **2** | **Quick exit, Safety PIN, account security, neutral icon** | 2–4 | Root-shell triple-tap over GoRouter; Android `finishAndRemoveTask`; PIN gate on cold start and resume with keystore KDF, delay on failure, sign-out recovery; "Where you're signed in", sign out others, in-app new-device notice, no partner-assisted recovery; iOS alternate icon + Android alias with neutral name; sender-name audit. | F2, F3, F7, F8 (icon) | Real-device matrix (3 Android OEMs, 2 iOS); widget test asserting route coverage; session revocation test. |
| **3** | **Ending v2: states, no-push, read-only window, export, chapter scoping, provable deletion** | 3–6 | `paused` RPC and UI; `end_relationship()` without notification work and without instant archive; 30-day read-only per person; "seal my side now"; archive on new relationship; warm discovery screen; `export` Edge Function (JSON + media per 05 D.2, exclusions enforced); resurfacing stops at `ended`; `relationship_id` on personal insights, translator logs, Love map and game answers; hard-delete account path; 12-month archive deletion job; Healing Stage 2 snapshot at `ended`. | F1, F13 | Integration test: zero outbox rows for the other member; CI RLS canary (two former partners + one new partner); delete-then-reregister test; export round-trip. |
| **4** | **Support resources v2, crisis catalogue, writer-facing disclosure routing, lexicon** | 4–8 (authorship from week 1) | Versioned resource model with country routing, nine categories, verification dates that block release, tap-to-call confirmation, offline cache, removal of prohibited copy; `self_disclosure` corpus with victimisation/sexual-assault/self-harm families, wired before every provider call on journal, chat (sender), Sessions/Understand/Assist, truth answers, Healing; writer card and recipient supporter card (clinician-reviewed); journal lock; resources entry on journal/Healing; normaliser zero-width fix; DV-reviewed lexicon with Tier 2 monitoring/outing/financial families; golden fixtures and mutation review. | F10, F11, F12 | Test proves matched text never reaches `gemini_json.ts`; fixtures pass; every launch-country number `verified_at` within 7 days; no detector path imports an AI SDK. |
| **5** | **Unlock what is built, safely** | 6–8 | Replace the attachment pairing card with the non-typing Ask-2 reward; attachment caveat; route "What feels loving to me right now" (rebuilt from the love-languages quiz) and the communication/conflict quizzes behind the clinical gate with "where you differ" copy; 48-h gate, keep-private/share prompt, day-7 pivot; schedule the Sunday check-in reminder; ship Map/widget `db push` + device checks, Stories realtime, Together device surfaces (after Spec 1 titles); accessibility gate on the three tabs (Dynamic Type, 44 dp, contrast, labels, reduced motion); doc amendments §8 applied as the owner accepts them. | F9, F16, A1–A3, A6–A7, A10 | No pairing string anywhere (grep gate); a11y audit checklist green; device checks recorded. |
| **6** | **Couple profile v1 + private safety check + faith/sex gate lint** | 7–10 | Shared fields (stage, distance + end date, intent, household); per-partner special-category table under `auth.uid()` RLS (faith, sexual content, health context, access needs, topic exclusions, quiet state, prompt pace, location-sensitive, communication preferences); gates per §5.2; distance-end retirement proposal; Settings → Us UI; HARK-adapted 4-item private safety check at Ask-2 and quarterly, own table, invisible one-directional flag with 180-day expiry; lint test rendering every surface for `none/off` and asserting zero tagged strings; topic exclusions applied to all prompt banks; community prompt block list + report button; Opinions tag mute. | F14, F17, B0, B13 | RLS tests; lint green; no AI prompt includes profile fields (prompt-builder test); no analytics on special-category values. |
| **7** | **Positive-affect pair** | 9–11 | "I noticed…" note as a chat message subtype with leaf motif, optional faith-on phrasing, private appreciation jar (received notes, no counts); "Share a win" posting a highlight and an in-app ask-about-it card via the care-card machinery (never a push, no AI text); celebration-suppression hook honoured by Progress celebration and shimmer; quiet states "Having a hard time" / "Going through a loss" with the once-only fixed line; support-request chips; "Put this away gently"; "Hide a period". | B1, B2, B9, A9 | No counter or history view exists (code review); card never pushes; quiet state silences every celebratory surface (test). |
| **8** | **Conflict toolkit v1 + AI gates, then resume** | 10–13 | Pause chip with three fixed messages, sender-only timer and self-soothing card, partner's single fixed reply; repair tray (six phrases, localised); "Help me apologise" four-field scaffold (never a forgiveness request, no recipient control); "Help me start this conversation" scaffold with the seven-need taxonomy (communal obligation added); plain register; all hidden under a positive safety check; Understand/Assist deterministic pre-check with the do-not-interpret family; Understand footer + "a trained outside perspective" handoff card; third-party attribution ban in prohibited patterns; translator boundary-statement evals; abuse-context suppression flag, co-framing line, adversarial Verdict suite → **only then** enable `…_resume_ai_jobs.sql` for Layer 1/2, Pulse chat dimensions and Love map refresh (Verdict cron stays off); flip `ai_together_enabled` after the RPC smoke test. | F15, B3, B10, A4, A5, A8 | No count, Pulse input or partner-visible state from any tool (tests); pre-check runs before every provider call; suite passes; cost-per-couple dashboard live before resumption. |

**After day 90** (Phase B continues): Spec 9 quarterly strengths-first check-up (B4); Spec 10 conversation-pack engine + Living together / Coming home / Our families / First year / Money values / Gridlock (B5); Spec 11 recurrence + Household + self-set reminders (B6) and family relation types (B7); Spec 12 Our plan / tentative reunion / sensitive location + presence honesty copy (B8, B12); Spec 13 Our year templated (B11). Phase C begins with the intimacy and faith scope decisions (Q1, Q6) and their authorship.

**Honesty about the plan.** Thirteen weeks is tight for Specs 1–8 with one engineer; Specs 1–4 carry the lethality and trust risk and must not slip. If something slips, it is Specs 7–8, and the AI crons stay paused until Spec 8 lands in full. Nothing in Phase B or C is worth shipping on top of an unfinished floor; the market shows what happens to trust-branded products that ship broken (01 §5 item 9), and the strain scenarios show what happens to people (05 S3–S5).

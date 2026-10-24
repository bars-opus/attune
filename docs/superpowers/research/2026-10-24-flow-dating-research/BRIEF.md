# Flow + Dating research — shared brief (2026-10-24)

## Why this research exists
The owner is restructuring Attune's whole app flow, from store download to first open, sign-in, choosing a path and onboarding. Alongside that, Dating Mode gets built properly and the Forum feature is removed (Opinions stays). The research decides **what to build and how**: every piece of data collected, every step, every flow and every animation. The later steps are scenario simulations, one decision document, then specs.

## Owner decisions already made (binding inputs, 2026-10-24)

**Paths and sign-in**
- After sign-in, "What brings you to Attune?" offers three paths: **In a relationship** / **Single and open to dating** / **Just for me**. "Just for me" covers the reflection journal, quizzes and Healing. Dating can be switched on later.
- Sign-in is by phone code, as today. Apple/Google may be added later, so design for it.
- Guests can read Opinions before signing in.
- **Date of birth for everyone at sign-up.** Attune is 18+. Only age is ever shown, never the date.

**Relationship Mode**
- A **shared couple profile** that either partner can fill in and edit. It holds:
  - when you got together;
  - stage: dating / engaged / married (with year) / other, as the couple describes it;
  - living together, apart or long distance;
  - children.
- **Never a type or a score.** Permanent rule: no couple "type", no partner scorecard.

**Dating Mode**
- Matchmaking for singles, **worldwide** (not Ghana-only).
- A **few curated introductions a day**, double opt-in ("Interested" privately; a match only when both are interested).
- **Who you want to meet:** men / women / everyone. It is never shown on a profile, only mutual matches are introduced, and **country-aware safety notes** cover places where same-gender relationships carry legal or entrapment risk.
- A **separate dating chat** with stronger safety, kept apart from the couples chat. A matched pair who become a couple can link into Relationship Mode.
- A gentle wait (Healing offered, not forced) applies **only** to people whose relationship ended inside Attune. Today the whole Dating Mode is gated behind Healing; that is changing.

**Other**
- **Forums:** remove the screens, jobs and notifications now; drop the tables later. **Opinions stays** (anonymous, judgment-free writing).
- **Do not touch** the in-chat Games feature.
- Fresh start: no real users yet, so test accounts can be reset.

## What already exists
Read only what your area needs:
- **Couples research from 2026-10-16:** `docs/superpowers/research/2026-10-16-couples-research/`. Don't redo it; cite and build on it.
  - `06-synthesis-roadmap.md` is the decision doc: safety floor F1–F17, the couple profile in §5, and §9 "what not to build".
  - `01-market-reviews.md` explains how App Store review corpora were pulled through Apple's public RSS feed. Reddit and Google Play text were not reachable then.
- **Dating:**
  - `lib/architecture/DATING_MODE_SPEC.md` and its review/gate/packet docs in `lib/architecture/DATING_MODE_*.md`;
  - `docs/reviews/DATING_REVIEW_FABLE.md`;
  - the code in `lib/features/dating/**`;
  - the schema in `supabase/migrations/*dating*`.
- **Flow:**
  - `lib/architecture/AUTH_ONBOARDING_ENGINE.md`;
  - `lib/architecture/attune/ATTUNE_MASTER_SPEC.md`, decision log from line ~3045;
  - `lib/features/onboarding/**`, `lib/features/auth/**`, `lib/app/routing/app_router.dart`, `lib/home/home_screen.dart`.
- **Product rules:**
  - `lib/architecture/ATTUNE_SOUL.md` and `ATTUNE_THESIS.md` (read only, never edit);
  - the permanent constraints: no couple report combining both users' insights; asymmetric behaviour data self-facing only; safety notifications to the at-risk user only; the safety system never depends on an LLM; quick exit everywhere.

## Rules (binding for every researcher)
- **Repo access:** READ-ONLY. Never edit, format, stage or commit anything. Write ONLY your own output file in this folder.
- **Agents and models:** do not dispatch subagents, and never use the Fable model.
- **External services:** don't read `.env`, credentials or the keychain. Don't sign up for or log into external services. Don't contact anyone. Public web pages, papers, store listings and public review feeds only.
- **Citations:** every factual claim carries a source (URL, or paper with authors + year + venue). Grade each evidence item: **Strong** (meta-analysis, large RCT, large dataset), **Moderate** (peer-reviewed study, large survey, official policy), **Weak** (single small study, press, vendor claim), **Anecdote** (reviews, forum posts). Say plainly when something is unknown, contested or unreachable.
- **Context:** Attune is worldwide but its first users are in Ghana and the diaspora. Call out where findings differ by culture or region (West Africa, faith communities, LGBTQ+ safety, diaspora).
- **No design by fiat.** End with **Implications for Attune** (concrete, each tied to evidence) and **Open questions for the owner** (each with your recommendation).

## Output format
1. **How this was researched** (sources, method, limits).
2. **Findings**, organised by your area's questions, with evidence grades.
3. **Implications for Attune.** Numbered; each one says what to build, change, avoid or measure, and why.
4. **Open questions for the owner**, each with a recommendation.

Aim for thorough but scannable: tables where they help, no padding.

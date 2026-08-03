# Feature Intro Flow (Dating Mode + Healing Mode) — Design

## Problem

Dating Mode and Healing Mode are both high-stakes, easy-to-misjudge features by Attune's own Soul document standard (`lib/architecture/attune/ATTUNE_SOUL.md`): Healing Mode is entered by someone processing a breakup, and Dating Mode already carries a mandatory standalone data-consent requirement (Soul §9). Neither currently frames itself before the user lands inside it — `DatingDashboardScreen` and `HealingJourneyScreen` both render directly, with existing documentation/FAQ content (`dating_mode_docs.dart`, `healing_docs.dart`) reachable only via an opt-in `IntroGuideWidget` card elsewhere in the app, never surfaced at the point of entry.

Per Soul Document §13 (Video 7, "the app onboarding paradox" — short vs. long onboarding as a *strategic exception*, not a default) and Principle 6 ("design for the hard moment, not the easy one"), a mandatory walkthrough is not appropriate for every feature — but it is justified for these two specifically, where the stakes and Soul's own existing requirements (Dating consent) already call for deliberate framing before action.

## Goal

Build a reusable 3-page intro flow — brief intro → written docs → FAQ → then into the feature — and apply it as the first-time gate for Dating Mode and Healing Mode only. Not a general pattern applied to every feature.

## Non-Goals

- Not a universal `FeatureIntroFlow` rolled out to every major feature. Scope is exactly two features per this request.
- Not a replacement for `DatingConsentScreen`'s existing legal/data consent flow — that screen, its checkboxes, and its position (reached via the dashboard's "Get started"/"Review consent" CTAs) are unchanged. The new intro is purely educational framing that precedes the dashboard; consent remains its own separate, later step.
- Not new FAQ/doc copy — `dating_mode_docs.dart` and `healing_docs.dart` already have real `ManualSection`/`FAQModel` content (registered as `DatingModeDocs`/`HealingDocs` `DocumentationModule`s). The intro flow consumes this content directly; no new copy is authored as part of this feature, beyond a short page-1 "brief intro" blurb per feature (see Content section).
- Not account-level persistence. "Has the user seen this intro" is tracked device-locally via `SharedPreferences`, matching this codebase's existing convention for this exact class of state (`QuizProgressStore`'s `hasSavedProgress`/keyed-prefix pattern). A reinstall or new device re-shows the intro once — an accepted tradeoff, not a gap to fix here.

## User Flow

### Gating (both features)

On attempting to enter either feature (see Entry Points below), a check runs against a new persisted flag. If the intro has not been seen for that specific feature, the 3-page intro is shown first; on completing or explicitly skipping it, the flag is set and the user proceeds into the feature's existing entry point unchanged. If the flag is already set, the intro is skipped entirely and today's behavior (direct navigation) is unchanged.

### The 3 pages

1. **Brief intro** — a short, single-screen framing of what the feature is and isn't, using `module.getTitle(context)`/`getSubtitle(context)`/`icon` from the existing `DatingModeDocs`/`HealingDocs` modules plus one short additional paragraph per feature (see Content below). A single "Continue" action advances to page 2. A visible "Skip" affordance is available on every page (see Skippability below).
2. **Documentation** — renders `module.getSections(context)` via the existing `ManualWidget` (`lib/app/documentations/user_manual/widgets/manual_widget.dart`), full-page rather than inside a bottom sheet. "Continue" advances to page 3; "Back" returns to page 1.
3. **FAQ** — renders `module.getFAQs(context)` via the existing `FAQWidget` (`lib/app/documentations/user_manual/widgets/faq_widget.dart`), full-page. A final CTA ("Get started" / "Enter Healing Mode", feature-specific label) marks the intro seen and proceeds into the feature. "Back" returns to page 2.

Pages 2 and 3 deliberately reuse `ManualWidget`/`FAQWidget` directly (the same widgets `DocumentationTabView` composes into tabs) rather than reusing `DocumentationTabView` itself, since the user asked for three distinct sequential pages, not two tabs — `DocumentationTabView`'s tabbed collapsing of docs+FAQ into one screen doesn't match "3 pages" literally.

### Skippability

A "Skip intro" text action is present on all 3 pages, positioned consistently (e.g. top-right of the page indicator), which marks the flag seen and proceeds directly into the feature without requiring the user to page through content they don't want. This keeps the flow aligned with Soul Principle 5 (respect autonomy absolutely) and Principle 6 — the intro informs, it does not trap. A user in an urgent state (e.g. needing Healing Mode's safety-adjacent framing right now) is never forced through 3 screens before reaching help.

## Components

### `SeenFeatureIntroStore` (new)

New file: `lib/core/intro/data/seen_feature_intro_store.dart`. Mirrors `QuizProgressStore`'s exact shape (`lib/features/quiz/data/local/quiz_progress_store.dart:1-65`) — a thin `SharedPreferences`-backed class with a keyed prefix:

```dart
class SeenFeatureIntroStore {
  SeenFeatureIntroStore(this._prefs);
  final SharedPreferences _prefs;
  static const _keyPrefix = 'seen_feature_intro_';

  bool hasSeenIntro(String featureId) {
    return _prefs.getBool('$_keyPrefix$featureId') ?? false;
  }

  Future<void> markIntroSeen(String featureId) async {
    await _prefs.setBool('$_keyPrefix$featureId', true);
  }
}
```

`featureId` values are the same `id` strings the `DocumentationModule`s already use — confirmed `DatingModeDocs.id => 'datingMode'` (`dating_mode_docs.dart:17`) and `HealingDocs.id => 'healing'` (`healing_docs.dart:20`) — so no new id vocabulary is introduced.

### `SeenFeatureIntroStore` construction (no new Riverpod provider)

Checked at implementation-planning time: `QuizProgressStore`, the direct precedent this class mirrors, has **no** Riverpod provider anywhere in the codebase (confirmed via grep — zero matches for any `Provider` wrapping it). It's constructed ad hoc via `final prefs = await SharedPreferences.getInstance(); _progressStore = QuizProgressStore(prefs);` inside an async init method on the consuming `State` (`attachment_quiz_screen.dart:61-64`). `SeenFeatureIntroStore` follows the same construction call, not a provider — this spec's earlier draft assumed a provider existed for this pattern; it doesn't, and introducing one here would be inventing a new convention rather than matching the real one.

Because the gate check happens at route-build time (see Entry Point Wiring) rather than inside a widget with a natural async `initState`, the wrapper widget described below owns its own async load of the `SharedPreferences` instance and `SeenFeatureIntroStore`, the same way `attachment_quiz_screen.dart` does it locally — not a shared/global provider.

### `FeatureIntroFlowGate` (new, shared route wrapper)

New file: `lib/core/intro/presentation/widgets/feature_intro_flow_gate.dart`. A `StatefulWidget` taking `DocumentationModule module`, `Widget Function() buildFeature` (builds the real destination screen once gated past), used directly as a `GoRoute` builder's return value. On `initState`, kicks off `SharedPreferences.getInstance()` → `SeenFeatureIntroStore(prefs).hasSeenIntro(module.id)`, matching `attachment_quiz_screen.dart`'s async-init-method pattern exactly. While loading, renders a minimal loading state (a bare `Scaffold` with a centered `CircularProgressIndicator`, matching this codebase's existing async-gate convention elsewhere, e.g. `HealingJourneyScreen`'s own `loading: () => const Center(child: CircularProgressIndicator())`). Once resolved: if seen, calls `buildFeature()` directly (via `setState`, no navigation push — so the back stack does not grow by an extra entry); if unseen, renders `FeatureIntroFlowScreen(module: module, onComplete: () { store.markIntroSeen(module.id); setState(() => _seen = true); })`, and on `onComplete` swaps in-place to `buildFeature()` the same way, still with no extra back-stack entry.

### `FeatureIntroFlowScreen` (new, shared)

New file: `lib/core/intro/presentation/screens/feature_intro_flow_screen.dart`. Takes a `DocumentationModule module` and a `VoidCallback onComplete` (called on both final-page completion and "Skip" — this widget does not touch `SeenFeatureIntroStore` itself; `FeatureIntroFlowGate` owns marking the flag seen, keeping this screen a pure presentation component with no persistence dependency). Internally a `PageView` (non-swipeable — advanced only by the Continue/Back buttons, matching this codebase's existing quiz-flow navigation convention rather than allowing free swiping past content) with 3 children:
- Page 1: new lightweight widget rendering `module.icon`/`getTitle`/`getSubtitle` plus the feature-specific brief paragraph (see Content).
- Page 2: `ManualWidget(sections: module.getSections(context))`.
- Page 3: `FAQWidget(faqs: module.getFAQs(context))`.

A page-index-driven bottom bar renders Back/Continue (page 1 has no Back; page 3's Continue reads as the feature-specific launch label instead of "Continue"). "Skip intro" appears in the app bar on all 3 pages. Both the final CTA and Skip call `onComplete`.

### Content (new copy, minimal)

Two short paragraphs, one per feature, for page 1 only — everything else reuses existing doc/FAQ copy:

- **Dating Mode**: framing that Dating Mode is separate from Healing Mode, requires its own consent step next, and is never automatic — matching the tone already established in `dating_dashboard_screen.dart:196` ("Dating Mode stays separate from Healing...").
- **Healing Mode**: framing that this is private, self-paced, and not therapy — matching `healing_docs.dart`'s own `healing_purpose`/`healing_not_therapy` manual content tone, so the new paragraph doesn't contradict or duplicate the docs page that follows it.

Exact copy is written at implementation time following these tonal anchors and Soul §10's voice rules (honest, specific, warm, respectful, grounded) — not fully specified here since it's presentation copy, not a structural decision.

## Entry Point Wiring

### Dating Mode

`DatingDashboardScreen` (`lib/features/dating/presentation/screens/dating_dashboard_screen.dart:10-25`) is reached via `RouteNames.datingMode` (`app_router.dart:188`, `:1266-1268`). Change that route's builder from `(context, state) => const DatingDashboardScreen()` to `(context, state) => FeatureIntroFlowGate(module: DatingModeDocs(), buildFeature: () => const DatingDashboardScreen())`. `DatingConsentScreen` and its 3 existing `pushNamed('datingConsent')` call sites (`dating_dashboard_screen.dart:159, 202, 585`) are completely unchanged — they fire from within the dashboard exactly as today, after the intro has already been dismissed once.

### Healing Mode

Two existing entry points both need the same gate:
- `EndRelationshipAction.confirmAndEnd` (`end_relationship_action.dart:47`), which currently does `context.push(RouteNames.healingJourney)` directly.
- `ChatCouplesLockedScreen._onHealingEntryTap` (`chat_couples_locked_screen.dart:131-149`), which pushes `RouteNames.healingJourney` either directly (existing solo journey) or after `HealingSelfReportSheet` completes.

Rather than duplicating the gate check at both call sites, insert it at the route itself, the same way as Dating Mode's: change `RouteNames.healingJourney`'s builder from `(context, state) => const HealingJourneyScreen()` to `(context, state) => FeatureIntroFlowGate(module: HealingDocs(), buildFeature: () => const HealingJourneyScreen())`. This means both call sites' existing `context.push(RouteNames.healingJourney)` calls need zero changes — the gating is centralized at the destination, not duplicated at each origin.

**Important distinction from the existing solo-journey check**: `ChatCouplesLockedScreen._onHealingEntryTap` already has its own pre-navigation logic (checking `hasActiveSoloHealingJourneyProvider` to decide direct-navigate vs. self-report-sheet-first). That logic is unrelated to and unaffected by this change — it decides *what* happens before reaching `RouteNames.healingJourney`; this feature decides what renders *at* that route the first time. The two compose without conflict: a first-time solo-journey user still sees `HealingSelfReportSheet` first (existing behavior), then on completion still lands at `RouteNames.healingJourney`, which — if this is their first time — now shows the intro before `HealingJourneyScreen`.

## Testing

- Unit tests for `SeenFeatureIntroStore`: `hasSeenIntro` returns `false` before any `markIntroSeen` call, `true` after, independently keyed per `featureId` (marking `'dating'` seen doesn't affect `'healing'`'s flag).
- Widget test for `FeatureIntroFlowScreen`: renders page 1 initially; Continue advances through all 3 pages in order; Back from page 2/3 returns to the previous page; page 1 has no Back control; Skip on any page calls `onComplete`; completing page 3's final CTA calls `onComplete`. This screen has no `SeenFeatureIntroStore` dependency to test — `onComplete` firing is the full contract.
- Widget test for `FeatureIntroFlowGate`: with a fake/overridden `SeenFeatureIntroStore` reporting unseen, renders `FeatureIntroFlowScreen`, not the result of `buildFeature`; with it reporting seen, renders `buildFeature()`'s result directly; triggering `FeatureIntroFlowScreen`'s `onComplete` calls `markIntroSeen` and swaps to `buildFeature()`'s result. One test instance per feature (Dating, Healing) confirming each is wired with its own `module`/`buildFeature`.
- No test coverage needed for `DatingConsentScreen` itself — explicitly unchanged.

## Open Questions Resolved During Brainstorming

- **Gating persistence**: first-time-only, persisted device-locally via `SharedPreferences`, matching `QuizProgressStore`'s established convention — not shown on every entry, not un-persisted.
- **Relationship to `DatingConsentScreen`**: the new intro sits before the dashboard; the existing consent screen is entirely unchanged and remains a separate, later, still-mandatory step.

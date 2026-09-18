# AI Assistant — Plan B: Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Flutter client for the AI Assistant — the app-switcher
privacy cover Understand mode depends on (does not exist anywhere in this
app today), a repository over Plan A's two edge functions, the long-press
"Ask Attune" entry point, the Assist mode sheet (Ideas/Nearby, preview,
Share/Edit-as-mine/Close), the Understand mode sheet (private, ephemeral,
no share path), the Attune Assist chat bubble with its "Add to Planning"
affordance, and the immutable/deletable-but-not-editable message-action
split — so both partners can actually use every capability Plan A shipped.

**Architecture:** `lib/features/ai_assistant/` follows the existing
`data/{models,repositories}` + `presentation/{providers,screens,widgets}`
layout `lib/features/planning/` already uses. A new
`lib/core/services/app_privacy_cover.dart` + `_AppPrivacyCoverState`
wraps `MaterialApp.router`'s own `builder` callback in `lib/app/app.dart`
(the same seam this app already uses for `MediaQuery.withClampedTextScaling`)
with an `AppLifecycleListener`-driven opaque cover, following the exact
`AppLifecycleListener` import/usage pattern `story_providers.dart` and
`planning_providers.dart` already established (import from
`flutter/widgets.dart`, not `foundation.dart`). Assist and Understand each
get their own sealed result type, their own Riverpod provider, and their
own sheet widget — never a shared `AiAssistantResult` (spec §2's explicit
prohibition).

**Tech Stack:** Flutter, Riverpod (`AsyncNotifierProvider`,
`StateNotifierProvider.family`), `http`/Supabase Dart client's function
invocation for calling the two edge functions, `geolocator` (already a
dependency), `go_router`.

**Depends on:** Plan A must be merged and its migrations/edge functions
applied to the local test environment before Task 2 of this plan begins —
every RPC/endpoint name and response shape this plan calls is defined
there. Task 1 (the privacy cover) has no backend dependency and may be
built first regardless of Plan A's status.

**Spec:** `docs/superpowers/specs/2026-09-15-ai-assistant-design.md` (this
plan implements its client-facing halves of §1-§3 (entry/eligibility),
§5.2-§5.3 (Assist location flow, preview/share/edit UI), §6.2-§6.3
(Understand's response rendering and hard non-persistence boundary), §11
(error/retry/lifecycle rendering), and §14.1 gate 4 (the privacy cover
itself) — everything except the server-side halves Plan A already built,
and except §13.2's human-reviewed eval gates, which are release gates, not
client code). Also read `lib/architecture/PLANNING.md` §5-§7 (Surfaces,
client architecture) for the closest existing analog of this plan's
repository/provider/screen layering, and
`lib/features/chat/presentation/widgets/message_bubble.dart` lines ~570-960
for the real, working `onInfo`/`_buildInfoOpener`/`_openMessageInfo`
wiring this plan's own `onAskAttune` entry point copies the shape of.

## Global Constraints

These bind every task below. Copied/derived verbatim from the spec; do not
relax any of them without stopping and asking.

- **No shared `AiAssistantResult` type, ever.** Assist uses `AssistDraft`
  (or equivalent sealed name), Understand uses `UnderstandResult`, each
  with its own Riverpod provider and its own widget. Neither exposes
  `share()`, `copyToComposer()`, or `createPlanningItem()` on the other's
  type — there is no generic interface either could accidentally satisfy.
  (Spec §2)
- **Understand mode cannot ship without the app-switcher privacy cover
  being real-device verified.** Task 1 of this plan builds that cover;
  every later Understand-mode task must build on top of it, and no task
  may mark Understand's client work "done" while treating the cover as
  optional or stubbed. (Spec §6.3, §14.1 gate 4)
- **The Understand result lives in an `.autoDispose` provider owned by
  the sheet**, cleared on dismiss/background/auth-or-relationship-change/
  late-response, never written to Drift, `SharedPreferences`, secure
  storage, state restoration, Sentry breadcrumbs, analytics, clipboard,
  notification previews, or debug logs. (Spec §6.3)
- **Location for Nearby uses a NEW raw-position method, never
  `LocationService.getCurrentLocation()`.** That existing method
  internally calls `getCurrentLocationWithDetails()`, which
  reverse-geocodes and contacts an additional platform provider — using
  it here would violate the spec's explicit "your coordinates will not be
  sent to Gemini" promise's supporting infrastructure, since it does more
  network work than Nearby needs or discloses. (Spec §5.2, confirmed by
  reading `lib/core/services/location_service.dart` directly: line 360's
  `getCurrentLocation()` calls line 362's
  `getCurrentLocationWithDetails()` internally)
- **Assist's preview never auto-posts.** Share/Edit-as-mine/Close are
  three distinct, explicit user actions. A successful generation always
  lands in a private preview first, with no code path that skips the
  preview and posts directly. (Spec §5.3)
- **The Attune Assist bubble's label, sources, and proposal use
  `message_origin`/`assistant_payload` — never content-string matching or
  `is_system_notice`.** A message is an Attune suggestion because the
  server said so via `message_origin`, not because its text happens to
  look like one. (Spec §5.3)
- **`Message.canEditOrDelete` splits into `canEdit`/`canDelete`.** This is
  a real, current single-method API (confirmed:
  `lib/features/chat/domain/entities/message.dart` line 455) that every
  existing caller (`message_actions_sheet.dart` and others) uses today —
  splitting it is a breaking change to an existing shared method, not a
  new addition, and every existing call site must be updated to call the
  correct one of the two new methods, not silently left calling a method
  that no longer exists. (Spec §5.3)
- **No push notifications from this feature.** Do not add any OneSignal
  category or `scheduled_notifications` row for anything this plan
  builds. (Implied by spec §1's "never schedules work" and matching
  Planning's own identical constraint.)
- **Every edge-function error is mapped to a typed failure the UI acts
  on**, never a raw HTTP/JSON error surfaced as string text. Follow
  `PlanningRepository`/`PlanningError`'s established sealed-error pattern
  (`lib/features/planning/data/repositories/planning_error.dart`) for the
  shape, but this feature's error codes are the spec's own
  `AssistantErrorCode` enum (§11) — do not reuse `PlanningError`'s actual
  cases, they mean different things here.
- **No test may pass vacuously.** Every widget/provider test added by
  this plan must be mutation-tested: break the behavior it claims to
  protect, confirm the test fails, then restore. This exact codebase has
  shipped a vacuous wiring test before (a bare substring check that also
  matched a class's own constructor declaration, found and fixed during
  Planning's client work) — do not repeat that mistake; if a test checks
  "is this widget in the render tree," make sure the check cannot also be
  satisfied by the widget merely existing as a class in the same file.
- **Per-file test runs are not sufficient evidence of a passing suite.**
  Run the full commands each task specifies.
- **Follow this project's per-feature relationship-id convention.**
  `currentRelationshipIdProvider` is redefined independently inside each
  feature's own provider file (`reminders_providers.dart`,
  `timeline_providers.dart`, `planning_providers.dart` all do this
  independently) rather than imported across feature boundaries — this
  plan's own provider file follows the same convention.

---

## Task 1: The app-switcher privacy cover

**Files:**
- Create: `lib/core/services/app_privacy_cover.dart`
- Modify: `lib/app/app.dart`
- Test: `test/core/services/app_privacy_cover_test.dart`

**Interfaces:**
- Produces: `AppPrivacyCover` — a widget that wraps a `child` and shows an
  opaque, neutral cover whenever the app's `AppLifecycleState` is
  `inactive`, `paused`, or `hidden`, clearing it on `resumed`.
  `AppPrivacyCover.isCurrentlyObscured` (a `ValueListenable<bool>` or
  equivalent inspectable state) so later tasks/tests can assert the cover
  is active without needing to simulate a real OS-level screenshot.
  `lib/app/app.dart`'s `MaterialApp.router` `builder` callback wraps its
  existing `MediaQuery.withClampedTextScaling` child in
  `AppPrivacyCover(child: ...)`. Every later task in this plan that gates
  Understand mode on "the privacy cover is verified" checks
  `AppPrivacyCover.isCurrentlyObscured`'s existence/wiring, not a
  hand-rolled second mechanism.

This task has no dependency on Plan A and no dependency on any other task
in this plan — it can be built and shipped independently, and should be,
since it is a real, standing gap in this app's Safety posture regardless
of whether the AI Assistant feature ever ships.

- [ ] **Step 1: Write the failing widget test**

Create `test/core/services/app_privacy_cover_test.dart`:

```dart
import 'package:attune/core/services/app_privacy_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows no cover while the app is resumed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrivacyCover(
          child: const Text('secret content'),
        ),
      ),
    );
    expect(find.text('secret content'), findsOneWidget);
    expect(find.byKey(const Key('app_privacy_cover_overlay')), findsNothing);
  });

  testWidgets('shows an opaque cover when the app lifecycle goes inactive, and clears it on resume', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrivacyCover(
          child: const Text('secret content'),
        ),
      ),
    );

    // Simulate the OS delivering an inactive lifecycle message -- this is
    // the same mechanism a real app-switcher snapshot event delivers
    // through, exercised via the test binding rather than a real OS
    // event, which is the standard way Flutter widget tests drive
    // AppLifecycleState changes.
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.byKey(const Key('app_privacy_cover_overlay')), findsOneWidget);
    // The underlying content must be genuinely covered, not merely
    // painted behind a transparent widget -- assert the cover is opaque
    // by checking it's the topmost hit-testable widget at that location,
    // not just present in the tree.
    final coverFinder = find.byKey(const Key('app_privacy_cover_overlay'));
    final renderBox = tester.renderObject<RenderBox>(coverFinder);
    expect(renderBox.size, greaterThan(Size.zero));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('app_privacy_cover_overlay')), findsNothing);
  });

  testWidgets('paused and hidden also trigger the cover, matching inactive', (tester) async {
    for (final state in [AppLifecycleState.paused, AppLifecycleState.hidden]) {
      await tester.pumpWidget(
        MaterialApp(home: AppPrivacyCover(child: const Text('x'))),
      );
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(
        find.byKey(const Key('app_privacy_cover_overlay')),
        findsOneWidget,
        reason: 'AppLifecycleState.$state must trigger the cover',
      );
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }
  });

  testWidgets('the cover shows no readable content of its own -- no message text, no user names, no app-specific branding beyond the app icon/name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AppPrivacyCover(child: const Text('secret content'))),
    );
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('secret content'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/services/app_privacy_cover_test.dart`
Expected: fails — the module does not exist yet.

- [ ] **Step 3: Write `app_privacy_cover.dart`**

```dart
// A global, always-on cover that obscures every screen the instant the
// app leaves the foreground -- inactive (an incoming call, the app
// switcher, a system dialog), paused, or hidden. This closes the gap the
// AI Assistant spec's §6.3/§14.1 identified: this app previously had
// only Quick Exit's manually-triggered neutral route
// (lib/features/safety/domain/services/quick_exit_service.dart), never
// an automatic cover for an ordinary platform snapshot (the app-switcher
// thumbnail, a screenshot taken while backgrounding). Understand mode's
// private interpretation may rely on this only because it is wired in
// globally here, not per-screen.
//
// Uses AppLifecycleListener (not a WidgetsBindingObserver mixin), the
// same choice story_providers.dart and planning_providers.dart already
// made for their own lifecycle-driven logic in this codebase.
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

class AppPrivacyCover extends StatefulWidget {
  const AppPrivacyCover({super.key, required this.child});

  final Widget child;

  @override
  State<AppPrivacyCover> createState() => _AppPrivacyCoverState();
}

class _AppPrivacyCoverState extends State<AppPrivacyCover> {
  late final AppLifecycleListener _lifecycleListener;
  bool _obscured = false;

  static const _obscuringStates = {
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
  };

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        final shouldObscure = _obscuringStates.contains(state);
        if (shouldObscure != _obscured && mounted) {
          setState(() => _obscured = shouldObscure);
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_obscured)
          Positioned.fill(
            child: ColoredBox(
              key: const Key('app_privacy_cover_overlay'),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const _NeutralCoverContent(),
            ),
          ),
      ],
    );
  }
}

class _NeutralCoverContent extends StatelessWidget {
  const _NeutralCoverContent();

  @override
  Widget build(BuildContext context) {
    // Deliberately minimal: the app's own icon/name only, nothing that
    // could itself leak information about what was on screen a moment
    // ago. No message text, no partner name, no screen-specific state.
    return const Center(
      child: Icon(Icons.favorite, size: 48),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/services/app_privacy_cover_test.dart`
Expected: all pass.

- [ ] **Step 5: Wire it into `lib/app/app.dart`**

Modify `App`'s `MaterialApp.router` `builder` callback to wrap the
existing `MediaQuery.withClampedTextScaling` child:

```dart
builder: (context, child) {
  return AppPrivacyCover(
    child: MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: child ?? const SizedBox.shrink(),
    ),
  );
},
```

Add the import (`import 'package:attune/core/services/app_privacy_cover.dart';`).

- [ ] **Step 6: Mutation-test the state-set logic**

Temporarily remove `AppLifecycleState.hidden` from `_obscuringStates`,
confirm the "paused and hidden also trigger" test fails specifically on
the hidden case, restore, confirm it passes. Temporarily invert the
`shouldObscure != _obscured` guard to `==`, confirm the resume-clears-the-
cover assertion fails, restore.

- [ ] **Step 7: Manual real-device verification — this is a hard
  requirement, not optional polish**

The spec is explicit that this feature "may rely on it only after an
implementation test proves the root app obscures this sheet before
inactive/paused snapshots" and that "Quick Exit's explicit neutral route
alone is not that proof" — a widget test proves the Flutter-level state
machine works, but does not prove the OS actually captures the covered
frame rather than a stale one from before the state change. On a real
iOS and a real Android device (or the closest available simulator/
emulator if physical devices are unavailable — note explicitly in this
task's report which was actually used), background the app from a screen
showing real-looking content, open the OS app switcher, and visually
confirm the snapshot/thumbnail shown is the neutral cover, not the
underlying content. Take a screenshot of the app-switcher view itself as
evidence and reference it in this task's report (describe what it shows;
embedding an actual image file is not required, but the verification
must be described concretely, not asserted without detail).

- [ ] **Step 8: Run the full existing test suite for regressions**

Run: `flutter test`
Expected: no new failures relative to this worktree's own established
baseline (re-establish that baseline count now if this is the first task
in this worktree to run the full suite, per Planning's own Global
Constraints precedent on establishing a fresh worktree's baseline rather
than trusting a number carried over from elsewhere).

- [ ] **Step 9: Commit**

```bash
git add lib/core/services/app_privacy_cover.dart \
        lib/app/app.dart \
        test/core/services/app_privacy_cover_test.dart
git commit -m "feat(safety): global app-switcher privacy cover"
```

---

## Task 2: Domain models and the repository

**Files:**
- Create: `lib/features/ai_assistant/data/models/assist_draft_model.dart`
- Create: `lib/features/ai_assistant/data/models/understand_result_model.dart`
- Create: `lib/features/ai_assistant/data/models/place_source_model.dart`
- Create: `lib/features/ai_assistant/data/repositories/assistant_error.dart`
- Create: `lib/features/ai_assistant/data/repositories/ai_assistant_repository.dart`
- Test: `test/features/ai_assistant/ai_assistant_models_test.dart`
- Test: `test/features/ai_assistant/ai_assistant_repository_test.dart`

**Interfaces:**
- Consumes: Plan A's two edge functions (`ai-assist`, `ai-understand`) by
  HTTP contract (spec §4.1 request shapes, §5.3/§6.2 response shapes,
  §11 error envelope) and its RPCs by exact name (`share_ai_assist_draft`,
  `record_ai_processing_consent`, `get_ai_processing_consent_status`,
  `create_planning_from_assist_message`).
- Produces: `AssistDraftModel` (sealed on `assist_kind`: `ideas` carries
  `{ replyText: String, suggestedPlanningItem: SuggestedPlanningItem? }`,
  `nearby` carries `{ replyText: String, sources: List<PlaceSourceModel>
  }` — both share `{ draftId: String, expiresAt: DateTime }`),
  `UnderstandResultModel` (sealed on `status`: `ok` carries `{
  possibleReadings: List<String>, responseOptions: List<String>,
  confidence: 'low' | 'medium' }`, `cannotHelp` carries `{ reason: String
  }`), `PlaceSourceModel` (`{ providerId, name, formattedAddress,
  category, mapUrl }`, all matching spec §5.2's exact field list),
  `AssistantError` (sealed class matching spec §11's exact
  `AssistantErrorCode` enum — `AssistantError.unauthenticated()`,
  `.consentRequired()`, `.targetUnavailable()`, `.invalidInput()`,
  `.unsupportedRequest()`, `.locationRequired()`, `.noResults()`,
  `.rateLimited(int retryAfterSeconds)`, `.requestInProgress()`,
  `.resultUnavailable()`, `.providerUnavailable()`, `.internalError()`),
  `AiAssistantRepository` with `requestAssist(...)`, `requestUnderstand(...)`,
  `shareDraft(String draftId)`, `getConsentStatus(String relationshipId)`,
  `recordConsent(String relationshipId, String action)`,
  `addToPlanning(String messageId, {String? editedTitle, DateTime?
  editedDate})`, each throwing `AssistantError` on failure, never a raw
  exception. Every later task in this plan calls these exact class/method
  names.

- [ ] **Step 1: Write the failing model tests**

Create `test/features/ai_assistant/ai_assistant_models_test.dart` proving
`fromJson`/`fromRow`-style parsing for each model against the exact real
response shapes spec §5.3 (`IdeasModelOutput`-plus-server-assembled
sources), §5.2 (`PlaceSource`), and §6.2 (`UnderstandResponse`) define —
including the discriminated-union branches (an `ideas` draft never
carries `sources`; a `nearby` draft never carries
`suggestedPlanningItem`; a `cannotHelp` result never carries
`possibleReadings`). Include at least one test proving a malformed/
unexpected shape from the server throws a parse error rather than
silently constructing a model with null/default fields that could then
render as if the server had said something it didn't.

- [ ] **Step 2: Run the tests to verify they fail**

- [ ] **Step 3: Write the three model files**

Follow `lib/features/planning/data/models/planning_goal_model.dart`'s
established `fromRow`/`fromJson` factory-constructor shape for the exact
pattern this codebase uses. Match every field name to the spec's own
TypeScript literally (§5.2/§5.3/§6.2) — do not rename `reply_text` to
`replyText` inconsistently between the wire format and the Dart field in
a way that could cause a silent parse miss; use the wire name as the JSON
key and the idiomatic Dart name as the field, exactly as Planning's own
models already do for `child_count`/`childCount` etc.

- [ ] **Step 4: Run the model tests to verify they pass**

- [ ] **Step 5: Write the failing repository tests**

Create `test/features/ai_assistant/ai_assistant_repository_test.dart`.
Check `lib/features/planning/data/repositories/planning_repository.dart`
and its test file for this codebase's real pattern for injecting a fake
HTTP/RPC gateway (an abstract `AiAssistantGateway` seam, implemented for
real via the Supabase Dart client's edge-function-invoke method, faked in
tests) — match that pattern. Cover:

- a successful `requestAssist` call for `assist_kind: 'ideas'` parses the
  response into an `AssistDraftModel.ideas`;
- a successful `requestAssist` call for `assist_kind: 'nearby'` parses
  into `AssistDraftModel.nearby` with its `sources` list;
- every one of the 12 `AssistantErrorCode` values from spec §11 maps to
  the correct `AssistantError` subtype (test the exact mapping for each,
  not just a couple as a spot check — a missed mapping here means a raw
  code leaks to the UI as an unhandled case later);
- `RATE_LIMITED`'s `retry_after_seconds` field is carried through into
  `AssistantError.rateLimited`'s `retryAfterSeconds`, not dropped;
- `shareDraft` calls `share_ai_assist_draft` with exactly `p_draft_id`
  (the RPC's real, single-parameter signature per Plan A Task 6 — confirm
  against Plan A's actual committed migration if it exists in this
  worktree already, not just this plan's own draft text);
- `getConsentStatus`/`recordConsent` call
  `get_ai_processing_consent_status`/`record_ai_processing_consent` with
  the exact parameter names Plan A's Task 3 RPCs use;
- `addToPlanning` calls `create_planning_from_assist_message` with
  `p_message_id`, `p_edited_title`, `p_edited_date` by exact name;
- a malformed/unparseable success-status response (should never happen
  server-side, but the client must not crash) maps to
  `AssistantError.internalError()` rather than propagating a raw parse
  exception to the UI layer.

- [ ] **Step 6: Run the tests to verify they fail**

- [ ] **Step 7: Write `assistant_error.dart` and
  `ai_assistant_repository.dart`**

- [ ] **Step 8: Run the tests to verify they pass**

Run: `flutter test test/features/ai_assistant/`

- [ ] **Step 9: Mutation-test the error-mapping exhaustiveness**

For at least 3 of the 12 error codes, temporarily remove that specific
mapping branch (so it falls through to whatever default/else exists),
confirm the corresponding test fails, restore, confirm it passes again.
Additionally confirm — by reading the actual switch/if-chain, and
ideally via Dart's own exhaustiveness checking if the error-code source
type is itself a Dart enum/sealed type rather than a bare string compared
against 12 literals — that no code path can silently produce an
unmapped/generic error for a code the server actually sent.

- [ ] **Step 10: Run `flutter analyze` and the full existing suite for
  regressions**

- [ ] **Step 11: Commit**

```bash
git add lib/features/ai_assistant/data/ \
        test/features/ai_assistant/ai_assistant_models_test.dart \
        test/features/ai_assistant/ai_assistant_repository_test.dart
git commit -m "feat(ai-assistant): domain models and a typed-error repository over the edge functions"
```

---

## Task 3: Riverpod providers, consent, and quota state

**Files:**
- Create: `lib/features/ai_assistant/presentation/providers/ai_assistant_providers.dart`
- Test: `test/features/ai_assistant/ai_assistant_providers_test.dart`

**Interfaces:**
- Consumes: `AiAssistantRepository` (Task 2).
- Produces: `currentRelationshipIdProvider` (this feature's own
  independent copy, per the Global Constraints), `aiConsentStatusProvider
  (relationshipId)` — a `FutureProvider.autoDispose.family` wrapping
  `getConsentStatus`, `assistDraftProvider` — an
  `AsyncNotifierProvider.autoDispose` holding the in-flight/last
  `AssistDraftModel` for the currently-open Assist sheet (cleared on
  dismiss, never persisted across sheet instances — a fresh sheet open is
  a fresh provider instance, matching spec §1's "no previous assistant
  result is context for a later call"), `understandResultProvider` — an
  `AsyncNotifierProvider.autoDispose` holding the in-flight/last
  `UnderstandResultModel`, cleared identically plus on
  background/relationship-change per spec §6.3.

- [ ] **Step 1: Write the failing tests**

Cover: `assistDraftProvider` starts empty for a freshly-opened sheet
instance (no leakage from a previous invocation — construct two separate
`ProviderContainer`s or dispose-and-recreate the provider scope between
two simulated "sheet opens" and assert the second sees no trace of the
first's result); `understandResultProvider` clears itself when its
container is disposed (simulating dismiss) and cannot be read again after
disposal without throwing/being empty; a consent-required error from the
repository surfaces through the provider's error state distinctly from a
network error (so the UI can render the "waiting for your partner"
copy specifically, not a generic failure).

- [ ] **Step 2: Run the tests to verify they fail**

- [ ] **Step 3: Write `ai_assistant_providers.dart`**

- [ ] **Step 4: Run the tests to verify they pass, mutation-test the
  no-leakage-across-sheet-instances guarantee**

Temporarily make the provider `keepAlive()` (or otherwise defeat its
`.autoDispose` scoping), confirm the leakage test now fails (proving it
was actually testing something), restore.

- [ ] **Step 5: Run `flutter analyze` and the full suite for
  regressions**

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_assistant/presentation/providers/ai_assistant_providers.dart \
        test/features/ai_assistant/ai_assistant_providers_test.dart
git commit -m "feat(ai-assistant): riverpod providers for consent, assist drafts, and understand results"
```

---

## Task 4: Entry point — the long-press "Ask Attune" action and mode sheet

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`
- Modify: `lib/features/chat/presentation/widgets/message_actions_sheet.dart`
- Create: `lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart`
- Test: `test/features/chat/chat_screen_message_actions_test.dart` (extend
  existing — this file already has the wiring test pattern for the Info
  action; follow it, do not create a parallel new file)
- Test: `test/features/ai_assistant/ask_attune_mode_sheet_test.dart`

**Interfaces:**
- Produces: an `onAskAttune` callback wired through
  `message_actions_sheet.dart` exactly the way `onInfo` already is (read
  the real current `onInfo`/`_buildInfoOpener`/`_openMessageInfo` code in
  `message_bubble.dart` around lines 570-960 first, and copy that exact
  wiring shape — do not invent a different pattern for this one action).
  `AskAttuneModeSheet({required Message message})` — shows the two-mode
  choice (spec §3's "Get ideas"/"Possible ways to read this" copy),
  consent-gates via `aiConsentStatusProvider` before either mode can
  proceed, and routes to the Assist or Understand sheet (Tasks 5/6) on
  selection.

- [ ] **Step 1: Read the real eligibility-gating logic already in place
  for other focused-menu actions**

Before writing anything, read how `message_actions_sheet.dart` currently
decides which actions to show/hide for a given message (e.g. the
`canEditOrDelete`-gated edit/delete tiles). This task's own eligibility
gate (spec §3: active+unarchived relationship, non-deleted, non-blank,
≤4,000 chars, ordinary user-authored text only, server-acknowledged not
optimistic) needs to follow the same "compute once, pass down" shape this
file already uses for its existing gates, not a new ad hoc check.

- [ ] **Step 2: Write the failing wiring test**

Extend `test/features/chat/chat_screen_message_actions_test.dart` (the
file that already has the Info-action wiring test from Planning's own
prior chat work) with a new test proving: the "Ask Attune" tile appears
for an eligible message and is absent for an ineligible one (deleted,
media-only, over 4,000 chars, `message_origin = 'attune_assist'` — test
at least 2 of these ineligibility reasons, not just one, since each is
a distinct code path); tapping it opens `AskAttuneModeSheet` with the
correct `message` passed through (assert by identity/id, not just that
some sheet opened).

- [ ] **Step 3: Run the test to verify it fails**

- [ ] **Step 4: Wire `onAskAttune` through `message_bubble.dart`/
  `message_actions_sheet.dart`**

- [ ] **Step 5: Write the failing test for the mode sheet itself**

Create `test/features/ai_assistant/ask_attune_mode_sheet_test.dart`.
Cover: both mode options render with the spec's exact §3 copy; "Possible
ways to read this" (Understand) is hidden/disabled when the message's
`sender_id == current user's id` (spec §3: "Understand is available only
when `message.sender_id != auth.uid()`" — this is a UX gate, the server
independently enforces it too, but the client must not even offer the
option); before either mode is selectable, if `aiConsentStatusProvider`
shows the caller has not yet granted, the disclosure/consent prompt is
shown first and neither mode proceeds until it resolves; if consent is
granted by the caller but not yet by the partner, the sheet shows the
caller's own state and a "waiting for your partner" message, and
selecting a mode is a no-op (does not call either edge function).

- [ ] **Step 6: Run the test to verify it fails, then write
  `ask_attune_mode_sheet.dart`**

- [ ] **Step 7: Run all new/extended tests, mutation-test the
  own-message Understand-hiding logic and the consent gate**

Temporarily invert the `sender_id != auth.uid()` check, confirm the test
now wrongly shows Understand for the user's own message, restore.
Temporarily make the consent gate always treat consent as granted,
confirm the "waiting for partner" test fails, restore.

- [ ] **Step 8: Run `flutter analyze` and the full existing suite for
  regressions**

- [ ] **Step 9: Commit**

```bash
git add lib/features/chat/presentation/widgets/message_bubble.dart \
        lib/features/chat/presentation/widgets/message_actions_sheet.dart \
        lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart \
        test/features/chat/chat_screen_message_actions_test.dart \
        test/features/ai_assistant/ask_attune_mode_sheet_test.dart
git commit -m "feat(ai-assistant): the Ask Attune entry point and mode-choice sheet"
```

---

## Task 5: Assist mode — Ideas, Nearby, preview, and share

**Files:**
- Create: `lib/features/ai_assistant/presentation/screens/assist_sheet.dart`
- Create: `lib/features/ai_assistant/data/services/raw_location_service.dart`
- Test: `test/features/ai_assistant/assist_sheet_test.dart`
- Test: `test/features/ai_assistant/raw_location_service_test.dart`

**Interfaces:**
- Consumes: `assistDraftProvider` (Task 3), `AiAssistantRepository` (Task
  2).
- Produces: `RawLocationService.getCurrentPosition()` — a new,
  Geolocator-direct method distinct from and never calling
  `LocationService.getCurrentLocation()` (Global Constraints). `AssistSheet
  ({required Message message, required AssistKind kind})` — the Ideas
  input (optional 1-300 char instruction field) or Nearby flow (location
  disclosure → permission → generate), the private preview once a draft
  resolves, and the Share/Edit-as-mine/Close actions.

- [ ] **Step 1: Write the failing test for the raw location service**

Create `test/features/ai_assistant/raw_location_service_test.dart`. Since
this wraps a real platform plugin (`Geolocator`), follow whatever mocking
convention this codebase already uses for Geolocator-based tests if one
exists (check `test/` for an existing Geolocator mock/fake before writing
a new one) — check permission-denied handling returns a typed result the
UI can act on (not a thrown platform exception surfacing raw), and check
the returned position never includes any reverse-geocoded
address/locality field (proving, at the type level, that this service
genuinely cannot leak more than coordinates+accuracy — if the return type
itself has no field for an address, there is no code path that could
accidentally populate one).

- [ ] **Step 2: Run the test to verify it fails, then write
  `raw_location_service.dart`**

Use `Geolocator.getCurrentPosition()` directly with balanced/approximate
accuracy (spec §5.2: "not high-accuracy tracking") — confirm the real
`Geolocator` package version in `pubspec.yaml` for its actual current API
surface (accuracy enum values may differ from memory) before writing the
call.

- [ ] **Step 3: Run the test to verify it passes**

- [ ] **Step 4: Write the failing test for the Assist sheet**

Create `test/features/ai_assistant/assist_sheet_test.dart`. Cover, at
minimum:

- Ideas: typing an instruction over 300 characters disables Generate (or
  truncates — pick one behavior and test it explicitly; the spec caps at
  300 but doesn't mandate which UX handles the overflow, so decide and
  document the choice in this task's report);
- Nearby: before any permission request, the exact §5.2 disclosure copy
  is shown; declining returns to the sheet without calling the repository
  at all (assert the fake repository's request method was never invoked
  — this is the "declining consumes no quota" guarantee);
- a successful generation shows the private preview with Share/Edit as my
  message/Close, and does NOT show any of these until generation
  completes (no premature/optimistic preview of unconfirmed content);
- tapping Share calls `AiAssistantRepository.shareDraft` with the exact
  draft id and, on success, closes the sheet (assert via a passed-in
  callback or navigator pop, matching however this codebase's other
  sheets signal completion);
- tapping "Edit as my message" copies ONLY `replyText` into a value the
  test can assert against (e.g. a returned string via callback) — and
  explicitly does NOT carry over `assistant_payload`, sources, or the
  Attune label; assert no share/RPC call happens on this path at all,
  since sending happens later via the ordinary composer/Send button, not
  as a side effect of tapping this option;
- Close discards the client-side preview state without calling
  `shareDraft`;
- a `RATE_LIMITED` error renders the returned `retry_after_seconds` as
  actual seconds-until-retry copy, never the word "tomorrow" (spec §11);
- an expired-draft Share attempt (simulate the repository throwing the
  appropriate error) shows "This suggestion expired — ask again," not a
  generic failure, and never attempts to post anything.

- [ ] **Step 5: Run the tests to verify they fail, then write
  `assist_sheet.dart`**

- [ ] **Step 6: Run all new tests, mutation-test the "declining consumes
  no quota" and "Edit as mine strips provenance" guarantees specifically**

For the first: temporarily make the decline path call the repository
anyway, confirm the test catches it, restore. For the second: temporarily
have "Edit as my message" also pass through `assistant_payload`, confirm
a test fails (add one first if the existing suite doesn't already assert
the payload is absent from whatever value this path produces), restore.

- [ ] **Step 7: Run `flutter analyze` and the full existing suite for
  regressions**

- [ ] **Step 8: Commit**

```bash
git add lib/features/ai_assistant/presentation/screens/assist_sheet.dart \
        lib/features/ai_assistant/data/services/raw_location_service.dart \
        test/features/ai_assistant/assist_sheet_test.dart \
        test/features/ai_assistant/raw_location_service_test.dart
git commit -m "feat(ai-assistant): assist mode — ideas, nearby, preview, and share"
```

---

## Task 6: Understand mode

**Files:**
- Create: `lib/features/ai_assistant/presentation/screens/understand_sheet.dart`
- Test: `test/features/ai_assistant/understand_sheet_test.dart`

**Interfaces:**
- Consumes: `understandResultProvider` (Task 3), `AppPrivacyCover` (Task
  1) — this sheet's own tests assert the privacy cover is genuinely wired
  in for the surrounding app, not that this sheet reimplements its own
  separate obscuring logic.
- Produces: `UnderstandSheet({required Message message})` — no Copy,
  Share, Add to Planning, Send, or composer-prefill affordance anywhere
  in this widget's tree (spec §6.3's explicit list).

- [ ] **Step 1: Write the failing test**

Create `test/features/ai_assistant/understand_sheet_test.dart`. Cover:

- an `ok` result renders 2-3 `possibleReadings` and 2-3
  `responseOptions`, and the sheet's own source contains no `share`,
  `copy`, `composer`, or `Planning`-referencing widget/callback anywhere
  (grep the built widget tree for interactive affordances beyond
  dismissing the sheet, or — stronger — assert via static source
  inspection of the file the way Task 4's own "no share semantics" checks
  should work, matching whatever pattern this plan's earlier tasks
  established for proving an absence rather than a presence);
- the "Attune cannot know what your partner meant" framing (or
  equivalent uncertainty-forward copy) is shown alongside every result,
  not only when `confidence == 'low'` (spec §6.1: "UI says this before
  the result, not only when model confidence is low");
- `cannot_help: unsafe_to_infer` shows the same discreet Safety Resources
  link every OTHER result/error state also shows — assert the link's
  presence is IDENTICAL (same widget, same visibility) across at least
  one `ok` result and the `unsafe_to_infer` result, proving its presence
  cannot be used to infer whether the deterministic safety pipeline
  separately fired (spec §6.2's explicit anti-side-channel requirement);
- dismissing the sheet clears `understandResultProvider`'s state
  (assert by re-reading the provider after dismiss and confirming it's
  back to its initial/empty state, not merely that the widget
  unmounted);
- backgrounding the app while the sheet is open triggers the same
  clearing (simulate via the same `AppLifecycleState` mechanism Task 1's
  test uses) — and confirm the privacy cover (Task 1) is simultaneously
  active during this same simulated lifecycle transition, i.e. this test
  proves both guarantees fire together, not just one in isolation.

- [ ] **Step 2: Run the test to verify it fails, then write
  `understand_sheet.dart`**

- [ ] **Step 3: Run the tests, mutation-test the confidence-framing-
  always-shown and the safety-resources-link-parity guarantees**

For the first: temporarily gate the uncertainty framing on `confidence ==
'low'` only, confirm the medium-confidence test fails, restore. For the
second: temporarily hide the Safety Resources link specifically on the
`unsafe_to_infer` path (simulating a side-channel leak), confirm the
parity test fails, restore.

- [ ] **Step 4: Run `flutter analyze` and the full existing suite for
  regressions**

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_assistant/presentation/screens/understand_sheet.dart \
        test/features/ai_assistant/understand_sheet_test.dart
git commit -m "feat(ai-assistant): understand mode — private, ephemeral interpretation help"
```

---

## Task 7: The Attune Assist chat bubble, message edit/delete split, and Add to Planning

**Files:**
- Modify: `lib/features/chat/domain/entities/message.dart`
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`
- Modify: `lib/features/chat/presentation/widgets/message_actions_sheet.dart`
- Create: `lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart`
- Test: extend `test/features/chat/presentation/widgets/message_bubble_test.dart`
- Test: `test/features/ai_assistant/attune_assist_bubble_test.dart`

**Interfaces:**
- Consumes: `AiAssistantRepository.addToPlanning` (Task 2).
- Produces: `Message.canEdit({required String currentUserId, required
  DateTime now})` and `Message.canDelete({required String currentUserId,
  required DateTime now})` replacing the single existing `canEditOrDelete`
  — `canEdit` additionally returns `false` whenever
  `message.messageOrigin == 'attune_assist'` (regardless of sender/time
  window), `canDelete` retains the existing five-minute-sender logic
  unchanged for both origins. `AttuneAssistBubble({required Message
  message})` — the distinct visual treatment (per spec §5.3, attributed
  to the requester, not an authorless system notice), rendering
  `assistant_payload.sources` (Nearby) and the "Add to Planning"
  affordance (present only when `assistant_payload.suggested_planning_item
  != null` and no `ai_assist_planning_links` row exists yet for this
  message — check whether the client already has a way to know about that
  link row's existence, e.g. via a Realtime signal or a field on the
  message itself; if not, this task must add a minimal read path for it,
  following Planning's own `.autoDispose` Realtime-refresh pattern rather
  than polling).

This task's `Message.canEditOrDelete` split is a breaking API change to
existing shared code. Before starting, run
`grep -rn "canEditOrDelete" lib/ test/` and enumerate every real call
site — this plan's earlier drafts found exactly 4
(`message.dart`'s own definition, `message_bubble.dart`,
`message_actions_sheet.dart`, and their respective test files), but
re-run the grep yourself rather than trusting that count, since other
work may have added a call site since.

- [ ] **Step 1: Enumerate every real `canEditOrDelete` call site**

Run the grep above. Read each call site's surrounding code to determine
whether it needs `canEdit`, `canDelete`, or both (a site gating a single
"..." overflow menu that shows both Edit and Delete tiles needs both
computed separately now, since they can disagree for an Assist message).

- [ ] **Step 2: Write the failing tests for the split**

Extend `test/features/chat/presentation/widgets/message_bubble_test.dart`
and add a direct unit test on `Message` itself (find or create
`test/features/chat/domain/entities/message_test.dart` — check if a
Message-entity-level test file already exists for the current
`canEditOrDelete` before creating a new one) proving: an ordinary user
message's `canEdit`/`canDelete` both match the OLD combined method's
result exactly for every existing test case that method already had
(this is the regression-safety net — the split must not change behavior
for non-Assist messages at all); an Assist-origin message within the
five-minute window has `canDelete == true` but `canEdit == false`; an
Assist-origin message outside the window has both `false`.

- [ ] **Step 3: Run the tests to verify they fail (compile errors are
  expected and fine — the method doesn't exist yet in the new shape)**

- [ ] **Step 4: Perform the split in `message.dart`, updating every call
  site found in Step 1**

- [ ] **Step 5: Run the tests to verify they pass**

- [ ] **Step 6: Write the failing test for the Attune Assist bubble**

Create `test/features/ai_assistant/attune_assist_bubble_test.dart`. Cover:
the bubble's visual identity comes from `message.messageOrigin`, not from
inspecting `content` for AI-sounding phrasing (construct a test message
whose `content` looks exactly like ordinary human text but has
`messageOrigin: 'attune_assist'`, and a second message whose `content` is
deliberately AI-suggestion-shaped text but `messageOrigin: 'user'` —
assert the first renders as Attune-attributed and the second does not,
proving the check is genuinely on the field, not accidentally still
sniffing content somewhere); Nearby sources render with the required
Mapbox attribution (spec §5.2); "Add to Planning" is absent when
`suggested_planning_item` is null; "Add to Planning" is absent (shows
"Added to Planning" instead) once a link already exists; tapping "Add to
Planning" with an edited title calls `addToPlanning` with that edited
value, not the original proposal's title; a second concurrent tap (or a
tap after another client already created the link) does not error
visibly — it either shows "Added to Planning" after the call returns the
existing link, or is disabled during the in-flight call (pick one and
test it, matching whatever Plan A's Task 7 RPC actually guarantees for a
concurrent second call).

- [ ] **Step 7: Run the test to verify it fails, then write
  `attune_assist_bubble.dart`**

- [ ] **Step 8: Wire the bubble into the real message-rendering path**

Find wherever `message_bubble.dart` currently branches on message type/
shape to choose which bubble widget to render (it already does this for
game cards, media, system notices — follow the same branch-on-a-specific-
field pattern) and add a branch for `messageOrigin == 'attune_assist'`
rendering `AttuneAssistBubble` instead of the ordinary text bubble.

- [ ] **Step 9: Run all new/extended tests, mutation-test the
  content-sniffing-vs-field-check guarantee specifically**

Temporarily make the bubble-selection branch also match on a content
heuristic (e.g. `content.contains('suggestion')`) in addition to the
field check, confirm the "AI-shaped content but user origin" test now
fails (proving it would have caught real content-sniffing regressions),
restore to the field-only check.

- [ ] **Step 10: Run `flutter analyze` and the full existing suite for
  regressions**

- [ ] **Step 11: Commit**

```bash
git add lib/features/chat/domain/entities/message.dart \
        lib/features/chat/presentation/widgets/message_bubble.dart \
        lib/features/chat/presentation/widgets/message_actions_sheet.dart \
        lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart \
        test/features/chat/presentation/widgets/message_bubble_test.dart \
        test/features/ai_assistant/attune_assist_bubble_test.dart
git commit -m "feat(ai-assistant): the attune assist bubble, immutable-edit split, and add to planning"
```

---

## Task 8: Consent onboarding UI

**Files:**
- Create: `lib/features/ai_assistant/presentation/screens/ai_consent_screen.dart`
- Test: `test/features/ai_assistant/ai_consent_screen_test.dart`

**Interfaces:**
- Consumes: `aiConsentStatusProvider`, `AiAssistantRepository.recordConsent`
  (both from Tasks 2-3).
- Produces: `AiConsentScreen({required String relationshipId})` — the
  approved third-party AI disclosure (spec §10.1), a Grant/Decline choice,
  and the "waiting for your partner" state. Task 4's mode sheet routes
  here on first use per spec §3's "the first use also shows the approved
  ... disclosure and consent state."

- [ ] **Step 1: Write the failing test**

Cover: the disclosure text is genuinely present (not a placeholder — this
task must write real, spec-consistent copy, since §10.1's actual wording
is a product/legal decision this plan cannot make unilaterally; write
reasonable placeholder-free copy consistent with the spec's own quoted
disclosure text in §5.2/§10.1 and flag in this task's report that the
exact final wording is a release-gate item per §14.1 gate 2, not
something this task's code should be treated as final on); tapping
Grant calls `recordConsent(relationshipId, 'granted')` with a
client-generated idempotency key (assert a UUID-shaped value is passed,
not a hardcoded/reused one across two separate taps); after granting,
if the partner has not yet granted, the screen shows the waiting state
without erroring; withdrawing (if this screen also exposes withdrawal —
decide and document whether withdrawal lives here or in a separate
settings screen, matching however this codebase's existing chat-settings-
adjacent screens are organized) calls `recordConsent(relationshipId,
'withdrawn')`.

- [ ] **Step 2: Run the test to verify it fails, then write the screen**

- [ ] **Step 3: Run the tests, mutation-test the idempotency-key
  uniqueness**

Temporarily hardcode a fixed idempotency key across calls, confirm a test
catches the reuse (add one if the existing suite doesn't already assert
uniqueness across two taps), restore.

- [ ] **Step 4: Run `flutter analyze` and the full existing suite for
  regressions**

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_assistant/presentation/screens/ai_consent_screen.dart \
        test/features/ai_assistant/ai_consent_screen_test.dart
git commit -m "feat(ai-assistant): the consent disclosure/grant/withdraw screen"
```

---

## Task 9: Final client review pass

**Files:**
- No new feature files. A review-and-fix pass over Tasks 1–8's combined
  output, mirroring Planning's own final client review task.

- [ ] **Step 1: Run the complete AI-Assistant-related Flutter test
  surface together**

Run: `flutter test test/features/ai_assistant test/features/chat
test/core/services`
Expected: all pass, with this worktree's own freshly-established
baseline counts (not a number carried over from Planning's worktree or
an earlier session).

- [ ] **Step 2: Run the full Flutter test suite once, not per-directory**

Run: `flutter test`
Expected: no failures beyond this worktree's own pre-existing, already-
known baseline (re-establish that baseline in THIS worktree if it hasn't
been established yet by an earlier task).

- [ ] **Step 3: Run `flutter analyze` on the whole repo**

Run: `flutter analyze lib test`
Expected: 0 errors.

- [ ] **Step 4: Verify no AI Assistant provider leaks — every `.family`
  that opens a resource is `.autoDispose`**

Grep `lib/features/ai_assistant/presentation/providers/ai_assistant_providers.dart`
for every `.family<` and confirm each is `.autoDispose.family`.

- [ ] **Step 5: Verify the privacy cover is genuinely wired into the app
  root, not merely present as an unused widget**

Run: `grep -n "AppPrivacyCover" lib/app/app.dart`
Expected: a match showing it wraps the router's actual child, not just an
import with no usage.

- [ ] **Step 6: Verify every `Message.canEditOrDelete` call site was
  actually migrated — the old method must no longer exist at all**

Run: `grep -rn "canEditOrDelete" lib/ test/`
Expected: no matches anywhere in the codebase. Any match means Task 7's
split left a stale call site calling a method that either no longer
exists (a compile error that should have been caught already) or, worse,
was left as a second, un-migrated definition sitting alongside the two
new methods (a real correctness gap if so — investigate and fix).

- [ ] **Step 7: Verify no test added by this plan is vacuous in the
  specific way this codebase has shipped before**

For every widget test in this plan's own new test files that asserts a
widget/action "is present" or "is wired up" via any kind of source-text
or tree-presence check (not a full interaction simulation), re-read it
specifically for the substring-collision failure mode Planning's own
Task 5 review found and fixed (a private class's own constructor
declaration satisfying a presence check meant to prove usage). Fix any
found.

- [ ] **Step 8: Sweep for accidental push-notification code paths**

Run: `grep -rln "OneSignal\|scheduled_notifications" lib/features/ai_assistant/`
Expected: no matches (the feature must add none).

- [ ] **Step 9: Write the completion note**

If Steps 1–8 surfaced any fix, commit it now with a message describing
exactly what was wrong and which step caught it, then re-run Steps 1–8 in
full before considering this task done. If nothing needed fixing, no
commit is required beyond what Tasks 1–8 already committed.
</content>

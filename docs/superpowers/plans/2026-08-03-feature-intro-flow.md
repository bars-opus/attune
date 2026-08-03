# Feature Intro Flow (Dating Mode + Healing Mode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate first-time entry into Dating Mode and Healing Mode behind a reusable 3-page intro flow (brief intro → documentation → FAQ), reusing existing `DatingModeDocs`/`HealingDocs` content, persisted device-locally so it shows exactly once per feature per user.

**Architecture:** A `SeenFeatureIntroStore` (SharedPreferences-backed, mirrors `QuizProgressStore`'s exact shape) tracks which feature intros have been seen. A `FeatureIntroFlowGate` widget wraps each feature's `GoRoute` builder, loading the seen-flag asynchronously and rendering either the real feature screen or a `FeatureIntroFlowScreen` (a 3-page `PageView`: brief intro, `ManualWidget`, `FAQWidget`) that marks the flag seen on completion or skip. Neither `DatingConsentScreen` nor any existing navigation call site (`EndRelationshipAction`, `ChatCouplesLockedScreen._onHealingEntryTap`, the dating dashboard's 3 consent CTAs) changes at all — gating is centralized at the two route builders.

**Tech Stack:** Flutter, `shared_preferences`, GoRouter, existing `DocumentationModule`/`ManualWidget`/`FAQWidget` documentation system.

## Global Constraints

- No changes to `DatingConsentScreen` or its 3 existing `pushNamed('datingConsent')` call sites (`dating_dashboard_screen.dart:159, 202, 585`).
- No changes to `EndRelationshipAction.confirmAndEnd`'s `context.push(RouteNames.healingJourney)` call (`end_relationship_action.dart:47`), or to `ChatCouplesLockedScreen._onHealingEntryTap`'s two `context.push(RouteNames.healingJourney)` calls (`chat_couples_locked_screen.dart:137, 147`).
- No new copy beyond one short page-1 paragraph per feature — all documentation/FAQ content comes from the existing `DatingModeDocs.getSections/getFAQs` and `HealingDocs.getSections/getFAQs` (confirmed real content, not placeholders, in `lib/app/documentations/user_manual/data/dating_mode_docs.dart` and `healing_docs.dart`).
- `SeenFeatureIntroStore` follows `QuizProgressStore`'s exact construction convention (`lib/features/quiz/data/local/quiz_progress_store.dart`): plain class taking a `SharedPreferences` instance in its constructor, no Riverpod provider — confirmed via grep that no provider wraps `QuizProgressStore` anywhere in this codebase.
- `PageView` in `FeatureIntroFlowScreen` is non-swipeable (`physics: const NeverScrollableScrollPhysics()`), advanced only via Continue/Back buttons.
- Confirmed exact `DocumentationModule.id` values: `DatingModeDocs.id => 'datingMode'` (`dating_mode_docs.dart:17`), `HealingDocs.id => 'healing'` (`healing_docs.dart:20`).
- Confirmed exact current route builders to modify: `app_router.dart` around line 1266 (`RouteNames.datingMode` → `DatingDashboardScreen`) and around line 452 (`RouteNames.healingJourney` → `HealingJourneyScreen`).

---

### Task 1: `SeenFeatureIntroStore`

**Files:**
- Create: `lib/core/intro/data/seen_feature_intro_store.dart`
- Test: `test/core/intro/seen_feature_intro_store_test.dart`

**Interfaces:**
- Produces: `SeenFeatureIntroStore(SharedPreferences prefs)`, `bool hasSeenIntro(String featureId)`, `Future<void> markIntroSeen(String featureId)` — consumed by Task 4 (`FeatureIntroFlowGate`).

This is a plain SharedPreferences wrapper, no widget/provider involved — matches `QuizProgressStore`'s exact shape (`lib/features/quiz/data/local/quiz_progress_store.dart:1-65`, in particular its keyed-prefix `hasSavedProgress` pattern at lines 61-64).

- [ ] **Step 1: Write the failing test**

Create `test/core/intro/seen_feature_intro_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attune/core/intro/data/seen_feature_intro_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SeenFeatureIntroStore', () {
    test('hasSeenIntro returns false before markIntroSeen is called', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SeenFeatureIntroStore(prefs);

      expect(store.hasSeenIntro('datingMode'), isFalse);
    });

    test('hasSeenIntro returns true after markIntroSeen', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SeenFeatureIntroStore(prefs);

      await store.markIntroSeen('datingMode');

      expect(store.hasSeenIntro('datingMode'), isTrue);
    });

    test('flags are independently keyed per featureId', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SeenFeatureIntroStore(prefs);

      await store.markIntroSeen('datingMode');

      expect(store.hasSeenIntro('datingMode'), isTrue);
      expect(store.hasSeenIntro('healing'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/intro/seen_feature_intro_store_test.dart`
Expected: FAIL — `seen_feature_intro_store.dart` does not exist yet (import error).

- [ ] **Step 3: Write the implementation**

Create `lib/core/intro/data/seen_feature_intro_store.dart`:

```dart
// lib/core/intro/data/seen_feature_intro_store.dart

import 'package:shared_preferences/shared_preferences.dart';

/// Tracks, per feature id, whether the first-time intro flow
/// (FeatureIntroFlowScreen) has already been shown on this device.
/// Mirrors QuizProgressStore's construction and keyed-prefix convention.
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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/intro/seen_feature_intro_store_test.dart`
Expected: PASS, 3/3.

- [ ] **Step 5: Commit**

```bash
git add lib/core/intro/data/seen_feature_intro_store.dart test/core/intro/seen_feature_intro_store_test.dart
git commit -m "feat(intro): add SeenFeatureIntroStore"
```

---

### Task 2: `FeatureIntroFlowScreen`

**Files:**
- Create: `lib/core/intro/presentation/screens/feature_intro_flow_screen.dart`
- Create: `lib/core/intro/presentation/widgets/feature_intro_brief_page.dart`
- Test: `test/core/intro/feature_intro_flow_screen_test.dart`

**Interfaces:**
- Consumes: `DocumentationModule` (`lib/app/documentations/user_manual/models/documentation_model.dart` — `id`, `icon`, `getTitle(context)`, `getSubtitle(context)`, `getSections(context) → List<ManualSection>`, `getFAQs(context) → List<FAQModel>`), `ManualWidget` (`lib/app/documentations/user_manual/widgets/manual_widget.dart` — `ManualWidget({required List<ManualSection> sections})`), `FAQWidget` (`lib/app/documentations/user_manual/widgets/faq_widget.dart` — `FAQWidget({required List<FAQModel> faqs})`), `AppButton` (`lib/core/widgets/buttons/app_button.dart` — `AppButton({required String label, required VoidCallback? onPressed, ButtonSize size, ButtonVariant variant, bool center, double? width})`).
- Produces: `FeatureIntroFlowScreen(module: DocumentationModule, briefParagraph: String, launchLabel: String, onComplete: VoidCallback)` — consumed by Task 4 (`FeatureIntroFlowGate`). `onComplete` is called on both final-page completion and Skip; this screen has **no** `SeenFeatureIntroStore`/`SharedPreferences` dependency — persistence is entirely the caller's (`FeatureIntroFlowGate`'s) responsibility.

- [ ] **Step 1: Write the failing test**

Create `test/core/intro/feature_intro_flow_screen_test.dart`. This test needs a real `DocumentationModule` — build a minimal fake inline rather than depending on `DatingModeDocs`/`HealingDocs`, so the test is self-contained and fast:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';
import 'package:attune/core/intro/presentation/screens/feature_intro_flow_screen.dart';

class _FakeDocs implements DocumentationModule {
  @override
  String get id => 'fakeFeature';

  @override
  IconData get icon => Icons.star;

  @override
  int get order => 1;

  @override
  String getTitle(BuildContext context) => 'Fake Feature';

  @override
  String getSubtitle(BuildContext context) => 'A feature for testing';

  @override
  List<ManualSection> getSections(BuildContext context) => [
        ManualSection(
          id: 'fake_section',
          title: 'Fake Section',
          icon: Icons.info,
          category: 'Fake Feature',
          order: 1,
          contents: [
            ManualContent(
              id: 'fake_content',
              title: 'Fake content title',
              content: 'Fake content body',
              type: ManualContentType.text,
              order: 1,
            ),
          ],
        ),
      ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => [
        const FAQModel(
          id: 'fake_faq',
          question: 'Is this a real FAQ?',
          answer: 'No, it is a fake one for testing.',
          category: 'Fake Feature',
          order: 1,
        ),
      ];
}

void main() {
  Widget buildTestable({required VoidCallback onComplete}) {
    return MaterialApp(
      home: FeatureIntroFlowScreen(
        module: _FakeDocs(),
        briefParagraph: 'This is the brief intro paragraph.',
        launchLabel: 'Get started',
        onComplete: onComplete,
      ),
    );
  }

  testWidgets('starts on page 1 with brief intro content, no Back control', (tester) async {
    await tester.pumpWidget(buildTestable(onComplete: () {}));

    expect(find.text('Fake Feature'), findsOneWidget);
    expect(find.text('This is the brief intro paragraph.'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
  });

  testWidgets('Continue advances page 1 to page 2 (documentation)', (tester) async {
    await tester.pumpWidget(buildTestable(onComplete: () {}));

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Fake content title'), findsOneWidget);
  });

  testWidgets('Continue advances page 2 to page 3 (FAQ), Back returns to page 2', (tester) async {
    await tester.pumpWidget(buildTestable(onComplete: () {}));

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Is this a real FAQ?'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Fake content title'), findsOneWidget);
  });

  testWidgets('final CTA on page 3 calls onComplete', (tester) async {
    var completed = false;
    await tester.pumpWidget(buildTestable(onComplete: () => completed = true));

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });

  testWidgets('Skip on page 1 calls onComplete immediately', (tester) async {
    var completed = false;
    await tester.pumpWidget(buildTestable(onComplete: () => completed = true));

    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/intro/feature_intro_flow_screen_test.dart`
Expected: FAIL — `feature_intro_flow_screen.dart` does not exist yet.

- [ ] **Step 3: Write `FeatureIntroBriefPage`**

Create `lib/core/intro/presentation/widgets/feature_intro_brief_page.dart`:

```dart
// lib/core/intro/presentation/widgets/feature_intro_brief_page.dart

import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// Page 1 of FeatureIntroFlowScreen: icon, title, subtitle from the
/// module plus one feature-specific brief paragraph.
class FeatureIntroBriefPage extends StatelessWidget {
  const FeatureIntroBriefPage({
    super.key,
    required this.module,
    required this.briefParagraph,
  });

  final DocumentationModule module;
  final String briefParagraph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: EdgeInsets.all(Spacing.xl.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Gap(Spacing.xxl.h),
          Container(
            width: 72.w,
            height: 72.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.primary.withOpacity(0.4)),
            ),
            child: Icon(module.icon, size: 32.h, color: colorScheme.primary),
          ),
          Gap(Spacing.lg.h),
          Text(
            module.getTitle(context),
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.sm.h),
          Text(
            module.getSubtitle(context),
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.xl.h),
          Text(
            briefParagraph,
            style: textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write `FeatureIntroFlowScreen`**

Create `lib/core/intro/presentation/screens/feature_intro_flow_screen.dart`:

```dart
// lib/core/intro/presentation/screens/feature_intro_flow_screen.dart

import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/documentations/user_manual/widgets/faq_widget.dart';
import 'package:attune/app/documentations/user_manual/widgets/manual_widget.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/intro/presentation/widgets/feature_intro_brief_page.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// A 3-page first-time intro (brief → documentation → FAQ) shown once
/// per feature before its real screen. Persistence (marking the intro
/// seen) is entirely the caller's responsibility via onComplete — this
/// widget is pure presentation.
class FeatureIntroFlowScreen extends StatefulWidget {
  const FeatureIntroFlowScreen({
    super.key,
    required this.module,
    required this.briefParagraph,
    required this.launchLabel,
    required this.onComplete,
  });

  final DocumentationModule module;
  final String briefParagraph;
  final String launchLabel;
  final VoidCallback onComplete;

  @override
  State<FeatureIntroFlowScreen> createState() =>
      _FeatureIntroFlowScreenState();
}

class _FeatureIntroFlowScreenState extends State<FeatureIntroFlowScreen> {
  final _pageController = PageController();
  int _pageIndex = 0;

  static const _pageCount = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    setState(() => _pageIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.getTitle(context)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: widget.onComplete,
            child: const Text('Skip intro'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                FeatureIntroBriefPage(
                  module: widget.module,
                  briefParagraph: widget.briefParagraph,
                ),
                ManualWidget(sections: widget.module.getSections(context)),
                FAQWidget(faqs: widget.module.getFAQs(context)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(Spacing.lg.w),
            child: Row(
              children: [
                if (_pageIndex > 0)
                  Expanded(
                    child: AppButton(
                      label: 'Back',
                      variant: ButtonVariant.outline,
                      onPressed: () => _goToPage(_pageIndex - 1),
                    ),
                  ),
                if (_pageIndex > 0) SizedBox(width: Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: _pageIndex == _pageCount - 1
                        ? widget.launchLabel
                        : 'Continue',
                    onPressed: () {
                      if (_pageIndex == _pageCount - 1) {
                        widget.onComplete();
                      } else {
                        _goToPage(_pageIndex + 1);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

Confirmed at plan-writing time: `ButtonVariant` (`lib/core/widgets/buttons/app_button.dart:392`) is `enum ButtonVariant { primary, secondary, outline, text, custom }` — `ButtonVariant.outline` above is correct as written, no adjustment needed.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/intro/feature_intro_flow_screen_test.dart`
Expected: PASS, 5/5.

- [ ] **Step 6: Commit**

```bash
git add lib/core/intro/presentation/screens/feature_intro_flow_screen.dart lib/core/intro/presentation/widgets/feature_intro_brief_page.dart test/core/intro/feature_intro_flow_screen_test.dart
git commit -m "feat(intro): add FeatureIntroFlowScreen 3-page widget"
```

---

### Task 3: `FeatureIntroFlowGate`

**Files:**
- Create: `lib/core/intro/presentation/widgets/feature_intro_flow_gate.dart`
- Test: `test/core/intro/feature_intro_flow_gate_test.dart`

**Interfaces:**
- Consumes: `SeenFeatureIntroStore` (Task 1 — `hasSeenIntro(String) → bool`, `markIntroSeen(String) → Future<void>`), `FeatureIntroFlowScreen` (Task 2 — `FeatureIntroFlowScreen({required DocumentationModule module, required String briefParagraph, required String launchLabel, required VoidCallback onComplete})`).
- Produces: `FeatureIntroFlowGate({required DocumentationModule module, required String briefParagraph, required String launchLabel, required Widget Function() buildFeature})` — consumed by Task 5 (route wiring).

This widget owns its own async `SharedPreferences` load (matching `attachment_quiz_screen.dart:61-64`'s exact pattern), so `SeenFeatureIntroStore` construction is testable by injecting a pre-built store rather than always hitting real `SharedPreferences.getInstance()` — add an optional `SeenFeatureIntroStore? storeOverride` constructor parameter used only by tests, defaulting to `null` in production use (production always constructs via `SharedPreferences.getInstance()`).

- [ ] **Step 1: Write the failing test**

Create `test/core/intro/feature_intro_flow_gate_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';
import 'package:attune/core/intro/data/seen_feature_intro_store.dart';
import 'package:attune/core/intro/presentation/widgets/feature_intro_flow_gate.dart';

class _FakeDocs implements DocumentationModule {
  @override
  String get id => 'fakeFeature';

  @override
  IconData get icon => Icons.star;

  @override
  int get order => 1;

  @override
  String getTitle(BuildContext context) => 'Fake Feature';

  @override
  String getSubtitle(BuildContext context) => 'A feature for testing';

  @override
  List<ManualSection> getSections(BuildContext context) => [];

  @override
  List<FAQModel> getFAQs(BuildContext context) => [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestable(SeenFeatureIntroStore store) {
    return MaterialApp(
      home: FeatureIntroFlowGate(
        module: _FakeDocs(),
        briefParagraph: 'Brief.',
        launchLabel: 'Enter',
        storeOverride: store,
        buildFeature: () => const Scaffold(body: Text('Real Feature Screen')),
      ),
    );
  }

  testWidgets('renders the real feature directly when intro already seen', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = SeenFeatureIntroStore(prefs);
    await store.markIntroSeen('fakeFeature');

    await tester.pumpWidget(buildTestable(store));
    await tester.pumpAndSettle();

    expect(find.text('Real Feature Screen'), findsOneWidget);
    expect(find.text('Fake Feature'), findsNothing);
  });

  testWidgets('renders the intro flow when unseen, then swaps to the real feature on completion', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = SeenFeatureIntroStore(prefs);

    await tester.pumpWidget(buildTestable(store));
    await tester.pumpAndSettle();

    expect(find.text('Fake Feature'), findsOneWidget);
    expect(find.text('Real Feature Screen'), findsNothing);

    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    expect(find.text('Real Feature Screen'), findsOneWidget);
    expect(store.hasSeenIntro('fakeFeature'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/intro/feature_intro_flow_gate_test.dart`
Expected: FAIL — `feature_intro_flow_gate.dart` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/core/intro/presentation/widgets/feature_intro_flow_gate.dart`:

```dart
// lib/core/intro/presentation/widgets/feature_intro_flow_gate.dart

import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/core/intro/data/seen_feature_intro_store.dart';
import 'package:attune/core/intro/presentation/screens/feature_intro_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps a feature's real screen behind a one-time intro gate. Used
/// directly as a GoRoute builder's return value so the gating logic
/// lives at the route, not duplicated at every navigation call site.
class FeatureIntroFlowGate extends StatefulWidget {
  const FeatureIntroFlowGate({
    super.key,
    required this.module,
    required this.briefParagraph,
    required this.launchLabel,
    required this.buildFeature,
    this.storeOverride,
  });

  final DocumentationModule module;
  final String briefParagraph;
  final String launchLabel;
  final Widget Function() buildFeature;

  /// Test-only: inject a pre-built store instead of loading real
  /// SharedPreferences. Always null in production use.
  final SeenFeatureIntroStore? storeOverride;

  @override
  State<FeatureIntroFlowGate> createState() => _FeatureIntroFlowGateState();
}

class _FeatureIntroFlowGateState extends State<FeatureIntroFlowGate> {
  SeenFeatureIntroStore? _store;
  bool _seen = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initializeStore();
  }

  Future<void> _initializeStore() async {
    final store = widget.storeOverride ??
        SeenFeatureIntroStore(await SharedPreferences.getInstance());
    if (!mounted) return;
    setState(() {
      _store = store;
      _seen = store.hasSeenIntro(widget.module.id);
      _loading = false;
    });
  }

  void _handleIntroComplete() {
    _store?.markIntroSeen(widget.module.id);
    setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_seen) {
      return widget.buildFeature();
    }

    return FeatureIntroFlowScreen(
      module: widget.module,
      briefParagraph: widget.briefParagraph,
      launchLabel: widget.launchLabel,
      onComplete: _handleIntroComplete,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/intro/feature_intro_flow_gate_test.dart`
Expected: PASS, 2/2.

- [ ] **Step 5: Commit**

```bash
git add lib/core/intro/presentation/widgets/feature_intro_flow_gate.dart test/core/intro/feature_intro_flow_gate_test.dart
git commit -m "feat(intro): add FeatureIntroFlowGate route wrapper"
```

---

### Task 4: Wire the gate into Dating Mode and Healing Mode routes

**Files:**
- Modify: `lib/app/routing/app_router.dart`
- Test: `test/app/routing/feature_intro_route_wiring_test.dart`

**Interfaces:**
- Consumes: `FeatureIntroFlowGate` (Task 3), `DatingModeDocs` (`lib/app/documentations/user_manual/data/dating_mode_docs.dart`), `HealingDocs` (`lib/app/documentations/user_manual/data/healing_docs.dart`).

This is the only task that touches `app_router.dart`. Both route changes are one-line builder swaps; nothing else in the file changes.

- [ ] **Step 1: Locate and read the exact current route builders**

Run: `grep -n "RouteNames.datingMode\|RouteNames.healingJourney" lib/app/routing/app_router.dart`

Confirm the two `GoRoute` blocks look like this (these are the confirmed current contents as of this plan's writing — re-verify before editing in case other work has touched this file since):

```dart
      GoRoute(
        path: RouteNames.datingMode,
        name: 'datingMode',
        builder: (context, state) => const DatingDashboardScreen(),
      ),
```

```dart
      GoRoute(
        path: RouteNames.healingJourney,
        name: 'healingJourney',
        builder: (context, state) => const HealingJourneyScreen(),
      ),
```

- [ ] **Step 2: Add the import**

At the top of `lib/app/routing/app_router.dart`, add:

```dart
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/documentations/user_manual/data/healing_docs.dart';
import 'package:attune/core/intro/presentation/widgets/feature_intro_flow_gate.dart';
```

Confirmed at plan-writing time: `app_router.dart` has no existing transitive import reaching `dating_mode_docs.dart` or `healing_docs.dart` (checked its full import block), so add both directly as shown above — no conditional check needed.

- [ ] **Step 3: Replace the Dating Mode route builder**

Change:
```dart
        builder: (context, state) => const DatingDashboardScreen(),
```
to:
```dart
        builder: (context, state) => FeatureIntroFlowGate(
          module: DatingModeDocs(),
          briefParagraph:
              'Dating Mode is separate from Healing Mode, and never automatic. '
              'Before you can browse introductions, you\'ll go through a short, '
              'explicit consent step — nothing here is enabled without your say-so.',
          launchLabel: 'Continue to Dating Mode',
          buildFeature: () => const DatingDashboardScreen(),
        ),
```

- [ ] **Step 4: Replace the Healing Mode route builder**

Change:
```dart
        builder: (context, state) => const HealingJourneyScreen(),
```
to:
```dart
        builder: (context, state) => FeatureIntroFlowGate(
          module: HealingDocs(),
          briefParagraph:
              'Healing Mode is private and self-paced. It\'s not therapy, it '
              'doesn\'t diagnose you or your relationship, and your former '
              'partner is never told you\'re using it.',
          launchLabel: 'Enter Healing Mode',
          buildFeature: () => const HealingJourneyScreen(),
        ),
```

- [ ] **Step 5: Write the wiring test**

Create `test/app/routing/feature_intro_route_wiring_test.dart`. This is a narrow, targeted check confirming the two route builders actually construct `FeatureIntroFlowGate` with the right `module`/`buildFeature`, not a full app-router integration test:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/documentations/user_manual/data/healing_docs.dart';
import 'package:attune/core/intro/presentation/widgets/feature_intro_flow_gate.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Dating Mode intro gate shows DatingModeDocs content on first entry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeatureIntroFlowGate(
          module: DatingModeDocs(),
          briefParagraph: 'Test paragraph.',
          launchLabel: 'Continue to Dating Mode',
          buildFeature: () => const Scaffold(body: Text('Dating Dashboard Stub')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dating Mode'), findsOneWidget);
    expect(find.text('Dating Dashboard Stub'), findsNothing);
  });

  testWidgets('Healing Mode intro gate shows HealingDocs content on first entry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeatureIntroFlowGate(
          module: HealingDocs(),
          briefParagraph: 'Test paragraph.',
          launchLabel: 'Enter Healing Mode',
          buildFeature: () => const Scaffold(body: Text('Healing Journey Stub')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Healing Mode'), findsOneWidget);
    expect(find.text('Healing Journey Stub'), findsNothing);
  });
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/app/routing/feature_intro_route_wiring_test.dart`
Expected: PASS, 2/2.

- [ ] **Step 7: Run full regression**

```bash
flutter analyze lib/app/routing/app_router.dart lib/core/intro/
flutter test
```

Expected: 0 new analyzer errors, full suite green.

- [ ] **Step 8: Commit**

```bash
git add lib/app/routing/app_router.dart test/app/routing/feature_intro_route_wiring_test.dart
git commit -m "feat(routing): gate Dating Mode and Healing Mode routes behind first-time intro"
```

---

## Self-Review Notes

- **Spec coverage:** `SeenFeatureIntroStore` (Task 1), `FeatureIntroFlowScreen` + brief-page content (Task 2), `FeatureIntroFlowGate` (Task 3), and the two route-builder swaps (Task 4) together cover every component and entry-point-wiring section of the spec. `DatingConsentScreen` and all pre-existing Healing Mode call sites are explicitly untouched per the Global Constraints, matching the spec's Non-Goals exactly.
- **Deviation surfaced during planning, documented in-line**: the spec's draft assumed a Riverpod provider (`hasSeenFeatureIntroProvider`) would exist for this pattern; checking `QuizProgressStore`'s real usage during planning found no such provider anywhere in the codebase, so this plan uses direct async construction inside `FeatureIntroFlowGate.initState`, matching `attachment_quiz_screen.dart`'s actual convention rather than inventing a new provider-based one.
- **Type consistency**: `FeatureIntroFlowScreen`'s constructor (`module`, `briefParagraph`, `launchLabel`, `onComplete`) is defined in Task 2 and consumed identically by `FeatureIntroFlowGate` in Task 3. `SeenFeatureIntroStore`'s `hasSeenIntro`/`markIntroSeen` signatures from Task 1 are consumed identically in Task 3. `FeatureIntroFlowGate`'s constructor (`module`, `briefParagraph`, `launchLabel`, `buildFeature`) is defined in Task 3 and consumed identically in Task 4's two route builders.
- **Placeholder scan**: no open-ended "handle appropriately" instructions remain. Both `ButtonVariant.outline` (Task 2) and the `app_router.dart` import path for the two doc modules (Task 4) were verified directly against the current codebase during planning rather than left as implementer-time checks.

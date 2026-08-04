# Nested/Related Documentation Modules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user drill from Games' documentation into an individual game's own docs (Truth or Dare, This or That, 36 Questions) and back, via a new "Related" tab shown only where a relation is declared.

**Architecture:** `DocumentationRegistry` gains a static `getRelatedModuleIds(String moduleId)` lookup (empty for every id except `'games'`). `DocumentationTabView` changes from taking pre-extracted `documentation`/`faqs` lists to taking the whole `module`, tracks which module it's currently displaying as local state, and renders a third "Related" tab (with `InfoRowWidget` cards, one per related module) whenever the currently-displayed module has any. Tapping a related card swaps the displayed module in place; a back row appears when a parent is set. Four existing call sites are updated to the new constructor shape.

**Tech Stack:** Flutter, existing `DocumentationModule`/`DocumentationRegistry`/`ManualWidget`/`FAQWidget`/`TabsWithContent`/`InfoRowWidget` system — no new dependencies.

## Global Constraints

- One level only: parent ↔ child. Children (`TruthOrDareDocs`, `ThisOrThatDocs`, `ThirtySixQuestionsDocs`) do not declare relations back to Games or to each other — `getRelatedModuleIds` returns `const []` for every id except `'games'`.
- No `DocumentationModule` interface change. The relation lookup lives entirely in `DocumentationRegistry` (confirmed during design: all 22 modules use `implements DocumentationModule`, which does not inherit default getter bodies — adding a defaulted interface member would require touching every module file, which this plan does not do).
- `DocumentationRegistry`'s real file path is `lib/app/documentations/user_manual/data/manual_documentation_registry.dart` — its own header comment says `lib/core/documentation/documentation_registry.dart`, which is stale and wrong; do not follow it.
- `TabsWithContent` (`lib/home/widgets/tabs_with_content.dart`) already handles a changing tab count safely via its own `didUpdateWidget` (rebuilds `TabController` when `tabs.length` differs) — the `ValueKey(_currentModule.id)` added to `DocumentationTabView`'s `TabsWithContent` is NOT for tab-count safety. It exists solely to reset tab *selection* to index 0 on every module swap, since `TabsWithContent` otherwise preserves `_currentIndex` across same-tab-count updates.
- No changes to the 4 standalone quiz modules (`AttachmentStyleQuizDocs`, `CommunicationStyleQuizDocs`, `ConflictStyleQuizDocs`, `LoveLanguageQuizDocs`) — none have a parent/child relationship to model.
- `TabsWithContent`'s existing `appBarOnPressed`/`appBartext` props render a trailing "Done"-style text button, not a leading back arrow — do not repurpose them for the back-to-parent affordance; a new small custom row handles that instead.

---

### Task 1: `DocumentationRegistry.getRelatedModuleIds`

**Files:**
- Modify: `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`
- Test: `test/app/documentations/documentation_registry_related_modules_test.dart`

**Interfaces:**
- Produces: `DocumentationRegistry.getRelatedModuleIds(String moduleId) → List<String>` — a `static` method, consumed by Task 2.

- [ ] **Step 1: Write the failing test**

Create `test/app/documentations/documentation_registry_related_modules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';

void main() {
  group('DocumentationRegistry.getRelatedModuleIds', () {
    test('returns the 3 games for "games"', () {
      expect(
        DocumentationRegistry.getRelatedModuleIds('games'),
        ['truthOrDare', 'thisOrThat', 'thirtySixQuestions'],
      );
    });

    test('returns empty for a module with no relations', () {
      expect(DocumentationRegistry.getRelatedModuleIds('healing'), isEmpty);
      expect(DocumentationRegistry.getRelatedModuleIds('chat'), isEmpty);
      expect(DocumentationRegistry.getRelatedModuleIds('truthOrDare'), isEmpty);
    });

    test('returns empty for an unknown id, not a throw', () {
      expect(
        () => DocumentationRegistry.getRelatedModuleIds('not_a_real_id'),
        returnsNormally,
      );
      expect(DocumentationRegistry.getRelatedModuleIds('not_a_real_id'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app/documentations/documentation_registry_related_modules_test.dart`
Expected: FAIL — `getRelatedModuleIds` is not defined on `DocumentationRegistry`.

- [ ] **Step 3: Add the method**

Open `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`. Add this method inside `class DocumentationRegistry { ... }`, directly after the `_idMap` field declaration (before `initialize()`):

```dart
  /// IDs of modules related to [moduleId], shown as a "Related" tab in
  /// DocumentationTabView. Empty for every module except the ones
  /// explicitly listed here. One level only: a related module's own
  /// related ids are not consulted (no sibling-to-sibling or
  /// multi-level nesting).
  static List<String> getRelatedModuleIds(String moduleId) {
    switch (moduleId) {
      case 'games':
        return const ['truthOrDare', 'thisOrThat', 'thirtySixQuestions'];
      default:
        return const [];
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app/documentations/documentation_registry_related_modules_test.dart`
Expected: PASS, 3/3.

- [ ] **Step 5: Commit**

```bash
git add lib/app/documentations/user_manual/data/manual_documentation_registry.dart test/app/documentations/documentation_registry_related_modules_test.dart
git commit -m "feat(docs): add DocumentationRegistry.getRelatedModuleIds"
```

---

### Task 2: `DocumentationTabView` — module-driven state, Related tab, back navigation

**Files:**
- Modify: `lib/app/documentations/user_manual/widgets/documentation_tab_view.dart`
- Test: `test/app/documentations/documentation_tab_view_related_test.dart`

**Interfaces:**
- Consumes: `DocumentationRegistry.getRelatedModuleIds` (Task 1), `DocumentationRegistry.getById` (existing), `DocumentationModule` (existing — `id`, `icon`, `getTitle(context)`, `getSubtitle(context)`, `getSections(context)`, `getFAQs(context)`), `ManualWidget`, `FAQWidget`, `InfoRowWidget`, `AppTabItem`, `TabsWithContent` (all existing, unchanged).
- Produces: `DocumentationTabView({required DocumentationModule module, bool showDocumentationFirst = true})` — a **breaking constructor change** from the current `{required List<ManualSection> documentation, required List<FAQModel> faqs, bool showDocumentationFirst = true}`. Task 3 updates all 4 call sites to match.

This task replaces the entire widget file's body. The `documentation`/`faqs` fields go away entirely — every existing call site must move to passing `module` (handled in Task 3, immediately after this task, so the codebase never sits in a broken intermediate state across a commit boundary for longer than this one task).

- [ ] **Step 1: Write the failing test**

Create `test/app/documentations/documentation_tab_view_related_test.dart`. This test uses real, already-registered content (`GamesDocs`/`TruthOrDareDocs`) rather than fakes, since both exist and Task 1's registry method already returns real data for `'games'`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/app/documentations/user_manual/data/games_docs.dart';
import 'package:attune/app/documentations/user_manual/data/truth_or_dare_docs.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/widgets/documentation_tab_view.dart';

void main() {
  setUp(() {
    DocumentationRegistry.initialize();
  });

  Widget buildTestable(module) {
    return MaterialApp(
      home: Scaffold(body: DocumentationTabView(module: module)),
    );
  }

  testWidgets('shows a Related tab for a module with related ids', (tester) async {
    await tester.pumpWidget(buildTestable(GamesDocs()));
    await tester.pumpAndSettle();

    expect(find.text('Related'), findsOneWidget);
  });

  testWidgets('shows no Related tab for a module without related ids', (tester) async {
    await tester.pumpWidget(buildTestable(TruthOrDareDocs()));
    await tester.pumpAndSettle();

    expect(find.text('Related'), findsNothing);
  });

  testWidgets('tapping a related card drills into that module and shows a back row', (tester) async {
    await tester.pumpWidget(buildTestable(GamesDocs()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();

    expect(find.text('Truth or Dare'), findsWidgets);

    await tester.tap(find.text('Truth or Dare').first);
    await tester.pumpAndSettle();

    expect(find.text('Games'), findsOneWidget); // back row shows parent's title
    expect(find.text('Related'), findsNothing); // Truth or Dare has no related tab of its own
  });

  testWidgets('tapping the back row returns to the parent, whose Related tab reappears', (tester) async {
    await tester.pumpWidget(buildTestable(GamesDocs()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Truth or Dare').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();

    expect(find.text('Related'), findsOneWidget);
  });

  testWidgets('drilling into a related module always opens its Documentation tab, even from FAQs', (tester) async {
    await tester.pumpWidget(buildTestable(GamesDocs()));
    await tester.pumpAndSettle();

    // Select the FAQs tab first.
    await tester.tap(find.text('FAQs'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Truth or Dare').first);
    await tester.pumpAndSettle();

    // Truth or Dare's Documentation tab content should be visible, not its FAQ content.
    expect(find.text('How it works'), findsWidgets); // a real ManualSection title in TruthOrDareDocs
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app/documentations/documentation_tab_view_related_test.dart`
Expected: FAIL — `DocumentationTabView` does not yet accept a `module:` parameter.

- [ ] **Step 3: Rewrite the widget**

Replace the full contents of `lib/app/documentations/user_manual/widgets/documentation_tab_view.dart`:

```dart
// lib/features/documentation/presentation/widgets/documentation_tab_view.dart
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/documentations/user_manual/widgets/faq_widget.dart';
import 'package:attune/app/documentations/user_manual/widgets/manual_widget.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

class DocumentationTabView extends StatefulWidget {
  final DocumentationModule module;
  final bool showDocumentationFirst;

  const DocumentationTabView({
    super.key,
    required this.module,
    this.showDocumentationFirst = true,
  });

  @override
  State<DocumentationTabView> createState() => _DocumentationTabViewState();
}

class _DocumentationTabViewState extends State<DocumentationTabView> {
  late DocumentationModule _currentModule;
  DocumentationModule? _parentModule;

  @override
  void initState() {
    super.initState();
    _currentModule = widget.module;
  }

  void _openRelated(DocumentationModule related) {
    setState(() {
      _parentModule = _currentModule;
      _currentModule = related;
    });
  }

  void _backToParent() {
    setState(() {
      _currentModule = _parentModule!;
      _parentModule = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final relatedIds = DocumentationRegistry.getRelatedModuleIds(_currentModule.id);
    final relatedModules = relatedIds
        .map((id) => DocumentationRegistry.getById(id))
        .whereType<DocumentationModule>()
        .toList();

    final tabs = [
      AppTabItem(
        label: 'Documentation',
        icon: Icons.article,
        content: ManualWidget(sections: _currentModule.getSections(context)),
      ),
      AppTabItem(
        label: 'FAQs',
        icon: Icons.help_outline,
        content: FAQWidget(faqs: _currentModule.getFAQs(context)),
      ),
      if (relatedModules.isNotEmpty)
        AppTabItem(
          label: 'Related',
          icon: Icons.apps_outlined,
          content: _RelatedModulesList(
            modules: relatedModules,
            onTap: _openRelated,
          ),
        ),
    ];

    return Column(
      children: [
        if (_parentModule != null)
          _BackToParentRow(
            parentTitle: _parentModule!.getTitle(context),
            onTap: _backToParent,
          ),
        Expanded(
          child: TabsWithContent(
            key: ValueKey(_currentModule.id),
            useNestedScrollMode: true,
            tabs: widget.showDocumentationFirst ? tabs : tabs.reversed.toList(),
            initialIndex: 0,
            scrollable: false,
            showContent: true,
          ),
        ),
      ],
    );
  }
}

class _RelatedModulesList extends StatelessWidget {
  const _RelatedModulesList({required this.modules, required this.onTap});

  final List<DocumentationModule> modules;
  final ValueChanged<DocumentationModule> onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      children: modules.map((module) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.xs.h),
          child: InfoRowWidget(
            title: module.getTitle(context),
            subtitle: module.getSubtitle(context),
            icon: module.icon,
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: IconSizes.md.h,
              color: colorScheme.onBackground.withOpacity(0.3),
            ),
            avatarRadius: 25.h,
            onTap: () => onTap(module),
            showTrailingArrow: true,
          ),
        );
      }).toList(),
    );
  }
}

class _BackToParentRow extends StatelessWidget {
  const _BackToParentRow({required this.parentTitle, required this.onTap});

  final String parentTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.lg.w,
          vertical: Spacing.sm.h,
        ),
        child: Row(
          children: [
            Icon(Icons.arrow_back, size: IconSizes.sm.h, color: colorScheme.primary),
            Gap(Spacing.xs.w),
            Text(
              parentTitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Before finalizing, verify `export_screens.dart` actually re-exports `InfoRowWidget`, `AppTabItem`, `TabsWithContent`, `Spacing`, `IconSizes`, and `Gap` (the original file already imported `attune/core/utils/exports/export_screens.dart` and used `TabsWithContent`/`AppTabItem` without a separate import, so this should hold — but confirm directly by running `flutter analyze` in Step 5 rather than assuming). If any type is not covered by that barrel import, add its direct import instead.

Note before running tests: `DocumentationTabView`'s 4 existing call sites still pass `documentation:`/`faqs:` and will fail to compile against this new constructor. Do not attempt to fix them in this task — Task 3 owns that. This task's own test file (Step 1) is self-contained and does not depend on the 4 call sites compiling, so it can pass on its own even while the rest of the codebase has compile errors elsewhere. Run the test in isolation (Step 4 below), not `flutter analyze` on the whole `lib/` tree (which will show the expected, temporary breakage in the 4 call sites — that's Task 3's job, not a regression in this task).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app/documentations/documentation_tab_view_related_test.dart`
Expected: PASS, 5/5.

Also run `flutter analyze lib/app/documentations/user_manual/widgets/documentation_tab_view.dart` (the single file, not the whole tree) and confirm it's clean — the 4 call-site files elsewhere will show new errors at this point; that's expected and is Task 3's responsibility, not this task's.

- [ ] **Step 5: Commit**

```bash
git add lib/app/documentations/user_manual/widgets/documentation_tab_view.dart test/app/documentations/documentation_tab_view_related_test.dart
git commit -m "feat(docs): DocumentationTabView takes a module, adds Related tab and back navigation"
```

---

### Task 3: Update the 4 `DocumentationTabView` call sites

**Files:**
- Modify: `lib/app/documentations/user_manual/widgets/all_manual_widget.dart`
- Modify: `lib/features/auth/intro/widgets/intro_guide_widget.dart`
- Modify: `lib/features/onboarding/presentation/screens/onboarding_flow.dart`
- Test: none new — this task's correctness is verified by the full suite passing and by the two widget tests already written in Task 2, which exercise `DocumentationTabView` directly

**Interfaces:**
- Consumes: `DocumentationTabView({required DocumentationModule module, bool showDocumentationFirst})` (Task 2).

Each of the 4 call sites currently extracts `documentation:`/`faqs:` from a module already in scope, then passes those two lists. Change each to pass `module:` directly instead — the module variable already exists at every site, so no new data needs to be threaded in.

- [ ] **Step 1: `all_manual_widget.dart`**

In `lib/app/documentations/user_manual/widgets/all_manual_widget.dart`, find:

```dart
                  widget: DocumentationTabView(
                    documentation: module.getSections(context),
                    faqs: module.getFAQs(context),
                    showDocumentationFirst: true,
                  ),
```

Change to:

```dart
                  widget: DocumentationTabView(
                    module: module,
                    showDocumentationFirst: true,
                  ),
```

- [ ] **Step 2: `intro_guide_widget.dart`**

In `lib/features/auth/intro/widgets/intro_guide_widget.dart`, find the equivalent `DocumentationTabView(documentation: module.getSections(context), faqs: module.getFAQs(context), showDocumentationFirst: true)` call (inside the `onTap` of `IntroGuideWidget`, which already has `module` as an instance field). Change to `DocumentationTabView(module: module, showDocumentationFirst: true)`.

- [ ] **Step 3: `onboarding_flow.dart` (2 call sites)**

In `lib/features/onboarding/presentation/screens/onboarding_flow.dart`, there are two separate `DocumentationTabView(documentation: docs.getSections(context), faqs: docs.getFAQs(context), showDocumentationFirst: true)` calls (around lines 138 and 186 as of this plan's writing — re-locate by searching for `DocumentationTabView(` since exact line numbers may have shifted). Both use a local variable named `docs` (the module) already in scope. Change both to `DocumentationTabView(module: docs, showDocumentationFirst: true)`.

- [ ] **Step 4: Run full analyze and full suite**

```bash
flutter analyze lib/
flutter test
```

Expected: 0 new analyzer errors anywhere in `lib/` (the 4 call-site errors from Task 2 should now be gone), full suite green including both new test files from Tasks 1 and 2.

- [ ] **Step 5: Commit**

```bash
git add lib/app/documentations/user_manual/widgets/all_manual_widget.dart lib/features/auth/intro/widgets/intro_guide_widget.dart lib/features/onboarding/presentation/screens/onboarding_flow.dart
git commit -m "fix(docs): update DocumentationTabView call sites to pass module directly"
```

---

## Self-Review Notes

- **Spec coverage:** Task 1 covers the registry-side data model, Task 2 covers the widget's Related tab + drill-down + back navigation + the `ValueKey` tab-reset fix, Task 3 covers all 4 call sites. Every component in the spec's "Components" section maps to a task.
- **Deviation from the spec's own draft code, caught and fixed during plan-writing, not left for the implementer to discover**: the spec's original justification for `ValueKey(_currentModule.id)` claimed it was needed to prevent a crash from a changing tab count. Direct verification of `TabsWithContent`'s `didUpdateWidget` (`lib/home/widgets/tabs_with_content.dart:105-117`) during planning showed this is false — that widget already handles a changing tab count safely on its own. The real, narrower reason (tab *selection* carrying over across a same-tab-count swap, landing a user on the wrong tab) was substituted into both the spec and this plan's Global Constraints and Task 2 Step 3, with a corresponding test (Task 2's 5th test case) that actually exercises the FAQ-tab-carries-over scenario rather than a generic "doesn't crash" check.
- **Type consistency:** `DocumentationTabView`'s constructor (`module`, `showDocumentationFirst`) is defined once in Task 2 and consumed identically by all 3 call-site files in Task 3. `DocumentationRegistry.getRelatedModuleIds(String) → List<String>` from Task 1 is consumed with the exact same signature in Task 2.
- **Placeholder scan:** no "TBD"/"handle appropriately" language. Task 2's note about `export_screens.dart` barrel coverage is a concrete, bounded verification step (run `flutter analyze`, add a direct import only if needed) rather than an open-ended instruction.
- **Sequencing note for whoever executes this plan**: Task 2 intentionally leaves the codebase non-compiling outside its own test file's scope (the 4 call sites break against the new constructor) until Task 3 lands. This is called out explicitly in Task 2 Step 4 so the task reviewer doesn't mistake the 4 call-site errors for a Task 2 regression — they're expected, temporary, and Task 3's explicit responsibility.

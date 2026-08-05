# Nested/Related Documentation Modules — Design

## Problem

`GamesDocs` documents the shared Games hub (entry point, tone system, session lifecycle) and explicitly says in its own header comment that individual games — `TruthOrDareDocs`, `ThisOrThatDocs`, `ThirtySixQuestionsDocs` — "have their own docs elsewhere in this registry with the full play-by-play." All four are registered as flat, independent siblings in `DocumentationRegistry` today, with no structural link between them. A user who opens Games' documentation has no way to reach an individual game's own docs from there — they'd have to back out and find it separately in whatever list surfaced Games in the first place.

## Goal

Let a documentation module declare related/child modules. When viewing a module with related modules, show a way to jump into each related module's own documentation, then back to where you started. Ship this for exactly one real case (Games → Truth or Dare / This or That / 36 Questions) — not a speculative feature for modules that don't need it.

## Non-Goals

- No sibling-to-sibling navigation (Truth or Dare linking to This or That directly). Confirmed during brainstorming: one level only, parent ↔ child.
- No multi-level nesting (a related module's own related modules are not shown/followed).
- No changes to the 4 quiz modules (`AttachmentStyleQuizDocs`, `CommunicationStyleQuizDocs`, `ConflictStyleQuizDocs`, `LoveLanguageQuizDocs`) — checked during brainstorming, none of them have a parent/child relationship to model; they stay flat, independent modules exactly as today.
- No changes to `DocumentationRegistry`'s public API beyond what's needed to look up a module by id (`getById`, which already exists).

## User Flow

1. A user opens Games' documentation (from any of the 4 existing `DocumentationTabView` entry points — Settings' guide list, the chat-locked-screen intro carousel, the auth intro screen, or the onboarding quiz-prompt sheets).
2. `DocumentationTabView` renders as today (Documentation tab, FAQ tab), plus a third tab, **Related**, shown only because `DocumentationRegistry.getRelatedModuleIds('games')` is non-empty. The Related tab lists one `InfoRowWidget` card per related module (Truth or Dare, This or That, 36 Questions), each using that module's own `icon`/`getTitle`/`getSubtitle` — the same visual language `DocumentationList` already uses for the top-level module list.
3. Tapping a related card swaps the same `DocumentationTabView` instance to show that module's own Documentation/FAQ tabs instead (no related tab of its own, since `getRelatedModuleIds` returns empty for every id except `'games'`). A small back row appears above the tab strip reading "← Games" (the parent's title), tappable to swap back.
4. Every other module's `DocumentationTabView` (the other ~21) renders exactly as it does today — two tabs, no related tab, no back row — since `getRelatedModuleIds` returns empty for every id but `'games'`.

## Components

### `DocumentationRegistry.getRelatedModuleIds` (new, registry-side)

**Not a `DocumentationModule` interface change.** Verified during planning: every one of the 22 existing modules declares `class XDocs implements DocumentationModule`, and Dart's `implements` does not inherit a default getter body from the interface it implements — only `extends` or a mixin would, and both require touching every module's class declaration regardless. Since the goal is genuinely zero changes to modules that don't need this feature, the relationship lives in the registry instead.

Add to `DocumentationRegistry` (`lib/app/documentations/user_manual/data/manual_documentation_registry.dart` — note this file's own header comment says `lib/core/documentation/documentation_registry.dart`, which is stale/wrong; the real path was confirmed directly during planning):

```dart
class DocumentationRegistry {
  // ... existing members unchanged ...

  /// IDs of modules related to [moduleId], shown as a "Related" tab in
  /// DocumentationTabView. Empty for every module except the ones
  /// explicitly listed here. One level only: a related module's own
  /// related ids are not consulted (no sibling-to-sibling or
  /// multi-level nesting) — see the design doc's Non-Goals.
  static List<String> getRelatedModuleIds(String moduleId) {
    switch (moduleId) {
      case 'games':
        return const ['truthOrDare', 'thisOrThat', 'thirtySixQuestions'];
      default:
        return const [];
    }
  }
}
```

These three string ids already exist and are already registered (`TruthOrDareDocs.id => 'truthOrDare'`, etc., confirmed in `DocumentationRegistry.initialize()`) — no new registration needed. `DocumentationModule` itself is untouched; no module file changes.

### `DocumentationTabView` (modified)

Currently (`lib/app/documentations/user_manual/widgets/documentation_tab_view.dart`):
```dart
class DocumentationTabView extends StatefulWidget {
  final List<ManualSection> documentation;
  final List<FAQModel> faqs;
  final bool showDocumentationFirst;
  ...
}
```

New signature — takes the module itself, not pre-extracted lists, since the widget now needs to look up related modules and re-derive sections/FAQs when the displayed module changes:

```dart
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
```

Internal state:
```dart
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
```

The `key: ValueKey(_currentModule.id)` on `TabsWithContent` is required for a narrower reason than tab-count safety: `TabsWithContent`'s own `didUpdateWidget` (verified directly in `lib/home/widgets/tabs_with_content.dart:105-117`) already rebuilds its internal `TabController` correctly when `tabs.length` changes between builds, so a differing tab count alone would not crash even without a key. The real problem the key solves is tab *selection* carrying over: without it, a user who drills from Games' FAQ tab (index 1) into Truth or Dare — which also has exactly 2 tabs — would land on Truth or Dare's FAQ tab, not its Documentation tab, because `TabsWithContent` preserves `_currentIndex` across a same-tab-count update. Keying on the module id forces a full remount (fresh `initState`, `_currentIndex` reset to `initialIndex`) whenever the displayed module changes, so every module swap always opens on its own Documentation tab first, consistent with `showDocumentationFirst: true`.

`_RelatedModulesList` and `_BackToParentRow` are small private widgets in the same file:

```dart
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

This mirrors `InfoRowWidget`'s existing visual language (`DocumentationList`'s own card style — icon, title, subtitle, trailing chevron) exactly, so the Related tab's cards look identical to the top-level module list a user already saw before drilling into Games.

### Call site changes (4 files)

Every existing `DocumentationTabView(...)` invocation changes from passing `documentation:`/`faqs:` to passing `module:` directly. All four already have the module in scope at the call site — this is a mechanical signature change, not a logic change:

1. `lib/app/documentations/user_manual/widgets/all_manual_widget.dart:62-66` — `DocumentationTabView(documentation: module.getSections(context), faqs: module.getFAQs(context), showDocumentationFirst: true)` → `DocumentationTabView(module: module, showDocumentationFirst: true)`.
2. `lib/features/auth/intro/widgets/intro_guide_widget.dart:31-35` — same pattern, `module` already in scope (it's the widget's own field).
3. `lib/features/onboarding/presentation/screens/onboarding_flow.dart:138-142` — `docs` (the module) already in scope.
4. `lib/features/onboarding/presentation/screens/onboarding_flow.dart:186-190` — same, `docs` already in scope.

## Data Flow Summary

```
DocumentationTabView(module: GamesDocs())
  -> _currentModule = GamesDocs(), _parentModule = null
  -> tabs: [Documentation, FAQs, Related]  (Related shown: getRelatedModuleIds('games') non-empty)
  -> user taps "Truth or Dare" card in Related tab
  -> _openRelated(TruthOrDareDocs()) -> setState
  -> _currentModule = TruthOrDareDocs(), _parentModule = GamesDocs()
  -> tabs: [Documentation, FAQs]  (no Related: getRelatedModuleIds('truthOrDare') is empty)
  -> back row "← Games" shown (_parentModule != null)
  -> user taps back row
  -> _backToParent() -> setState -> _currentModule = GamesDocs(), _parentModule = null
```

## Testing

- Unit test: `DocumentationRegistry.getRelatedModuleIds('games')` returns the 3 expected ids in order; `getRelatedModuleIds` for every other existing module id (spot-check a handful, e.g. `'healing'`, `'chat'`, one quiz module id) returns an empty list; an unknown/made-up id also returns empty (the `default` branch), not a throw.
- Widget test for `DocumentationTabView`: with `module: GamesDocs()` (real, already-registered content — `getRelatedModuleIds('games')` is non-empty), confirm a 3rd "Related" tab appears; with `module: TruthOrDareDocs()` (or any other real module), confirm only 2 tabs appear and no back row is shown.
- Widget test: tapping a related module's card swaps to that module's Documentation tab content and shows the back row with the parent's title; tapping the back row swaps back to the parent, and the parent's own Related tab reappears (`getRelatedModuleIds` is a pure function of id, so it must still return the same 3 ids after returning, not silently drop to empty).
- Widget test: from Games' FAQ tab (tap to select it first), tap into a related module, and confirm the new module opens on its Documentation tab, not carrying over the FAQ tab selection — this is the specific bug the `ValueKey(_currentModule.id)` addition exists to prevent, so a test that changes tab selection before drilling in is the real regression guard for it, not just a default-state check.
- Regression: run the full suite after the call-site signature change lands, since 4 files change in ways that must still compile and behave identically for every module without related children.

## Open Questions Resolved During Brainstorming

- **Data model**: a new `DocumentationRegistry.getRelatedModuleIds(String moduleId)` static method, not a `DocumentationModule` interface member — verified during planning that Dart's `implements` (the pattern all 22 modules use) does not inherit default getter bodies from the interface, so adding a defaulted member to the abstract class would have required touching every module's class declaration anyway. The registry-side approach achieves genuinely zero changes to modules that don't need this feature.
- **Placement**: a third "Related" tab, shown conditionally, not an always-visible section bolted onto the existing two tabs.
- **Navigation**: an in-place state swap inside the same `DocumentationTabView` instance (no nested `Navigator`, no closing/reopening the bottom sheet), with a lightweight custom back row rather than reusing `TabsWithContent`'s existing `appBarOnPressed` (checked during planning: that prop renders a trailing "Done"-style text button, not a leading back arrow — wrong affordance for this).
- **Depth**: one level only, parent ↔ child. Children do not declare relations back to the parent or to siblings.

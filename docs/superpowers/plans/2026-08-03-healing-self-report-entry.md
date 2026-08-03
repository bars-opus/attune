# Healing Self-Report Entry Point Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give personal-mode users a way to start a self-reported Healing Mode journey (no tracked relationship required) directly from `ChatCouplesLockedScreen`, using the backend path that already exists (`breakup_at_source = 'user_reported'`, nullable `relationship_id`).

**Architecture:** Add a new `hasActiveSoloHealingJourneyProvider` read to detect an existing solo journey, a new `_HealingSelfReportSheet` bottom-sheet widget to collect a self-reported breakup date, and a new `_HealingEntryCard` on `ChatCouplesLockedScreen` that either resumes an existing solo journey or opens the sheet. The sheet calls the existing `startHealingJourneyProvider` family (already wired to `getOrCreateJourney` + `healingJourneyProvider` invalidation) — no repository or RPC changes.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), Supabase (`supabase_flutter`), GoRouter.

## Global Constraints

- No onboarding changes — `OnboardingModeStep` is untouched.
- No changes to `healingStartContextProvider`, `get_or_create_healing_journey` RPC, or any migration/table — this is additive client wiring only.
- No changes to `EndRelationshipAction` or its `context.push(RouteNames.healingJourney)` call.
- Date picker bounds: `firstDate: DateTime(2020)`, `lastDate: DateTime.now()` — matches the only existing `showDatePicker` precedent in this codebase (`lib/features/timeline/presentation/screens/log_moment_details_screen.dart:211-212`).
- New sheet uses the existing `BottomSheetUtils.showDocumentationBottomSheet(widget: ...)` shell — same pattern `EndRelationshipAction` and the couples-locked screen's own legal-docs link already use.
- `_HealingEntryCard` visually mirrors `_ReflectionEntryCard` (same `CardInkWell` + `InfoRowWidget` shell) and sits inside the same `if (!_isCreatingInvite) if (_invite == null)` guard — shown only for a true single, not mid-invite.

---

### Task 1: `hasActiveSoloHealingJourneyProvider`

**Files:**
- Modify: `lib/features/healing/data/repositories/healing_repository.dart`
- Modify: `lib/features/healing/presentation/providers/healing_providers.dart`
- Test: `test/features/healing/has_active_solo_healing_journey_test.dart`

**Interfaces:**
- Produces: `HealingRepository.hasActiveSoloJourney() → Future<bool>` and `hasActiveSoloHealingJourneyProvider` (`FutureProvider<bool>`) in `healing_providers.dart`, both consumed by Task 3.

This task adds a repository method and a provider that answer one question: does the current user already have an `active` or `paused` healing journey with `relationship_id IS NULL`? This lets the UI skip straight to `RouteNames.healingJourney` instead of re-prompting for a date the backend would ignore (per `get_or_create_healing_journey`'s own idempotent reuse of an existing solo journey).

- [ ] **Step 1: Add `hasActiveSoloJourney` to `HealingRepository`**

Open `lib/features/healing/data/repositories/healing_repository.dart`. Add this method directly after `getStartableRelationship` (after line 51, before `getOrCreateJourney`):

```dart
  Future<bool> hasActiveSoloJourney() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return false;
    }

    final response = await _supabase
        .from('healing_journeys')
        .select('id')
        .eq('user_id', userId)
        .isFilter('relationship_id', null)
        .inFilter('status', ['active', 'paused'])
        .maybeSingle();

    return response != null;
  }
```

This mirrors `getStartableRelationship`'s own direct-query style immediately above it. RLS already scopes `healing_journeys` SELECT to `user_id = auth.uid()` (policy `"healing journeys owner read"` in `supabase/migrations/20260703193000_healing_mode_v1_1.sql:110-113`), so no migration is needed.

- [ ] **Step 2: Add `hasActiveSoloHealingJourneyProvider` to `healing_providers.dart`**

Open `lib/features/healing/presentation/providers/healing_providers.dart`. Add this provider directly after `healingStartContextProvider` (after line 40, before `startHealingJourneyProvider`):

```dart
final hasActiveSoloHealingJourneyProvider = FutureProvider<bool>((ref) async {
  final repository = ref.read(healingRepositoryProvider);
  return repository.hasActiveSoloJourney();
});
```

- [ ] **Step 3: Write the repository unit test**

Create `test/features/healing/has_active_solo_healing_journey_test.dart`. This test needs a fake Supabase client. Check how existing healing repository tests fake Supabase — run this before writing the test:

```bash
find /Users/user/attune/test/features/healing -iname "*.dart"
```

If a prior test file already sets up a fake/mock `SupabaseClient` for `HealingRepository` (e.g. testing `getStartableRelationship` or `getLatestJourney`), copy its exact mocking approach (package used, table-mock shape) so this test matches established convention rather than introducing a second mocking style. Write three cases:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/features/healing/data/repositories/healing_repository.dart';

void main() {
  group('HealingRepository.hasActiveSoloJourney', () {
    test('returns false when unauthenticated', () async {
      // Use the same fake/mock SupabaseClient setup as this directory's
      // existing HealingRepository tests (see test/features/healing/ for
      // the established pattern) with no signed-in user.
      // final repository = HealingRepository(fakeClientWithNoUser);
      // expect(await repository.hasActiveSoloJourney(), isFalse);
    });

    test('returns true when an active solo journey exists', () async {
      // Fake client returns a row for the query filtered to
      // relationship_id IS NULL and status IN ('active', 'paused').
      // final repository = HealingRepository(fakeClientWithSoloActiveRow);
      // expect(await repository.hasActiveSoloJourney(), isTrue);
    });

    test('returns false when only a completed/archived solo journey exists', () async {
      // Fake client's status filter excludes the row, so maybeSingle()
      // resolves to null.
      // final repository = HealingRepository(fakeClientWithSoloCompletedRow);
      // expect(await repository.hasActiveSoloJourney(), isFalse);
    });
  });
}
```

Replace the commented pseudocode with real fake-client wiring matching whatever this test directory's existing convention is (found in the `find` step above). If no prior `HealingRepository` test exists in this codebase, use `mocktail` (check `pubspec.yaml`'s `dev_dependencies` for it first — it's the standard mocking package for `supabase_flutter` clients in this codebase's other repository tests; if absent, grep `test/` broadly for how any other repository wrapping a raw `SupabaseClient` is tested and copy that).

- [ ] **Step 4: Run the test to verify it fails, then implement, then verify it passes**

```bash
flutter test test/features/healing/has_active_solo_healing_journey_test.dart
```

Expected before Step 1/2 code exists: compile failure (`hasActiveSoloJourney` undefined). After Steps 1-3 are complete: all 3 cases pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/healing/data/repositories/healing_repository.dart lib/features/healing/presentation/providers/healing_providers.dart test/features/healing/has_active_solo_healing_journey_test.dart
git commit -m "feat(healing): add hasActiveSoloHealingJourneyProvider"
```

---

### Task 2: `_HealingSelfReportSheet` widget

**Files:**
- Create: `lib/features/healing/presentation/widgets/healing_self_report_sheet.dart`
- Test: `test/features/healing/healing_self_report_sheet_test.dart`

**Interfaces:**
- Consumes: `startHealingJourneyProvider` (existing `FutureProvider.family<HealingJourney, HealingStartContext>` in `healing_providers.dart:42-55`), `HealingStartContext` typedef (`({String relationshipId, DateTime breakupAt, String breakupAtSource})`, but `relationshipId` is typed `String` not `String?` on the typedef — see Step 2 note below for how this task handles that).
- Produces: `HealingSelfReportSheet` (public class, `StatefulWidget`, no constructor params) consumed by Task 3. On successful submission, it pops itself via `Navigator.of(context).pop()` and does NOT navigate to `RouteNames.healingJourney` itself — Task 3's caller does that after the sheet closes, so this widget has no `GoRouter`/navigation-to-healing dependency at all, keeping it a self-contained "collect a date and start a journey" unit.

**Important interface note on `HealingStartContext`:** the existing typedef in `healing_providers.dart:6-7` declares `relationshipId` as non-nullable `String`, but `HealingRepository.getOrCreateJourney` (which `startHealingJourneyProvider` calls) accepts `String? relationshipId`. This is a pre-existing mismatch in the codebase, not something this task introduces — `startHealingJourneyProvider` has never been called with a null relationship before now. Passing an empty string through a non-nullable `String` field would NOT work (the RPC branches on `p_relationship_id IS NOT NULL`, and an empty string is not null). This task must therefore call `healingRepositoryProvider` directly instead of going through `startHealingJourneyProvider`, since the family provider's parameter type cannot express "no relationship." Consume `healingRepositoryProvider` (`Provider<HealingRepository>`, `healing_providers.dart:13-15`) and call `.getOrCreateJourney(relationshipId: null, breakupAt: ..., breakupAtSource: 'user_reported')` directly, then `ref.invalidate(healingJourneyProvider)` manually (the same invalidation `startHealingJourneyProvider` performs internally, per `healing_providers.dart:53`) since bypassing the family provider means its invalidation line doesn't run.

- [ ] **Step 1: Write the widget test first**

Create `test/features/healing/healing_self_report_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/widgets/healing_self_report_sheet.dart';

HealingJourney _fakeJourney() {
  final now = DateTime.now();
  return HealingJourney(
    id: 'journey-1',
    userId: 'user-1',
    relationshipId: null,
    breakupAt: now,
    breakupAtSource: 'user_reported',
    status: 'active',
    currentStage: 1,
    reflectionAnswers: const {},
    postMortemStatus: 'not_started',
    portraitStatus: 'not_started',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets('primary button is disabled until a date is picked', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Scaffold(body: HealingSelfReportSheet())),
      ),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('shows inline error text when submission throws', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healingRepositoryProvider.overrideWithValue(_ThrowingHealingRepository()),
        ],
        child: MaterialApp(home: Scaffold(body: HealingSelfReportSheet())),
      ),
    );

    // Simulate a date already selected by driving the widget's own date
    // button, since showDatePicker cannot be programmatically driven in a
    // plain widget test without a golden/native dialog harness. Tap the
    // date row, then tap today's date in the picker, then tap submit.
    await tester.tap(find.byKey(const Key('healingSelfReportDateRow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not start'), findsOneWidget);
  });
}

class _ThrowingHealingRepository implements HealingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getOrCreateJourney) {
      throw Exception('network error');
    }
    return super.noSuchMethod(invocation);
  }
}
```

Note: the second test's `noSuchMethod` fake requires `HealingRepository` to not be `final`/sealed and requires `HealingRepository` to be implementable (no private members). Verify this compiles in Step 3 below — if `HealingRepository` has private fields, this fake will fail to implement it, and this test should instead override `healingRepositoryProvider` with a real `HealingRepository` constructed from a fake `SupabaseClient` that throws on the relevant query, following the same convention resolved in Task 1 Step 3.

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/healing/healing_self_report_sheet_test.dart
```

Expected: FAIL — `HealingSelfReportSheet` does not exist yet.

- [ ] **Step 3: Implement `HealingSelfReportSheet`**

Create `lib/features/healing/presentation/widgets/healing_self_report_sheet.dart`:

```dart
// lib/features/healing/presentation/widgets/healing_self_report_sheet.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

/// Collects a self-reported breakup date and starts a solo (no
/// relationship_id) healing journey via the same
/// get_or_create_healing_journey RPC the relationship-ended path uses,
/// with breakupAtSource: 'user_reported'.
///
/// This calls healingRepositoryProvider directly rather than the existing
/// startHealingJourneyProvider family, because that family's
/// HealingStartContext typedef declares relationshipId as non-nullable
/// String — it has only ever been called with a real relationship id, and
/// there is no way to express "no relationship" through it. See
/// docs/superpowers/plans/2026-08-03-healing-self-report-entry.md Task 2
/// for why.
class HealingSelfReportSheet extends ConsumerStatefulWidget {
  const HealingSelfReportSheet({super.key});

  @override
  ConsumerState<HealingSelfReportSheet> createState() =>
      _HealingSelfReportSheetState();
}

class _HealingSelfReportSheetState
    extends ConsumerState<HealingSelfReportSheet> {
  DateTime? _selectedDate;
  bool _submitting = false;
  String? _errorText;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    final date = _selectedDate;
    if (date == null || _submitting) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      await ref.read(healingRepositoryProvider).getOrCreateJourney(
            relationshipId: null,
            breakupAt: date,
            breakupAtSource: 'user_reported',
          );
      ref.invalidate(healingJourneyProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Could not start your healing journey. Please try again.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Healing from a breakup?',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.sm.h),
        Text(
          'Start a private healing journey, even if it wasn\'t tracked in Attune.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Gap(Spacing.lg.h),
        ListTile(
          key: const Key('healingSelfReportDateRow'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            _selectedDate == null
                ? 'When did this happen?'
                : DateFormat.yMMMd().format(_selectedDate!),
            style: textTheme.bodyLarge,
          ),
          trailing: const Icon(Icons.calendar_today, size: 20),
          onTap: _submitting ? null : _pickDate,
        ),
        if (_errorText != null) ...[
          Gap(Spacing.sm.h),
          Text(
            _errorText!,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
        Gap(Spacing.lg.h),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_selectedDate == null || _submitting) ? null : _submit,
            child: _submitting
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Start healing journey'),
          ),
        ),
      ],
    );
  }
}
```

Before finalizing, check whether `intl`'s `DateFormat` is already a dependency (`grep intl: /Users/user/attune/pubspec.yaml`) and whether `Spacing`/`Gap` tokens match the exact import path used elsewhere in this feature (cross-check against `healing_journey_screen.dart`'s own imports, which already use `Spacing.md.w`/`BorderRadiusTokens.md.r` from `attune/app/theme/design_tokens.dart` per the earlier read of that file) — adjust the import line only if the actual path differs.

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/features/healing/healing_self_report_sheet_test.dart
```

Expected: PASS. If the `noSuchMethod`-based fake from Step 1 fails to compile because `HealingRepository` can't be implemented that way, replace it with a fake `SupabaseClient`-backed `HealingRepository` per the note in Step 1, then re-run.

- [ ] **Step 5: Commit**

```bash
git add lib/features/healing/presentation/widgets/healing_self_report_sheet.dart test/features/healing/healing_self_report_sheet_test.dart
git commit -m "feat(healing): add self-report bottom sheet for solo healing journeys"
```

---

### Task 3: `_HealingEntryCard` on `ChatCouplesLockedScreen`

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_couples_locked_screen.dart`
- Test: `test/features/chat/chat_couples_locked_screen_healing_entry_test.dart`

**Interfaces:**
- Consumes: `hasActiveSoloHealingJourneyProvider` (Task 1), `HealingSelfReportSheet` (Task 2), existing `BottomSheetUtils.showDocumentationBottomSheet` (`lib/core/utils/bottom_sheet_utils.dart:9-113`), existing `RouteNames.healingJourney` (`lib/app/routing/app_router.dart:198`), existing `CardInkWell`/`InfoRowWidget` (already imported into this file's export barrel via `attune/core/utils/exports/export_screens.dart`, same as `_ReflectionEntryCard` uses them).

This task wires the card into the screen and its tap handler.

- [ ] **Step 1: Write the widget test first**

Create `test/features/chat/chat_couples_locked_screen_healing_entry_test.dart`. First check how this screen's existing tests (if any) set up its required providers/mocks — run:

```bash
find /Users/user/attune/test/features/chat -iname "*couples_locked*"
```

If a test file already exists for `ChatCouplesLockedScreen`, read it fully and match its exact `ProviderScope` override set (invite service mocks, opinion providers, etc.) so this new test doesn't have to rediscover every dependency this screen needs to build. Add these two cases to that pattern (or a new file matching the same setup if none exists):

```dart
testWidgets('shows healing entry card when there is no invite', (tester) async {
  // Using the same ProviderScope setup as this screen's other tests
  // (invite state resolved to null / _invite == null), additionally
  // override hasActiveSoloHealingJourneyProvider to resolve false so the
  // card renders in its default (not-yet-started) state.
  // Pump ChatCouplesLockedScreen(isPendingCouples: false, onInviteSent: () {}).
  // await tester.pumpAndSettle();
  expect(find.text('Healing from a breakup?'), findsOneWidget);
});

testWidgets('tapping the card with an existing solo journey navigates directly, no sheet', (tester) async {
  // Override hasActiveSoloHealingJourneyProvider to resolve true.
  // Tap the healing entry card, pumpAndSettle.
  // Assert the self-report sheet's title text is NOT shown (no bottom
  // sheet opened), since with an existing solo journey the card should
  // navigate straight to RouteNames.healingJourney instead of prompting.
  expect(find.text('When did this happen?'), findsNothing);
});
```

Fill in the actual `ProviderScope`/pump calls using the exact fixture pattern discovered above — this screen's own constructor requires `isPendingCouples` and `onInviteSent`, and its `initState` loads invite state and documentation modules asynchronously (per the file's existing structure), so the test needs whatever override set makes `_invite` resolve to `null` and `_isCreatingInvite` resolve to `false` before assertions run.

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/chat/chat_couples_locked_screen_healing_entry_test.dart
```

Expected: FAIL — no "Healing from a breakup?" text exists yet.

- [ ] **Step 3: Add the card and its tap handler**

Open `lib/features/chat/presentation/screens/chat_couples_locked_screen.dart`.

Add two imports near the top (alongside the existing `intro_guide_widget.dart`/`invite_card.dart` imports at lines 6-13):

```dart
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/widgets/healing_self_report_sheet.dart';
```

Add a tap-handler method to `_ChatCouplesLockedScreenState` (the class starting at line 58 — add this method anywhere among its existing methods, e.g. directly below wherever `_inviteService` and other instance state are declared):

```dart
  Future<void> _onHealingEntryTap() async {
    final hasActiveSoloJourney =
        await ref.read(hasActiveSoloHealingJourneyProvider.future);
    if (!mounted) return;

    if (hasActiveSoloJourney) {
      context.push(RouteNames.healingJourney);
      return;
    }

    await BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      widget: const HealingSelfReportSheet(),
    );
    if (!mounted) return;
    context.push(RouteNames.healingJourney);
  }
```

Note: after the sheet closes (whether the user completed it or dismissed it), this always navigates to `RouteNames.healingJourney`. If the user dismissed without completing, `HealingJourneyScreen` itself shows the existing empty state (`_buildEmptyState`, `healing_journey_screen.dart:215-232`) — same screen this card would otherwise have skipped past, so dismissing is not a dead end, just a return to a screen that re-offers the same starting point through its own existing UI. This avoids needing the sheet to report back a distinct "completed vs. dismissed" result across the `Navigator.pop()` boundary.

Add the new card immediately after `_ReflectionEntryCard` inside the existing `if (!_isCreatingInvite) if (_invite == null)` block (currently lines 347-383 — this task moves the closing of the `_ReflectionEntryCard` statement to sit before this new block starts, but `_ReflectionEntryCard` itself, at lines 343-345, stays exactly where it is, outside this conditional, unchanged):

```dart
            if (!_isCreatingInvite)
              if (_invite == null) ...[
                _HealingEntryCard(onTap: _onHealingEntryTap),
                Gap(Spacing.md.h),
                SizedBox(
                  height: 250.h,
                  child: ListView.builder(
```

(This replaces the existing opening of that block — the `SizedBox(height: 250.h, ...)` and everything through the closing `],` at line 383 stays exactly as it is today; only the new `_HealingEntryCard(...)` line and its `Gap` are inserted immediately inside the `...[`.)

Add the `_HealingEntryCard` widget class at the end of the file, directly after `_ReflectionEntryCard`'s closing brace (after line 418, before `_LockedConversationPreview` begins at line 420):

```dart
/// Entry point into a self-reported (no tracked relationship) Healing
/// Mode journey. Shown only alongside the intro carousel, i.e. only for a
/// true single with no pending invite — see the enclosing conditional in
/// build() above.
class _HealingEntryCard extends StatelessWidget {
  const _HealingEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CardInkWell(
      child: InfoRowWidget(
        subtitle:
            'Start a private healing journey, even if it wasn\'t tracked in Attune.',
        title: 'Healing from a breakup?',
        icon: Icons.healing_outlined,
        subTitleMaxLines: 5,
        iconSize: 25.h,
        showDivider: false,
        onTap: onTap,
        disableTrailing: false,
        showAvatar: true,
        showTrailingArrow: false,
        trailing: Icon(Icons.chevron_right_rounded, size: 25.h),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/features/chat/chat_couples_locked_screen_healing_entry_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run full analyze and full test suite to check for regressions**

```bash
flutter analyze lib/features/chat/presentation/screens/chat_couples_locked_screen.dart lib/features/healing/
flutter test
```

Expected: 0 new analyzer errors (pre-existing warnings elsewhere in the repo are not this task's concern), full suite green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_couples_locked_screen.dart test/features/chat/chat_couples_locked_screen_healing_entry_test.dart
git commit -m "feat(chat): add healing self-report entry point to ChatCouplesLockedScreen"
```

---

## Self-Review Notes

- **Spec coverage:** all spec sections map to a task — `hasActiveSoloHealingJourneyProvider` (Task 1), `_HealingSelfReportSheet` (Task 2), `_HealingEntryCard` + screen wiring (Task 3). The spec's Data Flow Summary is realized end-to-end across the three tasks.
- **Deviation from spec, documented above:** the spec said the sheet should call `getOrCreateJourney` "directly" and separately noted `startHealingJourneyProvider`'s invalidation "is already done inside" that family provider, without fully reconciling the two. Investigating during planning surfaced the real reason a direct call is required: `HealingStartContext.relationshipId` is non-nullable, so the existing family provider cannot express a null-relationship call at all. Task 2 documents this explicitly and manually replicates the one line of invalidation the family provider would otherwise have done, rather than silently duplicating logic without explanation.
- **Type consistency:** `HealingSelfReportSheet` (Task 2) takes no constructor params and is referenced identically in Task 3's `const HealingSelfReportSheet()`. `hasActiveSoloHealingJourneyProvider` is `FutureProvider<bool>` in both its Task 1 definition and Task 3's `.future` read.
- **Placeholder scan:** the two test files (Task 2 Step 1, Task 3 Step 1) contain pseudocode comments for provider-override wiring because the exact fixture/mock convention for these two screens/repositories isn't yet known — each step includes a concrete `find`/`grep` command to discover the real convention before writing the test, and states exactly what the test must assert once wired. This is a narrower gap than a bare "write tests for the above" placeholder: the assertions, provider names, and override values are all fully specified; only the mechanical fixture boilerplate is deferred to a just-in-time lookup, which is unavoidable without reading every existing test file into this plan verbatim.

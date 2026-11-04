// Spec 1 W7a (§3.6 X1, §3.10 Healing, §5.2, §5.4): where Support resources
// v2 is reached from. X1's "Support for young people" opens the youth view
// for this phone's country; the Healing row asks "A breakup" or "Someone I
// love died" (grief support, with the journal); Settings -> Support has
// "Find support"; the route takes ?focus=; the manual's passage shows only
// with the flag. With support_resources_v2 off, each is exactly as before.
//   flutter test --update-goldens test/features/safety/w7/support_hooks_test.dart
import 'dart:io';

import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/core/widgets/circular_documentation_container.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/me/presentation/widgets/healing_choice_sheet.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/screens/report_child_concern_screen.dart';
import 'package:attune/features/safety/presentation/screens/support_resources_v2_screen.dart';
import 'package:attune/features/settings/data/settings_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../helpers/flow_harness.dart';

Future<FlowHarness> _space(WidgetTester tester, {required bool v2}) =>
    pumpFlowScreen(
      tester,
      () => const Scaffold(body: YourSpaceSection()),
      overrides: [
        supportResourcesV2Provider.overrideWithValue(v2),
        // An active journey: "A breakup" goes straight to it, as today.
        hasActiveSoloHealingJourneyProvider.overrideWith((ref) async => true),
      ],
    );

/// Records what was opened; answers yes to canLaunch (X1's flag-off path
/// is UrlLauncherUtils, which asks first).
class _FakeLauncher extends UrlLauncherPlatform {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  testWidgets('Healing, flag on: asked first; a loss opens grief support', (
    tester,
  ) async {
    await _space(tester, v2: true);
    await tester.tap(find.text('Healing'));
    await tester.pumpAndSettle();
    expect(find.text('What happened?'), findsOneWidget);
    expect(find.text('A breakup'), findsOneWidget);
    await tester.tap(find.text('Someone I love died'));
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources?focus=grief'), findsOneWidget);
  });

  testWidgets('Healing, flag on: a breakup opens Healing as before', (
    tester,
  ) async {
    await _space(tester, v2: true);
    await tester.tap(find.text('Healing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A breakup'));
    await tester.pumpAndSettle();
    expect(find.text('at /healingJourney'), findsOneWidget);
  });

  testWidgets('Healing, flag off: no question, Healing as before', (
    tester,
  ) async {
    await _space(tester, v2: false);
    await tester.tap(find.text('Healing'));
    await tester.pumpAndSettle();
    expect(find.text('What happened?'), findsNothing);
    expect(find.text('at /healingJourney'), findsOneWidget);
  });

  testWidgets('the Healing question: guidelines and goldens', (tester) async {
    await pumpFlowScreen(
      tester,
      () => const Scaffold(body: HealingChoiceSheet()),
    );
    await expectFlowGuidelines(tester);
    await expectFlowGoldens(
      tester,
      'healing_choice',
      () => const Scaffold(body: HealingChoiceSheet()),
    );
  });

  testWidgets('X1, flag on: the youth view for this country', (tester) async {
    await pumpFlowScreen(
      tester,
      () => const UnderAgeStopScreen(),
      overrides: [supportResourcesV2Provider.overrideWithValue(true)],
    );
    await tester.tap(find.text('Support for young people'));
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources?focus=youth'), findsOneWidget);
  });

  // Batch 3 review I-1: what ships until the W7a gate clears.
  testWidgets('X1, flag off: the directory, never the Support screen', (
    tester,
  ) async {
    final fake = _FakeLauncher();
    final original = UrlLauncherPlatform.instance;
    addTearDown(() => UrlLauncherPlatform.instance = original);
    UrlLauncherPlatform.instance = fake;
    await pumpFlowScreen(
      tester,
      () => const UnderAgeStopScreen(),
      overrides: [supportResourcesV2Provider.overrideWithValue(false)],
    );
    await tester.tap(find.text('Support for young people'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/safety-resources'), findsNothing);
    expect(fake.launched, ['https://findahelpline.com']);
  });

  test('X1, flag off: the international directory, as before W7', () {
    expect(UnderAgeStopScreen.youthSupportUrl, 'https://findahelpline.com');
    expect(
      UnderAgeStopScreen.youthSupportLocation,
      '/safety-resources?focus=youth',
    );
  });

  test('the route takes ?focus= and nothing else', () {
    expect(SupportFocus.parse('grief'), SupportFocus.grief);
    expect(SupportFocus.parse('youth'), SupportFocus.youth);
    expect(SupportFocus.parse('dv'), isNull);
    expect(SupportFocus.parse(null), isNull);
    expect(griefSupportLocation, '/safety-resources?focus=grief');
    final router = File('lib/app/routing/app_router.dart').readAsStringSync();
    expect(
      router,
      contains("focus: SupportFocus.parse(state.uri.queryParameters['focus'])"),
    );
  });

  testWidgets('Settings -> Support: Find support first, only when given', (
    tester,
  ) async {
    late List<String> on;
    late List<String> off;
    await pumpFlowScreen(
      tester,
      () => Builder(
        builder: (context) {
          List<String> support(List sections) => [
            for (final s in sections)
              if (s.id == 'support')
                for (final i in s.items) i.id as String,
          ];
          final report = childReportSetting(
            context,
            id: 'child_report_support',
            order: 0,
          );
          on = support(
            SettingsDataSource.getSettingsSections(
              context,
              'me',
              childReportSupport: report,
              supportResources: supportResourcesSetting(context),
            ),
          );
          off = support(
            SettingsDataSource.getSettingsSections(
              context,
              'me',
              childReportSupport: report,
            ),
          );
          return const SizedBox();
        },
      ),
    );
    expect(on.first, 'support_resources');
    expect(on[1], 'child_report_support');
    expect(on.skip(1), off);
    expect(off, isNot(contains('support_resources')));
  });

  testWidgets('the manual says "Help for where you are" only with the flag', (
    tester,
  ) async {
    DocumentationRegistry.initialize();
    Future<String> text(Set<String> flags) async {
      late BuildContext context;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentationFlagsProvider.overrideWith((ref) async => flags),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (c, ref, _) {
                ref.watch(documentationFlagsProvider);
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final module = DocumentationRegistry.getById('safety')!;
      return [
        for (final s in module.getSections(context))
          for (final c in s.contents) '${c.title} ${c.content}',
      ].join('\n');
    }

    expect(await text(const {}), isNot(contains('Help for where you are')));
    final on = await text(const {'support_resources_v2'});
    expect(on, contains('Help for where you are'));
    // Batch 3 review M-3: emergency lines that aren't the police carry no
    // tag; every other line that isn't the police does. Final review M-7:
    // worded so it can't read as "alternate lines".
    expect(
      on,
      contains(
        'Apart from emergency numbers, help that isn\'t the police is marked '
        '"Not the police".',
      ),
    );
    expect(on, isNot(contains('Every other line')));
  });

  // W7 ruling PF-M1: the question is never animated (§2.2), and keeps the
  // app's sheet chrome (the drag handle, the rounded top, the surface).
  testWidgets('Healing, flag on: the question is whole in its first frame', (
    tester,
  ) async {
    await _space(tester, v2: true);
    await tester.tap(find.text('Healing'));
    await tester.pump();
    final sheet = find.byType(HealingChoiceSheet);
    expect(find.text('What happened?').hitTestable(), findsOneWidget);
    expect(find.text('Someone I love died').hitTestable(), findsOneWidget);
    final first = tester.getRect(sheet);
    expect(first.top, greaterThanOrEqualTo(0));
    expect(first.bottom, lessThanOrEqualTo(844));
    expect(find.byKey(const ValueKey('healing_choice_handle')), findsOneWidget);
    expect(
      find.ancestor(
        of: sheet,
        matching: find.byType(CircularDocumentationContainer),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet), first, reason: 'nothing moved after');
    // Batch 3 review M-4: the presented sheet, chrome included.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/healing_choice_presented.png'),
    );
  });

  // Batch 3 review M-2: the Healing sheet's handle is a copy of
  // BottomSheetUtils' private one; the two stay the same size, colour and
  // shape.
  test('the Healing handle matches every other sheet\'s', () {
    final shared =
        File('lib/core/utils/bottom_sheet_utils.dart').readAsStringSync();
    final healing =
        File(
          'lib/features/me/presentation/widgets/healing_choice_sheet.dart',
        ).readAsStringSync();
    String handle(String source) {
      final start = source.indexOf('class _DragHandle');
      expect(start, isNot(-1));
      return source.substring(start);
    }

    for (final part in [
      'padding: EdgeInsets.symmetric(vertical: 8.h),',
      'width: 40.w,',
      'height: 4.h,',
      'color: colorScheme.onSurface.withValues(alpha: 0.3),',
      'borderRadius: BorderRadius.circular(2.r),',
    ]) {
      expect(handle(shared), contains(part), reason: 'BottomSheetUtils');
      expect(handle(healing), contains(part), reason: 'HealingChoiceSheet');
    }
  });
}

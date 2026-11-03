// Spec 1 W5 (§3.8, §5.2): where About us is entered, only with
// couple_profile on: R3's card (the draft, the partner named), Settings ->
// Your relationship (the shared profile after linking, the draft while an
// invite waits, nothing otherwise), and the anniversary reminder's sheet
// ("This reminder follows About us" -> AU6) for that one reminder only.
// Batch 5: the M-2 card text ("{name} sees your answers after joining.")
// and its "your partner" fallback; preflight F-5 (offline, the reminder's
// probe is bounded and the offline state is shown, never a 15 s stall).
import 'dart:async';
import 'dart:io';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/couple_profile/presentation/widgets/about_us_card.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-entry';

List<Override> _overrides(
  FakeCoupleProfileServer server, {
  required bool on,
}) => [
  coupleProfileEnabledProvider.overrideWithValue(on),
  coupleProfileRpcProvider.overrideWithValue(server.rpc),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
  togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
];

/// Builds Settings' About us row and shows a button that taps it.
class _SettingsProbe extends ConsumerWidget {
  const _SettingsProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsConfig? row = aboutUsSetting(context, ref);
    return Scaffold(
      body: Center(
        child:
            row == null
                ? const Text('no row')
                : TextButton(onPressed: row.onTap, child: Text(row.title)),
      ),
    );
  }
}

class _ReminderProbe extends StatelessWidget {
  const _ReminderProbe(this.reminderId, {this.type = 'anniversary'});

  final String reminderId;
  final String type;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder:
          (context) => TextButton(
            onPressed: () async {
              final shown = await showAboutUsReminderLink(
                context,
                reminderId: reminderId,
                relationshipId: 'r1',
                reminderType: type,
                title: 'Anniversary',
              );
              if (!shown && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('the edit form')));
              }
            },
            child: const Text('open reminder'),
          ),
    ),
  );
}

Future<void> _setLink(WidgetTester tester, String link, {String? id}) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  await container
      .read(homeStateProvider(_uid).notifier)
      .apply(
        HomeState.fromJson(
          homeJson(path: 'relationship', link: link, relationshipId: id),
        ),
      );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'R3\'s card: only with couple_profile, the partner named, the draft',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => const Scaffold(body: AboutUsCard(partnerName: 'Ama')),
        overrides: _overrides(FakeCoupleProfileServer(), on: false),
      );
      expect(find.text('About us'), findsNothing);

      await pumpFlowScreen(
        tester,
        () => const Scaffold(body: AboutUsCard(partnerName: 'Ama')),
        overrides: _overrides(FakeCoupleProfileServer(), on: true),
      );
      expect(find.text('About us'), findsOneWidget);
      expect(
        find.text(
          'A few easy questions about you two. Skip any of them. Ama sees your answers after joining.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('About us'));
      await tester.pumpAndSettle();
      expect(find.text('at /about-us/draft'), findsOneWidget);

      // Batch-4 re-review N-2: the fallback, exactly.
      await pumpFlowScreen(
        tester,
        () => const Scaffold(body: AboutUsCard()),
        overrides: _overrides(FakeCoupleProfileServer(), on: true),
      );
      expect(
        find.text(
          'A few easy questions about you two. Skip any of them. Your partner sees your answers after joining.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Settings: shared after linking, the draft while pending, else none',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => const _SettingsProbe(),
        overrides: _overrides(FakeCoupleProfileServer(), on: true),
      );
      expect(find.text('no row'), findsOneWidget, reason: 'nothing known yet');
      await _setLink(tester, 'none');
      expect(
        find.text('no row'),
        findsOneWidget,
        reason: 'never before an invite',
      );
      await _setLink(tester, 'linked', id: 'r1');
      await tester.tap(find.text('About us'));
      await tester.pumpAndSettle();
      expect(find.text('at /about-us/r1'), findsOneWidget);

      await pumpFlowScreen(
        tester,
        () => const _SettingsProbe(),
        overrides: _overrides(FakeCoupleProfileServer(), on: true),
      );
      await _setLink(tester, 'pending', id: 'r-pending');
      await tester.tap(find.text('About us'));
      await tester.pumpAndSettle();
      expect(find.text('at /about-us/draft'), findsOneWidget);

      await pumpFlowScreen(
        tester,
        () => const _SettingsProbe(),
        overrides: _overrides(FakeCoupleProfileServer(), on: false),
      );
      await _setLink(tester, 'linked', id: 'r1');
      expect(find.text('no row'), findsOneWidget, reason: 'couple_profile off');
    },
  );

  testWidgets(
    'the anniversary reminder follows About us; others open as before',
    (tester) async {
      final server = FakeCoupleProfileServer(
        profiles: {
          'r1': aboutUsJson(
            togetherSince: '2016-03-12',
            precision: 'day',
            anniversary: 'together_since',
            reminderId: 'rem-about-us',
          ),
        },
      );
      await pumpFlowScreen(
        tester,
        () => const _ReminderProbe('rem-about-us'),
        overrides: _overrides(server, on: true),
      );
      await tester.tap(find.text('open reminder'));
      await tester.pumpAndSettle();
      expect(find.text('This reminder follows About us'), findsOneWidget);
      await tester.tap(find.text('Change in About us'));
      await tester.pumpAndSettle();
      expect(find.text('Remember your anniversary?'), findsOneWidget);

      await pumpFlowScreen(
        tester,
        () => const _ReminderProbe('rem-other'),
        overrides: _overrides(server, on: true),
      );
      await tester.tap(find.text('open reminder'));
      await tester.pumpAndSettle();
      expect(find.text('the edit form'), findsOneWidget);

      final calls = server.calls.length;
      await pumpFlowScreen(
        tester,
        () => const _ReminderProbe('rem-about-us', type: 'birthday'),
        overrides: _overrides(server, on: true),
      );
      await tester.tap(find.text('open reminder'));
      await tester.pumpAndSettle();
      expect(find.text('the edit form'), findsOneWidget);
      expect(server.calls.length, calls, reason: 'a birthday asks nothing');

      await pumpFlowScreen(
        tester,
        () => const _ReminderProbe('rem-about-us'),
        overrides: _overrides(server, on: false),
      );
      await tester.tap(find.text('open reminder'));
      await tester.pumpAndSettle();
      expect(find.text('the edit form'), findsOneWidget, reason: 'flag off');
    },
  );

  Map<String, dynamic> followed() => aboutUsJson(
    togetherSince: '2016-03-12',
    precision: 'day',
    anniversary: 'together_since',
    reminderId: 'rem-about-us',
  );
  // Fix round 1 (review M-2a): the reminder's own words.
  const offline =
      "We couldn't check this reminder. Check your connection and try again.";

  testWidgets(
    'F-5: offline, the anniversary reminder says so at once; Try again',
    (tester) async {
      final server = FakeCoupleProfileServer(profiles: {'r1': followed()})
        ..failNext = const SocketException('offline');
      await pumpFlowScreen(
        tester,
        () => const _ReminderProbe('rem-about-us'),
        overrides: _overrides(server, on: true),
      );
      await tester.tap(find.text('open reminder'));
      await tester.pumpAndSettle();
      expect(find.text(offline), findsOneWidget);
      expect(find.text('the edit form'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsWidgets);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text(offline), findsNothing);
      expect(find.text('This reminder follows About us'), findsOneWidget);
      await tester.tap(find.text('Change in About us'));
      await tester.pumpAndSettle();
      expect(find.text('Remember your anniversary?'), findsOneWidget);
    },
  );

  testWidgets('F-5: a hanging connection is bounded, never a 15 s stall', (
    tester,
  ) async {
    final hold = Completer<void>();
    final server = FakeCoupleProfileServer(profiles: {'r1': followed()})
      ..hold = hold;
    await pumpFlowScreen(
      tester,
      () => const _ReminderProbe('rem-about-us'),
      overrides: _overrides(server, on: true),
    );
    await tester.tap(find.text('open reminder'));
    await tester.pump();
    expect(
      aboutUsReminderProbeBound,
      lessThanOrEqualTo(const Duration(seconds: 3)),
    );
    await tester.pump(aboutUsReminderProbeBound);
    await tester.pumpAndSettle();
    expect(find.text(offline), findsOneWidget);
    expect(find.text('the edit form'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text(offline), findsNothing);
    hold.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the reminder sheet and its offline state meet the guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final server = FakeCoupleProfileServer(profiles: {'r1': followed()});
    await pumpFlowScreen(
      tester,
      () => const _ReminderProbe('rem-about-us'),
      overrides: _overrides(server, on: true),
    );
    await tester.tap(find.text('open reminder'));
    await tester.pumpAndSettle();
    await expectFlowGuidelines(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    server.failNext = const SocketException('offline');
    await tester.tap(find.text('open reminder'));
    await tester.pumpAndSettle();
    expect(find.text(offline), findsOneWidget);
    await expectFlowGuidelines(tester);
    handle.dispose();
  });

  // showReminderSheet is how Together, the calendar day sheet and the
  // Timeline open a reminder: About us's anniversary gets its sheet there.
  testWidgets('showReminderSheet: About us\'s anniversary opens its sheet', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer(profiles: {'r1': followed()});
    final reminder = ReminderModel(
      id: 'rem-about-us',
      relationshipId: 'r1',
      createdBy: _uid,
      reminderType: 'anniversary',
      title: 'Our anniversary',
      remindAt: DateTime(2027, 3, 12),
      recurrence: 'yearly',
      sent: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await pumpFlowScreen(
      tester,
      () => Scaffold(
        body: Builder(
          builder:
              (context) => TextButton(
                onPressed: () => showReminderSheet(context, reminder: reminder),
                child: const Text('open'),
              ),
        ),
      ),
      overrides: _overrides(server, on: true),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Our anniversary'), findsOneWidget);
    expect(find.text('This reminder follows About us'), findsOneWidget);
  });

  // Fix round 1 (review M-2b): offline, then back online, and it isn't
  // About us's reminder: the sheet closes and the edit form opens.
  testWidgets('F-5: Try again finds another reminder: the edit form opens', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer(profiles: {'r1': followed()})
      ..failNext = const SocketException('offline');
    await pumpFlowScreen(
      tester,
      () => const _ReminderProbe('rem-other'),
      overrides: _overrides(server, on: true),
    );
    await tester.tap(find.text('open reminder'));
    await tester.pumpAndSettle();
    expect(find.text(offline), findsOneWidget);
    expect(find.text('the edit form'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text(offline), findsNothing);
    expect(find.text('the edit form'), findsOneWidget);
  });

  // Fix round 1 (review M-4): Settings' draft names the partner R1 typed.
  testWidgets('Settings, pending: the draft gets R1\'s partner name', (
    tester,
  ) async {
    // The harness's other locations drop `extra`, so a router of its own
    // with an About us route that shows what it was given.
    SharedPreferences.setMockInitialValues({
      'attune.flow.$_uid.partner_first_name': 'Ama',
    });
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/test',
      routes: [
        GoRoute(path: '/test', builder: (_, __) => const _SettingsProbe()),
        GoRoute(
          path: '/about-us/:relationshipId',
          builder:
              (_, state) =>
                  Scaffold(body: Text('at ${state.uri} for ${state.extra}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ..._overrides(FakeCoupleProfileServer(), on: true),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _setLink(tester, 'pending', id: 'r-pending');
    await tester.tap(find.text('About us'));
    await tester.pumpAndSettle();
    expect(find.text('at /about-us/draft for Ama'), findsOneWidget);
  });

  // Fix round 1 (review M-5): R3's card meets the guidelines.
  testWidgets('R3\'s card meets the guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      () => const Scaffold(
        body: AllowLargeText(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: AboutUsCard(partnerName: 'Ama'),
          ),
        ),
      ),
      overrides: _overrides(FakeCoupleProfileServer(), on: true),
    );
    await expectFlowGuidelines(tester);
    handle.dispose();
  });

  testWidgets('goldens: about_us_card', (tester) async {
    await expectFlowGoldens(
      tester,
      'about_us_card',
      // As R3 shows it: inside AllowLargeText, so the text sizes apply.
      () => const Scaffold(
        body: AllowLargeText(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: AboutUsCard(partnerName: 'Ama'),
          ),
        ),
      ),
      overrides: _overrides(FakeCoupleProfileServer(), on: true),
    );
  });
}

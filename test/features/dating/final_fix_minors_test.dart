// Spec 2 W3 final fix (client minors): M-2 the not-open screen belongs to
// one account; M-3 the card names no one; M-4 one settings write per
// action at a time; M-5 a failed profile read in settings says so; M-6
// the profile rows only once a profile exists; M-7 three raised reasons in
// words, with a way on; M-13 a leftover prepared photo is swept; M-15
// Leave's deleted and kept items are read as list items.
import 'dart:async';
import 'dart:io';

import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/settings/dating_leave_screen.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_push_asker.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';
import '../../helpers/tap_in_reach.dart';
import 'support/dating_fakes.dart';
import 'support/dating_photos_fakes.dart';
import 'support/dating_setup_fakes.dart';
import 'support/dating_shell.dart';

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

/// Settings' writes, held until [hold] completes; the profile read can fail.
class _Setup extends FakeDatingSetupGateway {
  _Setup({super.profile});
  Completer<void>? hold;
  Object? profileError;

  @override
  Future<DatingMyProfile> myProfile() async {
    final e = profileError;
    if (e != null) throw e;
    return super.myProfile();
  }

  @override
  Future<DatingWrite> saveSettings(String key, Map<String, Object> values) {
    calls.add(('saveSettings', {'key': key, 'values': values}));
    final h = hold;
    if (h == null) return Future.value(const DatingWrite(ok: true));
    return h.future.then((_) => const DatingWrite(ok: true));
  }
}

Future<_Setup> _settings(
  WidgetTester t, {
  DatingHomeState state = DatingHomeState.active,
  DatingMyProfile profile = const DatingMyProfile(
    dropTime: '19:00:00',
    minAge: 25,
    maxAge: 35,
  ),
  Object? profileError,
}) async {
  final setup = _Setup(profile: profile)..profileError = profileError;
  await pumpFlowScreen(
    t,
    () => const DatingSettingsScreen(),
    overrides: [
      ...datingShellOverrides(
        home: FakeDatingHomeGateway(
          home: DatingHome(state: state, hasData: true),
        ),
      ),
      datingSetupGatewayProvider.overrideWithValue(setup),
      datingPhotosGatewayProvider.overrideWithValue(
        FakeDatingPhotosGateway(afterMutualFrom: DateTime.utc(2026, 1, 1)),
      ),
      pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
    ],
  );
  await t.pumpAndSettle();
  return setup;
}

void main() {
  group('M-2: the not-open screen belongs to one account (D8)', () {
    List<Override> overrides(FakeDatingHomeGateway home) => [
      ...datingShellOverrides(home: home),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
      ),
    ];

    testWidgets("the last account's answer never lands on the next", (t) async {
      final home = FakeDatingHomeGateway()..noticeHold = Completer<void>();
      await pumpFlowScreen(
        t,
        () => const DatingNotOpenScreen(country: 'NG'),
        overrides: overrides(home),
      );
      await tapInReach(t, find.text("Tell me when it's here"));
      await t.pump();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      await t.pump();
      home.noticeHold!.complete();
      await t.pumpAndSettle();
      expect(
        find.text("We'll let you know. You can turn this off in Settings."),
        findsNothing,
      );
      expect(find.text("Tell me when it's here"), findsOneWidget);
      // Nothing is left busy for the next account either.
      final button = t.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text("Tell me when it's here"),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets("a saved request isn't shown to the next account", (t) async {
      final home = FakeDatingHomeGateway();
      await pumpFlowScreen(
        t,
        () => const DatingNotOpenScreen(country: 'NG'),
        overrides: overrides(home),
      );
      await tapInReach(t, find.text("Tell me when it's here"));
      await t.pumpAndSettle();
      expect(find.text('Turn this off'), findsOneWidget);
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      await t.pumpAndSettle();
      expect(find.text('Turn this off'), findsNothing);
      expect(
        find.text("We'll let you know. You can turn this off in Settings."),
        findsNothing,
      );
    });
  });

  test('M-3: the companionship line names no one ("they" rule)', () {
    final loc = lookupAppLocalizations(const Locale('en'));
    expect(
      loc.dating_cardCompanionship,
      isNot(matches(RegExp(r'\b(they|their|them|theirs)\b'))),
    );
    expect(
      loc.dating_cardCompanionship,
      startsWith('Looking for companionship'),
    );
  });

  group('settings', () {
    testWidgets('M-4: a fast second toggle sends no second write', (t) async {
      final setup = await _settings(t);
      setup.hold = Completer<void>();
      final saver = find.widgetWithText(SwitchListTile, 'Data saver');
      await tapInReach(t, saver);
      await t.pump();
      await tapInReach(t, saver);
      await t.pump();
      expect(setup.writes.where((w) => w == 'saveSettings'), hasLength(1));
      setup.hold!.complete();
      await t.pumpAndSettle();
      // Once it has answered, the next toggle is a new write.
      await tapInReach(t, saver);
      await t.pumpAndSettle();
      expect(setup.writes.where((w) => w == 'saveSettings'), hasLength(2));
    });

    testWidgets('M-5: a failed profile read says so, with Retry', (t) async {
      final setup = await _settings(t, profileError: StateError('read'));
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Never a made-up 19:00 or a blank Ages row.
      expect(find.text('Introduction time'), findsNothing);
      expect(find.text('Ages'), findsNothing);
      setup.profileError = null;
      await tapInReach(t, find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsNothing);
      expect(find.text('Introduction time'), findsOneWidget);
      expect(find.text('25 to 35'), findsOneWidget);
    });

    testWidgets('M-6: a gentle wait with no profile shows no profile rows', (
      t,
    ) async {
      await _settings(
        t,
        state: DatingHomeState.gentleWait,
        profile: const DatingMyProfile(exists: false),
      );
      for (final row in [
        'Introduction time',
        'Ages',
        'How far',
        'Data saver',
      ]) {
        expect(find.text(row), findsNothing, reason: row);
      }
      // Leave and Clear stay (R-41, C-2).
      expect(find.text('Leave Dating and delete my data'), findsOneWidget);
    });

    testWidgets('M-6: with a profile, a gentle wait shows them', (t) async {
      await _settings(t, state: DatingHomeState.gentleWait);
      expect(find.text('Introduction time'), findsOneWidget);
    });

    test('M-6: no profile row is a profile that does not exist', () {
      expect(const DatingMyProfile(exists: false).exists, isFalse);
      expect(DatingMyProfile.fromJson(const {}).exists, isTrue);
    });
  });

  group('M-7: three raised reasons in words', () {
    final loc = lookupAppLocalizations(const Locale('en'));
    for (final (reason, text) in [
      ('terms_consent_required', loc.dating_errorConsent),
      ('dating_opt_in_required', loc.dating_errorConsent),
      ('path_not_dating', loc.dating_errorPathNotDating),
    ]) {
      test('$reason: its own copy, not "Something went wrong."', () {
        expect(
          datingWriteError(loc, DatingWrite(ok: false, reason: reason)),
          text,
        );
      });
    }

    Future<DatingShell> refusal(WidgetTester t, String reason) =>
        pumpDatingShell(
          t,
          initial: '/refusal',
          overrides: [
            datingSetupGatewayProvider.overrideWithValue(
              FakeDatingSetupGateway(),
            ),
            datingPreviewGatewayProvider.overrideWithValue(
              FakeDatingPreviewGateway(),
            ),
          ],
          extraRoutes: [
            GoRoute(
              path: '/refusal',
              builder:
                  (context, _) => Scaffold(
                    body: datingRefusalLine(
                      AppLocalizations.of(context)!,
                      DatingWrite(ok: false, reason: reason),
                    ),
                  ),
            ),
          ],
        );

    testWidgets('path_not_dating: a way to How you use Attune', (t) async {
      await refusal(t, 'path_not_dating');
      expect(find.text(loc.dating_errorPathNotDating), findsOneWidget);
      await tapInReach(t, find.text('How you use Attune'));
      await t.pumpAndSettle();
      expect(find.text('HOW YOU USE ATTUNE'), findsOneWidget);
    });

    for (final reason in ['terms_consent_required', 'dating_opt_in_required']) {
      testWidgets('$reason: a way back to the terms (D4)', (t) async {
        await refusal(t, reason);
        expect(find.text(loc.dating_errorConsent), findsOneWidget);
        await tapInReach(t, find.text('Finish setting up Dating'));
        await t.pumpAndSettle();
        expect(find.text('Your answers stay private'), findsOneWidget);
      });
    }
  });

  group('M-13: a prepared photo left behind is swept', () {
    test('only p_<micros>.jpg from before the sweep goes', () async {
      final dir = Directory.systemTemp.createTempSync('m13');
      addTearDown(() => dir.deleteSync(recursive: true));
      final now = DateTime.now();
      final old = File('${dir.path}/p_${now.microsecondsSinceEpoch - 5}.jpg')
        ..writeAsBytesSync([1]);
      final later = File(
        '${dir.path}/p_${now.microsecondsSinceEpoch + 1000000}.jpg',
      )..writeAsBytesSync([1]);
      final others = [
        for (final name in ['other.jpg', 'p_abc.jpg', 'p_12.png', 'xp_12.jpg'])
          File('${dir.path}/$name')..writeAsBytesSync([1]),
      ];
      final swept = await const DatingImagePreparer().sweepLeftovers(
        dir: dir,
        before: now,
      );
      expect(swept, 1);
      expect(old.existsSync(), isFalse);
      expect(later.existsSync(), isTrue);
      for (final f in others) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
    });

    test('an unreadable folder sweeps nothing and never throws', () async {
      final swept = await const DatingImagePreparer().sweepLeftovers(
        dir: Directory('${Directory.systemTemp.path}/m13-missing-folder'),
      );
      expect(swept, 0);
    });
  });

  testWidgets('M-15: Leave reads the deleted and kept items as list items', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final loc = lookupAppLocalizations(const Locale('en'));
    await pumpFlowScreen(
      t,
      () => const DatingLeaveScreen(),
      overrides: datingShellOverrides(
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active, hasData: true),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final item in [
      loc.dating_leaveNow,
      loc.dating_leave30,
      loc.dating_leaveSafety,
      loc.dating_leaveRecord,
    ]) {
      final label = t.getSemantics(find.text(item)).label;
      expect(label, startsWith('•'), reason: item);
      expect(label, contains(item));
    }
    semantics.dispose();
  });
}

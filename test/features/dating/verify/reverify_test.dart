// Spec 2 W4b (§3.3.4, §3.14; carry 9; D8): a phone Dating doesn't trust.
// Before a passed check the setup starts again there (the draft deleted as
// exit, then D1); after one, a video check (no consent box, liveness and
// CompareFaces, a person as the other way, never an ID). Every
// reverify_device answer offers the way there, behind the Dating lock.
import 'dart:async';

import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart'
    show datingDeviceReadyProvider;
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/settings/dating_leave_screen.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/setup/how_step.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/dating/verify/reverify_route.dart';
import 'package:attune/features/dating/verify/verify_flow.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_verify_fakes.dart';

const _restart = DatingHome(
  state: DatingHomeState.reverifyDevice,
  reverifyVariant: DatingReverifyVariant.setupRestart,
  hasData: true,
);
const _verifiedPhone = DatingHome(
  state: DatingHomeState.reverifyDevice,
  reverifyVariant: DatingReverifyVariant.verified,
  hasData: true,
);

/// A saved profile, so Dating settings shows its rows.
const _profile = DatingMyProfile(dropTime: '19:00:00', minAge: 25, maxAge: 35);

/// An untrusted phone's own status read: only the device answer.
const _untrusted = DatingVerification(available: true, trustedDevice: false);

Future<(DatingShell, FakeDatingVerificationGateway)> _shell(
  WidgetTester t, {
  required DatingHome home,
  String initial = '/me',
  DatingVerification state = _untrusted,
  bool locked = false,
  bool pinSet = false,
}) async {
  final verification = FakeDatingVerificationGateway(state: state);
  final s = await pumpDatingShell(
    t,
    initial: initial,
    locked: locked,
    pinSet: pinSet,
    home: FakeDatingHomeGateway(home: home),
    extraRoutes: [
      GoRoute(
        path: '/me',
        builder:
            (_, __) => const Scaffold(
              body: SingleChildScrollView(child: DatingSection()),
            ),
      ),
    ],
    overrides: [
      datingVerificationGatewayProvider.overrideWithValue(verification),
      datingCaptureLauncherProvider.overrideWithValue(FakeCaptureLauncher()),
      datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
      deviceCountryProvider.overrideWith(
        (ref) async => (sim: 'GB', region: null),
      ),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
      ),
    ],
  );
  return (s, verification);
}

void main() {
  test('the home reads the variant; anything else is a video check', () {
    expect(
      DatingHome.fromJson({
        'state': 'reverify_device',
        'variant': 'setup_restart',
      }).reverifyVariant,
      DatingReverifyVariant.setupRestart,
    );
    for (final v in ['verified', 'something_new', null]) {
      expect(
        DatingHome.fromJson({
          'state': 'reverify_device',
          'variant': v,
        }).reverifyVariant,
        DatingReverifyVariant.verified,
        reason: '$v',
      );
    }
  });

  group('before a passed check: start again here', () {
    testWidgets('the section says so; Start again leaves (keeping the list) '
        'and opens D1', (t) async {
      final (s, _) = await _shell(t, home: _restart);
      expect(
        find.text(
          'You started setting up Dating on another phone. To keep your '
          'answers private, start again here.',
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Start again'));
      await t.pumpAndSettle();
      expect(find.byType(DatingStartAgainScreen), findsOneWidget);
      expect(
        find.text(
          "Your 'Never introduce me' list stays. You can delete it from Leave "
          'Dating and delete my data.',
        ),
        findsOneWidget,
      );
      s.home.home = const DatingHome(state: DatingHomeState.notStarted);
      await tapInReach(t, find.text('Start again'));
      await t.pumpAndSettle();
      expect(s.life.calls, ['exit']);
      expect(s.life.keptList, isTrue, reason: 'R-32');
      expect(s.location, DatingPaths.step('how'));
      expect(find.byType(DatingHowStep), findsOneWidget);
    });

    testWidgets('a refused leave shows its words and stays', (t) async {
      final (s, _) = await _shell(
        t,
        home: _restart,
        initial: DatingPaths.verify,
      );
      s.life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.busy,
      );
      await tapInReach(t, find.text('Start again'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'This is taking a little longer than usual. Try again in a moment.',
        ),
        findsOneWidget,
      );
      expect(find.byType(DatingStartAgainScreen), findsOneWidget);
    });
  });

  group('after a passed check: a video check here', () {
    testWidgets('no consent box; the re-check actions; verified, back to Me', (
      t,
    ) async {
      final (s, verification) = await _shell(t, home: _verifiedPhone);
      expect(
        find.text("Confirm it's you on this phone to see Dating."),
        findsOneWidget,
      );
      await tapInReach(t, find.text("Verify it's you"));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Welcome back. Before we show Dating on this phone, please do a '
          "quick video check. It's how we keep your conversations yours.",
        ),
        findsOneWidget,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      verification.answers['reverify_start'] = [datingStarted()];
      verification.answers['reverify_complete'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      verification.onAct = (a) {
        if (a == 'reverify_complete') {
          verification.state = const DatingVerification(
            available: true,
            age: DatingCheck.pass,
            identity: DatingCheck.pass,
          );
        }
      };
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(verification.actionNames, ['reverify_start', 'reverify_complete']);
      expect(verification.consents, isEmpty, reason: 'the standing consent');
      expect(find.text("You're verified."), findsOneWidget);
      s.home.home = const DatingHome(state: DatingHomeState.active);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('ME me'), findsOneWidget);
    });

    testWidgets('the other way is a person, never an ID', (t) async {
      final (_, verification) = await _shell(
        t,
        home: _verifiedPhone,
        initial: DatingPaths.verify,
      );
      verification.answers['reverify_start'] = [datingStarted()];
      verification.answers['reverify_complete'] = [
        datingOutcome(DatingVerifyOutcome.anotherWay),
      ];
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(find.text('Check with my ID'), findsNothing);
      verification.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['$datingTestSession/1.jpg', '$datingTestSession/2.jpg'],
        ),
      ];
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      expect(verification.actions.last.$1, 'human_start');
      expect(verification.actions.last.$2, {'reverify': true});
      expect(find.text('Take two quick photos'), findsWidgets);
    });

    testWidgets('Check another way on the intro goes to a person directly', (
      t,
    ) async {
      final (_, verification) = await _shell(
        t,
        home: _verifiedPhone,
        initial: DatingPaths.verify,
      );
      verification.answers['human_start'] = [
        datingRefused(DatingVerifyRefusal.busy),
      ];
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      expect(verification.actions.single.$1, 'human_start');
      expect(verification.actions.single.$2, {'reverify': true});
    });

    testWidgets('a person is checking this phone: the waiting screen', (
      t,
    ) async {
      await _shell(
        t,
        home: _verifiedPhone,
        initial: DatingPaths.verify,
        state: const DatingVerification(
          available: true,
          trustedDevice: false,
          session: DatingVerifySession(
            id: datingTestSession,
            kind: 'reverify',
            step: 'human',
            state: 'awaiting_review',
            open: true,
          ),
        ),
      );
      expect(
        find.text(
          "A person is checking. This usually takes less than a day. We'll "
          'show the result here.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('behind the Dating lock (§3.14)', (t) async {
    final (s, _) = await _shell(
      t,
      home: _verifiedPhone,
      initial: DatingPaths.verify,
      locked: true,
      pinSet: true,
    );
    expect(s.location, startsWith('/dating/unlock?from='));
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.textContaining('Welcome back'), findsNothing);
  });

  group('carry 9: every reverify_device answer leads here', () {
    for (final (name, build)
        in <(String, Widget Function(BuildContext, AppLocalizations))>[
          (
            'a setup writer',
            (c, loc) => datingRefusalLine(
              loc,
              const DatingWrite(ok: false, reason: 'reverify_device'),
            ),
          ),
          (
            'a lifecycle refusal',
            (c, loc) => Column(
              children: datingLifecycleErrorRows(
                c,
                loc,
                DatingLifecycleError.reverifyDevice,
              ),
            ),
          ),
        ]) {
      testWidgets(name, (t) async {
        final s = await pumpDatingShell(
          t,
          initial: '/rows',
          home: FakeDatingHomeGateway(home: _verifiedPhone),
          extraRoutes: [
            GoRoute(
              path: '/rows',
              builder:
                  (context, __) => Scaffold(
                    body: build(context, AppLocalizations.of(context)!),
                  ),
            ),
          ],
          overrides: [
            datingVerificationGatewayProvider.overrideWithValue(
              FakeDatingVerificationGateway(state: _untrusted),
            ),
          ],
        );
        expect(
          find.text("Confirm it's you on this phone to see Dating."),
          findsOneWidget,
        );
        await tapInReach(t, find.text("Verify it's you"));
        await t.pumpAndSettle();
        expect(find.byType(DatingReverifyRoute), findsOneWidget);
        expect(s.location, '/rows', reason: 'pushed over it');
      });
    }
  });

  testWidgets('carry 9: the gentle wait\'s refused save leads here too', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      home: FakeDatingHomeGateway(home: _verifiedPhone),
      overrides: [
        datingVerificationGatewayProvider.overrideWithValue(
          FakeDatingVerificationGateway(state: _untrusted),
        ),
      ],
    );
    s.wait.result = GentleWaitSave.reverifyDevice;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Kindness');
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(
      find.text("Confirm it's you on this phone to see Dating."),
      findsOneWidget,
    );
    await tapInReach(t, find.text("Verify it's you"));
    await t.pumpAndSettle();
    expect(find.byType(DatingReverifyRoute), findsOneWidget);
  });

  testWidgets('D8: the next account starts from nothing on Start again', (
    t,
  ) async {
    final (s, _) = await _shell(t, home: _restart, initial: DatingPaths.verify);
    s.life.result = const DatingLifecycleResult.refused(
      DatingLifecycleError.failed,
    );
    await tapInReach(t, find.text('Start again'));
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    s.container.read(datingTestAccount.notifier).state = 'kofi';
    await t.pump();
    expect(find.text('Something went wrong. Try again.'), findsNothing);
    await t.pumpAndSettle();
  });

  testWidgets('large text at 2.0 and the dark theme', (t) async {
    final semantics = t.ensureSemantics();
    for (final home in [_restart, _verifiedPhone]) {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await pumpFlowScreen(
          t,
          () => Theme(data: theme, child: const DatingReverifyRoute()),
          textScale: 2.0,
          overrides: datingShellOverrides(
            home: FakeDatingHomeGateway(home: home),
            verification: FakeDatingVerificationGateway(state: _untrusted),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(
          t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          theme.colorScheme.surface,
        );
        await expectFlowGuidelines(t);
      }
    }
    semantics.dispose();
  });

  for (final (name, home) in [
    ('reverify_restart', _restart),
    ('reverify_verified', _verifiedPhone),
  ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        () => const DatingReverifyRoute(),
        overrides: datingShellOverrides(
          home: FakeDatingHomeGateway(home: home),
          verification: FakeDatingVerificationGateway(state: _untrusted),
        ),
        before: (t) => t.pumpAndSettle(),
      );
    });
  }

  // Task 7: what the brief couldn't know (the controller's A-H, against
  // Tasks 1-6 as their fix rounds left them).
  group('Task 7 carries', () {
    const deviceLine =
        "We can't check this phone right now. Close Attune and open it "
        'again. If this keeps happening, contact support.';
    const reverifyLine = "Confirm it's you on this phone to see Dating.";
    final verifyLink = find.widgetWithText(FlowTextLink, "Verify it's you");

    group('A: a phone with no install id is never sent to the re-check', () {
      for (final home in [_restart, _verifiedPhone]) {
        testWidgets(
          'the section and /dating/verify (${home.reverifyVariant})',
          (t) async {
            final s = await pumpDatingShell(
              t,
              initial: '/me',
              home: FakeDatingHomeGateway(home: home),
              deviceReady: false,
              extraRoutes: [
                GoRoute(
                  path: '/me',
                  builder:
                      (_, __) => const Scaffold(
                        body: SingleChildScrollView(child: DatingSection()),
                      ),
                ),
              ],
              overrides: [
                datingVerificationGatewayProvider.overrideWithValue(
                  FakeDatingVerificationGateway(state: _untrusted),
                ),
              ],
            );
            expect(find.text(deviceLine), findsOneWidget);
            expect(find.text("Verify it's you"), findsNothing);
            expect(find.text('Start again'), findsNothing);
            expect(find.text(reverifyLine), findsNothing);
            s.router.go(DatingPaths.verify);
            await t.pumpAndSettle();
            expect(find.text(deviceLine), findsOneWidget);
            for (final button in [
              'Start again',
              'Start video check',
              'Check another way',
            ]) {
              expect(find.text(button), findsNothing, reason: button);
            }
            expect(find.byType(FlowErrorLine), findsNothing, reason: 'calm');
            expect(s.life.calls, isEmpty);
          },
        );
      }

      for (final (name, build)
          in <(String, Widget Function(BuildContext, AppLocalizations))>[
            (
              'a setup writer',
              (c, loc) => datingRefusalLine(
                loc,
                const DatingWrite(ok: false, reason: 'reverify_device'),
              ),
            ),
            (
              'a lifecycle refusal',
              (c, loc) => Column(
                children: datingLifecycleErrorRows(
                  c,
                  loc,
                  DatingLifecycleError.reverifyDevice,
                ),
              ),
            ),
          ]) {
        testWidgets('$name: the calm line, no way to a check', (t) async {
          await pumpDatingShell(
            t,
            initial: '/rows',
            home: FakeDatingHomeGateway(home: _verifiedPhone),
            deviceReady: false,
            extraRoutes: [
              GoRoute(
                path: '/rows',
                builder:
                    (context, __) => Scaffold(
                      body: build(context, AppLocalizations.of(context)!),
                    ),
              ),
            ],
          );
          expect(find.text(deviceLine), findsOneWidget);
          expect(find.text("Verify it's you"), findsNothing);
          expect(find.byType(FlowErrorLine), findsNothing);
        });
      }

      testWidgets('the gentle wait: the calm line, no way to a check', (
        t,
      ) async {
        final s = await pumpDatingShell(
          t,
          initial: DatingPaths.step('wait'),
          home: FakeDatingHomeGateway(home: _verifiedPhone),
          deviceReady: false,
        );
        s.wait.result = GentleWaitSave.reverifyDevice;
        await t.enterText(
          find.byKey(const ValueKey('gentle_wait_q2')),
          'Kindness',
        );
        await tapInReach(t, find.text('Save my answers'));
        await t.pumpAndSettle();
        expect(find.text(deviceLine), findsOneWidget);
        expect(find.text("Verify it's you"), findsNothing);
      });

      testWidgets('the edge says device_unavailable: the same line, and no '
          'check to start', (t) async {
        final (_, verification) = await _shell(
          t,
          home: _verifiedPhone,
          initial: DatingPaths.verify,
        );
        verification.answers['reverify_start'] = [
          datingRefused(DatingVerifyRefusal.deviceUnavailable),
        ];
        await tapInReach(t, find.text('Start video check'));
        await t.pumpAndSettle();
        expect(find.text(deviceLine), findsOneWidget);
        expect(find.byType(FlowErrorLine), findsNothing);
        await tapInReach(t, find.text('Start video check'));
        await tapInReach(t, find.text('Check another way'));
        await t.pumpAndSettle();
        expect(verification.actionNames, ['reverify_start'], reason: 'once');
      });
    });

    group(
      'B: every writer\'s reverify_device answer leads to the re-check',
      () {
        Future<DatingShell> settingsShell(
          WidgetTester t,
          FakeDatingSetupGateway setup,
        ) => pumpDatingShell(
          t,
          initial: DatingPaths.settings,
          home: FakeDatingHomeGateway(
            home: const DatingHome(
              state: DatingHomeState.active,
              hasData: true,
            ),
          ),
          overrides: [
            datingSetupGatewayProvider.overrideWithValue(setup),
            datingPhotosGatewayProvider.overrideWithValue(
              FakeDatingPhotosGateway(),
            ),
            pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
            datingVerificationGatewayProvider.overrideWithValue(
              FakeDatingVerificationGateway(state: _untrusted),
            ),
          ],
        );

        testWidgets('settings: a save answering reverify_device', (t) async {
          final setup = FakeDatingSetupGateway(profile: _profile)
            ..answer = const DatingWrite(ok: false, reason: 'reverify_device');
          final s = await settingsShell(t, setup);
          await tapInReach(t, find.text('Data saver'));
          await t.pumpAndSettle();
          expect(find.text(reverifyLine), findsOneWidget);
          expect(find.text('Something went wrong. Try again.'), findsNothing);
          // Fix round 1 (M-1): the route reads the home again on open.
          s.home.home = _verifiedPhone;
          await tapInReach(t, verifyLink);
          await t.pumpAndSettle();
          expect(find.byType(DatingReverifyRoute), findsOneWidget);
        });

        testWidgets('settings: not_eligible is its own calm line (W2 M-3)', (
          t,
        ) async {
          final setup = FakeDatingSetupGateway(profile: _profile)
            ..answer = const DatingWrite(ok: false, reason: 'not_eligible');
          await settingsShell(t, setup);
          await tapInReach(t, find.text('Data saver'));
          await t.pumpAndSettle();
          expect(
            find.text("Dating isn't available on this account right now."),
            findsOneWidget,
          );
          expect(find.text('Something went wrong. Try again.'), findsNothing);
          expect(find.byType(FlowErrorLine), findsNothing);
        });

        testWidgets('the gentle wait\'s unreadable answers', (t) async {
          final s = await pumpDatingShell(
            t,
            initial: '/home',
            home: FakeDatingHomeGateway(home: _verifiedPhone),
            overrides: [
              datingVerificationGatewayProvider.overrideWithValue(
                FakeDatingVerificationGateway(state: _untrusted),
              ),
            ],
          );
          s.wait.readError = const GentleWaitUnavailable('reverify_device');
          s.router.go(DatingPaths.step('wait'));
          await t.pumpAndSettle();
          expect(find.text(reverifyLine), findsOneWidget);
          expect(find.text('Clear my answers'), findsOneWidget);
          await tapInReach(t, verifyLink);
          await t.pumpAndSettle();
          expect(find.byType(DatingReverifyRoute), findsOneWidget);
        });

        testWidgets('the section: a Resume answering reverify_device', (
          t,
        ) async {
          final (s, _) = await _shell(
            t,
            home: const DatingHome(
              state: DatingHomeState.paused,
              pauseReason: DatingPauseReason.user,
              hasData: true,
            ),
          );
          s.life.result = const DatingLifecycleResult.refused(
            DatingLifecycleError.reverifyDevice,
          );
          await tapInReach(t, find.text('Resume'));
          await t.pumpAndSettle();
          expect(find.text(reverifyLine), findsOneWidget);
          // Fix round 1 (M-1): the route reads the home again on open.
          s.home.home = _verifiedPhone;
          await tapInReach(t, verifyLink);
          await t.pumpAndSettle();
          expect(find.byType(DatingReverifyRoute), findsOneWidget);
        });

        testWidgets('D11: a consent answering reverify_device', (t) async {
          final verification = FakeDatingVerificationGateway(
              state: const DatingVerification(
                available: true,
                photosReady: true,
              ),
            )
            ..consentAnswer = const DatingWrite(
              ok: false,
              reason: 'reverify_device',
            );
          await pumpDatingShell(
            t,
            initial: DatingPaths.step('verify'),
            home: FakeDatingHomeGateway(home: _verifiedPhone),
            overrides: [
              datingVerificationGatewayProvider.overrideWithValue(verification),
              datingCaptureLauncherProvider.overrideWithValue(
                FakeCaptureLauncher(),
              ),
            ],
          );
          await tapInReach(
            t,
            find.byKey(const ValueKey('dating_verify_consent')),
          );
          await t.pump();
          await tapInReach(t, find.text('Start video check'));
          await t.pumpAndSettle();
          expect(find.text(reverifyLine), findsOneWidget);
          expect(verification.actions, isEmpty);
          await tapInReach(t, verifyLink);
          await t.pumpAndSettle();
          expect(find.byType(DatingReverifyRoute), findsOneWidget);
        });

        testWidgets('the re-check itself never links to itself', (t) async {
          final (_, verification) = await _shell(
            t,
            home: _verifiedPhone,
            initial: DatingPaths.verify,
          );
          verification.answers['reverify_start'] = [
            datingRefused(DatingVerifyRefusal.reverifyDevice),
          ];
          await tapInReach(t, find.text('Start video check'));
          await t.pumpAndSettle();
          expect(find.text(reverifyLine), findsOneWidget);
          expect(verifyLink, findsNothing);
        });
      },
    );

    group('C: the kept list (Task 5 rulings)', () {
      test('the list reads its rows and only how many are kept', () {
        final l = DatingNeverIntroduceList.fromJson({
          'ok': true,
          'items': [
            {'id': 'a1', 'label': 'Kojo', 'last_two': '42'},
            {'id': 7, 'label': 'bad'},
            // Fix round 1 (I-1): the name is optional (§3.12).
            {'id': 'b2', 'label': null, 'last_two': '07'},
            {'id': 'c3', 'label': 5, 'last_two': '11'},
          ],
          'kept_count': 3,
        });
        expect(l.ok, isTrue);
        expect(
          [for (final i in l.items) (i.id, i.label, i.lastTwo)],
          [('a1', 'Kojo', '42'), ('b2', null, '07')],
        );
        expect(l.keptCount, 3);
        for (final raw in <Object?>[
          {'ok': false, 'reason': 'reverify_device'},
          {'ok': true, 'items': 'x', 'kept_count': '2'},
          null,
          'nope',
        ]) {
          final r = DatingNeverIntroduceList.fromJson(raw);
          expect(r.keptCount, 0, reason: '$raw');
          expect(r.items, isEmpty, reason: '$raw');
        }
        expect(
          DatingNeverIntroduceList.fromJson({
            'ok': false,
            'reason': 'reverify_device',
          }).reason,
          'reverify_device',
        );
      });

      test('the repository reads the list through the Dating RPC', () async {
        final rpc = ScriptedRpc([
          (fn, p) => {'ok': true, 'items': [], 'kept_count': 1},
        ]);
        final l = await DatingNeverIntroduceRepository(rpc.rpc).list();
        expect(rpc.calls.single.$1, 'list_dating_never_introduce');
        expect(l.keptCount, 1);
      });

      Future<void> settings(WidgetTester t, DatingNeverIntroduceList l) async {
        await t.pumpWidget(const SizedBox());
        await pumpFlowScreen(
          t,
          () => const DatingSettingsScreen(),
          overrides: [
            ...datingShellOverrides(
              home: FakeDatingHomeGateway(
                home: const DatingHome(
                  state: DatingHomeState.notStarted,
                  hasData: true,
                ),
              ),
            ),
            datingSetupGatewayProvider.overrideWithValue(
              FakeDatingSetupGateway(),
            ),
            datingPhotosGatewayProvider.overrideWithValue(
              FakeDatingPhotosGateway(),
            ),
            pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
            datingNeverIntroduceGatewayProvider.overrideWithValue(
              FakeNeverIntroduce(l),
            ),
          ],
        );
        await t.pumpAndSettle();
      }

      testWidgets('kept people: how many, and that only Leave removes them; '
          'never a row', (t) async {
        await settings(
          t,
          const DatingNeverIntroduceList(ok: true, keptCount: 3),
        );
        expect(
          find.text(
            '3 people from before stay protected. To remove them, leave '
            'Dating and delete your data.',
          ),
          findsOneWidget,
        );
        expect(find.text('Leave Dating and delete my data'), findsOneWidget);
        await settings(
          t,
          const DatingNeverIntroduceList(ok: true, keptCount: 1),
        );
        expect(
          find.text(
            '1 person from before stays protected. To remove this '
            'protection, leave Dating and delete your data.',
          ),
          findsOneWidget,
        );
        for (final l in const [
          DatingNeverIntroduceList(ok: true),
          DatingNeverIntroduceList(reason: 'reverify_device'),
        ]) {
          await settings(t, l);
          expect(find.textContaining('from before'), findsNothing);
        }
      });
    });

    group('D: a verification pause says where the check stands', () {
      test('the home reads check; anything else is unknown', () {
        for (final (wire, check) in [
          ('held', DatingPauseCheck.held),
          ('final', DatingPauseCheck.ended),
          ('waiting', DatingPauseCheck.waiting),
          ('needed', DatingPauseCheck.needed),
          ('later', DatingPauseCheck.unknown),
          (null, DatingPauseCheck.unknown),
        ]) {
          expect(
            DatingHome.fromJson({
              'state': 'paused',
              'pause_reason': 'verification',
              'check': wire,
            }).check,
            check,
            reason: '$wire',
          );
        }
      });

      DatingHome paused(DatingPauseCheck check, {bool? canResume}) =>
          DatingHome(
            state: DatingHomeState.paused,
            pauseReason: DatingPauseReason.verification,
            check: check,
            canResume: canResume,
            hasData: true,
          );

      testWidgets('needed: the check', (t) async {
        await _shell(
          t,
          home: paused(DatingPauseCheck.needed, canResume: false),
        );
        expect(
          find.text("Dating is paused until you verify it's you again."),
          findsOneWidget,
        );
        expect(find.text("Verify it's you"), findsOneWidget);
        expect(find.text('Resume'), findsNothing);
      });

      testWidgets('waiting: a person or the ID vendor is checking', (t) async {
        await _shell(
          t,
          home: paused(DatingPauseCheck.waiting, canResume: false),
        );
        expect(
          find.text(
            "We're checking it's you. This usually takes less than a day.",
          ),
          findsOneWidget,
        );
        expect(find.text('See where it is'), findsOneWidget);
        expect(find.text("Verify it's you"), findsNothing);
        expect(find.text('Resume'), findsNothing);
      });

      testWidgets('final: a failed ID, support copy and nothing to retry', (
        t,
      ) async {
        await _shell(t, home: paused(DatingPauseCheck.ended, canResume: false));
        expect(
          find.text(
            "We couldn't confirm your age, so Dating isn't available on this "
            "account. If you think this is wrong, contact support.",
          ),
          findsOneWidget,
        );
        expect(find.text('Contact support'), findsOneWidget);
        for (final none in [
          "Verify it's you",
          'Resume',
          'Try again',
          'See where it is',
        ]) {
          expect(find.text(none), findsNothing, reason: none);
        }
      });

      testWidgets('held: Resume once it can; a shared space says so', (
        t,
      ) async {
        await _shell(t, home: paused(DatingPauseCheck.held, canResume: true));
        expect(
          find.text('Dating is paused. Nobody new sees you.'),
          findsOneWidget,
        );
        expect(find.text('Resume'), findsOneWidget);
        expect(find.text("Verify it's you"), findsNothing);
        await _shell(t, home: paused(DatingPauseCheck.held, canResume: false));
        expect(
          find.text(
            'Dating is paused while you have a shared space on Attune.',
          ),
          findsOneWidget,
        );
        expect(find.text('Resume'), findsNothing);
        expect(find.text("Verify it's you"), findsNothing);
      });

      testWidgets('unknown: the plain paused copy, nothing offered', (t) async {
        await _shell(
          t,
          home: paused(DatingPauseCheck.unknown, canResume: false),
        );
        expect(
          find.text('Dating is paused. Nobody new sees you.'),
          findsOneWidget,
        );
        for (final none in [
          "Verify it's you",
          'Resume',
          'See where it is',
          'Contact support',
        ]) {
          expect(find.text(none), findsNothing, reason: none);
        }
      });
    });

    group('E: the copy carries of Task 6', () {
      testWidgets('M-5: Start again says it can follow a phone or app '
          'problem', (t) async {
        await _shell(t, home: _restart, initial: DatingPaths.verify);
        expect(
          find.text(
            'This can also happen on the same phone after a problem with the '
            'phone or the app.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('M-6: photos_required on the re-check never says add '
          'photos: a trusted phone, or Leave', (t) async {
        final (_, verification) = await _shell(
          t,
          home: _verifiedPhone,
          initial: DatingPaths.verify,
        );
        verification.answers['reverify_start'] = [datingStarted()];
        verification.answers['reverify_complete'] = [
          datingRefused(DatingVerifyRefusal.photosRequired),
        ];
        await tapInReach(t, find.text('Start video check'));
        await t.pumpAndSettle();
        expect(
          find.text(
            'This check needs two approved photos. You can change your photos '
            'on a phone where you already use Dating, or leave Dating and '
            'delete your data.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Add two photos'), findsNothing);
        expect(find.text('Go to my photos'), findsNothing);
        await tapInReach(t, find.text('Leave Dating and delete my data'));
        await t.pumpAndSettle();
        expect(find.byType(DatingLeaveScreen), findsOneWidget);
      });
    });

    group('F: every answer settles; busy reads the home again', () {
      testWidgets('Start again: busy keeps its key, a named refusal drops '
          'it', (t) async {
        final (s, _) = await _shell(
          t,
          home: _restart,
          initial: DatingPaths.verify,
        );
        s.life.result = const DatingLifecycleResult.refused(
          DatingLifecycleError.busy,
        );
        await tapInReach(t, find.text('Start again'));
        await t.pumpAndSettle();
        await tapInReach(t, find.text('Start again'));
        await t.pumpAndSettle();
        s.life.result = const DatingLifecycleResult.refused(
          DatingLifecycleError.rateLimited,
        );
        await tapInReach(t, find.text('Start again'));
        await t.pumpAndSettle();
        await tapInReach(t, find.text('Start again'));
        await t.pumpAndSettle();
        expect(s.life.keys[0], s.life.keys[1], reason: 'busy keeps it');
        expect(s.life.keys[1], s.life.keys[2]);
        expect(s.life.keys[3], isNot(s.life.keys[2]), reason: 'settled');
      });

      testWidgets('busy on the re-check: the home is read again; a server\'s '
          'text never shows', (t) async {
        final verification =
            _Wire(state: _untrusted)
              ..answers['reverify_start'] = [datingStarted()]
              ..wire['reverify_complete'] = {
                'ok': false,
                'reason': 'busy',
                'message': 'SERVER SAYS NO',
              };
        final s = await pumpDatingShell(
          t,
          initial: DatingPaths.verify,
          home: FakeDatingHomeGateway(home: _verifiedPhone),
          overrides: [
            datingVerificationGatewayProvider.overrideWithValue(verification),
            datingCaptureLauncherProvider.overrideWithValue(
              FakeCaptureLauncher(),
            ),
          ],
        );
        final before = s.home.reads;
        await tapInReach(t, find.text('Start video check'));
        await t.pumpAndSettle();
        expect(s.home.reads, greaterThan(before));
        expect(find.textContaining('SERVER'), findsNothing);
        expect(
          find.text(
            'This is taking a little longer than usual. Try again in a '
            'moment.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('busy, but the phone was trusted meanwhile: verified, no '
          'failure', (t) async {
        final verification =
            _Wire(state: _untrusted)
              ..answers['reverify_start'] = [datingStarted()]
              ..wire['reverify_complete'] = {'ok': false, 'reason': 'busy'};
        verification.onAct = (a) {
          if (a == 'reverify_complete') {
            verification.state = const DatingVerification(
              available: true,
              age: DatingCheck.pass,
              identity: DatingCheck.pass,
            );
          }
        };
        final s = await pumpDatingShell(
          t,
          initial: DatingPaths.verify,
          home: FakeDatingHomeGateway(home: _verifiedPhone),
          overrides: [
            datingVerificationGatewayProvider.overrideWithValue(verification),
            datingCaptureLauncherProvider.overrideWithValue(
              FakeCaptureLauncher(),
            ),
          ],
        );
        s.home.home = const DatingHome(state: DatingHomeState.active);
        await tapInReach(t, find.text('Start video check'));
        await t.pumpAndSettle();
        expect(find.text("You're verified."), findsOneWidget);
        expect(find.textContaining('longer than usual'), findsNothing);
      });

      testWidgets('a result still pending is read again with the re-check '
          'action', (t) async {
        final (_, verification) = await _shell(
          t,
          home: _verifiedPhone,
          initial: DatingPaths.verify,
        );
        verification.answers['reverify_start'] = [datingStarted()];
        verification.answers['reverify_complete'] = [
          datingOutcome(DatingVerifyOutcome.pending),
          datingOutcome(DatingVerifyOutcome.retry),
        ];
        await tapInReach(t, find.text('Start video check'));
        await t.pumpAndSettle();
        await tapInReach(t, find.text('Check again'));
        await t.pumpAndSettle();
        expect(verification.actionNames, [
          'reverify_start',
          'reverify_complete',
          'reverify_complete',
        ]);
      });
    });

    group('G: the shared patterns', () {
      testWidgets('a double tap starts one re-check and one Start again', (
        t,
      ) async {
        final (s, verification) = await _shell(
          t,
          home: _verifiedPhone,
          initial: DatingPaths.verify,
        );
        verification.answers['reverify_start'] = [datingStarted()];
        verification.answers['reverify_complete'] = [
          datingOutcome(DatingVerifyOutcome.retry),
        ];
        verification.actHold = Completer<void>();
        await tapInReach(t, find.text('Start video check'));
        await tapInReach(t, find.text('Start video check'));
        await t.pump();
        verification.actHold!.complete();
        verification.actHold = null;
        await t.pumpAndSettle();
        expect(verification.actionNames, [
          'reverify_start',
          'reverify_complete',
        ]);
        final (s2, _) = await _shell(
          t,
          home: _restart,
          initial: DatingPaths.verify,
        );
        s2.life.result = const DatingLifecycleResult.refused(
          DatingLifecycleError.busy,
        );
        s2.life.callHold = Completer<void>();
        await tapInReach(t, find.text('Start again'));
        await tapInReach(t, find.text('Start again'));
        await t.pump();
        s2.life.callHold!.complete();
        await t.pumpAndSettle();
        expect(s2.life.calls, ['exit']);
        expect(s.life.calls, isEmpty);
      });

      testWidgets('the capture goes through the seam (its voice and haptics '
          'follow reduce motion)', (t) async {
        final capture = FakeCaptureLauncher();
        final verification =
            FakeDatingVerificationGateway(state: _untrusted)
              ..answers['reverify_start'] = [datingStarted()]
              ..answers['reverify_complete'] = [
                datingOutcome(DatingVerifyOutcome.retry),
              ];
        await pumpDatingShell(
          t,
          initial: DatingPaths.verify,
          home: FakeDatingHomeGateway(home: _verifiedPhone),
          overrides: [
            datingVerificationGatewayProvider.overrideWithValue(verification),
            datingCaptureLauncherProvider.overrideWithValue(capture),
          ],
        );
        await tapInReach(t, find.text('Start video check'));
        await t.pumpAndSettle();
        expect(capture.calls, ['liveness:fake:ref-1']);
      });

      testWidgets('large text through the step frame; no text field', (
        t,
      ) async {
        for (final (home, line) in [
          (_restart, 'Start again'),
          (_verifiedPhone, 'Start video check'),
        ]) {
          await _shell(t, home: home, initial: DatingPaths.verify);
          expect(
            find.ancestor(
              of: find.text(line),
              matching: find.byType(AllowLargeText),
            ),
            findsWidgets,
          );
          expect(find.byType(TextField), findsNothing);
        }
      });

      testWidgets('D8: an answer that lands after the account changed shows '
          'nothing of the last one', (t) async {
        final (s, verification) = await _shell(
          t,
          home: _verifiedPhone,
          initial: DatingPaths.verify,
        );
        verification.answers['reverify_start'] = [datingStarted()];
        verification.answers['reverify_complete'] = [
          datingOutcome(DatingVerifyOutcome.anotherWay),
        ];
        verification.actHold = Completer<void>();
        await tapInReach(t, find.text('Start video check'));
        await t.pump();
        s.container.read(datingTestAccount.notifier).state = 'kofi';
        await t.pump();
        expect(find.text('Ask a person to review it'), findsNothing);
        verification.actHold!.complete();
        verification.actHold = null;
        await t.pumpAndSettle();
        expect(verification.actionNames, ['reverify_start']);
        expect(find.text('Ask a person to review it'), findsNothing);
        expect(find.textContaining('Welcome back'), findsOneWidget);
      });

      group('quick exit', () {
        setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));
        setUp(() {
          QuickExitService.clearStories = () async {};
          addTearDown(
            () => QuickExitService.clearStories = clearStoryDeviceCaches,
          );
        });

        testWidgets('mid re-check: the decoy, and nothing of it left', (
          t,
        ) async {
          final verification =
              FakeDatingVerificationGateway(state: _untrusted)
                ..answers['reverify_start'] = [datingStarted()]
                ..answers['reverify_complete'] = [
                  datingOutcome(DatingVerifyOutcome.anotherWay),
                ];
          final s = await pumpDatingShell(
            t,
            initial: DatingPaths.verify,
            home: FakeDatingHomeGateway(home: _verifiedPhone),
            locked: true,
            wrap:
                (router, child) => QuickExitZone(router: router, child: child),
            overrides: [
              datingVerificationGatewayProvider.overrideWithValue(verification),
              datingCaptureLauncherProvider.overrideWithValue(
                FakeCaptureLauncher(),
              ),
            ],
          );
          await tapInReach(t, find.text('Start video check'));
          await t.pumpAndSettle();
          expect(find.text('Ask a person to review it'), findsOneWidget);
          for (var i = 0; i < 3; i++) {
            await t.tap(
              find.byKey(const Key('quick_exit_zone')),
              warnIfMissed: false,
            );
            await t.pump(const Duration(milliseconds: 50));
          }
          await t.pumpAndSettle(const Duration(milliseconds: 400));
          expect(find.text('DECOY'), findsOneWidget);
          expect(
            find.byType(DatingReverifyRoute, skipOffstage: false),
            findsNothing,
          );
          expect(
            find.byType(DatingVerifyFlow, skipOffstage: false),
            findsNothing,
          );
          expect(s.lock.on, isTrue);
        });
      });
    });

    testWidgets('H: the manual says what W4b built', (t) async {
      late BuildContext context;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final passage = DatingModeDocs()
          .getSections(context)
          .expand((s) => s.contents)
          .singleWhere((c) => c.id == 'dating_new_phone');
      expect(passage.title, 'A new phone');
      expect(
        passage.content,
        'On a new phone, a phone restored from a backup, or after a problem '
        "with your phone or the app, Dating asks you to check it's you "
        'before it shows anything: a short video check, or a person looks at '
        'two quick photos. It never asks for your ID again. Dating keeps '
        "working on up to three of your phones, and a phone you haven't used "
        'for Dating in 180 days needs the check again. If you started '
        "setting up Dating on another phone and hadn't passed the check yet, "
        'you start again on this one, so your answers stay private. Starting '
        'again keeps your "Never introduce me" list, and you can still delete '
        'it from Leave Dating and delete my data. People kept on your list '
        "from before stay protected but aren't shown, and can't be removed "
        'one at a time: to remove them, leave Dating and delete your data. '
        "If Attune can't check your phone at all, close Attune and open it "
        'again; if that keeps happening, contact support.',
      );
    });
  });

  // Task 7 fix round 1 (task-7-review.md): I-1 is in C above.
  group('fix round 1', () {
    const deviceLine =
        "We can't check this phone right now. Close Attune and open it "
        'again. If this keeps happening, contact support.';
    const reverifyLine = "Confirm it's you on this phone to see Dating.";
    final verifyLink = find.widgetWithText(FlowTextLink, "Verify it's you");

    // M-3: a device-gated read that answers reverify_device leads to the
    // re-check (or, with no install id, the calm line), never the red
    // "Something went wrong" and Retry.
    for (final (name, step, setup, photosError, preview) in <
      (String, String, FakeDatingSetupGateway, Object?, DatingPreviewGateway)
    >[
      for (final step in ['looking-for', 'children', 'prompts', 'ready'])
        (
          '$step: the profile read',
          step,
          _RefusingSetup(profileRefused: true),
          null,
          FakeDatingPreviewGateway(),
        ),
      (
        'preview: the profile read',
        'preview',
        _RefusingSetup(profileRefused: true),
        null,
        FakeDatingPreviewGateway(),
      ),
      (
        'preview: the card read',
        'preview',
        _RefusingSetup(),
        null,
        _RefusingPreview(),
      ),
      for (final step in ['you', 'meet', 'faith', 'where'])
        (
          '$step: the lists read',
          step,
          _RefusingSetup(listsRefused: true),
          null,
          FakeDatingPreviewGateway(),
        ),
      (
        'photos: the photo list read',
        'photos',
        _RefusingSetup(),
        StateError('photos:reverify_device'),
        FakeDatingPreviewGateway(),
      ),
    ]) {
      for (final ready in [true, false]) {
        testWidgets('M-3 $name (install id: $ready)', (t) async {
          await pumpDatingShell(
            t,
            initial: DatingPaths.step(step),
            home: FakeDatingHomeGateway(home: _verifiedPhone),
            deviceReady: ready,
            overrides: [
              datingSetupGatewayProvider.overrideWithValue(setup),
              datingPhotosGatewayProvider.overrideWithValue(
                FakeDatingPhotosGateway()..listError = photosError,
              ),
              datingPreviewGatewayProvider.overrideWithValue(preview),
              deviceCountryProvider.overrideWith(
                (ref) async => (sim: 'GH', region: null),
              ),
              pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
              datingVerificationGatewayProvider.overrideWithValue(
                FakeDatingVerificationGateway(state: _untrusted),
              ),
            ],
          );
          expect(find.text('Something went wrong. Try again.'), findsNothing);
          expect(find.text('Retry'), findsNothing);
          expect(find.byType(FlowErrorLine), findsNothing);
          if (!ready) {
            expect(find.text(deviceLine), findsOneWidget);
            expect(verifyLink, findsNothing);
            return;
          }
          expect(find.text(reverifyLine), findsOneWidget);
          await tapInReach(t, verifyLink);
          await t.pumpAndSettle();
          expect(find.byType(DatingReverifyRoute), findsOneWidget);
        });
      }
    }

    for (final ready in [true, false]) {
      testWidgets('M-3 settings: the profile read (install id: $ready)', (
        t,
      ) async {
        await pumpDatingShell(
          t,
          initial: DatingPaths.settings,
          home: FakeDatingHomeGateway(
            home: const DatingHome(
              state: DatingHomeState.active,
              hasData: true,
            ),
          ),
          deviceReady: ready,
          overrides: [
            datingSetupGatewayProvider.overrideWithValue(
              _RefusingSetup(profileRefused: true),
            ),
            datingPhotosGatewayProvider.overrideWithValue(
              FakeDatingPhotosGateway(),
            ),
            pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
            datingVerificationGatewayProvider.overrideWithValue(
              FakeDatingVerificationGateway(state: _untrusted),
            ),
          ],
        );
        expect(find.text('Something went wrong. Try again.'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(find.text(ready ? reverifyLine : deviceLine), findsOneWidget);
        expect(verifyLink, ready ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('M-3: any other failed read still offers Retry', (t) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.step('children'),
        home: FakeDatingHomeGateway(home: _verifiedPhone),
        overrides: [
          datingSetupGatewayProvider.overrideWithValue(
            _RefusingSetup(profileRefused: true, reason: 'not_eligible'),
          ),
        ],
      );
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text(reverifyLine), findsNothing);
    });

    group('M-1: a link followed after the home moved on', () {
      testWidgets('the home is read again on open: a stale cached state '
          'never decides', (t) async {
        final (s, _) = await _shell(
          t,
          home: const DatingHome(state: DatingHomeState.active, hasData: true),
        );
        s.home.home = _verifiedPhone;
        s.router.push(DatingPaths.verify);
        await t.pumpAndSettle();
        expect(find.byType(DatingVerifyFlow), findsOneWidget);
        expect(find.textContaining('Welcome back'), findsOneWidget);
      });

      testWidgets('a phone Dating trusts again goes back to Me', (t) async {
        await _shell(
          t,
          home: const DatingHome(state: DatingHomeState.active, hasData: true),
          initial: DatingPaths.verify,
        );
        expect(find.text('ME me'), findsOneWidget);
        expect(find.byType(DatingVerifyFlow), findsNothing);
      });

      testWidgets('a verification pause goes to D11, never the re-check', (
        t,
      ) async {
        final (s, _) = await _shell(
          t,
          home: const DatingHome(
            state: DatingHomeState.paused,
            pauseReason: DatingPauseReason.verification,
            check: DatingPauseCheck.needed,
            canResume: false,
            hasData: true,
          ),
          initial: DatingPaths.verify,
        );
        expect(s.location, DatingPaths.step('verify'));
        expect(find.textContaining('Welcome back'), findsNothing);
      });
    });

    testWidgets('M-2: while the home is read, the screen has a way back', (
      t,
    ) async {
      final home = FakeDatingHomeGateway(home: _verifiedPhone)
        ..hold = Completer<DatingHome>();
      await pumpDatingShell(
        t,
        initial: DatingPaths.verify,
        home: home,
        overrides: [
          datingVerificationGatewayProvider.overrideWithValue(
            FakeDatingVerificationGateway(state: _untrusted),
          ),
        ],
      );
      expect(find.textContaining('Welcome back'), findsNothing);
      await tapInReach(t, find.byType(BackButtonIcon));
      await t.pumpAndSettle();
      expect(find.text('ME me'), findsOneWidget);
      home.hold!.complete(_verifiedPhone);
      await t.pumpAndSettle();
    });

    testWidgets('M-4: settings never reads the list on a phone to check', (
      t,
    ) async {
      final list = FakeNeverIntroduce(
        const DatingNeverIntroduceList(ok: true, keptCount: 2),
      );
      await pumpFlowScreen(
        t,
        () => const DatingSettingsScreen(),
        overrides: [
          ...datingShellOverrides(home: FakeDatingHomeGateway(home: _restart)),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(),
          ),
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(),
          ),
          pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
          datingNeverIntroduceGatewayProvider.overrideWithValue(list),
        ],
      );
      await t.pumpAndSettle();
      expect(list.reads, 0);
      expect(find.textContaining('from before'), findsNothing);
    });

    testWidgets('M-5: one kept person says what goes', (t) async {
      await pumpFlowScreen(
        t,
        () => const DatingSettingsScreen(),
        overrides: [
          ...datingShellOverrides(
            home: FakeDatingHomeGateway(
              home: const DatingHome(
                state: DatingHomeState.notStarted,
                hasData: true,
              ),
            ),
          ),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(),
          ),
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(),
          ),
          pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
          datingNeverIntroduceGatewayProvider.overrideWithValue(
            FakeNeverIntroduce(
              const DatingNeverIntroduceList(ok: true, keptCount: 1),
            ),
          ),
        ],
      );
      await t.pumpAndSettle();
      expect(
        find.text(
          '1 person from before stays protected. To remove this protection, '
          'leave Dating and delete your data.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('M-8: while the install id is read, the card offers nothing', (
      t,
    ) async {
      for (final (home, button) in [
        (_verifiedPhone, "Verify it's you"),
        (_restart, 'Start again'),
      ]) {
        await pumpDatingShell(
          t,
          initial: '/me',
          home: FakeDatingHomeGateway(home: home),
          extraRoutes: [
            GoRoute(
              path: '/me',
              builder:
                  (_, __) => const Scaffold(
                    body: SingleChildScrollView(child: DatingSection()),
                  ),
            ),
          ],
          overrides: [
            datingDeviceReadyProvider.overrideWith(
              (ref) => Completer<bool>().future,
            ),
          ],
        );
        expect(find.text(button), findsNothing);
        expect(find.text(deviceLine), findsNothing);
        final line =
            home == _restart
                ? 'You started setting up Dating on another phone. To keep '
                    'your answers private, start again here.'
                : reverifyLine;
        expect(find.text(line), findsOneWidget);
        await tapInReach(t, find.text(line));
        await t.pumpAndSettle();
        expect(find.byType(DatingReverifyRoute), findsNothing);
      }
    });
  });

  group('final fix wave', () {
    DatingHome paused(DatingPauseCheck check, {bool? canResume}) => DatingHome(
      state: DatingHomeState.paused,
      pauseReason: DatingPauseReason.verification,
      check: check,
      canResume: canResume,
      hasData: true,
    );
    final fromSection = '${DatingPaths.step('verify')}?from=section';
    String d11At(WidgetTester t) =>
        GoRouterState.of(
          t.element(find.byType(DatingVerifyFlow)),
        ).uri.toString();

    testWidgets('M-2: Verify it\'s you on a verification pause opens D11 from '
        'the section; passing comes back to Resume, never D12 or D13', (
      t,
    ) async {
      final (s, verification) = await _shell(
        t,
        home: paused(DatingPauseCheck.needed, canResume: false),
        state: datingVerifiedState,
      );
      await tapInReach(t, find.text("Verify it's you"));
      await t.pumpAndSettle();
      expect(d11At(t), fromSection);
      expect(find.text("You're verified."), findsOneWidget);
      s.home.home = paused(DatingPauseCheck.held, canResume: true);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(s.location, '/me');
      expect(find.byType(DatingVerifyFlow), findsNothing);
      expect(find.byType(DatingSection), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.textContaining('Step 11 of 12'), findsNothing);
      expect(find.textContaining('Step 12 of 12'), findsNothing);
      expect(verification.actions, isEmpty);
    });

    testWidgets('M-2: See where it is on a waiting pause opens D11 from the '
        'section too', (t) async {
      await _shell(
        t,
        home: paused(DatingPauseCheck.waiting, canResume: false),
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'human',
            state: 'awaiting_review',
            open: true,
          ),
        ),
      );
      await tapInReach(t, find.text('See where it is'));
      await t.pumpAndSettle();
      expect(d11At(t), fromSection);
      expect(find.textContaining('A person is checking.'), findsOneWidget);
    });

    testWidgets('M-5: a stale /dating/verify link from a trusted screen goes '
        'back there, not to Me', (t) async {
      final (s, _) = await _shell(
        t,
        home: const DatingHome(state: DatingHomeState.active, hasData: true),
      );
      unawaited(s.router.push(DatingPaths.verify));
      await t.pumpAndSettle();
      expect(s.location, '/me');
      expect(find.byType(DatingSection), findsOneWidget);
      expect(find.text('ME me'), findsNothing);
      expect(find.byType(DatingVerifyFlow), findsNothing);
    });

    testWidgets('server M-4: /dating/verify: a check open on another phone '
        'is its own calm line', (t) async {
      final (_, verification) = await _shell(
        t,
        home: _verifiedPhone,
        initial: DatingPaths.verify,
      );
      verification.answers['reverify_start'] = [
        DatingVerifyAnswer.fromJson({
          'ok': false,
          'reason': 'session_elsewhere',
        }),
      ];
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'A check is already open on another phone. Finish it there, or '
          'try again later.',
        ),
        findsOneWidget,
      );
      expect(find.text('Something went wrong. Try again.'), findsNothing);
      expect(find.byType(FlowErrorLine), findsNothing, reason: 'calm');
      expect(find.text('Start video check'), findsOneWidget);
    });

    testWidgets('M-10: the final ID ending on the card is the same error row '
        'as in D11, at full contrast', (t) async {
      await _shell(t, home: paused(DatingPauseCheck.ended, canResume: false));
      const text =
          "We couldn't confirm your age, so Dating isn't available on this "
          'account. If you think this is wrong, contact support.';
      expect(find.widgetWithText(FlowErrorLine, text), findsOneWidget);
      final style = t.widget<Text>(find.text(text)).style;
      final scheme = Theme.of(t.element(find.text(text))).colorScheme;
      expect(style?.color, scheme.onSurface);
      expect(find.text('Contact support'), findsOneWidget);
    });
  });
}

/// Answers as they come off the wire (a server's text next to the code).
class _Wire extends FakeDatingVerificationGateway {
  _Wire({required super.state});

  final wire = <String, Map<String, Object?>>{};

  @override
  Future<DatingVerifyAnswer> act(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    final raw = wire[action];
    if (raw == null) return super.act(action, body);
    actions.add((action, body));
    onAct?.call(action);
    return DatingVerifyAnswer.fromJson(raw);
  }
}

/// Fix round 1 (M-3): the setup reads as a phone Dating doesn't trust
/// gets them (the repositories raise `<read>:<reason>`).
class _RefusingSetup extends FakeDatingSetupGateway {
  _RefusingSetup({
    this.profileRefused = false,
    this.listsRefused = false,
    this.reason = 'reverify_device',
  });

  final bool profileRefused;
  final bool listsRefused;
  final String reason;

  @override
  Future<DatingSetupLists> lists() async {
    if (listsRefused) throw StateError('lists:$reason');
    return super.lists();
  }

  @override
  Future<DatingMyProfile> myProfile() async {
    if (profileRefused) throw StateError('profile:$reason');
    return super.myProfile();
  }
}

/// Fix round 1 (M-3): D12's card read refused on a phone to check.
class _RefusingPreview implements DatingPreviewGateway {
  @override
  Future<DatingCard?> preview() async =>
      throw StateError('preview:reverify_device');
}

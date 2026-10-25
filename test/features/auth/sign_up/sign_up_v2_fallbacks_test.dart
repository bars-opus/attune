// Spec 1 W2b, batch 5 carries for the shared files: under flow_signin_v2
// EulaGate's fallback never shows the v1 sheet nor records consent, it
// sends the person to A5 or A5c instead (batch 3 M-6, D8, Review Focus 4);
// the flag off still prompts as today. The replay's under-18 stop runs
// before its reset, and its block closes sign-up in the same session
// (ruling C9).
import 'package:attune/app/documentations/legal_documentation/widgets/legal_documentation_modal_sheet.dart';
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/features/auth/data/eula_acceptance_service.dart';
import 'package:attune/features/auth/presentation/eula_gate.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_account_gateway.dart';
import '../../../helpers/flow_harness.dart';

/// A consent check whose answer is scripted; records what it was asked to
/// record.
class _Eula extends EulaAcceptanceService {
  _Eula({required this.needs, super.version});

  final bool needs;
  final recorded = <String>[];

  @override
  Future<bool> needsAcceptance() async => needs;

  @override
  Future<void> recordAcceptance() async => recorded.add(version);
}

class _NoSubmission implements OnboardingSubmissionService {
  @override
  Future<void> submit({
    required OnboardingMode mode,
    required String displayName,
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async {}
}

class _ClearPendingFails extends OnboardingStore {
  const _ClearPendingFails(super.prefs, {required super.scope});

  @override
  Future<void> clearPendingSignUp() async => throw StateError('disk full');
}

class _ResetFails extends OnboardingStore {
  const _ResetFails(super.prefs, {required super.scope});

  @override
  Future<void> reset() async => throw StateError('disk full');
}

/// OnboardingFlow's last step, reduced to the call it makes.
Widget Function() _finish(
  EulaAcceptanceService service,
  List<EulaOutcome> outcomes,
) =>
    () => Builder(
      builder:
          (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed:
                    () async => outcomes.add(
                      await EulaGate.ensureAccepted(context, service: service),
                    ),
                child: const Text('Finish'),
              ),
            ),
          ),
    );

/// The v1 sheet's buttons sit below its text, built only once scrolled to.
Future<void> _scrollTo(WidgetTester tester, String label) async {
  await tester.dragUntilVisible(
    find.text(label),
    find.byType(ListView).last,
    const Offset(0, -300),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('EulaGate under flow_signin_v2 (batch 3 M-6)', () {
    Future<FlowHarness> pump(
      WidgetTester tester, {
      required bool flowV2,
      required EulaAcceptanceService service,
      required List<EulaOutcome> outcomes,
      FakeAccountGateway? gateway,
    }) => pumpFlowScreen(
      tester,
      _finish(service, outcomes),
      overrides: [
        signInFlowV2Provider.overrideWithValue(flowV2),
        accountServiceProvider.overrideWithValue(
          AccountService(gateway ?? FakeAccountGateway()),
        ),
      ],
    );

    testWidgets('no account yet: A5, never the v1 sheet, nothing recorded', (
      tester,
    ) async {
      final eula = _Eula(needs: true, version: '2');
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(hasAccount: false),
      );
      final outcomes = <EulaOutcome>[];
      final h = await pump(
        tester,
        flowV2: true,
        service: eula,
        outcomes: outcomes,
        gateway: gateway,
      );
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(outcomes, [EulaOutcome.unavailable]);
      expect(h.location, RouteNames.signUp);
      expect(eula.recorded, isEmpty);
      expect(gateway.count('record_eula_acceptance'), 0);
      expect(find.byType(LegalDocumentationModalSheet), findsNothing);
    });

    testWidgets('an account on an older EULA: A5c ("We\'ve updated our '
        'terms"), never the v1 sheet', (tester) async {
      final eula = _Eula(needs: true, version: '2');
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(needs: ['consent']),
      );
      final outcomes = <EulaOutcome>[];
      final h = await pump(
        tester,
        flowV2: true,
        service: eula,
        outcomes: outcomes,
        gateway: gateway,
      );
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(outcomes, [EulaOutcome.unavailable]);
      expect(h.location, '${RouteNames.signUp}?entry=returning');
      expect(eula.recorded, isEmpty);
      expect(gateway.count('record_eula_acceptance'), 0);
    });

    testWidgets('the server says consent is done: carry on, no sheet', (
      tester,
    ) async {
      final eula = _Eula(needs: true, version: '2');
      final outcomes = <EulaOutcome>[];
      final h = await pump(
        tester,
        flowV2: true,
        service: eula,
        outcomes: outcomes,
        gateway: FakeAccountGateway(homeState: FakeAccountGateway.account()),
      );
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(outcomes, [EulaOutcome.accepted]);
      expect(h.location, '/test');
      expect(eula.recorded, isEmpty);
    });

    testWidgets('offline: stays put, no sheet, nothing recorded', (
      tester,
    ) async {
      final eula = _Eula(needs: true, version: '2');
      final outcomes = <EulaOutcome>[];
      final h = await pump(
        tester,
        flowV2: true,
        service: eula,
        outcomes: outcomes,
        // get_my_home_state answers nothing: AccountOffline.
        gateway: FakeAccountGateway(),
      );
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(outcomes, [EulaOutcome.unavailable]);
      expect(h.location, '/test');
      expect(eula.recorded, isEmpty);
      expect(find.byType(LegalDocumentationModalSheet), findsNothing);
      // Review B5 M-4: never a silent Finish.
      expect(find.text("We couldn't save that. Try again."), findsOneWidget);
    });

    testWidgets('flag off: today\'s prompt, unchanged (v1 recorded on '
        'Accept, no account call)', (tester) async {
      final eula = _Eula(needs: true);
      final gateway = FakeAccountGateway();
      final outcomes = <EulaOutcome>[];
      final h = await pump(
        tester,
        flowV2: false,
        service: eula,
        outcomes: outcomes,
        gateway: gateway,
      );
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentationModalSheet), findsOneWidget);
      await _scrollTo(tester, 'Accept');
      expect(find.text('Reject'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(outcomes, [EulaOutcome.accepted]);
      expect(eula.recorded, ['1']);
      expect(h.location, '/test');
      expect(gateway.calls, isEmpty);
    });

    testWidgets('flag off: Reject is still a decline', (tester) async {
      final eula = _Eula(needs: true);
      final outcomes = <EulaOutcome>[];
      await pump(tester, flowV2: false, service: eula, outcomes: outcomes);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, 'Reject');
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      expect(outcomes, [EulaOutcome.declined]);
      expect(eula.recorded, isEmpty);
    });
  });

  group('the replay\'s under-18 stop', () {
    late SharedPreferences prefs;
    final pending = PendingSignUp(
      displayName: 'Ama',
      birthDate: DateTime.utc(1990, 1, 2),
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    OnboardingSyncService refused() => OnboardingSyncService(
      submissionService: _NoSubmission(),
      accountService: AccountService(
        FakeAccountGateway()
          ..failWith = FakeAccountGateway.refusal('signup:not_eligible'),
      ),
    );

    test('blocks the phone even when the reset after it fails', () async {
      final store = _ResetFails(prefs, scope: 'user.me');
      await store.savePendingSignUp(pending);
      try {
        await refused().flush(store);
      } catch (_) {
        // Whether a failed reset surfaces is not the point here.
      }
      expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
    });

    test('fix round 2: dropping the payload comes after the block, so a '
        'throw there never loses it', () async {
      final store = _ClearPendingFails(prefs, scope: 'user.me');
      await store.savePendingSignUp(pending);
      try {
        await refused().flush(store);
      } catch (_) {
        // Whether the failed drop surfaces is not the point here.
      }
      expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
    });

    test('C9: its block closes sign-up and the guest pass in this '
        'session', () async {
      final routing = RoutingNotifier(
        prefs: prefs,
        flowV2: true,
        guestAgeOk: true,
        currentUserId: () => null,
      );
      expect(appRedirect(routing, RouteNames.signUp), isNull);
      expect(appRedirect(routing, RouteNames.home), isNull);

      final store = OnboardingStore(prefs, scope: 'user.me');
      await store.savePendingSignUp(pending);
      // The default stop: block, then a sign-out that throws here (no
      // Supabase) and is caught.
      await refused().flush(store);

      expect(routing.underAgeBlocked, isTrue);
      expect(appRedirect(routing, RouteNames.signUp), RouteNames.ageStop);
      expect(appRedirect(routing, RouteNames.invite), RouteNames.ageStop);
      expect(appRedirect(routing, RouteNames.home), RouteNames.guestAge);
      expect(store.pendingSignUp, isNull);
    });
  });
}

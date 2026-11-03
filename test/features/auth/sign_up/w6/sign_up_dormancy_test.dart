// Spec 1 W6a (§3.5, §3.15; W3 carry C-2): a code sign-in the access-token
// hook refused. A recycled number: DM1 keeps the challenge in memory, the
// fresh start parks the old account and a new code makes a new account
// (A1/A2 kept, never N1). A held account: H1, the draft gone, the phone
// blocked for an age hold only.
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/fresh_start_service.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_coordinator.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/domain/otp_failure.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../helpers/fake_account_gateway.dart';
import '../../../../helpers/fake_sign_up.dart';

final _now = DateTime.utc(2026, 11, 3, 12);
const _phone = '+233244123456';
final _nonce = 'cd' * 64;

class FakeFreshStart implements FreshStartGateway {
  final results = <FreshStartResult>[];
  final nonces = <String>[];

  @override
  Future<FreshStartResult> start(String nonce) async {
    nonces.add(nonce);
    return results.isEmpty ? FreshStartResult.done : results.removeAt(0);
  }
}

class _Rig {
  _Rig(this.prefs)
    : auth = FakeSignUpAuth(),
      gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(hasAccount: false),
      );

  final SharedPreferences prefs;
  final sender = FakeCodeSender();
  final FakeSignUpAuth auth;
  final FakeAccountGateway gateway;
  final fresh = FakeFreshStart();

  SignUpDraftStore get drafts => SignUpDraftStore(prefs, now: () => _now);

  SignUpCoordinator coordinator() => SignUpCoordinator(
    drafts: drafts,
    sender: sender,
    auth: auth,
    accounts: AccountService(gateway),
    ageGate: AgeGateStore(prefs, now: () => _now),
    onboardingStoreFor: (uid) => OnboardingStore(prefs, scope: 'user.$uid'),
    metrics: MetricCounter((key) async {}),
    now: () => _now,
    freshStart: fresh,
  );

  /// The hook refuses the next verify with [message] (a 403, as Auth sends it).
  void refuse(String message) =>
      auth.failVerifyWith = AuthException(message, statusCode: '403');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<SignUpCoordinator> atCode(_Rig rig, SignUpEntry entry) async {
    final c = rig.coordinator();
    c.start(entry);
    if (entry == SignUpEntry.newAccount) {
      await c.saveName('Esi');
      expect(await c.saveBirthDate(DateTime.utc(1996, 3, 27)), isTrue);
    }
    expect(await c.sendCode(phoneE164: _phone, countryIso: 'GH'), isNull);
    return c;
  }

  test('a dormant number: DM1, then a fresh start and a new code make a new '
      'account with the name and date already typed', () async {
    final rig = _Rig(prefs);
    final c = await atCode(rig, SignUpEntry.newAccount);
    rig.refuse('account_dormant:$_nonce');
    expect(await c.verify('123456'), isA<VerifiedDormant>());
    expect(rig.auth.signOuts, 0);
    expect(
      prefs.getKeys().map((k) => '${prefs.get(k)}').join(' '),
      isNot(contains(_nonce)),
      reason: 'the challenge never reaches the phone\'s storage',
    );

    expect(await c.startFresh(), FreshStartOutcome.done);
    expect(rig.fresh.nonces, [_nonce]);
    expect(c.draft.entry, SignUpEntry.newAccount);
    expect(c.draft.lastSentAt, isNull, reason: 'DM2 sends a new code');
    expect(c.draft.phoneE164, _phone);

    expect(await c.sendCode(), isNull);
    expect(rig.sender.sent.last.$1, _phone);
    rig.auth
      ..failVerifyWith = null
      ..verifiesAs = 'u-new';
    final outcome = await c.verify('123456');
    expect(outcome, isA<VerifiedNew>());
    expect((outcome as VerifiedNew).next, SignUpStepId.consent);
  });

  test('"I already have an account" on a dormant number: after the fresh '
      'start, A1 and A2, never N1', () async {
    final rig = _Rig(prefs);
    final c = await atCode(rig, SignUpEntry.returning);
    rig.refuse('account_dormant:$_nonce');
    expect(await c.verify('123456'), isA<VerifiedDormant>());
    expect(await c.startFresh(), FreshStartOutcome.done);
    expect(await c.sendCode(), isNull);
    rig.auth.failVerifyWith = null;
    final outcome = await c.verify('123456');
    expect((outcome as VerifiedNew).next, SignUpStepId.name);
  });

  test(
    'a used or expired challenge: A3 with the number open; nothing is kept',
    () async {
      final rig = _Rig(prefs);
      final c = await atCode(rig, SignUpEntry.newAccount);
      rig.refuse('account_dormant:$_nonce');
      await c.verify('123456');
      rig.fresh.results.add(FreshStartResult.invalid);
      expect(await c.startFresh(), FreshStartOutcome.expired);
      expect(c.phoneForA3, _phone);
      expect(c.draft.phoneE164, isNull);
      expect(
        await c.startFresh(),
        FreshStartOutcome.expired,
        reason: 'the challenge is gone',
      );
      expect(rig.fresh.nonces, hasLength(1));
    },
  );

  test(
    'offline or too many tries: DM1 stays, and the same challenge is tried again',
    () async {
      final rig = _Rig(prefs);
      final c = await atCode(rig, SignUpEntry.newAccount);
      rig.refuse('account_dormant:$_nonce');
      await c.verify('123456');
      rig.fresh.results.addAll([
        FreshStartResult.unavailable,
        FreshStartResult.tryLater,
      ]);
      expect(await c.startFresh(), FreshStartOutcome.failed);
      expect(await c.startFresh(), FreshStartOutcome.tryLater);
      expect(await c.startFresh(), FreshStartOutcome.done);
      expect(rig.fresh.nonces, [_nonce, _nonce, _nonce]);
    },
  );

  test(
    'an age hold: H1, the draft gone and the phone blocked (W3 carry C-2)',
    () async {
      final rig = _Rig(prefs);
      final c = await atCode(rig, SignUpEntry.newAccount);
      rig.refuse('account_review:age');
      final outcome = await c.verify('123456');
      expect(outcome, isA<VerifiedHeld>());
      expect((outcome as VerifiedHeld).age, isTrue);
      expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
      expect(rig.drafts.read(), isNull);
    },
  );

  test(
    'a safety or recovery hold: H1 and the draft gone; the phone is not blocked',
    () async {
      final rig = _Rig(prefs);
      final c = await atCode(rig, SignUpEntry.returning);
      rig.refuse('account_review');
      final outcome = await c.verify('123456');
      expect((outcome as VerifiedHeld).age, isFalse);
      expect(AgeGateStore.readBlocked(prefs, _now), isFalse);
      expect(rig.drafts.read(), isNull);
    },
  );

  test(
    'a wrong code is still a wrong code (the hook\'s 403s are told apart)',
    () async {
      final rig = _Rig(prefs);
      final c = await atCode(rig, SignUpEntry.newAccount);
      final outcome = await c.verify('000000');
      expect((outcome as VerifyFailed).failure, OtpVerifyFailure.wrongCode);
    },
  );
}

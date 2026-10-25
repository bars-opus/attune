// Spec 1 W2b (§3.3, §3.4, §3.6, §7.3): the sign-up's decisions — resume
// at A4, under 18 writes nothing, an existing account discards the draft,
// N1, the queued A5 and the server's under-18 refusal.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_coordinator.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/domain/otp_failure.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/fake_account_gateway.dart';
import '../../../helpers/fake_sign_up.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
final _adult = DateTime.utc(1996, 3, 27);
const _phone = '+233244123456';

class _ClearFails extends SignUpDraftStore {
  _ClearFails(super.prefs, {super.now});

  @override
  Future<void> clear() async => throw StateError('disk full');
}

class _Rig {
  _Rig(
    this.prefs, {
    String? signedInAs,
    Map<String, dynamic>? home,
    String? name,
  }) : auth = FakeSignUpAuth(userId: signedInAs),
       gateway = FakeAccountGateway(homeState: home, name: name);

  final SharedPreferences prefs;
  final sender = FakeCodeSender();
  final FakeSignUpAuth auth;
  final FakeAccountGateway gateway;
  final metrics = <String>[];

  /// The phone's clock; a test may move it on (the app left running).
  DateTime clock = _now;

  SignUpDraftStore get drafts => SignUpDraftStore(prefs, now: () => clock);
  OnboardingStore store(String uid) =>
      OnboardingStore(prefs, scope: 'user.$uid');

  /// The draft as written on the phone, read without the store's 7-day
  /// clean-up (so looking never deletes it).
  SignUpDraft? get stored => SignUpDraft.fromJson(
    jsonDecode(prefs.getString(SignUpDraftStore.key) ?? 'null'),
  );

  SignUpCoordinator coordinator({
    Duration callTimeout = SignUpCoordinator.callTimeout,
  }) => SignUpCoordinator(
    drafts: drafts,
    sender: sender,
    auth: auth,
    accounts: AccountService(gateway),
    ageGate: AgeGateStore(prefs, now: () => clock),
    onboardingStoreFor: store,
    metrics: MetricCounter((key) async => metrics.add(key)),
    now: () => clock,
    timeout: callTimeout,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<SignUpCoordinator> throughCode(_Rig rig) async {
    final c = rig.coordinator();
    expect(c.start(SignUpEntry.newAccount), SignUpStepId.name);
    await c.saveName('Ɛsi');
    expect(await c.saveBirthDate(_adult), isTrue);
    expect(c.afterBirthDate, SignUpStepId.phone);
    expect(await c.sendCode(phoneE164: _phone, countryIso: 'GH'), isNull);
    return c;
  }

  test('a new account: name, date, phone, code, consent, done', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = await throughCode(rig);
    expect(rig.sender.sent.single.$1, _phone);
    expect(rig.sender.sent.single.$3, c.draft.deviceNonce);
    expect(c.draft.sendCount, 1);

    final outcome = await c.verify('123456');
    expect(outcome, isA<VerifiedNew>());
    expect((outcome as VerifiedNew).next, SignUpStepId.consent);

    expect(await c.complete(), CompleteOutcome.done);
    expect(rig.gateway.count('complete_sign_up'), 1);
    expect(
      rig.drafts.read(),
      isNull,
      reason: 'the draft goes once the account exists',
    );
    expect(rig.store('u1').displayName, 'Ɛsi');
    expect(rig.store('u1').pendingSignUp, isNull);
    expect(rig.metrics, [
      'signup_started',
      'signup_step:name',
      'signup_step:dob',
      'signup_step:phone',
    ]);
  });

  test('under 18 at A2 writes nothing anywhere and blocks the phone', () async {
    final rig = _Rig(prefs);
    final c = rig.coordinator();
    c.start(SignUpEntry.newAccount);
    await c.saveName('Kid');
    expect(await c.saveBirthDate(DateTime.utc(2008, 10, 26)), isFalse);
    expect(rig.sender.sent, isEmpty);
    expect(rig.gateway.calls, isEmpty);
    expect(rig.drafts.read(), isNull);
    expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
    expect(rig.metrics.last, 'signup_age_stop');
  });

  test('an 18th birthday on the UTC date gets in', () async {
    final rig = _Rig(prefs);
    final c = rig.coordinator();
    c.start(SignUpEntry.newAccount);
    expect(await c.saveBirthDate(DateTime.utc(2008, 10, 25)), isTrue);
  });

  test('closing the app after a code was sent resumes at A4', () async {
    final rig = _Rig(prefs);
    await throughCode(rig);
    final reopened = rig.coordinator();
    expect(reopened.start(SignUpEntry.newAccount), SignUpStepId.code);
    expect(reopened.draft.name, 'Ɛsi');
    expect(reopened.draft.sendCount, 1);
  });

  test(
    'verified but closed before A5 resumes at A5 for that account only',
    () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = await throughCode(rig);
      await c.verify('123456');
      expect(
        rig.coordinator().start(SignUpEntry.newAccount),
        SignUpStepId.consent,
      );
      rig.auth.userId = 'someone-else';
      final other = rig.coordinator();
      expect(
        other.start(SignUpEntry.newAccount),
        SignUpStepId.code,
        reason:
            'review B5 I-1: that account is checked first, never A5 at once',
      );
      expect(other.needsAccountCheck, isTrue);
      expect(other.draft.verifiedUserId, 'someone-else');

      // Ruling C4 (as amended by fix round 5): the session is gone (signed
      // out, or W1's hourly purge of an unfinished account): the code and
      // the account go, and A3 opens on the number for a new code, A1–A2
      // set aside for it (shown nowhere, kept nowhere on the phone).
      await c.verify('123456');
      expect(rig.drafts.read()!.verifiedUserId, 'u1');
      rig.auth.userId = null;
      final reopened = rig.coordinator();
      expect(reopened.start(SignUpEntry.newAccount), SignUpStepId.phone);
      expect(reopened.draft.verifiedUserId, isNull);
      expect(reopened.draft.name, isNull);
      expect(reopened.phoneForA3, _phone);
      expect(reopened.draft.accountChecked, isFalse);
      expect(rig.drafts.read(), isNull, reason: 'nothing left on the phone');
      expect(await reopened.sendCode(phoneE164: _phone), isNull);
      expect(reopened.draft.name, 'Ɛsi', reason: 'the same number');
    },
  );

  test('an existing account discards the typed name and date', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(needs: ['consent']),
      name: 'Kofi Mensah',
    );
    final c = await throughCode(rig);
    final outcome = await c.verify('123456') as VerifiedExisting;
    expect(outcome.firstName, 'Kofi');
    expect(outcome.needsConsent, isTrue);
    expect(rig.drafts.read(), isNull);
    expect(rig.gateway.count('complete_sign_up'), 0);
    expect(rig.store('u1').displayName, 'Kofi Mensah');

    await c.acceptUpdatedTerms();
    expect(rig.gateway.calls.last.$1, 'record_eula_acceptance');
  });

  test('a stored phone number is never used as a first name', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(),
      name: '+233 24 412',
    );
    final c = await throughCode(rig);
    final outcome = await c.verify('123456') as VerifiedExisting;
    expect(outcome.firstName, isNull);
    expect(
      rig.store('u1').displayName,
      isNull,
      reason: 'nor kept as the name onboarding would skip asking for',
    );
  });

  test('C8: "Welcome back" reads the stored name as the server normalises it, '
      'and remembers that', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(),
      name: '\u202EKofi\u200B  Mensah ',
    );
    final c = await throughCode(rig);
    final outcome = await c.verify('123456') as VerifiedExisting;
    expect(outcome.firstName, 'Kofi');
    expect(rig.store('u1').displayName, 'Kofi Mensah');
  });

  test('C8: a stored name with nothing visible greets without a name and is '
      'not remembered', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(),
      name: '\u200B \u2066',
    );
    final c = await throughCode(rig);
    final outcome = await c.verify('123456') as VerifiedExisting;
    expect(outcome.firstName, isNull);
    expect(rig.store('u1').displayName, isNull);
  });

  test('returning with no account: N1, then name and date, then A5', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = rig.coordinator();
    expect(c.start(SignUpEntry.returning), SignUpStepId.phone);
    await c.sendCode(phoneE164: _phone, countryIso: 'GH');
    final outcome = await c.verify('123456') as VerifiedNew;
    expect(outcome.next, SignUpStepId.noAccount);
    await c.saveName('Ama');
    await c.saveBirthDate(_adult);
    expect(
      c.afterBirthDate,
      SignUpStepId.consent,
      reason: 'the number is already verified',
    );
  });

  test(
    'N1 "Use a different number" signs out and forgets the number',
    () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = rig.coordinator();
      c.start(SignUpEntry.returning);
      await c.sendCode(phoneE164: _phone, countryIso: 'GH');
      await c.verify('123456');
      await c.useDifferentNumber();
      expect(rig.auth.signOuts, 1);
      expect(c.draft.phoneE164, isNull);
      expect(c.draft.verifiedUserId, isNull);
    },
  );

  test('offline at A5 the call is queued and the flow carries on', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = await throughCode(rig);
    await c.verify('123456');
    rig.gateway.failWith = TimeoutException('offline');
    expect(await c.complete(), CompleteOutcome.queued);
    expect(rig.store('u1').pendingSignUp!.displayName, 'Ɛsi');
    expect(rig.store('u1').pendingSignUp!.birthDate, _adult);
    expect(rig.drafts.read(), isNull);
  });

  test("the server's under-18 refusal signs out, forgets and blocks", () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = await throughCode(rig);
    await c.verify('123456');
    rig.gateway.failWith = FakeAccountGateway.refusal('signup:not_eligible');
    expect(await c.complete(), CompleteOutcome.notEligible);
    expect(rig.auth.signOuts, 1);
    expect(rig.drafts.read(), isNull);
    expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
  });

  test('"Not now" signs out and leaves nothing to resume', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = await throughCode(rig);
    await c.verify('123456');
    await c.notNow();
    expect(rig.auth.signOuts, 1);
    expect(
      rig.drafts.read(),
      isNull,
      reason: 'P-18 as amended by fix round 5: nothing is kept',
    );
    expect(rig.gateway.count('complete_sign_up'), 0);
  });

  test('a wrong code and a failed send are told apart', () async {
    final rig = _Rig(prefs);
    final c = await throughCode(rig);
    final wrong = await c.verify('000000') as VerifyFailed;
    expect(wrong.failure, OtpVerifyFailure.wrongCode);

    rig.sender.failNext = const AuthException('otp:rate_limited:120');
    final failure = await c.sendCode();
    expect(failure!.kind, OtpSendFailureKind.rateLimited);
    expect(failure.minutes, 2);
    expect(c.draft.sendCount, 1, reason: 'a failed resend changes nothing');

    expect(await c.sendCode(), isNull);
    expect(c.draft.sendCount, 2);
  });

  test('a new number restarts the ladder', () async {
    final rig = _Rig(prefs);
    final c = await throughCode(rig);
    await c.sendCode();
    expect(c.draft.sendCount, 2);
    await c.changeNumber();
    expect(
      await c.sendCode(phoneE164: '+447911123456', countryIso: 'GB'),
      isNull,
    );
    expect(c.draft.sendCount, 1);
    expect(c.draft.phoneE164, '+447911123456');
  });

  test('a send or a check that never answers is bounded, and changes '
      'nothing (B4 M-1 carry)', () async {
    final rig = _Rig(
      prefs,
      home: FakeAccountGateway.account(hasAccount: false),
    );
    final c = rig.coordinator(callTimeout: const Duration(milliseconds: 20));
    c.start(SignUpEntry.newAccount);
    await c.saveName('Ɛsi');
    await c.saveBirthDate(_adult);

    rig.sender.hold = Completer<void>();
    final failure = await c.sendCode(phoneE164: _phone, countryIso: 'GH');
    expect(failure!.kind, OtpSendFailureKind.unavailable);
    expect(c.draft.sendCount, 0);
    expect(c.draft.lastSentAt, isNull, reason: 'nothing to resume at A4');
    rig.sender.hold!.complete();
    rig.sender.hold = null;

    expect(await c.sendCode(phoneE164: _phone, countryIso: 'GH'), isNull);
    rig.auth.holdVerify = Completer<void>();
    final check = await c.verify('123456') as VerifyFailed;
    expect(check.failure, OtpVerifyFailure.unavailable);
    expect(c.draft.verifiedUserId, isNull);
    rig.auth.holdVerify!.complete();
  });

  group('review B5 fix round 1', () {
    test('I-1: signed in with no draft and no account: the account is '
        'checked, then A1, A2 and A5, and no code is ever sent', () async {
      final rig = _Rig(
        prefs,
        signedInAs: 'u1',
        home: FakeAccountGateway.account(hasAccount: false),
      );
      rig.auth.phone = _phone;
      final c = rig.coordinator();
      expect(c.start(SignUpEntry.newAccount), SignUpStepId.code);
      expect(c.needsAccountCheck, isTrue);
      expect(c.draft.phoneE164, _phone, reason: "the session's own number");
      expect(
        rig.drafts.read()!.verifiedUserId,
        'u1',
        reason: 'saved, so the router holds /home until A5',
      );
      final outcome = await c.resolveVerified() as VerifiedNew;
      expect(outcome.next, SignUpStepId.name);
      await c.saveName('Ama');
      expect(await c.saveBirthDate(_adult), isTrue);
      expect(c.afterBirthDate, SignUpStepId.consent);
      expect(await c.complete(), CompleteOutcome.done);
      expect(rig.sender.sent, isEmpty);
      expect(rig.gateway.count('complete_sign_up'), 1);
    });

    test(
      'I-1: signed in on an account that needs consent: A5c, no code',
      () async {
        final rig = _Rig(
          prefs,
          signedInAs: 'u1',
          home: FakeAccountGateway.account(needs: ['consent']),
          name: 'Kofi',
        );
        final c = rig.coordinator();
        expect(c.start(SignUpEntry.returning), isNot(SignUpStepId.phone));
        final outcome = await c.resolveVerified() as VerifiedExisting;
        expect(outcome.needsConsent, isTrue);
        expect(outcome.firstName, 'Kofi');
        expect(rig.sender.sent, isEmpty);
        expect(rig.drafts.read(), isNull, reason: 'nothing to resume');
      },
    );

    test('I-1: signed in, returning, no account: N1 without a code', () async {
      final rig = _Rig(
        prefs,
        signedInAs: 'u1',
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = rig.coordinator();
      expect(c.start(SignUpEntry.returning), SignUpStepId.code);
      final outcome = await c.resolveVerified() as VerifiedNew;
      expect(outcome.next, SignUpStepId.noAccount);
      expect(rig.sender.sent, isEmpty);
    });

    test('I-2: a check that failed, then the app closed: the account is '
        'checked again, never A5 on an existing account', () async {
      // get_my_home_state unreadable at first.
      final rig = _Rig(prefs, name: 'Kofi Mensah');
      final c = await throughCode(rig);
      expect(await c.verify('123456'), isA<VerifiedUnresolved>());

      rig.gateway.homeState = FakeAccountGateway.account(needs: ['consent']);
      final reopened = rig.coordinator();
      expect(
        reopened.start(SignUpEntry.newAccount),
        isNot(SignUpStepId.consent),
      );
      expect(reopened.needsAccountCheck, isTrue);
      expect(await reopened.resolveVerified(), isA<VerifiedExisting>());
      expect(rig.gateway.count('complete_sign_up'), 0);
      expect(rig.drafts.read(), isNull, reason: 'what was typed is discarded');
      expect(rig.store('u1').displayName, 'Kofi Mensah');
    });

    test('I-2: returning: never N1 for someone who has an account', () async {
      final rig = _Rig(prefs);
      final c = rig.coordinator();
      c.start(SignUpEntry.returning);
      await c.sendCode(phoneE164: _phone, countryIso: 'GH');
      expect(await c.verify('123456'), isA<VerifiedUnresolved>());

      rig.gateway.homeState = FakeAccountGateway.account();
      final reopened = rig.coordinator();
      expect(
        reopened.start(SignUpEntry.returning),
        isNot(SignUpStepId.noAccount),
      );
      expect(await reopened.resolveVerified(), isA<VerifiedExisting>());
    });

    test(
      'I-2: once checked as no account, a reopen goes straight on',
      () async {
        final rig = _Rig(
          prefs,
          home: FakeAccountGateway.account(hasAccount: false),
        );
        final c = await throughCode(rig);
        await c.verify('123456');
        expect(rig.drafts.read()!.accountChecked, isTrue);
        final reopened = rig.coordinator();
        expect(reopened.start(SignUpEntry.newAccount), SignUpStepId.consent);
        expect(reopened.needsAccountCheck, isFalse);
      },
    );

    test('I-3: under 18 at A2 after N1 ends the verified session: blocked, '
        'nothing kept, signed out', () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = rig.coordinator();
      c.start(SignUpEntry.returning);
      await c.sendCode(phoneE164: _phone, countryIso: 'GH');
      expect(
        (await c.verify('123456') as VerifiedNew).next,
        SignUpStepId.noAccount,
      );
      await c.saveName('Kid');
      expect(await c.saveBirthDate(DateTime.utc(2012, 1, 1)), isFalse);
      expect(rig.auth.signOuts, 1);
      expect(rig.auth.currentUserId, isNull);
      expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
      expect(rig.drafts.read(), isNull);
    });

    test('I-3: signed out at A2, the stop has nobody to sign out', () async {
      final rig = _Rig(prefs);
      final c = rig.coordinator();
      c.start(SignUpEntry.newAccount);
      expect(await c.saveBirthDate(DateTime.utc(2012, 1, 1)), isFalse);
      expect(rig.auth.signOuts, 0);
    });

    test("I-4: the server's under-18 refusal with a sign-out that throws "
        'still blocks and forgets', () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = await throughCode(rig);
      await c.verify('123456');
      rig.auth.failSignOut = true;
      rig.gateway.failWith = FakeAccountGateway.refusal('signup:not_eligible');
      expect(await c.complete(), CompleteOutcome.notEligible);
      expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
      expect(rig.drafts.read(), isNull);
    });

    test('I-4: the A2 stop with a sign-out that throws still blocks and '
        'forgets', () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = rig.coordinator();
      c.start(SignUpEntry.returning);
      await c.sendCode(phoneE164: _phone, countryIso: 'GH');
      await c.verify('123456');
      rig.auth.failSignOut = true;
      expect(await c.saveBirthDate(DateTime.utc(2012, 1, 1)), isFalse);
      expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
      expect(rig.drafts.read(), isNull);
    });

    test('I-4: a draft that cannot be deleted still leaves the block set '
        'and the session ended, and X1 still shows', () async {
      final rig = _Rig(
        prefs,
        signedInAs: 'u1',
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = SignUpCoordinator(
        drafts: _ClearFails(prefs, now: () => _now),
        sender: rig.sender,
        auth: rig.auth,
        accounts: AccountService(rig.gateway),
        ageGate: AgeGateStore(prefs, now: () => _now),
        onboardingStoreFor: rig.store,
        metrics: MetricCounter((key) async {}),
        now: () => _now,
      );
      c.start(SignUpEntry.newAccount);
      await c.resolveVerified();
      expect(await c.saveBirthDate(DateTime.utc(2012, 1, 1)), isFalse);
      expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
      expect(rig.auth.signOuts, 1);
    });

    test(
      'M-1: "Not now" on A5c leaves the discarded draft discarded',
      () async {
        final rig = _Rig(
          prefs,
          home: FakeAccountGateway.account(needs: ['consent']),
          name: 'Kofi',
        );
        final c = await throughCode(rig);
        expect(await c.verify('123456'), isA<VerifiedExisting>());
        await c.notNow();
        expect(rig.auth.signOuts, 1);
        expect(rig.drafts.read(), isNull);
      },
    );

    test('M-6: a check that signs in after its timeout is used, not asked '
        'again', () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = rig.coordinator(callTimeout: const Duration(milliseconds: 20));
      c.start(SignUpEntry.newAccount);
      await c.saveName('Ama');
      await c.saveBirthDate(_adult);
      await c.sendCode(phoneE164: _phone, countryIso: 'GH');

      rig.auth.holdVerify = Completer<void>();
      final lost = await c.verify('123456') as VerifyFailed;
      expect(lost.failure, OtpVerifyFailure.unavailable);
      rig.auth.holdVerify!.complete();
      rig.auth.holdVerify = null;
      await Future<void>.delayed(Duration.zero);
      expect(rig.auth.currentUserId, 'u1', reason: 'it landed after all');

      final outcome = await c.verify('123456');
      expect(outcome, isA<VerifiedNew>());
      expect(rig.auth.verifyCalls, 1, reason: 'the code is spent');
      expect(c.draft.verifiedUserId, 'u1');
    });

    test('M-6: a check that times out and lands nowhere asks again', () async {
      final rig = _Rig(prefs);
      final c = rig.coordinator(callTimeout: const Duration(milliseconds: 20));
      c.start(SignUpEntry.newAccount);
      await c.sendCode(phoneE164: _phone, countryIso: 'GH');
      rig.auth.holdVerify = Completer<void>();
      await c.verify('123456');
      rig.auth.holdVerify = null;
      expect(await c.verify('000000'), isA<VerifyFailed>());
      expect(rig.auth.verifyCalls, 2);
    });

    test('M-7: the session gone at A5: back to A3 for a new code, A1–A2 '
        'set aside for the same number (fix round 4)', () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = await throughCode(rig);
      await c.verify('123456');
      rig.auth.userId = null;
      expect(await c.complete(), CompleteOutcome.signedOut);
      expect(c.draft.verifiedUserId, isNull);
      expect(c.draft.awaitingCode, isFalse);
      expect(c.draft.name, isNull, reason: 'Back to A1/A2 shows nothing');
      expect(c.phoneForA3, _phone);
      expect(rig.drafts.read(), isNull, reason: 'no code left sent (round 5)');
      expect(rig.gateway.count('complete_sign_up'), 0);
      expect(await c.sendCode(phoneE164: _phone, countryIso: 'GH'), isNull);
      expect(c.draft.name, 'Ɛsi', reason: 'the same number brings them back');
    });
  });

  group('review B5 fix round 2 (I-6)', () {
    final adultA = DateTime.utc(1990, 5, 5);
    final adultB = DateTime.utc(1995, 8, 1);
    const phoneA = '+233244111111';
    const phoneB = '+233244222222';

    String? sentDob(FakeAccountGateway gateway) =>
        [
          for (final (fn, params) in gateway.calls)
            if (fn == 'complete_sign_up') params!['p_birth_date'] as String,
        ].lastOrNull;

    /// Person A: A1, A2 (adult), A3 to number A, A4 (no account), then
    /// "Not now" at A5. Since fix round 5 nothing stays on the phone.
    Future<_Rig> leftByA() async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      rig.auth.verifiesAs = 'uA';
      final a = rig.coordinator();
      expect(a.start(SignUpEntry.newAccount), SignUpStepId.name);
      await a.saveName('Adult A');
      expect(await a.saveBirthDate(adultA), isTrue);
      expect(await a.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      expect(
        (await a.verify('123456') as VerifiedNew).next,
        SignUpStepId.consent,
      );
      await a.notNow();
      expect(rig.drafts.read(), isNull);
      return rig;
    }

    test(
      'Q1: "I already have an account" with B\'s own number never '
      'carries A\'s name and date to A5: N1, then B\'s own A1 and A2',
      () async {
        final rig = await leftByA();
        rig.auth.verifiesAs = 'uB';
        final b = rig.coordinator();
        expect(b.start(SignUpEntry.returning), SignUpStepId.phone);
        expect(b.draft.name, isNull);
        expect(b.draft.birthDate, isNull);
        expect(await b.sendCode(phoneE164: phoneB, countryIso: 'GH'), isNull);
        expect(
          (await b.verify('123456') as VerifiedNew).next,
          SignUpStepId.noAccount,
        );
        expect(rig.gateway.count('complete_sign_up'), 0);
        await b.saveName('B');
        expect(await b.saveBirthDate(adultB), isTrue);
        expect(b.afterBirthDate, SignUpStepId.consent);
        expect(await b.complete(), CompleteOutcome.done);
        expect(sentDob(rig.gateway), '1995-08-01');
      },
    );

    for (final (entry, next) in [
      (SignUpEntry.newAccount, SignUpStepId.name),
      (SignUpEntry.returning, SignUpStepId.noAccount),
    ]) {
      test('Q2: a session on another number adopts the draft without A\'s '
          'name and date (${entry.wire}: $next)', () async {
        final rig = await leftByA();
        rig.auth
          ..userId = 'uB'
          ..phone = phoneB;
        final b = rig.coordinator();
        expect(b.start(entry), SignUpStepId.code);
        expect(b.draft.name, isNull);
        expect(b.draft.birthDate, isNull);
        expect((await b.resolveVerified() as VerifiedNew).next, next);
        expect(
          await b.complete(),
          CompleteOutcome.failed,
          reason: 'no date of birth until B gives one at A2',
        );
        expect(rig.gateway.count('complete_sign_up'), 0);
        expect(rig.sender.sent, hasLength(1), reason: "only A's own code");
      });
    }

    test('Q2: the same number signed in (LoginScreen\'s sheet): A1–A2 kept, '
        'A5 at once, no second code', () async {
      // A left at A4 (a code sent, so A1–A3 are on the phone), then signed
      // in on that same number elsewhere.
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final left = rig.coordinator()..start(SignUpEntry.newAccount);
      await left.saveName('Adult A');
      await left.saveBirthDate(adultA);
      await left.sendCode(phoneE164: phoneA, countryIso: 'GH');
      rig.auth
        ..userId = 'uA'
        ..phone = phoneA;
      final a = rig.coordinator();
      expect(a.start(SignUpEntry.newAccount), SignUpStepId.code);
      expect(a.draft.birthDate, adultA);
      expect(
        (await a.resolveVerified() as VerifiedNew).next,
        SignUpStepId.consent,
      );
      expect(await a.complete(), CompleteOutcome.done);
      expect(sentDob(rig.gateway), '1990-05-05');
      expect(rig.sender.sent, hasLength(1), reason: "A's code only, no second");
    });

    test(
      'a session whose number is unknown never inherits a name and date',
      () async {
        final rig = await leftByA();
        rig.auth.userId = 'uB';
        final b = rig.coordinator();
        expect(b.start(SignUpEntry.newAccount), SignUpStepId.code);
        expect(b.draft.birthDate, isNull);
      },
    );

    test("A's own resume is untouched: a code on its way resumes at A4, "
        'even by "I already have an account", and A5 follows', () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final a = rig.coordinator();
      a.start(SignUpEntry.newAccount);
      await a.saveName('Adult A');
      await a.saveBirthDate(adultA);
      await a.sendCode(phoneE164: phoneA, countryIso: 'GH');
      final reopened = rig.coordinator();
      expect(reopened.start(SignUpEntry.returning), SignUpStepId.code);
      expect(reopened.draft.birthDate, adultA);
      expect(
        (await reopened.verify('123456') as VerifiedNew).next,
        SignUpStepId.consent,
      );
    });

    test('a new-account visit after "Not now" shows nothing of the earlier '
        'attempt (fix round 5: path 6 closed)', () async {
      final rig = await leftByA();
      final again = rig.coordinator();
      expect(again.start(SignUpEntry.newAccount), SignUpStepId.name);
      expect(again.draft.name, isNull);
      expect(again.draft.birthDate, isNull);
      expect(again.afterBirthDate, SignUpStepId.phone);
    });
  });

  group('review B5 fix round 3 (I-7)', () {
    final adultA = DateTime.utc(1990, 5, 5);
    final adultB = DateTime.utc(1995, 8, 1);
    const phoneA = '+233244111111';
    const phoneB = '+233244222222';

    List<String> sentDobs(FakeAccountGateway gateway) => [
      for (final (fn, params) in gateway.calls)
        if (fn == 'complete_sign_up') params!['p_birth_date'] as String,
    ];

    /// Person A: A1, A2 (adult), A3 to number A, then closes the app at
    /// A4. The draft resumes at A4 for its 7 days.
    Future<_Rig> leftAtA4() async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final a = rig.coordinator();
      a.start(SignUpEntry.newAccount);
      await a.saveName('Adult A');
      expect(await a.saveBirthDate(adultA), isTrue);
      expect(await a.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      expect(rig.drafts.read()!.awaitingCode, isTrue);
      return rig;
    }

    for (final entry in SignUpEntry.values) {
      test('(a) a resumed A4, "Change it", another number: A1 and A2 are '
          'asked again and A\'s date is never sent (${entry.wire})', () async {
        final rig = await leftAtA4();
        rig.auth.verifiesAs = 'uB';
        final b = rig.coordinator();
        expect(b.start(entry), SignUpStepId.code);
        await b.changeNumber();
        expect(await b.sendCode(phoneE164: phoneB, countryIso: 'GH'), isNull);
        expect(b.draft.name, isNull);
        expect(b.draft.birthDate, isNull);
        expect(rig.drafts.read()!.birthDate, isNull, reason: 'saved too');
        final next = (await b.verify('123456') as VerifiedNew).next;
        expect(next, anyOf(SignUpStepId.name, SignUpStepId.noAccount));
        expect(rig.gateway.count('complete_sign_up'), 0);
        await b.saveName('B');
        expect(await b.saveBirthDate(adultB), isTrue);
        expect(b.afterBirthDate, SignUpStepId.consent);
        expect(await b.complete(), CompleteOutcome.done);
        expect(sentDobs(rig.gateway), ['1995-08-01']);
      });
    }

    test('(b → h, fix round 4) A fixing a typo in the number retypes A1 and '
        "A2 after the code (the ruled cost), then A5 sends A's date", () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final a = rig.coordinator();
      a.start(SignUpEntry.newAccount);
      await a.saveName('Adult A');
      await a.saveBirthDate(adultA);
      await a.sendCode(phoneE164: '+233244111112', countryIso: 'GH');
      await a.changeNumber();
      expect(await a.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      expect(a.draft.name, isNull);
      expect(a.draft.birthDate, isNull);
      expect((await a.verify('123456') as VerifiedNew).next, SignUpStepId.name);
      await a.saveName('Adult A');
      expect(await a.saveBirthDate(adultA), isTrue);
      expect(a.afterBirthDate, SignUpStepId.consent);
      expect(await a.complete(), CompleteOutcome.done);
      expect(sentDobs(rig.gateway), ['1990-05-05']);
    });

    test('(c) a resumed A4 on the same number keeps A1 and A2: a resend, '
        'the code, then A5', () async {
      final rig = await leftAtA4();
      final a = rig.coordinator();
      expect(a.start(SignUpEntry.returning), SignUpStepId.code);
      expect(await a.sendCode(), isNull, reason: 'a resend, same number');
      expect(a.draft.birthDate, adultA);
      expect(
        (await a.verify('123456') as VerifiedNew).next,
        SignUpStepId.consent,
      );
    });

    test('(c) "Change it" then the same number again keeps them too', () async {
      final rig = await leftAtA4();
      final a = rig.coordinator();
      a.start(SignUpEntry.newAccount);
      await a.changeNumber();
      expect(await a.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      expect(a.draft.birthDate, adultA);
    });

    test('a date given again after "Change it" goes with the number sent '
        "next; A's name never does (fix round 4)", () async {
      final rig = await leftAtA4();
      final b = rig.coordinator();
      b.start(SignUpEntry.newAccount);
      await b.changeNumber();
      await b.saveBirthDate(adultB);
      expect(await b.sendCode(phoneE164: phoneB, countryIso: 'GH'), isNull);
      expect(b.draft.birthDate, adultB);
      expect(b.draft.name, isNull, reason: "A's name stays with A's number");
    });

    test('the search: A5 never completes for a session other than the one '
        'the draft was verified for', () async {
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final a = await throughCode(rig);
      await a.verify('123456');
      final resumed = rig.coordinator();
      expect(resumed.start(SignUpEntry.newAccount), SignUpStepId.consent);
      rig.auth.userId = 'someone-else';
      expect(await resumed.complete(), CompleteOutcome.signedOut);
      expect(rig.gateway.count('complete_sign_up'), 0);
      expect(resumed.draft.verifiedUserId, isNull);
      // A3 next: another number drops A1/A2 (fix round 4: always).
      expect(
        await resumed.sendCode(phoneE164: '+447911123456', countryIso: 'GB'),
        isNull,
      );
      expect(resumed.draft.birthDate, isNull);
    });
  });

  group('review B5 fix round 4 (I-8: A1/A2 are bound to their number)', () {
    final adultA = DateTime.utc(1990, 5, 5);
    final adultB = DateTime.utc(1995, 8, 1);
    const phoneA = '+233244111111';
    const phoneB = '+233244222222';

    List<(Object?, Object?)> sent(FakeAccountGateway gateway) => [
      for (final (fn, params) in gateway.calls)
        if (fn == 'complete_sign_up')
          (params!['p_display_name'], params['p_birth_date']),
    ];

    /// Neither A1 nor A2 on the draft: in memory, and as written.
    void expectNoNameOrDate(_Rig rig, SignUpCoordinator c, {String? why}) {
      expect(c.draft.name, isNull, reason: why);
      expect(c.draft.birthDate, isNull, reason: why);
      expect(rig.stored?.name, isNull, reason: '$why (on the phone)');
      expect(rig.stored?.birthDate, isNull, reason: '$why (on the phone)');
    }

    void expectAs(SignUpCoordinator c, {String? why}) {
      expect(c.draft.name, 'Adult A', reason: why);
      expect(c.draft.birthDate, adultA, reason: why);
    }

    _Rig noAccount() =>
        _Rig(prefs, home: FakeAccountGateway.account(hasAccount: false));

    /// Person A, live: A1, A2 (adult), A3 to number A; this flow is at A4.
    Future<SignUpCoordinator> aAtA4(_Rig rig) async {
      final a = rig.coordinator();
      a.start(SignUpEntry.newAccount);
      await a.saveName('Adult A');
      expect(await a.saveBirthDate(adultA), isTrue);
      expect(await a.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      return a;
    }

    /// Person A verified number A (no account yet), then "Not now" at A5:
    /// since fix round 5 nothing of it stays on the phone.
    Future<void> aNotNow(_Rig rig) async {
      rig.auth.verifiesAs = 'uA';
      final a = await aAtA4(rig);
      await a.verify('123456');
      await a.notNow();
      expect(rig.stored, isNull);
    }

    test(
      '(f) R1: the same flow, the app only in the background for 8 days: '
      "B's new number asks A1 and A2 again, and only B's date is sent",
      () async {
        final rig = noAccount();
        final c = await aAtA4(rig);
        rig.auth.verifiesAs = 'uB';
        rig.clock = rig.clock.add(const Duration(days: 8));
        await c.changeNumber();
        expect(await c.sendCode(phoneE164: phoneB, countryIso: 'GH'), isNull);
        expectNoNameOrDate(rig, c);
        final next = (await c.verify('123456') as VerifiedNew).next;
        expect(next, SignUpStepId.name, reason: 'A1, never A5');
        expect(await c.complete(), CompleteOutcome.failed);
        expect(sent(rig.gateway), isEmpty);
        await c.saveName('B');
        expect(await c.saveBirthDate(adultB), isTrue);
        expect(c.afterBirthDate, SignUpStepId.consent);
        expect(await c.complete(), CompleteOutcome.done);
        expect(sent(rig.gateway), [('B', '1995-08-01')]);
        expect(rig.sender.sent.map((s) => s.$1), [phoneA, phoneB]);
      },
    );

    for (final resumed in [false, true]) {
      test('F2 (the coordinator\'s part): after "Change it" nothing of A\'s '
          'is left on the draft for A1/A2 to show, nor on the phone; A3 still '
          'opens on the number (${resumed ? 'resumed' : 'live'})', () async {
        final rig = noAccount();
        var c = await aAtA4(rig);
        if (resumed) {
          c = rig.coordinator();
          expect(c.start(SignUpEntry.newAccount), SignUpStepId.code);
        }
        await c.changeNumber();
        expectNoNameOrDate(rig, c);
        expect(c.phoneForA3, phoneA);
        expect(rig.stored, isNull, reason: 'no code left sent (round 5)');
        // Closed now and opened again: nothing of A's either.
        final reopened = rig.coordinator();
        expect(reopened.start(SignUpEntry.newAccount), SignUpStepId.name);
        expectNoNameOrDate(rig, reopened);
      });
    }

    test('the same number after "Change it" brings A1 and A2 back; a send to '
        "another number ends that: A's number later brings nothing", () async {
      final rig = noAccount();
      final a = await aAtA4(rig);
      await a.changeNumber();
      expect(await a.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      expectAs(a, why: 'the same number: a no-op');
      expect(rig.stored!.birthDate, adultA);

      await a.changeNumber();
      expect(await a.sendCode(phoneE164: phoneB, countryIso: 'GH'), isNull);
      expectNoNameOrDate(rig, a);
      await a.changeNumber();
      expect(await a.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      expectNoNameOrDate(rig, a, why: 'they went when the number did');
    });

    test('a send to another number that fails changes nothing: A1/A2 stay off '
        'the draft, and come back only with their own number', () async {
      final rig = noAccount();
      final a = await aAtA4(rig);
      await a.changeNumber();
      rig.sender.failNext = StateError('offline');
      expect(await a.sendCode(phoneE164: phoneB, countryIso: 'GH'), isNotNull);
      expectNoNameOrDate(rig, a);
      expect(await a.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      expectAs(a);
    });

    test('"Use a different number" forgets A1/A2 with the number', () async {
      final rig = noAccount();
      final c = rig.coordinator();
      c.start(SignUpEntry.returning);
      await c.sendCode(phoneE164: phoneA, countryIso: 'GH');
      await c.verify('123456');
      await c.saveName('Adult A');
      await c.useDifferentNumber();
      expect(c.draft.phoneE164, isNull);
      expectNoNameOrDate(rig, c);
    });

    test('a check for a session the draft never named binds nothing to it '
        '(the account is checked only for a proven or adopted one)', () async {
      final rig = noAccount();
      final c = await aAtA4(rig);
      rig.auth
        ..userId = 'uB'
        ..phone = phoneB;
      expect(await c.resolveVerified(), isA<VerifyFailed>());
      expect(c.draft.verifiedUserId, isNull);
      expect(await c.complete(), CompleteOutcome.signedOut);
      expect(sent(rig.gateway), isEmpty);
    });

    // Every public call that can move the draft's number, from a draft
    // whose A1/A2 were given for number A. Each returns the coordinator.
    final moves = <String, (String?, Future<SignUpCoordinator> Function(_Rig))>{
      'sendCode: live A4, "Change it", another number': (
        phoneB,
        (rig) async {
          final c = await aAtA4(rig);
          await c.changeNumber();
          await c.sendCode(phoneE164: phoneB, countryIso: 'GH');
          return c;
        },
      ),
      'sendCode: resumed A4, "Change it", another number': (
        phoneB,
        (rig) async {
          await aAtA4(rig);
          final c = rig.coordinator()..start(SignUpEntry.invite);
          await c.changeNumber();
          await c.sendCode(phoneE164: phoneB, countryIso: 'GH');
          return c;
        },
      ),
      'sendCode: A3 after the session went at A5 (M-7), another number': (
        phoneB,
        (rig) async {
          rig.auth.verifiesAs = 'uA';
          final c = await aAtA4(rig);
          await c.verify('123456');
          rig.auth.userId = null;
          expect(await c.complete(), CompleteOutcome.signedOut);
          await c.sendCode(phoneE164: phoneB, countryIso: 'GH');
          return c;
        },
      ),
      'sendCode: a later visit after "Not now", another number': (
        phoneB,
        (rig) async {
          await aNotNow(rig);
          final c = rig.coordinator()..start(SignUpEntry.newAccount);
          await c.sendCode(phoneE164: phoneB, countryIso: 'GH');
          return c;
        },
      ),
      'sendCode: a later visit after the session went (C4), another number': (
        phoneB,
        (rig) async {
          rig.auth.verifiesAs = 'uA';
          final a = await aAtA4(rig);
          await a.verify('123456');
          rig.auth.userId = null;
          final c = rig.coordinator()..start(SignUpEntry.newAccount);
          await c.sendCode(phoneE164: phoneB, countryIso: 'GH');
          return c;
        },
      ),
      'changeNumber: "Wrong number? Change it"': (
        null,
        (rig) async {
          final c = await aAtA4(rig);
          await c.changeNumber();
          return c;
        },
      ),
      'useDifferentNumber: N1': (
        null,
        (rig) async {
          final c = rig.coordinator()..start(SignUpEntry.returning);
          await c.sendCode(phoneE164: phoneA, countryIso: 'GH');
          await c.verify('123456');
          await c.saveName('Adult A');
          await c.saveBirthDate(adultA);
          await c.useDifferentNumber();
          return c;
        },
      ),
      'start: adopted by a session on another number': (
        phoneB,
        (rig) async {
          await aNotNow(rig);
          rig.auth
            ..userId = 'uB'
            ..phone = phoneB;
          return rig.coordinator()..start(SignUpEntry.newAccount);
        },
      ),
      'start: adopted by a session whose number is unknown': (
        null,
        (rig) async {
          await aNotNow(rig);
          rig.auth.userId = 'uB';
          return rig.coordinator()..start(SignUpEntry.newAccount);
        },
      ),
    };

    for (final MapEntry(key: how, value: (to, move)) in moves.entries) {
      test('the rule, by every way in: a different number leaves no name or '
          'date ($how)', () async {
        final rig = noAccount();
        final c = await move(rig);
        expect(c.draft.phoneE164, to, reason: 'the number did move');
        expect(to, isNot(phoneA));
        expectNoNameOrDate(rig, c, why: how);
      });
    }

    final stays = <String, Future<SignUpCoordinator> Function(_Rig)>{
      'a resend on A4': (rig) async {
        final c = await aAtA4(rig);
        await c.sendCode();
        return c;
      },
      '"Change it", then the same number': (rig) async {
        final c = await aAtA4(rig);
        await c.changeNumber();
        await c.sendCode(phoneE164: phoneA, countryIso: 'GH');
        return c;
      },
      'a resumed A4, "Change it", then the same number': (rig) async {
        await aAtA4(rig);
        final c = rig.coordinator()..start(SignUpEntry.returning);
        await c.changeNumber();
        await c.sendCode(phoneE164: phoneA, countryIso: 'GH');
        return c;
      },
      'A3 after the session went at A5 (M-7), the same number': (rig) async {
        rig.auth.verifiesAs = 'uA';
        final c = await aAtA4(rig);
        await c.verify('123456');
        rig.auth.userId = null;
        await c.complete();
        await c.sendCode(phoneE164: phoneA, countryIso: 'GH');
        return c;
      },
      'adopted by a session on the same number': (rig) async {
        await aAtA4(rig);
        rig.auth
          ..userId = 'uA'
          ..phone = phoneA;
        return rig.coordinator()..start(SignUpEntry.newAccount);
      },
    };

    for (final MapEntry(key: how, value: stay) in stays.entries) {
      test('the rule: the same number keeps A1 and A2 ($how)', () async {
        final rig = noAccount();
        final c = await stay(rig);
        expect(c.draft.phoneE164, phoneA);
        expectAs(c, why: how);
        if (c.draft.lastSentAt != null) {
          expect(rig.stored!.birthDate, adultA);
        } else {
          // Adopted, no code sent by this flow: memory only (round 5).
          expect(rig.stored!.birthDate, isNull);
        }
      });
    }

    test('property: in any order of calls (backgrounds, kills and "Not now" '
        'included), complete_sign_up only ever sends a name and a date given '
        'for the number of the account it completes, typed in this session '
        'or kept with a code sent for that number', () async {
      const numbers = [phoneA, phoneB, '+233244333333'];
      String uidOf(String phone) => 'u$phone';
      String? phoneOf(String? uid) => uid?.substring(1);
      var checked = 0;
      var completions = 0;
      var gone = 0;
      for (var seed = 0; seed < 600; seed++) {
        await prefs.clear();
        final rng = Random(seed);
        final rig = noAccount();
        // Each value typed, and the number it was given with (null: none
        // yet; it then binds to the first number its draft is sent to).
        final givenFor = <String, String?>{};
        // Values on the phone with a code sent for their number (they may
        // outlive the app), and values that must never be sent again: gone
        // with a kill or a long background before any code, or with "Not
        // now" (fix round 5).
        final kept = <String>{};
        final dead = <String>{};
        late SignUpCoordinator c;
        List<String> inDraft() => [
          if (c.draft.name case final n?) n,
          if (c.draft.birthDate case final d?) SignUpDraft.dateOnly(d),
        ];
        var serial = 0;
        Future<void> open() async {
          switch (rng.nextInt(3)) {
            case 0:
              rig.auth.userId = null;
            case 1:
              break;
            default:
              final p = numbers[rng.nextInt(numbers.length)];
              rig.auth
                ..userId = uidOf(p)
                ..phone = p;
          }
          c = rig.coordinator();
          c.start(SignUpEntry.values[rng.nextInt(3)]);
          // The flow checks an unread account as it opens.
          if (c.needsAccountCheck) await c.resolveVerified();
        }

        await open();
        // Weighted towards going on (A1, A2, a send, the code, A5), with
        // every other call mixed in: call i is drawn weights[i] times in 23.
        const weights = [2, 2, 3, 1, 2, 3, 3, 1, 1, 1, 1, 1, 1, 1];
        final ops = [
          for (final (op, weight) in weights.indexed)
            ...List.filled(weight, op),
        ];
        for (var step = 0; step < 50; step++) {
          final before = c.draft.phoneE164;
          var reopened = false;
          switch (ops[rng.nextInt(ops.length)]) {
            case 0:
              final name = 'N$seed.${serial++}';
              givenFor[name] = c.draft.phoneE164;
              await c.saveName(name);
            case 1:
              final date = DateTime.utc(1960).add(Duration(days: serial++));
              givenFor[SignUpDraft.dateOnly(date)] = c.draft.phoneE164;
              await c.saveBirthDate(date);
            case 2:
              final p = numbers[rng.nextInt(numbers.length)];
              final ok =
                  await c.sendCode(phoneE164: p, countryIso: 'GH') == null;
              if (ok && before == null) {
                for (final value in [
                  c.draft.name,
                  if (c.draft.birthDate case final d?) SignUpDraft.dateOnly(d),
                ]) {
                  if (value != null && givenFor[value] == null) {
                    givenFor[value] = p;
                  }
                }
              }
            case 3:
              await c.sendCode();
            case 4:
              await c.changeNumber();
            case 5:
              final p = c.draft.phoneE164;
              if (p != null) rig.auth.verifiesAs = uidOf(p);
              final outcome = await c.verify('123456');
              // The session a code signs in has that code's number.
              if (p != null && outcome is! VerifyFailed) rig.auth.phone = p;
            case 6:
              final uid = rig.auth.currentUserId;
              final calls = rig.gateway.count('complete_sign_up');
              final outcome = await c.complete();
              if (rig.gateway.count('complete_sign_up') > calls) {
                completions++;
                final (name, date) = sent(rig.gateway).last;
                expect(
                  (givenFor[name], givenFor[date]),
                  (phoneOf(uid), phoneOf(uid)),
                  reason: 'seed $seed step $step: $name / $date for $uid',
                );
                expect(
                  [name, date].where(dead.contains),
                  isEmpty,
                  reason: 'seed $seed step $step: sent after it was gone',
                );
              }
              if (outcome case CompleteOutcome.done || CompleteOutcome.queued) {
                dead.addAll(givenFor.keys);
                await open();
                reopened = true;
              }
            case 7:
              await c.notNow();
              dead.addAll(givenFor.keys);
              await open();
              reopened = true;
            case 8:
              await c.useDifferentNumber();
            case 9:
              // Closed (or killed) and opened again.
              dead.addAll(givenFor.keys.where((v) => !kept.contains(v)));
              await open();
              reopened = true;
            case 10:
              rig.auth.userId = null;
            case 11:
              await c.resolveVerified();
            case 12:
              c.wentToBackground();
              rig.clock = rig.clock.add(
                Duration(seconds: 1 + rng.nextInt(300)),
              );
              c.cameBack();
            default:
              if (c.draft.lastSentAt == null) dead.addAll(inDraft());
              c.wentToBackground();
              rig.clock = rig.clock.add(
                Duration(seconds: 301 + rng.nextInt(3600)),
              );
              c.cameBack();
          }
          if (c.draft.lastSentAt != null) kept.addAll(inDraft());
          // Rule 1 on the phone itself: a name or date only with a code.
          final stored = rig.stored;
          if (stored != null && stored.lastSentAt == null) {
            expect(stored.name, isNull, reason: 'seed $seed step $step');
            expect(stored.birthDate, isNull, reason: 'seed $seed step $step');
          }
          // The rule itself, after every call: a draft that moved off a
          // number holds no name or date, and what it holds was given for
          // its own number (or for none yet).
          if (!reopened && before != null && c.draft.phoneE164 != before) {
            expect(c.draft.name, isNull, reason: 'seed $seed step $step');
            expect(c.draft.birthDate, isNull, reason: 'seed $seed step $step');
          }
          final own = c.draft.phoneE164;
          for (final value in [
            c.draft.name,
            if (c.draft.birthDate case final d?) SignUpDraft.dateOnly(d),
          ]) {
            if (value == null) continue;
            final given = givenFor[value];
            expect(
              given == null || given == own,
              isTrue,
              reason:
                  'seed $seed step $step: $value was given for $given, '
                  'the draft is on $own',
            );
            checked++;
          }
        }
        gone += dead.length;
      }
      expect(completions, greaterThan(40), reason: 'the walk reaches A5');
      expect(gone, greaterThan(1000), reason: 'kills, backgrounds, Not now');
      expect(checked, greaterThan(5000));
    });
  });

  group('review B5 fix round 5 (unbound A1/A2: memory only)', () {
    final adultA = DateTime.utc(1990, 5, 5);
    final adultB = DateTime.utc(1995, 8, 1);
    const phoneA = '+233244111111';
    const phoneB = '+233244222222';

    List<(Object?, Object?)> sent(FakeAccountGateway gateway) => [
      for (final (fn, params) in gateway.calls)
        if (fn == 'complete_sign_up')
          (params!['p_display_name'], params['p_birth_date']),
    ];

    _Rig noAccount({String? signedInAs}) => _Rig(
      prefs,
      signedInAs: signedInAs,
      home: FakeAccountGateway.account(hasAccount: false),
    );

    /// The draft exactly as written under its key, or null.
    Map<String, dynamic>? written() {
      final raw = prefs.getString(SignUpDraftStore.key);
      return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    }

    /// No key on the phone holds [values] (asserted on every key).
    void expectNowhereOnThePhone(List<String> values, {String? why}) {
      for (final key in prefs.getKeys()) {
        for (final value in values) {
          expect('${prefs.get(key)}', isNot(contains(value)), reason: why);
        }
      }
    }

    /// A1 and A2 typed, no code sent yet: the flow is on A3.
    Future<SignUpCoordinator> typedAtA3(_Rig rig) async {
      final c = rig.coordinator();
      c.start(SignUpEntry.newAccount);
      await c.saveName('Adult A');
      expect(await c.saveBirthDate(adultA), isTrue);
      return c;
    }

    void away(_Rig rig, SignUpCoordinator c, Duration time) {
      c.wentToBackground();
      rig.clock = rig.clock.add(time);
    }

    test('before a code is sent, nothing is written: no draft key, and no '
        'key holds the name or the date', () async {
      final rig = noAccount();
      final c = await typedAtA3(rig);
      expect(prefs.containsKey(SignUpDraftStore.key), isFalse);
      expectNowhereOnThePhone(['Adult A', '1990-05-05']);

      rig.sender.failNext = StateError('offline');
      expect(await c.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNotNull);
      expect(prefs.containsKey(SignUpDraftStore.key), isFalse);

      expect(await c.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      expect(written(), containsPair('phone', phoneA));
      expect(written(), containsPair('name', 'Adult A'));
      expect(written(), containsPair('birth_date', '1990-05-05'));
    });

    test('a signed-in session adopted with no code sent: only the account is '
        'written (the router hold); A1 and A2 stay in memory', () async {
      final rig = noAccount(signedInAs: 'u1');
      rig.auth.phone = phoneA;
      final c = rig.coordinator();
      expect(c.start(SignUpEntry.newAccount), SignUpStepId.code);
      expect(
        (await c.resolveVerified() as VerifiedNew).next,
        SignUpStepId.name,
      );
      await c.saveName('Adult A');
      expect(await c.saveBirthDate(adultA), isTrue);
      expect(written(), containsPair('verified_user_id', 'u1'));
      expect(written(), containsPair('name', null));
      expect(written(), containsPair('birth_date', null));
      expectNowhereOnThePhone(['Adult A', '1990-05-05']);
      expect(await c.complete(), CompleteOutcome.done);
      expect(sent(rig.gateway), [('Adult A', '1990-05-05')]);
    });

    for (final entry in SignUpEntry.values) {
      test('path 6: a cold start after A typed A1 and A2 and left at A3 '
          'shows nothing of them (${entry.wire})', () async {
        final rig = noAccount();
        await typedAtA3(rig);
        final b = rig.coordinator();
        final at = b.start(entry);
        expect(
          at,
          entry == SignUpEntry.returning
              ? SignUpStepId.phone
              : SignUpStepId.name,
        );
        expect(b.draft.name, isNull);
        expect(b.draft.birthDate, isNull);
        expect(b.phoneForA3, isNull);
      });
    }

    test('P1: A typed A1 and A2, the send failed, the phone locked for more '
        "than 5 minutes: they are dropped, and B's number never receives "
        "A's name or date", () async {
      final rig = noAccount();
      final c = await typedAtA3(rig);
      rig.sender.failNext = StateError('offline');
      expect(await c.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNotNull);
      away(rig, c, const Duration(minutes: 5, seconds: 1));
      expect(c.cameBack(), SignUpStepId.name, reason: 'A1, empty');
      expect(c.draft.name, isNull);
      expect(c.draft.birthDate, isNull);

      rig.auth.verifiesAs = 'uB';
      expect(await c.sendCode(phoneE164: phoneB, countryIso: 'GH'), isNull);
      expect(c.draft.name, isNull);
      expect(c.draft.birthDate, isNull);
      expect((await c.verify('123456') as VerifiedNew).next, SignUpStepId.name);
      expect(await c.complete(), CompleteOutcome.failed);
      await c.saveName('B');
      expect(await c.saveBirthDate(adultB), isTrue);
      expect(await c.complete(), CompleteOutcome.done);
      expect(sent(rig.gateway), [('B', '1995-08-01')]);
    });

    test('a background of 5 minutes or less keeps A1 and A2', () async {
      final rig = noAccount();
      final c = await typedAtA3(rig);
      away(rig, c, const Duration(minutes: 5));
      expect(c.cameBack(), isNull);
      expect(c.draft.name, 'Adult A');
      expect(c.draft.birthDate, adultA);
    });

    test('a code sent: a background of any length keeps everything (A4 '
        'reads the SMS; A5 resumes)', () async {
      final rig = noAccount();
      final c = await typedAtA3(rig);
      await c.sendCode(phoneE164: phoneA, countryIso: 'GH');
      away(rig, c, const Duration(days: 3));
      expect(c.cameBack(), isNull);
      expect(c.draft.name, 'Adult A');
      expect(written(), containsPair('name', 'Adult A'));
    });

    test('after "Change it", a long background drops what was set aside: '
        'the same number brings nothing back, and A3 opens empty', () async {
      final rig = noAccount();
      final c = await typedAtA3(rig);
      await c.sendCode(phoneE164: phoneA, countryIso: 'GH');
      await c.changeNumber();
      away(rig, c, const Duration(minutes: 6));
      expect(c.cameBack(), SignUpStepId.name);
      expect(c.phoneForA3, isNull);
      expect(await c.sendCode(phoneE164: phoneA, countryIso: 'GH'), isNull);
      expect(c.draft.name, isNull);
      expect(c.draft.birthDate, isNull);
    });

    test('adopted with no code sent: a long background drops A1 and A2 but '
        'keeps the account (A1 again, never A5 with them)', () async {
      final rig = noAccount(signedInAs: 'u1');
      rig.auth.phone = phoneA;
      final c = rig.coordinator()..start(SignUpEntry.newAccount);
      await c.resolveVerified();
      await c.saveName('Adult A');
      await c.saveBirthDate(adultA);
      away(rig, c, const Duration(minutes: 6));
      expect(c.cameBack(), SignUpStepId.name);
      expect(c.draft.verifiedUserId, 'u1');
      expect(c.draft.name, isNull);
      expect(await c.complete(), CompleteOutcome.failed);
      expect(sent(rig.gateway), isEmpty);
    });

    test('a send still in flight when the app comes back after a long '
        'background never puts the dropped A1/A2 back', () async {
      final rig = noAccount();
      final c = await typedAtA3(rig);
      rig.sender.hold = Completer<void>();
      final pending = c.sendCode(phoneE164: phoneA, countryIso: 'GH');
      away(rig, c, const Duration(minutes: 6));
      expect(c.cameBack(), SignUpStepId.name);
      rig.sender.hold!.complete();
      expect(await pending, isNotNull, reason: 'its result is not used');
      expect(c.draft.name, isNull);
      expect(c.draft.lastSentAt, isNull);
      expect(prefs.containsKey(SignUpDraftStore.key), isFalse);
    });

    test('"Not now" keeps nothing: after A5 by code, nothing is left on the '
        'phone, and the next visit opens A1 empty', () async {
      final rig = noAccount();
      final c = await typedAtA3(rig);
      await c.sendCode(phoneE164: phoneA, countryIso: 'GH');
      await c.verify('123456');
      expect(written(), containsPair('name', 'Adult A'));
      await c.notNow();
      expect(prefs.containsKey(SignUpDraftStore.key), isFalse);
      expectNowhereOnThePhone(['Adult A', '1990-05-05', phoneA]);
      final next = rig.coordinator();
      expect(next.start(SignUpEntry.newAccount), SignUpStepId.name);
      expect(next.draft.name, isNull);
    });

    test('"Not now" before any code was sent (an adopted session): nothing '
        'at all is left', () async {
      final rig = noAccount(signedInAs: 'u1');
      rig.auth.phone = phoneA;
      final c = rig.coordinator()..start(SignUpEntry.newAccount);
      await c.resolveVerified();
      await c.saveName('Adult A');
      await c.saveBirthDate(adultA);
      expect(prefs.containsKey(SignUpDraftStore.key), isTrue);
      await c.notNow();
      expect(prefs.containsKey(SignUpDraftStore.key), isFalse);
      expectNowhereOnThePhone(['Adult A', '1990-05-05']);
    });

    for (final existing in [true, false]) {
      final what = existing ? 'an existing account' : 'the account made';
      test('a draft gone for good ($what, signed in with no code sent) is '
          'never written back by a long background', () async {
        final rig = _Rig(
          prefs,
          signedInAs: 'u1',
          home: FakeAccountGateway.account(hasAccount: existing),
          name: 'Kofi',
        );
        rig.auth.phone = phoneA;
        final c = rig.coordinator()..start(SignUpEntry.newAccount);
        if (existing) {
          expect(await c.resolveVerified(), isA<VerifiedExisting>());
        } else {
          await c.resolveVerified();
          await c.saveName('Adult A');
          await c.saveBirthDate(adultA);
          expect(await c.complete(), CompleteOutcome.done);
        }
        expect(prefs.containsKey(SignUpDraftStore.key), isFalse);
        away(rig, c, const Duration(minutes: 6));
        c.cameBack();
        await Future<void>.delayed(Duration.zero);
        expect(prefs.containsKey(SignUpDraftStore.key), isFalse);
      });
    }

    test("A's own resume is untouched: closed at A4 and reopened, the same "
        "number's code leads to A5 with A's date", () async {
      final rig = noAccount();
      final c = await typedAtA3(rig);
      await c.sendCode(phoneE164: phoneA, countryIso: 'GH');
      final reopened = rig.coordinator();
      expect(reopened.start(SignUpEntry.newAccount), SignUpStepId.code);
      expect(
        (await reopened.verify('123456') as VerifiedNew).next,
        SignUpStepId.consent,
      );
      final again = rig.coordinator();
      expect(again.start(SignUpEntry.newAccount), SignUpStepId.consent);
      expect(await again.complete(), CompleteOutcome.done);
      expect(sent(rig.gateway), [('Adult A', '1990-05-05')]);
    });
  });

  // Final review M-1 (re-graded Important): under X1's block a phone still
  // signs in to an account it has; a number with no account creates none.
  group('M-1: a blocked device', () {
    Future<void> block() => prefs.setString(
      AgeGateStore.blockUntilKey,
      _now.add(const Duration(days: 3)).toIso8601String(),
    );

    test('returning, an existing account: Welcome back, as anywhere', () async {
      await block();
      final rig = _Rig(prefs, home: FakeAccountGateway.account(), name: 'Kofi');
      final c = rig.coordinator();
      expect(c.start(SignUpEntry.returning), SignUpStepId.phone);
      expect(await c.sendCode(phoneE164: _phone, countryIso: 'GH'), isNull);
      final outcome = await c.verify('123456');
      expect(outcome, isA<VerifiedExisting>());
      expect((outcome as VerifiedExisting).firstName, 'Kofi');
      expect(rig.auth.signOuts, 0);
      expect(rig.auth.currentUserId, 'u1');
    });

    test('returning, no account: X1 with the session ended, nothing kept '
        'and the block as it was', () async {
      await block();
      final until = prefs.getString(AgeGateStore.blockUntilKey);
      final rig = _Rig(
        prefs,
        home: FakeAccountGateway.account(hasAccount: false),
      );
      final c = rig.coordinator();
      expect(c.start(SignUpEntry.returning), SignUpStepId.phone);
      expect(await c.sendCode(phoneE164: _phone, countryIso: 'GH'), isNull);
      expect(await c.verify('123456'), isA<VerifiedBlocked>());
      expect(rig.auth.signOuts, 1);
      expect(rig.auth.currentUserId, isNull);
      expect(rig.drafts.read(), isNull);
      expect(prefs.getString(AgeGateStore.blockUntilKey), until);
      expect(rig.gateway.count('complete_sign_up'), 0);
    });

    test('a reopened draft already checked "no account" is asked again '
        'under the block, and ends at X1, never N1', () async {
      final checked = SignUpDraft.start(
        SignUpEntry.returning,
        now: _now,
      ).copyWith(
        phoneE164: _phone,
        lastSentAt: _now,
        sendCount: 1,
        verifiedUserId: 'u1',
        accountChecked: true,
      );
      final rig = _Rig(
        prefs,
        signedInAs: 'u1',
        home: FakeAccountGateway.account(hasAccount: false),
      );
      await rig.drafts.write(checked);
      expect(
        rig.coordinator().start(SignUpEntry.returning),
        SignUpStepId.noAccount,
        reason: 'unblocked: N1, as before',
      );

      await block();
      final c = rig.coordinator();
      expect(c.start(SignUpEntry.returning), SignUpStepId.code);
      expect(c.needsAccountCheck, isTrue);
      expect(await c.resolveVerified(), isA<VerifiedBlocked>());
      expect(rig.auth.signOuts, 1);
      expect(rig.drafts.read(), isNull);
    });
  });
}

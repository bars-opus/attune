import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/shared_axis_step.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_coordinator.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/domain/default_phone_country.dart';
import 'package:attune/features/auth/sign_up/domain/otp_failure.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/account_check_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/birth_date_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/code_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/consent_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/name_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/no_account_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// The clock the flow reads; tests pin it.
final signUpClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final signUpCoordinatorProvider = Provider.autoDispose<SignUpCoordinator>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final now = ref.watch(signUpClockProvider);
  return SignUpCoordinator(
    drafts: SignUpDraftStore(prefs, now: now),
    sender: ref.watch(codeSenderProvider),
    auth: ref.watch(signUpAuthProvider),
    accounts: ref.watch(accountServiceProvider),
    ageGate: ref.watch(ageGateStoreProvider),
    onboardingStoreFor:
        (userId) => OnboardingStore(
          prefs,
          scope: '${OnboardingStore.userScopePrefix}.$userId',
        ),
    metrics: ref.watch(metricCounterProvider),
    now: now,
  );
});

/// `/signup` (Spec 1 §3.3, §3.4): A1–A5, N1 and "Welcome back" in one
/// route, stepped with the shared-axis transition. [entry] is how the
/// person came in; a draft on this phone can resume where it stopped.
class SignUpFlow extends ConsumerStatefulWidget {
  const SignUpFlow({super.key, required this.entry, this.backTo});

  final SignUpEntry entry;

  /// Where the first step's back button goes (`/welcome` by default).
  final String? backTo;

  @override
  ConsumerState<SignUpFlow> createState() => _SignUpFlowState();
}

class _SignUpFlowState extends ConsumerState<SignUpFlow> {
  late final SignUpCoordinator _c = ref.read(signUpCoordinatorProvider);
  late SignUpStepId _step;
  bool _forward = true;

  /// The flow's own work (saving, sending, checking, signing out) is
  /// running: Back waits for it.
  bool _busy = false;

  /// A3's send failure, A5's save failure.
  String? _error;

  // A4 (review B4 I-2): what is wrong with the code (read out and red; a
  // wrong code also shakes), apart from a notice about anything else.
  String? _codeError;
  int _codeErrorCount = 0;
  int _shakeCount = 0;
  String? _notice;
  int _noticeCount = 0;

  /// System back on A4, handed to the step so it runs through the step's
  /// own guard ("Wrong number? Change it").
  final _codeBack = ValueNotifier<int>(0);
  bool _accepted = false;

  /// The account check (review B5 fix round 2): the first read is running;
  /// how many reads failed.
  bool _accountChecking = false;
  int _accountFails = 0;

  /// A resend refused "for {minutes} minutes" waits until then (B5 M-3).
  DateTime? _resendNotBefore;
  int? _guestYear;
  String? _welcomeName;

  /// The app's background and return (review B5 fix round 5): the
  /// coordinator drops A1/A2 that no code was sent for after more than 5
  /// minutes away, and the flow then starts again with empty fields.
  late final AppLifecycleListener _lifecycle;

  /// Bumped by each such restart: the steps are built afresh (no field
  /// keeps what was typed, nothing fades out), and work begun before it
  /// lands nowhere.
  int _restarts = 0;

  /// W2c: Android reads A4's code from its SMS (no permission) and A4
  /// fills it in ([_autofill]). On from the moment A3's send goes out (or
  /// A4's first frame, for a resumed draft) until the send fails or the
  /// flow leaves A4.
  late final SmsCodeListener _listener;
  bool _listening = false;

  /// A [SmsCodeListener.next] is out; [_listenRound] tells its answer from
  /// one asked for before the listener last stopped.
  bool _awaitingCode = false;
  int _listenRound = 0;
  String? _autofill;

  @override
  void initState() {
    super.initState();
    _listener = ref.read(smsCodeListenerProvider);
    _step = _c.start(widget.entry);
    if (_c.needsAccountCheck) {
      // Review B5 I-1, I-2: a proven number whose account wasn't read yet
      // opens on the account check while the server is asked; no code.
      _step = SignUpStepId.accountCheck;
      _accountChecking = true;
      unawaited(_checkAccount());
    }
    if (_step == SignUpStepId.code) _listenForCode();
    _lifecycle = AppLifecycleListener(
      onHide: _c.wentToBackground,
      onShow: _cameBack,
    );
    // A3's default country, read early so it is ready by then.
    ref.read(deviceCountryProvider.future).ignore();
    _c.guestBirthYear().then((year) {
      if (mounted && year != null) setState(() => _guestYear = year);
    });
  }

  @override
  void dispose() {
    _stopListening();
    _lifecycle.dispose();
    _codeBack.dispose();
    super.dispose();
  }

  /// Back from the background, before the screen shows again (it is still
  /// covered while inactive). Only the steps that hold typed A1/A2, or
  /// A5 for an account no code was sent for, start again.
  void _cameBack() {
    final restartAt = _c.cameBack();
    if (restartAt == null || !mounted) return;
    const typed = {
      SignUpStepId.name,
      SignUpStepId.birthDate,
      SignUpStepId.phone,
      SignUpStepId.consent,
    };
    if (!typed.contains(_step)) return;
    // A send still out from before listens for a number that is gone.
    _stopListening();
    // The WhatsApp question or the country picker over A3 asks about what
    // was typed before: it goes with it (review B8 m-2).
    Navigator.of(context).popUntil((route) => route is! PopupRoute);
    setState(() {
      _restarts++;
      _forward = true;
      _step = restartAt;
      _busy = false;
      _error = null;
      _codeError = null;
      _notice = null;
      _accepted = false;
    });
  }

  AppLocalizations get _loc => AppLocalizations.of(context)!;

  void _go(SignUpStepId step, {bool forward = true}) {
    setState(() {
      _forward = forward;
      _step = step;
      _error = null;
      _codeError = null;
      _notice = null;
      _accepted = false;
      // A code read while A3's send was out is A4's (review B8 m-1).
      if (step != SignUpStepId.code) _autofill = null;
    });
    step == SignUpStepId.code ? _listenForCode() : _stopListening();
  }

  /// Listens for A4's SMS, unless a listen is already out.
  void _listenForCode() {
    _listening = true;
    if (_awaitingCode) return;
    _awaitingCode = true;
    final round = _listenRound;
    unawaited(
      _listener.next().then(
        (code) {
          if (round != _listenRound) return;
          _awaitingCode = false;
          if (!mounted || code == null) return;
          setState(() => _autofill = code);
        },
        onError: (Object _) {
          if (round == _listenRound) _awaitingCode = false;
        },
      ),
    );
  }

  void _stopListening() {
    _autofill = null;
    if (!_listening) return;
    _listening = false;
    _awaitingCode = false;
    _listenRound++;
    _listener.stop().ignore();
  }

  void _leave() => context.go(widget.backTo ?? RouteNames.welcome);

  void _back() {
    // A4's Back is the step's own "Wrong number? Change it", through its
    // guard: never while a code is checked or sent, and once however often
    // it is pressed.
    if (_step == SignUpStepId.code) {
      _codeBack.value++;
      return;
    }
    // A1–A3's work lands on the step it started from, so Back waits for it.
    if (_busy) return;
    switch (_step) {
      case SignUpStepId.name:
        _leave();
      case SignUpStepId.birthDate:
        _go(SignUpStepId.name, forward: false);
      case SignUpStepId.phone:
        // The draft's own way in: a resumed draft opens on a bare /signup.
        _c.draft.entry == SignUpEntry.returning && _c.draft.name == null
            ? _leave()
            : _go(SignUpStepId.birthDate, forward: false);
      case SignUpStepId.code:
      case SignUpStepId.consent:
      case SignUpStepId.consentUpdate:
      case SignUpStepId.noAccount:
      case SignUpStepId.welcomeBack:
      case SignUpStepId.accountCheck:
        // Signed in by now: only the screen's own buttons leave.
        break;
    }
  }

  /// WhatsApp codes are only for numbers with no account yet (final review
  /// I-2): the server sends an existing account's code by SMS whatever is
  /// asked, so the returning way (the draft's own way in) never offers it.
  bool get _offersWhatsApp => _c.draft.entry != SignUpEntry.returning;

  String _sendError(OtpSendFailure failure) => switch (failure.kind) {
    OtpSendFailureKind.rateLimited => _loc.flow_tooManyCodes(
      failure.minutes ?? 1,
    ),
    // Never an option that isn't there.
    OtpSendFailureKind.unavailable =>
      _offersWhatsApp ? _loc.flow_sendFailed : _loc.flow_sendFailedSms,
    OtpSendFailureKind.signInOff => _loc.flow_phoneUnavailable,
  };

  /// [send], with anything it didn't expect read as "couldn't send".
  Future<OtpSendFailure?> _sending(
    Future<OtpSendFailure?> Function() send,
  ) async {
    try {
      return await send();
    } catch (_) {
      return const OtpSendFailure(OtpSendFailureKind.unavailable);
    }
  }

  Future<void> _send(String e164, String iso, {String channel = 'sms'}) async {
    final restarts = _restarts;
    // Listening before the request goes out (review B8 m-1): the SMS can
    // land before the send has returned, and it is A4's code then.
    _listenForCode();
    setState(() {
      _busy = true;
      _error = null;
      _autofill = null;
    });
    final failure = await _sending(
      () => _c.sendCode(phoneE164: e164, countryIso: iso, channel: channel),
    );
    // A restart stopped the listener already (and a new send may be
    // listening by now).
    if (!mounted || restarts != _restarts) return;
    setState(() => _busy = false);
    if (failure != null) {
      _stopListening();
      setState(() => _error = _sendError(failure));
      return;
    }
    _resendNotBefore = null;
    _go(SignUpStepId.code);
  }

  Future<void> _resend({String channel = 'sms'}) async {
    // Listening again for the new SMS when the last one was read, or the
    // listener gave up (the SMS Retriever waits 5 minutes).
    if (_step == SignUpStepId.code) _listenForCode();
    setState(() => _busy = true);
    final failure = await _sending(() => _c.sendCode(channel: channel));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (failure != null) {
        // Not about the code: a notice, the boxes untouched.
        _notice = _sendError(failure);
        _noticeCount++;
        final minutes = failure.minutes;
        if (failure.kind == OtpSendFailureKind.rateLimited && minutes != null) {
          _resendNotBefore = ref
              .read(signUpClockProvider)()
              .add(Duration(minutes: minutes));
        }
      } else {
        _notice = null;
        _codeError = null;
        _resendNotBefore = null;
      }
    });
  }

  Future<void> _changeNumber() async {
    await _c.changeNumber();
    if (mounted) _go(SignUpStepId.phone, forward: false);
  }

  Future<void> _verify(String code) async {
    setState(() {
      _busy = true;
      _codeError = null;
    });
    VerifyOutcome outcome;
    try {
      outcome = await _c.verify(code);
    } catch (_) {
      outcome = const VerifyFailed(OtpVerifyFailure.unavailable);
    }
    if (!mounted) return;
    await _afterVerify(outcome);
  }

  /// The hold's "Try again"; the step stays busy until it has finished.
  Future<void> _retryResolve() => _checkAccount();

  /// Which account the verified number is (A4's "Try again", and the
  /// check a signed-in or unchecked draft opens with).
  Future<void> _checkAccount() async {
    VerifyOutcome outcome;
    try {
      outcome = await _c.resolveVerified();
    } catch (_) {
      outcome = const VerifiedUnresolved();
    }
    if (mounted) await _afterVerify(outcome, announce: false);
  }

  /// [announce]: read out "Code accepted" and hold on the check, after a
  /// code typed just now; a check that only reads the account goes on.
  Future<void> _afterVerify(
    VerifyOutcome outcome, {
    bool announce = true,
  }) async {
    if (outcome is VerifiedBlocked) {
      // Final review M-1: no account to sign in to, and creating one is
      // closed on this phone: X1, at once (never animated).
      ref.read(routingNotifierProvider).setUnderAgeBlocked(true);
      context.go(RouteNames.ageStop);
      return;
    }
    if (outcome is VerifiedUnresolved ||
        (outcome is VerifyFailed && _step == SignUpStepId.accountCheck)) {
      // The number is proven (the code is spent); only the account is
      // unread: the hold, in its own words, never A4 (fix round 2).
      setState(() {
        _busy = false;
        _accountChecking = false;
        _accountFails++;
      });
      if (_step != SignUpStepId.accountCheck) _go(SignUpStepId.accountCheck);
      return;
    }
    if (outcome is VerifyFailed) {
      final failure = outcome.failure;
      // The haptic and the shake are for a wrong code only (§3.3 A4).
      if (failure == OtpVerifyFailure.wrongCode) HapticFeedback.mediumImpact();
      setState(() {
        _busy = false;
        switch (failure) {
          case OtpVerifyFailure.wrongCode:
            _codeError = _loc.flow_codeWrong;
            _codeErrorCount++;
            _shakeCount++;
          case OtpVerifyFailure.expired:
            _codeError = _loc.flow_codeExpired;
            _codeErrorCount++;
          case OtpVerifyFailure.rateLimited:
            // Auth gives no minutes for this one (review B5 M-3).
            _notice = _loc.flow_tooManyTries;
            _noticeCount++;
          case OtpVerifyFailure.unavailable:
            _notice = _loc.flow_codeCheckFailed;
            _noticeCount++;
        }
      });
      return;
    }
    // Accepted: the check fades in, holds, then the flow moves on.
    setState(() {
      _busy = false;
      _accepted = true;
      _codeError = null;
      _notice = null;
    });
    if (announce) {
      SemanticsService.announce(
        _loc.flow_codeAccepted,
        Directionality.of(context),
      );
      await Future<void>.delayed(kCodeAcceptedHold);
      if (!mounted) return;
    }
    switch (outcome) {
      case VerifiedNew(:final next):
        _go(next);
      case VerifiedExisting(:final firstName, :final needsConsent):
        _welcomeName = firstName;
        needsConsent ? _go(SignUpStepId.consentUpdate) : await _welcomeBack();
      default:
        break;
    }
  }

  Future<void> _welcomeBack() async {
    _go(SignUpStepId.welcomeBack);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) context.go(RouteNames.home);
  }

  Future<void> _agree() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_step == SignUpStepId.consentUpdate) {
      try {
        await _c.acceptUpdatedTerms();
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = _loc.flow_saveFailed;
          });
        }
        return;
      }
      if (mounted) await _welcomeBack();
      return;
    }
    CompleteOutcome outcome;
    try {
      outcome = await _c.complete();
    } catch (_) {
      outcome = CompleteOutcome.failed;
    }
    if (!mounted) return;
    switch (outcome) {
      case CompleteOutcome.done:
      case CompleteOutcome.queued:
        context.go(RouteNames.home);
      case CompleteOutcome.notEligible:
        ref.read(routingNotifierProvider).setUnderAgeBlocked(true);
        context.go('${RouteNames.ageStop}?from=server');
      case CompleteOutcome.phoneRequired:
        setState(() {
          _busy = false;
          _error = _loc.flow_signupPhoneRequired;
        });
      case CompleteOutcome.signedOut:
        // Review B5 M-7: the session ended; A3 for a new code.
        _go(SignUpStepId.phone, forward: false);
        setState(() {
          _busy = false;
          _error = _loc.flow_codeExpired;
        });
      case CompleteOutcome.failed:
        setState(() {
          _busy = false;
          _error = _loc.flow_saveFailed;
        });
    }
  }

  Future<void> _notNow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _c.notNow();
    } catch (_) {
      // Still signed in: say so, and leave both buttons usable again.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _loc.flow_saveFailed;
        });
      }
      return;
    }
    if (mounted) context.go(RouteNames.welcome);
  }

  Future<void> _useDifferentNumber() async {
    setState(() => _error = null);
    try {
      await _c.useDifferentNumber();
    } catch (_) {
      // Still signed in: say so on N1 (review B5 M-5).
      if (mounted) setState(() => _error = _loc.flow_saveFailed);
      return;
    }
    if (mounted) _go(SignUpStepId.phone, forward: false);
  }

  PhoneCountry? _initialCountry(DeviceCountries? device) {
    final saved = _c.draft.countryIso;
    return defaultPhoneCountry(
      simIso: saved ?? device?.sim,
      regionIso: device?.region,
    );
  }

  String _initialNational() {
    final e164 = _c.phoneForA3;
    if (e164 == null) return '';
    try {
      return PhoneNumber.parse(e164).nsn;
    } catch (_) {
      return '';
    }
  }

  Widget _stepWidget() {
    final draft = _c.draft;
    switch (_step) {
      case SignUpStepId.name:
        return NameStep(
          initialName: draft.name,
          onBack: _back,
          onSubmit: (name) async {
            _busy = true;
            try {
              await _c.saveName(name);
            } finally {
              _busy = false;
            }
            if (mounted) _go(SignUpStepId.birthDate);
          },
        );
      case SignUpStepId.birthDate:
        return BirthDateStep(
          // The phone's own region, not the app's language-only locale:
          // Ghana writes the day first (Review Focus 1, review B3 I-1).
          order: birthDateOrderFor(
            WidgetsBinding.instance.platformDispatcher.locale,
          ),
          todayUtc: _c.todayUtc,
          initialDate: draft.birthDate,
          initialYear: _guestYear,
          onBack: _back,
          onSubmit: (date) async {
            _busy = true;
            final bool adult;
            try {
              adult = await _c.saveBirthDate(date);
            } finally {
              _busy = false;
            }
            if (!mounted) return;
            if (!adult) {
              ref.read(routingNotifierProvider).setUnderAgeBlocked(true);
              context.go(RouteNames.ageStop);
              return;
            }
            _go(_c.afterBirthDate);
          },
        );
      case SignUpStepId.phone:
        final device = ref.watch(deviceCountryProvider);
        if (device.isLoading) {
          // The SIM answers within a second; the country picker must not
          // open before it has.
          return FlowFrame(
            title: _loc.flow_phoneTitle,
            hint: _loc.flow_phoneHint,
            onBack: _back,
            body: const SizedBox.shrink(),
          );
        }
        return PhoneStep(
          initialCountry: _initialCountry(device.valueOrNull),
          initialNational: _initialNational(),
          busy: _busy,
          sendError: _error,
          onBack: _back,
          onSend: _send,
          onSendWhatsApp:
              _offersWhatsApp
                  ? (e164, iso) => _send(e164, iso, channel: 'whatsapp')
                  : null,
        );
      case SignUpStepId.code:
        final now = ref.read(signUpClockProvider);
        return CodeStep(
          phoneE164: draft.phoneE164 ?? '',
          lastSentAt: draft.lastSentAt,
          sendCount: draft.sendCount,
          now: now,
          busy: _busy,
          accepted: _accepted,
          errorText: _codeError,
          errorCount: _codeErrorCount,
          shakeCount: _shakeCount,
          noticeText: _notice,
          noticeCount: _noticeCount,
          resendNotBefore: _resendNotBefore,
          systemBack: _codeBack,
          onCode: _verify,
          onResend: _resend,
          onChangeNumber: _changeNumber,
          lastChannel: draft.channel,
          onTryWhatsApp:
              _offersWhatsApp ? () => _resend(channel: 'whatsapp') : null,
          // W2 never offers a call: voice is off on the server (batch 7
          // M-4), until it can tell an answering machine from a person.
          autofillCode: _autofill,
        );
      case SignUpStepId.consent:
      case SignUpStepId.consentUpdate:
        return ConsentStep(
          updatedTerms: _step == SignUpStepId.consentUpdate,
          busy: _busy,
          errorText: _error,
          onAgree: _agree,
          onNotNow: _notNow,
        );
      case SignUpStepId.noAccount:
        return NoAccountStep(
          errorText: _error,
          onCreate: () => _go(SignUpStepId.name),
          onOtherNumber: _useDifferentNumber,
        );
      case SignUpStepId.welcomeBack:
        return WelcomeBackStep(firstName: _welcomeName);
      case SignUpStepId.accountCheck:
        return AccountCheckStep(
          checking: _accountChecking,
          failCount: _accountFails,
          errorText: _error,
          onRetry: _retryResolve,
          onNotNow: _notNow,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Consent, the under-18 stop and the account screens are never
    // animated (§2.2): they replace the previous step at once.
    final still =
        _step == SignUpStepId.consent || _step == SignUpStepId.consentUpdate;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: KeyedSubtree(
        key: ValueKey(_restarts),
        child:
            still
                ? KeyedSubtree(key: ValueKey(_step), child: _stepWidget())
                : SharedAxisStep(
                  stepKey: _step,
                  forward: _forward,
                  child: _stepWidget(),
                ),
      ),
    );
  }
}

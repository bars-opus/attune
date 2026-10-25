import 'dart:async';

import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/domain/display_name_validator.dart';
import 'package:attune/features/auth/sign_up/domain/otp_failure.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter/foundation.dart';

/// The steps `/signup` can show (Spec 1 §3.3, §3.4).
enum SignUpStepId {
  name,
  birthDate,
  phone,
  code,
  consent,
  consentUpdate,
  noAccount,
  welcomeBack,

  /// The account of a proven number is read, or couldn't be (offline).
  accountCheck,
}

/// Where a verified code leads.
sealed class VerifyOutcome {
  const VerifyOutcome();
}

/// A new account: A5 (or N1 when A1/A2 weren't asked, the returning way).
class VerifiedNew extends VerifyOutcome {
  const VerifiedNew(this.next);

  final SignUpStepId next;
}

/// An existing account: the typed name and date are discarded.
class VerifiedExisting extends VerifyOutcome {
  const VerifiedExisting({required this.firstName, required this.needsConsent});

  final String? firstName;

  /// EULA older than v2: A5c first.
  final bool needsConsent;
}

/// The code was accepted but the account couldn't be read: try again.
class VerifiedUnresolved extends VerifyOutcome {
  const VerifiedUnresolved();
}

/// A number with no account, on a phone under X1's block (final review
/// M-1): signed out and the draft gone; X1. The block closes creating an
/// account, never signing in to one, and isn't restarted by this.
class VerifiedBlocked extends VerifyOutcome {
  const VerifiedBlocked();
}

class VerifyFailed extends VerifyOutcome {
  const VerifyFailed(this.failure);

  final OtpVerifyFailure failure;
}

enum CompleteOutcome {
  /// The account exists.
  done,

  /// Offline: queued as PendingSignUp, the flow carries on (§3.14).
  queued,

  /// `signup:not_eligible`: signed out, draft gone, device blocked. X1.
  notEligible,

  /// `signup:phone_required`.
  phoneRequired,

  /// Anything else the server refused.
  failed,

  /// The session ended while A5 was showing (review B5 M-7): the code and
  /// the account are dropped, A1–A3 kept, and the flow goes back to A3.
  signedOut,
}

/// The sign-up's decisions, apart from any widget (Spec 1 §3.3, §3.4,
/// §3.6, §5.5). Every step writes the draft, so closing the app resumes.
class SignUpCoordinator {
  SignUpCoordinator({
    required SignUpDraftStore drafts,
    required CodeSender sender,
    required SignUpAuth auth,
    required AccountService accounts,
    required AgeGateStore ageGate,
    required OnboardingStore Function(String userId) onboardingStoreFor,
    required MetricCounter metrics,
    required DateTime Function() now,
    Duration timeout = callTimeout,
  }) : _drafts = drafts,
       _sender = sender,
       _auth = auth,
       _accounts = accounts,
       _ageGate = ageGate,
       _onboardingStoreFor = onboardingStoreFor,
       _metrics = metrics,
       _now = now,
       _timeout = timeout;

  /// The longest a send or a check may take before A3/A4 say it couldn't
  /// run (review B4 M-1): a backstop above the Auth calls' own 30 s, so a
  /// call that never answers can't hold the person on a busy step.
  static const callTimeout = Duration(seconds: 45);

  /// How long the app may be in the background before A1/A2 that no code
  /// was sent for are dropped (review B5 fix round 5).
  static const unboundAwayLimit = Duration(minutes: 5);

  final SignUpDraftStore _drafts;
  final CodeSender _sender;
  final SignUpAuth _auth;
  final AccountService _accounts;
  final AgeGateStore _ageGate;
  final OnboardingStore Function(String userId) _onboardingStoreFor;
  final MetricCounter _metrics;
  final DateTime Function() _now;
  final Duration _timeout;

  late SignUpDraft _draft;

  SignUpDraft get draft => _draft;

  /// The number A3 opens with: the draft's, or the one "Wrong number?
  /// Change it" took off it, so a typo is fixed rather than retyped.
  String? get phoneForA3 => _draft.phoneE164 ?? _setAside?.phoneE164;

  /// The draft names a verified account the server hasn't been asked about
  /// yet (review B5 I-1, I-2): the flow opens on the account check and
  /// asks ([resolveVerified]) before anything else.
  bool get needsAccountCheck =>
      _draft.verifiedUserId != null && !_draft.accountChecked;

  /// The draft is gone for good (an existing account, review B5 M-1; the
  /// account made; the under-18 stop): nothing writes it again.
  bool _discarded = false;

  /// A1/A2 that "Change it" took off the draft, with the number they were
  /// given for (review B5 I-8). Nothing shows them; they come back only
  /// when A3 sends that same number again, and any other number ends
  /// them. Held by this flow only, never written to the phone.
  ({String phoneE164, String? name, DateTime? birthDate})? _setAside;

  /// When the app went to the background, while it is there (fix round 5).
  DateTime? _awaySince;

  /// Bumped when unbound A1/A2 are dropped, so a send still in flight from
  /// before can't put the draft it started from back (fix round 5).
  int _epoch = 0;

  /// A check timed out; the session it started from tells whether it
  /// signed in after all (review B5 M-6).
  bool _checkLost = false;
  String? _sessionBeforeLostCheck;

  DateTime get todayUtc {
    final now = _now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// The app went to the background (review B5 fix round 5).
  void wentToBackground() => _awaySince ??= _now();

  /// The app is back. After more than [unboundAwayLimit] away, A1/A2 that
  /// no code was sent for are dropped, from the draft and from "Change
  /// it"'s set-aside alike (they were never on the phone), whoever is
  /// holding it now. Returns where the flow starts again, empty: A1, or
  /// A3 (N1 for an adopted account) on the returning way; null when
  /// nothing changed (a short absence, or a code sent: A4 reads the SMS).
  SignUpStepId? cameBack() {
    final since = _awaySince;
    _awaySince = null;
    if (since == null || _discarded || _draft.lastSentAt != null) return null;
    final away = _now().difference(since);
    // A clock set back while away counts as long: the safe side.
    if (!away.isNegative && away <= unboundAwayLimit) return null;
    _epoch++;
    _setAside = null;
    _draft = _draft.keepable ?? SignUpDraft.start(_draft.entry, now: _now());
    unawaited(_save());
    if (_draft.verifiedUserId != null) return _afterNoAccount;
    return _draft.entry == SignUpEntry.returning
        ? SignUpStepId.phone
        : SignUpStepId.name;
  }

  /// Loads or starts the draft and says where the flow opens.
  SignUpStepId start(SignUpEntry entry) {
    final existing = _drafts.read();
    final userId = _auth.currentUserId;
    if (existing != null &&
        userId != null &&
        existing.verifiedUserId == userId) {
      _draft = existing;
      // Review B5 I-2: a check that failed before the app closed is asked
      // again; only a "no account" answer resumes at A5 (or N1). Under X1's
      // block it is asked again too, and ends at X1 (final review M-1).
      if (!existing.accountChecked) return SignUpStepId.code;
      if (!_ageGate.isBlocked) return _afterNoAccount;
      _draft = existing.copyWith(accountChecked: false);
      return SignUpStepId.code;
    }
    if (existing != null && userId == null && existing.awaitingCode) {
      _draft = existing;
      return SignUpStepId.code;
    }
    if (existing != null && userId == null && existing.verifiedUserId != null) {
      // Ruling C4, as amended by fix round 5: verified for an account that
      // isn't signed in now (signed out, or W1's purge ended the session),
      // so its code and account can't finish. A3 opens on its number with
      // A1/A2 set aside for it (only that number brings them back, I-8);
      // nothing of them is shown, nor left on the phone.
      _draft = existing.copyWith(entry: entry);
      _setNumberOpen();
      unawaited(_save());
      return SignUpStepId.phone;
    }
    // Ruling C4: a draft verified for an account that isn't the session's
    // drops the code and that account; the adoption below decides what of
    // A1/A2 stays.
    final base =
        existing != null &&
                existing.verifiedUserId != null &&
                existing.verifiedUserId != userId
            ? existing.withoutCode()
            : existing;
    final fresh = base ?? SignUpDraft.start(entry, now: _now());
    if (existing == null) {
      _metrics.bump(ClientMetricKey.signupStarted);
    }
    if (userId != null) {
      // Review B5 I-1: already signed in (sign-in is by code only, so the
      // number is proven) and the draft doesn't name this account. No
      // second code: the account is adopted and checked first. Saved, so
      // the router holds /home and /onboarding until it is. A1–A2 stay
      // only when they were typed for this very number (review B5 I-6).
      // The draft takes the session's number (none when it isn't known),
      // through the one number setter (review B5 I-8).
      final sessionPhone = _auth.currentPhone;
      final ownNumber = sessionPhone != null && fresh.phoneE164 == sessionPhone;
      _draft = (ownNumber ? fresh.withoutCode() : fresh.withoutNameAndDate())
          .withNumber(sessionPhone)
          .copyWith(entry: entry, verifiedUserId: userId);
      unawaited(_save());
      return SignUpStepId.code;
    }
    // Review B5 I-6: the returning way never shows A1/A2 before A4, so a
    // name and date left by an earlier attempt (no code on its way, not
    // this session's) are not carried to A5; N1 leads to A1 and A2.
    _draft = (entry == SignUpEntry.returning
            ? fresh.withoutNameAndDate()
            : fresh)
        .copyWith(entry: entry);
    unawaited(_save());
    return entry == SignUpEntry.returning
        ? SignUpStepId.phone
        : SignUpStepId.name;
  }

  /// A verified number with no account: A5 once A1/A2 are done, else A1;
  /// N1 when the person came the returning way (§3.4).
  SignUpStepId get _afterNoAccount =>
      _hasNameAndDate
          ? SignUpStepId.consent
          : _draft.entry == SignUpEntry.returning
          ? SignUpStepId.noAccount
          : SignUpStepId.name;

  bool get _hasNameAndDate => _draft.name != null && _draft.birthDate != null;

  /// After A2: A5 when the code was already verified (N1's "Create an
  /// account"), otherwise A3.
  SignUpStepId get afterBirthDate =>
      _draft.verifiedUserId != null ? SignUpStepId.consent : SignUpStepId.phone;

  Future<void> saveName(String name) async {
    _draft = _draft.copyWith(name: name);
    _metrics.bump(ClientMetricKey.signupStepName);
    await _save();
  }

  /// G1's year, for A2's pre-fill.
  Future<int?> guestBirthYear() => _ageGate.guestBirthYear();

  /// False: under 18 on today's UTC date. Nothing was sent anywhere; the
  /// draft is deleted and the phone blocked for 30 days (§3.6).
  Future<bool> saveBirthDate(DateTime birthDate) async {
    if (ageOn(birthDate, todayUtc) < 18) {
      _metrics.bump(ClientMetricKey.signupAgeStop);
      await _stopUnderAge();
      return false;
    }
    _draft = _draft.copyWith(birthDate: birthDate);
    _metrics.bump(ClientMetricKey.signupStepDob);
    await _save();
    return true;
  }

  /// A3's send, or A4's resend when [phoneE164] is null. Null on success.
  Future<OtpSendFailure?> sendCode({
    String? phoneE164,
    String? countryIso,
    String channel = 'sms',
  }) async {
    final epoch = _epoch;
    var draft = _draft;
    if (phoneE164 != null && phoneE164 != draft.phoneE164) {
      // Review B5 I-8, the root rule: another number takes nothing given
      // for the one before (withNumber), so A1/A2 are asked again after
      // the code. Only those "Change it" set aside for this very number
      // come back with it, and only when nothing was typed since: A1 or A2
      // typed after the number was opened may be someone else's, so both
      // are asked again after the code (batch 5 re-review 4 m-1).
      draft = draft.withoutCode().withNumber(phoneE164, countryIso: countryIso);
      final setAside = _setAside;
      if (setAside != null && setAside.phoneE164 == phoneE164) {
        draft =
            draft.name == null && draft.birthDate == null
                ? draft.copyWith(
                  name: setAside.name,
                  birthDate: setAside.birthDate,
                )
                : draft.withoutNameAndDate();
      }
    }
    final phone = draft.phoneE164;
    if (phone == null) {
      return const OtpSendFailure(OtpSendFailureKind.unavailable);
    }
    try {
      await _sender
          .send(
            phoneE164: phone,
            channel: channel,
            deviceNonce: draft.deviceNonce,
          )
          .timeout(_timeout);
    } catch (error) {
      return classifyOtpSendError(error);
    }
    // Fix round 5: A1/A2 were dropped while this send was out (a long
    // background); the draft it started from is not put back.
    if (epoch != _epoch) {
      return const OtpSendFailure(OtpSendFailureKind.unavailable);
    }
    if (draft.sendCount == 0) _metrics.bump(ClientMetricKey.signupStepPhone);
    draft = draft.copyWith(
      channel: channel,
      lastSentAt: _now(),
      sendCount: draft.sendCount + 1,
    );
    _draft = draft;
    _setAside = null;
    _checkLost = false;
    await _save();
    return null;
  }

  /// A4: verifies, then asks the server which account this number is.
  Future<VerifyOutcome> verify(String code) async {
    final phone = _draft.phoneE164;
    if (phone == null) return const VerifyFailed(OtpVerifyFailure.unavailable);
    String? userId;
    // Review B5 M-6: the check that timed out signed in after all, and its
    // code is spent: use that session.
    final current = _auth.currentUserId;
    if (_checkLost && current != null && current != _sessionBeforeLostCheck) {
      userId = current;
    } else {
      final before = current;
      try {
        userId = await _auth
            .verify(phoneE164: phone, code: code)
            .timeout(_timeout);
      } catch (error) {
        final after = _auth.currentUserId;
        if (error is TimeoutException && after != null && after != before) {
          userId = after;
        } else {
          if (error is TimeoutException) {
            _checkLost = true;
            _sessionBeforeLostCheck = before;
          }
          return VerifyFailed(
            classifyOtpVerifyError(
              error,
              lastSentAt: _draft.lastSentAt,
              now: _now(),
            ),
          );
        }
      }
    }
    _checkLost = false;
    if (userId == null) {
      return const VerifyFailed(OtpVerifyFailure.unavailable);
    }
    _draft = _draft.copyWith(verifiedUserId: userId);
    await _save();
    return resolveVerified();
  }

  /// The account behind the verified number (also the hold's "Try
  /// again"). Only for the account the draft was verified or adopted for
  /// (fix round 4): a session the draft never named is not asked about,
  /// so the draft's A1/A2 are never bound to it here.
  Future<VerifyOutcome> resolveVerified() async {
    final userId = _draft.verifiedUserId;
    if (userId == null) return const VerifyFailed(OtpVerifyFailure.unavailable);
    final HomeState state;
    try {
      state = await _accounts.homeState();
    } catch (_) {
      return const VerifiedUnresolved();
    }
    if (!state.hasAccount) {
      // Final review M-1: under X1's block a number with no account creates
      // none (no N1, no A1/A2): X1, as at A2, with the block as it is.
      if (_ageGate.isBlocked) {
        await _stopUnderAge(blockInForce: true);
        return const VerifiedBlocked();
      }
      // Review B5 I-2: only this answer lets a reopen resume at A5 or N1.
      _draft = _draft.copyWith(verifiedUserId: userId, accountChecked: true);
      await _save();
      return VerifiedNew(_afterNoAccount);
    }
    // An existing account: what was typed here is discarded (§3.3 A4).
    _discarded = true;
    await _drafts.clear();
    // Ruling C8: the stored name as the server reads it (W1's
    // normalize_display_name), never a legacy row's raw characters.
    final clean = normalizeDisplayName(
      await _accounts.storedDisplayName(userId) ?? '',
    );
    final firstName = _firstName(clean);
    // A phone number stored as a name is never kept as the name either.
    if (clean.isNotEmpty && firstName != null) {
      await _onboardingStoreFor(userId).rememberDisplayName(clean);
    }
    return VerifiedExisting(
      firstName: firstName,
      needsConsent: state.needs.contains(HomeNeed.consent),
    );
  }

  /// A5: the account, or the call queued when offline.
  Future<CompleteOutcome> complete() async {
    final userId = _auth.currentUserId;
    final name = _draft.name;
    final birthDate = _draft.birthDate;
    if (userId == null || _draft.verifiedUserId != userId) {
      // Review B5 M-7 (as C4): back to A3 for a new code. Also when the
      // session isn't the account this draft was verified for (fix round
      // 3): A5 completes only for that one. A3 opens on the number, and
      // A1/A2 are set aside for it as by "Change it" (I-8).
      await _openNumber();
      return CompleteOutcome.signedOut;
    }
    if (name == null || birthDate == null) {
      return CompleteOutcome.failed;
    }
    var outcome = CompleteOutcome.done;
    try {
      await _accounts.completeSignUp(displayName: name, birthDate: birthDate);
    } on SignUpRefused catch (refused) {
      switch (refused.reason) {
        case SignUpRefusal.notEligible:
          await _stopUnderAge();
          return CompleteOutcome.notEligible;
        case SignUpRefusal.phoneRequired:
          return CompleteOutcome.phoneRequired;
        case SignUpRefusal.invalid:
          return CompleteOutcome.failed;
      }
    } on AccountOffline {
      await _onboardingStoreFor(userId).savePendingSignUp(
        PendingSignUp(displayName: name, birthDate: birthDate),
      );
      outcome = CompleteOutcome.queued;
    }
    await _onboardingStoreFor(userId).rememberDisplayName(name);
    await _ageGate.clearGuestBirthYear();
    _discarded = true;
    await _drafts.clear();
    return outcome;
  }

  /// A5c: EULA v2 for an existing account. Throws AccountOffline.
  Future<void> acceptUpdatedTerms() => _accounts.acceptUpdatedTerms();

  /// A5's "Not now" (and the hold's): signed out, nothing written. P-18
  /// as amended by fix round 5: nothing is kept, since no code is left
  /// sent for the number; A1–A3 go, from the phone too.
  Future<void> notNow() async {
    await _auth.signOut();
    // A5c's existing account: the typed draft was discarded; keep it so.
    if (_discarded) return;
    _setAside = null;
    _draft = _draft.withoutNameAndDate().withNumber(null);
    await _save();
  }

  /// N1's "Use a different number": signed out, back to A3. The number
  /// is forgotten, and A1/A2 with it (I-8).
  Future<void> useDifferentNumber() async {
    await _auth.signOut();
    _setAside = null;
    _draft = _draft.withoutCode(keepPhone: false);
    await _save();
  }

  /// A4's "Wrong number? Change it": back to A3, the ladder restarts.
  Future<void> changeNumber() => _openNumber();

  /// Back to A3 from a later step with the number open again ("Change
  /// it", or A5's session gone), review B5 I-8. A1/A2 come off the draft,
  /// on the phone too, so Back to A1/A2 or a reopened flow never shows
  /// them to whoever holds the phone now; only the same number brings
  /// them back ([sendCode]).
  Future<void> _openNumber() async {
    _setNumberOpen();
    await _save();
  }

  void _setNumberOpen() {
    final phone = _draft.phoneE164;
    _setAside =
        phone == null
            ? null
            : (
              phoneE164: phone,
              name: _draft.name,
              birthDate: _draft.birthDate,
            );
    _draft = _draft.withoutNameAndDate().withNumber(null);
  }

  /// X1 (§3.6), at A2 and on the server's refusal alike, in the order
  /// that can't lose the block (review B5 I-3, I-4): block, delete the
  /// draft, then end a verified session. Each step is best-effort and
  /// never skips the next, and X1 shows whatever fails. [blockInForce]
  /// (final review M-1): the block is already on, and is kept as it is.
  Future<void> _stopUnderAge({bool blockInForce = false}) async {
    _discarded = true;
    if (!blockInForce) await _ageGate.block();
    try {
      await _drafts.clear();
    } catch (error) {
      debugPrint('[sign-up] draft not deleted at X1: ${error.runtimeType}');
    }
    if (_auth.currentUserId != null) {
      try {
        await _auth.signOut();
      } catch (error) {
        debugPrint('[sign-up] sign-out failed at X1: ${error.runtimeType}');
      }
    }
  }

  /// Writes what may be kept of the draft ([SignUpDraft.keepable]); never
  /// once it is gone for good.
  Future<void> _save() async {
    if (_discarded) return;
    await _drafts.write(_draft);
  }

  /// A first name, never a phone number stored as a name.
  static String? _firstName(String? stored) {
    final first = (stored ?? '').trim().split(RegExp(r'\s+')).first;
    if (first.isEmpty || RegExp(r'^\+?[0-9 ()-]*$').hasMatch(first)) {
      return null;
    }
    return first;
  }
}

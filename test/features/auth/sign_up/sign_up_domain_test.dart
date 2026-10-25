// Spec 1 W2b (§3.3, §7.3): the pure sign-up rules.
import 'dart:async';
import 'dart:ui' show Locale;

import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/domain/default_phone_country.dart';
import 'package:attune/features/auth/sign_up/domain/display_name_validator.dart';
import 'package:attune/features/auth/sign_up/domain/otp_failure.dart';
import 'package:attune/features/auth/sign_up/domain/phone_entry.dart';
import 'package:attune/features/auth/sign_up/domain/resend_ladder.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _today = DateTime.utc(2026, 10, 25);

String _national(IsoCode iso) => metadataExamplesByIsoCode[iso]!.mobile;

void main() {
  group('display name (A1)', () {
    test('any script, kept as typed, inner spaces collapsed', () {
      expect(validateDisplayName('عائشة'), isNull);
      expect(validateDisplayName('Ɛsi  Ɔbɛng'), isNull);
      expect(normalizeDisplayName('  Ɛsi  Ɔbɛng '), 'Ɛsi Ɔbɛng');
      expect(validateDisplayName('张伟'), isNull);
    });

    test('at least one letter; digits and punctuation alone are refused', () {
      expect(validateDisplayName(''), DisplayNameError.needsLetter);
      expect(validateDisplayName('   '), DisplayNameError.needsLetter);
      expect(validateDisplayName('+233 24 412'), DisplayNameError.needsLetter);
      expect(validateDisplayName('!!'), DisplayNameError.needsLetter);
    });

    test('invisible and direction characters never count or survive', () {
      expect(
        validateDisplayName('\u200B\u202E\uFEFF'),
        DisplayNameError.needsLetter,
      );
      expect(normalizeDisplayName('Ama\u200B\u202E'), 'Ama');
    });

    // Ruling C1: W1's strip set (private.strip_name_controls and
    // OnboardingSubmissionService.clampDisplayName): ZWNJ U+200C and ZWJ
    // U+200D are kept, the bidi isolates U+2066–U+2069 go.
    test('ZWNJ and ZWJ stay as typed; bidi isolates go', () {
      const persian = 'می\u200Cخواهم';
      expect(normalizeDisplayName(persian), persian);
      expect(validateDisplayName(persian), isNull);
      const coder = '\u{1F469}\u200D\u{1F4BB}';
      expect(normalizeDisplayName(coder), coder);
      expect(normalizeDisplayName('Ama $coder'), 'Ama $coder');
      expect(normalizeDisplayName('Ama\u2066'), 'Ama');
      expect(normalizeDisplayName('Ama\u2066x\u2069'), 'Amax');
    });

    test('nothing visible once spaces, ZWNJ and ZWJ are set aside', () {
      expect(validateDisplayName('\u200C\u200D'), DisplayNameError.needsLetter);
      expect(
        validateDisplayName(' \u200C \u200D '),
        DisplayNameError.needsLetter,
      );
      expect(
        normalizeDisplayName(' \u200C \u200D '),
        '',
        reason: 'the server stores no name (private.name_is_blank)',
      );
    });

    test('a ZWJ sequence counts in code points, as char_length does', () {
      const coder = '\u{1F469}\u200D\u{1F4BB}';
      expect(validateDisplayName('${'a' * 37}$coder'), isNull);
      expect(
        validateDisplayName('${'a' * 38}$coder'),
        DisplayNameError.tooLong,
      );
    });

    test('the same characters as the server and the legacy clamp', () {
      final codePoints = [for (var c = 0x2000; c <= 0x206F; c++) c, 0xFEFF];
      for (final c in codePoints) {
        final ch = String.fromCharCode(c);
        final at = 'U+${c.toRadixString(16).toUpperCase()}';
        expect(
          normalizeDisplayName('a${ch}b'),
          OnboardingSubmissionService.clampDisplayName('a${ch}b'),
          reason: 'a${at}b',
        );
        expect(
          normalizeDisplayName(ch),
          OnboardingSubmissionService.clampDisplayName(ch),
          reason: '$at alone',
        );
      }
    });

    test('40 characters at most, counted as the server counts them', () {
      expect(validateDisplayName('a' * 40), isNull);
      expect(validateDisplayName('a' * 41), DisplayNameError.tooLong);
      expect(
        validateDisplayName('${'a' * 39}😀'),
        isNull,
        reason: 'an emoji is one',
      );
    });
  });

  group('date of birth (A2)', () {
    test('field order follows the locale; Ghana reads day first', () {
      expect(
        birthDateOrderFor(const Locale('en', 'US')),
        BirthDateOrder.monthDayYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'GB')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'GH')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'NG')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'CA')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('fr', 'FR')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('en', 'PH')),
        BirthDateOrder.monthDayYear,
      );
      // Review M-1: the exact pattern wins over the region fallback (es_US
      // is d/M/y), and a language-only locale reads that language's pattern
      // (plain en is M/d/y).
      expect(
        birthDateOrderFor(const Locale('es', 'US')),
        BirthDateOrder.dayMonthYear,
      );
      expect(
        birthDateOrderFor(const Locale('en')),
        BirthDateOrder.monthDayYear,
      );
      expect(birthDateExample(BirthDateOrder.dayMonthYear), '27 3 1996');
      expect(birthDateExample(BirthDateOrder.monthDayYear), '3 27 1996');
    });

    test('each mistake has its own message, in reading order', () {
      BirthDateError? e(String d, String m, String y) =>
          validateBirthDate(day: d, month: m, year: y, todayUtc: _today).error;
      expect(e('0', '3', '1996'), BirthDateError.dayRange);
      expect(e('32', '3', '1996'), BirthDateError.dayRange);
      expect(e('', '3', '1996'), BirthDateError.dayRange);
      expect(e('27', '13', '1996'), BirthDateError.monthRange);
      expect(e('27', '3', '96'), BirthDateError.yearDigits);
      expect(e('31', '4', '1996'), BirthDateError.noSuchDate);
      expect(e('29', '2', '2023'), BirthDateError.noSuchDate);
      expect(
        e('29', '2', '2024'),
        isNull,
        reason: 'a leap day exists in a leap year',
      );
      expect(e('26', '10', '2026'), BirthDateError.future);
      expect(e('24', '10', '1906'), BirthDateError.tooOld);
      expect(e('25', '10', '1906'), isNull, reason: 'exactly 120 years');
    });

    test('age on the UTC date, the server rule', () {
      expect(
        ageOn(DateTime.utc(2008, 10, 25), _today),
        18,
        reason: '18th birthday',
      );
      expect(ageOn(DateTime.utc(2008, 10, 26), _today), 17, reason: 'tomorrow');
      expect(ageOn(DateTime.utc(2008, 2, 29), DateTime.utc(2026, 2, 28)), 17);
      expect(ageOn(DateTime.utc(2008, 2, 29), DateTime.utc(2026, 3, 1)), 18);
    });
  });

  group('phone (A3)', () {
    test('a leading national 0 is dropped; the result is E.164', () {
      final national = _national(IsoCode.GH);
      final withZero = parsePhoneEntry('0$national', 'GH');
      expect(withZero.error, isNull);
      expect(withZero.e164, '+233$national');
      expect(parsePhoneEntry(national, 'GH').e164, '+233$national');
      expect(
        parsePhoneEntry('0${_national(IsoCode.GB)}', 'GB').e164,
        '+44${_national(IsoCode.GB)}',
      );
    });

    test('too short, too long, or not that country', () {
      final national = _national(IsoCode.GH);
      expect(
        parsePhoneEntry(national.substring(0, 5), 'GH').error,
        PhoneEntryError.tooShort,
      );
      expect(
        parsePhoneEntry('${national}12', 'GH').error,
        PhoneEntryError.tooLong,
      );
      expect(
        parsePhoneEntry('+44${_national(IsoCode.GB)}', 'GH').error,
        PhoneEntryError.wrongCountry,
      );
      expect(parsePhoneEntry('12', 'GH').error, PhoneEntryError.tooShort);
    });

    test('display form and country of a number', () {
      final e164 = '+233${_national(IsoCode.GH)}';
      expect(formatPhoneForDisplay(e164), startsWith('+233 '));
      expect(countryOfPhone(e164), 'GH');
      expect(countryOfPhone('+44${_national(IsoCode.GB)}'), 'GB');
    });
  });

  group('default country', () {
    test('SIM, then region, then none; never a hard-coded Ghana', () {
      expect(defaultPhoneCountry(simIso: 'gb', regionIso: 'US')?.isoCode, 'GB');
      expect(defaultPhoneCountry(regionIso: 'ng')?.isoCode, 'NG');
      expect(defaultPhoneCountry(), isNull);
      expect(defaultPhoneCountry(simIso: '', regionIso: 'ZZ'), isNull);
      expect(PhoneCountries.all, isNotEmpty);
    });
  });

  group('resend ladder (A4)', () {
    final sent = DateTime.utc(2026, 10, 25, 12);
    test('30 s, then 60 s, then 120 s', () {
      expect(ResendLadder.waitAfter(1), const Duration(seconds: 30));
      expect(ResendLadder.waitAfter(2), const Duration(seconds: 60));
      expect(ResendLadder.waitAfter(3), const Duration(seconds: 120));
      expect(ResendLadder.waitAfter(7), const Duration(seconds: 120));
      expect(
        ResendLadder.remaining(
          lastSentAt: sent,
          sendCount: 2,
          now: sent.add(const Duration(seconds: 45)),
        ),
        const Duration(seconds: 15),
      );
      expect(
        ResendLadder.remaining(lastSentAt: null, sendCount: 0, now: sent),
        Duration.zero,
      );
      expect(ResendLadder.clock(const Duration(seconds: 30)), '0:30');
      expect(ResendLadder.clock(const Duration(seconds: 65)), '1:05');
    });

    test('other channels after the second resend; "newest code" after any', () {
      expect(ResendLadder.offersOtherChannels(2), isFalse);
      expect(ResendLadder.offersOtherChannels(3), isTrue);
      expect(ResendLadder.saysUseNewest(1), isFalse);
      expect(ResendLadder.saysUseNewest(2), isTrue);
    });

    test('a code lives 10 minutes', () {
      expect(
        ResendLadder.isExpired(
          lastSentAt: sent,
          now: sent.add(const Duration(minutes: 10)),
        ),
        isFalse,
      );
      expect(
        ResendLadder.isExpired(
          lastSentAt: sent,
          now: sent.add(const Duration(minutes: 11)),
        ),
        isTrue,
      );
    });
  });

  group('send and verify failures', () {
    test('the hook\'s and Auth\'s limits read as minutes to wait', () {
      final hook = classifyOtpSendError(
        const AuthException('otp:rate_limited:600', statusCode: '429'),
      );
      expect(hook.kind, OtpSendFailureKind.rateLimited);
      expect(hook.minutes, 10);
      final auth = classifyOtpSendError(
        const AuthException(
          'For security purposes, you can only request this after 27 seconds.',
          code: 'over_sms_send_rate_limit',
        ),
      );
      expect(auth.kind, OtpSendFailureKind.rateLimited);
      expect(auth.minutes, 1);
    });

    test('anything else is "couldn\'t send", or sign-in off', () {
      expect(
        classifyOtpSendError(const AuthException('otp:unavailable')).kind,
        OtpSendFailureKind.unavailable,
      );
      expect(
        classifyOtpSendError(TimeoutException('x')).kind,
        OtpSendFailureKind.unavailable,
      );
      expect(
        classifyOtpSendError(
          const AuthException('off', code: 'otp_disabled'),
        ).kind,
        OtpSendFailureKind.signInOff,
      );
    });

    test(
      'a refused code is wrong while fresh and expired after 10 minutes',
      () {
        final sent = DateTime.utc(2026, 10, 25, 12);
        const refusal = AuthException(
          'Token has expired or is invalid',
          code: 'otp_expired',
          statusCode: '403',
        );
        expect(
          classifyOtpVerifyError(
            refusal,
            lastSentAt: sent,
            now: sent.add(const Duration(minutes: 2)),
          ),
          OtpVerifyFailure.wrongCode,
        );
        expect(
          classifyOtpVerifyError(
            refusal,
            lastSentAt: sent,
            now: sent.add(const Duration(minutes: 11)),
          ),
          OtpVerifyFailure.expired,
        );
        expect(
          classifyOtpVerifyError(
            TimeoutException('x'),
            lastSentAt: sent,
            now: sent,
          ),
          OtpVerifyFailure.unavailable,
        );
      },
    );
  });
}

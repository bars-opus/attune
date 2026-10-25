import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// How someone entered `/signup` (Spec 1 §5.4).
enum SignUpEntry {
  newAccount('new'),
  returning('returning'),
  invite('invite');

  const SignUpEntry(this.wire);

  final String wire;

  static SignUpEntry fromWire(Object? value) {
    for (final entry in values) {
      if (entry.wire == value) return entry;
    }
    return newAccount;
  }
}

/// A1–A4 held on this phone (Spec 1 §3.3, §5.5): the name, date of birth,
/// number, channel and resend ladder, so closing the app resumes at A4, and
/// the random `device_nonce` sent only to `otp-delivery-intent`. The date of
/// birth never leaves the phone before `complete_sign_up`.
@immutable
class SignUpDraft {
  const SignUpDraft({
    required this.entry,
    required this.deviceNonce,
    required this.createdAt,
    this.name,
    this.birthDate,
    this.phoneE164,
    this.countryIso,
    this.channel = 'sms',
    this.lastSentAt,
    this.sendCount = 0,
    this.verifiedUserId,
    this.accountChecked = false,
  });

  /// A new draft with a fresh 16-byte nonce.
  factory SignUpDraft.start(
    SignUpEntry entry, {
    required DateTime now,
    Random? random,
  }) => SignUpDraft(
    entry: entry,
    deviceNonce: newNonce(random),
    createdAt: now.toUtc(),
  );

  /// 16 random bytes, base64url without padding (22 characters).
  static String newNonce([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  final SignUpEntry entry;
  final String deviceNonce;
  final DateTime createdAt;
  final String? name;

  /// A UTC date (midnight).
  final DateTime? birthDate;
  final String? phoneE164;
  final String? countryIso;

  /// `sms`, `whatsapp` or `voice`: the channel the last code was asked on.
  final String channel;
  final DateTime? lastSentAt;
  final int sendCount;

  /// Set once A4 verified this account, until A5 completes or "Not now".
  final String? verifiedUserId;

  /// The server said [verifiedUserId] has no account yet (review B5 I-2).
  /// Until then a reopen asks again, so a check that failed never leads to
  /// A5 on an existing account, or to N1 for someone who has one.
  final bool accountChecked;

  /// A code was sent and not yet verified: reopening resumes at A4.
  bool get awaitingCode => lastSentAt != null && verifiedUserId == null;

  /// What of this draft may outlive the flow (review B5 fix round 5): A1
  /// and A2 are unbound until a code was sent for the draft's number, and
  /// unbound they live in memory only. With a code sent, all of it; with
  /// only a proven account (a signed-in session adopted), the account
  /// without A1/A2; otherwise nothing (null).
  SignUpDraft? get keepable {
    if (lastSentAt != null) return this;
    if (verifiedUserId == null) return null;
    return SignUpDraft(
      entry: entry,
      deviceNonce: deviceNonce,
      createdAt: createdAt,
      phoneE164: phoneE164,
      countryIso: countryIso,
      verifiedUserId: verifiedUserId,
      accountChecked: accountChecked,
    );
  }

  /// A new [phoneE164] goes through [withNumber] (review B5 I-8), so it
  /// takes along only what this same call gives it.
  SignUpDraft copyWith({
    SignUpEntry? entry,
    String? name,
    DateTime? birthDate,
    String? phoneE164,
    String? countryIso,
    String? channel,
    DateTime? lastSentAt,
    int? sendCount,
    String? verifiedUserId,
    bool? accountChecked,
  }) {
    final base = phoneE164 == null ? this : withNumber(phoneE164);
    return SignUpDraft(
      entry: entry ?? base.entry,
      deviceNonce: deviceNonce,
      createdAt: createdAt,
      name: name ?? base.name,
      birthDate: birthDate ?? base.birthDate,
      phoneE164: base.phoneE164,
      countryIso: countryIso ?? base.countryIso,
      channel: channel ?? base.channel,
      lastSentAt: lastSentAt ?? base.lastSentAt,
      sendCount: sendCount ?? base.sendCount,
      verifiedUserId: verifiedUserId ?? base.verifiedUserId,
      accountChecked: accountChecked ?? base.accountChecked,
    );
  }

  /// Back to A3 with no code in flight ("Wrong number? Change it", "Use a
  /// different number", "Not now"): the ladder restarts. Without the
  /// number, A1 and A2 go too ([withNumber]).
  SignUpDraft withoutCode({bool keepPhone = true}) {
    final reset = SignUpDraft(
      entry: entry,
      deviceNonce: deviceNonce,
      createdAt: createdAt,
      name: name,
      birthDate: birthDate,
      phoneE164: phoneE164,
      countryIso: countryIso,
    );
    return keepPhone ? reset : reset.withNumber(null);
  }

  /// The draft on [phoneE164]: the one way its number changes (review B5
  /// I-8, the root rule). A1 and A2 are bound to the number they were
  /// given with. Moved to a different number, or to none, the draft keeps
  /// neither of them, nor the code or the account (they were that
  /// number's too); the way in, the nonce, its date and the country stay.
  /// The same number changes nothing. A draft with no number yet gives
  /// its first one the A1 and A2 typed before it (they come before A3).
  SignUpDraft withNumber(String? phoneE164, {String? countryIso}) {
    if (phoneE164 == this.phoneE164) {
      return countryIso == null ? this : copyWith(countryIso: countryIso);
    }
    final first = this.phoneE164 == null;
    return SignUpDraft(
      entry: entry,
      deviceNonce: deviceNonce,
      createdAt: createdAt,
      name: first ? name : null,
      birthDate: first ? birthDate : null,
      phoneE164: phoneE164,
      countryIso: countryIso ?? this.countryIso,
    );
  }

  /// A1 and A2 dropped as well as the code: they were typed for a number
  /// that isn't the one verified now, maybe by someone else on this phone
  /// (review B5 I-6), so A1 and A2 are asked again.
  SignUpDraft withoutNameAndDate() => SignUpDraft(
    entry: entry,
    deviceNonce: deviceNonce,
    createdAt: createdAt,
    phoneE164: phoneE164,
    countryIso: countryIso,
  );

  Map<String, dynamic> toJson() => {
    'entry': entry.wire,
    'device_nonce': deviceNonce,
    'created_at': createdAt.toUtc().toIso8601String(),
    'name': name,
    'birth_date': birthDate == null ? null : dateOnly(birthDate!),
    'phone': phoneE164,
    'country': countryIso,
    'channel': channel,
    'last_sent_at': lastSentAt?.toUtc().toIso8601String(),
    'send_count': sendCount,
    'verified_user_id': verifiedUserId,
    'account_checked': accountChecked,
  };

  /// Null when the payload isn't a draft (a corrupt one is dropped).
  static SignUpDraft? fromJson(Object? json) {
    if (json is! Map) return null;
    final nonce = json['device_nonce'];
    final created = DateTime.tryParse(json['created_at'] as String? ?? '');
    if (nonce is! String || nonce.isEmpty || created == null) return null;
    DateTime? at(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    final birth = at(json['birth_date']);
    return SignUpDraft(
      entry: SignUpEntry.fromWire(json['entry']),
      deviceNonce: nonce,
      createdAt: created,
      name: json['name'] as String?,
      birthDate:
          birth == null
              ? null
              : DateTime.utc(birth.year, birth.month, birth.day),
      phoneE164: json['phone'] as String?,
      countryIso: json['country'] as String?,
      channel: json['channel'] as String? ?? 'sms',
      lastSentAt: at(json['last_sent_at']),
      sendCount: json['send_count'] is int ? json['send_count'] as int : 0,
      verifiedUserId: json['verified_user_id'] as String?,
      accountChecked: json['account_checked'] == true,
    );
  }

  /// `yyyy-MM-dd`, the wire form of a date of birth (this draft and
  /// AccountService's complete_sign_up).
  static String dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

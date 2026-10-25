// Spec 1 W2b (§5.5): the device sign-up draft.
import 'dart:convert';
import 'dart:math';

import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 25, 12);
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('a nonce is 16 random bytes, base64url, never repeated', () {
    final a = SignUpDraft.newNonce();
    final b = SignUpDraft.newNonce();
    expect(a, hasLength(22));
    expect(base64Url.decode('$a=='), hasLength(16));
    expect(a, isNot(b));
    expect(SignUpDraft.newNonce(Random(1)), SignUpDraft.newNonce(Random(1)));
  });

  test('the whole draft round-trips, the date of birth as a date', () async {
    final store = SignUpDraftStore(prefs, now: () => now);
    final draft = SignUpDraft.start(SignUpEntry.returning, now: now).copyWith(
      name: 'Ɛsi',
      birthDate: DateTime.utc(1996, 3, 27),
      phoneE164: '+233244123456',
      countryIso: 'GH',
      channel: 'whatsapp',
      lastSentAt: now,
      sendCount: 2,
    );
    await store.write(draft);
    final back = store.read()!;
    expect(back.entry, SignUpEntry.returning);
    expect(back.name, 'Ɛsi');
    expect(back.birthDate, DateTime.utc(1996, 3, 27));
    expect(back.phoneE164, '+233244123456');
    expect(back.channel, 'whatsapp');
    expect(back.sendCount, 2);
    expect(back.deviceNonce, draft.deviceNonce);
    expect(back.awaitingCode, isTrue);
    expect(
      jsonDecode(prefs.getString(SignUpDraftStore.key)!)['birth_date'],
      '1996-03-27',
    );
  });

  test('a draft older than 7 days, or a corrupt one, is gone', () async {
    await SignUpDraftStore(prefs, now: () => now).write(
      SignUpDraft.start(
        SignUpEntry.newAccount,
        now: now,
      ).copyWith(phoneE164: '+233244123456', lastSentAt: now, sendCount: 1),
    );
    expect(
      SignUpDraftStore(
        prefs,
        now: () => now.add(const Duration(days: 7)),
      ).read(),
      isNotNull,
    );
    expect(
      SignUpDraftStore(
        prefs,
        now: () => now.add(const Duration(days: 8)),
      ).read(),
      isNull,
    );
    expect(prefs.containsKey(SignUpDraftStore.key), isFalse);

    await prefs.setString(SignUpDraftStore.key, '{not json');
    expect(SignUpDraftStore(prefs, now: () => now).read(), isNull);
  });

  test(
    'verified means no longer awaiting a code; withoutCode restarts the ladder',
    () {
      final draft = SignUpDraft.start(
        SignUpEntry.newAccount,
        now: now,
      ).copyWith(phoneE164: '+447911123456', lastSentAt: now, sendCount: 3);
      expect(draft.copyWith(verifiedUserId: 'u1').awaitingCode, isFalse);
      final reset = draft.withoutCode();
      expect(reset.lastSentAt, isNull);
      expect(reset.sendCount, 0);
      expect(reset.phoneE164, '+447911123456');
      expect(draft.withoutCode(keepPhone: false).phoneE164, isNull);
      expect(reset.deviceNonce, draft.deviceNonce);
    },
  );

  test('review B5 I-8, the root rule: a draft moved to another number, or '
      'to none, takes no name, date of birth, code or account along; the '
      'same number keeps them; a first number takes what was typed before '
      'it', () {
    final typed = SignUpDraft.start(
      SignUpEntry.newAccount,
      now: now,
    ).copyWith(name: 'Ama', birthDate: DateTime.utc(1990, 1, 1));
    final onA = typed.withNumber('+233244111111', countryIso: 'GH');
    expect(onA.phoneE164, '+233244111111');
    expect(onA.name, 'Ama', reason: 'A1/A2 typed just before A3');
    expect(onA.birthDate, DateTime.utc(1990, 1, 1));

    final sent = onA.copyWith(
      lastSentAt: now,
      sendCount: 2,
      verifiedUserId: 'uA',
      accountChecked: true,
    );
    final moved = {
      'withNumber': sent.withNumber('+233244222222'),
      'copyWith': sent.copyWith(phoneE164: '+233244222222'),
      'withNumber(null)': sent.withNumber(null),
      'withoutCode(keepPhone: false)': sent.withoutCode(keepPhone: false),
    };
    for (final MapEntry(key: how, value: draft) in moved.entries) {
      expect(draft.name, isNull, reason: how);
      expect(draft.birthDate, isNull, reason: how);
      expect(draft.lastSentAt, isNull, reason: how);
      expect(draft.sendCount, 0, reason: how);
      expect(draft.verifiedUserId, isNull, reason: how);
      expect(draft.accountChecked, isFalse, reason: how);
      expect(draft.deviceNonce, sent.deviceNonce, reason: how);
      expect(draft.countryIso, 'GH', reason: how);
    }
    expect(
      sent.copyWith(phoneE164: '+233244222222', name: 'B').name,
      'B',
      reason: 'only what the call itself gives the new number',
    );

    final same = sent.withNumber('+233244111111');
    expect(same.name, 'Ama');
    expect(same.birthDate, DateTime.utc(1990, 1, 1));
    expect(same.sendCount, 2, reason: 'the same number changes nothing');
    expect(sent.copyWith(phoneE164: '+233244111111').name, 'Ama');
  });

  // Review N-2: a clock set back can't keep a draft (and its date of birth)
  // on the phone past its 7 days.
  test('a draft from more than a day in the future is gone', () async {
    await SignUpDraftStore(
      prefs,
      now: () => now.add(const Duration(hours: 25)),
    ).write(
      SignUpDraft.start(
        SignUpEntry.newAccount,
        now: now.add(const Duration(hours: 25)),
      ).copyWith(
        phoneE164: '+233244123456',
        lastSentAt: now.add(const Duration(hours: 25)),
        sendCount: 1,
      ),
    );
    expect(SignUpDraftStore(prefs, now: () => now).read(), isNull);
    expect(prefs.containsKey(SignUpDraftStore.key), isFalse);

    await SignUpDraftStore(prefs, now: () => now).write(
      SignUpDraft.start(
        SignUpEntry.newAccount,
        now: now.add(const Duration(hours: 23)),
      ).copyWith(phoneE164: '+233244123456', lastSentAt: now, sendCount: 1),
    );
    expect(
      SignUpDraftStore(prefs, now: () => now).read(),
      isNotNull,
      reason: 'a clock a few hours apart is not a reset',
    );
  });

  // Ruling C6: the one date-only helper, shared with AccountService.
  test('a date of birth is written as yyyy-MM-dd', () {
    expect(SignUpDraft.dateOnly(DateTime.utc(1996, 3, 7)), '1996-03-07');
    expect(SignUpDraft.dateOnly(DateTime.utc(987, 11, 25)), '0987-11-25');
  });

  test('the device key never names Dating (D20)', () {
    expect(SignUpDraftStore.key.contains('dating'), isFalse);
  });
}

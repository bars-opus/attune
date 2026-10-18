import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  SafetyPinStore store() => SafetyPinStore(
    clock: () => now,
    hasher: (pin) async => hashPin(pin, iterations: 1000),
    verifier: (pin, encoded) async => verifyPinHash(pin, encoded),
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 11, 10, 12);
  });

  test('set, check, remove', () async {
    final s = store();
    expect(await s.hasPin(), isFalse);
    await s.setPin('2468');
    expect(await s.hasPin(), isTrue);
    expect((await s.check('2468')).result, PinCheck.ok);
    expect((await s.check('1111')).result, PinCheck.wrong);
    await s.clearAll();
    expect(await s.hasPin(), isFalse);
  });

  test('an invalid PIN is refused', () async {
    expect(() => store().setPin('12'), throwsArgumentError);
  });

  test(
    'the fifth miss starts a wait; a right PIN during it still waits',
    () async {
      final s = store();
      await s.setPin('2468');
      for (var i = 0; i < 4; i++) {
        expect((await s.check('0000')).result, PinCheck.wrong);
      }
      final fifth = await s.check('0000');
      expect(fifth.result, PinCheck.wrong);
      expect(fifth.retryAt, now.add(const Duration(seconds: 30)));
      expect((await s.check('2468')).result, PinCheck.waiting);
      now = now.add(const Duration(seconds: 31));
      expect((await s.check('2468')).result, PinCheck.ok);
      // A success resets the count.
      expect((await s.check('0000')).retryAt, isNull);
    },
  );

  test(
    'the delay survives a restart (a new store over the same keystore)',
    () async {
      await store().setPin('2468');
      for (var i = 0; i < 5; i++) {
        await store().check('0000');
      }
      expect(await store().retryAt(), now.add(const Duration(seconds: 30)));
      expect((await store().check('2468')).result, PinCheck.waiting);
    },
  );

  test('moving the clock back does not end a wait', () async {
    final s = store();
    await s.setPin('2468');
    for (var i = 0; i < 5; i++) {
      await s.check('0000');
    }
    // Someone sets the phone's clock back a day: the wait starts over from
    // the new "now" instead of ending.
    now = now.subtract(const Duration(days: 1));
    expect((await s.check('2468')).result, PinCheck.waiting);
  });

  test('every-open is off by default and cleared with the PIN', () async {
    final s = store();
    expect(await s.everyOpen(), isFalse);
    await s.setPin('2468');
    await s.setEveryOpen(true);
    expect(await s.everyOpen(), isTrue);
    await s.clearAll();
    expect(await s.everyOpen(), isFalse);
  });

  test('a PIN that went missing is corrupt, not absent (review I-4)', () async {
    final s = store();
    expect(await s.isCorrupt(), isFalse);
    await s.setPin('2468');
    expect(await s.isCorrupt(), isFalse);
    await SafetyPinStore.defaultStorage.delete(key: 'safety_pin_hash');
    expect(await s.hasPin(), isFalse);
    expect(await s.isCorrupt(), isTrue);
    await s.clearAll();
    expect(await s.isCorrupt(), isFalse);
  });

  test('only a well-formed hash counts as a PIN', () async {
    final s = store();
    await SafetyPinStore.defaultStorage.write(
      key: 'safety_pin_hash',
      value: 'Data has been reset',
    );
    expect(await s.hasPin(), isFalse);
  });

  test('the safety keys live in their own keystore file, so a reset cannot '
      'take other features\' keys (review I-4)', () {
    expect(
      SafetyPinStore.defaultStorage.aOptions.toMap()['sharedPreferencesName'],
      safetyKeystoreFile,
    );
  });
}

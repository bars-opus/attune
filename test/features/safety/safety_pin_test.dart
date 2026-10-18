import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a PIN is 4 to 8 digits', () {
    for (final ok in ['1234', '00000000', '9876543']) {
      expect(isValidPin(ok), isTrue, reason: ok);
    }
    for (final bad in ['123', '123456789', '12a4', ' 1234', '', '１２３４']) {
      expect(isValidPin(bad), isFalse, reason: bad);
    }
  });

  test('the hash is salted, versioned and verifies only its own PIN', () {
    final a = hashPin('2468', iterations: 1000);
    final b = hashPin('2468', iterations: 1000);
    expect(a, startsWith(r'v1$1000$'));
    expect(a, isNot(b), reason: 'a fresh salt each time');
    expect(verifyPinHash('2468', a), isTrue);
    expect(verifyPinHash('2469', a), isFalse);
    expect(verifyPinHash('2468', 'garbage'), isFalse);
    expect(a.contains('2468'), isFalse);
  });

  test('five failures start an escalating delay up to a day, never a wipe', () {
    expect(safetyPinDelayAfter(4), Duration.zero);
    expect(safetyPinDelayAfter(5), const Duration(seconds: 30));
    expect(safetyPinDelayAfter(6), const Duration(minutes: 1));
    expect(safetyPinDelayAfter(7), const Duration(minutes: 5));
    expect(safetyPinDelayAfter(8), const Duration(minutes: 15));
    expect(safetyPinDelayAfter(9), const Duration(hours: 1));
    expect(safetyPinDelayAfter(10), const Duration(hours: 2));
    expect(safetyPinDelayAfter(11), const Duration(hours: 4));
    expect(safetyPinDelayAfter(12), const Duration(hours: 8));
    expect(safetyPinDelayAfter(13), const Duration(hours: 24));
    expect(safetyPinDelayAfter(40), const Duration(hours: 24));
  });
}

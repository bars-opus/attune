import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('minor units follow the currency: 2 digits for USD/GHS, 0 for JPY', () {
    expect(planningCurrencyDigits('USD'), 2);
    expect(planningCurrencyDigits('GHS'), 2);
    expect(planningCurrencyDigits('JPY'), 0);
  });

  test('formats minor units with the currency symbol', () {
    expect(formatPlanningMoney(123456, 'USD', locale: 'en_US'), r'$1,234.56');
    expect(formatPlanningMoney(1500, 'JPY', locale: 'en_US'), '¥1,500');
    expect(formatPlanningMoney(5, 'USD', locale: 'en_US'), r'$0.05');
  });

  test('parses typed amounts exactly, without floating point', () {
    expect(parsePlanningMoney('12.50', 'USD'), 1250);
    expect(parsePlanningMoney('12', 'USD'), 1200);
    expect(parsePlanningMoney('1,234.5', 'USD'), 123450);
    expect(parsePlanningMoney(' 0.29 ', 'USD'), 29, reason: '0.29 * 100 is 28.999… as a double');
    expect(parsePlanningMoney('1500', 'JPY'), 1500);
  });

  test('refuses what is not an amount', () {
    for (final bad in ['', ' ', 'abc', '-5', '1.234', '1.2.3', '12.5', '1e3']) {
      expect(parsePlanningMoney(bad, bad == '12.5' ? 'JPY' : 'USD'), isNull, reason: bad);
    }
    expect(parsePlanningMoney('99999999999', 'USD'), isNull, reason: 'over the server cap');
  });
}

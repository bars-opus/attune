// test/core/services/user_timezone_reporter_test.dart
import 'package:attune/core/services/user_timezone_reporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late List<String> sent;
  late String zone;
  late bool failSend;
  late UserTimezoneReporter reporter;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent = [];
    zone = 'Africa/Accra';
    failSend = false;
    reporter = UserTimezoneReporter(
      deviceTimezone: () async => zone,
      send: (z) async {
        if (failSend) throw Exception('offline');
        sent.add(z);
      },
    );
  });

  test('reports once per zone per user', () async {
    await reporter.report('u1');
    await reporter.report('u1');
    expect(sent, ['Africa/Accra']);
  });

  test('a changed zone is reported again (a traveller, on resume)', () async {
    await reporter.report('u1');
    zone = 'Europe/London';
    await reporter.report('u1');
    expect(sent, ['Africa/Accra', 'Europe/London']);
  });

  test('another user on the same phone reports for themselves', () async {
    await reporter.report('u1');
    await reporter.report('u2');
    expect(sent, ['Africa/Accra', 'Africa/Accra']);
  });

  test('signed out or no zone: nothing is sent', () async {
    await reporter.report(null);
    zone = '';
    await reporter.report('u1');
    expect(sent, isEmpty);
  });

  test('a device read that throws sends nothing', () async {
    final broken = UserTimezoneReporter(
      deviceTimezone: () async => throw StateError('channel'),
      send: (z) async => sent.add(z),
    );
    await broken.report('u1');
    expect(sent, isEmpty);
  });

  test('a failed send never throws and is retried next time', () async {
    failSend = true;
    await reporter.report('u1');
    expect(sent, isEmpty);
    failSend = false;
    await reporter.report('u1');
    expect(sent, ['Africa/Accra']);
  });
}

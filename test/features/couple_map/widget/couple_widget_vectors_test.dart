// test/features/couple_map/widget/couple_widget_vectors_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:flutter_test/flutter_test.dart';

const fixturePath =
    'test/features/couple_map/widget/fixtures/couple_widget_vectors.json';

/// Noon UTC: the same calendar date in every zone from UTC-11 to UTC+11
/// (a machine at UTC+12/+13 fails the first test; regenerate there with care).
final nowMs = DateTime.utc(2026, 10, 16, 12).millisecondsSinceEpoch;
const today = '2026-10-16';

int at(Duration d) => nowMs + d.inMilliseconds;
String p(Map<String, Object> m) => jsonEncode({'v': 1, ...m});
final live = at(const Duration(hours: 1));
final gone = at(const Duration(minutes: -1));

final cases = <(String, String?)>[
  ('null payload', null),
  ('malformed', '{'),
  ('unknown version', '{"v":2,"headline":"x"}'),
  ('empty', '{"v":1}'),
  ('together', p({'headline': 'Practically together', 'validUntilMs': live})),
  ('nearby', p({'headline': '15 min away', 'validUntilMs': live})),
  (
    'same country with clock line',
    p({
      'headline': '8 hours by road',
      'caption': '400 km apart',
      'clockOffsetMinutes': 60,
      'clockLine': true,
      'validUntilMs': live,
    }),
  ),
  (
    'same country, same zone',
    p({
      'headline': '8 hours by road',
      'caption': '400 km apart',
      'validUntilMs': live,
    }),
  ),
  (
    'distant clock headline',
    p({
      'headlineIsClock': true,
      'caption': '5.1k km apart',
      'clockOffsetMinutes': 330,
      'validUntilMs': live,
    }),
  ),
  (
    'distant clock headline, negative half hour',
    p({
      'headlineIsClock': true,
      'caption': '9.2k km apart',
      'clockOffsetMinutes': -210,
      'validUntilMs': live,
    }),
  ),
  (
    'distant without offset',
    p({'headline': '5.1k km apart', 'validUntilMs': live}),
  ),
  (
    'countdown 12 days with clock line',
    p({
      'caption': '5.1k km apart',
      'clockOffsetMinutes': 60,
      'clockLine': true,
      'validUntilMs': live,
      'reunionDate': '2026-10-28',
    }),
  ),
  (
    'countdown tomorrow',
    p({
      'caption': '5.1k km apart',
      'validUntilMs': live,
      'reunionDate': '2026-10-17',
    }),
  ),
  (
    'countdown today',
    p({
      'caption': '5.1k km apart',
      'validUntilMs': live,
      'reunionDate': '2026-10-16',
    }),
  ),
  (
    'expired distance, reunion in 12 days',
    p({
      'caption': '5.1k km apart',
      'validUntilMs': gone,
      'reunionDate': '2026-10-28',
    }),
  ),
  (
    'expired distance, reunion tomorrow',
    p({
      'caption': '5.1k km apart',
      'validUntilMs': gone,
      'reunionDate': '2026-10-17',
    }),
  ),
  (
    'expired distance alone',
    p({'headline': '8 hours by road', 'validUntilMs': gone}),
  ),
  ('valid until exactly now', p({'headline': 'x', 'validUntilMs': nowMs})),
  ('past reunion', p({'reunionDate': '2026-10-15'})),
  ('malformed reunion date', p({'reunionDate': 'soon'})),
  (
    'clock headline without offset',
    p({'headlineIsClock': true, 'validUntilMs': live}),
  ),
];

Map<String, Object?> expectFor(String? raw) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final stored = CoupleWidgetPayload.decode(raw);
  final cur = stored.current(now);
  final v = resolveCoupleWidget(stored, now);
  final off = cur.clockOffsetMinutes;
  final clock =
      off == null
          ? null
          : '${formatClock(now.toUtc().add(Duration(minutes: off)))} there';
  final headlineIsClock = clock != null && v.headline == clock;
  final clockLine = v.clockLine != null;
  return {
    'headline': headlineIsClock ? null : v.headline,
    'headlineIsClock': headlineIsClock,
    'caption': v.caption,
    'clockLine': clockLine,
    'clockOffsetMinutes': headlineIsClock || clockLine ? off : null,
    'neutral': v.neutral,
    'showMap': cur.hasDistance && !v.neutral,
  };
}

String encodeVectors() =>
    '${const JsonEncoder.withIndent('  ').convert({
      'nowMs': nowMs,
      'today': today,
      'neutralHeadline': neutralHeadline,
      'vectors': [
        for (final (name, raw) in cases) {'name': name, 'payload': raw, 'expect': expectFor(raw)},
      ],
    })}\n';

void main() {
  test("the machine's date at nowMs is the fixture's today", () {
    expect(dateKey(DateTime.fromMillisecondsSinceEpoch(nowMs)), today);
  });

  test(
    'native resolvers share these vectors (regenerate: UPDATE_VECTORS=1)',
    () {
      final file = File(fixturePath);
      final fresh = encodeVectors();
      if (Platform.environment['UPDATE_VECTORS'] == '1') {
        file
          ..createSync(recursive: true)
          ..writeAsStringSync(fresh);
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run once with UPDATE_VECTORS=1',
      );
      expect(file.readAsStringSync(), fresh);
    },
  );

  test('the vectors cover every view shape', () {
    final vs =
        ((jsonDecode(encodeVectors()) as Map)['vectors'] as List)
            .map((v) => (v as Map)['expect'] as Map)
            .toList();
    expect(vs.any((e) => e['neutral'] == true), isTrue);
    expect(vs.any((e) => e['headlineIsClock'] == true), isTrue);
    expect(vs.any((e) => e['clockLine'] == true), isTrue);
    expect(vs.any((e) => e['showMap'] == true), isTrue);
    expect(
      vs.any((e) => e['showMap'] == false && e['neutral'] == false),
      isTrue,
    );
    expect(vs.any((e) => e['clockOffsetMinutes'] == -210), isTrue);
  });
}

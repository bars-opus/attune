// Spec 3c: "Download my data" -- the service and the screen.
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/data_export/data/data_export_service.dart';
import 'package:attune/features/data_export/presentation/data_export_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _clock = DateTime.utc(2026, 10, 18, 12);

Map<String, dynamic> _row(String status, {String? expires, String? next, int? parts, int? earlier, String? earlierExpires}) => {
  'id': 'j1',
  'status': status,
  'requested_at': '2026-10-18T09:00:00Z',
  'ready_at': status == 'ready' ? '2026-10-18T09:03:00Z' : null,
  'expires_at': expires,
  'next_allowed_at': next,
  'parts': parts,
  'earlier_parts': earlier,
  'earlier_expires_at': earlierExpires,
};

// Within a day the time is what matters (re-review M2).
String _soon(DateTime utc) {
  final at = utc.toLocal();
  final now = _clock.toLocal();
  final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
  return sameDay ? MyDateFormat.toTime(at) : MyDateFormat.join([MyDateFormat.toDateShort(at), MyDateFormat.toTime(at)]);
}

class _Fake extends DataExportService {
  _Fake(this.rows) : super(rpc: (fn, [p]) async => null, invoke: (fn) async => null);
  List<Map<String, dynamic>> rows;
  int requests = 0;
  int urls = 0;
  Object? requestError;
  String? opened;
  @override
  Future<DataExportStatus?> latest() async =>
      rows.isEmpty ? null : DataExportStatus.fromRow(rows.first);
  @override
  Future<void> request() async {
    requests++;
    if (requestError != null) throw requestError!;
    rows = [_row('queued')];
  }

  @override
  Future<List<String>> downloadUrls() async {
    urls++;
    return ['https://example.test/part-1.zip', 'https://example.test/part-2.zip'];
  }
}

Future<_Fake> _pump(WidgetTester t, List<Map<String, dynamic>> rows, {bool pinOk = true}) async {
  await t.pumpWidget(const SizedBox()); // a fresh screen each time
  final fake = _Fake(rows);
  await t.pumpWidget(
    ProviderScope(
      overrides: [dataExportServiceProvider.overrideWithValue(fake)],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: DataExportScreen(
            pollEvery: const Duration(milliseconds: 50),
            openUrl: (url) async => fake.opened = url,
            now: () => _clock,
            confirmPin: (_) async => pinOk,
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
  return fake;
}

bool _enabled(WidgetTester t, String label) =>
    t.widget<FilledButton>(find.widgetWithText(FilledButton, label)).onPressed != null;

void main() {
  group('service', () {
    test('request calls request_my_export; refusals are typed; anything else is "other"', () async {
      final calls = <String>[];
      Object? fail;
      final s = DataExportService(
        rpc: (fn, [p]) async {
          calls.add(fn);
          if (fail != null) throw fail;
          return fn == 'get_my_export'
              ? [_row('ready', expires: '2026-10-25T09:03:00Z', parts: 1)]
              : 'j1';
        },
        invoke: (fn) async => {'urls': ['https://x/1.zip']},
      );
      await s.request();
      expect(calls, ['request_my_export']);
      expect((await s.latest())!.state, ExportState.ready);
      expect(await s.downloadUrls(), ['https://x/1.zip']);
      fail = const PostgrestException(message: 'export:too_soon');
      expect(() => s.request(), throwsA(isA<DataExportException>().having((e) => e.reason, 'r', ExportRefusal.tooSoon)));
      fail = const PostgrestException(message: 'export:in_progress');
      expect(() => s.request(), throwsA(isA<DataExportException>().having((e) => e.reason, 'r', ExportRefusal.inProgress)));
      fail = StateError('network');
      expect(() => s.request(), throwsA(isA<DataExportException>().having((e) => e.reason, 'r', ExportRefusal.other)));
    });

    test('status rows parse, including expired and parts', () {
      expect(DataExportStatus.fromRow(_row('expired')).state, ExportState.expired);
      expect(DataExportStatus.fromRow(_row('building')).state, ExportState.building);
      expect(DataExportStatus.fromRow(_row('ready', parts: 3)).parts, 3);
    });
  });

  group('screen', () {
    testWidgets('nothing yet: the intro and Prepare my download', (t) async {
      final f = await _pump(t, []);
      expect(
        find.text(
          "A copy of what's yours: your messages and the photos you shared, plans, "
          'calendar, stories, check-ins, journal, quiz answers, and the insights '
          'and readouts Attune showed you. Never anything about safety, and never '
          'the behind-the-scenes analysis of your chats.',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Prepare my download'));
      await t.pump();
      await t.pump();
      expect(f.requests, 1);
      expect(find.text('Getting it ready… you can leave this screen.'), findsOneWidget);
    });

    testWidgets('ready: one button per part; the date it is kept until', (t) async {
      final f = await _pump(t, [_row('ready', expires: '2026-10-25T09:03:00Z', parts: 2)]);
      expect(find.text('Ready until ${MyDateFormat.toDate(DateTime.utc(2026, 10, 25, 9, 3).toLocal())}.'), findsOneWidget);
      expect(find.text('Download part 1 of 2'), findsOneWidget);
      await t.tap(find.text('Download part 2 of 2'));
      await t.pump();
      await t.pump();
      expect(f.opened, 'https://example.test/part-2.zip');
    });

    testWidgets('ready, one part: a single Download', (t) async {
      final f = await _pump(t, [_row('ready', expires: '2026-10-25T09:03:00Z', parts: 1)]);
      await t.tap(find.text('Download'));
      await t.pump();
      await t.pump();
      expect(f.opened, 'https://example.test/part-1.zip');
    });

    testWidgets('a second one within a day says when', (t) async {
      await _pump(t, [_row('ready', expires: '2026-10-25T09:03:00Z', next: '2026-10-19T09:00:00Z', parts: 1)]);
      expect(
        find.text('You can ask for a new one after ${_soon(DateTime.utc(2026, 10, 19, 9))}.'),
        findsOneWidget,
      );
      expect(find.text('Prepare a new one'), findsNothing);
    });

    testWidgets('a ready one past its day can be replaced (final review I4)', (t) async {
      final f = await _pump(t, [_row('ready', expires: '2026-10-25T09:03:00Z', next: '2026-10-18T09:00:00Z', parts: 1)]);
      await t.tap(find.text('Prepare a new one'));
      await t.pump();
      expect(f.requests, 1);
    });

    testWidgets('failed: try again once the pause is over (final review I4)', (t) async {
      final f = await _pump(t, [_row('failed', next: '2026-10-18T11:00:00Z')]);
      expect(find.text("Couldn't prepare it. Try again."), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pump();
      expect(f.requests, 1);
      await _pump(t, [_row('failed', next: '2026-10-18T13:00:00Z')]);
      expect(
        find.text("Couldn't prepare it. You can try again after ${_soon(DateTime.utc(2026, 10, 18, 13))}."),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('an unexpected failure never leaves the screen stuck (final review I6)', (t) async {
      final f = await _pump(t, []);
      f.requestError = const DataExportException(ExportRefusal.other);
      await t.tap(find.text('Prepare my download'));
      await t.pump();
      await t.pump();
      expect(find.text("Couldn't prepare it. Try again."), findsOneWidget);
      expect(_enabled(t, 'Prepare my download'), isTrue);
    });

    testWidgets('building: polls until ready', (t) async {
      final f = await _pump(t, [_row('building')]);
      expect(find.text('Getting it ready… you can leave this screen.'), findsOneWidget);
      f.rows = [_row('ready', expires: '2026-10-25T09:03:00Z', parts: 1)];
      await t.pump(const Duration(milliseconds: 60));
      await t.pump();
      await t.pump();
      expect(find.text('Download'), findsOneWidget);
    });
  });

  testWidgets('with a Safety PIN set, a wrong or cancelled PIN stops it (plan review I8)', (t) async {
    final f = await _pump(t, [], pinOk: false);
    await t.tap(find.text('Prepare my download'));
    await t.pump();
    await t.pump();
    expect(f.requests, 0);
    final g = await _pump(t, [_row('ready', expires: '2026-10-25T09:03:00Z', parts: 1)], pinOk: false);
    await t.tap(find.text('Download'));
    await t.pump();
    expect(g.urls, 0);
  });

  testWidgets('an expired download says so and offers a new one (I10)', (t) async {
    await _pump(t, [_row('expired', expires: '2026-10-10T09:00:00Z')]);
    expect(find.text('Your last download has expired.'), findsOneWidget);
    expect(find.text('Prepare my download'), findsOneWidget);
  });

  testWidgets('one PIN and one set of links per visit (re-review M3)', (t) async {
    var pins = 0;
    await t.pumpWidget(const SizedBox());
    final fake = _Fake([_row('ready', expires: '2026-10-25T09:03:00Z', parts: 2)]);
    await t.pumpWidget(
      ProviderScope(
        overrides: [dataExportServiceProvider.overrideWithValue(fake)],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp(
            home: DataExportScreen(
              openUrl: (url) async => fake.opened = url,
              now: () => _clock,
              confirmPin: (_) async {
                pins++;
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    await t.tap(find.text('Download part 1 of 2'));
    await t.pump();
    await t.pump();
    await t.tap(find.text('Download part 2 of 2'));
    await t.pump();
    await t.pump();
    expect(pins, 1);
    expect(fake.urls, 1);
    expect(fake.opened, 'https://example.test/part-2.zip');
  });

  testWidgets('while a new one builds, the ready one is still offered (re-review M8)', (t) async {
    final f = await _pump(t, [_row('building', earlier: 2, earlierExpires: '2026-10-22T09:00:00Z')]);
    expect(find.text('Getting it ready… you can leave this screen.'), findsOneWidget);
    expect(
      find.text('Your earlier download is ready until ${MyDateFormat.toDate(DateTime.utc(2026, 10, 22, 9).toLocal())}.'),
      findsOneWidget,
    );
    await t.tap(find.text('Download part 2 of 2'));
    await t.pump();
    await t.pump();
    expect(f.opened, 'https://example.test/part-2.zip');
  });

  test('status rows carry the earlier download', () {
    final s = DataExportStatus.fromRow(_row('failed', earlier: 1, earlierExpires: '2026-10-22T09:00:00Z'));
    expect(s.earlierParts, 1);
    expect(s.earlierExpiresAt, DateTime.utc(2026, 10, 22, 9));
  });
}

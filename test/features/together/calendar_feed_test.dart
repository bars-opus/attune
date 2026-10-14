import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/calendar_feed.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<(FakeTogetherGateway, List<String>)> _open(
  WidgetTester t, {
  bool active = false,
  dynamic Function(Map<String, dynamic>)? status,
  bool settle = true,
}) async {
  t.view.physicalSize = const Size(1170, 4200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final copied = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  var isActive = active;
  final g = FakeTogetherGateway({
    'get_together_prefs': (_) => {'daily_summary': true, 'care_nudges': true},
    'get_calendar_feed_status':
        status ??
        (_) => [
          {
            'is_active': isActive,
            'since': isActive ? '2026-10-14T09:00:00Z' : null,
          },
        ],
    'create_calendar_feed_token': (_) {
      isActive = true;
      return _token;
    },
    'revoke_calendar_feed': (_) {
      isActive = false;
      return null;
    },
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherSupabaseUrlProvider.overrideWithValue(
          'https://abc.supabase.co',
        ),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (c) => TextButton(
                        onPressed: () => showTogetherSettingsSheet(c, 'r1'),
                        child: const Text('open'),
                      ),
                ),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    // A spinner never settles: let the sheet open and stop there.
    await t.pump(const Duration(seconds: 1));
  }
  return (g, copied);
}

void main() {
  test('links point at the feed function, https and webcal', () {
    final l = calendarFeedLinks('https://abc.supabase.co/', _token);
    expect(
      l.https,
      'https://abc.supabase.co/functions/v1/calendar-feed/$_token.ics',
    );
    expect(
      l.webcal,
      'webcal://abc.supabase.co/functions/v1/calendar-feed/$_token.ics',
    );
    expect(
      CalendarFeedStatus.fromRow({'is_active': false, 'since': null}).active,
      isFalse,
    );
  });

  testWidgets('turning the link on shows it once, with copy and the caveats', (
    t,
  ) async {
    final (g, copied) = await _open(t);
    await t.tap(find.text('Show Together in my calendar app'));
    await t.pumpAndSettle();
    expect(g.calls.any((c) => c.$1 == 'create_calendar_feed_token'), isTrue);
    expect(find.textContaining('every 12–24 hours'), findsOneWidget);
    expect(find.textContaining('Anyone with this link'), findsOneWidget);
    await t.tap(find.text('Copy link'));
    await t.pumpAndSettle();
    expect(copied, [
      'https://abc.supabase.co/functions/v1/calendar-feed/$_token.ics',
    ]);
  });

  testWidgets('when on: a new link replaces it; turning off asks first', (
    t,
  ) async {
    final (g, _) = await _open(t, active: true);
    expect(find.textContaining('On since'), findsOneWidget);
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Turn off'));
    await t.pumpAndSettle();
    expect(g.calls.any((c) => c.$1 == 'revoke_calendar_feed'), isTrue);
    expect(find.text('Show Together in my calendar app'), findsOneWidget);
  });

  testWidgets(
    "while the link's status is loading, nothing offers to replace it",
    (t) async {
      final never = Completer<List<Map<String, dynamic>>>();
      final (g, _) = await _open(t, status: (_) => never.future, settle: false);
      expect(find.text('Show Together in my calendar app'), findsNothing);
      expect(g.calls.any((c) => c.$1 == 'create_calendar_feed_token'), isFalse);
    },
  );

  testWidgets('if the status check fails, it says so and can retry', (t) async {
    var fail = true;
    await _open(
      t,
      status: (_) {
        if (fail) throw Exception('offline');
        return [
          {'is_active': true, 'since': '2026-10-14T09:00:00Z'},
        ];
      },
    );
    expect(find.text('Show Together in my calendar app'), findsNothing);
    expect(find.text("Couldn't check your calendar link"), findsOneWidget);
    fail = false;
    await t.tap(find.text("Couldn't check your calendar link"));
    await t.pumpAndSettle();
    expect(find.textContaining('On since'), findsOneWidget);
  });

  testWidgets('Open in Calendar is offered on iPhone only', (t) async {
    await _open(t);
    await t.tap(find.text('Show Together in my calendar app'));
    await t.pumpAndSettle();
    // Android: nothing handles webcal://, so no dead-end row.
    expect(find.text('Open in Calendar'), findsNothing);
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('on iPhone the link opens Calendar straight away', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _open(t);
      await t.tap(find.text('Show Together in my calendar app'));
      await t.pumpAndSettle();
      expect(find.text('Open in Calendar'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

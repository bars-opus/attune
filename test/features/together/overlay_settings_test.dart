import 'package:flutter/rendering.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'busy_sync_test.dart' show FakeBusySource;
import 'together_repository_test.dart' show FakeTogetherGateway;

Future<FakeTogetherGateway> _open(
  WidgetTester t,
  FakeBusySource source, {
  String level = 'off',
}) async {
  // The busy upload checks for the calendar copy's id (Phase 8d).
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(1170, 4000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  var current = level;
  final g = FakeTogetherGateway({
    'get_together_prefs': (_) => {'daily_summary': true, 'care_nudges': true},
    'get_calendar_feed_status':
        (_) => [
          {'is_active': false, 'since': null},
        ],
    'get_together_overlay': (_) => {'level': current},
    'set_together_overlay': (p) {
      current = p['p_level'] as String;
      return {'level': current};
    },
    'replace_my_busy_blocks': (_) => 0,
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        deviceBusySourceProvider.overrideWithValue(source),
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
  await t.pumpAndSettle();
  return g;
}

void main() {
  testWidgets('the sheet reads as one: a divider under its title, choices sized like the other rows', (t) async {
    await _open(t, FakeBusySource());
    // A divider right under "Together settings".
    final title = t.getBottomLeft(find.text('Together settings')).dy;
    final dividers = t.widgetList(find.byType(AppDivider)).map((w) => t.getTopLeft(find.byWidget(w)).dy);
    expect(dividers.any((y) => y >= title && y - title < 40), isTrue);
    // The Free time together choices use the same type as the other rows.
    double? size(String text) => (t.renderObject(find.text(text)) as RenderParagraph).text.style?.fontSize;
    final rowTitle = size('Morning summary');
    for (final choice in ['Off', "Show when we're both free", 'Also show Kofi my busy times']) {
      expect(size(choice), rowTitle, reason: choice);
    }
  });

  testWidgets('turning it on asks for the calendar, then saves and uploads', (
    t,
  ) async {
    final g = await _open(t, FakeBusySource());
    expect(find.textContaining('never titles'), findsOneWidget);
    await t.tap(find.text("Show when we're both free"));
    await t.pumpAndSettle();
    expect(
      g.calls.where((c) => c.$1 == 'set_together_overlay').single.$2['p_level'],
      'free_windows',
    );
    expect(g.calls.any((c) => c.$1 == 'replace_my_busy_blocks'), isTrue);
  });

  testWidgets('no calendar access: it stays off and says where to allow it', (
    t,
  ) async {
    final source = FakeBusySource(access: false);
    final g = await _open(t, source);
    await t.tap(find.text("Show when we're both free"));
    await t.pumpAndSettle();
    expect(g.calls.any((c) => c.$1 == 'set_together_overlay'), isFalse);
    expect(find.textContaining('Calendar access is off'), findsOneWidget);
    // iOS never asks twice: the only way back is the phone's Settings.
    await t.tap(find.text('Open Settings'));
    await t.pumpAndSettle();
    expect(source.settingsOpened, 1);
  });

  testWidgets('turning it off deletes, with no partner wording', (t) async {
    final g = await _open(t, FakeBusySource(), level: 'strips');
    await t.tap(find.text('Off'));
    await t.pumpAndSettle();
    expect(g.calls.lastWhere((c) => c.$1 == 'set_together_overlay').$2, {
      'p_relationship_id': 'r1',
      'p_level': 'off',
    });
    expect(find.textContaining('turned this on'), findsNothing);
  });
}

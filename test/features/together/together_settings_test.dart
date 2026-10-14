import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

void main() {
  testWidgets('turning off the morning summary saves straight away', (t) async {
    final g = FakeTogetherGateway({
      'get_together_prefs': (_) => {'daily_summary': true, 'care_nudges': true},
      'set_together_prefs':
          (p) => {
            'daily_summary': p['p_daily_summary'],
            'care_nudges': p['p_care_nudges'],
          },
    });
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
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
    expect(find.text('Morning summary'), findsOneWidget);
    expect(find.text("Kofi's big days"), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.widgetWithText(InfoRowWidget, 'Morning summary'),
        matching: find.byType(Switch),
      ),
    );
    await t.pumpAndSettle();
    final call = g.calls.lastWhere((c) => c.$1 == 'set_together_prefs');
    expect(call.$2, {
      'p_relationship_id': 'r1',
      'p_daily_summary': false,
      'p_care_nudges': true,
    });
  });

  Future<FakeTogetherGateway> open(
    WidgetTester t,
    Map<String, dynamic Function(Map<String, dynamic>)> h,
  ) async {
    final g = FakeTogetherGateway(h);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
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
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    return g;
  }

  testWidgets('while my settings load, no switch pretends to know them', (
    t,
  ) async {
    final never = Completer<Map<String, dynamic>>();
    await open(t, {'get_together_prefs': (_) => never.future});
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('a failed save puts the switch back and says so', (t) async {
    await open(t, {
      'get_together_prefs': (_) => {'daily_summary': true, 'care_nudges': true},
      'set_together_prefs': (_) => throw Exception('offline'),
    });
    await t.pumpAndSettle();
    final sw = find.descendant(
      of: find.widgetWithText(InfoRowWidget, 'Morning summary'),
      matching: find.byType(Switch),
    );
    await t.tap(sw);
    await t.pumpAndSettle();
    expect(t.widget<Switch>(sw).value, isTrue);
    expect(find.text('Could not save that. Please try again.'), findsOneWidget);
  });
}

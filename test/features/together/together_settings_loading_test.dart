import 'dart:async';

import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'busy_sync_test.dart' show FakeBusySource;
import 'together_repository_test.dart' show FakeTogetherGateway;

void main() {
  testWidgets('while settings load, rows of placeholders hold their place — no spinners', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(1170, 5200);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    // Every read stays in flight.
    Future<dynamic> never(Map<String, dynamic> _) => Completer<dynamic>().future;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          togetherRepositoryProvider.overrideWithValue(
            TogetherRepository(
              FakeTogetherGateway({
                'get_together_prefs': never,
                'get_together_overlay': never,
                'get_calendar_feed_status': never,
              }),
            ),
          ),
          deviceBusySourceProvider.overrideWithValue(FakeBusySource()),
          quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
          togetherLiveSupportedProvider.overrideWith((ref) async => false),
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
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Two toggles, three Free time choices, one calendar-link row.
    final skeletons = t.widgetList<TogetherSettingsSkeleton>(find.byType(TogetherSettingsSkeleton)).toList();
    expect(skeletons.map((s) => s.rows), [2, 3, 1]);
    expect(find.bySemanticsLabel('Loading settings'), findsWidgets);
  });
}

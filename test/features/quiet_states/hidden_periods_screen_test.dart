// Spec 7 (B9 (d)): "Hide a period" keeps a span of dates out of my own
// On this day and memory prompts.
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/quiet_states/data/hidden_periods_service.dart';
import 'package:attune/features/quiet_states/presentation/hidden_periods_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fake extends HiddenPeriodsService {
  _Fake(this.periods);
  List<HiddenPeriod> periods;
  final calls = <String>[];

  @override
  Future<List<HiddenPeriod>> mine() async => periods;

  @override
  Future<void> add(DateTime start, DateTime end) async {
    calls.add(
      'add:${start.toIso8601String().substring(0, 10)}..${end.toIso8601String().substring(0, 10)}',
    );
    periods = [
      ...periods,
      HiddenPeriod(id: 'new', startsOn: start, endsOn: end),
    ];
  }

  @override
  Future<void> remove(String id) async {
    calls.add('remove:$id');
    periods = periods.where((p) => p.id != id).toList();
  }
}

String _range(DateTime a, DateTime b) =>
    '${MyDateFormat.toDateShort(a)} to ${MyDateFormat.toDateShort(b)}';

void main() {
  testWidgets('lists, adds and removes my hidden periods', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final fake = _Fake([
      HiddenPeriod(
        id: 'p1',
        startsOn: DateTime(2025, 3, 1),
        endsOn: DateTime(2025, 4, 30),
      ),
    ]);
    await t.pumpWidget(
      ProviderScope(
        overrides: [hiddenPeriodsServiceProvider.overrideWithValue(fake)],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => MaterialApp(
                home: HiddenPeriodsScreen(
                  pickRange:
                      (_) async => DateTimeRange(
                        start: DateTime(2024, 6, 1),
                        end: DateTime(2024, 6, 30),
                      ),
                ),
              ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text(_range(DateTime(2025, 3, 1), DateTime(2025, 4, 30))),
      findsOneWidget,
    );
    await t.tap(find.text('Add a period'));
    await t.pumpAndSettle();
    expect(fake.calls, ['add:2024-06-01..2024-06-30']);
    expect(
      find.text(_range(DateTime(2024, 6, 1), DateTime(2024, 6, 30))),
      findsOneWidget,
    );
    await t.tap(find.byTooltip('Show again').first);
    await t.pumpAndSettle();
    expect(fake.calls.last, 'remove:p1');
    expect(
      find.text(_range(DateTime(2025, 3, 1), DateTime(2025, 4, 30))),
      findsNothing,
    );
  });

  testWidgets('empty: says what it does', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [hiddenPeriodsServiceProvider.overrideWithValue(_Fake([]))],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => const MaterialApp(home: HiddenPeriodsScreen()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.textContaining('never come back on On this day'),
      findsOneWidget,
    );
  });
}

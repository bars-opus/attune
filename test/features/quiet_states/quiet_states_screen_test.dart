// Spec 7 (B9, A9): the private quiet-state switch and its once-only line.
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/quiet_states/data/quiet_state_service.dart';
import 'package:attune/features/quiet_states/presentation/quiet_state_providers.dart';
import 'package:attune/features/quiet_states/presentation/quiet_states_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _line = "I'm in a heavy patch. I may be quieter; it isn't about you.";

class _Fake extends QuietStateService {
  _Fake(this.state);
  QuietState? state;
  final calls = <String>[];

  @override
  Future<QuietState?> mine() async => state;

  @override
  Future<void> start(QuietKind kind) async {
    calls.add('start:${kind.key}');
    state = QuietState(
      kind: kind,
      until: DateTime.utc(2026, 11, 1),
      lineOffered: state?.lineOffered ?? false,
    );
  }

  @override
  Future<void> end() async {
    calls.add('end');
    state = null;
  }

  @override
  Future<void> markLineOffered() async {
    calls.add('offered');
    final s = state!;
    state = QuietState(kind: s.kind, until: s.until, lineOffered: true);
  }
}

Future<(_Fake, List<String>)> _pump(WidgetTester t, QuietState? state) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox());
  final fake = _Fake(state);
  final sent = <String>[];
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        quietStateServiceProvider.overrideWithValue(fake),
        quietStatesEnabledProvider.overrideWith((ref) async => true),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: QuietStatesScreen(
                canSendLine: () async => true,
                sendLine: (text) async {
                  sent.add(text);
                  return true;
                },
              ),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (fake, sent);
}

void main() {
  testWidgets('switching on offers the line once; Send sends it as a message', (
    t,
  ) async {
    final (fake, sent) = await _pump(t, null);
    expect(find.text('Having a hard time'), findsOneWidget);
    expect(find.text('Going through a loss'), findsOneWidget);
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(find.text(_line), findsOneWidget);
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(sent, [_line]);
    expect(fake.calls, ['start:hard_time', 'offered']);
    expect(
      find.text(
        'Until ${MyDateFormat.toDate(DateTime.utc(2026, 11, 1).toLocal())}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Not now sends nothing and is not asked again', (t) async {
    final (fake, sent) = await _pump(t, null);
    await t.tap(find.byType(Switch).last);
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(sent, isEmpty);
    expect(fake.calls, ['start:loss', 'offered']);
    // Switching to the other kind keeps the line offered: no second sheet.
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(find.text(_line), findsNothing);
  });

  testWidgets('on: says until when, and can end now', (t) async {
    final (fake, _) = await _pump(
      t,
      QuietState(
        kind: QuietKind.loss,
        until: DateTime.utc(2026, 10, 30),
        lineOffered: true,
      ),
    );
    expect(t.widget<Switch>(find.byType(Switch).last).value, isTrue);
    expect(t.widget<Switch>(find.byType(Switch).first).value, isFalse);
    await t.tap(find.text('End now'));
    await t.pumpAndSettle();
    expect(fake.calls, ['end']);
    expect(find.text('End now'), findsNothing);
  });

  test('loading and a failed read both count as quiet (plan review M2)', () async {
    final loading = ProviderContainer(
      overrides: [
        quietStateProvider.overrideWith(
          (ref) => Future<QuietState?>.delayed(const Duration(days: 1)),
        ),
      ],
    );
    addTearDown(loading.dispose);
    expect(loading.read(isQuietProvider), isTrue);
    final failed = ProviderContainer(
      overrides: [
        quietStateProvider.overrideWith(
          (ref) async => throw StateError('offline'),
        ),
      ],
    );
    addTearDown(failed.dispose);
    await failed.read(quietStateProvider.future).catchError((_) => null);
    expect(failed.read(isQuietProvider), isTrue);
  });

  testWidgets('behind its flag: Coming soon', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          quietStatesEnabledProvider.overrideWith((ref) async => false),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => const MaterialApp(home: QuietStatesScreen()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });
}

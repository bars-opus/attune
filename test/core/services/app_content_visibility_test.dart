// test/core/services/app_content_visibility_test.dart
// Stories Wave 3: the shell keeps the app mounted behind the privacy cover
// and the Safety lock check, so anything that must stop when unseen asks
// this one signal instead of relying on being unmounted.
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void go(WidgetTester t, List<AppLifecycleState> states) {
    for (final s in states) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
  }

  ProviderContainer container(WidgetTester t) {
    // Registered first so it runs last (LIFO), after the listener is gone.
    addTearDown(
      () => t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('on screen while resumed with the lock open', (t) async {
    final c = container(t);
    expect(c.read(appContentVisibleProvider), isTrue);
  });

  testWidgets('off screen in every state but resumed, decided in the '
      'lifecycle callback itself (no frame needed)', (t) async {
    final c = container(t);
    final seen = <bool>[];
    c.listen<bool>(
      appContentVisibleProvider,
      (_, v) => seen.add(v),
      fireImmediately: true,
    );
    go(t, [AppLifecycleState.inactive]);
    expect(
      c.read(appContentVisibleProvider),
      isFalse,
      reason: 'iOS can hide before another frame is drawn',
    );
    go(t, [AppLifecycleState.hidden, AppLifecycleState.paused]);
    expect(c.read(appContentVisibleProvider), isFalse);
    go(t, [AppLifecycleState.hidden, AppLifecycleState.inactive]);
    expect(c.read(appContentVisibleProvider), isFalse);
    go(t, [AppLifecycleState.resumed]);
    expect(c.read(appContentVisibleProvider), isTrue);
    expect(seen, [true, false, true], reason: 'one change each way');
  });

  testWidgets('a lock being checked keeps it off through a resume; opening '
      'the lock shows the app', (t) async {
    final c = container(t);
    final seen = <bool>[];
    c.listen<bool>(
      appContentVisibleProvider,
      (_, v) => seen.add(v),
      fireImmediately: true,
    );
    go(t, [AppLifecycleState.inactive]);
    c.read(appContentVisibleProvider.notifier).setLockOpen(false);
    go(t, [AppLifecycleState.resumed]);
    expect(c.read(appContentVisibleProvider), isFalse);
    c.read(appContentVisibleProvider.notifier).setLockOpen(true);
    expect(c.read(appContentVisibleProvider), isTrue);
    expect(seen, [true, false, true]);
  });

  testWidgets('opening the lock while Attune is still not resumed does not '
      'show it', (t) async {
    final c = container(t);
    expect(c.read(appContentVisibleProvider), isTrue);
    go(t, [AppLifecycleState.inactive]);
    c.read(appContentVisibleProvider.notifier).setLockOpen(false);
    c.read(appContentVisibleProvider.notifier).setLockOpen(true);
    expect(c.read(appContentVisibleProvider), isFalse);
    go(t, [AppLifecycleState.resumed]);
    expect(c.read(appContentVisibleProvider), isTrue);
  });

  testWidgets('setLockOpen is never called during a build: its listeners '
      'call setState synchronously (debug assert)', (t) async {
    final c = container(t);
    expect(c.read(appContentVisibleProvider), isTrue);
    await t.pumpWidget(
      Builder(
        builder: (_) {
          // Same value: Riverpod itself would not notice this one.
          c.read(appContentVisibleProvider.notifier).setLockOpen(true);
          return const SizedBox();
        },
      ),
    );
    final error = t.takeException();
    expect(error, isA<AssertionError>());
    expect('$error', contains('during a build'));
  });
}

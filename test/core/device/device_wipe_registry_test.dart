// Spec 1 W3a (§5.8, D19): the device wipe registry runs in order, each
// entry in its own try and bound, never throws, and refuses a protective
// entry on quick exit.
import 'dart:async';

import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceWipeEntry _entry(
  String id,
  List<String> log, {
  int order = 0,
  Set<WipeMoment> moments = const {WipeMoment.signOut},
  Future<void> Function()? run,
  Duration bound = const Duration(milliseconds: 200),
  bool protective = false,
}) => DeviceWipeEntry(
  id: id,
  order: order,
  moments: moments,
  bound: bound,
  protective: protective,
  run: run ?? () async => log.add(id),
);

void main() {
  test('runs only the moment asked for, lower orders first', () async {
    final log = <String>[];
    final registry =
        DeviceWipeRegistry()
          ..register(_entry('late', log, order: 2))
          ..register(_entry('early', log, order: 1))
          ..register(_entry('exit only', log, moments: {WipeMoment.quickExit}))
          ..register(
            _entry(
              'both',
              log,
              order: 3,
              moments: {WipeMoment.signOut, WipeMoment.quickExit},
            ),
          );
    await registry.run(WipeMoment.signOut);
    expect(log, ['early', 'late', 'both']);
    log.clear();
    await registry.run(WipeMoment.quickExit);
    expect(log, ['exit only', 'both']);
  });

  test('one order runs side by side; a failing entry skips no other', () async {
    final log = <String>[];
    final gate = Completer<void>();
    final registry =
        DeviceWipeRegistry()
          ..register(
            _entry(
              'waits',
              log,
              run: () async {
                await gate.future;
                log.add('waits');
              },
            ),
          )
          ..register(
            _entry(
              'opens',
              log,
              run: () async {
                log.add('opens');
                gate.complete();
              },
            ),
          )
          ..register(
            _entry('throws', log, run: () async => throw StateError('disk')),
          )
          ..register(_entry('after', log, order: 1));
    await registry.run(WipeMoment.signOut);
    expect(log, ['opens', 'waits', 'after']);
  });

  test(
    'a hanging entry is cut at its bound; the next order still runs',
    () async {
      final log = <String>[];
      final registry =
          DeviceWipeRegistry()
            ..register(
              _entry(
                'hangs',
                log,
                bound: const Duration(milliseconds: 50),
                run: () => Completer<void>().future,
              ),
            )
            ..register(_entry('next', log, order: 1));
      final clock = Stopwatch()..start();
      await registry.run(WipeMoment.signOut);
      expect(log, ['next']);
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    },
  );

  test('the whole run is bounded and never throws', () async {
    final registry = DeviceWipeRegistry(
      totalBound: const Duration(milliseconds: 100),
    );
    for (var i = 0; i < 3; i++) {
      registry.register(
        _entry(
          'slow$i',
          [],
          order: i,
          bound: const Duration(seconds: 2),
          run: () => Future<void>.delayed(const Duration(seconds: 2)),
        ),
      );
    }
    final clock = Stopwatch()..start();
    await registry.run(WipeMoment.signOut);
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test(
    'refuses a duplicate id, no moment, a bad bound, a protective quick exit',
    () {
      final registry = DeviceWipeRegistry()..register(_entry('a', []));
      for (final bad in [
        _entry('a', []),
        _entry('none', [], moments: const {}),
        _entry('zero', [], bound: Duration.zero),
        _entry('long', [], bound: const Duration(seconds: 3)),
        _entry(
          'lock',
          [],
          protective: true,
          moments: {WipeMoment.signOut, WipeMoment.quickExit},
        ),
      ]) {
        expect(
          () => registry.register(bad),
          throwsA(isA<AssertionError>()),
          reason: bad.id,
        );
      }
      expect(registry.entries.map((e) => e.id), ['a']);
      expect(
        registry.register(_entry('lock', [], protective: true)),
        isTrue,
        reason: 'a protective entry may run on sign-out',
      );
    },
  );
}

// Spec 2 (research 06 §3 F7 (2); review I6, M9): the in-app notice when a new
// device signs in, and the one-time "review where you're signed in" notice.
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/account/data/account_sessions.dart';
import 'package:attune/features/account/presentation/new_device_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

SignedInDevice _d(String id, {bool current = false, int day = 1}) =>
    SignedInDevice(
      sessionId: id,
      label: id == 'b' ? 'Android phone' : 'iPhone or iPad',
      platform: 'android',
      signedInAt: DateTime.utc(2026, 10, day, 9),
      lastActiveAt: DateTime.utc(2026, 10, day, 10),
      isCurrent: current,
    );

class _Repo extends AccountSessionsRepository {
  _Repo(this.devices) : super((fn, [p]) async => null, () async {});
  List<SignedInDevice> devices;
  int registers = 0;
  int lists = 0;
  bool fail = false;
  @override
  Future<void> registerThisDevice() async {
    registers++;
    if (fail) throw Exception('offline');
  }

  @override
  Future<List<SignedInDevice>> list() async {
    lists++;
    if (fail) throw Exception('offline');
    return devices;
  }
}

class _Fixed extends NewDeviceWatcher {
  _Fixed(this.initial);
  final DeviceNotice? initial;
  @override
  DeviceNotice? build() => initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('check', () {
    test('first run: records what is there and offers one review', () async {
      final repo = _Repo([_d('a', current: true), _d('b')]);
      final n = await NewDeviceWatcher.check(repo, 'u1');
      expect(n, isNotNull);
      expect(n!.device, isNull, reason: 'the one-time review (M9)');
      expect(repo.registers, 1);
      final again = await NewDeviceWatcher.check(repo, 'u1');
      expect(again, isNull);
    });

    test('first run with only this phone says nothing', () async {
      final repo = _Repo([_d('a', current: true)]);
      expect(await NewDeviceWatcher.check(repo, 'u1'), isNull);
    });

    test(
      'a device signed in since the last check is reported, newest first',
      () async {
        final repo = _Repo([_d('a', current: true)]);
        await NewDeviceWatcher.check(repo, 'u1');
        repo.devices = [
          _d('a', current: true),
          _d('b', day: 3),
          _d('c', day: 5),
        ];
        final n = await NewDeviceWatcher.check(repo, 'u1');
        expect(n!.device!.sessionId, 'c');
        expect(await NewDeviceWatcher.check(repo, 'u1'), isNull);
      },
    );

    test('what is known is kept per account', () async {
      final repo = _Repo([_d('a', current: true)]);
      await NewDeviceWatcher.check(repo, 'u1');
      repo.devices = [_d('a', current: true), _d('b')];
      final other = await NewDeviceWatcher.check(repo, 'u2');
      expect(other!.device, isNull, reason: 'u2 is on its first run');
    });

    test('a failure says nothing and remembers nothing', () async {
      final repo = _Repo([_d('a', current: true), _d('b')])..fail = true;
      expect(await NewDeviceWatcher.check(repo, 'u1'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(NewDeviceWatcher.knownKey('u1')), isNull);
    });
  });

  group('watcher', () {
    ProviderContainer container(
      _Repo repo, {
      bool allowed = true,
      String? userId = 'u1',
      DateTime Function()? clock,
    }) {
      final c = ProviderContainer(
        overrides: [
          accountSessionsRepositoryProvider.overrideWithValue(repo),
          newDeviceCheckAllowedProvider.overrideWithValue(() => allowed),
          newDeviceUserIdProvider.overrideWithValue(userId),
          if (clock != null) newDeviceClockProvider.overrideWithValue(clock),
          newDeviceLockOpenProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('no check while locked or on the decoy screen (I6)', () async {
      final repo = _Repo([_d('a', current: true), _d('b')]);
      final c = container(repo, allowed: false);
      await c.read(newDeviceNoticeProvider.notifier).maybeCheck(force: true);
      expect(repo.lists, 0);
      expect(c.read(newDeviceNoticeProvider), isNull);
    });

    test('no check while signed out', () async {
      final repo = _Repo([_d('a', current: true)]);
      final c = container(repo, userId: null);
      await c.read(newDeviceNoticeProvider.notifier).maybeCheck(force: true);
      expect(repo.lists, 0);
    });

    test('checks at most every five minutes unless forced', () async {
      var now = DateTime(2026, 10, 17, 9);
      final repo = _Repo([_d('a', current: true)]);
      final c = container(repo, clock: () => now);
      final w = c.read(newDeviceNoticeProvider.notifier);
      await w.maybeCheck();
      await w.maybeCheck();
      expect(repo.lists, 1);
      now = now.add(const Duration(minutes: 6));
      await w.maybeCheck();
      expect(repo.lists, 2);
      await w.maybeCheck(force: true);
      expect(repo.lists, 3);
    });

    test('checks again when the lock opens, not while it is checking '
        '(review M-6)', () async {
      final repo = _Repo([_d('a', current: true)]);
      final open = StateProvider<bool>((_) => false);
      var now = DateTime(2026, 10, 17, 9);
      final c = ProviderContainer(
        overrides: [
          newDeviceClockProvider.overrideWithValue(() => now),
          accountSessionsRepositoryProvider.overrideWithValue(repo),
          newDeviceCheckAllowedProvider.overrideWithValue(() => true),
          newDeviceUserIdProvider.overrideWithValue('u1'),
          newDeviceLockOpenProvider.overrideWith((ref) => ref.watch(open)),
        ],
      );
      addTearDown(c.dispose);
      c.read(newDeviceNoticeProvider);
      await Future<void>.delayed(Duration.zero);
      final before = repo.lists;
      now = now.add(const Duration(minutes: 6));
      c.read(open.notifier).state = true;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(repo.lists, before + 1);
    });

    test('a found device becomes the notice; dismiss clears it', () async {
      final repo = _Repo([_d('a', current: true)]);
      final c = container(repo);
      final w = c.read(newDeviceNoticeProvider.notifier);
      await w.maybeCheck(force: true);
      repo.devices = [_d('a', current: true), _d('b')];
      await w.maybeCheck(force: true);
      expect(c.read(newDeviceNoticeProvider)!.device!.sessionId, 'b');
      w.dismiss();
      expect(c.read(newDeviceNoticeProvider), isNull);
    });
  });

  group('banner', () {
    late GoRouter router;

    Future<void> pump(WidgetTester t, DeviceNotice? notice) async {
      router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
          GoRoute(
            path: '/neutralScreen',
            name: 'neutralScreen',
            builder: (_, __) => const Text('NEUTRAL'),
          ),
          GoRoute(
            path: '/settings/signed-in-devices',
            name: 'signedInDevices',
            builder: (_, __) => const Text('DEVICES'),
          ),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            newDeviceNoticeProvider.overrideWith(() => _Fixed(notice)),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder:
                (_, child) => NewDeviceNotice(router: router, child: child!),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('names the device and the day it signed in', (t) async {
      final b = _d('b');
      await pump(t, DeviceNotice(device: b));
      expect(
        find.text(
          'A new device signed in to your account: Android phone, '
          '${MyDateFormat.toDate(b.signedInAt.toLocal())}. '
          'Not you? Review your devices.',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Dismiss'));
      await t.pumpAndSettle();
      expect(find.textContaining('A new device'), findsNothing);
    });

    testWidgets('Review opens Where you\'re signed in', (t) async {
      await pump(t, DeviceNotice(device: _d('b')));
      await t.tap(find.text('Review'));
      await t.pumpAndSettle();
      expect(find.text('DEVICES'), findsOneWidget);
      expect(find.textContaining('A new device'), findsNothing);
    });

    testWidgets('the one-time review notice (M9)', (t) async {
      await pump(t, const DeviceNotice());
      expect(find.text("Review where you're signed in"), findsOneWidget);
    });

    testWidgets('never shows over the decoy screen', (t) async {
      await pump(t, DeviceNotice(device: _d('b')));
      router.go('/neutralScreen');
      await t.pumpAndSettle();
      expect(find.text('NEUTRAL'), findsOneWidget);
      expect(find.textContaining('A new device'), findsNothing);
    });

    testWidgets('nothing to say: just the app', (t) async {
      await pump(t, null);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Dismiss'), findsNothing);
    });
  });
}

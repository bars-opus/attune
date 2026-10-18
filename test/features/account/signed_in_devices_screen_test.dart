// Spec 2 (research 06 §3 F7 (1), (2)): Settings → Where you're signed in.
import 'package:attune/features/account/data/account_sessions.dart';
import 'package:attune/features/account/presentation/signed_in_devices_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

final _phone = SignedInDevice(
  sessionId: 's1',
  label: 'iPhone or iPad · iOS 17.2',
  platform: 'ios',
  signedInAt: DateTime.utc(2026, 10, 1, 9),
  lastActiveAt: DateTime.utc(2026, 10, 2, 9),
  isCurrent: true,
);
final _other = SignedInDevice(
  sessionId: 's2',
  label: 'Android phone',
  platform: 'android',
  signedInAt: DateTime.utc(2026, 9, 20, 9),
  lastActiveAt: DateTime.utc(2026, 9, 21, 9),
  isCurrent: false,
);

class _Repo extends AccountSessionsRepository {
  _Repo() : super((fn, [p]) async => null, () async {});
  int signOuts = 0;
  @override
  Future<void> signOutOtherDevices() async => signOuts++;
}

Future<int> _pump(
  WidgetTester t,
  _Repo repo,
  List<SignedInDevice> devices,
) async {
  var loads = 0;
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        accountSessionsRepositoryProvider.overrideWithValue(repo),
        signedInDevicesProvider.overrideWith((ref) async {
          loads++;
          return devices;
        }),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => const MaterialApp(home: SignedInDevicesScreen()),
      ),
    ),
  );
  await t.pumpAndSettle();
  return loads;
}

void main() {
  testWidgets('lists each device, marking this phone', (t) async {
    await _pump(t, _Repo(), [_phone, _other]);
    expect(find.text("Where you're signed in"), findsOneWidget);
    expect(
      find.text("Phones you no longer use stay here until you sign them out."),
      findsOneWidget,
    );
    expect(find.text('iPhone or iPad · iOS 17.2 · This phone'), findsOneWidget);
    expect(find.text('Android phone'), findsOneWidget);
    expect(find.textContaining('Last active'), findsNWidgets(2));
    expect(find.textContaining('Signed in '), findsNWidgets(2));
  });

  testWidgets('sign out others asks first, then signs them out once', (
    t,
  ) async {
    final repo = _Repo();
    var loads = 0;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          accountSessionsRepositoryProvider.overrideWithValue(repo),
          signedInDevicesProvider.overrideWith((ref) async {
            loads++;
            return [_phone, _other];
          }),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => const MaterialApp(home: SignedInDevicesScreen()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(loads, 1);
    await t.tap(find.text('Sign out all other devices'));
    await t.pumpAndSettle();
    expect(find.text('Sign out all other devices?'), findsOneWidget);
    expect(find.textContaining('up to an hour'), findsOneWidget);
    expect(repo.signOuts, 0);
    await t.tap(find.text('Sign out others'));
    await t.pumpAndSettle();
    expect(repo.signOuts, 1);
    expect(find.text('Other devices are signed out.'), findsOneWidget);
    expect(loads, 2, reason: 'the list reloads after signing out');
  });

  testWidgets('one device: a plain line and no button', (t) async {
    await _pump(t, _Repo(), [_phone]);
    expect(find.text('Only this phone is signed in.'), findsOneWidget);
    expect(find.text('Sign out all other devices'), findsNothing);
  });
}

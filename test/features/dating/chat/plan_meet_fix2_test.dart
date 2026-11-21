// Spec 2 W6c Task 10 fix round 2 (re-review minors): a check-in read that
// fails online says so, still offers Cancel (safe with nothing pending)
// and a way to read again; the no-push line waits until this phone's push
// state is known (the SDK started, the permission and the device token
// read), while the server's own "no device" is always believed.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/notifications/onesignal_service_test.dart'
    show FakePushSdk;
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_shell.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

final _meet = DateTime(2026, 11, 21, 15, 30);
final _checkin = _meet.add(kDatingCheckinAfter);
const _plan = '/dating/chat/m1/plan';

Future<void> _remember() async {
  await DatingPlanMemory.clear();
  DatingPlanMemory.account = 'ama';
  DatingPlanMemory.place = 'Osu';
  DatingPlanMemory.at = _meet;
}

void main() {
  final loc = AppLocalizationsEn();
  List<Override> kit(FakeDatingChat fake) => [
    ...datingChatOverrides(fake),
    datingShareProvider.overrideWithValue((text, origin) async {}),
    datingSmsProvider.overrideWithValue((body, origin) async {}),
  ];
  String setLine(DateTime at) => loc.dating_planCheckinSet(
    MyDateFormat.toDate(at),
    MyDateFormat.toTime(at),
  );

  setUp(() async => DatingPlanMemory.clear());

  testWidgets('a read that fails online says so, offers Cancel with nothing '
      'in memory, and reads again on Try again', (t) async {
    await _remember();
    final fake = FakeDatingChat()..refusals['checkin'] = 'failed';
    await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
    expect(find.text(loc.dating_planCheckinUnknown), findsOneWidget);
    expect(find.text(loc.dating_planCheckinCancel), findsOneWidget);
    // The server answers now: a check-in is set.
    fake.refusals.remove('checkin');
    fake.checkinAt = _checkin.toUtc();
    final reads = fake.checkinReads;
    await tap(t, find.text(loc.dating_tryAgain));
    await t.pumpAndSettle();
    expect(fake.checkinReads, reads + 1);
    expect(find.text(loc.dating_planCheckinUnknown), findsNothing);
    expect(find.text(setLine(_checkin)), findsOneWidget);
  });

  testWidgets('Cancel while the state is unknown asks the server', (t) async {
    await _remember();
    final fake = FakeDatingChat()..refusals['checkin'] = 'failed';
    await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
    await tap(t, find.text(loc.dating_planCheckinCancel));
    await t.pumpAndSettle();
    expect(fake.checkins, [null]);
    expect(find.text(loc.dating_planCheckinCancel), findsNothing);
  });

  testWidgets('offline, nothing says the read failed (it was not tried)', (
    t,
  ) async {
    await _remember();
    await pumpDatingShell(
      t,
      initial: _plan,
      online: false,
      overrides: kit(FakeDatingChat()..refusals['checkin'] = 'failed'),
    );
    expect(find.text(loc.dating_planCheckinUnknown), findsNothing);
  });

  for (final (phone, server, noPush) in [
    (null, true, false),
    (null, false, true),
    (false, true, true),
    (true, true, false),
  ]) {
    testWidgets('this phone $phone, the server $server: no-push line '
        '$noPush', (t) async {
      await _remember();
      final fake =
          FakeDatingChat()
            ..checkinAt = _checkin.toUtc()
            ..checkinPush = server;
      await pumpDatingShell(
        t,
        initial: _plan,
        overrides: [
          ...kit(fake),
          datingPushAllowedProvider.overrideWithValue(() => phone),
        ],
      );
      expect(
        find.text(loc.dating_planCheckinNoPush),
        noPush ? findsOneWidget : findsNothing,
      );
      expect(
        find.text(setLine(_checkin)),
        noPush ? findsNothing : findsOneWidget,
      );
    });
  }

  test('this phone\'s push state is known only once the SDK has started '
      'and, when allowed, has a device token', () {
    expect(datingPushState(started: false, granted: true, token: 'x'), isNull);
    expect(datingPushState(started: true, granted: false, token: 'x'), false);
    expect(datingPushState(started: true, granted: true, token: null), isNull);
    expect(datingPushState(started: true, granted: true, token: 'x'), true);
    final container = ProviderContainer(
      overrides: [
        oneSignalServiceProvider.overrideWith(
          (ref) => OneSignalService(ref, sdk: FakePushSdk(), platform: 'ios'),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Never started: unknown, never "off".
    expect(container.read(datingPushAllowedProvider)(), isNull);
  });
}

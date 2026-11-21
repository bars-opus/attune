// Spec 2 W6 final client fix wave (final-client-review.md): leave, never
// introduce, abroad and not-open have a way back as the only page (C-5);
// the meet plan stays wiped after quick exit, whatever answer lands after
// (M-2); a remembered meet time that has passed is dropped (M-4); a
// realtime rejoin is one more "read again" (I-1).
import 'dart:async';

import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_shell.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

/// The kit's read of the pending check-in, held until the test answers.
class _HeldRead extends FakeDatingChat {
  Completer<DatingCheckin>? readHold;

  @override
  Future<DatingCheckin> checkin() {
    final h = readHold;
    if (h == null) return super.checkin();
    checkinReads++;
    return h.future;
  }
}

final _meet = DateTime(2026, 11, 21, 15, 30);

Future<void> _remember(String place, DateTime at) async {
  await DatingPlanMemory.clear();
  DatingPlanMemory.account = 'ama';
  DatingPlanMemory.place = place;
  DatingPlanMemory.at = at;
}

Future<void> _quickExit() async {
  final registry = DeviceWipeRegistry();
  registerDatingDeviceWipes(registry);
  await registry.run(WipeMoment.quickExit);
}

void main() {
  final loc = AppLocalizationsEn();
  final rootBack = find.byKey(const ValueKey('dating_root_back'));

  List<Override> kit(FakeDatingChat fake) => [
    ...datingChatOverrides(fake),
    datingShareProvider.overrideWithValue((text, origin) async {}),
    datingSmsProvider.overrideWithValue((body, origin) async {}),
  ];

  setUp(DatingPlanMemory.clear);

  group('C-5: the only page has a way back', () {
    for (final (name, initial, title) in [
      ('Leave', DatingPaths.leave, loc.dating_leaveTitle),
      ('Never introduce', DatingPaths.neverIntroduce, null),
      ('Other countries', DatingPaths.abroad, loc.dating_abroadTitle),
    ]) {
      testWidgets('$name: back to Dating settings (button and system back)', (
        t,
      ) async {
        var s = await pumpDatingShell(t, initial: initial);
        expect(s.location, initial);
        if (title != null) expect(find.text(title), findsWidgets);
        expect(s.router.canPop(), isFalse);
        expect(rootBack, findsOneWidget);
        await tap(t, rootBack);
        await t.pumpAndSettle();
        expect(s.location, DatingPaths.settings);

        s = await pumpDatingShell(t, initial: initial);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(s.location, DatingPaths.settings);
      });
    }

    testWidgets('Not open: the system back goes to Me', (t) async {
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.notOpenFor(country: 'NG'),
      );
      expect(s.location, startsWith(DatingPaths.notOpen));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('ME me'), findsOneWidget);
    });

    testWidgets('pushed over settings: the ordinary back', (t) async {
      final s = await pumpDatingShell(t, initial: DatingPaths.settings);
      unawaited(s.router.push(DatingPaths.leave));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_leaveTitle), findsWidgets);
      expect(rootBack, findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(s.location, DatingPaths.settings);
    });
  });

  group('M-2: quick exit while an answer is on its way', () {
    testWidgets('Check on me answered after the wipe writes nothing back', (
      t,
    ) async {
      await _remember('Accra Mall food court', _meet);
      final fake = FakeDatingChat();
      final hold = fake.checkinHold = Completer<DatingChatAnswer>();
      await pumpDatingShell(
        t,
        initial: '/dating/chat/m1/plan',
        overrides: kit(fake),
      );
      expect(find.text('Accra Mall food court'), findsOneWidget);
      await tap(t, find.text(loc.dating_planCheckOnMe));
      expect(fake.checkins, hasLength(1));
      await _quickExit();
      hold.complete(const DatingChatAnswer(ok: true, push: true));
      await t.pumpAndSettle();
      expect(DatingPlanMemory.place, isNull);
      expect(DatingPlanMemory.at, isNull);
      expect(DatingPlanMemory.account, isNull);
      expect(DatingPlanMemory.checkinAt, isNull);
    });

    testWidgets('the check-in read answered after the wipe writes nothing '
        'back', (t) async {
      await _remember('Accra Mall food court', _meet);
      final fake = _HeldRead();
      final hold = fake.readHold = Completer<DatingCheckin>();
      await pumpDatingShell(
        t,
        initial: '/dating/chat/m1/plan',
        overrides: kit(fake),
      );
      expect(find.text('Accra Mall food court'), findsOneWidget);
      expect(fake.checkinReads, 1);
      await _quickExit();
      hold.complete(
        DatingCheckin(
          known: true,
          at: _meet.add(kDatingCheckinAfter),
          push: true,
        ),
      );
      await t.pumpAndSettle();
      expect(DatingPlanMemory.place, isNull);
      expect(DatingPlanMemory.at, isNull);
      expect(DatingPlanMemory.account, isNull);
      expect(DatingPlanMemory.checkinAt, isNull);
    });

    testWidgets('another account\'s plan is remembered for it', (t) async {
      await _remember('Osu', _meet);
      final s = await pumpDatingShell(
        t,
        initial: '/dating/chat/m1/plan',
        overrides: kit(FakeDatingChat()),
      );
      expect(find.text('Osu'), findsOneWidget);
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      expect(find.text('Osu'), findsNothing);
      await t.enterText(
        find.byKey(const ValueKey('dating_plan_place')),
        'Labadi',
      );
      await t.pump();
      expect(DatingPlanMemory.account, 'esi');
      expect(DatingPlanMemory.place, 'Labadi');
    });

    testWidgets('the kit alone (no lock gate rebuilding it): another '
        'account\'s plan is remembered for it', (t) async {
      await _remember('Osu', _meet);
      await pumpFlowScreen(
        t,
        () => const DatingPlanMeetScreen(matchId: 'm1'),
        overrides: [...datingShellOverrides(), ...kit(FakeDatingChat())],
      );
      expect(find.text('Osu'), findsOneWidget);
      ProviderScope.containerOf(t.element(find.byType(MaterialApp)))
          .read(datingTestAccount.notifier)
          .state = 'esi';
      await t.pumpAndSettle();
      expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
      expect(find.text('Osu'), findsNothing);
      await t.enterText(
        find.byKey(const ValueKey('dating_plan_place')),
        'Labadi',
      );
      await t.pump();
      expect(DatingPlanMemory.account, 'esi');
      expect(DatingPlanMemory.place, 'Labadi');
    });

    testWidgets('without a wipe, the plan is still remembered', (t) async {
      await _remember('Osu', _meet);
      final fake = FakeDatingChat();
      await pumpDatingShell(
        t,
        initial: '/dating/chat/m1/plan',
        overrides: kit(fake),
      );
      await tap(t, find.text(loc.dating_planCheckOnMe));
      await t.pumpAndSettle();
      expect(DatingPlanMemory.place, 'Osu');
      expect(DatingPlanMemory.at, _meet);
      expect(DatingPlanMemory.checkinAt, _meet.add(kDatingCheckinAfter));
    });
  });

  testWidgets('M-4: a remembered meet time that has passed is dropped', (
    t,
  ) async {
    // The shell's clock is 2026-11-21 09:00.
    await _remember('Osu', DateTime(2026, 11, 20, 15));
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1/plan',
      overrides: kit(FakeDatingChat()),
    );
    expect(find.text('Osu'), findsOneWidget);
    expect(find.text(loc.dating_planPickWhen), findsOneWidget);
    expect(find.text(loc.dating_planCheckinInvalid), findsNothing);
    expect(DatingPlanMemory.at, isNull);
  });

  test('I-1: a realtime rejoin is one more "read again" (the first join '
      'is not)', () async {
    final client = SupabaseClient('http://127.0.0.1:9', 'anon');
    addTearDown(client.dispose);
    final repo = DatingChatRepository(
      DatingRpc.withCall((fn, params) async => null),
      client,
    );
    var events = 0;
    final listening = repo.signals('ama').listen((_) => events++);
    addTearDown(listening.cancel);
    final channel = client.getChannels().single;
    Future<void> joined() async {
      // ignore: invalid_use_of_internal_member
      channel.joinPush.trigger('ok', <String, dynamic>{});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    await joined();
    expect(events, 0);
    // ignore: invalid_use_of_internal_member
    channel.joinPush.resend(const Duration(seconds: 1));
    await joined();
    expect(events, 1);
  });
}

// Owner follow-up to Spec 2 W6 (the fallback poll): some networks block
// WebSockets, so the chat's realtime signals never arrive. While the
// signal channel is not joined, the open chat and the conversations list
// read again every 30 s (give or take 3), only while they are the page
// shown, the app is in the foreground and the phone is online, never over
// a read already on its way, and never for another account. A join stops
// it, with one catch-up read when something may have been missed (N-2);
// a drop starts it again; dispose, another account, quick exit and the
// Dating lock end it. The connection's return reads nothing more when a
// rejoin already has (N-1).
import 'dart:async';

import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/chat/conversations_screen.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/data/dating_providers.dart'
    show datingAccountProvider;
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show datingUnlockedProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show RealtimeSubscribeStatus;

import '../../../helpers/flow_harness.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_shell.dart';

/// The fake whose next newest-page read can be held (the account-switch
/// test holds the last account's poll).
class _Fake extends FakeDatingChat {
  _Fake({this.holdNext = false}) {
    joins = false;
  }

  bool holdNext;
  Completer<DatingChatPage>? held;

  /// Fix round 1 (I-1): the list read throws (the provider's error state).
  bool listThrows = false;

  @override
  Future<DatingConversations> conversations({bool ended = false}) {
    if (!listThrows) return super.conversations(ended: ended);
    listReads++;
    return Future.error(StateError('list'));
  }

  @override
  Future<DatingChatPage> messages(String matchId, {DateTime? before}) {
    if (holdNext && before == null) {
      holdNext = false;
      reads.add((matchId, before));
      return (held = Completer<DatingChatPage>()).future;
    }
    return super.messages(matchId, before: before);
  }
}

/// Fix round 1 (M-4): the chat's safety-card read can be held.
class _CardsFake extends _Fake {
  Completer<List<DatingSafetyCard>>? cardsHold;
  Completer<DatingGuided>? guidedHold;

  @override
  Future<DatingGuided> guided(String matchId) {
    final h = guidedHold;
    if (h == null) return super.guided(matchId);
    guidedReads++;
    return h.future;
  }

  @override
  Future<List<DatingSafetyCard>> cards(String matchId) {
    final h = cardsHold;
    if (h == null) return super.cards(matchId);
    cardReads.add(matchId);
    return h.future;
  }
}

void main() {
  /// The connection, as the test turns it off and on.
  late StreamController<bool> network;

  setUp(() => network = StreamController<bool>.broadcast());
  tearDown(() => network.close());

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingChat fake, {
    String initial = '/dating/chat/m1',
    bool locked = false,
    List<Override> overrides = const [],
  }) => pumpDatingShell(
    t,
    initial: initial,
    locked: locked,
    pinSet: locked,
    overrides: [
      ...datingChatOverrides(fake),
      datingOnlineProvider.overrideWith((ref) async* {
        yield true;
        yield* network.stream;
      }),
      datingChatPollJitterProvider.overrideWithValue(() => Duration.zero),
      ...overrides,
    ],
  );

  /// [seconds] of the clock, then the frame that shows what was read.
  Future<void> wait(WidgetTester t, num seconds) async {
    await t.pump(Duration(milliseconds: (seconds * 1000).round()));
    await t.pump();
  }

  Future<void> status(
    WidgetTester t,
    FakeDatingChat fake,
    RealtimeSubscribeStatus s,
  ) async {
    fake.channelStatus(s);
    await t.pump();
    await t.pump();
  }

  /// The app put away (resumed, inactive, hidden, paused) or brought back.
  Future<void> lifecycle(WidgetTester t, AppLifecycleState s) async {
    const away = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    for (final step
        in s == AppLifecycleState.paused ? away : away.reversed.skip(1)) {
      t.binding.handleAppLifecycleStateChanged(step);
    }
    if (s == AppLifecycleState.resumed) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pump();
  }

  DatingChatSignalsNotifier poll(DatingShell s, [String account = 'ama']) =>
      s.container.read(datingChatSignalsProvider(account).notifier);

  group('the chat', () {
    testWidgets('a channel that never joins: a read every 30 s while shown, '
        'in the foreground and online', (t) async {
      final fake = _Fake();
      final s = await open(t, fake);
      expect(fake.reads.length, 1);
      expect(poll(s).polling, isTrue);
      await wait(t, 29);
      expect(fake.reads.length, 1);
      await wait(t, 1);
      expect(fake.reads.length, 2);
      await wait(t, 30);
      expect(fake.reads.length, 3);
      await wait(t, 30);
      expect(fake.reads.length, 4);
      // Only the newest page: never an older one.
      expect(fake.reads.every((r) => r.$1 == 'm1' && r.$2 == null), isTrue);
    });

    testWidgets('each wait is 30 s plus the jitter', (t) async {
      final jitters = [
        // The first wait, armed before the fake's join lands (then dropped).
        Duration.zero,
        const Duration(seconds: -3),
        const Duration(seconds: 3),
      ];
      final fake = FakeDatingChat();
      await open(
        t,
        fake,
        overrides: [
          datingChatPollJitterProvider.overrideWithValue(
            () => jitters.isEmpty ? Duration.zero : jitters.removeAt(0),
          ),
        ],
      );
      // Joined: the drop starts the poll at a known moment.
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await wait(t, 26.9);
      expect(fake.reads.length, 1);
      await wait(t, 0.2);
      expect(fake.reads.length, 2);
      await wait(t, 32.8);
      expect(fake.reads.length, 2);
      await wait(t, 0.2);
      expect(fake.reads.length, 3);
    });

    testWidgets('none while the app is away; on resume a full wait first', (
      t,
    ) async {
      addTearDown(
        () => t.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final fake = _Fake();
      final s = await open(t, fake);
      await wait(t, 10);
      await lifecycle(t, AppLifecycleState.paused);
      expect(poll(s).polling, isFalse);
      await wait(t, 120);
      expect(fake.reads.length, 1);
      await lifecycle(t, AppLifecycleState.resumed);
      // The chat's own resume read.
      expect(fake.reads.length, 2);
      await wait(t, 29);
      expect(fake.reads.length, 2);
      await wait(t, 1);
      expect(fake.reads.length, 3);
    });

    testWidgets('none while offline; on the return a full wait first', (
      t,
    ) async {
      final fake = _Fake();
      final s = await open(t, fake);
      await wait(t, 10);
      network.add(false);
      await t.pump();
      expect(poll(s).polling, isFalse);
      await wait(t, 120);
      expect(fake.reads.length, 1);
      network.add(true);
      await t.pump();
      await t.pump();
      // The return's own read (final client fix I-1).
      expect(fake.reads.length, 2);
      await wait(t, 29);
      expect(fake.reads.length, 2);
      await wait(t, 1);
      expect(fake.reads.length, 3);
    });

    testWidgets('none while a pushed page covers it', (t) async {
      final fake = _Fake();
      final s = await open(t, fake);
      unawaited(s.router.push(DatingPaths.plan('m1')));
      await t.pumpAndSettle();
      final before = fake.reads.length;
      await wait(t, 95);
      expect(fake.reads.length, before);
      s.router.pop();
      await t.pumpAndSettle();
      await wait(t, 30);
      expect(fake.reads.length, before + 1);
    });

    testWidgets('the channel joins: the poll stops, with one catch-up read', (
      t,
    ) async {
      final fake = _Fake();
      final s = await open(t, fake);
      await wait(t, 30);
      expect(fake.reads.length, 2);
      await wait(t, 5);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      expect(fake.reads.length, 3);
      expect(poll(s).polling, isFalse);
      await wait(t, 120);
      expect(fake.reads.length, 3);
    });

    testWidgets('a first join with nothing missed reads nothing (as before)', (
      t,
    ) async {
      final fake = _Fake();
      final s = await open(t, fake);
      await wait(t, 2);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      expect(fake.reads.length, 1);
      expect(poll(s).polling, isFalse);
      await wait(t, 120);
      expect(fake.reads.length, 1);
    });

    for (final failure in [
      RealtimeSubscribeStatus.channelError,
      RealtimeSubscribeStatus.timedOut,
    ]) {
      testWidgets('N-2: a join that fails ($failure), then a retry that '
          'succeeds: one catch-up read', (t) async {
        final fake = _Fake();
        await open(t, fake);
        await wait(t, 3);
        await status(t, fake, failure);
        expect(fake.reads.length, 1);
        await wait(t, 5);
        await status(t, fake, RealtimeSubscribeStatus.subscribed);
        expect(fake.reads.length, 2);
        await wait(t, 120);
        expect(fake.reads.length, 2);
      });
    }

    testWidgets('I-1: a second join reads again once', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      expect(fake.reads.length, 1);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      expect(fake.reads.length, 2);
    });

    testWidgets('a drop after the join starts the poll again; the rejoin '
        'stops it', (t) async {
      final fake = FakeDatingChat();
      final s = await open(t, fake);
      await wait(t, 60);
      expect(fake.reads.length, 1);
      expect(poll(s).polling, isFalse);
      await status(t, fake, RealtimeSubscribeStatus.closed);
      expect(fake.reads.length, 1);
      expect(poll(s).polling, isTrue);
      await wait(t, 30);
      expect(fake.reads.length, 2);
      // Failed retries every few seconds never hold the poll off.
      for (var i = 0; i < 5; i++) {
        await wait(t, 5);
        await status(t, fake, RealtimeSubscribeStatus.channelError);
      }
      await wait(t, 5);
      expect(fake.reads.length, 3);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      expect(fake.reads.length, 4);
      await wait(t, 120);
      expect(fake.reads.length, 4);
    });

    testWidgets('never over a read already on its way', (t) async {
      final fake = _Fake();
      await open(t, fake);
      fake.hold = Completer<DatingChatPage>();
      await wait(t, 30);
      expect(fake.reads.length, 2);
      await wait(t, 30);
      await wait(t, 30);
      expect(fake.reads.length, 2);
      final h = fake.hold!;
      fake.hold = null;
      h.complete(DatingChatPage.fromJson(fake.pageJson));
      await t.pump();
      await wait(t, 30);
      expect(fake.reads.length, 3);
    });

    testWidgets('a read from a signal pushes the next poll a full wait out '
        '(no second read in the same window)', (t) async {
      final fake = _Fake();
      await open(t, fake);
      await wait(t, 20);
      fake.signalEvents.add(null);
      await t.pump();
      await t.pump();
      expect(fake.reads.length, 2);
      await wait(t, 29);
      expect(fake.reads.length, 2);
      await wait(t, 1.5);
      expect(fake.reads.length, 3);
    });

    testWidgets('another account mid-poll: the last one\'s poll never lands '
        'on it, and its own starts fresh', (t) async {
      final fake = _Fake(holdNext: false);
      final s = await open(t, fake);
      final ama = poll(s);
      // Ama's poll is on its way when the account changes.
      await wait(t, 20);
      fake.holdNext = true;
      await wait(t, 10);
      expect(fake.reads.length, 2);
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      // Esi's own first read(s), as before the poll.
      final esi = fake.reads.length;
      expect(esi, greaterThan(2));
      expect(ama.polling, isFalse);
      expect(fake.signalAccounts.last, 'esi');
      fake.held!.complete(
        DatingChatPage.fromJson(
          datingPageJson(
            messages: [datingMessageJson('a9', 'Only for Ama', minute: 9)],
          ),
        ),
      );
      await t.pump();
      expect(find.text('Only for Ama'), findsNothing);
      // Esi's own poll: a full wait from the change, not Ama's timing.
      await wait(t, 29);
      expect(fake.reads.length, esi);
      await wait(t, 1.5);
      expect(fake.reads.length, esi + 1);
      expect(find.text('Only for Ama'), findsNothing);
    });

    testWidgets('the last account\'s poll, landing after the change is '
        'known but before the chat listens again, reads nothing', (t) async {
      final fake = FakeDatingChat();
      final s = await open(t, fake);
      // A drop starts Ama's poll at a known moment.
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await wait(t, 29.9);
      expect(fake.reads.length, 1);
      // The change is known at once (read), the chat rebuilds a frame later.
      s.container.read(datingTestAccount.notifier).state = 'esi';
      s.container.read(datingAccountProvider);
      // Only the change's own read; Ama's poll (due now) adds none.
      expect(fake.reads.length, 2);
      await t.pump(const Duration(milliseconds: 200));
      expect(fake.reads.length, 2);
      await t.pumpAndSettle();
    });

    testWidgets('leaving the chat ends the poll', (t) async {
      final fake = _Fake();
      final s = await open(t, fake);
      final ama = poll(s);
      expect(ama.polling, isTrue);
      s.router.go('/home');
      await t.pumpAndSettle();
      expect(s.container.exists(datingChatSignalsProvider('ama')), isFalse);
      expect(ama.polling, isFalse);
      await wait(t, 120);
      expect(fake.reads.length, 1);
    });

    testWidgets('quick exit ends the poll', (t) async {
      final fake = _Fake();
      final s = await open(t, fake);
      final ama = poll(s);
      await wait(t, 10);
      expect(ama.polling, isTrue);
      final registry = DeviceWipeRegistry();
      registerDatingDeviceWipes(registry);
      await registry.run(WipeMoment.quickExit);
      expect(ama.polling, isFalse);
      await wait(t, 120);
      expect(fake.reads.length, 1);
      // Even a drop after it starts nothing.
      await status(t, fake, RealtimeSubscribeStatus.closed);
      expect(ama.polling, isFalse);
    });

    testWidgets('the Dating lock ends the poll', (t) async {
      final fake = _Fake();
      final s = await open(t, fake, locked: true);
      s.container.read(datingUnlockedProvider.notifier).unlock();
      s.router.go('/dating/chat/m1');
      await t.pumpAndSettle();
      final ama = poll(s);
      expect(ama.polling, isTrue);
      final before = fake.reads.length;
      s.container.read(datingUnlockedProvider.notifier).lock();
      await t.pumpAndSettle();
      expect(s.location, startsWith('/dating/unlock?from='));
      expect(s.container.exists(datingChatSignalsProvider('ama')), isFalse);
      expect(ama.polling, isFalse);
      await wait(t, 120);
      expect(fake.reads.length, before);
    });
  });

  group('N-1: the connection comes back', () {
    Future<void> offline(WidgetTester t) async {
      network.add(false);
      await t.pump();
      await t.pump();
    }

    Future<void> online(WidgetTester t) async {
      network.add(true);
      await t.pump();
      await t.pump();
    }

    testWidgets('after a rejoin has read again: no second read', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      await offline(t);
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      expect(fake.reads.length, 2);
      await online(t);
      expect(fake.reads.length, 2);
    });

    testWidgets('before the rejoin: both read (only the rejoin\'s covers '
        'what came after the return)', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      await offline(t);
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await online(t);
      expect(fake.reads.length, 2);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      expect(fake.reads.length, 3);
    });

    testWidgets('a rejoin from before the phone went offline still lets '
        'the return read', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      expect(fake.reads.length, 2);
      await offline(t);
      await online(t);
      expect(fake.reads.length, 3);
    });

    testWidgets('fix round 1 (M-1): a drop after the rejoin clears it, so '
        'the return reads again', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      await offline(t);
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      expect(fake.reads.length, 2);
      await status(t, fake, RealtimeSubscribeStatus.channelError);
      await online(t);
      expect(fake.reads.length, 3);
    });

    testWidgets('a first join while offline read nothing, so the return '
        'still reads', (t) async {
      final fake = _Fake();
      await open(t, fake);
      await offline(t);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      expect(fake.reads.length, 1);
      await online(t);
      expect(fake.reads.length, 2);
    });

    testWidgets('the list: after a rejoin has read again, no second read', (
      t,
    ) async {
      final fake = FakeDatingChat();
      await open(t, fake, initial: DatingPaths.chats);
      expect(fake.listReads, 1);
      await offline(t);
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      await t.pumpAndSettle();
      expect(fake.listReads, 2);
      await online(t);
      await t.pumpAndSettle();
      expect(fake.listReads, 2);
    });
  });

  group('the conversations list', () {
    Future<DatingShell> list(WidgetTester t, FakeDatingChat fake) =>
        open(t, fake, initial: DatingPaths.chats);

    Future<void> waitList(WidgetTester t, num seconds) async {
      await wait(t, seconds);
      await t.pumpAndSettle();
    }

    testWidgets('a channel that never joins: a read every 30 s while shown, '
        'in the foreground and online', (t) async {
      final fake = _Fake();
      final s = await list(t, fake);
      expect(fake.listReads, 1);
      expect(poll(s).polling, isTrue);
      await waitList(t, 29);
      expect(fake.listReads, 1);
      await waitList(t, 1);
      expect(fake.listReads, 2);
      await waitList(t, 30);
      expect(fake.listReads, 3);
    });

    testWidgets('none while the app is away', (t) async {
      addTearDown(
        () => t.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final fake = _Fake();
      final s = await list(t, fake);
      await waitList(t, 10);
      await lifecycle(t, AppLifecycleState.paused);
      expect(poll(s).polling, isFalse);
      await waitList(t, 120);
      expect(fake.listReads, 1);
      await lifecycle(t, AppLifecycleState.resumed);
      await t.pumpAndSettle();
      // Fix round 1 (M-2): the list's own resume read, then a full wait.
      expect(fake.listReads, 2);
      await waitList(t, 29);
      expect(fake.listReads, 2);
      await waitList(t, 1);
      expect(fake.listReads, 3);
    });

    testWidgets('none while offline', (t) async {
      final fake = _Fake();
      final s = await list(t, fake);
      expect(poll(s).polling, isTrue);
      network.add(false);
      await t.pump();
      expect(poll(s).polling, isFalse);
      await waitList(t, 120);
      expect(fake.listReads, 1);
    });

    testWidgets('none while a chat covers it; the chat reads instead', (
      t,
    ) async {
      final fake = _Fake();
      await list(t, fake);
      await t.tap(find.byKey(const ValueKey('dating_chats_row_m1')));
      await t.pumpAndSettle();
      expect(find.text('Hi Ama!'), findsOneWidget);
      final lists = fake.listReads;
      final reads = fake.reads.length;
      await waitList(t, 95);
      expect(fake.listReads, lists);
      expect(fake.reads.length, reads + 3);
    });

    testWidgets('the channel joins: the poll stops, with one catch-up read', (
      t,
    ) async {
      final fake = _Fake();
      final s = await list(t, fake);
      await waitList(t, 30);
      expect(fake.listReads, 2);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      await t.pumpAndSettle();
      expect(fake.listReads, 3);
      expect(poll(s).polling, isFalse);
      await waitList(t, 120);
      expect(fake.listReads, 3);
    });

    testWidgets('N-2: a failed join, then one that succeeds: one catch-up '
        'read', (t) async {
      final fake = _Fake();
      await list(t, fake);
      await status(t, fake, RealtimeSubscribeStatus.timedOut);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      await t.pumpAndSettle();
      expect(fake.listReads, 2);
      await waitList(t, 120);
      expect(fake.listReads, 2);
    });

    testWidgets('a drop after the join starts the poll again', (t) async {
      final fake = FakeDatingChat();
      await list(t, fake);
      await waitList(t, 60);
      expect(fake.listReads, 1);
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await waitList(t, 30);
      expect(fake.listReads, 2);
    });

    testWidgets('never over a read already on its way', (t) async {
      final fake = _Fake();
      await list(t, fake);
      fake.listHold = Completer<DatingConversations>();
      await wait(t, 30);
      expect(fake.listReads, 2);
      await wait(t, 30);
      await wait(t, 30);
      expect(fake.listReads, 2);
      final h = fake.listHold!;
      fake.listHold = null;
      h.complete(DatingConversations.fromJson(datingConversationsJson()));
      await t.pumpAndSettle();
      await waitList(t, 30);
      expect(fake.listReads, 3);
    });

    testWidgets('another account: the last one\'s poll ends, its own starts '
        'fresh', (t) async {
      final fake = _Fake();
      final s = await list(t, fake);
      final ama = poll(s);
      await waitList(t, 20);
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      final reads = fake.listReads;
      expect(ama.polling, isFalse);
      expect(poll(s, 'esi').polling, isTrue);
      await waitList(t, 15);
      expect(fake.listReads, reads);
      await waitList(t, 16);
      expect(fake.listReads, reads + 1);
    });

    testWidgets('the last account\'s poll, landing after the change is '
        'known but before the list listens again, reads nothing', (t) async {
      final fake = FakeDatingChat();
      final s = await list(t, fake);
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await wait(t, 29.9);
      expect(fake.listReads, 1);
      s.container.read(datingTestAccount.notifier).state = 'esi';
      s.container.read(datingAccountProvider);
      await t.pump(const Duration(milliseconds: 200));
      // Ama's poll is due inside that pump; only Esi's own first read.
      expect(fake.listReads, 2);
      await t.pumpAndSettle();
    });

    testWidgets('leaving the list ends the poll', (t) async {
      final fake = _Fake();
      final s = await list(t, fake);
      final ama = poll(s);
      expect(ama.polling, isTrue);
      s.router.go('/home');
      await t.pumpAndSettle();
      expect(s.container.exists(datingChatSignalsProvider('ama')), isFalse);
      expect(ama.polling, isFalse);
      await waitList(t, 120);
      expect(fake.listReads, 1);
    });
  });

  group('fix round 1', () {
    final loc = AppLocalizationsEn();
    final kofi = find.text('Kofi, 31');
    final announced = find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.liveRegion ?? false),
    );

    Future<void> waitList(WidgetTester t, num seconds) async {
      await wait(t, seconds);
      await t.pumpAndSettle();
    }

    testWidgets('I-1: a failed poll keeps the list, under a line that says '
        'nothing aloud', (t) async {
      final fake = _Fake();
      await open(t, fake, initial: DatingPaths.chats);
      expect(kofi, findsOneWidget);
      fake.refusals['conversations'] = 'failed';
      await waitList(t, 30);
      expect(fake.listReads, 2);
      expect(kofi, findsOneWidget);
      expect(find.text('Yaw, 34'), findsOneWidget);
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
      expect(announced, findsNothing);
      // The next good poll takes the line away; the rows stay.
      fake.refusals.clear();
      await waitList(t, 30);
      expect(fake.listReads, 3);
      expect(kofi, findsOneWidget);
      expect(find.text(loc.dating_errorGeneric), findsNothing);
    });

    testWidgets('I-1: a poll that throws keeps the list too', (t) async {
      final fake = _Fake();
      await open(t, fake, initial: DatingPaths.chats);
      fake.listThrows = true;
      await waitList(t, 30);
      expect(fake.listReads, 2);
      expect(kofi, findsOneWidget);
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
      expect(announced, findsNothing);
    });

    testWidgets('I-1: a busy poll keeps the list under the busy line', (
      t,
    ) async {
      final fake = _Fake();
      await open(t, fake, initial: DatingPaths.chats);
      fake.refusals['conversations'] = 'busy';
      await waitList(t, 30);
      expect(kofi, findsOneWidget);
      expect(find.text(loc.dating_busy), findsOneWidget);
      expect(announced, findsNothing);
    });

    testWidgets('I-1: a failed rejoin read keeps the list too', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake, initial: DatingPaths.chats);
      fake.refusals['conversations'] = 'failed';
      await status(t, fake, RealtimeSubscribeStatus.closed);
      await status(t, fake, RealtimeSubscribeStatus.subscribed);
      await t.pumpAndSettle();
      expect(fake.listReads, 2);
      expect(kofi, findsOneWidget);
      expect(announced, findsNothing);
    });

    testWidgets('I-1: Try again under the kept list is asked for, so its '
        'failure is said aloud', (t) async {
      final fake = _Fake();
      await open(t, fake, initial: DatingPaths.chats);
      fake.refusals['conversations'] = 'failed';
      await waitList(t, 30);
      expect(announced, findsNothing);
      await t.tap(find.text(loc.dating_tryAgain));
      await t.pumpAndSettle();
      expect(fake.listReads, 3);
      expect(kofi, findsOneWidget);
      expect(announced, findsOneWidget);
    });

    testWidgets('I-1: a first load that fails is still the error with Try '
        'again', (t) async {
      final fake = _Fake()..refusals['conversations'] = 'failed';
      await open(t, fake, initial: DatingPaths.chats);
      expect(kofi, findsNothing);
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
      expect(find.text(loc.dating_tryAgain), findsOneWidget);
    });

    testWidgets('I-1, D8: the kept list is never shown to another account', (
      t,
    ) async {
      final fake = _Fake();
      final s = await open(t, fake, initial: DatingPaths.chats);
      expect(kofi, findsOneWidget);
      fake.refusals['conversations'] = 'failed';
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      expect(kofi, findsNothing);
      expect(find.text(loc.dating_tryAgain), findsOneWidget);
    });

    testWidgets('I-1, D8, the list alone (no lock gate rebuilding it): the '
        'kept list is never shown to another account', (t) async {
      final fake = _Fake();
      await pumpFlowScreen(
        t,
        () => const DatingConversationsScreen(),
        overrides: [
          ...datingShellOverrides(),
          ...datingChatOverrides(fake),
          datingChatPollJitterProvider.overrideWithValue(() => Duration.zero),
        ],
      );
      expect(kofi, findsOneWidget);
      fake.refusals['conversations'] = 'failed';
      ProviderScope.containerOf(t.element(find.byType(MaterialApp)))
          .read(datingTestAccount.notifier)
          .state = 'esi';
      await t.pumpAndSettle();
      expect(find.byType(DatingConversationsScreen), findsOneWidget);
      expect(kofi, findsNothing);
      expect(find.text(loc.dating_tryAgain), findsOneWidget);
    });

    testWidgets('M-2: the list reads again on resume', (t) async {
      addTearDown(
        () => t.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final fake = FakeDatingChat();
      await open(t, fake, initial: DatingPaths.chats);
      await lifecycle(t, AppLifecycleState.paused);
      await lifecycle(t, AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(fake.listReads, 2);
    });

    testWidgets('M-2: covered by the chat, the list leaves resume to the '
        'chat', (t) async {
      addTearDown(
        () => t.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final fake = FakeDatingChat();
      await open(t, fake, initial: DatingPaths.chats);
      await t.tap(find.byKey(const ValueKey('dating_chats_row_m1')));
      await t.pumpAndSettle();
      final lists = fake.listReads;
      final reads = fake.reads.length;
      await lifecycle(t, AppLifecycleState.paused);
      await lifecycle(t, AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(fake.listReads, lists);
      expect(fake.reads.length, reads + 1);
    });

    testWidgets('M-3: the chat\'s own open read pushes the next poll a full '
        'wait out', (t) async {
      final fake = _Fake();
      await open(t, fake, initial: DatingPaths.chats);
      await waitList(t, 20);
      await t.tap(find.byKey(const ValueKey('dating_chats_row_m1')));
      await t.pumpAndSettle();
      expect(fake.reads.length, 1);
      await wait(t, 29);
      expect(fake.reads.length, 1);
      await wait(t, 1.5);
      expect(fake.reads.length, 2);
    });

    testWidgets('M-3: the list\'s way-back read pushes the next poll a '
        'full wait out', (t) async {
      final fake = _Fake();
      final s = await open(t, fake, initial: DatingPaths.chats);
      await t.tap(find.byKey(const ValueKey('dating_chats_row_m1')));
      await t.pumpAndSettle();
      await wait(t, 20);
      s.router.pop();
      await t.pumpAndSettle();
      final lists = fake.listReads;
      await waitList(t, 29);
      expect(fake.listReads, lists);
      await waitList(t, 1.5);
      expect(fake.listReads, lists + 1);
    });

    testWidgets('M-4: never over a safety-card read on its way', (t) async {
      final fake = _CardsFake();
      await open(t, fake);
      fake.cardsHold = Completer<List<DatingSafetyCard>>();
      await wait(t, 30);
      expect(fake.reads.length, 2);
      await wait(t, 30);
      expect(fake.reads.length, 2);
      final h = fake.cardsHold!;
      fake.cardsHold = null;
      h.complete(const []);
      await t.pump();
      await wait(t, 30);
      expect(fake.reads.length, 3);
    });
  });

  testWidgets('fix round 1 (M-4): never over a guided read on its way', (
    t,
  ) async {
    final fake = _CardsFake()..guidedHold = Completer<DatingGuided>();
    await open(t, fake);
    expect(fake.guidedReads, 1);
    await wait(t, 30);
    await wait(t, 30);
    expect(fake.reads.length, 1);
    final h = fake.guidedHold!;
    fake.guidedHold = null;
    h.complete(DatingGuided.none);
    await t.pump();
    await wait(t, 30);
    expect(fake.reads.length, 2);
  });

  test('the jitter stays within 3 s either way and varies', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final jitter = container.read(datingChatPollJitterProvider);
    final ms = [for (var i = 0; i < 2000; i++) jitter().inMilliseconds];
    expect(kDatingChatFallbackPoll, const Duration(seconds: 30));
    expect(ms.every((m) => m >= -3000 && m <= 3000), isTrue);
    expect(ms.reduce((a, b) => a < b ? a : b), lessThan(-2500));
    expect(ms.reduce((a, b) => a > b ? a : b), greaterThan(2500));
  });
}

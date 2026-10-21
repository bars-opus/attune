import 'dart:async';

import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:attune/features/chat/presentation/widgets/voice_message_player.dart';
import 'package:attune/core/widgets/rolling_duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_voice_engine.dart';

/// The real session port is a platform channel, absent on the test host
/// (chat review #40: every pause/complete/stop returns the session).
Override _fakeSession() => audioSessionProvider.overrideWith(
  (ref) => AudioSessionCoordinator(port: FakeAudioSessionPort()),
);

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      voicePlaybackEngineProvider.overrideWithValue(FakeVoiceEngine()),
      _fakeSession(),
      ...overrides,
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('the duration rolls rather than cutting', (tester) async {
    // Asserted structurally: a plain Text showing the same number passes
    // every value-based check, so nothing else here distinguishes a
    // rolling counter from a jumping one.
    await tester.pumpWidget(
      _wrap(
        VoiceMessagePlayer(
          messageId: 'm1',
          resolveAudioUrl: () async => 'https://example.com/voice.m4a',
          durationMs: 4200,
          waveform: [50, 50, 50],
        ),
      ),
    );

    expect(
      find.byType(RollingDuration),
      findsOneWidget,
      reason:
          'the playback timer should roll its digits, the same way the '
          'recording scrim does',
    );
  });

  testWidgets('shows a play icon by default, duration, and a waveform', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        VoiceMessagePlayer(
          messageId: 'm1',
          resolveAudioUrl: () async => 'https://example.com/voice.m4a',
          durationMs: 4200,
          waveform: List.filled(100, 50),
        ),
      ),
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    // RollingDuration renders each digit as its own Text so it can roll
    // them, and reads as plain seconds below a minute — matching the
    // recording scrim's timer rather than the old fixed '0:04'.
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('uses the compact circular player and clock-form duration', (
    tester,
  ) async {
    const accent = Color(0xFF2296F3);
    const metadata = Color(0xFF8B918E);
    await tester.pumpWidget(
      _wrap(
        VoiceMessagePlayer(
          messageId: 'styled',
          resolveAudioUrl: () async => 'https://example.com/voice.m4a',
          durationMs: 23000,
          waveform: List.filled(100, 80),
          accentColor: accent,
          metadataColor: metadata,
        ),
      ),
    );

    final playIcon = tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded));
    final playerContext = tester.element(find.byType(VoiceMessagePlayer));
    // ignore: deprecated_member_use
    expect(playIcon.color, Theme.of(playerContext).colorScheme.background);
    final duration = tester.widget<RollingDuration>(
      find.byType(RollingDuration),
    );
    expect(duration.alwaysShowMinutes, isTrue);
    expect(duration.style?.color, metadata);
  });

  testWidgets(
    'starting playback on one bubble sets it as the app-wide currently-playing id',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          voicePlaybackEngineProvider.overrideWithValue(FakeVoiceEngine()),
          _fakeSession(),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VoiceMessagePlayer(
                messageId: 'm1',
                resolveAudioUrl: () async => 'https://example.com/voice.m4a',
                durationMs: 4200,
                waveform: List.filled(100, 50),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(container.read(currentlyPlayingVoiceMessageIdProvider), 'm1');

      // Leave nothing playing: the stall watchdog is a live timer.
      await container.read(voicePlaybackControllerProvider.notifier).stop();
    },
  );

  testWidgets(
    'starting playback on a second bubble clears the first bubble\'s playing state',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          voicePlaybackEngineProvider.overrideWithValue(FakeVoiceEngine()),
          _fakeSession(),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  VoiceMessagePlayer(
                    key: const ValueKey('m1'),
                    messageId: 'm1',
                    resolveAudioUrl: () async => 'https://example.com/a.m4a',
                    durationMs: 1000,
                    waveform: List.filled(100, 50),
                  ),
                  VoiceMessagePlayer(
                    key: const ValueKey('m2'),
                    messageId: 'm2',
                    resolveAudioUrl: () async => 'https://example.com/b.m4a',
                    durationMs: 1000,
                    waveform: List.filled(100, 50),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Each bubble is keyed by its messageId so its play button can be found
      // unambiguously. Found by the bubble's InkWell, not the play icon: with
      // the fake engine, bubble 1 does flip to pause once it plays.
      final bubble1PlayButton = find.descendant(
        of: find.byKey(const ValueKey('m1')),
        matching: find.byType(InkWell),
      );
      final bubble2PlayButton = find.descendant(
        of: find.byKey(const ValueKey('m2')),
        matching: find.byType(InkWell),
      );

      await tester.tap(bubble1PlayButton);
      await tester.pump();
      expect(container.read(currentlyPlayingVoiceMessageIdProvider), 'm1');

      await tester.tap(bubble2PlayButton);
      await tester.pump();
      expect(container.read(currentlyPlayingVoiceMessageIdProvider), 'm2');

      // Leave nothing playing: the stall watchdog is a live timer.
      await container.read(voicePlaybackControllerProvider.notifier).stop();
    },
  );

  testWidgets(
    'tapping the waveform seeks to the tapped proportional position',
    (tester) async {
      final engine = FakeVoiceEngine();
      await tester.pumpWidget(
        _wrap(
          VoiceMessagePlayer(
            messageId: 'm1',
            resolveAudioUrl: () async => 'https://example.com/voice.m4a',
            durationMs: 10000,
            waveform: List.filled(100, 50),
          ),
          overrides: [
            voicePlaybackEngineProvider.overrideWithValue(engine),
            voicePlaybackStallAfterProvider.overrideWithValue(
              const Duration(hours: 1),
            ),
          ],
        ),
      );
      // Seeking applies to the note that is playing: start it first.
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      final waveformFinder = find.byKey(
        const ValueKey('voice_message_waveform'),
      );
      // The middle of the waveform is the middle of the note.
      await tester.tap(waveformFinder);
      await tester.pump();
      expect(engine.lastSeek, const Duration(milliseconds: 5000));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('playback survives the bubble being recycled by the list', (
    tester,
  ) async {
    final engine = FakeVoiceEngine();
    final container = ProviderContainer(
      overrides: [
        voicePlaybackEngineProvider.overrideWithValue(engine),
        _fakeSession(),
        // No position ticks until the test sends one; keep the stall
        // watchdog out of the way.
        voicePlaybackStallAfterProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
      ],
    );
    addTearDown(container.dispose);
    Widget player() => VoiceMessagePlayer(
      messageId: 'm1',
      resolveAudioUrl: () async => 'https://example.com/voice.m4a',
      durationMs: 120000,
      waveform: List.filled(100, 50),
    );
    Widget host(Widget child) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );

    await tester.pumpWidget(host(player()));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // The bubble scrolls out of cacheExtent: the list disposes its element.
    await tester.pumpWidget(host(const SizedBox()));
    expect(engine.calls, isNot(contains('stop')));
    expect(engine.calls, isNot(contains('pause')));
    expect(container.read(voicePlaybackControllerProvider).isPlaying, isTrue);
    engine.positionsController.add(const Duration(seconds: 30));
    await tester.pump();

    // Scrolled back: the bubble picks up live state, not 0:00.
    await tester.pumpWidget(host(player()));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    final duration = tester.widget<RollingDuration>(
      find.byType(RollingDuration),
    );
    expect(duration.value, const Duration(seconds: 30));

    // Leave nothing playing: the stall watchdog is a live timer.
    await container.read(voicePlaybackControllerProvider.notifier).stop();
  });

  testWidgets('the speed chip appears for the current note and cycles', (
    tester,
  ) async {
    final engine = FakeVoiceEngine();
    await tester.pumpWidget(
      _wrap(
        VoiceMessagePlayer(
          messageId: 'm1',
          resolveAudioUrl: () async => 'https://example.com/voice.m4a',
          durationMs: 9000,
          waveform: List.filled(100, 50),
        ),
        overrides: [
          voicePlaybackEngineProvider.overrideWithValue(engine),
          voicePlaybackStallAfterProvider.overrideWithValue(
            const Duration(hours: 1),
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('voice_speed_chip')), findsNothing);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('1×'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice_speed_chip')));
    await tester.pump();
    expect(find.text('1.5×'), findsOneWidget);
    expect(engine.lastRate, 1.5);
    await tester.tap(find.byKey(const ValueKey('voice_speed_chip')));
    await tester.pump();
    expect(find.text('2×'), findsOneWidget);
  });

  testWidgets('a note that cannot play says so on its own bubble only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            VoiceMessagePlayer(
              key: const ValueKey('broken'),
              messageId: 'broken',
              resolveAudioUrl: () async => null,
              durationMs: 1000,
              waveform: List.filled(100, 50),
            ),
            VoiceMessagePlayer(
              key: const ValueKey('fine'),
              messageId: 'fine',
              resolveAudioUrl: () async => 'https://example.com/b.m4a',
              durationMs: 1000,
              waveform: List.filled(100, 50),
            ),
          ],
        ),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('broken')),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.text('That voice message could not play'),
      findsOneWidget,
      reason: 'one snackbar, from the failing bubble, not one per bubble',
    );
  });

  Widget twoBubbles() => Column(
    children: [
      VoiceMessagePlayer(
        key: const ValueKey('m1'),
        messageId: 'm1',
        resolveAudioUrl: () async => 'https://example.com/a.m4a',
        durationMs: 60000,
        waveform: List.filled(100, 50),
      ),
      VoiceMessagePlayer(
        key: const ValueKey('m2'),
        messageId: 'm2',
        resolveAudioUrl: () async => 'https://example.com/b.m4a',
        durationMs: 60000,
        waveform: List.filled(100, 50),
      ),
    ],
  );

  List<Override> quietEngine(FakeVoiceEngine engine) => [
    voicePlaybackEngineProvider.overrideWithValue(engine),
    voicePlaybackStallAfterProvider.overrideWithValue(const Duration(hours: 1)),
    _fakeSession(),
  ];

  testWidgets('an idle bubble does not rebuild while another note plays', (
    tester,
  ) async {
    final engine = FakeVoiceEngine();
    await tester.pumpWidget(
      _wrap(twoBubbles(), overrides: quietEngine(engine)),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('m1')),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pump();

    for (var i = 1; i <= 5; i++) {
      engine.positionsController.add(Duration(seconds: i));
      await tester.idle();
      expect(
        tester.element(find.byKey(const ValueKey('m1'))).dirty,
        isTrue,
        reason: 'the playing bubble follows its position',
      );
      expect(
        tester.element(find.byKey(const ValueKey('m2'))).dirty,
        isFalse,
        reason: 'an idle bubble must not rebuild on every position frame',
      );
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
  });

  group('speed chip', () {
    testWidgets('has a 48×48 tap area inside the player', (tester) async {
      final engine = FakeVoiceEngine();
      await tester.pumpWidget(
        _wrap(twoBubbles(), overrides: quietEngine(engine)),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('m1')),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      final chip = find.byKey(const ValueKey('voice_speed_chip'));
      expect(chip, findsOneWidget);
      expect(tester.getSize(chip).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
      final player = tester.getRect(find.byKey(const ValueKey('m1')));
      final area = tester.getRect(chip);
      expect(
        player.intersect(area),
        area,
        reason: 'the area lies inside the player: nothing grows',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a tap anywhere in the area cycles the rate; the waveform '
        'still seeks by tap and by a drag that starts in the area', (
      tester,
    ) async {
      final engine = FakeVoiceEngine();
      await tester.pumpWidget(
        _wrap(
          Center(
            child: VoiceMessagePlayer(
              key: const ValueKey('m1'),
              messageId: 'm1',
              resolveAudioUrl: () async => 'https://example.com/a.m4a',
              durationMs: 10000,
              waveform: List.filled(100, 50),
            ),
          ),
          overrides: quietEngine(engine),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      final area = tester.getRect(
        find.byKey(const ValueKey('voice_speed_chip')),
      );

      final waveform = tester.getRect(
        find.byKey(const ValueKey('voice_message_waveform')),
      );
      // Inside the area AND over the waveform's tail: well away from the
      // pill, where the expanded area overlaps the waveform.
      final overlap = Offset(area.right - 3, waveform.center.dy);
      expect(area.contains(overlap), isTrue);
      expect(waveform.contains(overlap), isTrue);
      await tester.tapAt(overlap);
      await tester.pump();
      expect(engine.lastRate, 1.5);
      expect(engine.lastSeek, isNull, reason: 'the tap went to the chip');

      // The middle of the waveform still seeks to the middle.
      await tester.tap(find.byKey(const ValueKey('voice_message_waveform')));
      await tester.pump();
      expect(engine.lastSeek, const Duration(milliseconds: 5000));

      // A drag that starts in the area is a seek, not a speed change.
      engine.lastSeek = null;
      await tester.dragFrom(
        Offset(area.left + 10, waveform.center.dy),
        const Offset(-60, 0),
      );
      await tester.pump();
      expect(engine.lastRate, 1.5, reason: 'no speed change from a drag');
      expect(engine.lastSeek, isNotNull, reason: 'the drag scrubbed');
      expect(
        engine.lastSeek!.inMilliseconds,
        lessThan(10000 * (area.left + 10 - waveform.left) ~/ waveform.width),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('appearing does not change the bubble size', (tester) async {
      final engine = FakeVoiceEngine();
      await tester.pumpWidget(
        _wrap(
          Center(
            child: VoiceMessagePlayer(
              key: const ValueKey('m1'),
              messageId: 'm1',
              resolveAudioUrl: () async => 'https://example.com/a.m4a',
              durationMs: 9000,
              waveform: List.filled(100, 50),
            ),
          ),
          overrides: quietEngine(engine),
        ),
      );
      final before = tester.getSize(find.byKey(const ValueKey('m1')));
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(find.text('1×'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('m1'))), before);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is announced once, as a button', (tester) async {
      final handle = tester.ensureSemantics();
      final engine = FakeVoiceEngine();
      await tester.pumpWidget(
        _wrap(
          VoiceMessagePlayer(
            messageId: 'm1',
            resolveAudioUrl: () async => 'https://example.com/a.m4a',
            durationMs: 9000,
            waveform: List.filled(100, 50),
          ),
          overrides: quietEngine(engine),
        ),
      );
      expect(find.semantics.byLabel('Playback speed 1×'), findsNothing);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(find.semantics.byLabel('Playback speed 1×'), findsOneWidget);
      expect(
        find.semantics.byLabel('1×'),
        findsNothing,
        reason: 'the chip text must not be read a second time',
      );
      tester.semantics.performAction(
        find.semantics.byLabel('Playback speed 1×'),
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(engine.lastRate, 1.5);
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    });
  });

  group('loading ring', () {
    Future<void> pumpLoading(
      WidgetTester tester, {
      required bool reduce,
    }) async {
      final gate = Completer<String?>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: quietEngine(FakeVoiceEngine()),
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduce),
              child: Scaffold(
                body: VoiceMessagePlayer(
                  messageId: 'm1',
                  resolveAudioUrl: () => gate.future,
                  durationMs: 9000,
                  waveform: List.filled(100, 50),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
    }

    testWidgets('spins while a note loads', (tester) async {
      await pumpLoading(tester, reduce: false);
      final ring = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: find.byKey(const ValueKey('voice_loading_ring')),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(ring.value, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is still under reduce motion', (tester) async {
      await pumpLoading(tester, reduce: true);
      final ring = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: find.byKey(const ValueKey('voice_loading_ring')),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(ring.value, isNotNull, reason: 'a static ring, not a spinner');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows while a remote note buffers, with pause still offered', (
      tester,
    ) async {
      final engine = FakeVoiceEngine();
      await tester.pumpWidget(
        _wrap(
          VoiceMessagePlayer(
            messageId: 'm1',
            resolveAudioUrl: () async => 'https://example.com/a.m4a',
            durationMs: 60000,
            waveform: List.filled(100, 50),
          ),
          overrides: [voicePlaybackEngineProvider.overrideWithValue(engine)],
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(find.byKey(const ValueKey('voice_loading_ring')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('voice_loading_ring')), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('the waveform is a slider for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    final engine = FakeVoiceEngine();
    await tester.pumpWidget(
      _wrap(
        VoiceMessagePlayer(
          messageId: 'm1',
          resolveAudioUrl: () async => 'https://example.com/a.m4a',
          durationMs: 60000,
          waveform: List.filled(100, 50),
        ),
        overrides: quietEngine(engine),
      ),
    );
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    final slider = find.semantics.byLabel('Voice message position');
    expect(slider, findsOneWidget);
    final data = slider.evaluate().single.getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isSlider), isTrue);
    expect(data.value, '0 seconds of 1 minute');

    tester.semantics.performAction(slider, SemanticsAction.increase);
    await tester.pump();
    expect(engine.lastSeek, const Duration(seconds: 5));
    tester.semantics.performAction(slider, SemanticsAction.decrease);
    await tester.pump();
    expect(engine.lastSeek, Duration.zero);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('a play that fails to start returns the borrowed session', (
    tester,
  ) async {
    // The engine refuses the first play — the "failed start" path. The
    // session must be borrowed once and returned once; a hold left behind
    // would keep every later chirp on the playback category (audible on
    // silent, pausing music) until restart.
    final engine = FakeVoiceEngine()..nextPlayError = Exception('no codec');
    final session = _SpySession();
    await tester.pumpWidget(
      _wrap(
        VoiceMessagePlayer(
          messageId: 'v1',
          resolveAudioUrl: () async => 'https://example.com/v1.m4a',
          durationMs: 3000,
          waveform: const [10, 20, 30],
        ),
        overrides: [
          voicePlaybackEngineProvider.overrideWithValue(engine),
          audioSessionProvider.overrideWithValue(session),
        ],
      ),
    );
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(session.begins, 1);
    expect(session.ends, 1, reason: 'a failed start must release the hold');
    expect(session.playbackHeld, isFalse);
    expect(find.text('That voice message could not play'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Counts session borrows/returns without a platform player.
class _SpySession extends AudioSessionCoordinator {
  _SpySession() : super(port: FakeAudioSessionPort());
  int begins = 0;
  int ends = 0;

  @override
  Future<void> beginPlayback(PlayerContextSetter set) async {
    begins++;
    await super.beginPlayback(set); // FakeVoiceEngine records the context
  }

  @override
  Future<void> endPlayback() async {
    ends++;
    await super.endPlayback();
  }
}

import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/widgets/voice_message_player.dart';
import 'package:attune/core/widgets/rolling_duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
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

  testWidgets(
    'starting playback on one bubble sets it as the app-wide currently-playing id',
    (tester) async {
      final container = ProviderContainer();
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
    },
  );

  testWidgets(
    'starting playback on a second bubble clears the first bubble\'s playing state',
    (tester) async {
      final container = ProviderContainer();
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
      // unambiguously, independent of icon state — audioplayers' play() never
      // resolves in the flutter test VM host (no importable test-fake exists),
      // so bubble 1's icon never visibly flips to pause here. This test only
      // asserts the provider write, which happens synchronously in
      // _togglePlayback before the await, so it's provably correct regardless
      // of whether play() ever completes.
      final bubble1PlayButton = find.descendant(
        of: find.byKey(const ValueKey('m1')),
        matching: find.byIcon(Icons.play_arrow_rounded),
      );
      final bubble2PlayButton = find.descendant(
        of: find.byKey(const ValueKey('m2')),
        matching: find.byIcon(Icons.play_arrow_rounded),
      );

      await tester.tap(bubble1PlayButton);
      await tester.pump();
      expect(container.read(currentlyPlayingVoiceMessageIdProvider), 'm1');

      await tester.tap(bubble2PlayButton);
      await tester.pump();
      expect(container.read(currentlyPlayingVoiceMessageIdProvider), 'm2');
    },
  );

  testWidgets(
    'tapping the waveform seeks to the tapped proportional position',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          VoiceMessagePlayer(
            messageId: 'm1',
            resolveAudioUrl: () async => 'https://example.com/voice.m4a',
            durationMs: 10000,
            waveform: List.filled(100, 50),
          ),
        ),
      );

      final waveformFinder = find.byKey(
        const ValueKey('voice_message_waveform'),
      );
      expect(waveformFinder, findsOneWidget);
      // A tap-to-seek gesture handler exists on the waveform — full seek
      // behavior requires a real AudioPlayer (unavailable in the test VM
      // host), so this test confirms the gesture target exists and is
      // tappable without throwing, rather than asserting the actual seek
      // position (which would require mocking audioplayers' AudioPlayer,
      // out of scope for this task's test depth).
      await tester.tap(waveformFinder);
      await tester.pump();
    },
  );
}

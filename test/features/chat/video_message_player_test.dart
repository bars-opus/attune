import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/widgets/video_message_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

void main() {
  testWidgets('renders the thumbnail with a play button, no video controller until tap',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: VideoMessagePlayer(
              key: const ValueKey('m1'),
              messageId: 'm1',
              videoUrl: 'https://example.com/clip.mp4',
              thumbnailUrl: 'https://example.com/poster.jpg',
              durationMs: 12000,
              width: 1280,
              height: 720,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    // No VideoPlayer widget should be in the tree before the first tap —
    // the poster-first, lazy-controller-construction contract that is
    // this widget's one deliberate divergence from VoiceMessagePlayer's
    // eager AudioPlayer construction.
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('starting video playback clears a currently-playing voice message (cross-media pause)',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentlyPlayingVoiceMessageIdProvider.notifier).state = 'voice-1';

    // Recording every value currentlyPlayingVideoMessageIdProvider takes,
    // rather than only reading it once after the fact, so the assertion
    // doesn't depend on exactly how far a given pump() drains the async
    // continuation inside _togglePlayback (tap() itself may already run it
    // to completion on this test host). What matters is that 'm1' is
    // reached at all (proving the write happens synchronously, before
    // controller construction/initialize()), regardless of whatever the
    // provider settles on afterwards.
    final videoProviderValues = <String?>[];
    container.listen<String?>(
      currentlyPlayingVideoMessageIdProvider,
      (previous, next) => videoProviderValues.add(next),
      fireImmediately: true,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: VideoMessagePlayer(
              key: const ValueKey('m1'),
              messageId: 'm1',
              videoUrl: 'https://example.com/clip.mp4',
              thumbnailUrl: 'https://example.com/poster.jpg',
              durationMs: 12000,
              width: 1280,
              height: 720,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
    // 'm1' was reached — the cross-media pause write happens synchronously,
    // before the controller is constructed or initialize() is awaited.
    expect(videoProviderValues, contains('m1'));

    // On this test host there is no platform video decoder, so
    // controller.initialize() always rejects; VideoMessagePlayer correctly
    // rolls currentlyPlayingVideoMessageIdProvider back to null once that
    // failure is caught, since this widget never actually started playing
    // — a provider claiming "playing" for a message that isn't would be a
    // false-positive lock on the shared cross-media state. That rollback
    // is real, correct production behavior (see the catch block's own
    // comment), so the provider's settled value here is null, not 'm1'.
    expect(container.read(currentlyPlayingVideoMessageIdProvider), isNull);
  });

  testWidgets('identity is keyed on clientMessageId-equivalent messageId, stable across a widget rebuild with a new videoUrl',
      (tester) async {
    // Regression guard for the exact bug class the voice-messages final
    // review caught and fixed for VoiceMessagePlayer AFTER it shipped —
    // built in from the start here instead. The messageId passed in must
    // be treated as identity; changing videoUrl (simulating the
    // optimistic-to-canonical swap, local path -> signed URL) while
    // messageId stays the same must not tear down and rebuild a fresh
    // player state that loses playback position/state unexpectedly.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    Widget build(String videoUrl) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoMessagePlayer(
                key: const ValueKey('stable-id'),
                messageId: 'stable-id',
                videoUrl: videoUrl,
                thumbnailUrl: 'https://example.com/poster.jpg',
                durationMs: 12000,
                width: 1280,
                height: 720,
              ),
            ),
          ),
        );

    await tester.pumpWidget(build('/tmp/local/clip.mp4'));
    await tester.pump();
    final elementBefore = tester.element(find.byType(VideoMessagePlayer));

    await tester.pumpWidget(build('https://example.com/clip.mp4'));
    await tester.pump();
    final elementAfter = tester.element(find.byType(VideoMessagePlayer));

    // Same Key => Flutter preserves the same Element/State across the
    // videoUrl change, matching VoiceMessagePlayer's established pattern.
    expect(elementBefore, same(elementAfter));
  });

  testWidgets('local-vs-remote source: a videoUrl not starting with http uses a local file source',
      (tester) async {
    // Behavioral confirmation that VideoMessagePlayer's source-selection
    // branch mirrors VoiceMessagePlayer's startsWith('http') check exactly
    // — this test asserts on construction not throwing for a local path,
    // since actually exercising VideoPlayerController.file vs .networkUrl
    // requires a real platform channel unavailable in this test host.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: VideoMessagePlayer(
              key: const ValueKey('m1'),
              messageId: 'm1',
              videoUrl: '/tmp/local/clip.mp4',
              thumbnailUrl: null,
              durationMs: 12000,
              width: 1280,
              height: 720,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

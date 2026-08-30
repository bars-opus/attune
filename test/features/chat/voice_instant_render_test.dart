import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a voice bubble renders its waveform without waiting on the network', () {
    // durationMs and waveform both come straight off the message row, so
    // the bubble has everything it needs to draw immediately. It was
    // nonetheless wrapped in ResolvedMediaUrl, whose shimmer blocked the
    // whole player behind a round-trip to sign a URL — a URL only PLAYBACK
    // needs.
    //
    // On a cold open (or after the 10-minute signed-URL TTL lapses) every
    // voice note in the conversation shimmered before showing anything.
    final bubble =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    final audioBranch = bubble.substring(
      bubble.indexOf('if (message.hasAudio) {'),
      bubble.indexOf('if (message.isStreak) {'),
    );

    // Constructor calls, not mentions: the branch explains in a comment
    // why ResolvedMediaUrl is gone, and matching prose would fail against
    // correct code.
    expect(
      audioBranch.contains('ResolvedMediaUrl('),
      isFalse,
      reason:
          'the waveform is local data; gating it on a signed URL is what '
          'produces the shimmer on every cold open',
    );
    expect(
      audioBranch.contains('Shimmer('),
      isFalse,
      reason: 'there is nothing to wait for before drawing the waveform',
    );
  });

  test('the player resolves its URL lazily, on play', () {
    final player =
        File(
          'lib/features/chat/presentation/widgets/voice_message_player.dart',
        ).readAsStringSync();

    expect(
      player,
      contains('resolveAudioUrl'),
      reason:
          'playback still needs a signed URL — it just must not block the '
          'first paint',
    );
  });
}

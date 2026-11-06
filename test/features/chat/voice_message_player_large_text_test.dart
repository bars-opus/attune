// Spec 1 W10a (batch 2 fix round 1, M-4): the voice note's time only takes
// a flex share once text is scaled up. At the normal size the Spacer takes
// all the free space, so the speed pill sits flush at the row's end, as it
// always has.
import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:attune/core/widgets/rolling_duration.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:attune/features/chat/presentation/widgets/voice_message_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_voice_engine.dart';

Future<void> _pump(WidgetTester t, double scale) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        voicePlaybackEngineProvider.overrideWithValue(FakeVoiceEngine()),
        audioSessionProvider.overrideWith(
          (ref) => AudioSessionCoordinator(port: FakeAudioSessionPort()),
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Center(
              child: VoiceMessagePlayer(
                messageId: 'm1',
                resolveAudioUrl: () async => 'https://example.com/voice.m4a',
                durationMs: 4200,
                waveform: List.filled(100, 50),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _timeRow() =>
    find
        .ancestor(of: find.byType(RollingDuration), matching: find.byType(Row))
        .first;

void main() {
  testWidgets('at 1.0 the speed pill sits flush at the end of the time row', (
    t,
  ) async {
    await _pump(t, 1.0);
    final row = t.getRect(_timeRow());
    final pill = t.getRect(
      find.descendant(of: _timeRow(), matching: find.byType(Visibility)),
    );
    final time = t.getRect(find.byType(RollingDuration));
    expect(pill.right, row.right);
    expect(time.left, row.left);
  });

  testWidgets('at 2.0 the time fits beside the pill', (t) async {
    await _pump(t, 2.0);
    expect(t.takeException(), isNull);
  });
}

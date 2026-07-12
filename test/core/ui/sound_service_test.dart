import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:audioplayers/audioplayers.dart'; // ensure resolves
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FakeSoundService records played sounds and preloads', () async {
    final s = FakeSoundService();
    await s.preload();
    s.play(ChatSound.send);
    s.play(ChatSound.receive);
    s.play(ChatSound.send);
    expect(s.preloadCount, 1);
    expect(s.played, [ChatSound.send, ChatSound.receive, ChatSound.send]);
  });

  test('AudioPlayerSoundService constructs and play() never throws '
      'even before preload', () {
    final s = AudioPlayerSoundService();
    // Must not throw synchronously in a headless test (no audio device).
    expect(() => s.play(ChatSound.send), returnsNormally);
    s.dispose();
  });

  test('ChatSound back-compat aliases map onto AppSound values', () {
    expect(ChatSound.send, AppSound.chatSend);
    expect(ChatSound.receive, AppSound.chatReceive);
  });

  test('FakeSoundService records the universal game sounds', () {
    final s = FakeSoundService();
    s.play(AppSound.gameTap);
    s.play(AppSound.gameCardFlip);
    s.play(AppSound.gameMatch);
    s.play(AppSound.gameReveal);
    s.play(AppSound.gameComplete);
    expect(s.played, [
      AppSound.gameTap,
      AppSound.gameCardFlip,
      AppSound.gameMatch,
      AppSound.gameReveal,
      AppSound.gameComplete,
    ]);
  });
}

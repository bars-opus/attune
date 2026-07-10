import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FakeSoundService records played sounds and preloads', () async {
    final s = FakeSoundService();
    await s.preload();
    s.play(ChatSound.send);
    s.play(ChatSound.receive);
    s.play(ChatSound.send);
    expect(s.preloadCount, 1);
    expect(s.played, [ChatSound.send, ChatSound.receive, ChatSound.send]);
  });
}

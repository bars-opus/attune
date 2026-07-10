import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chat UI sounds. Content-blind — these are event sounds, not tied to
/// message content.
enum ChatSound { send, receive }

/// Injectable one-shot sound player. Universal (any feature can use it); chat
/// is the first consumer. Playback failures are silent no-ops and never block
/// the caller.
abstract class SoundService {
  /// Preloads the clips so the first play has no cold-start latency.
  Future<void> preload();

  /// Plays [sound] if audio is available. Never throws.
  void play(ChatSound sound);
}

/// Test double: records calls, plays nothing.
class FakeSoundService implements SoundService {
  final List<ChatSound> played = [];
  int preloadCount = 0;

  @override
  Future<void> preload() async => preloadCount++;

  @override
  void play(ChatSound sound) => played.add(sound);
}

/// Overridden in app startup / by the real impl (Task 3). Throwing default so a
/// missing override is caught in tests rather than silently no-op'ing.
final soundServiceProvider = Provider<SoundService>((ref) {
  throw UnimplementedError('soundServiceProvider must be overridden');
});

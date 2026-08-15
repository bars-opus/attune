import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The message id of the voice message currently playing, if any — app-wide
/// (not scoped per conversation) so at most one voice message plays at a
/// time across the whole app. See design spec's "Playback" section: leaving
/// the chat screen while a voice message is playing stops it (no
/// background/lock-screen playback), rather than this provider itself
/// enforcing that — the widget that owns the actual AudioPlayer instance is
/// responsible for stopping playback in its own dispose(), which happens
/// naturally when the message list holding that widget leaves the tree.
final currentlyPlayingVoiceMessageIdProvider = StateProvider<String?>(
  (ref) => null,
);

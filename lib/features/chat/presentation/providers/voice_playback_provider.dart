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

/// The message id of the video message currently playing, if any —
/// app-wide (not scoped per conversation), same shape as
/// currentlyPlayingVoiceMessageIdProvider. Deliberately in the same file so
/// VideoMessagePlayer/VoiceMessagePlayer can each cross-pause the other:
/// starting a video should stop any currently-playing voice message, and
/// vice versa, since two simultaneous audio streams is the actual
/// user-facing failure mode both providers exist to prevent — not just
/// "two of the same media type."
final currentlyPlayingVideoMessageIdProvider = StateProvider<String?>(
  (ref) => null,
);

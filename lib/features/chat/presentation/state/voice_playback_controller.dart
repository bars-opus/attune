import 'dart:async';

import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What voice playback needs from an audio backend. One instance app-wide.
abstract class VoicePlaybackEngine {
  Stream<Duration> get positions;
  Stream<void> get completions;

  /// True while audio is actually coming out; false after pause, stop,
  /// completion, and whenever the OS takes the output away (call, Siri).
  Stream<bool> get playing;

  /// This player's audio session. The controller never picks a context
  /// itself: it hands this method to AudioSessionCoordinator.beginPlayback
  /// (chat review #40).
  Future<void> setAudioContext(AudioContext context);

  Future<void> play(
    String source, {
    required bool isLocalFile,
    required double rate,
  });
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> dispose();
}

/// audioplayers-backed engine.
class AudioPlayersVoiceEngine implements VoicePlaybackEngine {
  AudioPlayersVoiceEngine({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positions => _player.onPositionChanged;
  @override
  Stream<void> get completions => _player.onPlayerComplete;
  @override
  Stream<bool> get playing =>
      _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  @override
  Future<void> setAudioContext(AudioContext context) =>
      _player.setAudioContext(context);

  @override
  Future<void> play(
    String source, {
    required bool isLocalFile,
    required double rate,
  }) async {
    await _player.setPlaybackRate(rate);
    // UrlSource only works for real HTTP(S) URLs; a just-recorded or cached
    // note is a local file.
    await _player.play(
      isLocalFile ? DeviceFileSource(source) : UrlSource(source),
    );
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> resume() => _player.resume();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setRate(double rate) => _player.setPlaybackRate(rate);
  @override
  Future<void> dispose() => _player.dispose();
}

typedef VoiceSourceResolver = Future<String?> Function();

/// Signs a storage key for playback; null when it cannot be signed.
typedef VoiceMediaSigner = Future<String?> Function(String mediaKey);

@immutable
class VoicePlaybackState {
  const VoicePlaybackState({
    this.messageId,
    this.isPlaying = false,
    this.isLoading = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.rate = 1.0,
    this.failureCount = 0,
    this.failedMessageId,
  });

  static const idle = VoicePlaybackState();
  static const Object _unset = Object();

  /// The message the engine currently holds (playing, loading or paused).
  final String? messageId;
  final bool isPlaying;

  /// Resolving / downloading before the first audio frame.
  final bool isLoading;

  /// Playing, but a remote source has not advanced for a while (a slow
  /// network): the bubble shows its loading ring while [isPlaying] stays
  /// true, so the note carries on by itself when the data arrives.
  final bool isBuffering;
  final Duration position;
  final double rate;

  /// Bumped on every playback failure; [failedMessageId] says whose.
  final int failureCount;
  final String? failedMessageId;

  bool isCurrent(String id) => messageId == id;
  Duration positionFor(String id) => messageId == id ? position : Duration.zero;

  VoicePlaybackState copyWith({
    Object? messageId = _unset,
    bool? isPlaying,
    bool? isLoading,
    bool? isBuffering,
    Duration? position,
    double? rate,
    int? failureCount,
    Object? failedMessageId = _unset,
  }) {
    return VoicePlaybackState(
      messageId:
          identical(messageId, _unset) ? this.messageId : messageId as String?,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      rate: rate ?? this.rate,
      failureCount: failureCount ?? this.failureCount,
      failedMessageId:
          identical(failedMessageId, _unset)
              ? this.failedMessageId
              : failedMessageId as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoicePlaybackState &&
      other.messageId == messageId &&
      other.isPlaying == isPlaying &&
      other.isLoading == isLoading &&
      other.isBuffering == isBuffering &&
      other.position == position &&
      other.rate == rate &&
      other.failureCount == failureCount &&
      other.failedMessageId == failedMessageId;

  @override
  int get hashCode => Object.hash(
    messageId,
    isPlaying,
    isLoading,
    isBuffering,
    position,
    rate,
    failureCount,
    failedMessageId,
  );
}

/// Owns the one voice [VoicePlaybackEngine] for the app (chat review #21):
/// the bubble used to own the AudioPlayer, so scrolling it past the list's
/// cacheExtent disposed the player mid-sentence. Bubbles are views of this
/// state; one message plays at a time; leaving the chat screen calls
/// [stop] (spec: no background playback). Also the only place the
/// voice-note audio session is borrowed and returned (chat review #40): the
/// AudioSessionCoordinator restores the chirp context when the last hold
/// ends.
class VoicePlaybackController extends StateNotifier<VoicePlaybackState>
    with WidgetsBindingObserver {
  VoicePlaybackController({
    required VoicePlaybackEngine engine,
    required void Function(String? messageId) publishCurrent,
    required VoidCallback stopOtherMedia,
    required VoiceMediaSigner signMediaUrl,
    required AudioSessionCoordinator session,
    ChatMediaCache? mediaCache,
    VoiceMediaSigner? refreshMediaUrl,
    Duration stallAfter = const Duration(milliseconds: 1500),
    Duration bufferingGiveUpAfter = const Duration(seconds: 8),
  }) : _engine = engine,
       _publishCurrent = publishCurrent,
       _stopOtherMedia = stopOtherMedia,
       _signMediaUrl = signMediaUrl,
       _session = session,
       _mediaCache = mediaCache,
       _refreshMediaUrl = refreshMediaUrl,
       _stallAfter = stallAfter,
       _bufferingGiveUpAfter = bufferingGiveUpAfter,
       super(VoicePlaybackState.idle) {
    _subscriptions.addAll([
      _engine.positions.listen(_onPosition),
      _engine.completions.listen((_) => _onComplete()),
      _engine.playing.listen(_onEnginePlaying),
    ]);
    WidgetsBinding.instance.addObserver(this);
  }

  static const rates = [1.0, 1.5, 2.0];

  final VoicePlaybackEngine _engine;
  final void Function(String?) _publishCurrent;
  final VoidCallback _stopOtherMedia;
  final VoiceMediaSigner _signMediaUrl;
  final AudioSessionCoordinator _session;

  /// Whether this controller currently holds the audio session. Paired
  /// strictly: one begin per start/resume, one end per pause/complete/
  /// playing-false/stop/fail/dispose — a leaked hold keeps every later chirp
  /// on the playback category (audible on silent, pausing music) until
  /// restart. The latch also absorbs [_playSource]'s second run (the cached
  /// file refused, the URL streamed instead) and a switch between notes.
  bool _holdsSession = false;

  /// Voice bytes on disk (#28); null: always stream (bare test hosts).
  final ChatMediaCache? _mediaCache;

  /// A FORCED re-sign, for a download whose token expired mid-flight.
  final VoiceMediaSigner? _refreshMediaUrl;
  final Duration _stallAfter;
  final Duration _bufferingGiveUpAfter;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  int _generation = 0;

  /// The conversation the current note was started in (relationship id);
  /// null when the caller did not say. See [stop] / [stopIfOwnedByAnother].
  String? _ownerId;

  /// The current note's server row id, when the caller knows it: a realtime
  /// hard delete names only that id (see [stopMessages]).
  String? _serverMessageId;

  /// The [_generation] whose source has advanced at least once. A
  /// completion is only this source's own once it has played: one arriving
  /// before that belongs to the previous source (it raced the switch) and
  /// must not reset the new note.
  int _advancedGeneration = -1;

  /// Whether the current source is a file on this device (it cannot be
  /// buffering, so no advance means interrupted).
  bool _isLocalSource = false;

  /// One periodic check while playing, against [_lastAdvanceAt] — not a
  /// timer recreated on every position frame.
  Timer? _watchdog;
  DateTime _lastAdvanceAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// A fresh signed URL for [mediaKey], or null when it cannot be signed
  /// (the caller falls back to a stored URL). Signed through
  /// [signedMediaUrlProvider] kept LISTENED for the read: an unlistened
  /// `.future` read disposes the autoDispose member before its first retry,
  /// so play used to get exactly one sign attempt.
  Future<String?> signedUrlFor(String mediaKey) => _signMediaUrl(mediaKey);

  /// Play, pause or resume [messageId]. [resolve] yields a local file path
  /// or an http(s) URL (null: nothing playable). [ownerId] is the
  /// conversation the note belongs to, so leaving ANOTHER chat does not
  /// stop it; [serverMessageId] is its server row id, so a delete that
  /// names only that id still stops it. With [mediaKey] (the storage key)
  /// the bytes go through [ChatMediaCache]: see [_resolveSource].
  Future<void> toggle(
    String messageId,
    VoiceSourceResolver resolve, {
    String? ownerId,
    String? serverMessageId,
    String? mediaKey,
  }) async {
    if (state.messageId == messageId) {
      // A second tap on a note still fetching stops it (M2): pause() turns
      // a loading note into a cancel, as WhatsApp does.
      if (state.isLoading || state.isPlaying) {
        await pause();
        return;
      }
      // Paused (by the person, a call, or backgrounding): pick up where it
      // stopped. (A FINISHED note is not held — see _onComplete — so this
      // never resumes a source the plugin already released.)
      _ownerId = ownerId ?? _ownerId;
      _serverMessageId = serverMessageId ?? _serverMessageId;
      _stopOtherMedia();
      _publishCurrent(messageId);
      state = state.copyWith(isPlaying: true, isBuffering: false);
      _startWatchdog();
      try {
        await _acquireSession();
        // The borrow is a platform round trip (iOS setCategory can block
        // while it interrupts other audio): a pause or stop that landed
        // meanwhile wins, and has already returned the session.
        if (!mounted || state.messageId != messageId || !state.isPlaying) {
          return;
        }
        await _engine.resume();
      } catch (error, stack) {
        if (!mounted) return;
        if (state.messageId == messageId) {
          _fail(messageId, error, stack);
          return;
        }
        // Another note took over while this borrow was in flight: its own
        // borrow was a no-op (the latch was held), and the failure just
        // dropped the latch. Leave that note's state alone and borrow for
        // it now, so it still holds the session.
        ChatLog.diagnostic('voice resume borrow failed (superseded)', error);
        if (state.messageId != null && !_holdsSession) {
          unawaited(
            _acquireSession().catchError(
              (Object error) =>
                  ChatLog.diagnostic('voice re-borrow failed', error),
            ),
          );
        }
      }
      return;
    }
    await _startFresh(messageId, resolve, ownerId, serverMessageId, mediaKey);
  }

  Future<void> _startFresh(
    String messageId,
    VoiceSourceResolver resolve,
    String? ownerId,
    String? serverMessageId,
    String? mediaKey,
  ) async {
    final generation = ++_generation;
    _stopWatchdog();
    if (state.messageId != null) {
      try {
        await _engine.stop();
      } catch (error) {
        ChatLog.diagnostic('voice stop before switch failed', error);
      }
      // Superseded while the platform stopped (another tap, or the chat
      // was left): writing the loading state now would strand it.
      if (generation != _generation) return;
    }
    _ownerId = ownerId;
    _serverMessageId = serverMessageId;
    state = VoicePlaybackState(
      messageId: messageId,
      isLoading: true,
      rate: state.rate,
      failureCount: state.failureCount,
    );
    _stopOtherMedia();
    _publishCurrent(messageId);

    ({String? source, bool cached}) resolved;
    try {
      resolved = await _resolveSource(
        resolve,
        mediaKey: mediaKey,
        ownerId: ownerId,
        messageIds: {messageId, if (serverMessageId != null) serverMessageId},
      );
    } catch (error, stack) {
      if (generation == _generation) _fail(messageId, error, stack);
      return;
    }
    if (generation != _generation) return; // superseded or cancelled
    final source = resolved.source;
    if (source == null) {
      _fail(messageId, null, null);
      return;
    }
    try {
      await _playSource(source, generation);
    } catch (error, stack) {
      if (generation != _generation) return;
      // A cached file that will not play (#28): dropped so the next play
      // downloads a good copy, and this play streams instead, once.
      final instead =
          resolved.cached && mediaKey != null
              ? await _uncachedSource(mediaKey, resolve)
              : null;
      if (generation != _generation) return;
      if (instead == null) {
        _fail(messageId, error, stack);
        return;
      }
      try {
        await _playSource(instead, generation);
      } catch (error, stack) {
        if (generation == _generation) _fail(messageId, error, stack);
        return;
      }
    }
    if (generation != _generation) {
      // Cancelled while play() was in flight (backgrounded, a video, the
      // chat left): the platform may have started anyway. A newer tap
      // replaces the source itself; with nothing current, silence it.
      if (state.messageId == null) unawaited(_stopEngineQuietly());
      return;
    }
    state = state.copyWith(
      isLoading: false,
      isPlaying: true,
      position: Duration.zero,
    );
    _startWatchdog();
  }

  Future<void> _playSource(String source, int generation) async {
    _isLocalSource = !source.startsWith('http');
    // A voice note the person tapped plays through the silent switch, as in
    // every messaging app: borrowed here, returned at every stop.
    await _acquireSession();
    // Cancelled during the borrow (a second tap, backgrounding, the chat
    // left): the cancel already returned the session; playing now would be
    // an audible blip. [_startFresh] sees the same stale generation.
    if (generation != _generation) return;
    await _engine.play(source, isLocalFile: _isLocalSource, rate: state.rate);
  }

  Future<void> _acquireSession() async {
    if (_holdsSession) return;
    _holdsSession = true;
    try {
      await _session.beginPlayback(_engine.setAudioContext);
    } catch (error) {
      _holdsSession = false; // the coordinator already dropped its count
      rethrow;
    }
  }

  /// Best effort and never throws: a release that fails is logged, and the
  /// next chirp's beforeChirp re-applies ambient on iOS anyway.
  void _releaseSession() {
    if (!_holdsSession) return;
    _holdsSession = false;
    unawaited(
      _session.endPlayback().catchError(
        (Object error) =>
            ChatLog.diagnostic('audio session release failed', error),
      ),
    );
  }

  /// Where the note plays from (chat review #28: a replay re-downloaded it
  /// and nothing played offline), and whether that is a cached file:
  /// 1. bytes already in [ChatMediaCache]: a file, no signing, no network;
  /// 2. otherwise [resolve] (a local recording on this device, else a
  ///    signed URL) — a URL is downloaded into the cache once and the file
  ///    played, recorded under [ownerId] and [messageIds] so deleting the
  ///    message or purging the relationship removes it;
  /// 3. a download that fails, stalls (ChatMediaFileService bounds the
  ///    silence) or takes longer than [_bufferingGiveUpAfter] streams the
  ///    URL, as before the cache.
  /// Still inside [_startFresh]'s generation: a tap elsewhere while it
  /// downloads supersedes the play (the download still lands in the cache).
  Future<({String? source, bool cached})> _resolveSource(
    VoiceSourceResolver resolve, {
    required String? mediaKey,
    required String? ownerId,
    required Set<String> messageIds,
  }) async {
    final cache = _mediaCache;
    if (cache == null || mediaKey == null) {
      return (source: await resolve(), cached: false);
    }
    final hit = await cache.cachedPath(mediaKey);
    if (hit != null) {
      // Played again: last in line for the cache's byte budget.
      unawaited(cache.touch(mediaKey));
      return (source: hit, cached: true);
    }
    final source = await resolve();
    if (source == null || !source.startsWith('http')) {
      return (source: source, cached: false);
    }
    final download = cache.fetch(
      mediaKey: mediaKey,
      url: source,
      refreshUrl: () async => _refreshMediaUrl?.call(mediaKey),
      relationshipId: ownerId,
      messageIds: messageIds,
    );
    try {
      // Voice waits no longer than a stream may buffer: a slow link (one
      // that trickles, which never trips the download's silence bound)
      // streams instead.
      final path = await download.timeout(_bufferingGiveUpAfter);
      return (source: path, cached: true);
    } on TimeoutException {
      // The download carries on and lands in the cache, owned, for the next
      // play; its late result is not used (no second play, no swap).
      unawaited(download.then<void>((_) {}, onError: (Object _) {}));
      ChatLog.diagnostic('voice download slower than the give-up', null);
      return (source: source, cached: false);
    } catch (error) {
      ChatLog.diagnostic('voice cache download failed; streaming', error);
      return (source: source, cached: false);
    }
  }

  /// The cached copy of [mediaKey] would not play: drop it and resolve the
  /// note afresh (its local recording, else a signed URL to stream).
  Future<String?> _uncachedSource(
    String mediaKey,
    VoiceSourceResolver resolve,
  ) async {
    ChatLog.diagnostic('cached voice file would not play; streaming', null);
    await _mediaCache?.remove(mediaKey);
    try {
      return await resolve();
    } catch (error) {
      ChatLog.diagnostic('voice resolve after cache drop failed', error);
      return null;
    }
  }

  /// Pause the current note. A note still loading has nothing to pause, so
  /// it is cancelled instead (otherwise it would start once loaded).
  Future<void> pause() async {
    if (state.messageId == null) return;
    if (state.isLoading) {
      await _stopNow();
      return;
    }
    _stopWatchdog();
    state = state.copyWith(isPlaying: false, isBuffering: false);
    _publishCurrent(null);
    _releaseSession();
    try {
      await _engine.pause();
    } catch (error) {
      ChatLog.diagnostic('voice pause failed', error);
    }
  }

  Future<void> seek(String messageId, Duration to) async {
    if (state.messageId != messageId || state.isLoading) return;
    state = state.copyWith(position: to);
    try {
      await _engine.seek(to);
    } catch (error) {
      ChatLog.diagnostic('voice seek failed', error);
    }
  }

  Future<void> cycleRate() async {
    final next = rates[(rates.indexOf(state.rate) + 1) % rates.length];
    state = state.copyWith(rate: next);
    if (state.messageId != null) {
      try {
        await _engine.setRate(next);
      } catch (error) {
        ChatLog.diagnostic('voice rate failed', error);
      }
    }
  }

  /// Everything off: a chat screen was left. With [ifOwnedBy], only a note
  /// started in that conversation (or one whose owner is unknown) stops —
  /// leaving chat A must not silence chat B's note.
  Future<void> stop({String? ifOwnedBy}) async {
    // Scheduled by ChatScreen after its route went away; the container may
    // have been torn down in between.
    if (!mounted) return;
    if (ifOwnedBy != null && _ownerId != null && _ownerId != ifOwnedBy) {
      return;
    }
    await _stopNow();
  }

  /// Chat [ownerId] took the screen: a note from any OTHER conversation
  /// stops (one conversation audible at a time, as in WhatsApp).
  Future<void> stopIfOwnedByAnother(String ownerId) async {
    if (!mounted || state.messageId == null || _ownerId == ownerId) return;
    await _stopNow();
  }

  /// [messageId] went away (deleted, purged, hidden): stop it if it is the
  /// current note, since its bubble — the only way to pause it — is gone.
  Future<void> stopMessage(String messageId) => stopMessages({messageId});

  /// Messages that went away, named by client id and/or server id: stop the
  /// current note if it is one of them.
  Future<void> stopMessages(Set<String> ids) async {
    final current = state.messageId;
    if (!mounted || current == null) return;
    final server = _serverMessageId;
    if (!ids.contains(current) && (server == null || !ids.contains(server))) {
      return;
    }
    await _stopNow();
  }

  Future<void> _stopNow() async {
    _generation++;
    _stopWatchdog();
    _ownerId = null;
    _serverMessageId = null;
    final hadMessage = state.messageId != null;
    state = VoicePlaybackState(
      rate: state.rate,
      failureCount: state.failureCount,
    );
    _publishCurrent(null);
    // Before the early return: a stale hold must go even with no note.
    _releaseSession();
    if (!hadMessage) return;
    await _stopEngineQuietly();
  }

  Future<void> _stopEngineQuietly() async {
    try {
      await _engine.stop();
    } catch (error) {
      ChatLog.diagnostic('voice stop failed', error);
    }
  }

  /// Another player (a video) took the floor: the handshake is the shared
  /// provider going null while we are playing — or still loading, which
  /// [pause] turns into a cancel.
  void onCurrentIdCleared() {
    if (state.isPlaying || state.isLoading) unawaited(pause());
  }

  @override
  // `state` is the notifier's own state here.
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Any state but resumed (stories Wave 3): the privacy cover is up from
    // `inactive` on and the chat stays mounted behind it, so nothing else
    // stops a note playing to a covered screen. It does not resume itself.
    if (lifecycle != AppLifecycleState.resumed &&
        (state.isPlaying || state.isLoading)) {
      unawaited(pause());
    }
  }

  void _onPosition(Duration position) {
    if (state.messageId == null || state.isLoading) return;
    // audioplayers' FramePositionUpdater reports EVERY frame while it
    // believes it is playing, so a repeated value is no progress: it must
    // neither count as an advance nor rebuild the bubble per frame.
    if (position == state.position) return;
    _lastAdvanceAt = clock.now();
    _advancedGeneration = _generation;
    state = state.copyWith(position: position, isBuffering: false);
  }

  void _onComplete() {
    // A late completion of the previous source must not wipe a new note:
    // not while it loads, and not before it has played (the source token —
    // see [_advancedGeneration]).
    if (state.messageId == null || state.isLoading) return;
    if (_advancedGeneration != _generation) return;
    _stopWatchdog();
    // Not held: audioplayers' default ReleaseMode.release frees the source
    // on completion, so resuming it would do nothing. Reset, and the next
    // tap starts the note fresh from the start.
    _ownerId = null;
    _serverMessageId = null;
    state = VoicePlaybackState(
      rate: state.rate,
      failureCount: state.failureCount,
    );
    _publishCurrent(null);
    _releaseSession();
  }

  void _onEnginePlaying(bool playing) {
    if (state.messageId == null || state.isLoading) return;
    if (!playing && state.isPlaying) {
      _stopWatchdog();
      state = state.copyWith(isPlaying: false, isBuffering: false);
      _publishCurrent(null);
      _releaseSession();
    }
  }

  /// Checks progress while playing. No ADVANCE (position ticks arrive every
  /// frame, advancing or not) means one of two things:
  /// - a local file: the OS paused us without telling the plugin (a call,
  ///   Siri) — after [_stallAfter], reflect it and make the pause real so
  ///   the next tap resumes cleanly;
  /// - a remote source: most likely the network — after [_stallAfter] show
  ///   the loading ring but keep playing; only after
  ///   [_bufferingGiveUpAfter] call it paused.
  void _startWatchdog() {
    _lastAdvanceAt = clock.now();
    _watchdog ??= Timer.periodic(_watchdogInterval, (_) => _checkProgress());
  }

  Duration get _watchdogInterval {
    final quarter = _stallAfter ~/ 4;
    if (quarter > const Duration(milliseconds: 250)) {
      return const Duration(milliseconds: 250);
    }
    if (quarter < const Duration(milliseconds: 10)) {
      return const Duration(milliseconds: 10);
    }
    return quarter;
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  void _checkProgress() {
    if (!state.isPlaying) {
      _stopWatchdog();
      return;
    }
    final quiet = clock.now().difference(_lastAdvanceAt);
    if (_isLocalSource) {
      if (quiet >= _stallAfter) unawaited(pause());
      return;
    }
    if (quiet >= _bufferingGiveUpAfter) {
      unawaited(pause());
    } else if (quiet >= _stallAfter && !state.isBuffering) {
      state = state.copyWith(isBuffering: true);
    }
  }

  void _fail(String messageId, Object? error, StackTrace? stack) {
    // diagnostic, not e: a playback failure carries no message content.
    if (error != null) {
      ChatLog.diagnostic('voice playback failed', error);
      if (stack != null) debugPrintStack(stackTrace: stack);
    }
    _stopWatchdog();
    _ownerId = null;
    _serverMessageId = null;
    state = VoicePlaybackState(
      rate: state.rate,
      failureCount: state.failureCount + 1,
      failedMessageId: messageId,
    );
    _publishCurrent(null);
    _releaseSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopWatchdog();
    for (final s in _subscriptions) {
      s.cancel();
    }
    // The engine is disposed by voicePlaybackEngineProvider, which owns it.
    _releaseSession();
    super.dispose();
  }
}

/// The one voice engine. Owned (and disposed) here, not by the controller,
/// so an override in tests is never disposed behind the test's back.
final voicePlaybackEngineProvider = Provider<VoicePlaybackEngine>((ref) {
  final engine = AudioPlayersVoiceEngine();
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});

/// How long without an advance before a local note counts as interrupted
/// and a remote one shows its loading ring.
final voicePlaybackStallAfterProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 1500),
);

/// How long a remote note may buffer (no advance) before it is shown as
/// paused.
final voicePlaybackBufferingGiveUpProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 8),
);

final voicePlaybackControllerProvider = StateNotifierProvider<
  VoicePlaybackController,
  VoicePlaybackState
>((ref) {
  final controller = VoicePlaybackController(
    engine: ref.watch(voicePlaybackEngineProvider),
    session: ref.watch(audioSessionProvider),
    signMediaUrl: (mediaKey) async {
      final provider = signedMediaUrlProvider(mediaKey);
      // Listened for the duration of the read, so the member stays alive
      // through its in-place retries/backoff; closed once it settles (a
      // success keeps itself alive until its grant needs re-signing).
      final subscription = ref.listen<AsyncValue<String>>(provider, (_, __) {});
      try {
        return await ref.read(provider.future);
      } catch (error) {
        ChatLog.diagnostic('voice sign failed', error);
        return null;
      } finally {
        subscription.close();
      }
    },
    mediaCache: ref.watch(chatMediaCacheProvider),
    refreshMediaUrl: (mediaKey) => ref.read(resignMediaUrlProvider)(mediaKey),
    stallAfter: ref.watch(voicePlaybackStallAfterProvider),
    bufferingGiveUpAfter: ref.watch(voicePlaybackBufferingGiveUpProvider),
    publishCurrent:
        (id) =>
            ref.read(currentlyPlayingVoiceMessageIdProvider.notifier).state =
                id,
    stopOtherMedia: () {
      if (ref.read(currentlyPlayingVideoMessageIdProvider) != null) {
        ref.read(currentlyPlayingVideoMessageIdProvider.notifier).state = null;
      }
    },
  );
  // VideoMessagePlayer clears the voice id when a video starts.
  ref.listen<String?>(currentlyPlayingVoiceMessageIdProvider, (_, next) {
    if (next == null) controller.onCurrentIdCleared();
  });
  // A message that went away on the server (realtime soft or hard delete),
  // even one this device never loaded into a chat list (a note played from
  // Media): stop it if it is the current note.
  final removals = ref
      .read(chatMessageRemovalsProvider)
      .stream
      .listen((ids) => unawaited(controller.stopMessages(ids)));
  ref.onDispose(removals.cancel);
  // Signing out or switching account stops playback by construction: the
  // controller is app-scoped and would otherwise play on for the next
  // account (a note from someone else's conversation).
  ref.listen<String?>(
    currentUserProvider.select((user) => user?.id),
    (previous, next) {
      if (previous != next) unawaited(controller.stop());
    },
    onError: (error, _) => ChatLog.diagnostic('voice account watch', error),
  );
  return controller;
});

import 'dart:async';
import 'dart:io';

import 'package:attune/core/providers/profile_providers/profile_provider.dart';
import 'package:attune/core/services/media/screenshot_detection_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

/// Full-screen one-shot ephemeral video playback. Unlike VideoMessagePlayer
/// (Part 1's gallery-video bubble player, which is reused across a
/// scrolling list and therefore needs lazy controller construction), this
/// screen has exactly one playback per screen instance — the
/// VideoPlayerController is constructed eagerly in initState, matching
/// VoiceMessagePlayer's eager-construction precedent rather than
/// VideoMessagePlayer's lazy one, since the list-reuse concern that
/// motivated lazy construction there doesn't apply to a single full-screen
/// route.
///
/// Calls markVideoViewed on playback completion OR explicit dismissal
/// (tap anywhere on screen) — both count as "viewed," there is no
/// partial-view distinction (matches real Snapchat behavior).
///
/// Takes the same [Conversation] object chat_screen.dart itself holds
/// (rather than a bare relationshipId string), mirroring
/// EphemeralCameraScreen's identical correction — chatControllerProvider
/// (and the ephemeralVideoExpiredProvider derived from it, used below to
/// detect a cross-device revocation while this screen is open) is a family
/// provider keyed on the whole Conversation object, so a relationshipId-only
/// constructor could not reach the SAME controller instance chat_screen.dart
/// is using.
class EphemeralVideoViewerScreen extends ConsumerStatefulWidget {
  const EphemeralVideoViewerScreen({
    super.key,
    required this.messageId,
    required this.videoUrl,
    required this.conversation,
  });

  final String messageId;
  final String videoUrl;
  final Conversation conversation;

  @override
  ConsumerState<EphemeralVideoViewerScreen> createState() =>
      _EphemeralVideoViewerScreenState();
}

class _EphemeralVideoViewerScreenState
    extends ConsumerState<EphemeralVideoViewerScreen> {
  VideoPlayerController? _controller;
  bool _hasMarkedViewed = false;
  bool _expiredElsewhere = false;
  bool _initFailed = false;
  // One-notice-per-viewing-session latch (Important finding I4): the
  // Android-side ContentObserver debounce is native, per-session, and
  // 2-second-windowed, and iOS has no debounce at all — either can still
  // fire onScreenshotDetected more than once for what feels like a single
  // screenshot to the user. Set true on the FIRST attempted notice
  // (success or failure) so at most one "X took a screenshot" system
  // message is ever sent per screen instance.
  bool _screenshotNotified = false;
  final _screenshotDetection = ScreenshotDetectionService();
  StreamSubscription<void>? _screenshotSubscription;

  @override
  void initState() {
    super.initState();
    final controller =
        widget.videoUrl.startsWith('http')
            ? VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
            : VideoPlayerController.file(File(widget.videoUrl));
    controller.addListener(_onPlaybackUpdate);
    controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _controller = controller);
          controller.play();
        })
        .catchError((_) {
          // Does NOT auto-pop and does NOT auto-mark-viewed: a decode
          // failure is surfaced as a real, visible error state (see
          // build()'s _initFailed branch) with its own explicit dismiss
          // affordance, rather than either silently closing (the brief's
          // original draft, which left the message unmarked and looked
          // like the app just closed on its own) or silently leaving an
          // indefinite spinner with no indication anything failed (this
          // screen's behavior before this fix — indistinguishable from a
          // hang from the user's perspective).
          if (mounted) setState(() => _initFailed = true);
        });
    _screenshotSubscription = _screenshotDetection.onScreenshotDetected.listen(
      (_) => unawaited(_notifyScreenshot()),
    );
  }

  Future<void> _notifyScreenshot() async {
    // Best-effort instrumentation only (see ScreenshotDetectionService's own
    // doc comment) — a screenshot notice is authored as if from the viewer
    // (the person who screenshotted), riding the ordinary sender_id/insert
    // path unchanged (see 20260816140000_chat_screenshot_notice.sql), so no
    // separate "system author" concept is needed.
    //
    // Latched to at most one attempt per screen instance (Important finding
    // I4): set BEFORE the await, same "claim intent first" shape as
    // _markViewedAndClose's _hasMarkedViewed, so a second screenshot event
    // arriving while the first notice is still in flight can't also pass
    // the guard and send a duplicate.
    if (_screenshotNotified) return;
    _screenshotNotified = true;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    final name = profile?.displayName ?? profile?.username ?? 'Someone';
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendTextMessage(
            relationshipId: widget.conversation.relationshipId,
            senderId: user.id,
            clientMessageId: const Uuid().v4(),
            content: '$name took a screenshot',
            isSystemNotice: true,
          );
    } catch (error) {
      // Best-effort: a failed screenshot notice must never propagate
      // uncaught into the onScreenshotDetected stream listener (which
      // would otherwise crash the isolate's error zone), and must never
      // block or affect video playback/dismissal. Logged so it's at least
      // diagnosable, not silently swallowed.
      ChatLog.e('screenshot notice send failed', error);
    }
  }

  void _onPlaybackUpdate() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      unawaited(_markViewedAndClose());
    }
  }

  Future<void> _markViewedAndClose() async {
    if (_hasMarkedViewed) return;
    _hasMarkedViewed = true;
    // markVideoViewed is documented idempotent/safe-to-retry (see
    // mark_video_viewed's own header comment in
    // 20260816130000_chat_ephemeral_video.sql — the UPDATE ... WHERE
    // viewed_at IS NULL guard means a second call after a failed first
    // attempt is a safe no-op if the first actually landed, and a full
    // retry otherwise). One retry after a brief delay covers a transient
    // network blip without making the user wait indefinitely; a second
    // failure just logs and still closes the screen (Important finding
    // I1) — the user's dismissal intent must be honored either way, since
    // _hasMarkedViewed is already latched true and there is otherwise no
    // way for the user to get off this screen except the OS back gesture.
    try {
      await ref
          .read(chatRepositoryProvider)
          .markVideoViewed(messageId: widget.messageId);
    } catch (error) {
      ChatLog.e('mark video viewed failed, retrying once', error);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await ref
            .read(chatRepositoryProvider)
            .markVideoViewed(messageId: widget.messageId);
      } catch (retryError) {
        ChatLog.e('mark video viewed retry failed', retryError);
      }
    }
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlaybackUpdate);
    _controller?.dispose();
    unawaited(_screenshotSubscription?.cancel());
    _screenshotDetection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cross-device revocation while this screen is open: ephemeralVideoExpiredProvider
    // is derived from chatControllerProvider(conversation)'s own
    // state.messages, so it recomputes whenever a realtime UPDATE for this
    // message lands (e.g. the partner opened it on another device and
    // mark_video_viewed already deleted the media server-side).
    //
    // Watched (not just listened) so an already-expired message is caught
    // on this screen's very first build too — ref.listen's callback only
    // fires on a CHANGE, so a message that was already expired by the time
    // this screen mounted (e.g. a revocation that landed a moment before
    // the push completed) would otherwise never be caught, since there is
    // no earlier "previous" value for listen to compare against.
    final expiredProvider = ephemeralVideoExpiredProvider((
      conversation: widget.conversation,
      messageId: widget.messageId,
    ));
    final isExpiredNow = ref.watch(expiredProvider);
    ref.listen<bool>(expiredProvider, (previous, isExpired) {
      if (isExpired && !_expiredElsewhere) {
        setState(() => _expiredElsewhere = true);
      }
    });

    if (_expiredElsewhere || isExpiredNow) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('Already viewed', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    if (_initFailed) {
      // A visible error state, not an indefinite spinner: without this the
      // user has no way to tell a decode failure apart from the app
      // hanging — the tap-anywhere-to-dismiss affordance below is the same
      // established gesture as the normal playback view, and dismissing
      // from here is a deliberate "I'm done, close it" action, so it marks
      // the message viewed exactly like any other explicit dismissal.
      return Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          // opaque, not the default deferToChild: the error message itself
          // is a small centered Column, but the tap-anywhere affordance is
          // meant to cover the whole screen, matching the normal playback
          // view's Stack(fit: StackFit.expand) hit area.
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_markViewedAndClose()),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.white70, size: 40),
                SizedBox(height: 12),
                Text(
                  "Couldn't play this video",
                  style: TextStyle(color: Colors.white),
                ),
                SizedBox(height: 4),
                Text(
                  'Tap to close',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => unawaited(_markViewedAndClose()),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              )
            else
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void initState() {
    super.initState();
    final controller = widget.videoUrl.startsWith('http')
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
          // Deliberately does NOT auto-pop: the tap-anywhere-to-dismiss
          // affordance (see build()'s GestureDetector, which wraps the
          // loading state too) already covers "this video can't be
          // played," and routing a decode failure through the same
          // _markViewedAndClose path — rather than a silent pop here —
          // means a corrupt/undecodable ephemeral video still gets
          // correctly marked viewed instead of leaking a message that can
          // never be dismissed as viewed.
        });
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
    await ref
        .read(chatRepositoryProvider)
        .markVideoViewed(messageId: widget.messageId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlaybackUpdate);
    _controller?.dispose();
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
          child: Text(
            'Already viewed',
            style: TextStyle(color: Colors.white),
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

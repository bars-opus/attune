import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:flutter/material.dart';
import 'package:video_compress/video_compress.dart';

/// Modal, non-dismissible dialog shown while [ChatVideoPreparer.prepare]
/// transcodes and thumbnails the trimmed clip. Pushed via `showDialog` from
/// `chat_screen.dart`'s `_attachVideo`.
///
/// Kept as its own small widget file rather than inlined in chat_screen.dart
/// (1600+ lines already) — mirrors this codebase's "split when a file grows
/// unwieldy" convention already applied to voice_message_player.dart and
/// video_message_player.dart living alongside chat_text_field.dart rather
/// than inside chat_screen.dart.
///
/// Contract with the caller: [show] resolves with a [PreparedChatVideo] on
/// success, or throws [ChatVideoRejected] on failure OR explicit cancel (the
/// cancel path throws the same `media_compress_failed` code `prepare()`
/// itself throws for a compression failure, since from the caller's
/// perspective both mean "no usable output" and share the same user-facing
/// message). This mirrors `_attachImage`'s `ChatImagePreparer.prepare()`
/// call, which the caller already wraps in `on ChatVideoRejected catch`.
class VideoPrepareProgressDialog extends StatefulWidget {
  const VideoPrepareProgressDialog({
    super.key,
    required this.localPath,
    required this.trimStart,
    required this.trimEnd,
  });

  final String localPath;
  final Duration trimStart;
  final Duration trimEnd;

  /// Shows the dialog and returns a future that completes exactly like
  /// [ChatVideoPreparer.prepare] itself would — with the prepared video, or
  /// throwing [ChatVideoRejected] — so callers can reuse the exact same
  /// try/on-catch shape they'd use calling `prepare()` directly.
  static Future<PreparedChatVideo> show(
    BuildContext context, {
    required String localPath,
    required Duration trimStart,
    required Duration trimEnd,
  }) async {
    final result = await showDialog<_DialogResult>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => VideoPrepareProgressDialog(
            localPath: localPath,
            trimStart: trimStart,
            trimEnd: trimEnd,
          ),
    );
    // A null `result` only happens if the dialog route is popped by
    // something other than this widget itself (e.g. the app-level route
    // observer during a hot-reload/teardown) — treat it the same as any
    // other failed prepare rather than leaving the caller's await hanging.
    if (result == null) {
      throw const ChatVideoRejected('media_compress_failed');
    }
    return result.resolve();
  }

  @override
  State<VideoPrepareProgressDialog> createState() =>
      _VideoPrepareProgressDialogState();
}

/// Carries either the successful output or the rejection back through
/// Navigator.pop's value channel (which can't carry a thrown exception
/// directly), so [VideoPrepareProgressDialog.show] can re-throw it on the
/// caller's side and preserve the "await this, catch ChatVideoRejected"
/// calling convention the rest of chat_screen.dart already uses.
class _DialogResult {
  const _DialogResult.success(this._video) : _rejection = null;
  const _DialogResult.rejected(ChatVideoRejected rejection)
    : _rejection = rejection,
      _video = null;

  final PreparedChatVideo? _video;
  final ChatVideoRejected? _rejection;

  PreparedChatVideo resolve() {
    final rejection = _rejection;
    if (rejection != null) throw rejection;
    return _video!;
  }
}

class _VideoPrepareProgressDialogState
    extends State<VideoPrepareProgressDialog> {
  double? _progress;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final prepared = await const ChatVideoPreparer().prepare(
        localPath: widget.localPath,
        trimStart: widget.trimStart,
        trimEnd: widget.trimEnd,
        onProgress: (value) {
          if (!mounted) return;
          // video_compress reports 0-100 on its native progress channel;
          // normalize once here for LinearProgressIndicator's 0-1 contract.
          setState(() => _progress = (value / 100).clamp(0.0, 1.0));
        },
      );
      if (!mounted || _cancelling) return;
      Navigator.of(context).pop(_DialogResult.success(prepared));
    } on ChatVideoRejected catch (rejected) {
      if (!mounted || _cancelling) return;
      Navigator.of(context).pop(_DialogResult.rejected(rejected));
    } catch (_) {
      if (!mounted || _cancelling) return;
      Navigator.of(
        context,
      ).pop(const _DialogResult.rejected(ChatVideoRejected('media_compress_failed')));
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    try {
      await VideoCompress.cancelCompression();
    } catch (_) {
      // Best-effort — the dialog still closes below regardless of whether
      // the native side had anything in-flight to actually cancel.
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      const _DialogResult.rejected(ChatVideoRejected('media_compress_failed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The only way out is the explicit Cancel button — a system back
      // gesture mid-transcode would otherwise leave compressVideo() running
      // with nothing awaiting it and no cleanup of its output temp file.
      canPop: false,
      child: AlertDialog(
        title: const Text('Preparing video'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: _progress),
            SizedBox(height: Spacing.sm),
            Text(
              _cancelling
                  ? 'Cancelling…'
                  : 'This can take a moment for longer clips.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _cancelling ? null : _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';

/// Full-screen preview shown after every gallery/crop pick, before
/// ChatImagePreparer.prepare() runs — lets the user see the actual image
/// and type a caption for it directly, matching WhatsApp/iMessage's
/// pick-then-caption flow instead of silently reusing whatever was already
/// typed in the composer. Reached via the 'imageCaption' named route
/// (registered in app_router.dart) — imagePath is passed via `extra`.
///
/// Returns the caption text on send, or null if the user backs out
/// (cancelling the whole attach — matches VideoTrimScreen's null-means-
/// user-backed-out convention).
class ImageCaptionScreen extends StatefulWidget {
  const ImageCaptionScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ImageCaptionScreen> createState() => _ImageCaptionScreenState();
}

class _ImageCaptionScreenState extends State<ImageCaptionScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    context.pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Separate from ChatTextField's own send icon, which only enables
          // once there's caption text (correct for normal chat, where an
          // empty send is meaningless) — here an empty caption is a valid
          // send (the image alone is the message), so this is always
          // enabled regardless of what's typed.
          TextButton(
            onPressed: _send,
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: ChatTextField(
                controller: _controller,
                focusNode: _focusNode,
                hintText: 'Add a caption',
                onSend: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class ChatTextField extends StatefulWidget {
  const ChatTextField({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttachImage,
    this.onOpenTranslator,
    this.showAttachImage = false,
    this.showTranslator = false,
    this.enabled = true,
    this.hintText = 'Type a message...',
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttachImage;
  final VoidCallback? onOpenTranslator;
  final bool showAttachImage;
  final bool showTranslator;
  final bool enabled;
  final String hintText;

  @override
  State<ChatTextField> createState() => _ChatTextFieldState();
}

class _ChatTextFieldState extends State<ChatTextField> {
  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.showAttachImage)
              IconButton(
                onPressed: widget.enabled ? widget.onAttachImage : null,
                icon: const Icon(Icons.photo_outlined),
                tooltip: 'Add image',
              ),
            if (widget.showTranslator && _hasText)
              IconButton(
                onPressed: widget.enabled ? widget.onOpenTranslator : null,
                icon: const Icon(Icons.help_outline_rounded),
                tooltip: 'Help me say this',
              ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onSubmitted: (_) {
                  if (_hasText && widget.enabled) {
                    widget.onSend();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: widget.enabled && _hasText ? widget.onSend : null,
              tooltip: 'Send message',
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

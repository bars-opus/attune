import 'package:attune/core/ui/motion/scale_pop.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
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
    this.focusNode,
    this.sendButtonColor,
    this.onSendButtonColor,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttachImage;
  final VoidCallback? onOpenTranslator;
  final bool showAttachImage;
  final bool showTranslator;
  final bool enabled;
  final String hintText;

  /// Overrides the send button's fill AND the text field's focused border
  /// color, which otherwise both default to colorScheme.primary. Null (the
  /// default) keeps those defaults — 1:1 chat has no notion of "side" to
  /// tint by. DebateRoomScreen passes its FOR/AGAINST color here so the
  /// whole composer matches the side it's about to post to, the same way
  /// ForumPostBubble's own bubbles are tinted by side rather than always
  /// primary. Ignored when null.
  final Color? sendButtonColor;

  /// The icon's contrast color against [sendButtonColor] — e.g.
  /// colorScheme.onPrimary / colorScheme.onError, the same token pairing
  /// ForumPostBubble uses for its own bubble content. Only meaningful
  /// alongside [sendButtonColor]; ignored when that's null (the theme
  /// default IconButtonTheme already supplies the right onPrimary pairing).
  final Color? onSendButtonColor;

  /// Optional external focus node — e.g. so a caller can programmatically
  /// focus the field (tapping "Reply" on a comment) without owning its
  /// own separately-created, never-attached FocusNode.
  final FocusNode? focusNode;

  @override
  State<ChatTextField> createState() => _ChatTextFieldState();
}

class _ChatTextFieldState extends State<ChatTextField> {
  int _sendPulse = 0;

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

  void _handleSend() {
    if (!(widget.enabled && _hasText)) return;
    setState(() => _sendPulse++);
    widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
            // No entrance animation here: this composer is persistent, and it
            // rebuilds on every keystroke (_hasText drives the translator and
            // send affordances). A ShakeTransition re-ran its 900ms slide on
            // each rebuild, shifting the field — and the send button's hit
            // target — sideways while the user typed.
            child: CardInkWell(
              // Plain token rather than `20.r`: the .r extension reads
              // ScreenUtil.screenWidth, which throws in widget tests that
              // render this field without initialising ScreenUtil.
              borderRadius: BorderRadius.circular(BorderRadiusTokens.xl),
              padding: const EdgeInsets.all(0),
              margin: const EdgeInsets.all(0),
              elevation: ElevationTokens.sm,

              // AppTextFormField's fill paints square corners when
              // showBorder is false (InputBorder.none doesn't clip the
              // fill) — clip explicitly so the visible shape stays rounded
              // to match the shadow's outline.
              child: AppTextFormField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                hintText: widget.hintText,
                minLines: 1,
                maxLines: 5,
                showBorder: true,
                focusedBorderColor: widget.sendButtonColor,
                // prefixIcon: const Icon(Icons.search, size: 20),
                onFieldSubmitted: (_) => _handleSend(),
                label: '',
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Not wrapped in an entrance animation: AnimatedScaleFade starts at
          // scale 0 and takes 800ms to reach full size, and it restarts on
          // every rebuild of this composer (each keystroke). That left the
          // send button scaled down — and effectively untappable — for most of
          // a second after the user finished typing. ScalePop below still
          // gives the button its press feedback.
          IconButton.filled(
            onPressed: widget.enabled && _hasText ? _handleSend : null,
            tooltip: 'Send message',
            style:
                widget.sendButtonColor == null
                    ? null
                    : IconButton.styleFrom(
                      backgroundColor: widget.sendButtonColor,
                      foregroundColor: widget.onSendButtonColor,
                    ),
            icon: ScalePop(
              trigger: _sendPulse,
              child: const Icon(Icons.send_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

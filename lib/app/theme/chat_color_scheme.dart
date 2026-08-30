import 'package:flutter/material.dart';

/// Semantic colors for Attune's conversation surface.
///
/// Chat needs tighter coordination than the app-wide [ColorScheme] provides:
/// its wallpaper, sender and receiver bubbles are viewed as one composition.
/// Keeping those roles together prevents local color tweaks from breaking the
/// balance or text contrast elsewhere in the conversation.
@immutable
class ChatColorScheme extends ThemeExtension<ChatColorScheme> {
  const ChatColorScheme({
    required this.background,
    required this.pattern,
    required this.patternOpacity,
    required this.senderBubble,
    required this.onSenderBubble,
    required this.receiverBubble,
    required this.onReceiverBubble,
    required this.metadata,
    required this.relationshipAccent,
  });

  /// Attune Paper: a warm conversation canvas inspired by familiar chat apps,
  /// with sage patterning and a softer mint sender surface.
  static const light = ChatColorScheme(
    background: Color(0xFFF6F3EC),
    pattern: Color(0xFFC5D3C4),
    patternOpacity: 0.46,
    senderBubble: Color(0xFFD7F4DF),
    onSenderBubble: Color(0xFF14231D),
    receiverBubble: Color(0xFFFFFEFA),
    onReceiverBubble: Color(0xFF171E1B),
    metadata: Color(0xFF65736D),
    relationshipAccent: Color(0xFFD83D79),
  );

  /// Attune Paper in dark mode: plain charcoal depth with quiet neutral
  /// doodles, while the message bubbles keep the relationship color story.
  static const dark = ChatColorScheme(
    background: Color(0xFF101112),
    pattern: Color(0xFFE2E4E3),
    patternOpacity: 0.16,
    senderBubble: Color(0xFF12604A),
    onSenderBubble: Color(0xFFF1F7F3),
    receiverBubble: Color(0xFF1F2925),
    onReceiverBubble: Color(0xFFF0F4F2),
    metadata: Color(0xFF91A098),
    relationshipAccent: Color(0xFFFF6F9E),
  );

  final Color background;
  final Color pattern;
  final double patternOpacity;
  final Color senderBubble;
  final Color onSenderBubble;
  final Color receiverBubble;
  final Color onReceiverBubble;
  final Color metadata;
  final Color relationshipAccent;

  @override
  ChatColorScheme copyWith({
    Color? background,
    Color? pattern,
    double? patternOpacity,
    Color? senderBubble,
    Color? onSenderBubble,
    Color? receiverBubble,
    Color? onReceiverBubble,
    Color? metadata,
    Color? relationshipAccent,
  }) {
    return ChatColorScheme(
      background: background ?? this.background,
      pattern: pattern ?? this.pattern,
      patternOpacity: patternOpacity ?? this.patternOpacity,
      senderBubble: senderBubble ?? this.senderBubble,
      onSenderBubble: onSenderBubble ?? this.onSenderBubble,
      receiverBubble: receiverBubble ?? this.receiverBubble,
      onReceiverBubble: onReceiverBubble ?? this.onReceiverBubble,
      metadata: metadata ?? this.metadata,
      relationshipAccent: relationshipAccent ?? this.relationshipAccent,
    );
  }

  @override
  ChatColorScheme lerp(covariant ChatColorScheme? other, double t) {
    if (other == null) return this;

    return ChatColorScheme(
      background: Color.lerp(background, other.background, t)!,
      pattern: Color.lerp(pattern, other.pattern, t)!,
      patternOpacity:
          patternOpacity + (other.patternOpacity - patternOpacity) * t,
      senderBubble: Color.lerp(senderBubble, other.senderBubble, t)!,
      onSenderBubble: Color.lerp(onSenderBubble, other.onSenderBubble, t)!,
      receiverBubble: Color.lerp(receiverBubble, other.receiverBubble, t)!,
      onReceiverBubble:
          Color.lerp(onReceiverBubble, other.onReceiverBubble, t)!,
      metadata: Color.lerp(metadata, other.metadata, t)!,
      relationshipAccent:
          Color.lerp(relationshipAccent, other.relationshipAccent, t)!,
    );
  }
}

extension ChatThemeDataExtension on ThemeData {
  ChatColorScheme get chatColors =>
      extension<ChatColorScheme>() ??
      (brightness == Brightness.dark
          ? ChatColorScheme.dark
          : ChatColorScheme.light);
}

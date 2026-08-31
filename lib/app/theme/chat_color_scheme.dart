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
    required this.backgroundAccent,
    required this.pattern,
    required this.patternOpacity,
    required this.senderBubble,
    required this.onSenderBubble,
    required this.receiverBubble,
    required this.onReceiverBubble,
    required this.metadata,
    required this.senderMetadata,
    required this.receiverMetadata,
    required this.senderReplySurface,
    required this.senderReplyAccent,
    required this.receiverReplySurface,
    required this.receiverReplyAccent,
    required this.voiceAccent,
    required this.relationshipAccent,
  });

  /// Attune Paper: a cool, airy conversation canvas with a restrained mint
  /// lift toward the lower edge and high-clarity message surfaces.
  static const light = ChatColorScheme(
    background: Color(0xFFE5E9E5),
    backgroundAccent: Color(0xFFA9D8BE),
    pattern: Color(0xFFC5D3C4),
    patternOpacity: 0.70,
    senderBubble: Color(0xFFDCFFC2),
    onSenderBubble: Color(0xFF14200F),
    receiverBubble: Color(0xFFFFFEFC),
    onReceiverBubble: Color(0xFF171B19),
    metadata: Color(0xFF65736D),
    senderMetadata: Color(0xFF67A43E),
    receiverMetadata: Color(0xFF8B918E),
    senderReplySurface: Color(0xFFC9F3A8),
    senderReplyAccent: Color(0xFF58AE22),
    receiverReplySurface: Color(0xFFE8F2F9),
    receiverReplyAccent: Color(0xFF3C98D2),
    voiceAccent: Color(0xFF2296F3),
    relationshipAccent: Color(0xFFD83D79),
  );

  /// Attune Paper in dark mode: plain charcoal depth with quiet neutral
  /// doodles, while the message bubbles keep the relationship color story.
  static const dark = ChatColorScheme(
    background: Color(0xFF101112),
    backgroundAccent: Color(0xFF101112),
    pattern: Color(0xFFE2E4E3),
    patternOpacity: 0.19,
    senderBubble: Color(0xFFDCFFC2),
    onSenderBubble: Color(0xFF14200F),
    receiverBubble: Color(0xFF1F2925),
    onReceiverBubble: Color(0xFFF0F4F2),
    metadata: Color(0xFF91A098),
    senderMetadata: Color(0xFF67A43E),
    receiverMetadata: Color(0xFF91A098),
    senderReplySurface: Color(0xFF0F4D3C),
    senderReplyAccent: Color(0xFFFF6F9E),
    receiverReplySurface: Color(0xFF35413D),
    receiverReplyAccent: Color(0xFFE2E4E3),
    voiceAccent: Color(0xFFB6FD9D),
    relationshipAccent: Color(0xFFFF6F9E),
  );

  final Color background;
  final Color backgroundAccent;
  final Color pattern;
  final double patternOpacity;
  final Color senderBubble;
  final Color onSenderBubble;
  final Color receiverBubble;
  final Color onReceiverBubble;
  final Color metadata;
  final Color senderMetadata;
  final Color receiverMetadata;
  final Color senderReplySurface;
  final Color senderReplyAccent;
  final Color receiverReplySurface;
  final Color receiverReplyAccent;
  final Color voiceAccent;
  final Color relationshipAccent;

  @override
  ChatColorScheme copyWith({
    Color? background,
    Color? backgroundAccent,
    Color? pattern,
    double? patternOpacity,
    Color? senderBubble,
    Color? onSenderBubble,
    Color? receiverBubble,
    Color? onReceiverBubble,
    Color? metadata,
    Color? senderMetadata,
    Color? receiverMetadata,
    Color? senderReplySurface,
    Color? senderReplyAccent,
    Color? receiverReplySurface,
    Color? receiverReplyAccent,
    Color? voiceAccent,
    Color? relationshipAccent,
  }) {
    return ChatColorScheme(
      background: background ?? this.background,
      backgroundAccent: backgroundAccent ?? this.backgroundAccent,
      pattern: pattern ?? this.pattern,
      patternOpacity: patternOpacity ?? this.patternOpacity,
      senderBubble: senderBubble ?? this.senderBubble,
      onSenderBubble: onSenderBubble ?? this.onSenderBubble,
      receiverBubble: receiverBubble ?? this.receiverBubble,
      onReceiverBubble: onReceiverBubble ?? this.onReceiverBubble,
      metadata: metadata ?? this.metadata,
      senderMetadata: senderMetadata ?? this.senderMetadata,
      receiverMetadata: receiverMetadata ?? this.receiverMetadata,
      senderReplySurface: senderReplySurface ?? this.senderReplySurface,
      senderReplyAccent: senderReplyAccent ?? this.senderReplyAccent,
      receiverReplySurface: receiverReplySurface ?? this.receiverReplySurface,
      receiverReplyAccent: receiverReplyAccent ?? this.receiverReplyAccent,
      voiceAccent: voiceAccent ?? this.voiceAccent,
      relationshipAccent: relationshipAccent ?? this.relationshipAccent,
    );
  }

  @override
  ChatColorScheme lerp(covariant ChatColorScheme? other, double t) {
    if (other == null) return this;

    return ChatColorScheme(
      background: Color.lerp(background, other.background, t)!,
      backgroundAccent:
          Color.lerp(backgroundAccent, other.backgroundAccent, t)!,
      pattern: Color.lerp(pattern, other.pattern, t)!,
      patternOpacity:
          patternOpacity + (other.patternOpacity - patternOpacity) * t,
      senderBubble: Color.lerp(senderBubble, other.senderBubble, t)!,
      onSenderBubble: Color.lerp(onSenderBubble, other.onSenderBubble, t)!,
      receiverBubble: Color.lerp(receiverBubble, other.receiverBubble, t)!,
      onReceiverBubble:
          Color.lerp(onReceiverBubble, other.onReceiverBubble, t)!,
      metadata: Color.lerp(metadata, other.metadata, t)!,
      senderMetadata: Color.lerp(senderMetadata, other.senderMetadata, t)!,
      receiverMetadata:
          Color.lerp(receiverMetadata, other.receiverMetadata, t)!,
      senderReplySurface:
          Color.lerp(senderReplySurface, other.senderReplySurface, t)!,
      senderReplyAccent:
          Color.lerp(senderReplyAccent, other.senderReplyAccent, t)!,
      receiverReplySurface:
          Color.lerp(receiverReplySurface, other.receiverReplySurface, t)!,
      receiverReplyAccent:
          Color.lerp(receiverReplyAccent, other.receiverReplyAccent, t)!,
      voiceAccent: Color.lerp(voiceAccent, other.voiceAccent, t)!,
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

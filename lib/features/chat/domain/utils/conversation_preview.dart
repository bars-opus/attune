import 'package:attune/features/chat/domain/entities/conversation.dart';

/// The one-line summary of a conversation's most recent message, shown in
/// the conversations list.
///
/// Shared rather than duplicated: this logic previously existed twice —
/// in conversations_screen and previous_relationships_screen — and both
/// copies handled image and video while omitting audio, so a voice note
/// fell through to the message's own (empty) content and the row rendered
/// a blank subtitle.
String conversationPreviewText(Conversation conversation) {
  final message = conversation.lastMessage;
  if (message == null) return 'No messages yet';
  if (message.isDeleted) return 'This message was deleted';

  final caption = message.content.trim();

  const labels = <String, String>{
    'image': 'Photo',
    'video': 'Video',
    'audio': 'Voice message',
    'streak': 'Streak',
  };

  final label = labels[message.mediaType];
  if (label != null) {
    // A streak reveals nothing before it is opened — not even whether it
    // HAS a caption, since that is itself information about the message.
    // Every other media type appends its caption as usual.
    if (message.mediaType == 'streak') return label;
    return caption.isEmpty ? label : '$label: $caption';
  }

  return message.content;
}

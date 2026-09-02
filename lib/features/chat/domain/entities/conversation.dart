import 'package:attune/features/chat/domain/entities/message.dart';

enum ConversationAvailability { active, readOnly, archived }

class Conversation {
  final String id;
  final String relationshipId;
  final String partnerId;
  /// The COUPLE's name for this chat: the shared chat_name if they set
  /// one, otherwise the partner's display name.
  ///
  /// For the header only. Anywhere a single person is speaking or being
  /// addressed -- a typing indicator, a reply preview, a bubble -- use
  /// [partnerName] instead, or the couple's shared name is put in one
  /// individual's mouth.
  final String name;

  /// The partner's own display name, never the couple's chat name.
  ///
  /// Falls back to [name] when the partner has no display name, so a
  /// caller always has something to show.
  final String partnerName;
  final String? avatarUrl;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;
  final String relationshipStatus;
  final ConversationAvailability availability;

  Conversation({
    required this.id,
    required this.relationshipId,
    required this.partnerId,
    required this.name,
    String? partnerName,
    required this.updatedAt,
    required this.relationshipStatus,
    required this.availability,
    this.avatarUrl,
    this.lastMessage,
    this.unreadCount = 0,
  }) : partnerName = partnerName ?? name;

  Conversation copyWith({
    String? id,
    String? relationshipId,
    String? partnerId,
    String? name,
    String? partnerName,
    String? avatarUrl,
    Message? lastMessage,
    int? unreadCount,
    DateTime? updatedAt,
    String? relationshipStatus,
    ConversationAvailability? availability,
  }) {
    return Conversation(
      id: id ?? this.id,
      relationshipId: relationshipId ?? this.relationshipId,
      partnerId: partnerId ?? this.partnerId,
      name: name ?? this.name,
      partnerName: partnerName ?? this.partnerName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
      relationshipStatus: relationshipStatus ?? this.relationshipStatus,
      availability: availability ?? this.availability,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'relationshipId': relationshipId,
      'partnerId': partnerId,
      'name': name,
      'partnerName': partnerName,
      'avatarUrl': avatarUrl,
      'lastMessage': lastMessage?.toJson(),
      'unreadCount': unreadCount,
      'updatedAt': updatedAt.toIso8601String(),
      'relationshipStatus': relationshipStatus,
      'availability': availability.name,
    };
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      relationshipId: json['relationshipId'] as String,
      partnerId: json['partnerId'] as String,
      name: json['name'] as String,
      // Older cached rows predate the field; falling back to name keeps
      // them rendering rather than crashing on a null.
      partnerName: json['partnerName'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      lastMessage:
          json['lastMessage'] == null
              ? null
              : Message.fromJson(
                Map<String, dynamic>.from(json['lastMessage'] as Map),
              ),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      relationshipStatus: json['relationshipStatus'] as String,
      availability: ConversationAvailability.values.byName(
        json['availability'] as String,
      ),
    );
  }

  bool get canSend => availability == ConversationAvailability.active;

  bool get isArchived => availability == ConversationAvailability.archived;

  String? get readOnlyReason {
    if (availability == ConversationAvailability.archived) {
      return 'This conversation has been archived and is no longer available.';
    }
    if (availability == ConversationAvailability.readOnly) {
      return 'This relationship chat is read-only.';
    }
    return null;
  }
}

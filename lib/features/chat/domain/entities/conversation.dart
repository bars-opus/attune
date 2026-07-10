import 'package:attune/features/chat/domain/entities/message.dart';

enum ConversationAvailability { active, readOnly, archived }

class Conversation {
  final String id;
  final String relationshipId;
  final String partnerId;
  final String name;
  final String? avatarUrl;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;
  final String relationshipStatus;
  final ConversationAvailability availability;

  const Conversation({
    required this.id,
    required this.relationshipId,
    required this.partnerId,
    required this.name,
    required this.updatedAt,
    required this.relationshipStatus,
    required this.availability,
    this.avatarUrl,
    this.lastMessage,
    this.unreadCount = 0,
  });

  Conversation copyWith({
    String? id,
    String? relationshipId,
    String? partnerId,
    String? name,
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

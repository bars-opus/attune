// lib/features/timeline/data/models/timeline_event_model.dart

import 'package:flutter/material.dart';

class TimelineEventModel {
  final String id;
  final String relationshipId;
  final String loggedBy;
  final String eventType;
  final String title;
  final String? note;
  final int? moodScore;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  TimelineEventModel({
    required this.id,
    required this.relationshipId,
    required this.loggedBy,
    required this.eventType,
    required this.title,
    this.note,
    this.moodScore,
    required this.occurredAt,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory TimelineEventModel.fromJson(Map<String, dynamic> json) {
    return TimelineEventModel(
      id: json['id'],
      relationshipId: json['relationship_id'],
      loggedBy: json['logged_by'],
      eventType: json['event_type'],
      title: json['title'],
      note: json['note'],
      moodScore: json['mood_score'],
      occurredAt: DateTime.parse(json['occurred_at']),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt:
          json['updated_at'] != null
              ? DateTime.parse(json['updated_at'])
              : null,
      deletedAt:
          json['deleted_at'] != null
              ? DateTime.parse(json['deleted_at'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'relationship_id': relationshipId,
      'logged_by': loggedBy,
      'event_type': eventType,
      'title': title,
      'note': note,
      'mood_score': moodScore,
      'occurred_at': occurredAt.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  String get eventTypeDisplay {
    switch (eventType) {
      case 'milestone':
        return 'Milestone';
      case 'conflict':
        return 'Conflict';
      case 'highlight':
        return 'Highlight';
      case 'first':
        return 'First';
      case 'anniversary':
        return 'Anniversary';
      default:
        return eventType;
    }
  }

  Color eventTypeColor(ColorScheme colorScheme) {
    switch (eventType) {
      case 'milestone':
        return colorScheme.primary;
      case 'conflict':
        return Colors.red;
      case 'highlight':
        return Colors.amber;
      case 'first':
        return Colors.purple;
      case 'anniversary':
        return Colors.pink;
      default:
        return colorScheme.primary;
    }
  }
}

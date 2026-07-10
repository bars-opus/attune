// lib/features/community/data/models/community_question.dart

import 'package:flutter/material.dart';

class CommunityQuestion {
  final String id;
  final String type; // 'this_or_that' or 'truth_or_dare'
  final String content;
  final String? optionA; // This or That only
  final String? optionB; // This or That only
  final String? emojiA; // This or That only
  final String? emojiB; // This or That only
  final String? questionType; // Truth or Dare only: 'truth' or 'dare'
  final String tone;
  final int communityUsageCount;
  final bool isSaved; // Whether the current user has saved this question
  final DateTime createdAt;

  const CommunityQuestion({
    required this.id,
    required this.type,
    required this.content,
    this.optionA,
    this.optionB,
    this.emojiA,
    this.emojiB,
    this.questionType,
    required this.tone,
    required this.communityUsageCount,
    this.isSaved = false,
    required this.createdAt,
  });

  factory CommunityQuestion.fromThisOrThatJson(Map<String, dynamic> json, {bool isSaved = false}) {
    return CommunityQuestion(
      id: json['id'],
      type: 'this_or_that',
      content: json['question_text'],
      optionA: json['option_a'],
      optionB: json['option_b'],
      emojiA: json['emoji_a'],
      emojiB: json['emoji_b'],
      tone: json['tone'],
      communityUsageCount: json['community_usage_count'] ?? 0,
      isSaved: isSaved,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  factory CommunityQuestion.fromTruthOrDareJson(Map<String, dynamic> json, {bool isSaved = false}) {
    return CommunityQuestion(
      id: json['id'],
      type: 'truth_or_dare',
      content: json['content'],
      questionType: json['question_type'],
      tone: json['tone'],
      communityUsageCount: json['community_usage_count'] ?? 0,
      isSaved: isSaved,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  String get typeDisplay {
    switch (type) {
      case 'this_or_that': return 'This or That';
      case 'truth_or_dare':
        return questionType == 'truth' ? 'Truth' : 'Dare';
      default: return '';
    }
  }

  String get typeIcon {
    switch (type) {
      case 'this_or_that': return '🔀';
      case 'truth_or_dare':
        return questionType == 'truth' ? '🗣' : '🎯';
      default: return '📌';
    }
  }

  String get toneDisplay {
    switch (tone) {
      case 'connecting': return '💙 Connecting';
      case 'romantic': return '❤️ Romantic';
      case 'playful': return '😄 Playful';
      case 'spicy': return '🔥 Spicy';
      case 'intimate': return '🌙 Intimate';
      default: return tone;
    }
  }

  Color get toneColor {
    switch (tone) {
      case 'connecting': return const Color(0xFF4A90D9);
      case 'romantic': return const Color(0xFFE74C3C);
      case 'playful': return const Color(0xFFF39C12);
      case 'spicy': return const Color(0xFFE67E22);
      case 'intimate': return const Color(0xFF9B59B6);
      default: return Colors.grey;
    }
  }
}

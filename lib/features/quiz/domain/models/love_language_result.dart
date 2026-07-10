// lib/features/quiz/domain/models/love_language_result.dart

import 'package:equatable/equatable.dart';

class LoveLanguageResult extends Equatable {
  final int words;
  final int qualityTime;
  final int gifts;
  final int acts;
  final int touch;
  final String primary;
  final String secondary;
  final DateTime completedAt;

  const LoveLanguageResult({
    required this.words,
    required this.qualityTime,
    required this.gifts,
    required this.acts,
    required this.touch,
    required this.primary,
    required this.secondary,
    required this.completedAt,
  });

  factory LoveLanguageResult.fromJson(Map<String, dynamic> json) {
    return LoveLanguageResult(
      words: json['words'] ?? 0,
      qualityTime: json['quality_time'] ?? 0,
      gifts: json['gifts'] ?? 0,
      acts: json['acts'] ?? 0,
      touch: json['touch'] ?? 0,
      primary: json['primary'] ?? '',
      secondary: json['secondary'] ?? '',
      completedAt: DateTime.tryParse(json['completed_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'words': words,
      'quality_time': qualityTime,
      'gifts': gifts,
      'acts': acts,
      'touch': touch,
      'primary': primary,
      'secondary': secondary,
      'completed_at': completedAt.toIso8601String(),
    };
  }

  List<Map<String, dynamic>> get spectrumData {
    return [
      {'label': 'Words of Affirmation', 'value': words, 'key': 'words'},
      {'label': 'Quality Time', 'value': qualityTime, 'key': 'quality_time'},
      {'label': 'Receiving Gifts', 'value': gifts, 'key': 'gifts'},
      {'label': 'Acts of Service', 'value': acts, 'key': 'acts'},
      {'label': 'Physical Touch', 'value': touch, 'key': 'touch'},
    ]..sort((a, b) => b['value'].compareTo(a['value']));
  }

  String getPrimaryDisplay() {
    return _getDisplayName(primary);
  }

  String getSecondaryDisplay() {
    return _getDisplayName(secondary);
  }

  String _getDisplayName(String key) {
    switch (key) {
      case 'words': return 'Words of Affirmation';
      case 'quality_time': return 'Quality Time';
      case 'gifts': return 'Receiving Gifts';
      case 'acts': return 'Acts of Service';
      case 'touch': return 'Physical Touch';
      default: return key;
    }
  }

  String getDescription(String key) {
    switch (key) {
      case 'words':
        return 'You tend to feel most loved through words — hearing appreciation, encouragement, and "I love you."';
      case 'quality_time':
        return 'You tend to feel most loved through undivided attention — being truly present with your partner.';
      case 'gifts':
        return 'You tend to feel most loved through thoughtful gifts — the effort and thought behind them matters most.';
      case 'acts':
        return 'You tend to feel most loved through actions — when your partner does something helpful or supportive.';
      case 'touch':
        return 'You tend to feel most loved through physical affection — touch, hugs, and closeness.';
      default:
        return '';
    }
  }

  @override
  List<Object?> get props => [
    words,
    qualityTime,
    gifts,
    acts,
    touch,
    primary,
    secondary,
    completedAt,
  ];
}

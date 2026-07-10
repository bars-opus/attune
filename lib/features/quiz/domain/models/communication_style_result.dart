// lib/features/quiz/domain/models/communication_style_result.dart

import 'package:equatable/equatable.dart';

class CommunicationStyleResult extends Equatable {
  static const Map<String, int> _canonicalOrder = {
    'assertive': 0,
    'passive': 1,
    'aggressive': 2,
    'passive_aggressive': 3,
  };

  final int assertive;
  final int passive;
  final int aggressive;
  final int passiveAggressive;
  final String primary;
  final String secondary;
  final int separation;
  final int instrumentVersion;
  final int resultVersion;
  final DateTime? completedAt;

  const CommunicationStyleResult({
    required this.assertive,
    required this.passive,
    required this.aggressive,
    required this.passiveAggressive,
    required this.primary,
    required this.secondary,
    required this.separation,
    this.instrumentVersion = 1,
    this.resultVersion = 1,
    this.completedAt,
  });

  factory CommunicationStyleResult.fromJson(Map<String, dynamic> json) {
    return CommunicationStyleResult(
      assertive: json['assertive'] ?? 0,
      passive: json['passive'] ?? 0,
      aggressive: json['aggressive'] ?? 0,
      passiveAggressive: json['passive_aggressive'] ?? 0,
      primary: json['primary'] ?? 'assertive',
      secondary: json['secondary'] ?? 'passive',
      separation: json['separation'] ?? 0,
      instrumentVersion: json['instrument_version'] ?? 1,
      resultVersion: json['result_version'] ?? 1,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'assertive': assertive,
      'passive': passive,
      'aggressive': aggressive,
      'passive_aggressive': passiveAggressive,
      'primary': primary,
      'secondary': secondary,
      'separation': separation,
      'instrument_version': instrumentVersion,
      'result_version': resultVersion,
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  CommunicationStyleResult copyWith({
    int? assertive,
    int? passive,
    int? aggressive,
    int? passiveAggressive,
    String? primary,
    String? secondary,
    int? separation,
    int? instrumentVersion,
    int? resultVersion,
    DateTime? completedAt,
  }) {
    return CommunicationStyleResult(
      assertive: assertive ?? this.assertive,
      passive: passive ?? this.passive,
      aggressive: aggressive ?? this.aggressive,
      passiveAggressive: passiveAggressive ?? this.passiveAggressive,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      separation: separation ?? this.separation,
      instrumentVersion: instrumentVersion ?? this.instrumentVersion,
      resultVersion: resultVersion ?? this.resultVersion,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  List<Map<String, dynamic>> get spectrumData {
    return [
      {'label': 'Assertive', 'value': assertive, 'key': 'assertive'},
      {'label': 'Passive', 'value': passive, 'key': 'passive'},
      {'label': 'Aggressive', 'value': aggressive, 'key': 'aggressive'},
      {'label': 'Passive-Aggressive', 'value': passiveAggressive, 'key': 'passive_aggressive'},
    ]..sort((a, b) {
      final valueCompare = (b['value'] as int).compareTo(a['value'] as int);
      if (valueCompare != 0) {
        return valueCompare;
      }

      return _canonicalOrder[a['key']]!.compareTo(_canonicalOrder[b['key']]!);
    });
  }

  bool get isMixed => separation < 10;
  bool get isTie => separation == 0;

  String getPrimaryDisplay() {
    return _getDisplayName(primary);
  }

  String getSecondaryDisplay() {
    return _getDisplayName(secondary);
  }

  String getMixedDisplay() {
    return 'Mixed: ${getPrimaryDisplay()} + ${getSecondaryDisplay()}';
  }

  String _getDisplayName(String key) {
    switch (key) {
      case 'assertive': return 'Assertive';
      case 'passive': return 'Passive';
      case 'aggressive': return 'Aggressive';
      case 'passive_aggressive': return 'Passive-Aggressive';
      default: return key;
    }
  }

  String getSummary() {
    if (isTie) {
      return 'Your answers show a mixed pattern, with ${getPrimaryDisplay()} and ${getSecondaryDisplay()} tied.';
    }
    if (isMixed) {
      return 'Your answers show a mixed pattern, with ${getPrimaryDisplay()} and ${getSecondaryDisplay()} close together.';
    }
    return 'Your answers lean most toward ${getPrimaryDisplay()}, with ${getSecondaryDisplay()} also present.';
  }

  String getDescription() {
    switch (primary) {
      case 'assertive':
        return 'Your answers suggest you often try to express needs directly while making room for the other person\'s perspective.';
      case 'passive':
        return 'Your answers suggest you may sometimes hold back needs or disagreement, especially when speaking up feels difficult.';
      case 'aggressive':
        return 'Your answers suggest that strong feelings may sometimes come through as interruption, accusation, or forceful language. This is a pattern to notice, not a judgment about you.';
      case 'passive_aggressive':
        return 'Your answers suggest that frustration may sometimes come out indirectly rather than being named openly. This is a pattern to notice, not a fixed label.';
      default:
        return '';
    }
  }

  @override
  List<Object?> get props => [
    assertive,
    passive,
    aggressive,
    passiveAggressive,
    primary,
    secondary,
    separation,
    instrumentVersion,
    resultVersion,
    completedAt,
  ];
}

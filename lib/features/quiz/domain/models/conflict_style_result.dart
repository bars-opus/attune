// lib/features/quiz/domain/models/conflict_style_result.dart

import 'package:equatable/equatable.dart';

class ConflictStyleResult extends Equatable {
  static const _canonicalOrder = <String, int>{
    'collaborating': 0,
    'competing': 1,
    'avoiding': 2,
    'accommodating': 3,
    'compromising': 4,
  };

  final int collaborating;
  final int competing;
  final int avoiding;
  final int accommodating;
  final int compromising;
  final String primary;
  final String secondary;
  final int separation;
  final int instrumentVersion;
  final int resultVersion;
  final DateTime? completedAt;

  const ConflictStyleResult({
    required this.collaborating,
    required this.competing,
    required this.avoiding,
    required this.accommodating,
    required this.compromising,
    required this.primary,
    required this.secondary,
    required this.separation,
    this.instrumentVersion = 1,
    this.resultVersion = 1,
    this.completedAt,
  });

  factory ConflictStyleResult.fromJson(Map<String, dynamic> json) {
    int readScore(String key) => (json[key] as num?)?.round() ?? 0;

    return ConflictStyleResult(
      collaborating: readScore('collaborating'),
      competing: readScore('competing'),
      avoiding: readScore('avoiding'),
      accommodating: readScore('accommodating'),
      compromising: readScore('compromising'),
      primary: json['primary'] ?? 'collaborating',
      secondary: json['secondary'] ?? 'compromising',
      separation: json['separation'] ?? 0,
      instrumentVersion: json['instrument_version'] ?? 1,
      resultVersion: json['result_version'] ?? 1,
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
    );
  }

  ConflictStyleResult copyWith({int? resultVersion, DateTime? completedAt}) {
    return ConflictStyleResult(
      collaborating: collaborating,
      competing: competing,
      avoiding: avoiding,
      accommodating: accommodating,
      compromising: compromising,
      primary: primary,
      secondary: secondary,
      separation: separation,
      instrumentVersion: instrumentVersion,
      resultVersion: resultVersion ?? this.resultVersion,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'collaborating': collaborating,
      'competing': competing,
      'avoiding': avoiding,
      'accommodating': accommodating,
      'compromising': compromising,
      'primary': primary,
      'secondary': secondary,
      'separation': separation,
      'instrument_version': instrumentVersion,
      'result_version': resultVersion,
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  List<Map<String, dynamic>> get spectrumData {
    return [
      {
        'label': 'Collaborating',
        'value': collaborating,
        'key': 'collaborating',
      },
      {'label': 'Competing', 'value': competing, 'key': 'competing'},
      {'label': 'Avoiding', 'value': avoiding, 'key': 'avoiding'},
      {
        'label': 'Accommodating',
        'value': accommodating,
        'key': 'accommodating',
      },
      {'label': 'Compromising', 'value': compromising, 'key': 'compromising'},
    ]..sort((a, b) {
      final scoreOrder = (b['value'] as int).compareTo(a['value'] as int);
      if (scoreOrder != 0) return scoreOrder;
      return _canonicalOrder[a['key']]!.compareTo(_canonicalOrder[b['key']]!);
    });
  }

  bool get isMixed => separation > 0 && separation < 10;
  bool get isTied => separation == 0;

  String getPrimaryDisplay() {
    return _getDisplayName(primary);
  }

  String getSecondaryDisplay() {
    return _getDisplayName(secondary);
  }

  String getMixedDisplay() {
    if (isTied) {
      return 'Tied: ${getPrimaryDisplay()} + ${getSecondaryDisplay()}';
    }
    return 'Mixed: ${getPrimaryDisplay()} + ${getSecondaryDisplay()}';
  }

  String _getDisplayName(String key) {
    switch (key) {
      case 'collaborating':
        return 'Collaborating';
      case 'competing':
        return 'Competing';
      case 'avoiding':
        return 'Avoiding';
      case 'accommodating':
        return 'Accommodating';
      case 'compromising':
        return 'Compromising';
      default:
        return key;
    }
  }

  String getSummary() {
    if (isTied) {
      return 'Your answers place ${getPrimaryDisplay()} and ${getSecondaryDisplay()} tied at the top.';
    }
    if (isMixed) {
      return 'Your answers show a mixed pattern, with ${getPrimaryDisplay()} and ${getSecondaryDisplay()} close together.';
    }
    return 'Your answers lean most toward ${getPrimaryDisplay()}, with ${getSecondaryDisplay()} also present.';
  }

  String getDescription() {
    switch (primary) {
      case 'collaborating':
        return 'Your answers suggest you often try to understand the concerns involved and work toward a solution that addresses important needs on each side.';
      case 'competing':
        return 'Your answers suggest you may press firmly for your preferred outcome, especially when the issue, timing, or principle feels important.';
      case 'avoiding':
        return 'Your answers suggest you may sometimes step back, postpone, or leave a disagreement alone. Context and safety can shape when this feels available or protective.';
      case 'accommodating':
        return 'Your answers suggest you may sometimes set aside your preference to support harmony or the other person\'s concerns.';
      case 'compromising':
        return 'Your answers suggest you often look for a workable middle ground in which each person adjusts something.';
      default:
        return '';
    }
  }

  @override
  List<Object?> get props => [
    collaborating,
    competing,
    avoiding,
    accommodating,
    compromising,
    primary,
    secondary,
    separation,
    instrumentVersion,
    resultVersion,
    completedAt,
  ];
}

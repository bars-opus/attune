// lib/features/quiz/domain/models/love_language_result.dart
//
// Spec 5 (R5-5, research 06 A2): "What feels loving to me right now". Five
// ways, each rated not really / a little / a lot, with optional moments it
// applies to. No primary, no type, changeable at any time. Stored with
// `instrument_version: 2`; a v1 (15-question, percentage) result is read
// through [LoveLanguageResult.fromJson] and its typology dropped.

import 'package:equatable/equatable.dart';

enum LovingWay {
  words('words', 'Words'),
  time('time', 'Time together'),
  help('help', 'Help'),
  touch('touch', 'Touch'),
  gifts('gifts', 'Small gifts');

  const LovingWay(this.key, this.label);
  final String key;
  final String label;
}

enum LovingRating {
  notReally('not_really', 'Not really'),
  aLittle('a_little', 'A little'),
  aLot('a_lot', 'A lot');

  const LovingRating(this.key, this.label);
  final String key;
  final String label;
}

enum LovingMoment {
  stressed('stressed', 'When stressed'),
  sad('sad', 'When sad'),
  celebrating('celebrating', 'When celebrating'),
  everyday('everyday', 'Everyday');

  const LovingMoment(this.key, this.label);
  final String key;
  final String label;
}

class LoveLanguageResult extends Equatable {
  const LoveLanguageResult({
    required this.ratings,
    required this.moments,
    required this.updatedAt,
    this.fromEarlierVersion = false,
  });

  static const int instrumentVersion = 2;
  static const String frameworkNote =
      'Based on a popular framework, not a science.';

  final Map<LovingWay, LovingRating> ratings;
  final Set<LovingMoment> moments;
  final DateTime updatedAt;

  /// Read from a v1 result: ratings approximated from its percentages.
  final bool fromEarlierVersion;

  factory LoveLanguageResult.fromJson(Map<String, dynamic> json) {
    if (json['instrument_version'] == instrumentVersion) {
      final raw = Map<String, dynamic>.from(json['ratings'] as Map? ?? {});
      return LoveLanguageResult(
        ratings: {
          for (final way in LovingWay.values)
            if (_rating(raw[way.key]) case final r?) way: r,
        },
        moments: {
          for (final m in (json['moments'] as List? ?? const []))
            ...LovingMoment.values.where((x) => x.key == m),
        },
        updatedAt:
            DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
    // v1: five percentages summing to 100 (an even spread is 20 each).
    LovingRating fromShare(Object? v) {
      final n = (v as num?) ?? 0;
      if (n >= 25) return LovingRating.aLot;
      if (n >= 15) return LovingRating.aLittle;
      return LovingRating.notReally;
    }

    return LoveLanguageResult(
      ratings: {
        LovingWay.words: fromShare(json['words']),
        LovingWay.time: fromShare(json['quality_time']),
        LovingWay.help: fromShare(json['acts']),
        LovingWay.touch: fromShare(json['touch']),
        LovingWay.gifts: fromShare(json['gifts']),
      },
      moments: const {},
      updatedAt:
          DateTime.tryParse(json['completed_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      fromEarlierVersion: true,
    );
  }

  static LovingRating? _rating(Object? key) {
    for (final r in LovingRating.values) {
      if (r.key == key) return r;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'instrument_version': instrumentVersion,
    'ratings': {for (final e in ratings.entries) e.key.key: e.value.key},
    'moments': [
      for (final m in LovingMoment.values)
        if (moments.contains(m)) m.key,
    ],
    'updated_at': updatedAt.toIso8601String(),
  };

  /// The ways rated [rating], in a fixed order.
  List<LovingWay> rated(LovingRating rating) => [
    for (final way in LovingWay.values)
      if (ratings[way] == rating) way,
  ];

  /// One line for a list row: what helps a lot (never a type).
  String get summary {
    final lot = rated(LovingRating.aLot);
    if (lot.isNotEmpty) {
      return 'A lot: ${lot.map((w) => w.label.toLowerCase()).join(', ')}';
    }
    final little = rated(LovingRating.aLittle);
    if (little.isNotEmpty) {
      return 'A little: ${little.map((w) => w.label.toLowerCase()).join(', ')}';
    }
    return 'Not set yet';
  }

  @override
  List<Object?> get props => [
    ratings.entries.map((e) => '${e.key.key}=${e.value.key}').toList()..sort(),
    moments.map((m) => m.key).toList()..sort(),
    updatedAt,
    fromEarlierVersion,
  ];
}

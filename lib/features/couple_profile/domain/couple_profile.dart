import 'package:flutter/foundation.dart';

/// About us (Spec 1 §3.8 AU1-AU6, §4.2 `couple_profiles`): the couple's
/// shared answers, or one inviter's draft before linking. Plain facts the
/// couple chose to tell, each attributed. Never a type, a score or a label
/// (permanent constraint): nothing here derives anything from the answers,
/// and test/architecture/couple_profile_never_typed_test.dart keeps every
/// reader of this model inside lib/features/couple_profile/.

/// AU1 · Where the two of you are.
enum CoupleStage {
  dating('dating'),
  engaged('engaged'),
  married('married'),
  other('other');

  const CoupleStage(this.wire);

  final String wire;

  static CoupleStage? fromWire(Object? value) {
    for (final stage in values) {
      if (stage.wire == value) return stage;
    }
    return null;
  }
}

/// AU2 · How much of "When did you two get together?" was given.
enum DatePrecision {
  day,
  month,
  year;

  String get wire => name;

  static DatePrecision? fromWire(Object? value) {
    for (final precision in values) {
      if (precision.wire == value) return precision;
    }
    return null;
  }
}

/// AU3 · An optional label for a ceremony.
enum CeremonyLabel {
  customary,
  church,
  mosque,
  civil,
  other;

  String get wire => name;

  static CeremonyLabel? fromWire(Object? value) {
    for (final label in values) {
      if (label.wire == value) return label;
    }
    return null;
  }
}

/// AU4 · Where the two of you live. No option ranks above another.
enum Living {
  together('together'),
  apartNearby('apart_nearby'),
  longDistance('long_distance');

  const Living(this.wire);

  final String wire;

  static Living? fromWire(Object? value) {
    for (final living in values) {
      if (living.wire == value) return living;
    }
    return null;
  }
}

/// AU5 · Children in your life together. No names, counts or "yet".
enum Children {
  none('none'),
  yes('yes'),
  expecting('expecting'),
  preferNotToSay('prefer_not_to_say');

  const Children(this.wire);

  final String wire;

  static Children? fromWire(Object? value) {
    for (final children in values) {
      if (children.wire == value) return children;
    }
    return null;
  }
}

/// AU5 · Their ages, as bands, only with [Children.yes].
enum ChildAgeBand {
  under2('under2'),
  twoToFive('2to5'),
  sixToTwelve('6to12'),
  thirteenToSeventeen('13to17'),
  eighteenPlus('18plus');

  const ChildAgeBand(this.wire);

  final String wire;

  static ChildAgeBand? fromWire(Object? value) {
    for (final band in values) {
      if (band.wire == value) return band;
    }
    return null;
  }
}

/// AU6 · The one source of Together's anniversary reminder.
enum AnniversarySource {
  off('off'),
  togetherSince('together_since'),
  ceremony1('ceremony_1'),
  ceremony2('ceremony_2');

  const AnniversarySource(this.wire);

  final String wire;

  static AnniversarySource fromWire(Object? value) {
    for (final source in values) {
      if (source.wire == value) return source;
    }
    return off;
  }
}

/// The six attributed fields (one "Changed by" line each).
enum AboutUsField {
  togetherSince('together_since'),
  stage('stage'),
  ceremonies('ceremonies'),
  living('living'),
  children('children'),
  anniversary('anniversary');

  const AboutUsField(this.wire);

  final String wire;
}

/// `YYYY-MM-DD` for a civil date (no time, no zone).
String aboutUsWireDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// A real civil date, or null: 30 February, 29 February outside a leap
/// year, month 13 or day 0 are refused, never rolled over to another day
/// as `DateTime(y, m, d)` would (batch-3 fix round 1, M-4).
DateTime? civilDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) return null;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

final _wireDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// `YYYY-MM-DD` (a longer ISO string is read by its date part), strictly.
DateTime? _civilDate(Object? value) {
  if (value is! String) return null;
  final match = _wireDate.firstMatch(value);
  if (match == null) return null;
  return civilDate(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// AU1's "Something else" words: at most this many characters, counted as
/// the server's `char_length` counts them (code points, not what the eye
/// sees as one character: an emoji family is five).
const stageWordsMax = 40;

final _controls = RegExp('[\x00-\x1F\x7F-\x9F]');
final _edgeSpaces = RegExp(r'^ +| +$');

/// The words as the server keeps them (update_couple_profile: control
/// characters become spaces, then spaces are trimmed; empty is none).
String? normalizeStageWords(String? words) {
  if (words == null) return null;
  final cleaned = words.replaceAll(_controls, ' ').replaceAll(_edgeSpaces, '');
  return cleaned.isEmpty ? null : cleaned;
}

/// True when the server will take [words] (batch-3 fix round 1, M-5).
bool stageWordsFit(String words) =>
    (normalizeStageWords(words)?.runes.length ?? 0) <= stageWordsMax;

/// True when [date] is after [today] (both civil dates): AU2 and AU3 never
/// take one ("That date is in the future.").
bool isFutureCivilDate(DateTime date, DateTime today) => DateTime(
  date.year,
  date.month,
  date.day,
).isAfter(DateTime(today.year, today.month, today.day));

/// AU2's answer. The server keeps a month as its 1st and a year as 1 January.
@immutable
class TogetherSince {
  const TogetherSince(this.date, this.precision);

  final DateTime date;
  final DatePrecision precision;

  /// A full date, as AU6 needs.
  bool get hasDay => precision == DatePrecision.day;

  @override
  bool operator ==(Object other) =>
      other is TogetherSince &&
      other.precision == precision &&
      aboutUsWireDate(other.date) == aboutUsWireDate(date);

  @override
  int get hashCode => Object.hash(aboutUsWireDate(date), precision);
}

/// AU3's answer: a year, an optional month and day, an optional label.
@immutable
class Ceremony {
  const Ceremony({required this.year, this.month, this.day, this.label});

  final int year;
  final int? month;
  final int? day;
  final CeremonyLabel? label;

  /// A full date, as AU6 needs; null without a month and a day.
  DateTime? get fullDate =>
      month == null || day == null ? null : civilDate(year, month!, day!);

  Map<String, Object?> toJson() => {
    'year': year,
    if (month != null) 'month': month,
    if (day != null) 'day': day,
    if (label != null) 'label': label!.wire,
  };

  static Ceremony? fromJson(Object? json) {
    if (json is! Map) return null;
    final year = json['year'];
    if (year is! int) return null;
    final month = json['month'];
    final day = json['day'];
    return Ceremony(
      year: year,
      month: month is int ? month : null,
      day: day is int ? day : null,
      label: CeremonyLabel.fromWire(json['label']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Ceremony &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.label == label;

  @override
  int get hashCode => Object.hash(year, month, day, label);
}

/// Who last changed a field and when: the server sends a first name or
/// "me", never an account id (spec §4.3 W5).
@immutable
class FieldChange {
  const FieldChange({required this.byMe, this.byFirstName, required this.at});

  final bool byMe;
  final String? byFirstName;
  final DateTime at;

  static FieldChange? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['changed_at'];
    final parsed = at is String ? DateTime.tryParse(at) : null;
    if (parsed == null) return null;
    final name = (json['changed_by_first_name'] as String?)?.trim();
    return FieldChange(
      byMe: json['changed_by_me'] == true,
      byFirstName: name == null || name.isEmpty ? null : name,
      at: parsed.toLocal(),
    );
  }
}

/// get_couple_profile() or get_my_couple_profile_draft() (spec §4.3 W5).
@immutable
class CoupleProfile {
  const CoupleProfile({
    this.isDraft = false,
    this.readOnly = false,
    this.readUntil,
    this.togetherSince,
    this.stage,
    this.stageWords,
    this.ceremonies = const [],
    this.living,
    this.children,
    this.childAgeBands = const [],
    this.anniversarySource = AnniversarySource.off,
    this.anniversaryReminderId,
    this.changes = const {},
    this.pendingSync = false,
  });

  static const emptyDraft = CoupleProfile(isDraft: true);

  final bool isDraft;

  /// Paused or inside the ending window: read, never written.
  final bool readOnly;

  /// When a read-only profile goes ("You can read this until {date}.").
  final DateTime? readUntil;
  final TogetherSince? togetherSince;
  final CoupleStage? stage;
  final String? stageWords;
  final List<Ceremony> ceremonies;
  final Living? living;
  final Children? children;
  final List<ChildAgeBand> childAgeBands;
  final AnniversarySource anniversarySource;

  /// The one Together reminder About us keeps (its sheet points back here).
  final String? anniversaryReminderId;
  final Map<AboutUsField, FieldChange> changes;

  /// An answer given offline that hasn't reached the server yet.
  final bool pendingSync;

  /// No question answered yet.
  bool get isEmpty =>
      togetherSince == null &&
      stage == null &&
      ceremonies.isEmpty &&
      living == null &&
      children == null &&
      anniversarySource == AnniversarySource.off;

  /// The date the anniversary reminder follows, when it has a full date.
  DateTime? get anniversaryDate => switch (anniversarySource) {
    AnniversarySource.off => null,
    AnniversarySource.togetherSince =>
      togetherSince != null && togetherSince!.hasDay
          ? togetherSince!.date
          : null,
    AnniversarySource.ceremony1 =>
      ceremonies.isNotEmpty ? ceremonies[0].fullDate : null,
    AnniversarySource.ceremony2 =>
      ceremonies.length > 1 ? ceremonies[1].fullDate : null,
  };

  factory CoupleProfile.fromJson(Map<String, dynamic> json) {
    final since = _civilDate(json['together_since']);
    final precision = DatePrecision.fromWire(json['together_since_precision']);
    final rawCeremonies = json['ceremonies'];
    final rawBands = json['child_age_bands'];
    final rawChanges = json['changes'];
    final readUntil = json['read_until'];
    return CoupleProfile(
      isDraft: json['draft'] == true,
      readOnly: json['read_only'] == true,
      readUntil:
          readUntil is String ? DateTime.tryParse(readUntil)?.toLocal() : null,
      togetherSince:
          since == null || precision == null
              ? null
              : TogetherSince(since, precision),
      stage: CoupleStage.fromWire(json['stage']),
      stageWords: json['stage_words'] as String?,
      ceremonies: [
        if (rawCeremonies is List)
          for (final item in rawCeremonies)
            if (Ceremony.fromJson(item) case final ceremony?) ceremony,
      ],
      living: Living.fromWire(json['living']),
      children: Children.fromWire(json['children']),
      childAgeBands: [
        if (rawBands is List)
          for (final band in rawBands)
            if (ChildAgeBand.fromWire(band) case final known?) known,
      ],
      anniversarySource: AnniversarySource.fromWire(json['anniversary_source']),
      anniversaryReminderId: json['anniversary_reminder_id'] as String?,
      changes: {
        if (rawChanges is Map)
          for (final field in AboutUsField.values)
            if (FieldChange.fromJson(rawChanges[field.wire]) case final c?)
              field: c,
      },
    );
  }

  /// [patch] applied the way update_couple_profile applies it, for an
  /// answer queued offline (spec §3.8: offline edits queue and replay). The
  /// server's answer replaces this once it arrives.
  CoupleProfile applying(AboutUsPatch patch) {
    final v = patch.values;
    var since = togetherSince;
    if (v.containsKey('together_since')) {
      final date = _civilDate(v['together_since']);
      final precision = DatePrecision.fromWire(v['together_since_precision']);
      since =
          date == null || precision == null
              ? null
              : TogetherSince(switch (precision) {
                DatePrecision.day => date,
                DatePrecision.month => DateTime(date.year, date.month),
                DatePrecision.year => DateTime(date.year),
              }, precision);
    }
    var nextStage = stage;
    var words = stageWords;
    if (v.containsKey('stage')) {
      nextStage = CoupleStage.fromWire(v['stage']);
      words =
          nextStage == CoupleStage.other
              ? normalizeStageWords(v['stage_words'] as String?)
              : null;
    }
    var nextCeremonies = ceremonies;
    if (v.containsKey('ceremonies')) {
      final raw = v['ceremonies'];
      nextCeremonies = [
        if (raw is List)
          for (final item in raw)
            if (Ceremony.fromJson(item) case final ceremony?) ceremony,
      ];
    } else if (nextStage != CoupleStage.married) {
      nextCeremonies = const [];
    }
    var nextChildren = children;
    var bands = childAgeBands;
    if (v.containsKey('children')) {
      nextChildren = Children.fromWire(v['children']);
      final raw = v['child_age_bands'];
      bands =
          nextChildren == Children.yes && raw is List
              ? [
                for (final band in raw)
                  if (ChildAgeBand.fromWire(band) case final known?) known,
              ]
              : const [];
    }
    var source = anniversarySource;
    if (v.containsKey('anniversary_source')) {
      source = AnniversarySource.fromWire(v['anniversary_source']);
    }
    if ((source == AnniversarySource.ceremony1 && nextCeremonies.isEmpty) ||
        (source == AnniversarySource.ceremony2 && nextCeremonies.length < 2)) {
      source = AnniversarySource.off;
    }
    return CoupleProfile(
      isDraft: isDraft,
      readOnly: readOnly,
      readUntil: readUntil,
      togetherSince: since,
      stage: nextStage,
      stageWords: words,
      ceremonies: nextCeremonies,
      living: v.containsKey('living') ? Living.fromWire(v['living']) : living,
      children: nextChildren,
      childAgeBands: bands,
      anniversarySource: source,
      anniversaryReminderId: anniversaryReminderId,
      changes: changes,
      pendingSync: true,
    );
  }
}

/// One answer as update_couple_profile / update_my_couple_profile_draft
/// take it (`p_patch`): only the keys of the question answered.
@immutable
class AboutUsPatch {
  const AboutUsPatch(this.values);

  final Map<String, Object?> values;

  /// AU1. [words] only with [CoupleStage.other] (40 characters).
  factory AboutUsPatch.stage(CoupleStage? stage, {String? words}) =>
      AboutUsPatch({
        'stage': stage?.wire,
        'stage_words': stage == CoupleStage.other ? words : null,
      });

  /// AU2; null clears it.
  factory AboutUsPatch.togetherSince(TogetherSince? since) => AboutUsPatch({
    'together_since': since == null ? null : aboutUsWireDate(since.date),
    'together_since_precision': since?.precision.wire,
  });

  /// AU3: at most two.
  factory AboutUsPatch.ceremonies(List<Ceremony> ceremonies) => AboutUsPatch({
    'ceremonies': [for (final c in ceremonies) c.toJson()],
  });

  /// AU4.
  factory AboutUsPatch.living(Living? living) =>
      AboutUsPatch({'living': living?.wire});

  /// AU5: the bands only with [Children.yes].
  factory AboutUsPatch.children(
    Children? children, {
    List<ChildAgeBand> bands = const [],
  }) => AboutUsPatch({
    'children': children?.wire,
    'child_age_bands':
        children == Children.yes ? [for (final b in bands) b.wire] : <String>[],
  });

  /// AU6, with the full date AU6's "What day was it?" just completed, if
  /// any, in the same write.
  factory AboutUsPatch.anniversary(
    AnniversarySource source, {
    TogetherSince? completedSince,
    List<Ceremony>? completedCeremonies,
  }) => AboutUsPatch({
    if (completedSince != null)
      ...AboutUsPatch.togetherSince(completedSince).values,
    if (completedCeremonies != null)
      ...AboutUsPatch.ceremonies(completedCeremonies).values,
    'anniversary_source': source.wire,
  });

  /// Batch-3 fix round 1 (ruling I-4, as adopt_couple_profile_drafts
  /// adopts a draft at accept): this patch's answers for the fields of
  /// [shared] the partner didn't change last, and none the shared profile
  /// can't take (ceremonies without Married, an anniversary without a full
  /// date). Null when nothing is left.
  ///
  /// Fix round 4 (ruling NI-3): a field with no change line, or one this
  /// person changed last (their own draft answer, adopted at the accept),
  /// takes the answer; a field the partner changed last, set or cleared,
  /// keeps the partner's answer.
  AboutUsPatch? onlyUnsetIn(CoupleProfile shared) {
    final out = <String, Object?>{};
    void take(AboutUsField field, List<String> keys) {
      if (shared.changes[field]?.byMe == false) return;
      for (final key in keys) {
        if (values.containsKey(key)) out[key] = values[key];
      }
    }

    take(AboutUsField.togetherSince, const [
      'together_since',
      'together_since_precision',
    ]);
    take(AboutUsField.stage, const ['stage', 'stage_words']);
    take(AboutUsField.ceremonies, const ['ceremonies']);
    take(AboutUsField.living, const ['living']);
    take(AboutUsField.children, const ['children', 'child_age_bands']);
    take(AboutUsField.anniversary, const ['anniversary_source']);
    if (out.containsKey('ceremonies') &&
        shared.applying(AboutUsPatch(out)).stage != CoupleStage.married) {
      out.remove('ceremonies');
    }
    if (AnniversarySource.fromWire(out['anniversary_source']) !=
            AnniversarySource.off &&
        shared.applying(AboutUsPatch(out)).anniversaryDate == null) {
      out.remove('anniversary_source');
    }
    return out.isEmpty ? null : AboutUsPatch(out);
  }

  static AboutUsPatch? fromJson(Object? json) =>
      json is Map ? AboutUsPatch(Map<String, Object?>.from(json)) : null;

  /// [later]'s keys win: the last write wins (spec §3.8).
  AboutUsPatch merge(AboutUsPatch later) =>
      AboutUsPatch({...values, ...later.values});
}

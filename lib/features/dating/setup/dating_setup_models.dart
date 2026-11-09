// Spec 2 W3b (§3.2 D2-D8): the setup lists (get_dating_setup_lists) and the
// person's own answers (get_my_dating_profile), in memory only.
import 'package:flutter/foundation.dart' show listEquals;

class DatingOption {
  const DatingOption({required this.code, required this.nameKey});

  final String code;
  final String nameKey;

  static List<DatingOption> listOf(Object? raw) => [
    if (raw is List)
      for (final o in raw.whereType<Map>())
        if (o['code'] is String && o['name_key'] is String)
          DatingOption(
            code: o['code'] as String,
            nameKey: o['name_key'] as String,
          ),
  ];
}

class DatingRegion {
  const DatingRegion({
    required this.code,
    required this.nameKey,
    required this.open,
    this.sides = const [],
  });

  final String code;
  final String nameKey;
  final bool open;
  final List<DatingOption> sides;
}

class DatingFaith {
  const DatingFaith({
    required this.code,
    required this.nameKey,
    this.denominations = const [],
  });

  final String code;
  final String nameKey;
  final List<DatingOption> denominations;
}

class DatingCountryLists {
  const DatingCountryLists({
    required this.code,
    required this.sameGender,
    this.regions = const [],
    this.faiths = const [],
  });

  final String code;
  final bool sameGender;
  final List<DatingRegion> regions;
  final List<DatingFaith> faiths;

  DatingRegion? region(String? code) {
    for (final r in regions) {
      if (r.code == code) return r;
    }
    return null;
  }
}

class DatingSetupLists {
  const DatingSetupLists({
    this.countries = const [],
    this.phoneCountry,
    this.noteCountry,
    this.defaultAges = (18, 99),
  });

  final List<DatingCountryLists> countries;
  final String? phoneCountry;
  final String? noteCountry;
  final (int, int) defaultAges;

  DatingCountryLists? country(String? code) {
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  factory DatingSetupLists.fromJson(Map<String, dynamic> json) {
    final ages = json['default_ages'];
    return DatingSetupLists(
      countries: [
        if (json['countries'] is List)
          for (final c in (json['countries'] as List).whereType<Map>())
            if (c['code'] is String)
              DatingCountryLists(
                code: c['code'] as String,
                sameGender: c['same_gender'] == true,
                regions: [
                  if (c['regions'] is List)
                    for (final r in (c['regions'] as List).whereType<Map>())
                      if (r['code'] is String && r['name_key'] is String)
                        DatingRegion(
                          code: r['code'] as String,
                          nameKey: r['name_key'] as String,
                          open: r['open'] == true,
                          sides: DatingOption.listOf(r['sides']),
                        ),
                ],
                faiths: [
                  if (c['faiths'] is List)
                    for (final f in (c['faiths'] as List).whereType<Map>())
                      if (f['code'] is String && f['name_key'] is String)
                        DatingFaith(
                          code: f['code'] as String,
                          nameKey: f['name_key'] as String,
                          denominations: DatingOption.listOf(
                            f['denominations'],
                          ),
                        ),
                ],
              ),
      ],
      phoneCountry:
          json['phone_country'] is String
              ? json['phone_country'] as String
              : null,
      noteCountry:
          json['note_country'] is String
              ? json['note_country'] as String
              : null,
      defaultAges:
          ages is List && ages.length == 2 && ages[0] is int && ages[1] is int
              ? (ages[0] as int, ages[1] as int)
              : (18, 99),
    );
  }
}

/// What a [DatingMyProfile] prints, whatever it holds (T5 fix round 2).
const datingMyProfileText = 'DatingMyProfile(…)';

/// The person's own answers (get_my_dating_profile), for prefilling a step.
class DatingMyProfile {
  const DatingMyProfile({
    this.intention,
    this.marriageTimeline,
    this.timelineVisible = true,
    this.attested = false,
    this.marital,
    this.maritalVisible = false,
    this.countryCode,
    this.regionCode,
    this.sideCode,
    this.regionScope,
    this.identity,
    this.specific,
    this.specificText,
    this.pronouns,
    this.pools = const [],
    this.genderVisible = false,
    this.seeking = const [],
    this.minAge,
    this.maxAge,
    this.childrenHave,
    this.childrenWant,
    this.wantMustMatch = false,
    this.excludeParents = false,
    this.faith,
    this.denomination,
    this.importance,
    this.faithVisible = false,
    this.displayName,
    this.prompts = const [],
    this.dropTime,
    this.digestPush = false,
    this.chatPush = true,
    this.dataSaver = false,
    this.photosAfterMutual = false,
    this.exists = true,
  });

  final String? intention;
  final String? marriageTimeline;
  final bool timelineVisible;
  final bool attested;
  final String? marital;
  final bool maritalVisible;
  final String? countryCode;
  final String? regionCode;
  final String? sideCode;
  final String? regionScope;
  final String? identity;
  final String? specific;
  final String? specificText;
  final String? pronouns;
  final List<String> pools;
  final bool genderVisible;
  final List<String> seeking;
  final int? minAge;
  final int? maxAge;
  final bool? childrenHave;
  final String? childrenWant;
  final bool wantMustMatch;
  final bool excludeParents;
  final String? faith;
  final String? denomination;
  final String? importance;
  final bool faithVisible;
  final String? displayName;
  final List<(String, String)> prompts;
  final String? dropTime;
  final bool digestPush;
  final bool chatPush;
  final bool dataSaver;
  final bool photosAfterMutual;

  /// Final fix (M-6): false when get_my_dating_profile() has no profile
  /// for the person (nothing saved yet), so no profile row is offered.
  final bool exists;

  factory DatingMyProfile.fromJson(Map<String, dynamic> p) {
    String? text(Object? v) => v is String ? v : null;
    Map<dynamic, dynamic> map(Object? v) => v is Map ? v : const {};
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];
    final identity = map(p['identity']);
    final faith = map(p['faith']);
    final prefs = map(p['preferences']);
    final settings = map(p['settings']);
    return DatingMyProfile(
      intention: text(p['intention']),
      marriageTimeline: text(p['marriage_timeline']),
      timelineVisible: p['timeline_visible'] != false,
      attested: p['attested'] == true,
      marital: text(p['marital']),
      maritalVisible: p['marital_visible'] == true,
      countryCode: text(p['country_code']),
      regionCode: text(p['region_code']),
      sideCode: text(p['side_code']),
      regionScope: text(prefs['region_scope']),
      identity: text(identity['identity']),
      specific: text(identity['specific']),
      specificText: text(identity['specific_text']),
      pronouns: text(identity['pronouns']),
      pools: strings(identity['pools']),
      genderVisible: p['gender_visible'] == true,
      seeking: strings(p['seeking']),
      minAge: prefs['min_age'] is int ? prefs['min_age'] as int : null,
      maxAge: prefs['max_age'] is int ? prefs['max_age'] as int : null,
      childrenHave:
          p['children_have'] is bool ? p['children_have'] as bool : null,
      childrenWant: text(p['children_want']),
      wantMustMatch: prefs['want_must_match'] == true,
      excludeParents: prefs['exclude_parents'] == true,
      faith: text(faith['faith']),
      denomination: text(faith['denomination']),
      importance: text(faith['importance']),
      faithVisible: p['faith_visible'] == true,
      displayName: text(p['display_name']),
      prompts: [
        if (p['prompts'] is List)
          for (final q in (p['prompts'] as List).whereType<Map>())
            if (q['prompt_id'] is String && q['answer'] is String)
              (q['prompt_id'] as String, q['answer'] as String),
      ],
      dropTime: text(settings['drop_time']),
      digestPush: settings['digest_push'] == true,
      chatPush: settings['chat_push'] != false,
      dataSaver: settings['data_saver'] == true,
      photosAfterMutual: p['photos_after_mutual'] == true,
    );
  }

  /// Every field, by name: equality compares all of them (T5 fix round 1).
  Map<String, Object?> get _fields => {
    'intention': intention,
    'marriageTimeline': marriageTimeline,
    'timelineVisible': timelineVisible,
    'attested': attested,
    'marital': marital,
    'maritalVisible': maritalVisible,
    'countryCode': countryCode,
    'regionCode': regionCode,
    'sideCode': sideCode,
    'regionScope': regionScope,
    'identity': identity,
    'specific': specific,
    'specificText': specificText,
    'pronouns': pronouns,
    'pools': pools,
    'genderVisible': genderVisible,
    'seeking': seeking,
    'minAge': minAge,
    'maxAge': maxAge,
    'childrenHave': childrenHave,
    'childrenWant': childrenWant,
    'wantMustMatch': wantMustMatch,
    'excludeParents': excludeParents,
    'faith': faith,
    'denomination': denomination,
    'importance': importance,
    'faithVisible': faithVisible,
    'displayName': displayName,
    'prompts': prompts,
    'dropTime': dropTime,
    'digestPush': digestPush,
    'chatPush': chatPush,
    'dataSaver': dataSaver,
    'photosAfterMutual': photosAfterMutual,
  };

  @override
  bool operator ==(Object other) {
    if (other is! DatingMyProfile) return false;
    final a = _fields;
    final b = other._fields;
    for (final name in a.keys) {
      final x = a[name];
      final y = b[name];
      if (x is List && y is List ? !listEquals(x, y) : x != y) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(
    _fields.values.map((v) => v is List ? Object.hashAll(v) : v),
  );

  /// Always the same text: no answer, and not even which answers exist
  /// (an identity detail, pronouns or a denomination is itself special
  /// category data), reaches a log line, a test failure or a crash report.
  @override
  String toString() => datingMyProfileText;
}

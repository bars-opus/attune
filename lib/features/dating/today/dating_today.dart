// Spec 2 W5b (§3.4, §3.5, §5.6): Today as the server sends it. Every field
// is read defensively: an unknown state is unavailable, a malformed card is
// dropped, and nothing here holds a date but when the next introductions
// arrive (no countdown, no expiry: Fable M8). Memory only (D20).
import 'package:attune/features/dating/card/dating_card.dart';

/// Task 6 ruling: a refusal is one of the server's fixed codes, or failed
/// (never a server's text). Today and the v2 read answer `paused` for a
/// paused person (Task 4 fix round 1, M-5): its own code, its own screen.
const datingTodayReasons = {
  'reverify_device',
  'paused',
  'not_eligible',
  'unavailable',
  'busy',
};

/// act_on_dating_introduction()'s fixed refusals (`busy` after its bounded
/// lock wait).
const datingActReasons = {
  'invalid',
  'reverify_device',
  'not_eligible',
  'introduction_unavailable',
  'rate_limited',
  'busy',
};

String _fixed(Object? reason, Set<String> codes) =>
    reason is String && codes.contains(reason) ? reason : 'failed';

int _position(Map p) => p['position'] is int ? p['position'] as int : 0;

enum DatingTodayState {
  beforeDrop('before_drop'),
  delivered('delivered'),
  empty('empty'),
  queueFull('queue_full'),
  pausedOpenChats('paused_open_chats'),
  coolOff('cool_off'),
  unavailable('unavailable');

  const DatingTodayState(this.wire);

  final String wire;

  static DatingTodayState fromWire(Object? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => DatingTodayState.unavailable,
  );
}

/// One introduction: the card, its reason ids, the photos' spoken labels
/// and the viewer's own answer (never the other person's).
class DatingIntroCard {
  const DatingIntroCard({
    required this.id,
    required this.card,
    this.reasons = const [],
    this.sideNameKey,
    this.captions = const [],
    this.photoPositions = const [],
    this.acted,
  });

  final String id;
  final DatingCard card;
  final List<String> reasons;
  final String? sideNameKey;

  /// Each shown photo's caption, in card order (null when none).
  final List<String?> captions;

  /// Each shown photo's position, in card order: the photo URLs are
  /// matched to the card's slots by position, so a photo that fails to
  /// sign leaves its own slot empty (never shifts the next one into it).
  final List<int> photoPositions;

  /// 'interested' once the viewer said so; null before.
  final String? acted;

  /// Null for anything that isn't a card (a malformed one drops; the rest
  /// of Today stands).
  static DatingIntroCard? fromJson(Object? raw) {
    try {
      return _fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  static DatingIntroCard? _fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final j = Map<String, dynamic>.from(raw);
    final photos =
        j['photos'] is List
            ? (j['photos'] as List).whereType<Map>().toList()
            : <Map>[];
    photos.sort((a, b) => _position(a).compareTo(_position(b)));
    return DatingIntroCard(
      id: j['id'] as String,
      card: DatingCard.fromJson(j),
      reasons: [
        if (j['reasons'] is List)
          for (final r in j['reasons'] as List)
            if (r is String) r,
      ],
      sideNameKey: j['side_name_key'] is String ? j['side_name_key'] : null,
      captions: [
        for (final p in photos)
          if (p['id'] is String)
            p['caption'] is String && (p['caption'] as String).isNotEmpty
                ? p['caption'] as String
                : null,
      ],
      photoPositions: [
        for (final p in photos)
          if (p['id'] is String) _position(p),
      ],
      acted: j['acted'] == 'interested' ? 'interested' : null,
    );
  }

  DatingIntroCard asInterested() => DatingIntroCard(
    id: id,
    card: card,
    reasons: reasons,
    sideNameKey: sideNameKey,
    captions: captions,
    photoPositions: photoPositions,
    acted: 'interested',
  );

  /// Never printed: the card is another person's answers.
  @override
  String toString() => 'DatingIntroCard(…)';
}

/// A match the person hasn't seen yet (§3.5).
class DatingMoment {
  const DatingMoment({required this.matchId, required this.name});

  final String matchId;
  final String name;

  @override
  String toString() => 'DatingMoment(…)';
}

/// get_my_dating_today(): `{ok, today_state, …}` or `{ok: false, reason}`.
class DatingToday {
  const DatingToday({
    this.ok = false,
    this.reason,
    this.state = DatingTodayState.unavailable,
    this.dropAt,
    this.regionNameKey,
    this.myName,
    this.cards = const [],
    this.waiting = const [],
    this.moments = const [],
    this.familyQuestion = false,
    this.quietNote = false,
    this.dataSaver = false,
    this.minAge,
    this.maxAge,
    this.scope,
  });

  static const failed = DatingToday(reason: 'failed');
  static const busy = DatingToday(reason: 'busy');

  final bool ok;
  final String? reason;
  final DatingTodayState state;

  /// When the next introductions arrive (before_drop, cool_off).
  final DateTime? dropAt;
  final String? regionNameKey;

  /// The person's own first name (the match moment's own avatar).
  final String? myName;
  final List<DatingIntroCard> cards;
  final List<DatingIntroCard> waiting;
  final List<DatingMoment> moments;
  final bool familyQuestion;
  final bool quietNote;
  final bool dataSaver;
  final int? minAge;
  final int? maxAge;
  final String? scope;

  factory DatingToday.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      return DatingToday(reason: _fixed(raw['reason'], datingTodayReasons));
    }
    List<DatingIntroCard> cards(Object? list) => [
      if (list is List)
        for (final c in list)
          if (DatingIntroCard.fromJson(c) case final card?) card,
    ];
    final widen = raw['widen'] is Map ? raw['widen'] as Map : const {};
    final drop = raw['drop_at'];
    return DatingToday(
      ok: true,
      state: DatingTodayState.fromWire(raw['today_state']),
      dropAt: drop is String ? DateTime.tryParse(drop) : null,
      regionNameKey:
          raw['region_name_key'] is String ? raw['region_name_key'] : null,
      myName: raw['my_name'] is String ? raw['my_name'] : null,
      cards: cards(raw['cards']),
      waiting: cards(raw['waiting']),
      moments: [
        if (raw['moments'] is List)
          for (final m in (raw['moments'] as List).whereType<Map>())
            // W5 final fix (M-13): a missing name (JSON null) still shows
            // the moment, with the no-name copy.
            if (m['match_id'] is String &&
                (m['display_name'] is String || m['display_name'] == null))
              DatingMoment(
                matchId: m['match_id'] as String,
                name:
                    m['display_name'] is String
                        ? m['display_name'] as String
                        : '',
              ),
      ],
      familyQuestion: raw['family_question'] == true,
      quietNote: raw['quiet_note'] == true,
      dataSaver: raw['data_saver'] == true,
      minAge: widen['min_age'] is int ? widen['min_age'] as int : null,
      maxAge: widen['max_age'] is int ? widen['max_age'] as int : null,
      scope: widen['scope'] is String ? widen['scope'] as String : null,
    );
  }

  @override
  String toString() => 'DatingToday(${state.wire})';
}

/// act_on_dating_introduction(): `{ok, action, matched}` or a refusal.
class DatingActAnswer {
  const DatingActAnswer({
    required this.ok,
    this.action,
    this.matched = false,
    this.reason,
  });

  static const busy = DatingActAnswer(ok: false, reason: 'busy');
  static const failed = DatingActAnswer(ok: false, reason: 'failed');

  final bool ok;
  final String? action;
  final bool matched;
  final String? reason;

  factory DatingActAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      return DatingActAnswer(
        ok: false,
        reason: _fixed(raw['reason'], datingActReasons),
      );
    }
    final action = raw['action'];
    return DatingActAnswer(
      ok: true,
      action: action is String ? action : null,
      matched: raw['matched'] == true,
    );
  }
}

/// block_dating_introduction()'s fixed refusals (Task 7b): `busy` after
/// its bounded lock wait; it never answers `reverify_device` (Ruling R-36),
/// which is read as the device line if it ever does.
const datingBlockReasons = {
  'invalid',
  'reverify_device',
  'introduction_unavailable',
  'rate_limited',
  'busy',
};

/// block_dating_introduction(): `{ok: true}` or a refusal.
class DatingBlockAnswer {
  const DatingBlockAnswer({required this.ok, this.reason});

  static const busy = DatingBlockAnswer(ok: false, reason: 'busy');
  static const failed = DatingBlockAnswer(ok: false, reason: 'failed');

  final bool ok;
  final String? reason;

  factory DatingBlockAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] == true) return const DatingBlockAnswer(ok: true);
    return DatingBlockAnswer(
      ok: false,
      reason: _fixed(raw['reason'], datingBlockReasons),
    );
  }
}

/// One signed photo URL (dating-photo-urls): lives 60 seconds.
class DatingPhotoUrl {
  const DatingPhotoUrl(this.position, this.url);

  final int position;
  final String url;
}

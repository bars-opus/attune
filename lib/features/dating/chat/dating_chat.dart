// Spec 2 W6a (§3.5, §3.6, §6.1): the dating chat as the server sends it.
// Every field is read defensively (a malformed message is dropped, an
// unknown refusal is failed, never a server's text). The text a message
// carries is the server's view of it: masked ("•••") until both people
// have swapped. Memory only (D20): nothing here is written to disk.

/// The chat RPCs' fixed refusals. `unavailable` (send and a swap offer):
/// messages are paused (the chat's flag is off); it is retryable and does
/// not mean the chat has ended.
const datingChatReasons = {
  'invalid',
  'reverify_device',
  'match_unavailable',
  'closed',
  'restricted',
  'rate_limited',
  'too_early',
  'already_swapped',
  'unavailable',
  'busy',
};

/// The span every hidden contact detail becomes (§6.1).
const kDatingMask = '•••';

String _fixed(Object? reason) =>
    reason is String && datingChatReasons.contains(reason) ? reason : 'failed';

DateTime? _time(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

String? _text(Object? raw) => raw is String ? raw : null;

/// One message as this person reads it.
class DatingChatMessage {
  const DatingChatMessage({
    required this.id,
    required this.mine,
    required this.text,
    required this.at,
    this.kind = 'text',
    this.questionId,
  });

  final String id;
  final bool mine;
  final String kind;
  final String? questionId;
  final String text;
  final DateTime at;

  static DatingChatMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    final at = _time(raw['at']);
    if (id is! String || text is! String || at == null) return null;
    return DatingChatMessage(
      id: id,
      mine: raw['mine'] == true,
      kind: _text(raw['kind']) ?? 'text',
      questionId: _text(raw['question_id']),
      text: text,
      at: at,
    );
  }
}

/// The text in order, each part a plain run or a hidden contact detail.
List<(String, bool)> datingMaskedParts(String text) {
  final parts = <(String, bool)>[];
  var rest = text;
  while (rest.isNotEmpty) {
    final i = rest.indexOf(kDatingMask);
    if (i < 0) {
      parts.add((rest, false));
      break;
    }
    if (i > 0) parts.add((rest.substring(0, i), false));
    parts.add((kDatingMask, true));
    rest = rest.substring(i + kDatingMask.length);
  }
  return parts;
}

/// Swap contacts: each side's offer, and from when it can be offered.
class DatingSwap {
  const DatingSwap({
    this.mine = false,
    this.theirs = false,
    this.both = false,
    this.from,
  });

  final bool mine;
  final bool theirs;
  final bool both;
  final DateTime? from;

  factory DatingSwap.fromJson(Object? raw, {DateTime? from}) {
    if (raw is! Map) return DatingSwap(from: from);
    return DatingSwap(
      mine: raw['mine'] == true,
      theirs: raw['theirs'] == true,
      both: raw['both'] == true,
      from: _time(raw['from']) ?? from,
    );
  }

  /// Whether Swap can be offered at [now].
  bool open(DateTime now) => from == null || !now.isBefore(from!);
}

/// The chat's header: the other person's first name and age, and whether
/// the conversation has ended.
class DatingChatHeader {
  const DatingChatHeader({
    required this.matchId,
    this.displayName = '',
    this.age,
    this.ended = false,
    this.swap = const DatingSwap(),
    this.weMet = false,
    this.theyMet = false,
    this.timebox,
  });

  final String matchId;
  final String displayName;
  final int? age;
  final bool ended;
  final DatingSwap swap;

  /// Spec 2 W6c (§3.6): this side said "We met"; the other side did.
  final bool weMet;
  final bool theyMet;

  /// Spec 2 W6c (§3.6): the timebox card due for this side ('day7' or
  /// 'day21'), never a date.
  final String? timebox;

  static DatingChatHeader? fromJson(Object? raw) {
    if (raw is! Map || raw['match_id'] is! String) return null;
    return DatingChatHeader(
      matchId: raw['match_id'] as String,
      displayName: (_text(raw['display_name']) ?? '').trim(),
      age: raw['age'] is int ? raw['age'] as int : null,
      ended: raw['state'] != 'active',
      swap: DatingSwap.fromJson(raw['swap']),
      weMet: raw['we_met'] is Map && (raw['we_met'] as Map)['mine'] == true,
      theyMet: raw['we_met'] is Map && (raw['we_met'] as Map)['theirs'] == true,
      timebox:
          raw['timebox'] == 'day7' || raw['timebox'] == 'day21'
              ? raw['timebox'] as String
              : null,
    );
  }
}

/// One page of the chat, newest first.
class DatingChatPage {
  const DatingChatPage({
    this.ok = false,
    this.reason,
    this.header,
    this.messages = const [],
    this.more = false,
  });

  static const failed = DatingChatPage(reason: 'failed');
  static const busy = DatingChatPage(reason: 'busy');

  final bool ok;
  final String? reason;
  final DatingChatHeader? header;
  final List<DatingChatMessage> messages;
  final bool more;

  factory DatingChatPage.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) return DatingChatPage(reason: _fixed(raw['reason']));
    final header = DatingChatHeader.fromJson(raw['chat']);
    final list = raw['messages'];
    if (header == null || list is! List) return failed;
    return DatingChatPage(
      ok: true,
      header: header,
      messages: [
        for (final m in list.map(DatingChatMessage.fromJson))
          if (m != null) m,
      ],
      more: raw['more'] == true,
    );
  }
}

/// send_dating_message()'s answer.
class DatingSendAnswer {
  const DatingSendAnswer({required this.ok, this.reason, this.message});

  static const busy = DatingSendAnswer(ok: false, reason: 'busy');
  static const failed = DatingSendAnswer(ok: false, reason: 'failed');

  final bool ok;
  final String? reason;
  final DatingChatMessage? message;

  factory DatingSendAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      return DatingSendAnswer(ok: false, reason: _fixed(raw['reason']));
    }
    final m = DatingChatMessage.fromJson(raw['message']);
    return m == null ? failed : DatingSendAnswer(ok: true, message: m);
  }
}

/// An answer that only says ok or why not (swap, block, unmatch).
class DatingChatAnswer {
  const DatingChatAnswer({
    required this.ok,
    this.reason,
    this.swap,
    this.from,
    this.push,
  });

  static const busy = DatingChatAnswer(ok: false, reason: 'busy');
  static const failed = DatingChatAnswer(ok: false, reason: 'failed');

  final bool ok;
  final String? reason;
  final DatingSwap? swap;

  /// too_early: when Swap opens.
  final DateTime? from;

  /// Spec 2 W6c Task 10 fix round 1 (I-3): the check-in's answer says
  /// whether a push can reach this person at all (null: not said).
  final bool? push;

  factory DatingChatAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      return DatingChatAnswer(
        ok: false,
        reason: _fixed(raw['reason']),
        from: _time(raw['from']),
      );
    }
    return DatingChatAnswer(
      ok: true,
      swap: raw['swap'] is Map ? DatingSwap.fromJson(raw['swap']) : null,
      push: raw['push'] is bool ? raw['push'] as bool : null,
    );
  }
}

/// Spec 2 W6c Task 10 fix round 1 (I-1, I-3): this person's own pending
/// check-in as the server holds it ([at] null: none), and whether a push
/// can reach them. [known] is false when it could not be read.
class DatingCheckin {
  const DatingCheckin({required this.known, this.at, this.push = true});

  static const unknown = DatingCheckin(known: false);

  final bool known;
  final DateTime? at;
  final bool push;

  factory DatingCheckin.fromJson(Object? raw) {
    if (raw is! Map || raw['ok'] != true) return unknown;
    return DatingCheckin(
      known: true,
      at: _time(raw['at']),
      push: raw['push'] != false,
    );
  }
}

/// One row of the conversations list.
class DatingConversation {
  const DatingConversation({
    required this.matchId,
    this.displayName = '',
    this.age,
    this.last,
    this.isNew = false,
  });

  final String matchId;
  final String displayName;
  final int? age;
  final DatingChatMessage? last;
  final bool isNew;
}

/// A conversation that ended in the last 30 days.
class DatingEndedConversation {
  const DatingEndedConversation({required this.matchId, this.displayName = ''});

  final String matchId;
  final String displayName;
}

class DatingConversations {
  const DatingConversations({
    this.ok = false,
    this.reason,
    this.conversations = const [],
    this.ended = const [],
  });

  static const failed = DatingConversations(reason: 'failed');
  static const busy = DatingConversations(reason: 'busy');

  final bool ok;
  final String? reason;
  final List<DatingConversation> conversations;
  final List<DatingEndedConversation> ended;

  factory DatingConversations.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      return DatingConversations(reason: _fixed(raw['reason']));
    }
    final rows = raw['conversations'];
    if (rows is! List) return failed;
    final ended = raw['ended'];
    return DatingConversations(
      ok: true,
      conversations: [
        for (final r in rows.whereType<Map>())
          if (r['match_id'] is String)
            DatingConversation(
              matchId: r['match_id'] as String,
              displayName: (_text(r['display_name']) ?? '').trim(),
              age: r['age'] is int ? r['age'] as int : null,
              last: DatingChatMessage.fromJson(r['last']),
              isNew: r['new'] == true,
            ),
      ],
      ended: [
        if (ended is List)
          for (final r in ended.whereType<Map>())
            if (r['match_id'] is String)
              DatingEndedConversation(
                matchId: r['match_id'] as String,
                displayName: (_text(r['display_name']) ?? '').trim(),
              ),
      ],
    );
  }
}

/// Spec 2 W6b (§3.6 Safety cards, §6.1): the families a card can show (tier
/// 1 and 2; the server never sends a tier 3 one).
const datingCardFamilies = {
  'sexual_pressure',
  'harassment_abuse',
  'contact_migration_pressure',
  'meet_private_pressure',
  'threat_intimidation',
  'financial_request',
  'sextortion',
  'child_access',
};

/// A resource a card names (S1 W7a's support_resources).
class DatingCardResource {
  const DatingCardResource({
    required this.name,
    this.phone,
    this.sms,
    this.url,
  });

  final String name;
  final String? phone;

  /// Fix round 1 (I-2): a number to text, and a web address (https only;
  /// shown as plain text, never opened from the card).
  final String? sms;
  final String? url;

  /// The threat card's number: the name and the phone to call (none
  /// without a phone: a text number or an address is not "call").
  String? get callLine => phone == null ? null : '$name ($phone)';

  /// The sextortion card's resource: the name with its phone, else its
  /// text number, else its address as plain text; none without any.
  String? get contactLine {
    final how = phone ?? sms ?? _address;
    return how == null ? null : '$name ($how)';
  }

  /// [url] as words ("stopncii.org"): https only, never a link here.
  String? get _address {
    final u = url;
    if (u == null || !u.startsWith('https://') || u.length <= 8) return null;
    final rest = u.substring(8);
    return rest.endsWith('/') ? rest.substring(0, rest.length - 1) : rest;
  }
}

/// One safety card for this person, under the message that raised it.
class DatingSafetyCard {
  const DatingSafetyCard({
    required this.id,
    required this.messageId,
    required this.family,
    this.resource,
  });

  final String id;
  final String messageId;
  final String family;
  final DatingCardResource? resource;

  static DatingSafetyCard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final message = raw['message_id'];
    final family = raw['family'];
    if (id is! String ||
        message is! String ||
        family is! String ||
        !datingCardFamilies.contains(family)) {
      return null;
    }
    final r = raw['resource'];
    return DatingSafetyCard(
      id: id,
      messageId: message,
      family: family,
      resource:
          r is Map && r['name'] is String
              ? DatingCardResource(
                name: r['name'] as String,
                phone: _text(r['phone']),
                sms: _text(r['sms']),
                url: _text(r['url']),
              )
              : null,
    );
  }

  /// The cards in an answer; none for a refusal or anything malformed.
  static List<DatingSafetyCard> listFromJson(Object? raw) {
    if (raw is! Map || raw['ok'] != true || raw['cards'] is! List) {
      return const [];
    }
    return [
      for (final c in (raw['cards'] as List).map(fromJson))
        if (c != null) c,
    ];
  }
}

/// Spec 2 W6c (§3.6): the reviewed questions, in order.
const datingGuidedQuestions = [
  'good_saturday',
  'food_every_week',
  'looking_forward',
  'proud_of',
  'laugh_with',
  'where_you_grew_up',
  'good_relationship',
  'time_with_family',
  'before_first_meeting',
];

/// Spec 2 W6c (§3.6): the guided first conversation as this side sees it.
class DatingGuided {
  const DatingGuided({
    this.questionId,
    this.answered = false,
    this.revealed = 0,
    this.ok = true,
  });

  static const none = DatingGuided();

  /// Task 9 (Ruling 4): a read that failed or was refused. The chat keeps
  /// what it showed, as it keeps its messages on a failed re-read.
  static const failed = DatingGuided(ok: false);

  /// The current question; null once every one is answered or skipped.
  final String? questionId;

  /// This side answered it (the other side's answer waits for both).
  final bool answered;

  /// How many questions both have answered (the tip follows the first).
  final int revealed;

  /// False for [failed].
  final bool ok;

  factory DatingGuided.fromJson(Object? raw) {
    if (raw is! Map || raw['ok'] != true) return failed;
    final q = raw['question_id'];
    return DatingGuided(
      questionId: q is String && datingGuidedQuestions.contains(q) ? q : null,
      answered: raw['answered'] == true,
      revealed: raw['revealed'] is int ? raw['revealed'] as int : 0,
    );
  }
}

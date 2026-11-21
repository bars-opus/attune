// Spec 2 W6a: the chat faked for widget tests. Every answer is the test's;
// every call is recorded; a read or a send can be held open (D8 tests);
// the signals are a stream the test drives, one per account.
// Fix round 1 (review M-1): it answers as the server does. Every text is
// masked ("•••") until both people swapped, the sender's own copy too
// (simple patterns; never the server's masker); a page before a time holds
// only older messages; withdraw answers mine false; a bad key is invalid,
// an ended chat closed, a swap before its time too_early, a withdraw after
// both swapped already_swapped; and any call can be refused with a reason.
// Final client fix (M-10): a Block or an Unmatch that succeeds ends the
// chat, so the next read answers ended, as the server does.
import 'dart:async';

import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final datingChatT0 = DateTime.utc(2026, 11, 20, 18);

/// Phone-like digit runs, emails, links and @handles: the masker's simple
/// cases, so a fake answer never shows a contact before both swapped.
final _contact = RegExp(
  r'[\w.+-]+@[\w-]+\.[\w.]+|https?://\S+|www\.\S+|wa\.me/\S*|@\w{2,}|'
  r'\+?\d[\d\s.-]{5,}\d',
  caseSensitive: false,
);

/// [text] as the server reads it before both swapped (simple cases only).
String datingFakeMask(String text) => text.replaceAll(_contact, kDatingMask);

/// The server's idempotency key rule (16-128 of [A-Za-z0-9_:.-]).
final _key = RegExp(r'^[A-Za-z0-9_:.-]{16,128}$');

/// A message as the server sends it.
Map<String, Object?> datingMessageJson(
  String id,
  String text, {
  bool mine = false,
  int minute = 0,
}) => {
  'id': id,
  'mine': mine,
  'kind': 'text',
  'question_id': null,
  'text': text,
  'at': datingChatT0.add(Duration(minutes: minute)).toIso8601String(),
};

/// A page as the server sends it (newest first), [over] on top.
Map<String, Object?> datingPageJson({
  String matchId = 'm1',
  String name = 'Kofi',
  int? age = 31,
  bool ended = false,
  Map<String, Object?> swap = const {
    'mine': false,
    'theirs': false,
    'both': false,
  },
  DateTime? swapFrom,
  List<Map<String, Object?>>? messages,
  bool more = false,
}) => {
  'ok': true,
  'chat': {
    'match_id': matchId,
    'display_name': name,
    'age': age,
    'state': ended ? 'ended' : 'active',
    'swap': {
      ...swap,
      'from':
          (swapFrom ?? datingChatT0.subtract(const Duration(days: 1)))
              .toIso8601String(),
    },
  },
  'messages':
      messages ??
      [
        datingMessageJson('d2', 'Call me on •••', minute: 2),
        datingMessageJson('d1', 'Hi Ama!', mine: true, minute: 1),
      ],
  'more': more,
};

Map<String, Object?> datingConversationsJson({
  List<Map<String, Object?>>? rows,
  List<Map<String, Object?>> ended = const [],
}) => {
  'ok': true,
  'conversations':
      rows ??
      [
        {
          'match_id': 'm1',
          'display_name': 'Kofi',
          'age': 31,
          'last': datingMessageJson('d2', 'Call me on •••', minute: 2),
          'new': true,
        },
        {
          'match_id': 'm2',
          'display_name': 'Yaw',
          'age': 34,
          'last': null,
          'new': false,
        },
      ],
  'ended': ended,
};

class FakeDatingChat implements DatingChatGateway {
  FakeDatingChat({Map<String, Object?>? page, Map<String, Object?>? list})
    : pageJson = page ?? datingPageJson(),
      listJson = list ?? datingConversationsJson();

  Map<String, Object?> pageJson;
  Map<String, Object?> listJson;
  Completer<DatingChatPage>? hold;
  Completer<DatingConversations>? listHold;
  Completer<DatingSendAnswer>? sendHold;
  DatingSendAnswer Function(String text)? sendAnswer;
  DatingChatAnswer swapAnswer = const DatingChatAnswer(
    ok: true,
    swap: DatingSwap(mine: true),
  );
  DatingChatAnswer withdrawAnswer = const DatingChatAnswer(
    ok: true,
    swap: DatingSwap(),
  );
  DatingChatAnswer endAnswer = const DatingChatAnswer(ok: true);

  /// A refusal per call, by method name (`conversations`, `messages`,
  /// `send`, `offerSwap`, `withdrawSwap`, `block`, `unmatch`): the call
  /// answers `{ok: false, reason}` as the server would (an unknown reason
  /// reads as failed).
  final refusals = <String, String>{};

  /// The page's time "now" for too_early.
  DateTime Function() now = () => datingChatT0;

  final _signals = <String, StreamController<void>>{};

  /// [account]'s own signal stream.
  StreamController<void> signalsFor(String account) =>
      _signals.putIfAbsent(account, () => StreamController<void>.broadcast());

  /// The signals of the account that subscribed last ('ama' before any).
  StreamController<void> get signalEvents =>
      signalsFor(signalAccounts.isEmpty ? 'ama' : signalAccounts.last);

  final reads = <(String, DateTime?)>[];
  int listReads = 0;
  final sends = <(String key, String matchId, String text)>[];
  final swaps = <(String matchId, bool offer)>[];
  final blocks = <(String key, String matchId)>[];
  final unmatches = <(String key, String matchId)>[];
  final signalAccounts = <String>[];

  /// Spec 2 W6b: the cards to show, the reads of them, and the dismissals
  /// asked. A `cards` refusal answers none, as the repository does.
  List<DatingSafetyCard> cardList = const [];
  final cardReads = <String>[];
  final dismissed = <String>[];

  /// Spec 2 W6c: the guided state, and every guided or closing call. Each
  /// honours `refusals[call]` (`guided` answers [DatingGuided.failed], as
  /// the repository does); an answer and Close kindly refuse a bad key
  /// (invalid); an answer, a skip, We met and Close kindly refuse an ended
  /// chat (closed), as the server does.
  DatingGuided guidedState = DatingGuided.none;
  int guidedReads = 0;
  final answers = <(String key, String questionId, String text)>[];
  final skips = <String>[];
  int weMets = 0;
  final timeboxes = <String>[];
  final kindCloses = <String>[];

  /// Spec 2 W6c: the check-ins asked (null: a cancel). Each honours
  /// `refusals['scheduleCheckin']` / `refusals['cancelCheckin']`; a held
  /// schedule waits on [checkinHold] (D8 tests).
  final checkins = <DateTime?>[];
  Completer<DatingChatAnswer>? checkinHold;

  /// Task 10 fix round 1 (I-1, I-3): the server's pending check-in (a
  /// schedule sets it, a cancel clears it), whether a push device exists,
  /// and the reads of it (`refusals['checkin']` answers unknown).
  DateTime? checkinAt;
  bool checkinPush = true;
  int checkinReads = 0;

  @override
  Future<DatingConversations> conversations({bool ended = false}) async {
    listReads++;
    final h = listHold;
    if (h != null) return h.future;
    final refused = _refusal('conversations');
    if (refused != null) return DatingConversations.fromJson(refused);
    final rows = listJson['conversations'];
    return DatingConversations.fromJson({
      ...listJson,
      if (rows is List)
        'conversations': [
          for (final r in rows) r is Map ? {...r, 'last': _read(r['last'])} : r,
        ],
    });
  }

  @override
  Future<DatingChatPage> messages(String matchId, {DateTime? before}) async {
    reads.add((matchId, before));
    final h = hold;
    if (h != null) return h.future;
    final refused = _refusal('messages');
    if (refused != null) return DatingChatPage.fromJson(refused);
    final list = pageJson['messages'];
    if (list is! List) return DatingChatPage.fromJson(pageJson);
    return DatingChatPage.fromJson({
      ...pageJson,
      'messages': [
        for (final m in list)
          if (before == null ||
              (m is Map &&
                  m['at'] is String &&
                  DateTime.parse(m['at'] as String).isBefore(before)))
            _read(m),
      ],
      if (before != null) 'more': false,
    });
  }

  @override
  Future<DatingSendAnswer> send(String key, String matchId, String text) async {
    sends.add((key, matchId, text));
    final h = sendHold;
    if (h != null) return h.future;
    final a = sendAnswer;
    if (a != null) return a(text);
    final refused =
        _refusal('send') ??
        (!_key.hasMatch(key)
            ? {'ok': false, 'reason': 'invalid'}
            : _ended
            ? {'ok': false, 'reason': 'closed'}
            : null);
    if (refused != null) return DatingSendAnswer.fromJson(refused);
    return DatingSendAnswer.fromJson({
      'ok': true,
      'message': _read(
        datingMessageJson('s${sends.length}', text, mine: true, minute: 9),
      ),
    });
  }

  @override
  Future<DatingChatAnswer> offerSwap(String matchId) async {
    swaps.add((matchId, true));
    final from =
        _swap['from'] is String
            ? DateTime.parse(_swap['from'] as String)
            : null;
    final refused =
        _refusal('offerSwap') ??
        (_ended
            ? {'ok': false, 'reason': 'closed'}
            : from != null && now().isBefore(from)
            ? {
              'ok': false,
              'reason': 'too_early',
              'from': from.toUtc().toIso8601String(),
            }
            : null);
    if (refused != null) return DatingChatAnswer.fromJson(refused);
    return swapAnswer;
  }

  @override
  Future<DatingChatAnswer> withdrawSwap(String matchId) async {
    swaps.add((matchId, false));
    final refused =
        _refusal('withdrawSwap') ??
        (_ended
            ? {'ok': false, 'reason': 'closed'}
            : _both
            ? {'ok': false, 'reason': 'already_swapped'}
            : null);
    if (refused != null) return DatingChatAnswer.fromJson(refused);
    return withdrawAnswer;
  }

  Map<String, Object?>? _endRefusal(String call, String key) =>
      _refusal(call) ??
      (_key.hasMatch(key) ? null : {'ok': false, 'reason': 'invalid'});

  @override
  Future<DatingChatAnswer> block(String key, String matchId) async {
    blocks.add((key, matchId));
    final refused = _endRefusal('block', key);
    if (refused != null) return DatingChatAnswer.fromJson(refused);
    return _end(endAnswer);
  }

  @override
  Future<DatingChatAnswer> unmatch(String key, String matchId) async {
    unmatches.add((key, matchId));
    final refused = _endRefusal('unmatch', key);
    if (refused != null) return DatingChatAnswer.fromJson(refused);
    return _end(endAnswer);
  }

  /// M-10: [answer], and when it succeeded the chat reads ended from now.
  DatingChatAnswer _end(DatingChatAnswer answer) {
    if (answer.ok && pageJson['chat'] is Map) {
      pageJson = {
        ...pageJson,
        'chat': {...pageJson['chat']! as Map, 'state': 'ended'},
      };
    }
    return answer;
  }

  @override
  Future<List<DatingSafetyCard>> cards(String matchId) async {
    cardReads.add(matchId);
    if (refusals.containsKey('cards')) return const [];
    return [
      for (final c in cardList)
        if (!_dismissConfirmed.contains(c.id)) c,
    ];
  }

  /// Fix round 1 (M-1): true unless `refusals['dismissCard']` is set; a
  /// confirmed dismissal is never served again, as the server does.
  @override
  Future<bool> dismissCard(String id) async {
    dismissed.add(id);
    if (refusals.containsKey('dismissCard')) return false;
    _dismissConfirmed.add(id);
    return true;
  }

  final _dismissConfirmed = <String>{};

  @override
  Future<DatingGuided> guided(String matchId) async {
    guidedReads++;
    return refusals.containsKey('guided') ? DatingGuided.failed : guidedState;
  }

  Map<String, Object?>? get _closed =>
      _ended ? {'ok': false, 'reason': 'closed'} : null;

  @override
  Future<DatingSendAnswer> answerGuided(
    String key,
    String matchId,
    String questionId,
    String text,
  ) async {
    answers.add((key, questionId, text));
    final refused = _endRefusal('answerGuided', key) ?? _closed;
    if (refused != null) return DatingSendAnswer.fromJson(refused);
    // As the server: this side has now answered the current question.
    if (guidedState.questionId == questionId) {
      guidedState = DatingGuided(
        questionId: questionId,
        answered: true,
        revealed: guidedState.revealed,
      );
    }
    return DatingSendAnswer.fromJson({
      'ok': true,
      'message': {
        ...datingMessageJson('g${answers.length}', text, mine: true),
        'kind': 'guided_answer',
        'question_id': questionId,
      },
    });
  }

  @override
  Future<DatingChatAnswer> skipGuided(String matchId, String questionId) async {
    skips.add(questionId);
    final refused = _refusal('skipGuided') ?? _closed;
    if (refused != null) return DatingChatAnswer.fromJson(refused);
    return endAnswer;
  }

  @override
  Future<DatingChatAnswer> weMet(String matchId) async {
    weMets++;
    final refused = _refusal('weMet') ?? _closed;
    if (refused != null) return DatingChatAnswer.fromJson(refused);
    return endAnswer;
  }

  /// Fix round 1 (M-3): true unless `refusals['dismissTimebox']` is set.
  @override
  Future<bool> dismissTimebox(String matchId, String card) async {
    timeboxes.add(card);
    return !refusals.containsKey('dismissTimebox');
  }

  @override
  Future<DatingChatAnswer> closeKindly(String key, String matchId) async {
    kindCloses.add(key);
    final refused = _endRefusal('closeKindly', key) ?? _closed;
    if (refused != null) return DatingChatAnswer.fromJson(refused);
    return endAnswer;
  }

  @override
  Future<DatingChatAnswer> scheduleCheckin(DateTime at) async {
    checkins.add(at);
    final h = checkinHold;
    if (h != null) return h.future;
    final refused = _refusal('scheduleCheckin');
    if (refused != null) return DatingChatAnswer.fromJson(refused);
    checkinAt = at;
    return DatingChatAnswer(ok: true, push: checkinPush);
  }

  @override
  Future<DatingCheckin> checkin() async {
    checkinReads++;
    if (refusals.containsKey('checkin')) return DatingCheckin.unknown;
    return DatingCheckin(known: true, at: checkinAt, push: checkinPush);
  }

  @override
  Future<DatingChatAnswer> cancelCheckin() async {
    checkins.add(null);
    final refused = _refusal('cancelCheckin');
    if (refused != null) return DatingChatAnswer.fromJson(refused);
    checkinAt = null;
    return endAnswer;
  }

  @override
  Stream<void> signals(String account) {
    signalAccounts.add(account);
    return signalsFor(account).stream;
  }

  Map<String, Object?>? _refusal(String call) {
    final reason = refusals[call];
    return reason == null ? null : {'ok': false, 'reason': reason};
  }

  Map<Object?, Object?> get _chat =>
      pageJson['chat'] is Map ? pageJson['chat'] as Map : const {};

  Map<Object?, Object?> get _swap =>
      _chat['swap'] is Map ? _chat['swap'] as Map : const {};

  bool get _both => _swap['both'] == true;

  bool get _ended => _chat['state'] != 'active';

  /// [message] as this person reads it: masked until both swapped.
  Object? _read(Object? message) {
    if (_both || message is! Map || message['text'] is! String) return message;
    return {...message, 'text': datingFakeMask(message['text'] as String)};
  }
}

List<Override> datingChatOverrides(FakeDatingChat fake) => [
  datingChatGatewayProvider.overrideWithValue(fake),
];

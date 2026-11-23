// Spec 2 W6a (§3.5, §3.6, §4.4): the chat's calls, all through the Dating
// RPC client (its device header), and its "something changed" signal
// through the same Dating-scoped client's realtime (the person's own
// dating_chat_signals rows; no content). Every call is bounded; a failure
// answers failed or busy, never the error's text.
import 'dart:async';

import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Owner follow-up to W6 (fallback poll): what the chat's signal channel
/// says. Some networks block WebSockets, so the channel may never join;
/// the providers decide what to read again (datingChatSignalsProvider).
enum DatingChatSignal {
  /// Something changed in one of this person's chats.
  changed,

  /// The channel joined (the first time or again).
  live,

  /// The channel failed, timed out or closed: realtime may not reach here.
  down,
}

/// The channel's [status] as a [DatingChatSignal].
DatingChatSignal datingChannelSignal(RealtimeSubscribeStatus status) =>
    switch (status) {
      RealtimeSubscribeStatus.subscribed => DatingChatSignal.live,
      RealtimeSubscribeStatus.channelError ||
      RealtimeSubscribeStatus.timedOut ||
      RealtimeSubscribeStatus.closed => DatingChatSignal.down,
    };

abstract class DatingChatGateway {
  /// The conversations list; with [ended], the last 30 days' ended ones.
  Future<DatingConversations> conversations({bool ended = false});

  /// The newest page of [matchId], or the page before [before].
  Future<DatingChatPage> messages(String matchId, {DateTime? before});

  Future<DatingSendAnswer> send(String key, String matchId, String text);

  Future<DatingChatAnswer> offerSwap(String matchId);

  Future<DatingChatAnswer> withdrawSwap(String matchId);

  Future<DatingChatAnswer> block(String key, String matchId);

  Future<DatingChatAnswer> unmatch(String key, String matchId);

  /// One [DatingChatSignal.changed] each time something changed in one of
  /// [account]'s chats, and the channel's state as it moves (owner
  /// follow-up, fallback poll): [DatingChatSignal.live] on every join,
  /// [DatingChatSignal.down] on an error, a timeout or a close.
  Stream<DatingChatSignal> signals(String account);

  /// Spec 2 W6b: this person's safety cards in [matchId] (none on any
  /// failure: the chat never waits on them).
  Future<List<DatingSafetyCard>> cards(String matchId);

  /// Spec 2 W6b: the card is not shown again (detection is unchanged).
  /// True once the server confirmed it (fix round 1, M-1: until then the
  /// chat keeps it hidden and sends it again).
  Future<bool> dismissCard(String id);

  /// Spec 2 W6c (§3.6): the guided conversation ([DatingGuided.failed] on
  /// any failure or refusal).
  Future<DatingGuided> guided(String matchId);

  /// Spec 2 W6c: this side's answer to [questionId].
  Future<DatingSendAnswer> answerGuided(
    String key,
    String matchId,
    String questionId,
    String text,
  );

  /// Spec 2 W6c: [questionId] skipped for both.
  Future<DatingChatAnswer> skipGuided(String matchId, String questionId);

  /// Spec 2 W6c: "We met".
  Future<DatingChatAnswer> weMet(String matchId);

  /// Spec 2 W6c: the timebox card ('day7' or 'day21') is not shown again.
  /// True once the server confirmed it (fix round 1, M-3: until then the
  /// chat keeps it hidden and sends it again).
  Future<bool> dismissTimebox(String matchId, String card);

  /// Spec 2 W6c: the reviewed message, then the chat ends for both.
  Future<DatingChatAnswer> closeKindly(String key, String matchId);

  /// Spec 2 W6c (§3.6 Check on me): one neutral push at [at] (it replaces
  /// the last one).
  Future<DatingChatAnswer> scheduleCheckin(DateTime at);

  Future<DatingChatAnswer> cancelCheckin();

  /// Task 10 fix round 1 (I-1): the caller's own pending check-in
  /// ([DatingCheckin.unknown] on any failure).
  Future<DatingCheckin> checkin();
}

/// Fix round 1 (M-8): a channel the server closed is never rejoined by
/// realtime, so the signals make a new one after this pause.
const kDatingChatReopenAfter = Duration(seconds: 5);

class DatingChatRepository implements DatingChatGateway {
  DatingChatRepository(
    this._rpc,
    this._client, {
    this.reopenAfter = kDatingChatReopenAfter,
    Future<bool> Function()? showSameGender,
  }) : _showSameGender = showSameGender;

  final DatingRpc _rpc;
  final SupabaseClient? _client;

  /// Spec 2 W8b (R-T5-1): this phone's "Show it on this phone anyway" for
  /// the signed-in account, sent with the conversations and the messages.
  final Future<bool> Function()? _showSameGender;

  /// How long after a close the channel is made again (tests shorten it).
  final Duration reopenAfter;

  Future<T> _guard<T>(
    Future<dynamic> Function() call,
    T Function(Object? raw) parse,
    T busy,
    T failed,
  ) async {
    try {
      return parse(await call());
    } on DatingBusy {
      return busy;
    } catch (_) {
      return failed;
    }
  }

  @override
  Future<DatingConversations> conversations({bool ended = false}) => _guard(
    () async => _rpc.call(
      'get_my_dating_matches',
      await datingShowSameGender(_showSameGender, {'p_include_ended': ended}),
    ),
    DatingConversations.fromJson,
    DatingConversations.busy,
    DatingConversations.failed,
  );

  @override
  Future<DatingChatPage> messages(String matchId, {DateTime? before}) => _guard(
    () async => _rpc.call(
      'get_dating_messages',
      await datingShowSameGender(_showSameGender, {
        'p_match_id': matchId,
        'p_before': before?.toUtc().toIso8601String(),
        'p_limit': 50,
      }),
    ),
    DatingChatPage.fromJson,
    DatingChatPage.busy,
    DatingChatPage.failed,
  );

  @override
  Future<DatingSendAnswer> send(String key, String matchId, String text) =>
      _guard(
        () => _rpc.call('send_dating_message', {
          'p_idempotency_key': key,
          'p_match_id': matchId,
          'p_body': text,
        }),
        DatingSendAnswer.fromJson,
        DatingSendAnswer.busy,
        DatingSendAnswer.failed,
      );

  Future<DatingChatAnswer> _answer(String fn, Map<String, dynamic> params) =>
      _guard(
        () => _rpc.call(fn, params),
        DatingChatAnswer.fromJson,
        DatingChatAnswer.busy,
        DatingChatAnswer.failed,
      );

  @override
  Future<DatingChatAnswer> offerSwap(String matchId) =>
      _answer('offer_dating_contact_swap', {'p_match_id': matchId});

  @override
  Future<DatingChatAnswer> withdrawSwap(String matchId) =>
      _answer('withdraw_dating_contact_swap', {'p_match_id': matchId});

  @override
  Future<DatingChatAnswer> block(String key, String matchId) => _answer(
    'block_dating_match',
    {'p_idempotency_key': key, 'p_match_id': matchId},
  );

  @override
  Future<DatingChatAnswer> unmatch(String key, String matchId) => _answer(
    'unmatch_dating_match',
    {'p_idempotency_key': key, 'p_match_id': matchId},
  );

  @override
  Future<List<DatingSafetyCard>> cards(String matchId) async {
    try {
      return DatingSafetyCard.listFromJson(
        await _rpc.call('get_my_dating_safety_cards', {'p_match_id': matchId}),
      );
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> dismissCard(String id) async {
    try {
      final r = await _rpc.call('dismiss_dating_safety_card', {
        'p_event_id': id,
      });
      return r is Map && r['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DatingGuided> guided(String matchId) async {
    try {
      return DatingGuided.fromJson(
        await _rpc.call('get_dating_guided_state', {'p_match_id': matchId}),
      );
    } catch (_) {
      return DatingGuided.failed;
    }
  }

  @override
  Future<DatingSendAnswer> answerGuided(
    String key,
    String matchId,
    String questionId,
    String text,
  ) => _guard(
    () => _rpc.call('send_dating_message', {
      'p_idempotency_key': key,
      'p_match_id': matchId,
      'p_body': text,
      'p_kind': 'guided_answer',
      'p_question_id': questionId,
    }),
    DatingSendAnswer.fromJson,
    DatingSendAnswer.busy,
    DatingSendAnswer.failed,
  );

  @override
  Future<DatingChatAnswer> skipGuided(String matchId, String questionId) =>
      _answer('skip_dating_guided_question', {
        'p_match_id': matchId,
        'p_question_id': questionId,
      });

  @override
  Future<DatingChatAnswer> weMet(String matchId) =>
      _answer('mark_dating_we_met', {'p_match_id': matchId});

  @override
  Future<bool> dismissTimebox(String matchId, String card) async {
    try {
      final r = await _rpc.call('dismiss_dating_timebox', {
        'p_match_id': matchId,
        'p_card': card,
      });
      return r is Map && r['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DatingChatAnswer> closeKindly(String key, String matchId) => _answer(
    'close_dating_match_kindly',
    {'p_idempotency_key': key, 'p_match_id': matchId},
  );

  @override
  Future<DatingChatAnswer> scheduleCheckin(DateTime at) => _answer(
    'schedule_dating_checkin',
    {'p_at': at.toUtc().toIso8601String()},
  );

  @override
  Future<DatingChatAnswer> cancelCheckin() =>
      _answer('cancel_dating_checkin', {});

  @override
  Future<DatingCheckin> checkin() async {
    try {
      return DatingCheckin.fromJson(
        await _rpc.call('get_my_dating_checkin', {}),
      );
    } catch (_) {
      return DatingCheckin.unknown;
    }
  }

  @override
  Stream<DatingChatSignal> signals(String account) {
    final client = _client;
    if (client == null) return const Stream.empty();
    RealtimeChannel? channel;
    Timer? reopen;
    var cancelled = false;
    final events = StreamController<DatingChatSignal>(
      onCancel: () {
        cancelled = true;
        reopen?.cancel();
        final last = channel;
        channel = null;
        if (last != null) unawaited(client.removeChannel(last));
      },
    );
    void open() {
      // INSERT and UPDATE only: a DELETE frame carries only the row's opaque
      // id (never user_id), so it could never match this filter.
      var listening = client.channel('dating-chat:${const Uuid().v4()}');
      for (final event in [
        PostgresChangeEvent.insert,
        PostgresChangeEvent.update,
      ]) {
        listening = listening.onPostgresChanges(
          event: event,
          schema: 'public',
          table: 'dating_chat_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: account,
          ),
          callback: (_) {
            if (!cancelled) events.add(DatingChatSignal.changed);
          },
        );
      }
      final made = listening;
      channel = made;
      // Owner follow-up (fallback poll): every status goes up as it comes;
      // the provider turns a rejoin into a read again (final client fix
      // I-1) and polls while the channel is not joined. Fix round 1 (M-8):
      // realtime never rejoins a closed channel, so a new one is made
      // after a pause (the old one's own close is not heard again).
      made.subscribe((status, _) {
        if (cancelled || !identical(channel, made)) return;
        events.add(datingChannelSignal(status));
        if (status != RealtimeSubscribeStatus.closed) return;
        reopen?.cancel();
        reopen = Timer(reopenAfter, () {
          if (cancelled || !identical(channel, made)) return;
          channel = null;
          unawaited(client.removeChannel(made));
          open();
        });
      });
    }

    open();
    return events.stream;
  }
}

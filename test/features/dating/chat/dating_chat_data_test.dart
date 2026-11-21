// Spec 2 W6a (§3.5, §3.6, §6.1; D8, D20): the chat's data. Every answer is
// read defensively (a malformed message dropped, an unknown refusal
// failed, never a server's text); the repository calls the chat RPCs with
// their parameters through the Dating RPC client; a busy or failing call
// answers a fixed code; the list is one entry per account (the next
// account's starts loading, nothing of the last); each chat signal is a
// new count.
import 'dart:async';
import 'dart:convert';

import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/dating_chat_fakes.dart';

void main() {
  test('a page reads defensively: masked parts, a malformed message dropped, '
      'an unknown refusal is failed', () {
    final page = DatingChatPage.fromJson({
      ...datingPageJson(),
      'messages': [
        datingMessageJson('d2', 'Call me on •••, or ••• later', minute: 2),
        {'id': 'bad', 'text': 7},
        {'id': 'bad2', 'text': 7, 'at': datingChatT0.toIso8601String()},
        datingMessageJson('d1', 'Hi!', mine: true, minute: 1),
      ],
    });
    expect(page.ok, isTrue);
    expect(page.header!.displayName, 'Kofi');
    expect(page.header!.age, 31);
    expect(page.header!.ended, isFalse);
    expect([for (final m in page.messages) m.id], ['d2', 'd1']);
    expect([for (final m in page.messages) m.mine], [false, true]);
    expect(page.more, isFalse);
    expect(DatingChatPage.fromJson(datingPageJson(more: true)).more, isTrue);
    expect(
      page.header!.swap.from,
      datingChatT0.subtract(const Duration(days: 1)),
    );
    final offered =
        DatingChatPage.fromJson(
          datingPageJson(
            swap: const {'mine': true, 'theirs': false, 'both': false},
            swapFrom: datingChatT0.add(const Duration(days: 2)),
          ),
        ).header!.swap;
    expect((offered.mine, offered.theirs, offered.both), (true, false, false));
    expect(offered.from, datingChatT0.add(const Duration(days: 2)));
    expect(offered.open(datingChatT0), isFalse);
    expect(offered.open(datingChatT0.add(const Duration(days: 2))), isTrue);
    final swapped =
        DatingChatPage.fromJson(
          datingPageJson(
            swap: const {'mine': false, 'theirs': true, 'both': true},
          ),
        ).header!.swap;
    expect((swapped.mine, swapped.theirs, swapped.both), (false, true, true));
    expect(datingMaskedParts(page.messages.first.text), [
      ('Call me on ', false),
      ('•••', true),
      (', or ', false),
      ('•••', true),
      (' later', false),
    ]);
    expect(
      DatingChatPage.fromJson({
        'ok': false,
        'reason': 'Kofi blocked you',
      }).reason,
      'failed',
    );
    expect(
      DatingChatPage.fromJson({
        'ok': false,
        'reason': 'match_unavailable',
      }).reason,
      'match_unavailable',
    );
    expect(DatingChatPage.fromJson('nope').reason, 'failed');
    final list = DatingConversations.fromJson(datingConversationsJson());
    expect([for (final c in list.conversations) c.matchId], ['m1', 'm2']);
    expect(list.conversations.first.isNew, isTrue);
    expect(list.conversations.last.last, isNull);
    final swap = DatingChatAnswer.fromJson({
      'ok': false,
      'reason': 'too_early',
      'from': '2026-11-23T18:00:00Z',
    });
    expect(swap.reason, 'too_early');
    expect(swap.from, DateTime.utc(2026, 11, 23, 18));
    // The live server (Task 2 fix round 1b): messages paused is its own
    // fixed reason (retryable, not ended); a swap offer can answer
    // restricted or closed while the chat is open.
    expect(
      DatingSendAnswer.fromJson({'ok': false, 'reason': 'unavailable'}).reason,
      'unavailable',
    );
    for (final reason in ['unavailable', 'restricted', 'closed']) {
      expect(
        DatingChatAnswer.fromJson({'ok': false, 'reason': reason}).reason,
        reason,
      );
    }
    // A chat blocked by phone alone: the header reads ended, though the
    // match is in neither the conversations nor the ended list.
    final hidden = DatingChatPage.fromJson(
      datingPageJson(matchId: 'm9', ended: true),
    );
    expect(hidden.ok, isTrue);
    expect(hidden.header!.matchId, 'm9');
    expect(hidden.header!.ended, isTrue);
    // Any state but active reads as ended (fails safe); active reads open.
    for (final (state, ended) in [
      ('held', true),
      (null, true),
      ('active', false),
    ]) {
      expect(
        DatingChatHeader.fromJson({'match_id': 'm9', 'state': state})!.ended,
        ended,
        reason: '$state',
      );
    }
  });

  test('the repository calls the chat RPCs with their parameters', () async {
    final calls = <(String, Map<String, dynamic>?)>[];
    final repo = DatingChatRepository(
      DatingRpc.withCall((fn, params) async {
        calls.add((fn, params));
        return fn == 'get_my_dating_matches'
            ? datingConversationsJson()
            : fn == 'get_dating_messages'
            ? datingPageJson()
            : fn == 'send_dating_message'
            ? {'ok': true, 'message': datingMessageJson('s1', 'Hi', mine: true)}
            : {'ok': true};
      }),
      null,
    );
    await repo.conversations(ended: true);
    await repo.messages('m1');
    await repo.messages('m1', before: DateTime.utc(2026, 11, 20, 18));
    final sent = await repo.send('key-0123456789abcdef', 'm1', 'Hi');
    await repo.offerSwap('m1');
    await repo.withdrawSwap('m1');
    await repo.block('key-block-0123456789', 'm1');
    await repo.unmatch('key-unmatch-0123456', 'm1');
    expect(sent.ok, isTrue);
    expect(sent.message!.mine, isTrue);
    expect(
      [for (final (fn, params) in calls) '$fn ${jsonEncode(params)}'],
      [
        'get_my_dating_matches {"p_include_ended":true}',
        'get_dating_messages {"p_match_id":"m1","p_before":null,"p_limit":50}',
        'get_dating_messages {"p_match_id":"m1","p_before":"2026-11-20T18:00:00.000Z","p_limit":50}',
        'send_dating_message {"p_idempotency_key":"key-0123456789abcdef","p_match_id":"m1","p_body":"Hi"}',
        'offer_dating_contact_swap {"p_match_id":"m1"}',
        'withdraw_dating_contact_swap {"p_match_id":"m1"}',
        'block_dating_match {"p_idempotency_key":"key-block-0123456789","p_match_id":"m1"}',
        'unmatch_dating_match {"p_idempotency_key":"key-unmatch-0123456","p_match_id":"m1"}',
      ],
    );
    expect(await repo.signals('ama').isEmpty, isTrue);
    // With a client: the person's own signal rows, INSERT and UPDATE only
    // (a DELETE frame carries only the row's opaque id, never user_id), and
    // the channel goes when nothing listens.
    final client = SupabaseClient('http://127.0.0.1:9', 'anon');
    addTearDown(client.dispose);
    final live = DatingChatRepository(
      DatingRpc.withCall((fn, params) async => null),
      client,
    );
    final listening = live.signals('ama').listen((_) {});
    addTearDown(listening.cancel);
    final channel = client.getChannels().single;
    // ignore: invalid_use_of_internal_member
    final config = channel.joinPush.payload['config'] as Map;
    expect(config['postgres_changes'], [
      for (final event in ['INSERT', 'UPDATE'])
        {
          'event': event,
          'schema': 'public',
          'table': 'dating_chat_signals',
          'filter': 'user_id=eq.ama',
        },
    ]);
    await listening.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(client.getChannels(), isEmpty);
  });

  test('a busy server and any failure answer fixed codes', () async {
    final busy = DatingChatRepository(
      DatingRpc.withCall(
        (fn, params) async =>
            throw const PostgrestException(message: 'dating:busy'),
      ),
      null,
    );
    expect((await busy.messages('m1')).reason, 'busy');
    expect((await busy.send('key-0123456789abcdef', 'm1', 'x')).reason, 'busy');
    expect((await busy.conversations()).reason, 'busy');
    final broken = DatingChatRepository(
      DatingRpc.withCall((fn, params) async => throw StateError('socket')),
      null,
    );
    expect((await broken.messages('m1')).reason, 'failed');
    expect((await broken.offerSwap('m1')).reason, 'failed');
    expect(
      (await broken.unmatch('key-0123456789abcdef', 'm1')).reason,
      'failed',
    );
  });

  test('D8: the list is one entry per account; the next account\'s starts '
      'loading and holds nothing of the last', () async {
    final fake = FakeDatingChat();
    final container = ProviderContainer(overrides: datingChatOverrides(fake));
    addTearDown(container.dispose);
    final sub = container.listen(
      datingConversationsProvider('ama'),
      (_, __) {},
    );
    addTearDown(sub.close);
    final ama = await container.read(datingConversationsProvider('ama').future);
    expect(ama.conversations.first.displayName, 'Kofi');
    fake.listHold = Completer<DatingConversations>();
    final next = container.listen(
      datingConversationsProvider('esi'),
      (_, __) {},
    );
    addTearDown(next.close);
    final esi = container.read(datingConversationsProvider('esi'));
    expect(esi.isLoading, isTrue);
    expect(esi.valueOrNull, isNull);
    // The last account's entry is disposed once nothing shows it.
    sub.close();
    await Future<void>.delayed(Duration.zero);
    expect(container.exists(datingConversationsProvider('ama')), isFalse);
    expect(
      container.read(datingConversationsProvider(null).future),
      completion(predicate<DatingConversations>((d) => !d.ok)),
    );
  });

  test(
    'each chat signal is a new count; nothing listens while signed out',
    () async {
      // Fallback poll: the signals now also watch the app's lifecycle and
      // the connection (pinned online here).
      TestWidgetsFlutterBinding.ensureInitialized();
      final fake = FakeDatingChat();
      final container = ProviderContainer(
        overrides: [
          ...datingChatOverrides(fake),
          datingOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
      );
      addTearDown(container.dispose);
      final seen = <int>[];
      final sub = container.listen(
        datingChatSignalsProvider('ama'),
        (previous, next) {
          if (next.reads != previous?.reads) seen.add(next.reads);
        },
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      fake.signalEvents.add(null);
      fake.signalEvents.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [1, 2]);
      expect(fake.signalAccounts, ['ama']);
      final none = container.listen(
        datingChatSignalsProvider(null),
        (_, __) {},
      );
      addTearDown(none.close);
      await Future<void>.delayed(Duration.zero);
      expect(fake.signalAccounts, ['ama']);
    },
  );

  test('the fake answers as the server does: masked before both swap, '
      'withdraw is mine false, older pages, a refusal per call, a signal '
      'stream per account', () async {
    final fake = FakeDatingChat(
      page: datingPageJson(
        messages: [
          datingMessageJson('d3', 'Text me on 024 123 4567', minute: 3),
          datingMessageJson('d2', 'or ama@mail.com', minute: 2),
          datingMessageJson('d1', 'Hi', mine: true, minute: 1),
        ],
      ),
      list: datingConversationsJson(
        rows: [
          {
            'match_id': 'm1',
            'display_name': 'Kofi',
            'last': datingMessageJson('d3', 'Text me on 024 123 4567'),
          },
        ],
      ),
    );
    const key = 'key-0123456789abcdef';
    final page = await fake.messages('m1');
    expect(
      [for (final m in page.messages) m.text],
      ['Text me on •••', 'or •••', 'Hi'],
    );
    expect(
      (await fake.conversations()).conversations.single.last!.text,
      'Text me on •••',
    );
    expect(
      (await fake.send(
        key,
        'm1',
        'wa.me/233241234567 or @kofi_g',
      )).message!.text,
      '••• or •••',
    );
    final older = await fake.messages('m1', before: page.messages[1].at);
    expect([for (final m in older.messages) m.id], ['d1']);
    expect(older.more, isFalse);
    expect(fake.reads.last, ('m1', page.messages[1].at));

    final withdrawn = await fake.withdrawSwap('m1');
    expect(withdrawn.ok, isTrue);
    expect(withdrawn.swap!.mine, isFalse);
    expect((await fake.offerSwap('m1')).swap!.mine, isTrue);

    // The server's own refusals: a bad key, an ended chat, before 72 hours,
    // a withdraw after both swapped.
    expect((await fake.send('short', 'm1', 'Hi')).reason, 'invalid');
    expect((await fake.block('short', 'm1')).reason, 'invalid');
    expect((await fake.unmatch('short', 'm1')).reason, 'invalid');
    fake.pageJson = datingPageJson(ended: true);
    expect((await fake.send(key, 'm1', 'Hi')).reason, 'closed');
    expect((await fake.offerSwap('m1')).reason, 'closed');
    fake.pageJson = datingPageJson(
      swapFrom: datingChatT0.add(const Duration(days: 2)),
    );
    final early = await fake.offerSwap('m1');
    expect(early.reason, 'too_early');
    expect(early.from, datingChatT0.add(const Duration(days: 2)));
    fake.pageJson = datingPageJson(
      swap: const {'mine': true, 'theirs': true, 'both': true},
      messages: [datingMessageJson('d4', 'Call 024 123 4567')],
    );
    expect((await fake.withdrawSwap('m1')).reason, 'already_swapped');
    // Once both swapped nothing is masked.
    expect(
      (await fake.messages('m1')).messages.single.text,
      'Call 024 123 4567',
    );
    expect(
      (await fake.send(key, 'm1', 'Call 024 123 4567')).message!.text,
      'Call 024 123 4567',
    );

    // A refusal per call, any of the fixed codes.
    for (final reason in [...datingChatReasons, 'failed']) {
      fake.refusals['send'] = reason;
      expect((await fake.send(key, 'm1', 'Hi')).reason, reason);
    }
    fake.refusals
      ..clear()
      ..addAll({
        'conversations': 'reverify_device',
        'messages': 'match_unavailable',
        'offerSwap': 'unavailable',
        'withdrawSwap': 'restricted',
        'block': 'rate_limited',
        'unmatch': 'busy',
      });
    expect((await fake.conversations()).reason, 'reverify_device');
    expect((await fake.messages('m1')).reason, 'match_unavailable');
    expect((await fake.offerSwap('m1')).reason, 'unavailable');
    expect((await fake.withdrawSwap('m1')).reason, 'restricted');
    expect((await fake.block(key, 'm1')).reason, 'rate_limited');
    expect((await fake.unmatch(key, 'm1')).reason, 'busy');

    // Each account its own signals.
    final ama = <int>[];
    final esi = <int>[];
    // Fallback poll: the changes (the channel's own join is not one).
    final a = fake.signals('ama').listen((s) {
      if (s == DatingChatSignal.changed) ama.add(1);
    });
    final e = fake.signals('esi').listen((s) {
      if (s == DatingChatSignal.changed) esi.add(1);
    });
    addTearDown(a.cancel);
    addTearDown(e.cancel);
    fake.signalsFor('ama').add(null);
    await Future<void>.delayed(Duration.zero);
    expect(
      [ama, esi],
      [
        [1],
        <int>[],
      ],
    );
    fake.signalEvents.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(
      [ama, esi],
      [
        [1],
        [1],
      ],
    );
  });
}

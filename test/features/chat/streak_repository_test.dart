import 'dart:convert';
import 'dart:io';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A real SupabaseClient whose HTTP goes to [respond] (same harness as
/// supabase_get_conversation_unread_test.dart): the RPC name, path and
/// body the repository actually sends are what is asserted, not its
/// source text.
SupabaseClient _client(
  List<http.Request> sent,
  http.Response Function(http.Request request) respond,
) {
  return SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    httpClient: MockClient((request) async {
      sent.add(request);
      return respond(request);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

http.Response _json(http.Request request, Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
  request: request,
);

void main() {
  test('StreakClip parses a row, and clips sort into playback order', () {
    final clips = [
      StreakClip.fromRow(const {
        'clip_index': 1,
        'media_url': 'b',
        'duration_ms': 20000,
      }),
      StreakClip.fromRow(const {
        'clip_index': 0,
        'media_url': 'a',
        'duration_ms': 60000,
      }),
    ]..sort((x, y) => x.index.compareTo(y.index));

    expect(clips.map((c) => c.mediaUrl), ['a', 'b']);
    expect(clips.first.durationMs, 60000);
  });

  test('fetchClips calls streak_clips_for_viewing and parses its rows', () async {
    // The RPC is what enforces "readable only inside the 30-minute replay
    // window"; a direct table read would hand out an expired clip. (Its
    // RETURNS TABLE is clip_index, media_url, duration_ms, media_kind:
    // still no caption or budget, which supabase/tests/
    // streak_replay_window_contracts.sql pins server-side.) A misnamed
    // parameter would fail every streak at runtime (PGRST202), so the
    // request itself is asserted.
    final sent = <http.Request>[];
    final client = _client(
      sent,
      (request) => _json(request, [
        {
          'clip_index': 0,
          'media_url': 'chat/a',
          'duration_ms': 3000,
          'media_kind': 'video',
        },
        {
          'clip_index': 1,
          'media_url': 'chat/b',
          'duration_ms': 0,
          'media_kind': 'photo',
        },
      ]),
    );
    addTearDown(client.dispose);

    final clips = await StreakRepository(client: client).fetchClips('m1');

    expect(sent, hasLength(1));
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/rest/v1/rpc/streak_clips_for_viewing');
    expect(jsonDecode(sent.single.body), {'p_message_id': 'm1'});
    expect(clips.map((c) => c.index), [0, 1]);
    expect(clips.map((c) => c.mediaUrl), ['chat/a', 'chat/b']);
    expect(clips.map((c) => c.mediaKind), [
      StreakClipKind.video,
      StreakClipKind.photo,
    ]);
    expect(clips.first.durationMs, 3000);
  });

  test('markViewed spends through the RPC with the open id', () async {
    // The open id is what makes a retried spend idempotent server-side
    // (mark_streak_viewed(p_message_id, p_open_id), 20261019140100).
    final sent = <http.Request>[];
    final client = _client(sent, (request) => _json(request, 2));
    addTearDown(client.dispose);

    final left = await StreakRepository(
      client: client,
    ).markViewed('m1', openId: 'open-1');

    expect(left, 2);
    expect(sent, hasLength(1));
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/rest/v1/rpc/mark_streak_viewed');
    expect(jsonDecode(sent.single.body), {
      'p_message_id': 'm1',
      'p_open_id': 'open-1',
    });
  });

  test('markViewed goes through the RPC, never a direct update', () {
    // messages' RLS would let a client write any value, including
    // refilling its own budget.
    final src =
        File(
          'lib/features/chat/data/repositories/streak_repository.dart',
        ).readAsStringSync();

    expect(src, contains("rpc(\n      'mark_streak_viewed'"));
    expect(
      src,
      isNot(contains("update({'streak_views_remaining'")),
      reason: 'the budget must never be client-writable',
    );
  });
}

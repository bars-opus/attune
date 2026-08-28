import 'dart:io';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StreakClip parses a row, and clips sort into playback order', () {
    final clips = [
      StreakClip.fromRow(
          const {'clip_index': 1, 'media_url': 'b', 'duration_ms': 20000}),
      StreakClip.fromRow(
          const {'clip_index': 0, 'media_url': 'a', 'duration_ms': 60000}),
    ]..sort((x, y) => x.index.compareTo(y.index));

    expect(clips.map((c) => c.mediaUrl), ['a', 'b']);
    expect(clips.first.durationMs, 60000);
  });

  test('fetchClips selects no caption or budget columns', () {
    // The caption is view-time only and the budget is server-owned. A
    // client select pulling either invites rendering them in the chat
    // row, which the spec forbids.
    final src = File(
      'lib/features/chat/data/repositories/streak_repository.dart',
    ).readAsStringSync();
    final select = RegExp(r"\.select\('([^']*clip_index[^']*)'\)")
        .firstMatch(src)
        ?.group(1);

    expect(select, isNotNull);
    expect(select, contains('media_url'));
    expect(select, isNot(contains('caption')));
    expect(select, isNot(contains('streak_views_remaining')));
  });

  test('markViewed goes through the RPC, never a direct update', () {
    // messages' RLS would let a client write any value, including
    // refilling its own budget.
    final src = File(
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

import 'dart:async';

import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(int i) => {
  'id': 'm-${i.toString().padLeft(3, '0')}',
  'updated_at': '2026-10-19T10:00:${i.toString().padLeft(2, '0')}.000000+00:00',
};

List<Map<String, dynamic>> _rows(int from, int count) => [
  for (var i = from; i < from + count; i++) _row(i),
];

void main() {
  const limit = 3;
  const maxPages = 4;
  const pageTimeout = Duration(milliseconds: 50);

  test(
    'pages on the exact (updated_at, id) of the last row received',
    () async {
      final asked = <(String?, String?)>[];
      final rows = await collectChangedSincePages(
        fetchPage: (at, id) async {
          asked.add((at, id));
          return _rows(asked.length * limit - limit, limit);
        },
        startUpdatedAt: null,
        startId: null,
        limit: limit,
        maxPages: maxPages,
        pageTimeout: pageTimeout,
      );

      expect(rows, hasLength(limit * maxPages), reason: 'cut at the cap');
      expect(asked.first, (null, null));
      expect(asked[1], (_row(2)['updated_at'], _row(2)['id']));
      expect(asked.last, (_row(8)['updated_at'], _row(8)['id']));
    },
  );

  test('a short page ends the read', () async {
    var calls = 0;
    final rows = await collectChangedSincePages(
      fetchPage: (at, id) async => calls++ == 0 ? _rows(0, limit) : _rows(3, 1),
      startUpdatedAt: null,
      startId: null,
      limit: limit,
      maxPages: maxPages,
      pageTimeout: pageTimeout,
    );
    expect(rows, hasLength(limit + 1));
    expect(calls, 2);
  });

  test('a slow later page keeps the pages that arrived (progress on a slow '
      'link)', () async {
    var calls = 0;
    final rows = await collectChangedSincePages(
      fetchPage: (at, id) {
        calls++;
        if (calls <= 2) return Future.value(_rows((calls - 1) * limit, limit));
        return Completer<List<Map<String, dynamic>>>().future; // never answers
      },
      startUpdatedAt: null,
      startId: null,
      limit: limit,
      maxPages: maxPages,
      pageTimeout: pageTimeout,
    );
    expect(rows, hasLength(2 * limit));
    expect(
      rows.length,
      lessThan(limit * maxPages),
      reason: 'shorter than the cap, so the caller commits what it got',
    );
  });

  test('a later page that errors keeps the pages that arrived', () async {
    var calls = 0;
    final rows = await collectChangedSincePages(
      fetchPage: (at, id) async {
        calls++;
        if (calls == 2) throw Exception('connection reset');
        return _rows(0, limit);
      },
      startUpdatedAt: null,
      startId: null,
      limit: limit,
      maxPages: maxPages,
      pageTimeout: pageTimeout,
    );
    expect(rows, hasLength(limit));
  });

  test('a first page that never answers fails the read', () async {
    await expectLater(
      collectChangedSincePages(
        fetchPage: (at, id) => Completer<List<Map<String, dynamic>>>().future,
        startUpdatedAt: null,
        startId: null,
        limit: limit,
        maxPages: maxPages,
        pageTimeout: pageTimeout,
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a continuation starts from the caller\'s (since, afterId)', () async {
    final asked = <(String?, String?)>[];
    await collectChangedSincePages(
      fetchPage: (at, id) async {
        asked.add((at, id));
        return const [];
      },
      startUpdatedAt: '2026-10-19T10:00:00.123456+00:00',
      startId: 'm-9',
      limit: limit,
      maxPages: maxPages,
      pageTimeout: pageTimeout,
    );
    expect(asked, [('2026-10-19T10:00:00.123456+00:00', 'm-9')]);
  });
}

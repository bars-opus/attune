import 'dart:convert';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/forums/data/cache/forum_feed_cache.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userA = 'user-aaa';
const _userB = 'user-bbb';

TopicModel _topic(
  String id, {
  String? userVote,
  String? userSide,
  String content = 'topic content',
}) {
  return TopicModel(
    id: id,
    content: content,
    submitterStatus: 'single',
    status: 'active',
    upvoteCount: 5,
    downvoteCount: 2,
    seenCount: 30,
    totalPosts: 7,
    forPosts: 4,
    againstPosts: 3,
    lastPostAt: DateTime.utc(2026, 7, 24, 9),
    activatedAt: DateTime.utc(2026, 7, 23, 8),
    votingExpiresAt: DateTime.utc(2026, 7, 26, 10),
    createdAt: DateTime.utc(2026, 7, 22, 7),
    userVote: userVote,
    userSide: userSide,
  );
}

Future<(ForumFeedCache, SharedPreferences)> _makeCache([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return (container.read(forumFeedCacheProvider), prefs);
}

void main() {
  group('ForumFeedCache', () {
    test('round-trips every field a topic carries', () async {
      final (cache, _) = await _makeCache();
      final original = _topic('a', userVote: 'up', userSide: 'FOR');

      await cache.writeFeed(ForumFeed.active, _userA, [original]);
      final restored = cache.readFeed(ForumFeed.active, _userA).single;

      expect(restored.id, original.id);
      expect(restored.content, original.content);
      expect(restored.submitterStatus, original.submitterStatus);
      expect(restored.status, original.status);
      expect(restored.upvoteCount, original.upvoteCount);
      expect(restored.downvoteCount, original.downvoteCount);
      expect(restored.seenCount, original.seenCount);
      expect(restored.totalPosts, original.totalPosts);
      expect(restored.forPosts, original.forPosts);
      expect(restored.againstPosts, original.againstPosts);
      expect(restored.lastPostAt, original.lastPostAt);
      expect(restored.activatedAt, original.activatedAt);
      expect(restored.votingExpiresAt, original.votingExpiresAt);
      expect(restored.createdAt, original.createdAt);
    });

    test(
      'round-trips userVote/userSide, which fromJson takes as named args',
      () async {
        // These two don't come from the JSON map on the live path, so a
        // naive toJson/fromJson pair silently drops the viewer's own vote.
        final (cache, _) = await _makeCache();

        await cache.writeFeed(ForumFeed.contributing, _userA, [
          _topic('a', userVote: 'down', userSide: 'AGAINST'),
        ]);
        final restored = cache.readFeed(ForumFeed.contributing, _userA).single;

        expect(restored.userVote, 'down');
        expect(restored.userSide, 'AGAINST');
        expect(restored.displaySide, 'AGAINST');
      },
    );

    test(
      'keeps null userVote/userSide null rather than inventing a side',
      () async {
        final (cache, _) = await _makeCache();

        await cache.writeFeed(ForumFeed.voting, _userA, [_topic('a')]);
        final restored = cache.readFeed(ForumFeed.voting, _userA).single;

        expect(restored.userVote, isNull);
        expect(restored.userSide, isNull);
        expect(restored.displaySide, isNull);
      },
    );

    test('handles null lastPostAt/activatedAt', () async {
      final (cache, _) = await _makeCache();
      final neverPosted = TopicModel(
        id: 'n',
        content: 'c',
        status: 'voting',
        upvoteCount: 0,
        downvoteCount: 0,
        seenCount: 0,
        totalPosts: 0,
        forPosts: 0,
        againstPosts: 0,
        votingExpiresAt: DateTime.utc(2026, 8),
        createdAt: DateTime.utc(2026, 7),
      );

      await cache.writeFeed(ForumFeed.voting, _userA, [neverPosted]);
      final restored = cache.readFeed(ForumFeed.voting, _userA).single;

      expect(restored.lastPostAt, isNull);
      expect(restored.activatedAt, isNull);
      expect(restored.submitterStatus, isNull);
    });

    test('returns empty on a cold miss', () async {
      final (cache, _) = await _makeCache();
      expect(cache.readFeed(ForumFeed.active, _userA), isEmpty);
    });

    test('keeps all four lists separate', () async {
      final (cache, _) = await _makeCache();

      await cache.writeFeed(ForumFeed.voting, _userA, [_topic('v')]);
      await cache.writeFeed(ForumFeed.active, _userA, [_topic('a')]);
      await cache.writeFeed(ForumFeed.quiet, _userA, [_topic('q')]);
      await cache.writeFeed(ForumFeed.contributing, _userA, [_topic('c')]);

      expect(cache.readFeed(ForumFeed.voting, _userA).single.id, 'v');
      expect(cache.readFeed(ForumFeed.active, _userA).single.id, 'a');
      expect(cache.readFeed(ForumFeed.quiet, _userA).single.id, 'q');
      expect(cache.readFeed(ForumFeed.contributing, _userA).single.id, 'c');
    });

    test(
      'isolates users, so one account never reads another\'s vote state',
      () async {
        final (cache, prefs) = await _makeCache();

        await cache.writeFeed(ForumFeed.contributing, _userA, [
          _topic('a', userVote: 'up', userSide: 'FOR'),
        ]);

        expect(cache.readFeed(ForumFeed.contributing, _userB), isEmpty);
        expect(cache.readFeed(ForumFeed.contributing, _userA), isNotEmpty);

        final keys = prefs.getKeys().where(
          (k) => k.startsWith('forum_feed_cache_'),
        );
        expect(keys, contains('forum_feed_cache_${_userA}_contributing'));
      },
    );

    test('does not collide with the opinions cache namespace', () async {
      final (cache, prefs) = await _makeCache();
      await cache.writeFeed(ForumFeed.active, _userA, [_topic('a')]);

      final keys = prefs.getKeys();
      expect(keys.where((k) => k.startsWith('opinion_feed_cache_')), isEmpty);
      expect(keys.where((k) => k.startsWith('forum_feed_cache_')), isNotEmpty);
    });

    test('caps what it persists at maxCachedItems', () async {
      final (cache, _) = await _makeCache();
      final tooMany = List.generate(
        ForumFeedCache.maxCachedItems + 15,
        (i) => _topic('id-$i'),
      );

      await cache.writeFeed(ForumFeed.active, _userA, tooMany);
      final restored = cache.readFeed(ForumFeed.active, _userA);

      expect(restored, hasLength(ForumFeedCache.maxCachedItems));
      expect(restored.first.id, 'id-0');
    });

    test('treats a corrupt payload as a miss and clears it', () async {
      final key = 'forum_feed_cache_${_userA}_active';
      final (cache, prefs) = await _makeCache({key: 'not valid json{{'});

      expect(cache.readFeed(ForumFeed.active, _userA), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(key), isNull);
    });

    test('treats an older schema version as a miss', () async {
      final key = 'forum_feed_cache_${_userA}_active';
      final stale = jsonEncode({
        'v': ForumFeedCache.currentSchemaVersion - 1,
        'writtenAt': DateTime.now().millisecondsSinceEpoch,
        'rows': [_topic('a').toCachedJson()],
      });
      final (cache, prefs) = await _makeCache({key: stale});

      expect(cache.readFeed(ForumFeed.active, _userA), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(key), isNull);
    });

    test('treats a payload past maxAge as a miss', () async {
      final key = 'forum_feed_cache_${_userA}_active';
      final expired = jsonEncode({
        'v': ForumFeedCache.currentSchemaVersion,
        'writtenAt':
            DateTime.now()
                .subtract(ForumFeedCache.maxAge + const Duration(minutes: 1))
                .millisecondsSinceEpoch,
        'rows': [_topic('a').toCachedJson()],
      });
      final (cache, prefs) = await _makeCache({key: expired});

      expect(cache.readFeed(ForumFeed.active, _userA), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(key), isNull);
    });

    test('still serves a payload just inside maxAge', () async {
      final key = 'forum_feed_cache_${_userA}_active';
      final fresh = jsonEncode({
        'v': ForumFeedCache.currentSchemaVersion,
        'writtenAt':
            DateTime.now()
                .subtract(ForumFeedCache.maxAge - const Duration(minutes: 1))
                .millisecondsSinceEpoch,
        'rows': [_topic('a').toCachedJson()],
      });
      final (cache, _) = await _makeCache({key: fresh});

      expect(cache.readFeed(ForumFeed.active, _userA).single.id, 'a');
    });

    test('rejects a future timestamp rather than caching it forever', () async {
      final key = 'forum_feed_cache_${_userA}_active';
      final futureStamp = jsonEncode({
        'v': ForumFeedCache.currentSchemaVersion,
        'writtenAt':
            DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch,
        'rows': [_topic('a').toCachedJson()],
      });
      final (cache, _) = await _makeCache({key: futureStamp});

      expect(cache.readFeed(ForumFeed.active, _userA), isEmpty);
    });

    test('treats a payload with no timestamp as a miss', () async {
      final key = 'forum_feed_cache_${_userA}_active';
      final noStamp = jsonEncode({
        'v': ForumFeedCache.currentSchemaVersion,
        'rows': [_topic('a').toCachedJson()],
      });
      final (cache, _) = await _makeCache({key: noStamp});

      expect(cache.readFeed(ForumFeed.active, _userA), isEmpty);
    });

    test('clear() removes only the targeted list', () async {
      final (cache, _) = await _makeCache();
      await cache.writeFeed(ForumFeed.active, _userA, [_topic('a')]);
      await cache.writeFeed(ForumFeed.quiet, _userA, [_topic('q')]);

      await cache.clearFeed(ForumFeed.active, _userA);

      expect(cache.readFeed(ForumFeed.active, _userA), isEmpty);
      expect(cache.readFeed(ForumFeed.quiet, _userA), isNotEmpty);
    });

    test('overwrites rather than appending on repeat writes', () async {
      final (cache, _) = await _makeCache();

      await cache.writeFeed(ForumFeed.active, _userA, [_topic('first')]);
      await cache.writeFeed(ForumFeed.active, _userA, [_topic('second')]);

      final restored = cache.readFeed(ForumFeed.active, _userA);
      expect(restored, hasLength(1));
      expect(restored.single.id, 'second');
    });
  });
}

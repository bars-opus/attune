import 'dart:convert';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/opinions/data/cache/opinion_feed_cache.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key shape is asserted directly in the per-user isolation test rather than
/// reconstructed here, so a key-format change fails loudly instead of these
/// helpers silently following it.
const _userA = 'user-aaa';
const _userB = 'user-bbb';

OpinionModel _opinion(
  String id, {
  bool isMine = false,
  String? userReaction,
  String content = 'content',
  bool isSaved = false,
  int repostCount = 5,
  bool isRepostedByMe = false,
  String? quotedOpinionId,
  DateTime? editedAt,
  List<String> tags = const [],
}) {
  return OpinionModel(
    id: id,
    authorHandle: 'handle-$id',
    isMine: isMine,
    content: content,
    relationshipStatus: 'single',
    likeCount: 1,
    dislikeCount: 2,
    commentCount: 3,
    followerCount: 4,
    userReaction: userReaction,
    isSaved: isSaved,
    repostCount: repostCount,
    isRepostedByMe: isRepostedByMe,
    quotedOpinionId: quotedOpinionId,
    editedAt: editedAt,
    tags: tags,
    createdAt: DateTime.utc(2026, 7, 25, 12),
  );
}

Future<(OpinionFeedCache, SharedPreferences)> _makeCache([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return (container.read(opinionFeedCacheProvider), prefs);
}

void main() {
  group('OpinionFeedCache', () {
    test('round-trips every field a feed row carries', () async {
      final (cache, _) = await _makeCache();
      final original = _opinion(
        'a',
        isMine: true,
        userReaction: 'like',
        isSaved: true,
        repostCount: 7,
        isRepostedByMe: true,
      );

      await cache.writeFeed(OpinionFeed.discover, _userA, [original]);
      final restored = cache.readFeed(OpinionFeed.discover, _userA).single;

      expect(restored.id, original.id);
      expect(restored.authorHandle, original.authorHandle);
      expect(restored.isMine, isTrue);
      expect(restored.content, original.content);
      expect(restored.relationshipStatus, original.relationshipStatus);
      expect(restored.likeCount, original.likeCount);
      expect(restored.dislikeCount, original.dislikeCount);
      expect(restored.commentCount, original.commentCount);
      expect(restored.followerCount, original.followerCount);
      expect(restored.userReaction, 'like');
      expect(restored.isSaved, isTrue);
      expect(restored.repostCount, 7);
      expect(restored.isRepostedByMe, isTrue);
      expect(restored.createdAt, original.createdAt);
    });

    test('returns empty on a cold miss', () async {
      final (cache, _) = await _makeCache();
      expect(cache.readFeed(OpinionFeed.discover, _userA), isEmpty);
    });

    test('keeps discover and following separate', () async {
      final (cache, _) = await _makeCache();

      await cache.writeFeed(OpinionFeed.discover, _userA, [_opinion('d')]);
      await cache.writeFeed(OpinionFeed.following, _userA, [_opinion('f')]);

      expect(cache.readFeed(OpinionFeed.discover, _userA).single.id, 'd');
      expect(cache.readFeed(OpinionFeed.following, _userA).single.id, 'f');
    });

    test(
      'isolates users, so one account never reads another\'s viewer state',
      () async {
        final (cache, prefs) = await _makeCache();

        await cache.writeFeed(OpinionFeed.discover, _userA, [
          _opinion('a', isMine: true, userReaction: 'like'),
        ]);

        // B must not see A's rows at all — isMine/my_reaction are per-viewer.
        expect(cache.readFeed(OpinionFeed.discover, _userB), isEmpty);
        expect(cache.readFeed(OpinionFeed.discover, _userA), isNotEmpty);

        // The persisted key must carry the user id, otherwise the logout
        // sweep and this isolation both quietly stop working.
        final keys = prefs.getKeys().where(
          (k) => k.startsWith('opinion_feed_cache_'),
        );
        expect(keys, contains('opinion_feed_cache_${_userA}_discover'));
      },
    );

    test('caps what it persists at maxCachedItems', () async {
      final (cache, _) = await _makeCache();
      final tooMany = List.generate(
        OpinionFeedCache.maxCachedItems + 15,
        (i) => _opinion('id-$i'),
      );

      await cache.writeFeed(OpinionFeed.discover, _userA, tooMany);
      final restored = cache.readFeed(OpinionFeed.discover, _userA);

      expect(restored, hasLength(OpinionFeedCache.maxCachedItems));
      // Keeps the head of the list (newest-first from the RPC), not the tail.
      expect(restored.first.id, 'id-0');
    });

    test('treats a corrupt payload as a miss and clears it', () async {
      final key = 'opinion_feed_cache_${_userA}_discover';
      final (cache, prefs) = await _makeCache({key: 'not valid json{{'});

      expect(cache.readFeed(OpinionFeed.discover, _userA), isEmpty);
      await Future<void>.delayed(Duration.zero); // let the unawaited clear run
      expect(prefs.getString(key), isNull);
    });

    test('treats an older schema version as a miss', () async {
      final key = 'opinion_feed_cache_${_userA}_discover';
      final stalePayload = jsonEncode({
        'v': OpinionFeedCache.currentSchemaVersion - 1,
        'writtenAt': DateTime.now().millisecondsSinceEpoch,
        'rows': [_opinion('a').toFeedRow()],
      });
      final (cache, prefs) = await _makeCache({key: stalePayload});

      expect(cache.readFeed(OpinionFeed.discover, _userA), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(key), isNull);
    });

    test('treats a payload past maxAge as a miss', () async {
      final key = 'opinion_feed_cache_${_userA}_discover';
      final expired = jsonEncode({
        'v': OpinionFeedCache.currentSchemaVersion,
        'writtenAt':
            DateTime.now()
                .subtract(OpinionFeedCache.maxAge + const Duration(minutes: 1))
                .millisecondsSinceEpoch,
        'rows': [_opinion('a').toFeedRow()],
      });
      final (cache, prefs) = await _makeCache({key: expired});

      expect(cache.readFeed(OpinionFeed.discover, _userA), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(key), isNull);
    });

    test('still serves a payload just inside maxAge', () async {
      final key = 'opinion_feed_cache_${_userA}_discover';
      final fresh = jsonEncode({
        'v': OpinionFeedCache.currentSchemaVersion,
        'writtenAt':
            DateTime.now()
                .subtract(OpinionFeedCache.maxAge - const Duration(minutes: 1))
                .millisecondsSinceEpoch,
        'rows': [_opinion('a').toFeedRow()],
      });
      final (cache, _) = await _makeCache({key: fresh});

      expect(cache.readFeed(OpinionFeed.discover, _userA).single.id, 'a');
    });

    test('rejects a future timestamp rather than caching it forever', () async {
      final key = 'opinion_feed_cache_${_userA}_discover';
      // A backwards device-clock change leaves writtenAt in the future;
      // a naive age check would read that as "always fresh".
      final futureStamp = jsonEncode({
        'v': OpinionFeedCache.currentSchemaVersion,
        'writtenAt':
            DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch,
        'rows': [_opinion('a').toFeedRow()],
      });
      final (cache, _) = await _makeCache({key: futureStamp});

      expect(cache.readFeed(OpinionFeed.discover, _userA), isEmpty);
    });

    test('treats a payload with no timestamp as a miss', () async {
      final key = 'opinion_feed_cache_${_userA}_discover';
      final noStamp = jsonEncode({
        'v': OpinionFeedCache.currentSchemaVersion,
        'rows': [_opinion('a').toFeedRow()],
      });
      final (cache, _) = await _makeCache({key: noStamp});

      expect(cache.readFeed(OpinionFeed.discover, _userA), isEmpty);
    });

    test('clear() removes only the targeted feed', () async {
      final (cache, _) = await _makeCache();
      await cache.writeFeed(OpinionFeed.discover, _userA, [_opinion('d')]);
      await cache.writeFeed(OpinionFeed.following, _userA, [_opinion('f')]);

      await cache.clearFeed(OpinionFeed.discover, _userA);

      expect(cache.readFeed(OpinionFeed.discover, _userA), isEmpty);
      expect(cache.readFeed(OpinionFeed.following, _userA), isNotEmpty);
    });

    test('overwrites rather than appending on repeat writes', () async {
      final (cache, _) = await _makeCache();

      await cache.writeFeed(OpinionFeed.discover, _userA, [_opinion('first')]);
      await cache.writeFeed(OpinionFeed.discover, _userA, [_opinion('second')]);

      final restored = cache.readFeed(OpinionFeed.discover, _userA);
      expect(restored, hasLength(1));
      expect(restored.single.id, 'second');
    });

    test('preserves a saved opinion through a cache round-trip', () async {
      final (cache, _) = await _makeCache();

      await cache.writeFeed(OpinionFeed.discover, _userA, [
        _opinion('saved', isSaved: true),
        _opinion('unsaved'),
      ]);
      final restored = cache.readFeed(OpinionFeed.discover, _userA);

      // A bookmark that survives to the cache but not back out of it renders
      // as an empty bookmark on relaunch — the failure mode this guards.
      expect(restored.firstWhere((o) => o.id == 'saved').isSaved, isTrue);
      expect(restored.firstWhere((o) => o.id == 'unsaved').isSaved, isFalse);
    });

    test(
      'preserves repost state and count through a cache round-trip',
      () async {
        final (cache, _) = await _makeCache();

        await cache.writeFeed(OpinionFeed.discover, _userA, [
          _opinion('reposted', repostCount: 12, isRepostedByMe: true),
          _opinion('plain', repostCount: 0),
        ]);
        final restored = cache.readFeed(OpinionFeed.discover, _userA);

        // Same failure mode the isSaved test above guards: a repost that
        // survives into the cache but not back out renders as a hollow repeat
        // icon with the wrong count on relaunch.
        final reposted = restored.firstWhere((o) => o.id == 'reposted');
        expect(reposted.isRepostedByMe, isTrue);
        expect(reposted.repostCount, 12);
        final plain = restored.firstWhere((o) => o.id == 'plain');
        expect(plain.isRepostedByMe, isFalse);
        expect(plain.repostCount, 0);
      },
    );

    test('preserves quotedOpinionId through a cache round-trip', () async {
      final (cache, _) = await _makeCache();

      await cache.writeFeed(OpinionFeed.discover, _userA, [
        _opinion('quote', quotedOpinionId: 'original-99'),
        _opinion('plain'),
      ]);
      final restored = cache.readFeed(OpinionFeed.discover, _userA);

      // Same failure mode the isSaved/repost tests guard: a quote that
      // survives into the cache but not back out renders on relaunch as a
      // plain opinion with its embedded original silently missing.
      expect(
        restored.firstWhere((o) => o.id == 'quote').quotedOpinionId,
        'original-99',
      );
      expect(
        restored.firstWhere((o) => o.id == 'plain').quotedOpinionId,
        isNull,
      );
    });

    test('preserves tags through a cache round-trip', () async {
      final (cache, _) = await _makeCache();

      await cache.writeFeed(OpinionFeed.discover, _userA, [
        _opinion('tagged', tags: const ['dating', 'red flags']),
        _opinion('untagged'),
      ]);
      final restored = cache.readFeed(OpinionFeed.discover, _userA);

      // Tags are NOT a column on any feed RPC — they are merged in from a
      // separate batch call. So the cache is the only thing carrying them
      // across a relaunch: a tag that survives in but not back out means a
      // restored card silently renders with no chips until the next batch
      // fetch lands.
      expect(restored.firstWhere((o) => o.id == 'tagged').tags, [
        'dating',
        'red flags',
      ]);
      expect(restored.firstWhere((o) => o.id == 'untagged').tags, isEmpty);
    });
  });

  group('OpinionModel feed-row mapping', () {
    // toFeedRow and fromFeedRow must mirror each other key-for-key: a field
    // written by one and not read by the other silently loses its value on
    // every cache round-trip. Asserted directly here so a regression names the
    // mapping rather than surfacing as a confusing cache failure.
    test('round-trips isSaved in both directions', () {
      for (final saved in [true, false]) {
        final row = _opinion('a', isSaved: saved).toFeedRow();
        expect(row['is_saved'], saved, reason: 'toFeedRow must emit is_saved');
        expect(OpinionModel.fromFeedRow(row).isSaved, saved);
      }
    });

    test('defaults isSaved to false when the column is absent', () {
      // get_saved_opinions predates nothing, but older cached payloads and any
      // RPC without the opinion_saves join omit is_saved entirely.
      final row = _opinion('a', isSaved: true).toFeedRow()..remove('is_saved');

      expect(OpinionModel.fromFeedRow(row).isSaved, isFalse);
    });

    test('round-trips repostCount and isRepostedByMe in both directions', () {
      for (final reposted in [true, false]) {
        final row =
            _opinion('a', repostCount: 9, isRepostedByMe: reposted).toFeedRow();
        expect(
          row['repost_count'],
          9,
          reason: 'toFeedRow must emit repost_count',
        );
        expect(
          row['is_reposted_by_me'],
          reposted,
          reason: 'toFeedRow must emit is_reposted_by_me',
        );
        final parsed = OpinionModel.fromFeedRow(row);
        expect(parsed.repostCount, 9);
        expect(parsed.isRepostedByMe, reposted);
      }
    });

    test('defaults the repost fields when the columns are absent', () {
      // Cached payloads written before opinion_reposts existed, and any RPC
      // without the join, omit both columns entirely.
      final row =
          _opinion('a', repostCount: 3, isRepostedByMe: true).toFeedRow()
            ..remove('repost_count')
            ..remove('is_reposted_by_me');

      final parsed = OpinionModel.fromFeedRow(row);
      expect(parsed.repostCount, 0);
      expect(parsed.isRepostedByMe, isFalse);
    });

    test('round-trips quotedOpinionId in both directions', () {
      for (final quotedId in [null, 'original-42']) {
        final row = _opinion('a', quotedOpinionId: quotedId).toFeedRow();
        expect(
          row['quoted_opinion_id'],
          quotedId,
          reason: 'toFeedRow must emit quoted_opinion_id',
        );
        expect(OpinionModel.fromFeedRow(row).quotedOpinionId, quotedId);
      }
    });

    test('defaults quotedOpinionId to null when the column is absent', () {
      // Cached payloads written before opinion_quotes existed omit the column
      // entirely — an opinion with no quote reference is exactly what that is.
      final row =
          _opinion('a', quotedOpinionId: 'original-42').toFeedRow()
            ..remove('quoted_opinion_id');

      expect(OpinionModel.fromFeedRow(row).quotedOpinionId, isNull);
    });

    test('round-trips tags in both directions', () {
      for (final tags in [
        const <String>[],
        const ['love'],
        const ['dating', 'long distance', 'vals day'],
      ]) {
        final row = _opinion('a', tags: tags).toFeedRow();
        expect(row['tags'], tags, reason: 'toFeedRow must emit tags');
        expect(OpinionModel.fromFeedRow(row).tags, tags);
      }
    });

    test('defaults tags to empty when the key is absent', () {
      // The normal case on the live path, not just an old payload: no feed RPC
      // returns tags at all, so every freshly parsed row hits this branch until
      // the batch tag fetch merges them in.
      final row =
          _opinion('a', tags: const ['love']).toFeedRow()..remove('tags');

      expect(OpinionModel.fromFeedRow(row).tags, isEmpty);
    });

    test('copyWith attaches tags without disturbing other fields', () {
      // This is how the batch tag merge lands on an already-parsed page
      // (OpinionRepository.withTags), so it must set tags and preserve
      // everything else the row already carried.
      final original = _opinion(
        'a',
        isSaved: true,
        quotedOpinionId: 'original-42',
      );

      final merged = original.copyWith(tags: const ['healing']);
      expect(merged.tags, ['healing']);
      expect(merged.isSaved, isTrue);
      expect(merged.quotedOpinionId, 'original-42');
    });

    test('copyWith preserves tags across an optimistic toggle', () {
      // Same trap as quotedOpinionId below: an optimistic save/repost patch
      // that dropped tags would strip the chips off a card the instant the
      // user bookmarked it.
      final original = _opinion('a', tags: const ['trust', 'boundaries']);

      expect(original.copyWith(isSaved: true).tags, ['trust', 'boundaries']);
      expect(original.copyWith(isRepostedByMe: true, repostCount: 6).tags, [
        'trust',
        'boundaries',
      ]);
    });

    test('copyWith preserves quotedOpinionId across an optimistic toggle', () {
      // copyWith backs the optimistic save/repost toggles. Dropping the quote
      // reference there would make a quote card lose its embedded original the
      // instant the user bookmarked or reposted it.
      final original = _opinion('a', quotedOpinionId: 'original-42');

      expect(original.copyWith(isSaved: true).quotedOpinionId, 'original-42');
      expect(
        original.copyWith(isRepostedByMe: true, repostCount: 6).quotedOpinionId,
        'original-42',
      );
    });

    test('round-trips editedAt in both directions', () {
      // Encoded as an ISO8601 string, so this asserts the parse back as well
      // as the emit — a DateTime that survives one leg but not the other
      // would silently drop the "(edited)" marker on every cache read.
      final edited = DateTime.utc(2026, 7, 25, 12, 7, 30);

      final editedRow = _opinion('a', editedAt: edited).toFeedRow();
      expect(
        editedRow['edited_at'],
        edited.toIso8601String(),
        reason: 'toFeedRow must emit edited_at as an ISO8601 string',
      );
      expect(OpinionModel.fromFeedRow(editedRow).editedAt, edited);

      final unEditedRow = _opinion('a').toFeedRow();
      expect(unEditedRow['edited_at'], isNull);
      expect(OpinionModel.fromFeedRow(unEditedRow).editedAt, isNull);
    });

    test('defaults editedAt to null when the column is absent', () {
      // Cached payloads written before the edit window existed omit the
      // column entirely — a never-edited opinion is exactly what that is.
      final row =
          _opinion('a', editedAt: DateTime.utc(2026, 7, 25, 12, 7)).toFeedRow()
            ..remove('edited_at');

      expect(OpinionModel.fromFeedRow(row).editedAt, isNull);
    });

    test('preserves editedAt through a full cache round-trip', () async {
      final (cache, _) = await _makeCache();
      final edited = DateTime.utc(2026, 7, 25, 12, 7, 30);

      await cache.writeFeed(OpinionFeed.discover, _userA, [
        _opinion('edited', editedAt: edited),
        _opinion('plain'),
      ]);
      final restored = cache.readFeed(OpinionFeed.discover, _userA);

      expect(restored.firstWhere((o) => o.id == 'edited').editedAt, edited);
      expect(restored.firstWhere((o) => o.id == 'plain').editedAt, isNull);
    });

    test('copyWith preserves editedAt across an optimistic toggle', () {
      // Same trap as quotedOpinionId above: dropping editedAt in copyWith
      // would clear an edited post's "(edited)" marker the instant the user
      // bookmarked or reposted it.
      final edited = DateTime.utc(2026, 7, 25, 12, 7);
      final original = _opinion('a', editedAt: edited);

      expect(original.copyWith(isSaved: true).editedAt, edited);
      expect(
        original.copyWith(isRepostedByMe: true, repostCount: 6).editedAt,
        edited,
      );
    });

    test('copyWith applies an edit without disturbing other fields', () {
      // Backs patchEditedContent: the edit patch must move content and
      // editedAt together and leave the save/repost state alone.
      final original = _opinion(
        'a',
        content: 'before',
        isSaved: true,
        repostCount: 4,
        isRepostedByMe: true,
      );
      final stamp = DateTime.utc(2026, 7, 25, 12, 9);
      final patched = original.copyWith(content: 'after', editedAt: stamp);

      expect(patched.content, 'after');
      expect(patched.editedAt, stamp);
      expect(patched.isSaved, isTrue);
      expect(patched.repostCount, 4);
      expect(patched.isRepostedByMe, isTrue);
      expect(
        original.content,
        'before',
        reason: 'must not mutate the original',
      );
      expect(original.editedAt, isNull);
    });

    test('copyWith moves repost fields without disturbing other fields', () {
      final original = _opinion('a', repostCount: 4, isSaved: true);
      final toggled = original.copyWith(isRepostedByMe: true, repostCount: 5);

      expect(toggled.isRepostedByMe, isTrue);
      expect(toggled.repostCount, 5);
      expect(
        original.isRepostedByMe,
        isFalse,
        reason: 'must not mutate the original',
      );
      expect(original.repostCount, 4);
      // The repost toggle must not disturb the independent save state.
      expect(toggled.isSaved, isTrue);
      expect(toggled.likeCount, original.likeCount);
      expect(toggled.createdAt, original.createdAt);
    });

    test('copyWith flips isSaved without disturbing other fields', () {
      final original = _opinion('a', isMine: true, userReaction: 'like');
      final toggled = original.copyWith(isSaved: true);

      expect(toggled.isSaved, isTrue);
      expect(original.isSaved, isFalse, reason: 'must not mutate the original');
      expect(toggled.id, original.id);
      expect(toggled.authorHandle, original.authorHandle);
      expect(toggled.isMine, original.isMine);
      expect(toggled.content, original.content);
      expect(toggled.relationshipStatus, original.relationshipStatus);
      expect(toggled.likeCount, original.likeCount);
      expect(toggled.dislikeCount, original.dislikeCount);
      expect(toggled.commentCount, original.commentCount);
      expect(toggled.followerCount, original.followerCount);
      expect(toggled.userReaction, original.userReaction);
      expect(toggled.createdAt, original.createdAt);
    });
  });
}

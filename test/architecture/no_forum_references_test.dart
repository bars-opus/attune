// Spec 3 (forum removal) §7.4: nothing in the app or its tests still names a
// removed forum route, screen, provider, RPC, table or push. House pattern of
// no_pairing_strings_test.dart; full-line comments (`//`, `///`) are skipped,
// as in design_tokens_test.dart, so historic notes in kept files stay. Every
// failure reads `path:line: pattern`.
import 'dart:convert';
import 'dart:io';

import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:flutter_test/flutter_test.dart';

const _self = 'test/architecture/no_forum_references_test.dart';

/// Spec 3 §3.9: the 29 forum-only functions and the 10 forum relations.
const _forumRpcs = [
  'activate_pending_topics',
  'expire_old_topics',
  'mark_quiet_topics',
  'notify_quiet_topic',
  'queue_forum_activity_notifications',
  'record_forum_topic_visit',
  'create_forum_post',
  'create_forum_topic',
  'create_forum_topic_with_poll',
  'edit_forum_post',
  'attach_forum_topic_tags',
  'get_forum_topic_tags',
  'get_forum_topics_by_tag',
  'get_tags_for_forum_topics',
  'get_polls_for_topics',
  'get_active_forums_filtered',
  'get_quiet_forums_filtered',
  'get_voting_topics_filtered',
  'increment_topic_upvote_count',
  'decrement_topic_upvote_count',
  'increment_topic_downvote_count',
  'decrement_topic_downvote_count',
  'increment_topic_post_count',
  'decrement_topic_post_count',
  'increment_topic_seen_count',
  'increment_forum_post_like_count',
  'decrement_forum_post_like_count',
  'report_forum_post',
  'report_forum_topic',
];
const _forumRelations = [
  'forum_topics',
  'topic_votes',
  'topic_impressions',
  'forum_posts',
  'forum_post_likes',
  'user_forum_sides',
  'forum_topic_tags',
  'forum_topic_visits',
  'public_forum_topics',
  'public_forum_posts',
];

/// Every `.dart` file under [roots], except this one.
List<File> _dartFiles(List<String> roots) => [
  for (final root in roots)
    for (final entity in Directory(root).listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          entity.path != _self)
        entity,
];

/// `path:line: pattern` for each non-comment line of [files] that matches one
/// of [patterns], unless [allow] accepts that path and line.
List<String> _hits(
  Iterable<File> files,
  List<RegExp> patterns, {
  bool Function(String path, String line)? allow,
}) {
  final hits = <String>[];
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      for (final pattern in patterns) {
        if (!pattern.hasMatch(line)) continue;
        if (allow != null && allow(file.path, line)) continue;
        hits.add('${file.path}:${i + 1}: ${pattern.pattern}');
      }
    }
  }
  return hits;
}

void main() {
  test('no removed forum route is named', () {
    final hits = _hits(_dartFiles(['lib', 'test']), [
      RegExp(r'RouteNames\.(debateRoom|sideSelection|forumInsight)\b'),
      RegExp(r'''['"]/(debateRoom|sideSelection|forumInsight)['"]'''),
      RegExp(r'''name:\s*['"](debateRoom|sideSelection|forumInsight)['"]'''),
    ]);
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('no deleted forum code is named', () {
    const classes = [
      'ForumsSection',
      'ForumsExploreScreen',
      'ContributingForumsScreen',
      'DebateRoomScreen',
      'SideSelectionScreen',
      'ForumInsightScreen',
      'SubmitTopicScreen',
      'ForumCard',
      'ForumCardSubDetails',
      'ForumPostBubble',
      'TopicVotingCard',
      'TopicImpressionTracker',
      'MiniContainerIndicator',
      'TopicModel',
      'ForumPostModel',
      'ForumRepository',
      'ForumFeedCache',
      'ForumHome',
      'TopicLiveCounts',
      'WidgetsBindingListener',
    ];
    // §3.4, minus the generic supabaseClientProvider and
    // currentUserStatusProvider (other features own same-named providers).
    const providers = [
      'forumRepositoryProvider',
      'submitTopicProvider',
      'forumsExploreTagFilterProvider',
      'votingTopicsProvider',
      'activeForumsProvider',
      'quietForumsProvider',
      'castTopicVoteProvider',
      'recordTopicImpressionProvider',
      'recordTopicVisitProvider',
      'joinForumProvider',
      'forumPostsProvider',
      'submitForumPostProvider',
      'likeForumPostProvider',
      'unlikeForumPostProvider',
      'contributingForumsProvider',
      'topicDetailsProvider',
      'reportForumProvider',
      'reportForumPostProvider',
      'forumTopicsByTagProvider',
      'topicLiveCountsProvider',
      'postLikeLiveCountProvider',
      'forumFeedCacheProvider',
      'onTopicSubmitted',
    ];
    final names = [..._forumRpcs, ..._forumRelations].join('|');
    final hits = _hits(
      _dartFiles(['lib', 'test']),
      [
        RegExp(r'package:attune/features/forums/'),
        RegExp('\\b(${[...classes, ...providers].join('|')})\\b'),
        // A named push to a removed route compiles and then throws.
        RegExp(r'''['"](debateRoom|sideSelection|forumInsight)['"]'''),
        RegExp('[\'"][^\'"]*\\b($names)\\b[^\'"]*[\'"]'),
      ],
      // The dead topic-poll lookup goes with its RPC in W3 (§6.3).
      allow:
          (path, line) =>
              path.endsWith(
                'core/polls/data/repositories/poll_repository.dart',
              ) &&
              line.contains("'get_polls_for_topics'"),
    );
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('no app copy mentions Forums', () {
    // lib only: test files assert the word is absent (find.text('Forums'))
    // and universal_bubble_test.dart's kept "forums-shaped bubble" guards
    // name the old caller on purpose.
    final hits = _hits(_dartFiles(['lib']), [
      RegExp(r'''['"][^'"]*\b[Ff]orums?\b[^'"]*['"]'''),
      RegExp(r'\bForumDocs\b'),
    ]);
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('no translation mentions Forums', () {
    final word = RegExp(
      r'\bforums?\b|\bforo\b|\bforen|\bfórum\b',
      caseSensitive: false,
    );
    final hits = <String>[];
    for (final entity in Directory('lib/i10n').listSync()) {
      if (entity is! File || !entity.path.endsWith('.arb')) continue;
      final arb = jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
      arb.forEach((key, value) {
        if (!key.startsWith('@') && value is String && word.hasMatch(value)) {
          hits.add('${entity.path}: $key');
        }
      });
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the manual has no Forums topic', () {
    expect(DocumentationRegistry.getById('forums'), isNull);
    expect(
      DocumentationRegistry.getAllModules().map((m) => m.id),
      isNot(contains('forums')),
    );
    expect(
      DocumentationRegistry.visibleModules(const {}).map((m) => m.id),
      isNot(contains('forums')),
    );
    // The guard's floor (manual_content_guard_test.dart). No exact count:
    // Specs 1 and 2 register more topics later.
    expect(
      DocumentationRegistry.getAllModules().length,
      greaterThanOrEqualTo(33),
    );
  });

  test('the forum producers are gone from the server folders', () {
    for (final dir in [
      'supabase/functions/activate-topics',
      'supabase/functions/forum-quiet-check',
    ]) {
      expect(Directory(dir).existsSync(), isFalse, reason: dir);
    }
    for (final script in [
      'supabase/sql/schedule_activate_topics.sql',
      'supabase/sql/schedule_forum_quiet_check.sql',
      'supabase/sql/patch_mark_quiet_forums_null_last_post.sql',
    ]) {
      expect(File(script).existsSync(), isFalse, reason: script);
    }

    // No edge function or operator script names a forum RPC, relation or
    // retired push type. The dispatcher's allowlist keys forum_post_id and
    // topic_id match none of these.
    final names = [
      ..._forumRpcs,
      ..._forumRelations,
      'forum_topic_activated',
      'forum_activity',
      'forum_quiet',
    ].join('|');
    final pattern = RegExp('\\b($names)\\b');
    final hits = <String>[];
    final files = [
      for (final entity in Directory(
        'supabase/functions',
      ).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.ts')) entity,
      for (final entity in Directory('supabase/sql').listSync())
        if (entity is File && entity.path.endsWith('.sql')) entity,
    ];
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) hits.add('${file.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}

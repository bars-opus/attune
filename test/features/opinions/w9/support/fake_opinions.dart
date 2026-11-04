// Spec 1 W9: Opinions screens on fakes, the way the app shows them (the
// flow harness: app theme, the shell's 1.0 clamp, ScreenUtil, real
// localisations, every other route "at <location>"). Signed in as "me".
import 'package:attune/core/polls/data/models/poll_model.dart';
import 'package:attune/core/polls/presentation/providers/poll_providers.dart';
import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/repositories/opinion_repository.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/flow_harness.dart';

OpinionModel w9Opinion({
  String id = 'o1',
  bool mine = false,
  String content = 'Trust is built in small moments.',
}) => OpinionModel(
  id: id,
  authorHandle: 'quiet-otter',
  isMine: mine,
  content: content,
  relationshipStatus: 'single',
  likeCount: 0,
  dislikeCount: 0,
  commentCount: 2,
  createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
);

CommentModel w9Comment(String id, {required bool mine, String? content}) =>
    CommentModel(
      id: id,
      authorHandle: mine ? 'me' : 'other',
      isMine: mine,
      content:
          content ??
          (mine ? 'My own comment here.' : 'Someone else wrote this.'),
      relationshipStatus: 'single',
      likeCount: 0,
      createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

/// Records every write; [refuseWith] makes every write throw it.
class FakeOpinionRepository implements OpinionRepository {
  Object? refuseWith;
  final writes = <String>[];
  final reports = <String>[];
  List<CommentModel> comments = [
    w9Comment('c-other', mine: false),
    w9Comment('c-mine', mine: true),
  ];

  Future<void> _write(String what) async {
    writes.add(what);
    final error = refuseWith;
    if (error != null) throw error;
  }

  @override
  Future<void> createOpinion({
    required String content,
    List<String>? pollOptions,
    List<String>? tagSlugs,
  }) => _write('create:$content');

  @override
  Future<String> createQuoteOpinion({
    required String content,
    required String quotedOpinionId,
    List<String>? tagSlugs,
  }) async {
    await _write('quote:$content');
    return 'q1';
  }

  @override
  Future<void> editOpinion({
    required String opinionId,
    required String content,
  }) => _write('edit:$content');

  @override
  Future<String> createComment({
    required String opinionId,
    required String content,
    String? replyToCommentId,
    String? quotedText,
  }) async {
    await _write('comment:$content');
    return 'c-new';
  }

  @override
  Future<void> editComment({
    required String commentId,
    required String content,
  }) => _write('edit-comment:$content');

  @override
  Future<void> reportOpinion({
    required String opinionId,
    String reason = 'Other',
  }) async {
    reports.add('opinion:$opinionId:$reason');
    final error = refuseWith;
    if (error != null) throw error;
  }

  @override
  Future<void> reportComment({
    required String commentId,
    String reason = 'Other',
  }) async {
    reports.add('comment:$commentId:$reason');
    final error = refuseWith;
    if (error != null) throw error;
  }

  @override
  Future<List<CommentModel>> getComments(String opinionId) async => comments;

  @override
  Future<OpinionModel?> getQuotedOpinion(String opinionId) async =>
      w9Opinion(id: opinionId);

  @override
  Future<bool> isFollowingAuthor(String authorHandle) async => false;

  @override
  Future<List<String>> getAllTags() async => const ['trust'];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _NoPoll extends PollNotifier {
  @override
  Future<PollModel?> build(PollTarget arg) async => null;
}

/// The overrides every Opinions screen here needs.
List<Override> opinionOverrides(FakeOpinionRepository repo) => [
  opinionRepositoryProvider.overrideWithValue(repo),
  currentUserIdProvider.overrideWithValue('me'),
  userRelationshipStatusProvider.overrideWith((ref) async => 'single'),
  opinionLiveCountsProvider.overrideWith((ref, id) => const Stream.empty()),
  pollProvider.overrideWith(_NoPoll.new),
];

Future<FlowHarness> pumpOpinionScreen(
  WidgetTester tester,
  Widget Function() screen, {
  required FakeOpinionRepository repo,
  List<Override> overrides = const [],
  double textScale = 1.0,
}) => pumpFlowScreen(
  tester,
  screen,
  textScale: textScale,
  overrides: [...opinionOverrides(repo), ...overrides],
);

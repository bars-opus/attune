import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ask 2 so far: one answer per quiz question (null: not yet) and the
/// three anchors as typed.
class Ask2Progress {
  const Ask2Progress({required this.answers, required this.anchors});

  final List<int?> answers;
  final List<String> anchors;

  bool get isEmpty =>
      answers.every((a) => a == null) && anchors.every((a) => a.isEmpty);

  /// The first unanswered question, or null when every one is answered.
  int? get firstUnanswered {
    final index = answers.indexWhere((a) => a == null);
    return index < 0 ? null : index;
  }
}

/// R5 · Ask 2 saves as it goes (Spec 1 §3.8, W4b): each answer and anchor
/// is written to `attune.ask2.<uid>.<relationshipId>` as it is given;
/// cleared on completion, and by the device wipe registry on sign-out and
/// on quick exit (`spec1.ask2_progress`, §5.8). The server write stays at
/// the end (ask2_submission_service.dart).
class Ask2ProgressStore {
  const Ask2ProgressStore(
    this._prefs, {
    required this.userId,
    required this.relationshipId,
  });

  final SharedPreferences _prefs;
  final String userId;
  final String relationshipId;

  static const prefix = 'attune.ask2.';

  static String keyFor(String userId, String relationshipId) =>
      '$prefix$userId.$relationshipId';

  /// Every account's progress on the phone (the wipe's match).
  static bool isProgressKey(String key) => key.startsWith(prefix);

  String get _key => keyFor(userId, relationshipId);

  /// The saved progress, shaped to [questionCount] answers and
  /// [anchorCount] anchors; null when there is none or it can't be read.
  Ask2Progress? read({required int questionCount, required int anchorCount}) {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final answers = json['answers'];
      final anchors = json['anchors'];
      if (answers is! List || anchors is! List) return null;
      final progress = Ask2Progress(
        answers: [
          for (var i = 0; i < questionCount; i++)
            i < answers.length && answers[i] is int ? answers[i] as int : null,
        ],
        anchors: [
          for (var i = 0; i < anchorCount; i++)
            i < anchors.length && anchors[i] is String
                ? anchors[i] as String
                : '',
        ],
      );
      return progress.isEmpty ? null : progress;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Ask2Progress progress) => _prefs.setString(
    _key,
    jsonEncode({'answers': progress.answers, 'anchors': progress.anchors}),
  );

  Future<void> clear() => _prefs.remove(_key);
}

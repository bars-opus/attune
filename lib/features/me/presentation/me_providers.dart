import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What J1 needs to know (Spec 1 §3.10): whether this person has a journal
/// note and a finished quiz. Null while unknown.
final firstActionInputsProvider = Provider<({bool? hasNote, bool? hasQuiz})>((
  ref,
) {
  // Spec 1 W9c (D8): the signed-in account's entries only.
  final notes = ref.watch(journalOwnEntriesProvider);
  final quizzes = ref.watch(userQuizzesStatusProvider).valueOrNull;
  return (
    hasNote: notes?.isNotEmpty,
    hasQuiz: quizzes?.values.any((status) => status.completed),
  );
});

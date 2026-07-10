class SavedQuizProgress {
  final String quizType;
  final int currentScreen;
  final Map<int, int?> answers;
  final DateTime lastUpdated;

  SavedQuizProgress({
    required this.quizType,
    required this.currentScreen,
    required this.answers,
    required this.lastUpdated,
  });

  int get answeredCount => answers.values.where((v) => v != null).length;
  int get totalQuestions => 25; // For attachment quiz
  double get progressPercent => answeredCount / totalQuestions;
}

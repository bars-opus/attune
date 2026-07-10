class QuestionData {
  final String text;
  final int globalIndex;
  final String dimension; // 'A' for anxiety, 'V' for avoidance
  final bool isReverseScored;

  QuestionData({
    required this.text,
    required this.globalIndex,
    required this.dimension,
    this.isReverseScored = false,
  });
}

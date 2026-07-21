class QuestionData {
  final String text;
  final int globalIndex;
  final String dimension; // 'A' for anxiety, 'V' for avoidance
  final bool isReverseScored;

  /// Plain-language explanation of what the item is asking about: the kind of
  /// situation it refers to and where it tends to show up, so a user can
  /// recognise themselves in it rather than guessing at the wording.
  ///
  /// Describes the SITUATION only. It must never tell the user what an answer
  /// says about them, name an attachment style, or imply a healthier answer —
  /// that is scoring's job, and per ATTUNE_MASTER_SPEC the interpretive layer
  /// is clinically gated. Null where no explanation has been written yet.
  final String? description;

  QuestionData({
    required this.text,
    required this.globalIndex,
    required this.dimension,
    this.isReverseScored = false,
    this.description,
  });
}

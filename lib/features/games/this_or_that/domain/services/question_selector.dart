// lib/features/games/this_or_that/domain/services/question_selector.dart

import 'dart:math';

import 'package:attune/features/games/this_or_that/data/models/custom_question.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_question.dart';

class QuestionSelector {
  final Random _random = Random();

  /// Select a random preset question from available pool
  ThisOrThatQuestion selectPresetQuestion(List<ThisOrThatQuestion> questions) {
    if (questions.isEmpty) {
      throw Exception('No preset questions available');
    }
    return questions[_random.nextInt(questions.length)];
  }

  /// Select a random custom question from a user's pool
  CustomQuestion? selectCustomQuestion(List<CustomQuestion> questions) {
    if (questions.isEmpty) return null;
    return questions[_random.nextInt(questions.length)];
  }

  /// Get the partner who should choose the next source (alternating)
  String getNextChooser(String currentChooser, String partnerAId, String partnerBId) {
    return currentChooser == partnerAId ? partnerBId : partnerAId;
  }
}

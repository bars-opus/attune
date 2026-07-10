// lib/features/quiz/data/local/quiz_progress_store.dart

import 'dart:convert';
import 'package:attune/features/quiz/domain/models/saved_quiz_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuizProgressStore {
  static const String _keyPrefix = 'quiz_progress_';
  
  final SharedPreferences _prefs;

  QuizProgressStore(this._prefs);

  /// Save quiz progress locally when user exits mid-quiz
  Future<void> saveProgress({
    required String quizType,
    required int currentScreen,
    required Map<int, int?> answers,
  }) async {
    final key = '$_keyPrefix$quizType';
    final data = {
      'quizType': quizType,
      'currentScreen': currentScreen,
      'answers': answers.map((k, v) => MapEntry(k.toString(), v)),
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    await _prefs.setString(key, jsonEncode(data));
  }

  /// Load saved quiz progress
  SavedQuizProgress? loadProgress(String quizType) {
    final key = '$_keyPrefix$quizType';
    final jsonString = _prefs.getString(key);
    if (jsonString == null) return null;

    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      final answersMap = <int, int?>{};
      final answersJson = data['answers'] as Map<String, dynamic>;
      for (var entry in answersJson.entries) {
        answersMap[int.parse(entry.key)] = entry.value as int?;
      }

      return SavedQuizProgress(
        quizType: data['quizType'],
        currentScreen: data['currentScreen'],
        answers: answersMap,
        lastUpdated: DateTime.parse(data['lastUpdated']),
      );
    } catch (e) {
      return null;
    }
  }

  /// Clear saved progress for a quiz type
  Future<void> clearProgress(String quizType) async {
    final key = '$_keyPrefix$quizType';
    await _prefs.remove(key);
  }

  /// Check if there's saved progress (for resume prompt)
  bool hasSavedProgress(String quizType) {
    final key = '$_keyPrefix$quizType';
    return _prefs.containsKey(key);
  }
}


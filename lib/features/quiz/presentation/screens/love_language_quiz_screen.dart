// lib/features/quiz/presentation/screens/love_language_quiz_screen.dart

import 'dart:convert';

import 'package:attune/features/quiz/data/love_language_questions.dart';
import 'package:attune/features/quiz/domain/models/question_data.dart';
import 'package:attune/features/quiz/domain/services/love_language_scoring_service.dart';
import 'package:attune/features/quiz/presentation/screens/love_language_loading_screen.dart';
import 'package:attune/features/quiz/presentation/widgets/question_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'love_language_result_screen.dart';

class LoveLanguageQuizScreen extends ConsumerStatefulWidget {
  const LoveLanguageQuizScreen({super.key});

  @override
  ConsumerState<LoveLanguageQuizScreen> createState() => _LoveLanguageQuizScreenState();
}

class _LoveLanguageQuizScreenState extends ConsumerState<LoveLanguageQuizScreen> {
  late PageController _pageController;
  Map<int, int?> _answers = {};
  int _currentScreen = 0;
  bool _isResuming = false;

  final int _questionsPerScreen = 5;
  late List<List<QuestionData>> _screens;

  @override
  void initState() {
    super.initState();
    _initializeQuestions();
    _checkForSavedProgress();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _initializeQuestions() {
    final allQuestions = LoveLanguageQuestions.getAllQuestions();
    _screens = [];
    for (var i = 0; i < allQuestions.length; i += _questionsPerScreen) {
      _screens.add(
        allQuestions.sublist(
          i,
          i + _questionsPerScreen > allQuestions.length
              ? allQuestions.length
              : i + _questionsPerScreen,
        ),
      );
    }
    _pageController = PageController();
    _answers = {};
  }

  void _checkForSavedProgress() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('love_language_quiz_progress');
      if (saved != null) {
        try {
          final data = jsonDecode(saved);
          final savedAnswers = data['answers'] as Map<String, dynamic>;
          final savedScreen = data['currentScreen'] as int;

          // Restore answers
          final restoredAnswers = <int, int?>{};
          for (final entry in savedAnswers.entries) {
            restoredAnswers[int.parse(entry.key)] = entry.value as int?;
          }

          // Check if any answers exist
          if (restoredAnswers.values.any((v) => v != null)) {
            _showResumeDialog(restoredAnswers, savedScreen);
          }
        } catch (_) {}
      }
    });
  }

  void _showResumeDialog(Map<int, int?> savedAnswers, int savedScreen) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Continue where you left off?'),
        content: const Text('You have a love language quiz in progress.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startFresh();
            },
            child: const Text('Start over'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resumeQuiz(savedAnswers, savedScreen);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _resumeQuiz(Map<int, int?> savedAnswers, int savedScreen) {
    setState(() {
      _answers = savedAnswers;
      _currentScreen = savedScreen;
      _isResuming = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(savedScreen);
      }
      setState(() => _isResuming = false);
    });
  }

  void _startFresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('love_language_quiz_progress');
    setState(() {
      _answers = {};
      _currentScreen = 0;
    });
    _pageController.jumpToPage(0);
  }

  void _saveProgress() async {
    if (_answers.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'answers': _answers.map((k, v) => MapEntry(k.toString(), v)),
      'currentScreen': _currentScreen,
    };
    await prefs.setString('love_language_quiz_progress', jsonEncode(data));
  }

  void _onAnswerChanged(int globalIndex, int value) {
    setState(() {
      _answers[globalIndex] = value;
    });
    _saveProgress();
  }

  void _nextScreen() {
    if (_currentScreen < _screens.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentScreen++;
      });
      _saveProgress();
    } else if (_currentScreen == _screens.length - 1) {
      _submitQuiz();
    }
  }

  void _previousScreen() {
    if (_currentScreen > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentScreen--;
      });
      _saveProgress();
    } else {
      _showExitConfirmation();
    }
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit quiz?'),
        content: const Text('Your progress will be saved. You can continue later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _saveProgress();
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitQuiz() async {
    final totalQuestions = _screens.length * _questionsPerScreen;
    if (_answers.length != totalQuestions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer all questions before submitting.')),
      );
      return;
    }

    // Clear saved progress
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('love_language_quiz_progress');

    if (!mounted) return;

    // Calculate result
    final result = LoveLanguageScoringService.calculateScore(_answers);

    // Navigate to loading screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LoveLanguageLoadingScreen(
          result: result,
          answers: Map.from(_answers),
          onComplete: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => LoveLanguageResultScreen(result: result),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_screens.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isResuming) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _screens.length,
      onPageChanged: (index) {
        setState(() => _currentScreen = index);
      },
      itemBuilder: (context, index) {
        final questions = _screens[index];
        return QuestionScreen(
          title: 'Love languages',
          screenIndex: index,
          totalScreens: _screens.length,
          questions: questions,
          answers: _answers,
          onAnswerChanged: _onAnswerChanged,
          onNext: _nextScreen,
          onPrevious: _previousScreen,
          isFirstScreen: index == 0,
          isLastScreen: index == _screens.length - 1,
        );
      },
    );
  }
}

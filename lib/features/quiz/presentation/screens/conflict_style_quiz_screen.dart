// lib/features/quiz/presentation/screens/conflict_style_quiz_screen.dart

import 'dart:convert';
import 'package:attune/features/quiz/domain/models/question_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'conflict_style_loading_screen.dart';
import 'conflict_style_result_screen.dart';
import '../widgets/question_screen.dart';
import '../../data/conflict_style_questions.dart';
import '../../domain/services/conflict_style_scoring_service.dart';

class ConflictStyleQuizScreen extends ConsumerStatefulWidget {
  const ConflictStyleQuizScreen({super.key});

  @override
  ConsumerState<ConflictStyleQuizScreen> createState() =>
      _ConflictStyleQuizScreenState();
}

class _ConflictStyleQuizScreenState
    extends ConsumerState<ConflictStyleQuizScreen> {
  late PageController _pageController;
  Map<int, int?> _answers = {};
  int _currentScreen = 0;
  bool _isResuming = false;

  static const int _questionsPerScreen = 5;
  late List<List<QuestionData>> _screens;
  String get _progressKey {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    return 'conflict_style_quiz_progress_${ConflictStyleQuestions.instrumentVersion}_$userId';
  }

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
    final allQuestions = ConflictStyleQuestions.getAllQuestions();
    _screens = [];
    for (var i = 0; i < allQuestions.length; i += _questionsPerScreen) {
      final end =
          (i + _questionsPerScreen > allQuestions.length)
              ? allQuestions.length
              : i + _questionsPerScreen;
      _screens.add(allQuestions.sublist(i, end));
    }
    _pageController = PageController();
    _answers = {};
  }

  Future<void> _checkForSavedProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_progressKey);
    if (saved != null) {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        final savedAnswers = data['answers'] as Map<String, dynamic>;
        final savedScreen = (data['currentScreen'] as num).toInt();

        final restoredAnswers = <int, int?>{};
        for (final entry in savedAnswers.entries) {
          restoredAnswers[int.parse(entry.key)] =
              (entry.value as num?)?.toInt();
        }

        if (restoredAnswers.values.any((v) => v != null)) {
          if (!mounted) return;
          _showResumeDialog(
            restoredAnswers,
            savedScreen.clamp(0, _screens.length - 1),
          );
        }
      } catch (_) {
        // Invalid saved data, ignore
      }
    }
  }

  void _showResumeDialog(Map<int, int?> savedAnswers, int savedScreen) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('Continue where you left off?'),
            content: const Text('You have a conflict style quiz in progress.'),
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
      if (mounted) setState(() => _isResuming = false);
    });
  }

  Future<void> _startFresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_progressKey);
    if (!mounted) return;
    setState(() {
      _answers = {};
      _currentScreen = 0;
    });
    if (_pageController.hasClients) _pageController.jumpToPage(0);
  }

  Future<void> _saveProgress() async {
    if (_answers.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'answers': _answers.map((k, v) => MapEntry(k.toString(), v)),
      'currentScreen': _currentScreen,
    };
    await prefs.setString(_progressKey, jsonEncode(data));
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
    } else {
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
    if (_answers.isEmpty) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Exit quiz?'),
            content: const Text(
              'Your progress will be saved. You can continue later.',
            ),
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
    const totalQuestions = 18;
    if (_answers.length != totalQuestions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please answer all questions before submitting.'),
        ),
      );
      return;
    }

    // Validate all answers
    for (int i = 0; i < totalQuestions; i++) {
      final value = _answers[i];
      if (value == null || value < 1 || value > 7) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid answer detected. Please retry.'),
          ),
        );
        return;
      }
    }

    if (!mounted) return;

    // Calculate result (pure function)
    final result = ConflictStyleScoringService.calculateScore(_answers);

    // Navigate to loading screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ConflictStyleLoadingScreen(
              result: result,
              answers: Map.from(_answers),
              onComplete: (savedResult) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => ConflictStyleResultScreen(result: savedResult),
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
          title: 'Conflict style',
          screenIndex: index,
          totalScreens: _screens.length,
          totalQuestionCount: ConflictStyleQuestions.getAllQuestions().length,
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

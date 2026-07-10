// lib/features/quiz/presentation/screens/attachment_quiz_screen.dart

import 'package:attune/features/quiz/data/attachment_questions.dart';
import 'package:attune/features/quiz/data/local/quiz_progress_store.dart';
import 'package:attune/features/quiz/domain/models/question_data.dart';
import 'package:attune/features/quiz/domain/models/saved_quiz_progress.dart';
import 'package:attune/features/quiz/presentation/screens/quiz_loading_screen.dart';
import 'package:attune/features/quiz/presentation/screens/quiz_result_screen.dart';
import 'package:attune/features/quiz/presentation/widgets/question_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AttachmentQuizScreen extends ConsumerStatefulWidget {
  final String quizType;

  const AttachmentQuizScreen({super.key, required this.quizType});

  @override
  ConsumerState<AttachmentQuizScreen> createState() =>
      _AttachmentQuizScreenState();
}

class _AttachmentQuizScreenState extends ConsumerState<AttachmentQuizScreen>
    with WidgetsBindingObserver {
  late PageController _pageController;
  late QuizProgressStore _progressStore;
  Map<int, int?> _answers = {};
  int _currentScreen = 0;
  bool _isResuming = false;
  bool _isFirstFrame = true;

  final int _questionsPerScreen = 5;
  late List<List<QuestionData>> _screens;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeProgressStore();
    _initializeQuestions();
    _checkForSavedProgress();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save progress when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveProgress();
    }
  }

  Future<void> _initializeProgressStore() async {
    final prefs = await SharedPreferences.getInstance();
    _progressStore = QuizProgressStore(prefs);
  }

  void _initializeQuestions() {
    final allQuestions = AttachmentQuestions.getAllQuestions();
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
  }

  void _checkForSavedProgress() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_progressStore.hasSavedProgress(widget.quizType)) {
        _showResumeDialog();
      }
    });
  }

  void _showResumeDialog() {
    final saved = _progressStore.loadProgress(widget.quizType);
    if (saved == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('Continue where you left off?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You completed ${saved.answeredCount} of ${saved.totalQuestions} questions.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Last saved: ${_formatDate(saved.lastUpdated)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
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
                  _resumeQuiz(saved);
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

  void _resumeQuiz(SavedQuizProgress saved) {
    setState(() {
      _answers = saved.answers;
      _currentScreen = saved.currentScreen;
      _isResuming = true;
    });

    // Jump to the saved screen after layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentScreen);
      }
      setState(() {
        _isResuming = false;
      });
    });
  }

  void _startFresh() {
    setState(() {
      _answers = {};
      _currentScreen = 0;
    });
    _progressStore.clearProgress(widget.quizType);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  void _saveProgress() {
    if (_answers.isNotEmpty && !_isResuming) {
      _progressStore.saveProgress(
        quizType: widget.quizType,
        currentScreen: _currentScreen,
        answers: _answers,
      );
    }
  }

  void _onAnswerChanged(int globalIndex, int value) {
    setState(() {
      _answers[globalIndex] = value;
    });
    // Auto-save progress after each answer
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
      // On first screen, confirm exit
      _showExitConfirmation();
    }
  }

  void _showExitConfirmation() {
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
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Exit quiz
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
        const SnackBar(
          content: Text('Please answer all questions before submitting.'),
        ),
      );
      return;
    }

    // Clear saved progress on successful submission
    await _progressStore.clearProgress(widget.quizType);

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => QuizLoadingScreen(
              answers: Map.from(_answers),
              quizType: widget.quizType,
              onComplete: (result) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => QuizResultScreen(
                          result: result,
                          quizType: widget.quizType,
                        ),
                  ),
                );
              },
            ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays} days ago';
    if (diff.inHours > 0) return '${diff.inHours} hours ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes} minutes ago';
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    if (_screens.isEmpty || _pageController == null) {
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
        setState(() {
          _currentScreen = index;
        });
      },
      itemBuilder: (context, index) {
        final questions = _screens[index];
        return QuestionScreen(
          title: 'Attachment style',
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

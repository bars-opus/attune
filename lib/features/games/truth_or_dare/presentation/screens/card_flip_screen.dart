// lib/features/games/truth_or_dare/presentation/screens/card_flip_screen.dart

import 'dart:math';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/dare_reveal_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_reveal_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class CardFlipScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final int roundNumber;
  final int totalRounds;
  final String tone;
  final bool isPartnerA;
  final String partnerName;
  final String activePartnerId;

  const CardFlipScreen({
    super.key,
    required this.sessionId,
    required this.roundNumber,
    required this.totalRounds,
    required this.tone,
    required this.isPartnerA,
    required this.partnerName,
    required this.activePartnerId,
  });

  @override
  ConsumerState<CardFlipScreen> createState() => _CardFlipScreenState();
}

class _CardFlipScreenState extends ConsumerState<CardFlipScreen> with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  bool _isFlipped = false;
  bool _isLoading = false;
  String? _selectedType;
  Map<String, dynamic>? _questionData;
  String? _roundId;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  Future<void> _flipCard() async {
    if (_isFlipped || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      // Randomly select type (50/50)
      final repository = ref.read(truthOrDareRepositoryProvider);
      final type = repository.selectRandomType();
      _selectedType = type;

      // Select question for this type
      final questionData = await ref.read(selectQuestionForRoundProvider((
        tone: widget.tone,
        questionType: type,
        sessionId: widget.sessionId,
      )).future);

      final round = await ref.read(
        createTruthOrDareRoundProvider((
          sessionId: widget.sessionId,
          roundNumber: widget.roundNumber,
          activePartnerId: widget.activePartnerId,
          questionData: questionData,
        )).future,
      );

      _questionData = questionData;
      _roundId = round.id;

      // Flip the card
      setState(() {
        _isFlipped = true;
        _isLoading = false;
      });
      _flipController.forward();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load question: $e')),
        );
      }
    }
  }

  void _navigateToReveal() {
    if (_selectedType == 'truth') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TruthRevealScreen(
            sessionId: widget.sessionId,
            roundId: _roundId!,
            roundNumber: widget.roundNumber,
            totalRounds: widget.totalRounds,
            tone: widget.tone,
            isPartnerA: widget.isPartnerA,
            partnerName: widget.partnerName,
            questionText: _questionData!['question_text'],
            isCustom: _questionData!['is_custom'],
            customQuestionId: _questionData!['question_id'],
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DareRevealScreen(
            sessionId: widget.sessionId,
            roundId: _roundId!,
            roundNumber: widget.roundNumber,
            totalRounds: widget.totalRounds,
            tone: widget.tone,
            isPartnerA: widget.isPartnerA,
            partnerName: widget.partnerName,
            dareText: _questionData!['question_text'],
            isCustom: _questionData!['is_custom'],
            customQuestionId: _questionData!['question_id'],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Truth or Dare • Round ${widget.roundNumber}/${widget.totalRounds}'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Your turn',
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            // Card
            GestureDetector(
              onTap: _isLoading ? null : _flipCard,
              child: AnimatedBuilder(
                animation: _flipController,
                builder: (context, child) {
                  final value = _flipController.value;
                  final isBack = value > 0.5;

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(value * pi),
                    child: isBack
                        ? _buildCardBack(colorScheme, textTheme)
                        : _buildCardFront(colorScheme, textTheme),
                  );
                },
              ),
            ),
            Gap(Spacing.xl.h),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_isFlipped)
              Text(
                'Tap the card to reveal what you got!',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            if (_isFlipped && _selectedType != null) ...[
              Gap(Spacing.lg.h),
              AppButton(
                label: _selectedType == 'truth' ? 'Continue to Truth →' : 'Continue to Dare →',
                onPressed: _navigateToReveal,
                size: ButtonSize.medium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCardFront(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      width: 250,
      height: 350,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withOpacity(0.8),
            colorScheme.primary.withOpacity(0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '?',
              style: textTheme.displayLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Gap(Spacing.md.h),
            Text(
              'Tap to flip',
              style: textTheme.bodyMedium?.copyWith(
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBack(ColorScheme colorScheme, TextTheme textTheme) {
    final isTruth = _selectedType == 'truth';

    return Container(
      width: 250,
      height: 350,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isTruth ? Colors.green.shade700 : Colors.orange.shade700,
            isTruth ? Colors.green.shade400 : Colors.orange.shade400,
          ],
        ),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isTruth ? '🗣' : '🎯',
              style: const TextStyle(fontSize: 48),
            ),
            Gap(Spacing.md.h),
            Text(
              isTruth ? 'TRUTH' : 'DARE',
              style: textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              _questionData?['question_text'] ?? 'Loading...',
              style: textTheme.bodyMedium?.copyWith(
                color: Colors.white.withOpacity(0.9),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

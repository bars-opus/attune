// lib/features/healing/presentation/screens/healing_post_mortem_screen.dart

import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/animated_circle.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/healing_providers.dart';
import '../providers/healing_support_providers.dart';
import '../widgets/healing_support.dart';

class HealingPostMortemScreen extends ConsumerStatefulWidget {
  final HealingJourney journey;

  const HealingPostMortemScreen({super.key, required this.journey});

  @override
  ConsumerState<HealingPostMortemScreen> createState() =>
      _HealingPostMortemScreenState();
}

/// Rotating micro-copy shown while the reflection generates. These describe
/// work actually happening upstream, so the wait reads as consideration rather
/// than as a stalled request.
const _kAnticipationLines = [
  'Reading back through what you shared...',
  'Noticing patterns...',
  'Looking for what this revealed...',
  'Putting it into words...',
];

class _HealingPostMortemScreenState
    extends ConsumerState<HealingPostMortemScreen>
    with SingleTickerProviderStateMixin {
  bool _isGenerating = false;
  String? _observation;
  String? _confidence;
  String? _reflectionPrompt;
  bool _isComplete = false;
  bool _hasSkipped = false;

  late final AnimationController _revealController;
  Timer? _anticipationTimer;
  int _anticipationLine = 0;

  /// The reveal unfolds one element at a time: framing label, then the
  /// observation, then the reflection prompt. Intervals are fractions of
  /// [_revealController]'s 2200ms, giving roughly 400ms between each entrance —
  /// slow enough to read as deliberate, short of feeling withheld.
  late final Animation<double> _labelFade = _fadeIn(0.00, 0.25);
  late final Animation<double> _observationFade = _fadeIn(0.18, 0.55);
  late final Animation<double> _promptFade = _fadeIn(0.45, 0.80);
  late final Animation<double> _footnoteFade = _fadeIn(0.70, 1.00);

  /// The afterglow: the continue action stays dimmed and inert until the reveal
  /// has finished, so nothing competes with the observation while it lands.
  /// Only true once a reveal is actually in flight — the pre-generation state
  /// leaves the controller at 0 and must stay fully actionable.
  bool get _isWaitingOnReveal => _isComplete && _revealController.value < 1.0;

  Animation<double> _fadeIn(double begin, double end) {
    return CurvedAnimation(
      parent: _revealController,
      curve: Interval(begin, end, curve: Curves.easeOut),
    );
  }

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    )..addStatusListener((status) {
      // Rebuild once the sequence lands so the continue action un-dims.
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
    _checkExistingStatus();
    // Spec 1 W9e: a match for this stage, from any request, hides the
    // AI text this screen shows at once.
    ref.listenManual(
      healingSupportProvider.select((s) => s.hidden.contains(_supportKey)),
      (_, hidden) {
        if (hidden && mounted) setState(_dropAiText);
      },
    );
  }

  @override
  void dispose() {
    _anticipationTimer?.cancel();
    _revealController.dispose();
    super.dispose();
  }

  /// Spec 1 W9e: this journey's stage in the support state.
  late final HealingSupportKey _supportKey = (
    journeyId: widget.journey.id,
    stage: HealingAiStage.postMortem,
  );

  /// Spec 1 W9e: drops the AI text this screen holds; a completed stage
  /// then shows as having none (plan P-9).
  void _dropAiText() {
    _observation = null;
    _confidence = null;
    _reflectionPrompt = null;
    if (_isComplete) {
      _hasSkipped = true;
      _revealController.value = 1.0;
    }
  }

  void _checkExistingStatus() {
    // Spec 1 W9e: AI text the crisis check matched this run is never
    // shown, and a completed stage whose AI text was removed shows as
    // having none.
    final hidden = ref.read(healingSupportProvider).hidden.contains(
      _supportKey,
    );
    final saved = widget.journey.postMortemObservation;
    if (widget.journey.postMortemStatus == 'completed' &&
        !hidden &&
        saved != null &&
        saved.trim().isNotEmpty) {
      setState(() {
        _observation = widget.journey.postMortemObservation;
        _confidence = widget.journey.postMortemConfidence;
        _reflectionPrompt = widget.journey.postMortemReflectionPrompt;
        _isComplete = true;
      });
      // Revisiting an already-generated reflection is not a reveal — the user
      // has seen it. Show it whole.
      _revealController.value = 1.0;
    } else if (widget.journey.postMortemStatus == 'completed' ||
        widget.journey.postMortemStatus == 'skipped' ||
        widget.journey.postMortemStatus == 'insufficient_evidence') {
      setState(() {
        _hasSkipped = true;
        _isComplete = true;
      });
      _revealController.value = 1.0;
    }
  }

  void _startAnticipation() {
    _anticipationLine = 0;
    _anticipationTimer?.cancel();
    _anticipationTimer = Timer.periodic(const Duration(milliseconds: 2600), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Hold on the final line rather than looping, so a long wait never looks
      // like the same four lines cycling forever.
      if (_anticipationLine >= _kAnticipationLines.length - 1) {
        timer.cancel();
        return;
      }
      setState(() => _anticipationLine++);
    });
  }

  void _stopAnticipation() {
    _anticipationTimer?.cancel();
    _anticipationTimer = null;
  }

  Future<void> _generatePostMortem() async {
    setState(() => _isGenerating = true);
    // The real network latency is the anticipation window — no artificial delay
    // is added on top of it.
    _startAnticipation();
    // Spec 1 W9e: taken now; the answer may land after the screen or
    // the account is gone.
    final support = ref.read(healingSupportProvider.notifier);
    final account = ref.read(healingAccountProvider);
    final request = support.begin();

    try {
      final service = ref.read(healingGenerationServiceProvider);

      final result = await service.generatePostMortem(
        journeyId: widget.journey.id,
      );

      // Spec 1 W9e: the crisis check matched. Nothing is saved; any AI
      // text held for this stage is hidden and the card shows instead.
      // An answer that lands after the account changed is dropped (D8).
      if (result != null && result['status'] == 'support_offered') {
        if (support.account != account) return;
        support.offer(_supportKey);
        _stopAnticipation();
        if (!mounted) return;
        setState(() {
          _observation = null;
          _confidence = null;
          _reflectionPrompt = null;
          _isGenerating = false;
        });
        return;
      }
      // Spec 1 W9e (D8): every other answer that lands after the
      // account changed is dropped too: never shown, never saved.
      if (support.account != account) return;
      if (result != null && result['status'] == 'completed') {
        // Spec 1 W9e: an answer to a request sent before this stage's
        // latest match is stale: never shown, never saved.
        if (support.isStale(_supportKey, request)) {
          _stopAnticipation();
          if (mounted) setState(() => _isGenerating = false);
          return;
        }
        support.completed(_supportKey); // Spec 1 W9e
        _stopAnticipation();
        setState(() {
          _observation = result['observation'];
          _confidence = result['confidence'];
          _reflectionPrompt = result['reflection_prompt'] as String?;
          _isComplete = true;
          _isGenerating = false;
        });
        _revealController.forward(from: 0);

        // Save to database
        await ref.read(
          completePostMortemProvider((
            journeyId: widget.journey.id,
            status: 'completed',
            observation: _observation,
            confidence: _confidence,
            reflectionPrompt: _reflectionPrompt,
          )).future,
        );
      } else {
        await ref.read(
          completePostMortemProvider((
            journeyId: widget.journey.id,
            status: 'insufficient_evidence',
            observation: null,
            confidence: null,
            reflectionPrompt: null,
          )).future,
        );

        setState(() {
          _isComplete = true;
          _hasSkipped = true;
          _isGenerating = false;
        });
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate: $e')));
      }
    }
  }

  Future<void> _skipStage() async {
    await ref.read(
      completePostMortemProvider((
        journeyId: widget.journey.id,
        status: 'skipped',
        observation: null,
        confidence: null,
        reflectionPrompt: null,
      )).future,
    );

    if (mounted) {
      setState(() {
        _hasSkipped = true;
        _isComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Spec 1 W9e: the crisis check's card for this stage, this run.
    final supportOffered = ref.watch(
      healingSupportProvider.select((s) => s.offered.contains(_supportKey)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relationship reflection'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stage 2 of 5',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            Text(
              'Relationship reflection',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),

            if (_isGenerating) ...[
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    // A slow breathing shape rather than a determinate spinner:
                    // this is considered work, not a measurable download.
                    AnimatedCircle(
                      animateSize: true,
                      animateShape: true,
                      size: 72,
                      stroke: 2,
                      firstColor: colorScheme.primary.withValues(alpha: 0.6),
                      secondColor: colorScheme.primary.withValues(alpha: 0.2),
                    ),
                    Gap(Spacing.xl.h),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      child: Text(
                        _kAnticipationLines[_anticipationLine],
                        key: ValueKey(_anticipationLine),
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ] else if (supportOffered) ...[
              // Spec 1 W9e: the card instead of the AI text.
              Gap(Spacing.md.h),
              Expanded(
                child: SingleChildScrollView(
                  child: HealingSupportCard(
                    onNotNow:
                        () => ref
                            .read(healingSupportProvider.notifier)
                            .notNow(_supportKey),
                  ),
                ),
              ),
            ] else if (_isComplete && _observation != null) ...[
              Gap(Spacing.xl.h),
              Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RevealStep(
                      animation: _labelFade,
                      child: Text(
                        'One pattern that surfaced:',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Gap(Spacing.md.h),
                    _RevealStep(
                      animation: _observationFade,
                      child: Text(_observation!, style: textTheme.bodyLarge),
                    ),
                    if (_reflectionPrompt != null &&
                        _reflectionPrompt!.trim().isNotEmpty) ...[
                      Gap(Spacing.md.h),
                      _RevealStep(
                        animation: _promptFade,
                        child: Text(
                          _reflectionPrompt!,
                          style: textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                    Gap(Spacing.sm.h),
                    _RevealStep(
                      animation: _footnoteFade,
                      child: Text(
                        _confidence != null && _confidence != 'none'
                            ? 'Confidence: ${_confidence?.toUpperCase()}'
                            : 'Based on available data',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Gap(Spacing.md.h),
              Text(
                'This is based on shared data. It is not a judgment.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ] else if (_isComplete && _hasSkipped) ...[
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 48,
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    Gap(Spacing.md.h),
                    Text(
                      'There is not enough information for a grounded reflection yet.',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ] else ...[
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Text(
                      'Ready for a grounded reflection on the relationship dynamic?',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Gap(Spacing.md.h),
                    Text(
                      'This analysis is private and based on shared data.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],

            Gap(Spacing.md.h),

            Row(
              children: [
                if (!_isComplete)
                  Expanded(
                    child: AppButton(
                      label: 'Skip',
                      onPressed: _isGenerating ? null : _skipStage,
                      size: ButtonSize.medium,
                      customColor: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                if (!_isComplete) Gap(Spacing.md.w),
                Expanded(
                  // Afterglow: while the reveal is still unfolding, the continue
                  // action fades in alongside it instead of sitting fully lit, so
                  // the observation is what holds attention first. Only gates the
                  // post-reveal state — "Generate reflection" is never withheld.
                  child: AnimatedOpacity(
                    opacity: _isWaitingOnReveal ? 0.4 : 1.0,
                    duration: const Duration(milliseconds: 400),
                    child: AppButton(
                      label: _isComplete ? 'Continue →' : 'Generate reflection',
                      onPressed:
                          _isGenerating || _isWaitingOnReveal
                              ? null
                              : _isComplete
                              ? () => Navigator.pop(context, true)
                              : _generatePostMortem,
                      size: ButtonSize.medium,
                      isLoading: _isGenerating,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One beat of the reveal: fades and lifts its child into place on the shared
/// controller's timeline. Movement is small (8px) so the sequence reads as
/// settling rather than as an animated entrance.
class _RevealStep extends StatelessWidget {
  const _RevealStep({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, 8 * (1 - animation.value)),
            child: child,
          );
        },
        child: child,
      ),
    );
  }
}

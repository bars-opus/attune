// lib/features/quiz/presentation/widgets/share_quiz_button.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShareQuizButton extends ConsumerStatefulWidget {
  final String quizType;
  final Object result;

  const ShareQuizButton({
    super.key,
    required this.quizType,
    required this.result,
  });

  @override
  ConsumerState<ShareQuizButton> createState() => _ShareQuizButtonState();
}

class _ShareQuizButtonState extends ConsumerState<ShareQuizButton> {
  bool _isSharing = false;
  bool _hasShared = false;

  @override
  void initState() {
    super.initState();
    _checkShareStatus();
  }

  Future<void> _checkShareStatus() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final shared = await ref.read(
      hasSharedQuizProvider((widget.quizType, userId)).future,
    );
    if (mounted) {
      setState(() {
        _hasShared = shared;
      });
    }
  }

  Future<void> _shareWithPartner() async {
    setState(() => _isSharing = true);

    try {
      await ref.read(
        shareQuizResultProvider((quizType: widget.quizType)).future,
      );

      setState(() {
        _hasShared = true;
        _isSharing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Result shared with partner')),
        );
      }
    } catch (e) {
      setState(() => _isSharing = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
      }
    }
  }

  Future<void> _stopSharing() async {
    setState(() => _isSharing = true);
    try {
      await ref.read(stopSharingQuizProvider(widget.quizType).future);
      if (!mounted) return;
      setState(() {
        _hasShared = false;
        _isSharing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Result is private again')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSharing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not stop sharing. Try again.')),
      );
    }
  }

  void _showShareConfirmation() {
    final partnerName =
        ref.read(partnerNameProvider).valueOrNull ?? 'your partner';
    final visibleData = switch (widget.quizType) {
      'conflict' => 'your five tendency scores and summary',
      'communication' => 'your four tendency scores and summary',
      _ => 'your current quiz result and summary',
    };

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Share with $partnerName?'),
            content: Text(
              'They will see $visibleData. They will not see your individual answers or previous results. You can stop sharing at any time.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _shareWithPartner();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('Yes, share it'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final relationshipMode = ref.watch(userRelationshipModeProvider);

    if (relationshipMode.valueOrNull != 'couples') {
      return const SizedBox.shrink();
    }

    if (_hasShared) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: Spacing.md.h),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 20, color: colorScheme.primary),
                Gap(Spacing.sm.w),
                Text(
                  'Shared with partner',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isSharing ? null : _stopSharing,
            child: const Text('Stop sharing'),
          ),
        ],
      );
    }

    return AppButton(
      label: 'Share with partner',
      onPressed: _isSharing ? null : _showShareConfirmation,
      size: ButtonSize.large,
      width: double.infinity,
      isLoading: _isSharing,
    );
  }
}

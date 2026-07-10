// lib/features/forums/presentation/widgets/topic_voting_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class TopicVotingCard extends ConsumerStatefulWidget {
  final TopicModel topic;

  const TopicVotingCard({super.key, required this.topic});

  @override
  ConsumerState<TopicVotingCard> createState() => _TopicVotingCardState();
}

class _TopicVotingCardState extends ConsumerState<TopicVotingCard> {
  late int _upvoteCount;
  late int _downvoteCount;
  late int _seenCount;
  String? _userVote;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _upvoteCount = widget.topic.upvoteCount;
    _downvoteCount = widget.topic.downvoteCount;
    _seenCount = widget.topic.seenCount;
    _userVote = widget.topic.userVote;
  }

  double get _activationPercentage {
    if (_seenCount == 0) return 0;
    return (_upvoteCount / _seenCount) * 100;
  }

  bool get _isAboveThreshold {
    return _activationPercentage > 50 && _seenCount >= 20;
  }

  Future<void> _castVote(String voteType) async {
    if (_isUpdating) return;
    if (ref.read(supabaseClientProvider).auth.currentUser?.id == null) {
      context.showInfoSnackbar(
        'Continue with phone number from Chat to vote on topics.',
      );
      return;
    }

    setState(() => _isUpdating = true);

    try {
      final previousVote = _userVote;

      // Optimistic update
      setState(() {
        if (previousVote == 'up') {
          _upvoteCount--;
        } else if (previousVote == 'down') {
          _downvoteCount--;
        }

        if (voteType == 'up') {
          _upvoteCount++;
          _userVote = (_userVote == 'up') ? null : 'up';
        } else if (voteType == 'down') {
          _downvoteCount++;
          _userVote = (_userVote == 'down') ? null : 'down';
        }
      });

      await ref.read(
        castTopicVoteProvider((
          topicId: widget.topic.id,
          voteType: voteType,
        )).future,
      );
    } catch (e) {
      // Revert on error
      setState(() {
        _upvoteCount = widget.topic.upvoteCount;
        _downvoteCount = widget.topic.downvoteCount;
        _userVote = widget.topic.userVote;
      });
      if (mounted) {
        context.showErrorSnackbar('Failed to vote right now.');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final statusDisplay = _getStatusDisplay(widget.topic.submitterStatus);
    final percentage = _activationPercentage;
    final needsMore = !_isAboveThreshold;

    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: BorderWidthTokens.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topic label
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.sm.w,
              vertical: Spacing.xs.h,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
            ),
            child: Text(
              'TOPIC UP FOR VOTE',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Gap(Spacing.sm.h),
          // Topic content
          Text(
            '"${widget.topic.content}"',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          Gap(Spacing.sm.h),
          // Submitter info
          Text(
            'Submitted by: $statusDisplay',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          Text(
            'Seen by $_seenCount people',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          Gap(Spacing.md.h),
          // Vote buttons
          Row(
            children: [
              // Upvote button
              _buildVoteButton(
                icon: Icons.arrow_upward,
                label: 'Upvote (FOR)',
                count: _upvoteCount,
                isActive: _userVote == 'up',
                onTap: () => _castVote('up'),
              ),
              Gap(Spacing.md.w),
              // Downvote button
              _buildVoteButton(
                icon: Icons.arrow_downward,
                label: 'Downvote (AGAINST)',
                count: _downvoteCount,
                isActive: _userVote == 'down',
                onTap: () => _castVote('down'),
              ),
            ],
          ),
          Gap(Spacing.md.h),
          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${percentage.toStringAsFixed(0)}% upvote',
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color:
                          _isAboveThreshold
                              ? Colors.green
                              : colorScheme.primary,
                    ),
                  ),
                  Text(
                    needsMore ? 'needs 50% to activate' : 'ACTIVATED!',
                    style: textTheme.bodySmall?.copyWith(
                      color:
                          _isAboveThreshold
                              ? Colors.green
                              : colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
              Gap(Spacing.xs.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: _isAboveThreshold ? Colors.green : colorScheme.primary,
                ),
              ),
              if (needsMore && _seenCount < 20)
                Padding(
                  padding: EdgeInsets.only(top: Spacing.xs.h),
                  child: Text(
                    '${20 - _seenCount} more people need to see this before it can activate',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoteButton({
    required IconData icon,
    required String label,
    required int count,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: _isUpdating ? null : onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: Spacing.sm.h),
          decoration: BoxDecoration(
            color:
                isActive
                    ? colorScheme.primary.withOpacity(0.1)
                    : colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
            border: Border.all(
              color: isActive ? colorScheme.primary : Colors.transparent,
              width: BorderWidthTokens.hairline,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color:
                    isActive
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.6),
                size: 24,
              ),
              Gap(Spacing.xs.h),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isActive ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color:
                      isActive
                          ? colorScheme.primary
                          : colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusDisplay(String? status) {
    switch (status) {
      case 'single':
        return 'Single';
      case 'taken':
        return 'Taken';
      case 'figuring_it_out':
        return 'Figuring it out';
      case 'open':
        return 'Open';
      default:
        return 'Someone';
    }
  }
}

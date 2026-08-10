// lib/features/forums/presentation/widgets/topic_voting_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/widgets/mini_container_indicator.dart';
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
      context.showErrorSnackbar('Sign in to perform this action');
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

    // Live cross-user vote counts (20260826120000_realtime_count_broadcasts.sql)
    // — every viewer's card, including a guest's, ticks up the instant ANY
    // viewer votes. Folded into the same _upvoteCount/_downvoteCount fields
    // _castVote's optimistic update already owns (rather than a separate
    // "effective count" read only at the button) so _activationPercentage
    // stays in sync with what the vote buttons display — both read the same
    // numbers. Skipped while _isUpdating: a broadcast landing mid-optimistic
    // update would otherwise stomp the just-applied optimistic value with a
    // (possibly stale, cross-request-ordering) server value before this
    // card's own castTopicVoteProvider call has even returned.
    ref.listen(topicLiveCountsProvider(widget.topic.id), (previous, next) {
      final counts = next.valueOrNull;
      if (counts == null || _isUpdating) return;
      setState(() {
        _upvoteCount = counts.upvoteCount;
        _downvoteCount = counts.downvoteCount;
      });
    });

    final rawStatusDisplay = statusDisplayFor(widget.topic.submitterStatus);
    // 'Someone' here, not '' like statusDisplayFor's own default: this
    // string is read directly as "Submitted by: $statusDisplay" below, so an
    // empty status needs a real word, unlike the icon/color call sites where
    // '' selects the unknown-status glyph.
    final statusDisplay =
        rawStatusDisplay.isEmpty ? 'Someone' : rawStatusDisplay;
    final percentage = _activationPercentage;
    final needsMore = !_isAboveThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Gap(Spacing.lg.h),
        // Topic label
        MiniContainerIndicator(
          color: colorScheme.primary,
          text: 'TOPIC UP FOR VOTE',
        ),
        Gap(Spacing.sm.h),
        // Topic content
        Text(
          '"${widget.topic.content}"',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        Gap(Spacing.sm.h),
        // Submitter info
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submitted by: $statusDisplay',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Seen by ',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    AnimatedRollingCounter(
                      count: _seenCount,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    Text(
                      ' people',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${percentage.toStringAsFixed(0)}% upvote',
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                        _isAboveThreshold ? Colors.green : colorScheme.primary,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                // Upvote button
                _buildVoteButton(
                  icon: Icons.arrow_upward,
                  label: 'FOR',
                  count: _upvoteCount,
                  isActive: _userVote == 'up',
                  onTap: () => _castVote('up'),
                ),
                Gap(Spacing.md.w),
                // Downvote button
                _buildVoteButton(
                  icon: Icons.arrow_downward,
                  label: 'AGAINST',
                  count: _downvoteCount,
                  isActive: _userVote == 'down',
                  onTap: () => _castVote('down'),
                ),
              ],
            ),
          ],
        ),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: 6,
            backgroundColor: colorScheme.primary.withOpacity(.1),
            color: _isAboveThreshold ? colorScheme.primary : colorScheme.info,
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
        Gap(Spacing.md),
        AppDivider(),
      ],
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

    return CardInkWell(
      elevation: 0,
      padding: const EdgeInsets.all(0),
      onTap: _isUpdating ? null : onTap,
      color:
          isActive
              ? colorScheme.primary.withOpacity(0.1)
              : colorScheme.background,
      child: SizedBox(
        width: 80.w,
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
            AnimatedRollingCounter(
              count: count,
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
    );
  }
}

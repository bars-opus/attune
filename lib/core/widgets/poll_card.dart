// lib/core/widgets/poll_card.dart

import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/polls/data/models/poll_model.dart';
import 'package:attune/core/polls/presentation/providers/poll_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders a poll attached to an opinion or a forum topic (§8.11).
///
/// Before voting, options are tappable buttons and no counts are shown — the
/// server withholds them, so there is nothing here to accidentally reveal.
/// After voting, each option becomes a result bar with its share, and the
/// viewer's own choice is marked. Tapping a different option moves the vote;
/// tapping the current one retracts it and re-hides the results.
class PollCard extends ConsumerWidget {
  final PollTarget target;

  /// Rendered inside a card that already pads its content.
  final EdgeInsetsGeometry padding;

  const PollCard({
    super.key,
    required this.target,
    this.padding = const EdgeInsets.symmetric(horizontal: Spacing.md),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pollAsync = ref.watch(pollProvider(target));

    return pollAsync.when(
      // A poll is an optional attachment: no poll, nothing to show. Errors stay
      // silent too — a failed poll fetch must not blank out the post it hangs
      // off, which is the actual content.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (poll) {
        if (poll == null) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: _PollBody(poll: poll, target: target),
        );
      },
    );
  }
}

class _PollBody extends ConsumerStatefulWidget {
  final PollModel poll;
  final PollTarget target;

  const _PollBody({required this.poll, required this.target});

  @override
  ConsumerState<_PollBody> createState() => _PollBodyState();
}

class _PollBodyState extends ConsumerState<_PollBody> {
  bool _busy = false;

  Future<void> _onOptionTap(PollOptionModel option) async {
    if (_busy) return;
    setState(() => _busy = true);

    final notifier = ref.read(pollProvider(widget.target).notifier);
    final isCurrentChoice = widget.poll.myOptionId == option.id;

    try {
      // Tapping your current choice retracts it (§8.11 allows retraction);
      // tapping any other option moves the vote.
      if (isCurrentChoice) {
        await notifier.retract();
      } else {
        await notifier.vote(option.id);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_voteErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Maps the RPC's stable error codes to something a person can act on.
  String _voteErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('posting_banned')) {
      return 'Your account is temporarily restricted from voting.';
    }
    if (text.contains('not_authenticated')) {
      return 'Verify your phone number to vote in polls.';
    }
    return 'Could not register your vote. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...poll.options.map(
          (option) => Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _PollOptionTile(
              option: option,
              isMyChoice: poll.myOptionId == option.id,
              share: option.shareOf(poll.totalVotes),
              revealed: poll.hasVoted,
              enabled: !_busy,
              onTap: () => _onOptionTap(option),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            poll.hasVoted
                ? '${_voteLabel(poll.totalVotes)} · Tap your choice to undo'
                : 'Vote to see results',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  String _voteLabel(int? total) {
    if (total == null) return 'Results';
    return total == 1 ? '1 vote' : '$total votes';
  }
}

class _PollOptionTile extends StatelessWidget {
  final PollOptionModel option;
  final bool isMyChoice;
  final double? share;
  final bool revealed;
  final bool enabled;
  final VoidCallback onTap;

  const _PollOptionTile({
    required this.option,
    required this.isMyChoice,
    required this.share,
    required this.revealed,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final borderColor =
        isMyChoice ? colorScheme.primary : colorScheme.outlineVariant;
    final fillColor =
        isMyChoice
            ? colorScheme.primary.withValues(alpha: 0.18)
            : colorScheme.surfaceContainerHighest;

    return Semantics(
      button: true,
      selected: isMyChoice,
      // Without this the screen reader announces only the label, losing both
      // the result and which option the viewer picked.
      label:
          revealed
              ? '${option.label}, ${_percentLabel(share)}'
                  '${isMyChoice ? ', your vote' : ''}'
              : option.label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadiusTokens.mdAll,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadiusTokens.mdAll,
            border: Border.all(
              color: borderColor,
              width: isMyChoice ? 1.5 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // The result bar. Width animates from 0 on reveal, so the standing
              // reads as a result rather than appearing pre-drawn.
              if (revealed && share != null)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share!.clamp(0.0, 1.0),
                    child: AnimatedContainer(
                      duration: kSettleDuration,
                      curve: Curves.easeOutCubic,
                      color: fillColor,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.smMd,
                  vertical: Spacing.smMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.label,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isMyChoice ? FontWeight.w600 : FontWeight.w400,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (revealed) ...[
                      if (isMyChoice)
                        Padding(
                          padding: const EdgeInsets.only(right: Spacing.xs),
                          child: Icon(
                            Icons.check_circle,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ),
                      Text(
                        _percentLabel(share),
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _percentLabel(double? share) {
    if (share == null) return '—';
    return '${(share * 100).round()}%';
  }
}

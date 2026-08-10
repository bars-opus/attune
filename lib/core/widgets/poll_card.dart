// lib/core/widgets/poll_card.dart

import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/polls/data/models/poll_model.dart';
import 'package:attune/core/polls/presentation/providers/poll_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Renders a poll attached to an opinion or a forum topic (§8.11).
///
/// Before voting, options are tappable buttons and no counts are shown — the
/// server withholds them, so there is nothing here to accidentally reveal.
/// After voting, each option becomes a result bar with its share, and the
/// viewer's own choice is marked. Tapping a different option asks for
/// confirmation first (a bottom sheet) since it overwrites an existing
/// choice; tapping the current one retracts it directly — that tap is
/// already the explicit "undo" gesture — and re-hides the results.
class PollCard extends ConsumerWidget {
  final PollTarget target;

  /// Rendered inside a card that already pads its content on the left —
  /// both call sites (OpinionCard, DebateRoomScreen's topic header) sit
  /// inside a layout already indented past an avatar/leading element, so
  /// only the right side gets its own padding here.
  final EdgeInsetsGeometry padding;

  const PollCard({
    super.key,
    required this.target,
    this.padding = const EdgeInsets.only(right: Spacing.md),
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
    // Guarded before the confirm-dialog/busy-state dance below, same as the
    // other action buttons on OpinionCard/CommentThreadScreen/forum widgets
    // — vote/retract are authenticated-only RPCs, so a guest tap should
    // explain why rather than surface a raw error from deep in the call.
    if (Supabase.instance.client.auth.currentUser == null) {
      context.showErrorSnackbar('Sign in to perform this action');
      return;
    }

    final isCurrentChoice = widget.poll.myOptionId == option.id;
    // Changing an already-cast vote overwrites it, unlike the first vote (no
    // prior choice to lose) or a retraction (tapping your own choice is
    // already the explicit "undo" gesture) — only the "swap to a different
    // option" path can accidentally discard a choice with a stray tap, so
    // only that path is gated.
    final isChangingVote = widget.poll.myOptionId != null && !isCurrentChoice;
    if (isChangingVote) {
      final confirmed = await _confirmChangeVote(option);
      if (!confirmed || !mounted) return;
    }

    setState(() => _busy = true);

    final notifier = ref.read(pollProvider(widget.target).notifier);

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_voteErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Same Completer-bridged BottomSheetUtils + ConfirmationDialog pattern as
  // CommentThreadScreen's delete confirmation: ConfirmationDialog's
  // onConfirm/onCancel are plain callbacks, not a Future, so a Completer
  // adapts them into the awaitable bool this method needs. Also completes
  // `false` if the sheet is dismissed by tapping outside/dragging down
  // rather than tapping either button, so an accidental dismiss is treated
  // as "don't change my vote," not as silent confirmation.
  Future<bool> _confirmChangeVote(PollOptionModel option) {
    final completer = Completer<bool>();
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 320.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.warning,
        title: 'Change your vote?',
        message: 'Switch your vote to "${option.label}"?',
        confirmText: 'Change vote',
        onConfirm: () => completer.complete(true),
        onCancel: () => completer.complete(false),
      ),
    ).then((_) {
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future;
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
        Gap(Spacing.md),
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
        Gap(Spacing.sm),
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

    final borderColor =
        isMyChoice ? colorScheme.primary : colorScheme.outlineVariant;
    final fillColor =
        isMyChoice ? colorScheme.primary : colorScheme.surfaceContainerHighest;

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
            color: colorScheme.primary.withOpacity(.1),
            borderRadius: BorderRadiusTokens.mdAll,
            border: Border.all(color: borderColor, width: isMyChoice ? 1 : 0.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // The base content: text/icon colored for the UNCOVERED part of
              // the tile (colorScheme.onSurface). Always laid out full-width
              // so the Stack's size comes from this, and the row's own
              // Padding/spacing is the single source of truth for layout.
              _buildContent(context, onFill: false),
              // The result bar, clipped to exactly its own animated width —
              // widthFactor tweens from 0 on first reveal (and from its
              // previous width on any later vote/retract that changes
              // `share`), so the bar always reads as growing into place
              // rather than appearing pre-drawn or snapping between states.
              if (revealed && share != null)
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: share!.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 2000),
                    curve: Curves.easeOutBack,
                    builder: (context, widthFactor, child) {
                      // Curves.easeOutBack overshoots past its target and
                      // dips slightly negative before settling — fine for a
                      // scale/offset animation, but FractionallySizedBox
                      // asserts widthFactor >= 0.0, so the raw curved value
                      // has to be clamped before it drives any layout below.
                      final clampedWidth = widthFactor.clamp(0.0, 1.0);
                      return ClipRect(
                        clipper: _LeftFractionClipper(clampedWidth),
                        // StackFit.expand: Stack's default fit is `loose`,
                        // which gives non-positioned children (ColoredBox,
                        // _buildContent below) unconstrained sizing — a
                        // ColoredBox with no child then collapses to zero
                        // size and paints nothing, which is why the primary
                        // fill wasn't visible. `expand` forces both children
                        // to the ClipRect's own full bounds instead.
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Fills only the clipped region — ClipRect above
                            // already bounds it to the bar's own width, so
                            // this can stay a plain full-size ColoredBox.
                            ColoredBox(color: fillColor),
                            // The SAME content, but colored for the COVERED
                            // part of the tile — colorScheme.onPrimary reads
                            // correctly against a primary-colored fill in
                            // both themes (white in light mode, near-black
                            // in dark mode; see LightColors/DarkColors.white
                            // in app_theme.dart). Only rendered when this
                            // option is the selected one, since only the
                            // selected option's bar is primary-colored —
                            // the neutral surfaceContainerHighest fill on
                            // other options never needs inverted text.
                            if (isMyChoice)
                              _buildContent(context, onFill: true),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The label/checkmark/percent row, in one of two color sets depending on
  /// whether it's being drawn for the covered (over the primary-colored
  /// fill, [onFill] true) or uncovered (over the tile's base background,
  /// [onFill] false) portion of the tile. Two full-width copies are
  /// stacked and clipped by [_LeftFractionClipper] rather than trying to
  /// split a single Text's color mid-string, since the split point moves
  /// continuously as the bar animates.
  Widget _buildContent(BuildContext context, {required bool onFill}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final contentColor = onFill ? colorScheme.onPrimary : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.smMd,
        vertical: Spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              option.label,
              style: textTheme.bodySmall?.copyWith(
                fontWeight: isMyChoice ? FontWeight.w600 : FontWeight.w400,
                color: contentColor,
              ),
            ),
          ),
          if (revealed) ...[
            if (isMyChoice)
              Padding(
                padding: const EdgeInsets.only(right: Spacing.xs),
                child: Icon(Icons.check_circle, size: 16, color: contentColor),
              ),
            Text(
              _percentLabel(share),
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: contentColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _percentLabel(double? share) {
    if (share == null) return '—';
    return '${(share * 100).round()}%';
  }
}

/// Clips to the left [fraction] of the child's own bounds — used to bound
/// the covered-text overlay to exactly the animated bar width, the same
/// width FractionallySizedBox(widthFactor: fraction) would occupy, but as a
/// clip rather than a resize so the two stacked content copies underneath
/// stay pixel-aligned with each other (a resized child would re-lay-out its
/// text at a different width and could wrap differently).
class _LeftFractionClipper extends CustomClipper<Rect> {
  final double fraction;

  const _LeftFractionClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftFractionClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A6 · What brings you to Attune? (Spec 1 §3.7): three equal cards,
/// nothing preselected, a radio group; Continue once one is chosen.
class PathStep extends StatefulWidget {
  const PathStep({
    super.key,
    required this.onContinue,
    this.ownCountry,
    this.openCountries = const [],
    this.onAlreadyInvited,
    this.errorText,
  });

  /// The chosen path. The step stays busy until it has finished.
  final FutureOr<void> Function(AppPath path) onContinue;

  /// ISO 3166-1 alpha-2 of the person's own number, when known.
  final String? ownCountry;

  /// config.dating_open_countries (the D15 seam); empty when never read.
  final List<String> openCountries;

  /// "My partner already invited me" (RI-2).
  final VoidCallback? onAlreadyInvited;

  /// Shown under the cards and read out (e.g. Dating chosen offline).
  final String? errorText;

  @override
  State<PathStep> createState() => _PathStepState();
}

class _PathStepState extends State<PathStep> with SubmitOnce {
  AppPath? _selected;

  @override
  void didUpdateWidget(covariant PathStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final error = widget.errorText;
    if (error != null && error != oldWidget.errorText) {
      SemanticsService.announce(error, Directionality.of(context));
    }
  }

  void _select(AppPath path) {
    if (_selected == path) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = path);
  }

  void _continue() {
    final path = _selected;
    if (path == null || submitting) return;
    submitOnce(() => widget.onContinue(path));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final own = widget.ownCountry;
    final notOpenHere =
        own != null &&
        widget.openCountries.isNotEmpty &&
        !widget.openCountries.contains(own);
    final cards = [
      (
        AppPath.relationship,
        loc.flow_pathRelationshipTitle,
        loc.flow_pathRelationshipLine,
        null,
      ),
      (
        AppPath.dating,
        loc.flow_pathDatingTitle,
        loc.flow_pathDatingLine,
        notOpenHere
            ? loc.flow_pathNotOpen(
              countryNameFor(
                own,
                special: {'GB': loc.flow_countryUk, 'US': loc.flow_countryUs},
              ),
            )
            : null,
      ),
      (
        AppPath.justMe,
        loc.flow_pathJustMeTitle,
        loc.flow_pathJustMeLineFull,
        null,
      ),
    ];
    final error = widget.errorText;

    return FlowFrame(
      title: loc.flow_pathTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: loc.flow_pathGroupSemantics,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (path, title, line, note) in cards) ...[
                  PathChoiceCard(
                    title: title,
                    line: line,
                    note: note,
                    selected: _selected == path,
                    onTap: () => _select(path),
                  ),
                  const SizedBox(height: Spacing.smMd),
                ],
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: Spacing.sm),
            FlowErrorLine(
              text: error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
          const SizedBox(height: Spacing.md),
          Text(
            loc.flow_pathFooter,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.onAlreadyInvited != null) ...[
            const SizedBox(height: Spacing.sm),
            FlowTextLink(
              label: loc.flow_pathAlreadyInvited,
              alignment: AlignmentDirectional.centerStart,
              onPressed: widget.onAlreadyInvited!,
            ),
          ],
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_continue,
          busy: submitting,
          onPressed: _selected == null ? null : _continue,
        ),
      ],
    );
  }
}

/// One path as a radio card (A6, and Settings -> How you use Attune).
class PathChoiceCard extends StatelessWidget {
  const PathChoiceCard({
    super.key,
    required this.title,
    required this.line,
    required this.selected,
    required this.onTap,
    this.note,
  });

  final String title;
  final String line;
  final String? note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = flowAccent(context);
    final duration =
        reduceMotionOf(context) ? Duration.zero : kSelectionDuration;
    return Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: [title, line, if (note != null) note!].join('. '),
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadiusTokens.lgAll,
            child: AnimatedContainer(
              duration: duration,
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: selected ? accent.withValues(alpha: 0.08) : null,
                borderRadius: BorderRadiusTokens.lgAll,
                border: Border.all(
                  color: selected ? accent : scheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          line,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (note != null) ...[
                          const SizedBox(height: Spacing.xs),
                          Text(
                            note!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? accent : scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

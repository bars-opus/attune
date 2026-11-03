import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/about_us_copy.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/couple_profile/presentation/widgets/changed_by_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The About us screen (Spec 1 §3.8, `/about-us/:relationshipId`, or the
/// draft at `/about-us/draft`): one row per question, the answer, and
/// under each answered row "Changed by {first name or 'you'} - {date}".
/// Tapping a row asks that one question again. Read-only while paused or
/// in the ending window ("You can read this until {date}."). No push, no
/// feed, no history list; "Together since" is a date, never a count.
class AboutUsScreen extends ConsumerWidget {
  const AboutUsScreen({
    super.key,
    required this.target,
    required this.onClose,
    this.partnerName,
    this.now,
  });

  final AboutUsTarget target;
  final VoidCallback onClose;

  /// The partner's first name, for the draft's "More about this".
  final String? partnerName;

  /// Today (tests pin it).
  final DateTime? now;

  Future<void> _ask(
    BuildContext context,
    AboutUsQuestion? only, {
    bool all = false,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder:
          (route) => AboutUsQuestionFlow(
            target: target,
            only: all ? null : only,
            partnerName: partnerName,
            onDone: () => Navigator.of(route).pop(),
          ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final id = target.relationshipId;
    final coupleName =
        id == null ? null : ref.watch(coupleNameProvider(id)).valueOrNull;
    final title = coupleName ?? loc.aboutUs_title;
    final async = ref.watch(coupleProfileProvider(target));
    final profile = async.valueOrNull;
    if (profile == null) {
      final failed = async.hasError && !async.isLoading;
      // Fix round 1 (review M-3): a refusal (archived, sealed, the draft
      // after linking, another couple's id) can't be retried; anything
      // else is the connection.
      final refused = failed && async.error is AboutUsRefused;
      return FlowFrame(
        title: title,
        onBack: onClose,
        body:
            failed
                ? FlowErrorLine(
                  text:
                      refused
                          ? loc.aboutUs_errorReadOnly
                          : loc.aboutUs_loadFailed,
                  liveRegion: true,
                  // Fix round 1 (review M-6): as the route page and sheet.
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                )
                : LinearProgressIndicator(semanticsLabel: loc.aboutUs_title),
        actions: [
          if (failed && !refused)
            FlowPrimaryButton(
              label: loc.flow_tryAgain,
              onPressed: () => ref.invalidate(coupleProfileProvider(target)),
            ),
          if (refused)
            FlowSecondaryButton(label: loc.flow_close, onPressed: onClose),
        ],
      );
    }
    final today = now ?? DateTime.now();
    final readOnly = profile.readOnly;
    final rows = <(AboutUsQuestion, AboutUsField, String, String?)>[
      (
        AboutUsQuestion.together,
        AboutUsField.togetherSince,
        loc.aboutUs_rowSince,
        profile.togetherSince == null
            ? null
            : sinceText(profile.togetherSince!),
      ),
      (
        AboutUsQuestion.stage,
        AboutUsField.stage,
        loc.aboutUs_rowStage,
        profile.stage == null
            ? null
            : stageText(loc, profile.stage!, words: profile.stageWords),
      ),
      if (profile.stage == CoupleStage.married || profile.ceremonies.isNotEmpty)
        (
          AboutUsQuestion.married,
          AboutUsField.ceremonies,
          loc.aboutUs_rowCeremonies,
          profile.ceremonies.isEmpty
              ? null
              : [
                for (final c in profile.ceremonies) ceremonyText(loc, c),
              ].join('\n'),
        ),
      (
        AboutUsQuestion.living,
        AboutUsField.living,
        loc.aboutUs_rowLiving,
        profile.living == null ? null : livingText(loc, profile.living!),
      ),
      (
        AboutUsQuestion.children,
        AboutUsField.children,
        loc.aboutUs_rowChildren,
        profile.children == null
            ? null
            : childrenText(loc, profile.children!, profile.childAgeBands),
      ),
      (
        AboutUsQuestion.anniversary,
        AboutUsField.anniversary,
        loc.aboutUs_rowAnniversary,
        anniversaryText(loc, profile),
      ),
    ];
    return FlowFrame(
      title: title,
      onBack: onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (readOnly && profile.readUntil != null) ...[
            Text(
              loc.aboutUs_readOnlyUntil(
                MyDateFormat.toDate(profile.readUntil!),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          if (profile.pendingSync) ...[
            Text(
              loc.aboutUs_pendingSync,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          for (final (question, field, label, answer) in rows)
            _AboutUsRow(
              label: label,
              value: answer ?? loc.aboutUs_notAnswered,
              change: profile.changes[field],
              now: today,
              onTap: readOnly ? null : () => _ask(context, question),
            ),
          const SizedBox(height: Spacing.md),
          Text(
            loc.aboutUs_footer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        if (!readOnly && profile.isEmpty)
          FlowPrimaryButton(
            label: loc.aboutUs_answerQuestions,
            onPressed: () => _ask(context, null, all: true),
          ),
      ],
    );
  }
}

class _AboutUsRow extends StatelessWidget {
  const _AboutUsRow({
    required this.label,
    required this.value,
    required this.change,
    required this.now,
    required this.onTap,
  });

  final String label;
  final String value;
  final FieldChange? change;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final changedBy = change == null ? null : changedByText(loc, change!, now);
    return Semantics(
      container: true,
      button: onTap != null,
      label: [label, value, if (changedBy != null) changedBy].join('. '),
      hint: onTap == null ? null : loc.aboutUs_rowEditHint,
      // Fix round 1 (review I-1): the one node a screen reader activates
      // (the InkWell's own action is excluded with its text).
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          value,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (change != null) ...[
                          const SizedBox(height: Spacing.xs),
                          ChangedByLine(change: change!, now: now),
                        ],
                      ],
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
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

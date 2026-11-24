// Spec 2 W9 (§3.9 steps 3 and 5, §8 W9; I-12): what About us shows of
// the couple's Dating start. The AU2 chip "The day you matched: {date}"
// through the client override of Spec 1's aboutUsDateSuggestionsProvider
// (never pre-filled: a tap fills it), and one row, "How we met", opening
// the card of the first messages as both saw them. Both are read by the
// relationship's members only, and show nothing when there is nothing
// (no Dating origin, no card, the flag off, a failed read).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/locale_provider.dart'
    show currentLocaleProvider;
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart'
    show DatePrecision, TogetherSince;
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart'
    show AboutUsDateSuggestion;
import 'package:attune/features/dating/chat/guided_questions.dart'
    show datingGuidedQuestion;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The localisations outside a widget (the chip's words), English when the
/// app's locale can't be read.
AppLocalizations _loc(Ref ref) {
  try {
    return lookupAppLocalizations(ref.watch(currentLocaleProvider));
  } catch (_) {
    return lookupAppLocalizations(const Locale('en'));
  }
}

/// I-12: About us's AU2 chips for [relationshipId]: "The day you matched:
/// {date}" when the couple came from Dating, else none.
List<AboutUsDateSuggestion> datingAboutUsDateSuggestions(
  Ref ref,
  String relationshipId,
) {
  final account = ref.watch(datingAccountProvider);
  if (account == null) return const [];
  final at =
      ref
          .watch(datingLinkOriginProvider((account, relationshipId)))
          .valueOrNull;
  if (at == null) return const [];
  final local = at.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  return [
    AboutUsDateSuggestion(
      label: _loc(ref).dating_linkMatchedChip(MyDateFormat.toDate(day)),
      since: TogetherSince(day, DatePrecision.day),
    ),
  ];
}

/// About us's "How we met" row: nothing unless the couple kept the card.
class DatingHowWeMetRow extends ConsumerWidget {
  const DatingHowWeMetRow({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final account = ref.watch(datingAccountProvider);
    if (account == null) return const SizedBox.shrink();
    final items =
        ref
            .watch(datingHowWeMetProvider((account, relationshipId)))
            .valueOrNull;
    if (items == null) return const SizedBox.shrink();
    void open() => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => DatingHowWeMetScreen(items: items)),
    );
    return Semantics(
      container: true,
      button: true,
      label: loc.dating_howWeMetRow,
      hint: loc.dating_howWeMetRowHint,
      onTap: open,
      child: ExcludeSemantics(
        child: InkWell(
          key: const ValueKey('dating_how_we_met_row'),
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      loc.dating_howWeMetRow,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
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

/// The How we met card: the first messages as both saw them, in order,
/// each with who wrote it. Read only; nothing here moves.
class DatingHowWeMetScreen extends StatelessWidget {
  const DatingHowWeMetScreen({super.key, required this.items});

  final List<DatingHowWeMetItem> items;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(title: Text(loc.dating_howWeMetRow)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Text(
                loc.dating_howWeMetIntro,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.md),
              for (final item in items)
                Semantics(
                  container: true,
                  label: [
                    item.mine
                        ? loc.dating_howWeMetYou
                        : loc.dating_howWeMetThem,
                    if (_question(loc, item) case final q?) q,
                    item.text,
                  ].join('. '),
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: Align(
                        alignment:
                            item.mine
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.all(Spacing.sm),
                          decoration: BoxDecoration(
                            color:
                                item.mine
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadiusTokens.mdAll,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.mine
                                    ? loc.dating_howWeMetYou
                                    : loc.dating_howWeMetThem,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color:
                                      item.mine
                                          ? theme.colorScheme.onPrimaryContainer
                                          : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: Spacing.xs),
                              // Fix round 2 (M-3): a guided answer under
                              // its question, as the chat shows it.
                              if (_question(loc, item) case final q?) ...[
                                Text(
                                  q,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color:
                                        item.mine
                                            ? theme
                                                .colorScheme
                                                .onPrimaryContainer
                                            : theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: Spacing.xs),
                              ],
                              Text(
                                item.text,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color:
                                      item.mine
                                          ? theme.colorScheme.onPrimaryContainer
                                          : theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The guided question [item] answers, in the chat's own words; null for a
/// message (or a question this app doesn't know).
String? _question(AppLocalizations loc, DatingHowWeMetItem item) {
  final id = item.questionId;
  if (id == null) return null;
  final q = datingGuidedQuestion(loc, id);
  return q.isEmpty ? null : q;
}

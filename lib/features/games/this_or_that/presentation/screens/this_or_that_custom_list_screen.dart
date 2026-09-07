import 'package:attune/features/games/this_or_that/data/models/custom_this_or_that_question.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_custom_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_custom_card.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ThisOrThatCustomListScreen extends ConsumerWidget {
  const ThisOrThatCustomListScreen({super.key});

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final changed = await context.pushNamed('thisOrThatCustomCreate');
    if (changed == true) {
      ref.invalidate(myThisOrThatCustomQuestionsProvider);
      ref.invalidate(partnerThisOrThatCustomQuestionsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ThisOrThatPalette.of(context);
    final partnerName = ref.watch(partnerNameProvider).valueOrNull ?? 'Partner';

    return DefaultTabController(
      length: 2,
      child: ThisOrThatGameScaffold(
        title: 'Our question decks',
        bottom: ThisOrThatPrimaryAction(
          label: 'Write a question',
          icon: Icons.add_rounded,
          onPressed: () => _openCreate(context, ref),
        ),
        child: Column(
          children: [
            Text(
              'Make the game sound more like the two of you.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.mutedInk,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 46,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: palette.panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.line),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: palette.ink,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: palette.canvas,
                unselectedLabelColor: palette.mutedInk,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
                tabs: [
                  const Tab(text: 'Mine'),
                  Tab(
                    child: Text(
                      partnerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: TabBarView(
                children: [
                  _QuestionDeck(
                    questions: ref.watch(myThisOrThatCustomQuestionsProvider),
                    emptyTitle: 'Your deck is waiting',
                    emptyMessage:
                        'Write a choice that only the two of you could answer.',
                    emptyIcon: Icons.edit_note_rounded,
                    onRetry:
                        () =>
                            ref.invalidate(myThisOrThatCustomQuestionsProvider),
                    onRefresh: () async {
                      final _ = await ref.refresh(
                        myThisOrThatCustomQuestionsProvider.future,
                      );
                    },
                    itemBuilder:
                        (question) => ThisOrThatCustomCard(
                          question: question,
                          isOwnQuestion: true,
                          onDeleted:
                              () => ref.invalidate(
                                myThisOrThatCustomQuestionsProvider,
                              ),
                          onPrivacyChanged: () {
                            ref.invalidate(myThisOrThatCustomQuestionsProvider);
                            ref.invalidate(
                              partnerThisOrThatCustomQuestionsProvider,
                            );
                          },
                          onSharedChanged: () {
                            ref.invalidate(myThisOrThatCustomQuestionsProvider);
                            ref.invalidate(
                              partnerThisOrThatCustomQuestionsProvider,
                            );
                          },
                        ),
                  ),
                  _QuestionDeck(
                    questions: ref.watch(
                      partnerThisOrThatCustomQuestionsProvider,
                    ),
                    emptyTitle: '$partnerName has not shared a question yet',
                    emptyMessage:
                        'Shared questions will appear here when they are ready.',
                    emptyIcon: Icons.favorite_outline_rounded,
                    onRetry:
                        () => ref.invalidate(
                          partnerThisOrThatCustomQuestionsProvider,
                        ),
                    onRefresh: () async {
                      final _ = await ref.refresh(
                        partnerThisOrThatCustomQuestionsProvider.future,
                      );
                    },
                    itemBuilder:
                        (question) => ThisOrThatCustomCard(
                          question: question,
                          isOwnQuestion: false,
                          onReported:
                              () => ref.invalidate(
                                partnerThisOrThatCustomQuestionsProvider,
                              ),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionDeck extends StatelessWidget {
  const _QuestionDeck({
    required this.questions,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.onRetry,
    required this.onRefresh,
    required this.itemBuilder,
  });

  final AsyncValue<List<CustomThisOrThatQuestion>> questions;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final Widget Function(CustomThisOrThatQuestion question) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return questions.when(
      loading:
          () => const Center(
            key: Key('custom-question-loading'),
            child: CircularProgressIndicator(),
          ),
      error:
          (_, __) => _DeckMessage(
            icon: Icons.cloud_off_rounded,
            title: 'This deck could not load',
            message: 'Check your connection and try again.',
            actionLabel: 'Try again',
            onAction: onRetry,
          ),
      data: (items) {
        if (items.isEmpty) {
          return _DeckMessage(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) => itemBuilder(items[index]),
          ),
        );
      },
    );
  }
}

class _DeckMessage extends StatelessWidget {
  const _DeckMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: palette.thatColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: palette.thatColor, size: 29),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.mutedInk,
                height: 1.4,
                letterSpacing: 0,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// lib/features/games/this_or_that/presentation/screens/this_or_that_custom_list_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_custom_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_custom_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThisOrThatCustomListScreen extends ConsumerStatefulWidget {
  const ThisOrThatCustomListScreen({super.key});

  @override
  ConsumerState<ThisOrThatCustomListScreen> createState() =>
      _ThisOrThatCustomListScreenState();
}

class _ThisOrThatCustomListScreenState
    extends ConsumerState<ThisOrThatCustomListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(myThisOrThatCustomQuestionsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final myQuestionsAsync = ref.watch(myThisOrThatCustomQuestionsProvider);
    final partnerName = ref.watch(partnerNameProvider).valueOrNull ?? 'Partner';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Custom This or That questions'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'My questions'),
              Tab(text: "$partnerName's questions"),
            ],
            indicatorColor: colorScheme.primary,
            labelColor: colorScheme.primary,
          ),
        ),
        floatingActionButton: AppFab(
          icon: Icons.add,
          onPressed: () async {
            final needsRefresh = await context.pushNamed(
              'thisOrThatCustomCreate',
            );
            if (needsRefresh == true) {
              ref.invalidate(myThisOrThatCustomQuestionsProvider);
              ref.invalidate(partnerThisOrThatCustomQuestionsProvider);
            }
          },
        ),
        body: TabBarView(
          children: [
            // My questions tab
            myQuestionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
              data: (questions) {
                if (questions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.edit_note_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        Gap(Spacing.md.h),
                        Text(
                          'No custom questions yet',
                          style: textTheme.titleMedium,
                        ),
                        Gap(Spacing.sm.h),
                        Text(
                          'Create your own This or That questions\nfor you and your partner',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium,
                        ),
                        Gap(Spacing.lg.h),
                        AppButton(
                          label: 'Create your first question',
                          onPressed: () async {
                            final needsRefresh = await context.pushNamed(
                              'thisOrThatCustomCreate',
                            );
                            if (needsRefresh == true) {
                              ref.invalidate(
                                myThisOrThatCustomQuestionsProvider,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.all(Spacing.md.w),
                  itemCount: questions.length,
                  itemBuilder: (context, index) {
                    final question = questions[index];
                    return ThisOrThatCustomCard(
                      question: question,
                      isOwnQuestion: true,
                      onDeleted: () {
                        ref.invalidate(myThisOrThatCustomQuestionsProvider);
                      },
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
                    );
                  },
                );
              },
            ),
            // Partner's questions tab
            ref
                .watch(partnerThisOrThatCustomQuestionsProvider)
                .when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('Error: $error')),
                  data: (questions) {
                    if (questions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 64,
                              color: Colors.grey,
                            ),
                            Gap(Spacing.md.h),
                            Text(
                              'No shared questions yet',
                              style: textTheme.titleMedium,
                            ),
                            Gap(Spacing.sm.h),
                            Text(
                              "$partnerName hasn't shared any custom questions yet.",
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: EdgeInsets.all(Spacing.md.w),
                      itemCount: questions.length,
                      itemBuilder: (context, index) {
                        final question = questions[index];
                        return ThisOrThatCustomCard(
                          question: question,
                          isOwnQuestion: false,
                          onReported: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Thank you for reporting. We will review it.',
                                ),
                              ),
                            );
                            ref.invalidate(
                              partnerThisOrThatCustomQuestionsProvider,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}

// lib/features/games/truth_or_dare/presentation/screens/custom_truth_or_dare_list_screen.dart

import 'package:attune/features/auth/utility/auth_exports.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:attune/features/games/truth_or_dare/presentation/widgets/custom_truth_or_dare_card.dart';

class CustomTruthOrDareListScreen extends ConsumerStatefulWidget {
  const CustomTruthOrDareListScreen({super.key});

  @override
  ConsumerState<CustomTruthOrDareListScreen> createState() =>
      _CustomTruthOrDareListScreenState();
}

class _CustomTruthOrDareListScreenState
    extends ConsumerState<CustomTruthOrDareListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(myCustomTruthOrDareQuestionsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final customQuestionsAsync = ref.watch(
      myCustomTruthOrDareQuestionsProvider,
    );
    final partnerName = ref.watch(partnerNameProvider).valueOrNull ?? 'Partner';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Custom questions'),
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
              'customTruthOrDareCreate',
            );
            if (needsRefresh == true) {
              ref.invalidate(myCustomTruthOrDareQuestionsProvider);
              ref.invalidate(partnerCustomTruthOrDareQuestionsProvider);
            }
          },
        ),
        body: TabBarView(
          children: [
            // My questions tab
            customQuestionsAsync.when(
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
                          'Create your own Truth or Dare questions\nfor you and your partner',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium,
                        ),
                        Gap(Spacing.lg.h),
                        AppButton(
                          label: 'Create your first question',
                          onPressed: () async {
                            final needsRefresh = await context.pushNamed(
                              'customTruthOrDareCreate',
                            );
                            if (needsRefresh == true) {
                              ref.invalidate(
                                myCustomTruthOrDareQuestionsProvider,
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
                    return CustomTruthOrDareCard(
                      question: question,
                      isOwnQuestion: true,
                      onDeleted: () {
                        ref.invalidate(myCustomTruthOrDareQuestionsProvider);
                      },
                      onPrivacyChanged: () {
                        ref.invalidate(myCustomTruthOrDareQuestionsProvider);
                        ref.invalidate(
                          partnerCustomTruthOrDareQuestionsProvider,
                        );
                      },
                      onSharedChanged: () {
                        // For future community sharing
                      },
                    );
                  },
                );
              },
            ),
            // Partner's questions tab
            ref
                .watch(partnerCustomTruthOrDareQuestionsProvider)
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
                        return CustomTruthOrDareCard(
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
                              partnerCustomTruthOrDareQuestionsProvider,
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

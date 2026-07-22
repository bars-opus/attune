// lib/features/games/this_or_that/presentation/screens/custom_question_list_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/custom_question_create_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/custom_question_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';


class CustomQuestionListScreen extends ConsumerStatefulWidget {
  const CustomQuestionListScreen({super.key});

  @override
  ConsumerState<CustomQuestionListScreen> createState() =>
      _CustomQuestionListScreenState();
}

class _CustomQuestionListScreenState
    extends ConsumerState<CustomQuestionListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(myCustomQuestionsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final customQuestionsAsync = ref.watch(myCustomQuestionsProvider);
    final partnerName = ref.watch(partnerNameProvider).valueOrNull ?? 'Partner';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Custom questions'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'My questions'),
              Tab(text: "$partnerName's questions"),
            ],
            indicatorColor: colorScheme.primary,
            labelColor: colorScheme.primary,
          ),
        ),
        floatingActionButton: AppFab(
          icon: Icons.add,
          onPressed: () async {
            final needsRefresh = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CustomQuestionCreateScreen(),
              ),
            );
            if (needsRefresh == true) {
              ref.invalidate(myCustomQuestionsProvider);
              ref.invalidate(partnerCustomQuestionsProvider);
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
                          'Create your own questions to play\nwith your partner',
                          textAlign: TextAlign.center,
                        ),
                        Gap(Spacing.lg.h),
                        AppButton(
                          label: 'Create your first question',
                          onPressed: () async {
                            final needsRefresh = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CustomQuestionCreateScreen(),
                              ),
                            );
                            if (needsRefresh == true) {
                              ref.invalidate(myCustomQuestionsProvider);
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
                    return CustomQuestionCard(
                      question: question,
                      isOwnQuestion: true,
                      onDeleted: () {
                        ref.invalidate(myCustomQuestionsProvider);
                      },
                      onPrivacyChanged: () {
                        ref.invalidate(myCustomQuestionsProvider);
                        ref.invalidate(partnerCustomQuestionsProvider);
                      },
                    );
                  },
                );
              },
            ),
            // Partner's questions tab
            ref.watch(partnerCustomQuestionsProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
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
                    return CustomQuestionCard(
                      question: question,
                      isOwnQuestion: false,
                      onReported: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Thank you for reporting. We will review it.'),
                          ),
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

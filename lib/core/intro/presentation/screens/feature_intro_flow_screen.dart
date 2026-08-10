// lib/core/intro/presentation/screens/feature_intro_flow_screen.dart

import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/documentations/user_manual/widgets/faq_widget.dart';
import 'package:attune/app/documentations/user_manual/widgets/manual_widget.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/intro/presentation/widgets/feature_intro_brief_page.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/features/onboarding/presentation/widgets/animated_stepped_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// A 3-page first-time intro (brief → documentation → FAQ) shown once
/// per feature before its real screen. Persistence (marking the intro
/// seen) is entirely the caller's responsibility via onComplete — this
/// widget is pure presentation.
class FeatureIntroFlowScreen extends StatefulWidget {
  const FeatureIntroFlowScreen({
    super.key,
    required this.module,
    required this.briefParagraph,
    required this.launchLabel,
    required this.onComplete,
  });

  final DocumentationModule module;
  final String briefParagraph;
  final String launchLabel;
  final VoidCallback onComplete;

  @override
  State<FeatureIntroFlowScreen> createState() => _FeatureIntroFlowScreenState();
}

class _FeatureIntroFlowScreenState extends State<FeatureIntroFlowScreen> {
  final _pageController = PageController();
  int _pageIndex = 0;

  static const _pageCount = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    setState(() => _pageIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: colorScheme.neutral,
        automaticallyImplyLeading: true,
        // Blank on the brief page (index 0) — that page already carries the
        // feature's name via FeatureIntroBriefPage's own "Welcome To
        // ${module.getTitle(context)}" heading, so repeating it here would
        // be redundant. Docs/FAQs instead label which of the other two
        // pages is showing, since neither carries its own heading the way
        // the brief page does.
        title: Text(
          switch (_pageIndex) {
            1 => 'Docs',
            2 => 'FAQs',
            _ => '',
          },
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: widget.onComplete,
            child: const Text('Skip intro'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.lg.w,
              Spacing.md.h,
              Spacing.lg.w,
              Spacing.md.h,
            ),
            // Same stepped progress bar the onboarding quiz uses
            // (attachment_quiz_step.dart etc., via OnboardingStepFrame) —
            // one shared "how far through this flow am I" indicator across
            // the app rather than a one-off style per feature.
            //
            // Driven off _pageIndex directly, not the PageController — this
            // flow disables swipe (NeverScrollableScrollPhysics below), so
            // the only way pages change is _goToPage's animateToPage call,
            // and controller.page only updates mid-animation. _pageIndex is
            // the value _goToPage sets synchronously via setState, so it's
            // the immediately-correct source rather than one that could lag
            // a frame behind during the page transition. 1-based fraction to
            // match how the quiz steps compute their own progressValue
            // ((questionIndex + 1) / total).
            child: AnimatedSteppedProgressBar(
              totalSegments: _pageCount,
              progressValue: (_pageIndex + 1) / _pageCount,
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              // Swipe is already disabled below, so this only changes the
              // direction animateToPage slides in — vertical instead of the
              // PageView default horizontal.
              scrollDirection: Axis.vertical,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                FeatureIntroBriefPage(
                  module: widget.module,
                  briefParagraph: widget.briefParagraph,
                ),
                Padding(
                  padding: EdgeInsets.all(Spacing.xl.w),
                  child: ManualWidget(
                    sections: widget.module.getSections(context),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(Spacing.xl.w),
                  child: FAQWidget(faqs: widget.module.getFAQs(context)),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(Spacing.lg.w),
            child: Row(
              children: [
                if (_pageIndex > 0)
                  AppIconButton(
                    iconSize: 20.h,
                    size: 30.h,
                    icon: Icons.arrow_back,
                    onPressed: () => _goToPage(_pageIndex - 1),
                  ),
                if (_pageIndex > 0) SizedBox(width: Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label:
                        _pageIndex == _pageCount - 1
                            ? widget.launchLabel
                            : 'Continue',
                    onPressed: () {
                      if (_pageIndex == _pageCount - 1) {
                        widget.onComplete();
                      } else {
                        _goToPage(_pageIndex + 1);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

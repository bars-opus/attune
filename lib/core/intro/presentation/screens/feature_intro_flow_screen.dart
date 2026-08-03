// lib/core/intro/presentation/screens/feature_intro_flow_screen.dart

import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/documentations/user_manual/widgets/faq_widget.dart';
import 'package:attune/app/documentations/user_manual/widgets/manual_widget.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/intro/presentation/widgets/feature_intro_brief_page.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
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
  State<FeatureIntroFlowScreen> createState() =>
      _FeatureIntroFlowScreenState();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.getTitle(context)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: widget.onComplete,
            child: const Text('Skip intro'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                FeatureIntroBriefPage(
                  module: widget.module,
                  briefParagraph: widget.briefParagraph,
                ),
                ManualWidget(sections: widget.module.getSections(context)),
                FAQWidget(faqs: widget.module.getFAQs(context)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(Spacing.lg.w),
            child: Row(
              children: [
                if (_pageIndex > 0)
                  Expanded(
                    child: AppButton(
                      label: 'Back',
                      variant: ButtonVariant.outline,
                      onPressed: () => _goToPage(_pageIndex - 1),
                    ),
                  ),
                if (_pageIndex > 0) SizedBox(width: Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: _pageIndex == _pageCount - 1
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

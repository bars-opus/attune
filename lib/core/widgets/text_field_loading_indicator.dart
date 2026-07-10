
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_packages.dart';
import 'package:attune/core/widgets/feedback/circular_loading_indicator.dart';
import 'package:flutter/material.dart';

class TextFieldLoadingIndicator extends StatelessWidget {
  const TextFieldLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(15.0.h),
      child:
      CircularLoadingIndicator(
         size:  Spacing.sm,
        ),
      
      
    );
  }
}

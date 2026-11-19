// Spec 2 W3c (carries 1, 13); W4b fix round 1 (M-7): a calm line, read out
// when it appears, in the theme's own colours (never error red). Busy,
// device and not-eligible answers use it across Dating.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

class DatingCalmLine extends StatelessWidget {
  const DatingCalmLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

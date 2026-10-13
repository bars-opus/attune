import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The stacked-media "2 / 5" counter, whose number rolls (so it is not one
/// Text). [text] is how it reads, e.g. '2 / 5'; null matches any counter.
Finder mediaCounter([String? text]) => find.byWidgetPredicate(
      (w) =>
          w is AnimatedRollingCounter &&
          w.suffix.startsWith(' / ') &&
          (text == null || '${w.count}${w.suffix}' == text),
      description: 'media counter ${text ?? ''}',
    );

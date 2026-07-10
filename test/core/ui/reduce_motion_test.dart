import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reduceMotionOf reflects MediaQuery.disableAnimations',
      (tester) async {
    late bool reduced;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            reduced = reduceMotionOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(reduced, isTrue);
  });
}

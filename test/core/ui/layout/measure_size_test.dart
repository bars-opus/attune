import 'package:attune/core/ui/layout/measure_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reports the laid-out size once per change', (tester) async {
    final sizes = <Size>[];
    var height = 40.0;
    late StateSetter setHeight;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHeight = setState;
            return Align(
              alignment: Alignment.bottomCenter,
              child: MeasureSize(
                onChange: sizes.add,
                child: SizedBox(width: 100, height: height),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(sizes, [const Size(100, 40)]);

    setHeight(() {});
    await tester.pump();
    await tester.pump();
    expect(sizes, hasLength(1), reason: 'same size: no second report');

    setHeight(() => height = 96);
    await tester.pump();
    await tester.pump();
    expect(sizes.last, const Size(100, 96));
    expect(sizes, hasLength(2));
  });
}

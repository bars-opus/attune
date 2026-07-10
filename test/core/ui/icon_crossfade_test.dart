// test/core/ui/icon_crossfade_test.dart
import 'package:attune/core/ui/motion/icon_crossfade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('crossfades to the new child when the keyed child changes',
      (tester) async {
    IconData icon = Icons.check;
    late StateSetter setState;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, s) {
        setState = s;
        return IconCrossfade(child: Icon(icon, key: ValueKey(icon)));
      }),
    ));
    expect(find.byIcon(Icons.check), findsOneWidget);
    setState(() => icon = Icons.done_all);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });
}

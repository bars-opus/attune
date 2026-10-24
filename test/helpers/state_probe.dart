// test/helpers/state_probe.dart
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// A screen whose State counts taps: "LABEL n". A fresh State shows 0, so a
/// test can tell a kept screen from a rebuilt one (stories Wave 3).
class StateProbe extends StatefulWidget {
  const StateProbe(this.label, {super.key});

  final String label;

  @override
  State<StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<StateProbe> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => setState(() => _taps++),
        child: Text('${widget.label} $_taps'),
      ),
    ),
  );
}

/// Every semantics label currently on screen. Call with semantics enabled
/// (`tester.ensureSemantics()`).
List<String> semanticLabels(WidgetTester tester) {
  final out = <String>[];
  void visit(SemanticsNode node) {
    out.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  return out;
}

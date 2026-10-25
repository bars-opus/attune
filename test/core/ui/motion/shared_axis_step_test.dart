// Spec 1 §2.2 (W2a): the step transition. Forward 300 ms, back 250 ms, a
// 30 dp shared-axis slide that flips right to left, and a 150 ms cross-fade
// with nothing moving when reduce motion is on.
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/shared_axis_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  String step, {
  String? label,
  bool forward = true,
  bool reduceMotion = false,
  TextDirection direction = TextDirection.ltr,
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: Directionality(
    textDirection: direction,
    child: SharedAxisStep(
      stepKey: step,
      forward: forward,
      child: Center(
        child: TextButton(onPressed: () {}, child: Text(label ?? 'step $step')),
      ),
    ),
  ),
);

double _dx(WidgetTester tester, String label) {
  final transform = tester.widget<Transform>(
    find.ancestor(of: find.text(label), matching: find.byType(Transform)).first,
  );
  return transform.transform.getTranslation().x;
}

double _opacity(WidgetTester tester, String label) {
  final fade = tester.widget<FadeTransition>(
    find
        .ancestor(of: find.text(label), matching: find.byType(FadeTransition))
        .first,
  );
  return fade.opacity.value;
}

bool _ignored(WidgetTester tester, String label) => tester
    .widgetList<IgnorePointer>(
      find.ancestor(of: find.text(label), matching: find.byType(IgnorePointer)),
    )
    .any((w) => w.ignoring);

/// A step with state of its own: it logs each initState, and its field
/// (autofocused, like A1–A4's) keeps what was typed.
class _FieldStep extends StatefulWidget {
  const _FieldStep(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  State<_FieldStep> createState() => _FieldStepState();
}

class _FieldStepState extends State<_FieldStep> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.log.add(widget.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextField(
      key: ValueKey('field ${widget.name}'),
      controller: _controller,
      autofocus: true,
    ),
  );
}

Future<ValueNotifier<String>> _pumpFieldSteps(
  WidgetTester tester,
  List<String> log,
) async {
  final step = ValueNotifier('a');
  addTearDown(step.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<String>(
          valueListenable: step,
          builder:
              (_, name, __) =>
                  SharedAxisStep(stepKey: name, child: _FieldStep(name, log)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return step;
}

FocusNode _focusOf(WidgetTester tester, String name) =>
    tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(ValueKey('field $name')),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode;

void main() {
  testWidgets(
    'forward: the new step slides in from 30 dp and owns the screen at 300 ms',
    (tester) async {
      await tester.pumpWidget(_host('a'));
      await tester.pumpWidget(_host('b'));
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('step a'), findsOneWidget);
      expect(find.text('step b'), findsOneWidget);
      expect(_dx(tester, 'step b'), closeTo(kSharedAxisOffset, 0.5));
      expect(_dx(tester, 'step a'), closeTo(0, 0.5));

      await tester.pump(kStepForwardDuration - const Duration(milliseconds: 2));
      expect(find.text('step a'), findsOneWidget, reason: 'still leaving');
      await tester.pump(const Duration(milliseconds: 2));
      expect(find.text('step a'), findsNothing);
      expect(_dx(tester, 'step b'), 0);
    },
  );

  testWidgets('back: 250 ms, and the slide comes from the other side', (
    tester,
  ) async {
    await tester.pumpWidget(_host('b'));
    await tester.pumpWidget(_host('a', forward: false));
    await tester.pump(const Duration(milliseconds: 1));
    expect(_dx(tester, 'step a'), closeTo(-kSharedAxisOffset, 0.5));

    await tester.pump(kStepBackDuration);
    expect(find.text('step b'), findsNothing);
  });

  testWidgets('right to left reverses the forward slide', (tester) async {
    await tester.pumpWidget(_host('a', direction: TextDirection.rtl));
    await tester.pumpWidget(_host('b', direction: TextDirection.rtl));
    await tester.pump(const Duration(milliseconds: 1));
    expect(_dx(tester, 'step b'), closeTo(-kSharedAxisOffset, 0.5));
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion: a 150 ms cross-fade, nothing moves', (
    tester,
  ) async {
    await tester.pumpWidget(_host('a', reduceMotion: true));
    await tester.pumpWidget(_host('b', reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 1));
    expect(_dx(tester, 'step b'), 0);
    expect(_dx(tester, 'step a'), 0);

    await tester.pump(kReducedMotionFade);
    expect(find.text('step a'), findsNothing);
  });

  testWidgets('reduce motion from the platform: the cross-fade still takes '
      '150 ms (review B2 M-2)', (tester) async {
    // The platform switch that reduceMotionOf reads also runs animations 20
    // times faster unless the controller preserves its duration.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_host('a', reduceMotion: true));
    await tester.pumpWidget(_host('b', reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 75));
    expect(_opacity(tester, 'step b'), inExclusiveRange(0.3, 0.7));
    expect(find.text('step a'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('step a'), findsNothing);
    expect(_opacity(tester, 'step b'), 1);
  });

  testWidgets('the leaving step takes no taps and is not read out', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host('a'));
    await tester.pumpWidget(_host('b'));
    // 30 ms: the leaving step is still visible, so only its exclusion keeps
    // it out of the live semantics tree (its render objects still hold
    // their old, detached nodes, which bySemanticsLabel would find).
    await tester.pump(const Duration(milliseconds: 30));
    expect(_opacity(tester, 'step a'), greaterThan(0));
    expect(find.semantics.byLabel('step a'), findsNothing);

    await tester.pump(const Duration(milliseconds: 70));
    expect(find.semantics.byLabel('step a'), findsNothing);
    expect(find.semantics.byLabel('step b'), findsOne);
    expect(_ignored(tester, 'step a'), isTrue);
    expect(_ignored(tester, 'step b'), isFalse);
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('the same step with new content rebuilds in place', (
    tester,
  ) async {
    await tester.pumpWidget(_host('a'));
    await tester.pumpWidget(_host('a', label: 'step a, edited'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('step a'), findsNothing);
    expect(find.text('step a, edited'), findsOneWidget);
    expect(_dx(tester, 'step a, edited'), 0);
    expect(_opacity(tester, 'step a, edited'), 1);
  });

  testWidgets(
    'a step keeps its state while it leaves: no rebuild from scratch (review I-2)',
    (tester) async {
      final log = <String>[];
      final step = await _pumpFieldSteps(tester, log);
      await tester.enterText(find.byKey(const ValueKey('field a')), 'Ama');

      step.value = 'b';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(log, ['a', 'b']);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('field a')))
            .controller!
            .text,
        'Ama',
        reason: 'what was typed stays while the step slides out',
      );

      await tester.pumpAndSettle();
      expect(log, ['a', 'b']);
    },
  );

  testWidgets('focus leaves with the old step and lands in the new one', (
    tester,
  ) async {
    final step = await _pumpFieldSteps(tester, <String>[]);
    expect(_focusOf(tester, 'a').hasPrimaryFocus, isTrue);

    step.value = 'b';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_focusOf(tester, 'a').hasFocus, isFalse);
    // Not even a late request from the leaving step itself takes it back.
    _focusOf(tester, 'a').requestFocus();
    await tester.pump();
    expect(_focusOf(tester, 'a').hasFocus, isFalse);

    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, _focusOf(tester, 'b'));
  });

  testWidgets('going straight back takes the focus back to that step', (
    tester,
  ) async {
    final log = <String>[];
    final step = await _pumpFieldSteps(tester, log);
    step.value = 'b';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    step.value = 'a';
    await tester.pumpAndSettle();

    expect(log, ['a', 'b'], reason: 'a came back as it was');
    expect(FocusManager.instance.primaryFocus, _focusOf(tester, 'a'));
  });

  testWidgets(
    'a new step mid-transition keeps the slide going, no jump cut (review M-6)',
    (tester) async {
      await tester.pumpWidget(_host('a'));
      await tester.pumpWidget(_host('b'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(_host('c'));
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('step b'), findsOneWidget, reason: 'b is still leaving');
      expect(find.text('step a'), findsNothing);
      expect(_opacity(tester, 'step c'), lessThan(1));

      await tester.pumpAndSettle();
      expect(find.text('step b'), findsNothing);
      expect(_opacity(tester, 'step c'), 1);
    },
  );
}

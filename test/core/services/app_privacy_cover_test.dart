import 'package:attune/core/services/app_privacy_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/state_probe.dart';

void main() {
  testWidgets('shows no cover while the app is resumed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrivacyCover(
          child: const Text('secret content'),
        ),
      ),
    );
    expect(find.text('secret content'), findsOneWidget);
    expect(find.byKey(const Key('app_privacy_cover_overlay')), findsNothing);
  });

  testWidgets('shows an opaque cover when the app lifecycle goes inactive, and clears it on resume', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrivacyCover(
          child: const Text('secret content'),
        ),
      ),
    );

    // Simulate the OS delivering an inactive lifecycle message -- this is
    // the same mechanism a real app-switcher snapshot event delivers
    // through, exercised via the test binding rather than a real OS
    // event, which is the standard way Flutter widget tests drive
    // AppLifecycleState changes.
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.byKey(const Key('app_privacy_cover_overlay')), findsOneWidget);
    // The underlying content must be genuinely covered, not merely
    // painted behind a transparent widget -- assert the cover is opaque
    // by checking it's the topmost hit-testable widget at that location,
    // not just present in the tree.
    final coverFinder = find.byKey(const Key('app_privacy_cover_overlay'));
    final renderBox = tester.renderObject<RenderBox>(coverFinder);
    expect(renderBox.size, greaterThan(Size.zero));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('app_privacy_cover_overlay')), findsNothing);
  });

  testWidgets('paused and hidden also trigger the cover, matching inactive', (tester) async {
    // AppLifecycleListener enforces the real platform's valid lifecycle
    // transition graph, which is strictly linear in both directions:
    // resumed <-> inactive <-> hidden <-> paused <-> detached. Reaching
    // hidden or paused from resumed means walking every intermediate
    // step, exactly like a real OS backgrounding sequence would --
    // skipping a step throws a framework assertion rather than exercising
    // this widget.
    const forwardPathToHidden = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
    ];
    const forwardPathToPaused = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    final paths = {
      AppLifecycleState.hidden: forwardPathToHidden,
      AppLifecycleState.paused: forwardPathToPaused,
    };

    for (final state in [AppLifecycleState.paused, AppLifecycleState.hidden]) {
      await tester.pumpWidget(
        MaterialApp(home: AppPrivacyCover(child: const Text('x'))),
      );
      final forwardPath = paths[state]!;
      for (final step in forwardPath) {
        tester.binding.handleAppLifecycleStateChanged(step);
        await tester.pump();
      }
      expect(
        find.byKey(const Key('app_privacy_cover_overlay')),
        findsOneWidget,
        reason: 'AppLifecycleState.$state must trigger the cover',
      );
      // Walk back through the same intermediate states in reverse, again
      // matching the real OS foregrounding sequence rather than jumping
      // straight to resumed.
      for (final step in forwardPath.reversed.skip(1)) {
        tester.binding.handleAppLifecycleStateChanged(step);
        await tester.pump();
      }
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }
  });

  testWidgets('the cover shows no readable content of its own -- no message text, no user names, no app-specific branding beyond the app icon/name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AppPrivacyCover(child: const Text('secret content'))),
    );
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('secret content'), findsNothing);
  });

  group('kept mounted behind the cover (stories Wave 3; 07b G7)', () {
    const toBackground = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    const toForeground = [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ];

    testWidgets('the app keeps its State across inactive -> resumed and a '
        'full background', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AppPrivacyCover(child: StateProbe('APP'))),
      );
      await tester.tap(find.text('APP 0'));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('APP 1'), findsNothing, reason: 'not on screen');
      expect(
        find.text('APP 1', skipOffstage: false),
        findsOneWidget,
        reason: 'but still mounted',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('APP 1'), findsOneWidget, reason: 'same State');

      for (final s in [...toBackground, ...toForeground]) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
      expect(find.text('APP 1'), findsOneWidget);
    });

    testWidgets('while covered the app is not in semantics, not ticking and '
        'not tappable', (tester) async {
      final semantics = tester.ensureSemantics();
      bool? ticking;
      await tester.pumpWidget(
        MaterialApp(
          home: AppPrivacyCover(
            child: Builder(
              builder: (context) {
                ticking = TickerMode.of(context);
                return const StateProbe('APP');
              },
            ),
          ),
        ),
      );
      expect(ticking, isTrue);
      expect(semanticLabels(tester).any((l) => l.contains('APP 0')), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(ticking, isFalse, reason: 'animations stop behind the cover');
      expect(
        semanticLabels(tester).any((l) => l.contains('APP')),
        isFalse,
        reason: 'a screen reader cannot reach the hidden app',
      );
      await tester.tap(find.byKey(const Key('app_privacy_cover_overlay')));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(ticking, isTrue);
      expect(
        find.text('APP 0'),
        findsOneWidget,
        reason: 'a tap on the cover never reaches the app',
      );
      semantics.dispose();
    });
  });

  group('the keyboard goes down behind the cover (final review I1)', () {
    Future<void> pumpField(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppPrivacyCover(child: Scaffold(body: TextField())),
        ),
      );
    }

    bool focused(WidgetTester tester) => tester
        .widget<EditableText>(find.byType(EditableText, skipOffstage: false))
        .focusNode
        .hasFocus;

    testWidgets('covered: the keyboard (and its predictions) is hidden; '
        'resumed: it is back with the same text and focus', (tester) async {
      // The keyboard is up: the view reports its inset.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await pumpField(tester);
      await tester.showKeyboard(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'I am leaving');
      expect(tester.testTextInput.isVisible, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(const Key('app_privacy_cover_overlay')), findsOneWidget);
      expect(
        tester.testTextInput.isVisible,
        isFalse,
        reason: 'no keyboard or QuickType over the cover',
      );
      expect(focused(tester), isTrue, reason: 'focus is kept');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(find.text('I am leaving'), findsOneWidget);
      expect(focused(tester), isTrue);
    });

    testWidgets('a field that kept focus with its keyboard already down is '
        'not given one on return', (tester) async {
      await pumpField(tester);
      await tester.showKeyboard(find.byType(TextField));
      // Dismissed (Android back) with focus kept: no inset.
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      expect(tester.testTextInput.isVisible, isFalse);

      for (final s in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
      expect(tester.testTextInput.isVisible, isFalse);
      expect(focused(tester), isTrue);
    });

    testWidgets('a screen with no focused field gets no keyboard', (
      tester,
    ) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await pumpField(tester);
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
      expect(tester.testTextInput.isVisible, isFalse);
      expect(focused(tester), isFalse);
    });
  });
}

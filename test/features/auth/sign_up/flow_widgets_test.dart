// Spec 1 W2a (§2.3; rulings C5, C6): the shared pieces later screens reuse.
// The one error line every sign-in screen shows (an icon and the message at
// full contrast, never colour alone), the field's label colours, the primary
// button's busy state, and the read-only Terms and Privacy sheets that
// Welcome and consent link to.
import 'dart:math' as math;

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_text_button.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

Widget _host(Widget child, {ThemeData? theme}) =>
    MaterialApp(theme: theme, home: Scaffold(body: child));

/// WCAG contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The colour the field's label is actually painted in.
Color _labelColor(WidgetTester tester, String label) =>
    tester.renderObject<RenderParagraph>(find.text(label)).text.style!.color!;

void main() {
  for (final (name, open, title) in [
    ('Terms', showTermsSheet, 'Terms of Service'),
    ('Privacy', showPrivacySheet, 'Privacy Policy'),
  ]) {
    testWidgets('the $name link opens its document, with nothing to agree to', (
      tester,
    ) async {
      await pumpFlowScreen(
        tester,
        () => Scaffold(
          body: Builder(
            builder:
                (context) =>
                    FlowTextLink(label: name, onPressed: () => open(context)),
          ),
        ),
      );
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      // The sheet shows its plain close button only when showButtons is
      // false (legal_documentation_modal_sheet.dart).
      expect(find.byType(AppTextButton), findsOneWidget);
      expect(find.text('I Agree'), findsNothing);
      expect(find.text('Decline'), findsNothing);
    });
  }

  testWidgets('FlowTextField shows its error as an icon and the message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FlowTextField(
          controller: TextEditingController(),
          label: 'Year',
          errorText: 'Check the year.',
        ),
      ),
    );
    final theme = Theme.of(tester.element(find.byType(FlowErrorLine)));
    expect(find.byType(FlowErrorLine), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
      theme.colorScheme.error,
    );
    expect(
      tester.widget<Text>(find.text('Check the year.')).style?.color,
      theme.colorScheme.onSurface,
    );
  });

  testWidgets('a live error line is read out; a given style is kept', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const style = TextStyle(fontSize: 17, color: Color(0xFF101010));
    await tester.pumpWidget(
      _host(
        const FlowErrorLine(
          text: 'The code has expired.',
          style: style,
          liveRegion: true,
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('The code has expired.')).style,
      style,
    );
    final node = tester.getSemantics(
      find.bySemanticsLabel('The code has expired.'),
    );
    expect(node.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    semantics.dispose();
  });

  testWidgets(
    'G1\'s label reads at 4.5:1 focused and after an error (review I-1)',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => GuestAgeGateScreen(now: () => DateTime.utc(2026, 10, 25, 12)),
      );
      final context = tester.element(find.byType(FlowTextField));
      final colorScheme = Theme.of(context).colorScheme;

      // G1 opens with the field focused.
      expect(_labelColor(tester, 'Year'), flowAccent(context));
      expect(
        _contrast(_labelColor(tester, 'Year'), colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );

      await tester.enterText(find.byType(TextField), '94');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(_labelColor(tester, 'Year'), colorScheme.onSurface);
      expect(
        _contrast(_labelColor(tester, 'Year'), colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  for (final (mode, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('$mode: every label state reads at 4.5:1 (review I-1)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          theme: theme,
          Column(
            children: [
              FlowTextField(
                controller: TextEditingController(),
                label: 'Focused',
                autofocus: true,
              ),
              FlowTextField(
                controller: TextEditingController(text: '94'),
                label: 'In error',
                errorText: 'Enter the year with 4 digits, like 1994.',
              ),
              FlowTextField(
                controller: TextEditingController(text: '1994'),
                label: 'Resting',
              ),
              FlowTextField(
                controller: TextEditingController(),
                label: 'Empty',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Column));
      final colorScheme = Theme.of(context).colorScheme;

      for (final (label, expected) in [
        ('Focused', flowAccent(context)),
        ('In error', colorScheme.onSurface),
        ('Resting', colorScheme.onSurfaceVariant),
        ('Empty', colorScheme.onSurfaceVariant),
      ]) {
        final color = _labelColor(tester, label);
        expect(color, expected, reason: '$mode $label');
        expect(
          _contrast(color, colorScheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$mode $label',
        );
      }
    });
  }

  testWidgets('the field keeps the theme\'s 12 dp corners when focused', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(FlowTextField(controller: TextEditingController(), label: 'Year')),
    );
    final decoration =
        tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
    for (final border in [decoration.border, decoration.focusedBorder]) {
      expect(
        (border! as OutlineInputBorder).borderRadius,
        BorderRadiusTokens.mdAll,
      );
    }
  });

  testWidgets(
    'busy: the button stops taking taps at once; the ring only after 400 ms',
    (tester) async {
      final busy = ValueNotifier(false);
      addTearDown(busy.dispose);
      var taps = 0;
      await pumpFlowScreen(
        tester,
        () => Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: busy,
            builder:
                (_, value, __) => FlowPrimaryButton(
                  label: 'Continue',
                  busy: value,
                  onPressed: () => taps++,
                ),
          ),
        ),
      );

      busy.value = true;
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isFalse,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(taps, 0);

      await tester.pump(const Duration(milliseconds: 399));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      busy.value = false;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isTrue,
      );
    },
  );
}

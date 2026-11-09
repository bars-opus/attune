// Spec 2 W3 final fix (client M-12, required): on a shared phone the
// keyboard must not learn identity terms, prompts, captions or a first
// name and offer them to the next person. Every Dating free-text field
// turns off suggestions, autocorrect and personalised learning. The scan
// pins every TextField under lib/features/dating (a new one fails until it
// has the three flags); the widget checks read what D5 and the picker
// build. Caption, prompts, first name and the gentle-wait answers are
// checked where their own tests open them (d9_d10, d11_d13, gentle_wait).
import 'dart:io';

import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_picker_sheet.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/you_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_private_keyboard.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

/// The argument list of each `TextField(` in [src], parentheses balanced.
Iterable<String> _textFields(String src) sync* {
  for (final m in RegExp(r'\bTextField\(').allMatches(src)) {
    var depth = 0;
    for (var i = m.end - 1; i < src.length; i++) {
      final c = src[i];
      if (c == '(') depth++;
      if (c == ')' && --depth == 0) {
        yield src.substring(m.start, i + 1);
        break;
      }
    }
  }
}

void main() {
  test('every Dating TextField turns off suggestions, autocorrect and '
      'personalised learning', () {
    var seen = 0;
    for (final f in Directory('lib/features/dating')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final field in _textFields(f.readAsStringSync())) {
        seen++;
        for (final flag in const [
          'enableSuggestions: false',
          'autocorrect: false',
          'enableIMEPersonalizedLearning: false',
        ]) {
          expect(field, contains(flag), reason: '${f.path}: $field');
        }
      }
    }
    // D5 own words and pronouns, prompts, caption, first name, the picker's
    // search and the gentle-wait answers.
    expect(seen, greaterThanOrEqualTo(7));
  });

  testWidgets('D5 on-country: own words and pronouns', (t) async {
    final setup = FakeDatingSetupGateway(
      profile: const DatingMyProfile(countryCode: 'GB', regionCode: 'TLI'),
    );
    await pumpFlowScreen(
      t,
      () => DatingYouStep(
        nav: DatingStepNav(next: (_) {}, back: () {}, toMe: () {}),
      ),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(setup),
      ],
    );
    await t.pumpAndSettle();
    expectPrivateKeyboard(t, find.byKey(const ValueKey('dating_pronouns')));
    await tapInReach(t, find.text('Add something more specific'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('In my own words'));
    await t.pumpAndSettle();
    expectPrivateKeyboard(t, find.byKey(const ValueKey('dating_ownWords')));
  });

  testWidgets("the picker's search", (t) async {
    await pumpFlowScreen(
      t,
      () => Builder(
        builder:
            (context) => TextButton(
              onPressed:
                  () => showDatingPicker<String>(
                    context,
                    title: 'Faith',
                    items: [for (var i = 0; i < 8; i++) ('f$i', 'Faith $i')],
                  ),
              child: const Text('Open'),
            ),
      ),
      overrides: datingShellOverrides(),
    );
    await tapInReach(t, find.text('Open'));
    await t.pumpAndSettle();
    expectPrivateKeyboard(t, find.byType(TextField));
  });
}

// Spec 1 W4b (§2.3; carried from W3 P-30 and the batch-3 report): the
// shared InviteCard (R1, R3, the couples waiting step, the Chat locked
// screen) meets the tap-target, label and contrast guidelines; its code is
// one labelled item; its words are unchanged.
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

final _invite = RelationshipInvite(
  relationshipId: 'r1',
  code: 'K7P2QM',
  expiresAt: DateTime.utc(2026, 11, 9),
);

// Preflight F-7: inside AllowLargeText, as R3 and FlowFrame show it, so
// the 2.0 case really runs at 2.0 (the harness clamps every route to 1.0).
Widget _card() => Scaffold(
  body: AllowLargeText(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: InviteCard(invite: _invite),
    ),
  ),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('meets the guidelines at $scale', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFlowScreen(
        tester,
        _card,
        textScale: scale,
        size: const Size(390, 1400),
      );
      await expectFlowGuidelines(tester);
      semantics.dispose();
    });
  }

  testWidgets('the code is one labelled item; the words are today\'s', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(tester, _card, size: const Size(390, 1400));
    expect(find.bySemanticsLabel('Invite code K 7 P 2 Q M'), findsOneWidget);
    expect(find.text('Partner invite'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    // Final review #4: the code is selectable again (one item, the
    // spelled label), the link stays plain text.
    expect(find.byType(SelectableText), findsOneWidget);
    for (final label in ['Share', 'Copy link']) {
      final size = tester.getSize(
        find
            .ancestor(of: find.text(label), matching: find.byType(SizedBox))
            .first,
      );
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
    }
    semantics.dispose();
  });

  // Final review #4: P-8 had made the code plain text; a long-press copies
  // it again, with the platform's own Copy (no new words).
  testWidgets('a long-press on the code copies it', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') return {'text': copied};
        if (call.method == 'Clipboard.hasStrings') {
          return {'value': copied != null};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpFlowScreen(tester, _card, size: const Size(390, 1400));
    await tester.longPress(find.text('K7P2QM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'K7P2QM');
  });
}

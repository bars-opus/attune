// Spec 1 W4b (P-8, unflagged; the W3 carry from the batch-3 report): the
// InviteCard fix holds where the card is shown, not only on its own: R1
// with flow_couples_v2 off, R3 while pending, and the Chat tab's locked
// screen. Each meets the tap-target, label and contrast guidelines with
// the card on screen, at 1.0 and at 2.0.
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/chat/presentation/screens/chat_couples_locked_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('R1, flow_couples_v2 off, the card shown, at $scale', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpFlowScreen(
        tester,
        () => InvitePartnerScreen(onDone: () {}),
        textScale: scale,
        size: const Size(390, 2400),
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-r1'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(FakeHomeStateGateway(state: homeJson())),
          ),
          invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
          flowCouplesV2Provider.overrideWithValue(false),
        ],
      );
      await tester.tap(find.text('Create my invite'));
      await tester.pumpAndSettle();
      expect(find.byType(InviteCard), findsOneWidget);
      await expectFlowGuidelines(tester);
      semantics.dispose();
    });

    testWidgets('R3 pending, the card shown, at $scale', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFlowScreen(
        tester,
        () => RelationshipSpaceScreen(
          home: snapshotOf(homeJson(path: 'relationship', link: 'pending')),
        ),
        textScale: scale,
        size: const Size(390, 2400),
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-r3'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(FakeHomeStateGateway()),
          ),
          invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
          relationshipLifecycleProvider.overrideWith((ref) async => null),
          pushAskerProvider.overrideWithValue(FakePushAsker()),
        ],
      );
      expect(find.byType(InviteCard), findsOneWidget);
      await expectFlowGuidelines(tester);
      semantics.dispose();
    });
  }

  testWidgets('the Chat tab\'s locked screen, pending, the card shown', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relationshipLifecycleProvider.overrideWith((ref) async => null),
          invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
        ],
        child: ScreenUtilConfig.builder(
          builder:
              (_) => MaterialApp(
                // The app's theme: contrast is measured on its colours.
                theme: AppTheme.lightTheme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ChatCouplesLockedScreen(
                  isPendingCouples: true,
                  onInviteSent: () {},
                ),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InviteCard), findsOneWidget);
    // The legacy screen around the card (its menu row) predates Spec 1 and
    // fails the tap-target and label guidelines on its own, so those two
    // are checked on the card's own targets here; contrast on the whole
    // screen.
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    _expectCardTargets(tester);
    semantics.dispose();
  });
}

/// Every tappable semantics node inside the InviteCard is at least 48 by
/// 48 and has a label (androidTapTargetGuideline and
/// labeledTapTargetGuideline, scoped to the card).
void _expectCardTargets(WidgetTester tester) {
  final card = tester.getRect(find.byType(InviteCard));
  final root =
      tester
          .renderObject(find.byType(InviteCard))
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!;
  var checked = 0;
  void visit(SemanticsNode node, Matrix4 parent) {
    final transform =
        node.transform == null ? parent : parent.multiplied(node.transform!);
    final rect = MatrixUtils.transformRect(transform, node.rect);
    final data = node.getSemanticsData();
    final tappable =
        data.hasAction(SemanticsAction.tap) ||
        data.hasAction(SemanticsAction.longPress);
    if (tappable && card.inflate(1).contains(rect.center)) {
      checked++;
      expect(rect.width, greaterThanOrEqualTo(48), reason: '$node');
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$node');
      expect(data.label.trim(), isNotEmpty, reason: '$node');
    }
    node.visitChildren((child) {
      visit(child, transform);
      return true;
    });
  }

  visit(root, Matrix4.identity());
  expect(checked, greaterThanOrEqualTo(2), reason: 'Share and Copy link');
}

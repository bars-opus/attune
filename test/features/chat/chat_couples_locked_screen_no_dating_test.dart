// Spec 1 W3b (§3.8 R3, §5.6 R17, review R-5): the legacy Chat-tab screen
// (what flow_paths_v2 off shows) never offers Dating, pending or not; the
// invite area and the Healing entry around the removed button stay.
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/chat/presentation/screens/chat_couples_locked_screen.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, {required bool pending}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        relationshipLifecycleProvider.overrideWith((ref) async => null),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ChatCouplesLockedScreen(
                isPendingCouples: pending,
                onInviteSent: () {},
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final pending in [false, true]) {
    testWidgets('pending: $pending: no way into Dating', (tester) async {
      await _pump(tester, pending: pending);
      await tester.scrollUntilVisible(
        find.text('Personal reflections'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Meet someone in Dating mode', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.textContaining(
          RegExp('dating', caseSensitive: false),
          skipOffstage: false,
        ),
        findsNothing,
      );
    });
  }

  testWidgets('the invite area and Healing stay', (tester) async {
    await _pump(tester, pending: false);
    // No Supabase in a test: the invite button's place says so.
    expect(
      find.text(
        'Invites are unavailable right now. Please try again later.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Healing from a breakup?'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Healing from a breakup?'), findsOneWidget);
  });
}

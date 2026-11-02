// Spec 1 W3a (B3 review #8): /invite-partner is for a signed-in account; a
// signed-out visit goes to sign-in instead of a button that does nothing.
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_invites.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

Future<String> _visit(WidgetTester tester, {required bool signedIn}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A set-up account, so the boot settles on home before the visit.
  SharedPreferences.setMockInitialValues({
    'attune.onboarding.user.u-route.completed': true,
  });
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final notifier = RoutingNotifier(
    prefs: prefs,
    flowV2: true,
    currentUserId: () => signedIn ? 'u-route' : null,
  );
  final router = createAppRouter(notifier);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routingNotifierProvider.overrideWith((ref) => notifier),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(),
        ),
        homeAuthProvider.overrideWithValue(
          FakeHomeAuth(signedIn ? testUser('u-route') : null),
        ),
        invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  router.go(RouteNames.invitePartner);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return router.routerDelegate.currentConfiguration.uri.path;
}

void main() {
  testWidgets('signed out: /invite-partner goes to sign-in', (tester) async {
    final at = await _visit(tester, signedIn: false);
    expect(at, isNot(RouteNames.invitePartner));
    expect(find.byType(InvitePartnerScreen), findsNothing);
  });

  testWidgets('signed in: /invite-partner opens R1', (tester) async {
    final at = await _visit(tester, signedIn: true);
    expect(at, RouteNames.invitePartner);
    expect(find.byType(InvitePartnerScreen), findsOneWidget);
  });
}

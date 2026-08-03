import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/chat/presentation/screens/chat_couples_locked_screen.dart';
import 'package:attune/features/healing/data/repositories/healing_repository.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Fake repository so `hasActiveSoloHealingJourneyProvider` (which reads
/// `healingRepositoryProvider`) resolves without touching Supabase. Only
/// `hasActiveSoloJourney` is exercised by this screen's tap handler.
class _FakeHealingRepository implements HealingRepository {
  _FakeHealingRepository({required bool hasActiveSoloJourney})
      : _hasActiveSoloJourney = hasActiveSoloJourney;

  final bool _hasActiveSoloJourney;

  @override
  Future<bool> hasActiveSoloJourney() async => _hasActiveSoloJourney;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp({required bool hasActiveSoloJourney}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder:
            (context, state) => ChatCouplesLockedScreen(
              isPendingCouples: false,
              onInviteSent: () {},
            ),
      ),
      GoRoute(
        path: RouteNames.healingJourney,
        name: 'healingJourney',
        builder: (context, state) => const Scaffold(body: Text('Healing journey stub')),
      ),
      GoRoute(
        path: RouteNames.reflectionJournal,
        name: 'reflectionJournal',
        builder: (context, state) => const Scaffold(body: Text('Reflection stub')),
      ),
      GoRoute(
        path: RouteNames.datingMode,
        builder: (context, state) => const Scaffold(body: Text('Dating stub')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      healingRepositoryProvider.overrideWithValue(
        _FakeHealingRepository(hasActiveSoloJourney: hasActiveSoloJourney),
      ),
    ],
    child: ScreenUtilConfig.builder(
      builder:
          (_) => MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
    ),
  );
}

void main() {
  testWidgets('shows healing entry card when there is no invite', (tester) async {
    await tester.pumpWidget(_buildTestApp(hasActiveSoloJourney: false));
    await tester.pumpAndSettle();

    expect(find.text('Healing from a breakup?'), findsOneWidget);
  });

  testWidgets(
    'tapping the card with an existing solo journey navigates directly, no sheet',
    (tester) async {
      await tester.pumpWidget(_buildTestApp(hasActiveSoloJourney: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Healing from a breakup?'));
      await tester.pumpAndSettle();

      expect(find.text('When did this happen?'), findsNothing);
      expect(find.text('Healing journey stub'), findsOneWidget);
    },
  );
}

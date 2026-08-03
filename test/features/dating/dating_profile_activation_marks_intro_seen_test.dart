import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/intro/data/seen_feature_intro_store.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/dating/data/models/dating_enrollment.dart';
import 'package:attune/features/dating/data/repositories/dating_repository.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:attune/features/dating/presentation/screens/dating_profile_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake repository so the profile screen's save/activate calls resolve
/// without touching Supabase. Only the methods this screen exercises are
/// implemented; everything else falls through to noSuchMethod.
class _FakeDatingRepository implements DatingRepository {
  @override
  Future<Map<String, dynamic>?> getProfile() async => null;

  @override
  Future<Map<String, dynamic>> saveProfile({
    required String displayName,
    required String cityRegionCode,
    required String relationshipIntention,
    required int minAge,
    required int maxAge,
    String? bio,
  }) async {
    return {
      'display_name': displayName,
      'city_region_code': cityRegionCode,
      'relationship_intention': relationshipIntention,
      'min_age': minAge,
      'max_age': maxAge,
      'bio': bio,
      'moderation_state': 'approved',
    };
  }

  @override
  Future<DatingEnrollment> activateProfile() async {
    final now = DateTime.now();
    return DatingEnrollment(
      userId: 'test-user',
      state: 'active',
      createdAt: now,
      updatedAt: now,
      activatedAt: now,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const DatingProfileScreen(),
      ),
      GoRoute(
        path: RouteNames.datingMode,
        name: 'datingMode',
        builder: (context, state) => const Scaffold(body: Text('Dating dashboard stub')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      datingRepositoryProvider.overrideWithValue(_FakeDatingRepository()),
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'activating a dating profile marks the Dating Mode intro as seen before navigating',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = SeenFeatureIntroStore(prefs);
      expect(store.hasSeenIntro('datingMode'), isFalse);

      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Ama');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Select your city or region'));
      await tester.tap(
        find.text('Select your city or region'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accra').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Select your intention'));
      await tester.tap(
        find.text('Select your intention'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intentional dating').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Activate profile'));
      await tester.tap(find.text('Activate profile'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Dating dashboard stub'), findsOneWidget);
      expect(store.hasSeenIntro('datingMode'), isTrue);
    },
  );
}

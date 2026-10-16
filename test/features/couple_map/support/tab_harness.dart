// Shared map-tab harness (couple_map_tab_test + accessibility_test).
import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/couple_map/presentation/screens/couple_map_tab.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../location/presence_repository_test.dart'
    show FakePresenceGateway, FakeSampler;
import '../../stories/support/fake_story_read_gateway.dart';
import 'fakes.dart';

class NoReminders extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => const [];
}

const selfRow = {
  'who': 'self',
  'cell_lat': 5.565,
  'cell_lng': -0.208,
  'city': 'Accra',
  'freshness': 'fresh',
};
Map<String, Object?> partnerRow({String freshness = 'fresh'}) => {
  'who': 'partner',
  'cell_lat': 51.505,
  'cell_lng': -0.121,
  'city': 'London',
  'utc_offset_minutes': 60,
  'freshness': freshness,
  'distance_km': 5100,
  'together': false,
};

class TabHarness {
  TabHarness(this.rows);
  List<Map<String, Object?>> rows;
  late final gateway = FakePresenceGateway({
    'couple_map_presence': (_) => rows,
  });
  final sampler = FakeSampler(
    next: const PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40),
  );
  final view = FakeCoupleMapView();
  final pins = FakePinImageRenderer();
  String token = 'pk.test';
  ThemeMode themeMode = ThemeMode.light;
  bool reduceMotion = false;
  List<Map<String, Object?>> places = const [];
  late final placesGateway = FakeStoryPlacesGateway({
    'list_story_places': (_) => places,
  });
  final local = MemoryCoupleMapLocalStore();
  final reads = FakeStoryReadGateway();

  /// Re-pumps after changing a field (theme, motion) on the same harness.
  Future<void> repump(WidgetTester t) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
  }

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
  }

  Widget app() => ProviderScope(
    overrides: [
      presenceGatewayProvider.overrideWithValue(gateway),
      presenceSamplerProvider.overrideWithValue(sampler),
      presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
      coupleMapViewBuilderProvider.overrideWithValue(view.builder),
      coupleMapTokenProvider.overrideWithValue(token),
      pinImageRendererProvider.overrideWithValue(pins),
      coupleMapPeopleProvider.overrideWith(
        (ref, rel) async => const CoupleMapPeople(
          selfInitials: 'AM',
          partnerInitials: 'K',
          partnerName: 'Kofi',
        ),
      ),
      remindersListProvider.overrideWith(NoReminders.new),
      storyPlacesGatewayProvider.overrideWithValue(placesGateway),
      storyChangeSignalProvider.overrideWith(
        (ref, rel) => const Stream<void>.empty(),
      ),
      coupleMapLocalStoreProvider.overrideWithValue(local),
      currentUserProvider.overrideWithValue(
        const User(
          id: 'ama',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01',
        ),
      ),
      storyReadGatewayProvider.overrideWithValue(reads),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, __) => MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: themeMode,
            home: MediaQuery(
              data: MediaQueryData(
                disableAnimations: reduceMotion,
                size: const Size(390, 844),
              ),
              child: const Scaffold(body: CoupleMapTab(relationshipId: 'r1')),
            ),
          ),
    ),
  );
}

import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/app/app.dart' show appLocalizationsDelegates;
import 'package:attune/features/planning/data/planning_repository.dart';
import 'package:attune/features/planning/domain/planning_outbox.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline_providers;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/support/chat_test_harness.dart' show withScreenUtil;
import 'fake_planning_gateway.dart';

class _FakeRemindersListNotifier extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => const [];
}

List<Override> planningOverrides(
  FakePlanningGateway gateway, {
  MemoryOutboxStore? store,
  String userId = 'u-a',
  FakePlanningMediaGateway? media,
  PartnerDistance? partner,
  String? deviceTimezone,
  String? coupleName,
  bool mapEnabled = false,
}) =>
    [
      // The couple's chosen name (null: none chosen yet).
      coupleNameProvider.overrideWith((ref, relationshipId) async => coupleName),
      planningRepositoryProvider.overrideWithValue(PlanningRepository(gateway)),
      // The dual clock reads presence; Planning reports the device zone.
      partnerDistanceProvider.overrideWith((ref, relationshipId) => Stream.value(partner)),
      coupleMapEnabledProvider.overrideWith((ref) async => mapEnabled),
      planningDeviceTimezoneProvider.overrideWith((ref) async => deviceTimezone),
      planningMediaGatewayProvider.overrideWithValue(media ?? FakePlanningMediaGateway()),
      planningChangeSignalProvider.overrideWith((ref, relationshipId) => const Stream<void>.empty()),
      planningOutboxStoreProvider.overrideWithValue(store ?? MemoryOutboxStore()),
      planningOutboxSleepProvider.overrideWithValue((_) async {}),
      planningCurrentUserIdProvider.overrideWithValue(userId),
      // The Planning home's Calendar tab is the shared TimelineScreen.
      timeline_providers.currentUserIdProvider.overrideWithValue(null),
      timeline_providers.currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
      timeline_providers.timelineEventsProvider.overrideWith((ref, month) async => []),
      remindersListProvider.overrideWith(_FakeRemindersListNotifier.new),
      // The Calendar tab is now the Together screen (Together plan 1b R1).
      togetherRepositoryProvider.overrideWithValue(
        TogetherRepository(_EmptyTogetherGateway()),
      ),
      timeline_providers.togetherChangeSignalProvider.overrideWith(
        (ref, relationshipId) => const Stream<void>.empty(),
      ),
      togetherMeProvider.overrideWithValue(userId),
      togetherPartnerIdProvider.overrideWith((ref) async => null),
    ];

Widget planningTestApp(
  FakePlanningGateway gateway,
  Widget home, {
  MemoryOutboxStore? store,
  ThemeMode themeMode = ThemeMode.light,
  String? coupleName,
  bool mapEnabled = false,
}) =>
    ProviderScope(
      overrides: planningOverrides(gateway, store: store, coupleName: coupleName, mapEnabled: mapEnabled),
      // The app's shared widgets (ErrorStateWidget, CardInkWell, AppButton...)
      // size with flutter_screenutil, exactly as in the app.
      child: withScreenUtil(MaterialApp(
        localizationsDelegates: appLocalizationsDelegates, // exactly the app's
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: themeMode,
        home: home,
      )),
    );

/// Together with nothing on it.
class _EmptyTogetherGateway implements TogetherRpcGateway {
  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async =>
      const [];
}

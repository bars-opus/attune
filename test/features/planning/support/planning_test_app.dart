import 'package:attune/features/planning/data/planning_repository.dart';
import 'package:attune/features/planning/domain/planning_outbox.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline_providers;
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
}) =>
    [
      planningRepositoryProvider.overrideWithValue(PlanningRepository(gateway)),
      planningChangeSignalProvider.overrideWith((ref, relationshipId) => const Stream<void>.empty()),
      planningOutboxStoreProvider.overrideWithValue(store ?? MemoryOutboxStore()),
      planningOutboxSleepProvider.overrideWithValue((_) async {}),
      planningCurrentUserIdProvider.overrideWithValue(userId),
      // The Planning home's Calendar tab is the shared TimelineScreen.
      timeline_providers.currentUserIdProvider.overrideWithValue(null),
      timeline_providers.currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
      timeline_providers.timelineEventsProvider.overrideWith((ref, month) async => []),
      remindersListProvider.overrideWith(_FakeRemindersListNotifier.new),
    ];

Widget planningTestApp(
  FakePlanningGateway gateway,
  Widget home, {
  MemoryOutboxStore? store,
  ThemeMode themeMode = ThemeMode.light,
}) =>
    ProviderScope(
      overrides: planningOverrides(gateway, store: store),
      // The app's shared widgets (ErrorStateWidget, CardInkWell, AppButton...)
      // size with flutter_screenutil, exactly as in the app.
      child: withScreenUtil(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: themeMode,
        home: home,
      )),
    );

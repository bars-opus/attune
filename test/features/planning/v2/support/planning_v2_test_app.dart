import 'package:attune/features/planning/presentation/providers/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:attune/features/planning/v2/data/planning_v2_repository.dart';
import 'package:attune/features/planning/v2/domain/planning_outbox.dart';
import 'package:attune/features/planning/v2/presentation/planning_v2_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/support/chat_test_harness.dart' show withScreenUtil;
import 'fake_planning_gateway.dart';

List<Override> planningV2Overrides(
  FakePlanningGateway gateway, {
  MemoryOutboxStore? store,
  String userId = 'u-a',
}) =>
    [
      planningV2RepositoryProvider.overrideWithValue(PlanningV2Repository(gateway)),
      planningChangeSignalProvider.overrideWith((ref, relationshipId) => const Stream<void>.empty()),
      planningV2OutboxStoreProvider.overrideWithValue(store ?? MemoryOutboxStore()),
      planningV2OutboxSleepProvider.overrideWithValue((_) async {}),
      planningV2CurrentUserIdProvider.overrideWithValue(userId),
    ];

Widget planningV2TestApp(
  FakePlanningGateway gateway,
  Widget home, {
  MemoryOutboxStore? store,
  ThemeMode themeMode = ThemeMode.light,
}) =>
    ProviderScope(
      overrides: planningV2Overrides(gateway, store: store),
      // The app's shared widgets (ErrorStateWidget, CardInkWell, AppButton...)
      // size with flutter_screenutil, exactly as in the app.
      child: withScreenUtil(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: themeMode,
        home: home,
      )),
    );

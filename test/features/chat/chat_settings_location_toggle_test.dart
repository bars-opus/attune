// test/features/chat/chat_settings_location_toggle_test.dart
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/widgets/chat_settings_static_rows.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../location/presence_repository_test.dart'
    show FakePresenceGateway, FakeSampler;

Conversation _conversation() => Conversation(
  id: 'c1',
  relationshipId: 'r1',
  partnerId: 'p1',
  name: 'Partner',
  updatedAt: DateTime.utc(2026, 10, 1),
  relationshipStatus: 'active',
  availability: ConversationAvailability.active,
  unreadCount: 0,
);

Future<(FakePresenceGateway, FakeSampler)> _pump(
  WidgetTester t,
  Conversation? c, {
  Map<String, dynamic Function(Map<String, dynamic>)> handlers = const {},
}) async {
  final g = FakePresenceGateway({
    'couple_map_presence': (_) => const [],
    ...handlers,
  });
  final s = FakeSampler(
    next: const PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40),
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        presenceGatewayProvider.overrideWithValue(g),
        presenceSamplerProvider.overrideWithValue(s),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        chatHistoricalImportEnabledProvider.overrideWith((ref) async => false),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ChatSettingsStaticRows(conversation: c),
                ),
              ),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (g, s);
}

InfoRowWidget _toggle(WidgetTester t) => t.widget<InfoRowWidget>(
  find.widgetWithText(InfoRowWidget, 'Share my location'),
);

void main() {
  testWidgets('reads off when nothing is shared', (t) async {
    await _pump(t, _conversation());
    expect(_toggle(t).toggleValue, isFalse);
  });

  testWidgets('on: opts in, asks once, records; off: deletes', (t) async {
    final (g, s) = await _pump(t, _conversation());
    _toggle(t).onToggleChanged!(true);
    await t.pumpAndSettle();
    expect(
      g.calls.map((c) => c.$1),
      containsAllInOrder(['start_presence', 'record_presence']),
    );
    expect(s.asked, 1);
    _toggle(t).onToggleChanged!(false);
    await t.pumpAndSettle();
    expect(g.calls.map((c) => c.$1), contains('stop_presence'));
  });

  testWidgets('with no conversation the toggle stays off and calls nothing', (
    t,
  ) async {
    final (g, s) = await _pump(t, null);
    // InfoRowWidget requires a callback on toggle rows, so it is a no-op here.
    _toggle(t).onToggleChanged!(true);
    await t.pumpAndSettle();
    expect(_toggle(t).toggleValue, isFalse);
    expect(g.calls, isEmpty);
    expect(s.asked, 0);
  });

  testWidgets('a failed switch says so, and re-reads the real state', (
    t,
  ) async {
    final (g, _) = await _pump(
      t,
      _conversation(),
      handlers: {'stop_presence': (_) => throw Exception('offline')},
    );
    final reads = g.calls.where((c) => c.$1 == 'couple_map_presence').length;
    _toggle(t).onToggleChanged!(false);
    await t.pumpAndSettle();
    expect(
      find.text("Couldn't update location sharing. Try again."),
      findsOneWidget,
    );
    expect(
      g.calls.where((c) => c.$1 == 'couple_map_presence').length,
      greaterThan(reads),
    );
  });
}

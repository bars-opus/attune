// test/features/chat/chat_settings_seen_receipts_toggle_test.dart
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/chat/data/seen_receipts_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/seen_receipts.dart';
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

/// A server double: holds each member's vote; `effective` is both on.
class _FakeSeenServer {
  _FakeSeenServer({
    this.mine = false,
    this.partner = false,
    this.failSet = false,
  });
  bool mine;
  bool partner;
  bool failSet;
  final calls = <(String, Map<String, dynamic>)>[];

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    calls.add((fn, params));
    if (fn == 'set_seen_receipts') {
      if (failSet) throw Exception('offline');
      mine = params['p_on'] as bool;
    }
    return {'mine': mine, 'effective': mine && partner};
  }
}

Future<_FakeSeenServer> _pump(
  WidgetTester t,
  Conversation? c, {
  _FakeSeenServer? server,
}) async {
  final s = server ?? _FakeSeenServer();
  final g = FakePresenceGateway({'couple_map_presence': (_) => const []});
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        presenceGatewayProvider.overrideWithValue(g),
        presenceSamplerProvider.overrideWithValue(
          FakeSampler(
            next: const PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40),
          ),
        ),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        chatHistoricalImportEnabledProvider.overrideWith((ref) async => false),
        seenReceiptsRepositoryProvider.overrideWithValue(
          SeenReceiptsRepository(s.call),
        ),
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
  return s;
}

InfoRowWidget _toggle(WidgetTester t) => t.widget<InfoRowWidget>(
  find.widgetWithText(InfoRowWidget, seenReceiptsTitle),
);

void main() {
  testWidgets('a new couple reads off, with the off subtitle', (t) async {
    await _pump(t, _conversation());
    expect(_toggle(t).toggleValue, isFalse);
    expect(find.text(seenReceiptsSubtitle(SeenReceipts.off)), findsOneWidget);
  });

  testWidgets('turning on alone shows my vote and the waiting line', (t) async {
    final s = await _pump(t, _conversation());
    _toggle(t).onToggleChanged!(true);
    await t.pumpAndSettle();
    expect(s.calls.map((c) => c.$1), contains('set_seen_receipts'));
    // The last call is the re-read after the switch; check the set itself.
    expect(s.calls.lastWhere((c) => c.$1 == 'set_seen_receipts').$2, {
      'p_relationship_id': 'r1',
      'p_on': true,
    });
    expect(s.calls.last.$1, 'get_seen_receipts');
    expect(_toggle(t).toggleValue, isTrue);
    expect(
      find.text("Turns on once you've both turned it on."),
      findsOneWidget,
    );
  });

  testWidgets('both on reads on; turning off calls set false', (t) async {
    final s = await _pump(
      t,
      _conversation(),
      server: _FakeSeenServer(mine: true, partner: true),
    );
    expect(_toggle(t).toggleValue, isTrue);
    expect(
      find.text(
        seenReceiptsSubtitle(const SeenReceipts(mine: true, effective: true)),
      ),
      findsOneWidget,
    );
    _toggle(t).onToggleChanged!(false);
    await t.pumpAndSettle();
    expect(s.calls.lastWhere((c) => c.$1 == 'set_seen_receipts').$2, {
      'p_relationship_id': 'r1',
      'p_on': false,
    });
    expect(_toggle(t).toggleValue, isFalse);
  });

  testWidgets('the row never names who turned it off', (t) async {
    await _pump(
      t,
      _conversation(),
      server: _FakeSeenServer(mine: true, partner: false),
    );
    expect(find.textContaining('partner turned'), findsNothing);
    expect(find.textContaining('Partner'), findsNothing);
  });

  testWidgets('a failed switch says so and re-reads the real state', (t) async {
    final s = await _pump(
      t,
      _conversation(),
      server: _FakeSeenServer(failSet: true),
    );
    final reads = s.calls.where((c) => c.$1 == 'get_seen_receipts').length;
    _toggle(t).onToggleChanged!(true);
    await t.pumpAndSettle();
    expect(find.text(seenReceiptsFailureCopy), findsOneWidget);
    expect(
      s.calls.where((c) => c.$1 == 'get_seen_receipts').length,
      greaterThan(reads),
    );
    expect(_toggle(t).toggleValue, isFalse);
  });

  testWidgets('with no conversation the toggle is off and calls nothing', (
    t,
  ) async {
    final s = await _pump(t, null);
    _toggle(t).onToggleChanged!(true);
    await t.pumpAndSettle();
    expect(_toggle(t).toggleValue, isFalse);
    expect(s.calls, isEmpty);
  });

  // The row ends the relationship through the same confirmation as
  // Settings (it used to open Starred messages).
  testWidgets('End relationship opens the end confirmation', (t) async {
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t, _conversation());
    expect(find.textContaining('brocken'), findsNothing);
    await t.tap(find.text('End relationship'));
    await t.pumpAndSettle();
    expect(find.text('End your shared space?'), findsOneWidget);
  });
}

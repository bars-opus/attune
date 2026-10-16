import 'dart:async';

// test/features/couple_map/sharing_sheet_test.dart
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/couple_map/presentation/widgets/sharing_sheet.dart';
import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_preview.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_publisher.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    show currentRelationshipIdProvider;
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    show remindersListProvider, RemindersListNotifier;
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'widget/support/memory_widget_store.dart';
import '../location/presence_repository_test.dart'
    show FakePresenceGateway, FakeSampler;

class _NoReminders extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => <ReminderModel>[];
}

/// The real publisher's render and reminder timeouts would leave timers
/// pending in testWidgets; it has its own tests.
class _IdlePublisher extends Fake implements CoupleWidgetPublisher {
  @override
  final preview = ValueNotifier<CoupleWidgetPreview?>(null);
  @override
  bool started = false;
  @override
  void start() => started = true;
  @override
  Future<void> refreshFromServer({bool force = false}) async {}
}

const _self = {
  'who': 'self',
  'cell_lat': 5.565,
  'cell_lng': -0.208,
  'freshness': 'fresh',
};

Future<FakePresenceGateway> _pump(
  WidgetTester t,
  List<Map<String, Object?>> rows, {
  Map<String, dynamic Function(Map<String, dynamic>)> handlers = const {},
  ValueNotifier<bool>? shown,
  FakeStoryPlacesGateway? placesGateway,
  MemoryCoupleMapLocalStore? local,
  bool noFix = false,
}) async {
  final visible = shown ?? ValueNotifier(true);
  final g = FakePresenceGateway({
    'couple_map_presence': (_) => rows,
    ...handlers,
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        presenceGatewayProvider.overrideWithValue(g),
        presenceSamplerProvider.overrideWithValue(
          FakeSampler(
            next:
                noFix
                    ? null
                    : const PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40),
          ),
        ),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        storyPlacesGatewayProvider.overrideWithValue(
          placesGateway ?? FakeStoryPlacesGateway(),
        ),
        coupleMapLocalStoreProvider.overrideWithValue(
          local ?? MemoryCoupleMapLocalStore(),
        ),
        coupleMapEnabledProvider.overrideWith((ref) async => true),
        currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
        remindersListProvider.overrideWith(_NoReminders.new),
        coupleWidgetPublisherProvider.overrideWithValue(_IdlePublisher()),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder:
                      (_, show, __) =>
                          show
                              ? const SharingSheet(relationshipId: 'r1')
                              : const SizedBox(),
                ),
              ),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return g;
}

Iterable<String> _fns(FakePresenceGateway g) => g.calls.map((c) => c.$1);

void main() {
  setUp(() {
    CoupleWidgetSync.store = MemoryCoupleWidgetStore();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'off: one switch, no pause rows; turning it on opts in and records',
    (t) async {
      final g = await _pump(t, const []);
      expect(find.text('Share my approximate area'), findsOneWidget);
      expect(find.text('Pause for 1 hour'), findsNothing);
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      expect(
        _fns(g),
        containsAllInOrder(['start_presence', 'record_presence']),
      );
    },
  );

  testWidgets('sharing: the three pause rows; each sends its end', (t) async {
    final g = await _pump(t, const [_self]);
    for (final row in [
      'Pause for 1 hour',
      'Pause for 8 hours',
      'Pause until I resume',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    await t.tap(find.text('Pause for 1 hour'));
    await t.pumpAndSettle();
    final hour =
        g.calls.lastWhere((c) => c.$1 == 'set_presence_pause').$2['p_until']
            as String;
    expect(
      DateTime.parse(hour).difference(DateTime.now().toUtc()).inMinutes,
      inInclusiveRange(58, 60),
    );
  });

  testWidgets('pause until I resume sends infinity', (t) async {
    final g = await _pump(t, const [_self]);
    await t.tap(find.text('Pause until I resume'));
    await t.pumpAndSettle();
    expect(
      g.calls.lastWhere((c) => c.$1 == 'set_presence_pause').$2['p_until'],
      'infinity',
    );
  });

  testWidgets('paused: Resume replaces the pause rows and clears the pause', (
    t,
  ) async {
    final g = await _pump(t, const [
      {'who': 'self', 'freshness': 'fresh', 'my_paused_until': 'infinity'},
    ]);
    expect(find.text('Pause for 1 hour'), findsNothing);
    expect(find.text('Resume'), findsOneWidget);
    await t.tap(find.text('Resume'));
    await t.pumpAndSettle();
    final pause = g.calls.lastWhere((c) => c.$1 == 'set_presence_pause');
    expect(pause.$2.containsKey('p_until'), isTrue);
    expect(pause.$2['p_until'], isNull);
  });

  testWidgets('a failure says so in plain words (spec §9 2.4)', (t) async {
    await _pump(
      t,
      const [_self],
      handlers: {'set_presence_pause': (_) => throw Exception('offline')},
    );
    await t.tap(find.text('Pause for 8 hours'));
    await t.pumpAndSettle();
    expect(find.text("Couldn't update your area. Try again."), findsOneWidget);
  });

  testWidgets(
    'dismissing the sheet mid-call is safe and the map still re-reads',
    (t) async {
      final shown = ValueNotifier(true);
      final g = await _pump(
        t,
        const [_self],
        shown: shown,
        handlers: {
          'set_presence_pause':
              (_) => Future<void>.delayed(const Duration(milliseconds: 50)),
        },
      );
      final reads = g.calls.where((c) => c.$1 == 'couple_map_presence').length;
      await t.tap(find.text('Pause for 1 hour'));
      shown.value = false; // the sheet is swiped away before the RPC returns
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
      expect(
        g.calls.where((c) => c.$1 == 'couple_map_presence').length,
        greaterThan(reads),
        reason: 'the map re-reads even though the sheet is gone',
      );
    },
  );

  testWidgets('pause and resume rows carry no external-link glyph', (t) async {
    await _pump(t, const [_self]);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
  });

  testWidgets('explains symmetry without naming the partner\'s state', (
    t,
  ) async {
    await _pump(t, const [_self]);
    expect(
      find.text('Pausing hides you from each other. Nobody is told.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'remove all my places asks first, then calls the RPC and says how many',
    (t) async {
      final places = FakeStoryPlacesGateway({
        'clear_my_story_places': (_) => 3,
      });
      await _pump(t, const [_self], placesGateway: places);
      await t.ensureVisible(find.text('Remove all my places'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove all my places'));
      await t.pumpAndSettle();
      expect(find.text('Remove all your places?'), findsOneWidget);
      expect(find.text('Your stories stay.'), findsOneWidget);
      await t.tap(find.text('Remove all'));
      await t.pumpAndSettle();
      expect(places.calls.single.$1, 'clear_my_story_places');
      expect(find.text('Removed 3 places'), findsOneWidget);
    },
  );

  testWidgets('home area: set from here (device only), then clear', (t) async {
    final local = MemoryCoupleMapLocalStore();
    await _pump(t, const [_self], local: local);
    await t.ensureVisible(find.text('Warn me near home'));
    await t.pumpAndSettle();
    await t.tap(find.text('Warn me near home'));
    await t.pumpAndSettle();
    // It says plainly that it uses where you are now, and asks first.
    expect(
      find.text('Use where you are right now as your home area?'),
      findsOneWidget,
    );
    expect(local.values[CoupleMapLocalKeys.homeArea], isNull);
    await t.tap(find.text('Use here'));
    await t.pumpAndSettle();
    expect(local.values[CoupleMapLocalKeys.homeArea], isNotNull);
    expect(find.text('Home area set'), findsOneWidget);
    await t.ensureVisible(find.text('Clear home area'));
    await t.pumpAndSettle();
    await t.tap(find.text('Clear home area'));
    await t.pumpAndSettle();
    expect(local.values[CoupleMapLocalKeys.homeArea], isNull);
  });

  testWidgets('home area with no fix says so and stores nothing', (t) async {
    final local = MemoryCoupleMapLocalStore();
    await _pump(t, const [_self], local: local, noFix: true);
    await t.ensureVisible(find.text('Warn me near home'));
    await t.pumpAndSettle();
    await t.tap(find.text('Warn me near home'));
    await t.pumpAndSettle();
    await t.tap(find.text('Use here'));
    await t.pumpAndSettle();
    expect(
      find.text("Couldn't find where you are. Try again."),
      findsOneWidget,
    );
    expect(local.values, isEmpty);
  });

  testWidgets('home area: cancelling the confirmation stores nothing', (
    t,
  ) async {
    final local = MemoryCoupleMapLocalStore();
    await _pump(t, const [_self], local: local);
    await t.ensureVisible(find.text('Warn me near home'));
    await t.pumpAndSettle();
    await t.tap(find.text('Warn me near home'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(local.values, isEmpty);
  });

  testWidgets(
    'the switch moves at once while the call is in flight (no snap back)',
    (t) async {
      final gate = Completer<void>();
      await _pump(
        t,
        const [],
        handlers: {'start_presence': (_) => gate.future},
      );
      await t.tap(find.byType(Switch).first);
      await t.pump();
      expect(t.widget<Switch>(find.byType(Switch).first).value, isTrue);
      gate.complete();
      await t.pump();
      // The refetch frame: it used to snap back here.
      expect(t.widget<Switch>(find.byType(Switch).first).value, isTrue);
      await t.pumpAndSettle();
      expect(t.widget<Switch>(find.byType(Switch).first).value, isTrue);
    },
  );

  testWidgets(
    'remove all: a double tap opens one dialog; the dialog has a short title',
    (t) async {
      final places = FakeStoryPlacesGateway({
        'clear_my_story_places': (_) => 1,
      });
      await _pump(t, const [_self], placesGateway: places);
      await t.ensureVisible(find.text('Remove all my places'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove all my places'));
      await t.tap(find.text('Remove all my places'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Remove all your places?'), findsOneWidget);
      expect(find.text('Your stories stay.'), findsOneWidget);
    },
  );

  testWidgets('home-screen toggle: off by default; on shows the preview; off clears', (t) async {
    final widget = MemoryCoupleWidgetStore();
    CoupleWidgetSync.store = widget;
    await _pump(t, const [_self]);
    // A toggle row isn't an InkWell (info_row_widget.dart): tap its switch.
    final toggle = find.descendant(
      of: find.widgetWithText(InfoRowWidget, widgetToggleTitle),
      matching: find.byType(Switch),
    );
    await t.ensureVisible(toggle);
    await t.pumpAndSettle();
    expect(find.text(widgetPreviewLabel), findsNothing);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(await CoupleWidgetSync.isEnabled(), isTrue);
    expect(find.text(widgetPreviewLabel), findsOneWidget);
    await t.ensureVisible(toggle);
    await t.pumpAndSettle();
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(await CoupleWidgetSync.isEnabled(), isFalse);
    expect(widget.payload, '{"v":1}');
  });

  testWidgets('pausing hides the widget distance before the call (spec §4.3)', (t) async {
    await _pump(t, const [_self]);
    final g = CoupleWidgetSync.generation;
    await t.tap(find.text('Pause for 1 hour'));
    await t.pumpAndSettle();
    expect(CoupleWidgetSync.generation, greaterThan(g));
  });

  testWidgets('turning sharing off hides the widget distance too', (t) async {
    await _pump(t, const [_self]);
    final g = CoupleWidgetSync.generation;
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(CoupleWidgetSync.generation, greaterThan(g));
  });
}

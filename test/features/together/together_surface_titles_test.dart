// test/features/together/together_surface_titles_test.dart
// Spec 1b (research 06 §3 F8 (1)): the home-screen card, the lock-screen
// plan and the calendar copy show "Next plan" (calendar: "Plan", no place)
// unless this phone turned titles on for that surface. Off by default.
import 'package:attune/features/together/data/together_calendar_mirror.dart';
import 'package:attune/features/together/data/together_live_activity.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_live.dart';
import 'package:attune/features/together/domain/together_mirror.dart';
import 'package:attune/features/together/domain/together_overlay.dart';
import 'package:attune/features/together/domain/together_widget.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_calendar_mirror_test.dart' show FakeMirrorCalendar;
import 'together_live_activity_test.dart' show FakeLiveStore;
import 'together_widget_sync_test.dart' show FakeWidgetStore;

final _now = DateTime(2026, 11, 2, 9);

TogetherItem _item(
  String title, {
  TogetherItemKind kind = TogetherItemKind.event,
  Map<String, dynamic> ref = const {},
}) => TogetherItem(
  kind: kind,
  id: title,
  date: DateTime(2026, 11, 3),
  startsAt: DateTime(2026, 11, 3, 19),
  allDay: false,
  title: title,
  participantIds: const ['ama', 'kofi'],
  createdBy: 'ama',
  sourceRef: ref,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the card lines know their neutral words: plan, reminder, free', () {
    final lines = togetherWidgetLines(
      items: [
        _item('Clinic'),
        _item('Pick up pills', kind: TogetherItemKind.reminder),
      ],
      windows: [
        FreeWindow(
          start: DateTime(2026, 11, 2, 18),
          end: DateTime(2026, 11, 2, 20),
          partnerFrom: '18:00',
          partnerTo: '20:00',
          partnerDiffers: false,
        ),
      ],
      me: 'ama',
      now: _now,
    );
    expect(
      widgetLinesForCard(lines, showTitles: false).map((l) => l.title),
      containsAll(['Free', widgetNeutralTitle, widgetNeutralReminderTitle]),
    );
    expect(
      widgetLinesForCard(lines, showTitles: true).map((l) => l.title),
      containsAll(['Free', 'Clinic', 'Pick up pills']),
    );
  });

  test('the card publishes "Next plan" unless titles are on', () async {
    final store = FakeWidgetStore();
    TogetherWidgetSync.store = store;
    const line = WidgetLine(
      title: 'Clinic',
      label: 'Tue 7:00 PM',
      startMs: 1,
      endMs: 2,
    );
    SharedPreferences.setMockInitialValues({'together_widget_enabled': true});
    await TogetherWidgetSync.publishIfEnabled([line]);
    expect(store.saved.last, contains('Next plan'));
    expect(store.saved.last, isNot(contains('Clinic')));
    SharedPreferences.setMockInitialValues({
      'together_widget_enabled': true,
      'together_widget_titles': true,
    });
    await TogetherWidgetSync.publishIfEnabled([line]);
    expect(store.saved.last, contains('Clinic'));
  });

  test('the lock screen shows "Next plan" unless titles are on', () async {
    final store = FakeLiveStore();
    TogetherLiveActivity.store = store;
    final plan = LivePlan(
      title: 'Clinic',
      start: DateTime(2026, 11, 2, 19),
      end: DateTime(2026, 11, 2, 20),
    );
    SharedPreferences.setMockInitialValues({'together_live_enabled': true});
    await TogetherLiveActivity.showIfEnabled(plan);
    expect(store.shown.last.title, liveNeutralTitle);
    expect(store.shown.last.start, plan.start);
    SharedPreferences.setMockInitialValues({
      'together_live_enabled': true,
      'together_live_titles': true,
    });
    await TogetherLiveActivity.showIfEnabled(plan);
    expect(store.shown.last, plan);
  });

  test('the calendar copy is "Plan" with no place unless titles are on', () {
    final items = [
      _item('Clinic', ref: {'location_name': 'Ridge Hospital'}),
    ];
    final off = mirrorEventsFor(items: items, me: 'ama');
    expect(off.single.title, mirrorNeutralTitle);
    expect(off.single.location, isNull);
    final on = mirrorEventsFor(items: items, me: 'ama', showTitles: true);
    expect(on.single.title, 'Clinic');
    expect(on.single.location, 'Ridge Hospital');
  });

  test('turning titles on replaces the calendar entries', () async {
    final cal = FakeMirrorCalendar();
    TogetherMirror.calendar = cal;
    final items = [_item('Clinic')];
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
    await TogetherMirror.syncIfEnabled((from, to) async => items, 'ama', _now);
    expect(cal.entries('Plans').map((e) => e.title), [mirrorNeutralTitle]);
    // Set on the same store: resetting the mock would also forget the
    // calendar's id and make a second "Plans" calendar.
    await (await SharedPreferences.getInstance()).setBool(
      mirrorTitlesKey,
      true,
    );
    await TogetherMirror.syncIfEnabled((from, to) async => items, 'ama', _now);
    expect(cal.entries('Plans').map((e) => e.title), ['Clinic']);
  });

  test(
    'each surface\'s titles switch is off by default and remembered',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      for (final key in [widgetTitlesKey, liveTitlesKey, mirrorTitlesKey]) {
        expect(
          await c.read(togetherSurfaceTitlesProvider(key).future),
          isFalse,
        );
      }
      await c
          .read(togetherSurfaceTitlesProvider(widgetTitlesKey).notifier)
          .set(true);
      expect(
        await c.read(togetherSurfaceTitlesProvider(widgetTitlesKey).future),
        isTrue,
      );
      expect(
        (await SharedPreferences.getInstance()).getBool(widgetTitlesKey),
        isTrue,
      );
      expect(
        await c.read(togetherSurfaceTitlesProvider(liveTitlesKey).future),
        isFalse,
      );
    },
  );

  test('two same-time plans with titles off are two calendar entries, and '
      'a second sync changes nothing', () async {
    final cal = FakeMirrorCalendar();
    TogetherMirror.calendar = cal;
    final items = [_item('Clinic'), _item('Dinner')];
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
    await TogetherMirror.syncIfEnabled((from, to) async => items, 'ama', _now);
    expect(cal.entries('Plans'), hasLength(2));
    final (adds, removes) = (cal.adds, cal.removes);
    await TogetherMirror.syncIfEnabled((from, to) async => items, 'ama', _now);
    expect((cal.adds, cal.removes), (adds, removes));
  });
}

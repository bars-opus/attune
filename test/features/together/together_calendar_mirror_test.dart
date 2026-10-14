import 'dart:async';

import 'package:attune/features/together/data/together_calendar_mirror.dart';
import 'package:attune/features/together/data/together_device_surfaces.dart';
import 'package:attune/features/together/data/together_live_activity.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_mirror.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_live_activity_test.dart' show FakeLiveStore;
import 'together_widget_sync_test.dart' show FakeWidgetStore;

class FakeMirrorCalendar implements MirrorCalendar {
  FakeMirrorCalendar({this.access = true, this.gate});
  bool access;

  /// Holds every access check until completed (a slow phone).
  final Completer<void>? gate;
  final names = <String, String>{};
  final events = <String, List<(String, MirrorEvent)>>{};
  int adds = 0;
  int removes = 0;
  var _n = 0;

  List<MirrorEvent> entries(String name) => [
    for (final id in names.keys.where((k) => names[k] == name))
      for (final (_, e) in events[id] ?? const <(String, MirrorEvent)>[]) e,
  ];

  @override
  Future<bool> hasAccess() async {
    await gate?.future;
    return access;
  }
  @override
  Future<bool> requestAccess() async => access;
  @override
  Future<bool> exists(String calendarId) async =>
      events.containsKey(calendarId);
  @override
  Future<String> create(String name) async {
    final id = 'cal-${++_n}';
    names[id] = name;
    events[id] = [];
    return id;
  }

  @override
  Future<List<DeviceMirrorEvent>> list(
    String calendarId,
    DateTime from,
    DateTime to,
  ) async => [
    for (final (id, e) in events[calendarId] ?? const <(String, MirrorEvent)>[])
      if (!e.start.isBefore(from) && e.start.isBefore(to))
        DeviceMirrorEvent(id: id, start: e.start, fingerprint: e.fingerprint),
  ];
  @override
  Future<void> add(String calendarId, MirrorEvent e) async {
    adds++;
    events[calendarId]!.add(('ev-${++_n}', e));
  }

  @override
  Future<void> remove(String eventId) async {
    removes++;
    for (final l in events.values) {
      l.removeWhere((x) => x.$1 == eventId);
    }
  }

  @override
  Future<void> deleteCalendar(String calendarId) async {
    events.remove(calendarId);
    names.remove(calendarId);
  }
}

final _now = DateTime(2026, 11, 2, 9);

TogetherItem _plan(String title, DateTime start) => TogetherItem(
  kind: TogetherItemKind.event,
  id: title,
  date: DateTime(start.year, start.month, start.day),
  startsAt: start,
  allDay: false,
  title: title,
  participantIds: const ['ama', 'kofi'],
  createdBy: 'ama',
);

void main() {
  late FakeMirrorCalendar cal;
  setUp(() {
    cal = FakeMirrorCalendar();
    TogetherMirror.calendar = cal;
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
  });

  Future<bool> sync(List<TogetherItem> items) =>
      TogetherMirror.syncIfEnabled((from, to) async => items, 'ama', _now);

  test(
    'copies my plans into a calendar called Plans, and remembers it',
    () async {
      expect(await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]), isTrue);
      expect(cal.names.values, ['Plans']);
      expect(cal.entries('Plans').map((e) => e.title), ['Dinner']);
      expect(await TogetherMirror.calendarId(), cal.names.keys.single);
    },
  );

  test('a second sync with nothing changed changes nothing', () async {
    final items = [_plan('Dinner', DateTime(2026, 11, 3, 19))];
    await sync(items);
    final (adds, removes) = (cal.adds, cal.removes);
    await sync(items);
    expect((cal.adds, cal.removes), (adds, removes));
    expect(cal.names, hasLength(1));
  });

  test('a renamed plan replaces its entry', () async {
    await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]);
    await sync([_plan('Dinner at Kozo', DateTime(2026, 11, 3, 19))]);
    expect(cal.entries('Plans').map((e) => e.title), ['Dinner at Kozo']);
  });

  test('a deleted calendar is made again', () async {
    await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]);
    await cal.deleteCalendar(cal.names.keys.single);
    expect(await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]), isTrue);
    expect(cal.entries('Plans').map((e) => e.title), ['Dinner']);
  });

  test('off, or no calendar access: nothing is made or read', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]), isFalse);
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
    cal.access = false;
    expect(await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]), isFalse);
    expect(cal.names, isEmpty);
  });

  test('turning it on asks for access; refused, it stays off', () async {
    SharedPreferences.setMockInitialValues({});
    cal.access = false;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(togetherMirrorEnabledProvider.future), isFalse);
    expect(
      await c.read(togetherMirrorEnabledProvider.notifier).set(true),
      isFalse,
    );
    expect(await c.read(togetherMirrorEnabledProvider.future), isFalse);
    cal.access = true;
    expect(
      await c.read(togetherMirrorEnabledProvider.notifier).set(true),
      isTrue,
    );
    expect(await c.read(togetherMirrorEnabledProvider.future), isTrue);
  });

  test('off deletes the whole calendar and forgets it', () async {
    await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(togetherMirrorEnabledProvider.notifier).set(false);
    expect(cal.names, isEmpty);
    expect(await TogetherMirror.calendarId(), isNull);
  });

  test(
    'quick exit and sign-out clear every surface: card, lock screen, calendar',
    () async {
      final widget = FakeWidgetStore();
      final live = FakeLiveStore();
      TogetherWidgetSync.store = widget;
      TogetherLiveActivity.store = live;
      await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]);
      await clearTogetherDeviceSurfaces();
      expect(widget.saved, [null]);
      expect(live.ends, 1);
      expect(cal.names, isEmpty);
    },
  );

  test('a plan on the 60th day is found again, not copied twice', () async {
    // From 2 Nov, day 60 is 1 Jan.
    final items = [_plan('New Year lunch', DateTime(2027, 1, 1, 13))];
    await sync(items);
    await sync(items);
    expect(cal.entries('Plans').map((e) => e.title), ['New Year lunch']);
  });
}

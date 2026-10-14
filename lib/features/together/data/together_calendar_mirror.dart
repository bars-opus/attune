import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/together_item.dart';
import '../domain/together_mirror.dart';

/// This phone's opt-in (Phase 8d); off unless set.
const mirrorEnabledKey = 'together_mirror_enabled';

/// The copy's calendar on this phone (the only thing stored, R3).
const mirrorCalendarKey = 'together_mirror_calendar_id';

/// No app name, no partner name (owner rule: discreet).
const mirrorCalendarName = 'Plans';

/// The phone's calendar store (a seam so tests never touch the platform).
abstract class MirrorCalendar {
  Future<bool> hasAccess();
  Future<bool> requestAccess();
  Future<bool> exists(String calendarId);
  Future<String> create(String name);
  Future<List<DeviceMirrorEvent>> list(
    String calendarId,
    DateTime from,
    DateTime to,
  );
  Future<void> add(String calendarId, MirrorEvent e);
  Future<void> remove(String eventId);
  Future<void> deleteCalendar(String calendarId);
}

class DeviceCalendarPlusMirror implements MirrorCalendar {
  const DeviceCalendarPlusMirror();

  dc.DeviceCalendar get _cal => dc.DeviceCalendar.instance;

  @override
  Future<bool> hasAccess() async =>
      await _cal.hasPermissions() == dc.CalendarPermissionStatus.granted;

  @override
  Future<bool> requestAccess() async =>
      await _cal.requestPermissions() == dc.CalendarPermissionStatus.granted;

  @override
  Future<bool> exists(String calendarId) async =>
      (await _cal.listCalendars()).any((c) => c.id == calendarId);

  @override
  Future<String> create(String name) =>
      // The plugin's default account: iCloud where it's on (so the copy is
      // visible; the setting says it may show on other devices), else the
      // phone's own; Android's own account (R1).
      _cal.createCalendar(name: name, colorHex: '#8E8E93');

  @override
  Future<List<DeviceMirrorEvent>> list(
    String calendarId,
    DateTime from,
    DateTime to,
  ) async => [
    for (final e in await _cal.listEvents(from, to, calendarIds: [calendarId]))
      DeviceMirrorEvent(
        id: e.eventId,
        start: e.startDate,
        fingerprint: mirrorFingerprint(
          title: e.title,
          start: e.startDate,
          end: e.isAllDay ? allDayLastDay(e.startDate, e.endDate) : e.endDate,
          allDay: e.isAllDay,
          location: (e.location?.isEmpty ?? true) ? null : e.location,
        ),
      ),
  ];

  @override
  Future<void> add(String calendarId, MirrorEvent e) => _cal.createEvent(
    calendarId: calendarId,
    title: e.title,
    startDate: e.start,
    endDate:
        e.allDay
            ? deviceAllDayEnd(e.end, exclusiveEnd: Platform.isAndroid)
            : e.end,
    isAllDay: e.allDay,
    location: e.location,
  );

  @override
  Future<void> remove(String eventId) => _cal.deleteEvent(eventId: eventId);

  @override
  Future<void> deleteCalendar(String calendarId) =>
      _cal.deleteCalendar(calendarId);
}

/// Keeps the copy in step with Together, and removes it. Never throws.
class TogetherMirror {
  static MirrorCalendar calendar = const DeviceCalendarPlusMirror();

  static Future<String?> calendarId() async {
    try {
      return (await SharedPreferences.getInstance()).getString(
        mirrorCalendarKey,
      );
    } catch (_) {
      return null;
    }
  }

  /// Already allowed, or asks now. False when refused.
  static Future<bool> ensureAccess() async {
    try {
      return await calendar.hasAccess() || await calendar.requestAccess();
    } catch (_) {
      return false;
    }
  }

  /// Copies the plans I'm in for the next [mirrorDays] days, if this phone
  /// opted in (read from storage itself) and calendar access is allowed.
  /// [load] fetches Together items for a date range. Returns whether it ran.
  static Future<bool> syncIfEnabled(
    Future<List<TogetherItem>> Function(DateTime from, DateTime to) load,
    String? me,
    DateTime now,
) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(mirrorEnabledKey) ?? false) || me == null) {
        return false;
      }
      if (!await calendar.hasAccess()) return false;
      var id = prefs.getString(mirrorCalendarKey);
      if (id == null || !await calendar.exists(id)) {
        id = await calendar.create(mirrorCalendarName);
        await prefs.setString(mirrorCalendarKey, id);
      }
      final from = DateTime(now.year, now.month, now.day);
      final to = DateTime(from.year, from.month, from.day + mirrorDays);
      final desired = [
        for (final e in mirrorEventsFor(items: await load(from, to), me: me))
          if (!e.start.isBefore(from)) e,
      ];
      // Entries from before today stay as history (R3).
      // The load includes day 60 itself; the phone's read stops before its
      // end date, so read one day further.
      final listTo = DateTime(to.year, to.month, to.day + 1);
      final existing = [
        for (final e in await calendar.list(id, from, listTo))
          if (!e.start.isBefore(from)) e,
      ];
      final changes = mirrorChanges(desired, existing);
      for (final eventId in changes.delete) {
        await calendar.remove(eventId);
      }
      for (final e in changes.create) {
        await calendar.add(id, e);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Off", quick exit and sign-out: the whole calendar goes (R5).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(mirrorCalendarKey);
      if (id == null) return;
      await calendar.deleteCalendar(id);
      await prefs.remove(mirrorCalendarKey);
    } catch (_) {}
  }
}

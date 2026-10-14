import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;

import '../domain/together_overlay.dart';

/// The phone's own calendars, read for busy times only (plan R4). A seam so
/// tests never touch the platform.
abstract class DeviceBusySource {
  Future<bool> hasAccess();
  Future<bool> requestAccess();
  Future<List<DeviceBusy>> read(DateTime from, DateTime to);
  Future<void> openSettings();
}

class DeviceCalendarPlusSource implements DeviceBusySource {
  const DeviceCalendarPlusSource();

  dc.DeviceCalendar get _cal => dc.DeviceCalendar.instance;

  @override
  Future<bool> hasAccess() async =>
      await _cal.hasPermissions() == dc.CalendarPermissionStatus.granted;

  @override
  Future<bool> requestAccess() async =>
      await _cal.requestPermissions() == dc.CalendarPermissionStatus.granted;

  @override
  Future<List<DeviceBusy>> read(DateTime from, DateTime to) async {
    final events = await _cal.listEvents(from, to);
    // Titles, places and people are dropped here, on the phone.
    return [
      for (final e in events)
        DeviceBusy(
          start: e.startDate,
          end: e.endDate,
          allDay: e.isAllDay,
          free: e.availability == dc.EventAvailability.free,
          cancelled: e.status == dc.EventStatus.canceled,
          calendarId: e.calendarId,
        ),
    ];
  }

  @override
  Future<void> openSettings() => _cal.openAppSettings();
}

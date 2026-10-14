import 'package:add_2_calendar/add_2_calendar.dart' as a2c;

import '../domain/calendar_export.dart';

/// Opens the phone's own "new event" editor, prefilled. No calendar read
/// permission is needed (spec §6.4).
abstract class CalendarExporter {
  Future<bool> add(CalendarExport e);
}

class Add2CalendarExporter implements CalendarExporter {
  const Add2CalendarExporter();

  @override
  Future<bool> add(CalendarExport e) => a2c.Add2Calendar.addEvent2Cal(
    a2c.Event(
      title: e.title,
      description: e.description,
      location: e.location,
      startDate: e.start,
      endDate: e.end,
      allDay: e.allDay,
      recurrence:
          e.frequency == null
              ? null
              : a2c.Recurrence(
                frequency: switch (e.frequency!) {
                  ExportFrequency.daily => a2c.Frequency.daily,
                  ExportFrequency.weekly => a2c.Frequency.weekly,
                  ExportFrequency.monthly => a2c.Frequency.monthly,
                  ExportFrequency.yearly => a2c.Frequency.yearly,
                },
                interval: e.interval,
                endDate: e.until,
              ),
    ),
  );
}

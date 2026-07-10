// import 'package:flutter/material.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
// import 'package:table_calendar/table_calendar.dart';

// class SimpleCalendar extends StatefulWidget {
//   const SimpleCalendar({super.key});

//   @override
//   State<SimpleCalendar> createState() => _SimpleCalendarState();
// }

// class _SimpleCalendarState extends State<SimpleCalendar> {
//   CalendarFormat _calendarFormat = CalendarFormat.month;
//   DateTime _focusedDay = DateTime.now();
//   DateTime? _selectedDay;

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final colorScheme = theme.colorScheme;
//     return TableCalendar(
//       rowHeight: 52.h,

//       // 52 : 43,
//       daysOfWeekHeight: 50.h,
//       calendarBuilders: CalendarBuilders(
//         defaultBuilder: (context, date, _) {},
//         markerBuilder: (context, date, events) {},
//       ),

//       availableGestures: AvailableGestures.all,
//       pageAnimationCurve: Curves.easeInOut,
//       calendarFormat: CalendarFormat.month,
//       startingDayOfWeek: StartingDayOfWeek.sunday,
//       calendarStyle: CalendarStyle(
//         // Regular dates
//         defaultTextStyle: theme.textTheme.bodyMedium!.copyWith(
//           color: theme.colorScheme.onBackground,
//         ),
//         todayDecoration: BoxDecoration(
//           color: Colors.grey,
//           shape: BoxShape.circle,
//         ),
//         holidayTextStyle: TextStyle(color: Colors.red),
//         outsideDaysVisible: true,
//       ),
//       headerStyle: HeaderStyle(
//         titleCentered: false,
//         titleTextStyle: theme.textTheme.labelLarge!.copyWith(
//           color: theme.colorScheme.primary,
//           // fontWeight: FontWeight.bold,
//         ),
//         headerMargin: const EdgeInsets.only(top: 20, bottom: 10, left: 10),
//         leftChevronVisible: false,
//         rightChevronVisible: false,
//         formatButtonVisible: false,
//         formatButtonTextStyle: TextStyle(color: Colors.white),
//         formatButtonShowsNext: false,
//       ),
//       onDaySelected: (selectedDay, focusedDay) {},

//       firstDay: DateTime(2023),
//       lastDay: DateTime(2028),
//       focusedDay: _focusedDay,
//     );
//     // TableCalendar(
//     //   firstDay: DateTime.utc(2020, 1, 1),
//     //   lastDay: DateTime.utc(2030, 12, 31),
//     //   focusedDay: _focusedDay,
//     //   calendarFormat: _calendarFormat,
//     //   selectedDayPredicate: (day) {
//     //     return isSameDay(_selectedDay, day);
//     //   },
//     //   onDaySelected: (selectedDay, focusedDay) {
//     //     setState(() {
//     //       _selectedDay = selectedDay;
//     //       _focusedDay = focusedDay;
//     //     });

//     //     // Show selected date
//     //     ScaffoldMessenger.of(context).showSnackBar(
//     //       SnackBar(
//     //         content: Text('Selected: ${selectedDay.toString().split(' ')[0]}'),
//     //       ),
//     //     );
//     //   },
//     //   onFormatChanged: (format) {
//     //     setState(() {
//     //       _calendarFormat = format;
//     //     });
//     //   },
//     //   onPageChanged: (focusedDay) {
//     //     _focusedDay = focusedDay;
//     //   },
//     // );
//   }
// }

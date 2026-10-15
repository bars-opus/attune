import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/widgets/together_item_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _event({
  List<String> who = const ['ama', 'kofi'],
  TogetherVisibility visibility = TogetherVisibility.shared,
  String createdBy = 'ama',
  String title = 'Dinner',
  DateTime? startsAt,
}) => TogetherItem(
  kind: TogetherItemKind.event,
  id: 'e1',
  date: DateTime(2026, 11, 2),
  startsAt: startsAt ?? DateTime(2026, 11, 2, 19),
  endsAt: DateTime(2026, 11, 2, 21),
  allDay: false,
  title: title,
  participantIds: who,
  createdBy: createdBy,
  visibility: visibility,
);

Future<void> _pump(WidgetTester t, Widget w) => t.pumpWidget(
  ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(home: Scaffold(body: w)),
  ),
);

void main() {
  testWidgets('shows time and who, from my side', (t) async {
    var tapped = false;
    await _pump(
      t,
      TogetherItemRow(
        item: _event(),
        me: 'ama',
        partnerName: 'Kofi',
        coupleName: 'The Harolds',
        onTap: () => tapped = true,
      ),
    );
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.textContaining('The Harolds'), findsOneWidget); // the couple, by their name
    expect(find.textContaining('7:00'), findsOneWidget);
    await t.tap(find.text('Dinner'));
    expect(tapped, isTrue);
  });

  testWidgets("the partner's own event names them", (t) async {
    await _pump(
      t,
      TogetherItemRow(
        item: _event(who: ['kofi'], createdBy: 'kofi'),
        me: 'ama',
        partnerName: 'Kofi',
      ),
    );
    expect(find.textContaining('Kofi'), findsOneWidget);
  });

  testWidgets('a lead line comes first', (t) async {
    await _pump(
      t,
      TogetherItemRow(
        item: _event(),
        me: 'ama',
        partnerName: 'Kofi',
        lead: 'In 12 days',
      ),
    );
    expect(find.textContaining('In 12 days'), findsOneWidget);
  });

  testWidgets('a reminder: its occasion in the circle and at the end', (t) async {
    await _pump(
      t,
      TogetherItemRow(
        item: TogetherItem(
          kind: TogetherItemKind.reminder,
          id: 'r1',
          date: DateTime(2026, 11, 14),
          allDay: true,
          title: "Ama's birthday",
          participantIds: const ['ama', 'kofi'],
          sourceRef: const {'reminder_type': 'birthday', 'recurrence': 'yearly'},
        ),
        me: 'ama',
        partnerName: 'Kofi',
        lead: 'In 12 days',
      ),
    );
    // The circle and the end both say birthday.
    expect(find.byIcon(Icons.cake_outlined), findsOneWidget);
    expect(find.byIcon(FontAwesomeIcons.birthdayCake), findsOneWidget);
    expect(find.text('In 12 days - Reminder'), findsOneWidget);
  });

  testWidgets('an event keeps its plain row (no trailing icon)', (t) async {
    await _pump(t, TogetherItemRow(item: _event(), me: 'ama', partnerName: 'Kofi'));
    expect(find.byIcon(FontAwesomeIcons.birthdayCake), findsNothing);
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
  });

  test('who labels', () {
    expect(togetherWhoLabel(TogetherWho.me, 'Kofi'), 'You');
    expect(togetherWhoLabel(TogetherWho.partner, 'Kofi'), 'Kofi');
    expect(togetherWhoLabel(TogetherWho.us, 'Kofi', coupleName: 'The Harolds'), 'The Harolds');
    // No name chosen yet: the placeholder.
    expect(togetherWhoLabel(TogetherWho.us, 'Kofi'), 'Couples');
  });

  testWidgets(
    "a partner's busy block reads Busy, names no one, and can't be opened",
    (t) async {
      var tapped = false;
      await _pump(
        t,
        TogetherItemRow(
          item: _event(
            who: ['kofi'],
            createdBy: 'kofi',
            visibility: TogetherVisibility.busyOnly,
            title: 'Busy',
          ),
          me: 'ama',
          partnerName: 'Kofi',
          onTap: () => tapped = true,
        ),
      );
      expect(find.text('Busy'), findsOneWidget);
      expect(find.textContaining('Kofi'), findsNothing);
      await t.tap(find.text('Busy'));
      expect(tapped, isFalse);
    },
  );

  test('isMaskedFor: only a busy block someone else made', () {
    final busy = _event(
      who: ['kofi'],
      createdBy: 'kofi',
      visibility: TogetherVisibility.busyOnly,
    );
    expect(busy.isMaskedFor('ama'), isTrue);
    expect(busy.isMaskedFor('kofi'), isFalse);
    expect(_event().isMaskedFor('ama'), isFalse);
  });
}

// Spec 1 W5 final review I-2 (F-4 ruling) and M-2 (ruling, re-graded):
// About us's anniversary reminder opens the ordinary reminder form in a
// locked mode (its date, title, type and repeat follow About us, as the
// P-6 guard does; its lead times and note stay the couple's and save on
// their own), also offline, so the couple can always open their own
// reminder; and AU6 says About us won't add another beside a yearly
// anniversary reminder the couple made by hand (ruling "M-2 replaced").
import 'dart:io';

import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/data/repositories/reminders_repository.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';

const _uid = 'u-times';
const _locked = 'Its date, title and type follow About us.';
const _times = 'Reminder times and note';
const _uses =
    "You already have an anniversary reminder, so we won't add another.";

class _Repo implements RemindersRepository {
  _Repo([this.listed = const []]);

  final List<ReminderModel> listed;
  final updates = <Map<String, Object?>>[];
  final deleted = <String>[];

  @override
  Future<ReminderModel> updateReminder({
    required String id,
    String? reminderType,
    String? title,
    String? note,
    bool clearNote = false,
    DateTime? remindAt,
    String? recurrence,
    String? familyMemberId,
    List<int>? remindDaysBefore,
  }) async {
    updates.add({
      'id': id,
      'reminderType': reminderType,
      'title': title,
      'note': note,
      'clearNote': clearNote,
      'remindAt': remindAt,
      'recurrence': recurrence,
      'familyMemberId': familyMemberId,
      'remindDaysBefore': remindDaysBefore,
    });
    return _reminder();
  }

  @override
  Future<void> deleteReminder(String id) async => deleted.add(id);

  @override
  Future<List<ReminderModel>> listReminders(String relationshipId) async =>
      listed;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReminderModel _reminder({
  String id = 'rem-about-us',
  String type = 'anniversary',
  String title = 'Anniversary',
  String recurrence = 'yearly',
}) => ReminderModel(
  id: id,
  relationshipId: 'r1',
  createdBy: _uid,
  reminderType: type,
  title: title,
  note: 'Book the jollof place',
  remindAt: DateTime(2027, 3, 12),
  recurrence: recurrence,
  sent: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Map<String, dynamic> _followed() => aboutUsJson(
  togetherSince: '2016-03-12',
  precision: 'day',
  anniversary: 'together_since',
  reminderId: 'rem-about-us',
);

List<Override> _overrides(FakeCoupleProfileServer server, _Repo repo) => [
  coupleProfileEnabledProvider.overrideWithValue(true),
  coupleProfileRpcProvider.overrideWithValue(server.rpc),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
  togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
  coupleNameProvider.overrideWith((ref, id) async => null),
  remindersRepositoryProvider.overrideWithValue(repo),
];

/// Opens [reminder] the way Together, the calendar and the Timeline do.
Future<void> _open(
  WidgetTester tester,
  FakeCoupleProfileServer server,
  _Repo repo, {
  ReminderModel? reminder,
}) async {
  final r = reminder ?? _reminder();
  await pumpFlowScreen(
    tester,
    () => Scaffold(
      body: Builder(
        builder:
            (context) => TextButton(
              onPressed: () => showReminderSheet(context, reminder: r),
              child: const Text('open'),
            ),
      ),
    ),
    overrides: _overrides(server, repo),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  final form = find.descendant(
    of: find.byType(AddEditReminderScreen),
    matching: find.byType(Scrollable),
  );
  if (finder.evaluate().isEmpty && form.evaluate().isNotEmpty) {
    // The form is a lazy list: scroll back up for its header's Save. By
    // position, not a drag: at large text the drag's centre can miss.
    final position = tester.state<ScrollableState>(form.first).position;
    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tapInReach(tester, finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('I-2: "Reminder times and note" opens the form locked; a new '
      'lead time saves alone', (tester) async {
    final server = FakeCoupleProfileServer(profiles: {'r1': _followed()});
    final repo = _Repo();
    await _open(tester, server, repo);
    expect(find.text('This reminder follows About us'), findsOneWidget);
    await _tapVisible(tester, find.text(_times));

    expect(find.byType(AddEditReminderScreen), findsOneWidget);
    expect(find.text(_locked), findsOneWidget);
    await _tapVisible(tester, find.text('1 week before'));
    await _tapVisible(tester, find.text('Save'));

    expect(repo.updates, hasLength(1));
    final sent = repo.updates.single;
    expect(sent['id'], 'rem-about-us');
    expect(sent['remindDaysBefore'], [0, 3, 7]);
    expect(sent['note'], 'Book the jollof place');
    // The guard's fields are never sent from here.
    expect(sent['title'], isNull);
    expect(sent['reminderType'], isNull);
    expect(sent['remindAt'], isNull);
    expect(sent['recurrence'], isNull);
    expect(find.byType(AddEditReminderScreen), findsNothing, reason: 'saved');
  });

  testWidgets('I-2: the note can change and saves', (tester) async {
    final server = FakeCoupleProfileServer(profiles: {'r1': _followed()});
    final repo = _Repo();
    await _open(tester, server, repo);
    await _tapVisible(tester, find.text(_times));
    await tester.enterText(
      find.widgetWithText(TextField, 'Book the jollof place'),
      'Flowers',
    );
    await _tapVisible(tester, find.text('Save'));
    expect(repo.updates.single['note'], 'Flowers');
    expect(repo.updates.single['remindDaysBefore'], [0, 3]);
  });

  testWidgets('I-2: the date, title, type and repeat can\'t be changed, and '
      'it can\'t be deleted here', (tester) async {
    final server = FakeCoupleProfileServer(profiles: {'r1': _followed()});
    final repo = _Repo();
    await _open(tester, server, repo);
    await _tapVisible(tester, find.text(_times));

    await _tapVisible(tester, find.text('Date'));
    expect(find.byType(CupertinoDatePicker), findsNothing);

    final title = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Anniversary'),
    );
    expect(title.readOnly, isTrue);
    final types = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(types.onSelectionChanged, isNull);
    expect(find.text('Repeats every year'), findsNothing);
    expect(find.text('Delete reminder'), findsNothing);

    await _tapVisible(tester, find.text('Save'));
    expect(repo.updates.single['remindAt'], isNull);
    expect(repo.deleted, isEmpty);
  });

  testWidgets('I-2: the ordinary form is unchanged for any other reminder', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer(profiles: {'r1': _followed()});
    final repo = _Repo();
    await _open(
      tester,
      server,
      repo,
      reminder: _reminder(id: 'rem-other', type: 'birthday', title: 'Mum'),
    );
    expect(find.byType(AddEditReminderScreen), findsOneWidget);
    expect(find.text(_locked), findsNothing);
    expect(find.text('Repeats every year'), findsOneWidget);
    await _tapVisible(tester, find.text('Date'));
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  });

  testWidgets('M-2: offline, the couple can still open their reminder '
      '(locked: nothing About us keeps can change)', (tester) async {
    final server = FakeCoupleProfileServer(profiles: {'r1': _followed()})
      ..failNext = const SocketException('offline');
    final repo = _Repo();
    await _open(
      tester,
      server,
      repo,
      reminder: _reminder(id: 'rem-own', title: 'Our day'),
    );
    expect(
      find.text(
        "We couldn't check this reminder. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    await _tapVisible(tester, find.text(_times));
    expect(find.byType(AddEditReminderScreen), findsOneWidget);
    expect(find.text('Our day'), findsOneWidget);
    expect(find.text('Book the jollof place'), findsOneWidget);
    expect(find.text(_locked), findsOneWidget);
  });

  group('M-2: AU6 says it won\'t add another beside the couple\'s own', () {
    Future<void> au6(
      WidgetTester tester,
      Map<String, dynamic> profile,
      List<ReminderModel> listed,
    ) async {
      final server = FakeCoupleProfileServer(profiles: {'r1': profile});
      await pumpFlowScreen(
        tester,
        () => AboutUsQuestionFlow(
          target: const AboutUsTarget.shared('r1'),
          only: AboutUsQuestion.anniversary,
          now: () => DateTime(2026, 11, 2, 10),
          onDone: () {},
        ),
        overrides: _overrides(server, _Repo(listed)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remember your anniversary?'), findsOneWidget);
    }

    testWidgets('a hand-made anniversary reminder: said', (tester) async {
      await au6(tester, aboutUsJson(), [
        _reminder(id: 'rem-own', title: 'Our day'),
      ]);
      expect(find.text(_uses), findsOneWidget);
    });

    testWidgets('a hand-made one-off: nothing said (About us adds its own)', (
      tester,
    ) async {
      await au6(tester, aboutUsJson(), [
        _reminder(id: 'rem-once', title: 'Dinner', recurrence: 'none'),
      ]);
      expect(find.text(_uses), findsNothing);
    });

    testWidgets('none, or only other types: nothing said', (tester) async {
      await au6(tester, aboutUsJson(), [
        _reminder(id: 'rem-mum', type: 'birthday', title: 'Mum'),
      ]);
      expect(find.text(_uses), findsNothing);
    });

    testWidgets('About us already keeps one: nothing said', (tester) async {
      await au6(tester, _followed(), [_reminder()]);
      expect(find.text(_uses), findsNothing);
    });
  });
}

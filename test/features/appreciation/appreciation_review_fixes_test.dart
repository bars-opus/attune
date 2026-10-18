// Spec 7 final review M-8, M-9, M-11.
import 'package:attune/features/appreciation/data/appreciation_service.dart';
import 'package:attune/features/appreciation/presentation/appreciation_jar_screen.dart';
import 'package:attune/features/appreciation/presentation/appreciation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fake extends AppreciationService {
  _Fake(this.notes);
  List<JarNote> notes;
  final calls = <String>[];
  bool failRemove = false;

  @override
  Future<List<JarNote>> jar() async => notes;

  @override
  Future<void> save(String messageId) async => calls.add('save:$messageId');

  @override
  Future<void> remove(String messageId) async {
    calls.add('remove:$messageId');
    if (failRemove) throw StateError('offline');
    notes = notes.where((n) => n.messageId != messageId).toList();
  }
}

Widget _app(Widget home, _Fake fake) => ProviderScope(
  overrides: [
    appreciationServiceProvider.overrideWithValue(fake),
    appreciationEnabledProvider.overrideWith((ref) async => true),
  ],
  child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: home)),
);

final _note = JarNote(messageId: 'm1', relationshipId: 'r1', content: 'I noticed you made tea. Thank you.', sentAt: DateTime.utc(2026, 10, 1));

void main() {
  test('the server counts code points; a grapheme can be several (M-8)', () {
    expect(composeAppreciation('👨‍👩‍👧' * 60, thankful: false), isNull);
    expect(composeAppreciation('👨‍👩‍👧' * 50, thankful: false), isNotNull);
  });

  testWidgets('the field says what it is for (M-8)', (t) async {
    await t.pumpWidget(_app(const Scaffold(body: AppreciationSheet(relationshipId: 'r1', offerThankful: false)), _Fake([])));
    expect(t.widget<TextField>(find.byType(TextField)).decoration?.labelText, 'What you noticed');
  });

  testWidgets('removing offers an undo that keeps it again (M-9, M-11)', (t) async {
    final fake = _Fake([_note]);
    await t.pumpWidget(_app(const AppreciationJarScreen(), fake));
    await t.pumpAndSettle();
    expect(find.text('Your appreciation jar'), findsOneWidget);
    await t.tap(find.byTooltip('Remove from my jar'));
    await t.pumpAndSettle();
    expect(find.text('Removed from your jar'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(fake.calls, ['remove:m1', 'save:m1']);
  });

  testWidgets('a failed remove says so and keeps the note (M-9)', (t) async {
    final fake = _Fake([_note])..failRemove = true;
    await t.pumpWidget(_app(const AppreciationJarScreen(), fake));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Remove from my jar'));
    await t.pumpAndSettle();
    expect(find.text("Couldn't remove it. Try again."), findsOneWidget);
    expect(find.text('I noticed you made tea. Thank you.'), findsOneWidget);
  });
}

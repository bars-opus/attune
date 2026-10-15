import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/features/reminders/data/models/family_member_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/family_members_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

FamilyMemberModel _member(String id, String name) => FamilyMemberModel(
  id: id,
  relationshipId: 'r1',
  name: name,
  birthday: DateTime(2019, 4, 2),
  createdBy: 'ama',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<void> _open(WidgetTester t, List<FamilyMemberModel> members) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [familyMembersListProvider.overrideWith((ref) async => members)],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (c) => TextButton(onPressed: () => showFamilySheet(c), child: const Text('open')),
                ),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('family opens as a sheet: title, divider, Add on top, members below, no floating button', (t) async {
    await _open(t, [_member('m1', 'Kwame'), _member('m2', 'Abena')]);
    expect(find.text('Family'), findsOneWidget);
    expect(find.byType(AppDivider), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
    final add = find.text('Add family member');
    expect(add, findsOneWidget);
    // Add stays above the list, however long it grows.
    expect(t.getTopLeft(add).dy, lessThan(t.getTopLeft(find.text('Kwame')).dy));
    // Breathing room between Add and the first member.
    final addBottom = t.getBottomLeft(find.ancestor(of: add, matching: find.byWidgetPredicate((w) => w is TextButton))).dy;
    final firstRowTop = t.getTopLeft(find.ancestor(of: find.text('Kwame'), matching: find.byType(InfoRowWidget))).dy;
    expect(firstRowTop - addBottom, greaterThanOrEqualTo(16));
    expect(t.getTopLeft(find.text('Kwame')).dy, lessThan(t.getTopLeft(find.text('Abena')).dy));
  });

  testWidgets('with nobody yet, Add is still at the top, over the empty note', (t) async {
    await _open(t, const []);
    expect(t.getTopLeft(find.text('Add family member')).dy, lessThan(t.getTopLeft(find.text('No family members yet')).dy));
  });

  testWidgets('Add opens the member sheet', (t) async {
    await _open(t, const []);
    await t.tap(find.text('Add family member'));
    await t.pumpAndSettle();
    expect(find.text('Add a member'), findsOneWidget);
  });
}

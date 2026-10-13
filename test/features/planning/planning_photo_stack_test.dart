import 'dart:typed_data';

import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/core/widgets/media/stacked_media_cards.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/photo_block_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart' show withScreenUtil;
import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';
import '../../helpers/media_counter.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');
const _p = 'r1/e1';

FakePlanningGateway _gateway(List<String> paths) => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 'ph', type: 'photo', payload: {'title': 'Beach', 'paths': paths}),
          ]),
    });

Widget _app(FakePlanningGateway g, {PlanningPhotoPicker? picker}) => ProviderScope(
      overrides: [...planningOverrides(g), if (picker != null) planningPhotoPickerProvider.overrideWithValue(picker)],
      child: withScreenUtil(const MaterialApp(home: _screen)),
    );

void main() {
  testWidgets("a block's photos are one stack, like chat: counter, swipe, tap to open", (tester) async {
    await tester.pumpWidget(_app(_gateway(['$_p/a.jpg', '$_p/b.jpg', '$_p/c.jpg'])));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(tester.widget<StackedMediaCards>(find.byType(StackedMediaCards)).itemCount, 3);
    expect(tester.widget<StackedMediaCards>(find.byType(StackedMediaCards)).peekBehind, isTrue,
        reason: 'the other photos show beneath the front one');
    expect(mediaCounter('1 / 3'), findsOneWidget);
    await tester.drag(find.byType(StackedMediaCards), const Offset(-230, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(StackedMediaCards));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget, reason: 'the viewer opens on the front photo');
  });

  testWidgets('one photo is a single card', (tester) async {
    await tester.pumpWidget(_app(_gateway(['$_p/a.jpg'])));
    await tester.pumpAndSettle();
    expect(tester.widget<StackedMediaCards>(find.byType(StackedMediaCards)).itemCount, 1);
    expect(mediaCounter(), findsNothing);
  });

  testWidgets('several photos picked at once are all added, up to what the block has room for', (tester) async {
    final g = _gateway(['$_p/a.jpg']);
    final paths = <String>['$_p/a.jpg'];
    g.handlers['add_planning_photo'] = (p) {
      paths.add(p['p_path'] as String);
      return fakeBlockJson(id: 'ph', type: 'photo', payload: {'title': 'Beach', 'paths': [...paths]}, version: paths.length);
    };
    int? askedFor;
    await tester.pumpWidget(_app(g, picker: (source, limit) async {
      askedFor = limit;
      return (photos: [for (var i = 0; i < 3; i++) Uint8List.fromList([0xff, 0xd8, i])], rejected: 0);
    }));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Beach'), const Offset(0, -300)); // the button clear of the ribbon
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from library'));
    await tester.pumpAndSettle();
    expect(askedFor, 9, reason: 'ten a block, one already there');
    expect(g.callsTo('add_planning_photo'), hasLength(3));
    expect(mediaCounter('1 / 4'), findsOneWidget);
  });

  testWidgets('photos that cannot be used are left out and the person is told', (tester) async {
    final g = _gateway([]);
    g.handlers['add_planning_photo'] =
        (p) => fakeBlockJson(id: 'ph', type: 'photo', payload: {'paths': [p['p_path']]}, version: 2);
    await tester.pumpWidget(_app(g, picker: (source, limit) async => (photos: [Uint8List.fromList([0xff])], rejected: 2)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from library'));
    await tester.pumpAndSettle();
    expect(g.callsTo('add_planning_photo'), hasLength(1));
    expect(find.text("2 photos couldn't be used. Try JPEG or PNG."), findsOneWidget);
  });


  testWidgets('the photo block sits in the note, not in a card; its menu is in its heading row', (tester) async {
    await tester.pumpWidget(_app(_gateway(['$_p/a.jpg', '$_p/b.jpg'])));
    await tester.pumpAndSettle();
    final block = find.byType(PhotoBlockView);
    expect(find.ancestor(of: block, matching: find.byType(CardInkWell)), findsNothing);
    expect(find.ancestor(of: block, matching: find.byType(Dismissible)), findsNothing,
        reason: 'no block swipe fighting the photo swipe');
    expect(find.descendant(of: block, matching: find.byTooltip('Options for Beach')), findsOneWidget);
  });
}

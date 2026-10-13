import 'package:attune/features/planning/domain/youtube_link.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/link_block_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart' show withScreenUtil;
import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

void main() {
  group('planningYouTubeId', () {
    test('reads the id from every shape of YouTube link', () {
      const id = 'wmZtslmSqfk';
      for (final u in [
        'https://youtu.be/$id',
        'https://youtu.be/$id?si=AbCdEf123',
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?feature=share&v=$id&t=42s',
        'https://m.youtube.com/watch?v=$id',
        'https://music.youtube.com/watch?v=$id&list=RD',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/embed/$id',
        'https://www.youtube.com/live/$id?feature=shared',
        'https://www.youtube-nocookie.com/embed/$id',
      ]) {
        expect(planningYouTubeId(u), id, reason: u);
      }
    });

    test('anything else is not a YouTube video', () {
      for (final u in [
        'https://www.youtube.com/',
        'https://www.youtube.com/@channel',
        'https://www.youtube.com/watch?v=short',
        'https://youtube.com.evil.example/watch?v=wmZtslmSqfk',
        'https://notyoutube.com/watch?v=wmZtslmSqfk',
        'https://villa.example/ubud',
        'nonsense',
      ]) {
        expect(planningYouTubeId(u), isNull, reason: u);
      }
    });
  });

  FakePlanningGateway gateway(String url, {Map<String, dynamic>? preview}) => FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
              fakeBlockJson(id: 'ln', type: 'link', payload: {'url': url, if (preview != null) 'preview': preview}),
            ]),
      });

  final played = <String>[];
  Widget app(FakePlanningGateway g) => ProviderScope(
        overrides: [
          ...planningOverrides(g),
          // The real player is a web view; widget tests stand in for it.
          planningYouTubePlayerProvider.overrideWithValue((id) {
            played.add(id);
            return Text('player $id');
          }),
        ],
        child: withScreenUtil(const MaterialApp(home: _screen)),
      );

  testWidgets('a YouTube link shows its thumbnail and a play button; the player loads only when tapped', (tester) async {
    final semantics = tester.ensureSemantics();
    played.clear();
    await tester.pumpWidget(app(gateway('https://youtu.be/wmZtslmSqfk', preview: {
      'status': 'ok',
      'title': 'The Beast System',
      'description': 'Grace For Purpose',
      'host': 'youtu.be',
    })));
    await tester.pumpAndSettle();
    final link = find.byType(LinkBlockView);
    expect(find.descendant(of: link, matching: find.byIcon(Icons.play_arrow_rounded)), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Play video')), findsOneWidget, reason: 'announced as a button');
    expect(find.text('The Beast System'), findsOneWidget);
    expect(played, isEmpty, reason: 'no web view until the person asks for it');

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(played, ['wmZtslmSqfk']);
    expect(find.text('player wmZtslmSqfk'), findsOneWidget);
    expect(find.descendant(of: link, matching: find.byIcon(Icons.play_arrow_rounded)), findsNothing);
    expect(find.text('The Beast System'), findsOneWidget, reason: 'its title stays under the player');
    semantics.dispose();
  });

  testWidgets('a YouTube link plays before the server preview arrives', (tester) async {
    final semantics = tester.ensureSemantics();
    played.clear();
    await tester.pumpWidget(app(gateway('https://www.youtube.com/watch?v=wmZtslmSqfk')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Play video')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(played, ['wmZtslmSqfk']);
    semantics.dispose();
  });

  testWidgets('other links keep their preview card, with no player', (tester) async {
    final semantics = tester.ensureSemantics();
    played.clear();
    await tester.pumpWidget(app(gateway('https://villa.example/ubud',
        preview: {'status': 'ok', 'title': 'Ubud villa', 'host': 'villa.example'})));
    await tester.pumpAndSettle();
    expect(find.text('Ubud villa'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Play video')), findsNothing);
    semantics.dispose();
  });

  group('the inline player setup', () {
    test("loads from YouTube's privacy-enhanced domain (the default origin gets error 152-4)", () {
      expect(planningYouTubePlayerParams.origin, 'https://www.youtube-nocookie.com');
      expect(planningYouTubePlayerParams.playsInline, isTrue);
    });

    test('names its JavaScript channel safely: about 1 in 6 video ids contain a hyphen', () {
      for (final id in ['CXIkTuW-y3Q', 'wmZtslmSqfk', '-a_b-c_d-e_']) {
        final channel = 'Youtube${planningYouTubePlayerKey(id)}';
        expect(RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(channel), isTrue, reason: '$id -> $channel');
      }
      expect(planningYouTubePlayerKey('CXIkTuW-y3Q'), isNot(planningYouTubePlayerKey('CXIkTuW_y3Q')),
          reason: 'two different videos never share a channel');
    });
  });

  testWidgets("a YouTube video spans the note's width; its ⋮ menu sits at the end of the Open in YouTube row",
      (tester) async {
    await tester.pumpWidget(app(gateway('https://youtu.be/wmZtslmSqfk')));
    await tester.pumpAndSettle();
    final link = find.byType(LinkBlockView);
    final menu = find.descendant(
        of: link, matching: find.byWidgetPredicate((w) => w is PopupMenuButton && (w.tooltip ?? '').startsWith('Options for')));
    expect(menu, findsOneWidget, reason: 'the menu is part of the video block now');
    final video = tester.getRect(find.descendant(of: link, matching: find.byType(AspectRatio)).first);
    expect(video.width, moreOrLessEquals(tester.getSize(link).width), reason: 'full width, no menu column beside it');
    final open = tester.getRect(find.text('Open in YouTube'));
    final menuRect = tester.getRect(menu);
    expect(menuRect.top, greaterThan(video.bottom), reason: 'below the video');
    expect(menuRect.left, greaterThan(open.right), reason: 'after Open in YouTube');
    expect(menuRect.center.dy, moreOrLessEquals(open.center.dy, epsilon: 2), reason: 'on the same line');
  });

  Finder menuIn(Finder block) => find.descendant(
      of: block, matching: find.byWidgetPredicate((w) => w is PopupMenuButton && (w.tooltip ?? '').startsWith('Options for')));

  testWidgets("any link's preview spans the note; its ⋮ menu sits at the end of the address row", (tester) async {
    await tester.pumpWidget(app(gateway('https://villa.example/ubud',
        preview: {'status': 'ok', 'title': 'Ubud villa', 'description': 'Pool and rice fields', 'host': 'villa.example'})));
    await tester.pumpAndSettle();
    final link = find.byType(LinkBlockView);
    final menu = menuIn(link);
    expect(menu, findsOneWidget, reason: 'the menu is part of the link block');
    final card = find.ancestor(of: find.text('Ubud villa'), matching: find.byType(InkWell)).first;
    expect(tester.getSize(card).width, moreOrLessEquals(tester.getSize(link).width),
        reason: 'the preview spans the block, with no menu column beside it');
    final host = tester.getRect(find.text('villa.example'));
    final menuRect = tester.getRect(menu);
    expect(menuRect.left, greaterThan(host.right));
    expect(menuRect.center.dy, moreOrLessEquals(host.center.dy, epsilon: 4), reason: 'on the address row');
    expect(menuRect.top, greaterThanOrEqualTo(tester.getRect(find.text('Pool and rice fields')).bottom),
        reason: 'below the preview, not beside it');
  });

  testWidgets('a link with no preview yet keeps its menu on the address row too', (tester) async {
    await tester.pumpWidget(app(gateway('https://plain.example/x')));
    await tester.pumpAndSettle();
    final menu = menuIn(find.byType(LinkBlockView));
    expect(menu, findsOneWidget);
    expect(tester.getRect(menu).left, greaterThan(tester.getRect(find.text('plain.example')).right));
  });

  testWidgets("a template's empty link keeps its menu on the Add link row", (tester) async {
    await tester.pumpWidget(app(FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 'ln', type: 'link', payload: {'label': 'Places to stay'}),
          ]),
    })));
    await tester.pumpAndSettle();
    final menu = menuIn(find.byType(LinkBlockView));
    expect(menu, findsOneWidget);
    expect(tester.getRect(menu).center.dy, moreOrLessEquals(tester.getRect(find.text('Add link')).center.dy, epsilon: 4));
  });
}

// K1 (03 H1, 07a V10): on my own ring the photo opens my reel and only the
// `+` opens the camera. The `+` keeps a 48 dp target, hung outside the
// photo; inside the photo circle the reel wins except right on the badge.
//
// Geometry in dp from the ring's leading top corner (the ring is 69 dp: a
// 56 dp photo, 3 dp gap, 3.5 dp stroke): photo centre (34.5, 34.5), radius
// 28; badge centre (59, 59), drawn 20 dp, slop 14 dp; the badge's 48 dp
// target spans 35..83 on both axes. Literals on purpose: this file compiles
// and fails against the old layout.
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> _pumpMine(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
  double? pendingProgress,
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(40),
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: StoryRing(
                isMine: true,
                hasStories: true,
                segmentCount: 3,
                unviewedCount: 3,
                pendingProgress: pendingProgress,
                onTap: () => taps.add('reel'),
                onTapPlus: () => taps.add('camera'),
                semanticLabel: 'Your story, 3 items',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return taps;
}

/// Who must own a tap at [p] (leading-corner coordinates), or null within
/// about a dp of a boundary, where either answer is acceptable.
String? _owner(Offset p) {
  const photo = Offset(34.5, 34.5);
  const badge = Offset(59, 59);
  final toPhoto = (p - photo).distance;
  final toBadge = (p - badge).distance;
  final inTarget = p.dx > 36 && p.dx < 82 && p.dy > 36 && p.dy < 82;
  if (toBadge < 13) return 'camera';
  if (toPhoto < 27 && toBadge > 15) return 'reel';
  if (inTarget && toPhoto > 29) return 'camera';
  if (p.dx < 68 && p.dy < 68 && (p.dx < 34 || p.dy < 34)) return 'reel';
  return null;
}

Future<void> _expectEveryTapOwned(
  WidgetTester tester,
  List<String> taps,
  TextDirection direction,
) async {
  final rect = tester.getRect(find.byType(StoryRing));
  final rtl = direction == TextDirection.rtl;
  final wrong = <String>[];
  var reel = 0;
  var camera = 0;
  for (var y = 1.0; y < 83; y += 3) {
    for (var x = 1.0; x < 83; x += 3) {
      final want = _owner(Offset(x, y));
      if (want == null) continue;
      taps.clear();
      final at =
          rtl
              ? Offset(rect.right - x, rect.top + y)
              : Offset(rect.left + x, rect.top + y);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 1));
      final got = taps.isEmpty ? 'nothing' : taps.join(',');
      if (got != want) wrong.add('($x, $y): wanted $want, got $got');
      if (want == 'reel') {
        reel++;
      } else {
        camera++;
      }
    }
  }
  expect(wrong, isEmpty, reason: wrong.take(12).join('\n'));
  expect(reel, greaterThan(100));
  expect(camera, greaterThan(40));
}

void main() {
  testWidgets('a tap in the middle of my photo opens my reel, not the camera', (
    tester,
  ) async {
    final taps = await _pumpMine(tester);
    await tester.tapAt(
      tester.getTopLeft(find.byType(StoryRing)) + const Offset(34.5, 34.5),
    );
    expect(taps, ['reel']);
  });

  testWidgets('a tap on the drawn + opens the camera', (tester) async {
    final taps = await _pumpMine(tester);
    await tester.tapAt(
      tester.getTopLeft(find.byType(StoryRing)) + const Offset(59, 59),
    );
    expect(taps, ['camera']);
  });

  testWidgets('every tap on my ring reaches exactly the control under it', (
    tester,
  ) async {
    final taps = await _pumpMine(tester);
    await _expectEveryTapOwned(tester, taps, TextDirection.ltr);
  });

  testWidgets('right to left, the + and its target mirror (Review Focus 3)', (
    tester,
  ) async {
    final taps = await _pumpMine(tester, direction: TextDirection.rtl);
    await _expectEveryTapOwned(tester, taps, TextDirection.rtl);
  });

  testWidgets('the posting ring routes taps the same way (Review Focus 3)', (
    tester,
  ) async {
    final taps = await _pumpMine(tester, pendingProgress: 0.4);
    await _expectEveryTapOwned(tester, taps, TextDirection.ltr);
  });

  testWidgets('the + and the ring are separate buttons; the + is 48 dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpMine(tester);
    final plus = tester.getSemantics(
      find.bySemanticsLabel('Add to your story'),
    );
    final ring = tester.getSemantics(
      find.bySemanticsLabel('Your story, 3 items'),
    );
    expect(plus.rect.size, const Size(48, 48));
    expect(ring.rect.size, const Size(69, 69));
    expect(plus.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(ring.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}

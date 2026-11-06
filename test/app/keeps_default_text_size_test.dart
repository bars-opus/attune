// Spec 1 W10a (batch 6 review I-3): screens pushed with Navigator.push
// outside GoRouter take the scale of the GoRouter page below them, so the
// ones nobody has audited yet keep 1.0 at their own root through
// KeepsDefaultTextSize. Remove a screen from this list when it is audited.
import 'dart:io';

import 'package:attune/app/text_scale_policy.dart';
import 'package:attune/features/stories/data/past_story_chapters_repository.dart';
import 'package:attune/features/stories/presentation/screens/past_chapter_stories_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pushed pagelessly and not audited: class -> its file.
const _keptAtDefault = {
  'StoryReelScreen':
      'lib/features/stories/presentation/screens/story_reel_screen.dart',
  'StoryCameraScreen':
      'lib/features/stories/presentation/screens/story_camera_screen.dart',
  'CoupleMapScreen':
      'lib/features/couple_map/presentation/screens/couple_map_screen.dart',
  'PastChapterStoriesScreen':
      'lib/features/stories/presentation/screens/past_chapter_stories_screen.dart',
};

class _NoChapters implements PastStoryChaptersGateway {
  @override
  Future<List<PastStoryChapter>> listChapters() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('each unaudited pageless screen builds inside KeepsDefaultTextSize', () {
    for (final MapEntry(key: name, value: path) in _keptAtDefault.entries) {
      final src = File(path).readAsStringSync();
      final at = src.indexOf(RegExp('^class $name\\b', multiLine: true));
      expect(at, isNonNegative, reason: name);
      // The class itself, or its State, up to the next top-level class.
      final state = src.indexOf(
        RegExp('^class _${name}State\\b', multiLine: true),
      );
      final from = state >= 0 ? state : at;
      final next = src.indexOf(RegExp(r'^class ', multiLine: true), from + 1);
      final body = src.substring(from, next < 0 ? src.length : next);
      expect(body, contains('KeepsDefaultTextSize('), reason: name);
    }
  });

  testWidgets('KeepsDefaultTextSize: 1.0 under a 2.0 phone', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearAllTestValues);
    await t.pumpWidget(
      const MaterialApp(
        home: KeepsDefaultTextSize(child: Scaffold(body: Text('kept'))),
      ),
    );
    expect(
      MediaQuery.textScalerOf(t.element(find.text('kept'))).scale(10) / 10,
      1.0,
    );
  });

  testWidgets('past-chapter stories stays at 1.0 under a 2.0 phone', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearAllTestValues);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          pastStoryChaptersGatewayProvider.overrideWithValue(_NoChapters()),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => const MaterialApp(home: PastChapterStoriesScreen()),
        ),
      ),
    );
    await t.pumpAndSettle();
    final intro = find.text(PastChapterStoriesScreen.intro);
    expect(intro, findsOneWidget);
    expect(MediaQuery.textScalerOf(t.element(intro)).scale(10) / 10, 1.0);
  });
}

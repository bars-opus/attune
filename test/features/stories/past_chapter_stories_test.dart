// test/features/stories/past_chapter_stories_test.dart
// Stories Wave 5 (05 #3): after an ending, an author finds their own stories
// on Download my data and can delete them, all at once or one by one.
import 'dart:async';

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/data_export/data/data_export_service.dart';
import 'package:attune/features/data_export/presentation/data_export_screen.dart';
import 'package:attune/features/stories/data/past_story_chapters_repository.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/presentation/screens/past_chapter_stories_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

final _ended = DateTime(2026, 9, 12);

class _Gateway implements PastStoryChaptersGateway {
  _Gateway(this.items);
  List<PastStoryItem> items;
  final deletedOne = <String>[];
  final remainingScript = <int>[];
  int deleteAllCalls = 0;
  bool canDownload = true;
  Object? deleteAllError;

  /// When set, deletes wait for it (progress and leave-mid-delete tests).
  Completer<void>? gate;

  @override
  Future<List<PastStoryChapter>> listChapters() async =>
      items.isEmpty
          ? const []
          : [
            PastStoryChapter(
              relationshipId: 'r-old',
              status: 'ended',
              endedAt: _ended,
              storyCount: items.length,
              firstOn: items.first.occurredOn,
              lastOn: items.last.occurredOn,
              canDownload: canDownload,
            ),
          ];

  @override
  Future<List<PastStoryItem>> listItems(
    String relationshipId, {
    PastStoryItem? after,
    int limit = 50,
  }) async => after == null ? List.of(items) : const [];

  @override
  Future<int> deleteAllOnce(String relationshipId) async {
    deleteAllCalls++;
    await gate?.future;
    if (deleteAllError != null) throw deleteAllError!;
    final left = remainingScript.isEmpty ? 0 : remainingScript.removeAt(0);
    if (left == 0) items = [];
    return left;
  }

  @override
  Future<void> deleteOne(String storyItemId) async {
    await gate?.future;
    deletedOne.add(storyItemId);
    items = items.where((i) => i.id != storyItemId).toList();
  }
}

PastStoryItem _item(String id, String type, DateTime on) =>
    PastStoryItem(id: id, mediaType: type, occurredOn: on, createdAt: on);

class _NoExport extends DataExportService {
  @override
  Future<DataExportStatus?> latest() async => null;
}

Future<void> _pump(
  WidgetTester t,
  Widget home, {
  PastStoryChaptersGateway? gateway,
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        dataExportServiceProvider.overrideWithValue(_NoExport()),
        if (gateway != null)
          pastStoryChaptersGatewayProvider.overrideWithValue(gateway),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: home),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  final photo = _item('s1', 'image', DateTime(2026, 3, 1));
  final video = _item('s2', 'video', DateTime(2026, 8, 30));

  testWidgets(
    'Download my data shows the entry only when there are past stories',
    (t) async {
      await _pump(
        t,
        DataExportScreen(confirmPin: (_) async => true),
        gateway: _Gateway([]),
      );
      expect(find.text('Your stories from past chapters'), findsNothing);
      await _pump(
        t,
        DataExportScreen(confirmPin: (_) async => true),
        gateway: _Gateway([photo, video]),
      );
      expect(find.text('Your stories from past chapters'), findsOneWidget);
      expect(
        find.text('2 stories only you can see and delete'),
        findsOneWidget,
      );
    },
  );

  testWidgets('with no backend the entry stays out of the way', (t) async {
    await _pump(t, DataExportScreen(confirmPin: (_) async => true));
    expect(find.text('Your stories from past chapters'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'the screen names the chapter and lists each story by date and kind',
    (t) async {
      await _pump(
        t,
        const PastChapterStoriesScreen(),
        gateway: _Gateway([photo, video]),
      );
      expect(
        find.text(
          pastStoryChapterTitle(
            PastStoryChapter(
              relationshipId: 'r-old',
              status: 'ended',
              endedAt: _ended,
              storyCount: 2,
              firstOn: photo.occurredOn,
              lastOn: video.occurredOn,
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(MyDateFormat.toDate(_ended)), findsOneWidget);
      await t.tap(find.text('See them'));
      await t.pumpAndSettle();
      expect(
        find.text(
          MyDateFormat.join([MyDateFormat.toDate(photo.occurredOn), 'Photo']),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          MyDateFormat.join([MyDateFormat.toDate(video.occurredOn), 'Video']),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Delete all asks first, then deletes in batches until none is left',
    (t) async {
      final g = _Gateway([photo, video])..remainingScript.addAll([1, 0]);
      await _pump(t, const PastChapterStoriesScreen(), gateway: g);
      await t.tap(find.text('Delete all 2'));
      await t.pumpAndSettle();
      expect(find.text('Delete these stories?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(g.deleteAllCalls, 0);
      await t.tap(find.text('Delete all 2'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(g.deleteAllCalls, 2);
      expect(find.text('Deleted.'), findsOneWidget);
      expect(find.text('Delete all 2'), findsNothing);
    },
  );

  testWidgets('one story can be deleted on its own', (t) async {
    final g = _Gateway([photo, video]);
    await _pump(t, const PastChapterStoriesScreen(), gateway: g);
    await t.tap(find.text('See them'));
    await t.pumpAndSettle();
    await t.tap(
      find.byTooltip(
        'Delete the photo from ${MyDateFormat.toDate(photo.occurredOn)}',
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Delete this story?'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(g.deletedOne, ['s1']);
    expect(
      find.text(
        MyDateFormat.join([MyDateFormat.toDate(photo.occurredOn), 'Photo']),
      ),
      findsNothing,
    );
  });

  testWidgets('every control is a 48 dp target with a label', (t) async {
    final handle = t.ensureSemantics();
    await _pump(
      t,
      const PastChapterStoriesScreen(),
      gateway: _Gateway([photo]),
    );
    await t.tap(find.text('See them'));
    await t.pumpAndSettle();
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('offline: the screen says so and Try again reads again', (
    t,
  ) async {
    final g = _FlakyGateway([photo]);
    await _pump(t, const PastChapterStoriesScreen(), gateway: g);
    expect(find.text("Couldn't load your stories."), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text("Couldn't load your stories."), findsNothing);
    expect(find.text('Delete all 1'), findsOneWidget);
  });

  testWidgets('320 dp wide with large text: nothing overflows', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          pastStoryChaptersGatewayProvider.overrideWithValue(
            _Gateway([photo, video]),
          ),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => MaterialApp(
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: const TextScaler.linear(2)),
                      child: child!,
                    ),
                home: const PastChapterStoriesScreen(),
              ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // The list builds lazily: scroll until built, then fully on screen, so
    // the tap really lands (review M7).
    await t.scrollUntilVisible(find.text('See them'), 100);
    await t.ensureVisible(find.text('See them'));
    await t.pumpAndSettle();
    await t.tap(find.text('See them'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Hide them'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text(
        MyDateFormat.join([MyDateFormat.toDate(photo.occurredOn), 'Photo']),
      ),
      100,
    );
    expect(t.takeException(), isNull);
    expect(
      find.text(
        MyDateFormat.join([MyDateFormat.toDate(photo.occurredOn), 'Photo']),
      ),
      findsOneWidget,
    );
  });

  // Batch 7 review I1: the confirm never offers a download that can't happen.
  for (final can in [true, false]) {
    testWidgets('Delete all confirm when can_download is $can', (t) async {
      final g = _Gateway([photo, video])..canDownload = can;
      await _pump(t, const PastChapterStoriesScreen(), gateway: g);
      await t.tap(find.text('Delete all 2'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('download your data first'),
        can ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining("can't be downloaded any more"),
        can ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets('Delete all that stops short says how many are left', (t) async {
    final g = _Gateway([photo, video])
      ..remainingScript.addAll(List.filled(100, 5));
    await _pump(t, const PastChapterStoriesScreen(), gateway: g);
    await t.tap(find.text('Delete all 2'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(find.text('Deleted.'), findsNothing);
    expect(find.textContaining('5 stories are left'), findsOneWidget);
  });

  testWidgets('a space opened again while deleting says so', (t) async {
    final g = _Gateway([photo, video])
      ..deleteAllError = StoryApiError.fromJson({
        'error': true,
        'code': 'UNAVAILABLE',
      });
    await _pump(t, const PastChapterStoriesScreen(), gateway: g);
    await t.tap(find.text('Delete all 2'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(
      find.text('This space is open again. Delete these from the calendar.'),
      findsOneWidget,
    );
  });

  testWidgets('a single delete shows progress until it lands', (t) async {
    final handle = t.ensureSemantics();
    final g = _Gateway([photo, video])..gate = Completer<void>();
    await _pump(t, const PastChapterStoriesScreen(), gateway: g);
    await t.tap(find.text('See them'));
    await t.pumpAndSettle();
    final tip =
        'Delete the photo from ${MyDateFormat.toDate(photo.occurredOn)}';
    await t.tap(find.byTooltip(tip));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    // Let the dialog finish closing; the spinner keeps animating, so no
    // settle.
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    expect(find.byTooltip(tip), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'\bDeleting\b')), findsOneWidget);
    g.gate!.complete();
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'\bDeleting\b')), findsNothing);
    expect(g.deletedOne, ['s1']);
    handle.dispose();
  });

  testWidgets('leaving mid-delete still refreshes the Download my data entry', (
    t,
  ) async {
    final g = _Gateway([photo, video])..gate = Completer<void>();
    await _pump(t, DataExportScreen(confirmPin: (_) async => true), gateway: g);
    await t.tap(find.text('Your stories from past chapters'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete all 2'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pump();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('2 stories only you can see and delete'), findsOneWidget);
    g.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Your stories from past chapters'), findsNothing);
  });

  testWidgets('screen-reader labels say what each control does', (t) async {
    final handle = t.ensureSemantics();
    await _pump(
      t,
      const PastChapterStoriesScreen(),
      gateway: _Gateway([photo, video]),
    );
    expect(find.bySemanticsLabel('Delete all 2 stories'), findsOneWidget);
    await t.tap(find.text('See them'));
    await t.pumpAndSettle();
    expect(
      find.byTooltip(
        'Delete the video from ${MyDateFormat.toDate(video.occurredOn)}',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  test('rows parse from the RPC shapes', () {
    final c = PastStoryChapter.fromRow({
      'relationship_id': 'r1',
      'status': 'paused',
      'ended_at': null,
      'story_count': 3,
      'first_on': '2026-03-01',
      'last_on': '2026-03-04',
    });
    expect(c.paused, isTrue);
    expect(c.canDownload, isFalse); // absent (an older server) means no
    expect(c.endedAt, isNull);
    expect(c.firstOn, DateTime(2026, 3, 1));
    expect(pastStoryChapterTitle(c), 'A paused space');
    final i = PastStoryItem.fromRow({
      'id': 's1',
      'media_type': 'video',
      'occurred_on': '2026-03-01',
      'created_at': '2026-03-01T10:00:00.123456+00:00',
    });
    expect(i.isVideo, isTrue);
    expect(i.createdAt.toUtc().microsecond, 456);
  });
}

class _FlakyGateway extends _Gateway {
  _FlakyGateway(super.items);
  bool _failed = false;

  @override
  Future<List<PastStoryChapter>> listChapters() async {
    if (!_failed) {
      _failed = true;
      throw Exception('offline');
    }
    return super.listChapters();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:attune/features/stories/presentation/screens/story_camera_screen.dart';
import 'package:attune/features/stories/presentation/state/story_post_pipeline.dart';
import 'package:attune/features/stories/presentation/widgets/story_review_layer.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../helpers/recording_video_platform.dart';
import 'support/capture_fakes.dart';
import 'support/outbox_fakes.dart';

// settleIo cycles: a Share is about 10 sequential real file operations
// (the vault creates its folders and moves two files), so each settle
// allows three times that.
void main() {
  late Directory dir;
  late CameraPlatform original;
  late String photoPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('story_review');
    original = CameraPlatform.instance;
  });
  tearDown(() {
    CameraPlatform.instance = original;
    dir.deleteSync(recursive: true);
  });

  final share = find.byKey(const ValueKey('story-review-share'));
  final retake = find.byKey(const ValueKey('story-review-retake'));
  final close = find.byKey(const ValueKey('story-review-close'));

  Future<({StoryCameraHarness h, FakeImagePreparer main})> open(
    WidgetTester tester, {
    Completer<void>? gate,
    String? rejectWith,
    FakeImagePreparer? preparer,
  }) async {
    photoPath = await writeJpeg(tester, dir, 'photo.jpg');
    CameraPlatform.instance = FakeCameraPlatform(
      videoPath: '${dir.path}/clip.mp4',
      photoPath: photoPath,
    );
    final h = storyCameraContainer(dir);
    final main =
        preparer ?? FakeImagePreparer(gate: gate, rejectWith: rejectWith);
    await pumpStoryCamera(
      tester,
      h.container,
      StoryCameraScreen(
        relationshipId: 'rel-1',
        imagePreparerFactory: () => main,
        thumbnailPreparerFactory: () => FakeImagePreparer(suffix: 'thumb'),
      ),
    );
    return (h: h, main: main);
  }

  testWidgets('the shutter opens a review; nothing is queued until Share', (
    tester,
  ) async {
    final t = await open(tester);
    await tapShutterOnly(tester);
    expect(share, findsOneWidget);
    expect(retake, findsOneWidget);
    expect(find.byKey(const ValueKey('story-review-image')), findsOneWidget);
    expect(
      find.byType(StreakRecordButton),
      findsNothing,
      reason: 'the shared camera hides its controls while reviewing',
    );
    expect(await t.h.store.readAll(outboxUserId), isEmpty);
    expect(t.main.calls, 0, reason: 'nothing is prepared before Share');

    await tester.tap(share);
    await tester.pump();
    await settleIo(tester, 30);
    expect(await t.h.store.readAll(outboxUserId), hasLength(1));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byType(StoryCameraScreen),
      findsNothing,
      reason: 'Share leaves',
    );
  });

  testWidgets('Retake deletes the take and returns to a live camera', (
    tester,
  ) async {
    final t = await open(tester);
    await tapShutterOnly(tester);
    await tester.tap(retake);
    await tester.pump();
    await settleIo(tester, 30);
    expect(share, findsNothing);
    expect(find.byType(StreakRecordButton), findsOneWidget);
    expect(await t.h.store.readAll(outboxUserId), isEmpty);
    expect(await tester.runAsync(() => File(photoPath).exists()), isFalse);
  });

  testWidgets('closing the review asks first: Keep stays, Discard leaves', (
    tester,
  ) async {
    final t = await open(tester);
    await tapShutterOnly(tester);
    await tester.tap(close);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Discard this photo?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(share, findsOneWidget);

    await tester.tap(close);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Discard'));
    await tester.pump(const Duration(milliseconds: 300));
    await settleIo(tester, 30);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StoryCameraScreen), findsNothing);
    expect(await t.h.store.readAll(outboxUserId), isEmpty);
  });

  testWidgets('Share tapped twice queues once (Review Focus 5)', (
    tester,
  ) async {
    final t = await open(tester);
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.tap(share, warnIfMissed: false);
    await tester.pump();
    await settleIo(tester, 30);
    expect(await t.h.store.readAll(outboxUserId), hasLength(1));
    expect(t.main.calls, 1);
  });

  testWidgets('while sharing, Close is hidden and back does not leave', (
    tester,
  ) async {
    final gate = Completer<void>();
    await open(tester, gate: gate);
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.pump();
    expect(close, findsNothing);
    expect(find.text('Sharing…'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(StoryCameraScreen), findsOneWidget);
    gate.complete();
    await settleIo(tester, 30);
  });

  testWidgets('the camera unmounting mid-prepare still queues the story '
      '(01 #14, 07b G7)', (tester) async {
    final gate = Completer<void>();
    final t = await open(tester, gate: gate);
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.pump();
    // The privacy cover (Wave 3 not yet fixed) or any teardown: gone.
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await settleIo(tester, 40);
    expect(await t.h.store.readAll(outboxUserId), hasLength(1));
  });

  testWidgets('a rejected take says why and returns to the live camera', (
    tester,
  ) async {
    await open(tester, rejectWith: 'media_decode_failed');
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.pump();
    await settleIo(tester, 30);
    expect(
      find.text("That photo couldn't be read. Try again."),
      findsOneWidget,
    );
    expect(share, findsNothing);
    expect(find.byType(StreakRecordButton), findsOneWidget);
  });

  testWidgets('I3: a transient prepare failure keeps the take on the review, '
      'and Share works again', (tester) async {
    final t = await open(tester, preparer: _FailsOncePreparer());
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.pump();
    await settleIo(tester, 30);
    expect(
      find.text("Couldn't prepare that photo. Tap Share to try again."),
      findsOneWidget,
    );
    expect(share, findsOneWidget, reason: 'still on the review');
    expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
    expect(await tester.runAsync(() => File(photoPath).exists()), isTrue);
    expect(await t.h.store.readAll(outboxUserId), isEmpty);

    await tester.tap(share);
    await tester.pump();
    await settleIo(tester, 30);
    expect(await t.h.store.readAll(outboxUserId), hasLength(1));
    expect(t.main.calls, 2);
  });

  testWidgets('M4: "Sharing…" is announced to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    final gate = Completer<void>();
    await open(tester, gate: gate);
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.pump();
    expect(
      tester.getSemantics(find.text('Sharing…')),
      containsSemantics(isLiveRegion: true, label: 'Sharing…'),
    );
    gate.complete();
    await settleIo(tester, 30);
    handle.dispose();
  });

  testWidgets('M1: at 320 dp and 2x text the labels stay whole words and '
      'Share does not jump when tapped', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    Future<void> pumpLayer({required bool posting}) => tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
        home: StoryReviewLayer(
          media: const CapturedMedia(
            path: '/nonexistent/take.jpg',
            type: CapturedMediaType.image,
            width: 720,
            height: 1280,
          ),
          videoController: null,
          posting: posting,
          onShare: () {},
          onRetake: () {},
          onClose: () {},
        ),
      ),
    );

    void expectOneLine(String label) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      final style = paragraph.text.style!;
      final single = TextPainter(
        text: TextSpan(text: label, style: style),
        textScaler: paragraph.textScaler,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      expect(
        tester.getSize(find.text(label)).height,
        lessThan(single.height * 1.5),
        reason: '"$label" is on one line',
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: '"$label" whole');
      single.dispose();
    }

    await pumpLayer(posting: false);
    expect(tester.takeException(), isNull);
    expectOneLine('Retake');
    expectOneLine('Share');
    final idle = tester.getSize(share);

    await pumpLayer(posting: true);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expectOneLine('Retake');
    expectOneLine('Sharing…');
    expect(tester.getSize(share), idle, reason: 'Share keeps its size');
  });

  testWidgets('final review #1: a take on the review is deleted when the '
      'camera is torn down without Close or Share (quick exit, sign-out '
      'redirect, route replaced)', (tester) async {
    final t = await open(tester);
    await tapShutterOnly(tester);
    expect(share, findsOneWidget);
    expect(await tester.runAsync(() => File(photoPath).exists()), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await settleIo(tester, 30);

    expect(
      await tester.runAsync(() => File(photoPath).exists()),
      isFalse,
      reason: 'no raw plaintext take left in tmp/',
    );
    expect(await t.h.store.readAll(outboxUserId), isEmpty);
  });

  testWidgets('final review #1: a take kept for another Share (keystore '
      'refusal) is deleted when the camera unmounts before _share resumes', (
    tester,
  ) async {
    final gate = Completer<void>();
    photoPath = await writeJpeg(tester, dir, 'photo.jpg');
    CameraPlatform.instance = FakeCameraPlatform(
      videoPath: '${dir.path}/clip.mp4',
      photoPath: photoPath,
    );
    final h = storyCameraContainer(
      dir,
      extra: [
        storyPostPipelineProvider.overrideWith(
          (ref) => _HeldNotSavedPipeline(ref, gate),
        ),
      ],
    );
    await pumpStoryCamera(
      tester,
      h.container,
      const StoryCameraScreen(relationshipId: 'rel-1'),
    );
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.pump();
    // The pipeline decided "keep the take, the camera is there" and is
    // returning; the camera goes before _share resumes.
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await settleIo(tester, 30);

    expect(await tester.runAsync(() => File(photoPath).exists()), isFalse);
  });

  testWidgets('a video take\'s looping preview stops while Attune is off '
      'screen, and plays again only once the lock is open (stories Wave 3)', (
    tester,
  ) async {
    final video = RecordingVideoPlatform();
    final originalVideo = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = originalVideo);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.runAsync(
      () => File('${dir.path}/clip.mp4').writeAsBytes(List.filled(128, 1)),
    );
    await open(tester);
    // Past the 300 ms photo threshold, then record.
    final hold = await tester.startGesture(
      tester.getCenter(find.byType(StreakRecordButton)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await hold.up();
    await tester.pump();
    await settleIo(tester, 30);
    expect(share, findsOneWidget, reason: 'the take is on review');
    expect(video.calls, contains('play'));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StoryCameraScreen)),
    );
    video.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(video.calls, contains('pause'));
    container.read(appContentVisibleProvider.notifier).setLockOpen(false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(video.calls, isNot(contains('play')), reason: 'lock check');
    container.read(appContentVisibleProvider.notifier).setLockOpen(true);
    await tester.pump();
    expect(video.calls, contains('play'));
  });
}

/// Answers NotSaved (the raw take kept, as when the camera was still
/// listening) once [gate] completes, ignoring whether it still is.
class _HeldNotSavedPipeline extends StoryPostPipeline {
  _HeldNotSavedPipeline(super.ref, this.gate);
  final Completer<void> gate;

  @override
  Future<StoryPostOutcome> post(
    StoryPostRequest request, {
    bool Function()? callerListening,
  }) async {
    await gate.future;
    return const StoryPostNotSaved();
  }
}

/// Fails the first prepare as an interrupted export would, then succeeds.
class _FailsOncePreparer extends FakeImagePreparer {
  @override
  Future<PreparedCaptureImage> prepare(String localPath) async {
    if (calls == 0) {
      calls++;
      throw const CaptureImageRejected('media_compress_failed');
    }
    return super.prepare(localPath);
  }
}

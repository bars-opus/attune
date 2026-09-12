// Tests for the story camera adapter (Plan B, Task 7, spec §6/§6.1/§4.3) —
// the LAST piece tying capture to the posting outbox.
//
// StoryCameraScreen EMBEDS CaptureCameraScreen exactly like
// StreakCameraScreen does (a GlobalKey, onCaptured/onCancelled callbacks) —
// not a standalone push. CaptureCameraScreen supports both shapes; this
// adapter uses the embedded one because there is no review step of its own
// to sit in front of the camera (spec §6.1: the outbox queue itself, with
// its visible Retry/Discard, is the review). On a captured take, this
// screen calls confirmSend() itself (the MAIN media policy: 2560px/5MB for
// an image, 25MB for a video), generates the 400px/q75 JPEG thumbnail (spec
// §4.3 — thumbnail_key is NOT NULL server-side), builds a
// StoryOutboxRecord with utcOffsetMinutes read at capture time, enqueues it,
// and leaves. It must NOT upload inline (spec §6.1: "a capture must not
// hold the user on a progress screen through a 25MB upload") — that is the
// outbox's job (Task 6), driven by storyOutboxProvider.
//
// _FakeCameraPlatform mirrors capture_camera_test.dart's own fake (same
// CameraPlatform.instance seam, no change to shipped code).
//
// _FakeCaptureImagePreparer stands in for the real CaptureImagePreparer for
// the SAME reason _FakeChatVideoPreparer stands in for ChatVideoPreparer:
// CaptureImagePreparer.prepare() calls flutter_image_compress's
// compressAndGetFile(), a MethodChannel call. Under bare `test()` a call
// with no registered platform handler fails fast with
// MissingPluginException, but under `testWidgets` (TestWidgetsFlutterBinding)
// it never completes at all -- confirmed by isolating the call in a probe
// test during this task's development, which hung until an explicit
// timeout fired. StoryCameraScreen therefore takes BOTH an
// imagePreparerFactory (forwarded to CaptureCameraScreen's own main-image
// prepare step, 2560px/5MB) and a thumbnailPreparerFactory (this screen's
// own 400px/q75 thumbnail step, spec §4.3) as test seams, mirroring the
// existing videoPreparerFactory pattern.

import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:attune/features/stories/presentation/screens/story_camera_screen.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = 'story-camera-user';

final _signedInUser = User(
  id: _userId,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

/// Minimal fake CameraPlatform so CameraController.initialize(),
/// startVideoRecording(), stopVideoRecording() and takePicture() can run
/// without a device. Mirrors capture_camera_test.dart's own fake.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform({required this.videoPath, required this.photoPath});

  final String videoPath;
  final String photoPath;

  int _nextCameraId = 0;
  int takePictureCalls = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: 'fake-back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings mediaSettings,
  ) async => _nextCameraId++;

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          720,
          1280,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {}

  @override
  Future<XFile> stopVideoRecording(int cameraId) async => XFile(videoPath);

  @override
  Future<XFile> takePicture(int cameraId) async {
    takePictureCalls++;
    return XFile(photoPath);
  }

  @override
  Future<void> dispose(int cameraId) async {}

  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '${invocation.memberName} is not used by this suite',
      );
}

/// Records every call. Test doubles only — never a mock of SupabaseClient
/// itself (house style, per story_outbox_controller_test.dart).
///
/// [blockUploads] lets a test freeze the OUTBOX's own background flush at
/// its very first network call. This matters because
/// StoryOutboxController.enqueue() legitimately calls flush() itself
/// (Task 6, by design) — the outbox is SUPPOSED to attempt a post right
/// away when connectivity allows it. What "capturing enqueues, it does
/// not upload inline" actually proves is narrower and screen-scoped: the
/// CAMERA SCREEN itself never drives an upload/finalize to completion as
/// part of handling a capture — it enqueues and returns/pops immediately,
/// before anything the gateway does resolves. Blocking the gateway here
/// freezes the outbox's independent flush mid-flight so the test can
/// assert the screen-relevant state (the record landed in the store, the
/// screen returned) deterministically, without racing a background
/// flush's completion against pump()s.
class _FakeStoryGateway implements StoryGateway {
  final List<String> intentCallObjectKinds = [];
  final List<Map<String, dynamic>> uploadCalls = [];
  final List<Map<String, dynamic>> finalizeCalls = [];
  int _intentSeq = 0;

  /// When true, createUploadIntent never resolves — freezing the outbox's
  /// flush() before it can reach uploadObject/finalizeStory.
  bool blockUploads = false;
  final Completer<void> _uploadGate = Completer<void>();

  @override
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  }) async {
    if (blockUploads) await _uploadGate.future;
    intentCallObjectKinds.add(objectKind);
    _intentSeq++;
    return StoryUploadIntent(
      intentId: 'intent-$objectKind-$_intentSeq',
      storageKey: 'key-$objectKind-$_intentSeq',
      bucket: 'story-media',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
  }) async {
    uploadCalls.add({'bucket': bucket, 'storageKey': storageKey});
  }

  @override
  Future<StoryFinalizeResult> finalizeStory({
    required String relationshipId,
    required String clientStoryId,
    required String mediaIntentId,
    required String thumbnailIntentId,
    required int mediaWidth,
    required int mediaHeight,
    int? durationMs,
    required int utcOffsetMinutes,
  }) async {
    finalizeCalls.add({'clientStoryId': clientStoryId});
    return StoryFinalizeResult(
      storyId: 'story-for-$clientStoryId',
      existing: false,
    );
  }
}

/// Stands in for ChatVideoPreparer so a "hold" take's transcode succeeds
/// without video_compress's platform channel (unavailable on a test host).
class _FakeChatVideoPreparer extends ChatVideoPreparer {
  @override
  Future<PreparedChatVideo> prepare({
    required String localPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double)? onProgress,
    void Function(String posterPath)? onPosterReady,
    Duration? maxDuration,
    int? maxBytes,
  }) async {
    return PreparedChatVideo(
      file: File(localPath),
      mimeType: 'video/mp4',
      byteSize: 1024,
      durationMs: 4000,
      thumbnailFile: File(localPath),
      thumbnailMimeType: 'image/jpeg',
      thumbnailByteSize: 128,
      width: 720,
      height: 1280,
    );
  }
}

/// Stands in for CaptureImagePreparer so both the main-image prepare step
/// (inside CaptureCameraScreen.confirmSend) and StoryCameraScreen's own
/// 400px/q75 thumbnail step avoid flutter_image_compress's MethodChannel
/// entirely — see this file's header comment for why that call never
/// completes under testWidgets. Copies the source file byte-for-byte
/// rather than actually resizing: these tests assert the OUTPUT CONTRACT
/// (a thumbnail path is set and the file exists; width/height/mimeType are
/// plumbed through), not the real compression numbers, which is
/// CaptureImagePreparer's own unit-level concern.
class _FakeCaptureImagePreparer extends CaptureImagePreparer {
  _FakeCaptureImagePreparer({this.suffix = 'prepared'});

  final String suffix;
  final List<String> preparedPaths = [];

  @override
  Future<PreparedCaptureImage> prepare(String localPath) async {
    // Synchronous file I/O deliberately: this suite runs inside
    // testWidgets' FakeAsync zone, where an async dart:io Future (backed
    // by a real OS thread-pool callback) never completes without
    // tester.runAsync() wrapping it — confirmed by isolating a hang here
    // during this task's development. Sync I/O has no such dependency on
    // the real event loop, and CaptureImagePreparer's OWN async file I/O
    // is exactly what real callers need (there IS a real event loop in
    // production) — this fake's whole point is to skip
    // flutter_image_compress, not to also re-introduce the async-I/O gap
    // testWidgets has for a different reason.
    preparedPaths.add(localPath);
    final source = File(localPath);
    final bytes = source.readAsBytesSync();
    final outPath = '$localPath.$suffix.jpg';
    final outFile = File(outPath);
    outFile.writeAsBytesSync(bytes);
    return PreparedCaptureImage(
      file: outFile,
      mimeType: 'image/jpeg',
      byteSize: bytes.length,
      width: 32,
      height: 32,
    );
  }
}

/// Rejects its first N calls with [CaptureImageRejected], then delegates
/// to a real [_FakeCaptureImagePreparer] for every call after that. Lets
/// a test drive "first capture fails, retry succeeds" through the real
/// gesture/confirmSend path, proving the screen survives a failure and a
/// second genuine capture is not silently swallowed (F5/F6 of this
/// task's review: `_handled` must reset on a failure path, or the retry
/// itself would be the dropped capture).
class _FailNTimesCaptureImagePreparer extends CaptureImagePreparer {
  _FailNTimesCaptureImagePreparer(this._failuresRemaining);

  int _failuresRemaining;
  int calls = 0;
  final _delegate = _FakeCaptureImagePreparer(suffix: 'retry');

  @override
  Future<PreparedCaptureImage> prepare(String localPath) async {
    calls++;
    if (_failuresRemaining > 0) {
      _failuresRemaining--;
      throw const CaptureImageRejected('media_decode_failed');
    }
    return _delegate.prepare(localPath);
  }
}

void main() {
  late Directory tempDir;
  late CameraPlatform originalCameraPlatform;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('story_camera_test');
    originalCameraPlatform = CameraPlatform.instance;
  });

  tearDown(() async {
    CameraPlatform.instance = originalCameraPlatform;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> writeFile(
    WidgetTester tester,
    String name, {
    int bytes = 128,
  }) async {
    final path = '${tempDir.path}/$name';
    await tester.runAsync(() => File(path).writeAsBytes(List.filled(bytes, 1)));
    return path;
  }

  /// A REAL, decodable JPEG — confirmSend()'s image path runs the actual
  /// CaptureImagePreparer (decode -> resize -> compress), unlike
  /// capture_camera_test.dart which never calls confirmSend for a photo.
  /// Junk bytes decode-fail with CaptureImageRejected('media_decode_failed')
  /// before ever reaching the outbox.
  Future<String> writeJpegFile(WidgetTester tester, String name) async {
    final path = '${tempDir.path}/$name';
    await tester.runAsync(() async {
      final image = img.Image(width: 32, height: 32);
      img.fill(image, color: img.ColorRgb8(200, 100, 50));
      final bytes = img.encodeJpg(image, quality: 90);
      await File(path).writeAsBytes(bytes);
    });
    return path;
  }

  /// Real ProviderContainer with the store/gateway providers overridden to
  /// test doubles, same pattern as story_outbox_controller_test.dart.
  ({ProviderContainer container, StoryOutboxStore store, _FakeStoryGateway gateway})
  buildContainer() {
    final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
    final gateway = _FakeStoryGateway();
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(_signedInUser),
        storyOutboxStoreProvider.overrideWithValue(store),
        storyGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, store: store, gateway: gateway);
  }

  /// Wraps the screen the way the real app router does, mirroring
  /// streak_camera_contract_test.dart's own buildHarness.
  Widget buildHarness(ProviderContainer container, Widget screen) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => context.push('/story-camera'),
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
        GoRoute(path: '/story-camera', builder: (context, state) => screen),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pumpToReady(
    WidgetTester tester,
    ProviderContainer container,
    Widget screen,
  ) async {
    await tester.pumpWidget(buildHarness(container, screen));
    await tester.tap(find.text('open'));
    // GoRouter's own MaterialPageRoute push to StoryCameraScreen (~300ms),
    // which embeds CaptureCameraScreen directly (StreakCameraScreen's own
    // shape) rather than pushing a second nested route — so there is only
    // ONE transition to settle here, then CaptureCameraScreen's async
    // camera init.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Taps the shutter (a short press, well before the 300ms hold
  /// threshold) to take a photo.
  Future<void> tapShutter(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StreakRecordButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Let the image-prepare + thumbnail-generate + enqueue chain settle.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('capturing enqueues, it does not upload inline', (
    tester,
  ) async {
    final photoPath = await writeJpegFile(tester, 'photo.jpg');
    final videoPath = await writeFile(tester, 'clip.mp4');
    CameraPlatform.instance = _FakeCameraPlatform(
      videoPath: videoPath,
      photoPath: photoPath,
    );
    final h = buildContainer();
    // Freeze the outbox's own (legitimate, Task-6-owned) background flush
    // at its very first network call, so this test can assert the
    // SCREEN's behavior deterministically rather than racing a real
    // flush's completion: the screen must enqueue and return without
    // ever driving an upload/finalize to completion itself.
    h.gateway.blockUploads = true;

    await pumpToReady(
      tester,
      h.container,
      StoryCameraScreen(
        relationshipId: 'rel-1',
        videoPreparerFactory: () => _FakeChatVideoPreparer(),
        imagePreparerFactory: () => _FakeCaptureImagePreparer(),
        thumbnailPreparerFactory: () => _FakeCaptureImagePreparer(suffix: 'thumb'),
      ),
    );
    await tapShutter(tester);

    // The camera hands off and leaves: capturing never drives an upload
    // to completion itself — that is entirely the outbox's job (Task 6),
    // running independently in the background. Both halves matter — the
    // first alone would pass if nothing happened at all.
    expect(
      h.gateway.finalizeCalls,
      isEmpty,
      reason: 'the camera screen must never finalize a story itself; '
          'only the outbox does that, asynchronously',
    );
    expect(
      h.gateway.uploadCalls,
      isEmpty,
      reason: 'the camera screen must never upload media itself; the '
          'gateway is blocked at its very first call (createUploadIntent), '
          'so no upload could possibly have happened yet',
    );

    final queued = await h.store.readAll(_userId);
    expect(
      queued,
      hasLength(1),
      reason: 'the outbox must hold exactly one queued record',
    );
    expect(queued.single.relationshipId, 'rel-1');
    expect(queued.single.mediaType, CapturedMediaType.image);

    // The load-bearing assertion this test's NAME actually claims: the
    // user is released, not held on a progress screen through the
    // upload. uploadCalls/finalizeCalls being empty is necessary but not
    // sufficient on its own -- blockUploads makes those structurally
    // empty regardless of whether the screen awaited the enqueue, and the
    // record lands in the store via _store.put before any flush step
    // runs either way. Only "the screen actually left" proves the
    // fire-and-forget contract. Generous settle budget (no real-clock
    // wait beyond the one short runAsync already in tapShutter): the pop
    // needs more than tapShutter's own trailing pumps to land.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byType(StoryCameraScreen),
      findsNothing,
      reason: 'a capture must not hold the user on a progress screen '
          'through the upload -- the screen must have popped by now, '
          'independent of whether the (frozen) outbox has finished '
          'anything',
    );
  });

  testWidgets('a photo generates a thumbnail before enqueueing', (
    tester,
  ) async {
    final photoPath = await writeJpegFile(tester, 'photo.jpg');
    final videoPath = await writeFile(tester, 'clip.mp4');
    CameraPlatform.instance = _FakeCameraPlatform(
      videoPath: videoPath,
      photoPath: photoPath,
    );
    final h = buildContainer();
    // Freeze the outbox's own background flush (see the first test's own
    // comment on why): this test only cares that the record ENQUEUED
    // with a thumbnail, not that a full post round-trip completed.
    // Without this, flush() runs to completion and its own
    // post-success cleanup (deleting the local files via real async
    // dart:io calls) hangs indefinitely under testWidgets' FakeAsync zone
    // -- the same class of hang flutter_image_compress's platform channel
    // caused, just one step later in the pipeline.
    h.gateway.blockUploads = true;

    await pumpToReady(
      tester,
      h.container,
      StoryCameraScreen(
        relationshipId: 'rel-1',
        videoPreparerFactory: () => _FakeChatVideoPreparer(),
        imagePreparerFactory: () => _FakeCaptureImagePreparer(),
        thumbnailPreparerFactory: () => _FakeCaptureImagePreparer(suffix: 'thumb'),
      ),
    );
    await tapShutter(tester);

    final queued = await h.store.readAll(_userId);
    expect(queued, hasLength(1));
    final record = queued.single;

    // record.width/height come from confirmSend()'s PREPARED output
    // (the fake's distinctive 32x32), never the raw camera preview size
    // (720x1280, per _FakeCameraPlatform's onCameraInitialized). Asserting
    // 32 therefore both pins the plumbing AND proves confirmSend() was
    // actually called -- a regression that skipped the main-media prepare
    // step entirely (enqueuing raw camera output, spec §4.2's 2560px/5MB
    // ceiling silently bypassed) would enqueue 720x1280 instead and fail
    // here.
    expect(
      record.width,
      32,
      reason: 'must come from confirmSend()\'s prepared output, not the '
          'raw camera preview size -- proves the main-media prepare step '
          '(spec §4.2) actually ran',
    );
    expect(record.height, 32);
    expect(
      record.mimeType,
      'image/jpeg',
      reason: 'the server validates MIME at finalize (spec §4.2)',
    );

    expect(
      record.localThumbnailPath,
      isNotEmpty,
      reason: 'thumbnail_key is NOT NULL server-side; a story without one '
          'cannot be finalized at all',
    );
    expect(
      record.localThumbnailPath,
      isNot(record.localMediaPath),
      reason: 'the thumbnail must be its own distinct object',
    );

    // Real dart:io file I/O -- wrapped in runAsync so it does not depend
    // on the real event loop the way this file's other async-dart:io
    // calls have needed (see the header comment and _FakeCaptureImagePreparer's
    // sync-I/O note for the two other places this exact class of hang
    // showed up during development).
    final thumbFile = File(record.localThumbnailPath);
    final exists = await tester.runAsync(() => thumbFile.exists());
    expect(
      exists,
      isTrue,
      reason: 'the thumbnail file must actually exist on disk',
    );
  });

  testWidgets('utcOffsetMinutes is read from the device at capture time', (
    tester,
  ) async {
    final photoPath = await writeJpegFile(tester, 'photo.jpg');
    final videoPath = await writeFile(tester, 'clip.mp4');
    CameraPlatform.instance = _FakeCameraPlatform(
      videoPath: videoPath,
      photoPath: photoPath,
    );
    final h = buildContainer();
    // See the first test's comment: freezes the outbox's flush so this
    // assertion runs against a stable, still-queued record rather than
    // racing a background post (and its post-success file cleanup) to
    // completion.
    h.gateway.blockUploads = true;

    // A distinctive sentinel, injected through utcOffsetMinutesReader,
    // rather than recomputing DateTime.now().timeZoneOffset.inMinutes the
    // same way production does. Recomputing degenerates to expect(0, 0)
    // on any UTC host (this one and most CI included) -- proven by
    // mutation testing during this fix round: hardcoding the production
    // read to 0 still passed the old assertion here. -271 cannot collide
    // with a real host offset by accident and independently proves the
    // seam is actually consulted, in either timezone direction.
    const sentinelOffset = -271;

    await pumpToReady(
      tester,
      h.container,
      StoryCameraScreen(
        relationshipId: 'rel-1',
        videoPreparerFactory: () => _FakeChatVideoPreparer(),
        imagePreparerFactory: () => _FakeCaptureImagePreparer(),
        thumbnailPreparerFactory: () => _FakeCaptureImagePreparer(suffix: 'thumb'),
        utcOffsetMinutesReader: () => sentinelOffset,
      ),
    );
    await tapShutter(tester);

    final queued = await h.store.readAll(_userId);
    expect(queued, hasLength(1));
    expect(queued.single.utcOffsetMinutes, sentinelOffset);
  });

  testWidgets('a cancelled capture enqueues nothing', (tester) async {
    final photoPath = await writeJpegFile(tester, 'photo.jpg');
    final videoPath = await writeFile(tester, 'clip.mp4');
    CameraPlatform.instance = _FakeCameraPlatform(
      videoPath: videoPath,
      photoPath: photoPath,
    );
    final h = buildContainer();

    await pumpToReady(
      tester,
      h.container,
      StoryCameraScreen(
        relationshipId: 'rel-1',
        videoPreparerFactory: () => _FakeChatVideoPreparer(),
        imagePreparerFactory: () => _FakeCaptureImagePreparer(),
        thumbnailPreparerFactory: () => _FakeCaptureImagePreparer(suffix: 'thumb'),
      ),
    );

    // Close the camera without capturing anything.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(await h.store.readAll(_userId), isEmpty);
  });
}

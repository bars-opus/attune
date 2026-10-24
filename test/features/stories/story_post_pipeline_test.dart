import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_outbox_wipe.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/story_post_copy.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/state/story_post_pipeline.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_compress/video_compress.dart' show VideoQuality;

import 'support/capture_fakes.dart';
import 'support/outbox_fakes.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('story_pipeline'));
  tearDown(() => dir.deleteSync(recursive: true));

  StoryPostRequest photo(
    File raw, {
    FakeImagePreparer? main,
    Future<StoryPlaceDraft?> Function()? place,
  }) => StoryPostRequest(
    raw: CapturedMedia(
      path: raw.path,
      type: CapturedMediaType.image,
      width: 720,
      height: 1280,
    ),
    relationshipId: 'rel-1',
    utcOffsetMinutes: 60,
    place: place,
    imagePreparer: () => main ?? FakeImagePreparer(),
    thumbnailPreparer: () => FakeImagePreparer(suffix: 'thumb'),
  );

  File rawPhoto() =>
      File('${dir.path}/raw.jpg')..writeAsBytesSync([1, 2, 3, 4]);

  StoryPostRequest video(File raw, {required FakeVideoPreparer preparer}) =>
      StoryPostRequest(
        raw: CapturedMedia(
          path: raw.path,
          type: CapturedMediaType.video,
          width: 720,
          height: 1280,
          durationMs: 4000,
        ),
        relationshipId: 'rel-1',
        utcOffsetMinutes: 60,
        videoPreparer: () => preparer,
        thumbnailPreparer: () => FakeImagePreparer(suffix: 'thumb'),
        thumbnailGrabber: (_) async => null,
      );

  File rawVideo() =>
      File('${dir.path}/raw.mp4')..writeAsBytesSync([1, 2, 3, 4]);

  List<FileSystemEntity> vaultFor(Directory support, String userId) {
    final mine = Directory('${support.path}/story_outbox/$userId');
    return mine.existsSync() ? mine.listSync() : const [];
  }

  test(
    'a photo is prepared, moved into the vault and queued; the raw file goes',
    () async {
      final h = storyCameraContainer(dir);
      final raw = rawPhoto();
      final outcome = await h.container
          .read(storyPostPipelineProvider)
          .post(photo(raw));

      expect(outcome, isA<StoryPostQueued>());
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(
        row.localMediaPath,
        startsWith('story_outbox/$outboxUserId/${row.clientStoryId}/'),
      );
      expect(
        File('${h.support.path}/${row.localMediaPath}').existsSync(),
        isTrue,
      );
      expect(
        File('${h.support.path}/${row.localThumbnailPath}').existsSync(),
        isTrue,
      );
      expect(
        row.width,
        32,
        reason: 'the PREPARED size, not the raw preview size',
      );
      expect(row.utcOffsetMinutes, 60);
      // Deleted without holding the outcome (batch-7 review M2).
      await eventually(() => !raw.existsSync());
      expect(
        raw.existsSync(),
        isFalse,
        reason: 'no raw capture left in tmp (01 #19)',
      );
    },
  );

  test(
    'a slow place lookup is bounded: it posts without a place and says so',
    () async {
      final h = storyCameraContainer(
        dir,
        extra: [
          storyPostPipelineProvider.overrideWith(
            (ref) => StoryPostPipeline(
              ref,
              placeBound: const Duration(milliseconds: 50),
            ),
          ),
        ],
      );
      final outcome = await h.container
          .read(storyPostPipelineProvider)
          .post(
            photo(
              rawPhoto(),
              place: () => Completer<StoryPlaceDraft?>().future,
            ),
          );
      expect(
        outcome,
        isA<StoryPostQueued>().having(
          (o) => o.placeDropped,
          'placeDropped',
          isTrue,
        ),
      );
      expect((await h.store.readAll(outboxUserId)).single.place, isNull);
    },
  );

  test('a pin that resolves in time is kept', () async {
    final h = storyCameraContainer(dir);
    const here = StoryPlaceDraft(lat: 5.5, lng: -0.2, label: 'Near Osu, Accra');
    final outcome = await h.container
        .read(storyPostPipelineProvider)
        .post(photo(rawPhoto(), place: () async => here));
    expect(
      outcome,
      isA<StoryPostQueued>().having(
        (o) => o.placeDropped,
        'placeDropped',
        isFalse,
      ),
    );
    expect(
      (await h.store.readAll(outboxUserId)).single.place?.label,
      'Near Osu, Accra',
    );
  });

  test(
    'a rejection after the camera is gone is surfaced, not swallowed (01 #14)',
    () async {
      final h = storyCameraContainer(dir);
      final outcome = await h.container
          .read(storyPostPipelineProvider)
          .post(
            photo(
              rawPhoto(),
              main: FakeImagePreparer(rejectWith: 'media_decode_failed'),
            ),
            callerListening: () => false,
          );
      expect(
        outcome,
        isA<StoryPostRejected>().having(
          (o) => o.code,
          'code',
          'media_decode_failed',
        ),
      );
      final notice = h.container.read(storyPostNoticeProvider);
      expect(notice?.code, 'media_decode_failed');
      expect(await h.store.readAll(outboxUserId), isEmpty);
    },
  );

  test('a rejection the camera is still showing raises no notice', () async {
    final h = storyCameraContainer(dir);
    await h.container
        .read(storyPostPipelineProvider)
        .post(
          photo(
            rawPhoto(),
            main: FakeImagePreparer(rejectWith: 'media_compress_failed'),
          ),
          callerListening: () => true,
        );
    expect(h.container.read(storyPostNoticeProvider), isNull);
  });

  test('keystore unavailable: not saved, the raw take kept for another Share, '
      'nothing left in the vault', () async {
    final h = storyCameraContainer(dir, cipherUnavailable: true);
    final raw = rawPhoto();
    final outcome = await h.container
        .read(storyPostPipelineProvider)
        .post(photo(raw));
    expect(outcome, isA<StoryPostNotSaved>());
    expect(raw.existsSync(), isTrue);
    final mine = Directory('${h.support.path}/story_outbox/$outboxUserId');
    expect(mine.existsSync() ? mine.listSync() : const [], isEmpty);
  });

  test('signing out while a take is being prepared queues nothing for the '
      'old account and leaves nothing in the vault (Review Focus 2)', () async {
    final h = storyCameraContainer(dir);
    final gate = Completer<void>();
    final raw = rawPhoto();
    // Keep the outbox controller alive across the sign-out, as the rings
    // row does in the app.
    final sub = h.container.listen(storyOutboxProvider, (_, _) {});
    addTearDown(sub.close);
    final posting = h.container
        .read(storyPostPipelineProvider)
        .post(photo(raw, main: FakeImagePreparer(gate: gate)));
    await Future<void>.delayed(Duration.zero);
    h.container.updateOverrides([
      currentUserProvider.overrideWithValue(null),
      storyOutboxStoreProvider.overrideWithValue(h.store),
      storyGatewayProvider.overrideWithValue(h.gateway),
      storyMediaVaultProvider.overrideWithValue(
        h.container.read(storyMediaVaultProvider),
      ),
      coupleMapEnabledProvider.overrideWith((ref) async => false),
    ]);
    gate.complete();
    final outcome = await posting;

    expect(
      outcome,
      isA<StoryPostRejected>().having((o) => o.code, 'code', 'signed_out'),
    );
    expect(await h.store.readAll(outboxUserId), isEmpty);
    final mine = Directory('${h.support.path}/story_outbox/$outboxUserId');
    expect(mine.existsSync() ? mine.listSync() : const [], isEmpty);
    expect(
      dir.listSync().whereType<File>(),
      isEmpty,
      reason: 'neither the raw take nor its prepared copies are left behind',
    );
  });

  test('stories prepare video with the 60 s edge tolerance (Task 15) and the '
      '960x540 oversize step-down (batch-5 #2)', () {
    final preparer = StoryPostPipeline.storyVideoPreparer();
    expect(
      preparer.boundaryTolerance,
      StoryPostPipeline.videoBoundaryTolerance,
    );
    expect(
      StoryPostPipeline.videoBoundaryTolerance,
      const Duration(seconds: 2),
    );
    expect(preparer.oversizeRetryQuality, VideoQuality.Res960x540Quality);
    final src =
        File(
          'lib/features/stories/presentation/state/story_post_pipeline.dart',
        ).readAsStringSync();
    expect(src, contains('boundaryTolerance: videoBoundaryTolerance'));
    expect(
      src,
      contains('oversizeRetryQuality: VideoQuality.Res960x540Quality'),
    );
    // The default when no test seam is passed.
    expect(src, contains('videoPreparer ?? storyVideoPreparer'));
  });

  test('prepare failures carry a reason', () {
    expect(
      storyPrepareFailureMessage('media_too_long', CapturedMediaType.video),
      'That video is longer than a minute.',
    );
    expect(
      storyPrepareFailureMessage('anything-else', CapturedMediaType.image),
      'That could not be posted.',
    );
    expect(
      storyPrepareFailureMessage(
        'media_decode_failed',
        CapturedMediaType.image,
      ),
      contains('photo'),
    );
  });

  group('fix round 1 (batch-7 review)', () {
    test('I1: a sign-out wipe that runs while the session is still valid '
        'queues nothing (P1)', () async {
      final h = storyCameraContainer(dir);
      final gate = Completer<void>();
      final raw = rawPhoto();
      final posting = h.container
          .read(storyPostPipelineProvider)
          .post(
            photo(raw, main: FakeImagePreparer(gate: gate)),
            callerListening: () => false,
          );
      await Future<void>.delayed(Duration.zero);
      // AuthNotifier.signOut / quick exit: the wipe runs first, while the
      // old user is still current.
      await h.container.read(storyOutboxWiperProvider).wipeAll();
      gate.complete();
      final outcome = await posting;

      expect(
        outcome,
        isA<StoryPostRejected>().having((o) => o.code, 'code', 'signed_out'),
      );
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(vaultFor(h.support, outboxUserId), isEmpty);
      await eventually(() => !raw.existsSync());
      expect(raw.existsSync(), isFalse);
      expect(
        h.container.read(storyPostNoticeProvider),
        isNull,
        reason: 'a signed_out notice would be shown to the next person',
      );
    });

    test('I1: a wipe that lands while the files are moved into the vault '
        'queues nothing and leaves no files', () async {
      final support = Directory('${dir.path}/support')..createSync();
      final vault = _HookedVault(support);
      final store = StoryOutboxStore.forTesting(
        stub.createStoryOutboxBackend(),
      );
      final gateway = ScriptedStoryGateway()..uploadGate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(outboxUser()),
          storyOutboxStoreProvider.overrideWithValue(store),
          storyGatewayProvider.overrideWithValue(gateway),
          storyMediaVaultProvider.overrideWithValue(vault),
          coupleMapEnabledProvider.overrideWith((ref) async => false),
        ],
      );
      addTearDown(container.dispose);
      vault.afterAdopt =
          () => container.read(storyOutboxWiperProvider).wipeAll();

      final outcome = await container
          .read(storyPostPipelineProvider)
          .post(photo(rawPhoto()));

      expect(
        outcome,
        isA<StoryPostRejected>().having((o) => o.code, 'code', 'signed_out'),
      );
      expect(await store.readAll(outboxUserId), isEmpty);
      expect(vaultFor(support, outboxUserId), isEmpty);
      expect(gateway.uploads, isEmpty, reason: 'no upload was started');
    });

    test(
      'I1: the store refuses a write made under a stale wipe epoch',
      () async {
        final store = StoryOutboxStore.forTesting(
          stub.createStoryOutboxBackend(),
        );
        final before = store.epoch;
        await store.wipeAll();
        final record = outboxRecord(dir);
        expect(
          await store.put(outboxUserId, record, expectEpoch: before),
          isFalse,
        );
        expect(await store.readAll(outboxUserId), isEmpty);
        expect(
          await store.put(outboxUserId, record, expectEpoch: store.epoch),
          isTrue,
        );
      },
    );

    test('I2: keystore refusal after the camera has gone deletes the take '
        'and says so (P2)', () async {
      final h = storyCameraContainer(dir, cipherUnavailable: true);
      final raw = rawPhoto();
      final outcome = await h.container
          .read(storyPostPipelineProvider)
          .post(photo(raw), callerListening: () => false);
      expect(outcome, isA<StoryPostNotSaved>());
      await eventually(() => !raw.existsSync());
      expect(raw.existsSync(), isFalse);
      expect(h.container.read(storyPostNoticeProvider)?.code, 'not_saved');
      expect(vaultFor(h.support, outboxUserId), isEmpty);
    });

    test('I3: a transient prepare failure with the camera showing keeps the '
        'take for another Share', () async {
      final h = storyCameraContainer(dir);
      final raw = rawVideo();
      final outcome = await h.container
          .read(storyPostPipelineProvider)
          .post(
            video(
              raw,
              preparer: FakeVideoPreparer(rejectWith: 'media_compress_failed'),
            ),
            callerListening: () => true,
          );
      expect(
        outcome,
        isA<StoryPostRejected>()
            .having((o) => o.code, 'code', 'media_compress_failed')
            .having((o) => o.retryable, 'retryable', isTrue),
      );
      expect(raw.existsSync(), isTrue, reason: 'the only copy is kept');
      expect(
        dir.listSync().whereType<File>().map((f) => f.path),
        [raw.path],
        reason: 'no scratch left behind',
      );
      expect(h.container.read(storyPostNoticeProvider), isNull);
    });

    test('I3: a thumbnail failure is transient too', () async {
      final h = storyCameraContainer(dir);
      final raw = rawVideo();
      final outcome = await h.container
          .read(storyPostPipelineProvider)
          .post(
            video(raw, preparer: FakeVideoPreparer()),
            callerListening: () => true,
          );
      expect(
        outcome,
        isA<StoryPostRejected>()
            .having((o) => o.code, 'code', 'thumbnail_frame_failed')
            .having((o) => o.retryable, 'retryable', isTrue),
      );
      expect(raw.existsSync(), isTrue);
      expect(
        dir.listSync().whereType<File>().map((f) => f.path),
        [raw.path],
        reason: 'the prepared copy is cleaned up',
      );
    });

    test('I3: a permanent rejection still deletes the take', () async {
      final h = storyCameraContainer(dir);
      final raw = rawVideo();
      final outcome = await h.container
          .read(storyPostPipelineProvider)
          .post(
            video(
              raw,
              preparer: FakeVideoPreparer(rejectWith: 'media_too_long'),
            ),
            callerListening: () => true,
          );
      expect(
        outcome,
        isA<StoryPostRejected>().having(
          (o) => o.retryable,
          'retryable',
          isFalse,
        ),
      );
      await eventually(() => !raw.existsSync());
      expect(raw.existsSync(), isFalse);
    });

    test('I3: a transient failure after the camera has gone deletes the take '
        'and raises a notice', () async {
      final h = storyCameraContainer(dir);
      final raw = rawVideo();
      await h.container
          .read(storyPostPipelineProvider)
          .post(
            video(
              raw,
              preparer: FakeVideoPreparer(rejectWith: 'media_compress_failed'),
            ),
            callerListening: () => false,
          );
      await eventually(() => !raw.existsSync());
      expect(raw.existsSync(), isFalse);
      expect(
        h.container.read(storyPostNoticeProvider)?.code,
        'media_compress_failed',
      );
    });

    test(
      'M3: a notice belongs to its account and is dropped on a switch',
      () async {
        final h = storyCameraContainer(dir);
        await h.container
            .read(storyPostPipelineProvider)
            .post(
              photo(
                rawPhoto(),
                main: FakeImagePreparer(rejectWith: 'media_decode_failed'),
              ),
              callerListening: () => false,
            );
        final notice = h.container.read(storyPostNoticeProvider);
        expect(notice?.userId, outboxUserId);
        h.container.updateOverrides([
          currentUserProvider.overrideWithValue(outboxUser('someone-else')),
          storyOutboxStoreProvider.overrideWithValue(h.store),
          storyGatewayProvider.overrideWithValue(h.gateway),
          storyMediaVaultProvider.overrideWithValue(
            h.container.read(storyMediaVaultProvider),
          ),
          coupleMapEnabledProvider.overrideWith((ref) async => false),
        ]);
        expect(h.container.read(storyPostNoticeProvider), isNull);
      },
    );

    test('M3: a place dropped after the camera has gone is told too', () async {
      final h = storyCameraContainer(
        dir,
        extra: [
          storyPostPipelineProvider.overrideWith(
            (ref) => StoryPostPipeline(
              ref,
              placeBound: const Duration(milliseconds: 50),
            ),
          ),
        ],
      );
      await h.container
          .read(storyPostPipelineProvider)
          .post(
            photo(
              rawPhoto(),
              place: () => Completer<StoryPlaceDraft?>().future,
            ),
            callerListening: () => false,
          );
      expect(h.container.read(storyPostNoticeProvider)?.code, 'place_dropped');
    });

    test('M2: no synchronous file I/O in the pipeline', () {
      final src =
          File(
            'lib/features/stories/presentation/state/story_post_pipeline.dart',
          ).readAsStringSync();
      expect(src, isNot(contains('Sync(')));
    });

    test("final review #3b: the preparer's first-frame poster is not left "
        'in tmp/, whether the video is queued or refused', () async {
      for (final fail in [false, true]) {
        final h = storyCameraContainer(dir);
        addTearDown(h.container.dispose);
        final raw = rawVideo();
        final preparer = _PosterPreparer(fail: fail);
        final outcome = await h.container
            .read(storyPostPipelineProvider)
            .post(
              StoryPostRequest(
                raw: CapturedMedia(
                  path: raw.path,
                  type: CapturedMediaType.video,
                  width: 720,
                  height: 1280,
                  durationMs: 4000,
                ),
                relationshipId: 'rel-1',
                utcOffsetMinutes: 60,
                videoPreparer: () => preparer,
                thumbnailPreparer: () => FakeImagePreparer(suffix: 'thumb'),
                thumbnailGrabber: (_) async => Uint8List.fromList([9, 9]),
              ),
              callerListening: () => false,
            );
        expect(
          outcome,
          fail ? isA<StoryPostRejected>() : isA<StoryPostQueued>(),
          reason: 'fail: $fail',
        );
        expect(preparer.poster, isNotNull);
        await eventually(() => !File(preparer.poster!).existsSync());
        expect(
          File(preparer.poster!).existsSync(),
          isFalse,
          reason: 'no plaintext first frame left behind (fail: $fail)',
        );
      }
    });

    test('copy for the new codes', () {
      expect(
        storyPrepareFailureMessage('not_saved', CapturedMediaType.image),
        "That photo couldn't be saved. Try again.",
      );
      expect(
        storyPrepareFailureMessage('place_dropped', CapturedMediaType.image),
        "Shared without a place. We couldn't find where you are in time.",
      );
      expect(
        storyPrepareRetryMessage(CapturedMediaType.video),
        "Couldn't prepare that video. Tap Share to try again.",
      );
    });
  });
}

Future<void> eventually(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _HookedVault extends StoryMediaVault {
  _HookedVault(Directory support)
    : super(supportDirectory: () async => support);

  Future<void> Function()? afterAdopt;

  @override
  Future<({String media, String thumbnail})> adopt({
    required String userId,
    required String clientStoryId,
    required String mediaPath,
    required String thumbnailPath,
  }) async {
    final stored = await super.adopt(
      userId: userId,
      clientStoryId: clientStoryId,
      mediaPath: mediaPath,
      thumbnailPath: thumbnailPath,
    );
    await afterAdopt?.call();
    return stored;
  }
}

/// Writes a real poster beside the output, the way ChatVideoPreparer does,
/// and reports it; [fail] refuses the take after the poster exists.
class _PosterPreparer extends ChatVideoPreparer {
  _PosterPreparer({required this.fail});
  final bool fail;
  String? poster;

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
    final thumb = File('$localPath.poster.jpg')..writeAsBytesSync([7, 7, 7]);
    poster = thumb.path;
    onPosterReady?.call(thumb.path);
    if (fail) throw const ChatVideoRejected('media_compress_failed');
    final out = File('$localPath.out.mp4')
      ..writeAsBytesSync(File(localPath).readAsBytesSync());
    return PreparedChatVideo(
      file: out,
      mimeType: 'video/mp4',
      byteSize: 1024,
      durationMs: 4000,
      thumbnailFile: thumb,
      thumbnailMimeType: 'image/jpeg',
      thumbnailByteSize: 3,
      width: 720,
      height: 1280,
    );
  }
}

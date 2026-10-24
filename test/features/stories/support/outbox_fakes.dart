// Shared doubles for the Wave 2 outbox suites. The older
// story_outbox_controller_test.dart keeps its own private fake.
import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const outboxUserId = 'user-w2';

User outboxUser([String id = outboxUserId]) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

/// Each call pops its next scripted outcome (an Object to throw, or null
/// to succeed); an empty script succeeds. [uploadGate] holds uploads open
/// until completed, honouring the cancel token.
class ScriptedStoryGateway implements StoryGateway {
  final intentScript = <Object?>[];
  final uploadScript = <Object?>[];
  final finalizeScript = <Object?>[];
  final intentCalls = <String>[];
  final uploads = <({String key, String path})>[];
  final finalizes = <({String media, String thumb})>[];
  final capturedAts = <DateTime?>[];
  Completer<void>? uploadGate;
  Completer<void>? finalizeGate;
  Duration intentLifetime = const Duration(minutes: 15);

  /// Mint lifetimes as the Wave 5 server does (story_intent_hardening.sql):
  /// media/image 15 minutes, media/video and every thumbnail 60. Off by
  /// default: then every intent lasts [intentLifetime].
  bool serverLifetimes = false;
  DateTime Function() now = DateTime.now;
  int _seq = 0;

  Object? _next(List<Object?> script) =>
      script.isEmpty ? null : script.removeAt(0);

  @override
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  }) async {
    final failure = _next(intentScript);
    if (failure != null) throw failure;
    intentCalls.add(objectKind);
    _seq++;
    return StoryUploadIntent(
      intentId: 'intent-$objectKind-$_seq',
      storageKey: 'key-$objectKind-$_seq',
      bucket: 'story-media',
      expiresAt: now().add(
        !serverLifetimes
            ? intentLifetime
            : objectKind == 'media' && mediaType == 'image'
            ? const Duration(minutes: 15)
            : const Duration(minutes: 60),
      ),
    );
  }

  @override
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) async {
    final gate = uploadGate;
    if (gate != null) {
      cancelToken?.onCancel(() {
        if (!gate.isCompleted) {
          gate.completeError(
            StoryApiError.fromFailure(const ChatUploadCancelled()),
          );
        }
      });
      onProgress?.call(50, 100);
      await gate.future;
    }
    final failure = _next(uploadScript);
    if (failure != null) throw failure;
    if (!File(localPath).existsSync()) {
      throw StoryApiError.fromFailure(const FileSystemException('gone'));
    }
    onProgress?.call(100, 100);
    uploads.add((key: storageKey, path: localPath));
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
    Map<String, dynamic>? place,
    DateTime? capturedAt,
  }) async {
    await finalizeGate?.future;
    final failure = _next(finalizeScript);
    if (failure != null) throw failure;
    finalizes.add((media: mediaIntentId, thumb: thumbnailIntentId));
    capturedAts.add(capturedAt);
    return StoryFinalizeResult(storyId: 's-$clientStoryId', existing: false);
  }
}

StoryApiError storageError(int status) => StoryApiError.fromFailure(
  ChatMediaUploader.storageExceptionFor(
    400,
    '{"statusCode":"$status","message":"x"}',
  ),
);

const unknownError = StoryApiError(
  code: StoryErrorCodes.serverError,
  message: 'Something went wrong.',
  retryable: false,
);

StoryOutboxRecord outboxRecord(
  Directory dir, {
  String id = 'cid-1',
  StoryOutboxState state = StoryOutboxState.queued,
  CapturedMediaType mediaType = CapturedMediaType.image,
}) {
  final video = mediaType == CapturedMediaType.video;
  final media = File('${dir.path}/$id-media.${video ? 'mp4' : 'jpg'}')
    ..writeAsBytesSync([1, 2, 3]);
  final thumb = File('${dir.path}/$id-thumb.jpg')..writeAsBytesSync([4, 5]);
  return StoryOutboxRecord(
    clientStoryId: id,
    relationshipId: 'rel-1',
    localMediaPath: media.path,
    localThumbnailPath: thumb.path,
    mediaType: mediaType,
    mimeType: video ? 'video/mp4' : 'image/jpeg',
    width: 1080,
    height: 1920,
    durationMs: video ? 8000 : null,
    utcOffsetMinutes: 0,
    state: state,
    createdAt: DateTime.utc(2026, 10, 23, 8),
  );
}

typedef OutboxHarness =
    ({
      ProviderContainer container,
      StoryOutboxStore store,
      ScriptedStoryGateway gateway,
      StoryOutboxController Function() controller,
    });

/// [user] replaces the default signed-in-user override (a provider may be
/// overridden only once per container).
OutboxHarness outboxHarness({
  StoryOutboxStore? store,
  ScriptedStoryGateway? gateway,
  Override? user,
  List<Override> extra = const [],
}) {
  final s =
      store ?? StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
  final g = gateway ?? ScriptedStoryGateway();
  final container = ProviderContainer(
    overrides: [
      user ?? currentUserProvider.overrideWithValue(outboxUser()),
      storyOutboxStoreProvider.overrideWithValue(s),
      storyGatewayProvider.overrideWithValue(g),
      ...extra,
    ],
  );
  return (
    container: container,
    store: s,
    gateway: g,
    controller: () => container.read(storyOutboxProvider.notifier),
  );
}

/// Clears the backoff on every non-failed row and flushes once.
Future<void> forceOnce(OutboxHarness h) async {
  for (final row in await h.store.readAll(outboxUserId)) {
    await h.store.put(outboxUserId, row.copyWith(clearNextAttemptAt: true));
  }
  await h.controller().flush();
}

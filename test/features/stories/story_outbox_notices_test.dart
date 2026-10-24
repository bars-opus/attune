import 'dart:async';
import 'dart:io';

import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/story_post_copy.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/state/story_post_pipeline.dart';
import 'package:attune/features/stories/presentation/state/story_posted_hold.dart';
import 'package:attune/features/stories/presentation/widgets/story_outbox_notices.dart';
import 'package:attune/features/stories/presentation/widgets/story_rings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/outbox_fakes.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('notices'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Real file I/O (vault deletes) under FakeAsync: wait, then pump, repeatedly.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
  }

  Future<OutboxHarness> pump(
    WidgetTester tester,
    Widget notice, {
    OutboxHarness? harness,
  }) async {
    final h = harness ?? outboxHarness();
    addTearDown(h.container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(home: Scaffold(body: notice)),
      ),
    );
    await tester.pump();
    return h;
  }

  test('failure copy carries the reason, and Retry only where it can help', () {
    var c = storyOutboxFailureCopy(
      StoryErrorCodes.mediaMissing,
      CapturedMediaType.image,
    );
    expect(c.message, 'This photo is no longer on this phone.');
    expect(c.canRetry, isFalse);
    c = storyOutboxFailureCopy(
      StoryErrorCodes.mediaTooLarge,
      CapturedMediaType.video,
    );
    expect(c.message, 'This video is too large to post.');
    expect(c.canRetry, isFalse);
    c = storyOutboxFailureCopy('FORBIDDEN', CapturedMediaType.image);
    expect(c.canRetry, isFalse);
    c = storyOutboxFailureCopy(null, CapturedMediaType.image);
    expect(c.message, 'Your story could not be posted.');
    expect(c.canRetry, isTrue);
  });

  test('final review #3a: a notice raised after the camera has gone never '
      'says "Try again" (the take is already deleted): every known code '
      'tells the person to take it again', () {
    const codes = [
      'media_too_long',
      'media_too_short',
      'media_too_large',
      'media_dimensions_excessive',
      'media_compress_failed',
      'media_missing',
      'media_empty',
      'media_decode_failed',
      'media_type_unsupported',
      'thumbnail_failed',
      'thumbnail_frame_failed',
      'not_saved',
      'something_unexpected',
    ];
    for (final type in CapturedMediaType.values) {
      for (final code in codes) {
        final m = storyPostNoticeMessage(code, type);
        expect(m, isNot(contains('Try again')), reason: code);
        expect(m, startsWith("Your story wasn't shared. "), reason: code);
        expect(
          m,
          anyOf(
            endsWith('Take it again to share it.'),
            endsWith('Take a shorter one to share it.'),
            endsWith('Hold a little longer next time.'),
          ),
          reason: code,
        );
      }
    }
    expect(
      storyPostNoticeMessage('not_saved', CapturedMediaType.image),
      "Your story wasn't shared. That photo couldn't be saved. Take it again "
      'to share it.',
    );
    // On the camera "Try again" means retake, and stays.
    expect(
      storyPrepareFailureMessage('not_saved', CapturedMediaType.image),
      "That photo couldn't be saved. Try again.",
    );
  });

  test(
    'final review #2: a record stopped as too slow says why, keeps Retry',
    () {
      final c = storyOutboxFailureCopy(
        StoryErrorCodes.mediaLinkTooSlow,
        CapturedMediaType.video,
      );
      expect(
        c.message,
        'Your connection was too slow to post this video. Try again on Wi-Fi.',
      );
      expect(c.canRetry, isTrue);
    },
  );

  test('a story waiting on the network says so', () {
    final waiting = outboxRecord(dir).copyWith(
      lastErrorCode: StoryErrorCodes.network,
      nextAttemptAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    expect(
      storyPendingStatus(waiting),
      "Waiting for a connection. Your story will post when you're back online.",
    );
    expect(storyPendingStatus(outboxRecord(dir)), 'Posting your story…');
  });

  testWidgets('Discard asks first and names what is lost (06 #14)', (
    tester,
  ) async {
    final failed = outboxRecord(dir).copyWith(
      state: StoryOutboxState.failedPermanent,
      lastErrorCode: StoryErrorCodes.mediaTooLarge,
    );
    final h = outboxHarness();
    await h.store.put(outboxUserId, failed);
    await pump(tester, StoryFailedNotice(record: failed), harness: h);
    expect(find.text('Retry'), findsNothing, reason: 'hopeless: no Retry');

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this photo?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(await h.store.readAll(outboxUserId), hasLength(1));

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
    await settle(tester);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => h.store.readAll(outboxUserId)), isEmpty);
  });

  testWidgets('final review #3d: a finalizing story that keeps failing '
      'offline past the cap gets a way out: Discard, which says it may '
      'already have posted', (tester) async {
    StoryOutboxRecord finalizing(int attempts) => outboxRecord(dir).copyWith(
      state: StoryOutboxState.finalizing,
      attempts: attempts,
      lastErrorCode: StoryErrorCodes.network,
      nextAttemptAt: DateTime.now().add(const Duration(minutes: 1)),
    );
    // Below the cap it is a story on its way: no Discard (it may be live).
    final early = finalizing(storyFinalizingExitAfterAttempts - 1);
    expect(storyPendingStatus(early), startsWith('Waiting for a connection.'));

    final stuck = finalizing(storyFinalizingExitAfterAttempts);
    final h = outboxHarness();
    await h.store.put(outboxUserId, stuck);
    await pump(tester, StoryPendingNotice(record: stuck), harness: h);
    expect(
      find.text(
        'Still trying to post your story. It may already have posted, so '
        'check your story.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this photo?'), findsOneWidget);
    expect(
      find.text(
        "It may already have posted. Check your story first. If it hasn't, "
        "it can't be recovered.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
    await settle(tester);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => h.store.readAll(outboxUserId)), isEmpty);
    // The retry timer armed for nextAttemptAt above is harmless (an empty
    // flush) but still pending; end it with the container.
    h.container.dispose();
  });

  testWidgets('Cancel on a posting story asks, then stops it', (tester) async {
    final h = outboxHarness();
    h.gateway.uploadGate = Completer<void>();
    final record = outboxRecord(dir);
    unawaited(h.controller().enqueue(record));
    await pump(tester, StoryPendingNotice(record: record), harness: h);
    await settle(tester); // the drive reaches the held upload
    expect(find.text('Posting your story…'), findsOneWidget);
    expect(
      find.text('Discard'),
      findsNothing,
      reason: 'Discard cannot stop an in-flight finalize; Cancel can refuse',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this story?'), findsOneWidget);
    await tester.tap(find.text('Cancel story'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => h.store.readAll(outboxUserId)), isEmpty);
  });

  const alreadyPosted =
      'It has already posted. You can delete it from your story.';

  testWidgets('Cancel once finalize has been sent says it already posted', (
    tester,
  ) async {
    final h = outboxHarness();
    h.gateway.finalizeGate = Completer<void>();
    final record = outboxRecord(dir);
    unawaited(h.controller().enqueue(record));
    await pump(tester, StoryPendingNotice(record: record), harness: h);
    await settle(tester); // the drive reaches the held finalize

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel story'));
    await settle(tester);
    expect(find.text(alreadyPosted), findsOneWidget);
    h.gateway.finalizeGate!.complete();
    await settle(tester);
    // It posted: let the ring's posted hold (Wave 4 Task 7) run out.
    await tester.pump(kStoryPostedHoldCap);
  });

  testWidgets('Cancel of a story that has gone from the queue says it already '
      'posted (batch-3 review N1)', (tester) async {
    final h = outboxHarness();
    // Never queued here: it posted (and left the queue) before the tap.
    final record = outboxRecord(dir);
    await pump(tester, StoryPendingNotice(record: record), harness: h);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel story'));
    await settle(tester);
    expect(find.text(alreadyPosted), findsOneWidget);
  });

  testWidgets('a story that is finalizing offers no Cancel', (tester) async {
    final record = outboxRecord(
      dir,
    ).copyWith(state: StoryOutboxState.finalizing);
    await pump(tester, StoryPendingNotice(record: record));
    expect(find.text('Posting your story…'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('a take that failed after the camera closed is shown once, then '
      'dismissed', (tester) async {
    final h = await pump(tester, const StoryPrepareFailedNotice());
    expect(find.byType(StoryPrepareFailedNotice), findsOneWidget);
    expect(find.textContaining("couldn't"), findsNothing);
    h.container
        .read(storyPostNoticeProvider.notifier)
        .state = const StoryPostNotice(
      code: 'media_too_long',
      mediaType: CapturedMediaType.video,
      userId: outboxUserId,
    );
    await tester.pump();
    expect(
      find.text(
        "Your story wasn't shared. That video is longer than a minute. Take "
        'a shorter one to share it.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(h.container.read(storyPostNoticeProvider), isNull);
  });

  group('notices raised after the camera has gone (Task 16)', () {
    Future<OutboxHarness> raise(WidgetTester tester, StoryPostNotice n) async {
      final h = await pump(tester, const StoryPrepareFailedNotice());
      h.container.read(storyPostNoticeProvider.notifier).state = n;
      await tester.pump();
      return h;
    }

    testWidgets('not_saved says the story was not shared, and why', (
      tester,
    ) async {
      await raise(
        tester,
        const StoryPostNotice(
          code: 'not_saved',
          mediaType: CapturedMediaType.image,
          userId: outboxUserId,
        ),
      );
      expect(
        find.text(
          "Your story wasn't shared. That photo couldn't be saved. Take it "
          'again to share it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('place_dropped says it WAS shared, without a place', (
      tester,
    ) async {
      await raise(
        tester,
        const StoryPostNotice(
          code: 'place_dropped',
          mediaType: CapturedMediaType.image,
          userId: outboxUserId,
        ),
      );
      expect(find.textContaining("wasn't shared"), findsNothing);
      expect(
        find.text(
          "Your story was shared without a place. We couldn't find where you "
          'are in time.',
        ),
        findsOneWidget,
      );
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('an unexpected failure never shows a code or a vague line', (
      tester,
    ) async {
      await raise(
        tester,
        const StoryPostNotice(
          code: 'capture_failed',
          mediaType: CapturedMediaType.video,
          userId: outboxUserId,
        ),
      );
      expect(
        find.text(
          "Your story wasn't shared. Something went wrong preparing that "
          'video. Take it again to share it.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('capture_failed'), findsNothing);
    });

    testWidgets("another account's notice is never shown", (tester) async {
      await raise(
        tester,
        const StoryPostNotice(
          code: 'media_too_long',
          mediaType: CapturedMediaType.video,
          userId: 'someone-else',
        ),
      );
      expect(find.textContaining("wasn't shared"), findsNothing);
      expect(find.text('OK'), findsNothing);
    });
  });

  testWidgets('at 320 dp and 2x text the notices fit, with 48 dp buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final failed = outboxRecord(
      dir,
    ).copyWith(state: StoryOutboxState.failedPermanent);
    final h = outboxHarness();
    addTearDown(h.container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: Column(
                children: [
                  StoryFailedNotice(record: failed),
                  StoryPendingNotice(record: outboxRecord(dir, id: 'cid-2')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final label in ['Retry', 'Discard', 'Cancel']) {
      final size = tester.getSize(find.widgetWithText(TextButton, label));
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
    }
    // The message keeps a readable width rather than being squeezed by the
    // buttons.
    final message = tester.getSize(
      find.text('Your story could not be posted.'),
    );
    expect(message.width, greaterThan(200));
  });

  testWidgets('the rings row shows Cancel (not Discard) for a posting story, '
      'and a notice raised after the camera closed', (tester) async {
    final h = outboxHarness(
      extra: [
        storyRingSummaryProvider.overrideWith((ref, id) async => const {}),
      ],
    );
    h.gateway.uploadGate = Completer<void>();
    unawaited(h.controller().enqueue(outboxRecord(dir)));
    await pump(
      tester,
      const StoryRingsRow(
        relationshipId: 'rel-1',
        partnerId: 'partner-1',
        partnerName: 'Alex',
      ),
      harness: h,
    );
    await settle(tester);
    expect(find.text('Posting your story…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Discard'), findsNothing);

    h.container
        .read(storyPostNoticeProvider.notifier)
        .state = const StoryPostNotice(
      code: 'place_dropped',
      mediaType: CapturedMediaType.image,
      userId: outboxUserId,
    );
    await tester.pump();
    expect(find.textContaining('shared without a place'), findsOneWidget);
    h.gateway.uploadGate!.complete();
    await settle(tester);
    // It posted: let the ring's posted hold (Wave 4 Task 7) run out.
    await tester.pump(kStoryPostedHoldCap);
  });

  test('the rings row uses the notices', () {
    final src =
        File(
          'lib/features/stories/presentation/widgets/story_rings_row.dart',
        ).readAsStringSync();
    expect(src, contains('StoryPendingNotice('));
    expect(src, contains('StoryFailedNotice('));
    expect(src, contains('StoryPrepareFailedNotice('));
    expect(src, contains('storyUploadProgressProvider'));
  });
}

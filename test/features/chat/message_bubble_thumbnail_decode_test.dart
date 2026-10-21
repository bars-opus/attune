import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/chat_test_harness.dart';

/// 05 M-4: a 220px tile decoded the full 1600px bitmap (~7 MB each).
void main() {
  Message image(String id, String path, {int? w, int? h}) => Message(
    id: id,
    clientMessageId: 'c-$id',
    relationshipId: 'r1',
    senderId: 'me',
    content: '',
    createdAt: DateTime(2026, 7, 1, 12, id.length),
    status: MessageStatus.sending,
    isMine: true,
    mediaType: 'image',
    localMediaPath: path,
    mediaWidth: w,
    mediaHeight: h,
  );

  late Directory dir;
  late String photo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('attune_thumb');
    photo = '${dir.path}/p.jpg';
    File(
      photo,
    ).writeAsBytesSync(img.encodeJpg(img.Image(width: 40, height: 30)));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('a local image thumbnail decodes at display size', (
    tester,
  ) async {
    final path = photo;
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: image('m1', path, w: 1200, h: 1600)),
          ),
        ),
      ),
    );
    await tester.pump();

    final provider = tester.widget<Image>(find.byType(Image).first).image;
    expect(provider, isA<ResizeImage>());
    final dpr = tester.view.devicePixelRatio;
    expect((provider as ResizeImage).width, (220 * dpr).round());
    expect(provider.height, isNull);
  });

  // Only the front tile of a group is built, so each shape is its own case.
  Future<ResizeImage> pumpGroup(WidgetTester tester, {int? w, int? h}) async {
    final messages = [image('a', photo, w: w, h: h), image('bb', photo)];
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: messages.first, mediaGroup: messages),
          ),
        ),
      ),
    );
    await tester.pump();
    final resizes =
        tester
            .widgetList<Image>(find.byType(Image))
            .map((i) => i.image)
            .whereType<ResizeImage>()
            .toList();
    expect(resizes, hasLength(1), reason: 'group tile decoded at full size');
    return resizes.single;
  }

  testWidgets('a landscape group tile decodes its 300 pt long side', (
    tester,
  ) async {
    final r = await pumpGroup(tester, w: 1600, h: 1200);
    expect(r.height, (300 * tester.view.devicePixelRatio).round());
    expect(r.width, isNull);
  });

  testWidgets('a portrait group tile decodes its 238 pt width', (
    tester,
  ) async {
    final r = await pumpGroup(tester, w: 1200, h: 1600);
    expect(r.width, (238 * tester.view.devicePixelRatio).round());
    expect(r.height, isNull);
  });

  testWidgets('a near-square portrait group tile decodes its 300 pt height', (
    tester,
  ) async {
    final r = await pumpGroup(tester, w: 900, h: 1000);
    expect(r.height, (300 * tester.view.devicePixelRatio).round());
    expect(r.width, isNull);
  });

  testWidgets('a remote photo caps its in-memory decode, not its disk copy', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'me')..signMediaUrls = true;
    final container = buildChatContainer(repository: repo, userId: 'me');
    final remote = Message(
      id: 'm-remote',
      clientMessageId: 'c-remote',
      relationshipId: 'r1',
      senderId: 'partner',
      content: '',
      createdAt: DateTime(2026, 7, 1, 12),
      status: MessageStatus.delivered,
      isMine: false,
      mediaType: 'image',
      mediaKey: 'rel/photo.jpg',
      mediaWidth: 1600,
      mediaHeight: 1200,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: Scaffold(body: MessageBubble(message: remote))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    final dpr = tester.view.devicePixelRatio;
    expect(image.memCacheHeight, (220 * dpr).round(), reason: 'landscape');
    expect(image.memCacheWidth, isNull);
    expect(image.maxWidthDiskCache, isNull);
    expect(image.maxHeightDiskCache, isNull);
    // Unmount, then dispose: the signed-URL entry's refresh timer goes
    // with the container.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('a single-video bubble decodes its poster at the tile width', (
    tester,
  ) async {
    final video = Message(
      id: 'm-video',
      clientMessageId: 'c-video',
      relationshipId: 'r1',
      senderId: 'me',
      content: '',
      createdAt: DateTime(2026, 7, 1, 12),
      status: MessageStatus.sent,
      isMine: true,
      mediaType: 'video',
      mediaKey: 'rel/clip.mp4',
      localThumbnailPath: photo,
      mediaWidth: 1080,
      mediaHeight: 1920,
    );
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(home: Scaffold(body: MessageBubble(message: video))),
      ),
    );
    await tester.pump();
    final provider = tester.widget<Image>(find.byType(Image).first).image;
    expect(provider, isA<ResizeImage>());
    expect(
      (provider as ResizeImage).width,
      (220 * tester.view.devicePixelRatio).round(),
    );
    expect(provider.height, isNull);
    expect(provider.imageProvider, isA<FileImage>());
  });

  testWidgets('an unknown-shape group tile keeps the 2x width cap', (
    tester,
  ) async {
    final r = await pumpGroup(tester);
    expect(r.width, (300 * tester.view.devicePixelRatio).round() * 2);
    expect(r.height, isNull);
  });
}

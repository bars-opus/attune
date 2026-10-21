import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/image_caption_screen.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/chat_test_harness.dart';

/// Full-resolution picks (#20) reach these widgets as files: decoded
/// uncapped, a 12 MP photo is ~48 MB of pixels per Image, for a preview a
/// few hundred points wide. Both must ask the codec for a capped size.
void main() {
  late Directory dir;
  late String photo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('decode_cap');
    photo = '${dir.path}/pick.jpg';
    File(
      photo,
    ).writeAsBytesSync(img.encodeJpg(img.Image(width: 40, height: 30)));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ResizeImage resizeOf(WidgetTester tester, Finder within) {
    final image = tester.widget<Image>(
      find.descendant(of: within, matching: find.byType(Image)).first,
    );
    expect(
      image.image,
      isA<ResizeImage>(),
      reason: 'a FileImage decoded at full size',
    );
    return image.image as ResizeImage;
  }

  testWidgets('the caption preview decodes at screen width x pixel ratio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      withScreenUtil(MaterialApp(home: ImageCaptionScreen(imagePath: photo))),
    );
    await tester.pump();

    final resize = resizeOf(tester, find.byType(ImageCaptionScreen));
    expect(resize.width, 1170);
    expect(resize.imageProvider, isA<FileImage>());
  });

  testWidgets('the optimistic bubble decodes near its 220 pt square', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final message = Message(
      id: 'm1',
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      content: '',
      createdAt: DateTime(2026, 7, 1, 15, 4),
      status: MessageStatus.sending,
      isMine: true,
      mediaType: 'image',
      localMediaPath: photo,
    );
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(home: Scaffold(body: MessageBubble(message: message))),
      ),
    );
    await tester.pump();

    final resize = resizeOf(tester, find.byType(MessageBubble));
    expect(resize.imageProvider, isA<FileImage>());
    // 220 pt x 3 = 660 px; twice that keeps a 2:1 landscape's short edge
    // covering the BoxFit.cover square without an upscale.
    expect(resize.width, 1320);
    expect(resize.height, isNull);
  });
}

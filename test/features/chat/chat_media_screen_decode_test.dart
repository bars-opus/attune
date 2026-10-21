import 'package:attune/features/chat/presentation/screens/chat_media_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Final wave M-11: the media gallery's grid decoded every photo at full
/// size (a 1600 px bitmap behind a ~130 pt tile).
void main() {
  testWidgets('grid tiles cap their in-memory decode at the tile size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = FakeChatRepository(currentUserId: 'user-a')
      ..signMediaUrls = true;
    repo.seedIncoming(
      id: 'p1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: '',
      createdAt: DateTime.now(),
      mediaType: 'image',
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(
            home: ChatMediaScreen(conversation: activeConversation('rel-1')),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final tile = find.byType(CachedNetworkImage);
    expect(tile, findsOneWidget);
    final image = tester.widget<CachedNetworkImage>(tile);
    final tilePx = (tester.getSize(tile).width * 3).round();
    // No stored dimensions on this row: twice the tile, still far below
    // the full-size decode.
    expect(image.memCacheWidth, tilePx * 2);
    expect(image.memCacheHeight, isNull);
    expect(image.maxWidthDiskCache, isNull, reason: 'memory only');

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });
}

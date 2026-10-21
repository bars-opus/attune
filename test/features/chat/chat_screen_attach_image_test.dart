import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/chat_test_harness.dart';

class _SupportDirectory extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _SupportDirectory(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _FakePicker extends ChatImagePicker {
  _FakePicker(this.onPick);
  final Future<String?> Function() onPick;

  @override
  Future<String?> pickFromGallery() => onPick();
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('attach_image');
    // Staged picks are owned under Application Support/chat_picks.
    PathProviderPlatform.instance = _SupportDirectory(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    Future<String?> Function() onPick,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        chatImageSharingEnabledProvider.overrideWith((ref) async => true),
        chatImagePickerProvider.overrideWithValue(_FakePicker(onPick)),
      ],
    );
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> tapPhotos(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Photos'));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  for (final (failure, copy) in [
    (
      ChatImagePickFailure.unreadable,
      'That photo could not be opened. Try a different one.',
    ),
    (
      ChatImagePickFailure.accessDenied,
      'Attune needs access to your photos. You can allow it in Settings.',
    ),
  ]) {
    testWidgets('a pick that fails (${failure.name}) says so plainly', (
      tester,
    ) async {
      final container = await pumpChat(
        tester,
        () async => throw ChatImagePickException(failure),
      );

      await tapPhotos(tester);

      expect(find.text(copy), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        container
            .read(chatControllerProvider(activeConversation('rel-1')))
            .messages,
        isEmpty,
      );
      await tearDownChat(tester, container);
    });
  }

  testWidgets('a pick that lands after the chat closed is discarded', (
    tester,
  ) async {
    final staged = File(p.join(tmp.path, ChatImagePicker.folderName, 'a.jpg'))
      ..createSync(recursive: true);
    final pick = Completer<String?>();
    final container = await pumpChat(tester, () => pick.future);

    await tapPhotos(tester);
    await tester.pumpWidget(const SizedBox());
    pick.complete(staged.path);
    // The discard is real file I/O, fire-and-forget: wait for it (bounded)
    // outside the fake clock.
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && staged.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(staged.existsSync(), isFalse);
    container.dispose();
  });
}

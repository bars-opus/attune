import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// Fakes path_provider's platform singleton so VoiceRecorderService.start()'s
/// getTemporaryDirectory() call resolves under `flutter test` instead of
/// hitting a MissingPluginException — same pattern already used by
/// chat_state_send_voice_message_test.dart for the same underlying need.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

/// Fakes permission_handler's platform singleton so `Permission.microphone
/// .request()` resolves to "granted" under `flutter test` instead of
/// throwing MissingPluginException (no real platform channel is registered
/// in a widget-test host). Swapping `PermissionHandlerPlatform.instance` is
/// the package's own documented test seam — no production code changes.
class _GrantedPermissionHandlerPlatform extends PermissionHandlerPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    return {for (final p in permissions) p: PermissionStatus.granted};
  }

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    return PermissionStatus.granted;
  }
}

/// Fakes the `record` package's platform singleton so `AudioRecorder.start()`
/// / `.stop()` succeed under `flutter test` instead of hitting a
/// MissingPluginException — same rationale as the permission fake above.
class _FakeRecordPlatform extends RecordPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {}

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async => const Stream<Uint8List>.empty();

  @override
  Future<String?> stop(String recorderId) async => null;

  @override
  Future<void> cancel(String recorderId) async {}

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<bool> isRecording(String recorderId) async => false;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -30, max: -10);

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async => true;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async => [];

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();
}

Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController controller,
  VoidCallback? onSend,
  VoidCallback? onOpenTranslator,
  VoidCallback? onAttachImage,
  VoidCallback? onAttachVideo,
  VoidCallback? onAttachFile,
  VoidCallback? onCaptureVideo,
  VoidCallback? onOpenGames,
  bool showTranslator = false,
  bool showAttachImage = false,
  bool showAttachVideo = false,
  bool showVoiceMessage = false,
  bool showCaptureVideo = false,
  bool showGames = false,
  bool enabled = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatTextField(
          controller: controller,
          onSend: onSend ?? () {},
          onOpenTranslator: onOpenTranslator,
          onAttachImage: onAttachImage,
          onAttachVideo: onAttachVideo,
          onAttachFile: onAttachFile,
          onCaptureVideo: onCaptureVideo,
          onOpenGames: onOpenGames,
          showTranslator: showTranslator,
          showAttachImage: showAttachImage,
          showAttachVideo: showAttachVideo,
          showVoiceMessage: showVoiceMessage,
          showCaptureVideo: showCaptureVideo,
          showGames: showGames,
          enabled: enabled,
        ),
      ),
    ),
  );
}

void main() {
  // The press-and-hold recording gesture drives VoiceRecorderService, which
  // talks to the path_provider, permission_handler, and record plugins over
  // platform channels — unavailable under `flutter test`. Swap in fakes for
  // the duration of this file's tests only (restored after) so
  // getTemporaryDirectory(), Permission.microphone.request(), and
  // AudioRecorder.start()/stop() resolve instead of throwing
  // MissingPluginException.
  final realPathProviderPlatform = PathProviderPlatform.instance;
  final realPermissionPlatform = PermissionHandlerPlatform.instance;
  final realRecordPlatform = RecordPlatform.instance;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_text_field_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    PermissionHandlerPlatform.instance = _GrantedPermissionHandlerPlatform();
    RecordPlatform.instance = _FakeRecordPlatform();
  });

  tearDown(() async {
    PathProviderPlatform.instance = realPathProviderPlatform;
    PermissionHandlerPlatform.instance = realPermissionPlatform;
    RecordPlatform.instance = realRecordPlatform;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('send is disabled when empty and enabled once text is entered', (
    tester,
  ) async {
    final controller = TextEditingController();
    var sent = 0;
    await _pump(
      tester,
      controller: controller,
      onSend: () => sent++,
      showVoiceMessage: false,
    );

    // The send icon is present but its GestureDetector.onTap is null while
    // empty (the composer's own _ComposerIcon, not a Material IconButton —
    // tapping does nothing).
    await tester.tap(find.byIcon(Icons.send_rounded));
    expect(sent, 0);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.send_rounded));
    expect(sent, 1);
  });

  testWidgets('translator entry only appears with non-empty text (Spec 10)', (
    tester,
  ) async {
    final controller = TextEditingController();
    await _pump(
      tester,
      controller: controller,
      showTranslator: true,
      onOpenTranslator: () {},
    );

    expect(find.byIcon(Icons.help_outline_rounded), findsNothing);

    await tester.enterText(find.byType(TextField), 'draft');
    await tester.pump();
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
  });

  testWidgets('translator entry stays hidden when flag is off', (tester) async {
    final controller = TextEditingController(text: 'draft');
    await _pump(tester, controller: controller, showTranslator: false);
    expect(find.byIcon(Icons.help_outline_rounded), findsNothing);
  });

  testWidgets('attach-image button visibility follows its flag', (
    tester,
  ) async {
    final controller = TextEditingController();
    await _pump(tester, controller: controller, showAttachImage: false);
    // The circular '+' attach icon only renders when media/files are
    // available for the attachment sheet.
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);

    await _pump(
      tester,
      controller: controller,
      showAttachImage: true,
      onAttachImage: () {},
    );
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
  });

  testWidgets('disabled composer prevents send even with text', (tester) async {
    final controller = TextEditingController(text: 'hi');
    var sent = 0;
    await _pump(
      tester,
      controller: controller,
      enabled: false,
      onSend: () => sent++,
    );

    await tester.tap(find.byIcon(Icons.send_rounded));
    expect(sent, 0);
  });

  testWidgets(
    'shows mic icon (not send) when text is empty and voice messages are on',
    (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller: controller, showVoiceMessage: true);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
    },
  );

  testWidgets(
    'shows send icon (not mic) once text is entered, even with voice messages on',
    (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller: controller, showVoiceMessage: true);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    },
  );

  testWidgets(
    'mic stays absent when showVoiceMessage is false, regardless of text',
    (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller: controller, showVoiceMessage: false);
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      // send is present-but-disabled while empty when no voice shortcut is
      // available, per the existing test above.
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    },
  );

  testWidgets('idle composer shows camera left and mic, games, add right', (
    tester,
  ) async {
    await _pump(
      tester,
      controller: TextEditingController(),
      showCaptureVideo: true,
      onCaptureVideo: () {},
      showVoiceMessage: true,
      showGames: true,
      onOpenGames: () {},
      showAttachImage: true,
      onAttachImage: () {},
      showAttachVideo: true,
      onAttachVideo: () {},
      onAttachFile: () {},
    );

    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
  });

  testWidgets(
    'long-pressing the mic starts recording and shows the waveform bar',
    (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller: controller, showVoiceMessage: true);

      // tester.longPress() presses AND releases in one call (a down/up pair
      // separated by kLongPressTimeout), which would also fire
      // onLongPressEnd before this test gets to assert. Press and hold
      // manually via TestGesture instead, so the recording is still in
      // progress when we check.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      // Let the async permission-request/start chain resolve and rebuild.
      await tester.pump();

      expect(
        find.byType(TextField),
        findsNothing,
      ); // replaced by the waveform view

      // Release so the test's pending timers (elapsed ticker) are cleaned up
      // rather than leaking into pumpWidget's teardown/leak checks.
      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets(
    'attach ("+") icon opens a sheet with just Photos + Files when only showAttachImage is true (video off)',
    (tester) async {
      var attachImageCalled = 0;
      await _pump(
        tester,
        controller: TextEditingController(),
        showAttachImage: true,
        onAttachImage: () => attachImageCalled++,
        onAttachFile: () {},
        showAttachVideo: false,
      );

      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Video'), findsNothing);
      expect(find.text('Games'), findsNothing);

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      expect(attachImageCalled, 1);
    },
  );

  testWidgets(
    'attach icon opens a Photos/Video sheet when both showAttachImage and showAttachVideo are true',
    (tester) async {
      await _pump(
        tester,
        controller: TextEditingController(),
        showAttachImage: true,
        onAttachImage: () {},
        showAttachVideo: true,
        onAttachVideo: () {},
        onAttachFile: () {},
      );

      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Games'), findsNothing);
    },
  );

  testWidgets(
    'tapping Video in the sheet calls onAttachVideo and dismisses the sheet',
    (tester) async {
      var attachVideoCalled = 0;
      await _pump(
        tester,
        controller: TextEditingController(),
        showAttachImage: true,
        onAttachImage: () {},
        showAttachVideo: true,
        onAttachVideo: () => attachVideoCalled++,
        onAttachFile: () {},
      );

      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Video'));
      await tester.pumpAndSettle();

      expect(attachVideoCalled, 1);
      expect(find.text('Video'), findsNothing);
    },
  );

  testWidgets(
    'streak camera icon absent by default, existing attach/voice icons unaffected',
    (tester) async {
      final controller = TextEditingController();
      await _pump(
        tester,
        controller: controller,
        showAttachImage: true,
        onAttachImage: () {},
        showAttachVideo: true,
        onAttachVideo: () {},
        showVoiceMessage: true,
        // showCaptureVideo/onCaptureVideo deliberately omitted — this is
        // the additive-only guarantee: the new pair must default to
        // absent/off without disturbing any of the three pre-existing
        // pairs.
      );

      expect(find.byIcon(Icons.camera_alt_rounded), findsNothing);
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'camera icon appears and calls onCaptureVideo when showCaptureVideo is true',
    (tester) async {
      var captureVideoCalled = 0;
      final controller = TextEditingController();
      await _pump(
        tester,
        controller: controller,
        showCaptureVideo: true,
        onCaptureVideo: () => captureVideoCalled++,
      );

      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.camera_alt_rounded));
      expect(captureVideoCalled, 1);
    },
  );
}

// test/features/chat/chat_text_field_ai_mode_test.dart
//
// Spec §3.3: "Hide unsupported attachment controls in AI mode, restore
// on exit, preserve the ordinary unsent chat draft."
//
// THE REGRESSION CONSTRAINT IS THE POINT OF THIS FILE, not the feature.
// `ChatTextField` has FOUR construction sites and only ONE is chat:
// `chat_screen.dart`, `debate_room_screen.dart`,
// `comment_thread_screen.dart` and `image_caption_screen.dart`. The AI
// capability (`ai_assist_enabled`) is OFF in every environment and the
// user's decision is that it flips only after Plan D ships. So the
// default path through this widget must be byte-identical in behaviour
// to the composer on 131bbfa6, and the `defaults` group below is the
// proof of that rather than a courtesy -- it pins the state of EVERY
// control that AI mode touches, with the AI parameters absent.
//
// Modelled on `game_staged_composer_test.dart`, which proves the same
// shape for the only other mode this composer has (`gameStaged`): a
// boolean that removes controls because the thing being sent is already
// chosen. AI mode is that argument again with a different payload.
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  // Every control ChatScreen can switch on, all on. A test that pumped
  // with controls off could not tell "AI mode hid it" from "it was
  // never there", which is the vacuity this plan has caught four times.
  Future<void> pump(
    WidgetTester tester, {
    bool aiMode = false,
    bool includeAiMode = true,
    VoidCallback? onAiButtonTap,
    String text = '',
    TextEditingController? controller,
  }) async {
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body:
                includeAiMode
                    ? ChatTextField(
                      controller:
                          controller ?? TextEditingController(text: text),
                      onSend: () {},
                      aiMode: aiMode,
                      onAiButtonTap: onAiButtonTap,
                      showGames: true,
                      showAttachImage: true,
                      showAttachVideo: true,
                      showVoiceMessage: true,
                      showCaptureVideo: true,
                      showTranslator: true,
                      onOpenGames: () {},
                      onAttachImage: () {},
                      onAttachVideo: () {},
                      onCaptureVideo: () {},
                      onOpenTranslator: () {},
                      onAttachFile: () {},
                    )
                    // The SAME tree with the AI parameters never named,
                    // which is what the other three construction sites
                    // (debate room, comment thread, image caption) and
                    // chat_screen.dart itself compile to today.
                    : ChatTextField(
                      controller:
                          controller ?? TextEditingController(text: text),
                      onSend: () {},
                      showGames: true,
                      showAttachImage: true,
                      showAttachVideo: true,
                      showVoiceMessage: true,
                      showCaptureVideo: true,
                      showTranslator: true,
                      onOpenGames: () {},
                      onAttachImage: () {},
                      onAttachVideo: () {},
                      onCaptureVideo: () {},
                      onOpenTranslator: () {},
                      onAttachFile: () {},
                    ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the capability is OFF: the composer is exactly as it was', () {
    // These four tests are the regression proof. They assert the
    // composer that ships TODAY, with no AI parameter passed at all --
    // the literal compiled shape of all four existing construction
    // sites. If adding aiMode changed anything for a caller that does
    // not use it, one of these fails.
    testWidgets('no AI button is drawn when onAiButtonTap is not passed', (
      tester,
    ) async {
      await pump(tester, includeAiMode: false);
      expect(
        find.byIcon(Icons.auto_awesome),
        findsNothing,
        reason:
            'the AI entry point must not exist for a caller that never '
            'asked for it -- three of four ChatTextField callers are not '
            'chat at all, and the capability is OFF in every environment',
      );
    });

    testWidgets('every control the composer draws today is still drawn', (
      tester,
    ) async {
      await pump(tester, includeAiMode: false);

      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    });

    testWidgets('typing still swaps the mic for Send and reveals the '
        'translator', (tester) async {
      final controller = TextEditingController();
      await pump(tester, includeAiMode: false, controller: controller);

      // The composer's own text-dependent behaviour, unchanged.
      expect(find.byIcon(Icons.send_rounded), findsNothing);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
      // Games gives up its slot to make room, as it does today.
      expect(find.byIcon(Icons.sports_esports_outlined), findsNothing);
    });

    testWidgets('the composer pill occupies the SAME rect it does on '
        '131bbfa6', (tester) async {
      // The strongest form of "byte-identical to today" this file can
      // assert: not "an icon is present" but the laid-out geometry.
      //
      // These three rects were MEASURED by running this exact tree
      // against `git show 131bbfa6:...chat_text_field.dart` and against
      // the patched file, and they agreed to the pixel. They matter
      // because this change adds an `AnimatedSize` as the composer
      // Row's new FIRST child and alters `visibleTrailingIconSlots`,
      // the width term feeding the line-count estimate that sets the
      // pill's height -- either could have moved the pill for a caller
      // that passes no AI parameter at all. Empty / one-line / wrapped
      // because the height only varies in the third.
      // A long single token would not wrap, so the wrapped case uses
      // words.
      final cases = <String, (String, Rect)>{
        'empty': ('', const Rect.fromLTWH(68, 6, 664, 48)),
        'one line': ('hi', const Rect.fromLTWH(12, 6, 720, 48)),
        'wrapped': (
          List.filled(20, 'word').join(' '),
          const Rect.fromLTWH(12, 6, 720, 97),
        ),
      };

      for (final entry in cases.entries) {
        final (text, rect) = entry.value;
        await pump(
          tester,
          includeAiMode: false,
          controller: TextEditingController(text: text),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('composer-pill'))),
          rect,
          reason:
              'the pill moved for a caller that passes no AI parameter '
              '(the "${entry.key}" case)',
        );
      }
    });

    testWidgets('aiMode:false with a callback present is identical to '
        'passing nothing', (tester) async {
      // The state Task 9 will leave a chat composer in while the
      // capability is on but the user has not entered AI mode. Nothing
      // may be hidden here: the ONLY difference from today is one extra
      // satellite.
      await pump(tester, onAiButtonTap: () {});

      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });
  });

  group('the AI entry point', () {
    testWidgets('appears only when a callback is supplied', (tester) async {
      await pump(tester, onAiButtonTap: () {});
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('is absent when onAiButtonTap is null even though aiMode '
        'is a declared parameter', (tester) async {
      // THE GATE (Ruling 19). A null callback is how every other
      // optional control in this composer is turned off -- translator,
      // games, attachments all follow it -- so the capability check
      // lands at the construction site and this widget stays
      // provider-free. A caller whose capability read is `false` passes
      // null and gets today's composer.
      await pump(tester);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
    });

    testWidgets('invokes its callback exactly once when tapped', (
      tester,
    ) async {
      var taps = 0;
      await pump(tester, onAiButtonTap: () => taps++);

      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('aiMode hides the controls AI sessions cannot carry', () {
    testWidgets('aiMode:true removes the attachment, camera, games and mic '
        'controls', (tester) async {
      await pump(tester, aiMode: true, onAiButtonTap: () {});

      expect(
        find.byIcon(Icons.attach_file_rounded),
        findsNothing,
        reason: 'AI Send addresses the session, not a message with a photo',
      );
      expect(
        find.byIcon(Icons.photo_camera_outlined),
        findsNothing,
        reason: 'a streak video cannot be a turn in an AI session',
      );
      expect(
        find.byIcon(Icons.sports_esports_outlined),
        findsNothing,
        reason: 'a game invitation is not an AI session turn',
      );
      expect(
        find.byIcon(Icons.mic_none_rounded),
        findsNothing,
        reason: 'the §4 command surface takes text, not audio',
      );
    });

    testWidgets('aiMode:true keeps the AI button itself, so the mode can be '
        'left', (tester) async {
      // The same argument game staging makes for keeping its own icon:
      // removing the control that got you here leaves no way back.
      await pump(tester, aiMode: true, onAiButtonTap: () {});
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('aiMode:true keeps Send reachable with text', (tester) async {
      await pump(tester, aiMode: true, onAiButtonTap: () {}, text: 'why');
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('aiMode:true shows Send rather than the mic on an empty '
        'field', (tester) async {
      // The mic is gone, so SOMETHING must own the trailing slot or the
      // composer renders a hole. It is disabled (nothing to send), which
      // is the state the send satellite already models for gameStaged.
      await pump(tester, aiMode: true, onAiButtonTap: () {});
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });
  });

  group('exiting AI mode restores every dismissed control', () {
    testWidgets('rebuilding the same tree with aiMode:false brings all four '
        'controls back', (tester) async {
      // Spec §3.3's literal "restore on exit". Rebuilt rather than
      // re-pumped from scratch so the SAME State object is reused: a
      // hide implemented by mutating State rather than by reading the
      // widget would pass a fresh pump and fail here.
      final controller = TextEditingController();
      await pump(
        tester,
        aiMode: true,
        onAiButtonTap: () {},
        controller: controller,
      );
      expect(find.byIcon(Icons.attach_file_rounded), findsNothing);

      await pump(
        tester,
        aiMode: false,
        onAiButtonTap: () {},
        controller: controller,
      );

      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    });

    testWidgets('the unsent chat draft survives a round trip through AI '
        'mode', (tester) async {
      // §3.3: "preserve the ordinary unsent chat draft". The controller
      // is the draft, and this widget must not clear it when the mode
      // changes. ChatScreen owns a SEPARATE controller for the AI draft
      // (Task 7), which is why this one is never reinterpreted.
      final controller = TextEditingController(text: 'see you at seven');
      await pump(
        tester,
        aiMode: false,
        onAiButtonTap: () {},
        controller: controller,
      );
      await pump(
        tester,
        aiMode: true,
        onAiButtonTap: () {},
        controller: controller,
      );
      await pump(
        tester,
        aiMode: false,
        onAiButtonTap: () {},
        controller: controller,
      );

      expect(controller.text, 'see you at seven');
      expect(find.text('see you at seven'), findsOneWidget);
    });
  });

  group('aiMode composes with gameStaged rather than contradicting it', () {
    testWidgets('a staged game still hides what it hides when aiMode is '
        'false', (tester) async {
      // Guards the one real risk of extending the existing conditions:
      // that `!aiMode` was ORed in somewhere and re-exposed a control
      // gameStaged had removed.
      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: ChatTextField(
                controller: TextEditingController(),
                onSend: () {},
                gameStaged: true,
                showGames: true,
                showAttachImage: true,
                showVoiceMessage: true,
                showCaptureVideo: true,
                onOpenGames: () {},
                onAttachImage: () {},
                onCaptureVideo: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.attach_file_rounded), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      // Still the only route back to the picker.
      expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
    });
  });
}

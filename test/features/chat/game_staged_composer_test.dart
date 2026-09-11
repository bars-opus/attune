import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the composer becomes once a game is waiting above it.
///
/// The field stops being "write a message or attach something": the
/// thing being sent is already chosen, so the field is an optional note
/// about it. Getting this wrong offers a photo the send path has
/// nowhere to put, or hides the only route back to the picker.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool gameStaged,
    String text = '',
    VoidCallback? onSend,
  }) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (context, _) => MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: ChatTextField(
                  controller: TextEditingController(text: text),
                  onSend: onSend ?? () {},
                  gameStaged: gameStaged,
                  showGames: true,
                  showAttachImage: true,
                  showVoiceMessage: true,
                  onOpenGames: () {},
                  onAttachImage: () {},
                ),
              ),
            ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a staged game hides attachments and the mic', (tester) async {
    await pump(tester, gameStaged: true);

    expect(
      find.byIcon(Icons.attach_file_rounded),
      findsNothing,
      reason: 'a photo cannot caption a game invitation',
    );
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
  });

  testWidgets('a staged game keeps the games icon, so it can be changed', (
    tester,
  ) async {
    await pump(tester, gameStaged: true);
    expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
  });

  testWidgets('the games icon survives typing while a game is staged', (
    tester,
  ) async {
    // Normally the icon gives up its slot once there is text. While a
    // game is staged it is the only way back to the picker, so it stays.
    await pump(tester, gameStaged: true, text: 'rematch?');
    expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
  });

  testWidgets('an empty caption still sends, because the game is the payload', (
    tester,
  ) async {
    var sends = 0;
    await pump(tester, gameStaged: true, onSend: () => sends++);

    await tester.tap(find.byIcon(Icons.send_rounded));
    expect(sends, 1, reason: 'the game could not be sent without a caption');
  });

  testWidgets('without a staged game the composer is unchanged', (
    tester,
  ) async {
    // The whole feature must be invisible when no game is staged.
    await pump(tester, gameStaged: false);

    expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
  });

  testWidgets('without a staged game an empty field cannot send', (
    tester,
  ) async {
    var sends = 0;
    await pump(tester, gameStaged: false, onSend: () => sends++);

    // The mic owns the slot when there is nothing to send.
    expect(find.byIcon(Icons.send_rounded), findsNothing);
    expect(sends, 0);
  });
}

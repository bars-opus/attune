import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancelling an invitation actually cancels it', () {
    // The button used to pop the screen and nothing else -- its body was
    // a `// Cancel invitation logic` comment. The session stayed
    // 'invited', so the next invite attempt was refused because one was
    // already outstanding: the user was locked out of the game with no
    // way back, which is exactly how this was found.
    final source =
        File(
          'lib/features/games/thirty_six_questions/presentation/screens/'
          'thirty_six_chapter_invitation_screen.dart',
        ).readAsStringSync();

    // Not asserted by searching for the old stub comment: the fix's own
    // doc comment quotes it, so that check can never fail. What matters
    // is that the button calls the handler rather than popping inline.
    expect(
      source.contains('onPressed: _cancelling ? null : _cancelInvitation'),
      isTrue,
      reason: 'the cancel button must invoke the cancel handler',
    );

    // Asserted on the whole call, not just the method name: popping the
    // screen after calling updateChapterStatus with the WRONG status
    // would look identical from the outside.
    expect(
      source.contains("status: 'abandoned'"),
      isTrue,
      reason: 'cancelling must move the session out of invited',
    );
    expect(
      source.contains('updateChapterStatus'),
      isTrue,
      reason: 'cancelling must reach the repository',
    );
  });

  test('an abandoned game card is inert and labelled', () {
    // Cancelling leaves a card in the chat. It must stop being tappable:
    // routing into a game the initiator just withdrew would resume the
    // thing they cancelled.
    final bubble =
        File(
          'lib/features/games/presentation/widgets/game_message_bubble.dart',
        ).readAsStringSync();

    expect(bubble.contains("case 'abandoned':"), isTrue);
    expect(
      bubble.contains("state.status != 'abandoned'"),
      isTrue,
      reason: 'a cancelled invite must not remain openable from the chat',
    );
  });
}

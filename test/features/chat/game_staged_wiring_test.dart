import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The composer's game mode reaches the actual screen.
///
/// The widget tests construct ChatTextField directly with
/// gameStaged: true, so they prove the composer BEHAVES correctly and
/// say nothing about whether the chat screen ever sets the flag. It did
/// not: the edit that was supposed to pass it silently failed to match,
/// every test stayed green, and on a real phone the camera, attachments
/// and mic never went away -- and Send did nothing at all, because
/// _send() returned on the empty-text guard before reaching the game.
///
/// A source check rather than a screen test: ChatScreen needs Supabase,
/// a relationship and a live conversation to build, which is why it has
/// no widget test to hang this on.
void main() {
  final chatScreen =
      File(
        'lib/features/chat/presentation/screens/chat_screen.dart',
      ).readAsStringSync();

  test('the chat screen tells the composer a game is staged', () {
    expect(
      chatScreen.contains('gameStaged: stagedGame != null'),
      isTrue,
      reason: 'the composer keeps its attachments and mic while a game waits',
    );
  });

  test('send routes a staged game before the empty-text guard', () {
    // Order matters: a game with no caption is still a game, so the
    // staged branch must come first or Send is inert.
    final sendBody = chatScreen.substring(
      chatScreen.indexOf('Future<void> _send() async {'),
      chatScreen.indexOf('void _setReplyTarget('),
    );
    final stagedAt = sendBody.indexOf('_sendStagedGame(');
    final emptyGuardAt = sendBody.indexOf('if (text.isEmpty) return;');

    expect(stagedAt, isNot(-1), reason: 'send ignores a staged game');
    expect(
      stagedAt,
      lessThan(emptyGuardAt),
      reason: 'an uncaptioned game returns on the empty-text guard',
    );
  });

  test('the staged game bar is rendered alongside the composer', () {
    // Not "else if": the bar sits ABOVE the field, and both show.
    expect(chatScreen.contains('GameComposerBar('), isTrue);
    expect(
      chatScreen.contains('if (conversation.canSend && stagedGame != null)'),
      isTrue,
    );
  });
}

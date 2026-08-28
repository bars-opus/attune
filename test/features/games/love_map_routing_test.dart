import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Love Map has a route, and the chat launcher reaches it', () {
    final router =
        File('lib/app/routing/app_router.dart').readAsStringSync();
    expect(router, contains("static const String loveMap = '/loveMap'"));
    expect(router, contains("name: 'loveMap'"));

    // The session games shipped with routes nothing called, which is why
    // every one of them rendered "Question unavailable". This pins the
    // caller as well as the route.
    final chat = File(
      'lib/features/chat/presentation/screens/chat_screen.dart',
    ).readAsStringSync();
    expect(chat, contains("pushNamed('loveMap')"));

    final sheet = File(
      'lib/features/games/presentation/widgets/chat_games_sheet.dart',
    ).readAsStringSync();
    expect(sheet, contains('ChatGameDestination.loveMap'));
  });
}

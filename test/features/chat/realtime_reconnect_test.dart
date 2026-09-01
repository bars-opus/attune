import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Source-level, not behavioural: the reconnect path lives in the
  // Supabase channel callback, which a fake repository cannot exercise --
  // the fakes replace the very layer being tested. What must hold is that
  // .subscribe() is never called bare.
  //
  // A bare .subscribe() is how this shipped: the websocket died with the
  // network, Supabase reconnected the socket, and the app was never told
  // it had missed events. Messages sent while a partner was offline never
  // arrived at all -- not in the chat, not in the conversation list -- and
  // read receipts stopped updating, until the screen was rebuilt by
  // navigating away and back.
  test('realtime channels handle resubscribe after a dropped connection', () {
    final source =
        File(
          'lib/features/chat/data/repositories/supabase_chat_repository.dart',
        ).readAsStringSync();

    expect(
      source.contains('.subscribe();'),
      isFalse,
      reason:
          'a bare .subscribe() cannot detect a reconnect, so the client '
          'silently stops receiving events after the network returns',
    );

    // Both channels -- the per-chat one and the inbox one -- must react to
    // a successful (re)subscribe by emitting, which makes their listeners
    // refetch and close the gap opened while the socket was down.
    expect(
      'RealtimeSubscribeStatus.subscribed'.allMatches(source).length,
      greaterThanOrEqualTo(2),
      reason: 'both the chat channel and the inbox channel must resync',
    );
  });
}

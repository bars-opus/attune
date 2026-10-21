// test/features/chat/send_payload_guard_test.dart
//
// Chat review #19: is_system_notice is server-only (messages_system_notice_
// guard). The client's insert must not carry the column at all -- an old
// client sending `false` still works, but the new one has no business
// naming it, and the fake repository must mirror that.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the chat insert payload never names is_system_notice', () {
    final src =
        File(
          'lib/features/chat/data/repositories/supabase_chat_repository.dart',
        ).readAsStringSync();
    final insert = src.substring(
      src.indexOf("Future<Message> sendTextMessage("),
    );
    final body = insert.substring(0, insert.indexOf('return _hydrateMessage'));
    expect(body.contains("'is_system_notice'"), isFalse);
    expect(body.contains('isSystemNotice'), isFalse);
  });

  test('the screenshot notice is an RPC, not an insert', () {
    final src =
        File(
          'lib/features/chat/data/repositories/supabase_chat_repository.dart',
        ).readAsStringSync();
    expect(src, contains(".rpc('send_screenshot_notice'"));
  });
}

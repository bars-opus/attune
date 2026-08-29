import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the outbox treats a streak as a media send', () {
    // _attemptSend gates uploading on an allowlist of media types. With
    // 'streak' missing, no intent was created, no file uploaded, and
    // mediaKey stayed null — so the insert carried neither content nor
    // media_url and died on messages_payload_present.
    //
    // This is the FIFTH place a media_type allowlist had to learn about
    // streaks, after both CHECK constraints, the insert trigger and the
    // upload-intent RPC.
    final src = File(
      'lib/features/chat/presentation/state/chat_state.dart',
    ).readAsStringSync();

    final gate = RegExp(
      r'final isMediaSend\s*=\s*\(([\s\S]{0,300}?)\)\s*&&',
    ).firstMatch(src)?.group(1);

    expect(gate, isNotNull, reason: 'isMediaSend gate not found');
    for (final type in ['image', 'audio', 'video', 'streak']) {
      expect(
        gate,
        contains("'$type'"),
        reason: '$type must upload before its message row is inserted',
      );
    }
  });
}

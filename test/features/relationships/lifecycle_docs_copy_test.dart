// Spec 3a (F1 (1)-(4); 05 D.3 #3): the manual says what ending and pausing
// actually do.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src =
      File(
        'lib/app/documentations/user_manual/data/chat_docs.dart',
      ).readAsStringSync();

  test('ending: 30 days to read, then closed, deleted after 12 months', () {
    expect(src, contains('readable for both of you for 30 days'));
    expect(src, contains('deleted 12 months after it closes'));
    // Saying a chat closes when either starts a new relationship would tell
    // an ex why theirs closed early (final review MIN-6).
    expect(src, isNot(contains('if either of you starts a new relationship')));
    expect(
      src,
      isNot(
        contains(
          'makes chat read-only, not deleted. You can still scroll back',
        ),
      ),
    );
  });

  test('no one is notified, and seal and pause are explained', () {
    expect(src, contains("id: 'faq_chat_ending_notice'"));
    // The source escapes the apostrophe.
    expect(src, contains(r"Your partner isn\'t sent a notification"));
    expect(src, contains("id: 'faq_chat_seal'"));
    expect(src, contains('Seal my side now'));
    expect(src, contains("id: 'faq_chat_pause'"));
    expect(src, contains('Pause our shared space'));
  });
}

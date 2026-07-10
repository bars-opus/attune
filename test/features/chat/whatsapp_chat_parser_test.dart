import 'dart:convert';
import 'dart:typed_data';

import 'package:attune/features/chat/domain/services/whatsapp_chat_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = WhatsAppChatParser(maxFileBytes: 4096, maxMessages: 10);

  Uint8List exportBytes(String value) => Uint8List.fromList(utf8.encode(value));

  test('parses two-person Android export and preserves multiline text', () {
    final result = parser.parse(
      fileName: 'WhatsApp Chat.txt',
      bytes: exportBytes(
        '05/07/2026, 09:10 - Ama: First line\n'
        'second line\n'
        '05/07/2026, 09:11 - Kojo: Reply',
      ),
    );

    expect(result.participantLabels, ['Ama', 'Kojo']);
    expect(result.messages, hasLength(2));
    expect(result.messages.first.content, 'First line\nsecond line');
    expect(result.messages.first.sourceLine, 1);
  });

  test('omits media placeholders', () {
    final result = parser.parse(
      fileName: 'chat.txt',
      bytes: exportBytes(
        '[05/07/2026, 9:10 AM] Ama: <Media omitted>\n'
        '[05/07/2026, 9:11 AM] Ama: Text only\n'
        '[05/07/2026, 9:12 AM] Kojo: Reply',
      ),
    );

    expect(result.messages.map((message) => message.content), ['Text only', 'Reply']);
  });

  test('rejects exports with more than two participant labels', () {
    expect(
      () => parser.parse(
        fileName: 'chat.txt',
        bytes: exportBytes(
          '05/07/2026, 09:10 - Ama: One\n'
          '05/07/2026, 09:11 - Kojo: Two\n'
          '05/07/2026, 09:12 - Esi: Three',
        ),
      ),
      throwsA(isA<ChatImportParseException>()),
    );
  });

  test('rejects configured message-count overflow', () {
    const limited = WhatsAppChatParser(maxMessages: 1);
    expect(
      () => limited.parse(
        fileName: 'chat.txt',
        bytes: exportBytes(
          '05/07/2026, 09:10 - Ama: One\n'
          '05/07/2026, 09:11 - Kojo: Two',
        ),
      ),
      throwsA(isA<ChatImportParseException>()),
    );
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:attune/features/chat/domain/entities/chat_import.dart';
import 'package:crypto/crypto.dart';

class ChatImportParseException implements Exception {
  final String message;
  const ChatImportParseException(this.message);

  @override
  String toString() => message;
}

class WhatsAppChatParser {
  const WhatsAppChatParser({
    this.maxFileBytes = 10 * 1024 * 1024,
    this.maxMessages = 100000,
  });

  final int maxFileBytes;
  final int maxMessages;

  static final _androidLine = RegExp(
    r'^(\d{1,2})[\/.](\d{1,2})[\/.](\d{2,4}),?\s+(\d{1,2}):(\d{2})(?:\s*([AP]M))?\s+-\s+([^:]+):\s?(.*)$',
    caseSensitive: false,
  );
  static final _iosLine = RegExp(
    r'^\[(\d{1,2})[\/.](\d{1,2})[\/.](\d{2,4}),?\s+(\d{1,2}):(\d{2})(?::\d{2})?(?:\s*([AP]M))?\]\s+([^:]+):\s?(.*)$',
    caseSensitive: false,
  );

  ParsedChatImport parse({required Uint8List bytes, required String fileName}) {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const ChatImportParseException(
        'This export is empty or exceeds the allowed file size.',
      );
    }
    final lowerName = fileName.toLowerCase();
    final textBytes = switch (lowerName) {
      _ when lowerName.endsWith('.txt') => bytes,
      _ when lowerName.endsWith('.zip') => _textFromZip(bytes),
      _ =>
        throw const ChatImportParseException(
          'Choose a WhatsApp .txt or .zip export without media.',
        ),
    };
    final fingerprint = sha256.convert(textBytes).toString();
    final text = utf8
        .decode(textBytes, allowMalformed: false)
        .replaceFirst('\ufeff', '');
    final parsed = <ParsedChatImportMessage>[];
    final labels = <String>{};
    ParsedChatImportMessage? current;

    final lines = const LineSplitter().convert(text);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final match = _androidLine.firstMatch(line) ?? _iosLine.firstMatch(line);
      if (match == null) {
        if (current != null && line.trim().isNotEmpty) {
          current = ParsedChatImportMessage(
            sourceLine: current.sourceLine,
            createdAt: current.createdAt,
            senderLabel: current.senderLabel,
            content: '${current.content}\n$line',
          );
          parsed[parsed.length - 1] = current;
        }
        continue;
      }

      final sender = match.group(7)!.trim();
      final content = match.group(8) ?? '';
      if (_isMediaPlaceholder(content) || content.trim().isEmpty) continue;
      final timestamp = _parseTimestamp(match);
      labels.add(sender);
      if (labels.length > 2) {
        throw const ChatImportParseException(
          'This export contains more than two participant labels.',
        );
      }
      current = ParsedChatImportMessage(
        sourceLine: index + 1,
        createdAt: timestamp,
        senderLabel: sender,
        content: content,
      );
      parsed.add(current);
      if (parsed.length > maxMessages) {
        throw const ChatImportParseException(
          'This export contains more messages than can be imported safely.',
        );
      }
    }

    if (parsed.isEmpty || labels.length != 2) {
      throw const ChatImportParseException(
        "We couldn't read this as a two-person WhatsApp export.",
      );
    }
    parsed.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.sourceLine.compareTo(b.sourceLine);
    });
    return ParsedChatImport(
      source: 'whatsapp',
      fingerprint: fingerprint,
      participantLabels: labels.toList(growable: false)..sort(),
      messages: List.unmodifiable(parsed),
    );
  }

  Uint8List _textFromZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final textFiles = archive.files.where(
      (file) => file.isFile && file.name.toLowerCase().endsWith('.txt'),
    );
    if (textFiles.length != 1) {
      throw const ChatImportParseException(
        'The WhatsApp archive must contain exactly one text export.',
      );
    }
    final file = textFiles.single;
    if (file.size > maxFileBytes || file.content is! List<int>) {
      throw const ChatImportParseException('The text export is too large.');
    }
    return Uint8List.fromList(file.content as List<int>);
  }

  DateTime _parseTimestamp(RegExpMatch match) {
    final first = int.parse(match.group(1)!);
    final second = int.parse(match.group(2)!);
    var year = int.parse(match.group(3)!);
    var hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final period = match.group(6)?.toUpperCase();
    if (year < 100) year += 2000;
    if (period == 'PM' && hour < 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    // WhatsApp exports follow the device locale. Prefer day-first for Ghana;
    // an unambiguous first field above 12 is always the day.
    final day = first;
    final month = second;
    try {
      final value = DateTime(year, month, day, hour, minute);
      if (value.year != year || value.month != month || value.day != day) {
        throw const FormatException();
      }
      return value;
    } catch (_) {
      throw const ChatImportParseException(
        "We couldn't read one of the dates in this WhatsApp export.",
      );
    }
  }

  bool _isMediaPlaceholder(String content) {
    final normalized = content.trim().toLowerCase();
    return normalized == '<media omitted>' ||
        normalized == 'image omitted' ||
        normalized == 'video omitted' ||
        normalized == 'audio omitted' ||
        normalized.contains('attached:');
  }
}

import 'package:attune/features/chat/domain/services/relationship_chat_name_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateRelationshipChatName', () {
    test('accepts a normal name and trims surrounding whitespace', () {
      final result = validateRelationshipChatName('  Japerl34  ');
      expect(result.isValid, isTrue);
      expect(result.trimmedName, 'Japerl34');
      expect(result.errorMessage, isNull);
    });

    test('rejects an empty string', () {
      final result = validateRelationshipChatName('');
      expect(result.isValid, isFalse);
      expect(result.trimmedName, isNull);
      expect(result.errorMessage, isNotNull);
    });

    test('rejects a whitespace-only string', () {
      final result = validateRelationshipChatName('   ');
      expect(result.isValid, isFalse);
    });

    test('accepts exactly 30 trimmed characters (boundary)', () {
      final name = 'a' * 30;
      final result = validateRelationshipChatName(name);
      expect(result.isValid, isTrue);
      expect(result.trimmedName, name);
    });

    test('rejects 31 trimmed characters (boundary)', () {
      final name = 'a' * 31;
      final result = validateRelationshipChatName(name);
      expect(result.isValid, isFalse);
    });

    test(
      'length is measured after trimming — 30 chars plus padding whitespace '
      'still passes',
      () {
        final name = '  ${'a' * 30}  ';
        final result = validateRelationshipChatName(name);
        expect(result.isValid, isTrue);
        expect(result.trimmedName, 'a' * 30);
      },
    );

    test('accepts a single character (minimum boundary)', () {
      final result = validateRelationshipChatName('J');
      expect(result.isValid, isTrue);
      expect(result.trimmedName, 'J');
    });

    test('accepts unicode/emoji content within the length limit', () {
      final result = validateRelationshipChatName('Japerl 💕');
      expect(result.isValid, isTrue);
      expect(result.trimmedName, 'Japerl 💕');
    });
  });
}

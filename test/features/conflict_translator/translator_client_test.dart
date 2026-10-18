// Spec 8 (plan review I9, P7, P8, M5; research 06 A8): the translator sends
// only the message (no profile, no partner tone), in a chosen register; the
// seventh need reads naturally; nothing counts how often a need came up.
import 'dart:io';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/conflict_translator/data/models/translator_request.dart';
import 'package:attune/features/conflict_translator/data/models/translator_response.dart';
import 'package:attune/features/conflict_translator/data/repositories/translator_repository.dart';
import 'package:attune/features/conflict_translator/domain/services/translator_pattern_service.dart';
import 'package:attune/features/conflict_translator/presentation/providers/translator_register_preference.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('the request carries the message, the relationship and the register only', () {
    final json = const TranslatorRequest(message: 'hello there', relationshipId: 'r1', register: TranslatorRegister.plain).toJson();
    expect(json, {'message': 'hello there', 'relationship_id': 'r1', 'register': 'plain'});
  });

  test('the seventh need reads naturally', () {
    expect(translatorNeedDisplay('communal_obligation'), 'to honour family and community');
    expect(translatorNeedDisplay('rest'), 'for relief');
  });

  test('a writer card is recognised, not shown as an empty rewrite', () {
    expect(TranslatorResponse.fromJson({'status': 'writer_resources'}).writerResources, isTrue);
    expect(TranslatorResponse.fromJson({'rewrite': 'x', 'rewrite_confidence': 'high'}).writerResources, isFalse);
  });

  test('the register is remembered on this device only, NVC by default', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    expect(c.read(translatorRegisterProvider), TranslatorRegister.nvc);
    await c.read(translatorRegisterProvider.notifier).set(TranslatorRegister.plain);
    expect(prefs.getString('translator_register'), 'plain');
  });

  // Sync audit: the daily limit is its own answer, never "try again".
  test('the daily limit is recognised, with the server\'s words', () {
    final limit = translatorFailure(
      const FunctionException(
        status: 429,
        details: {
          'error': true,
          'code': 'RATE_LIMITED',
          'message': "You've used the translator a lot today. Try again tomorrow.",
        },
      ),
    );
    expect(limit, isA<TranslatorLimitReached>());
    expect(
      (limit as TranslatorLimitReached).message,
      "You've used the translator a lot today. Try again tomorrow.",
    );
    expect(
      translatorFailure(const FunctionException(status: 429)),
      isA<TranslatorLimitReached>(),
    );
    expect(
      translatorFailure(const FunctionException(status: 500)),
      isNot(isA<TranslatorLimitReached>()),
    );
  });

  test('no counted insight ("N of your last 6") is written anywhere', () {
    for (final f in Directory('lib/features/conflict_translator').listSync(recursive: true).whereType<File>()) {
      final src = f.readAsStringSync();
      expect(src.contains('personal_insights'), isFalse, reason: f.path);
      expect(src.contains('of your last'), isFalse, reason: f.path);
    }
  });
}

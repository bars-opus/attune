import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// §11 PERMANENT PRODUCT CONSTRAINTS — the rules the spec says can never be
/// reversed. They were prose only: nothing failed if a future change broke
/// one.
///
/// These tests read the source rather than exercising behaviour, which is
/// the right shape here — the constraints are architectural properties
/// ("this table has no user_id", "this output is filtered"), and a
/// behavioural test would need a live model to violate them.
void main() {
  /// §11 #8: permanently banned from all AI outputs.
  const bannedWords = [
    'toxic',
    'narcissist',
    'codependent',
    'disorder',
    'broken',
  ];

  /// Edge functions whose model output reaches a user as free text.
  const userFacingAiFunctions = [
    'generate-verdict',
    'analyse-session',
    'analyse-journal-entry',
    'translate-conflict',
    'generate-thirty-six-reflection',
  ];

  group('§11 #8 — no diagnosis language', () {
    for (final fn in userFacingAiFunctions) {
      test('$fn instructs the model against the banned words', () {
        final file = File('supabase/functions/$fn/index.ts');
        if (!file.existsSync()) return;
        final src = file.readAsStringSync().toLowerCase();

        // A prompt instruction is the floor. It is not a guarantee — the
        // model can still emit one — which is why the paths that publish
        // free text also need the output filter asserted below.
        final mentions =
            bannedWords.where((w) => src.contains(w)).length;
        expect(
          mentions,
          greaterThan(0),
          reason: '$fn produces user-facing text but never names the '
              'banned words, so the model is not even asked to avoid them',
        );
      });
    }

    test('generate-verdict filters its output, not just its prompt', () {
      final src = File('supabase/functions/generate-verdict/index.ts')
          .readAsStringSync();

      // The verdict is the highest-stakes output: it is the one the spec
      // calls a "sourced pattern summary", and it ingests
      // suggested_insight from analyse-session, which is itself unfiltered.
      expect(
        src,
        contains('BANNED_PATTERNS'),
        reason: 'the verdict must validate output, not merely request it',
      );

      // Assert against the DENYLIST BLOCK, not the whole file: every banned
      // word also appears in the prompt text, so a file-wide `contains`
      // passes even when a word has been dropped from the regex that
      // actually filters output.
      final block = RegExp(r'BANNED_PATTERNS\s*=\s*\[(.*?)\];',
              dotAll: true)
          .firstMatch(src)
          ?.group(1);
      expect(block, isNotNull, reason: 'BANNED_PATTERNS block not found');

      for (final w in bannedWords) {
        expect(
          block,
          contains(w),
          reason: '"\$w" is missing from the verdict denylist regex, so the '
              'model can emit it and the filter will not catch it',
        );
      }
    });

    test('analyse-journal-entry filters its output, not just its prompt', () {
      // Its summary is returned straight to the caller, so a prompt
      // instruction is the only thing between a banned word and a user.
      // The runtime filter fails closed — a match returns null and the
      // caller falls back to fixed boilerplate — so the words belong in
      // it, not only in the prompt.
      final src = File('supabase/functions/analyse-journal-entry/index.ts')
          .readAsStringSync();

      final block = RegExp(r'RUNTIME_PATTERNS\s*=\s*\[(.*?)\];',
              dotAll: true)
          .firstMatch(src)
          ?.group(1);
      expect(block, isNotNull, reason: 'RUNTIME_PATTERNS block not found');

      for (final w in bannedWords) {
        expect(
          block,
          contains(w),
          reason: '"\$w" is not filtered from the journal summary, which is '
              'returned directly to the user',
        );
      }
    });

    test('the disclaimer is fixed client-side, never model output', () {
      // §8.5: "disclaimer: fixed string appended by client code (never
      // model output)".
      final src = File('supabase/functions/generate-verdict/index.ts')
          .readAsStringSync();
      expect(src, contains('FIXED_DISCLAIMER'));
    });
  });

  group('§11 #9 — patterns has no user_id', () {
    test('no migration ever adds user_id to the patterns table', () {
      // "This is enforced at the schema level, not just in code."
      final migrations = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'));

      final offenders = <String>[];
      for (final m in migrations) {
        final src = m.readAsStringSync();
        // Look for a patterns-table definition or alteration naming user_id.
        final createsPatterns = RegExp(
          r'(CREATE TABLE[^;]*?public\.patterns\b[^;]*?user_id|'
          r'ALTER TABLE\s+(?:IF EXISTS\s+)?public\.patterns\b[^;]*?ADD COLUMN[^;]*?user_id)',
          caseSensitive: false,
          dotAll: true,
        );
        if (createsPatterns.hasMatch(src)) {
          offenders.add(m.uri.pathSegments.last);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'patterns describes relationship dynamics, not individuals',
      );
    });
  });

  group('§11 #6 — the safety system is never LLM-dependent', () {
    test('safety triggers are keyword matching, not a model call', () {
      final dir = Directory('supabase/functions');
      if (!dir.existsSync()) return;

      final safetyFns = dir
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('safety'));

      for (final fn in safetyFns) {
        final index = File('${fn.path}/index.ts');
        if (!index.existsSync()) continue;
        final src = index.readAsStringSync();
        expect(
          src.contains('anthropic.com') || src.contains('claude-'),
          isFalse,
          reason: '${fn.uri.pathSegments.last} routes safety through a '
              'model; §11 #6 forbids it — a model can fail, hallucinate, '
              'or be unavailable',
        );
      }
    });
  });
}

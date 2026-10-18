// Spec 8 (plan review P1, M7, M10, I16, §6.3): what must hold before launch.
//
// 1. No clinician placeholder ("[DRAFT]") is reachable with its flag on:
//    every file carrying one (outside comments) is mapped to the flags that
//    gate it, and none of those flags is seeded on in the migrations.
// 2. The AI resume file stays disabled, never schedules the Verdict, and
//    carries the resume gates; the dev snippet resumes exactly three jobs.
// 3. Spec 8's flags are seeded off.
//
// What this cannot see (final review I-8): a flag turned on outside the
// migrations — a dev snippet such as supabase/sql/dev_enable_spec8_flags.sql
// or a hand edit in production. Before flipping any flag below in
// production, the content it gates must be signed off and its marker
// removed. A draft is marked either by "[DRAFT]" outside comments or by a
// versioned corpus whose config_version ends in "-draft".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// File (or directory prefix) -> the flags that gate every way to it.
const _draftGates = <String, List<String>>{
  'lib/features/conflict_toolkit/': ['conflict_toolkit'],
  'lib/features/safety/self_check/': ['private_safety_check'],
  'lib/features/safety/presentation/outside_perspective_screen.dart': [
    'private_safety_check',
  ],
  'supabase/migrations/20261018150100_pause_messages.sql': ['conflict_toolkit'],
  'lib/features/ai_assistant/presentation/widgets/assistant_notice_card.dart': [
    'private_safety_check',
  ],
  // The victimisation list runs only with this flag (featureFlagEnabled).
  'supabase/functions/_shared/self_disclosure.ts': ['private_safety_check'],
};

Iterable<File> _files(String dir, bool Function(String) keep) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => keep(f.path));

bool _draftOutsideComments(String src) => src
    .split('\n')
    .map((l) => l.trimLeft())
    .where((l) => !l.startsWith('//') && !l.startsWith('--') && !l.startsWith('*'))
    .any((l) => l.contains('[DRAFT]') || RegExp(r'''config_version:\s*["'][^"']*-draft["']''').hasMatch(l));

/// The last value each flag is given anywhere in the migrations, in order.
Map<String, bool> _seededFlags() {
  final flags = <String, bool>{};
  final migrations = _files('supabase/migrations', (p) => p.endsWith('.sql')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final insert = RegExp(
    r"INSERT INTO public\.feature_flags[^;]*?VALUES([^;]*?)(ON CONFLICT[^;]*)?;",
    caseSensitive: false,
    dotAll: true,
  );
  final pair = RegExp(r"\(\s*'([a-z0-9_]+)'\s*,\s*(true|false)", caseSensitive: false);
  final update = RegExp(
    r"UPDATE public\.feature_flags\s+SET enabled\s*=\s*(true|false)\s+WHERE key\s*(?:=\s*'([a-z0-9_]+)'|IN\s*\(([^)]*)\))",
    caseSensitive: false,
  );
  for (final f in migrations) {
    final src = f.readAsStringSync();
    for (final m in insert.allMatches(src)) {
      final overwrites = (m.group(2) ?? '').toUpperCase().contains('DO UPDATE');
      for (final p in pair.allMatches(m.group(1)!)) {
        if (overwrites || !flags.containsKey(p.group(1))) {
          flags[p.group(1)!] = p.group(2)!.toLowerCase() == 'true';
        }
      }
    }
    for (final m in update.allMatches(src)) {
      final on = m.group(1)!.toLowerCase() == 'true';
      final keys = m.group(2) != null
          ? [m.group(2)!]
          : RegExp(r"'([a-z0-9_]+)'").allMatches(m.group(3)!).map((k) => k.group(1)!);
      for (final k in keys) {
        flags[k] = on;
      }
    }
  }
  return flags;
}

void main() {
  test('no [DRAFT] placeholder is reachable with its flag on', () {
    final flags = _seededFlags();
    final carriers = [
      ..._files('lib', (p) => p.endsWith('.dart')),
      ..._files('supabase/functions', (p) => p.endsWith('.ts') && !p.endsWith('.test.ts')),
      ..._files('supabase/migrations', (p) => p.endsWith('.sql')),
    ].where((f) => _draftOutsideComments(f.readAsStringSync()));
    final problems = <String>[];
    for (final f in carriers) {
      final gate = _draftGates.entries
          .where((e) => f.path == e.key || f.path.startsWith(e.key))
          .map((e) => e.value)
          .firstOrNull;
      if (gate == null) {
        problems.add('${f.path}: [DRAFT] with no gating flag on record');
      } else {
        for (final flag in gate) {
          if (flags[flag] != false) {
            problems.add('${f.path}: gated by $flag, seeded ${flags[flag] ?? 'nowhere'}');
          }
        }
      }
    }
    expect(problems, isEmpty);
    // The scanner sees what it should.
    expect(carriers.map((f) => f.path), containsAll([
      'lib/features/conflict_toolkit/data/toolkit_texts.dart',
      // The second marker: a versioned draft corpus.
      'supabase/functions/_shared/self_disclosure.ts',
    ]));
  });

  test("Spec 8's flags are seeded off", () {
    final flags = _seededFlags();
    for (final k in ['private_safety_check', 'conflict_toolkit', 'chat_hostility_signals_enabled']) {
      expect(flags[k], isFalse, reason: k);
    }
  });

  test('the AI resume file stays disabled, without the Verdict, with its gates', () {
    expect(File('supabase/migrations/20260931160000_resume_ai_jobs.sql').existsSync(), isFalse);
    final src = File('supabase/migrations/20260931160000_resume_ai_jobs.sql.disabled').readAsStringSync();
    final code = src.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
    expect(code.contains('generate-verdict'), isFalse);
    for (final job in ['analyse-message-backlog', 'analyse-session-sweep', 'compute-pulse-weekly']) {
      expect(code, contains("'$job'"));
    }
    for (final gate in [
      'relationship_ai_suppressed',
      'co-framing',
      'adversarial',
      'chat_hostility_signals_enabled',
      'ai_provider_calls',
      'patterns',
      'analysis_sessions',
      'pulse_scores',
      'GEMINI_API_KEY',
      'Verdict cron stays off',
      // Final review I-8.
      'never sets messages aside or cancels a job on an unreadable answer',
      'ai-sessions shared window',
      'relationship_id IS NULL',
      'SELECT count(*) FROM public.patterns',
      'flipped outside the migrations',
    ]) {
      expect(src, contains(gate), reason: gate);
    }
  });

  test('one dev snippet resumes exactly the three jobs; the old ones are gone', () {
    final src = File('supabase/sql/dev_resume_ai_jobs.sql').readAsStringSync();
    final jobs = RegExp(r"cron\.schedule\(\s*'([a-z0-9-]+)'").allMatches(src).map((m) => m.group(1)).toList();
    expect(jobs, ['analyse-message-backlog', 'analyse-session-sweep', 'compute-pulse-weekly']);
    for (final old in ['schedule_analyse_message.sql', 'schedule_analyse_session.sql', 'schedule_generate_verdict.sql']) {
      expect(File('supabase/sql/$old').existsSync(), isFalse, reason: old);
    }
  });
}

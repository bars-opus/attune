import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec 1 W5 (§7.1 "Never a type or score", the permanent constraint: no
/// couple type, score or partner scorecard, no couple report combining
/// both people's insights). About us is plain facts the couple chose to
/// tell. Its model and its tables are read only inside its own feature,
/// never by an AI loader or a prompt builder, so nothing can turn the
/// answers into a label. The SQL side is couple_profile_contracts.sql
/// section A.
void main() {
  /// The About us model, its provider and the server names.
  final aboutUsNames = RegExp(
    r'\b(CoupleProfile|CoupleStage|AboutUsPatch|coupleProfileProvider|coupleProfileDraftProvider)\b'
    r'|couple_profiles|couple_profile_drafts|get_couple_profile|update_couple_profile'
    r'|get_my_couple_profile_draft|update_my_couple_profile_draft',
  );

  List<File> dartFiles(String root) =>
      Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('/generated/'))
          .toList();

  test(
    'the About us model is read only inside lib/features/couple_profile',
    () {
      final outside = [
        for (final f in dartFiles('lib'))
          if (!f.path.startsWith('lib/features/couple_profile/') &&
              aboutUsNames.hasMatch(f.readAsStringSync()))
            f.path,
      ];
      expect(
        outside,
        isEmpty,
        reason:
            'About us is plain facts, never a type or a score: only its own '
            'feature reads the model (others use its entry points).',
      );
    },
  );

  // Batch-1 review minor 4: the tables' member SELECT returns the
  // `*_changed_by` account ids. The app reads About us only through
  // get_couple_profile / get_my_couple_profile_draft, which send a first
  // name or "me", never an id, so no Dart file (About us's own included)
  // reads either table directly.
  test('the app never reads the About us tables directly', () {
    final direct = RegExp(r'''\.from\(\s*['"]couple_profile(s|_drafts)['"]''');
    final readers = [
      for (final f in dartFiles('lib'))
        if (direct.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(readers, isEmpty);
    expect(
      direct.hasMatch("client.from('couple_profiles').select()"),
      isTrue,
      reason: 'the check itself',
    );
    expect(direct.hasMatch('.from("couple_profile_drafts")'), isTrue);
  });

  test('no edge function reads About us (no AI loader, no prompt)', () {
    final readers = [
      for (final f
          in Directory(
            'supabase/functions',
          ).listSync(recursive: true).whereType<File>())
        if (RegExp(
          r'couple_profile|about_us|aboutUs',
          caseSensitive: false,
        ).hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(readers, isEmpty);
  });

  test('W1\'s set_user_path_internal named no W5 table (review I-6)', () {
    final sql =
        File(
          'supabase/migrations/20261025100300_paths_and_home_state.sql',
        ).readAsStringSync();
    final start = sql.indexOf(
      'CREATE OR REPLACE FUNCTION public.set_user_path_internal(',
    );
    final body = sql.substring(start, sql.indexOf('\n\$\$;', start));
    expect(body, isNot(contains('couple_profile')));
  });
}

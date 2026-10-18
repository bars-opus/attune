// Spec 3b (R3b-7; 05 D.3 #1): the delete-account confirm and the manual say
// what deletion actually does to a shared space.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the confirm says the shared space ends and what leaves it', () {
    // Adjacent string literals joined, as Dart joins them.
    final src = File('lib/features/settings/widgets/delete_account_action.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r"""['"]\s*\n\s*(//[^\n]*\n\s*)*['"]"""), '');
    expect(src, contains("If you're in a shared space, it ends; your messages, photos and game answers are removed from it."));
    // Not everyone deleting an account is in one (final review M-4).
    expect(src, isNot(contains("'Your shared space ends; ")));
    expect(src, isNot(contains('Anything you shared with a partner is anonymised')));
  });

  test('the manual explains deletion and the 12-month rule', () {
    final src = File('lib/app/documentations/user_manual/data/about_attune_docs.dart').readAsStringSync();
    expect(src, contains("id: 'faq_about_delete_account'"));
    expect(src, contains('What happens to my data if I delete my account?'));
    expect(src, contains('12 months after it closes'));
  });
}

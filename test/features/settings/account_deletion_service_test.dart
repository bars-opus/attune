import 'package:attune/features/settings/data/account_deletion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // AccountDeletionService is a thin, deliberate wrapper: it must not gain
  // the ability to name WHICH account to delete (the edge function derives
  // that from the verified JWT alone), and it must not swallow a
  // server-side failure into a success. Exercising the live Supabase
  // functions client needs a real session, so these cover the contract
  // that is testable without one — the exception type that every call site
  // branches on.
  group('AccountDeletionException', () {
    test('carries a user-facing message', () {
      const exception = AccountDeletionException('Could not delete');
      expect(exception.message, 'Could not delete');
    });

    test('toString is prefixed and leaks no identifiers', () {
      const exception = AccountDeletionException('Could not delete');
      final text = exception.toString();
      expect(text, contains('AccountDeletionException'));
      expect(text, contains('Could not delete'));
      // No stack traces, ids, or emails — §10 / checklist 5.5.
      expect(text, isNot(contains('@')));
      expect(text, isNot(contains('/')));
    });
  });

  group('AccountDeletionService', () {
    test('deleteAccount takes no account identifier', () {
      // A regression guard on the security property, not on plumbing: if
      // someone later adds a userId parameter here, any authenticated
      // caller could ask the endpoint to delete somebody else's account.
      // Deletion must always be derived from the caller's own token.
      final service = AccountDeletionService();
      expect(service.deleteAccount, isA<Future<void> Function()>());
    });

    test('accepts an injected client for testing without touching the real one', () {
      // Mirrors RelationshipLifecycleService's constructor seam. Passing
      // null must fall back to the ambient Supabase instance lazily —
      // constructing the service must not itself require an initialised
      // Supabase, or importing it into a test host would throw.
      expect(() => AccountDeletionService(), returnsNormally);
      expect(() => AccountDeletionService(client: null), returnsNormally);
    });
  });
}

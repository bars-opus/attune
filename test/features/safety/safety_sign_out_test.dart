// test/features/safety/safety_sign_out_test.dart
//
// Chat review #18 (fix M4): the Safety sign-out's fallback -- taken when
// AuthOperations refuses (busy) or fails -- skips AuthOperations, so it
// releases this phone's push subscription itself before the direct auth
// sign-out. The normal path leaves that to AuthOperations.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/data/safety_sign_out.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _AuthOps extends AuthOperations {
  _AuthOps(super.ref, {required this.fail});
  final bool fail;
  int calls = 0;

  @override
  Future<void> signOut() async {
    calls++;
    if (fail) {
      throw StateError('Another auth operation is already in progress.');
    }
  }
}

final _signedIn = StateProvider<User?>(
  (_) => User(
    id: 'u1',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-10-01T00:00:00Z',
  ),
);

final _refProvider = Provider<Ref>((ref) => ref);

({ProviderContainer container, List<String> released}) _build({
  required bool authOpsFail,
  required bool stillSignedIn,
}) {
  final released = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SizedBox()),
      GoRoute(path: RouteNames.intro, builder: (_, __) => const SizedBox()),
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [
      authOperationsProvider.overrideWith(
        (ref) => _AuthOps(ref, fail: authOpsFail),
      ),
      currentUserProvider.overrideWith(
        (ref) => stillSignedIn ? ref.watch(_signedIn) : null,
      ),
      signOutHooksProvider.overrideWithValue(
        SignOutHooks(beforeSignOut: () async => released.add('released')),
      ),
      routingNotifierProvider.overrideWith((ref) => RoutingNotifier()),
      appRouterProvider.overrideWithValue(router),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, released: released);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fallback (AuthOperations busy): releases the device itself', () async {
    final t = _build(authOpsFail: true, stillSignedIn: true);
    await safetySignOut(t.container.read(_refProvider));
    expect(t.released, ['released']);
  });

  test(
    'normal path: AuthOperations already released it, no second call',
    () async {
      final t = _build(authOpsFail: false, stillSignedIn: false);
      await safetySignOut(t.container.read(_refProvider));
      expect((t.container.read(authOperationsProvider) as _AuthOps).calls, 1);
      expect(t.released, isEmpty);
    },
  );
}

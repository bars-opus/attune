import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
import 'package:attune/home/widgets/home_tab_two.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in account as HomeScreen reads it (Spec 1 W3a): the same two
/// members PasswordlessAuthService has, so tests can drive the shell
/// without Supabase.
abstract class HomeAuth {
  User? get currentUser;
  Stream<AuthState> get authStateChanges;
}

class PasswordlessHomeAuth implements HomeAuth {
  PasswordlessHomeAuth([PasswordlessAuthService? service])
    : _service = service ?? PasswordlessAuthService();

  final PasswordlessAuthService _service;

  @override
  User? get currentUser => _service.currentUser;

  @override
  Stream<AuthState> get authStateChanges => _service.authStateChanges;
}

final homeAuthProvider = Provider<HomeAuth>((ref) => PasswordlessHomeAuth());

/// Tab 1, Opinions (unchanged, Q9), replaceable in the shell's tests.
final homeOpinionsTabProvider = Provider<Widget>((ref) => const OpinionsTab());

typedef HomeTabTwoBuilder =
    Widget Function(AppTab tab, HomeSnapshot home, VoidCallback onInviteSent);

/// Tab 2 under flow_paths_v2, replaceable in the shell's tests. W4b: R4
/// under flow_couples_v2, read when Tab 2 is built.
final homeTabTwoBuilderProvider = Provider<HomeTabTwoBuilder>(
  (ref) =>
      (tab, home, onInviteSent) => HomeTabTwo(
        tab: tab,
        home: home,
        onInviteSent: onInviteSent,
        couplesV2: ref.read(flowCouplesV2Provider),
      ),
);

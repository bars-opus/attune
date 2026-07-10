import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, this.previewOnboarding = false});

  final bool previewOnboarding;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  final _authService = PasswordlessAuthService();
  late final Future<OnboardingStore> _storeFuture = _loadStore();

  Future<OnboardingStore> _loadStore() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingStore(prefs, scope: _storeScope);
  }

  String get _storeScope {
    if (kDebugMode && widget.previewOnboarding) {
      return OnboardingStore.previewScope;
    }

    final userId = _authService.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return OnboardingStore.anonymousScope;
    }

    return '${OnboardingStore.userScopePrefix}.$userId';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnboardingStore>(
      future: _storeFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        final store = snapshot.data!;
        final isPreview = kDebugMode && widget.previewOnboarding;
        if (_authService.currentUser == null && !isPreview) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go(RouteNames.home);
          });
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        if (store.isComplete) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go(RouteNames.home);
          });
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        // Debug-only UI preview; real onboarding is reached after phone auth.
        return OnboardingFlow(
          store: store,
          requireAuth: false,
          onComplete: () {
            context.go(RouteNames.home);
          },
        );
      },
    );
  }
}

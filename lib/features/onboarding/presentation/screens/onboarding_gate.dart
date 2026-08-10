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
  late final Future<_GateData> _gateDataFuture = _loadGateData();

  Future<_GateData> _loadGateData() async {
    final prefs = await SharedPreferences.getInstance();
    final store = OnboardingStore(prefs, scope: _storeScope);
    // Server-truth-first (see OnboardingStore.resolveIsComplete's doc): a
    // local-only isComplete check sent a returning, already-onboarded user
    // (onboarded on a different device/install) straight back into
    // OnboardingFlow.
    final isComplete = await store.resolveIsComplete(
      _authService.currentUser?.id,
    );
    return _GateData(store: store, isComplete: isComplete);
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
    return FutureBuilder<_GateData>(
      future: _gateDataFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        final store = snapshot.data!.store;
        final isComplete = snapshot.data!.isComplete;
        final isPreview = kDebugMode && widget.previewOnboarding;
        if (_authService.currentUser == null && !isPreview) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go(RouteNames.home);
          });
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        if (isComplete) {
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

class _GateData {
  const _GateData({required this.store, required this.isComplete});

  final OnboardingStore store;
  final bool isComplete;
}

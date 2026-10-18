import 'package:attune/features/appreciation/data/appreciation_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/conflict_toolkit/data/pause_service.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/quiet_states/presentation/quiet_state_providers.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:attune/features/wins/presentation/win_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The feature flags read once per process. Re-read on resume and on a
/// change of signed-in user, so a flag turned on or off reaches a running
/// app without a relaunch (sync audit, 2026-10-18). Riverpod keeps the
/// previous value while a re-read is in flight, so nothing flickers.
final List<ProviderOrFamily> refreshedFlagProviders = [
  quizClinicalSignoffProvider,
  coupleMapEnabledProvider,
  appreciationEnabledProvider,
  winsEnabledProvider,
  quietStatesEnabledProvider,
  safetySelfCheckEnabledProvider,
  conflictToolkitEnabledProvider,
];

class FeatureFlagRefresher extends ConsumerStatefulWidget {
  const FeatureFlagRefresher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FeatureFlagRefresher> createState() =>
      _FeatureFlagRefresherState();
}

class _FeatureFlagRefresherState extends ConsumerState<FeatureFlagRefresher> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    for (final provider in refreshedFlagProviders) {
      ref.invalidate(provider);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider.select((u) => u?.id), (previous, next) {
      if (previous != next) _refresh();
    });
    return widget.child;
  }
}

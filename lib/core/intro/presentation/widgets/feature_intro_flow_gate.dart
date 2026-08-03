// lib/core/intro/presentation/widgets/feature_intro_flow_gate.dart

import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/core/intro/data/seen_feature_intro_store.dart';
import 'package:attune/core/intro/presentation/screens/feature_intro_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps a feature's real screen behind a one-time intro gate. Used
/// directly as a GoRoute builder's return value so the gating logic
/// lives at the route, not duplicated at every navigation call site.
class FeatureIntroFlowGate extends StatefulWidget {
  const FeatureIntroFlowGate({
    super.key,
    required this.module,
    required this.briefParagraph,
    required this.launchLabel,
    required this.buildFeature,
    this.storeOverride,
  });

  final DocumentationModule module;
  final String briefParagraph;
  final String launchLabel;
  final Widget Function() buildFeature;

  /// Test-only: inject a pre-built store instead of loading real
  /// SharedPreferences. Always null in production use.
  final SeenFeatureIntroStore? storeOverride;

  @override
  State<FeatureIntroFlowGate> createState() => _FeatureIntroFlowGateState();
}

class _FeatureIntroFlowGateState extends State<FeatureIntroFlowGate> {
  SeenFeatureIntroStore? _store;
  bool _seen = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initializeStore();
  }

  Future<void> _initializeStore() async {
    final store = widget.storeOverride ??
        SeenFeatureIntroStore(await SharedPreferences.getInstance());
    if (!mounted) return;
    setState(() {
      _store = store;
      _seen = store.hasSeenIntro(widget.module.id);
      _loading = false;
    });
  }

  void _handleIntroComplete() {
    _store?.markIntroSeen(widget.module.id);
    setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_seen) {
      return widget.buildFeature();
    }

    return FeatureIntroFlowScreen(
      module: widget.module,
      briefParagraph: widget.briefParagraph,
      launchLabel: widget.launchLabel,
      onComplete: _handleIntroComplete,
    );
  }
}

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The contextual ask (Spec 1 §2.4): one line of reason and one "Turn on",
/// inside the feature, only while notifications are off. Dismissing is
/// carrying on (nothing else asks). Counts push_ask_shown:{context} once
/// per showing and push_ask_granted:{context} on a yes (S-2 exact keys).
class PushAskRow extends ConsumerStatefulWidget {
  const PushAskRow({
    super.key,
    required this.askContext,
    required this.reason,
    required this.action,
  });

  final PushAskContext askContext;
  final String reason;
  final String action;

  @override
  ConsumerState<PushAskRow> createState() => _PushAskRowState();
}

class _PushAskRowState extends ConsumerState<PushAskRow>
    with WidgetsBindingObserver {
  late bool _granted;
  bool _busy = false;

  ClientMetricKey get _shownKey => switch (widget.askContext) {
    PushAskContext.r2 => ClientMetricKey.pushAskShownR2,
    PushAskContext.r4 => ClientMetricKey.pushAskShownR4,
    PushAskContext.j3 => ClientMetricKey.pushAskShownJ3,
  };

  ClientMetricKey get _grantedKey => switch (widget.askContext) {
    PushAskContext.r2 => ClientMetricKey.pushAskGrantedR2,
    PushAskContext.r4 => ClientMetricKey.pushAskGrantedR4,
    PushAskContext.j3 => ClientMetricKey.pushAskGrantedJ3,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _granted = ref.read(pushAskerProvider).permissionGranted;
    if (!_granted) ref.read(metricCounterProvider).bump(_shownKey);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the phone's Settings: the switch may be on now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _granted) return;
    final granted = ref.read(pushAskerProvider).permissionGranted;
    if (granted && mounted) {
      ref.read(metricCounterProvider).bump(_grantedKey);
      setState(() => _granted = true);
    }
  }

  Future<void> _ask() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await ref
        .read(pushAskerProvider)
        .askInContext(widget.askContext);
    if (!mounted) return;
    if (outcome == PushAskOutcome.granted) {
      ref.read(metricCounterProvider).bump(_grantedKey);
    }
    setState(() {
      _busy = false;
      _granted = outcome == PushAskOutcome.granted;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_granted) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      // B6 review M-5: the screen's rhythm (sm between related items); the
      // call site's md below stays. Nothing shows when hidden.
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.notifications_none_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  widget.reason,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          // The label starts under the reason (icon 24 + gap), less the
          // button's own 12 dp inset.
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 24 + Spacing.sm - 12,
            ),
            child: TextButton(
              onPressed: _busy ? null : _ask,
              style: TextButton.styleFrom(
                foregroundColor: flowAccent(context),
                minimumSize: const Size(48, 48),
              ),
              child: Text(widget.action),
            ),
          ),
        ],
      ),
    );
  }
}

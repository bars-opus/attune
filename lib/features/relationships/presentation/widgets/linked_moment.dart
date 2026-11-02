import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart' show kSettleDuration;
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// R4 · Linked (Spec 1 §3.8, W4b): "Welcome, {couple}" (the couple's
/// chosen name, else "Couples": preflight F-1), the one calm
/// Relationship celebration (§2.2: two avatars settle with SettleIn, the
/// line fades in, one light haptic, all within kCelebrationMaxDuration;
/// reduce motion: static avatars and text), then the in-context ask for
/// message notifications (R4, §2.4), then Chat. The caller records it as
/// seen for this relationship on this phone (InviteDeviceStore).
class LinkedMoment extends ConsumerStatefulWidget {
  const LinkedMoment({
    super.key,
    required this.relationshipId,
    required this.onContinue,
    this.myInitial = '',
    this.partnerFirstName,
  });

  /// The relationship just linked: its chosen name titles the moment.
  final String relationshipId;
  final String myInitial;
  final String? partnerFirstName;
  final VoidCallback onContinue;

  @override
  ConsumerState<LinkedMoment> createState() => _LinkedMomentState();
}

class _LinkedMomentState extends ConsumerState<LinkedMoment> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotionOf(context)) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = widget.partnerFirstName?.trim();
    final named = name != null && name.isNotEmpty;
    final partnerInitial = named ? name.characters.first.toUpperCase() : '';
    final still = reduceMotionOf(context);
    final couple = coupleLabel(
      ref.watch(coupleNameProvider(widget.relationshipId)).valueOrNull,
    );
    Widget avatar(String initial, Offset from) => SettleIn(
      animate: !still,
      beginOffset: from,
      child: CircleAvatar(
        radius: 32,
        backgroundColor: theme.colorScheme.primaryContainer,
        child:
            initial.isEmpty
                ? Icon(
                  Icons.person_outline,
                  color: theme.colorScheme.onPrimaryContainer,
                )
                : Text(
                  initial,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
      ),
    );
    return FlowFrame(
      title: loc.flow_linkedTitle(couple),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                avatar(widget.myInitial, const Offset(-0.3, 0)),
                const SizedBox(width: Spacing.sm),
                avatar(partnerInitial, const Offset(0.3, 0)),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          // The line fades in as the avatars settle: 280 ms, inside the
          // 600 ms ceiling (kCelebrationMaxDuration).
          TweenAnimationBuilder<double>(
            tween: Tween(begin: still ? 1 : 0, end: 1),
            duration: still ? Duration.zero : kSettleDuration,
            builder: (_, value, child) => Opacity(opacity: value, child: child),
            child: Text(
              named ? loc.flow_linkedBody(name) : loc.flow_linkedBodyUnnamed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PushAskRow(
            askContext: PushAskContext.r4,
            reason:
                named ? loc.flow_pushAskR4(name) : loc.flow_pushAskR4Unnamed,
            action: loc.flow_pushTurnOn,
          ),
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_continue,
          onPressed: widget.onContinue,
        ),
      ],
    );
  }
}

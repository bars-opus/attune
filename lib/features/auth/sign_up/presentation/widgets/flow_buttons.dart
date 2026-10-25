import 'dart:async';

import 'package:attune/app/documentations/legal_documentation/data/legal_documentation_data.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The sign-in screens' buttons (Spec 1 §2.2–§2.3). Material 3 buttons from
/// the theme's colour scheme, at least 48 dp tall, with labels that wrap and
/// follow the phone's text size. Unlike AppButton they never pin the text
/// scale or play an entry animation, which §2.3 and the "never animated"
/// screens (X1, consent) need.
class FlowPrimaryButton extends StatefulWidget {
  const FlowPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Takes no taps at once, keeping its colours; only a wait longer than
  /// [ringDelay] swaps the label for a small progress ring, so a quick step
  /// never flashes one (§2.2).
  final bool busy;

  /// §2.2: nothing under 400 ms; past that, say something is happening.
  static const ringDelay = Duration(milliseconds: 400);

  @override
  State<FlowPrimaryButton> createState() => _FlowPrimaryButtonState();
}

class _FlowPrimaryButtonState extends State<FlowPrimaryButton> {
  Timer? _ringTimer;
  bool _showRing = false;

  @override
  void initState() {
    super.initState();
    if (widget.busy) _startRingTimer();
  }

  @override
  void didUpdateWidget(covariant FlowPrimaryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      _startRingTimer();
    } else if (!widget.busy && oldWidget.busy) {
      _ringTimer?.cancel();
      _showRing = false;
    }
  }

  void _startRingTimer() {
    _ringTimer?.cancel();
    _ringTimer = Timer(FlowPrimaryButton.ringDelay, () {
      if (mounted) setState(() => _showRing = true);
    });
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = flowAccent(context);
    final busy = widget.busy;
    final label = widget.label;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : widget.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: colorScheme.onPrimary,
          // Busy is not disabled: the button keeps its look while it waits.
          disabledBackgroundColor: busy ? accent : null,
          disabledForegroundColor: busy ? colorScheme.onPrimary : null,
          minimumSize: const Size.fromHeight(48),
          padding: EdgeInsets.symmetric(
            horizontal: Spacing.md.w,
            vertical: Spacing.sm.h,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusTokens.xlAll,
          ),
        ),
        child:
            busy && _showRing
                ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                    semanticsLabel: label,
                  ),
                )
                : Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class FlowSecondaryButton extends StatefulWidget {
  const FlowSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// As [FlowPrimaryButton.busy]: takes no taps at once, keeping its
  /// colours, and only a wait longer than [FlowPrimaryButton.ringDelay]
  /// swaps the label for a small progress ring. A screen that runs this
  /// button's action shows its progress here, not on the primary.
  final bool busy;

  @override
  State<FlowSecondaryButton> createState() => _FlowSecondaryButtonState();
}

class _FlowSecondaryButtonState extends State<FlowSecondaryButton> {
  Timer? _ringTimer;
  bool _showRing = false;

  @override
  void initState() {
    super.initState();
    if (widget.busy) _startRingTimer();
  }

  @override
  void didUpdateWidget(covariant FlowSecondaryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      _startRingTimer();
    } else if (!widget.busy && oldWidget.busy) {
      _ringTimer?.cancel();
      _showRing = false;
    }
  }

  void _startRingTimer() {
    _ringTimer?.cancel();
    _ringTimer = Timer(FlowPrimaryButton.ringDelay, () {
      if (mounted) setState(() => _showRing = true);
    });
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = flowAccent(context);
    final busy = widget.busy;
    final label = widget.label;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: busy ? null : widget.onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          // Busy is not disabled: the button keeps its look while it waits.
          disabledForegroundColor: busy ? accent : null,
          side: BorderSide(color: accent),
          minimumSize: const Size.fromHeight(48),
          padding: EdgeInsets.symmetric(
            horizontal: Spacing.md.w,
            vertical: Spacing.sm.h,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusTokens.xlAll,
          ),
        ),
        child:
            busy && _showRing
                ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                    semanticsLabel: label,
                  ),
                )
                : Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// A text link with a 48 dp target.
class FlowTextLink extends StatelessWidget {
  const FlowTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.alignment = AlignmentDirectional.center,
  });

  final String label;
  final VoidCallback onPressed;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: flowAccent(context),
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// The Terms of Service in the app's documentation sheet, read-only (no
/// agree or decline buttons). Welcome's and consent's Terms links open it.
Future<void> showTermsSheet(BuildContext context) =>
    BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      document: LegalDocumentationData.termsOfService(context),
      showButtons: false,
    );

/// The Privacy Policy in the app's documentation sheet, read-only (no agree
/// or decline buttons). Welcome's and consent's Privacy links open it.
Future<void> showPrivacySheet(BuildContext context) =>
    BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      document: LegalDocumentationData.privacyPolicy(context),
      showButtons: false,
    );

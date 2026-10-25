import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/domain/guest_year.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// G1 · the neutral birth-year gate before guest Opinions (Spec 1 §3.2).
/// No default, no list of years, no motion. Under 18 by year opens X1 and
/// starts the 30-day device block; otherwise the year is kept on this phone
/// for A2's pre-fill and the guest home opens.
class GuestAgeGateScreen extends ConsumerStatefulWidget {
  const GuestAgeGateScreen({super.key, this.now});

  /// Tests pin the date.
  final DateTime Function()? now;

  @override
  ConsumerState<GuestAgeGateScreen> createState() => _GuestAgeGateScreenState();
}

class _GuestAgeGateScreenState extends ConsumerState<GuestAgeGateScreen> {
  final _year = TextEditingController();
  GuestYearError? _error;

  /// One per failed submit, so the same message is read out again.
  int _errorCount = 0;
  bool _busy = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    // Done on the keyboard and Continue together run this once.
    if (_busy) return;
    final currentYear = localCalendarYear(_now);
    final error = validateGuestYear(_year.text, currentYear: currentYear);
    if (error != null) {
      setState(() {
        _error = error;
        _errorCount++;
      });
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final year = int.parse(_year.text.trim());
    final store = ref.read(ageGateStoreProvider);
    final routing = ref.read(routingNotifierProvider);
    if (isUnder18ByYear(year, currentYear: currentYear)) {
      // Fail closed: X1 and the in-session block even if saving failed.
      try {
        await store.block();
      } catch (error) {
        debugPrint('[age-gate] block not saved: ${error.runtimeType}');
      }
      routing.setUnderAgeBlocked(true);
      if (mounted) context.go(RouteNames.ageStop);
      return;
    }
    await store.passGuestGate(year);
    routing.setGuestAgeOk(true);
    ref.read(metricCounterProvider).bump(ClientMetricKey.guestAgeOk);
    if (mounted) context.go(RouteNames.home);
  }

  String? _errorText(AppLocalizations loc) => switch (_error) {
    GuestYearError.fourDigits => loc.flow_yearFourDigits,
    GuestYearError.future => loc.flow_yearFuture,
    GuestYearError.check => loc.flow_yearCheck,
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return FlowFrame(
      title: loc.flow_guestAgeTitle,
      hint: loc.flow_guestAgeHint,
      onBack: () => context.go(RouteNames.welcome),
      body: FlowTextField(
        controller: _year,
        label: loc.flow_guestAgeLabel,
        semanticsLabel: loc.flow_guestAgeSemantics,
        errorText: _errorText(loc),
        errorCount: _errorCount,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        autofocus: true,
        onSubmitted: (_) => _continue(),
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_continue,
          busy: _busy,
          onPressed: _continue,
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A2 · Date of birth (Spec 1 §3.3): three labelled numeric fields in the
/// locale's order, no defaults (the year only from G1). Checked on the
/// phone; the date leaves it only with complete_sign_up.
class BirthDateStep extends StatefulWidget {
  const BirthDateStep({
    super.key,
    required this.order,
    required this.todayUtc,
    required this.onSubmit,
    required this.onBack,
    this.initialDate,
    this.initialYear,
  });

  final BirthDateOrder order;
  final DateTime todayUtc;
  final DateTime? initialDate;

  /// G1's year, when the guest gate was passed on this phone.
  final int? initialYear;

  /// The valid date. The step stays busy until it has finished.
  final FutureOr<void> Function(DateTime date) onSubmit;
  final VoidCallback onBack;

  @override
  State<BirthDateStep> createState() => _BirthDateStepState();
}

class _BirthDateStepState extends State<BirthDateStep> with SubmitOnce {
  late final _day = TextEditingController(
    text: widget.initialDate?.day.toString() ?? '',
  );
  late final _month = TextEditingController(
    text: widget.initialDate?.month.toString() ?? '',
  );
  late final _year = TextEditingController(
    text:
        widget.initialDate?.year.toString() ??
        widget.initialYear?.toString() ??
        '',
  );
  BirthDateError? _error;
  DateTime? _valid;

  @override
  void initState() {
    super.initState();
    _check(showError: false);
  }

  @override
  void dispose() {
    _day.dispose();
    _month.dispose();
    _year.dispose();
    super.dispose();
  }

  ({DateTime? date, BirthDateError? error}) _result() => validateBirthDate(
    day: _day.text,
    month: _month.text,
    year: _year.text,
    todayUtc: widget.todayUtc,
  );

  void _check({required bool showError}) {
    final result = _result();
    setState(() {
      _valid = result.date;
      if (showError) _error = result.error;
      if (result.date != null) _error = null;
    });
    if (showError && result.error != null) {
      SemanticsService.announce(
        _message(AppLocalizations.of(context)!, result.error!),
        Directionality.of(context),
      );
    }
  }

  void _continue() {
    // A double tap, or Done and Continue together, run this once.
    if (submitting) return;
    _check(showError: true);
    final date = _result().date;
    if (date != null) submitOnce(() => widget.onSubmit(date));
  }

  String _message(AppLocalizations loc, BirthDateError error) =>
      switch (error) {
        BirthDateError.dayRange => loc.flow_dobDayRange,
        BirthDateError.monthRange => loc.flow_dobMonthRange,
        BirthDateError.yearDigits => loc.flow_dobYearDigits,
        BirthDateError.noSuchDate => loc.flow_dobNoSuchDate,
        BirthDateError.future => loc.flow_dobFuture,
        BirthDateError.tooOld => loc.flow_dobCheckYear,
      };

  Widget _field(
    TextEditingController controller,
    String label,
    String semantics,
    int maxLength,
  ) => FlowTextField(
    controller: controller,
    label: label,
    semanticsLabel: semantics,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(maxLength),
    ],
    onChanged: (_) => _check(showError: false),
  );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final day = _field(_day, loc.flow_dobDay, loc.flow_dobDaySemantics, 2);
    final month = _field(
      _month,
      loc.flow_dobMonth,
      loc.flow_dobMonthSemantics,
      2,
    );
    final year = _field(_year, loc.flow_dobYear, loc.flow_dobYearSemantics, 4);
    final ordered =
        widget.order == BirthDateOrder.dayMonthYear
            ? [day, month, year]
            : [month, day, year];
    final valid = _valid;

    return FlowFrame(
      title: loc.flow_dobTitle,
      hint: loc.flow_dobHint,
      onBack: widget.onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // At large text three fields side by side get too narrow for their
          // labels, so they stack (§2.3). Read under FlowFrame's
          // AllowLargeText: this step's own context has the app's 1.0 clamp.
          Builder(
            builder:
                (context) =>
                    MediaQuery.textScalerOf(context).scale(1) > 1.5
                        ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final field in ordered) ...[
                              field,
                              const SizedBox(height: 12),
                            ],
                          ],
                        )
                        : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: ordered[0]),
                            const SizedBox(width: 12),
                            Expanded(child: ordered[1]),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: ordered[2]),
                          ],
                        ),
          ),
          const SizedBox(height: 8),
          Text(
            loc.flow_dobExample(birthDateExample(widget.order)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FlowErrorLine(
              text: _message(loc, _error!),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
          if (valid != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                MyDateFormat.join([
                  MyDateFormat.toDate(valid),
                  loc.flow_dobAge(ageOn(valid, widget.todayUtc)),
                ]),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_continue,
          busy: submitting,
          onPressed: _continue,
        ),
      ],
    );
  }
}

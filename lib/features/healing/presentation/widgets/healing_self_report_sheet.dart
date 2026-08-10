// lib/features/healing/presentation/widgets/healing_self_report_sheet.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/core/widgets/cupertino_date_time_sheet.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

/// Collects a self-reported breakup date and starts a solo (no
/// relationship_id) healing journey via the same
/// get_or_create_healing_journey RPC the relationship-ended path uses,
/// with breakupAtSource: 'user_reported'.
///
/// This calls healingRepositoryProvider directly rather than the existing
/// startHealingJourneyProvider family, because that family's
/// HealingStartContext typedef declares relationshipId as non-nullable
/// String — it has only ever been called with a real relationship id, and
/// there is no way to express "no relationship" through it. See
/// .superpowers/sdd/2026-08-03-healing-self-report-entry/task-2-brief.md
/// for why.
class HealingSelfReportSheet extends ConsumerStatefulWidget {
  const HealingSelfReportSheet({super.key});

  @override
  ConsumerState<HealingSelfReportSheet> createState() =>
      _HealingSelfReportSheetState();
}

class _HealingSelfReportSheetState
    extends ConsumerState<HealingSelfReportSheet> {
  DateTime? _selectedDate;
  bool _submitting = false;
  String? _errorText;

  Future<void> _submit() async {
    final date = _selectedDate;
    if (date == null || _submitting) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      await ref
          .read(healingRepositoryProvider)
          .getOrCreateJourney(
            relationshipId: null,
            breakupAt: date,
            breakupAtSource: 'user_reported',
          );
      ref.invalidate(healingJourneyProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Could not start your healing journey. Please try again.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      children: [
        Gap(Spacing.xxl.h),
        Text(
          'Healing from a breakup?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
          // style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.sm.h),
        Text(
          'Start a private healing journey, even if it wasn\'t tracked in Attune.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Gap(Spacing.xxl.h),

        InfoRowWidget(
          key: const Key('healingSelfReportDateRow'),
          subtitle:
              _selectedDate == null
                  ? 'If you dont rememeber the exact date you can select any date in that month thats closer.'
                  : 'Happened on:',
          title:
              _selectedDate == null
                  ? 'When did this happen?'
                  : DateFormat.yMMMd().format(_selectedDate!),
          icon: Icons.calendar_month,
          showDivider: false,
          avatarRadius: 25.h,
          onTap: () {},
          disableTrailing: true,
          showAvatar: false,
          showTrailingArrow: false,
        ),
        if (_errorText != null) ...[
          Gap(Spacing.sm.h),
          Text(
            _errorText!,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
        Gap(Spacing.md.h),
        CardInkWell(
          borderRadius: BorderRadiusTokens.floatingNavAll,
          child: SizedBox(
            height: 250.h,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: _selectedDate ?? DateTime.now(),
              minimumDate: DateTime(2020),
              maximumDate: DateTime.now(),
              onDateTimeChanged:
                  (value) => setState(() => _selectedDate = value),
            ),
          ),
        ),
        Gap(Spacing.md.h),
        if (_selectedDate != null)
          ShakeTransition(
            axis: Axis.vertical,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            child: AppButton(
              label: 'Start healing journey',
              onPressed: _submit,
              elevation: 0,
              height: 40.h,
              animateButton: false,
              size: ButtonSize.small,
              // isDisabled: _selectedDate == null,
              isLoading: _submitting,
            ),
          ),
      ],
    );
  }
}

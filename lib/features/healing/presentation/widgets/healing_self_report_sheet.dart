// lib/features/healing/presentation/widgets/healing_self_report_sheet.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    final date = _selectedDate;
    if (date == null || _submitting) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      await ref.read(healingRepositoryProvider).getOrCreateJourney(
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Healing from a breakup?',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.sm.h),
        Text(
          'Start a private healing journey, even if it wasn\'t tracked in Attune.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Gap(Spacing.lg.h),
        ListTile(
          key: const Key('healingSelfReportDateRow'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            _selectedDate == null
                ? 'When did this happen?'
                : DateFormat.yMMMd().format(_selectedDate!),
            style: textTheme.bodyLarge,
          ),
          trailing: const Icon(Icons.calendar_today, size: 20),
          onTap: _submitting ? null : _pickDate,
        ),
        if (_errorText != null) ...[
          Gap(Spacing.sm.h),
          Text(
            _errorText!,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
        Gap(Spacing.lg.h),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_selectedDate == null || _submitting) ? null : _submit,
            child: _submitting
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Start healing journey'),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Share where you are, with a note.
///
/// The label is EDITABLE and pre-filled, not fixed to what the geocoder
/// returned. "At the hairdresser" is what a partner wants to read; "12
/// Oak Street" is what the API knows. Letting the user write it also
/// means they choose the precision of what they say, which is the whole
/// principle of this feature applied to one field.
class SharePlaceSheet extends ConsumerStatefulWidget {
  const SharePlaceSheet({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  ConsumerState<SharePlaceSheet> createState() => _SharePlaceSheetState();
}

class _SharePlaceSheetState extends ConsumerState<SharePlaceSheet> {
  final _labelController = TextEditingController();
  final _noteController = TextEditingController();

  ParsedAddress? _place;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolvePlace());
  }

  @override
  void dispose() {
    _labelController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _resolvePlace() async {
    final place = await ref.read(presenceRepositoryProvider).currentPlace();
    if (!mounted) return;
    setState(() {
      _place = place;
      _loading = false;
      // Pre-filled with the neighbourhood rather than the street: a
      // starting point the user edits, not an address the app publishes
      // on their behalf.
      _labelController.text = place?.city ?? '';
    });
  }

  Future<void> _send() async {
    final label = _labelController.text.trim();
    if (label.isEmpty || _sending) return;

    setState(() => _sending = true);
    final ok = await ref
        .read(presenceRepositoryProvider)
        .postPlaceUpdate(
          relationshipId: widget.relationshipId,
          label: label,
          note:
              _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
          latitude: _place?.latitude,
          longitude: _place?.longitude,
          city: _place?.city,
          country: _place?.country,
        );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share that. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg.w,
        Spacing.md.h,
        Spacing.lg.w,
        MediaQuery.of(context).viewInsets.bottom + Spacing.lg.h,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BottomSheetHeader(title: 'Share where you are'),
          Gap(Spacing.sm.h),
          Text(
            'Only what you write here is shared.',
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          Gap(Spacing.lg.h),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            TextField(
              controller: _labelController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Where are you?',
                hintText: 'At the coffee shop',
              ),
              maxLength: 120,
            ),
            Gap(Spacing.sm.h),
            TextField(
              controller: _noteController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Add a note (optional)',
                hintText: 'Thinking of you',
              ),
              maxLength: 500,
              maxLines: 2,
            ),
            Gap(Spacing.lg.h),
            AppButton(
              label: _sending ? 'Sharing…' : 'Share',
              onPressed: _sending ? null : _send,
              size: ButtonSize.medium,
            ),
          ],
        ],
      ),
    );
  }
}

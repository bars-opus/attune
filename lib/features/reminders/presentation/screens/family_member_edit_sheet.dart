// lib/features/reminders/presentation/screens/family_member_edit_sheet.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Add/edit form for a family member (name + optional birthday), shown via
/// [show] as a BottomSheetUtils sheet. Extracted from FamilyMembersScreen's
/// own StatefulBuilder into a real widget so its state (isSaving, birthday,
/// the canSave gate) doesn't have to live in closures.
class FamilyMemberEditSheet extends ConsumerStatefulWidget {
  const FamilyMemberEditSheet({
    super.key,
    this.id,
    this.existingName,
    this.existingBirthday,
  });

  final String? id;
  final String? existingName;
  final DateTime? existingBirthday;

  /// Presents this form in the app's shared bottom sheet.
  static Future<void> show(
    BuildContext context, {
    String? id,
    String? existingName,
    DateTime? existingBirthday,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      backgroundColor: colorScheme.neutral,
      widget: FamilyMemberEditSheet(
        id: id,
        existingName: existingName,
        existingBirthday: existingBirthday,
      ),
    );
  }

  @override
  ConsumerState<FamilyMemberEditSheet> createState() =>
      _FamilyMemberEditSheetState();
}

class _FamilyMemberEditSheetState extends ConsumerState<FamilyMemberEditSheet> {
  late final TextEditingController _nameController;
  DateTime? _birthday;
  bool _isSaving = false;

  // Mirrors AddEditReminderScreen's _canSave: only a non-empty name is
  // required here (birthday stays optional, unlike the reminder screen's
  // date requirement) — the Save button only appears once that's true.
  bool get _canSave => _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingName ?? '');
    _birthday = widget.existingBirthday;
    // A plain TextEditingController read doesn't trigger a rebuild on its
    // own — this re-runs setState as the user types, same role the reminder
    // screen's own _handleTitleChanged listener plays.
    _nameController.addListener(_handleNameChanged);
  }

  void _handleNameChanged() => setState(() {});

  @override
  void dispose() {
    _nameController.removeListener(_handleNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(
        upsertFamilyMemberProvider((
          id: widget.id,
          name: _nameController.text.trim(),
          birthday: _birthday,
        )).future,
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickBirthday() {
    return showCupertinoDateTimeSheet(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _birthday ?? DateTime(2020),
      minimumDate: DateTime(1900),
      maximumDate: DateTime(2100),
      onChanged: (value) => setState(() => _birthday = value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: InfoRowWidget(
                    title: 'Add a member',
                    subtitle: '',
                    iconColor: colorScheme.onBackground,
                    icon: Icons.close,
                    showAvatar: false,
                    showTrailingArrow: true,
                    showDivider: false,
                    disableTrailing: true,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                if (_canSave)
                  ShakeTransition(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutBack,
                    child: AppButton(
                      elevation: 0,
                      animateButton: false,
                      label: 'Save',
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _save,
                      textColor: colorScheme.surface,
                      size: ButtonSize.large,
                      width: 100,
                      padding: Spacing.horizontalMd,
                      height: 30.h,
                      borderRadius: BorderRadius.circular(100.r),
                    ),
                  ),
              ],
            ),
            Gap(Spacing.lg.h),
            AppTextFormField(
              controller: _nameController,
              label: 'Name',
              autofocus: true,
            ),
            Gap(Spacing.md.h),
            InfoRowWidget(
              key: const Key('familyMemberBirthdayRow'),
              subtitle: 'Birthday (optional)',
              title:
                  _birthday == null
                      ? 'Not set'
                      : DateFormat.yMMMd().format(_birthday!),
              icon: Icons.cake_outlined,
              showDivider: false,
              avatarRadius: 25.h,
              onTap: _pickBirthday,
              disableTrailing: true,
              showAvatar: false,
              showTrailingArrow: false,
            ),
            Gap(Spacing.md.h),
            SemanticContainerWidget(
              title: '',
              content:
                  'You can also add other special dates of loved ones, like anniversaries, graduations, etc.',
              icon: Icons.info_outline,
              backgroundColor: colorScheme.onBackground.withValues(alpha: 0.1),
              borderColor: colorScheme.onBackground,
              iconColor: colorScheme.onBackground,
              textTheme: textTheme,
            ),
          ],
        ),
      ),
    );
  }
}

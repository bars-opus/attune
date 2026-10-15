// lib/features/reminders/presentation/screens/family_members_screen.dart
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/family_member_edit_sheet.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Family as one of the app's sheets (Together's and the Month view's
/// Family buttons open it).
Future<void> showFamilySheet(BuildContext context) =>
    BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.neutral,
      widget: const _FamilySheet(),
    );

class _FamilySheet extends StatelessWidget {
  const _FamilySheet();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: ListView(
      children: [
        const BottomSheetHeader(title: 'Family'),
        AppDivider(),
        const FamilyMembersPanel(),
      ],
    ),
  );
}

/// The family list kept on its route too (deep links), without a floating
/// button: Add sits at the top, as in the sheet.
class FamilyMembersScreen extends StatelessWidget {
  const FamilyMembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Family',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      body: ListView(children: const [FamilyMembersPanel()]),
    );
  }
}

/// Add on top, the members below: however long the list grows, adding
/// someone is one tap away. The same "Add …" row as a table's Add row or
/// a plan's Add expense.
class FamilyMembersPanel extends ConsumerWidget {
  const FamilyMembersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(familyMembersListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add family member'),
              onPressed: () => FamilyMemberEditSheet.show(context),
            ),
          ),
        ),
        Gap(Spacing.md.h), // room between Add and the list
        membersAsync.when(
          loading: () => const TogetherSettingsSkeleton(rows: 2),
          error:
              (error, stack) => ErrorStateWidget(
                title: 'Something went wrong',
                subtitle: 'We couldn\'t load your family list right now.',
                primaryActionLabel: 'Try again',
                onPrimaryAction: () => ref.invalidate(familyMembersListProvider),
              ),
          data: (members) {
            if (members.isEmpty) {
              return const EmptyStateWidget(
                title: 'No family members yet',
                subtitle:
                    'Add kids or family so their birthdays show up on your calendar automatically.',
              );
            }
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Column(
                children: [
                  for (var i = 0; i < members.length; i++)
                    InfoRowWidget(
                      subtitle:
                          members[i].birthday != null
                              ? MyDateFormat.toDate(members[i].birthday!)
                              : 'No birthday set',
                      title: members[i].name,
                      icon: Icons.history_outlined,
                      iconSize: 0.h,
                      onTap:
                          () => FamilyMemberEditSheet.show(
                            context,
                            id: members[i].id,
                            existingName: members[i].name,
                            existingBirthday: members[i].birthday,
                          ),
                      disableTrailing: true,
                      showAvatar: false,
                      showDivider: i < members.length - 1,
                      showTrailingArrow: false,
                      trailing: AppIconButton(
                        icon: Icons.delete_outline,
                        tooltip: 'Delete',
                        onPressed:
                            () => ref.read(
                              deleteFamilyMemberProvider(members[i].id).future,
                            ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

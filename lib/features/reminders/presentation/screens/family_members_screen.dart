// lib/features/reminders/presentation/screens/family_members_screen.dart
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/family_member_edit_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FamilyMembersScreen extends ConsumerWidget {
  const FamilyMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(familyMembersListProvider);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Family',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stack) => Center(
              child: ErrorStateWidget(
                title: 'Something went wrong',
                subtitle: 'We couldn\'t load your family list right now.',
              ),
            ),
        data: (members) {
          if (members.isEmpty) {
            return Center(
              child: EmptyStateWidget(
                title: 'No family members yet',
                subtitle:
                    'Add kids or family so their birthdays show up on your calendar automatically.',
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.all(Spacing.md.w),
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              return InfoRowWidget(
                subtitle:
                    member.birthday != null
                        ? MyDateFormat.toDate(member.birthday!)
                        : 'No birthday set',
                title: member.name,
                icon: Icons.history_outlined,
                iconSize: 0.h,
                onTap:
                    () => FamilyMemberEditSheet.show(
                      context,
                      id: member.id,
                      existingName: member.name,
                      existingBirthday: member.birthday,
                    ),
                disableTrailing: true,
                showAvatar: false,
                showDivider: true,
                showTrailingArrow: false,
                trailing: AppIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete',
                  onPressed:
                      () => ref.read(
                        deleteFamilyMemberProvider(member.id).future,
                      ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: AppFab(
        icon: Icons.add,
        onPressed: () => FamilyMemberEditSheet.show(context),
      ),
    );
  }
}

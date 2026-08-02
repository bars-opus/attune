// lib/features/reminders/presentation/screens/family_members_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FamilyMembersScreen extends ConsumerWidget {
  const FamilyMembersScreen({super.key});

  Future<void> _addOrEdit(BuildContext context, WidgetRef ref, {String? id, String? existingName, DateTime? existingBirthday}) async {
    final nameController = TextEditingController(text: existingName ?? '');
    DateTime? birthday = existingBirthday;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.all(Spacing.md.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextFormField(controller: nameController, label: 'Name'),
                  Gap(Spacing.md.h),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Birthday (optional)'),
                    subtitle: Text(birthday == null
                        ? 'Not set'
                        : '${birthday!.year}-${birthday!.month.toString().padLeft(2, '0')}-${birthday!.day.toString().padLeft(2, '0')}'),
                    trailing: const Icon(Icons.cake_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: birthday ?? DateTime(2020),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSheetState(() { birthday = picked; });
                    },
                  ),
                  Gap(Spacing.md.h),
                  AppButton(
                    label: 'Save',
                    width: double.infinity,
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) return;
                      await ref.read(
                        upsertFamilyMemberProvider((
                          id: id,
                          name: nameController.text.trim(),
                          birthday: birthday,
                        )).future,
                      );
                      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() => nameController.dispose());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(familyMembersListProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Family',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
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
                subtitle: 'Add kids or family so their birthdays show up on your calendar automatically.',
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.all(Spacing.md.w),
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              return ListTile(
                title: Text(member.name),
                subtitle: member.birthday != null
                    ? Text('${member.birthday!.year}-${member.birthday!.month.toString().padLeft(2, '0')}-${member.birthday!.day.toString().padLeft(2, '0')}')
                    : const Text('No birthday set'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref.read(deleteFamilyMemberProvider(member.id).future),
                ),
                onTap: () => _addOrEdit(context, ref, id: member.id, existingName: member.name, existingBirthday: member.birthday),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}

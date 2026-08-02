import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';

class RemindersRepository {
  final SupabaseClient _supabase;

  RemindersRepository(this._supabase);

  Future<List<ReminderModel>> listReminders(String relationshipId) async {
    final response = await _supabase
        .from('reminders')
        .select()
        .eq('relationship_id', relationshipId)
        .order('remind_at');
    return (response as List)
        .map((row) => ReminderModel.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<ReminderModel> createReminder({
    required String relationshipId,
    required String createdBy,
    required String reminderType,
    required String title,
    String? note,
    required DateTime remindAt,
    required String recurrence,
    String? familyMemberId,
  }) async {
    final response = await _supabase
        .from('reminders')
        .insert({
          'relationship_id': relationshipId,
          'created_by': createdBy,
          'reminder_type': reminderType,
          'title': title,
          'note': note,
          'remind_at': remindAt.toIso8601String(),
          'recurrence': recurrence,
          'family_member_id': familyMemberId,
        })
        .select()
        .single();
    return ReminderModel.fromJson(response);
  }

  Future<ReminderModel> updateReminder({
    required String id,
    String? title,
    String? note,
    DateTime? remindAt,
    String? recurrence,
    String? familyMemberId,
  }) async {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (note != null) updates['note'] = note;
    if (remindAt != null) updates['remind_at'] = remindAt.toIso8601String();
    if (recurrence != null) updates['recurrence'] = recurrence;
    if (familyMemberId != null) updates['family_member_id'] = familyMemberId;

    final response = await _supabase
        .from('reminders')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
    return ReminderModel.fromJson(response);
  }

  Future<void> deleteReminder(String id) async {
    await _supabase.from('reminders').delete().eq('id', id);
  }

  Future<List<FamilyMemberModel>> listFamilyMembers(String relationshipId) async {
    final response = await _supabase
        .from('couple_family_members')
        .select()
        .eq('relationship_id', relationshipId)
        .order('name');
    return (response as List)
        .map((row) => FamilyMemberModel.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> upsertFamilyMember({
    String? id,
    required String name,
    DateTime? birthday,
  }) async {
    final response = await _supabase.rpc(
      'upsert_family_member',
      params: {
        'p_id': id,
        'p_name': name,
        'p_birthday': birthday != null
            ? birthday.toIso8601String().split('T')[0]
            : null,
      },
    );
    return response as String;
  }

  Future<void> deleteFamilyMember(String id) async {
    await _supabase.from('couple_family_members').delete().eq('id', id);
  }
}

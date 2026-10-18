import 'package:supabase_flutter/supabase_flutter.dart';

class ChatFeatureFlags {
  static const String imageSharing = 'chat_image_sharing';
  static const String translatorEntry = 'chat_translator_entry';
  static const String expandedHeaderDrawer = 'chat_expanded_header_drawer';
  static const String voiceMessages = 'chat_voice_messages';
  static const String reactions = 'chat_reactions';
  static const String editDelete = 'chat_edit_delete';
  static const String videoSharing = 'chat_video_sharing';
  static const String linkPreviews = 'chat_link_previews';
  static const String historicalImport = 'chat_historical_import';
  static const String ephemeralVideo = 'chat_ephemeral_video';

  /// Spec 5 (R5-6): communication and conflict quizzes after clinical
  /// sign-off. Read through this same shape (plan review I1).
  static const String quizClinicalSignoff = 'quiz_clinical_signoff';

  /// Spec 7 (research 06 B1, B2, B9).
  static const String appreciationNotes = 'appreciation_notes';
  static const String shareAWin = 'share_a_win';
  static const String quietStates = 'quiet_states';

  /// Spec 8 (research 06 F14, B3).
  static const String privateSafetyCheck = 'private_safety_check';
  static const String conflictToolkit = 'conflict_toolkit';

  /// The couple map (Planning's Map tab and the distance widget).
  static const String coupleMap = 'couple_map_enabled';

  static const Map<String, bool> _defaults = <String, bool>{
    imageSharing: false,
    translatorEntry: false,
    expandedHeaderDrawer: false,
    voiceMessages: false,
    reactions: false,
    editDelete: false,
    videoSharing: false,
    linkPreviews: false,
    historicalImport: false,
    ephemeralVideo: false,
    quizClinicalSignoff: false,
    appreciationNotes: false,
    shareAWin: false,
    quietStates: false,
    privateSafetyCheck: false,
    conflictToolkit: false,
    coupleMap: false,
  };

  /// The value used when the flag cannot be read.
  static bool defaultFor(String flagName) => _defaults[flagName] ?? false;

  static Future<bool> isEnabled(
    SupabaseClient supabase,
    String flagName,
  ) async {
    final safeDefault = _defaults[flagName] ?? false;
    try {
      final row =
          await supabase
              .from('feature_flags')
              .select('enabled')
              .eq('key', flagName)
              .maybeSingle();
      return row == null ? safeDefault : row['enabled'] == true;
    } catch (_) {
      return safeDefault;
    }
  }
}

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
  static const String streaks = 'chat_streaks';

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
    streaks: false,
  };

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

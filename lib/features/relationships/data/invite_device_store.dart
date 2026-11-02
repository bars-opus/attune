import 'package:shared_preferences/shared_preferences.dart';

/// What the couples flow keeps on this phone for one account (Spec 1 §3.8,
/// §4.8, §5.8), never on the server:
///   * R1's partner first name, `attune.flow.<uid>.partner_first_name`:
///     used in the message and on this phone only; deleted on linking and
///     by the sign-out wipe (`spec1.partner_first_name`).
///   * R3's day-30 line, `attune.flow.<uid>.invite_day30`: shown once.
///   * R4's linked moment, `attune.linked_moment:<uid>:<relationshipId>`:
///     once per phone per relationship, so it survives sign-out (its prefix
///     is in PreferencesService.keptPrefixes; W4 plan P-15). It holds no
///     name.
class InviteDeviceStore {
  const InviteDeviceStore(this._prefs, {required this.userId});

  final SharedPreferences _prefs;
  final String userId;

  /// A first name is at most 40 characters, as display names are.
  static const maxNameLength = 40;

  static String partnerNameKey(String userId) =>
      'attune.flow.$userId.partner_first_name';

  static String day30Key(String userId) => 'attune.flow.$userId.invite_day30';

  static const linkedMomentPrefix = 'attune.linked_moment:';

  static String linkedMomentKey(String userId, String relationshipId) =>
      '$linkedMomentPrefix$userId:$relationshipId';

  /// The keys the sign-out wipe removes, for every account on the phone.
  static bool isWipedOnSignOut(String key) =>
      key.startsWith('attune.flow.') &&
      (key.endsWith('.partner_first_name') || key.endsWith('.invite_day30'));

  String? get partnerFirstName {
    final name = _prefs.getString(partnerNameKey(userId))?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  /// Blank removes it; longer than [maxNameLength] is cut.
  Future<void> savePartnerFirstName(String? name) async {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      await _prefs.remove(partnerNameKey(userId));
      return;
    }
    await _prefs.setString(
      partnerNameKey(userId),
      trimmed.length > maxNameLength
          ? trimmed.substring(0, maxNameLength)
          : trimmed,
    );
  }

  Future<void> clearPartnerFirstName() => _prefs.remove(partnerNameKey(userId));

  bool get day30Done => _prefs.getBool(day30Key(userId)) ?? false;

  Future<void> markDay30Done() => _prefs.setBool(day30Key(userId), true);

  bool linkedMomentSeen(String relationshipId) =>
      _prefs.getBool(linkedMomentKey(userId, relationshipId)) ?? false;

  Future<void> markLinkedMomentSeen(String relationshipId) =>
      _prefs.setBool(linkedMomentKey(userId, relationshipId), true);
}

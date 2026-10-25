/// RI-2's invite code rule (Spec 1 §3.8): six characters, A–Z and 2–9,
/// case-insensitive, spaces ignored. Returns the code as the server stores
/// it, or null when it can't be one.
String? normalizeInviteCode(String input) {
  final code = input.replaceAll(RegExp(r'\s'), '').toUpperCase();
  return RegExp(r'^[A-Z2-9]{6}$').hasMatch(code) ? code : null;
}

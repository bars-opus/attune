/// A4's resend ladder and code lifetime (Spec 1 §3.3, §4.5).
class ResendLadder {
  const ResendLadder._();

  /// A phone code is valid for 10 minutes (the Auth setting).
  static const codeLifetime = Duration(minutes: 10);

  /// "Send a new code" is available 30 s after the first send, 60 s after
  /// the second and 120 s after every later one.
  static Duration waitAfter(int sendCount) =>
      sendCount <= 1
          ? const Duration(seconds: 30)
          : sendCount == 2
          ? const Duration(seconds: 60)
          : const Duration(seconds: 120);

  static Duration remaining({
    required DateTime? lastSentAt,
    required int sendCount,
    required DateTime now,
  }) {
    if (lastSentAt == null) return Duration.zero;
    final left = lastSentAt.add(waitAfter(sendCount)).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// After the second resend (the third send) A4 also offers WhatsApp and a
  /// call.
  static bool offersOtherChannels(int sendCount) => sendCount >= 3;

  /// After any resend A4 says "Use the newest code." (D11).
  static bool saysUseNewest(int sendCount) => sendCount >= 2;

  static bool isExpired({
    required DateTime lastSentAt,
    required DateTime now,
  }) => now.difference(lastSentAt) > codeLifetime;

  /// "0:30", "1:05".
  static String clock(Duration left) {
    final seconds = left.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

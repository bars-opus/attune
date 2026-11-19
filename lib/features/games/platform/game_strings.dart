/// Every word the games shell shows.
///
/// In one file, and never inline, because game text is not translated yet:
/// none of the games use the app's localisation today. Keeping the shell's
/// words together makes moving them into it a mechanical pass later.
abstract final class GameStrings {
  // Landing page
  static const String play = 'Play';
  static const String join = 'Join';
  static const String yourTurn = 'Your turn';
  static const String playAgain = 'Play again';
  static const String comingSoon = 'Coming soon';
  static const String waitingForPartner = 'Waiting for your partner';
  static String waitingFor(String name) => 'Waiting for $name';
  static const String remind = 'Send a reminder';
  static String entryNumber(int number, String title) => '$number. $title';
  static String roundOf(int round, int total) => 'Round $round of $total';
  static const String games = 'Games';
  static const String notAvailable = 'This game is not available.';

  // Hub
  static const String inPlay = 'In play';
  static const String playTogether = 'Play together';
  static String playWith(String name) => 'Play with $name';
  static String comingSoonNamed(String title) => '$title, coming soon';

  // Header
  static const String back = 'Back';
  static const String settings = 'Settings';
  static const String howToPlay = 'How to play';
  static const String close = 'Close';

  // Settings sheet
  static const String general = 'General';
  static const String support = 'Support';
  static const String soundEffects = 'Sound effects';
  static const String soundEffectsHint = 'Taps, reveals and wins';
  static const String haptics = 'Vibration';
  static const String hapticsHint = 'A small tap you can feel';
  static const String reportProblem = 'Report a problem';
  static const String leaveGame = 'Leave game';

  // Tutorial
  static const String next = 'Next';
  static const String skip = 'Skip';
  static const String gotIt = 'Got it';

  // Completion
  static const String backToGames = 'Back to games';
}

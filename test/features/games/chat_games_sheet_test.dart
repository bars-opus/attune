import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every launchable destination is reachable from the catalogue', () {
    // The catalogue is a const list, so a destination added to the enum
    // without a matching entry is invisible in the UI with no compile
    // error. This is the guard against that.
    //
    // gamesHub is excluded because it is not a game: it is the "see all"
    // destination the sheet itself routes to, so it correctly has no
    // catalogue entry. Verified against the current file — every other
    // enum value does have one.
    final reachable = chatGameDestinationsInCatalogue();
    final launchable = ChatGameDestination.values
        .where((d) => d != ChatGameDestination.gamesHub);
    for (final destination in launchable) {
      expect(
        reachable.contains(destination),
        isTrue,
        reason: '$destination has no entry in _chatGameCategories',
      );
    }
  });

  test('the three session games are present', () {
    final reachable = chatGameDestinationsInCatalogue();
    expect(reachable, contains(ChatGameDestination.mirror));
    expect(reachable, contains(ChatGameDestination.slidingScale));
    expect(reachable, contains(ChatGameDestination.scenario));
  });
}

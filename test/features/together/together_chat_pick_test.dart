import 'package:attune/features/together/presentation/screens/together_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart' show activeConversation;

void main() {
  test("the care card opens this couple's chat, not just the newest one", () {
    final other = activeConversation('rel-old');
    final ours = activeConversation('rel-1');
    expect(
      togetherConversationFor([other, ours], 'rel-1')?.relationshipId,
      'rel-1',
    );
    expect(
      togetherConversationFor([other], 'rel-1')?.relationshipId,
      'rel-old',
      reason: 'fallback: one we can send in',
    );
    expect(togetherConversationFor([], 'rel-1'), isNull);
  });
}

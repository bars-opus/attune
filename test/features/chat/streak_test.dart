import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  test('fetchStreak returns the repository value', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a')..streakValue = 5;
    expect(await repo.fetchStreak('rel-1'), 5);
  });

  test('fetchStreak defaults to 0', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    expect(await repo.fetchStreak('rel-1'), 0);
  });
}

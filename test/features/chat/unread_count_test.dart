import 'package:attune/features/chat/domain/services/unread_count.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a bare number is the count', () {
    expect(parseUnreadCount(3), 3);
    expect(parseUnreadCount(3.0), 3);
  });

  test('wrapped shapes are unwrapped', () {
    expect(parseUnreadCount([2]), 2);
    expect(parseUnreadCount({'count_unread_messages': 4}), 4);
    expect(
      parseUnreadCount([
        {'count_unread_messages': 5},
      ]),
      5,
    );
  });

  test('anything else is zero, never a throw', () {
    expect(parseUnreadCount(null), 0);
    expect(parseUnreadCount('x'), 0);
    expect(parseUnreadCount(const []), 0);
    expect(parseUnreadCount(-1), 0);
  });
}

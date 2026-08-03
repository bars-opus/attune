import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts a click event with title, body, and data into an AppNotification', () {
    final notification = appNotificationFromPushData(
      notificationId: 'abc-123',
      title: 'Your partner joined Attune',
      body: 'You can start chatting now.',
      additionalData: {'type': 'invite_accepted', 'screen': 'chat'},
    );

    expect(notification.id, 'abc-123');
    expect(notification.title, 'Your partner joined Attune');
    expect(notification.body, 'You can start chatting now.');
    expect(notification.data, {'type': 'invite_accepted', 'screen': 'chat'});
  });

  test('falls back to empty strings when title/body are null', () {
    final notification = appNotificationFromPushData(
      notificationId: 'xyz-789',
      title: null,
      body: null,
      additionalData: {'type': 'ask2_invite', 'relationship_id': 'rel-1'},
    );

    expect(notification.title, '');
    expect(notification.body, '');
    expect(notification.data?['relationship_id'], 'rel-1');
  });

  test('data is null when additionalData is null', () {
    final notification = appNotificationFromPushData(
      notificationId: 'no-data',
      title: 'Title only',
      body: 'Body only',
      additionalData: null,
    );

    expect(notification.data, isNull);
  });
}

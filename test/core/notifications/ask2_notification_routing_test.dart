// test/core/notifications/ask2_notification_routing_test.dart
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/notifications/domain/entities/notification_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ask2Invite notification type carries the expected value', () {
    expect(CommonNotificationTypes.ask2Invite.value, 'ask2_invite');
  });

  test('ask2Flow route path matches the relationship-id path param convention', () {
    expect(RouteNames.ask2Flow, '/ask2/:relationshipId');
  });
}

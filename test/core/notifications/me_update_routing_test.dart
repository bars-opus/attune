// Spec 2 W3a (§3.13, I-9, A-7): the neutral Dating push opens Me. Spec 2
// W10 (A-7): the old match push's case is gone; a stale one opens Home
// (no tab), as any type the app doesn't know.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final (type, shown) in [
    ('me_update', 'HOME me'),
    ('dating_mutual_match', 'HOME null'),
  ]) {
    testWidgets('$type opens $shown', (tester) async {
      late BuildContext tapContext;
      final router = GoRouter(
        initialLocation: '/somewhere',
        routes: [
          GoRoute(
            path: '/somewhere',
            builder:
                (context, _) => Builder(
                  builder: (c) {
                    tapContext = c;
                    return const Text('ELSEWHERE');
                  },
                ),
          ),
          GoRoute(
            path: RouteNames.home,
            builder: (_, s) => Text('HOME ${s.uri.queryParameters['tab']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      buildNanoEmbryoNotificationConfig().onNotificationTap!(
        AppNotification(
          id: 'n1',
          title: 'Attune',
          body: 'You have something new in Attune.',
          data: {'type': type, 'route': 'me'},
          createdAt: DateTime.utc(2026, 11, 7, 20),
        ),
        tapContext,
      );
      await tester.pumpAndSettle();
      expect(find.text(shown), findsOneWidget);
    });
  }
}

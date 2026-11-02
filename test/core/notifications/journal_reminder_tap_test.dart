// Spec 1 W3c (§3.11, §3.10 J3): a journal reminder tap opens Me (Tab 2,
// /home?tab=me) with the journal on top.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('journal_reminder: Me, then the journal', (tester) async {
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
        GoRoute(
          path: RouteNames.reflectionJournal,
          builder: (_, __) => const Text('JOURNAL'),
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
        body: "A few quiet minutes for you, if you'd like.",
        data: const {'type': 'journal_reminder'},
        createdAt: DateTime.utc(2026, 11, 2, 20),
      ),
      tapContext,
    );
    await tester.pumpAndSettle();
    expect(find.text('JOURNAL'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('HOME me'), findsOneWidget);
  });
}

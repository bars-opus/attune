// Spec 2 W6c (§3.6 Check on me, §3.13): the neutral check-in push opens
// the check-in behind the Dating lock: locked, the Safety PIN comes first.
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../features/dating/support/dating_shell.dart';

void main() {
  final loc = AppLocalizationsEn();
  for (final locked in [true, false]) {
    testWidgets('me_checkin opens the check-in (locked: $locked)', (t) async {
      late BuildContext tapContext;
      final s = await pumpDatingShell(
        t,
        initial: '/somewhere',
        locked: locked,
        pinSet: true,
        extraRoutes: [
          GoRoute(
            path: '/somewhere',
            builder:
                (context, _) => Builder(
                  builder: (c) {
                    tapContext = c;
                    return const Scaffold(body: Text('ELSEWHERE'));
                  },
                ),
          ),
        ],
      );
      buildNanoEmbryoNotificationConfig().onNotificationTap!(
        AppNotification(
          id: 'n1',
          title: 'Attune',
          body: 'A quick check-in from Attune.',
          data: const {'type': 'me_checkin', 'route': 'me_checkin'},
          createdAt: DateTime.utc(2026, 11, 21, 18, 30),
        ),
        tapContext,
      );
      await t.pumpAndSettle();
      if (locked) {
        expect(s.location, startsWith('/dating/unlock?from='));
        expect(find.text(loc.dating_checkinTitle), findsNothing);
        expect(find.text('Enter your Safety PIN'), findsOneWidget);
      } else {
        expect(s.location, '/dating/checkin');
        expect(find.text(loc.dating_checkinOk), findsOneWidget);
      }
    });
  }
}

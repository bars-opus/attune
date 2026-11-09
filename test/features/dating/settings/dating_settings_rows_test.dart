// Spec 2 W3c (§3.12, §3.8 pause; carries 1, 13; R-40, R-41): the rows.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/ready_step.dart'
    show datingDropTimeLabel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

Future<
  (
    FakeDatingSetupGateway,
    FakeDatingLifecycleGateway,
    FakeDatingPhotosGateway,
    FakePushAsker,
  )
>
_pump(
  WidgetTester t, {
  DatingHomeState state = DatingHomeState.active,
  bool hasData = false,
  DatingMyProfile profile = const DatingMyProfile(
    dropTime: '19:00:00',
    minAge: 25,
    maxAge: 35,
  ),
  DateTime? afterMutualFrom,
  bool granted = true,
  DatingLifecycleResult result = const DatingLifecycleResult.done('paused'),
}) async {
  await t.pumpWidget(const SizedBox());
  final setup = FakeDatingSetupGateway(profile: profile);
  final life = FakeDatingLifecycleGateway()..result = result;
  final photos = FakeDatingPhotosGateway(
    afterMutualFrom: afterMutualFrom ?? DateTime.utc(2026, 1, 1),
  );
  final asker = FakePushAsker(granted: granted);
  await pumpFlowScreen(
    t,
    () => const DatingSettingsScreen(),
    overrides: [
      ...datingShellOverrides(
        home: FakeDatingHomeGateway(
          home: DatingHome(state: state, hasData: hasData),
        ),
        life: life,
      ),
      datingSetupGatewayProvider.overrideWithValue(setup),
      datingPhotosGatewayProvider.overrideWithValue(photos),
      pushAskerProvider.overrideWithValue(asker),
    ],
  );
  await t.pumpAndSettle();
  return (setup, life, photos, asker);
}

void main() {
  testWidgets(
    '§3.12 order: time, who, ages, how far, photos, data saver, notifications, lock, pause, leave',
    (t) async {
      await _pump(t);
      final order = [
        'Introduction time',
        "Who I'd like to meet",
        'Ages',
        'How far',
        'Photos after mutual interest',
        'Data saver',
        'Notifications',
        'Dating lock',
        'Pause Dating',
        'Leave Dating and delete my data',
      ];
      double y(String s) => t.getTopLeft(find.text(s).first).dy;
      for (var i = 1; i < order.length; i++) {
        expect(
          y(order[i - 1]),
          lessThan(y(order[i])),
          reason: '${order[i - 1]} before ${order[i]}',
        );
      }
      expect(find.text(datingDropTimeLabel('19:00')), findsOneWidget);
      expect(find.text('25 to 35'), findsOneWidget);
      expect(find.textContaining('Never introduce'), findsNothing);
      expect(find.textContaining('App icon'), findsNothing);
    },
  );

  testWidgets('introduction time: the labelled list, saved', (t) async {
    final (setup, _, _, _) = await _pump(t);
    await tapInReach(t, find.text('Introduction time'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text(datingDropTimeLabel('07:00')));
    await t.pumpAndSettle();
    expect(setup.lastWrite.$2['values'], {'drop_time': '07:00'});
  });

  testWidgets('data saver and messages save their own keys', (t) async {
    final (setup, _, _, _) = await _pump(t);
    await tapInReach(t, find.widgetWithText(SwitchListTile, 'Data saver'));
    await t.pumpAndSettle();
    expect(setup.lastWrite.$2['values'], {'data_saver': true});
    await tapInReach(
      t,
      find.widgetWithText(SwitchListTile, 'Tell me when someone messages me'),
    );
    await t.pumpAndSettle();
    expect(setup.lastWrite.$2['values'], {'chat_push': false});
  });

  testWidgets('the digest asks for permission first when it is off', (t) async {
    final (setup, _, _, asker) = await _pump(t, granted: false);
    asker.grantOnAsk = false;
    await tapInReach(
      t,
      find.widgetWithText(
        SwitchListTile,
        'Tell me about new introductions and matches, at most once a day.',
      ),
    );
    await t.pumpAndSettle();
    expect(asker.asked, hasLength(1));
    expect(setup.writes, isEmpty);
  });

  testWidgets('photos after mutual interest waits for day 30', (t) async {
    await _pump(
      t,
      afterMutualFrom: DateTime.now().toUtc().add(const Duration(days: 3)),
    );
    final toggle = t.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Photos after mutual interest'),
    );
    expect(toggle.onChanged, isNull);
    expect(find.textContaining('Available from '), findsOneWidget);
  });

  testWidgets('pause: the §3.8 line, silent to everyone', (t) async {
    final (_, life, _, _) = await _pump(t);
    await tapInReach(t, find.text('Pause Dating'));
    await t.pumpAndSettle();
    expect(life.calls, ['pause']);
    expect(
      find.text(
        'Dating is paused. Nobody new sees you, and your conversations stay open.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'resume on a path that is not Dating says how to carry on (carry 1)',
    (t) async {
      final (_, life, _, _) = await _pump(
        t,
        state: DatingHomeState.paused,
        result: const DatingLifecycleResult.refused(
          DatingLifecycleError.pathNotDating,
        ),
      );
      expect(find.text('Pause Dating'), findsNothing);
      await tapInReach(t, find.text('Resume Dating'));
      await t.pumpAndSettle();
      expect(life.calls, ['resume']);
      expect(
        find.text('Choose Dating in How you use Attune to carry on.'),
        findsOneWidget,
      );
      expect(find.text('How you use Attune'), findsOneWidget);
    },
  );

  for (final state in DatingHomeState.values) {
    testWidgets('R-41: Leave is there for ${state.wire} unless not started', (
      t,
    ) async {
      await _pump(t, state: state);
      expect(
        find.text('Leave Dating and delete my data'),
        state == DatingHomeState.notStarted ? findsNothing : findsOneWidget,
      );
    });
  }

  // C-2: with any Dating data (a reflection, a notice, an enrolment) Leave
  // and Clear are both there, whatever the state.
  for (final state in DatingHomeState.values) {
    testWidgets('C-2: ${state.wire} with Dating data offers Leave and Clear', (
      t,
    ) async {
      await _pump(t, state: state, hasData: true);
      expect(find.text('Leave Dating and delete my data'), findsOneWidget);
      expect(
        find.text('Clear my answers to the three questions'),
        findsOneWidget,
      );
    });
  }

  testWidgets('settings goldens', (t) async {
    await expectFlowGoldens(
      t,
      'dating_settings_full',
      () => const DatingSettingsScreen(),
      overrides: [
        ...datingShellOverrides(
          home: FakeDatingHomeGateway(
            home: const DatingHome(state: DatingHomeState.active),
          ),
        ),
        datingSetupGatewayProvider.overrideWithValue(
          FakeDatingSetupGateway(
            profile: const DatingMyProfile(
              dropTime: '19:00:00',
              minAge: 25,
              maxAge: 35,
            ),
          ),
        ),
        datingPhotosGatewayProvider.overrideWithValue(
          FakeDatingPhotosGateway(afterMutualFrom: DateTime.utc(2026, 1, 1)),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
      ],
    );
  });
}

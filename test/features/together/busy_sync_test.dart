import 'package:attune/features/together/data/device_busy_source.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_overlay.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

class FakeBusySource implements DeviceBusySource {
  FakeBusySource({this.access = true, this.events = const []});
  bool access;
  final List<DeviceBusy> events;
  @override
  Future<bool> hasAccess() async => access;
  @override
  Future<bool> requestAccess() async => access;
  @override
  Future<List<DeviceBusy>> read(DateTime from, DateTime to) async => events;
  int settingsOpened = 0;
  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  final now = DateTime.utc(2026, 11, 10, 8);

  test('when on, only rounded times are uploaded', () async {
    final g = FakeTogetherGateway({
      'get_together_overlay': (_) => {'level': 'free_windows'},
      'replace_my_busy_blocks': (_) => 1,
    });
    final ok = await syncBusyTimes(
      TogetherRepository(g),
      FakeBusySource(
        events: [
          DeviceBusy(
            start: DateTime.utc(2026, 11, 10, 9, 10),
            end: DateTime.utc(2026, 11, 10, 9, 40),
          ),
        ],
      ),
      'r1',
      now,
    );
    expect(ok, isTrue);
    expect(g.calls.last.$2, {
      'p_relationship_id': 'r1',
      'p_blocks': [
        {
          'starts_at': '2026-11-10T09:00:00.000Z',
          'ends_at': '2026-11-10T10:00:00.000Z',
        },
      ],
    });
  });

  test('the calendar copy of our plans is never uploaded as busy', () async {
    SharedPreferences.setMockInitialValues({
      'together_mirror_calendar_id': 'cal-copy',
    });
    final g = FakeTogetherGateway({
      'get_together_overlay': (_) => {'level': 'free_windows'},
      'replace_my_busy_blocks': (_) => 1,
    });
    await syncBusyTimes(
      TogetherRepository(g),
      FakeBusySource(
        events: [
          DeviceBusy(
            start: DateTime.utc(2026, 11, 10, 9),
            end: DateTime.utc(2026, 11, 10, 10),
            calendarId: 'work',
          ),
          DeviceBusy(
            start: DateTime.utc(2026, 11, 10, 19),
            end: DateTime.utc(2026, 11, 10, 21),
            calendarId: 'cal-copy',
          ),
        ],
      ),
      'r1',
      now,
    );
    expect(g.calls.last.$2['p_blocks'], [
      {
        'starts_at': '2026-11-10T09:00:00.000Z',
        'ends_at': '2026-11-10T10:00:00.000Z',
      },
    ]);
  });

  test('off, or no calendar access: nothing is read or sent', () async {
    for (final (level, access) in [('off', true), ('free_windows', false)]) {
      final g = FakeTogetherGateway({
        'get_together_overlay': (_) => {'level': level},
        'replace_my_busy_blocks': (_) => 0,
      });
      final ok = await syncBusyTimes(
        TogetherRepository(g),
        FakeBusySource(access: access),
        'r1',
        now,
      );
      expect(ok, isFalse);
      expect(g.calls.any((c) => c.$1 == 'replace_my_busy_blocks'), isFalse);
    }
  });

  test('windows and strips map from the server', () async {
    final g = FakeTogetherGateway({
      'list_together_free_windows':
          (_) => [
            {
              'starts_at': '2026-11-10T13:00:00+00:00',
              'ends_at': '2026-11-10T15:00:00+00:00',
              'partner_from': '08:00',
              'partner_to': '10:00',
              'partner_differs': true,
            },
          ],
      'list_together_busy_strips':
          (_) => [
            {
              'is_mine': false,
              'starts_at': '2026-11-10T09:00:00+00:00',
              'ends_at': '2026-11-10T12:00:00+00:00',
            },
          ],
      'set_together_overlay': (_) => {'level': 'off'},
    });
    final repo = TogetherRepository(g);
    expect((await repo.listFreeWindows('r1')).single.partnerTo, '10:00');
    expect((await repo.listBusyStrips('r1')).single.isMine, isFalse);
    await repo.setOverlay('r1', OverlayLevel.off);
    expect(g.calls.last.$2, {'p_relationship_id': 'r1', 'p_level': 'off'});
  });
}

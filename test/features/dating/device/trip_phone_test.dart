// Spec 2 W8b (§2.5, §3.11; R-T4-9, Re4-I-2, carries 1-2): a same-gender
// trip's note and "Show it on this phone anyway" live on this phone only,
// one mark per account under one neutral key (nothing in it names Dating,
// a gender, a trip or a place). The mark is made only by an answer; every
// same-gender home moves its time; it goes after 7 consecutive days with
// no same-gender home (a flip within them keeps it), and quick exit and
// sign-out remove it. The reads (Today, act, the conversations, the
// messages) ask for the hidden ones only while this account chose to see
// them here; an unreadable keystore is no mark (fail closed).
import 'dart:async';
import 'dart:convert';

import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../support/dating_today_fakes.dart';

const _trip = DatingHome(
  state: DatingHomeState.active,
  hasData: true,
  trip: DatingTrip(kind: DatingTripKind.sameGender),
);
const _home = DatingHome(state: DatingHomeState.active, hasData: true);

final _day0 = DateTime.utc(2026, 11, 1, 9);
DateTime _day(num d) =>
    _day0.add(Duration(minutes: (d * Duration.minutesPerDay).round()));

/// The test's day: every test runs on a clock at [_today] (fix round 1:
/// a mark is read against the clock, so assertions outside [_at] must be
/// on the same day as the last step).
num _today = 0;

/// [f] with the clock moved to day [d] (and left there).
Future<T> _at<T>(num d, Future<T> Function() f) {
  _today = d;
  return f();
}

/// A test on the test's clock.
void _test(String name, Future<void> Function() body) =>
    test(name, () => withClock(Clock(() => _day(_today)), body));

Future<DatingHome> _read(String account, DatingHome home) async =>
    await DatingTripPhone.onHome(account, home);

/// The note shows for [account] on a same-gender home at day [d].
Future<bool> _noteAt(num d, [String account = 'ama']) =>
    _at(d, () async => (await _read(account, _trip)).trip!.note);

/// Lets the background expiry (and its write) land.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// A keystore whose writes land at once (in order, as the platform runs
/// them) but answer only when [gate] completes.
class _SlowStorage extends FlutterSecureStorage {
  final data = <String, String>{};
  final calls = <String>[];
  final gate = Completer<void>();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('write');
    data[key] = value!;
    await gate.future;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('delete');
    data.remove(key);
  }
}

/// Final client fix (M-1): a keystore as iOS's plugin runs it (calls on a
/// concurrent queue): a write lands on the keystore only when [gate]
/// completes, so a delete sent after it can land first.
class _LateStorage extends FlutterSecureStorage {
  final data = <String, String>{};
  final calls = <String>[];
  final gate = Completer<void>();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('read');
    return data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('write');
    await gate.future;
    data[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('delete');
    data.remove(key);
  }
}

Future<Map<String, String>> _stored() => const FlutterSecureStorage().readAll();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _today = 0;
    FlutterSecureStorage.setMockInitialValues({});
    DatingTripPhone.reset();
  });

  group('the mark', () {
    test('a same-gender home with no answer shows the note and nothing '
        'anyway; nothing is kept until the person answers', () async {
      final h = await _at(0, () => _read('ama', _trip));
      expect(h.trip?.kind, DatingTripKind.sameGender);
      expect(h.trip?.note, isTrue);
      expect(h.trip?.showHere, isFalse);
      expect(h.hasData, isTrue);
      expect(await _stored(), isEmpty);
      expect(await DatingTripPhone.showFor('ama'), isFalse);
    });

    _test('an answer is kept; the note is answered and its choice read '
        'back after a restart', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      DatingTripPhone.reset();
      final h = await _at(1, () => _read('ama', _trip));
      expect(h.trip?.note, isFalse);
      expect(h.trip?.showHere, isTrue);
      expect(await DatingTripPhone.showFor('ama'), isTrue);
      await _at(1, () => DatingTripPhone.answer('ama', show: false));
      DatingTripPhone.reset();
      expect(await DatingTripPhone.showFor('ama'), isFalse);
      expect(await _noteAt(1), isFalse);
    });

    _test('the key and the value are neutral', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      final stored = await _stored();
      expect(stored.keys, [DatingTripPhone.key]);
      final words = RegExp(
        'dating|gender|same|trip|away|show|note|country|place',
        caseSensitive: false,
      );
      for (final MapEntry(:key, :value) in stored.entries) {
        expect(words.hasMatch(key), isFalse, reason: key);
        expect(words.hasMatch(value), isFalse, reason: value);
      }
      expect(jsonDecode(stored[DatingTripPhone.key]!), {
        'ama': [1, _day0.millisecondsSinceEpoch ~/ 1000],
      });
    });

    _test('Re4-I-2: a home that flips within 7 days keeps the note '
        'answered', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: false));
      for (final d in [0.5, 2, 4, 6.9]) {
        await _at(d, () => _read('ama', _home));
        await _settle();
        expect(await _noteAt(d), isFalse, reason: 'day $d');
      }
      // Each same-gender home moved the time: 6.9 days after the last one
      // the note is still answered.
      for (final d in [8, 13.8]) {
        await _at(d, () => _read('ama', _home));
        await _settle();
      }
      expect(await _noteAt(13.8), isFalse);
      expect(await DatingTripPhone.markFor('ama'), isNotNull);
    });

    _test('Re4-I-2: 7 consecutive days with no same-gender home clear the '
        'mark: the note shows again, nothing is shown anyway', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      await _at(6.99, () => _read('ama', _home));
      await _settle();
      expect(await DatingTripPhone.showFor('ama'), isTrue);
      await _at(7, () => _read('ama', _home));
      await _settle();
      expect(await DatingTripPhone.markFor('ama'), isNull);
      expect(await DatingTripPhone.showFor('ama'), isFalse);
      expect(await _stored(), isEmpty);
      expect(await _noteAt(7.5), isTrue);
    });

    _test('fix round 1 (I-1): an answer 7 days old is no answer, even with '
        'no home read in between: the note shows again and nothing is '
        'shown anyway', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      expect(await _noteAt(30), isTrue);
      expect(await DatingTripPhone.showFor('ama'), isFalse);
      expect(await _stored(), isEmpty);
    });

    _test('fix round 1 (I-1): the reads ask for nothing on a stale answer '
        'before any home is read (Today opened first)', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      DatingTripPhone.reset();
      expect(await _at(6.9, () => DatingTripPhone.showFor('ama')), isTrue);
      expect(await _at(7, () => DatingTripPhone.showFor('ama')), isFalse);
    });

    _test('fix round 1 (I-1): the clock set back makes the answer no '
        'answer; a small skew keeps it', () async {
      await _at(30, () => DatingTripPhone.answer('ama', show: true));
      // Hours behind (a time zone change, a sync): still answered.
      expect(await _at(29.9, () => DatingTripPhone.showFor('ama')), isTrue);
      expect(await _noteAt(29.9), isFalse);
      // Set back 2 days: the answer is dated ahead of the phone's clock.
      expect(await _at(28, () => DatingTripPhone.showFor('ama')), isFalse);
      expect(await _noteAt(28), isTrue);
      // A home without a trip clears a future-dated mark too.
      await _at(30, () => DatingTripPhone.answer('kofi', show: true));
      await _at(0, () => _read('kofi', _home));
      await _settle();
      expect(await _stored(), isEmpty);
    });

    _test('fix round 1 (M-7): a wipe while a same-gender home is read: the '
        'note shows (the old answer is gone)', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      final read = _read('ama', _trip);
      await DatingTripPhone.clear();
      final h = await read;
      expect(h.trip?.note, isTrue);
      expect(h.trip?.showHere, isFalse);
      expect(await _stored(), isEmpty);
    });

    _test('D8: one mark per account; clearing one keeps the other', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      expect(await _noteAt(0, 'kofi'), isTrue);
      expect(await DatingTripPhone.showFor('kofi'), isFalse);
      expect(await DatingTripPhone.showFor(null), isFalse);
      await _at(3, () => DatingTripPhone.answer('kofi', show: false));
      await _at(8, () => _read('ama', _home));
      await _settle();
      expect(await DatingTripPhone.markFor('ama'), isNull);
      expect(await DatingTripPhone.markFor('kofi'), isNotNull);
      DatingTripPhone.reset();
      expect((await DatingTripPhone.markFor('kofi'))?.show, isFalse);
    });

    _test('final client fix (M-2): another account\'s mark leaves the '
        'keystore once 7 days old, while someone else uses the '
        'phone', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      await _at(3, () => DatingTripPhone.answer('kofi', show: false));
      // Kofi's home at day 8: Ama's mark is 8 days old.
      await _at(8, () => _read('kofi', _home));
      await _settle();
      expect(jsonDecode((await _stored())[DatingTripPhone.key]!).keys, [
        'kofi',
      ]);
      // An answer never writes another account's stale mark back.
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      await _at(9, () => DatingTripPhone.answer('kofi', show: true));
      expect(jsonDecode((await _stored())[DatingTripPhone.key]!).keys, [
        'kofi',
      ]);
    });

    _test('final client fix (M-2): a stale mark read from the keystore on a '
        'fresh start leaves it, whoever reads', () async {
      await _at(0, () => DatingTripPhone.answer('ama', show: true));
      await _at(5, () => DatingTripPhone.answer('kofi', show: true));
      DatingTripPhone.reset();
      // Kofi's own read at day 8 (a same-gender home): Ama's is stale.
      expect(await _noteAt(8, 'kofi'), isFalse);
      await _settle();
      expect(jsonDecode((await _stored())[DatingTripPhone.key]!).keys, [
        'kofi',
      ]);
      DatingTripPhone.reset();
      expect(await _at(8, () => DatingTripPhone.markFor('yaw')), isNull);
      await _settle();
      expect(jsonDecode((await _stored())[DatingTripPhone.key]!).keys, [
        'kofi',
      ]);
    });

    test('an unreadable or malformed keystore is no mark', () async {
      for (final raw in ['not json', '[1]', '{"ama": [1]}', '{"ama": "x"}']) {
        FlutterSecureStorage.setMockInitialValues({DatingTripPhone.key: raw});
        DatingTripPhone.reset();
        expect(await DatingTripPhone.showFor('ama'), isFalse, reason: raw);
        expect(await _noteAt(0), isTrue, reason: raw);
      }
    });

    test('a home that isn\'t a same-gender trip is the home as read', () {
      expect(identical(DatingTripPhone.onHome('ama', _home), _home), isTrue);
    });
  });

  group('the wipe', () {
    for (final moment in WipeMoment.values) {
      _test('${moment.name} removes every account\'s mark', () async {
        await _at(0, () => DatingTripPhone.answer('ama', show: true));
        await _at(0, () => DatingTripPhone.answer('kofi', show: false));
        final registry = DeviceWipeRegistry();
        registerDatingDeviceWipes(registry);
        await registry.run(moment);
        expect(await _stored(), isEmpty);
        expect(await DatingTripPhone.markFor('ama'), isNull);
        expect(await DatingTripPhone.markFor('kofi'), isNull);
        expect(await _noteAt(1), isTrue);
      });
    }

    _test('fix round 1 (M-5): the wipe empties memory and sends the '
        'keystore delete before its first await, even while a write is still '
        'on its way to the keystore', () async {
      final slow = _SlowStorage();
      DatingTripPhone.storage = slow;
      addTearDown(
        () => DatingTripPhone.storage = SafetyPinStore.defaultStorage,
      );
      final answered = DatingTripPhone.answer('ama', show: true);
      await _settle();
      expect(slow.data, isNotEmpty);
      final wipe = DatingTripPhone.clear();
      // Sent in this same turn, after the write already sent (the
      // platform runs them in order), before quick exit's decoy.
      expect(slow.data, isEmpty);
      expect(slow.calls, ['write', 'delete']);
      expect(await DatingTripPhone.markFor('ama'), isNull);
      slow.gate.complete();
      await answered;
      await wipe;
      expect(slow.data, isEmpty);
    });

    _test('final client fix (M-1): a write that lands on the keystore after '
        'the wipe\'s first delete (iOS) is deleted again: the mark is gone '
        'when the wipe is done', () async {
      final late = _LateStorage();
      DatingTripPhone.storage = late;
      addTearDown(
        () => DatingTripPhone.storage = SafetyPinStore.defaultStorage,
      );
      final answered = DatingTripPhone.answer('ama', show: true);
      while (!late.calls.contains('write')) {
        await _settle();
      }
      final wipe = DatingTripPhone.clear();
      // M-5 still holds: memory is empty and a delete is sent at once.
      expect(late.calls.last, 'delete');
      expect(await DatingTripPhone.markFor('ama'), isNull);
      // The write lands after that delete, as iOS may run it.
      late.gate.complete();
      await answered;
      await wipe;
      expect(late.data, isEmpty);
      expect(late.calls, ['read', 'write', 'delete', 'delete']);
    });

    _test('final client fix (M-1): a read, a write and the wipe reach the '
        'keystore one at a time, in the order the app sent them', () async {
      final late = _LateStorage();
      DatingTripPhone.storage = late;
      addTearDown(
        () => DatingTripPhone.storage = SafetyPinStore.defaultStorage,
      );
      final answered = DatingTripPhone.answer('ama', show: true);
      final again = DatingTripPhone.answer('ama', show: false);
      await _settle();
      await _settle();
      // The second answer's write waits for the first one's.
      expect(late.calls, ['read', 'write']);
      late.gate.complete();
      await answered;
      await again;
      expect(late.calls, ['read', 'write', 'write']);
      expect(jsonDecode(late.data[DatingTripPhone.key]!), {
        'ama': [0, _day0.millisecondsSinceEpoch ~/ 1000],
      });
    });

    test('the entry: neutral, both moments, its one key, not protective', () {
      final registry = DeviceWipeRegistry();
      registerDatingDeviceWipes(registry);
      final entry = registry.entries.singleWhere(
        (e) => e.id == 'spec2.section_view',
      );
      expect(entry.moments, {WipeMoment.signOut, WipeMoment.quickExit});
      expect(entry.keys, {DatingTripPhone.key});
      expect(entry.protective, isFalse);
    });

    _test('an answer whose read a wipe overtook is not kept', () async {
      final answered = _at(0, () => DatingTripPhone.answer('ama', show: true));
      await DatingTripPhone.clear();
      await answered;
      expect(await DatingTripPhone.markFor('ama'), isNull);
      expect(await _stored(), isEmpty);
    });
  });

  group('the reads ask for what this account chose to see here', () {
    test('Today and act: p_show_same_gender, always an explicit boolean in '
        'the body (carry c)', () async {
      final calls = <(String, Map<String, dynamic>?)>[];
      var show = false;
      final repo = DatingTodayRepository(
        DatingRpc.withCall((fn, p) async {
          calls.add((fn, p));
          return fn == 'get_my_dating_today'
              ? datingTodayJson()
              : {'ok': true, 'action': 'interested'};
        }),
        (body) async => null,
        showSameGender: () async => show,
      );
      await repo.today();
      await repo.act('k' * 20, 'i1', 'interested');
      show = true;
      await repo.today();
      await repo.act('k' * 20, 'i1', 'interested');
      expect(calls[0].$2, {'p_show_same_gender': false});
      expect(calls[1].$2, {
        'p_idempotency_key': 'k' * 20,
        'p_introduction_id': 'i1',
        'p_action': 'interested',
        'p_show_same_gender': false,
      });
      expect(calls[2].$2, {'p_show_same_gender': true});
      expect(calls[3].$2, {
        'p_idempotency_key': 'k' * 20,
        'p_introduction_id': 'i1',
        'p_action': 'interested',
        'p_show_same_gender': true,
      });
    });

    test('the conversations and the messages: the same', () async {
      final calls = <(String, Map<String, dynamic>?)>[];
      var show = false;
      final repo = DatingChatRepository(
        DatingRpc.withCall((fn, p) async {
          calls.add((fn, p));
          return {'ok': true};
        }),
        null,
        showSameGender: () async => show,
      );
      await repo.conversations(ended: true);
      await repo.messages('m1');
      show = true;
      await repo.conversations(ended: true);
      await repo.messages('m1');
      expect(
        [for (final c in calls) c.$2],
        [
          {'p_include_ended': true, 'p_show_same_gender': false},
          {
            'p_match_id': 'm1',
            'p_before': null,
            'p_limit': 50,
            'p_show_same_gender': false,
          },
          {'p_include_ended': true, 'p_show_same_gender': true},
          {
            'p_match_id': 'm1',
            'p_before': null,
            'p_limit': 50,
            'p_show_same_gender': true,
          },
        ],
      );
    });

    test('a choice that can\'t be read is false', () async {
      final calls = <Map<String, dynamic>?>[];
      final repo = DatingTodayRepository(
        DatingRpc.withCall((fn, p) async {
          calls.add(p);
          return datingTodayJson();
        }),
        (body) async => null,
        showSameGender: () async => throw StateError('keystore'),
      );
      expect((await repo.today()).ok, isTrue);
      expect(calls.single, {'p_show_same_gender': false});
    });

    test(
      'the app\'s gateways read the signed-in account\'s own mark (D8)',
      () async {
        await _at(0, () => DatingTripPhone.answer('ama', show: true));
        final calls = <(String, Map<String, dynamic>?)>[];
        final account = StateProvider<String?>((ref) => 'ama');
        final client = SupabaseClient('http://127.0.0.1:9', 'anon');
        addTearDown(client.dispose);
        final container = ProviderContainer(
          overrides: [
            datingAccountProvider.overrideWith((ref) => ref.watch(account)),
            datingSupabaseClientProvider.overrideWithValue(client),
            datingRpcProvider.overrideWithValue(
              DatingRpc.withCall((fn, p) async {
                calls.add((fn, p));
                return {'ok': true};
              }),
            ),
          ],
        );
        addTearDown(container.dispose);
        final today = container.read(datingTodayGatewayProvider);
        final chat = container.read(datingChatGatewayProvider);
        await today.today();
        await today.act('k' * 20, 'i1', 'passed');
        await chat.conversations();
        await chat.messages('m1');
        expect(
          [for (final c in calls) c.$2?['p_show_same_gender']],
          [true, true, true, true],
        );
        calls.clear();
        container.read(account.notifier).state = 'kofi';
        await today.today();
        await chat.conversations();
        expect(
          [for (final c in calls) c.$2?['p_show_same_gender']],
          [false, false],
        );
      },
    );
  });
}

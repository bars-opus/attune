// Spec 2 W5b Task 6 rulings (the server and dating-photo-urls as their
// review fix rounds left them): a paused person is its own fixed code and
// every refusal is a fixed code (never a server's text); act's `busy`; the
// card's reason ids are exactly the ones private.dating_card can send,
// including a card left with only same_region or across_borders; a
// caption the contact check left off is normal; no photos while the photo
// flag is off; the photo memory keyed by (kind, id, position), aligned to
// the card's slots, asked a bounded number of times, and its decoded
// copies leave the image cache with it.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/core/device/device_wipe_registry.dart';

import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_reasons.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../support/dating_today_fakes.dart';

void main() {
  final loc = AppLocalizationsEn();

  group('fixed codes', () {
    test('Today: paused is its own code; any other text is failed', () {
      for (final (reason, want) in [
        ('paused', 'paused'),
        ('reverify_device', 'reverify_device'),
        ('not_eligible', 'not_eligible'),
        ('unavailable', 'unavailable'),
        ('busy', 'busy'),
        ('dating: field +233 24 555 0101 bad', 'failed'),
      ]) {
        final t = DatingToday.fromJson({'ok': false, 'reason': reason});
        expect((t.ok, t.reason), (false, want), reason: reason);
      }
    });

    test('act: busy after the lock wait, and every refusal fixed', () {
      for (final (reason, want) in [
        ('busy', 'busy'),
        ('invalid', 'invalid'),
        ('reverify_device', 'reverify_device'),
        ('not_eligible', 'not_eligible'),
        ('introduction_unavailable', 'introduction_unavailable'),
        ('rate_limited', 'rate_limited'),
        ('paused', 'failed'),
        ('a server\'s own words', 'failed'),
      ]) {
        final a = DatingActAnswer.fromJson({'ok': false, 'reason': reason});
        expect((a.ok, a.reason), (false, want), reason: reason);
      }
    });

    test('a malformed card drops; the rest of Today stands', () {
      final t = DatingToday.fromJson(
        datingTodayJson({
          'cards': [
            datingCardJson('a', {
              'photos': [
                {'id': 'p', 'position': 'one'},
                {'id': 'q', 'position': 2},
              ],
            }),
            datingCardJson('b'),
          ],
        }),
      );
      expect(t.ok, isTrue);
      expect(t.cards.map((c) => c.id), ['b']);
    });
  });

  group('the card as the server sends it', () {
    test('a caption left off (absent or null) is normal', () {
      final c =
          DatingIntroCard.fromJson(
            datingCardJson('a', {
              'photos': [
                {'id': 'p1', 'position': 1},
                {'id': 'p2', 'position': 2, 'caption': null},
                {'id': 'p3', 'position': 3, 'caption': 'Kumasi'},
              ],
            }),
          )!;
      expect(c.card.photoIds, ['p1', 'p2', 'p3']);
      expect(c.captions, [null, null, 'Kumasi']);
      expect(c.photoPositions, [1, 2, 3]);
    });

    test('no photos while the photo flag is off', () {
      final c =
          DatingIntroCard.fromJson(
            datingCardJson('a', {'photos': <Object?>[]}),
          )!;
      expect(c.card.photoIds, isEmpty);
      expect(c.captions, isEmpty);
      expect(c.photoPositions, isEmpty);
    });

    test('a card showing some of its photos keeps their own captions', () {
      final c =
          DatingIntroCard.fromJson(
            datingCardJson('a', {
              'photos': [
                {'id': 'p1', 'position': 1, 'caption': 'One'},
                {'id': 'p2', 'position': 2, 'caption': 'Two'},
              ],
            }),
          )!;
      expect(c.card.withPhotos(['p2']).captions, ['Two']);
      expect(c.card.withPhotos(['zz']).captions, [null]);
    });
  });

  group('every reason id private.dating_card can send', () {
    DatingIntroCard card(List<String> reasons, Map<String, Object?> over) =>
        DatingIntroCard.fromJson(
          datingCardJson('a', {'reasons': reasons, ...over}),
        )!;

    test('each has its exact reviewed line, given the card it comes with', () {
      // private.dating_reasons ids 1-9, the family values, and §5.8's
      // fallback; private.dating_card re-checks them live. Fix round 1
      // (M-3): each case pins its own copy, never just a count.
      final cases = <(String, Map<String, Object?>, String)>[
        (
          'same_intention_timeline',
          {'intention': 'marriage', 'marriage_timeline': 'within_two_years'},
          loc.dating_reasonMarriageSoon,
        ),
        (
          'same_intention_timeline',
          {'intention': 'marriage', 'marriage_timeline': 'few_years'},
          loc.dating_reasonMarriageFew,
        ),
        (
          'same_intention_timeline',
          {'intention': 'marriage', 'marriage_timeline': 'no_set_time'},
          loc.dating_reasonMarriageNone,
        ),
        (
          'same_intention',
          {'intention': 'marriage'},
          loc.dating_reasonSameMarriage,
        ),
        (
          'same_intention',
          {'intention': 'committed'},
          loc.dating_reasonSameCommitted,
        ),
        (
          'same_intention',
          {'intention': 'companionship'},
          loc.dating_reasonSameCompanionship,
        ),
        (
          'same_intention',
          {'intention': 'not_sure'},
          loc.dating_reasonSameNotSure,
        ),
        ('compatible_intention', {}, loc.dating_reasonCompatible),
        ('children_want_yes', {}, loc.dating_reasonChildrenYes),
        ('children_want_no', {}, loc.dating_reasonChildrenNo),
        ('children_have_both', {}, loc.dating_reasonChildrenHave),
        (
          'same_faith',
          {
            'faith': {'faith': 'muslim'},
          },
          loc.dating_reasonSameFaith(loc.dating_faith_muslim),
        ),
        (
          'faith_matters',
          {
            'faith': {'faith': 'muslim'},
          },
          loc.dating_reasonFaithMatters,
        ),
        ('family_same_early', {}, loc.dating_reasonFamilyEarly),
        ('family_same_when_serious', {}, loc.dating_reasonFamilyWhenSerious),
        ('family_same_our_decision', {}, loc.dating_reasonFamilyOwn),
        (
          'same_side',
          {'side_name_key': 'dating_side_gh_accra'},
          loc.dating_reasonSamePlace(loc.dating_side_gh_accra),
        ),
        (
          'same_region',
          {},
          loc.dating_reasonSamePlace(loc.dating_region_gh_aa),
        ),
        ('across_borders', {}, loc.dating_reasonAcrossBorders),
      ];
      for (final (id, over, line) in cases) {
        expect(datingReasonLines(loc, card([id], over)), [
          line,
        ], reason: '$id $over');
      }
    });

    test('a faith reason never describes a hidden answer (M-4)', () {
      expect(datingReasonLines(loc, card(['faith_matters'], {})), isEmpty);
      expect(datingReasonLines(loc, card(['same_faith'], {})), isEmpty);
    });

    test('a card left with only its fallback reason still says why', () {
      expect(datingReasonLines(loc, card(['same_region'], {})), [
        loc.dating_reasonSamePlace(loc.dating_region_gh_aa),
      ]);
      expect(datingReasonLines(loc, card(['across_borders'], {})), [
        loc.dating_reasonAcrossBorders,
      ]);
      // A timeline the other person hid: the server sends same_intention.
      expect(
        datingReasonLine(
          loc,
          'same_intention_timeline',
          card([], {'intention': 'marriage'}),
        ),
        isNull,
      );
    });
  });

  group('dating-photo-urls', () {
    test('its non-2xx busy (500) and unauthorized are null', () async {
      for (final status in [500, 401, 405]) {
        final repo = DatingTodayRepository(
          DatingRpc.withCall((fn, p) async => null),
          (body) =>
              throw FunctionException(
                status: status,
                details: {'ok': false, 'reason': 'busy'},
              ),
        );
        expect(await repo.photoUrls('match', 'm1'), isNull, reason: '$status');
      }
    });
  });

  group('the photo memory', () {
    Future<Uint8List?> one(String url) async => Uint8List.fromList([1]);

    test('busy forever is asked a bounded number of times', () async {
      await DatingPhotoMemory.clear();
      final fake = FakeDatingToday()..urls = null;
      for (var i = 0; i < 6; i++) {
        expect(
          await loadDatingPhotos(
            fake,
            one,
            'introduction',
            'i1',
            positions: [1, 2],
          ),
          everyElement(isEmpty),
        );
      }
      expect(fake.photoCalls, hasLength(DatingPhotoMemory.maxMisses));
      await loadDatingPhotos(fake, one, 'introduction', 'i2');
      expect(fake.photoCalls.last, ('introduction', 'i2'));
      // Leaving Dating starts again.
      await DatingPhotoMemory.clear();
      fake.photoCalls.clear();
      await loadDatingPhotos(fake, one, 'introduction', 'i1');
      expect(fake.photoCalls, hasLength(1));
    });

    test('a photo that failed to sign leaves its own slot empty', () async {
      await DatingPhotoMemory.clear();
      final fake =
          FakeDatingToday()..urls = const [DatingPhotoUrl(2, 'https://s/2')];
      final out = await loadDatingPhotos(
        fake,
        one,
        'introduction',
        'i1',
        positions: [1, 2],
      );
      expect(out.map((b) => b.length), [0, 1]);
    });

    test('kept by (kind, id, position), never by URL', () async {
      await DatingPhotoMemory.clear();
      final fetched = <String>[];
      Future<Uint8List?> fetch(String url) async {
        fetched.add(url);
        return Uint8List.fromList([fetched.length]);
      }

      final fake = FakeDatingToday();
      await loadDatingPhotos(fake, fetch, 'introduction', 'i1');
      // A new signed URL for the same photo is not fetched again; when
      // every slot is in memory nothing is asked at all.
      fake.urls = const [
        DatingPhotoUrl(1, 'https://s.test/1?t=new'),
        DatingPhotoUrl(2, 'https://s.test/2?t=new'),
      ];
      await loadDatingPhotos(fake, fetch, 'introduction', 'i1');
      fake.photoCalls.clear();
      await loadDatingPhotos(
        fake,
        fetch,
        'introduction',
        'i1',
        positions: [1, 2],
      );
      expect(fake.photoCalls, isEmpty);
      // The same URL on a match is that match's own photo.
      fake.urls = const [DatingPhotoUrl(1, 'https://s.test/1')];
      await loadDatingPhotos(fake, fetch, 'match', 'i1');
      expect(fetched, [
        'https://s.test/1',
        'https://s.test/2',
        'https://s.test/1',
      ]);
      expect(DatingPhotoMemory.key('match', 'i1', 1), 'match:i1:1');
    });

    testWidgets('a cleared photo leaves the image cache too', (t) async {
      await DatingPhotoMemory.clear();
      final bytes = Uint8List.fromList(datingTestPng);
      DatingPhotoMemory.put(DatingPhotoMemory.key('match', 'm', 1), bytes);
      await t.pumpWidget(Image.memory(bytes));
      final cache = PaintingBinding.instance.imageCache;
      expect(cache.statusForKey(MemoryImage(bytes)).untracked, isFalse);
      await DatingPhotoMemory.clear();
      expect(cache.statusForKey(MemoryImage(bytes)).untracked, isTrue);
    });
  });

  group('fix round 1: fresh tries, leaving, wipes in flight, downloads', () {
    Future<Uint8List?> one(String url) async => Uint8List.fromList([1]);
    const two = [
      DatingPhotoUrl(1, 'https://s.test/1'),
      DatingPhotoUrl(2, 'https://s.test/2'),
    ];

    Future<DatingToday> readToday(FakeDatingToday fake) async {
      final c = ProviderContainer(
        overrides: [datingTodayGatewayProvider.overrideWithValue(fake)],
      );
      addTearDown(c.dispose);
      final sub = c.listen(datingTodayProvider('ama'), (_, __) {});
      final t = await c.read(datingTodayProvider('ama').future);
      sub.close();
      return t;
    }

    test('I-1: after the cap, an ok Today read lets the photos load', () async {
      await DatingPhotoMemory.clear();
      final fake = FakeDatingToday()..urls = null;
      for (var i = 0; i < 3; i++) {
        await loadDatingPhotos(
          fake,
          one,
          'introduction',
          'i1',
          positions: [1, 2],
        );
      }
      expect(fake.photoCalls, hasLength(DatingPhotoMemory.maxMisses));
      // A refused read (paused) gives no fresh tries.
      fake.json = {'ok': false, 'reason': 'paused'};
      expect((await readToday(fake)).ok, isFalse);
      await loadDatingPhotos(fake, one, 'introduction', 'i1', positions: [1]);
      expect(fake.photoCalls, hasLength(DatingPhotoMemory.maxMisses));
      // An ok read does: back online, the photos load.
      fake
        ..json = datingTodayJson()
        ..urls = two;
      expect((await readToday(fake)).ok, isTrue);
      final out = await loadDatingPhotos(
        fake,
        one,
        'introduction',
        'i1',
        positions: [1, 2],
      );
      expect(out.map((b) => b.length), [1, 1]);
    });

    test('leaving Dating empties the memory and the miss counts', () async {
      await DatingPhotoMemory.clear();
      final fake = FakeDatingToday()..urls = null;
      for (var i = 0; i < 2; i++) {
        await loadDatingPhotos(fake, one, 'introduction', 'i1');
      }
      expect(DatingPhotoMemory.mayAsk('introduction', 'i1'), isFalse);
      DatingPhotoMemory.put('k', Uint8List.fromList([1]));
      await DatingPhotoMemory.clearForLeave();
      expect(DatingPhotoMemory.length, 0);
      expect(DatingPhotoMemory.mayAsk('introduction', 'i1'), isTrue);
    });

    test(
      'M-1: a download in flight across quick exit writes nothing',
      () async {
        await DatingPhotoMemory.clear();
        final fake = FakeDatingToday();
        final held = Completer<Uint8List?>();
        final load = loadDatingPhotos(
          fake,
          (url) => held.future,
          'introduction',
          'i1',
          positions: [1, 2],
        );
        await Future<void>.delayed(Duration.zero);
        expect(fake.photoCalls, hasLength(1));
        final registry = DeviceWipeRegistry();
        registerDatingDeviceWipes(registry);
        await registry.run(WipeMoment.quickExit);
        held.complete(Uint8List.fromList([9]));
        expect(await load, everyElement(isEmpty));
        expect(DatingPhotoMemory.length, 0);
        expect(DatingPhotoMemory.mayAsk('introduction', 'i1'), isTrue);
      },
    );

    test('M-1: URL answers that land after a wipe count no miss', () async {
      await DatingPhotoMemory.clear();
      final fake = _HeldUrls();
      final loads = [
        for (var i = 0; i < 2; i++)
          loadDatingPhotos(fake, one, 'introduction', 'i1'),
      ];
      await Future<void>.delayed(Duration.zero);
      final registry = DeviceWipeRegistry();
      registerDatingDeviceWipes(registry);
      await registry.run(WipeMoment.signOut);
      fake.urlAnswer.complete(null);
      await Future.wait(loads);
      expect(DatingPhotoMemory.mayAsk('introduction', 'i1'), isTrue);
    });

    test('M-7: a card\'s photos download together', () async {
      await DatingPhotoMemory.clear();
      final fake =
          FakeDatingToday()
            ..urls = const [
              DatingPhotoUrl(1, 'u1'),
              DatingPhotoUrl(2, 'u2'),
              DatingPhotoUrl(3, 'u3'),
            ];
      final started = <String>[];
      final gate = Completer<void>();
      final load = loadDatingPhotos(
        fake,
        (url) async {
          started.add(url);
          await gate.future;
          return Uint8List.fromList([1]);
        },
        'introduction',
        'i1',
        positions: [1, 2, 3],
      );
      await Future<void>.delayed(Duration.zero);
      expect(started, ['u1', 'u2', 'u3']);
      gate.complete();
      expect((await load).map((b) => b.length), [1, 1, 1]);
    });

    test('M-7: a stalled download is abandoned, its client closed', () async {
      final stalled = _Stalled();
      final watch = Stopwatch()..start();
      expect(
        await datingFetchPhoto(
          'https://s.test/1',
          newClient: () => stalled,
          timeout: const Duration(milliseconds: 50),
        ),
        isNull,
      );
      expect(stalled.closed, isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('M-7: a 200 is its bytes, anything else null', () async {
      for (final (status, want) in [(200, 3), (403, null), (404, null)]) {
        final got = await datingFetchPhoto(
          'https://s.test/1',
          newClient:
              () => MockClient(
                (r) async => http.Response.bytes([1, 2, 3], status),
              ),
        );
        expect(got?.length, want, reason: '$status');
      }
    });
  });

  test('DatingCard carries captions from its own JSON', () {
    final c = DatingCard.fromJson({
      'photos': [
        {'id': 'p1', 'position': 1, 'caption': 'Here'},
      ],
    });
    expect(c.captions, ['Here']);
  });
}

/// photoUrls held open until the test answers it.
class _HeldUrls extends FakeDatingToday {
  final urlAnswer = Completer<List<DatingPhotoUrl>?>();

  @override
  Future<List<DatingPhotoUrl>?> photoUrls(String kind, String id) {
    photoCalls.add((kind, id));
    return urlAnswer.future;
  }
}

/// A download that never answers; closing it is the only way out.
class _Stalled extends http.BaseClient {
  bool closed = false;
  final _never = Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _never.future;

  @override
  void close() => closed = true;
}

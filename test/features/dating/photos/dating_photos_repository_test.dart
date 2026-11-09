// Spec 2 W3c Task 10 (carry A): the photo repository against Task 8's photo
// RPCs as their fix rounds left them: names and parameters, a busy server
// (raised `dating:busy`, or the delete's answered busy) read as busy, a
// raised error read by its code only, and a denied storage read as null.
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _busy = PostgrestException(message: 'dating:busy', code: '55P03');

/// Server text that must never become a reason (it names a phone number).
const _leaky = PostgrestException(
  message: 'photo +233 24 555 0101 refused',
  code: 'P0001',
);

class _Run {
  _Run({this.status = 200, this.body = const <int>[1, 2, 3]});

  final int status;
  final List<int> body;
  final calls = <(String, Map<String, dynamic>?)>[];
  final requests = <http.Request>[];
  final answers = <String, List<Object>>{};

  DatingPhotosRepository repo() => DatingPhotosRepository(
    DatingRpc.withCall((fn, params) async {
      calls.add((fn, params));
      final queue = answers[fn];
      final next = queue == null || queue.isEmpty ? null : queue.removeAt(0);
      if (next is Exception) throw next;
      return next;
    }),
    SupabaseStorageClient(
      'http://storage.test/storage/v1',
      const {'apikey': 'k'},
      httpClient: MockClient((request) async {
        requests.add(request);
        if (status != 200) {
          return http.Response(
            '{"statusCode":"$status","error":"x",'
            '"message":"denied +233 24 555 0101"}',
            status,
          );
        }
        if (request.method == 'POST') {
          return http.Response(
            '{"Key":"dating-profile-photos/x","Id":"i"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response.bytes(body, 200);
      }),
    ),
  );

  Iterable<String> get names => calls.map((c) => c.$1);
}

final _bytes = Uint8List.fromList(List.filled(8, 7));

const _intent = {
  'ok': true,
  'intent_id': '11111111-1111-1111-1111-111111111111',
  'storage_key': 'dating-photos/abc.jpg',
  'bucket': 'dating-profile-photos',
  'expires_at': '2026-11-08T10:15:00Z',
};

void main() {
  group('add', () {
    test('intent, upload under its key, insert by its id', () async {
      final r =
          _Run()
            ..answers['create_dating_photo_upload_intent'] = [_intent]
            ..answers['insert_dating_profile_photo'] = [
              {'ok': true, 'photo_id': 'p'},
            ];
      final w = await r.repo().add(3, _bytes, 'image/jpeg');
      expect(w.ok, isTrue);
      expect(r.calls[0].$2, {'p_mime_type': 'image/jpeg'});
      expect(
        r.requests.single.url.path,
        endsWith('/object/dating-profile-photos/dating-photos/abc.jpg'),
      );
      expect(r.calls[1].$1, 'insert_dating_profile_photo');
      expect(r.calls[1].$2, {
        'p_intent_id': '11111111-1111-1111-1111-111111111111',
        'p_position': 3,
      });
    });

    test('a busy intent (raised twice) is busy: nothing uploaded', () async {
      final r =
          _Run()..answers['create_dating_photo_upload_intent'] = [_busy, _busy];
      final w = await r.repo().add(1, _bytes, 'image/jpeg');
      expect(w.reason, 'busy');
      expect(r.requests, isEmpty);
      expect(r.names, isNot(contains('insert_dating_profile_photo')));
    });

    test('a refused intent is its reason: nothing uploaded', () async {
      final r =
          _Run()
            ..answers['create_dating_photo_upload_intent'] = [
              {'ok': false, 'reason': 'too_many'},
            ];
      final w = await r.repo().add(1, _bytes, 'image/jpeg');
      expect(w.reason, 'too_many');
      expect(r.requests, isEmpty);
    });

    test('a failed upload is failed: no insert', () async {
      final r = _Run(status: 403)
        ..answers['create_dating_photo_upload_intent'] = [_intent];
      final w = await r.repo().add(1, _bytes, 'image/jpeg');
      expect(w.reason, 'failed');
      expect(r.names, isNot(contains('insert_dating_profile_photo')));
    });

    test('a busy insert (raised twice) is busy', () async {
      final r =
          _Run()
            ..answers['create_dating_photo_upload_intent'] = [_intent]
            ..answers['insert_dating_profile_photo'] = [_busy, _busy];
      expect((await r.repo().add(1, _bytes, 'image/jpeg')).reason, 'busy');
    });

    test('a raised error is never its text', () async {
      final r = _Run()..answers['create_dating_photo_upload_intent'] = [_leaky];
      final w = await r.repo().add(1, _bytes, 'image/jpeg');
      expect(w.reason, 'failed');
      final r2 =
          _Run()
            ..answers['create_dating_photo_upload_intent'] = [_intent]
            ..answers['insert_dating_profile_photo'] = [_leaky];
      expect((await r2.repo().add(1, _bytes, 'image/jpeg')).reason, 'failed');
    });
  });

  test('delete: the answered busy is busy; ok is ok', () async {
    final r =
        _Run()
          ..answers['delete_dating_profile_photo'] = [
            {'ok': false, 'reason': 'busy'},
            {'ok': true},
          ];
    final repo = r.repo();
    expect((await repo.remove('p1')).reason, 'busy');
    expect((await repo.remove('p1')).ok, isTrue);
    expect(r.calls.first.$2, {'p_photo_id': 'p1'});
  });

  test('caption and reorder: a retried lock raised as busy is busy', () async {
    final r =
        _Run()
          ..answers['set_dating_photo_caption'] = [_busy, _busy]
          ..answers['reorder_dating_photos'] = [
            _busy,
            _busy,
            {'ok': true},
          ];
    final repo = r.repo();
    expect((await repo.caption('p1', 'Beach')).reason, 'busy');
    expect((await repo.reorder('k', ['p2', 'p1'])).reason, 'busy');
    expect((await repo.reorder('k', ['p2', 'p1'])).ok, isTrue);
    expect(r.calls.last.$2, {
      'p_idempotency_key': 'k',
      'p_order': ['p2', 'p1'],
    });
    expect(r.calls.first.$2, {'p_photo_id': 'p1', 'p_caption': 'Beach'});
  });

  test('a lock error that slips through raw is busy, never its text', () async {
    final r =
        _Run()
          ..answers['set_dating_photos_after_mutual'] = [
            const PostgrestException(
              message: 'canceling statement',
              code: '55P03',
            ),
          ];
    expect((await r.repo().photosAfterMutual('k', true)).reason, 'busy');
  });

  test('a storage read the policies deny (a hit, a quarantined object) is '
      'null, calmly', () async {
    final denied = _Run(status: 400);
    expect(await denied.repo().bytes('dating-photos/abc.jpg'), isNull);
    final ok = _Run(body: [9, 9]);
    expect(await ok.repo().bytes('dating-photos/abc.jpg'), [9, 9]);
  });

  test('the list: its keys; a refusal throws a code, never shown', () async {
    final r =
        _Run()
          ..answers['list_dating_profile_photos'] = [
            {
              'ok': true,
              'photos': [
                {
                  'id': 'p1',
                  'position': 1,
                  'state': 'approved',
                  'reason': null,
                  'caption': 'Beach',
                  'storage_key': 'dating-photos/a.jpg',
                  'created_at': '2026-11-07T10:00:00Z',
                },
              ],
              'after_mutual': true,
              'after_mutual_from': '2026-12-01T10:00:00Z',
            },
            {'ok': false, 'reason': 'reverify_device'},
          ];
    final repo = r.repo();
    final list = await repo.list();
    expect(list.photos.single.caption, 'Beach');
    expect(list.afterMutual, isTrue);
    expect(list.afterMutualFrom, DateTime.utc(2026, 12, 1, 10));
    expect(list.toString(), isNot(contains('Beach')));
    expect(list.photos.single.toString(), isNot(contains('Beach')));
    await expectLater(repo.list(), throwsStateError);
  });
}

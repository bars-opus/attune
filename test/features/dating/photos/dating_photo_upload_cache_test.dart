// Spec 2 W5b Task 6 (carry from Task 5): a Dating photo is uploaded with
// Cache-Control max-age=0, never Storage's default hour, so no CDN or
// browser copy outlives its 60-second signed URL. storage_client sends the
// value as the multipart field `cacheControl` (the server prefixes
// max-age=), so 0 is the least it can say.
import 'dart:convert';
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';
import 'package:attune/features/dating/verify/dating_verification_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a Dating photo upload says cacheControl 0', () async {
    final bodies = <String>[];
    final repo = DatingPhotosRepository(
      DatingRpc.withCall(
        (fn, p) async =>
            fn == 'create_dating_photo_upload_intent'
                ? {
                  'ok': true,
                  'intent_id': '11111111-1111-1111-1111-111111111111',
                  'storage_key': 'dating-photos/abc.jpg',
                }
                : {'ok': true, 'photo_id': 'p'},
      ),
      SupabaseStorageClient(
        'http://storage.test/storage/v1',
        const {'apikey': 'k'},
        httpClient: MockClient((request) async {
          bodies.add(latin1.decode(request.bodyBytes));
          return http.Response(
            '{"Key":"dating-profile-photos/x","Id":"i"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    final w = await repo.add(1, Uint8List.fromList([1, 2, 3]), 'image/jpeg');
    expect(w.ok, isTrue);
    expect(datingPhotoCacheControl, '0');
    expect(bodies.single, matches(RegExp(r'name="cacheControl"\r\n\r\n0\r\n')));
  });

  // Fix round 1 (M-5): the human route's two review photos, too.
  test('a verification review photo upload says cacheControl 0', () async {
    final bodies = <String>[];
    final repo = DatingVerificationRepository.of(
      DatingRpc.withCall((fn, p) async => null),
      SupabaseClient(
        'http://project.test',
        'k',
        httpClient: MockClient((request) async {
          bodies.add(latin1.decode(request.bodyBytes));
          return http.Response(
            '{"Key":"dating-verification-review/x","Id":"i"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    expect(
      await repo.uploadReviewPhoto(
        'u/attempt/1.jpg',
        Uint8List.fromList([1, 2, 3]),
      ),
      isTrue,
    );
    expect(datingReviewCacheControl, '0');
    expect(bodies.single, matches(RegExp(r'name="cacheControl"\r\n\r\n0\r\n')));
  });
}

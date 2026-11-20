// Spec 2 W4a (§3.3, §4.7): the verification calls. The status read and the
// biometric consent go through the Dating RPC client; the check steps go
// to the dating-verification edge function; the human route's two photos
// go to the private review bucket under the paths the server named. Every
// call is bounded; a failure answers `failed` (never the error's text).
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The policy version the D11 consent records (§3.3.2).
const datingBiometricPolicyVersion = 'dating-verify-1';

/// The human route's private bucket (§3.3.3).
const datingReviewBucket = 'dating-verification-review';

/// Spec 2 W5b Task 6 fix round 1 (M-5): a review photo's Cache-Control
/// max-age, in seconds. The two photos are deleted at the decision or after
/// 72 hours; no copy may stay fresh in a reviewer's browser or a CDN past
/// that (Storage's default is an hour; its upload sends max-age=N, so
/// 0 is the least).
const datingReviewCacheControl = '0';

typedef DatingVerifyInvoke =
    Future<Object?> Function(Map<String, Object?> body);
typedef DatingReviewUpload = Future<void> Function(String path, Uint8List jpeg);

abstract class DatingVerificationGateway {
  /// The person's own state; [DatingVerification.unavailable] on a failure.
  Future<DatingVerification> status();

  /// Records the D11 consent (biometric_verification, granted).
  Future<DatingWrite> consent(String key);

  /// One dating-verification action ('start', 'complete', 'start_id',
  /// 'complete_id', 'human_start', 'submit_human').
  Future<DatingVerifyAnswer> act(String action, [Map<String, Object?> body]);

  /// One human-review photo; false when it did not land.
  Future<bool> uploadReviewPhoto(String path, Uint8List jpeg);
}

class DatingVerificationRepository implements DatingVerificationGateway {
  DatingVerificationRepository(this._rpc, this._invoke, this._upload);

  /// Through the Dating-scoped client (its edge calls and uploads carry
  /// the same headers as its RPCs).
  factory DatingVerificationRepository.of(DatingRpc rpc, SupabaseClient c) =>
      DatingVerificationRepository(
        rpc,
        (body) async =>
            (await c.functions.invoke('dating-verification', body: body)).data,
        (path, jpeg) async {
          await c.storage
              .from(datingReviewBucket)
              .uploadBinary(
                path,
                jpeg,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: false,
                  cacheControl: datingReviewCacheControl,
                ),
              );
        },
      );

  final DatingRpc _rpc;
  final DatingVerifyInvoke _invoke;
  final DatingReviewUpload _upload;

  /// The status read, the consent and a review photo.
  static const timeout = Duration(seconds: 45);

  /// Fix round 1 (I-2): an edge action may work until the edge function's
  /// 150 s wall clock (handler.ts: vendor tries start until 100 s, busy
  /// waits end by 130 s), so the app waits past it.
  static const actTimeout = Duration(seconds: 155);

  @override
  Future<DatingVerification> status() async {
    try {
      return DatingVerification.fromJson(
        await _rpc.call('get_my_dating_verification'),
      );
    } catch (_) {
      return DatingVerification.unavailable;
    }
  }

  @override
  Future<DatingWrite> consent(String key) async {
    try {
      await _rpc.call('record_dating_consent', {
        'p_idempotency_key': key,
        'p_purpose': 'biometric_verification',
        'p_action': 'granted',
        'p_policy_version': datingBiometricPolicyVersion,
        'p_categories': const ['face'],
      });
      return const DatingWrite(ok: true);
    } on DatingBusy {
      return DatingWrite.busy;
    } on PostgrestException catch (e) {
      return e.message == 'reverify_device'
          ? const DatingWrite(ok: false, reason: 'reverify_device')
          : DatingWrite.failed;
    } catch (_) {
      return DatingWrite.failed;
    }
  }

  @override
  Future<DatingVerifyAnswer> act(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    try {
      return DatingVerifyAnswer.fromJson(
        await _invoke({...body, 'action': action}).timeout(actTimeout),
      );
    } on TimeoutException {
      // Fix round 1 (I-2): no answer in time: its outcome is unknown.
      return const DatingVerifyAnswer(
        ok: false,
        refusal: DatingVerifyRefusal.busy,
      );
    } on FunctionException catch (e) {
      // Fix round 1 (I-1): an edge error carries its own fixed code (a 500
      // answers busy); never an ok, never anything but a code.
      final answer = DatingVerifyAnswer.fromJson(e.details);
      return answer.ok ? DatingVerifyAnswer.failed : answer;
    } catch (_) {
      return DatingVerifyAnswer.failed;
    }
  }

  @override
  Future<bool> uploadReviewPhoto(String path, Uint8List jpeg) async {
    try {
      await _upload(path, jpeg).timeout(timeout);
      return true;
    } catch (e) {
      return isAlreadyStored(e);
    }
  }

  /// Fix round 1 (I-4): storage's answer to a path already holding an
  /// object. The paths are fixed per session and only the caller's own
  /// open human-route session may write them (dating_review_upload_open),
  /// so it is this person's earlier upload whose answer was lost: landed.
  static bool isAlreadyStored(Object e) =>
      e is StorageException &&
      (e.statusCode == '409' || e.error == 'Duplicate');
}

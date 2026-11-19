// Spec 2 W4a: in-memory verification gateway and capture for tests.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_repository.dart';
import 'package:flutter/widgets.dart';

class FakeDatingVerificationGateway implements DatingVerificationGateway {
  FakeDatingVerificationGateway({
    this.state = const DatingVerification(
      available: true,
      photosReady: true,
      idDocuments: [
        DatingIdDocument(code: 'ghana_card', nameKey: 'dating_id_ghana_card'),
        DatingIdDocument(code: 'passport', nameKey: 'dating_id_passport'),
      ],
    ),
  });

  DatingVerification state;
  Completer<DatingVerification>? hold;
  int reads = 0;
  DatingWrite consentAnswer = const DatingWrite(ok: true);
  final consents = <String>[];

  /// What each action answers next (the last one repeats).
  final answers = <String, List<DatingVerifyAnswer>>{};
  final actions = <(String, Map<String, Object?>)>[];
  final uploads = <String>[];
  bool uploadOk = true;

  /// Runs after each action is recorded (a test changes [state] here).
  void Function(String action)? onAct;

  /// Task 4: while set, every action waits for it (an answer in flight).
  Completer<void>? actHold;

  @override
  Future<DatingVerification> status() async {
    reads++;
    final held = hold;
    if (held != null) return held.future;
    return state;
  }

  @override
  Future<DatingWrite> consent(String key) async {
    consents.add(key);
    return consentAnswer;
  }

  @override
  Future<DatingVerifyAnswer> act(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    actions.add((action, body));
    final held = actHold;
    if (held != null) await held.future;
    onAct?.call(action);
    final list = answers[action];
    if (list == null || list.isEmpty) return DatingVerifyAnswer.failed;
    return list.length == 1 ? list.first : list.removeAt(0);
  }

  @override
  Future<bool> uploadReviewPhoto(String path, Uint8List jpeg) async {
    uploads.add(path);
    return uploadOk;
  }

  List<String> get actionNames => [for (final (a, _) in actions) a];
}

class FakeCaptureLauncher implements DatingCaptureLauncher {
  FakeCaptureLauncher({
    this.result = const DatingCaptureResult(DatingCaptureKind.done),
  });

  DatingCaptureResult result;
  final calls = <String>[];

  @override
  Future<DatingCaptureResult> liveness(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  }) async {
    calls.add('liveness:$vendor:$vendorRef');
    return result;
  }

  @override
  Future<DatingCaptureResult> idDocument(
    BuildContext context, {
    required String vendor,
    required String vendorRef,
  }) async {
    calls.add('id:$vendor:$vendorRef');
    return result;
  }
}

const datingTestSession = '11111111-2222-4333-8444-555555555555';

DatingVerifyAnswer datingStarted({String vendor = 'fake'}) =>
    DatingVerifyAnswer(
      ok: true,
      sessionId: datingTestSession,
      vendor: vendor,
      vendorRef: 'ref-1',
    );

DatingVerifyAnswer datingOutcome(DatingVerifyOutcome o, {int? position}) =>
    DatingVerifyAnswer(ok: true, outcome: o, position: position);

DatingVerifyAnswer datingRefused(DatingVerifyRefusal r) =>
    DatingVerifyAnswer(ok: false, refusal: r);

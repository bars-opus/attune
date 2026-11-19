// Spec 2 W4a (§3.3.2, §3.3.3, §3.15 D11): D11's whole flow on one route.
// The intro with the consent, the tips and the light warning; the video
// check through the capture seam; every outcome of §3.3.2; the ID route;
// the human route (two camera photos, never the gallery); the waiting
// screens. The flow opens where the person's own state says (a resumed
// session, a review in progress, an outcome to act on). Rules for every
// Dating screen hold: the step frame (offline banner, large text through
// FlowFrame), copy from the ARB only (never a server's or a vendor's
// text), one idempotency key per action settled once its answer is final,
// and nothing of one account shown to the next (D8). Motion: only the one
// "You're verified." check, a 400 ms fade, none under reduce motion.
//
// Task 4 (carries A–E): every answer is a calm line in the theme's own
// colours; only the one final ending (a failed ID check, R-13) is an
// error line, and it shows support copy. An answer whose outcome may not
// have reached the app (busy, failed, a timeout, a closed session) reads
// the person's status again before anything is shown, so a slow success
// shows its real outcome. A far-below-18 result leads to Spec 1's hold
// screen (the gate's one H1 path, R-8); a date of birth that differs
// leads to Spec 1's correction (W6b, R-12), then Check again.
import 'dart:io';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/photos/dating_photos_providers.dart'
    show datingImagePreparerProvider;
import 'package:attune/features/dating/routes/dating_routes.dart'
    show DatingPaths;
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart'
    show OnboardingGateV2;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// What the flow shows.
enum DatingVerifyStage {
  loading,
  intro,
  another,
  outcome,
  idChoose,
  human,

  /// Fix round 1 (I-4): the ID passed (it proves age only, §3.3.1); the
  /// identity check is still the video face match or a person.
  ageConfirmed,
  verified,
}

/// The one "You're verified." check (§3.0, §3.15 D11).
const kDatingVerifiedFade = Duration(milliseconds: 400);

/// Task 4 (carry A): every refusal in words, each its own line (no
/// fallback arm: a new code is a compile error, never the generic line).
/// All of them are calm: the final ending is an outcome, not a refusal.
String datingVerifyRefusalText(AppLocalizations loc, DatingVerifyRefusal r) =>
    switch (r) {
      DatingVerifyRefusal.unavailable => loc.dating_verifyUnavailable,
      // Spec 2 W4b Task 7 (T6 I-4 ruling): no install id, so no check runs.
      DatingVerifyRefusal.deviceUnavailable => loc.dating_deviceUnavailable,
      DatingVerifyRefusal.invalid ||
      DatingVerifyRefusal.vendorUnavailable ||
      DatingVerifyRefusal.sessionUnavailable ||
      DatingVerifyRefusal.alreadyVerified => loc.dating_verifyNetwork,
      // Fix round 1 (I-2): shown on the intro, next to the box.
      DatingVerifyRefusal.consentRequired => loc.dating_verifyConsentAgain,
      DatingVerifyRefusal.notEligible => loc.dating_sectionUnavailable,
      DatingVerifyRefusal.photosRequired ||
      DatingVerifyRefusal.photosMissing => loc.dating_verifyPhotosFirst,
      DatingVerifyRefusal.ageNotConfirmed => loc.dating_verifyAgeNotConfirmed,
      DatingVerifyRefusal.awaitingReview => loc.dating_verifyWaiting,
      // The vendor-session limit and the 5-a-day limit share the code.
      DatingVerifyRefusal.rateLimited => loc.dating_verifyRateLimited,
      DatingVerifyRefusal.busy => loc.dating_busy,
      DatingVerifyRefusal.reverifyDevice => loc.dating_sectionReverify,
      // Final fix (server M-4): another phone's check is open.
      DatingVerifyRefusal.sessionElsewhere => loc.dating_verifySessionElsewhere,
      // A code this build doesn't know, or no answer at all.
      DatingVerifyRefusal.failed => loc.dating_errorGeneric,
    };

/// The consent's answer as a verification refusal (a calm line too).
DatingVerifyRefusal datingConsentRefusal(DatingWrite w) => switch (w.reason) {
  'busy' => DatingVerifyRefusal.busy,
  'reverify_device' => DatingVerifyRefusal.reverifyDevice,
  'rate_limited' => DatingVerifyRefusal.rateLimited,
  'not_eligible' => DatingVerifyRefusal.notEligible,
  _ => DatingVerifyRefusal.failed,
};

class DatingVerifyFlow extends ConsumerStatefulWidget {
  const DatingVerifyFlow({
    super.key,
    required this.step,
    required this.onBack,
    required this.onDone,
    required this.onChangePhotos,
    this.onHeld,
    this.onFixBirthDate,
    this.reverify = false,
    @visibleForTesting this.newKeys,
  });

  /// 'verify' in setup ("Step 10 of 12"); anything else shows no step.
  final String step;
  final VoidCallback onBack;

  /// Both checks passed: D12 in setup, or back to where it was opened.
  final VoidCallback onDone;

  /// "Change that photo" (§3.3.2): D9.
  final VoidCallback onChangePhotos;

  /// Spec 2 W4b (§3.3.4): the re-check on an untrusted phone: the
  /// standing consent, liveness and CompareFaces only, the human route as
  /// the other way (no ID route).
  final bool reverify;

  /// R-8: after a far-below-18 result, leaving D11 goes to Spec 1's hold
  /// screen. Default: the gate's one H1 path (`go`, so nothing of Dating
  /// stays under it and no other gate screen is stacked with it).
  final VoidCallback? onHeld;

  /// R-12: Spec 1's date-of-birth correction (W6b). Default: pushes
  /// Settings → Date of birth; coming back, Check again compares again.
  final VoidCallback? onFixBirthDate;

  /// The idempotency keys (tests record what is settled).
  final DatingActionKeys Function()? newKeys;

  @override
  ConsumerState<DatingVerifyFlow> createState() => _DatingVerifyFlowState();
}

class _DatingVerifyFlowState extends ConsumerState<DatingVerifyFlow> {
  late DatingActionKeys _keys = _freshKeys();
  DatingVerifyStage _stage = DatingVerifyStage.loading;
  DatingVerification _state = DatingVerification.unavailable;
  DatingVerifyOutcome _outcome = DatingVerifyOutcome.unknown;
  DatingVerifyRefusal? _refusal;
  int? _position;
  bool _consent = false;
  bool _consentRecorded = false;
  bool _resumed = false;
  bool _busy = false;
  bool _readFailed = false;
  String? _document;
  String? _humanSession;

  /// The video check this screen started (a pending result is read again).
  String? _videoSession;

  /// The ID check this screen started (Check again reads it).
  String? _idSession;
  List<String> _gestures = const [];
  List<String> _paths = const [];
  final Set<int> _taken = {};
  int? _taking;
  bool _photoFailed = false;

  /// Final fix (M-4): the camera was refused: false while the phone can
  /// still ask, true once only Settings can allow it; null otherwise.
  bool? _cameraBlocked;

  /// Final fix (M-7): a person's review the person started and left
  /// before sending (the same session resumes on "Ask a person").
  bool _resumedHuman = false;
  int _generation = 0;

  /// Fix round 1 (M-3): the flow's own stages Back retraces before it
  /// leaves D11.
  final _trail = <DatingVerifyStage>[];

  /// The gesture codes this build can name (M-4: anything else fails
  /// closed, never shown as another gesture).
  static const _gestureCodes = {'three_fingers', 'left_ear', 'thumbs_up'};

  DatingActionKeys _freshKeys() => widget.newKeys?.call() ?? DatingActionKeys();

  /// Spec 2 W4b: the video check's two actions (the re-check's own).
  String get _start => widget.reverify ? 'reverify_start' : 'start';
  String get _complete => widget.reverify ? 'reverify_complete' : 'complete';

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      // D8: another account starts from nothing.
      setState(_reset);
      _read();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  void _reset() {
    _generation++;
    _keys = _freshKeys();
    _stage = DatingVerifyStage.loading;
    _state = DatingVerification.unavailable;
    _outcome = DatingVerifyOutcome.unknown;
    _refusal = null;
    _position = null;
    _consent = false;
    _consentRecorded = false;
    _resumed = false;
    _busy = false;
    _readFailed = false;
    _document = null;
    _humanSession = null;
    _videoSession = null;
    _idSession = null;
    _gestures = const [];
    _paths = const [];
    _taken.clear();
    _taking = null;
    _photoFailed = false;
    _cameraBlocked = null;
    _resumedHuman = false;
    _trail.clear();
  }

  /// Moves on to [next] inside the flow; Back returns here.
  void _forward(DatingVerifyStage next) {
    _refusal = null;
    _trail.add(_stage);
    _stage = next;
  }

  VoidCallback get _back =>
      _trail.isEmpty
          ? widget.onBack
          : () => setState(() {
            _refusal = null;
            _stage = _trail.removeLast();
          });

  bool _current(int gen, String? account) =>
      mounted &&
      gen == _generation &&
      ref.read(datingAccountProvider) == account;

  /// The person's own state decides where the flow opens.
  Future<void> _read() async {
    final gen = _generation;
    final account = ref.read(datingAccountProvider);
    ref.invalidate(datingVerificationProvider(account));
    DatingVerification v;
    try {
      v = await ref.read(datingVerificationProvider(account).future);
    } catch (_) {
      v = DatingVerification.unavailable;
    }
    if (!_current(gen, account)) return;
    setState(() {
      _state = v;
      // Fix round 1 (M-5): an older session never hides why.
      _readFailed = !v.available && !v.verified;
      _trail.clear();
      _stage = _stageFor(v);
    });
  }

  DatingVerifyStage _stageFor(DatingVerification v) {
    final s = v.session;
    if (v.verified) return DatingVerifyStage.verified;
    if (v.age == DatingCheck.fail) {
      // R-8: an age that failed on a far-below-18 result is Spec 1's hold.
      _outcome =
          s?.outcome == DatingVerifyOutcome.farBelow
              ? DatingVerifyOutcome.farBelow
              : DatingVerifyOutcome.ageNotConfirmed;
      return DatingVerifyStage.outcome;
    }
    if (s != null && s.waiting) {
      _outcome =
          s.step == 'id'
              ? (s.outcome == DatingVerifyOutcome.dobMismatch
                  ? DatingVerifyOutcome.dobMismatch
                  : DatingVerifyOutcome.idPending)
              : DatingVerifyOutcome.humanPending;
      if (s.step == 'id') _idSession = s.id;
      return DatingVerifyStage.outcome;
    }
    if (s != null && !s.open) {
      switch (s.outcome) {
        case DatingVerifyOutcome.photoMismatch:
          _outcome = s.outcome;
          _position = s.position;
          return DatingVerifyStage.outcome;
        case DatingVerifyOutcome.needsId:
        case DatingVerifyOutcome.ageUncertain:
          if (v.age != DatingCheck.pass) {
            _outcome = s.outcome;
            return DatingVerifyStage.outcome;
          }
        case DatingVerifyOutcome.askForId:
          if (v.age != DatingCheck.pass) {
            _outcome = DatingVerifyOutcome.askForId;
            return DatingVerifyStage.idChoose;
          }
        // R-35: a person's failed review offers the video again.
        case DatingVerifyOutcome.identityFailed:
          _outcome = DatingVerifyOutcome.identityFailed;
        default:
          break;
      }
    }
    _resumed = s != null && s.open && s.step == 'liveness';
    _resumedHuman =
        s != null && s.open && s.step == 'human' && s.state == 'started';
    // Fix round 1 (I-4): the ID confirmed the age; it is still to check
    // the person is the one in the photos (the video or a person).
    if (v.age == DatingCheck.pass && v.identity != DatingCheck.pass) {
      return DatingVerifyStage.ageConfirmed;
    }
    // Final fix (M-7): a person's review left before it was sent opens
    // where it was asked for (Back: the intro); the re-check's intro
    // asks a person itself.
    if (_resumedHuman && !widget.reverify) {
      _trail.add(DatingVerifyStage.intro);
      return DatingVerifyStage.another;
    }
    return DatingVerifyStage.intro;
  }

  /// Whether a status read answered at all.
  bool _known(DatingVerification v) =>
      v.available || v.verified || v.session != null;

  /// Whether a status read shows that an answer's call moved on after all
  /// (a slow success): both checks passed, the age decided (far below 18
  /// included), a review waiting, or [session] closed with an outcome.
  bool _moved(DatingVerification v, String? session) {
    if (v.verified || v.age == DatingCheck.fail || v.waiting) return true;
    final s = v.session;
    return s != null &&
        session != null &&
        s.id == session &&
        !s.open &&
        s.outcome != DatingVerifyOutcome.unknown;
  }

  /// Records the D11 consent the person just gave by ticking the box.
  /// Fix round 1 (I-2): a stage reached without the intro (a reopened
  /// outcome, the ID route a person asked for, the age confirmed) records
  /// nothing: the server's standing consent decides, and a
  /// `consent_required` answer leads back to the box.
  Future<bool> _ensureConsent(String? account) async {
    if (_consentRecorded || !_consent) return true;
    final key = _keys.keyFor('consent', account);
    final w = await ref.read(datingVerificationGatewayProvider).consent(key);
    _keys.settle('consent', reason: w.reason);
    if (!mounted) return false;
    if (!w.ok) {
      setState(() => _refusal = datingConsentRefusal(w));
      return false;
    }
    _consentRecorded = true;
    return true;
  }

  /// One dating-verification action; its key settled once the answer is
  /// final (the edge actions carry no key today: the server's session is
  /// their idempotency, Task 3 M-6, so this keeps the rule for any action
  /// that is ever keyed).
  Future<DatingVerifyAnswer> _act(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    final a = await ref
        .read(datingVerificationGatewayProvider)
        .act(action, body);
    _keys.settle(action, reason: a.settleReason);
    return a;
  }

  /// Runs [body] once (a second tap while busy does nothing), for the
  /// account it started with only.
  Future<void> _run(
    Future<void> Function(int gen, String? account) body,
  ) async {
    if (_busy) return;
    final gen = _generation;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _refusal = null;
      _photoFailed = false;
    });
    try {
      await body(gen, account);
    } finally {
      if (_current(gen, account)) setState(() => _busy = false);
    }
  }

  /// What an answer shows. A refusal whose outcome may not have reached
  /// the app reads the status again first (carry B): if the call moved on
  /// after all, the status decides; otherwise the refusal's calm line.
  Future<void> _answer(
    DatingVerifyAnswer a,
    int gen,
    String? account, {
    String? session,
  }) async {
    if (!_current(gen, account)) return;
    if (!a.ok) {
      final r = a.refusal ?? DatingVerifyRefusal.failed;
      if (a.readStatusAgain ||
          r == DatingVerifyRefusal.alreadyVerified ||
          r == DatingVerifyRefusal.awaitingReview ||
          r == DatingVerifyRefusal.ageNotConfirmed) {
        // Spec 2 W4b (T6 concern 2): a re-check's trust may have landed
        // without its answer, so the home is read again too.
        if (widget.reverify) ref.invalidate(datingHomeProvider(account));
        final v = await _reread(account);
        if (!_current(gen, account)) return;
        if (_moved(v, session)) {
          setState(() {
            _state = v;
            _trail.clear();
            _stage = _stageFor(v);
            _refusal = _stage == DatingVerifyStage.intro ? r : null;
          });
          return;
        }
      }
      if (r == DatingVerifyRefusal.ageNotConfirmed) {
        // R-13: the server says the check has ended (a failed ID check).
        return setState(() {
          _trail.clear();
          _outcome = DatingVerifyOutcome.ageNotConfirmed;
          _stage = DatingVerifyStage.outcome;
        });
      }
      if (r == DatingVerifyRefusal.consentRequired) {
        // Fix round 1 (I-2): the box, unticked, and why; a tick there
        // records the consent on the next start.
        return setState(() {
          _trail.clear();
          _consent = false;
          _consentRecorded = false;
          _outcome = DatingVerifyOutcome.unknown;
          _stage = DatingVerifyStage.intro;
          _refusal = r;
        });
      }
      return setState(() => _refusal = r);
    }
    if (a.outcome == DatingVerifyOutcome.verified ||
        a.outcome == DatingVerifyOutcome.unknown) {
      // Verified: the status shows what is left (or both done). An outcome
      // this build doesn't know: the status decides, never "verified".
      final v = await _reread(account);
      if (!_current(gen, account)) return;
      return setState(() {
        _trail.clear();
        if (_known(v)) {
          _state = v;
          _stage = _stageFor(v);
        } else if (a.outcome == DatingVerifyOutcome.verified) {
          // Final fix (M-1): a pass proves only its own step (an ID, the
          // age), so "You're verified." waits for the status to say both
          // passed: still checking, and Check again reads it.
          _outcome = DatingVerifyOutcome.verified;
          _stage = DatingVerifyStage.outcome;
        } else {
          _outcome = DatingVerifyOutcome.unknown;
          _stage = DatingVerifyStage.outcome;
        }
      });
    }
    setState(() {
      _trail.clear();
      _outcome = a.outcome;
      _position = a.position;
      _stage = switch (a.outcome) {
        DatingVerifyOutcome.retry ||
        DatingVerifyOutcome.identityFailed => DatingVerifyStage.intro,
        DatingVerifyOutcome.askForId => DatingVerifyStage.idChoose,
        _ => DatingVerifyStage.outcome,
      };
    });
  }

  /// Final fix (M-1): Check again after a pass whose status couldn't be
  /// read. Still unreadable: the same calm line, and why under it.
  Future<void> _resultCheckAgain() => _run((gen, account) async {
    final v = await _reread(account);
    if (!_current(gen, account)) return;
    if (!_known(v)) {
      return setState(() => _refusal = DatingVerifyRefusal.failed);
    }
    setState(() {
      _state = v;
      _trail.clear();
      _stage = _stageFor(v);
    });
  });

  Future<DatingVerification> _reread(String? account) async {
    try {
      return await ref.rereadDatingVerification(account);
    } catch (_) {
      return DatingVerification.unavailable;
    }
  }

  Future<void> _video() => _run((gen, account) async {
    if (!await _ensureConsent(account) || !_current(gen, account)) return;
    var started = await _act(_start);
    if (!_current(gen, account)) return;
    if (!started.ok || started.sessionId == null || started.vendorRef == null) {
      return _answer(started, gen, account);
    }
    _videoSession = started.sessionId;
    if (!mounted) return;
    final capture = await ref
        .read(datingCaptureLauncherProvider)
        .liveness(
          context,
          vendor: started.vendor ?? '',
          vendorRef: started.vendorRef!,
        );
    if (!_current(gen, account)) return;
    if (capture.kind == DatingCaptureKind.cancelled) return;
    if (capture.kind == DatingCaptureKind.unavailable) {
      return setState(() => _refusal = DatingVerifyRefusal.unavailable);
    }
    if (capture.scenario != null) {
      started = await _act(_start, {'scenario': capture.scenario});
      if (!_current(gen, account)) return;
      if (!started.ok) return _answer(started, gen, account);
      _videoSession = started.sessionId ?? _videoSession;
    }
    final session = started.sessionId;
    final done = await _act(_complete, {'session_id': session});
    await _answer(done, gen, account, session: session);
  });

  /// "Check again" on a video result the vendor hasn't finished.
  Future<void> _videoCheckAgain() => _run((gen, account) async {
    final session = _videoSession;
    if (session == null) return _read();
    final a = await _act(_complete, {'session_id': session});
    await _answer(a, gen, account, session: session);
  });

  Future<void> _idStart() => _run((gen, account) async {
    final document = _document;
    if (document == null) return;
    if (!await _ensureConsent(account) || !_current(gen, account)) return;
    var started = await _act('start_id', {'document': document});
    if (!_current(gen, account)) return;
    if (!started.ok || started.sessionId == null || started.vendorRef == null) {
      return _answer(started, gen, account);
    }
    if (!mounted) return;
    final capture = await ref
        .read(datingCaptureLauncherProvider)
        .idDocument(
          context,
          vendor: started.vendor ?? '',
          vendorRef: started.vendorRef!,
        );
    if (!_current(gen, account)) return;
    if (capture.kind == DatingCaptureKind.cancelled) return;
    if (capture.kind == DatingCaptureKind.unavailable) {
      return setState(() => _refusal = DatingVerifyRefusal.unavailable);
    }
    if (capture.scenario != null) {
      started = await _act('start_id', {
        'document': document,
        'scenario': capture.scenario,
      });
      if (!_current(gen, account)) return;
      if (!started.ok) return _answer(started, gen, account);
    }
    _idSession = started.sessionId;
    final a = await _act('complete_id', {'session_id': started.sessionId});
    await _answer(a, gen, account, session: started.sessionId);
  });

  /// "Check again" on a pending ID check (R-12: after a corrected date of
  /// birth too, on the same session; never a date sent).
  Future<void> _idCheckAgain() => _run((gen, account) async {
    final session = _idSession ?? _state.session?.id;
    if (session == null) return _read();
    final a = await _act('complete_id', {'session_id': session});
    await _answer(a, gen, account, session: session);
  });

  Future<void> _humanStart() => _run((gen, account) async {
    if (!await _ensureConsent(account) || !_current(gen, account)) return;
    final a = await _act('human_start', {
      if (widget.reverify) 'reverify': true,
    });
    if (!_current(gen, account)) return;
    if (!a.ok ||
        a.sessionId == null ||
        a.gestures.length != 2 ||
        !a.gestures.every(_gestureCodes.contains) ||
        a.paths.length != 2) {
      return _answer(a.ok ? DatingVerifyAnswer.failed : a, gen, account);
    }
    setState(() {
      _humanSession = a.sessionId;
      _gestures = a.gestures;
      _paths = a.paths;
      _taken.clear();
      _cameraBlocked = null;
      _forward(DatingVerifyStage.human);
    });
  });

  /// One of the two gesture photos: the camera, prepared, the file
  /// deleted, uploaded under the server's path (§3.3.3, C-5).
  Future<void> _takePhoto(int n) async {
    if (_busy || _taking != null) return;
    final gen = _generation;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _taking = n;
      _photoFailed = false;
      _cameraBlocked = null;
    });
    String? picked;
    String? prepared;
    var ok = false;
    var cancelled = false;
    var denied = false;
    try {
      picked = await ref.read(datingReviewCameraProvider)();
      cancelled = picked == null;
      if (picked != null && _current(gen, account)) {
        final file =
            (await ref.read(datingImagePreparerProvider).prepare(picked)).file;
        prepared = file.path;
        final bytes = await file.readAsBytes();
        await _delete([picked, prepared]);
        picked = prepared = null;
        if (_current(gen, account)) {
          ok = await ref
              .read(datingVerificationGatewayProvider)
              .uploadReviewPhoto(_paths[n - 1], bytes);
        }
      }
    } on PlatformException catch (e) {
      // Final fix (M-4): a refused camera is never "didn't go through".
      denied = e.code == 'camera_access_denied';
    } catch (_) {
      ok = false;
    } finally {
      await _delete([picked, prepared]);
    }
    final blocked =
        denied &&
        mounted &&
        await ref.read(datingCameraAccessProvider).blocked();
    if (!_current(gen, account)) return;
    setState(() {
      _taking = null;
      if (ok) _taken.add(n);
      _photoFailed = !ok && !cancelled && !denied;
      _cameraBlocked = denied ? blocked : null;
    });
  }

  Future<void> _delete(List<String?> paths) async {
    for (final p in paths) {
      if (p == null) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Best effort: a temp file the OS clears.
      }
    }
  }

  Future<void> _humanSubmit() => _run((gen, account) async {
    final session = _humanSession;
    final a = await _act('submit_human', {'session_id': session});
    await _answer(a, gen, account, session: session);
  });

  void _held() {
    final held = widget.onHeld;
    if (held != null) return held();
    GoRouter.of(
      context,
    ).go(RouteNames.onboarding, extra: OnboardingGateV2.heldExtra);
  }

  void _fixBirthDate() {
    final fix = widget.onFixBirthDate;
    if (fix != null) return fix();
    context.push(RouteNames.birthDateSettings);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final screen = switch (_stage) {
      DatingVerifyStage.loading => _frame(
        loc,
        body: const SizedBox(height: 96),
      ),
      DatingVerifyStage.intro => _intro(loc, online),
      DatingVerifyStage.another => _another(loc, online),
      DatingVerifyStage.outcome => _outcomeScreen(loc, online),
      DatingVerifyStage.idChoose => _idChoose(loc, online),
      DatingVerifyStage.human => _human(loc, online),
      DatingVerifyStage.ageConfirmed => _ageConfirmed(loc, online),
      DatingVerifyStage.verified => _verified(loc),
    };
    // Final fix (M-3): a system back or a swipe retraces the flow's own
    // stages, as the app bar's back does, and leaves D11 from the first.
    // The far-below screen keeps its own rule (Spec 1's hold screen).
    if (_stage == DatingVerifyStage.outcome &&
        _outcome == DatingVerifyOutcome.farBelow) {
      return screen;
    }
    return PopScope(
      canPop: _trail.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: screen,
    );
  }

  Widget _frame(
    AppLocalizations loc, {
    String? title,
    required Widget body,
    Widget? primary,
    List<Widget> more = const [],
    VoidCallback? onBack,
  }) => DatingStepFrame(
    step: widget.step,
    title: title ?? loc.dating_verifyTitle,
    onBack: onBack ?? _back,
    body: body,
    primary: primary,
    more: more,
  );

  Widget _text(String text, {TextStyle? style}) =>
      Text(text, style: style ?? Theme.of(context).textTheme.bodyLarge);

  List<Widget> _lines(List<String> lines) => [
    for (final l in lines) ...[_text(l), const SizedBox(height: Spacing.md)],
  ];

  List<Widget> _tips(AppLocalizations loc) => [
    for (final tip in [
      loc.dating_verifyTip1,
      loc.dating_verifyTip2,
      loc.dating_verifyTip3,
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(child: Text('•  ')),
            Expanded(
              child: _text(tip, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
  ];

  /// A calm line in the theme's own colours (carry A: never error red).
  Widget _calm(String text) => Semantics(
    liveRegion: true,
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );

  /// A refusal in words (never the server's), always calm; photos that
  /// aren't ready offer D9.
  Widget? _refusalLine(AppLocalizations loc) {
    final r = _refusal;
    if (r == null) return null;
    // Spec 2 W4b (carry 9): the way to the re-check on this phone (none
    // from the re-check itself; none for a phone with no install id).
    if (r == DatingVerifyRefusal.reverifyDevice) {
      return DatingReverifyLine(offerCheck: !widget.reverify);
    }
    final photos =
        r == DatingVerifyRefusal.photosRequired ||
        r == DatingVerifyRefusal.photosMissing;
    // Spec 2 W4b (T6 review M-6): a phone Dating doesn't trust can't add
    // photos: a phone that is trusted, or Leave.
    if (photos && widget.reverify) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _calm(loc.dating_reverifyPhotosElsewhere),
          FlowTextLink(
            label: loc.dating_settingsLeave,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => context.push(DatingPaths.leave),
          ),
        ],
      );
    }
    final line = _calm(datingVerifyRefusalText(loc, r));
    if (!photos) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line,
        FlowTextLink(
          label: loc.dating_verifyOpenPhotos,
          alignment: AlignmentDirectional.centerStart,
          onPressed: widget.onChangePhotos,
        ),
      ],
    );
  }

  Widget _intro(AppLocalizations loc, bool online) {
    // Spec 2 W4b: a re-check runs on the standing consent; a phone with
    // no install id has no check to start (T6 I-4 ruling).
    final ready =
        (_consent || widget.reverify) &&
        online &&
        !_busy &&
        _state.available &&
        _refusal != DatingVerifyRefusal.deviceUnavailable;
    final retry =
        _outcome == DatingVerifyOutcome.retry ||
        _outcome == DatingVerifyOutcome.identityFailed;
    final refusal = _refusalLine(loc);
    return _frame(
      loc,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_readFailed) ...[
            Semantics(
              liveRegion: true,
              child: _text(loc.dating_verifyUnavailable),
            ),
            FlowTextLink(
              label: loc.dating_verifyTryAgain,
              alignment: AlignmentDirectional.centerStart,
              onPressed: _read,
            ),
          ],
          if (retry)
            Semantics(liveRegion: true, child: _text(loc.dating_verifyRetry))
          else if (_resumed || (_resumedHuman && widget.reverify))
            _text(loc.dating_verifyResume),
          const SizedBox(height: Spacing.md),
          _text(
            widget.reverify ? loc.dating_reverifyBody : loc.dating_verifyBody,
          ),
          const SizedBox(height: Spacing.md),
          ..._tips(loc),
          const SizedBox(height: Spacing.md),
          _text(
            loc.dating_verifyLightWarning,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Spacing.md),
          // Spec 2 W4b: a re-check runs on the standing consent.
          if (!widget.reverify)
            CheckboxListTile(
              key: const ValueKey('dating_verify_consent'),
              value: _consent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(loc.dating_verifyConsent),
              onChanged: (v) => setState(() => _consent = v ?? false),
            ),
          if (refusal != null) refusal,
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_verifyStart,
        busy: _busy,
        onPressed: ready ? _video : null,
      ),
      more: [
        // §3.15 D11: as prominent as Start.
        FlowSecondaryButton(
          label: loc.dating_verifyAnotherWay,
          onPressed:
              !ready
                  ? null
                  : widget.reverify
                  ? _humanStart
                  : () => setState(() => _forward(DatingVerifyStage.another)),
        ),
      ],
    );
  }

  Widget _another(AppLocalizations loc, bool online) {
    final refusal = _refusalLine(loc);
    return _frame(
      loc,
      title: loc.dating_verifyAnotherWay,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Final fix (M-7): the person's review left half done.
          if (_resumedHuman) ...[
            _text(loc.dating_verifyResume),
            const SizedBox(height: Spacing.md),
          ],
          _text(loc.dating_verifyAnotherBody),
          if (refusal != null) refusal,
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_verifyUseId,
        onPressed:
            online && !_busy
                ? () => setState(() => _forward(DatingVerifyStage.idChoose))
                : null,
      ),
      more: [
        FlowSecondaryButton(
          label: loc.dating_verifyAskPerson,
          busy: _busy,
          onPressed: online && !_busy ? _humanStart : null,
        ),
      ],
    );
  }

  Widget _contactSupport(AppLocalizations loc) => FlowPrimaryButton(
    label: loc.flow_holdContact,
    onPressed:
        () => UrlLauncherUtils.launchEmail(
          context: context,
          email: AppConstants.supportEmail,
        ),
  );

  Widget _outcomeScreen(AppLocalizations loc, bool online) {
    final refusal = _refusalLine(loc);
    final position = _position ?? 1;
    void toId() => setState(() => _forward(DatingVerifyStage.idChoose));
    void toIntro() => setState(() {
      _trail.clear();
      _refusal = null;
      _outcome = DatingVerifyOutcome.unknown;
      _stage = DatingVerifyStage.intro;
    });
    // Exhaustive (carry A): every outcome its own copy, no fallback arm.
    final (
      List<String> lines,
      Widget? primary,
      List<Widget> more,
    ) = switch (_outcome) {
      // Spec 2 W4b: a re-check's other way is a person, never an ID.
      DatingVerifyOutcome.anotherWay when widget.reverify => (
        [loc.dating_verifyStillNotWorking],
        FlowPrimaryButton(
          label: loc.dating_verifyAskPerson,
          busy: _busy,
          onPressed: online && !_busy ? _humanStart : null,
        ),
        [
          FlowTextLink(
            label: loc.dating_verifyTryAgain,
            alignment: AlignmentDirectional.centerStart,
            onPressed: toIntro,
          ),
        ],
      ),
      DatingVerifyOutcome.anotherWay => (
        [loc.dating_verifyStillNotWorking],
        FlowPrimaryButton(
          label: loc.dating_verifyUseId,
          onPressed: online && !_busy ? toId : null,
        ),
        [
          FlowSecondaryButton(
            label: loc.dating_verifyAskPerson,
            busy: _busy,
            onPressed: online && !_busy ? _humanStart : null,
          ),
          FlowTextLink(
            label: loc.dating_verifyTryAgain,
            alignment: AlignmentDirectional.centerStart,
            onPressed: toIntro,
          ),
        ],
      ),
      // R-13 (owner ruling 2026-11-09): an estimate below 25, or one the
      // video couldn't give, never ends the check: the ID route.
      DatingVerifyOutcome.needsId || DatingVerifyOutcome.ageUncertain => (
        [
          _outcome == DatingVerifyOutcome.ageUncertain
              ? loc.dating_verifyUncertain
              : loc.dating_verifyUnder25,
        ],
        FlowPrimaryButton(
          label: loc.dating_verifyUseId,
          onPressed: online ? toId : null,
        ),
        const <Widget>[],
      ),
      // R-35: a profile photo that doesn't match stays fixable.
      DatingVerifyOutcome.photoMismatch => (
        [loc.dating_verifyPhotoMismatch(position)],
        FlowPrimaryButton(
          label: loc.dating_verifyChangePhoto,
          onPressed: widget.onChangePhotos,
        ),
        [
          FlowSecondaryButton(
            label: loc.dating_verifyAskPerson,
            busy: _busy,
            onPressed: online && !_busy ? _humanStart : null,
          ),
          // Fix round 1 (I-1): once the photo is changed (D9), the video
          // can run again.
          FlowTextLink(
            label: loc.dating_verifyTryAgain,
            alignment: AlignmentDirectional.centerStart,
            onPressed: toIntro,
          ),
        ],
      ),
      DatingVerifyOutcome.idPending => (
        [loc.dating_verifyIdThanks],
        FlowPrimaryButton(
          label: loc.dating_verifyCheckAgain,
          busy: _busy,
          onPressed: online && !_busy ? _idCheckAgain : null,
        ),
        const <Widget>[],
      ),
      // R-12: after a correction (Spec 1's path), the vendor's answer is
      // compared again. The app never shows or sends a date of birth.
      DatingVerifyOutcome.dobMismatch => (
        [loc.dating_verifyDobMismatch],
        FlowPrimaryButton(
          label: loc.dating_verifyCheckAgain,
          busy: _busy,
          onPressed: online && !_busy ? _idCheckAgain : null,
        ),
        [
          FlowTextLink(
            label: loc.dating_verifyFixDob,
            alignment: AlignmentDirectional.centerStart,
            onPressed: _fixBirthDate,
          ),
        ],
      ),
      DatingVerifyOutcome.humanPending => (
        [loc.dating_verifyWaiting],
        null,
        const <Widget>[],
      ),
      // The vendor hasn't finished the video: the same session, no new
      // capture.
      DatingVerifyOutcome.pending => (
        [loc.dating_verifyStillChecking],
        FlowPrimaryButton(
          label: loc.dating_verifyCheckAgain,
          busy: _busy,
          onPressed: online && !_busy ? _videoCheckAgain : null,
        ),
        // Fix round 1 (M-2): a session that expired meanwhile never loops.
        [
          FlowTextLink(
            label: loc.dating_verifyTryAgain,
            alignment: AlignmentDirectional.centerStart,
            onPressed: toIntro,
          ),
        ],
      ),
      // R-8: Spec 1's hold; support copy only, and leaving goes to H1.
      DatingVerifyOutcome.farBelow => (
        [loc.dating_verifyFarBelow],
        _contactSupport(loc),
        const <Widget>[],
      ),
      // R-13: the one ending (shown as an error line below), support copy.
      DatingVerifyOutcome.ageNotConfirmed => (
        const <String>[],
        _contactSupport(loc),
        const <Widget>[],
      ),
      DatingVerifyOutcome.retry || DatingVerifyOutcome.identityFailed => (
        [loc.dating_verifyRetry],
        FlowPrimaryButton(label: loc.dating_verifyTryAgain, onPressed: toIntro),
        const <Widget>[],
      ),
      DatingVerifyOutcome.askForId => (
        [loc.dating_verifyAskedForId],
        FlowPrimaryButton(
          label: loc.dating_verifyUseId,
          onPressed: online ? toId : null,
        ),
        const <Widget>[],
      ),
      // Final fix (M-1): a pass whose status couldn't be read.
      DatingVerifyOutcome.verified => (
        [loc.dating_verifyResultPending],
        FlowPrimaryButton(
          label: loc.dating_verifyCheckAgain,
          busy: _busy,
          onPressed: online && !_busy ? _resultCheckAgain : null,
        ),
        const <Widget>[],
      ),
      DatingVerifyOutcome.unknown => (
        [loc.dating_verifyNetwork],
        FlowPrimaryButton(
          label: loc.dating_verifyTryAgain,
          onPressed: () {
            setState(() => _stage = DatingVerifyStage.loading);
            _read();
          },
        ),
        const <Widget>[],
      ),
    };
    final farBelow = _outcome == DatingVerifyOutcome.farBelow;
    final frame = _frame(
      loc,
      onBack: farBelow ? _held : null,
      // Final fix (M-6): the outcome is one live region and a refusal
      // under it its own, so each is read once.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_outcome == DatingVerifyOutcome.ageNotConfirmed) ...[
                  FlowErrorLine(
                    text: loc.dating_verifyAgeNotConfirmed,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                ],
                ..._lines(lines),
              ],
            ),
          ),
          if (refusal != null) refusal,
        ],
      ),
      primary: primary,
      more: more,
    );
    if (!farBelow) return frame;
    // Fix round 1 (I-3): a system back or a swipe goes to Spec 1's hold
    // screen too, never down the stack to D10.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _held();
      },
      child: frame,
    );
  }

  Widget _idChoose(AppLocalizations loc, bool online) {
    final refusal = _refusalLine(loc);
    final docs = [
      for (final d in _state.idDocuments)
        if (datingListName(loc, d.nameKey) case final name?) (d.code, name),
    ];
    return _frame(
      loc,
      title: loc.dating_verifyWhichId,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_outcome == DatingVerifyOutcome.askForId) ...[
            Semantics(
              liveRegion: true,
              child: _text(loc.dating_verifyAskedForId),
            ),
            const SizedBox(height: Spacing.md),
          ],
          // Fix round 1 (M-6): a country that lists no ID says so calmly.
          if (docs.isEmpty) _calm(loc.dating_verifyUnavailable),
          DatingChoiceGroup<String>(
            label: loc.dating_verifyWhichId,
            showLabel: false,
            options: docs,
            value: _document,
            onChanged: (v) => setState(() => _document = v),
          ),
          if (refusal != null) refusal,
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: _busy,
        onPressed: _document != null && online && !_busy ? _idStart : null,
      ),
    );
  }

  Widget _human(AppLocalizations loc, bool online) {
    final refusal = _refusalLine(loc);
    String gesture(String code) => switch (code) {
      'three_fingers' => loc.dating_gestureThreeFingers,
      'left_ear' => loc.dating_gestureLeftEar,
      'thumbs_up' => loc.dating_gestureThumbsUp,
      _ => loc.dating_gestureThumbsUp,
    };
    return _frame(
      loc,
      title: loc.dating_humanTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _text(loc.dating_humanBody),
          const SizedBox(height: Spacing.md),
          for (var n = 1; n <= 2; n++) ...[
            Semantics(
              container: true,
              label: loc.dating_humanPhotoLabel(
                n,
                _taken.contains(n)
                    ? loc.dating_humanDone
                    : loc.dating_humanToDo,
              ),
              child: ExcludeSemantics(
                child: _text(
                  '$n. ${gesture(_gestures[n - 1])}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            if (_taken.contains(n))
              _text(loc.dating_humanDone)
            else
              FlowSecondaryButton(
                label: loc.dating_humanTake(n),
                busy: _taking == n,
                onPressed:
                    online && _taking == null && !_busy
                        ? () => _takePhoto(n)
                        : null,
              ),
            const SizedBox(height: Spacing.md),
          ],
          if (_photoFailed) _calm(loc.dating_humanPhotoFailed),
          // Final fix (M-4): a refused camera says how to allow it.
          if (_cameraBlocked case final blocked?) ...[
            _calm(
              blocked
                  ? loc.dating_humanCameraBlocked
                  : loc.dating_humanCameraDenied,
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.dating_openSettings,
              onPressed: ref.read(datingCameraAccessProvider).openSettings,
            ),
            if (_trail.isNotEmpty)
              FlowTextLink(
                label: loc.dating_verifyAnotherWay,
                alignment: AlignmentDirectional.centerStart,
                onPressed: _back,
              ),
          ],
          if (refusal != null) refusal,
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_humanSend,
        busy: _busy,
        onPressed: _taken.length == 2 && online && !_busy ? _humanSubmit : null,
      ),
    );
  }

  /// Fix round 1 (I-4): the ID passed; now it's you (the video, or a
  /// person for anyone the flashing light affects).
  Widget _ageConfirmed(AppLocalizations loc, bool online) {
    final refusal = _refusalLine(loc);
    return _frame(
      loc,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: _text(loc.dating_verifyAgeConfirmed),
          ),
          const SizedBox(height: Spacing.md),
          // Final fix (M-7): the person's review left half done.
          if (_resumedHuman) ...[
            _text(loc.dating_verifyResume),
            const SizedBox(height: Spacing.md),
          ],
          ..._tips(loc),
          const SizedBox(height: Spacing.md),
          _text(
            loc.dating_verifyLightWarningPerson,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (refusal != null) refusal,
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_verifyStart,
        busy: _busy,
        onPressed: online && !_busy && _state.available ? _video : null,
      ),
      more: [
        FlowSecondaryButton(
          label: loc.dating_verifyAskPerson,
          busy: _busy,
          onPressed: online && !_busy ? _humanStart : null,
        ),
      ],
    );
  }

  Widget _verified(AppLocalizations loc) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return _frame(
      loc,
      body: TweenAnimationBuilder<double>(
        key: const ValueKey('dating_verified_check'),
        tween: Tween(begin: reduce ? 1 : 0, end: 1),
        duration: reduce ? Duration.zero : kDatingVerifiedFade,
        builder:
            (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: _text(
                  loc.dating_verifyVerified,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        onPressed: widget.onDone,
      ),
    );
  }
}

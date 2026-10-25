import 'dart:async';

import 'package:attune/features/auth/sign_up/domain/phone_entry.dart';
import 'package:attune/features/auth/sign_up/domain/resend_ladder.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/one_time_code_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// A4 · Code (Spec 1 §3.3). The flow owns what happens to a code; this
/// shows the field, the resend ladder and the outcome.
///
/// Two places for a failure (review B4 I-2):
/// - about the code: [errorText] (raise [errorCount] each time; the boxes
///   turn red), and for a wrong code only, also raise [shakeCount];
/// - anything else (a send that failed, too many codes, a check that
///   couldn't run, an account that couldn't be read): [noticeText] (raise
///   [noticeCount] each time), under the resend row, the boxes untouched.
class CodeStep extends StatefulWidget {
  const CodeStep({
    super.key,
    required this.phoneE164,
    required this.lastSentAt,
    required this.sendCount,
    required this.now,
    required this.onCode,
    required this.onResend,
    required this.onChangeNumber,
    this.errorText,
    this.errorCount = 0,
    this.shakeCount = 0,
    this.noticeText,
    this.noticeCount = 0,
    this.accepted = false,
    this.busy = false,
    this.onRetry,
    this.autofillCode,
    this.systemBack,
    this.resendNotBefore,
    this.lastChannel = 'sms',
    this.onTryWhatsApp,
    this.onCallMe,
  });

  final String phoneE164;
  final DateTime? lastSentAt;
  final int sendCount;
  final DateTime Function() now;

  /// A complete code. The step stays busy until it has been checked.
  final FutureOr<void> Function(String code) onCode;
  final FutureOr<void> Function() onResend;

  /// "Wrong number? Change it" and Back. Not while a code is being checked
  /// or sent (review B4 M-1).
  final FutureOr<void> Function() onChangeNumber;

  /// What is wrong with the code, read out each time [errorCount] rises.
  final String? errorText;
  final int errorCount;

  /// Raise for a wrong code only: the boxes shake.
  final int shakeCount;

  /// A failure that isn't about the code, read out each time [noticeCount]
  /// rises.
  final String? noticeText;
  final int noticeCount;
  final bool accepted;
  final bool busy;

  /// Shown as "Try again" when the code was accepted but the account
  /// couldn't be read (offline right after verifying).
  final FutureOr<void> Function()? onRetry;

  /// W2c: a code Android's SMS listener read; it fills the field.
  final String? autofillCode;

  /// The flow's system back while this step shows: it runs Back's own
  /// guarded action, so it too waits for a check or a send in progress.
  final Listenable? systemBack;

  /// A resend was refused for a while ("Too many codes. Try again in
  /// {minutes} minutes."): the link waits until then (review B5 M-3).
  final DateTime? resendNotBefore;

  /// W2c: the channel the newest code was asked on; `voice` shows the
  /// calling line.
  final String lastChannel;

  /// W2c: after the second resend, "Try WhatsApp" and "Call me with the
  /// code" (null hides them; W2 never passes [onCallMe], voice being off on
  /// the server). Each keeps the step busy until it has finished.
  final FutureOr<void> Function()? onTryWhatsApp;
  final FutureOr<void> Function()? onCallMe;

  @override
  State<CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends State<CodeStep> with SubmitOnce {
  final _code = TextEditingController();
  Timer? _tick;

  /// A complete code that arrived while the step was busy (the SMS listener
  /// can read the new code before the resend's reply): checked once the
  /// step is free (review B4 M-4).
  String? _pending;

  /// The code last handed to [CodeStep.onCode]: the same text is not
  /// checked again until the field has changed (review B4 N-1: a code
  /// autofilled during a check that failed came round a second time when
  /// the field took its focus back).
  String? _lastSubmitted;

  bool get _busy => widget.busy || submitting;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    widget.systemBack?.addListener(_changeNumber);
    _code.addListener(_fieldChanged);
    // A code read while A3's send was out (review B8 m-1).
    _fill(widget.autofillCode);
  }

  /// Exactly six ASCII digits: setting the text skips the field's own
  /// digits-only and length formatters (review B8 m-4).
  static final _sixDigits = RegExp(r'^[0-9]{6}$');

  /// [autofill] into the field after this frame: a full code verifies at
  /// once, and the flow's state must not change while it is building.
  /// Anything but a six-digit code fills nothing.
  void _fill(String? autofill) {
    if (autofill == null || !_sixDigits.hasMatch(autofill)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _code.text = autofill;
    });
  }

  /// Typed over, cleared or filled anew: the last code may be checked again.
  void _fieldChanged() {
    if (_code.text != _lastSubmitted) _lastSubmitted = null;
  }

  @override
  void didUpdateWidget(covariant CodeStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.systemBack != oldWidget.systemBack) {
      oldWidget.systemBack?.removeListener(_changeNumber);
      widget.systemBack?.addListener(_changeNumber);
    }
    // A new code was sent: the old digits mean nothing now, unless the new
    // code has already arrived and waits to be checked.
    if (widget.sendCount != oldWidget.sendCount && _pending == null) {
      _code.clear();
    }
    if (widget.autofillCode != oldWidget.autofillCode) {
      _fill(widget.autofillCode);
    }
    if (oldWidget.busy && !widget.busy && _pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkPending());
    }
    final notice = widget.noticeText;
    if (notice != null &&
        (notice != oldWidget.noticeText ||
            widget.noticeCount != oldWidget.noticeCount)) {
      SemanticsService.announce(notice, Directionality.of(context));
    }
  }

  @override
  void dispose() {
    widget.systemBack?.removeListener(_changeNumber);
    _tick?.cancel();
    _code.dispose();
    super.dispose();
  }

  // Each runs once however fast it is pressed, and none starts while
  // another (or the flow) is busy.
  void _check(String code) {
    if (widget.accepted || code == _lastSubmitted) return;
    if (_busy) {
      _pending = code;
      return;
    }
    _pending = null;
    _lastSubmitted = code;
    submitOnce(() => widget.onCode(code), tag: #code);
  }

  void _checkPending() {
    final code = _pending;
    if (code == null || !mounted || _busy || widget.accepted) return;
    _pending = null;
    // Typed over or cleared since: that code is gone.
    if (_code.text == code) _check(code);
  }

  @override
  void didFinishSubmit() => _checkPending();

  void _resend() {
    if (_busy) return;
    submitOnce(widget.onResend, tag: #resend);
  }

  void _changeNumber() {
    if (_busy) return;
    submitOnce(widget.onChangeNumber, tag: #changeNumber);
  }

  void _retry() {
    final retry = widget.onRetry;
    if (_busy || retry == null) return;
    submitOnce(retry, tag: #retry);
  }

  void _tryWhatsApp() {
    final tryWhatsApp = widget.onTryWhatsApp;
    if (_busy || tryWhatsApp == null) return;
    submitOnce(tryWhatsApp, tag: #whatsApp);
  }

  void _callMe() {
    final callMe = widget.onCallMe;
    if (_busy || callMe == null) return;
    submitOnce(callMe, tag: #callMe);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final now = widget.now();
    final ladder = ResendLadder.remaining(
      lastSentAt: widget.lastSentAt,
      sendCount: widget.sendCount,
      now: now,
    );
    final refused = widget.resendNotBefore?.difference(now) ?? Duration.zero;
    final left = refused > ladder ? refused : ladder;
    final notice = widget.noticeText;
    return FlowFrame(
      title: loc.flow_codeTitle,
      hint: loc.flow_codeSubtitle(formatPhoneForDisplay(widget.phoneE164)),
      onBack: _changeNumber,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowTextLink(
            label: loc.flow_codeChangeNumber,
            alignment: AlignmentDirectional.centerStart,
            onPressed: _changeNumber,
          ),
          const SizedBox(height: 8),
          OneTimeCodeField(
            controller: _code,
            semanticsLabel: loc.flow_codeSemantics,
            enabled: !_busy && !widget.accepted,
            errorText: widget.errorText,
            errorCount: widget.errorCount,
            shakeCount: widget.shakeCount,
            accepted: widget.accepted,
            onCompleted: _check,
          ),
          if (ResendLadder.saysUseNewest(widget.sendCount)) ...[
            const SizedBox(height: 8),
            Text(loc.flow_codeNewest, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          if (left > Duration.zero)
            Text(
              loc.flow_codeResendIn(ResendLadder.clock(left)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            FlowTextLink(
              label: loc.flow_codeResend,
              alignment: AlignmentDirectional.centerStart,
              onPressed: _resend,
            ),
            if (ResendLadder.offersOtherChannels(widget.sendCount)) ...[
              if (widget.onTryWhatsApp != null)
                FlowTextLink(
                  label: loc.flow_codeTryWhatsApp,
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: _tryWhatsApp,
                ),
              if (widget.onCallMe != null)
                FlowTextLink(
                  label: loc.flow_codeCallMe,
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: _callMe,
                ),
            ],
          ],
          if (widget.lastChannel == 'voice') ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                loc.flow_codeCalling(formatPhoneForDisplay(widget.phoneE164)),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          if (notice != null) ...[
            const SizedBox(height: 12),
            FlowErrorLine(
              text: notice,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (widget.onRetry != null)
          FlowPrimaryButton(
            label: loc.flow_tryAgain,
            busy: runningTag == #retry,
            onPressed: _busy ? null : _retry,
          ),
      ],
    );
  }
}

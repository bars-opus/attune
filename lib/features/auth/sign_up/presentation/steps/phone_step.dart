import 'dart:async';

import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/auth/sign_up/domain/phone_entry.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A3 · Phone (Spec 1 §3.3). The country defaults to the SIM's, else the
/// device region's, else none and the picker opens. W2c also offers
/// "Send by WhatsApp instead", after asking whether WhatsApp is on it.
class PhoneStep extends StatefulWidget {
  const PhoneStep({
    super.key,
    required this.initialCountry,
    required this.onSend,
    required this.onBack,
    this.initialNational = '',
    this.busy = false,
    this.sendError,
    this.onSendWhatsApp,
  });

  final PhoneCountry? initialCountry;
  final String initialNational;

  /// A valid number, E.164, and its country. The step stays busy until it
  /// has finished.
  final FutureOr<void> Function(String e164, String countryIso) onSend;
  final VoidCallback onBack;
  final bool busy;

  /// A failed send, in the words to show.
  final String? sendError;

  /// W2c: "Send by WhatsApp instead", after the person confirms WhatsApp is
  /// on this number; the step stays busy until it has finished. Null hides
  /// it.
  final FutureOr<void> Function(String e164, String countryIso)? onSendWhatsApp;

  @override
  State<PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<PhoneStep> with SubmitOnce {
  late final _number = TextEditingController(text: widget.initialNational);
  late PhoneCountry? _country = widget.initialCountry;
  PhoneEntryError? _error;

  /// One per failed submit, so the same message is read out again.
  int _errorCount = 0;
  Timer? _slow;
  bool _showSending = false;

  /// No country is selected: matches no row in the picker.
  static const _none = PhoneCountry(
    isoCode: '',
    name: '',
    dialCode: '',
    flag: '',
    example: '',
  );

  bool get _busy => widget.busy || submitting;

  @override
  void initState() {
    super.initState();
    if (_country == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickCountry();
      });
    }
  }

  @override
  void didUpdateWidget(covariant PhoneStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      // Any wait over 400 ms says what is happening (§2.2).
      _slow = Timer(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _showSending = true);
      });
    } else if (!widget.busy && oldWidget.busy) {
      _slow?.cancel();
      _showSending = false;
    }
    final error = widget.sendError;
    if (error != null && error != oldWidget.sendError) {
      SemanticsService.announce(error, Directionality.of(context));
    }
  }

  @override
  void dispose() {
    _slow?.cancel();
    _number.dispose();
    super.dispose();
  }

  Future<void> _pickCountry() => BottomSheetUtils.showDocumentationBottomSheet(
    context: context,
    padding: 0,
    widget: PhoneCountryPickerSheet(
      selectedCountry: _country ?? _none,
      onCountrySelected: (country) {
        if (mounted) setState(() => _country = country);
      },
    ),
  );

  /// The valid number and its country, or null (and the error shown).
  (String, String)? _validNumber() {
    final country = _country;
    if (country == null) {
      _pickCountry();
      return null;
    }
    final result = parsePhoneEntry(_number.text, country.isoCode);
    setState(() {
      _error = result.error;
      if (result.error != null) _errorCount++;
    });
    final e164 = result.e164;
    return e164 == null ? null : (e164, country.isoCode);
  }

  void _send() {
    // Done on the keyboard and the button together send one code.
    if (_busy) return;
    final number = _validNumber();
    if (number != null) submitOnce(() => widget.onSend(number.$1, number.$2));
  }

  /// "Is WhatsApp on {number}?": yes sends by WhatsApp, no by SMS. One
  /// send however fast either is pressed, as [_send].
  Future<void> _sendWhatsApp() async {
    final onWhatsApp = widget.onSendWhatsApp;
    if (_busy || onWhatsApp == null) return;
    final number = _validNumber();
    if (number == null) return;
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Room for large text (§2.3): 60% of the screen at 1.0, up to 90% at
    // 2.0. The question scrolls; the two answers stay in view.
    final textScale = MediaQueryData.fromView(
      View.of(context),
    ).textScaler.scale(1).clamp(1.0, 2.0);
    final yes = await BottomSheetUtils.showDocumentationBottomSheet<bool>(
      context: context,
      maxHeight: MediaQuery.sizeOf(context).height * (0.3 + 0.3 * textScale),
      widget: AllowLargeText(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        loc.flow_whatsAppTitle(
                          formatPhoneForDisplay(number.$1),
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loc.flow_whatsAppBody,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Builder(
              builder:
                  (sheet) => FlowPrimaryButton(
                    label: loc.flow_whatsAppYes,
                    onPressed: () => Navigator.of(sheet).pop(true),
                  ),
            ),
            const SizedBox(height: 8),
            Builder(
              builder:
                  (sheet) => FlowSecondaryButton(
                    label: loc.flow_whatsAppNo,
                    onPressed: () => Navigator.of(sheet).pop(false),
                  ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || yes == null || _busy) return;
    submitOnce(
      () =>
          yes
              ? onWhatsApp(number.$1, number.$2)
              : widget.onSend(number.$1, number.$2),
      tag: yes ? #whatsApp : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final country = _country;
    return FlowFrame(
      title: loc.flow_phoneTitle,
      hint: loc.flow_phoneHint,
      onBack: widget.onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _pickCountry,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
              minimumSize: const Size.fromHeight(48),
              alignment: AlignmentDirectional.centerStart,
            ),
            // The button keeps its own role, state and tap action for a
            // screen reader (review B4 I-1); only what it reads is replaced:
            // "Country, Ghana, +233" instead of the flag and the arrow.
            child: Semantics(
              label:
                  country == null
                      ? loc.flow_phoneChooseCountry
                      : loc.flow_phoneCountrySemantics(
                        country.name,
                        country.dialCode,
                      ),
              excludeSemantics: true,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      country == null
                          ? loc.flow_phoneChooseCountry
                          : '${country.flag}  ${country.name} (${country.dialCode})',
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FlowTextField(
            controller: _number,
            label: loc.flow_phoneLabel,
            hintText: country?.example,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\+\(\)]')),
            ],
            autofocus: country != null,
            errorText: switch (_error) {
              PhoneEntryError.tooShort => loc.flow_phoneTooShort,
              PhoneEntryError.tooLong => loc.flow_phoneTooLong,
              PhoneEntryError.wrongCountry => loc.flow_phoneWrongCountry(
                country?.name ?? '',
              ),
              null => null,
            },
            errorCount: _errorCount,
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 12),
          Text(
            loc.flow_phoneTerms,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.sendError != null) ...[
            const SizedBox(height: 12),
            FlowErrorLine(
              text: widget.sendError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
          if (_showSending) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(color: flowAccent(context)),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(loc.flow_sending, style: theme.textTheme.bodyMedium),
            ),
          ],
        ],
      ),
      actions: [
        // Progress shows on the button that was pressed (review B4 I-3).
        FlowPrimaryButton(
          label: loc.flow_phoneSend,
          busy: _busy && runningTag != #whatsApp,
          onPressed: runningTag == #whatsApp ? null : _send,
        ),
        if (widget.onSendWhatsApp != null)
          FlowSecondaryButton(
            label: loc.flow_phoneWhatsApp,
            busy: runningTag == #whatsApp,
            onPressed: _busy ? null : _sendWhatsApp,
          ),
      ],
    );
  }
}

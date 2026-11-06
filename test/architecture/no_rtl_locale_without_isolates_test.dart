// Spec 1 W10b (§2.3), batch 7 review M-1: a tripwire. Today every language
// the app ships reads left to right, so a phone number inside a sentence
// ("Call 0800 000 000") follows a left-to-right word and shows in order.
// In a right-to-left translation its digit groups would show reversed
// ("000 000 0800", "(233+)"). Adding such a language must come with
// left-to-right isolates (U+2066 ... U+2069) around each number below.
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Right-to-left languages (ISO 639-1, plus 'iw' for older Hebrew codes).
const _rightToLeft = {
  'ar',
  'he',
  'iw',
  'fa',
  'ur',
  'ps',
  'sd',
  'yi',
  'dv',
  'ug',
  'ckb',
  'ku',
};

const _numbersInSentences = '''
Wrap the number in a left-to-right isolate first (owner item, W10b):
  lib/i10n/app_en.arb flow_codeSubtitle, flow_whatsAppTitle, flow_codeCalling,
  flow_freshStartBody, support_call, support_text, support_callConfirmTitle,
  support_textConfirmTitle; and the country button's "(+233)" in
  lib/features/auth/sign_up/presentation/steps/phone_step.dart.''';

void main() {
  test('no right-to-left language ships before its numbers are isolated', () {
    final rtl =
        AppLocalizations.supportedLocales
            .where((l) => _rightToLeft.contains(l.languageCode))
            .toList();
    expect(rtl, isEmpty, reason: _numbersInSentences);
  });
}

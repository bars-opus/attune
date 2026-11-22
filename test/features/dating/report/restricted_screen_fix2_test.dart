// Spec 2 W7a Task 4 fix round 2 (re-review N-1): the ID email can be
// matched to an account. Accounts are phone-based, so the age check's line
// asks for the phone number used for Attune; Verify with ID opens the
// email with a discreet subject ("Attune ID check": no Dating, no number,
// nothing of the person); Contact support opens it with none.
import 'package:attune/core/utils/constants.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/restricted_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/tap_in_reach.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';

DatingRestrictionRead _read(DatingRestrictionType type) =>
    DatingRestrictionRead(
      ok: true,
      restriction: DatingRestriction(id: 'r1', type: type),
    );

void main() {
  final loc = AppLocalizationsEn();
  const email = AppConstants.supportEmail;

  // W7 final client fix (I-6): the ID check's reference code matches the
  // email to the case, so the phone number is no longer asked for.
  test('N-1 (final fix I-6): the age check asks for no phone number', () {
    expect(
      loc.dating_restrictedVerifyHelp(email),
      'Verify with ID opens an email to our support team at $email. Attach '
      'a photo of an official ID that shows your date of birth.',
    );
  });

  test('N-1: the ID email\'s subject is discreet; support\'s has none', () {
    final id = datingSupportMail(idCheck: true);
    expect(id.scheme, 'mailto');
    expect(id.path, email);
    expect(id.toString(), 'mailto:$email?subject=Attune%20ID%20check');
    expect(id.toString(), isNot(contains('Dating')));
    expect(id.toString(), isNot(contains('body')));
    expect(datingSupportMail().toString(), 'mailto:$email');
  });

  Future<List<Uri>> open(WidgetTester t, DatingRestrictionType type) async {
    final sent = <Uri>[];
    await pumpDatingShell(
      t,
      initial: DatingPaths.restricted,
      overrides: [
        ...datingReportOverrides(FakeDatingReport()..read = _read(type)),
        datingSupportContactProvider.overrideWithValue(
          (context, mail) async => sent.add(mail),
        ),
      ],
    );
    return sent;
  }

  testWidgets('N-1: Verify with ID opens the ID email; Contact support the '
      'plain one', (t) async {
    final id = await open(t, DatingRestrictionType.ageReview);
    expect(find.text(loc.dating_restrictedVerifyHelp(email)), findsOneWidget);
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_verify')));
    await t.pump();
    expect(id, [datingSupportMail(idCheck: true)]);

    final plain = await open(t, DatingRestrictionType.hold);
    await tapInReach(
      t,
      find.byKey(const ValueKey('dating_restricted_support')),
    );
    await t.pump();
    expect(plain, [datingSupportMail()]);
  });
}

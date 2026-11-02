// Spec 1 W4b (§3.8 R1): the registers. The code is in every message; the
// name goes with its comma when blank; the optional line goes before the
// link; Pidgin waits for the cultural reviewer; no AI vocabulary.
import 'package:attune/features/relationships/data/invite_messages.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _link = 'https://invite.attune.barsopus.com/i/K7P2QM';

void main() {
  final loc = lookupAppLocalizations(const Locale('en'));

  String message(InviteRegister register, {String? name, bool found = false}) =>
      inviteMessage(
        loc,
        register: register,
        link: _link,
        code: 'K7P2QM',
        partnerFirstName: name,
        foundItMyself: found,
      );

  test('Simple, named: the spec text, the code in the last line', () {
    expect(
      message(InviteRegister.simple, name: 'Ama'),
      "Hi Ama, I'd like us to try Attune together. It's a private space just "
      'for the two of us.\n'
      'Get the app: $_link\n'
      'Open Attune \u2192 I have an invite \u2192 K7P2QM',
    );
  });

  test('Casual and Pidgin, named', () {
    expect(
      message(InviteRegister.casual, name: 'Ama'),
      'Hey Ama! I found an app for couples and thought of us. Private, just '
      'you and me.\n'
      'Get it here: $_link\n'
      'Open Attune \u2192 I have an invite \u2192 K7P2QM',
    );
    expect(
      message(InviteRegister.pidgin, name: 'Ama'),
      'Ama, make we try Attune. Na private space for only you and me.\n'
      'Download am: $_link\n'
      'Open Attune \u2192 I have an invite \u2192 K7P2QM',
    );
  });

  test('no name: the name goes, and so does its comma', () {
    expect(
      message(InviteRegister.simple, name: '  ').split('\n').first,
      "Hi, I'd like us to try Attune together. It's a private space just for "
      'the two of us.',
    );
    expect(
      message(InviteRegister.casual).split('\n').first,
      'Hey! I found an app for couples and thought of us. Private, just you '
      'and me.',
    );
    expect(
      message(InviteRegister.pidgin).split('\n').first,
      'Make we try Attune. Na private space for only you and me.',
    );
  });

  test('the optional line goes before the link', () {
    final lines = message(
      InviteRegister.simple,
      name: 'Ama',
      found: true,
    ).split('\n');
    expect(lines, hasLength(4));
    expect(lines[1], "I found this myself. I just thought it'd be nice.");
    expect(lines[2], 'Get the app: $_link');
  });

  test('every register carries the code and no AI vocabulary', () {
    for (final register in InviteRegister.values) {
      for (final name in [null, 'Ama']) {
        final text = message(register, name: name, found: true);
        expect(text, contains('K7P2QM'));
        expect(text, contains(_link));
        expect(
          text.toLowerCase(),
          isNot(
            matches(RegExp(r'\b(ai|analysis|insight|intelligence|patterns)\b')),
          ),
        );
      }
    }
  });

  test('Pidgin is not offered until the cultural review (W4 gate)', () {
    expect(kPidginRegisterReviewed, isFalse);
    expect(offeredInviteRegisters(), [
      InviteRegister.simple,
      InviteRegister.casual,
    ]);
  });
}

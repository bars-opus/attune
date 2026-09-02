import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Location attach entry shares a place, not a file', () {
    // The '+' sheet already listed "Location", wired to onAttachFile --
    // tapping it would have opened a file picker. A visible entry doing
    // the wrong thing is worse than no entry.
    final source =
        File(
          'lib/features/chat/presentation/widgets/chat_text_field.dart',
        ).readAsStringSync();

    final entry = source.substring(
      source.indexOf("title: 'Location'"),
      source.indexOf("title: 'Location'") + 300,
    );

    expect(
      entry.contains('onTap: widget.onSharePlace'),
      isTrue,
      reason: 'Location must open the share-a-place sheet',
    );
    expect(entry.contains('onTap: widget.onAttachFile'), isFalse);
  });

  test('the distance row renders nothing when there is no honest answer', () {
    // Either partner not sharing, a stale reading, or a failed fetch must
    // all produce an ABSENT row. A row saying "location unavailable"
    // invites the question "why", which is the pressure this whole design
    // exists to avoid.
    final source =
        File(
          'lib/features/location/presentation/widgets/partner_distance_row.dart',
        ).readAsStringSync();

    // No "location unavailable" placeholder and no error state: those
    // invite the question "why", which is the pressure this design
    // avoids. The one thing the row may offer is the viewer's OWN switch.
    //
    // Comment lines are stripped first: the widget's own doc comment
    // quotes the phrase it must not render, so a whole-file search finds
    // the warning against the thing rather than the thing.
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    for (final placeholder in [
      'unavailable',
      'Unavailable',
      'No location',
      'Location off',
      'Could not',
    ]) {
      expect(
        code.contains(placeholder),
        isFalse,
        reason: 'an absent distance must not explain itself: $placeholder',
      );
    }
  });

  test('stopping presence deletes the row rather than hiding it', () {
    // Presence that is merely flagged off is still presence. The
    // guarantee is that turning it off leaves nothing behind.
    final source =
        File(
          'lib/features/location/data/presence_repository.dart',
        ).readAsStringSync();

    final stop = source.substring(source.indexOf('Future<void> stopSharing'));
    expect(
      stop.contains(".delete()"),
      isTrue,
      reason: 'stopSharing must delete the stored position',
    );
  });

  test('the repository can read a distance but never a position', () {
    // The asymmetry the whole feature rests on. If a method ever returns
    // the partner's coordinates, the ambient row has become a location
    // channel.
    final source =
        File(
          'lib/features/location/data/presence_repository.dart',
        ).readAsStringSync();

    expect(source.contains('partner_distance'), isTrue);
    expect(
      source.contains("from('partner_presence').select"),
      isFalse,
      reason: 'a client must never select a partner presence row directly',
    );
  });

  test('the location toggle reflects real state, not a hardcoded true', () {
    // It shipped hardcoded on, persisting nowhere -- the worst shape for
    // a privacy control, telling every user their location was shared
    // when nothing was.
    final source =
        File(
          'lib/features/chat/presentation/widgets/chat_settings_static_rows.dart',
        ).readAsStringSync();

    expect(
      source.contains('toggleValue: true'),
      isFalse,
      reason: 'a privacy toggle must not claim a state it has not read',
    );
    expect(source.contains('toggleValue: isSharingLocation'), isTrue);
    expect(
      source.contains('onToggleChanged: (value) {}'),
      isFalse,
      reason: 'the toggle must actually do something',
    );
  });

  test('turning sharing off reaches stopSharing', () {
    final source =
        File(
          'lib/features/chat/presentation/widgets/chat_settings_static_rows.dart',
        ).readAsStringSync();

    expect(source.contains('repository.stopSharing()'), isTrue);
  });

  test('a place photo goes through the EXIF-stripping image pipeline', () {
    // The chat spec strips EXIF on image upload. That matters more here
    // than anywhere else in the app: a photo taken at the place would
    // otherwise carry its exact coordinates past every coarsening
    // decision this feature makes.
    final source =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();

    final handler = source.substring(
      source.indexOf('Future<void> _sharePlace()'),
      source.indexOf('Future<void> _openGameRoute'),
    );

    expect(
      handler.contains('sendImageMessage'),
      isTrue,
      reason: 'a place photo must not bypass the media pipeline',
    );
  });

  test('the location fix is time-bounded', () {
    // Geolocator.getCurrentPosition has no time limit of its own, and on
    // a device with a poor fix it can hang indefinitely -- blocking the
    // distance read that runs behind it, so the row never appears at all.
    // Presence is ambient: a bounded failure that skips one cycle is
    // strictly better than a request that never returns.
    final source =
        File(
          'lib/features/location/data/presence_repository.dart',
        ).readAsStringSync();

    final record = source.substring(
      source.indexOf('Future<bool> recordOwnPresence'),
      source.indexOf('Future<PartnerDistance?> fetchDistance'),
    );

    expect(
      record.contains('.timeout('),
      isTrue,
      reason: 'an unbounded location fix can hang the whole row',
    );
  });

  test('opening the chat list does not start sharing on its own', () {
    // The distance provider recorded a position unconditionally on mount,
    // so a user who turned sharing OFF had it silently switched back on
    // the next time they opened the app. A privacy toggle the app
    // overrides is worse than no toggle.
    //
    // Sharing now starts only from the settings toggle, and the provider
    // merely refreshes a position that already exists.
    final source =
        File(
          'lib/features/location/presentation/providers/presence_providers.dart',
        ).readAsStringSync();

    final refresh = source.substring(
      source.indexOf('Future<void> refresh()'),
      source.indexOf('unawaited(refresh());'),
    );

    expect(
      refresh.contains('if (await repository.isSharing())'),
      isTrue,
      reason:
          'the provider must not record a position for someone who has '
          'not opted in',
    );
  });

  test('a partner who has not shared produces silence, not a prompt', () {
    // The asymmetry that matters. "Waiting for your partner" would put
    // the question "why haven't you turned it on?" on their screen --
    // exactly the pressure this design exists to avoid. Someone who wants
    // to ask can ask; the app will not ask on their behalf.
    final source =
        File(
          'lib/features/location/presentation/widgets/partner_distance_row.dart',
        ).readAsStringSync();

    expect(
      source.contains('if (sharing) return const SizedBox.shrink();'),
      isTrue,
      reason:
          'when the viewer IS sharing and there is still no distance, the '
          'partner has not opted in -- and that must stay invisible',
    );

    for (final nudge in [
      'Waiting for',
      'has not shared',
      "hasn't shared",
      'Ask ',
      'Invite ',
    ]) {
      expect(
        source.contains(nudge),
        isFalse,
        reason: 'the row must never nudge about a partner\'s choice: $nudge',
      );
    }
  });

  test('a viewer who has not shared is offered the switch', () {
    // Their OWN state, which they can act on -- so silence here would
    // just make the feature look broken to someone who never enabled it.
    final source =
        File(
          'lib/features/location/presentation/widgets/partner_distance_row.dart',
        ).readAsStringSync();

    expect(source.contains('Share how far apart you are'), isTrue);
    expect(
      source.contains('recordOwnPresence()'),
      isTrue,
      reason: 'the offer must actually turn sharing on',
    );
  });

  test('an unknown sharing state stays silent', () {
    // Defaults to `true` (i.e. assume sharing, show nothing) while the
    // check is in flight. Defaulting the other way would flash an
    // opt-in prompt at every user on every cold start.
    final source =
        File(
          'lib/features/location/presentation/widgets/partner_distance_row.dart',
        ).readAsStringSync();

    expect(
      source.contains('.valueOrNull ?? true'),
      isTrue,
      reason: 'an unresolved state must not flash a prompt',
    );
  });
}

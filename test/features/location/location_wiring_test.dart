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

  test('a place photo goes through the EXIF-stripping image pipeline', () {
    // The chat spec strips EXIF on image upload. That matters more here
    // than anywhere else in the app: a photo taken at the place would
    // otherwise carry its exact coordinates past every coarsening
    // decision this feature makes.
    final source =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();

    // Sliced between two named functions rather than by line number.
    // The end anchor used to be `_openGameRoute`, which was renamed to
    // `openGameRoute` when it moved to a top-level function -- indexOf
    // then returned -1 and substring threw a RangeError, so this test
    // failed on a name change rather than on the thing it guards.
    final start = source.indexOf('Future<void> _sharePlace()');
    final end = source.indexOf('Future<void> openGameRoute');
    expect(start, isNonNegative, reason: '_sharePlace was renamed');
    expect(end, greaterThan(start), reason: 'openGameRoute was renamed');

    final handler = source.substring(start, end);

    expect(
      handler.contains('sendImageMessage'),
      isTrue,
      reason: 'a place photo must not bypass the media pipeline',
    );
  });

  test('stopping deletes through stop_presence', () {
    final source =
        File(
          'lib/features/location/data/presence_repository.dart',
        ).readAsStringSync();
    expect(source.contains("'stop_presence'"), isTrue);
  });

  test('the client reads presence only through couple_map_presence', () {
    final source =
        File(
          'lib/features/location/data/presence_repository.dart',
        ).readAsStringSync();
    expect(source.contains("'couple_map_presence'"), isTrue);
    expect(
      source.contains("from('partner_presence')"),
      isFalse,
      reason:
          'no direct table access: the RPCs enforce snapping, pause and '
          'symmetry',
    );
  });

  test('turning sharing off reaches stopSharing(relationshipId)', () {
    final source =
        File(
          'lib/features/chat/presentation/widgets/chat_settings_static_rows.dart',
        ).readAsStringSync();
    expect(source.contains('repository.stopSharing(relationshipId)'), isTrue);
  });

  test('the sampler is time-bounded and coarse (never GPS-precise)', () {
    final source =
        File(
          'lib/features/location/data/presence_sampler.dart',
        ).readAsStringSync();
    // medium, not low: Android's low is city-level (~10 km), which would
    // almost never pass the 2 km cutoff. medium is ~100 m and never GPS.
    expect(source.contains('LocationAccuracy.medium'), isTrue);
    expect(source.contains('timeLimit:'), isTrue);
    expect(source.contains('.timeout('), isTrue);
  });

  test('the sampler never asks for permission on its own', () {
    final source =
        File(
          'lib/features/location/data/presence_sampler.dart',
        ).readAsStringSync();
    final sample = source.substring(
      source.indexOf('Future<PresenceSample?> sample()'),
      source.indexOf('Future<bool> requestPermission()'),
    );
    expect(sample.contains('requestPermission'), isFalse);
  });

  test('a partner who has not shared produces silence, not a prompt', () {
    // "Waiting for your partner" would put the question "why haven't you
    // turned it on?" on their screen -- exactly the pressure this design
    // exists to avoid.
    final source =
        File(
          'lib/features/location/presentation/widgets/partner_distance_row.dart',
        ).readAsStringSync();
    expect(
      source.contains('if (sharing) return const SizedBox.shrink();'),
      isTrue,
    );
    for (final nudge in [
      'Waiting for',
      'has not shared',
      "hasn't shared",
      'Ask ',
      'Invite ',
    ]) {
      expect(source.contains(nudge), isFalse, reason: nudge);
    }
  });

  test('a viewer who has not shared is offered the switch', () {
    final source =
        File(
          'lib/features/location/presentation/widgets/partner_distance_row.dart',
        ).readAsStringSync();
    expect(source.contains('Share how far apart you are'), isTrue);
    expect(source.contains('startSharing(relationshipId)'), isTrue);
  });

  test('an unknown sharing state stays silent', () {
    // Assume sharing (show nothing) while the read is in flight, so no
    // opt-in prompt flashes on every cold start.
    final source =
        File(
          'lib/features/location/presentation/widgets/partner_distance_row.dart',
        ).readAsStringSync();
    expect(
      source.replaceAll(RegExp(r'\s'), '').contains('.valueOrNull?.isOn??true'),
      isTrue,
    );
  });

  test('checking location access never prompts', () {
    final source =
        File(
          'lib/features/location/data/presence_sampler.dart',
        ).readAsStringSync();
    final access = source.substring(
      source.indexOf('Future<LocationAccess> access()'),
      source.indexOf('Future<void> openSettings()'),
    );
    expect(access.contains('requestPermission'), isFalse);
  });

  test('the sampler does not claim on-device geocoding', () {
    final source =
        File(
          'lib/features/location/data/presence_sampler.dart',
        ).readAsStringSync();
    expect(
      source.contains('On-device geocoding'),
      isFalse,
      reason: 'Geocoder/CLGeocoder send the fix to Google/Apple (Phase 0 M12)',
    );
  });

  test('the presence time zone is re-read, so travel updates it', () {
    final source =
        File(
          'lib/features/location/presentation/providers/presence_providers.dart',
        ).readAsStringSync();
    expect(source.contains('TimezoneUtils.clearCache()'), isTrue);
  });
}

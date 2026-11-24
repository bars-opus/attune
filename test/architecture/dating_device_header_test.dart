// Spec 2 W4b (§3.3.4, §7.4, S-7, C-6, R15): only the Dating client sends
// the install's id: no other file in lib/ names the header, only the app's
// first-launch line and the Dating client read the id, nothing logs it,
// lib/main.dart knows nothing of it, and every Dating call (the
// repositories, the verification layer, settings, the gentle wait and
// isDatingModeAvailable) goes through the Dating client.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (f) => f.path.endsWith('.dart') && !f.path.contains('/i10n/generated/'),
    );

List<String> _filesWith(String text, [String dir = 'lib']) => [
  for (final f in _dart(dir))
    if (f.readAsStringSync().contains(text)) f.path,
]..sort();

void main() {
  test('only the Dating client names x-attune-device', () {
    expect(_filesWith('x-attune-device'), [
      'lib/features/dating/data/dating_supabase_client.dart',
    ]);
  });

  test('only the first launch and the Dating client read the id', () {
    expect(_filesWith('installIdStoreProvider'), [
      'lib/app/app.dart',
      'lib/core/device/install_id.dart',
      'lib/features/dating/data/dating_supabase_client.dart',
    ]);
    expect(_filesWith('InstallIdStore'), ['lib/core/device/install_id.dart']);
    expect(_filesWith('attune.install_id'), [
      'lib/core/device/install_id.dart',
    ]);
    expect(
      File('lib/main.dart').readAsStringSync(),
      isNot(contains('install_id')),
    );
  });

  test('nothing that holds the id logs', () {
    for (final path in [
      'lib/core/device/install_id.dart',
      'lib/features/dating/data/dating_supabase_client.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(matches(RegExp(r'\b(print|debugPrint|log|developer)\b\s*[(.]'))),
        reason: path,
      );
    }
  });

  test('every Dating call goes through the Dating client', () {
    expect(_filesWith('Supabase.instance', 'lib/features/dating'), [
      'lib/features/dating/data/dating_supabase_client.dart',
    ]);
    // W3 T1 M-5 (carry 10): the manual's Dating flag is read on it too.
    expect(
      File(
        'lib/app/documentations/user_manual/data/documentation_flags.dart',
      ).readAsStringSync(),
      matches(
        RegExp(
          r'isDatingModeAvailable\(\s*ref\.read\(datingSupabaseClientProvider\)',
        ),
      ),
    );
    expect(
      _filesWith(
        'isDatingModeAvailable(',
      ).where((f) => !f.startsWith('lib/features/dating/')),
      ['lib/app/documentations/user_manual/data/documentation_flags.dart'],
    );
  });

  // Fix round 1 (I-3a): the privacy direction. Nothing outside Dating
  // (but the manual's one flag read) uses the Dating client, its header
  // wrapper or its device signal, so no other traffic carries the id.
  test('only Dating uses the Dating client', () {
    for (final name in [
      'datingSupabaseClientProvider',
      'datingSupabaseClient(',
      'datingDeviceReadyProvider',
    ]) {
      expect(
        _filesWith(name).where((f) => !f.startsWith('lib/features/dating/')),
        name == 'datingSupabaseClientProvider'
            ? [
              'lib/app/documentations/user_manual/data/documentation_flags.dart',
            ]
            : isEmpty,
        reason: name,
      );
    }
    expect(_filesWith('DatingDeviceHttpClient'), [
      'lib/features/dating/data/dating_supabase_client.dart',
    ]);
  });

  // Fix round 1 (I-3b): the lockout direction. No Dating file reaches a
  // Supabase client but the Dating one: none of the app's other
  // supabaseClientProviders, and no client built by hand.
  test('Dating uses no other Supabase client', () {
    final other = RegExp(
      r'(?<![dD]ating)[sS]upabaseClientProvider|(?<![dD]ating)SupabaseClient\(',
    );
    expect([
      for (final f in _dart('lib/features/dating'))
        if (f.path != 'lib/features/dating/data/dating_supabase_client.dart' &&
            other.hasMatch(f.readAsStringSync()))
          f.path,
    ], isEmpty);
  });

  // Spec 2 W9 (R-W9-16 as built; Task 5 fix round 2, M-7): a named,
  // deliberate exception to the rule above (the final client fix's I-1
  // adds the couple side, below). Whether dating_couple_link is
  // on is read for every couple, Dating or not, so it is not Dating
  // traffic and carries no install id: lib/core/flags/couple_link_flag.dart
  // reads get_dating_home() on the app's own client, and the couple link's
  // provider is the only Dating file that reaches it.
  test('the couple-link flag read is a named non-Dating client', () {
    const flag = 'lib/core/flags/couple_link_flag.dart';
    expect(_filesWith('coupleLinkFlagReadProvider'), [
      flag,
      'lib/features/dating/link/dating_link.dart',
    ]);
    expect(
      _filesWith('core/flags/couple_link_flag.dart', 'lib/features/dating'),
      ['lib/features/dating/link/dating_link.dart'],
    );
    final source = File(flag).readAsStringSync();
    expect(source, contains('ref.watch(supabaseClientProvider)'));
    expect(RegExp(r'\.rpc\(').allMatches(source), hasLength(1));
    expect(source, contains("client.rpc('get_dating_home')"));
    for (final name in [
      'datingSupabaseClient',
      'DatingDeviceHttpClient',
      'x-attune-device',
      'installId',
      'InstallId',
    ]) {
      expect(source, isNot(contains(name)), reason: name);
    }
  });

  // Spec 2 W9 final client fix (I-1; S-7, R15): the second named exception.
  // The couple side of the link (the Relationship home's card and its
  // dismiss, the match date, How we met) is read by every couple, Dating or
  // not, so it is couples traffic: lib/core/flags/couple_link_couple_side.dart
  // makes those four calls on the app's own client, and the couple link's
  // repository is the only Dating file that reaches it. The chat side's
  // calls stay on Dating's client.
  test('the couple side of the link is the other non-Dating client', () {
    const side = 'lib/core/flags/couple_link_couple_side.dart';
    const link = 'lib/features/dating/link/dating_link.dart';
    expect(_filesWith('coupleLinkCoupleCallProvider'), [side, link]);
    expect(
      _filesWith(
        'core/flags/couple_link_couple_side.dart',
        'lib/features/dating',
      ),
      [link],
    );
    final source = File(side).readAsStringSync();
    expect(source, contains('ref.watch(supabaseClientProvider)'));
    expect(RegExp(r'\.rpc\(').allMatches(source), hasLength(1));
    for (final name in [
      'datingSupabaseClient',
      'datingRpc',
      'DatingRpc',
      'DatingDeviceHttpClient',
      'x-attune-device',
      'installId',
      'InstallId',
    ]) {
      expect(source, isNot(contains(name)), reason: name);
    }
    // The four couple-side calls are named only there in the repository's
    // couple path, never through Dating's RPC client.
    final repo = File(link).readAsStringSync();
    for (final fn in const [
      'get_dating_post_link_offer',
      'dismiss_dating_post_link_offer',
      'get_dating_link_origin',
      'get_how_we_met',
    ]) {
      expect(source, contains("'$fn'"), reason: fn);
      expect(repo, contains("_couple('$fn'"), reason: fn);
      expect(repo, isNot(contains("_rpc.call('$fn'")), reason: fn);
    }
    expect(repo, contains('couple: ref.watch(coupleLinkCoupleCallProvider)'));
  });

  // Fix round 1 (M-3): every Dating photo is read through the Dating
  // client's storage (bytes, Image.memory); no URL a request could fetch
  // without the header.
  test('no Dating photo is fetched by URL', () {
    final byUrl = RegExp(r'Image\.network|NetworkImage|createSignedUrls?\(');
    expect([
      for (final f in _dart('lib/features/dating'))
        if (byUrl.hasMatch(f.readAsStringSync())) f.path,
    ], isEmpty);
  });
}

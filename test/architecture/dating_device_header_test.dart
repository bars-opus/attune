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

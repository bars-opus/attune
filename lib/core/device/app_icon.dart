// Spec 2 W8b (§6.7, §3.2 D13; R-80): the plain app icon, for everyone.
// Android: one of two launcher aliases is on (MainActivity's appIcon and
// setAppIcon on attune/safety); iOS: the alternate icon IconPlain
// (AppDelegate's; iOS shows its own alert). The choice lives in the OS,
// never in a key the app stores, so quick exit and sign-out can't touch
// it (protective, C-2). Never throws: a phone without the channel answers
// null and changes nothing. One control behind both pages: Settings ->
// App icon and Dating settings' (R-80).
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppIconChoice { attune, plain }

abstract class AppIconControl {
  /// The icon on the home screen now; null when this phone can't say or
  /// can't change it.
  Future<AppIconChoice?> current();

  /// True once the phone took [choice].
  Future<bool> choose(AppIconChoice choice);
}

class PlatformAppIcon implements AppIconControl {
  const PlatformAppIcon();

  static const channel = MethodChannel('attune/safety');

  @override
  Future<AppIconChoice?> current() async {
    try {
      return switch (await channel.invokeMethod<String>('appIcon')) {
        'plain' => AppIconChoice.plain,
        'default' => AppIconChoice.attune,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> choose(AppIconChoice choice) async {
    try {
      return await channel.invokeMethod<bool>(
            'setAppIcon',
            choice == AppIconChoice.plain ? 'plain' : 'default',
          ) ==
          true;
    } catch (_) {
      return false;
    }
  }
}

final appIconControlProvider = Provider<AppIconControl>(
  (ref) => const PlatformAppIcon(),
);

/// The icon on the home screen, read again whenever it is shown.
final appIconProvider = FutureProvider.autoDispose<AppIconChoice?>(
  (ref) => ref.watch(appIconControlProvider).current(),
);

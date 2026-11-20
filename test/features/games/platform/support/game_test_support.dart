import 'dart:io';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The screens a golden is taken on.
///
/// A phone first, always. The default test surface is 800x600 landscape,
/// and judging a portrait screen's proportions against that is judging a
/// different screen: it distorted an earlier game's goldens by nearly 3x
/// before anyone noticed.
const Size phone = Size(375, 812);
const Size widePhone = Size(430, 932);
const Size tablet = Size(1024, 1366);

const Map<String, Size> goldenSurfaces = {
  'phone': phone,
  'wide': widePhone,
  'tablet': tablet,
};

/// Pins the test to a real screen size.
///
/// It also makes a tap that lands on nothing fail the test. By default a
/// missed tap only prints a warning, and a test that then checks for the
/// absence of something passes without having done anything.
void useSurface(WidgetTester tester, Size size) {
  WidgetController.hitTestWarningShouldBeFatal = true;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Loads Roboto and the Material icons, so goldens show words and icons
/// rather than the test font's solid blocks. A frame nobody can read is a
/// frame nobody can judge.
///
/// The fonts ship in the Flutter SDK's cache. If they are missing the test
/// font is used and the goldens will not match -- loudly, not silently.
Future<void> loadGameTestFonts() async {
  Directory? fonts;
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8 && fonts == null; i++) {
    for (final candidate in [
      Directory('${dir.path}/material_fonts'),
      Directory('${dir.path}/artifacts/material_fonts'),
    ]) {
      if (candidate.existsSync()) fonts = candidate;
    }
    dir = dir.parent;
  }
  if (fonts == null) return;

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    var any = false;
    for (final name in files) {
      final file = File('${fonts!.path}/$name');
      if (!file.existsSync()) continue;
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
      any = true;
    }
    if (any) await loader.load();
  }

  await load('Roboto', const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]);
  await load('MaterialIcons', const ['MaterialIcons-Regular.otf']);
}

Future<SharedPreferences> testPrefs([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

/// The themes a layout's fit is proven under, by name.
///
/// The tests' own theme (null: the host's default, plain Roboto) and the
/// app's light theme, which is what ships. The app's text styles carry a 1.5
/// line height on several roles, so a fit proven only under the plain theme
/// is a few pixels short of proven for the app. The app's dark theme has the
/// same text styles (`AppTextTheme.darkTextTheme` is the light one), so it
/// fits wherever the light one does.
///
/// The app sets no font family; on the test platform (Android) Material's
/// typography names Roboto, which [loadGameTestFonts] loads offline from the
/// SDK. A phone running iOS draws in its system font instead.
final Map<String, ThemeData?> fitThemes = {
  'test theme': null,
  'app light theme': AppTheme.lightTheme,
};

/// What a test run over [fitThemes] adds to its name: nothing under the
/// tests' own theme, so the test keeps the name it had, and the theme's name
/// under the app's.
String fitThemeSuffix(String name, ThemeData? theme) =>
    theme == null ? '' : ' (under the $name)';

/// Hosts a shell widget with the three things it reads from the app: local
/// preferences, sound and haptics.
///
/// [overrides] are a game screen's own providers. They go in the same scope:
/// a second scope around this one would hide the preferences from the
/// providers that read them.
///
/// [theme] is the app's theme around the game; left out, a plain Roboto
/// one. Pass `AppTheme.lightTheme` or `AppTheme.darkTheme` to host the game
/// in the app as it ships.
Widget gameHost(
  Widget child, {
  required SharedPreferences prefs,
  SoundService? sound,
  Haptics? haptics,
  bool reduceMotion = false,
  double textScale = 1,
  List<Override> overrides = const [],
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      soundServiceProvider.overrideWithValue(sound ?? FakeSoundService()),
      hapticsProvider.overrideWithValue(haptics ?? FakeHaptics()),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? ThemeData(fontFamily: 'Roboto'),
      builder:
          (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduceMotion,
              textScaler: TextScaler.linear(textScale),
            ),
            child: app!,
          ),
      home: child,
    ),
  );
}

/// Records what a painter asks a canvas to do.
///
/// It counts the calls a test cares about and NAMES every other call, so a
/// painter that reached for something costlier -- a saveLayer, a clip --
/// cannot satisfy a draw-count check unnoticed.
class RecordingCanvas implements Canvas {
  final List<({Offset from, Offset to, Paint paint})> lines = [];
  final List<String> unmodelled = [];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((from: p1, to: p2, paint: paint));

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unmodelled.add(invocation.memberName.toString());
    return null;
  }
}

/// WCAG contrast between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

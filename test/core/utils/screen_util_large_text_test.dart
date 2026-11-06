// Spec 1 W10a: ScreenUtil never scales text a second time. .sp is the
// identity (fontSizeResolver), so minTextAdapt has no effect on fonts, the
// phone's text size is applied once (by Flutter's TextScaler), and the iPad
// 1.25x cap moves spacing only, never text.
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, double>> _measure(
  WidgetTester t, {
  required Size screen,
  required double textScale,
}) async {
  t.view.physicalSize = screen;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
  late double sp;
  late double w;
  await t.pumpWidget(
    ScreenUtilConfig.builder(
      builder: (context) {
        sp = 16.sp;
        w = 100.w;
        return const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'Aa',
                key: ValueKey('probe'),
                style: TextStyle(fontSize: 16, height: 1),
              ),
            ),
          ),
        );
      },
    ),
  );
  return {
    'sp': sp,
    'w': w,
    'height': t.getSize(find.byKey(const ValueKey('probe'))).height,
  };
}

void main() {
  test('the resolver is the identity and minTextAdapt stays on', () {
    expect(ScreenUtilConfig.minTextAdapt, isTrue);
    expect(ScreenUtilConfig.maxScale, 1.25);
  });

  testWidgets('.sp ignores the screen size (phone and iPad)', (t) async {
    final phone = await _measure(t, screen: const Size(390, 844), textScale: 1);
    final pad = await _measure(t, screen: const Size(1024, 1366), textScale: 1);
    expect(phone['sp'], 16);
    expect(pad['sp'], 16);
  });

  testWidgets('the iPad cap moves spacing by at most 1.25x', (t) async {
    final pad = await _measure(t, screen: const Size(1024, 1366), textScale: 1);
    expect(pad['w'], closeTo(125, 0.01));
  });

  testWidgets('the phone text size is applied once, and not to spacing', (
    t,
  ) async {
    final one = await _measure(t, screen: const Size(390, 844), textScale: 1);
    final two = await _measure(t, screen: const Size(390, 844), textScale: 2);
    expect(two['sp'], one['sp'], reason: '.sp never reads the text scale');
    expect(two['w'], one['w'], reason: '.w never reads the text scale');
    expect(two['height'], closeTo(one['height']! * 2, 0.5));
  });
}

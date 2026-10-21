// On a big screen (iPad) phone-designed spacing stops growing at 1.25×, and
// content sits in a centred column — the Health app's way — while
// backgrounds still fill the screen. Phones are untouched.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = Size(375, 812);
const _proMax = Size(440, 956);
const _iPadPortrait = Size(1032, 1376); // 13" iPad (M3/M4)
const _iPadLandscape = Size(1376, 1032);

void _screen(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  group('spacing scale', () {
    test('phones keep the design size, so nothing on a phone moves', () {
      for (final s in [_phone, const Size(393, 852), _proMax]) {
        expect(ScreenUtilConfig.designSizeFor(s), ScreenUtilConfig.designSize);
      }
      // A small phone scales down as before.
      expect(
        ScreenUtilConfig.designSizeFor(const Size(320, 568)),
        ScreenUtilConfig.designSize,
      );
    });

    test('a big screen scales by at most 1.25 each way', () {
      for (final s in [_iPadPortrait, _iPadLandscape]) {
        final d = ScreenUtilConfig.designSizeFor(s);
        expect(s.width / d.width, closeTo(ScreenUtilConfig.maxScale, 1e-9));
        expect(s.height / d.height, closeTo(ScreenUtilConfig.maxScale, 1e-9));
      }
    });

    Future<double> sixteenW(WidgetTester t, Size size) async {
      _screen(t, size);
      late double w, h;
      await t.pumpWidget(
        ScreenUtilConfig.builder(
          builder: (_) {
            w = 16.w;
            h = 16.h;
            return const SizedBox();
          },
        ),
      );
      expect(h, closeTo(16 * (size.height / 812).clamp(0, 1.25), 1e-6));
      return w;
    }

    testWidgets('16.w on a phone is as it was', (t) async {
      expect(
        await sixteenW(t, const Size(393, 852)),
        closeTo(16 * 393 / 375, 1e-6),
      );
    });

    testWidgets('16.w on a 13" iPad is 20, not 44', (t) async {
      expect(await sixteenW(t, _iPadPortrait), closeTo(20, 1e-6));
    });
  });

  group('content column', () {
    Future<Rect> boxRect(WidgetTester t, Size size, double max) async {
      _screen(t, size);
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AppContentWidth(
            maxWidth: max,
            child: const SizedBox.expand(key: ValueKey('content')),
          ),
        ),
      );
      return t.getRect(find.byKey(const ValueKey('content')));
    }

    testWidgets('on a phone it is the full width', (t) async {
      final r = await boxRect(t, _phone, ContentWidth.list);
      expect(r, const Rect.fromLTWH(0, 0, 375, 812));
    });

    testWidgets('on an iPad it is centred and no wider than the cap', (
      t,
    ) async {
      final r = await boxRect(t, _iPadPortrait, ContentWidth.list);
      expect(r.width, ContentWidth.list);
      expect(r.left, (1032 - ContentWidth.list) / 2);
      expect(r.height, 1376, reason: 'only the width is capped');

      final l = await boxRect(t, _iPadLandscape, ContentWidth.form);
      expect(l.width, ContentWidth.form);
      expect(l.center.dx, 1376 / 2);
    });

    Future<Rect> sliverRect(WidgetTester t, Size size) async {
      _screen(t, size);
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CustomScrollView(
            slivers: [
              AppContentSliver(
                slivers: [
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 40, key: ValueKey('row')),
                  ),
                  SliverList.list(children: const [SizedBox(height: 40)]),
                ],
              ),
            ],
          ),
        ),
      );
      return t.getRect(find.byKey(const ValueKey('row')));
    }

    Future<EdgeInsets> padded(WidgetTester t, Size size) async {
      _screen(t, size);
      late EdgeInsets p;
      await t.pumpWidget(
        Builder(
          builder: (context) {
            p = AppContentWidth.padded(context, const EdgeInsets.all(16));
            return const SizedBox();
          },
        ),
      );
      return p;
    }

    testWidgets(
      'a list view\'s own padding grows by the side margin on an iPad only',
      (t) async {
        expect(await padded(t, _phone), const EdgeInsets.all(16));
        final side = (1032 - ContentWidth.list) / 2;
        expect(
          await padded(t, _iPadPortrait),
          EdgeInsets.fromLTRB(16 + side, 16, 16 + side, 16),
        );
      },
    );

    testWidgets(
      'a list keeps scrolling edge to edge but its rows sit in the column',
      (t) async {
        expect((await sliverRect(t, _phone)).width, 375);
        final r = await sliverRect(t, _iPadPortrait);
        expect(r.width, ContentWidth.list);
        expect(r.left, (1032 - ContentWidth.list) / 2);
      },
    );
  });
}

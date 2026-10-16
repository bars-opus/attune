import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_preview.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_publisher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Publisher extends Fake implements CoupleWidgetPublisher {
  @override
  final preview = ValueNotifier<CoupleWidgetPreview?>(null);
}

Future<_Publisher> pump(WidgetTester t, CoupleWidgetPreview? value) async {
  final p = _Publisher()..preview.value = value;
  await t.pumpWidget(
    ProviderScope(
      overrides: [coupleWidgetPublisherProvider.overrideWithValue(p)],
      child: const MaterialApp(home: Scaffold(body: CoupleWidgetPreviewCard())),
    ),
  );
  return p;
}

void main() {
  testWidgets(
    'shows the lines and the label; the image is hidden from screen readers',
    (t) async {
      final semantics = t.ensureSemantics();
      await pump(
        t,
        CoupleWidgetPreview(
          const CoupleWidgetView(
            headline: 'Together tomorrow',
            caption: '5.1k km apart',
            clockLine: '3:15pm there',
          ),
          Uint8List.fromList(kTransparentPng),
        ),
      );
      expect(find.text(widgetPreviewLabel), findsOneWidget);
      expect(find.text('Together tomorrow'), findsOneWidget);
      expect(find.text('5.1k km apart'), findsOneWidget);
      expect(find.text('3:15pm there'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(t.widget<Image>(find.byType(Image)).excludeFromSemantics, isTrue);
      semantics.dispose();
    },
  );

  testWidgets('nothing yet: the neutral card, no image', (t) async {
    await pump(t, null);
    expect(find.text(neutralHeadline), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('one platform instruction line', (t) async {
    await pump(t, null);
    expect(
      find.text(widgetHowToIos).evaluate().length +
          find.text(widgetHowToAndroid).evaluate().length,
      1,
    );
  });
}

const kTransparentPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

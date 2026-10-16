import 'dart:io';
// test/features/couple_map/pin_image_renderer_test.dart
import 'dart:ui' as ui;

import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

PinSpec _spec(String initials, {String? url}) => PinSpec(
  imageUrl: url,
  initials: initials,
  ring: Colors.white,
  fill: Colors.indigo,
  onFill: Colors.white,
  sizePx: 88,
);

Future<ui.Image> _photo() async {
  final r = ui.PictureRecorder();
  Canvas(r).drawColor(Colors.orange, BlendMode.src);
  return r.endRecording().toImage(10, 10);
}

void main() {
  testWidgets('initials render to a PNG of the requested size', (t) async {
    await t.runAsync(() async {
      final bytes = await PinImageRenderer().render(_spec('AM'));
      expect(bytes.sublist(0, 4), [137, 80, 78, 71]);
      final png = img.decodePng(bytes)!;
      expect((png.width, png.height), (88, 88));
    });
  });

  testWidgets(
    'loader failure falls back to initials, never a blank or a throw',
    (t) async {
      await t.runAsync(() async {
        final r = PinImageRenderer(loader: (_) async => throw Exception('404'));
        final bytes = await r.render(_spec('K', url: 'https://x/a.jpg'));
        expect(img.decodePng(bytes), isNotNull);
      });
    },
  );

  testWidgets('a photo is fetched once per spec (cached)', (t) async {
    await t.runAsync(() async {
      var loads = 0;
      final r = PinImageRenderer(
        loader: (_) async {
          loads++;
          return _photo();
        },
      );
      final a = await r.render(_spec('K', url: 'https://x/a.jpg'));
      final b = await r.render(_spec('K', url: 'https://x/a.jpg'));
      expect(loads, 1);
      expect(identical(a, b), isTrue);
    });
  });

  testWidgets('the cache is a bounded LRU (checklist 2.12–2.15)', (t) async {
    await t.runAsync(() async {
      var loads = 0;
      final r = PinImageRenderer(
        maxEntries: 2,
        loader: (_) async {
          loads++;
          return _photo();
        },
      );
      await r.render(_spec('A', url: 'u1'));
      await r.render(_spec('B', url: 'u2'));
      await r.render(_spec('A', url: 'u1')); // A is now most recent
      await r.render(_spec('C', url: 'u3')); // evicts B
      expect(r.length, 2);
      await r.render(_spec('A', url: 'u1'));
      expect(loads, 3, reason: 'A stayed cached');
      await r.render(_spec('B', url: 'u2'));
      expect(loads, 4, reason: 'B was evicted');
    });
  });

  testWidgets('clear empties the cache (quick exit)', (t) async {
    await t.runAsync(() async {
      final r = PinImageRenderer();
      await r.render(_spec('A'));
      r.clear();
      expect(r.length, 0);
    });
  });

  testWidgets(
    'a failed photo is not kept: the next render tries again (no sticky initials)',
    (t) async {
      await t.runAsync(() async {
        var loads = 0;
        final r = PinImageRenderer(
          loader: (_) async {
            loads++;
            if (loads == 1) throw Exception('offline');
            return _photo();
          },
        );
        await r.render(_spec('K', url: 'https://x/a.jpg'));
        await r.render(_spec('K', url: 'https://x/a.jpg'));
        expect(loads, 2);
        await r.render(_spec('K', url: 'https://x/a.jpg'));
        expect(loads, 2, reason: 'a successful photo stays cached');
      });
    },
  );

  testWidgets(
    'raw pins are premultiplied RGBA of 4 × w × h bytes, cached by key',
    (t) async {
      await t.runAsync(() async {
        var loads = 0;
        final r = PinImageRenderer(
          loader: (_) async {
            loads++;
            return _photo();
          },
        );
        PinSpec spec(String url) => PinSpec(
          imageUrl: url,
          cacheKey: 't/1.jpg',
          initials: '',
          ring: Colors.white,
          fill: Colors.black,
          onFill: Colors.white,
          sizePx: 20,
        );
        final a = await r.renderRaw(spec('https://signed/1?token=a'));
        final b = await r.renderRaw(
          spec('https://signed/1?token=b'),
        ); // a fresh signature, same thumbnail
        expect(a.rgba.length, 4 * 20 * 20);
        expect((a.width, a.height), (20, 20));
        expect(
          loads,
          1,
          reason: 'keyed by thumbnail key, not the signed URL (spec §9 3.4)',
        );
        expect(identical(a, b), isTrue);
      });
    },
  );

  testWidgets(
    'a cached raw pin is found by its key without a URL (no re-signing)',
    (t) async {
      await t.runAsync(() async {
        final r = PinImageRenderer(loader: (_) async => _photo());
        PinSpec spec(String? url) => PinSpec(
          imageUrl: url,
          cacheKey: 't/9.jpg',
          initials: '',
          ring: Colors.white,
          fill: Colors.black,
          onFill: Colors.white,
          sizePx: 20,
        );
        expect(r.peekRaw(spec(null)), isNull);
        await r.renderRaw(spec('https://signed/9?token=a'));
        expect(await r.peekRaw(spec(null)), isNotNull);
      });
    },
  );

  test(
    'network thumbnails are disk-cached by their storage key, not the signed URL',
    () {
      final src =
          File(
            'lib/features/couple_map/presentation/widgets/pin_image_renderer.dart',
          ).readAsStringSync();
      expect(src.contains('cacheKey: cacheKey'), isTrue);
    },
  );
}

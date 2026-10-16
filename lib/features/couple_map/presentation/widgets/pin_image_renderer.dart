import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

typedef PinImageLoader = Future<ui.Image?> Function(String url);

@immutable
class PinSpec {
  const PinSpec({
    this.imageUrl,
    this.cacheKey,
    required this.initials,
    required this.ring,
    required this.fill,
    required this.onFill,
    required this.sizePx,
  });
  final String? imageUrl;

  /// What the cache keys on instead of [imageUrl] when set — a story
  /// thumbnail's storage key, since its signed URL changes every time
  /// (spec §9 3.4: signed URLs are never the cache key).
  final String? cacheKey;
  final String initials;
  final Color ring;
  final Color fill;
  final Color onFill;
  final int sizePx;

  String? get _key => cacheKey ?? imageUrl;

  @override
  bool operator ==(Object other) =>
      other is PinSpec &&
      other._key == _key &&
      other.initials == initials &&
      other.ring == ring &&
      other.fill == fill &&
      other.onFill == onFill &&
      other.sizePx == sizePx;

  @override
  int get hashCode => Object.hash(_key, initials, ring, fill, onFill, sizePx);
}

/// A pin as premultiplied RGBA, for a Mapbox style image (MbxImage).
@immutable
class RawPin {
  const RawPin({required this.rgba, required this.width, required this.height});
  final Uint8List rgba;
  final int width;
  final int height;
}

/// Renders a pin (photo or initials in a ring) for the map: PNG bytes for
/// a point annotation ([render]) or raw RGBA for a style image
/// ([renderRaw]). Each kept in a bounded LRU; a failed photo falls back to
/// initials and isn't kept, so the next render tries again.
class PinImageRenderer {
  PinImageRenderer({
    PinImageLoader? loader,
    this.maxEntries = CoupleMapConfig.pinCacheEntries,
  }) : _loader = loader;

  /// A test seam; null means the network, disk-cached by the pin's key.
  final PinImageLoader? _loader;
  final int maxEntries;
  final _cache = <PinSpec, Future<Uint8List>>{}; // insertion order = recency
  final _rawCache = <PinSpec, Future<RawPin>>{};

  int get length => _cache.length + _rawCache.length;

  void clear() {
    _cache.clear();
    _rawCache.clear();
  }

  Future<Uint8List> render(PinSpec spec) => _cached(_cache, spec, () async {
    final p = await _paint(spec);
    final data = await p.image.toByteData(format: ui.ImageByteFormat.png);
    p.image.dispose();
    return (value: data!.buffer.asUint8List(), photoFailed: p.photoFailed);
  });

  /// A raw pin already rendered for [spec]'s key, or null. Lets the map
  /// skip signing a thumbnail URL it doesn't need (spec §9 3.4).
  Future<RawPin>? peekRaw(PinSpec spec) {
    final hit = _rawCache.remove(spec);
    if (hit != null) _rawCache[spec] = hit; // most recently used
    return hit;
  }

  Future<RawPin> renderRaw(PinSpec spec) => _cached(_rawCache, spec, () async {
    final p = await _paint(spec);
    // rawRgba is premultiplied, which is what MbxImage expects.
    final data = await p.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final raw = RawPin(
      rgba: data!.buffer.asUint8List(),
      width: p.image.width,
      height: p.image.height,
    );
    p.image.dispose();
    return (value: raw, photoFailed: p.photoFailed);
  });

  Future<T> _cached<T>(
    Map<PinSpec, Future<T>> cache,
    PinSpec spec,
    Future<({T value, bool photoFailed})> Function() draw,
  ) {
    final hit = cache.remove(spec);
    if (hit != null) {
      cache[spec] = hit;
      return hit;
    }
    // A photo that failed to load isn't kept: the next render tries again,
    // so one flaky open doesn't leave initials for the whole session.
    late final Future<T> result;
    result = draw().then(
      (r) {
        if (r.photoFailed && identical(cache[spec], result)) {
          cache.remove(spec);
        }
        return r.value;
      },
      onError: (Object e, StackTrace st) {
        if (identical(cache[spec], result)) cache.remove(spec);
        Error.throwWithStackTrace(e, st);
      },
    );
    cache[spec] = result;
    while (cache.length > maxEntries) {
      cache.remove(cache.keys.first);
    }
    return result;
  }

  Future<({ui.Image image, bool photoFailed})> _paint(PinSpec s) async {
    ui.Image? photo;
    final url = s.imageUrl;
    if (url != null && url.isNotEmpty) {
      try {
        final loader = _loader;
        photo = await (loader != null
                ? loader(url)
                : _networkImage(url, cacheKey: s.cacheKey))
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        photo = null;
      }
    }
    final size = s.sizePx.toDouble();
    final r = size / 2;
    final centre = Offset(r, r);
    final inner = r - size * 0.08;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(centre, r, Paint()..color = s.ring);
    final face = Rect.fromCircle(center: centre, radius: inner);
    if (photo != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(face));
      paintImage(canvas: canvas, rect: face, image: photo, fit: BoxFit.cover);
      canvas.restore();
    } else {
      canvas.drawCircle(centre, inner, Paint()..color = s.fill);
      final tp = TextPainter(
        text: TextSpan(
          text: s.initials,
          style: TextStyle(
            color: s.onFill,
            fontSize: inner * 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(s.sizePx, s.sizePx);
    picture.dispose();
    photo?.dispose();
    return (
      image: image,
      photoFailed: url != null && url.isNotEmpty && photo == null,
    );
  }
}

/// [cacheKey] keeps the disk cache on the storage key: a signed URL is
/// different every time and would re-download the same thumbnail.
Future<ui.Image?> _networkImage(String url, {String? cacheKey}) {
  final completer = Completer<ui.Image?>();
  final stream = CachedNetworkImageProvider(
    url,
    cacheKey: cacheKey,
  ).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (_, __) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// One process-wide cache, so quick exit can clear it without a ref.
final sharedPinImageRenderer = PinImageRenderer();

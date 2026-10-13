/// Client mirror of the server's rich-text whitelist (spec §6.1,
/// migration 20261012200100 `planning_delta_attribute_ok`). The server
/// stays the authority; this exists so text pasted from other apps is
/// cleaned BEFORE save and the user never sees a rejection for
/// formatting they did not choose (Review Focus 4).
library;

const Set<String> planningPaletteTokens = {'yellow', 'green', 'blue', 'pink', 'purple'};

final RegExp _httpUrl = RegExp(r'^https?://\S+$', caseSensitive: false);

class SanitizedDelta {
  const SanitizedDelta(this.ops, {required this.changed});
  final List<Map<String, dynamic>> ops;

  /// True when anything the user could see was removed.
  final bool changed;
}

bool _allowed(String key, Object? value) => switch (key) {
      'bold' || 'italic' || 'underline' || 'strike' || 'blockquote' => value == true,
      'background' || 'color' => planningPaletteTokens.contains(value),
      // Named sizes only (Normal is no attribute): the same on every phone.
      'size' => value == 'small' || value == 'large' || value == 'huge',
      'header' => value == 1 || value == 2 || value == 3,
      'align' => value == 'center' || value == 'right' || value == 'justify',
      'list' => value == 'bullet' || value == 'ordered',
      'link' => value is String && value.length <= 2048 && _httpUrl.hasMatch(value),
      _ => false,
    };

SanitizedDelta sanitizeDelta(List<dynamic> input) {
  var changed = false;
  final out = <Map<String, dynamic>>[];
  for (final raw in input) {
    if (raw is! Map) {
      changed = true;
      continue;
    }
    final insert = raw['insert'];
    if (insert is! String) {
      changed = true; // embed
      continue;
    }
    final attrs = raw['attributes'];
    final kept = <String, dynamic>{};
    if (attrs is Map) {
      attrs.forEach((k, v) {
        if (v == null) return; // toggled-off attribute; invisible
        if (_allowed(k as String, v)) {
          kept[k] = v;
        } else {
          changed = true;
        }
      });
    }
    out.add({'insert': insert, if (kept.isNotEmpty) 'attributes': kept});
  }
  if (out.isEmpty || !(out.last['insert'] as String).endsWith('\n')) {
    out.add({'insert': '\n'});
  }
  return SanitizedDelta(out, changed: changed);
}

String deltaPlainText(List<Map<String, dynamic>> ops) =>
    ops.map((o) => o['insert'] as String).join().replaceFirst(RegExp(r'\n+$'), '');

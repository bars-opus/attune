// Anchor-lattice scene generator.
//
// The shape that survives §4.2b: routes reconverge BY DESTINATION STAR,
// so every incoming route has reached that star and the anchor advances.
// My first attempt reconverged by depth alone, which froze the anchor at
// the origin and could only draw a starburst.
//
// This is authoring scaffolding, not app code. An author picks a depth, a
// width and a star layout; the lattice structure is mechanical.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

void main(List<String> args) {
  final name = args.isNotEmpty ? args[0] : 'lattice';
  final depth = args.length > 1 ? int.parse(args[1]) : 12;
  final width = args.length > 2 ? int.parse(args[2]) : 2;
  final spread = args.length > 3 ? double.parse(args[3]) : 0.55;

  final stars = <Map<String, Object>>[
    {'id': 0, 'x': 0.5, 'y': 0.5},
  ];
  final laneStar = <String, int>{};
  var starId = 1;

  for (var d = 1; d <= depth; d++) {
    for (var k = 0; k < width; k++) {
      final angle = (k / width) * 2 * math.pi + d * spread;
      final radius = 0.07 + (d / depth) * 0.40;
      laneStar['$d:$k'] = starId;
      stars.add({
        'id': starId,
        'x': double.parse(
          (0.5 + radius * math.cos(angle)).clamp(0.03, 0.97).toStringAsFixed(4),
        ),
        'y': double.parse(
          (0.5 + radius * math.sin(angle)).clamp(0.03, 0.97).toStringAsFixed(4),
        ),
      });
      starId++;
    }
  }

  var layer = 0;
  List<int> take(int n) => [for (var i = 0; i < n; i++) layer++];

  final states = <String, Object>{};
  states['s00'] = {
    'common_layers': <int>[],
    'choices': [
      for (var k = 0; k < width; k++)
        {
          'id': 'c00_$k',
          'next': 's01_$k',
          'from': 0,
          'to': laneStar['1:$k'],
          'variant_layers': take(2),
        },
    ],
  };

  for (var d = 1; d < depth; d++) {
    for (var k = 0; k < width; k++) {
      states['s${d.toString().padLeft(2, '0')}_$k'] = {
        'common_layers': <int>[],
        'choices': [
          for (var j = 0; j < width; j++)
            {
              'id': 'c${d.toString().padLeft(2, '0')}_$k$j',
              'next': 's${(d + 1).toString().padLeft(2, '0')}_$j',
              'from': laneStar['$d:$k'],
              'to': laneStar['${d + 1}:$j'],
              'variant_layers': take(2),
            },
        ],
      };
    }
  }
  for (var k = 0; k < width; k++) {
    states['s${depth.toString().padLeft(2, '0')}_$k'] = {
      'common_layers': <int>[],
      'choices': <Object>[],
    };
  }

  final scene = {
    'version': name,
    'stars': stars,
    'origin_star': 0,
    'origin_state': 's00',
    'min_divergence': 4,
    'states': states,
  };

  final out = File('assets/constellation/scenes/$name.json');
  out.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(scene));
  stdout.writeln(
    'wrote ${out.path}: ${states.length} states, '
    '${stars.length} stars, depth $depth, width $width',
  );
}

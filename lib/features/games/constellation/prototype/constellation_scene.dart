import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A scene, loaded from the JSON the validator checks.
///
/// PROTOTYPE. CONSTELLATION_GAME_SPEC.md §4.4c found the lattice graph is
/// mechanical and the ART is the unmeasured budget. This build exists to
/// answer two things a spec cannot: does no-stakes cooperation feel worth
/// opening, and does a 92-layer scene read as a picture two people made
/// rather than a progress bar?
///
/// So there is no server, no session, no cursor. Turns alternate on one
/// device. Only the scene format and the rules survive into a real build.
@immutable
class SceneChoice {
  const SceneChoice({
    required this.id,
    required this.next,
    required this.fromStar,
    required this.toStar,
    required this.variantLayers,
  });

  final String id;
  final String next;
  final int fromStar;
  final int toStar;
  final List<int> variantLayers;
}

@immutable
class SceneState {
  const SceneState({required this.id, required this.choices});
  final String id;
  final List<SceneChoice> choices;
  bool get isTerminal => choices.isEmpty;
}

@immutable
class Star {
  const Star(this.id, this.x, this.y);
  final int id;
  final double x;
  final double y;
}

@immutable
class Scene {
  const Scene({
    required this.version,
    required this.stars,
    required this.originStar,
    required this.originState,
    required this.states,
  });

  final String version;
  final Map<int, Star> stars;
  final int originStar;
  final String originState;
  final Map<String, SceneState> states;

  /// Total turns: every route is the same length (§4.3), so walking one
  /// route is enough.
  int get depth {
    var n = 0;
    var id = originState;
    while (!states[id]!.isTerminal) {
      id = states[id]!.choices.first.next;
      n++;
    }
    return n;
  }

  static Future<Scene> load(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final stars = <int, Star>{};
    for (final s in (json['stars'] as List).cast<Map<String, dynamic>>()) {
      stars[s['id'] as int] = Star(
        s['id'] as int,
        (s['x'] as num).toDouble(),
        (s['y'] as num).toDouble(),
      );
    }

    final states = <String, SceneState>{};
    (json['states'] as Map<String, dynamic>).forEach((id, raw) {
      final entry = raw as Map<String, dynamic>;
      states[id] = SceneState(
        id: id,
        choices: ((entry['choices'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(
              (c) => SceneChoice(
                id: c['id'] as String,
                next: c['next'] as String,
                fromStar: c['from'] as int,
                toStar: c['to'] as int,
                variantLayers: (c['variant_layers'] as List).cast<int>(),
              ),
            )
            .toList(growable: false),
      );
    });

    return Scene(
      version: json['version'] as String,
      stars: stars,
      originStar: json['origin_star'] as int,
      originState: json['origin_state'] as String,
      states: states,
    );
  }
}

/// Which partner. Slots, not user ids — §8.1.
enum Slot {
  a,
  b;

  Slot get other => this == Slot.a ? Slot.b : Slot.a;
}

/// One committed choice.
@immutable
class Move {
  const Move({required this.choice, required this.slot});
  final SceneChoice choice;
  final Slot slot;
}

/// The session, in memory. No server, no persistence.
@immutable
class SessionState {
  const SessionState({
    required this.scene,
    required this.currentState,
    required this.moves,
    required this.turn,
  });

  final Scene scene;
  final String currentState;
  final List<Move> moves;
  final Slot turn;

  factory SessionState.start(Scene scene) => SessionState(
    scene: scene,
    currentState: scene.originState,
    moves: const [],
    // §5.3: the invitee moves first. Slot A stands in for them here.
    turn: Slot.a,
  );

  List<SceneChoice> get offered => scene.states[currentState]!.choices;
  bool get isComplete => scene.states[currentState]!.isTerminal;
  int get movesPlayed => moves.length;

  /// Every layer revealed so far, in the order it was revealed — which is
  /// what the completion animation replays (§7.3).
  List<({int layer, Slot slot})> get revealedInOrder => [
    for (final m in moves)
      for (final l in m.choice.variantLayers) (layer: l, slot: m.slot),
  ];

  SessionState take(SceneChoice choice) => SessionState(
    scene: scene,
    currentState: choice.next,
    moves: [...moves, Move(choice: choice, slot: turn)],
    turn: turn.other,
  );
}

/// Layer geometry, derived from the line its choice draws.
///
/// THE HONEST PART OF THIS PROTOTYPE. Real scenes will ship hand-authored
/// `.vec` layers (§8.1); 92 of them do not exist and drawing them is the
/// budget §4.4c says is unmeasured. So the prototype derives a plausible
/// mark from each choice's own line — a filament and a bloom — purely to
/// find out whether the ASSEMBLED picture reads as something two people
/// made. It answers "does the shape of the game work", not "is the art
/// good".
class LayerGeometry {
  const LayerGeometry._();

  /// A deterministic pseudo-random in [0,1) from a layer id, so the same
  /// layer always draws the same mark.
  static double _noise(int layer, int salt) {
    final h = (layer * 2654435761 + salt * 40503) & 0x7fffffff;
    return (h % 10000) / 10000.0;
  }

  /// Filaments radiating from the line's midpoint, perpendicular-ish, so
  /// the mark belongs to the line that made it.
  static List<({double x1, double y1, double x2, double y2})> strokes(
    int layer,
    Star from,
    Star to,
  ) {
    final angle = math.atan2(to.y - from.y, to.x - from.x);
    final count = 2 + (_noise(layer, 1) * 3).floor();
    final out = <({double x1, double y1, double x2, double y2})>[];

    for (var i = 0; i < count; i++) {
      // Along the line, biased away from the endpoints so filaments do
      // not pile up on the stars.
      final t = 0.25 + _noise(layer, 10 + i) * 0.5;
      final ox = from.x + (to.x - from.x) * t;
      final oy = from.y + (to.y - from.y) * t;

      final spread = (_noise(layer, 20 + i) - 0.5) * 1.6;
      final len = 0.02 + _noise(layer, 30 + i) * 0.06;
      final a = angle + math.pi / 2 + spread;

      out.add((
        x1: ox,
        y1: oy,
        x2: ox + math.cos(a) * len,
        y2: oy + math.sin(a) * len,
      ));
    }
    return out;
  }
}

// Constellation scene validator.
//
// THE GATE. CONSTELLATION_GAME_SPEC.md §4.5 says three scenes get
// authored and validated before any server code, to find out whether the
// content model is practical or too expensive. This is the tool that
// makes "validated" mean something.
//
// Every rule here is from §4.2, §4.2b, §4.3, §4.4 and §4.4a. The SQL
// validator will need the identical logic; this exists first because
// authoring three scenes against a spec with no checker is how you
// discover on day twelve that the format cannot express anything.
//
// Deliberately NOT in lib/: this is authoring tooling, not app code.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

// ---------------------------------------------------------------------
// Format bounds (§4.4a)
// ---------------------------------------------------------------------
const int kMaxStates = 64;
const int kMaxChoicesPerScene = 160;
const int kMaxStars = 64;
const int kMaxLayers = 512;
const int kMinDepth = 12;
const int kMaxDepth = 20;
const int kMaxBlobBytes = 64 * 1024;
const int kMaxIdLength = 32;
const int kMinDivergenceFloor = 3;
final RegExp kIdPattern = RegExp(r'^[a-z0-9_]{1,32}$');

class SceneError {
  SceneError(this.rule, this.message);
  final String rule;
  final String message;
  @override
  String toString() => '[$rule] $message';
}

class Choice {
  Choice({
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

class SceneState {
  SceneState({
    required this.id,
    required this.commonLayers,
    required this.choices,
  });
  final String id;
  final List<int> commonLayers;
  final List<Choice> choices;
  bool get isTerminal => choices.isEmpty;
}

class Scene {
  Scene({
    required this.version,
    required this.stars,
    required this.originStar,
    required this.originState,
    required this.minDivergence,
    required this.states,
  });

  final String version;
  final Map<int, ({double x, double y})> stars;
  final int originStar;
  final String originState;
  final int minDivergence;
  final Map<String, SceneState> states;

  /// Parses defensively and reports rather than throwing.
  ///
  /// §4.4a requires malformed JSON to fail with the scene-validation
  /// error rather than a raw cast or missing-key exception. The first
  /// version of this tool threw a raw cast exception on a scene missing
  /// its stars, which is exactly the
  /// unhelpful failure the spec says not to produce.
  static (Scene?, List<SceneError>) parse(Object? raw) {
    final errors = <SceneError>[];
    void fail(String rule, String message) =>
        errors.add(SceneError(rule, message));

    if (raw is! Map<String, dynamic>) {
      return (null, [SceneError('4.4a', 'scene is not a JSON object')]);
    }

    T? typed<T>(String key, String rule) {
      final v = raw[key];
      if (v is T) return v;
      fail(
        rule,
        v == null
            ? 'missing "$key"'
            : '"$key" is ${v.runtimeType}, expected $T',
      );
      return null;
    }

    final version = typed<String>('version', '4.4a') ?? '<unnamed>';
    final originStar = typed<int>('origin_star', '4.4.7');
    final originState = typed<String>('origin_state', '4.4.1');
    final minDivergence = typed<int>('min_divergence', '4.2');
    final rawStars = typed<List<dynamic>>('stars', '4.4.7');
    final rawStates = typed<Map<String, dynamic>>('states', '4.4.1');

    final stars = <int, ({double x, double y})>{};
    for (final entry in rawStars ?? const []) {
      if (entry is! Map<String, dynamic>) {
        fail('4.4.7', 'a star is not an object');
        continue;
      }
      final id = entry['id'];
      final x = entry['x'];
      final y = entry['y'];
      if (id is! int || x is! num || y is! num) {
        fail('4.4.7', 'star $id has a non-numeric id or coordinate');
        continue;
      }
      // Duplicates were silently overwritten by the first version, so a
      // scene with two star 7s validated against whichever won.
      if (stars.containsKey(id)) {
        fail('4.4.7', 'star id $id is declared more than once');
        continue;
      }
      stars[id] = (x: x.toDouble(), y: y.toDouble());
    }

    final states = <String, SceneState>{};
    (rawStates ?? const <String, dynamic>{}).forEach((id, entry) {
      if (entry is! Map<String, dynamic>) {
        fail('4.4.1', 'state "$id" is not an object');
        return;
      }
      final commonRaw = entry['common_layers'] ?? const [];
      final choicesRaw = entry['choices'] ?? const [];
      if (commonRaw is! List || choicesRaw is! List) {
        fail('4.4.1', 'state "$id" has a non-list common_layers or choices');
        return;
      }

      final common = <int>[];
      for (final l in commonRaw) {
        if (l is int) {
          common.add(l);
        } else {
          fail('4.4.6', 'state "$id" lists a non-integer common layer');
        }
      }

      final choices = <Choice>[];
      for (final c in choicesRaw) {
        if (c is! Map<String, dynamic>) {
          fail('4.4.3', 'state "$id" has a choice that is not an object');
          continue;
        }
        final cid = c['id'];
        final next = c['next'];
        final from = c['from'];
        final to = c['to'];
        final variantRaw = c['variant_layers'];
        if (cid is! String ||
            next is! String ||
            from is! int ||
            to is! int ||
            variantRaw is! List) {
          fail(
            '4.4.3',
            'state "$id" has a choice with a missing or mistyped field',
          );
          continue;
        }
        final variant = <int>[];
        for (final l in variantRaw) {
          if (l is int) {
            variant.add(l);
          } else {
            fail('4.4.6', 'choice "$cid" lists a non-integer variant layer');
          }
        }
        choices.add(
          Choice(
            id: cid,
            next: next,
            fromStar: from,
            toStar: to,
            variantLayers: variant,
          ),
        );
      }

      states[id] = SceneState(id: id, commonLayers: common, choices: choices);
    });

    if (originStar == null || originState == null || minDivergence == null) {
      return (null, errors);
    }

    return (
      Scene(
        version: version,
        stars: stars,
        originStar: originStar,
        originState: originState,
        minDivergence: minDivergence,
        states: states,
      ),
      errors,
    );
  }
}

/// Every rule, in one pass each. Returns the failures rather than
/// throwing on the first, so an author sees everything wrong at once.
List<SceneError> validate(Scene scene, {int blobBytes = 0}) {
  final errors = <SceneError>[];
  void fail(String rule, String message) =>
      errors.add(SceneError(rule, message));

  // ---- §4.4a format bounds ------------------------------------------
  if (scene.states.length > kMaxStates) {
    fail('4.4a', '${scene.states.length} states exceeds $kMaxStates');
  }
  if (scene.stars.length > kMaxStars) {
    fail('4.4a', '${scene.stars.length} stars exceeds $kMaxStars');
  }
  if (blobBytes > kMaxBlobBytes) {
    fail('4.4a', 'states blob is $blobBytes bytes, over $kMaxBlobBytes');
  }
  if (!kIdPattern.hasMatch(scene.version)) {
    fail('4.4a', 'version "${scene.version}" is not [a-z0-9_]{1,32}');
  }

  final allChoices = scene.states.values.expand((s) => s.choices).toList();
  if (allChoices.length > kMaxChoicesPerScene) {
    fail('4.4a', '${allChoices.length} choices exceeds $kMaxChoicesPerScene');
  }
  for (final c in allChoices) {
    if (!kIdPattern.hasMatch(c.id)) {
      fail('4.4a', 'choice id "${c.id}" is not [a-z0-9_]{1,32}');
    }
  }
  for (final id in scene.states.keys) {
    if (!kIdPattern.hasMatch(id)) {
      fail('4.4a', 'state id "$id" is not [a-z0-9_]{1,32}');
    }
  }

  // Choice ids unique SCENE-WIDE: moves store only choice_id, so a
  // duplicate makes history ambiguous.
  final seenChoice = <String>{};
  for (final c in allChoices) {
    if (!seenChoice.add(c.id)) {
      fail('4.4a', 'choice id "${c.id}" appears more than once');
    }
  }

  // Coordinates finite and inside the unit field.
  scene.stars.forEach((id, p) {
    if (!p.x.isFinite ||
        !p.y.isFinite ||
        p.x < 0 ||
        p.x > 1 ||
        p.y < 0 ||
        p.y > 1) {
      fail('4.4a', 'star $id at (${p.x}, ${p.y}) is outside [0,1]');
    }
  });

  // ---- §4.4 rule 7: stars exist ------------------------------------
  if (!scene.stars.containsKey(scene.originStar)) {
    fail('4.4.7', 'origin_star ${scene.originStar} does not exist');
  }
  for (final c in allChoices) {
    if (!scene.stars.containsKey(c.fromStar)) {
      fail('4.4.7', 'choice ${c.id} draws from missing star ${c.fromStar}');
    }
    if (!scene.stars.containsKey(c.toStar)) {
      fail('4.4.7', 'choice ${c.id} draws to missing star ${c.toStar}');
    }
    if (c.fromStar == c.toStar) {
      fail('4.4.7', 'choice ${c.id} is zero length');
    }
    if (!scene.states.containsKey(c.next)) {
      fail('4.4.2', 'choice ${c.id} leads to missing state "${c.next}"');
    }
  }
  // Sibling destinations distinct.
  for (final s in scene.states.values) {
    final dests = s.choices.map((c) => c.toStar).toList();
    if (dests.toSet().length != dests.length) {
      fail('4.4.7', 'state ${s.id} has siblings drawing to the same star');
    }
  }

  if (!scene.states.containsKey(scene.originState)) {
    fail('4.4.1', 'origin_state "${scene.originState}" does not exist');
    return errors; // Nothing below can run without an origin.
  }

  // ---- §4.4 rule 3: 2 or 3 choices, or terminal --------------------
  for (final s in scene.states.values) {
    if (s.choices.isNotEmpty &&
        s.choices.length != 2 &&
        s.choices.length != 3) {
      fail(
        '4.4.3',
        'state ${s.id} offers ${s.choices.length} choices; must be 2, 3 or 0',
      );
    }
  }

  // ---- §4.4 rules 5 and 6: layer ownership -------------------------
  // Every layer id owned exactly once scene-wide, by one state's common
  // bundle or one choice's variant bundle. The two namespaces cannot
  // overlap. This is what makes §4.2's divergence proof local.
  final layerOwner = <int, String>{};
  void claim(int layer, String owner) {
    final existing = layerOwner[layer];
    if (existing != null) {
      fail('4.4.6', 'layer $layer is owned by both $existing and $owner');
    } else {
      layerOwner[layer] = owner;
    }
  }

  for (final s in scene.states.values) {
    for (final l in s.commonLayers) {
      claim(l, 'common:${s.id}');
    }
    for (final c in s.choices) {
      if (c.variantLayers.length < 2) {
        fail(
          '4.2',
          'choice ${c.id} reveals ${c.variantLayers.length} variant layers; '
              'at least 2 required, or the divergence bound fails',
        );
      }
      if (c.variantLayers.toSet().length != c.variantLayers.length) {
        fail('4.4.6', 'choice ${c.id} lists a layer twice');
      }
      for (final l in c.variantLayers) {
        claim(l, 'variant:${c.id}');
      }
    }
  }
  if (layerOwner.length > kMaxLayers) {
    fail('4.4a', '${layerOwner.length} layers exceeds $kMaxLayers');
  }

  // ---- §4.2 divergence, proved locally -----------------------------
  // guaranteed = min over sibling pairs of (|a.variant| + |b.variant|).
  // Never enumerates outcomes: the memo's VALUE would grow exponentially
  // even where the state count does not (the second draft's mistake).
  int? guaranteed;
  for (final s in scene.states.values) {
    for (var i = 0; i < s.choices.length; i++) {
      for (var j = i + 1; j < s.choices.length; j++) {
        final v =
            s.choices[i].variantLayers.length +
            s.choices[j].variantLayers.length;
        guaranteed = guaranteed == null ? v : math.min(guaranteed, v);
      }
    }
  }
  if (scene.minDivergence < kMinDivergenceFloor) {
    fail(
      '4.2',
      'min_divergence ${scene.minDivergence} is below the floor of '
          '$kMinDivergenceFloor',
    );
  }
  if (guaranteed != null && scene.minDivergence > guaranteed) {
    fail(
      '4.2',
      'scene declares min_divergence ${scene.minDivergence} but its '
          'sibling bundles only guarantee $guaranteed',
    );
  }

  // ---- §4.4 rules 1 and 2: reachability and termination ------------
  final reachable = <String>{scene.originState};
  final stack = <String>[scene.originState];
  while (stack.isNotEmpty) {
    final st = scene.states[stack.removeLast()]!;
    for (final c in st.choices) {
      if (scene.states.containsKey(c.next) && reachable.add(c.next)) {
        stack.add(c.next);
      }
    }
  }
  for (final id in scene.states.keys) {
    if (!reachable.contains(id)) {
      fail('4.4.1', 'state $id is unreachable from the origin');
    }
  }

  // Acyclic: a cycle means a route that never terminates.
  final colour = <String, int>{}; // 0 white, 1 grey, 2 black
  bool hasCycle(String id) {
    final c = colour[id] ?? 0;
    if (c == 1) return true;
    if (c == 2) return false;
    colour[id] = 1;
    for (final ch in scene.states[id]!.choices) {
      if (scene.states.containsKey(ch.next) && hasCycle(ch.next)) return true;
    }
    colour[id] = 2;
    return false;
  }

  if (hasCycle(scene.originState)) {
    fail('4.4.2', 'the state machine contains a cycle');
    return errors; // Depth and dataflow below assume acyclicity.
  }

  // ---- §4.3 rule 1: one depth per state, even, in range ------------
  // Also §4.4 rule 4: depth-wide arity.
  final depth = <String, int>{scene.originState: 0};
  final order = <String>[];
  final indegree = <String, int>{for (final id in reachable) id: 0};
  for (final id in reachable) {
    for (final c in scene.states[id]!.choices) {
      if (reachable.contains(c.next)) indegree[c.next] = indegree[c.next]! + 1;
    }
  }
  final queue = <String>[scene.originState];
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    order.add(id);
    for (final c in scene.states[id]!.choices) {
      if (!reachable.contains(c.next)) continue;
      final d = depth[id]! + 1;
      final existing = depth[c.next];
      if (existing != null && existing != d) {
        fail(
          '4.3.1',
          'state ${c.next} is reachable at depth $existing and $d; '
              'one depth per state',
        );
      }
      depth[c.next] = d;
      indegree[c.next] = indegree[c.next]! - 1;
      if (indegree[c.next] == 0) queue.add(c.next);
    }
  }

  final terminalDepths =
      scene.states.values
          .where((s) => s.isTerminal)
          .map((s) => depth[s.id])
          .toSet();
  if (terminalDepths.length > 1) {
    fail('4.3.1', 'routes have unequal depth: $terminalDepths');
  } else if (terminalDepths.isNotEmpty) {
    final d = terminalDepths.first!;
    if (d.isOdd) {
      fail(
        '4.3.1',
        'depth $d is odd, so the invitee gets ${(d + 1) ~/ 2} decisions '
            'and their partner ${d ~/ 2}',
      );
    }
    if (d < kMinDepth || d > kMaxDepth) {
      fail('4.4a', 'depth $d is outside $kMinDepth-$kMaxDepth');
    }
  }

  // Depth-wide arity: all states at one depth offer the same count, so
  // the shape of what remains does not depend on the route taken.
  final arityByDepth = <int, Set<int>>{};
  for (final id in reachable) {
    (arityByDepth[depth[id]!] ??= <int>{}).add(
      scene.states[id]!.choices.length,
    );
  }
  arityByDepth.forEach((d, arities) {
    if (arities.length > 1) {
      fail('4.3.3', 'states at depth $d offer differing counts: $arities');
    }
  });

  // ---- §4.2b: from_star connectivity across reconvergence ----------
  // Forward dataflow to a fixed point: each successor receives its
  // predecessor's guaranteed set plus the chosen to_star, and a
  // reconverged state INTERSECTS all incoming sets. A from_star outside
  // that intersection draws a line from a star that route never made.
  final guaranteedStars = <String, Set<int>>{
    scene.originState: {scene.originStar},
  };
  for (final id in order) {
    final here = guaranteedStars[id];
    if (here == null) continue;
    for (final c in scene.states[id]!.choices) {
      if (!reachable.contains(c.next)) continue;
      final incoming = {...here, c.toStar};
      final existing = guaranteedStars[c.next];
      guaranteedStars[c.next] =
          existing == null ? incoming : existing.intersection(incoming);
    }
  }
  for (final id in order) {
    final here = guaranteedStars[id] ?? const <int>{};
    for (final c in scene.states[id]!.choices) {
      if (!here.contains(c.fromStar)) {
        fail(
          '4.2b',
          'choice ${c.id} draws from star ${c.fromStar}, which is not '
              'reached on every route into $id (guaranteed: ${here.toList()..sort()})',
        );
      }
    }
  }

  // §4.4.7, the half the first version of this tool never implemented:
  // a destination must not be POSSIBLY reachable already on any route in.
  // The guaranteed-star intersection above proves a line starts
  // somewhere real; this union proves it does not redraw a line that may
  // already exist. Same forward pass, union instead of intersection.
  final possibleStars = <String, Set<int>>{
    scene.originState: {scene.originStar},
  };
  for (final id in order) {
    final here = possibleStars[id];
    if (here == null) continue;
    for (final c in scene.states[id]!.choices) {
      if (!reachable.contains(c.next)) continue;
      if (here.contains(c.toStar)) {
        fail(
          '4.4.7',
          'choice ${c.id} draws to star ${c.toStar}, which may already '
              'have been reached on a route into $id',
        );
      }
      (possibleStars[c.next] ??= <int>{}).addAll({...here, c.toStar});
    }
  }

  return errors;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart tool/constellation/scene_validator.dart <scene.json>...',
    );
    exit(64);
  }

  var failed = 0;
  for (final path in args) {
    final raw = File(path).readAsStringSync();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      stdout.writeln('FAIL  $path');
      stdout.writeln('        [4.4a] not valid JSON: ${e.message}');
      failed++;
      continue;
    }

    final (scene, parseErrors) = Scene.parse(decoded);
    if (scene == null) {
      stdout.writeln('FAIL  $path');
      for (final e in parseErrors) {
        stdout.writeln('        $e');
      }
      failed++;
      continue;
    }
    final errors = [
      ...parseErrors,
      ...validate(scene, blobBytes: utf8.encode(raw).length),
    ];

    final states = scene.states.length;
    final choices = scene.states.values.fold<int>(
      0,
      (n, s) => n + s.choices.length,
    );

    if (errors.isEmpty) {
      stdout.writeln(
        'PASS  ${scene.version.padRight(16)} '
        '$states states, $choices choices, ${scene.stars.length} stars',
      );
    } else {
      failed++;
      stdout.writeln('FAIL  ${scene.version}');
      for (final e in errors) {
        stdout.writeln('        $e');
      }
    }
  }
  exit(failed == 0 ? 0 : 1);
}

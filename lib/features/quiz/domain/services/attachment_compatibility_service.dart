// lib/features/quiz/domain/services/attachment_compatibility_service.dart
//
// Deterministic attachment compatibility notes.
//
// Replaces the old client-side Claude stub (which returned one hardcoded note for
// every couple). A lookup table is the launch-correct design here: the attachment
// type set is bounded, so an LLM would add cost, latency, and prompt-injection
// risk for no benefit — and, crucially, the ATTACHMENT_STYLE_QUIZ constraints are
// GUARANTEED here by construction rather than merely hoped for from a model:
//   - never uses toxic / narcissist / codependent / disorder / broken
//   - watch_area describes the DYNAMIC, never blames either person
//   - warm, non-clinical pairing names
//
// The 9 quiz result types collapse to 4 canonical styles for pairing (secure,
// anxious, avoidant, fearful) — the clinically standard way attachment
// compatibility is discussed. That yields 10 unordered pairs, all covered below.

class AttachmentCompatibilityNote {
  final String pairingName;
  final String pairingDescription;
  final String naturalStrength;
  final String watchArea;

  const AttachmentCompatibilityNote({
    required this.pairingName,
    required this.pairingDescription,
    required this.naturalStrength,
    required this.watchArea,
  });

  Map<String, String> toMap() => {
        'pairing_name': pairingName,
        'pairing_description': pairingDescription,
        'natural_strength': naturalStrength,
        'watch_area': watchArea,
      };
}

class AttachmentCompatibilityService {
  const AttachmentCompatibilityService._();

  /// Collapse any of the 9 quiz result types to one of the 4 canonical styles.
  static String canonicalStyle(String type) {
    switch (type) {
      case 'secure':
      case 'fearful_secure': // "cautiously secure" — leans secure
        return 'secure';
      case 'anxious':
      case 'anxious_secure':
        return 'anxious';
      case 'avoidant':
      case 'secure_avoidant':
        return 'avoidant';
      case 'fearful':
      case 'anxious_avoidant':
      case 'avoidant_anxious':
        return 'fearful';
      default:
        return 'secure';
    }
  }

  /// Deterministic note for a pair of attachment types (order-independent).
  static AttachmentCompatibilityNote noteFor(String typeA, String typeB) {
    final a = canonicalStyle(typeA);
    final b = canonicalStyle(typeB);
    // Order-independent key: sort the two canonical styles.
    final key = ([a, b]..sort()).join('+');
    return _table[key] ?? _fallback;
  }

  static const AttachmentCompatibilityNote _fallback =
      AttachmentCompatibilityNote(
    pairingName: 'A dynamic worth learning',
    pairingDescription:
        'Two different ways of relating meet here — with attention, they can '
        'become a source of balance rather than friction.',
    naturalStrength:
        'Your differences give you range: each of you sees what the other '
        'might miss.',
    watchArea:
        'Notice how the pair handles distance and closeness when stress is high.',
  );

  // 10 unordered pairs over {secure, anxious, avoidant, fearful}.
  // Keys are the two canonical styles sorted and joined with '+'.
  static const Map<String, AttachmentCompatibilityNote> _table = {
    // --- same-style pairs ---
    'secure+secure': AttachmentCompatibilityNote(
      pairingName: 'Steady ground, shared',
      pairingDescription:
          'Two grounded styles meet here. Closeness and space both feel safe, '
          'and repair tends to come naturally after friction.',
      naturalStrength:
          'You can be honest without it feeling like a threat, which lets '
          'small issues stay small.',
      watchArea:
          'Comfort can drift into autopilot — the pair benefits from keeping '
          'curiosity alive.',
    ),
    'anxious+anxious': AttachmentCompatibilityNote(
      pairingName: 'Two hearts wide open',
      pairingDescription:
          'Both of you feel connection intensely and want reassurance it is '
          'mutual. When it flows, the closeness is deep and expressive.',
      naturalStrength:
          'Neither of you takes the relationship for granted — attentiveness '
          'runs in both directions.',
      watchArea:
          'When both nervous systems spike at once, the pair can amplify '
          'worry rather than settle it. Naming it early helps.',
    ),
    'avoidant+avoidant': AttachmentCompatibilityNote(
      pairingName: 'Two who value space',
      pairingDescription:
          'Both of you prize independence and a calm, low-pressure rhythm. '
          'There is real ease when neither is demanding more than the other '
          'wants to give.',
      naturalStrength:
          'You give each other room without taking it personally, which few '
          'pairings manage so naturally.',
      watchArea:
          'The pair can drift toward parallel lives — closeness may need to be '
          'chosen deliberately, since neither instinctively reaches first.',
    ),
    'fearful+fearful': AttachmentCompatibilityNote(
      pairingName: 'Tender and true',
      pairingDescription:
          'Both of you want closeness and also feel its risks. When trust is '
          'built patiently, the understanding between you can run unusually '
          'deep.',
      naturalStrength:
          'Each of you recognises the other\'s push-pull from the inside, so '
          'there is room for real compassion.',
      watchArea:
          'Cycles of reaching and retreating can sync up. The pair does best '
          'with predictable rhythms and slow, steady reassurance.',
    ),
    // --- mixed pairs ---
    'anxious+secure': AttachmentCompatibilityNote(
      pairingName: 'The anchor and the tide',
      pairingDescription:
          'One brings steady reassurance, the other brings depth of feeling. '
          'Together this often becomes a calming, expressive balance.',
      naturalStrength:
          'Steadiness meets emotional attentiveness — each softens the other\'s '
          'edges over time.',
      watchArea:
          'When reassurance is needed and offered too routinely, it can lose '
          'meaning. Freshness in how care is shown keeps it real.',
    ),
    'avoidant+secure': AttachmentCompatibilityNote(
      pairingName: 'Open door, steady room',
      pairingDescription:
          'One offers easy closeness, the other a calm need for space. A secure '
          'presence often makes independence feel safe rather than distant.',
      naturalStrength:
          'Space is respected without it reading as rejection, which lets '
          'closeness happen on its own terms.',
      watchArea:
          'The pair can let distance stretch quietly — checking in before it '
          'grows keeps the connection warm.',
    ),
    'fearful+secure': AttachmentCompatibilityNote(
      pairingName: 'Safe harbour, slow trust',
      pairingDescription:
          'One brings groundedness, the other brings a longing for closeness '
          'held alongside caution. Consistency here can be quietly healing.',
      naturalStrength:
          'A steady presence gives the more guarded style room to lower its '
          'defences at its own pace.',
      watchArea:
          'Trust builds slowly and can wobble under stress — the pair does well '
          'with patience and predictable follow-through.',
    ),
    'anxious+avoidant': AttachmentCompatibilityNote(
      pairingName: 'The reach and the pause',
      pairingDescription:
          'One instinctively moves toward closeness, the other toward space. '
          'It is a common and workable pairing when the rhythm is understood '
          'rather than fought.',
      naturalStrength:
          'Each can stretch the other\'s range — toward more closeness, and '
          'toward more ease with independence.',
      watchArea:
          'Under stress the pair can fall into a pursue-and-withdraw loop. '
          'Spotting the pattern together defuses it faster than pushing through.',
    ),
    'anxious+fearful': AttachmentCompatibilityNote(
      pairingName: 'Deep feeling, held with care',
      pairingDescription:
          'Both of you experience connection vividly; one leans toward reaching, '
          'the other between reaching and retreating. There is real emotional '
          'richness here.',
      naturalStrength:
          'Neither of you is indifferent — the relationship gets genuine '
          'emotional investment from both sides.',
      watchArea:
          'Intensity can build quickly for the pair. Steady pacing and clear, '
          'kind signals keep it grounding rather than overwhelming.',
    ),
    'avoidant+fearful': AttachmentCompatibilityNote(
      pairingName: 'Space and the wish for more',
      pairingDescription:
          'One leans toward independence, the other holds both a wish for '
          'closeness and a caution about it. With clarity, the pair can find a '
          'comfortable middle.',
      naturalStrength:
          'Both of you understand the need for room, so space rarely feels '
          'like a rejection.',
      watchArea:
          'Closeness may need to be named out loud — left unspoken, the pair '
          'can quietly drift further apart than either intends.',
    ),
  };
}

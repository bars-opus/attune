// lib/features/conflict_translator/domain/services/translator_pattern_service.dart
//
// Spec 8 (plan review §3.5): the counted need insight is gone —
// nothing tallies how often a need came up. What is left is how a need
// reads, including the seventh (communal obligation; definition pending
// clinician sign-off).
String translatorNeedDisplay(String need) {
  switch (need) {
    case 'respect':
      return 'to be heard';
    case 'fairness':
      return 'to feel fairly treated';
    case 'affection':
      return 'to feel valued';
    case 'security':
      return 'to feel safe';
    case 'autonomy':
      return 'to have space';
    case 'rest':
      return 'for relief';
    case 'communal_obligation':
      return 'to honour family and community';
    default:
      return need;
  }
}

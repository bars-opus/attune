// lib/features/verdict/data/services/verdict_generator.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/services/evidence_registry.dart';

class VerdictGenerator {
  static const String _claudeUrl = 'https://api.anthropic.com/v1/messages';
  static const Duration _timeout = Duration(seconds: 10);

  final String _apiKey;
  final String _promptVersion = '1.0.0';
  final String _inputSchemaVersion = '1.0.0';
  final String _modelProvider = 'anthropic';
  final String _modelName = 'claude-3-5-sonnet-20241022';

  VerdictGenerator(this._apiKey);

  Future<Map<String, dynamic>?> generate({
    required String relationshipId,
    required EvidenceRegistry registry,
    required Map<String, dynamic> metadata,
  }) async {
    final context = _buildContext(registry, metadata);

    try {
      final response = await _callClaude(context);
      if (response == null) return null;

      // Validate response
      final validated = _validateResponse(response, registry);
      return validated;
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> _buildContext(EvidenceRegistry registry, Map<String, dynamic> metadata) {
    final evidenceSummary = registry.items.map((e) => {
          'evidence_id': e.id,
          'source_type': e.sourceType,
          'metric': e.metric,
          'value': e.value,
          'delta': e.delta,
          'sample_size': e.sampleSize,
          'framework_confidence': e.frameworkConfidence,
          'display_source': e.displaySource,
        }).toList();

    return {
      'metadata': metadata,
      'evidence': evidenceSummary,
      'evidence_count': evidenceSummary.length,
      'has_strength_evidence': registry.hasStrengthEvidence,
      'has_watch_area_evidence': registry.hasWatchAreaEvidence,
    };
  }

  Future<Map<String, dynamic>?> _callClaude(Map<String, dynamic> context) async {
    final systemPrompt = '''
ABSOLUTE CONSTRAINTS — these override all other instructions:

1. Never generate text that attributes a negative behaviour to a named or implied partner.
2. Never generate a sentence of form "[partner name] tends to X" where X is a negative or deficit behaviour.
3. Never use these words: toxic, narcissist, codependent, disorder, broken.
4. Never tell the user what to decide about the relationship.
5. Never diagnose. Observe patterns. Frame with agency.
6. Return ONLY valid JSON. No preamble. No markdown fences.
''';

    final userPrompt = '''
You are generating a monthly relationship verdict from structured data only.
You have NOT read raw messages. Do not reference anything not in the data below.

RELATIONSHIP CONTEXT:
Days together: ${context['metadata']['days_together'] ?? 'unknown'}
Eligible sessions: ${context['metadata']['sessions_count'] ?? 0}
Games completed: ${context['metadata']['games_count'] ?? 0}

EVIDENCE REGISTRY (use only these evidence IDs):
${jsonEncode(context['evidence'])}

Return ONLY valid JSON:
{
  "headline": string (max 20 words, specific to this relationship),
  "strengths": [
    { "title": string (max 12 words), "body": string (max 40 words), "evidence_ids": [string] }
  ],
  "watch_areas": [
    { "title": string (max 12 words), "body": string (max 40 words), "evidence_ids": [string] }
  ],
  "one_action": string (max 30 words, optional conversation starter),
  "one_action_evidence_ids": [string],
  "patterns_referenced": [string]
}

Rules:
- Headline must be specific to THIS data — never generic
- Every strength and watch area must cite its source (evidence_ids)
- one_action is a conversation starter — never therapy-speak
- Never use banned words
- Never tell the user what to decide
- Minimum 1 strength, maximum 3
- Minimum 1 watch area, maximum 3
- All evidence_ids must exist in the evidence registry above
''';

    try {
      final response = await http.post(
        Uri.parse(_claudeUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': _modelName,
          'max_tokens': 400,
          'system': systemPrompt,
          'messages': [{'role': 'user', 'content': userPrompt}],
        }),
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);
      final content = data['content']?[0]?['text'] ?? '';
      return jsonDecode(content.replaceAll(RegExp(r'```json|```'), '').trim());
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? _validateResponse(
    Map<String, dynamic> response,
    EvidenceRegistry registry,
  ) {
    // Validate schema
    if (response['headline'] == null || response['headline'].toString().isEmpty) {
      return null;
    }

    if (response['strengths'] == null || (response['strengths'] as List).isEmpty) {
      return null;
    }

    if (response['watch_areas'] == null || (response['watch_areas'] as List).isEmpty) {
      return null;
    }

    // Validate evidence IDs
    final allEvidenceIds = registry.items.map((e) => e.id).toSet();

    for (final strength in response['strengths'] as List) {
      final evidenceIds = List<String>.from(strength['evidence_ids'] ?? []);
      for (final id in evidenceIds) {
        if (!allEvidenceIds.contains(id)) {
          return null;
        }
      }
    }

    for (final watchArea in response['watch_areas'] as List) {
      final evidenceIds = List<String>.from(watchArea['evidence_ids'] ?? []);
      for (final id in evidenceIds) {
        if (!allEvidenceIds.contains(id)) {
          return null;
        }
      }
    }

    // Validate banned words
    const bannedWords = [
      'toxic', 'narcissist', 'codependent', 'disorder', 'broken',
      'you should', 'you must', 'you need to', 'your relationship is',
      'stay', 'leave', 'healthy', 'unhealthy',
    ];

    final text = jsonEncode(response).toLowerCase();
    for (final word in bannedWords) {
      if (text.contains(word)) {
        return null;
      }
    }

    return response;
  }
}

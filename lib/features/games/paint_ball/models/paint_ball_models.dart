// lib/features/games/paint_ball/models/paint_ball_models.dart

const Object _unset = Object();

Map<String, dynamic> _json(Map<String, dynamic>? json) =>
    Map<String, dynamic>.from(json ?? const <String, dynamic>{});

String? _asString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value?.toString();
}

bool _asBool(Map<String, dynamic> json, String key, [bool fallback = false]) {
  final value = json[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

int _asInt(Map<String, dynamic> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

DateTime? _asDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

List<T> _parseList<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) parser,
) {
  final raw = json[key];
  if (raw is! List) return <T>[];
  return raw
      .whereType<Map>()
      .map((item) => parser(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

// ============================================================
// Phase
// ============================================================
enum PaintBallGamePhase {
  lobby,
  waiting,
  playing,
  shotAnimating,
  knockout,
  ended,
}

// ============================================================
// Round
// ============================================================
class PaintBallRound {
  final int roundNumber;
  final String shotResult;
  final bool lifeLost;
  final DateTime createdAt;

  const PaintBallRound({
    required this.roundNumber,
    required this.shotResult,
    required this.lifeLost,
    required this.createdAt,
  });

  factory PaintBallRound.fromJson(Map<String, dynamic> json) {
    final data = _json(json);
    return PaintBallRound(
      roundNumber: _asInt(data, 'round_number'),
      shotResult: _asString(data, 'shot_result') ?? 'miss',
      lifeLost: _asBool(data, 'life_lost'),
      createdAt: _asDateTime(data, 'created_at') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'round_number': roundNumber,
      'shot_result': shotResult,
      'life_lost': lifeLost,
      'created_at': createdAt.toIso8601String(),
    };
  }

  PaintBallRound copyWith({
    int? roundNumber,
    String? shotResult,
    bool? lifeLost,
    DateTime? createdAt,
  }) {
    return PaintBallRound(
      roundNumber: roundNumber ?? this.roundNumber,
      shotResult: shotResult ?? this.shotResult,
      lifeLost: lifeLost ?? this.lifeLost,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// ============================================================
// Session State
// ============================================================
class PaintBallSessionState {
  final String sessionId;
  final String relationshipId;
  final String initiatorId;
  final String userAId;
  final String userBId;
  final String status;
  final String gameType;
  final String tone;
  final int currentRound;
  final int totalRoundsCompleted;
  final String? currentTurnUserId;
  final int livesA;
  final int livesB;
  final String? winnerUserId;
  final String? penaltyType;
  final String? penaltyStatus;
  final String? penaltyPromptId;
  final String? penaltyPromptSnapshot;
  final String? penaltySource;
  final bool penaltyAllowPartnerAuthored;
  final List<PaintBallRound> rounds;
  final bool isMyTurn;
  final bool isWinner;
  final bool isLoser;
  final bool existing;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? abandonedAt;
  final DateTime? createdAt;

  const PaintBallSessionState({
    required this.sessionId,
    required this.relationshipId,
    required this.initiatorId,
    required this.userAId,
    required this.userBId,
    required this.status,
    required this.gameType,
    required this.tone,
    required this.currentRound,
    required this.totalRoundsCompleted,
    required this.currentTurnUserId,
    required this.livesA,
    required this.livesB,
    required this.winnerUserId,
    required this.penaltyType,
    required this.penaltyStatus,
    required this.penaltyPromptId,
    required this.penaltyPromptSnapshot,
    required this.penaltySource,
    required this.penaltyAllowPartnerAuthored,
    required this.rounds,
    required this.isMyTurn,
    required this.isWinner,
    required this.isLoser,
    required this.existing,
    required this.startedAt,
    required this.completedAt,
    required this.abandonedAt,
    required this.createdAt,
  });

  factory PaintBallSessionState.fromJson(Map<String, dynamic> json) {
    final data = _json(json);
    return PaintBallSessionState(
      sessionId: _asString(data, 'session_id') ?? _asString(data, 'id') ?? '',
      relationshipId: _asString(data, 'relationship_id') ?? '',
      initiatorId: _asString(data, 'initiator_id') ?? '',
      userAId: _asString(data, 'user_a_id') ?? _asString(data, 'user_a') ?? '',
      userBId: _asString(data, 'user_b_id') ?? _asString(data, 'user_b') ?? '',
      status: _asString(data, 'status') ?? 'invited',
      gameType: _asString(data, 'game_type') ?? 'paint_ball',
      tone: _asString(data, 'tone') ?? 'playful',
      currentRound: _asInt(data, 'current_round', 1),
      totalRoundsCompleted: _asInt(data, 'total_rounds_completed'),
      currentTurnUserId: _asString(data, 'current_turn_user_id'),
      livesA: _asInt(data, 'lives_a', 3),
      livesB: _asInt(data, 'lives_b', 3),
      winnerUserId: _asString(data, 'winner_user_id'),
      penaltyType: _asString(data, 'penalty_type'),
      penaltyStatus: _asString(data, 'penalty_status'),
      penaltyPromptId: _asString(data, 'penalty_prompt_id'),
      penaltyPromptSnapshot: _asString(data, 'penalty_prompt_snapshot'),
      penaltySource: _asString(data, 'penalty_source'),
      penaltyAllowPartnerAuthored: _asBool(
        data,
        'penalty_allow_partner_authored',
      ),
      rounds: _parseList(
        data,
        'rounds',
        PaintBallRound.fromJson,
      ),
      isMyTurn: _asBool(data, 'is_my_turn'),
      isWinner: _asBool(data, 'is_winner'),
      isLoser: _asBool(data, 'is_loser'),
      existing: _asBool(data, 'existing'),
      startedAt: _asDateTime(data, 'started_at'),
      completedAt: _asDateTime(data, 'completed_at'),
      abandonedAt: _asDateTime(data, 'abandoned_at'),
      createdAt: _asDateTime(data, 'created_at'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'relationship_id': relationshipId,
      'initiator_id': initiatorId,
      'user_a_id': userAId,
      'user_b_id': userBId,
      'status': status,
      'game_type': gameType,
      'tone': tone,
      'current_round': currentRound,
      'total_rounds_completed': totalRoundsCompleted,
      'current_turn_user_id': currentTurnUserId,
      'lives_a': livesA,
      'lives_b': livesB,
      'winner_user_id': winnerUserId,
      'penalty_type': penaltyType,
      'penalty_status': penaltyStatus,
      'penalty_prompt_id': penaltyPromptId,
      'penalty_prompt_snapshot': penaltyPromptSnapshot,
      'penalty_source': penaltySource,
      'penalty_allow_partner_authored': penaltyAllowPartnerAuthored,
      'rounds': rounds.map((round) => round.toJson()).toList(growable: false),
      'is_my_turn': isMyTurn,
      'is_winner': isWinner,
      'is_loser': isLoser,
      'existing': existing,
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'abandoned_at': abandonedAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  PaintBallSessionState copyWith({
    String? sessionId,
    String? relationshipId,
    String? initiatorId,
    String? userAId,
    String? userBId,
    String? status,
    String? gameType,
    String? tone,
    int? currentRound,
    int? totalRoundsCompleted,
    Object? currentTurnUserId = _unset,
    int? livesA,
    int? livesB,
    Object? winnerUserId = _unset,
    Object? penaltyType = _unset,
    Object? penaltyStatus = _unset,
    Object? penaltyPromptId = _unset,
    Object? penaltyPromptSnapshot = _unset,
    Object? penaltySource = _unset,
    bool? penaltyAllowPartnerAuthored,
    List<PaintBallRound>? rounds,
    bool? isMyTurn,
    bool? isWinner,
    bool? isLoser,
    bool? existing,
    Object? startedAt = _unset,
    Object? completedAt = _unset,
    Object? abandonedAt = _unset,
    Object? createdAt = _unset,
  }) {
    return PaintBallSessionState(
      sessionId: sessionId ?? this.sessionId,
      relationshipId: relationshipId ?? this.relationshipId,
      initiatorId: initiatorId ?? this.initiatorId,
      userAId: userAId ?? this.userAId,
      userBId: userBId ?? this.userBId,
      status: status ?? this.status,
      gameType: gameType ?? this.gameType,
      tone: tone ?? this.tone,
      currentRound: currentRound ?? this.currentRound,
      totalRoundsCompleted: totalRoundsCompleted ?? this.totalRoundsCompleted,
      currentTurnUserId: identical(currentTurnUserId, _unset)
          ? this.currentTurnUserId
          : currentTurnUserId as String?,
      livesA: livesA ?? this.livesA,
      livesB: livesB ?? this.livesB,
      winnerUserId:
          identical(winnerUserId, _unset) ? this.winnerUserId : winnerUserId as String?,
      penaltyType:
          identical(penaltyType, _unset) ? this.penaltyType : penaltyType as String?,
      penaltyStatus: identical(penaltyStatus, _unset)
          ? this.penaltyStatus
          : penaltyStatus as String?,
      penaltyPromptId: identical(penaltyPromptId, _unset)
          ? this.penaltyPromptId
          : penaltyPromptId as String?,
      penaltyPromptSnapshot: identical(penaltyPromptSnapshot, _unset)
          ? this.penaltyPromptSnapshot
          : penaltyPromptSnapshot as String?,
      penaltySource: identical(penaltySource, _unset)
          ? this.penaltySource
          : penaltySource as String?,
      penaltyAllowPartnerAuthored:
          penaltyAllowPartnerAuthored ?? this.penaltyAllowPartnerAuthored,
      rounds: rounds ?? this.rounds,
      isMyTurn: isMyTurn ?? this.isMyTurn,
      isWinner: isWinner ?? this.isWinner,
      isLoser: isLoser ?? this.isLoser,
      existing: existing ?? this.existing,
      startedAt:
          identical(startedAt, _unset) ? this.startedAt : startedAt as DateTime?,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      abandonedAt: identical(abandonedAt, _unset)
          ? this.abandonedAt
          : abandonedAt as DateTime?,
      createdAt:
          identical(createdAt, _unset) ? this.createdAt : createdAt as DateTime?,
    );
  }

  bool get hasPendingPenalty => penaltyStatus == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isAbandoned => status == 'abandoned';
  bool get isActive => status == 'active';
  bool get isInvited => status == 'invited';

  int livesForUser(String? userId) {
    if (userId == null) return livesA;
    if (userId == userAId) return livesA;
    if (userId == userBId) return livesB;
    return livesA;
  }

  int opponentLivesForUser(String? userId) {
    if (userId == null) return livesB;
    if (userId == userAId) return livesB;
    if (userId == userBId) return livesA;
    return livesB;
  }

  bool isCurrentUserTurn(String? userId) {
    if (userId == null) return false;
    return currentTurnUserId == userId;
  }
}

// ============================================================
// Shot Result
// ============================================================
class PaintBallShotResult {
  final String sessionId;
  final int roundNumber;
  final String shotResult;
  final bool lifeLost;
  final int livesA;
  final int livesB;
  final String? currentTurnUserId;
  final bool knockout;
  final String? penaltyType;
  final String? penaltyPromptSnapshot;
  final bool existing;

  const PaintBallShotResult({
    required this.sessionId,
    required this.roundNumber,
    required this.shotResult,
    required this.lifeLost,
    required this.livesA,
    required this.livesB,
    required this.currentTurnUserId,
    required this.knockout,
    required this.penaltyType,
    required this.penaltyPromptSnapshot,
    required this.existing,
  });

  factory PaintBallShotResult.fromJson(Map<String, dynamic> json) {
    final data = _json(json);
    return PaintBallShotResult(
      sessionId: _asString(data, 'session_id') ?? '',
      roundNumber: _asInt(data, 'round_number'),
      shotResult: _asString(data, 'shot_result') ?? 'miss',
      lifeLost: _asBool(data, 'life_lost'),
      livesA: _asInt(data, 'lives_a', 3),
      livesB: _asInt(data, 'lives_b', 3),
      currentTurnUserId: _asString(data, 'current_turn_user_id'),
      knockout: _asBool(data, 'knockout'),
      penaltyType: _asString(data, 'penalty_type'),
      penaltyPromptSnapshot: _asString(data, 'penalty_prompt_snapshot'),
      existing: _asBool(data, 'existing'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'round_number': roundNumber,
      'shot_result': shotResult,
      'life_lost': lifeLost,
      'lives_a': livesA,
      'lives_b': livesB,
      'current_turn_user_id': currentTurnUserId,
      'knockout': knockout,
      'penalty_type': penaltyType,
      'penalty_prompt_snapshot': penaltyPromptSnapshot,
      'existing': existing,
    };
  }

  bool get isHit => shotResult == 'hit';
  bool get isMiss => shotResult == 'miss';
}

// ============================================================
// Create Session Request/Response
// ============================================================
class PaintBallCreateSessionRequest {
  final String relationshipId;
  final String tone;
  final String? idempotencyKey;
  final bool allowPartnerAuthored;

  const PaintBallCreateSessionRequest({
    required this.relationshipId,
    this.tone = 'playful',
    this.idempotencyKey,
    this.allowPartnerAuthored = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'relationship_id': relationshipId,
      'tone': tone,
      'idempotency_key': idempotencyKey,
      'allow_partner_authored': allowPartnerAuthored,
    };
  }
}

class PaintBallCreateSessionResponse {
  final String sessionId;
  final bool existing;

  const PaintBallCreateSessionResponse({
    required this.sessionId,
    required this.existing,
  });

  factory PaintBallCreateSessionResponse.fromJson(Map<String, dynamic> json) {
    final data = _json(json);
    return PaintBallCreateSessionResponse(
      sessionId: _asString(data, 'session_id') ?? '',
      existing: _asBool(data, 'existing'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'existing': existing,
    };
  }
}

// ============================================================
// Resolve Penalty Request
// ============================================================
class PaintBallResolvePenaltyRequest {
  final String sessionId;
  final String outcome;

  const PaintBallResolvePenaltyRequest({
    required this.sessionId,
    required this.outcome,
  });

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'outcome': outcome,
    };
  }
}

// ============================================================
// API Error Response
// ============================================================
class PaintBallApiError implements Exception {
  final bool error;
  final String code;
  final String message;

  const PaintBallApiError({
    required this.error,
    required this.code,
    required this.message,
  });

  factory PaintBallApiError.fromJson(Map<String, dynamic> json) {
    final data = _json(json);
    return PaintBallApiError(
      error: _asBool(data, 'error', true),
      code: _asString(data, 'code') ?? 'INTERNAL_ERROR',
      message: _asString(data, 'message') ?? 'Something went wrong.',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'error': error,
      'code': code,
      'message': message,
    };
  }

  @override
  String toString() => message;
}

// ============================================================
// Paint Ball UI State
// ============================================================
class PaintBallUiState {
  final PaintBallGamePhase phase;
  final bool isLoading;
  final bool isSubmitting;
  final String? errorMessage;
  final PaintBallSessionState? session;
  final bool showHitFeedback;
  final bool showMissFeedback;
  final bool showKnockout;

  const PaintBallUiState({
    this.phase = PaintBallGamePhase.lobby,
    this.isLoading = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.session,
    this.showHitFeedback = false,
    this.showMissFeedback = false,
    this.showKnockout = false,
  });

  PaintBallUiState copyWith({
    PaintBallGamePhase? phase,
    bool? isLoading,
    bool? isSubmitting,
    Object? errorMessage = _unset,
    Object? session = _unset,
    bool? showHitFeedback,
    bool? showMissFeedback,
    bool? showKnockout,
  }) {
    return PaintBallUiState(
      phase: phase ?? this.phase,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage:
          identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      session: identical(session, _unset) ? this.session : session as PaintBallSessionState?,
      showHitFeedback: showHitFeedback ?? this.showHitFeedback,
      showMissFeedback: showMissFeedback ?? this.showMissFeedback,
      showKnockout: showKnockout ?? this.showKnockout,
    );
  }

  bool get isGameActive =>
      phase == PaintBallGamePhase.playing ||
      phase == PaintBallGamePhase.shotAnimating;
  bool get isInKnockout => phase == PaintBallGamePhase.knockout;
  bool get hasError => errorMessage != null;
}

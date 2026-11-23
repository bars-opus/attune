import 'package:flutter/material.dart';

/// One mood a game of This or That can be played in.
@immutable
class ThisOrThatTone {
  const ThisOrThatTone({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  /// The `game_sessions.tone` value.
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

/// The tones, in the order they are offered: the tone screen's cards and
/// the landing page's rows.
const List<ThisOrThatTone> thisOrThatTones = [
  ThisOrThatTone(
    id: 'connecting',
    label: 'Connecting',
    description: 'Easy questions that bring you closer',
    icon: Icons.people_alt_rounded,
    color: Color(0xFF3F66D4),
  ),
  ThisOrThatTone(
    id: 'romantic',
    label: 'Romantic',
    description: 'Soft, affectionate, and a little dreamy',
    icon: Icons.favorite_rounded,
    color: Color(0xFFD94C65),
  ),
  ThisOrThatTone(
    id: 'playful',
    label: 'Playful',
    description: 'Silly choices and surprising debates',
    icon: Icons.celebration_rounded,
    color: Color(0xFFF09A36),
  ),
  ThisOrThatTone(
    id: 'spicy',
    label: 'Spicy',
    description: 'Flirty choices with extra heat',
    icon: Icons.local_fire_department_rounded,
    color: Color(0xFFE35843),
  ),
  ThisOrThatTone(
    id: 'intimate',
    label: 'Intimate',
    description: 'Deeper adult questions, with consent',
    icon: Icons.nights_stay_rounded,
    color: Color(0xFF7957C8),
  ),
];

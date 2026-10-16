import 'package:attune/core/config/env.dart';
import 'package:attune/core/providers/profile_providers/profile_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:attune/features/couple_map/presentation/map/mapbox_couple_map_view.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final coupleMapViewBuilderProvider = Provider<CoupleMapViewBuilder>(
  (ref) => mapboxCoupleMapViewBuilder,
);

/// Empty means no map: the list content shows in its place.
final coupleMapTokenProvider = Provider<String>(
  (ref) => Environment.mapboxAccessToken,
);

final pinImageRendererProvider = Provider<PinImageRenderer>(
  (ref) => sharedPinImageRenderer,
);

@immutable
class CoupleMapPeople {
  const CoupleMapPeople({
    this.selfUrl,
    required this.selfInitials,
    this.partnerUrl,
    required this.partnerInitials,
    required this.partnerName,
  });
  final String? selfUrl;
  final String selfInitials;
  final String? partnerUrl;
  final String partnerInitials;
  final String partnerName;
}

/// Names and avatars for the pins and the card. Never throws: a missing
/// profile shows initials.
final coupleMapPeopleProvider = FutureProvider.autoDispose
    .family<CoupleMapPeople, String>((ref, relationshipId) async {
      Future<T?> safe<T>(Future<T> f) async {
        try {
          return await f;
        } catch (_) {
          return null;
        }
      }

      final me = await safe(ref.watch(currentUserProfileProvider.future));
      final conversations =
          await safe(ref.watch(conversationsProvider.future)) ?? const [];
      final partnerConversation =
          conversations
              .where((c) => c.relationshipId == relationshipId)
              .firstOrNull;
      final partnerName =
          await safe(ref.watch(quiz.partnerNameProvider.future)) ??
          partnerConversation?.name;
      return CoupleMapPeople(
        selfUrl: me?.avatarUrl,
        selfInitials: initialsOf(me?.displayName ?? me?.username),
        partnerUrl: partnerConversation?.avatarUrl,
        partnerInitials: initialsOf(partnerName),
        partnerName: partnerName ?? 'your partner',
      );
    });

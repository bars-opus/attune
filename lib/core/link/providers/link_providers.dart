import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/link/models/link_models.dart';
import 'package:attune/core/link/service/link_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Provider for LinkConfig (override this in your app)
final linkConfigProvider = Provider<LinkConfig>((ref) {
  throw UnimplementedError('Override linkConfigProvider in your app');
});

// Provider for LinkService
final linkServiceProvider = Provider<LinkService>((ref) {
  final config = ref.watch(linkConfigProvider);
  final supabase = Supabase.instance.client;
  return LinkService(supabase, config);
});

// Provider for creating links
final createLinkProvider =
    FutureProvider.family<LinkCreationResult, CreateLinkParams>((
      ref,
      params,
    ) async {
      final service = ref.read(linkServiceProvider);

      switch (params.type) {
        case LinkType.shop:
          return await service.createShopLink(
            shopId: params.targetId,
            customSlug: params.customSlug,
            metadata: params.metadata,
          );
        case LinkType.worker:
          return await service.createWorkerLink(
            workerId: params.targetId,
            customSlug: params.customSlug,
            metadata: params.metadata,
          );
        case LinkType.booking:
          return await service.createBookingLink(
            bookingId: params.targetId,
            customSlug: params.customSlug,
            metadata: params.metadata,
          );
        case LinkType.campaign:
          return await service.createCampaignLink(
            campaignId: params.targetId,
            customSlug: params.customSlug,
            metadata: params.metadata,
          );
        default:
          throw Exception('Unsupported link type');
      }
    });

// Provider for getting a link by slug
final linkBySlugProvider = FutureProvider.family<ShortLink?, String>((
  ref,
  slug,
) async {
  final service = ref.read(linkServiceProvider);
  return await service.getLink(slug);
});

// Provider for user's links list
final userLinksProvider = FutureProvider<List<ShortLink>>((ref) async {
  final service = ref.read(linkServiceProvider);
  return await service.getUserLinks();
});

// Parameter class for creating links
class CreateLinkParams {
  final LinkType type;
  final String targetId;
  final String? customSlug;
  final Map<String, dynamic>? metadata;

  const CreateLinkParams({
    required this.type,
    required this.targetId,
    this.customSlug,
    this.metadata,
  });
}

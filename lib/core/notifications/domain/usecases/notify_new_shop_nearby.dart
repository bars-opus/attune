// lib/features/notifications/domain/usecases/notify_new_shop_nearby.dart
import 'package:equatable/equatable.dart';
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';

/// Parameters for notifying users about a new shop
class NotifyNewShopNearbyParams extends Equatable {
  final String shopId;
  final String shopName;
  final double latitude;
  final double longitude;
  final double radiusKm;

  const NotifyNewShopNearbyParams({
    required this.shopId,
    required this.shopName,
    required this.latitude,
    required this.longitude,
    this.radiusKm = 10,
  });

  @override
  List<Object?> get props => [shopId, shopName, latitude, longitude, radiusKm];
}

/// Use case for notifying nearby users about a new shop
class NotifyNewShopNearbyUseCase {
  final NotificationRepositoryInterface repository;

  NotifyNewShopNearbyUseCase(this.repository);

  Future<void> call(NotifyNewShopNearbyParams params) async {
    // Get nearby users
    final nearbyUserIds = await repository.getNearbyUsers(
      latitude: params.latitude,
      longitude: params.longitude,
      radiusKm: params.radiusKm,
    );

    // Send notification to each nearby user
    for (final userId in nearbyUserIds) {
      await repository.queueImmediateNotification(
        userId: userId,
        title: 'New Shop Nearby!',
        body: '${params.shopName} just opened near you. Check them out!',
        data: {
          'type': 'new_shop_nearby',
          'shop_id': params.shopId,
          'shop_name': params.shopName,
        },
        priority: 'normal',
      );
    }
  }
}

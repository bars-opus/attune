import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/location_provider.dart';
import 'package:attune/core/services/location_service.dart';
import 'package:attune/core/utils/location/map_launcher_helper.dart';
import 'package:attune/core/utils/location/widgets/location_display_widget.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:gap/gap.dart';

class RoutePreviewWidget extends ConsumerWidget {
  final double shopLat;
  final double shopLng;
  final String? shopName;
  final String? shopAddress;

  const RoutePreviewWidget({
    super.key,
    required this.shopLat,
    required this.shopLng,
    this.shopName,
    this.shopAddress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get user location from existing provider
    final userLocation = ref.watch(userLocationNotifierProvider);
    final distanceToShop = ref.watch(distanceToShopProvider(shopLat, shopLng));

    // Check if we have a user location
    final hasLocation = userLocation != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Gap(Spacing.sm.h),
        // Location Info
        if (!hasLocation)
          _noLocation(context)
        else
          _buildLocationInfo(context, userLocation!, distanceToShop, ref),
        Gap(Spacing.lg.h),
        // Action Buttons
        AppButton(
          height: 35.h,
          // iconData: Icons.send,
          label: 'Launch map',
          onPressed: () {
            if (!kIsWeb && Platform.isIOS) {
              _openAppleMaps(context);
            } else {
              _openGoogleMaps(context);
            }
          },
          padding: Spacing.horizontalMd,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          width: double.infinity,
          elevation: 0,
        ),
      ],
    );
  }

  _noLocation(BuildContext context) {
    return Column(
      children: [
        const LocationDisplayWidget(),
        _buildLocationRow(
          context,
          icon: Icons.location_on,
          label: shopName ?? 'Shop',
          value:
              shopAddress ??
              '${shopLat.toStringAsFixed(6)}, ${shopLng.toStringAsFixed(6)}',
        ),
      ],
    );
  }

  Widget _buildLocationInfo(
    BuildContext context,
    dynamic userLocation,
    double? distance,
    WidgetRef ref,
  ) {
    // In your RoutePreviewWidget, where you show distance and ETA
    if (distance != null) {
      final carTime = LocationService().getEstimatedTravelTime(distance, 'car');
      final walkTime = LocationService().getEstimatedTravelTime(
        distance,
        'walk',
      );

     

      // Display in UI
      Text('${distance.toStringAsFixed(1)} km');
      Text('$carTime by car');
      Text('$walkTime walking');
    }
    return Column(
      children: [
       
        _buildLocationRow(
          context,
          icon: Icons.location_on,
          label: shopName ?? 'Shop',
          value:
              shopAddress ??
              '${shopLat.toStringAsFixed(6)}, ${shopLng.toStringAsFixed(6)}',
        ),
        Gap(Spacing.sm.h),
        // Distance & ETA
        if (distance != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _distanceWidget(
                context,
                '${distance.toStringAsFixed(1)} km',
                'Distance',
                Icons.straighten,
              ),
              _verticalDivider(),
              _distanceWidget(
                context,
                _estimateTravelTime(distance, 'car'),
                'By car',
                Icons.directions_car,
              ),

              _verticalDivider(),
              _distanceWidget(
                context,
                _estimateTravelTime(distance, 'walk'),
                'Walking',
                Icons.directions_walk,
              ),
            ],
          ),
      ],
    );
  }

  _verticalDivider() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: Spacing.xs),
      width: 1,
      height: 40.h,
      color: Colors.grey.withOpacity(0.2),
    );
  }

  _distanceWidget(
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20.h, color: colorScheme.primary),
          Gap(4.h),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onBackground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onBackground.withOpacity(.5),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return InfoRowWidget(
      subtitle: label,
      titleMaxLines: 1,
      title: value,
      icon: icon,
      avatarRadius: 25.h,
      onTap: () {},
      disableTrailing: true,
      showAvatar: false,
      showTrailingArrow: false,
    );
  }

  String _estimateTravelTime(double distanceKm, String mode) {
    final double carSpeed = 40; // km/h city driving
    final double walkingSpeed = 5; // km/h walking
    final double speed = mode == 'car' ? carSpeed : walkingSpeed;
    final double hours = distanceKm / speed;
    final int minutes = (hours * 60).round();

    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} hr ${minutes % 60} min';
  }

  Future<void> _setCurrentLocation(WidgetRef ref, dynamic context) async {
    final notifier = ref.read(userLocationNotifierProvider.notifier);
    final success = await notifier.setCurrentLocation();

    if (success && context.mounted) {
      context.showSuccessSnackbar('Location updated successfully');
    } else if (context.mounted) {
      context.showSuccessSnackbar('Location updated successfully');
    }
  }

  void _openGoogleMaps(BuildContext context) {
    MapLauncherHelper.openMapLocation(
      lat: shopLat,
      lng: shopLng,
      address: shopAddress,
      label: shopName,
    );
  }

  void _openAppleMaps(BuildContext context) {
    MapLauncherHelper.openMapLocation(
      lat: shopLat,
      lng: shopLng,
      address: shopAddress,
      label: shopName,
    );
  }
}

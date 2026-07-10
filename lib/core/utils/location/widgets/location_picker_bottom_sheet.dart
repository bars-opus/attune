import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/location/location_search_mode.dart';

class LocationPickerBottomSheet extends ConsumerStatefulWidget {
  final Function(ParsedAddress)? onLocationSelected;

  /// Controls what kind of location is being picked and how the result is used.
  ///
  /// - [LocationSearchMode.city]    → client personal discovery location; shows
  ///   the saved user location and writes to [userLocationNotifierProvider].
  /// - [LocationSearchMode.address] → shop / freelancer address; does NOT read or
  ///   mutate [userLocationNotifierProvider].
  final LocationSearchMode mode;

  const LocationPickerBottomSheet({
    super.key,
    this.onLocationSelected,
    this.mode = LocationSearchMode.city,
  });

  @override
  ConsumerState<LocationPickerBottomSheet> createState() =>
      _LocationPickerBottomSheetState();
}

class _LocationPickerBottomSheetState
    extends ConsumerState<LocationPickerBottomSheet> {
  bool _isLoading = false;

  bool get _isAddressMode => widget.mode == LocationSearchMode.address;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final userLocation =
        _isAddressMode ? null : ref.watch(userLocationNotifierProvider);

    return Column(
      children: [
        AppTextButton(text: 'Done', onPressed: () => Navigator.pop(context)),
        Gap(Spacing.lg.h),
        if (!_isAddressMode && userLocation != null) ...[
          HighlightContainer(
            child: InfoRowWidget(
              title: userLocation.displayName,
              subtitle: 'Current location',
              icon: Icons.location_on,
              iconColor: colorScheme.surface,
              avatarRadius: 25.h,
              onTap: _setCurrentLocation,
              showDivider: false,
              backgroundColor: colorScheme.primary.withValues(alpha: 1),
              showTrailingArrow: false,
              trailing: AppIconButton(
                onPressed: () {
                  BottomSheetUtils.showDocumentationBottomSheet(
                    maxHeight: 350.h,
                    context: context,
                    widget: ConfirmationDialog(
                      type: ConfirmationType.warning,
                      title:
                          'Are you sure you want to remove this location: ${userLocation.displayName}',
                      message: '',
                      confirmText: 'Remove location',
                      onConfirm: () {
                        _clearLocation();
                      },
                    ),
                  );
                },
                icon: Icons.close,
              ),
            ),
          ),
        ],

        Gap(Spacing.lg.h),

        InfoRowWidget(
          title: 'Use current location',
          subtitle: '',
          icon: Icons.my_location,
          avatarRadius: 25.h,
          onTap: _setCurrentLocation,
          showAvatar: false,
          showDivider: false,
          showTrailingArrow: false,
          trailing: _isLoading ? CircularLoadingIndicator() : null,
        ),

        Gap(Spacing.md.h),
        AppDivider(),
        Gap(Spacing.md.h),

        InfoRowWidget(
          title: _isAddressMode ? 'Search for address' : 'Search for city',
          subtitle: '',
          icon: Icons.search,
          avatarRadius: 25.h,
          showDivider: false,
          onTap: _openSearchScreen,
          showAvatar: false,
          showTrailingArrow: true,
        ),

        Gap(Spacing.xl.h),
      ],
    );
  }

  Future<void> _setCurrentLocation() async {
    setState(() => _isLoading = true);

    try {
      if (_isAddressMode) {
        // Shop / freelancer: get GPS and hand the result to the caller.
        final parsedAddress = await ref
            .read(locationServiceProvider)
            .getCurrentLocationWithDetails();

        if (mounted) {
          setState(() => _isLoading = false);
          if (parsedAddress != null) {
            widget.onLocationSelected?.call(parsedAddress);
            Navigator.pop(context);
            context.showSuccessSnackbar('Location updated successfully');
          } else {
            context.showErrorSnackbar('Failed to get location. Please try again.');
          }
        }
      } else {
        // Personal browsing location: the notifier handles GPS + persistence
        // + currency detection in one call.
        final success = await ref
            .read(userLocationNotifierProvider.notifier)
            .setCurrentLocation();

        if (mounted) {
          setState(() => _isLoading = false);
          if (success) {
            Navigator.pop(context);
            context.showSuccessSnackbar('Location updated successfully');
          } else {
            context.showErrorSnackbar('Failed to get location. Please try again.');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        context.showErrorSnackbar('Error: $e');
      }
    }
  }

  Future<void> _openSearchScreen() async {
    final selectedAddress = await context.push<ParsedAddress>(
      '/locationSearchScreen',
      extra: widget.mode,
    );

    if (selectedAddress != null && mounted) {
      if (widget.onLocationSelected != null) {
        widget.onLocationSelected!(selectedAddress);
      }
      Navigator.pop(context);
    }
  }

  Future<void> _clearLocation() async {
    await ref.read(userLocationNotifierProvider.notifier).clearLocation();
    if (mounted) {
      Navigator.pop(context);
      setState(() {});
    }
  }
}

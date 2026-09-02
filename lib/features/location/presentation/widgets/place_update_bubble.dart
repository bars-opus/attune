import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

/// A place a partner chose to share.
///
/// Tapping opens a map at that spot. The map is a DESTINATION, never the
/// surface: the app shows where someone said they were, not where they
/// are -- and only because they said so.
class PlaceUpdateBubble extends StatelessWidget {
  const PlaceUpdateBubble({
    super.key,
    required this.label,
    this.note,
    this.latitude,
    this.longitude,
    this.foregroundColor,
  });

  final String label;
  final String? note;
  final double? latitude;
  final double? longitude;
  final Color? foregroundColor;

  bool get _hasCoordinates => latitude != null && longitude != null;

  Future<void> _openMap() async {
    if (!_hasCoordinates) return;
    // A geo: query rather than a pin drop, so the map opens on the place
    // by name where the platform can resolve it.
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=$latitude,$longitude',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colour =
        foregroundColor ?? Theme.of(context).colorScheme.onSurface;

    return Semantics(
      button: _hasCoordinates,
      label: 'Shared a place: $label',
      child: InkWell(
        onTap: _hasCoordinates ? _openMap : null,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.place_rounded, size: 20.h, color: colour),
            SizedBox(width: Spacing.sm.w),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colour,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note != null && note!.trim().isNotEmpty)
                    Text(
                      note!,
                      style: textTheme.bodySmall?.copyWith(
                        color: colour.withValues(alpha: 0.75),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

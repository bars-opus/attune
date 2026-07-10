import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

class LocationDisplayWidget extends ConsumerWidget {
  const LocationDisplayWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final userLocation = ref.watch(userLocationNotifierProvider);
    return GestureDetector(
      onTap: () {
        BottomSheetUtils.showDocumentationBottomSheet(
          maxHeight: 400.h,
          context: context,
          widget: LocationPickerBottomSheet(),
        );
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 200.w),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Icon(Icons.location_on, size: 16.sp, color: colorScheme.onBackground),
            Flexible(
              child: Text(
                userLocation?.displayName ?? 'Set location',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Gap(Spacing.xs.w),
            Icon(
              Icons.keyboard_arrow_down_sharp,
              size: 16.h,
              color: colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

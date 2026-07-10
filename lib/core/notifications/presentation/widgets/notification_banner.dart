// lib/features/notifications/presentation/widgets/notification_banner.dart
import 'package:attune/core/utils/exports/export_screens.dart';

/// In-app notification banner that slides from top
class NotificationBanner {
  static OverlayEntry? _currentEntry;
  
  /// Show a temporary notification banner
  static void show({
    required BuildContext context,
    required String title,
    required String message,
    IconData? icon,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    // Remove existing banner if any
    hide();
    
    final overlay = Overlay.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: GestureDetector(
              onTap: () {
                hide();
                onTap?.call();
              },
              child: Container(
                margin: EdgeInsets.symmetric(
                  horizontal: Spacing.md.w,
                  vertical: Spacing.sm.h,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: Spacing.md.w,
                  vertical: Spacing.md.h,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:0.1),
                      blurRadius: 8.r,
                      offset: Offset(0, 2.h),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (icon != null)
                      Container(
                        width: 40.w,
                        height: 40.w,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          color: colorScheme.primary,
                          size: 20.w,
                        ),
                      ),
                    if (icon != null) Gap(Spacing.md.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Gap(Spacing.xs.h),
                          Text(
                            message,
                            style: textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 16.w,
                        color: colorScheme.onSurface.withValues(alpha:0.5),
                      ),
                      onPressed: hide,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(_currentEntry!);
    
    // Auto hide after duration
    Future.delayed(duration, () {
      if (_currentEntry != null) {
        hide();
      }
    });
  }
  
  /// Hide the current notification banner
  static void hide() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

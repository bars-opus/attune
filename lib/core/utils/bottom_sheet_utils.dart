import 'package:attune/app/documentations/legal_documentation/models/documentation_item.dart';
import 'package:attune/app/documentations/legal_documentation/widgets/legal_documentation_modal_sheet.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/circular_documentation_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class BottomSheetUtils {
  static Future<T?> showDocumentationBottomSheet<T>({
    required BuildContext context,
    DocumentationItem? document,
    VoidCallback? onAgree,
    VoidCallback? onDecline,
    String agreeButtonText = 'I Agree',
    String declineButtonText = 'Decline',
    bool showButtons = true,
    bool isDismissible = true,
    bool enableDrag = true,
    double? maxHeight,
    Widget? widget,
    Color? backgroundColor,
    double? padding,
  }) async {
    assert(
      document != null || widget != null,
      'Either document or widget must be provided',
    );
    assert(
      document == null || widget == null,
      'Cannot provide both document and widget parameters',
    );

    final sheetMaxHeight =
        maxHeight ?? MediaQuery.of(context).size.height * 0.9;
    final contentPadding = padding ?? Spacing.xl.h;

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      // DraggableScrollableSheet owns all drag handling below.
      // Keeping enableDrag: true here would create two competing gesture
      // recognisers and break the drag-to-dismiss on scrollable content.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxHeight: sheetMaxHeight),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;

        return DraggableScrollableSheet(
          initialChildSize: 1.0,
          minChildSize: 0.3,
          maxChildSize: 1.0,
          expand: false,
          // Pops the modal automatically when the user drags past minChildSize.
          shouldCloseOnMinExtent: isDismissible && enableDrag,
          builder: (_, scrollController) {
            // ScaffoldMessenger + Scaffold provide a local snackbar scope
            // within the modal overlay. Without this, ScaffoldMessenger.of()
            // from inside the sheet resolves to the root ScaffoldMessenger,
            // which renders snackbars in the underlying page's Scaffold —
            // behind the modal and invisible to the user.
            return ScaffoldMessenger(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                resizeToAvoidBottomInset: false,
                body: CircularDocumentationContainer(
                  color: backgroundColor,
                  // Zero out container padding — we apply it manually below
                  // so the drag handle sits flush at the rounded top edge.
                  padding: 0,
                  child: Column(
                    children: [
                      if (enableDrag) _DragHandle(colorScheme: colorScheme),
                      Expanded(
                        // PrimaryScrollController threads the DraggableScrollableSheet's
                        // scrollController into every descendant ListView /
                        // SingleChildScrollView that doesn't set its own controller.
                        // This is what lets drag-to-dismiss work with scrollable content:
                        // the sheet sees scroll events through the shared controller and
                        // starts collapsing once the list reaches its top edge.
                        child: PrimaryScrollController(
                          controller: scrollController,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              contentPadding,
                              enableDrag ? Spacing.xs.h : contentPadding,
                              contentPadding,
                              contentPadding,
                            ),
                            child:
                                widget ??
                                LegalDocumentationModalSheet(
                                  document: document!,
                                  onAgree: onAgree,
                                  onDecline: onDecline,
                                  agreeButtonText: agreeButtonText,
                                  declineButtonText: declineButtonText,
                                  showButtons: showButtons,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Drag handle pill shown at the top of every draggable sheet.
class _DragHandle extends StatelessWidget {
  final ColorScheme colorScheme;
  const _DragHandle({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Center(
        child: Container(
          width: 40.w,
          height: 4.h,
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2.r),
          ),
        ),
      ),
    );
  }
}

// lib/features/couple_map/widget/presentation/couple_widget_preview.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_publisher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const widgetToggleTitle = 'Show distance on my home screen';
const widgetToggleSubtitle = 'No names or places. Cleared by quick exit.';
const widgetPreviewLabel = 'Your home screen shows roughly this';
const widgetHowToIos =
    'Touch and hold your home screen, tap +, then find Attune';
const widgetHowToAndroid =
    'Touch and hold your home screen, tap Widgets, then find Attune';

/// This phone's opt-in (spec §2 ruling 1). Off by default.
class CoupleWidgetEnabled extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    // Re-read storage after any hide or clear (sign-out, quick exit…), so
    // the next account never sees a stale "on" (final review C1).
    void reread() => ref.invalidateSelf();
    CoupleWidgetSync.changes.addListener(reread);
    ref.onDispose(() => CoupleWidgetSync.changes.removeListener(reread));
    return CoupleWidgetSync.isEnabled();
  }

  Future<void> set(bool on) async {
    if (on) {
      try {
        await (await SharedPreferences.getInstance()).setBool(
          coupleWidgetEnabledKey,
          true,
        );
      } catch (_) {}
      state = const AsyncData(true);
      // start() already does one forced read; a restart after "off" in the
      // same session needs its own.
      final publisher = ref.read(coupleWidgetPublisherProvider);
      if (publisher.started) {
        unawaited(publisher.refreshFromServer(force: true));
      } else {
        publisher.start();
      }
    } else {
      await CoupleWidgetSync.clear();
      state = const AsyncData(false);
    }
  }
}

final coupleWidgetEnabledProvider =
    AsyncNotifierProvider<CoupleWidgetEnabled, bool>(CoupleWidgetEnabled.new);

/// Roughly what the home screen shows (spec §3.4): the same lines and
/// image, in a plain card. Not a pixel copy of the native widget.
class CoupleWidgetPreviewCard extends ConsumerWidget {
  const CoupleWidgetPreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final publisher = ref.watch(coupleWidgetPublisherProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.xs,
        Spacing.md,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widgetPreviewLabel, style: muted),
          const SizedBox(height: Spacing.sm),
          ValueListenableBuilder<CoupleWidgetPreview?>(
            valueListenable: publisher.preview,
            builder: (context, value, _) {
              final view =
                  value?.view ??
                  const CoupleWidgetView(
                    headline: neutralHeadline,
                    neutral: true,
                  );
              final map = value?.map;
              return Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    if (map != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          map,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          gaplessPlayback: true,
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                    ] else if (view.neutral) ...[
                      Icon(
                        Icons.favorite_border,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Spacing.sm),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            view.headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (view.caption != null)
                            Text(view.caption!, style: muted),
                          if (view.clockLine != null)
                            Text(view.clockLine!, style: muted),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            Platform.isIOS ? widgetHowToIos : widgetHowToAndroid,
            style: muted,
          ),
        ],
      ),
    );
  }
}

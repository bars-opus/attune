import 'dart:math' as math;

import 'package:attune/features/chat/domain/entities/message.dart';

/// Decode dimensions for a thumbnail painted with BoxFit.cover inside a box
/// [displayPx] physical pixels wide and [displayHeightPx] tall (square when
/// null). Only one side is constrained so the decode never comes out
/// smaller than the box: a photo narrower than the box is width-bound, a
/// wider one height-bound (in a square box: portrait and landscape).
///
/// Unknown dimensions (optimistic local rows carry none, and the file can be
/// the full-resolution pick) keep twice the box's longer side as the width,
/// so a 2:1 landscape's short edge still covers the box without an upscale.
/// ResizeImage never upscales, so over-asking is harmless.
({int? width, int? height}) thumbnailDecodeSize({
  required int displayPx,
  int? displayHeightPx,
  int? mediaWidth,
  int? mediaHeight,
}) {
  final boxHeight = displayHeightPx ?? displayPx;
  if (mediaWidth == null ||
      mediaHeight == null ||
      mediaWidth <= 0 ||
      mediaHeight <= 0) {
    return (width: math.max(displayPx, boxHeight) * 2, height: null);
  }
  // Wider than the box (w/h > W/H): cover is bound by the box's height.
  return mediaWidth * boxHeight > mediaHeight * displayPx
      ? (width: null, height: boxHeight)
      : (width: displayPx, height: null);
}

/// Which own bubbles carry a delivery tick (Task 11 fills this in).
bool showsDeliveryStatus({
  required bool isMine,
  required bool isNewestOwn,
  required bool isGroupEnd,
  required MessageStatus status,
}) {
  if (!isMine) return false;
  return isNewestOwn ||
      isGroupEnd ||
      status == MessageStatus.queued ||
      status == MessageStatus.sending ||
      status == MessageStatus.failed;
}

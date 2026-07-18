import 'dart:io';

import 'package:attune/core/widgets/schimmer_skeleton.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Single image tile used by ShopImagePageview and any other image container
/// (including InfoRowWidget's avatar slot when isNotAvatarImage is true).
/// Pass [isPreview] = true when [imageUrl] is a local file path (e.g. during
/// product/shop creation before upload). Default is a network image, decoded
/// via CachedNetworkImage (matches the app's other network-image call sites)
/// so repeated builds of the same URL reuse the cached bytes instead of
/// re-fetching/re-decoding and flickering on every rebuild.
class ImageContainer extends StatelessWidget {
  final String imageUrl;
  final bool isPreview;
  final BorderRadius? borderRadius;

  const ImageContainer({
    super.key,
    required this.imageUrl,
    this.isPreview = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    // Empty/not-yet-ready URL — nothing to load or fail, show the skeleton
    // rather than let Image.network attempt (and immediately error on) ''.
    if (!isPreview && imageUrl.isEmpty) {
      return _skeleton();
    }

    final image = isPreview
        ? Image.file(
            File(imageUrl),
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => _placeholder(),
          )
        : CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, __) => _skeleton(),
            errorWidget: (_, __, ___) => _placeholder(),
          );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _skeleton() {
    final skeleton = SchimmerSkeleton(
      width: double.infinity,
      height: double.infinity,
      raduis: 0,
    );
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: skeleton);
    }
    return skeleton;
  }

  Widget _placeholder() {
    return Center(
      child: Icon(
        Icons.image_not_supported_rounded,
        color: Colors.grey.shade500,
        size: 50.h,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SchimmerSkeleton extends StatelessWidget {
  final double? width;
  final double? height;
  final int? raduis;

  final BoxShape? shape;

  const SchimmerSkeleton({
    super.key,
    this.width,
    this.height,
    this.shape,
    this.raduis = 12,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCircle = shape == BoxShape.circle;

    return Container(
      width: width ?? double.infinity,
      height: height ?? 400.h,
      decoration: BoxDecoration(
        shape: shape ?? BoxShape.rectangle,
        color: colorScheme.onBackground.withOpacity(.1),
        // Only apply borderRadius if shape is NOT circle
        borderRadius:
            isCircle ? null : BorderRadius.circular( raduis!.r),
      ),
    );
  }
}

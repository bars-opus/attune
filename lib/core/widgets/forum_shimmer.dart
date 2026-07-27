import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/schimmer_skeleton.dart';

class ForumSchimmer extends StatelessWidget {
  final bool isComment;

  const ForumSchimmer({super.key, this.isComment = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SchimmerSkeleton(
          width: isComment ? 30 : 40,
          height: isComment ? 30 : 40.h,
          shape: BoxShape.circle,
        ),
        Gap(10.h),
        Expanded(
          child:
              isComment
                  ? Column(
                    children: [
                      SchimmerSkeleton(height: 10.h),
                      Gap(5.h),
                      SchimmerSkeleton(height: 10.h),
                      Gap(5.h),
                      SchimmerSkeleton(height: 10.h),
                      Gap(20.h),
                    ],
                  )
                  : Column(
                    children: [
                      SchimmerSkeleton(height: 10.h),
                      Gap(5.h),
                      SchimmerSkeleton(height: 10.h),
                      Gap(5.h),

                      SchimmerSkeleton(height: 10.h),
                      Gap(5.h),
                      SchimmerSkeleton(height: 10.h),
                      Gap(20.h),
                    ],
                  ),
        ),
      ],
    );
  }
}

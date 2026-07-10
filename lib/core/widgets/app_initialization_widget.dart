import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/animated_circle.dart';

class AppInitializationWidget extends StatelessWidget {
  const AppInitializationWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.appColors.appColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedCircle(
              size: 30,
              stroke: 2,
              animateSize: true,
              animateShape: true,
              firstColor: Colors.white,
              secondColor: Colors.white.withValues(alpha: 0.5),
            ),
            Gap(Spacing.md),
            SizedBox(
              width: 50,
              height: 50,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
                child: Image.asset(
                  'assets/images/initializing_logo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

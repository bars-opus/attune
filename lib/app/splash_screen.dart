// In SplashScreen:
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/core/providers/profile_providers/profile_provider.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/widgets/app_initialization_widget.dart';

class SplashScreen extends ConsumerStatefulWidget {
  // Change this
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState(); // Change this
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Change this
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNavigation();
    });
  }

  Future<void> _handleNavigation() async {
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    // ✅ Now 'ref' is available
    final isFirstLaunch = ref.read(isFirstLaunchProvider);
    final user = ref.read(currentUserProvider);

    if (isFirstLaunch) {
      context.go(RouteNames.intro);
    } else if (user == null) {
      context.go(RouteNames.home);
    } else {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile?.hasUsername == true) {
        context.go(RouteNames.home);
      } else {
        context.go(RouteNames.createUsername);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppInitializationWidget();

    // Scaffold(
    //   backgroundColor: Theme.of(context).colorScheme.primary,
    //   body: Center(
    //     child: AppIconButton(
    //       iconSize: 70,
    //       iconColor: Colors.white,
    //       icon: Icons.rocket_launch,
    //     ),
    //   ),
    // );
  }
}

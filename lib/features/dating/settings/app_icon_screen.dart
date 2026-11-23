// Spec 2 W8b (§3.12 App icon, §6.7; R-80): Dating settings -> App icon and
// D13's offer open /dating/app-icon: Settings' own App icon page (one page,
// one control, for everyone) inside Dating, so behind the Dating lock,
// DatingPageWatch (FLAG_SECURE, the capture cover, blanking) and
// DatingRootBack like every Dating page; alone, its back is Dating
// settings.
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/settings/presentation/screens/app_icon_screen.dart';
import 'package:flutter/material.dart';

class DatingAppIconScreen extends StatelessWidget {
  const DatingAppIconScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      AppIconScreen(leading: datingRootBackButton(context));
}

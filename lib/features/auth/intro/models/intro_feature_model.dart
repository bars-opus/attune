// Keep IntroPage as data class
import 'package:attune/core/utils/exports/export_screens.dart';

class IntroFeatureModel {
  final String title;
  final String description;
   final VoidCallback onTap;
  final IconData icon;

  IntroFeatureModel({
    required this.title,
    required this.description,
    required this.icon,
    required  this.onTap,
  });
}



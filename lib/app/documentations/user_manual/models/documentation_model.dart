import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';
abstract class DocumentationModule {
  // We keep the getters that don't need context
  String get id;
  IconData get icon;
  int get order;

  // Methods that need localization now take BuildContext
  String getTitle(BuildContext context);
  String getSubtitle(BuildContext context);

  List<ManualSection> getSections(BuildContext context);
  List<FAQModel> getFAQs(BuildContext context);
}

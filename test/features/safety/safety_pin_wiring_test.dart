// Spec 2 (research 06 §3 F2 (6)): the Safety PIN is reachable from Settings
// and offered on Support resources.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the router serves /settings/safety-pin as safetyPin', () {
    final src = _read('lib/app/routing/app_router.dart');
    expect(
      src,
      contains("static const String safetyPin = '/settings/safety-pin';"),
    );
    expect(src, contains("name: 'safetyPin'"));
    expect(src, contains('const SafetyPinScreen()'));
  });

  test('Settings lists Safety PIN right after Safety resources', () {
    final src = _read('lib/features/settings/data/settings_data.dart');
    final resources = src.indexOf("id: 'safety_resources'");
    final pin = src.indexOf("id: 'safety_pin'");
    expect(resources, greaterThan(-1));
    expect(pin, greaterThan(resources));
    expect(src.indexOf("id: 'feedback'"), greaterThan(pin));
    expect(src, contains("routeName: '/settings/safety-pin'"));
    expect(src, contains("subtitle: 'Asked for after you use quick exit'"));
    // Review M-5: a slot of its own in the section.
    final row = src.substring(pin, src.indexOf('),', pin));
    expect(row, contains('order: 5,'));
  });

  test('Support resources mounts the one-time PIN offer', () {
    final src = _read(
      'lib/features/safety/presentation/screens/safety_resources_screen.dart',
    );
    expect(src, contains('const SafetyPinPromptCard()'));
  });
}

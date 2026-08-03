import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attune/core/intro/data/seen_feature_intro_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SeenFeatureIntroStore', () {
    test('hasSeenIntro returns false before markIntroSeen is called', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SeenFeatureIntroStore(prefs);

      expect(store.hasSeenIntro('datingMode'), isFalse);
    });

    test('hasSeenIntro returns true after markIntroSeen', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SeenFeatureIntroStore(prefs);

      await store.markIntroSeen('datingMode');

      expect(store.hasSeenIntro('datingMode'), isTrue);
    });

    test('flags are independently keyed per featureId', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SeenFeatureIntroStore(prefs);

      await store.markIntroSeen('datingMode');

      expect(store.hasSeenIntro('datingMode'), isTrue);
      expect(store.hasSeenIntro('healing'), isFalse);
    });
  });
}

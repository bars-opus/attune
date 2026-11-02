// Spec 1 W3a (§5.6 R19, §5.8): sign-out runs the device wipe registry beside
// its four existing wipes and the push release; a hanging entry is cut at
// its bound and the sign-out still lands.
import 'dart:async';

import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/auth/services/auth_service.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:attune/features/stories/data/story_outbox_wipe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeCache implements ChatCacheService {
  _FakeCache(this.events);
  final List<String> events;

  @override
  Future<void> clearAll() async => events.add('cache wiped');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Review #8: each of the four existing wipes records that it ran.
class _FakePicker implements ChatImagePicker {
  _FakePicker(this.events);
  final List<String> events;

  @override
  Future<void> wipeStaging() async => events.add('staging wiped');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMedia implements ChatMediaCache {
  _FakeMedia(this.events);
  final List<String> events;

  @override
  Future<void> clear() async => events.add('media wiped');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImages implements ChatImageCache {
  _FakeImages(this.events);
  final List<String> events;

  @override
  Future<void> clear() async => events.add('images wiped');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStories implements StoryOutboxWiper {
  _FakeStories(this.events);
  final List<String> events;

  @override
  Future<void> wipeAll() async => events.add('stories wiped');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthService {
  _FakeAuth(this.events);
  final List<String> events;

  @override
  Future<void> signOut() async => events.add('auth signed out');

  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

({ProviderContainer container, List<String> events}) _build(
  DeviceWipeRegistry registry, {
  bool brokenRegistry = false,
}) {
  final events = <String>[];
  final container = ProviderContainer(
    overrides: [
      chatCacheServiceProvider.overrideWithValue(_FakeCache(events)),
      chatImagePickerProvider.overrideWithValue(_FakePicker(events)),
      chatMediaCacheProvider.overrideWithValue(_FakeMedia(events)),
      chatImageCacheProvider.overrideWithValue(_FakeImages(events)),
      storyOutboxWiperProvider.overrideWithValue(_FakeStories(events)),
      authServiceProvider.overrideWithValue(_FakeAuth(events)),
      routingNotifierProvider.overrideWith((ref) => RoutingNotifier()),
      if (brokenRegistry)
        deviceWipeRegistryProvider.overrideWith(
          (ref) => throw StateError('broken'),
        )
      else
        deviceWipeRegistryProvider.overrideWithValue(registry),
      signOutHooksProvider.overrideWithValue(
        SignOutHooks(beforeSignOut: () async => events.add('push released')),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, events: events);
}

void main() {
  test(
    'the registry runs beside the existing wipes, before the sign-out',
    () async {
      final registry = DeviceWipeRegistry();
      late List<String> events;
      registry
        ..register(
          DeviceWipeEntry(
            id: 'probe.signout',
            moments: const {WipeMoment.signOut},
            run: () async => events.add('registry wiped'),
          ),
        )
        ..register(
          DeviceWipeEntry(
            id: 'probe.exit',
            moments: const {WipeMoment.quickExit},
            run: () async => events.add('quick exit only'),
          ),
        );
      final t = _build(registry);
      events = t.events;
      await t.container.read(authOperationsProvider).signOut();
      expect(
        events,
        containsAll([
          'cache wiped',
          'staging wiped',
          'media wiped',
          'images wiped',
          'stories wiped',
          'push released',
          'registry wiped',
        ]),
      );
      expect(events, isNot(contains('quick exit only')));
      expect(events.last, 'auth signed out');
    },
  );

  test('a hanging entry does not hold the sign-out past its bound', () async {
    final registry =
        DeviceWipeRegistry()..register(
          DeviceWipeEntry(
            id: 'probe.hang',
            moments: const {WipeMoment.signOut},
            bound: const Duration(milliseconds: 100),
            run: () => Completer<void>().future,
          ),
        );
    final t = _build(registry);
    final clock = Stopwatch()..start();
    await t.container.read(authOperationsProvider).signOut();
    expect(t.events.last, 'auth signed out');
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test(
    'a registry that fails to load never stops the sign-out (review #6)',
    () async {
      final t = _build(DeviceWipeRegistry(), brokenRegistry: true);
      await t.container.read(authOperationsProvider).signOut();
      expect(t.events, containsAll(['cache wiped', 'stories wiped']));
      expect(t.events.last, 'auth signed out');
    },
  );
}

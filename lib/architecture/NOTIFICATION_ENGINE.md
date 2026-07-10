# Notification Engine — Integration Guide

A plug-and-play push + in-app notification engine for Flutter + Supabase + OneSignal.

Copy `lib/core/notifications/` and `supabase/functions/` into any new project and follow this guide to go from zero to working notifications in under an hour.

---

## What you get out of the box

| Feature | Details |
|---------|---------|
| Push notifications | OneSignal delivery with automatic user login/logout |
| Scheduled pushes | Cron-based delivery with exponential back-off (2→4→8→16→32 min, max 5 retries) |
| Immediate pushes | Insert with `scheduled_for = now()`, cron picks up within ~1 min |
| In-app inbox | Real-time, mark-as-read, delete, badge count |
| Per-user settings | push/email/marketing opt-out; respected by delivery cron |
| Geo-notifications | Nearby-user query via PostGIS |
| Auth-gated push endpoint | Edge function accepts service-role key OR user JWT |

---

## Prerequisites

| Dependency | Version | Notes |
|-----------|---------|-------|
| `flutter_riverpod` | ^2.x | State management |
| `supabase_flutter` | ^2.x | Backend + real-time |
| `onesignal_flutter` | ^5.x | Push delivery |
| `go_router` | ^13.x | Navigation (only needed for tap callbacks) |

---

## 1 — Database setup

Run the migration once against your Supabase project:

```bash
supabase db push   # if using local Supabase CLI
# or paste supabase/migrations/20260507000000_notification_engine.sql
# into Dashboard → SQL Editor → Run
```

The migration creates five tables and a cron-compatible function:

| Table | Purpose |
|-------|---------|
| `scheduled_notifications` | Pending and processed push jobs |
| `in_app_notifications` | Notification inbox rows |
| `notification_settings` | Per-user opt-in/out |
| `push_tokens` | Device token registry (optional) |
| `user_locations` | Last-known location for geo-queries |

A trigger auto-creates a `notification_settings` row for every new user.

---

## 2 — Edge functions

Deploy both Supabase Edge Functions:

```bash
supabase functions deploy send-onesignal-push
supabase functions deploy process-scheduled-notifications
```

Set secrets on your project (Dashboard → Settings → Edge Functions):

```
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
SUPABASE_ANON_KEY
ONE_SIGNAL_APP_ID
ONE_SIGNAL_API_KEY        # REST API key from OneSignal dashboard
```

Schedule the cron (Dashboard → Database → Cron Jobs → New):

```
Name:     process-scheduled-notifications
Schedule: * * * * *   (every minute)
Command:  SELECT net.http_post(
            'https://<project-ref>.supabase.co/functions/v1/process-scheduled-notifications',
            headers => '{"Authorization":"Bearer <service-role-key>"}'
          );
```

---

## 3 — Environment variables

Add to your `.env.json` (or CI secrets):

```json
{
  "ONESIGNAL_APP_ID": "your-onesignal-app-id"
}
```

Run the app with:
```bash
flutter run --dart-define-from-file=.env.json
```

---

## 4 — Flutter wiring

### 4a. Wire the config in `main.dart`

```dart
import 'package:your_app/core/notifications/config/feature/notification_config.dart';
import 'package:your_app/core/notifications/config/notification_setting_toggle.dart';

// Inside ProviderScope overrides:
notificationConfigProvider.overrideWithValue(
  NotificationConfig(
    appName: 'Your App',

    // Called when the user taps a notification in the inbox.
    onNotificationTap: (notification, context) {
      final type = notification.data?['type'] as String?;
      switch (type) {
        case 'order_update':
          context.go('/orders/${notification.data?['order_id']}');
        default:
          context.go('/home');
      }
    },

    // Per-feature toggles shown in the settings screen.
    // Remove this list if your app has no per-type granularity.
    settingToggles: [
      NotificationSettingToggle(
        label: 'Order Updates',
        description: 'Status changes on your orders',
        getValue: (state) => state.bookingRemindersEnabled,  // reuse existing field
        setValue: (notifier, v) => notifier.setBookingRemindersEnabled(v),
      ),
    ],
  ),
),
```

> **Which `NotificationSettingsState` field to use?**
> The settings table has `booking_reminders_enabled` and `new_shops_nearby_enabled`.
> Map your app's toggle to whichever field makes sense, or add a new column to the
> table and the corresponding field to `NotificationSettingsState`.

### 4b. Initialise OneSignal

Call `OneSignalService.initialize()` somewhere after the first authenticated frame,
for example in a top-level `ConsumerWidget` `initState`:

```dart
ref.read(oneSignalServiceProvider).initialize();
```

The service automatically calls `OneSignal.login(userId)` when the user logs in and
`OneSignal.logout()` when they log out, so push tokens are always bound to the
correct Supabase user ID.

### 4c. Add the notification bell to your app bar

```dart
AppBar(
  actions: [
    NotificationBellIcon(),   // handles auth-gating and badge internally
  ],
)
```

### 4d. Add the inbox screen to your router

```dart
GoRoute(
  path: '/notifications',
  builder: (_, __) => const NotificationInboxScreen(),
),
```

### 4e. Add the settings screen to your router

```dart
GoRoute(
  path: '/settings/notifications',
  builder: (_, __) => const NotificationSettingsScreen(),
),
```

---

## 5 — Sending notifications

### Immediate push (self)

```dart
final repo = ref.read(notificationRepositoryProvider);
await repo.queueImmediateNotification(
  userId: currentUserId,
  title: 'Your order shipped!',
  body: 'Estimated delivery: tomorrow',
  data: {'type': 'order_update', 'order_id': '123'},
);
```

The row lands in `scheduled_notifications` with `scheduled_for = now()` and is
delivered within ~1 minute by the cron.

### Scheduled push

```dart
await repo.scheduleNotifications([
  ScheduledNotification(
    userId: userId,
    notificationType: 'order_reminder',
    scheduledFor: DateTime.now().add(const Duration(hours: 1)),
    metadata: {
      'title': 'Don't forget!',
      'body': 'Your order is waiting for payment',
      'type': 'order_reminder',
      'order_id': orderId,
    },
  ),
]);
```

### Cross-user push (server-side only)

Sending to a different user from the Flutter client is intentionally blocked
(prevents spam). Do it from an edge function or database trigger:

```typescript
// Inside a Supabase Edge Function (has access to service role key):
await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-onesignal-push`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    userId: recipientId,
    title: 'New booking!',
    body: 'A client just booked your 2pm slot',
    data: { type: 'booking_created', booking_id: bookingId },
  }),
});
```

Or insert directly into `in_app_notifications` from a database trigger:

```sql
INSERT INTO in_app_notifications (user_id, title, body, data)
VALUES (NEW.shop_owner_id, 'New Booking', 'Client booked 2pm', 
        jsonb_build_object('type','booking_created','booking_id',NEW.id));
```

---

## 6 — Customising notification types

### Add a new scheduled type

1. Add rows in `scheduled_notifications` with your new `notification_type` string.
2. Add a matching entry in `NotificationConfig.notificationTypes`.
3. Handle the type in `onNotificationTap`.

No source changes required in the engine itself.

### Add a new settings toggle

1. Add a column to `notification_settings` (e.g. `chat_notifications_enabled`).
2. Add a field to `NotificationSettingsState` + `copyWith`.
3. Add a setter method to `NotificationSettingsNotifier`.
4. Add a `NotificationSettingToggle` entry to your `NotificationConfig`.
5. Update the repository's `updateNotificationSettings` to pass the new field.

---

## 7 — Files to change per app

When porting to a new project, **only these files need editing**:

| File | What to change |
|------|---------------|
| `config/notification_config.dart` | `onNotificationTap` navigation + `settingToggles` + notification type map |
| `main.dart` | Add `notificationConfigProvider.overrideWithValue(...)` to `ProviderScope` |
| `.env.json` | `ONESIGNAL_APP_ID` |
| Supabase secrets | `ONE_SIGNAL_APP_ID`, `ONE_SIGNAL_API_KEY` |

Everything inside `core/notifications/` except `config/notification_config.dart`
is generic and can be copied unchanged.

---

## 8 — Architecture overview

```
┌─────────────────────────────────────────────────────────┐
│  Flutter App                                            │
│                                                         │
│  NotificationBellIcon ──► NotificationInboxScreen       │
│  NotificationSettingsScreen                             │
│  (both driven by NotificationConfig callbacks)          │
│                          │                              │
│  Riverpod Providers       │                              │
│  ├─ notificationListProvider (StateNotifier)            │
│  ├─ notificationSettingsProvider (StateNotifier)        │
│  ├─ realTimeNotificationsProvider (StreamProvider)      │
│  └─ unreadNotificationCountProvider (derived, reactive) │
└──────────────────────┬──────────────────────────────────┘
                       │ Supabase client
          ┌────────────┼────────────────────────┐
          │            │                        │
   in_app_notifications  scheduled_notifications  notification_settings
   (real-time stream)    (cron table)             (user prefs)
          │
          └─► process-scheduled-notifications (cron, 1 min)
                    │
                    └─► OneSignal REST API ──► Device push
```

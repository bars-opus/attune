# Auth & Onboarding Engine — Integration Guide

Phone-first authentication and onboarding flow for Attune.

This guide documents the launch implementation path:

```
phone OTP -> basic profile setup -> onboarding -> home/chat
```

It exists alongside `ATTUNE_MASTER_SPEC.md` as the practical implementation
guide for Flutter wiring, state transitions, failure modes, and review checks.

---

## What You Get

| Feature | Details |
|---------|---------|
| Phone OTP auth | Supabase phone auth only at launch |
| No password/social auth | Email/password, Apple, Google, and magic links are inactive in launch UI |
| Basic profile setup | Display name only before onboarding writes remote profile data |
| Onboarding fork | Single users route to Personal mode; relationship users route to Couples mode |
| Anonymous browsing | Opinions stays available without an account |
| Chat gate | Anonymous Chat shows `LoginProfile`; verified + onboarded users see Chat workspace |
| Public app invite | `LoginProfile` "Invite a friend" opens app sharing only; it is not a partner invite |
| Partner invite | Created only as the final couples onboarding step |
| Session resume | Authenticated users with incomplete onboarding resume onboarding |
| Default tab selection | Couples users default to Chat; anonymous/single/unknown users default to Opinions |

---

## Product Rules

### Launch Auth Decision

Attune uses one launch auth method:

```
Phone number -> SMS OTP -> Supabase session
```

Do not show:

- email/password
- email magic link
- Apple Sign-In
- Google Sign-In

Legacy screens and widgets may remain in the repository as reference material,
but active Attune routes must not expose those methods at launch.

### SMS Delivery Infrastructure (launch-market ground truth, July 2026)

The entire product sits behind SMS OTP, and OTP delivery is a known failure
point on Ghanaian carriers. These are requirements, not suggestions:

- **Use a Ghana-direct SMS provider as the primary route** (Arkesel /
  Termii / Africa's Talking class — direct MTN/Telecel/AirtelTigo
  connections), not a global aggregator alone. Global aggregators route
  Ghana traffic through international hubs with added latency and drop risk.
- **MTN alphanumeric Sender ID registration is mandatory and enforcement is
  already live** (deadline passed July 8, 2026 — unregistered senders are
  blocked). Registration takes ~3 weeks; verify current OTP deliverability
  on a real MTN SIM before any release, and budget registration lead time
  for every new sender ID. Numeric sender IDs fail outright on several
  Ghanaian carriers; short codes and two-way SMS are unsupported in Ghana.
- **Voice OTP is the required automatic fallback** when SMS delivery fails
  or times out — not a nice-to-have.
- **Never rely on Firebase phone auth alone**: it has a documented,
  unresolved reliability bug specifically affecting +233 numbers.
- Real-device, real-carrier OTP testing (MTN, Telecel, AirtelTigo) is a
  launch gate. Emulator/testing-number success proves nothing here.
- New launch markets repeat this exercise: per-market carrier registration
  requirements and a market-direct provider assessment before enabling
  signup in that market.

See `ATTUNE_RISK_SOLUTIONS.md` Section 10 (item 5) for why this is on the
pre-launch critical path.

### Basic Profile Setup

After phone verification, collect only:

- display name

Do not collect username, avatar, gender, or relationship details in this step.
Those belong to later profile/settings or onboarding surfaces.

The display name is required before remote onboarding submission because the
`public.users.display_name` column is required by the current schema.

---

## Route Flow

### Anonymous User

```
HomeScreen
  Opinions tab -> browse read-only
  Chat tab     -> LoginProfile
```

### Phone Verification

```
LoginProfile CTA
  -> Legal acceptance bottom sheet
  -> LoginScreen (phone OTP)
  -> OnboardingFlow
```

### Onboarding

```
Profile setup
  -> Single / In a relationship fork
  -> Attachment quiz
  -> Personal or relationship anchors
  -> Partner invite if relationship path
  -> HomeScreen
```

Partner invite rules:

- The public `LoginProfile` "Invite a friend" action must never create a relationship invite.
- Partner invites are created only for users who selected "In a relationship" and reached the final couples onboarding step.
- A pending partner invite does not make the inviter or invitee an active couple.
- Active couple recognition requires both users to phone-verify, link through the invite, and complete their own onboarding flows.
- Until both sides complete, shared partner chat, shared insights, Pulse, games, and couple recognition remain locked.

### Returning User

```
authenticated + onboarding complete + couples  -> HomeScreen, Chat selected
authenticated + onboarding complete + personal -> HomeScreen, Opinions selected
authenticated + onboarding incomplete          -> OnboardingFlow
anonymous                                      -> HomeScreen, Opinions selected
```

If mode cannot be read, fall back to Opinions.

---

## Data Writes

Remote submission is idempotent through Supabase upserts:

| Table | Write |
|-------|-------|
| `public.users` | `upsert(id, phone, display_name, mode)` |
| `public.onboarding_profiles` | `upsert(user_id, mode, attachment_answers, anchors)` |

The client must never write another user's profile or onboarding row. RLS must
enforce `auth.uid() = id/user_id`.

---

## Failure Modes

| Failure | User behavior |
|---------|---------------|
| Supabase not configured | Show local configuration guidance; disable OTP action |
| SMS request timeout | Tell user it took too long and is safe to retry |
| Invalid phone | Ask user to check international phone format |
| Invalid/expired OTP | Ask user to request or enter a fresh code |
| Remote onboarding submit fails | Save local completion; show sync-later message |
| Invite accept fails | Keep user in onboarding and show safe retry message |

No UI error should expose stack traces, project refs, internal table names, or
raw provider payloads.

---

## Algorithm Quality Checklist Alignment

Applies tags: `[ALL]`, `[MOBILE]`, `[UI]`, `[MUTATION]`.

| Checklist area | Implementation rule |
|----------------|---------------------|
| 1.1 / 2.18 Idempotency | Use Supabase upserts for profile/onboarding writes |
| 1.2 Timeouts | Auth and onboarding network calls use bounded timeouts |
| 1.11 Privacy | Phone is PII; never log raw phone numbers |
| 2.1 Input safety | Validate non-empty phone/code/display name before mutation |
| 2.4 / 5.5 Error leakage | User messages are friendly and generic |
| 2.10 Resource lifecycle | Dispose controllers, focus nodes, and auth subscriptions |
| 4.4 Logs | Log error categories/runtime types only, not PII |
| 5.1 UX | Every failure gives a next step |
| 5.2 Feedback | Button taps immediately show loading/disabled state |
| 6.13 Docs | This guide is the runbook for the flow |

---

## UI Reuse Rules

Use cloned app widgets before creating new UI:

- `AppTextFormField`
- `AppButton`
- `BottomSheetUtils.showDocumentationBottomSheet`
- `context.showInfoSnackbar`, `showErrorSnackbar`, `showSuccessSnackbar`
- `SemanticContainerWidget` for explanatory info blocks
- `Gap`, `Spacing`, `.h`, `.w`, `.sp`, `.r`
- theme `colorScheme`, `AppColors`, and design tokens

Info blocks should use this visual direction:

```dart
SemanticContainerWidget(
  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
  borderColor: colorScheme.primary,
  iconColor: colorScheme.primary,
  // ...
)
```

---

## Folder Structure

Auth/onboarding implementation follows the profile-style feature structure:

```text
lib/features/onboarding/
├── data/
│   ├── onboarding_store.dart
│   └── onboarding_submission_service.dart
├── domain/
│   └── onboarding_models.dart
└── presentation/
    ├── screens/
    │   ├── onboarding_flow.dart
    │   └── onboarding_gate.dart
    └── widgets/
        ├── anchors_step.dart
        ├── attachment_quiz_step.dart
        ├── couples_joined_step.dart
        ├── couples_waiting_step.dart
        ├── incoming_invite_step.dart
        ├── invite_card.dart
        ├── onboarding_choice_button.dart
        ├── onboarding_info_tile.dart
        ├── onboarding_mode_step.dart
        ├── onboarding_step_frame.dart
        ├── personal_ready_step.dart
        └── profile_setup_step.dart
```

`OnboardingFlow` is only the coordinator. It owns step index, controllers, and
transition decisions. It must not contain the visual implementation for each
step. New onboarding screens or repeated UI elements go in their own files.

## Design-System Review Gate

Before any new auth/onboarding UI is accepted, scan for:

- `SizedBox` used only for layout spacing instead of `Gap`
- raw `SnackBar`
- raw `Color(...)`
- raw UI `Duration(...)`
- plain `TextField`/`FilledButton` where `AppTextFormField`/`AppButton` fit
- hardcoded radii, icon sizes, or spacing where a token exists

Allowed exceptions must be intentional and small, such as non-UI service
timeouts or Flutter APIs requiring a concrete value.


## Deferred

These are not part of the first pass:

- country picker
- username
- avatar setup
- Apple/Google/email/password auth
- full relationship invite acceptance polish
- production SMS rate-limit UI
- final profile page cleanup

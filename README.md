# attune

<!-- After the first push, replace OWNER/REPO with your GitHub slug. -->
[![tests](https://github.com/OWNER/REPO/actions/workflows/tests.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/tests.yml)

Attune is a Flutter app backed by Supabase.

## Local setup

- Install Flutter and the Supabase CLI.
- Link the project with `supabase link`.
- Run the app normally with Flutter.

## Phone verification

Attune uses Supabase phone auth for account creation verification.

## Phone auth

For hosted Supabase projects, enable the phone provider in the Auth settings.
For local/self-hosted projects, configure the `auth.sms` settings in Supabase.

If your Twilio provider is configured in Supabase, you can choose between SMS and WhatsApp from the login screen.

## Testing

Two suites run in CI (`.github/workflows/tests.yml`) on every push and PR:

- **Flutter** — `flutter analyze` (gated on errors only) and `flutter test`.
- **SQL contracts** — database authorization/lifecycle tests under
  `supabase/tests/`, run against a real Supabase stack so the `auth` schema and
  `auth.uid()` the contracts depend on are present.

Run them locally:

```bash
flutter test                       # Dart/widget/controller tests
supabase start                     # needs Docker Desktop
scripts/run_sql_contracts.sh       # applies migrations, runs the SQL contracts
```

The SQL contracts wrap each file in a rollback-only transaction that
`RAISE EXCEPTION`s on any violated contract, so a green run persists nothing.
If you don't have Docker locally, let CI run them.

### Recommended branch protection

On GitHub, protect `main` and require the `tests` workflow checks
(`Flutter analyze + tests` and `SQL contract tests`) to pass before merge, so a
change can't land while the message-delivery or RLS contracts are red.

## Deploy

There is no custom verification edge function in this flow.
If you change backend functions, deploy them with the Supabase CLI as usual.

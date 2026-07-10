# attune

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

## Deploy

There is no custom verification edge function in this flow.
If you change backend functions, deploy them with the Supabase CLI as usual.

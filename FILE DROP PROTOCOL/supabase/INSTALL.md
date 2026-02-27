# Supabase Install (Backend)

## Assumptions

1. You already have a Supabase project.
2. You will run this in staging before production.
3. Client apps will only use `publishable` or `anon` keys.

## 1) Link project

```bash
supabase login
supabase link --project-ref <YOUR_PROJECT_REF>
```

## 2) Apply schema

Recommended path:

1. Copy `supabase/schema/install.sql` into a migration file under your existing app repo.
2. Run `supabase db push`.

Alternative quick path for evaluation:

```bash
supabase db execute --file supabase/schema/install.sql
```

## 3) Deploy functions

From this package root:

```bash
supabase functions deploy register-device
supabase functions deploy upload-file
supabase functions deploy list-pending
supabase functions deploy update-upload-status
```

## 4) Verify function auth mode

`supabase/config.toml` includes:

- `verify_jwt = false` for all four functions.

Reason: function-level device token authentication is used instead of Supabase Auth user sessions.

## 5) Smoke test backend

1. Register a device.
2. Upload a file.
3. Poll pending list from extension.
4. Acknowledge status as `downloaded` or `canceled`.

See `../qa/SMOKE_TEST.md` for exact steps.

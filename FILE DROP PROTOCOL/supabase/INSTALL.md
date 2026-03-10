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
2. Copy `supabase/schema/dropbridge_v2_account_link.sql` into a second migration file.
3. Ensure `supabase/migrations/20260302005800_dropbridge_v2_client_kind_lectra_ipad.sql` is included.
4. Ensure `supabase/migrations/20260310113000_dropbridge_v2_lectra_wake_hints.sql` is included.
5. Run `supabase db push`.

Alternative quick path for evaluation:

```bash
supabase db execute --file supabase/schema/install.sql
supabase db execute --file supabase/schema/dropbridge_v2_account_link.sql
supabase db execute --file supabase/migrations/20260302005800_dropbridge_v2_client_kind_lectra_ipad.sql
supabase db execute --file supabase/migrations/20260310113000_dropbridge_v2_lectra_wake_hints.sql
```

## 3) Deploy functions

From this package root:

```bash
supabase functions deploy register-device
supabase functions deploy upload-file
supabase functions deploy list-pending
supabase functions deploy update-upload-status
supabase functions deploy register-device-v2
supabase functions deploy upload-file-v2
supabase functions deploy list-pending-v2
supabase functions deploy update-upload-status-v2
supabase functions deploy get-upload-status-v2
supabase functions deploy wake-lectra-v2
supabase functions deploy cleanup-expired-uploads
```

## 4) Configure Realtime + optional APNs

1. Enable private-only Realtime channels in the Supabase dashboard.
2. The SQL migration installs a `realtime.messages` policy that only authorizes:
   - `dropbridge:user:<user_id>:device:<device_id>`
   - when the authenticated user owns that Lectra device.
3. Optional APNs env vars for `lectra_ipad` wake delivery:
   - `APNS_KEY_ID`
   - `APNS_TEAM_ID`
   - `APNS_TOPIC`
   - `APNS_PRIVATE_KEY_P8`

## 5) Verify function auth mode

`supabase/config.toml` includes:

- `verify_jwt = false` for v1 pairing functions.
- `verify_jwt = false` for v2 account-linked functions.
- `verify_jwt = true` for service-role-only cleanup function.

Reason: v1 uses device token auth, while v2 validates Supabase user JWTs inside the function via `_shared/auth-user.ts`.

## 6) Smoke test backend

1. Register a device.
2. Upload a file.
3. Poll pending list from extension.
4. Acknowledge status as `downloaded` or `canceled`.
5. Write a `synced_items` row for a Lectra PDF and call `wake-lectra-v2`.
6. Verify the receiver gets a private Realtime wake and, when configured, a silent push attempt.
5. Run `cleanup-expired-uploads` (service role) and verify expired rows are canceled.

See `../qa/SMOKE_TEST.md` for exact steps.

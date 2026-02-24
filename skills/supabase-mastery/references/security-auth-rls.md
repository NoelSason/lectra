# Supabase Security, Auth, and RLS

As of February 24, 2026.

## 1) API key model

Supabase supports publishable/secret API keys and legacy long-lived JWT keys (`anon`, `service_role`).

Use this default policy:

1. Use `publishable` keys in browser/mobile clients.
2. Use `secret` or `service_role` only in trusted server environments.
3. Rotate and scope server keys; never ship them to client bundles.

Quick matrix:

| Key type | Client safe | Typical use | RLS behavior |
|---|---|---|---|
| publishable | yes | public client calls | subject to RLS |
| anon (legacy JWT) | yes | legacy client calls | subject to RLS |
| secret | no | backend Data API calls | obeys DB role grants; never expose |
| service_role (legacy JWT) | no | admin backend tasks | can bypass RLS |

## 2) JWT validation and signing keys

Do not trust tokens by shape alone. Validate issuer, audience, expiration, and signature.

Use asymmetric JWT signing key workflows where available, and track signing key rotation in runbooks.

## 3) Session controls

Supabase Auth exposes controls for:

- JWT/access token lifetime.
- Time-boxed sessions.
- Inactivity timeout.
- Single-session per user.

Use shorter JWT lifetimes for higher-risk applications, then tune refresh/session behavior for UX.

## 4) Authentication architecture checklist

1. Select providers (email/password, OAuth, SSO, anonymous, etc.) by threat model.
2. Define identity linking/account merging behavior early.
3. Store authorization state in Postgres and enforce with RLS, not only client logic.
4. Keep privileged actions server-side behind trusted keys.

## 5) RLS design pattern

Baseline:

1. Enable RLS on exposed tables.
2. Start from deny-by-default.
3. Add explicit `SELECT/INSERT/UPDATE/DELETE` policies.
4. Keep policy predicates simple and indexed.

Performance rules from Supabase guidance:

- Add indexes on policy columns.
- Prefer wrapping function calls in `SELECT`, for example `(select auth.uid())` in policy predicates.
- Minimize joins inside policy expressions where possible.
- Use `security_invoker` views for Postgres 15+ when view behavior must respect caller policies.

## 6) Common auth and policy mistakes

1. Exposing `service_role` in client apps.
2. Relying on frontend checks without RLS enforcement.
3. Shipping unindexed policy columns causing full scans.
4. Mixing tenant authorization logic across app code and SQL with inconsistent rules.

## 7) Verification checklist

1. Test each role path (`anon`, authenticated user, service/admin backend).
2. Verify denied paths explicitly, not only happy path access.
3. Benchmark policy-heavy queries under realistic row counts.
4. Add regression tests for policies whenever schema changes.

## 8) Source links

- https://supabase.com/docs/guides/api/api-keys
- https://supabase.com/docs/guides/auth
- https://supabase.com/docs/guides/auth/sessions
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/launch-week/15

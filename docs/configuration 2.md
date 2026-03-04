# Runtime configuration

Lectra and the Share Extension can read Supabase coordinates from each target's `Info.plist`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

If either key is missing, the app falls back to the existing built-in defaults.

## Recommended setup

For each Xcode target:

1. Open target settings → **Info**.
2. Add `SUPABASE_URL` (String) and `SUPABASE_ANON_KEY` (String).
3. Keep production/staging values in xcconfig files per build configuration.

This avoids hardcoding environment coordinates directly into service code and makes key rotation easier.

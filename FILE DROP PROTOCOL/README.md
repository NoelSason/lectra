# File-Drop Installer Package

Package version: `1.1.0`  
Date: `February 25, 2026`

This package is for integrating DropBridge into:

1. an existing iOS/iPad uploader app
2. an existing Chrome extension receiver
3. a Supabase backend

## What this package gives you

1. Supabase schema install/rollback SQL
2. Edge Function source bundle (`register-device`, `upload-file`, `list-pending`, `update-upload-status`)
3. iOS native starter client (`DropBridgeClient.swift`) and pairing parser
4. extension integration contract and status rules
5. machine-readable API contract (`contracts/openapi.yaml`)
6. smoke test checklist

## Fast Start (for another agent)

1. Read `AGENT_HANDOFF.md`.
2. Apply `supabase/schema/install.sql`.
3. Deploy functions from `supabase/functions/*`.
4. Integrate iOS with `ios/DropBridgeClient.swift` and `ios/PairingLink.swift`.
5. Update extension with logic in `extension/EXTENSION_SETUP.md`.
6. Run `qa/SMOKE_TEST.md`.

## Core Architecture Assumptions

1. Client apps use publishable/anon key only.
2. Service role key exists only in Edge Function environment.
3. `drops` storage bucket is private.
4. RLS enabled with no public policies on app tables.
5. Device auth is `deviceId + deviceToken` (hashed in DB).

## Key Files

- `installer-manifest.json`
- `contracts/openapi.yaml`
- `docs/STATUS_MODEL.md`
- `supabase/INSTALL.md`
- `ios/IOS_SETUP.md`
- `extension/EXTENSION_SETUP.md`
- `qa/SMOKE_TEST.md`

## Date-sensitive note

Supabase quotas, pricing, and runtime limits may change. Re-check your dashboard limits before production rollout (as of February 25, 2026).

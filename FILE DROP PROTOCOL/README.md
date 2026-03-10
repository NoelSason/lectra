# File-Drop Installer Package

Package version: `1.3.0`  
Date: `March 10, 2026`

This package is for integrating DropBridge into:

1. an existing iOS/iPad uploader app
2. an existing Chrome extension receiver
3. a Supabase backend

## What this package gives you

1. Supabase schema install/rollback SQL
2. Edge Function source bundle (`register-device`, `upload-file`, `list-pending`, `update-upload-status`) plus account-linked v2 endpoints
3. Optional Lectra wake-hint path via private Realtime broadcast and APNs silent push
4. iOS native starter client (`DropBridgeClient.swift`) and pairing parser
5. extension integration contract and status rules
6. machine-readable API contract (`contracts/openapi.yaml`)
7. smoke test checklist

## Fast Start (for another agent)

1. Read `AGENT_HANDOFF.md`.
2. Apply `supabase/schema/install.sql`.
3. Apply `supabase/schema/dropbridge_v2_account_link.sql` for account-linked routing.
4. Apply `supabase/migrations/20260310113000_dropbridge_v2_lectra_wake_hints.sql`.
5. Deploy functions from `supabase/functions/*`.
6. Enable private-only Realtime channels before relying on wake subscriptions.
7. Integrate iOS with `ios/DropBridgeClient.swift`, `ios/PairingLink.swift`, and `wake-lectra-v2` support.
8. Update extension with logic in `extension/EXTENSION_SETUP.md`.
9. Run `qa/SMOKE_TEST.md`.

## Core Architecture Assumptions

1. Client apps use publishable/anon key only.
2. Service role key exists only in Edge Function environment.
3. `drops` storage bucket is private.
4. RLS enabled with no public policies on app tables.
5. Device auth is `deviceId + deviceToken` (v1) or account-linked user JWT + `deviceId` (v2).
6. Realtime and APNs are wake hints only; `synced_items` / storage remain canonical for Canvascope -> Lectra.

## Key Files

- `installer-manifest.json`
- `contracts/openapi.yaml`
- `docs/STATUS_MODEL.md`
- `supabase/INSTALL.md`
- `ios/IOS_SETUP.md`
- `extension/EXTENSION_SETUP.md`
- `qa/SMOKE_TEST.md`

## Date-sensitive note

Supabase quotas, pricing, and runtime limits may change. Re-check your dashboard limits before production rollout (as of March 10, 2026).

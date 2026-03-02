# Agent Handoff: Install DropBridge Into Existing Apps

## Outcome Required

1. iOS app can upload file to receiver device queue.
2. Existing extension auto-downloads upload and acknowledges status.
3. User-canceled download does not retry forever.
4. Zero-pairing v2 account-linked routing works when both clients are signed into same Supabase account.

## Step Order (do not reorder)

1. Backend install
- Execute `supabase/schema/install.sql`.
- Execute `supabase/schema/dropbridge_v2_account_link.sql`.
- Execute `supabase/migrations/20260302005800_dropbridge_v2_client_kind_lectra_ipad.sql`.
- Deploy all functions in `supabase/functions/`.
- Confirm v1 and v2 functions keep `verify_jwt = false` (JWT validated in function code), and only `cleanup-expired-uploads` uses `verify_jwt = true`.

2. iOS integration
- Add `ios/DropBridgeClient.swift`.
- Add `ios/PairingLink.swift`.
- Add pair-flow in app settings: paste pairing link -> parse -> store `deviceID/deviceToken` in Keychain.
- Wire upload button to `uploadFile(fileURL:)`.
- For zero-pairing mode, call `upload-file-v2` with user session JWT and no `deviceToken`.

3. Extension integration
- Ensure extension has persistent `deviceId` + `deviceToken`.
- Ensure extension calls:
  - `register-device`
  - `list-pending`
  - `update-upload-status`
- Map cancellation to terminal `canceled` state.
- For zero-pairing mode, use:
  - `register-device-v2`
  - `list-pending-v2`
  - `update-upload-status-v2`
  - `get-upload-status-v2`

4. Acceptance checks
- Run `qa/SMOKE_TEST.md` end-to-end.
- Capture one successful upload and one canceled upload.
- Verify same-account routing picks the most recently active receiver.
- Verify queued uploads expire after 24 hours and are cleaned by `cleanup-expired-uploads`.

## Non-negotiable constraints

1. Never expose service-role key in iOS app or extension.
2. Keep bucket private.
3. Only retry transient failures; cancellations are terminal.

## Deliverables

1. commit/PR with integration code
2. short runbook containing:
- env var names
- pair flow UX entrypoint
- where extension handles canceled status
- cron invocation for `cleanup-expired-uploads`

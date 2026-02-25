# Agent Handoff: Install DropBridge Into Existing Apps

## Outcome Required

1. iOS app can upload file to receiver device queue.
2. Existing extension auto-downloads upload and acknowledges status.
3. User-canceled download does not retry forever.

## Step Order (do not reorder)

1. Backend install
- Execute `supabase/schema/install.sql`.
- Deploy all functions in `supabase/functions/`.
- Confirm `supabase/config.toml` has `verify_jwt = false` for each function.

2. iOS integration
- Add `ios/DropBridgeClient.swift`.
- Add `ios/PairingLink.swift`.
- Add pair-flow in app settings: paste pairing link -> parse -> store `deviceID/deviceToken` in Keychain.
- Wire upload button to `uploadFile(fileURL:)`.

3. Extension integration
- Ensure extension has persistent `deviceId` + `deviceToken`.
- Ensure extension calls:
  - `register-device`
  - `list-pending`
  - `update-upload-status`
- Map cancellation to terminal `canceled` state.

4. Acceptance checks
- Run `qa/SMOKE_TEST.md` end-to-end.
- Capture one successful upload and one canceled upload.

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

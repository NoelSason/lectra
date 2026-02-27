# iOS Integration Setup

This package assumes you already have an iPad app and an existing extension.

## Goal

Use your iOS app as the uploader client while your extension acts as receiver.

For zero-setup mode, prefer account-linked v2 endpoints so users only need to sign into both apps with the same Google account.

## Inputs your iOS app needs

1. `supabaseURL` (for example `https://<ref>.supabase.co`)
2. `supabasePublishableKey` (or anon key)
3. `deviceID`
4. `deviceToken`

You can obtain `deviceID` and `deviceToken` from the extension pairing link.

In v2 mode, `deviceID` and `deviceToken` are not required in iOS upload calls.

## Recommended UX in your iOS app

1. Add a "Pair Receiver" screen.
2. Let user paste pairing link from extension popup.
3. Parse using `PairingLink.swift`.
4. Store credentials in Keychain.
5. Show paired receiver short ID in settings.

## Upload integration

1. Add `DropBridgeClient.swift` to your app target.
2. Build `DropBridgeConfig` from your stored pairing credentials.
3. Call:

```swift
let receipt = try await client.uploadFile(fileURL: localFileURL)
```

4. Show success if `receipt.ok == true`.

### v2 account-linked integration

1. Ensure user has active Supabase session JWT.
2. Call `POST /functions/v1/upload-file-v2` with multipart field `file`.
3. Include headers:
   - `apikey: <publishable-or-anon-key>`
   - `Authorization: Bearer <user access token>`
4. Handle `404` as "no active receiver found" (prompt user to open extension).

## ATS / network notes

1. Supabase uses HTTPS; ATS exceptions are usually not needed.
2. Keep uploads under 25 MB unless you increase server limit.

## Error handling expectations

1. `401/403` style errors map to invalid pairing token.
2. `413` maps to file too large.
3. Retry only for transient network failures.
4. Do not retry forever on explicit user cancellation.

## Security notes

1. Never embed service role key in iOS app.
2. Treat `deviceToken` as sensitive; store in Keychain.
3. Rotate token if device is lost (regenerate in extension, then re-pair iOS).

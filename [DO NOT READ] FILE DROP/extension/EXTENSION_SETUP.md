# Existing Extension Integration

This guide is for integrating DropBridge backend into an extension you already have.

## Required behavior

1. Extension has stable `deviceId` and long random `deviceToken`.
2. Extension polls `list-pending` every 30-300 seconds.
3. For each claimed upload, extension downloads file URL.
4. Extension calls `update-upload-status` with:
- `downloaded` on success
- `canceled` when user explicitly cancels
- `queued` on transient failures

## API headers for each call

- `apikey: <publishable-or-anon-key>`
- `Authorization: Bearer <publishable-or-anon-key>`

## Device bootstrap

1. Generate `deviceId` (UUID).
2. Generate `deviceToken` (minimum 32 chars random hex/base64).
3. Call `register-device`.
4. Provide pairing link to iOS app:

```text
https://your-upload-entrypoint?device=<deviceId>&token=<deviceToken>
```

## Cancel behavior (important)

If the download event indicates user canceled (for example `USER_CANCELED`), send `status = canceled`.

This prevents infinite redownload loops.

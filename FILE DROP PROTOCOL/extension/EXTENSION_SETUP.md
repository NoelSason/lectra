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

## v2 zero-pairing behavior (same-account routing)

When both Lectra and the extension use the same Supabase-authenticated Google account:

1. Persist a stable `deviceId` UUID.
2. Call `register-device-v2` using user JWT (no `deviceToken`).
3. Poll `list-pending-v2` with `{ deviceId, limit }`.
4. Acknowledge with `update-upload-status-v2`:
   - `downloaded` on success
   - `canceled` on user cancellation
   - `queued` on transient failure
5. Refresh presence by calling `register-device-v2` on startup and periodically.

## Instant receive: realtime `file_drop` wake (recommended)

Polling `list-pending-v2` on an interval adds up to one full interval of latency
before an incoming file is even noticed. To make Lectra -> Canvascope feel
instant, subscribe to the device's realtime channel and react the moment the
backend broadcasts, falling back to polling only as a safety net.

`upload-file-v2` now broadcasts a `file_drop` event to the receiver's private
channel immediately after queuing an upload. The channel topic is:

```text
dropbridge:user:<userId>:device:<deviceId>
```

(`userId` is the Supabase-auth user id; `deviceId` is the extension's stable
device UUID — the same one used with `register-device-v2` / `list-pending-v2`.)

Subscribe with `@supabase/supabase-js`:

```js
const channel = supabase.channel(
  `dropbridge:user:${userId}:device:${deviceId}`,
  { config: { private: true } },
);

channel
  .on("broadcast", { event: "file_drop" }, ({ payload }) => {
    // payload: { uploadId, fileName, sizeBytes }
    // React immediately: list-pending-v2 -> download from `drops`
    //                    -> update-upload-status-v2 { status: "downloaded" }.
    drainPendingUploads();
  })
  .subscribe();
```

Behavior notes:

1. Treat the broadcast as a wake hint, not the source of truth. Always reconcile
   via `list-pending-v2` so a missed broadcast (offline, reconnect) still drains.
2. Keep a slow `list-pending-v2` poll (e.g. every 60-300s) as a fallback.
3. Requires the channel to be marked `private`, matching the backend broadcast.
4. The same channel also carries `upload_status` events for files this device
   *sent*; ignore those on the receive path (Lectra consumes them).

## Canvascope -> Lectra wake hint

For the current Canvascope -> Lectra flow, keep the existing storage + `synced_items` write path as the canonical delivery model.

After the extension successfully:

1. uploads the PDF into `lectra_documents`, and
2. inserts or updates the `synced_items` row,

call `wake-lectra-v2` with the same authenticated user JWT:

```json
{
  "syncedItemId": "<synced_items.id>",
  "reason": "synced_item_inserted"
}
```

Behavior notes:

1. Treat `wake-lectra-v2` as best effort.
2. Do not fail the user-visible send flow if the wake hint fails after the canonical write succeeded.
3. Preserve any existing fast Canvascope -> Lectra behavior; this call is an acceleration hook, not a new source of truth.

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

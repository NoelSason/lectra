# Troubleshooting

## 404 when opening pairing link

Cause: upload entrypoint URL points to wrong route.

Fix:

1. Ensure uploader URL resolves to real page (`/web/` if hosted under subpath).
2. If deploying from repo root on Vercel, ensure root has redirect to `/web/`.

## Browser asks where to save each download

Cause: browser setting, not extension API behavior.

Fix:

1. Open `chrome://settings/downloads` (or `arc://settings/downloads`).
2. Disable "Ask where to save each file before downloading".

## Infinite retry loop after cancel

Cause: extension sends `queued` for user cancel.

Fix:

1. map user-cancel events to `status = canceled`.
2. ensure DB constraint includes `canceled` in allowed status values.

## Upload rejected as too large

Cause: backend enforces 25 MB per file.

Fix:

1. increase storage bucket file size limit.
2. update upload-file function max bytes check.
3. communicate max size in iOS UI.

# Upload Status Model

## States

1. `queued`: awaiting pickup by extension.
2. `downloading`: claimed by extension and download started.
3. `downloaded`: terminal success.
4. `canceled`: terminal user-canceled state (no retry loop).

## Transitions

1. iOS upload -> `queued`.
2. extension `list-pending` claims row -> `downloading`.
3. extension download complete -> `downloaded`.
4. extension interrupted:
- if user canceled: `canceled`
- if transient failure: `queued` (retry)

## Retry Rule

Only `queued` is eligible for re-pickup by `list-pending`.

## Wake Hint Rule

Realtime broadcasts and APNs silent pushes are hints only. They do not introduce new states and do not replace the queue row or `synced_items`/storage as the source of truth.

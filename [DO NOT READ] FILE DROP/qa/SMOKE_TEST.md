# Smoke Test Checklist

## Pre-check

1. Functions deployed and reachable.
2. iOS app paired with valid `device` and `token`.
3. Extension registered and polling.

## Test A: Happy path

1. Upload small file from iOS app.
2. Verify DB row enters `queued` then `downloading` then `downloaded`.
3. Verify file exists in extension download folder.

## Test B: User cancellation path

1. Upload second file from iOS app.
2. Cancel download on PC prompt (or cancel download in browser UI).
3. Verify DB row status becomes `canceled`.
4. Wait 2 poll cycles and verify it is not re-downloaded.

## Test C: Transient retry path

1. Simulate temporary network failure during extension download.
2. Verify status returns to `queued`.
3. Restore network and verify it is downloaded on next poll.

## Negative auth test

1. Tamper one character in `deviceToken` on iOS side.
2. Verify upload fails with auth error.

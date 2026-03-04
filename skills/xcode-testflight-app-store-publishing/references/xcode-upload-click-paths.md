# Xcode Upload Click Paths

## Preflight Checks

1. Confirm you are signed in to Xcode with the Apple ID tied to App Store Connect access.
2. Confirm target `Bundle Identifier` matches the app record in App Store Connect.
3. Increment build number (`CFBundleVersion`) before every upload.
4. Select a generic or physical device destination.

## Archive In Xcode

1. In Xcode: `Product` > `Archive`.
2. Wait for Organizer to open the archive list.
3. Select latest archive for the target app.

## Validate Archive (Recommended)

1. Click `Validate App`.
2. Choose `App Store Connect` distribution context.
3. Review validation messages and fix issues before upload.

## Upload Archive To App Store Connect

1. Click `Distribute App`.
2. Select `App Store Connect`.
3. Select `Upload`.
4. Review Distribution Options:
- `Strip Swift symbols`.
- `Manage version and build number`.
- `Upload your app's symbols to receive symbolicated reports from Apple`.
- `Include bitcode for iOS content` (iOS-only option).
5. Review Signing Options:
- `Automatically manage signing` (default for most teams).
- `Manually manage signing` (custom cert/profile workflow).
- If needed, use `Manage Certificates` to create/import certificates.
6. Review summary, entitlements, and provisioning.
7. Click `Upload`.
8. Wait for processing and confirm build appears in App Store Connect > TestFlight.

## Internal-Only Beta Mode

- If a build is marked `TestFlight Internal Only` (Xcode/Xcode Cloud upload setting), use it only with internal tester groups.
- Do not expect external testing or App Store release from an internal-only build.

## Common Upload Blockers

- `Invalid Binary`: Re-archive with corrected signing/entitlements or SDK/toolchain requirements.
- `Missing Compliance`: Add export compliance answers in App Store Connect before testing/review.
- Build not visible yet: Wait for processing completion and refresh TestFlight tab.

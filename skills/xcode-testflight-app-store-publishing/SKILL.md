---
name: xcode-testflight-app-store-publishing
description: End-to-end workflow for shipping Apple platform apps from Xcode to TestFlight and App Store Connect. Covers archive, validation, upload options, internal and external beta testing setup, Beta App Review, App Review submission, and App Store release choices. Use when preparing a TestFlight build, submitting a production build, or troubleshooting why a build cannot be tested or released.
---

# Xcode TestFlight App Store Publishing

## Execute Workflow

1. Determine target path.
- Choose one of: `TestFlight internal only`, `TestFlight internal + external`, or `App Store release`.
2. Execute Xcode upload flow.
- Follow [xcode-upload-click-paths.md](references/xcode-upload-click-paths.md).
- Complete archive, validation, and distribution option/signing decisions before upload.
3. Configure TestFlight.
- Follow [testflight-workflow.md](references/testflight-workflow.md).
- Start with internal testing, then external testing when needed.
4. Submit for App Store release.
- Follow [app-store-release-workflow.md](references/app-store-release-workflow.md).
- Attach build, add for review, submit for review, and choose release behavior.
5. Resolve blockers by status.
- Use the status sections in each reference to handle `Missing Compliance`, `In Beta Review`, `Invalid Binary`, `Pending Developer Release`, and rejection loops.
6. Re-check date-based Apple requirements.
- Before each upload, confirm minimum Xcode and SDK requirements in Apple’s upcoming requirements page.
- Use [apple-official-sources.md](references/apple-official-sources.md) for direct URLs.

## Guardrails

- Keep `CFBundleVersion` incrementing for every upload, even when `CFBundleShortVersionString` stays the same.
- Keep App Store Connect app record bundle ID exactly matched to Xcode target bundle identifier.
- Complete export compliance and Test Information before inviting external testers.
- Prefer manual App Store release when launch timing matters.

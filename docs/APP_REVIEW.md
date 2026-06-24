# App Review — Submission Checklist & Notes
I AM ADDING SOMETHING RIGHT HERE

Operational companion to the code changes that brought Lectra/Canvascope into
line with the App Review Guidelines. Items marked **[ASC]** are configured in
App Store Connect, **[BACKEND]** in Supabase, **[CODE]** already shipped in the
app binary.

---

## Current local release audit — June 21, 2026

**Current build identity**

- Bundle ID: `com.canvascope.Lectra`
- App name: `Lectra`
- Marketing version: `1.0`
- Build number: `4`
- Deployment target: iOS/iPadOS `17.2`
- Team ID: `3D8X943476`
- Launch screen: `UILaunchStoryboardName = LaunchScreen`
- App icon asset: `AppIcon`

**Apple upload requirement**

- Apple's current upcoming requirements page says uploads to App Store Connect
  must be built with Xcode 26 or later using the iOS/iPadOS 26 SDK or later.
- Local archive metadata satisfies this source-side requirement:
  `DTXcode = 2650`, `DTSDKName = iphoneos26.5`.

**Local verification completed**

- `xcodebuild -project Lectra.xcodeproj -scheme Lectra -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' test`
  passed: 22 unit tests and 10 UI tests.
- `xcodebuild -project Lectra.xcodeproj -scheme Lectra -configuration Release -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
  passed and ran Xcode's shallow store validation.
- `xcodebuild -project Lectra.xcodeproj -scheme Lectra -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/LectraAppReview-20260621.xcarchive archive`
  passed.
- `xcodebuild -exportArchive -archivePath /tmp/LectraAppReview-20260621.xcarchive -exportPath /tmp/LectraAppReview-export -exportOptionsPlist docs/AppStoreExportOptions.plist -allowProvisioningUpdates`
  currently fails on local Apple signing credentials; see Distribution signing.
- Live simulator launch on the booted iPad Pro 13-inch (M5) showed a
  Documents-only sidebar with no Course Brain or Gradescope entry points.
- `npx -y deno-bin@2.2.7 fmt --check supabase/functions/delete-account/index.ts`
  and `npx -y deno-bin@2.2.7 check supabase/functions/delete-account/index.ts`
  passed.
- `https://www.canvascope.org/privacy` and `https://www.canvascope.org` returned
  HTTP 200.

**Current blocking items**

The local source, tests, and archive are passing. Before submission, finish the
distribution signing, App Store Connect, and backend checks that cannot be fully
verified from this checkout:

- restore a usable App Store Connect/Xcode account session and iOS Distribution
  signing identity for export;
- provide reviewer access and notes;
- complete app privacy, age rating, pricing/availability, and export compliance;
- confirm the Supabase Apple provider and `delete-account` Edge Function are
  deployed and tested against a throwaway production account.

## 1. Reviewer access (Guideline 2.1) **[ASC]**

Sign-in (Google / Sign in with Apple) gates cloud-backed account data, so App
Review needs a working path:

- Provide a **demo account** in App Store Connect → App Review Information:
  - A Canvascope login (Sign in with Apple or Google) seeded with a few sample
    PDFs in the library so the reviewer can open the editor and annotate.
- In **Notes for Review**, explain the non-obvious flows explicitly:
  - "Documents are pushed from the Canvascope web/Chrome extension; the demo
    account already contains sample PDFs so no external push is required."
  - "The app no longer ships Canvas course import, Course Brain, or Gradescope
    workflows. The TestFlight/App Store build is focused on first-party Lectra
    document import, annotation, intelligence, backup, and Canvascope handoff."
  - Describe the on-device Apple Intelligence features (summaries, tags, study
    aids) run entirely on-device via Foundation Models.

## 2. App privacy "nutrition labels" (Guideline 5.1.1) **[ASC]**

Declare in App Store Connect → App Privacy. Must match `PrivacyInfo.xcprivacy`:

| Data type | Linked to user | Used for tracking | Purpose |
|-----------|----------------|-------------------|---------|
| Email address | Yes | No | App Functionality |
| Name | Yes | No | App Functionality |
| Other user content (PDFs, notes) | Yes | No | App Functionality |
| Device ID (app-generated push/install UUID) | Yes | No | App Functionality |

No data is used for tracking; no third-party analytics or ad SDKs are present.

## 3. Privacy policy & support URLs (Guidelines 5.1.1(i), 1.5) **[ASC + CODE]**

- **[CODE]** In-app links surface in the sign-in screen and Settings → Account:
  - Privacy Policy → https://www.canvascope.org/privacy
  - Support → https://www.canvascope.org
- **[ASC]** Set the same Privacy Policy URL and a reachable Support URL in App
  Store Connect. Both URLs returned HTTP 200 in the local release audit.

## 4. Sign in with Apple (Guideline 4.8) **[CODE + BACKEND]**

- **[CODE]** `SignInWithAppleButton` added to `AuthView`; `AuthManager` exchanges
  the Apple identity token for a Supabase session via `signInWithIdToken`.
- **[CODE]** `com.apple.developer.applesignin` entitlement added.
- **[BACKEND]** Enable the **Apple** provider in Supabase →
  Authentication → Providers:
  - Add the Services ID / Apple `client_id`, Team ID, Key ID and the `.p8`
    secret (or configure the native flow). The nonce is already sent by the app.
  - Ensure the Apple Service is configured for native iOS sign-in for bundle id
    `com.canvascope.Lectra`.

## 5. In-app account deletion (Guideline 5.1.1(v)) **[CODE + BACKEND]**

- **[CODE]** Settings → Account → "Delete Account" (confirmation dialog) calls
  `AuthManager.deleteAccount()`, which invokes the `delete-account` Edge
  Function and then signs out.
- **[BACKEND]** Deploy the function (service-role; never shipped in the app):

  ```bash
  supabase functions deploy delete-account --project-ref vcadcdgnwxjlgaoqktkd
  ```

  `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
  injected by the runtime — no extra secrets to set. The function deletes the
  user's `synced_items` rows, their `lectra_documents` storage objects, device
  registrations (best-effort), and the auth user. Required storage and database
  cleanup now fails closed before auth-user deletion if Supabase returns an
  error.

  Verify after deploy: sign in on a throwaway account, delete it, and confirm
  the row in `auth.users` and their storage folder are gone.

## 6. Push notifications (Guideline 4.5.4) **[CODE]**

- `aps-environment` set to `production` for TestFlight/App Store builds.
- Push is silent (background sync wake) only — not required to use the app, and
  carries no marketing. No user-facing notification permission is requested.

## 7. Data security (Guidelines 1.6 / 5.1.6) **[CODE]**

- Legacy third-party credential and link caches are scrubbed on sign-out,
  account deletion, and account-scoped purge. The app no longer reads those
  credentials for active functionality.
- Signing out or crossing an account boundary purges account-scoped local PDFs,
  folders, recents, title overrides, backups, thumbnails, search indexes,
  pending sync work, and legacy third-party integration caches.

## 8. Privacy manifests **[CODE + ASC]**

- **[CODE]** `Lectra.app` includes `PrivacyInfo.xcprivacy` for account data,
  user PDFs/notes, device ID, UserDefaults, file timestamp, and disk-space API
  use.
- **[CODE]** `LectraShareExtension.appex` includes its own
  `PrivacyInfo.xcprivacy` because it reads a shared file and uploads the
  user-selected content to the Lectra/Canvascope upload service.
- **[ASC]** Keep App Store Connect App Privacy answers aligned with both
  manifests before submission.

## 9. Distribution signing **[ASC]**

- Local archive succeeds, but the current local keychain only exposes an Apple
  Development signing identity.
- Fresh App Store Connect export fails with:
  - no usable Xcode/App Store account credentials;
  - no `iOS Distribution` signing certificate available locally.
- Reauthenticate the Apple Developer account in Xcode or install a valid
  distribution certificate/private key, then rerun export for the final
  submission build with the checked-in template:

  ```bash
  xcodebuild -exportArchive \
    -archivePath /tmp/LectraAppReview-20260621.xcarchive \
    -exportPath /tmp/LectraAppReview-export \
    -exportOptionsPlist docs/AppStoreExportOptions.plist \
    -allowProvisioningUpdates
  ```

## 10. App Store Connect metadata **[ASC]**

- Complete updated age-rating questions in App Store Connect before submission;
  Apple's 2026 age-rating update is already in effect.
- Complete pricing and availability.
- Complete export compliance for the selected build before TestFlight or App
  Review distribution.
- Create at least one internal TestFlight group before external testing.

---

## Removed before release

- **Third-party course and submission workflows (Guidelines 5.2.2 / 5.2.3).**
  Canvas course import, Course Brain, and Gradescope submission/template
  workflows were removed from the app binary before release because they relied
  on unapproved third-party service access. Reintroduce similar workflows only
  through sanctioned APIs, written authorization, or a first-party equivalent.

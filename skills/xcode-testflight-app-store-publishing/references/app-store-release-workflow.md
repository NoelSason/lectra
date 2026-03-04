# App Store Release Workflow

## Scope

Use this workflow to submit and release a production version after beta validation.

## Submission Readiness

1. Confirm app metadata and policy sections are complete for the target platform version.
2. Confirm screenshots, app description, keywords, support URL, marketing URL (if used), privacy policy URL, age rating, and App Review information are complete as required.
3. Confirm pricing and availability settings are configured.
4. Confirm export compliance is complete for the selected build.

## Attach Build To Version

1. Open `App Store Connect` > `Apps` > `{Your App}`.
2. Open the platform version page (for example iOS app version).
3. In the `Build` section, click to select the processed build you want to ship.

## Submit For Review

1. Click `Add for Review`.
2. Add the version to an existing draft review submission or create a new submission.
3. Click `Submit for Review`.
4. Monitor statuses: `Waiting for Review` -> `In Review` -> `Pending Developer Release` or `Ready for Sale`.

## Choose Release Behavior

Set this before final approval in the version page:

- `Manually release this version`.
- `Automatically release this version`.
- `Automatically release this version after App Review, no earlier than` (pick date/time).

## If Manual Release Is Selected

1. Wait until status is `Pending Developer Release`.
2. Click `Release This Version` when you are ready to go live.

## Availability And Distribution Options

1. Open pricing and availability sections.
2. Select countries/regions availability.
3. Choose distribution method where applicable.
4. Save changes before or during submission flow.

## Current Date-Sensitive Requirement Check

- Apple’s current upcoming requirement page states that starting **April 28, 2026**, uploads for apps and updates must be built with `Xcode 26` and the iOS 18, iPadOS 18, tvOS 18, visionOS 2, or watchOS 11 SDK.
- Re-check this page before every release because Apple updates these dates.

## Rejection Loop

1. Read rejection reason in Resolution Center.
2. Fix the issue in code/metadata/legal content.
3. Upload a new build if required.
4. Re-submit using `Add for Review` and `Submit for Review`.

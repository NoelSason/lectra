# TestFlight Workflow

## Scope

Use this workflow to move from Xcode upload to active beta testing for internal and external testers.

## App Store Connect Preflight

1. Ensure Apple Developer Program membership and active agreements.
2. Ensure app record exists: `Apps` > `+` > `New App`.
3. Set required app record fields: platform, name, primary language, bundle ID, SKU, and access.

## Upload Build From Xcode

1. Complete the steps in [xcode-upload-click-paths.md](xcode-upload-click-paths.md).
2. Wait for build processing in TestFlight.

## Internal Testing Path (Fastest)

1. Open `App Store Connect` > `Apps` > `{Your App}` > `TestFlight`.
2. Create an internal testing group.
3. Add internal testers (up to 100 people with App Store Connect access).
4. Assign a build to the group.
5. Choose automatic or manual distribution behavior for new builds.
6. Confirm testers can install from the TestFlight app.

## External Testing Path

1. Complete Test Information in TestFlight:
- Beta app description.
- Feedback email.
- Contact information and sign-in/demo instructions when applicable.
2. Create an external testing group.
- Keep at least one internal testing group configured (required dependency in current App Store Connect flow).
3. Add build to external group.
4. Submit build for Beta App Review when prompted (typically first build of each version).
5. After approval, invite testers:
- Email invites.
- Public link invites (up to 10,000 external testers total per app).

## Export Compliance For Beta Builds

1. If build shows `Missing Compliance`, open build details in TestFlight.
2. Provide export compliance answers.
3. Save and re-check build status.

## Status Interpretation

- `Processing`: Apple is still ingesting build; wait.
- `Ready to Test`: Build can be assigned to tester groups.
- `In Beta Review`: External test approval pending.
- `Testing`: Build actively distributed.
- `Expired`: Build exceeded TestFlight availability window (90 days); upload a new build.

## Practical Sequence

1. Upload build.
2. Run internal testing first.
3. Fix blockers and iterate quickly.
4. Promote stable build to external testing.
5. Use external feedback to finalize App Store submission build.

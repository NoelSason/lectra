# Removed Course Integrations

This note preserves the implementation shape of the removed course and
submission workflows without shipping the old code in the app target.

## Why It Was Removed

Course Brain, Canvas course-file import, and Gradescope template/submission
workflows used direct third-party web/API/session access that is not approved
for release. They were removed from the iPad app before TestFlight/App Store
preparation.

## Former Architecture

- Library sidebar tabs exposed Course Brain and Gradescope next to Documents.
- Course Brain normalized course snapshots into course twins, assignments,
  resources, evidence links, and graph/orbit views.
- Canvas import used stored web/session cookies plus API and web-view fallback
  fetchers to discover and download PDFs into managed import folders.
- Gradescope used a manager, HTML parsing, keychain session snapshots, template
  download, preflight, page assignment, and submission sheets.
- The PDF editor top bar exposed a Gradescope submit action beside the
  first-party Lectra handoff.
- Settings displayed third-party session status and expiration diagnostics.

## Current Release State

- Shipped UI now exposes only Documents in the primary sidebar.
- The PDF editor no longer includes Gradescope submit UI.
- The create menu no longer includes Gradescope template import.
- Canvas URL query schemes were removed from `Info.plist`.
- Old source directories and tests were deleted from the app target.
- Legacy stored cookies, keychain snapshots, and link caches are only scrubbed
  during sign-out/account deletion/account purge; they are not read to power
  features.
- Old imported third-party folders are migrated to neutral local "Imported
  Files" folders so users keep their PDFs without retaining special integration
  behavior.

## Reimplementation Constraints

Rebuild a similar idea only after one of these is true:

- A sanctioned public API supports the needed course/submission workflow.
- Written authorization is retained for the third-party service integration.
- The workflow is rebuilt as a first-party Canvascope/Lectra feature without
  automating or scraping third-party services.

Keep any future implementation behind a feature flag until the legal/API basis,
privacy disclosures, App Review notes, and user-facing account controls are all
ready.

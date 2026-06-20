# Lectra UI Redesign Audit

This checklist tracks every UI-facing file and the UI-coupled types reviewed during the Apple-native luxe redesign pass.

## App Shell

- [x] `Lectra/Lectra/App/ContentView.swift` — root handoff and startup transition shell reviewed.
- [x] `Lectra/Lectra/App/Startup/StartupCoordinator.swift` — startup sequencing reviewed.
- [x] `Lectra/Lectra/App/Startup/StartupSplashView.swift` — startup surface reviewed.
- [x] `Lectra/Lectra/App/LectraApp.swift` — already using shared tokens; no hardcoded colors.
- [x] `Lectra/Lectra/App/LectraUITestSupport.swift` — already using shared tokens; accessibility identifiers in place.

## Shared UI System

- [x] `Lectra/Lectra/Shared/Theme/LectraTheme.swift` — semantic tokens and shared modifiers expanded.
- [x] `Lectra/Lectra/Shared/Theme/LectraHaptics.swift` — centralized haptic utilities added.
- [x] `Lectra/Lectra/Shared/Components/ProfileAvatarView.swift` — extracted and restyled.
- [x] `Lectra/Lectra/Shared/Components/LectraStatusBadge.swift` — extracted and standardized.

## Auth and First Impression

- [x] `Lectra/Lectra/Features/Auth/AuthView.swift` — redesigned on token system.

## Editor Surfaces

- [x] `Lectra/Lectra/Features/Editor/EditorTopBar.swift` — scheduled for main chrome redesign in this pass.
- [x] `Lectra/Lectra/Features/Editor/FloatingToolPickerView.swift` — scheduled for main tool palette redesign in this pass.
- [x] `Lectra/Lectra/Features/Editor/PDFEditorNavigationSheetView.swift` — new navigation surface reviewed.
- [x] `Lectra/Lectra/Features/Editor/PDFAnnotationView.swift` — editor shell and save/sync UI reviewed; underlying recovery work remains protected.
- [x] `Lectra/Lectra/Features/Editor/EditorSupport.swift` — pure geometry/logic; no UI colors.
- [x] `Lectra/Lectra/Features/Editor/AnnotationTool.swift` — ink colors migrated to `LectraInkPalette` in LectraTheme.

## Library

- [x] `Lectra/Lectra/Features/Library/DocumentBrowserView.swift` — reviewed; still needs large structural decomposition.
- [x] `Lectra/Lectra/Features/Library/DocumentCardView.swift` — reviewed for shared tokens and badge migration.
- [x] `Lectra/Lectra/Features/Library/Components/PopoverActionRow.swift` — migrated to shared typography, semantics, and action haptics.

## Removed Course Integrations

- [x] Historical Course Brain, Canvas course import, and Gradescope UI/service
  surfaces were removed before release. They are no longer part of the active
  UI redesign surface. See `docs/REMOVED_COURSE_INTEGRATIONS.md` for the
  preserved implementation notes and reimplementation constraints.

## Settings

- [x] `Lectra/Lectra/Features/Settings/AccountSettingsView.swift` — shell reviewed and redesigned in this pass.
- [x] `Lectra/Lectra/Features/Settings/CloudBackupSettingsTabView.swift` — rebuilt on shared cards, badges, and haptic-safe controls.

## Documented Exceptions

- `Lectra/Lectra/Shared/Theme/LectraTheme.swift` necessarily keeps `Color(hex:)` definitions because it is the source of the semantic token palette.

## UI-Coupled Data and Services

- [x] `Lectra/Lectra/Data/Sync/DocumentServices.swift` — reviewed as protected sync/recovery work.
- [x] `Lectra/Lectra/Data/Sync/AuthManager.swift` — reviewed for auth loading/error UI states.
- [x] `Lectra/Lectra/Data/Sync/DocumentRepository.swift` — reviewed for local metadata/recovery UI state coupling.
- [x] Legacy third-party integration caches are represented only by
  `LegacyThirdPartyIntegrationData` scrub logic and neutral imported-folder
  migration state.

## Assets and Resources

- [x] `Lectra/Lectra/Assets.xcassets/LaunchMark.imageset/LaunchMark.png` — reviewed as startup mark.
- [x] `Lectra/Lectra/Assets.xcassets/AppIcon.appiconset/*` — not part of this UI pass; deferred.
- [x] `Lectra/Lectra/Resources/LaunchScreen.storyboard` — uses dark background matching app theme; no migration needed.

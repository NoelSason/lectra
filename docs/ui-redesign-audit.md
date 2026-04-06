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

## Course Brain

- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainPane.swift` — reviewed for chrome redesign.
- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainOrbitView.swift` — reviewed for visual/token migration.
- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainSpriteView.swift` — reviewed for host chrome integration.
- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainSpriteScene.swift` — retains intentional SpriteKit visualization colors (see Documented Exceptions).
- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainGraphBuilder.swift` — no UI colors; pure algorithmic graph building.
- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainViewModel.swift` — no UI colors; data layer only.
- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainModels.swift` — no UI colors; data models only.
- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainMissionModels.swift` — no UI colors; data models only.
- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainPDFDownloader.swift` — no UI colors; uses only `.systemBackground`.
- [x] `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainConceptExtractor.swift` — no UI colors; text processing only.

## Settings

- [x] `Lectra/Lectra/Features/Settings/AccountSettingsView.swift` — shell reviewed and redesigned in this pass.
- [x] `Lectra/Lectra/Features/Settings/IntegrationsSettingsView.swift` — status cards reviewed and redesigned in this pass.
- [x] `Lectra/Lectra/Features/Settings/CloudBackupSettingsTabView.swift` — rebuilt on shared cards, badges, and haptic-safe controls.

## Gradescope

- [x] `Lectra/Lectra/Features/Gradescope/GradescopeHubView.swift` — reviewed for auth/workspace shell redesign.
- [x] `Lectra/Lectra/Features/Gradescope/GradescopeSubmitSheet.swift` — major card/token/haptic pass completed without changing workflow behavior.
- [x] `Lectra/Lectra/Features/Gradescope/GradescopeAssignmentPickerSheet.swift` — migrated to shared sheet language.
- [x] `Lectra/Lectra/Features/Gradescope/GradescopeWebLoginSheet.swift` — migrated to shared sheet language and retry feedback.
- [x] `Lectra/Lectra/Features/Gradescope/GradescopeGroupMembersSheet.swift` — rebuilt on shared cards and button styles.
- [x] `Lectra/Lectra/Features/Gradescope/GradescopePageAssignmentSheet.swift` — rebuilt on shared cards and button styles.
- [x] `Lectra/Lectra/Features/Gradescope/GradescopeSubmissionWebSheet.swift` — migrated to shared sheet chrome.
- [x] `Lectra/Lectra/Features/Gradescope/TechnicalDetailsDisclosure.swift` — typography and card cleanup completed.

## Documented Exceptions

- `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainOrbitView.swift` retains several raw accent colors intentionally for course/type differentiation and graph-adjacent data expression rather than shared chrome.
- `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainPane.swift` retains some status color mappings where they communicate submission-state semantics tied to Course Brain data.
- `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainSpriteScene.swift` retains hardcoded UIColors for SpriteKit hub palette, satellite type colors, and scene backgrounds — intentional data visualization colors for the graph rendering engine.
- `Lectra/Lectra/Features/Library/CourseBrain/CourseBrainSpriteView.swift` retains a dark background UIColor matching the SpriteScene backdrop.
- `Lectra/Lectra/Shared/Theme/LectraTheme.swift` necessarily keeps `Color(hex:)` definitions because it is the source of the semantic token palette.

## UI-Coupled Data and Services

- [x] `Lectra/Lectra/Data/Sync/DocumentServices.swift` — reviewed as protected sync/recovery work.
- [x] `Lectra/Lectra/Data/Sync/AuthManager.swift` — reviewed for auth loading/error UI states.
- [x] `Lectra/Lectra/Data/Sync/DocumentRepository.swift` — reviewed for local metadata/recovery UI state coupling.
- [x] `Lectra/Lectra/Data/Gradescope/GradescopeManager.swift` — reviewed for auth/busy/error/session UI states.
- [x] `Lectra/Lectra/Data/Gradescope/GradescopeModels.swift` — reviewed for view-facing labels and selection data.
- [x] Other `Lectra/Lectra/Data/Gradescope/*.swift` files — no hardcoded UI colors; data/service layer only.

## Assets and Resources

- [x] `Lectra/Lectra/Assets.xcassets/LaunchMark.imageset/LaunchMark.png` — reviewed as startup mark.
- [x] `Lectra/Lectra/Assets.xcassets/AppIcon.appiconset/*` — not part of this UI pass; deferred.
- [x] `Lectra/Lectra/Resources/LaunchScreen.storyboard` — uses dark background matching app theme; no migration needed.

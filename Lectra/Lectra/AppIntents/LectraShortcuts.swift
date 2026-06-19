//
//  LectraShortcuts.swift
//  Lectra
//
//  Surfaces Lectra's App Intents to the Shortcuts app and Siri with spoken
//  trigger phrases. The compiler discovers this provider automatically.
//

import AppIntents

struct LectraShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .red }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SummarizeDocumentIntent(),
            phrases: [
                "Summarize \(\.$document) in \(.applicationName)",
                "Summarize my document in \(.applicationName)"
            ],
            shortTitle: "Summarize Document",
            systemImageName: "text.alignleft"
        )
        AppShortcut(
            intent: GenerateStudyAidsIntent(),
            phrases: [
                "Make flashcards from \(\.$document) in \(.applicationName)",
                "Create study cards in \(.applicationName)"
            ],
            shortTitle: "Generate Flashcards",
            systemImageName: "rectangle.on.rectangle.angled"
        )
        AppShortcut(
            intent: OpenDocumentIntent(),
            phrases: [
                "Open \(\.$document) in \(.applicationName)"
            ],
            shortTitle: "Open Document",
            systemImageName: "doc.text"
        )
    }
}

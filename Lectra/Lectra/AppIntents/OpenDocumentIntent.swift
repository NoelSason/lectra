//
//  OpenDocumentIntent.swift
//  Lectra
//
//  "Open ⟨document⟩ in Lectra" — launches the app and opens the document in
//  the annotation editor. Conforms to OpenIntent so the system knows it
//  brings the app to the foreground.
//

import AppIntents
import Foundation

extension Notification.Name {
    /// Posted by OpenDocumentIntent; observed by the library to route to the editor.
    static let lectraOpenDocumentRequest = Notification.Name("LectraOpenDocumentRequest")
}

struct OpenDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Document"
    static var description = IntentDescription("Open a Lectra document in the editor.")
    static var openAppWhenRun = true

    @Parameter(title: "Document")
    var document: LectraDocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$document)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .lectraOpenDocumentRequest,
            object: nil,
            userInfo: ["documentId": document.id.uuidString]
        )
        return .result()
    }
}

//
//  LectraDocumentEntity.swift
//  Lectra
//
//  Exposes a Lectra document to the system as an AppEntity so Siri, Spotlight,
//  and the Shortcuts app can reference "the Calc lecture" by name.
//

import AppIntents

struct LectraDocumentEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Document",
        numericFormat: "\(placeholder: .int) documents"
    )

    static var defaultQuery = LectraDocumentEntityQuery()

    let id: UUID

    @Property(title: "Title")
    var title: String

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }

    init(_ indexed: LectraIndexedDocument) {
        self.init(id: indexed.id, title: indexed.title)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "Lectra document")
    }
}

struct LectraDocumentEntityQuery: EntityQuery {
    func entities(for identifiers: [LectraDocumentEntity.ID]) async throws -> [LectraDocumentEntity] {
        let wanted = Set(identifiers)
        return LectraDocumentIndex.all()
            .filter { wanted.contains($0.id) }
            .map(LectraDocumentEntity.init)
    }

    func suggestedEntities() async throws -> [LectraDocumentEntity] {
        Array(LectraDocumentIndex.all().prefix(12)).map(LectraDocumentEntity.init)
    }
}

extension LectraDocumentEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [LectraDocumentEntity] {
        LectraDocumentIndex.search(string).map(LectraDocumentEntity.init)
    }
}

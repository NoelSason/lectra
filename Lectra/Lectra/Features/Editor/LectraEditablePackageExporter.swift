import Foundation

@MainActor
enum LectraEditablePackageExporter {
    private struct Manifest: Codable {
        let version: Int
        let documentId: UUID
        let title: String
        let createdAt: Date
        let annotationSchemaVersion: Int
        let files: [String]
    }

    static func preparedPackageURL(
        documentId: UUID,
        title: String,
        repository: DocumentRepository,
        originalPDFURL: URL?
    ) throws -> URL {
        let fileManager = FileManager.default
        let baseName = ExportNamer.sanitize(title).isEmpty ? "Document" : ExportNamer.sanitize(title)
        let packageRoot = fileManager.temporaryDirectory
            .appendingPathComponent("editable-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("\(baseName).lectra", isDirectory: true)

        try fileManager.createDirectory(at: packageRoot, withIntermediateDirectories: true)

        var files: [String] = []
        try copyIfPresent(
            source: originalPDFURL,
            destination: packageRoot.appendingPathComponent("original.pdf"),
            relativeName: "original.pdf",
            files: &files
        )
        try copyIfPresent(
            source: repository.localAnnotatedPDFURL(for: documentId),
            destination: packageRoot.appendingPathComponent("flattened.pdf"),
            relativeName: "flattened.pdf",
            files: &files
        )

        let annotationsURL = repository.localAnnotationsURL(for: documentId)
        if !fileManager.fileExists(atPath: annotationsURL.path),
           let drawingsData = repository.loadLocalDrawings(documentId: documentId),
           let drawingStore = try? JSONDecoder().decode(InkDrawingStore.self, from: drawingsData) {
            try? repository.saveLocalAnnotations(
                LectraAnnotationStore(documentId: documentId, migrating: drawingStore),
                documentId: documentId
            )
        }

        try copyIfPresent(
            source: repository.localDrawingsURL(for: documentId),
            destination: packageRoot.appendingPathComponent("drawings.dat"),
            relativeName: "drawings.dat",
            files: &files
        )
        try copyIfPresent(
            source: repository.localAnnotationsURL(for: documentId),
            destination: packageRoot.appendingPathComponent("annotations.json"),
            relativeName: "annotations.json",
            files: &files
        )
        try copyIfPresent(
            source: repository.localMetadataURL(for: documentId),
            destination: packageRoot.appendingPathComponent("metadata.json"),
            relativeName: "metadata.json",
            files: &files
        )

        let manifest = Manifest(
            version: 1,
            documentId: documentId,
            title: title,
            createdAt: Date(),
            annotationSchemaVersion: LectraAnnotationStore.currentVersion,
            files: files.sorted()
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: packageRoot.appendingPathComponent("manifest.json"), options: [.atomic])

        return packageRoot
    }

    private static func copyIfPresent(
        source: URL?,
        destination: URL,
        relativeName: String,
        files: inout [String]
    ) throws {
        guard let source, FileManager.default.fileExists(atPath: source.path) else { return }
        try FileManager.default.copyItem(at: source, to: destination)
        files.append(relativeName)
    }
}

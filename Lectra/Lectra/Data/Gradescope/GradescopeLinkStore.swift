import Foundation

final class GradescopeLinkStore {
    private struct Payload: Codable {
        var linksByDocumentID: [String: GSLinkedDocument]
        var recentSubmissionHashes: [String: Date]
    }

    private let linksKey = "lectra_gradescope_links_v1"

    private func loadPayload() -> Payload {
        guard let data = UserDefaults.standard.data(forKey: linksKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload(linksByDocumentID: [:], recentSubmissionHashes: [:])
        }
        return payload
    }

    private func savePayload(_ payload: Payload) {
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(encoded, forKey: linksKey)
    }

    func allLinks() -> [GSLinkedDocument] {
        Array(loadPayload().linksByDocumentID.values)
    }

    func link(for documentId: UUID) -> GSLinkedDocument? {
        loadPayload().linksByDocumentID[documentId.uuidString]
    }

    func upsertLink(documentId: UUID, courseId: String, assignmentId: String, mode: GSLinkMode) {
        var payload = loadPayload()
        let key = documentId.uuidString
        let previous = payload.linksByDocumentID[key]

        payload.linksByDocumentID[key] = GSLinkedDocument(
            documentId: documentId,
            courseId: courseId,
            assignmentId: assignmentId,
            mode: mode,
            linkedAt: previous?.linkedAt ?? Date(),
            lastSubmittedAt: previous?.lastSubmittedAt,
            lastSubmissionURL: previous?.lastSubmissionURL
        )

        savePayload(payload)
    }

    func removeLink(for documentId: UUID) {
        var payload = loadPayload()
        payload.linksByDocumentID.removeValue(forKey: documentId.uuidString)
        savePayload(payload)
    }

    func recordSubmission(documentId: UUID?, assignmentId: String, fileHash: String, submissionURL: URL?, submittedAt: Date = Date()) {
        var payload = loadPayload()
        pruneOldHashes(in: &payload.recentSubmissionHashes)

        let hashKey = makeHashKey(assignmentId: assignmentId, fileHash: fileHash)
        payload.recentSubmissionHashes[hashKey] = submittedAt

        if let documentId, var linked = payload.linksByDocumentID[documentId.uuidString] {
            linked.lastSubmittedAt = submittedAt
            linked.lastSubmissionURL = submissionURL?.absoluteString
            payload.linksByDocumentID[documentId.uuidString] = linked
        }

        savePayload(payload)
    }

    func wasRecentlySubmitted(assignmentId: String, fileHash: String, within seconds: TimeInterval) -> Bool {
        var payload = loadPayload()
        pruneOldHashes(in: &payload.recentSubmissionHashes)
        savePayload(payload)

        let key = makeHashKey(assignmentId: assignmentId, fileHash: fileHash)
        guard let at = payload.recentSubmissionHashes[key] else { return false }
        return Date().timeIntervalSince(at) <= seconds
    }

    private func makeHashKey(assignmentId: String, fileHash: String) -> String {
        "\(assignmentId)|\(fileHash)"
    }

    private func pruneOldHashes(in map: inout [String: Date]) {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        map = map.filter { $0.value >= cutoff }
    }
}

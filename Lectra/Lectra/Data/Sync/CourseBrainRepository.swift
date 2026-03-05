import Foundation
import Supabase

struct CourseBrainRepositorySnapshot {
    let sourceRecords: [CourseBrainSourceRecord]
    let manualLinks: [CourseBrainManualLink]
    let syncedNoteNodes: [CourseBrainNode]
    let collapsedTimelineBuckets: Set<String>
}

private struct CourseBrainSyncedItemRow: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let itemType: String
    let itemData: CourseBrainJSONValue
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case itemType = "item_type"
        case itemData = "item_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CourseBrainSyncedItemIdRow: Decodable {
    let id: UUID
}

private struct CourseBrainManualLinkPayload: Codable {
    let version: Int
    let scope: String
    let sourceNodeId: String
    let targetNodeId: String
    let relationship: String
    let courseId: Int?
    let createdAt: String
}

private struct CourseBrainConceptCachePayload: Codable {
    let version: Int
    let scope: String
    let fingerprint: String
    let generatedAt: String
    let concepts: [CourseBrainConceptCacheConcept]
}

private struct CourseBrainTimelineMetaPayload: Codable {
    let version: Int
    let scope: String
    let collapsedBuckets: [String]
    let updatedAt: String
}

private struct CourseBrainInsertPayload<T: Encodable>: Encodable {
    let user_id: UUID
    let item_type: String
    let item_data: T
}

final class CourseBrainRepository {
    private let client = SupabaseManager.shared.client

    private let manualLinkItemType = "course_brain_manual_link"
    private let conceptCacheItemType = "course_brain_concept_cache"
    private let timelineMetaItemType = "course_brain_timeline_meta"

    func fetchSnapshot() async throws -> CourseBrainRepositorySnapshot {
        let userId = try await resolveUserId()

        let rows: [CourseBrainSyncedItemRow] = try await client
            .from("synced_items")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value

        let sourceRecords = extractSourceRecords(from: rows)
        let manualLinks = extractManualLinks(from: rows)
        let syncedNoteNodes = extractSyncedNotes(from: rows)
        let collapsedTimelineBuckets = extractCollapsedTimelineBuckets(from: rows)

        return CourseBrainRepositorySnapshot(
            sourceRecords: sourceRecords,
            manualLinks: manualLinks,
            syncedNoteNodes: syncedNoteNodes,
            collapsedTimelineBuckets: collapsedTimelineBuckets
        )
    }

    func createManualLink(
        sourceNodeId: String,
        targetNodeId: String,
        relationship: CourseBrainRelationship,
        courseId: Int?
    ) async throws -> CourseBrainManualLink {
        let userId = try await resolveUserId()
        let createdAt = ISO8601DateFormatter.courseBrainStandard.string(from: Date())
        let payload = CourseBrainManualLinkPayload(
            version: 1,
            scope: "all_courses",
            sourceNodeId: sourceNodeId,
            targetNodeId: targetNodeId,
            relationship: relationship.rawValue,
            courseId: courseId,
            createdAt: createdAt
        )

        let inserted: [CourseBrainSyncedItemRow] = try await client
            .from("synced_items")
            .insert(CourseBrainInsertPayload(user_id: userId, item_type: manualLinkItemType, item_data: payload))
            .select()
            .execute()
            .value

        guard let row = inserted.first,
              let manualLink = parseManualLink(row) else {
            throw NSError(domain: "CourseBrainRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create Course Brain link."])
        }

        return manualLink
    }

    func deleteManualLink(rowId: UUID) async throws {
        let userId = try await resolveUserId()
        _ = try await client
            .from("synced_items")
            .delete()
            .eq("id", value: rowId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .eq("item_type", value: manualLinkItemType)
            .execute()
    }

    func saveConceptCache(fingerprint: String, concepts: [CourseBrainConceptCacheConcept]) async throws {
        let payload = CourseBrainConceptCachePayload(
            version: 1,
            scope: "all_courses",
            fingerprint: fingerprint,
            generatedAt: ISO8601DateFormatter.courseBrainStandard.string(from: Date()),
            concepts: concepts
        )

        try await replaceSingletonItem(itemType: conceptCacheItemType, itemData: payload)
    }

    func saveTimelineMeta(collapsedBuckets: [String]) async throws {
        let payload = CourseBrainTimelineMetaPayload(
            version: 1,
            scope: "all_courses",
            collapsedBuckets: collapsedBuckets,
            updatedAt: ISO8601DateFormatter.courseBrainStandard.string(from: Date())
        )

        try await replaceSingletonItem(itemType: timelineMetaItemType, itemData: payload)
    }

    private func replaceSingletonItem<T: Encodable>(itemType: String, itemData: T) async throws {
        let userId = try await resolveUserId()

        let existingRows: [CourseBrainSyncedItemIdRow] = try await client
            .from("synced_items")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("item_type", value: itemType)
            .execute()
            .value

        for row in existingRows {
            _ = try await client
                .from("synced_items")
                .delete()
                .eq("id", value: row.id.uuidString)
                .eq("item_type", value: itemType)
                .execute()
        }

        _ = try await client
            .from("synced_items")
            .insert(CourseBrainInsertPayload(user_id: userId, item_type: itemType, item_data: itemData))
            .execute()
    }

    private func resolveUserId() async throws -> UUID {
        if let userId = client.auth.currentSession?.user.id {
            return userId
        }

        let session = try await client.auth.session
        return session.user.id
    }

    private func extractSourceRecords(from rows: [CourseBrainSyncedItemRow]) -> [CourseBrainSourceRecord] {
        var result: [CourseBrainSourceRecord] = []
        result.reserveCapacity(rows.count)

        for row in rows {
            guard let data = row.itemData.objectValue else { continue }

            if let indexedContent = data.array("indexedContent") {
                for entry in indexedContent {
                    guard let entryObject = entry.objectValue,
                          let record = parseIndexedRecord(entryObject, row: row) else {
                        continue
                    }
                    result.append(record)
                }
                continue
            }

            if let rootRecord = parseIndexedRecord(data, row: row) {
                result.append(rootRecord)
                continue
            }

            if let entry = data.object("entry"),
               let nestedRecord = parseIndexedRecord(entry, row: row) {
                result.append(nestedRecord)
            }
        }

        return result
    }

    private func parseIndexedRecord(_ object: [String: CourseBrainJSONValue], row: CourseBrainSyncedItemRow) -> CourseBrainSourceRecord? {
        guard let title = object.firstString(keys: ["title", "name", "label"]),
              let type = object.firstString(keys: ["type", "itemType", "kind"]) else {
            return nil
        }

        let courseId = object.int("courseId") ?? object.int("course_id")
        let courseName = object.firstString(keys: ["courseName", "course_name"])
        let moduleName = object.firstString(keys: ["moduleName", "module", "section"])
        let folderPath = object.firstString(keys: ["folderPath", "folder_path"])

        let urlString = object.firstString(keys: ["url", "sourceUrl", "source_url"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = urlString.flatMap(URL.init(string:))

        let dueAt = courseBrainParseISODate(object.firstString(keys: ["dueAt", "due_at"]))
        let lockAt = courseBrainParseISODate(object.firstString(keys: ["lockAt", "lock_at"]))
        let unlockAt = courseBrainParseISODate(object.firstString(keys: ["unlockAt", "unlock_at"]))
        let scannedAt = courseBrainParseISODate(object.firstString(keys: ["scannedAt", "scanned_at"]))

        return CourseBrainSourceRecord(
            sourceSyncedItemId: row.id,
            sourceItemType: row.itemType,
            courseId: courseId,
            courseName: courseName,
            type: type,
            title: title,
            moduleName: moduleName,
            folderPath: folderPath,
            dueAt: dueAt,
            lockAt: lockAt,
            unlockAt: unlockAt,
            scannedAt: scannedAt,
            url: url,
            platform: object.firstString(keys: ["platform", "sourcePlatform"]),
            instructions: object.firstString(keys: ["instructions"]),
            description: object.firstString(keys: ["description"]),
            body: object.firstString(keys: ["body"]),
            content: object.firstString(keys: ["content"]),
            text: object.firstString(keys: ["text"])
        )
    }

    private func extractManualLinks(from rows: [CourseBrainSyncedItemRow]) -> [CourseBrainManualLink] {
        rows.compactMap(parseManualLink)
    }

    private func parseManualLink(_ row: CourseBrainSyncedItemRow) -> CourseBrainManualLink? {
        guard row.itemType == manualLinkItemType,
              let object = row.itemData.objectValue,
              let sourceNodeId = object.string("sourceNodeId"),
              let targetNodeId = object.string("targetNodeId") else {
            return nil
        }

        let createdAt = courseBrainParseISODate(object.string("createdAt"))
            ?? courseBrainParseISODate(row.createdAt)
            ?? Date()

        return CourseBrainManualLink(
            rowId: row.id,
            sourceNodeId: sourceNodeId,
            targetNodeId: targetNodeId,
            relationship: CourseBrainRelationship(rawValue: object.string("relationship") ?? "") ?? .manualLink,
            courseId: object.int("courseId"),
            createdAt: createdAt
        )
    }

    private func extractSyncedNotes(from rows: [CourseBrainSyncedItemRow]) -> [CourseBrainNode] {
        var notes: [CourseBrainNode] = []
        notes.reserveCapacity(48)

        for row in rows {
            guard let data = row.itemData.objectValue else { continue }

            let itemTypeLower = row.itemType.lowercased()
            let kindLower = data.firstString(keys: ["kind", "type", "itemType"])?.lowercased() ?? ""
            let looksLikeNote = itemTypeLower.contains("note") || kindLower.contains("note") || data.bool("isNote") == true
            guard looksLikeNote else { continue }

            let title = data.firstString(keys: ["title", "noteTitle", "name"]) ?? "Untitled Note"
            let courseId = data.int("courseId") ?? data.int("course_id")
            let url = data.firstString(keys: ["url", "sourceUrl"]).flatMap(URL.init(string:))

            let metadata = CourseBrainNodeMetadata(
                courseName: data.firstString(keys: ["courseName", "course_name"]),
                moduleName: data.firstString(keys: ["moduleName", "module"]),
                dueAt: courseBrainParseISODate(data.firstString(keys: ["dueAt", "due_at"])),
                unlockAt: courseBrainParseISODate(data.firstString(keys: ["unlockAt", "unlock_at"])),
                lockAt: courseBrainParseISODate(data.firstString(keys: ["lockAt", "lock_at"])),
                scannedAt: courseBrainParseISODate(data.firstString(keys: ["scannedAt", "scanned_at"])),
                folderPath: data.firstString(keys: ["folderPath", "folder_path"]),
                platform: data.firstString(keys: ["platform"]),
                sourceItemType: row.itemType,
                sourceSyncedItemId: row.id,
                sourceURLString: url?.absoluteString,
                instructions: data.firstString(keys: ["instructions"]),
                description: data.firstString(keys: ["description"]),
                body: data.firstString(keys: ["body"]),
                content: data.firstString(keys: ["content"]),
                text: data.firstString(keys: ["text"])
            )

            notes.append(
                CourseBrainNode(
                    id: "note:synced:\(row.id.uuidString)",
                    type: .note,
                    title: title,
                    courseId: courseId,
                    metadata: metadata,
                    resourceURL: url
                )
            )
        }

        return notes
    }

    private func extractCollapsedTimelineBuckets(from rows: [CourseBrainSyncedItemRow]) -> Set<String> {
        for row in rows where row.itemType == timelineMetaItemType {
            guard let data = row.itemData.objectValue else { continue }
            guard let bucketValues = data.array("collapsedBuckets") else { return [] }

            let buckets = bucketValues
                .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return Set(buckets)
        }

        return []
    }
}

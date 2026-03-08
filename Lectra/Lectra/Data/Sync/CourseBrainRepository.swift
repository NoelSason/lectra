import Foundation
import Supabase

struct CourseBrainRepositorySnapshot {
    let sourceRecords: [CourseBrainSourceRecord]
    let manualLinks: [CourseBrainManualLink]
    let syncedNoteNodes: [CourseBrainNode]
    let collapsedTimelineBuckets: Set<String>
    let courseTwins: [CourseTwin]
    let evidenceLinks: [CourseBrainEvidenceLink]
    let missionArtifacts: [CourseBrainMissionArtifact]
    let studyPlans: [CourseBrainStudyPlanArtifact]
}

struct CourseBrainSyncedItemRow: Codable, Identifiable {
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

private struct CourseBrainAssignmentMissionPayload: Codable {
    let version: Int
    let courseId: Int
    let assignmentId: String
    let snapshotFingerprint: String
    let briefMarkdown: String?
    let shortlistedResourceIDs: [String]
    let conceptIDs: [String]
    let evidenceIDs: [String]
    let createdAt: String
    let updatedAt: String
    let extras: [String: CourseBrainJSONValue]
}

private struct CourseBrainEvidenceLinkPayload: Codable {
    let version: Int
    let courseId: Int?
    let assignmentId: String?
    let snapshotFingerprint: String?
    let sourceKind: String
    let targetKind: String
    let targetId: String
    let sourceNodeId: String?
    let sourceDocumentId: String?
    let selectionText: String?
    let excerpt: String?
    let pageIndex: Int?
    let pageRect: CourseBrainRect?
    let createdAt: String
    let updatedAt: String
    let extras: [String: CourseBrainJSONValue]
}

private struct CourseBrainStudyPlanPayload: Codable {
    let version: Int
    let courseId: Int
    let assignmentId: String
    let snapshotFingerprint: String
    let sprints: [StudySprint]
    let createdAt: String
    let updatedAt: String
    let extras: [String: CourseBrainJSONValue]
}

private struct CourseBrainInsertPayload<T: Encodable>: Encodable {
    let user_id: UUID
    let item_type: String
    let item_data: T
}

final class CourseBrainRepository {
    nonisolated static let derivedItemTypesToPurge: Set<String> = [
        "course_brain_manual_link",
        "course_brain_concept_cache",
        "course_brain_timeline_meta",
        "course_brain_assignment_mission_v1",
        "course_brain_evidence_link_v1",
        "course_brain_study_plan_v1",
    ]

    private lazy var client = SupabaseManager.shared.client
    private let missionNormalizer = CourseBrainMissionNormalizer()

    private let manualLinkItemType = "course_brain_manual_link"
    private let conceptCacheItemType = "course_brain_concept_cache"
    private let timelineMetaItemType = "course_brain_timeline_meta"
    private let assignmentMissionItemType = "course_brain_assignment_mission_v1"
    private let evidenceLinkItemType = "course_brain_evidence_link_v1"
    private let studyPlanItemType = "course_brain_study_plan_v1"

    func fetchSnapshot() async throws -> CourseBrainRepositorySnapshot {
        let userId = try await resolveUserId()

        let rows: [CourseBrainSyncedItemRow] = try await client
            .from("synced_items")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value

        return snapshot(from: rows)
    }

    func snapshot(from rows: [CourseBrainSyncedItemRow]) -> CourseBrainRepositorySnapshot {
        let sourceRecords = extractSourceRecords(from: rows)
        let manualLinks = extractManualLinks(from: rows)
        let evidenceLinks = extractEvidenceLinks(from: rows)
        let missionArtifacts = extractMissionArtifacts(from: rows)
        let studyPlans = extractStudyPlans(from: rows)
        let syncedNoteNodes = extractSyncedNotes(from: rows)
        let collapsedTimelineBuckets = extractCollapsedTimelineBuckets(from: rows)
        let courseTwins = missionNormalizer.buildCourseTwins(
            from: rows,
            manualLinks: manualLinks,
            evidenceLinks: evidenceLinks,
            missionArtifacts: missionArtifacts,
            studyPlans: studyPlans
        )

        return CourseBrainRepositorySnapshot(
            sourceRecords: sourceRecords,
            manualLinks: manualLinks,
            syncedNoteNodes: syncedNoteNodes,
            collapsedTimelineBuckets: collapsedTimelineBuckets,
            courseTwins: courseTwins,
            evidenceLinks: evidenceLinks,
            missionArtifacts: missionArtifacts,
            studyPlans: studyPlans
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

    func upsertMissionArtifact(
        courseId: Int,
        assignmentId: String,
        snapshotFingerprint: String,
        briefMarkdown: String?,
        shortlistedResourceIDs: [String],
        conceptIDs: [String],
        evidenceIDs: [String],
        extras: [String: CourseBrainJSONValue] = [:]
    ) async throws -> CourseBrainMissionArtifact {
        let userId = try await resolveUserId()
        let nowString = ISO8601DateFormatter.courseBrainStandard.string(from: Date())
        let existingRows = try await fetchRows(forItemType: assignmentMissionItemType, userId: userId)
        let matchingArtifacts = existingRows.compactMap(parseMissionArtifact).filter {
            $0.courseId == courseId && $0.assignmentId == assignmentId
        }

        try await deleteRows(matchingArtifacts.map(\.rowId), userId: userId, itemType: assignmentMissionItemType)

        let payload = CourseBrainAssignmentMissionPayload(
            version: 1,
            courseId: courseId,
            assignmentId: assignmentId,
            snapshotFingerprint: snapshotFingerprint,
            briefMarkdown: briefMarkdown,
            shortlistedResourceIDs: shortlistedResourceIDs,
            conceptIDs: conceptIDs,
            evidenceIDs: evidenceIDs,
            createdAt: matchingArtifacts.first.map { ISO8601DateFormatter.courseBrainStandard.string(from: $0.createdAt) } ?? nowString,
            updatedAt: nowString,
            extras: extras
        )

        let inserted: [CourseBrainSyncedItemRow] = try await client
            .from("synced_items")
            .insert(CourseBrainInsertPayload(user_id: userId, item_type: assignmentMissionItemType, item_data: payload))
            .select()
            .execute()
            .value

        guard let row = inserted.first,
              let artifact = parseMissionArtifact(row) else {
            throw NSError(domain: "CourseBrainRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save Course Brain mission artifact."])
        }

        return artifact
    }

    func deleteMissionArtifact(rowId: UUID) async throws {
        let userId = try await resolveUserId()
        try await deleteRows([rowId], userId: userId, itemType: assignmentMissionItemType)
    }

    func createEvidenceLink(
        courseId: Int?,
        assignmentId: String?,
        snapshotFingerprint: String?,
        sourceKind: CourseBrainEvidenceSourceKind,
        targetKind: CourseBrainEvidenceTargetKind,
        targetId: String,
        sourceNodeId: String?,
        sourceDocumentId: UUID?,
        selectionText: String?,
        excerpt: String?,
        pageIndex: Int?,
        pageRect: CourseBrainRect?,
        extras: [String: CourseBrainJSONValue] = [:]
    ) async throws -> CourseBrainEvidenceLink {
        let userId = try await resolveUserId()
        let nowString = ISO8601DateFormatter.courseBrainStandard.string(from: Date())
        let payload = CourseBrainEvidenceLinkPayload(
            version: 1,
            courseId: courseId,
            assignmentId: assignmentId,
            snapshotFingerprint: snapshotFingerprint,
            sourceKind: sourceKind.rawValue,
            targetKind: targetKind.rawValue,
            targetId: targetId,
            sourceNodeId: sourceNodeId,
            sourceDocumentId: sourceDocumentId?.uuidString,
            selectionText: selectionText,
            excerpt: excerpt,
            pageIndex: pageIndex,
            pageRect: pageRect,
            createdAt: nowString,
            updatedAt: nowString,
            extras: extras
        )

        let inserted: [CourseBrainSyncedItemRow] = try await client
            .from("synced_items")
            .insert(CourseBrainInsertPayload(user_id: userId, item_type: evidenceLinkItemType, item_data: payload))
            .select()
            .execute()
            .value

        guard let row = inserted.first,
              let evidenceLink = parseEvidenceLink(row) else {
            throw NSError(domain: "CourseBrainRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save Course Brain evidence link."])
        }

        return evidenceLink
    }

    func deleteEvidenceLink(rowId: UUID) async throws {
        let userId = try await resolveUserId()
        try await deleteRows([rowId], userId: userId, itemType: evidenceLinkItemType)
    }

    func upsertStudyPlan(
        courseId: Int,
        assignmentId: String,
        snapshotFingerprint: String,
        sprints: [StudySprint],
        extras: [String: CourseBrainJSONValue] = [:]
    ) async throws -> CourseBrainStudyPlanArtifact {
        let userId = try await resolveUserId()
        let nowString = ISO8601DateFormatter.courseBrainStandard.string(from: Date())
        let existingRows = try await fetchRows(forItemType: studyPlanItemType, userId: userId)
        let matchingPlans = existingRows.compactMap(parseStudyPlan).filter {
            $0.courseId == courseId && $0.assignmentId == assignmentId
        }

        try await deleteRows(matchingPlans.map(\.rowId), userId: userId, itemType: studyPlanItemType)

        let payload = CourseBrainStudyPlanPayload(
            version: 1,
            courseId: courseId,
            assignmentId: assignmentId,
            snapshotFingerprint: snapshotFingerprint,
            sprints: sprints,
            createdAt: matchingPlans.first.map { ISO8601DateFormatter.courseBrainStandard.string(from: $0.createdAt) } ?? nowString,
            updatedAt: nowString,
            extras: extras
        )

        let inserted: [CourseBrainSyncedItemRow] = try await client
            .from("synced_items")
            .insert(CourseBrainInsertPayload(user_id: userId, item_type: studyPlanItemType, item_data: payload))
            .select()
            .execute()
            .value

        guard let row = inserted.first,
              let artifact = parseStudyPlan(row) else {
            throw NSError(domain: "CourseBrainRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save Course Brain study plan."])
        }

        return artifact
    }

    func deleteStudyPlan(rowId: UUID) async throws {
        let userId = try await resolveUserId()
        try await deleteRows([rowId], userId: userId, itemType: studyPlanItemType)
    }

    func purgeDerivedState() async throws {
        let userId = try await resolveUserId()
        for itemType in Self.derivedItemTypesToPurge.sorted() {
            try await deleteAllRows(forItemType: itemType, userId: userId)
        }
    }

    func rowsRemainingAfterPurgingDerivedState(_ rows: [CourseBrainSyncedItemRow]) -> [CourseBrainSyncedItemRow] {
        rows.filter { !Self.derivedItemTypesToPurge.contains($0.itemType) }
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

    private func fetchRows(forItemType itemType: String, userId: UUID) async throws -> [CourseBrainSyncedItemRow] {
        try await client
            .from("synced_items")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("item_type", value: itemType)
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    private func deleteAllRows(forItemType itemType: String, userId: UUID) async throws {
        _ = try await client
            .from("synced_items")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("item_type", value: itemType)
            .execute()
    }

    private func deleteRows(_ rowIDs: [UUID], userId: UUID, itemType: String) async throws {
        for rowID in rowIDs {
            _ = try await client
                .from("synced_items")
                .delete()
                .eq("id", value: rowID.uuidString)
                .eq("user_id", value: userId.uuidString)
                .eq("item_type", value: itemType)
                .execute()
        }
    }

    private func extractSourceRecords(from rows: [CourseBrainSyncedItemRow]) -> [CourseBrainSourceRecord] {
        var result: [CourseBrainSourceRecord] = []
        result.reserveCapacity(rows.count)

        for row in rows {
            guard let data = row.itemData.objectValue else { continue }

            if let snapshots = data.array("courseSnapshots") {
                for snapshotValue in snapshots {
                    guard let snapshotObject = snapshotValue.objectValue else { continue }
                    if let indexedContent = snapshotObject.array("indexedContent") {
                        for entry in indexedContent {
                            guard let entryObject = entry.objectValue,
                                  let record = parseIndexedRecord(entryObject, row: row) else {
                                continue
                            }
                            result.append(record)
                        }
                    }
                }
                continue
            }

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
        let assignmentId = object.string("assignmentId")
            ?? object.string("assignment_id")
            ?? object.int("assignmentId").map(String.init)
            ?? object.int("assignment_id").map(String.init)
        let moduleName = object.firstString(keys: ["moduleName", "module", "section"])
        let folderPath = object.firstString(keys: ["folderPath", "folder_path"])
        let submissionStatus = CourseBrainSubmissionStatus.parseCanvasValue(
            object.firstString(keys: ["submissionStatus", "submission_status"])
        )
        let submissionSummary = CourseBrainSubmissionSummary.parseCanvasObject(object)

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
            assignmentId: assignmentId,
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
            submitted: object.bool("submitted"),
            submissionStatus: submissionStatus,
            submissionSummary: submissionSummary,
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

    private func extractMissionArtifacts(from rows: [CourseBrainSyncedItemRow]) -> [CourseBrainMissionArtifact] {
        rows.compactMap(parseMissionArtifact)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func parseMissionArtifact(_ row: CourseBrainSyncedItemRow) -> CourseBrainMissionArtifact? {
        guard row.itemType == assignmentMissionItemType,
              let object = row.itemData.objectValue,
              let courseId = object.int("courseId"),
              let assignmentId = object.string("assignmentId"),
              let snapshotFingerprint = object.string("snapshotFingerprint") else {
            return nil
        }

        return CourseBrainMissionArtifact(
            rowId: row.id,
            courseId: courseId,
            assignmentId: assignmentId,
            snapshotFingerprint: snapshotFingerprint,
            briefMarkdown: object.firstString(keys: ["briefMarkdown"]),
            shortlistedResourceIDs: object.stringArray("shortlistedResourceIDs"),
            conceptIDs: object.stringArray("conceptIDs"),
            evidenceIDs: object.stringArray("evidenceIDs"),
            createdAt: courseBrainParseISODate(object.firstString(keys: ["createdAt"])) ?? courseBrainParseISODate(row.createdAt) ?? Date(),
            updatedAt: courseBrainParseISODate(object.firstString(keys: ["updatedAt"])) ?? courseBrainParseISODate(row.updatedAt) ?? Date(),
            rawPayload: object
        )
    }

    private func extractEvidenceLinks(from rows: [CourseBrainSyncedItemRow]) -> [CourseBrainEvidenceLink] {
        rows.compactMap(parseEvidenceLink)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func parseEvidenceLink(_ row: CourseBrainSyncedItemRow) -> CourseBrainEvidenceLink? {
        guard row.itemType == evidenceLinkItemType,
              let object = row.itemData.objectValue,
              let targetId = object.string("targetId") else {
            return nil
        }

        let rect = object["pageRect"].flatMap { decodeJSONValue($0, as: CourseBrainRect.self) }

        return CourseBrainEvidenceLink(
            rowId: row.id,
            courseId: object.int("courseId"),
            assignmentId: object.string("assignmentId"),
            snapshotFingerprint: object.string("snapshotFingerprint"),
            sourceKind: CourseBrainEvidenceSourceKind(rawValue: object.string("sourceKind") ?? "") ?? .noteNode,
            targetKind: CourseBrainEvidenceTargetKind(rawValue: object.string("targetKind") ?? "") ?? .resource,
            targetId: targetId,
            sourceNodeId: object.string("sourceNodeId"),
            sourceDocumentId: object.string("sourceDocumentId").flatMap(UUID.init(uuidString:)),
            selectionText: object.firstString(keys: ["selectionText"]),
            excerpt: object.firstString(keys: ["excerpt"]),
            pageIndex: object.int("pageIndex"),
            pageRect: rect,
            createdAt: courseBrainParseISODate(object.firstString(keys: ["createdAt"])) ?? courseBrainParseISODate(row.createdAt) ?? Date(),
            updatedAt: courseBrainParseISODate(object.firstString(keys: ["updatedAt"])) ?? courseBrainParseISODate(row.updatedAt) ?? Date(),
            rawPayload: object
        )
    }

    private func extractStudyPlans(from rows: [CourseBrainSyncedItemRow]) -> [CourseBrainStudyPlanArtifact] {
        rows.compactMap(parseStudyPlan)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func parseStudyPlan(_ row: CourseBrainSyncedItemRow) -> CourseBrainStudyPlanArtifact? {
        guard row.itemType == studyPlanItemType,
              let object = row.itemData.objectValue,
              let courseId = object.int("courseId"),
              let assignmentId = object.string("assignmentId"),
              let snapshotFingerprint = object.string("snapshotFingerprint"),
              let sprintsValue = object["sprints"],
              let sprints = decodeJSONValue(sprintsValue, as: [StudySprint].self) else {
            return nil
        }

        return CourseBrainStudyPlanArtifact(
            rowId: row.id,
            courseId: courseId,
            assignmentId: assignmentId,
            snapshotFingerprint: snapshotFingerprint,
            sprints: sprints,
            createdAt: courseBrainParseISODate(object.firstString(keys: ["createdAt"])) ?? courseBrainParseISODate(row.createdAt) ?? Date(),
            updatedAt: courseBrainParseISODate(object.firstString(keys: ["updatedAt"])) ?? courseBrainParseISODate(row.updatedAt) ?? Date(),
            rawPayload: object
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
                assignmentId: data.string("assignmentId")
                    ?? data.string("assignment_id")
                    ?? data.int("assignmentId").map(String.init)
                    ?? data.int("assignment_id").map(String.init),
                dueAt: courseBrainParseISODate(data.firstString(keys: ["dueAt", "due_at"])),
                unlockAt: courseBrainParseISODate(data.firstString(keys: ["unlockAt", "unlock_at"])),
                lockAt: courseBrainParseISODate(data.firstString(keys: ["lockAt", "lock_at"])),
                scannedAt: courseBrainParseISODate(data.firstString(keys: ["scannedAt", "scanned_at"])),
                folderPath: data.firstString(keys: ["folderPath", "folder_path"]),
                platform: data.firstString(keys: ["platform"]),
                sourceItemType: row.itemType,
                sourceSyncedItemId: row.id,
                sourceURLString: url?.absoluteString,
                submitted: data.bool("submitted"),
                submissionStatus: CourseBrainSubmissionStatus.parseCanvasValue(
                    data.firstString(keys: ["submissionStatus", "submission_status"])
                ),
                submissionSummary: CourseBrainSubmissionSummary.parseCanvasObject(data),
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

    private func decodeJSONValue<T: Decodable>(_ value: CourseBrainJSONValue, as type: T.Type) -> T? {
        func convert(_ value: CourseBrainJSONValue) -> Any {
            switch value {
            case .string(let value):
                return value
            case .number(let value):
                return value
            case .bool(let value):
                return value
            case .null:
                return NSNull()
            case .array(let values):
                return values.map(convert)
            case .object(let object):
                return Dictionary(uniqueKeysWithValues: object.map { ($0.key, convert($0.value)) })
            }
        }

        let jsonObject = convert(value)
        guard JSONSerialization.isValidJSONObject(jsonObject),
              let data = try? JSONSerialization.data(withJSONObject: jsonObject),
              let decoded = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        return decoded
    }
}

private extension Dictionary where Key == String, Value == CourseBrainJSONValue {
    func stringArray(_ key: String) -> [String] {
        array(key)?
            .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }
}

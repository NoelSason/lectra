import Foundation
import XCTest
@testable import Lectra

final class CourseBrainMissionControlPhase1Tests: XCTestCase {
    private static let sharedRepository = CourseBrainRepository()

    func testFixtureSnapshotBuildsCourseTwinsAndPreservesLegacySourceRecords() throws {
        let snapshot = Self.sharedRepository.snapshot(from: try fixtureRows())

        XCTAssertEqual(snapshot.sourceRecords.count, 6)
        XCTAssertEqual(snapshot.courseTwins.map(\.courseId).sorted(), [101, 202])

        let cs101 = try XCTUnwrap(snapshot.courseTwins.first { $0.courseId == 101 })
        XCTAssertEqual(cs101.metadata.courseName, "CS 101")
        XCTAssertTrue(cs101.resources.contains { $0.kind == .module && $0.title == "Week 1: Limits" })

        let homework = try XCTUnwrap(cs101.missions.first)
        XCTAssertEqual(homework.assignmentId, "9001")
        XCTAssertEqual(homework.title, "Homework 1")
        XCTAssertTrue(homework.instructions?.contains("limit laws") == true)

        let limitsOverview = try XCTUnwrap(cs101.resources.first { $0.title == "Limits Overview" && $0.kind == .page })
        XCTAssertEqual(limitsOverview.moduleName, "Week 1: Limits")
        XCTAssertEqual(limitsOverview.moduleItemPosition, 3)

        XCTAssertTrue(snapshot.sourceRecords.contains {
            $0.sourceItemType == "canvascope_imported_page_v1" && $0.title == "Legacy Study Guide"
        })

        let hist202 = try XCTUnwrap(snapshot.courseTwins.first { $0.courseId == 202 })
        XCTAssertEqual(hist202.missions.map(\.assignmentId), ["3001"])
    }

    func testAssignmentFingerprintAndResourceIDsAreDeterministic() throws {
        XCTAssertEqual(
            CourseBrainMissionNormalization.assignmentID(
                contentId: "assignment-9001",
                url: nil
            ),
            "9001"
        )

        XCTAssertEqual(
            CourseBrainMissionNormalization.assignmentID(
                contentId: nil,
                url: URL(string: "https://example.instructure.com/courses/202/assignments/3001?module_item_id=4#details")
            ),
            "3001"
        )

        let firstResourceID = CourseBrainMissionNormalization.stableResourceID(
            kind: .page,
            courseId: 101,
            contentId: nil,
            url: URL(string: "https://example.instructure.com/courses/101/pages/limits-overview?view=1"),
            title: "Limits Overview",
            moduleName: "Week 1: Limits",
            type: "page"
        )
        let secondResourceID = CourseBrainMissionNormalization.stableResourceID(
            kind: .page,
            courseId: 101,
            contentId: nil,
            url: URL(string: "https://example.instructure.com/courses/101/pages/limits-overview#top"),
            title: "Limits Overview",
            moduleName: "Week 1: Limits",
            type: "page"
        )

        XCTAssertEqual(firstResourceID, secondResourceID)

        let baseSnapshot = simpleAssignmentSnapshot(
            courseId: 505,
            courseName: "Physics 505",
            assignmentId: "7007",
            assignmentTitle: "Problem Set 7",
            assignmentURL: "https://example.instructure.com/courses/505/assignments/7007",
            instructions: "Model the projectile and show your work.",
            moduleId: "77",
            moduleName: "Week 7"
        )
        var updatedSnapshot = baseSnapshot
        updatedSnapshot["scannedAt"] = .string("2026-03-08T01:00:00Z")

        XCTAssertNotEqual(
            CourseBrainMissionNormalization.snapshotFingerprint(for: baseSnapshot),
            CourseBrainMissionNormalization.snapshotFingerprint(for: updatedSnapshot)
        )
    }

    func testModuleJoiningFallsBackFromContentIDToCanonicalURLToTitleWithinModule() throws {
        let snapshotObject: [String: CourseBrainJSONValue] = [
            "sourceApp": .string("Canvascope"),
            "platform": .string("canvas"),
            "course": .object([
                "courseId": .number(404),
                "courseName": .string("BIO 404"),
            ]),
            "modules": .array([
                .object([
                    "id": .number(88),
                    "name": .string("Module Alpha"),
                    "position": .number(1),
                    "items": .array([
                        .object([
                            "id": .number(8801),
                            "contentId": .number(501),
                            "position": .number(1),
                            "title": .string("Lab Intro"),
                            "type": .string("file"),
                            "url": .string("https://example.instructure.com/courses/404/files/501"),
                        ]),
                        .object([
                            "id": .number(8802),
                            "position": .number(2),
                            "title": .string("Reading 1"),
                            "type": .string("page"),
                            "url": .string("https://example.instructure.com/courses/404/pages/reading-1"),
                        ]),
                        .object([
                            "id": .number(8803),
                            "position": .number(3),
                            "title": .string("Prep Checklist"),
                            "type": .string("page"),
                        ]),
                    ]),
                ]),
            ]),
            "indexedContent": .array([
                .object([
                    "courseId": .number(404),
                    "courseName": .string("BIO 404"),
                    "type": .string("file"),
                    "title": .string("Lab Intro"),
                    "contentId": .number(501),
                    "url": .string("https://example.instructure.com/courses/404/files/999/download"),
                    "text": .string("Review the safety checklist before lab."),
                ]),
                .object([
                    "courseId": .number(404),
                    "courseName": .string("BIO 404"),
                    "type": .string("page"),
                    "title": .string("Reading 1"),
                    "url": .string("https://example.instructure.com/courses/404/pages/reading-1?module_item_id=8802"),
                    "body": .string("Read the introduction before class."),
                ]),
                .object([
                    "courseId": .number(404),
                    "courseName": .string("BIO 404"),
                    "type": .string("page"),
                    "title": .string("Prep Checklist"),
                    "moduleName": .string("Module Alpha"),
                    "body": .string("Bring your lab notebook."),
                ]),
            ]),
        ]

        let row = snapshotRow(
            id: "00000000-0000-0000-0000-000000000404",
            snapshotObject: snapshotObject,
            envelope: false
        )
        let twin = try XCTUnwrap(
            CourseBrainMissionNormalizer()
                .buildCourseTwins(from: [row], manualLinks: [], evidenceLinks: [], missionArtifacts: [], studyPlans: [])
                .first
        )

        let byTitle = Dictionary(uniqueKeysWithValues: twin.resources.map { ($0.title, $0) })
        XCTAssertEqual(byTitle["Lab Intro"]?.moduleItemPosition, 1)
        XCTAssertEqual(byTitle["Reading 1"]?.moduleItemPosition, 2)
        XCTAssertEqual(byTitle["Prep Checklist"]?.moduleItemPosition, 3)
        XCTAssertEqual(byTitle["Prep Checklist"]?.moduleName, "Module Alpha")
    }

    func testMissionArtifactsEvidenceAndStudyPlansRoundTripThroughRepositorySnapshot() throws {
        let assignmentURLString = "https://example.instructure.com/courses/303/assignments/9901"
        let snapshotObject = simpleAssignmentSnapshot(
            courseId: 303,
            courseName: "Linear Algebra",
            assignmentId: "9901",
            assignmentTitle: "Problem Set 5",
            assignmentURL: assignmentURLString,
            instructions: "Diagonalize the matrix and justify each step.",
            moduleId: "15",
            moduleName: "Week 5"
        )
        let snapshotFingerprint = CourseBrainMissionNormalization.snapshotFingerprint(for: snapshotObject)
        let assignmentURL = try XCTUnwrap(URL(string: assignmentURLString))
        let assignmentRowObject = try XCTUnwrap(snapshotObject.array("indexedContent")?.first?.objectValue)
        let assignmentResourceID = CourseBrainMissionNormalization.stableResourceID(
            kind: .assignment,
            courseId: 303,
            contentId: "9901",
            url: assignmentURL,
            title: "Problem Set 5",
            moduleName: "Week 5",
            type: "assignment"
        )
        let legacyAssignmentNodeID = try XCTUnwrap(
            CourseBrainMissionNormalization.legacyNodeID(
                for: MissionResource(
                    id: assignmentResourceID,
                    kind: .assignment,
                    courseId: 303,
                    snapshotFingerprint: snapshotFingerprint,
                    assignmentId: "9901",
                    title: "Problem Set 5",
                    courseName: "Linear Algebra",
                    moduleId: "15",
                    moduleName: "Week 5",
                    modulePosition: 1,
                    moduleItemId: "1501",
                    moduleItemPosition: 1,
                    assignmentGroupId: nil,
                    assignmentGroupName: nil,
                    folderPath: nil,
                    dueAt: courseBrainParseISODate("2026-03-20T23:59:00Z"),
                    unlockAt: nil,
                    lockAt: nil,
                    scannedAt: nil,
                    updatedAt: nil,
                    published: true,
                    pointsPossible: nil,
                    submissionTypes: ["online_upload"],
                    allowedExtensions: ["pdf"],
                    platform: nil,
                    platformDomain: nil,
                    url: assignmentURL,
                    contentId: "9901",
                    contentType: nil,
                    sizeBytes: nil,
                    instructions: "Diagonalize the matrix and justify each step.",
                    description: nil,
                    body: nil,
                    content: nil,
                    text: nil,
                    rawItem: assignmentRowObject
                )
            )
        )

        let snapshotRow = snapshotRow(
            id: "00000000-0000-0000-0000-000000000303",
            snapshotObject: snapshotObject,
            envelope: false
        )
        let manualLinkRow = syncedRow(
            id: "00000000-0000-0000-0000-000000000304",
            itemType: "course_brain_manual_link",
            itemData: .object([
                "version": .number(1),
                "sourceNodeId": .string("note:diagonalization-outline"),
                "targetNodeId": .string(legacyAssignmentNodeID),
                "relationship": .string(CourseBrainRelationship.manualLink.rawValue),
                "courseId": .number(303),
                "createdAt": .string("2026-03-07T17:15:00Z"),
            ])
        )
        let evidenceRow = syncedRow(
            id: "00000000-0000-0000-0000-000000000305",
            itemType: "course_brain_evidence_link_v1",
            itemData: .object([
                "version": .number(1),
                "courseId": .number(303),
                "assignmentId": .string("9901"),
                "snapshotFingerprint": .string(snapshotFingerprint),
                "sourceKind": .string(CourseBrainEvidenceSourceKind.noteSelection.rawValue),
                "targetKind": .string(CourseBrainEvidenceTargetKind.assignment.rawValue),
                "targetId": .string("9901"),
                "sourceNodeId": .string("note:diagonalization-outline"),
                "selectionText": .string("Diagonalize A using the eigenbasis."),
                "excerpt": .string("Start from the eigenvectors you found in lecture."),
                "pageIndex": .number(2),
                "pageRect": .object([
                    "x": .number(10),
                    "y": .number(20),
                    "width": .number(120),
                    "height": .number(40),
                ]),
                "createdAt": .string("2026-03-07T17:16:00Z"),
                "updatedAt": .string("2026-03-07T17:16:00Z"),
                "extras": .object([:]),
            ])
        )
        let missionRow = syncedRow(
            id: "00000000-0000-0000-0000-000000000306",
            itemType: "course_brain_assignment_mission_v1",
            itemData: .object([
                "version": .number(1),
                "courseId": .number(303),
                "assignmentId": .string("9901"),
                "snapshotFingerprint": .string(snapshotFingerprint),
                "briefMarkdown": .string("Focus on diagonalization and the lecture proof sketch."),
                "shortlistedResourceIDs": .array([.string(assignmentResourceID)]),
                "conceptIDs": .array([.string("concept:eigenvectors")]),
                "evidenceIDs": .array([.string("00000000-0000-0000-0000-000000000305")]),
                "createdAt": .string("2026-03-07T17:17:00Z"),
                "updatedAt": .string("2026-03-07T17:18:00Z"),
                "extras": .object([:]),
            ])
        )
        let studyPlanRow = syncedRow(
            id: "00000000-0000-0000-0000-000000000307",
            itemType: "course_brain_study_plan_v1",
            itemData: .object([
                "version": .number(1),
                "courseId": .number(303),
                "assignmentId": .string("9901"),
                "snapshotFingerprint": .string(snapshotFingerprint),
                "sprints": .array([
                    .object([
                        "id": .string("sprint-1"),
                        "title": .string("Rebuild the proof"),
                        "summary": .string("Re-derive the diagonalization steps before writing the final solution."),
                        "startAt": .null,
                        "dueAt": .null,
                        "resourceIDs": .array([.string(assignmentResourceID)]),
                        "conceptIDs": .array([.string("concept:eigenvectors")]),
                    ]),
                ]),
                "createdAt": .string("2026-03-07T17:19:00Z"),
                "updatedAt": .string("2026-03-07T17:20:00Z"),
                "extras": .object([:]),
            ])
        )

        let snapshot = Self.sharedRepository.snapshot(from: [
            snapshotRow,
            manualLinkRow,
            evidenceRow,
            missionRow,
            studyPlanRow,
        ])

        XCTAssertEqual(snapshot.missionArtifacts.count, 1)
        XCTAssertEqual(snapshot.evidenceLinks.count, 1)
        XCTAssertEqual(snapshot.studyPlans.count, 1)
        XCTAssertEqual(snapshot.manualLinks.count, 1)

        let twin = try XCTUnwrap(snapshot.courseTwins.first)
        let mission = try XCTUnwrap(twin.missions.first)
        XCTAssertEqual(mission.assignmentId, "9901")
        XCTAssertEqual(mission.missionArtifact?.briefMarkdown, "Focus on diagonalization and the lecture proof sketch.")
        XCTAssertEqual(mission.studyPlan?.sprints.map(\.title), ["Rebuild the proof"])
        XCTAssertTrue(mission.linkedEvidenceIDs.contains("00000000-0000-0000-0000-000000000305"))

        let manualEvidence = try XCTUnwrap(twin.noteEvidence.first { $0.sourceKind == .manualLink })
        XCTAssertEqual(manualEvidence.assignmentId, "9901")

        let selectionEvidence = try XCTUnwrap(twin.noteEvidence.first { $0.sourceKind == .noteSelection })
        XCTAssertEqual(selectionEvidence.targetKind, .assignment)
        XCTAssertEqual(selectionEvidence.targetId, "9901")
        XCTAssertEqual(selectionEvidence.pageIndex, 2)
    }
}

private extension CourseBrainMissionControlPhase1Tests {
    func fixtureRows() throws -> [CourseBrainSyncedItemRow] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "CourseBrainMissionControlFixture", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "CourseBrainMissionControlFixture", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([CourseBrainSyncedItemRow].self, from: data)
    }

    func snapshotRow(
        id: String,
        snapshotObject: [String: CourseBrainJSONValue],
        envelope: Bool
    ) -> CourseBrainSyncedItemRow {
        let itemData: CourseBrainJSONValue
        if envelope {
            itemData = .object(["courseSnapshots": .array([.object(snapshotObject)])])
        } else {
            itemData = .object(snapshotObject)
        }

        return syncedRow(id: id, itemType: CourseBrainMissionNormalization.snapshotItemType, itemData: itemData)
    }

    func syncedRow(
        id: String,
        itemType: String,
        itemData: CourseBrainJSONValue,
        createdAt: String = "2026-03-07T17:00:00Z",
        updatedAt: String = "2026-03-07T17:00:00Z"
    ) -> CourseBrainSyncedItemRow {
        CourseBrainSyncedItemRow(
            id: UUID(uuidString: id)!,
            userId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            itemType: itemType,
            itemData: itemData,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func simpleAssignmentSnapshot(
        courseId: Int,
        courseName: String,
        assignmentId: String,
        assignmentTitle: String,
        assignmentURL: String,
        instructions: String,
        moduleId: String,
        moduleName: String
    ) -> [String: CourseBrainJSONValue] {
        [
            "sourceApp": .string("Canvascope"),
            "platform": .string("canvas"),
            "scannedAt": .string("2026-03-07T17:00:00Z"),
            "course": .object([
                "courseId": .number(Double(courseId)),
                "courseName": .string(courseName),
            ]),
            "modules": .array([
                .object([
                    "id": .string(moduleId),
                    "name": .string(moduleName),
                    "position": .number(1),
                    "items": .array([
                        .object([
                            "id": .number(1501),
                            "contentId": .string(assignmentId),
                            "position": .number(1),
                            "title": .string(assignmentTitle),
                            "type": .string("assignment"),
                            "url": .string(assignmentURL),
                            "published": .bool(true),
                            "contentDetails": .object([
                                "dueAt": .string("2026-03-20T23:59:00Z"),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
            "indexedContent": .array([
                .object([
                    "courseId": .number(Double(courseId)),
                    "courseName": .string(courseName),
                    "type": .string("assignment"),
                    "title": .string(assignmentTitle),
                    "contentId": .string(assignmentId),
                    "url": .string(assignmentURL),
                    "instructions": .string(instructions),
                    "submissionTypes": .array([.string("online_upload")]),
                    "allowedExtensions": .array([.string("pdf")]),
                    "dueAt": .string("2026-03-20T23:59:00Z"),
                ]),
            ]),
        ]
    }
}

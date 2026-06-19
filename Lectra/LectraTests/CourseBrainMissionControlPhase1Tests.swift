import Foundation
import XCTest
@testable import Lectra

final class CourseBrainMissionControlPhase1Tests: XCTestCase {
    private static let sharedRepository = CourseBrainRepository()

    func testCanvasFolderPreviewURLResolvesToFileDownloadURL() throws {
        let folderPreviewURL = try XCTUnwrap(URL(string: "https://bcourses.berkeley.edu/courses/123/files/folder/Lecture%20Slides?preview=456789"))

        let resolved = try XCTUnwrap(CanvasFileURLResolver.pdfSourceURL(
            from: folderPreviewURL,
            title: "Lecture 1.pdf",
            contentType: nil
        ))

        XCTAssertEqual(
            resolved.absoluteString,
            "https://bcourses.berkeley.edu/courses/123/files/456789/download?download_frd=1"
        )

        let folderOnlyURL = try XCTUnwrap(URL(string: "https://bcourses.berkeley.edu/courses/123/files/folder/Lecture%20Slides"))
        XCTAssertNil(CanvasFileURLResolver.pdfSourceURL(
            from: folderOnlyURL,
            title: "Lecture 1.pdf",
            contentType: nil
        ))
    }

    func testCanvasAPIFileSynthesizesDownloadURLWhenCandidateIsFolderPage() throws {
        let json = """
        {
          "id": "456789",
          "display_name": "Lecture 1.pdf",
          "filename": "Lecture 1.pdf",
          "url": "https://bcourses.berkeley.edu/courses/123/files/folder/Lecture%20Slides",
          "content_type": "application/pdf",
          "mime_class": "pdf"
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(CanvasAPIFile.self, from: json)

        XCTAssertEqual(file.contentType, "application/pdf")
        XCTAssertEqual(
            file.bestDownloadURLString(host: "https://bcourses.berkeley.edu", courseId: 123),
            "https://bcourses.berkeley.edu/courses/123/files/456789/download?download_frd=1"
        )
    }

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
        XCTAssertEqual(homework.submitted, true)
        XCTAssertEqual(homework.headlineSubmissionStatus, .submitted)
        XCTAssertEqual(homework.submissionSummary?.submittedAt, isoDate("2026-03-09T02:15:00Z"))

        let limitsOverview = try XCTUnwrap(cs101.resources.first { $0.title == "Limits Overview" && $0.kind == .page })
        XCTAssertEqual(limitsOverview.moduleName, "Week 1: Limits")
        XCTAssertEqual(limitsOverview.moduleItemPosition, 3)

        XCTAssertTrue(snapshot.sourceRecords.contains {
            $0.sourceItemType == "canvascope_imported_page_v1" && $0.title == "Legacy Study Guide"
        })

        let hist202 = try XCTUnwrap(snapshot.courseTwins.first { $0.courseId == 202 })
        XCTAssertEqual(hist202.missions.map(\.assignmentId), ["3001"])
        XCTAssertNil(hist202.missions.first?.headlineSubmissionStatus)
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
                    submitted: nil,
                    submissionStatus: nil,
                    submissionSummary: nil,
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

    func testSubmissionStateFlowsThroughAssignmentBackedResources() throws {
        let submissionSummary: [String: CourseBrainJSONValue] = [
            "workflowState": .string("submitted"),
            "submittedAt": .string("2026-03-08T17:30:00Z"),
            "attempt": .number(2),
            "late": .bool(true),
            "missing": .bool(false),
            "excused": .bool(false),
            "grade": .string("18 / 20"),
            "score": .number(18),
            "submissionType": .string("online_upload"),
            "hasSubmittedSubmissions": .bool(true),
            "gradeMatchesCurrentSubmission": .bool(true),
        ]

        var snapshotObject = simpleAssignmentSnapshot(
            courseId: 606,
            courseName: "Chem 606",
            assignmentId: "4100",
            assignmentTitle: "Problem Set 4",
            assignmentURL: "https://example.instructure.com/courses/606/assignments/4100",
            instructions: "Show each equilibrium step clearly.",
            moduleId: "46",
            moduleName: "Week 4",
            submitted: true,
            submissionStatus: .late,
            submissionSummary: submissionSummary
        )

        if case var .array(indexedContent)? = snapshotObject["indexedContent"] {
            indexedContent.append(
                .object([
                    "courseId": .number(606),
                    "courseName": .string("Chem 606"),
                    "type": .string("quiz"),
                    "title": .string("Problem Set 4 Quiz Mirror"),
                    "assignmentId": .string("4100"),
                    "url": .string("https://example.instructure.com/courses/606/quizzes/9900"),
                    "submitted": .bool(true),
                    "submissionStatus": .string(CourseBrainSubmissionStatus.late.rawValue),
                    "submission": .object(submissionSummary),
                ])
            )
            indexedContent.append(
                .object([
                    "courseId": .number(606),
                    "courseName": .string("Chem 606"),
                    "type": .string("discussion"),
                    "title": .string("Problem Set 4 Discussion"),
                    "assignmentId": .string("4100"),
                    "url": .string("https://example.instructure.com/courses/606/discussion_topics/8800"),
                    "body": .string("Use this thread for clarifications."),
                    "submitted": .bool(true),
                    "submissionStatus": .string(CourseBrainSubmissionStatus.late.rawValue),
                    "submission": .object(submissionSummary),
                ])
            )
            snapshotObject["indexedContent"] = .array(indexedContent)
        }

        let row = snapshotRow(
            id: "00000000-0000-0000-0000-000000000606",
            snapshotObject: snapshotObject,
            envelope: false
        )

        let twin = try XCTUnwrap(
            CourseBrainMissionNormalizer()
                .buildCourseTwins(from: [row], manualLinks: [], evidenceLinks: [], missionArtifacts: [], studyPlans: [])
                .first
        )

        let mission = try XCTUnwrap(twin.missions.first { $0.assignmentId == "4100" })
        XCTAssertEqual(mission.submitted, true)
        XCTAssertEqual(mission.submissionStatus, .late)
        XCTAssertEqual(mission.submissionSummary?.attempt, 2)
        XCTAssertEqual(mission.submissionSummary?.submittedAt, isoDate("2026-03-08T17:30:00Z"))

        let quizResource = try XCTUnwrap(twin.resources.first { $0.title == "Problem Set 4 Quiz Mirror" })
        XCTAssertEqual(quizResource.assignmentId, "4100")
        XCTAssertEqual(quizResource.submissionStatus, .late)
        XCTAssertEqual(quizResource.headlineSubmissionStatus, .late)

        let discussionResource = try XCTUnwrap(twin.resources.first { $0.title == "Problem Set 4 Discussion" })
        XCTAssertEqual(discussionResource.assignmentId, "4100")
        XCTAssertEqual(discussionResource.submissionStatus, .late)
        XCTAssertEqual(discussionResource.headlineSubmissionStatus, .late)

        let dashboard = CourseBrainDashboardBuilder().build(
            courseTwins: [twin],
            documents: [],
            noteNodes: [],
            now: isoDate("2026-03-08T12:00:00Z")
        )
        let assignment = try XCTUnwrap(dashboard.assignments.first { $0.mission.assignmentId == "4100" })
        let detail = try XCTUnwrap(dashboard.detailsByAssignmentID[assignment.id])
        let quizDetailResource = try XCTUnwrap(detail.relatedResources.first { $0.title == "Problem Set 4 Quiz Mirror" })
        let discussionDetailResource = try XCTUnwrap(detail.relatedResources.first { $0.title == "Problem Set 4 Discussion" })
        XCTAssertEqual(quizDetailResource.headlineSubmissionStatus, .late)
        XCTAssertEqual(discussionDetailResource.headlineSubmissionStatus, .late)
    }

    func testDirectAssignmentSubmissionStatesRemainBackwardCompatible() throws {
        func mission(for snapshotObject: [String: CourseBrainJSONValue], id: String) throws -> CourseMission {
            let row = snapshotRow(id: id, snapshotObject: snapshotObject, envelope: false)
            return try XCTUnwrap(
                CourseBrainMissionNormalizer()
                    .buildCourseTwins(from: [row], manualLinks: [], evidenceLinks: [], missionArtifacts: [], studyPlans: [])
                    .first?
                    .missions
                    .first
            )
        }

        let submittedMission = try mission(
            for: simpleAssignmentSnapshot(
                courseId: 707,
                courseName: "Chem 707",
                assignmentId: "5100",
                assignmentTitle: "Lab Upload",
                assignmentURL: "https://example.instructure.com/courses/707/assignments/5100",
                instructions: "Upload the completed lab report.",
                moduleId: "17",
                moduleName: "Week 2",
                submitted: true,
                submissionStatus: nil,
                submissionSummary: [
                    "workflow_state": .string("submitted"),
                    "submitted_at": .string("2026-03-08T18:00:00Z"),
                    "has_submitted_submissions": .bool(true),
                ]
            ),
            id: "00000000-0000-0000-0000-000000000707"
        )
        XCTAssertEqual(submittedMission.headlineSubmissionStatus, .submitted)
        XCTAssertEqual(submittedMission.submitted, true)

        let missingMission = try mission(
            for: simpleAssignmentSnapshot(
                courseId: 708,
                courseName: "Chem 708",
                assignmentId: "5101",
                assignmentTitle: "Problem Set Missing",
                assignmentURL: "https://example.instructure.com/courses/708/assignments/5101",
                instructions: "Show all work.",
                moduleId: "18",
                moduleName: "Week 3",
                submitted: false,
                submissionStatus: .missing,
                submissionSummary: [
                    "workflowState": .string("unsubmitted"),
                    "missing": .bool(true),
                ]
            ),
            id: "00000000-0000-0000-0000-000000000708"
        )
        XCTAssertEqual(missingMission.headlineSubmissionStatus, .missing)

        let excusedMission = try mission(
            for: simpleAssignmentSnapshot(
                courseId: 709,
                courseName: "Chem 709",
                assignmentId: "5102",
                assignmentTitle: "Excused Discussion",
                assignmentURL: "https://example.instructure.com/courses/709/assignments/5102",
                instructions: "Participate in the discussion thread.",
                moduleId: "19",
                moduleName: "Week 4",
                submitted: false,
                submissionStatus: nil,
                submissionSummary: [
                    "workflow_state": .string("excused"),
                    "excused": .bool(true),
                ]
            ),
            id: "00000000-0000-0000-0000-000000000709"
        )
        XCTAssertEqual(excusedMission.headlineSubmissionStatus, .excused)
        XCTAssertNil(excusedMission.submissionStatus)

        let legacyMission = try mission(
            for: simpleAssignmentSnapshot(
                courseId: 710,
                courseName: "Chem 710",
                assignmentId: "5103",
                assignmentTitle: "Legacy Assignment",
                assignmentURL: "https://example.instructure.com/courses/710/assignments/5103",
                instructions: "This payload has no submission fields.",
                moduleId: "20",
                moduleName: "Week 5"
            ),
            id: "00000000-0000-0000-0000-000000000710"
        )
        XCTAssertNil(legacyMission.submitted)
        XCTAssertNil(legacyMission.submissionStatus)
        XCTAssertNil(legacyMission.submissionSummary)
        XCTAssertNil(legacyMission.headlineSubmissionStatus)
    }

    func testLegacyFlattenedRowsDecodeSubmissionFieldsAndPropagateToGraph() throws {
        let row = syncedRow(
            id: "00000000-0000-0000-0000-000000000711",
            itemType: "canvascope_assignment_row_v1",
            itemData: .object([
                "course_id": .number(711),
                "course_name": .string("ENG 711"),
                "type": .string("quiz"),
                "title": .string("Reading Check"),
                "assignment_id": .string("8801"),
                "url": .string("https://example.instructure.com/courses/711/quizzes/8801"),
                "submitted": .bool(false),
                "submission_status": .string("Excused"),
                "submission": .object([
                    "workflow_state": .string("excused"),
                    "excused": .bool(true),
                ]),
            ])
        )

        let snapshot = Self.sharedRepository.snapshot(from: [row])
        let record = try XCTUnwrap(snapshot.sourceRecords.first)

        XCTAssertEqual(snapshot.sourceRecords.count, 1)
        XCTAssertEqual(record.assignmentId, "8801")
        XCTAssertEqual(record.headlineSubmissionStatus, .excused)

        let graph = CourseBrainGraphBuilder.shared.build(
            payload: CourseBrainBuildPayload(
                records: snapshot.sourceRecords,
                localNotes: [],
                syncedNoteNodes: [],
                manualLinks: [],
                courseFilter: nil
            )
        )
        let node = graph.allNodes.first { $0.title == "Reading Check" }
        XCTAssertEqual(node?.metadata.assignmentId, "8801")
        XCTAssertEqual(node?.metadata.headlineSubmissionStatus, .excused)
    }

    func testDerivedStatePurgeHelperKeepsSnapshotsAndPDFs() {
        let rows = [
            syncedRow(id: "00000000-0000-0000-0000-000000000401", itemType: "course_brain_manual_link", itemData: .object([:])),
            syncedRow(id: "00000000-0000-0000-0000-000000000402", itemType: "course_brain_evidence_link_v1", itemData: .object([:])),
            syncedRow(id: "00000000-0000-0000-0000-000000000403", itemType: "canvascope_course_snapshot_v1", itemData: .object([:])),
            syncedRow(id: "00000000-0000-0000-0000-000000000404", itemType: "pdf_document", itemData: .object([:])),
            syncedRow(id: "00000000-0000-0000-0000-000000000405", itemType: "canvascope_imported_page_v1", itemData: .object([:])),
        ]

        let remainingRows = Self.sharedRepository.rowsRemainingAfterPurgingDerivedState(rows)
        XCTAssertEqual(
            remainingRows.map(\.itemType).sorted(),
            ["canvascope_course_snapshot_v1", "canvascope_imported_page_v1", "pdf_document"]
        )
        XCTAssertEqual(
            CourseBrainRepository.derivedItemTypesToPurge,
            Set([
                "course_brain_manual_link",
                "course_brain_concept_cache",
                "course_brain_timeline_meta",
                "course_brain_assignment_mission_v1",
                "course_brain_evidence_link_v1",
                "course_brain_study_plan_v1",
            ])
        )
    }

    func testDashboardBuilderAppliesStrictWindowAndDueDatePrecedence() {
        let now = isoDate("2026-03-07T12:00:00Z")
        let builder = CourseBrainDashboardBuilder()
        let twin = makeCourseTwin(
            courseId: 101,
            courseName: "CS 101",
            scannedAt: isoDate("2026-03-07T08:00:00Z"),
            missions: [
                makeMission(courseId: 101, assignmentId: "in-low-boundary", title: "Past Boundary", dueAt: isoDate("2026-02-28T12:00:00Z")),
                makeMission(courseId: 101, assignmentId: "in-high-boundary", title: "Future Boundary", dueAt: isoDate("2026-04-06T12:00:00Z")),
                makeMission(courseId: 101, assignmentId: "before-window", title: "Too Old", dueAt: isoDate("2026-02-28T11:59:59Z")),
                makeMission(courseId: 101, assignmentId: "after-window", title: "Too Far", dueAt: isoDate("2026-04-06T12:00:01Z")),
                makeMission(
                    courseId: 101,
                    assignmentId: "due-wins",
                    title: "Due Wins Over Unlock",
                    dueAt: isoDate("2026-01-10T12:00:00Z"),
                    unlockAt: isoDate("2026-03-08T12:00:00Z")
                ),
                makeMission(courseId: 101, assignmentId: "unlock-fallback", title: "Unlock Fallback", dueAt: nil, unlockAt: isoDate("2026-03-08T12:00:00Z")),
                makeMission(courseId: 101, assignmentId: "undated", title: "No Dates", dueAt: nil, unlockAt: nil, lockAt: nil),
            ],
            resources: []
        )

        let data = builder.build(courseTwins: [twin], documents: [], noteNodes: [], now: now)
        let titles = Set(data.assignments.map(\.title))

        XCTAssertTrue(titles.contains("Past Boundary"))
        XCTAssertTrue(titles.contains("Future Boundary"))
        XCTAssertTrue(titles.contains("Unlock Fallback"))
        XCTAssertFalse(titles.contains("Too Old"))
        XCTAssertFalse(titles.contains("Too Far"))
        XCTAssertFalse(titles.contains("Due Wins Over Unlock"))
        XCTAssertFalse(titles.contains("No Dates"))
    }

    func testDashboardBuilderDropsCoursesWithoutVisibleAssignments() {
        let now = isoDate("2026-03-07T12:00:00Z")
        let builder = CourseBrainDashboardBuilder()
        let visibleTwin = makeCourseTwin(
            courseId: 101,
            courseName: "CS 101",
            scannedAt: now,
            missions: [
                makeMission(courseId: 101, assignmentId: "visible", title: "Visible Assignment", dueAt: isoDate("2026-03-12T12:00:00Z")),
            ],
            resources: []
        )
        let oldTwin = makeCourseTwin(
            courseId: 202,
            courseName: "History 202",
            scannedAt: now,
            missions: [
                makeMission(courseId: 202, assignmentId: "old", title: "Old Assignment", dueAt: isoDate("2026-01-01T12:00:00Z")),
            ],
            resources: []
        )

        let data = builder.build(courseTwins: [visibleTwin, oldTwin], documents: [], noteNodes: [], now: now)

        XCTAssertEqual(data.courseFilters.map(\.id), [101])
        XCTAssertEqual(data.courseFilters.first?.name, "CS 101")
    }

    func testDashboardBuilderPrioritizesModuleThenAssignmentGroupThenDateForRelatedResources() throws {
        let now = isoDate("2026-03-07T12:00:00Z")
        let builder = CourseBrainDashboardBuilder()
        let mission = makeMission(
            courseId: 404,
            assignmentId: "ps1",
            title: "Problem Set 1",
            dueAt: isoDate("2026-03-10T12:00:00Z"),
            moduleId: "module-1",
            moduleName: "Week 1",
            assignmentGroupId: "group-a",
            assignmentGroupName: "Homework"
        )
        let twin = makeCourseTwin(
            courseId: 404,
            courseName: "BIO 404",
            scannedAt: now,
            missions: [mission],
            resources: [
                makeResource(
                    id: "same-module-id",
                    kind: .page,
                    courseId: 404,
                    snapshotFingerprint: mission.snapshotFingerprint,
                    title: "Module ID Match",
                    moduleId: "module-1",
                    moduleName: "Week 9",
                    assignmentGroupId: nil,
                    assignmentGroupName: nil,
                    datedAt: isoDate("2026-04-15T12:00:00Z")
                ),
                makeResource(
                    id: "same-module-name",
                    kind: .lecture,
                    courseId: 404,
                    snapshotFingerprint: mission.snapshotFingerprint,
                    title: "Module Name Match",
                    moduleId: "module-9",
                    moduleName: "Week 1",
                    assignmentGroupId: nil,
                    assignmentGroupName: nil,
                    datedAt: isoDate("2026-03-30T12:00:00Z")
                ),
                makeResource(
                    id: "same-group",
                    kind: .discussion,
                    courseId: 404,
                    snapshotFingerprint: mission.snapshotFingerprint,
                    title: "Assignment Group Match",
                    moduleId: "module-8",
                    moduleName: "Week 8",
                    assignmentGroupId: "group-a",
                    assignmentGroupName: "Homework",
                    datedAt: isoDate("2026-04-01T12:00:00Z")
                ),
                makeResource(
                    id: "closest-date",
                    kind: .file,
                    courseId: 404,
                    snapshotFingerprint: mission.snapshotFingerprint,
                    title: "Closest Date Only",
                    moduleId: "module-8",
                    moduleName: "Week 8",
                    assignmentGroupId: "group-z",
                    assignmentGroupName: "Extra Credit",
                    datedAt: isoDate("2026-03-11T12:00:00Z")
                ),
            ]
        )

        let data = builder.build(courseTwins: [twin], documents: [], noteNodes: [], now: now)
        let assignmentID = try XCTUnwrap(data.assignments.first?.id)
        let detail = try XCTUnwrap(data.detailsByAssignmentID[assignmentID])

        XCTAssertEqual(
            detail.relatedResources.map(\.title).prefix(4),
            ["Module ID Match", "Module Name Match", "Assignment Group Match", "Closest Date Only"]
        )
    }

    func testDashboardBuilderPrioritizesAttentionNeedingAssignmentsWhenDatesMatch() {
        let now = isoDate("2026-03-07T12:00:00Z")
        let due = isoDate("2026-03-09T12:00:00Z")
        let builder = CourseBrainDashboardBuilder()
        let twin = makeCourseTwin(
            courseId: 515,
            courseName: "STAT 515",
            scannedAt: now,
            missions: [
                makeMission(
                    courseId: 515,
                    assignmentId: "late-lab",
                    title: "Late Lab",
                    dueAt: due,
                    submitted: true,
                    submissionStatus: .late,
                    submissionSummary: CourseBrainSubmissionSummary(
                        workflowState: "submitted",
                        submittedAt: isoDate("2026-03-08T12:00:00Z"),
                        attempt: 1,
                        late: true,
                        missing: false,
                        excused: false,
                        grade: nil,
                        score: nil,
                        submissionType: nil,
                        hasSubmittedSubmissions: true,
                        gradeMatchesCurrentSubmission: nil
                    )
                ),
                makeMission(
                    courseId: 515,
                    assignmentId: "submitted-lab",
                    title: "Submitted Lab",
                    dueAt: due,
                    submitted: true,
                    submissionStatus: .submitted,
                    submissionSummary: CourseBrainSubmissionSummary(
                        workflowState: "submitted",
                        submittedAt: isoDate("2026-03-08T11:00:00Z"),
                        attempt: 1,
                        late: false,
                        missing: false,
                        excused: false,
                        grade: nil,
                        score: nil,
                        submissionType: nil,
                        hasSubmittedSubmissions: true,
                        gradeMatchesCurrentSubmission: nil
                    )
                ),
            ],
            resources: []
        )

        let data = builder.build(courseTwins: [twin], documents: [], noteNodes: [], now: now)
        XCTAssertEqual(data.assignments.map(\.title), ["Late Lab", "Submitted Lab"])
    }

    func testOrbitDueSoonSkipsCompletedCanvasSubmissions() {
        let now = isoDate("2026-03-07T12:00:00Z")

        func makeNode(
            id: String,
            title: String,
            dueAt: Date,
            submissionStatus: CourseBrainSubmissionStatus?
        ) -> CourseBrainNode {
            CourseBrainNode(
                id: id,
                type: .assignment,
                title: title,
                courseId: 616,
                metadata: CourseBrainNodeMetadata(
                    courseName: "BIO 616",
                    moduleName: "Week 6",
                    assignmentId: id,
                    dueAt: dueAt,
                    unlockAt: nil,
                    lockAt: nil,
                    scannedAt: now,
                    folderPath: nil,
                    platform: "canvas",
                    sourceItemType: "assignment",
                    sourceSyncedItemId: nil,
                    sourceURLString: "https://example.instructure.com/courses/616/assignments/\(id)",
                    submitted: submissionStatus == .submitted,
                    submissionStatus: submissionStatus,
                    submissionSummary: nil,
                    instructions: nil,
                    description: nil,
                    body: nil,
                    content: nil,
                    text: nil
                ),
                resourceURL: URL(string: "https://example.instructure.com/courses/616/assignments/\(id)")
            )
        }

        let dueSoon = CourseBrainOrbitView.dueSoonNodes(
            from: [
                makeNode(id: "submitted", title: "Submitted Quiz", dueAt: isoDate("2026-03-09T12:00:00Z"), submissionStatus: .submitted),
                makeNode(id: "excused", title: "Excused Discussion", dueAt: isoDate("2026-03-09T13:00:00Z"), submissionStatus: .excused),
                makeNode(id: "missing", title: "Missing Homework", dueAt: isoDate("2026-03-09T14:00:00Z"), submissionStatus: .missing),
                makeNode(id: "open", title: "Open Homework", dueAt: isoDate("2026-03-09T15:00:00Z"), submissionStatus: nil),
            ],
            now: now
        )

        XCTAssertEqual(dueSoon.map(\.title), ["Missing Homework", "Open Homework"])
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
        moduleName: String,
        submitted: Bool? = nil,
        submissionStatus: CourseBrainSubmissionStatus? = nil,
        submissionSummary: [String: CourseBrainJSONValue]? = nil
    ) -> [String: CourseBrainJSONValue] {
        var assignmentObject: [String: CourseBrainJSONValue] = [
            "courseId": .number(Double(courseId)),
            "courseName": .string(courseName),
            "type": .string("assignment"),
            "title": .string(assignmentTitle),
            "assignmentId": .string(assignmentId),
            "contentId": .string(assignmentId),
            "url": .string(assignmentURL),
            "instructions": .string(instructions),
            "submissionTypes": .array([.string("online_upload")]),
            "allowedExtensions": .array([.string("pdf")]),
            "dueAt": .string("2026-03-20T23:59:00Z"),
        ]

        if let submitted {
            assignmentObject["submitted"] = .bool(submitted)
        }

        if let submissionStatus {
            assignmentObject["submissionStatus"] = .string(submissionStatus.rawValue)
        }

        if let submissionSummary {
            assignmentObject["submission"] = .object(submissionSummary)
        }

        let moduleItem: [String: CourseBrainJSONValue] = [
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
        ]

        let moduleObject: [String: CourseBrainJSONValue] = [
            "id": .string(moduleId),
            "name": .string(moduleName),
            "position": .number(1),
            "items": .array([.object(moduleItem)]),
        ]

        let courseObject: [String: CourseBrainJSONValue] = [
            "courseId": .number(Double(courseId)),
            "courseName": .string(courseName),
        ]

        return [
            "sourceApp": .string("Canvascope"),
            "platform": .string("canvas"),
            "scannedAt": .string("2026-03-07T17:00:00Z"),
            "course": .object(courseObject),
            "modules": .array([.object(moduleObject)]),
            "indexedContent": .array([
                .object(assignmentObject),
            ]),
        ]
    }

    func isoDate(_ raw: String) -> Date {
        courseBrainParseISODate(raw)!
    }

    func makeCourseTwin(
        courseId: Int,
        courseName: String,
        scannedAt: Date?,
        missions: [CourseMission],
        resources: [MissionResource]
    ) -> CourseTwin {
        CourseTwin(
            courseId: courseId,
            snapshotFingerprint: "snapshot-\(courseId)",
            metadata: CourseTwinMetadata(
                courseName: courseName,
                courseCode: nil,
                termName: nil,
                startAt: nil,
                endAt: nil,
                defaultView: nil,
                workflowState: nil,
                enrollmentState: nil,
                imageURL: nil,
                syllabusText: nil,
                platform: "canvas",
                platformDomain: "example.instructure.com",
                sourceApp: "Canvascope",
                sourceKind: "snapshot",
                scannedAt: scannedAt,
                teacherSummaries: [],
                scanStats: [:]
            ),
            assignmentGroups: [],
            modules: [],
            resources: resources,
            missions: missions,
            conceptClusters: [],
            noteEvidence: []
        )
    }

    func makeMission(
        courseId: Int,
        assignmentId: String,
        title: String,
        dueAt: Date?,
        unlockAt: Date? = nil,
        lockAt: Date? = nil,
        moduleId: String? = "module-1",
        moduleName: String? = "Week 1",
        assignmentGroupId: String? = nil,
        assignmentGroupName: String? = nil,
        submitted: Bool? = nil,
        submissionStatus: CourseBrainSubmissionStatus? = nil,
        submissionSummary: CourseBrainSubmissionSummary? = nil
    ) -> CourseMission {
        CourseMission(
            courseId: courseId,
            assignmentId: assignmentId,
            snapshotFingerprint: "snapshot-\(courseId)",
            title: title,
            resourceId: "resource-\(assignmentId)",
            moduleId: moduleId,
            moduleName: moduleName,
            modulePosition: 1,
            assignmentGroupId: assignmentGroupId,
            assignmentGroupName: assignmentGroupName,
            dueAt: dueAt,
            unlockAt: unlockAt,
            lockAt: lockAt,
            pointsPossible: nil,
            submissionTypes: [],
            allowedExtensions: [],
            submitted: submitted,
            submissionStatus: submissionStatus,
            submissionSummary: submissionSummary,
            instructions: "Instructions for \(title)",
            url: URL(string: "https://example.instructure.com/courses/\(courseId)/assignments/\(assignmentId)"),
            linkedConceptIDs: [],
            linkedEvidenceIDs: [],
            missionArtifact: nil,
            studyPlan: nil
        )
    }

    func makeResource(
        id: String,
        kind: CourseBrainMissionResourceKind,
        courseId: Int,
        snapshotFingerprint: String,
        title: String,
        moduleId: String?,
        moduleName: String?,
        assignmentGroupId: String?,
        assignmentGroupName: String?,
        datedAt: Date?
    ) -> MissionResource {
        MissionResource(
            id: id,
            kind: kind,
            courseId: courseId,
            snapshotFingerprint: snapshotFingerprint,
            assignmentId: nil,
            title: title,
            courseName: "Course \(courseId)",
            moduleId: moduleId,
            moduleName: moduleName,
            modulePosition: 1,
            moduleItemId: nil,
            moduleItemPosition: 1,
            assignmentGroupId: assignmentGroupId,
            assignmentGroupName: assignmentGroupName,
            folderPath: nil,
            dueAt: datedAt,
            unlockAt: nil,
            lockAt: nil,
            scannedAt: datedAt,
            updatedAt: datedAt,
            published: true,
            pointsPossible: nil,
            submissionTypes: [],
            allowedExtensions: [],
            submitted: nil,
            submissionStatus: nil,
            submissionSummary: nil,
            platform: "canvas",
            platformDomain: "example.instructure.com",
            url: URL(string: "https://example.instructure.com/resources/\(id)"),
            contentId: nil,
            contentType: nil,
            sizeBytes: nil,
            instructions: nil,
            description: nil,
            body: nil,
            content: nil,
            text: nil,
            rawItem: [:]
        )
    }
}

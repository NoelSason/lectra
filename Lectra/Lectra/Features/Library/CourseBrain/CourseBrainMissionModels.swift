import Foundation

enum CourseBrainMissionResourceKind: String, Codable, CaseIterable, Hashable {
    case assignment
    case page
    case discussion
    case file
    case lecture
    case module
}

enum CourseBrainEvidenceSourceKind: String, Codable, CaseIterable, Hashable {
    case noteNode
    case noteSelection
    case pdfSelection
    case manualLink
}

enum CourseBrainEvidenceTargetKind: String, Codable, CaseIterable, Hashable {
    case assignment
    case concept
    case resource
    case lecture
}

enum CourseBrainSubmissionStatus: String, Codable, Hashable {
    case submitted
    case late
    case missing
    case excused
    case notSubmitted = "not_submitted"
    case unknown

    var displayTitle: String {
        switch self {
        case .submitted:
            return "Submitted"
        case .late:
            return "Late"
        case .missing:
            return "Missing"
        case .excused:
            return "Excused"
        case .notSubmitted:
            return "Not Submitted"
        case .unknown:
            return "Unknown"
        }
    }

    var isCompletionState: Bool {
        switch self {
        case .submitted, .excused:
            return true
        case .late, .missing, .notSubmitted, .unknown:
            return false
        }
    }

    var attentionSortRank: Int {
        switch self {
        case .late, .missing, .notSubmitted:
            return 0
        case .unknown:
            return 1
        case .submitted, .excused:
            return 2
        }
    }

    static func parseCanvasValue(_ rawValue: String?) -> CourseBrainSubmissionStatus? {
        guard let rawValue else { return nil }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case "submitted", "complete", "completed":
            return .submitted
        case "late", "late_submission":
            return .late
        case "missing":
            return .missing
        case "excused":
            return .excused
        case "notsubmitted", "not_submitted", "unsubmitted", "not_turned_in":
            return .notSubmitted
        default:
            return CourseBrainSubmissionStatus(rawValue: normalized) ?? .unknown
        }
    }

    static func resolveHeadlineStatus(
        submitted: Bool?,
        submissionStatus: CourseBrainSubmissionStatus?,
        submissionSummary: CourseBrainSubmissionSummary?
    ) -> CourseBrainSubmissionStatus? {
        if let submissionStatus, submissionStatus != .unknown {
            return submissionStatus
        }

        if let summaryStatus = submissionSummary?.headlineSubmissionStatus {
            return summaryStatus
        }

        if submitted == true {
            return .submitted
        }

        if submitted == false {
            return .notSubmitted
        }

        return submissionStatus
    }
}

struct CourseBrainSubmissionSummary: Codable, Hashable {
    let workflowState: String?
    let submittedAt: Date?
    let attempt: Int?
    let late: Bool?
    let missing: Bool?
    let excused: Bool?
    let grade: String?
    let score: Double?
    let submissionType: String?
    let hasSubmittedSubmissions: Bool?
    let gradeMatchesCurrentSubmission: Bool?

    var headlineSubmissionStatus: CourseBrainSubmissionStatus? {
        if excused == true {
            return .excused
        }

        if missing == true {
            return .missing
        }

        if late == true {
            return .late
        }

        if let workflowStatus = CourseBrainSubmissionStatus.parseCanvasValue(workflowState),
           workflowStatus != .unknown {
            return workflowStatus
        }

        if submittedAt != nil || hasSubmittedSubmissions == true || gradeMatchesCurrentSubmission == true {
            return .submitted
        }

        return nil
    }

    static func parseCanvasObject(_ object: [String: CourseBrainJSONValue]) -> CourseBrainSubmissionSummary? {
        guard let submissionObject = object.object("submission") else { return nil }

        let summary = CourseBrainSubmissionSummary(
            workflowState: submissionObject.firstString(keys: ["workflowState", "workflow_state"]),
            submittedAt: courseBrainParseISODate(submissionObject.firstString(keys: ["submittedAt", "submitted_at"])),
            attempt: submissionObject.int("attempt"),
            late: submissionObject.bool("late"),
            missing: submissionObject.bool("missing"),
            excused: submissionObject.bool("excused"),
            grade: submissionObject.firstString(keys: ["grade"]),
            score: submissionObject.double("score"),
            submissionType: submissionObject.firstString(keys: ["submissionType", "submission_type"]),
            hasSubmittedSubmissions: submissionObject.bool("hasSubmittedSubmissions")
                ?? submissionObject.bool("has_submitted_submissions"),
            gradeMatchesCurrentSubmission: submissionObject.bool("gradeMatchesCurrentSubmission")
                ?? submissionObject.bool("grade_matches_current_submission")
        )

        let hasMeaningfulValue =
            summary.workflowState != nil
            || summary.submittedAt != nil
            || summary.attempt != nil
            || summary.late != nil
            || summary.missing != nil
            || summary.excused != nil
            || summary.grade != nil
            || summary.score != nil
            || summary.submissionType != nil
            || summary.hasSubmittedSubmissions != nil
            || summary.gradeMatchesCurrentSubmission != nil

        return hasMeaningfulValue ? summary : nil
    }
}

struct CourseBrainRect: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct CourseTwin: Identifiable, Hashable {
    let courseId: Int
    let snapshotFingerprint: String
    let metadata: CourseTwinMetadata
    let assignmentGroups: [CourseBrainAssignmentGroup]
    let modules: [CourseBrainModule]
    let resources: [MissionResource]
    let missions: [CourseMission]
    let conceptClusters: [ConceptCluster]
    let noteEvidence: [NoteEvidence]

    var id: String {
        "course_twin:\(courseId):\(snapshotFingerprint)"
    }
}

struct CourseTwinMetadata: Hashable {
    let courseName: String
    let courseCode: String?
    let termName: String?
    let startAt: Date?
    let endAt: Date?
    let defaultView: String?
    let workflowState: String?
    let enrollmentState: String?
    let imageURL: URL?
    let syllabusText: String?
    let platform: String?
    let platformDomain: String?
    let sourceApp: String?
    let sourceKind: String?
    let scannedAt: Date?
    let teacherSummaries: [String]
    let scanStats: [String: CourseBrainJSONValue]
}

struct CourseBrainAssignmentGroup: Identifiable, Hashable {
    let courseId: Int
    let rawGroupId: String?
    let name: String
    let position: Int?
    let groupWeight: Double?
    let rules: [String: CourseBrainJSONValue]

    var id: String {
        rawGroupId ?? "assignment_group:\(courseId):\(courseBrainStableHash(name))"
    }
}

struct CourseBrainModule: Identifiable, Hashable {
    let courseId: Int
    let rawModuleId: String?
    let name: String
    let position: Int?
    let published: Bool?
    let unlockAt: Date?
    let items: [CourseBrainModuleItem]

    var id: String {
        rawModuleId ?? "module:\(courseId):\(courseBrainStableHash(name))"
    }
}

struct CourseBrainModuleItem: Identifiable, Hashable {
    let moduleId: String
    let rawItemId: String?
    let contentId: String?
    let position: Int?
    let title: String
    let type: String
    let url: URL?
    let pageURL: String?
    let published: Bool?
    let completionRequirement: [String: CourseBrainJSONValue]
    let contentDetails: [String: CourseBrainJSONValue]

    var id: String {
        rawItemId ?? "module_item:\(moduleId):\(courseBrainStableHash(title))"
    }
}

struct MissionResource: Identifiable, Hashable {
    let id: String
    let kind: CourseBrainMissionResourceKind
    let courseId: Int
    let snapshotFingerprint: String
    let assignmentId: String?
    let title: String
    let courseName: String?
    let moduleId: String?
    let moduleName: String?
    let modulePosition: Int?
    let moduleItemId: String?
    let moduleItemPosition: Int?
    let assignmentGroupId: String?
    let assignmentGroupName: String?
    let folderPath: String?
    let dueAt: Date?
    let unlockAt: Date?
    let lockAt: Date?
    let scannedAt: Date?
    let updatedAt: Date?
    let published: Bool?
    let pointsPossible: Double?
    let submissionTypes: [String]
    let allowedExtensions: [String]
    let submitted: Bool?
    let submissionStatus: CourseBrainSubmissionStatus?
    let submissionSummary: CourseBrainSubmissionSummary?
    let platform: String?
    let platformDomain: String?
    let url: URL?
    let contentId: String?
    let contentType: String?
    let sizeBytes: Int?
    let instructions: String?
    let description: String?
    let body: String?
    let content: String?
    let text: String?
    let rawItem: [String: CourseBrainJSONValue]

    var primaryText: String? {
        for candidate in [instructions, description, body, content, text] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }

    var searchableText: String {
        [
            title,
            courseName,
            moduleName,
            assignmentGroupName,
            folderPath,
            instructions,
            description,
            body,
            content,
            text,
            platform,
            platformDomain,
            contentType
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    var headlineSubmissionStatus: CourseBrainSubmissionStatus? {
        CourseBrainSubmissionStatus.resolveHeadlineStatus(
            submitted: submitted,
            submissionStatus: submissionStatus,
            submissionSummary: submissionSummary
        )
    }
}

struct CourseMission: Identifiable, Hashable {
    let courseId: Int
    let assignmentId: String
    let snapshotFingerprint: String
    let title: String
    let resourceId: String
    let moduleId: String?
    let moduleName: String?
    let modulePosition: Int?
    let assignmentGroupId: String?
    let assignmentGroupName: String?
    let dueAt: Date?
    let unlockAt: Date?
    let lockAt: Date?
    let pointsPossible: Double?
    let submissionTypes: [String]
    let allowedExtensions: [String]
    let submitted: Bool?
    let submissionStatus: CourseBrainSubmissionStatus?
    let submissionSummary: CourseBrainSubmissionSummary?
    let instructions: String?
    let url: URL?
    let linkedConceptIDs: [String]
    let linkedEvidenceIDs: [String]
    let missionArtifact: CourseBrainMissionArtifact?
    let studyPlan: CourseBrainStudyPlanArtifact?

    var id: String { assignmentId }

    var headlineSubmissionStatus: CourseBrainSubmissionStatus? {
        CourseBrainSubmissionStatus.resolveHeadlineStatus(
            submitted: submitted,
            submissionStatus: submissionStatus,
            submissionSummary: submissionSummary
        )
    }
}

struct ConceptCluster: Identifiable, Hashable {
    let id: String
    let title: String
    let score: Double
    let resourceIDs: [String]
}

struct NoteEvidence: Identifiable, Hashable {
    let id: String
    let rowId: UUID?
    let courseId: Int?
    let assignmentId: String?
    let snapshotFingerprint: String?
    let sourceKind: CourseBrainEvidenceSourceKind
    let targetKind: CourseBrainEvidenceTargetKind
    let targetId: String
    let sourceNodeId: String?
    let sourceDocumentId: UUID?
    let selectionText: String?
    let excerpt: String?
    let pageIndex: Int?
    let pageRect: CourseBrainRect?
    let createdAt: Date
    let updatedAt: Date
    let rawPayload: [String: CourseBrainJSONValue]
}

struct StudySprint: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let summary: String
    let startAt: Date?
    let dueAt: Date?
    let resourceIDs: [String]
    let conceptIDs: [String]
}

struct CourseBrainMissionArtifact: Identifiable, Hashable {
    let rowId: UUID
    let courseId: Int
    let assignmentId: String
    let snapshotFingerprint: String
    let briefMarkdown: String?
    let shortlistedResourceIDs: [String]
    let conceptIDs: [String]
    let evidenceIDs: [String]
    let createdAt: Date
    let updatedAt: Date
    let rawPayload: [String: CourseBrainJSONValue]

    var id: UUID { rowId }
}

struct CourseBrainStudyPlanArtifact: Identifiable, Hashable {
    let rowId: UUID
    let courseId: Int
    let assignmentId: String
    let snapshotFingerprint: String
    let sprints: [StudySprint]
    let createdAt: Date
    let updatedAt: Date
    let rawPayload: [String: CourseBrainJSONValue]

    var id: UUID { rowId }
}

struct CourseBrainEvidenceLink: Identifiable, Hashable {
    let rowId: UUID
    let courseId: Int?
    let assignmentId: String?
    let snapshotFingerprint: String?
    let sourceKind: CourseBrainEvidenceSourceKind
    let targetKind: CourseBrainEvidenceTargetKind
    let targetId: String
    let sourceNodeId: String?
    let sourceDocumentId: UUID?
    let selectionText: String?
    let excerpt: String?
    let pageIndex: Int?
    let pageRect: CourseBrainRect?
    let createdAt: Date
    let updatedAt: Date
    let rawPayload: [String: CourseBrainJSONValue]

    var id: UUID { rowId }
}

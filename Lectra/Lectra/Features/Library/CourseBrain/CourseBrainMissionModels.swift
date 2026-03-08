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
    let instructions: String?
    let url: URL?
    let linkedConceptIDs: [String]
    let linkedEvidenceIDs: [String]
    let missionArtifact: CourseBrainMissionArtifact?
    let studyPlan: CourseBrainStudyPlanArtifact?

    var id: String { assignmentId }
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

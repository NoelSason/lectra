import Foundation

// MARK: - Generic JSON

enum CourseBrainJSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: CourseBrainJSONValue])
    case array([CourseBrainJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }

        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }

        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        if let value = try? container.decode([String: CourseBrainJSONValue].self) {
            self = .object(value)
            return
        }

        if let value = try? container.decode([CourseBrainJSONValue].self) {
            self = .array(value)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON payload")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    nonisolated var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    nonisolated var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    nonisolated var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }

    nonisolated var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            return (value as NSString).boolValue
        default:
            return nil
        }
    }

    nonisolated var objectValue: [String: CourseBrainJSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    nonisolated var arrayValue: [CourseBrainJSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }
}

extension Dictionary where Key == String, Value == CourseBrainJSONValue {
    nonisolated func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    nonisolated func int(_ key: String) -> Int? {
        self[key]?.intValue
    }

    nonisolated func double(_ key: String) -> Double? {
        self[key]?.doubleValue
    }

    nonisolated func bool(_ key: String) -> Bool? {
        self[key]?.boolValue
    }

    nonisolated func object(_ key: String) -> [String: CourseBrainJSONValue]? {
        self[key]?.objectValue
    }

    nonisolated func array(_ key: String) -> [CourseBrainJSONValue]? {
        self[key]?.arrayValue
    }

    nonisolated func firstString(keys: [String]) -> String? {
        for key in keys {
            if let value = string(key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}

// MARK: - Graph Types

enum CourseBrainNodeType: String, Codable, CaseIterable {
    case topic
    case lecture
    case assignment
    case note
    case file
    case concept
}

enum CourseBrainRelationship: String, Codable, CaseIterable {
    case teaches
    case tests
    case references
    case assignmentToLecture
    case belongsToLecture
    case manualLink
}

struct CourseBrainNodeMetadata: Hashable {
    var courseName: String?
    var moduleName: String?
    var assignmentId: String?
    var dueAt: Date?
    var unlockAt: Date?
    var lockAt: Date?
    var scannedAt: Date?
    var folderPath: String?
    var platform: String?
    var sourceItemType: String?
    var sourceSyncedItemId: UUID?
    var sourceURLString: String?
    var submitted: Bool?
    var submissionStatus: CourseBrainSubmissionStatus?
    var submissionSummary: CourseBrainSubmissionSummary?
    var instructions: String?
    var description: String?
    var body: String?
    var content: String?
    var text: String?

    var bestInstructionText: String? {
        for candidate in [instructions, description, body, content, text] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }

    var headlineSubmissionStatus: CourseBrainSubmissionStatus? {
        CourseBrainSubmissionStatus.resolveHeadlineStatus(
            submitted: submitted,
            submissionStatus: submissionStatus,
            submissionSummary: submissionSummary
        )
    }
}

struct CourseBrainNode: Identifiable, Hashable {
    let id: String
    let type: CourseBrainNodeType
    let title: String
    let courseId: Int?
    let metadata: CourseBrainNodeMetadata
    let resourceURL: URL?

    var searchableText: String {
        [
            title,
            metadata.courseName,
            metadata.moduleName,
            metadata.folderPath,
            metadata.instructions,
            metadata.description,
            metadata.body,
            metadata.content,
            metadata.text,
            metadata.sourceItemType
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

struct CourseBrainEdge: Identifiable, Hashable {
    let id: String
    let source: String
    let target: String
    let relationship: CourseBrainRelationship
    let directional: Bool
    let inferred: Bool
    let manualLinkRowId: UUID?
}

struct CourseBrainGraph {
    let nodes: [CourseBrainNode]
    let edges: [CourseBrainEdge]
    let generatedAt: Date
    let fullNodeCount: Int
    let fullEdgeCount: Int
    let fingerprint: String

    var isCapped: Bool {
        fullNodeCount > nodes.count || fullEdgeCount > edges.count
    }
}

struct CourseBrainTimelineBucket: Identifiable, Hashable {
    let id: String
    let title: String
    let sortDate: Date?
    let items: [CourseBrainNode]
}

struct CourseBrainSourceRecord: Hashable {
    let sourceSyncedItemId: UUID
    let sourceItemType: String
    let courseId: Int?
    let courseName: String?
    let assignmentId: String?
    let type: String
    let title: String
    let moduleName: String?
    let folderPath: String?
    let dueAt: Date?
    let lockAt: Date?
    let unlockAt: Date?
    let scannedAt: Date?
    let url: URL?
    let platform: String?
    let submitted: Bool?
    let submissionStatus: CourseBrainSubmissionStatus?
    let submissionSummary: CourseBrainSubmissionSummary?
    let instructions: String?
    let description: String?
    let body: String?
    let content: String?
    let text: String?

    var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var headlineSubmissionStatus: CourseBrainSubmissionStatus? {
        CourseBrainSubmissionStatus.resolveHeadlineStatus(
            submitted: submitted,
            submissionStatus: submissionStatus,
            submissionSummary: submissionSummary
        )
    }
}

struct CourseBrainManualLink: Hashable {
    let rowId: UUID
    let sourceNodeId: String
    let targetNodeId: String
    let relationship: CourseBrainRelationship
    let courseId: Int?
    let createdAt: Date
}

struct CourseBrainConceptCacheConcept: Codable, Hashable {
    let id: String
    let title: String
    let score: Double
}

struct CourseBrainBuildPayload {
    let records: [CourseBrainSourceRecord]
    let localNotes: [CourseBrainNode]
    let syncedNoteNodes: [CourseBrainNode]
    let manualLinks: [CourseBrainManualLink]
    let courseFilter: Int?
}

struct CourseBrainTopicBucket: Identifiable, Hashable {
    let id: String
    let title: String
    let courseId: Int?
    let memberNodeIDs: [String]
    let countsByType: [CourseBrainNodeType: Int]
    let topConceptIDs: [String]
}

struct CourseBrainLeafSummary: Identifiable, Hashable {
    let id: String
    let type: CourseBrainNodeType
    let title: String
    let courseId: Int?
    let courseName: String?
    let moduleName: String?
    let assignmentId: String?
    let dueAt: Date?
    let unlockAt: Date?
    let lockAt: Date?
    let url: URL?
    let submitted: Bool?
    let submissionStatus: CourseBrainSubmissionStatus?
    let submissionSummary: CourseBrainSubmissionSummary?
    let instructionPreview: String?

    var headlineSubmissionStatus: CourseBrainSubmissionStatus? {
        CourseBrainSubmissionStatus.resolveHeadlineStatus(
            submitted: submitted,
            submissionStatus: submissionStatus,
            submissionSummary: submissionSummary
        )
    }
}

enum CourseBrainLeftSection: String, CaseIterable, Identifiable {
    case topics = "Topics"
    case concepts = "Concepts"
    case assignments = "Assignments"
    case lectures = "Lectures"
    case files = "Files"
    case timeline = "Timeline"

    var id: String { rawValue }
}

enum CourseBrainDisplayMode: String, CaseIterable, Identifiable {
    case graph = "Graph"
    case timeline = "Timeline"

    var id: String { rawValue }
}

enum CourseBrainGraphDensityMode: String, CaseIterable, Identifiable {
    case overviewTopicFirst
    case expandedTopic

    var id: String { rawValue }
}

struct CourseBrainCourseSummary: Identifiable, Hashable {
    let id: Int
    let name: String
    let count: Int
}

extension DateFormatter {
    nonisolated static let courseBrainTimelineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-'W'ww"
        return formatter
    }()
}

extension ISO8601DateFormatter {
    nonisolated static let courseBrainFlexible: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated static let courseBrainStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

nonisolated func courseBrainParseISODate(_ raw: String?) -> Date? {
    guard let raw else { return nil }
    if let parsed = ISO8601DateFormatter.courseBrainFlexible.date(from: raw) {
        return parsed
    }
    return ISO8601DateFormatter.courseBrainStandard.date(from: raw)
}

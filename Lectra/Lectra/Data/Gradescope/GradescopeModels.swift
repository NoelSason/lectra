import Foundation
import CryptoKit

enum GSError: LocalizedError {
    case invalidCredentials
    case missingAuthToken
    case missingCSRFToken
    case unauthorized
    case webSessionImportFailed
    case parsingFailed(String)
    case network(String)
    case noTemplateAvailable
    case fileNotFound
    case invalidFileType
    case emptyFile
    case duplicateSubmission
    case confirmationRequired
    case uploadFailed
    case workflowNotFound
    case workflowIncomplete(String)
    case contractMismatch
    case webRunnerFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Gradescope credentials."
        case .missingAuthToken:
            return "Could not find login token on Gradescope."
        case .missingCSRFToken:
            return "Could not retrieve CSRF token from Gradescope."
        case .unauthorized:
            return "Gradescope session expired. Please sign in again."
        case .webSessionImportFailed:
            return "Could not import the Gradescope web session. Please complete sign-in and try again."
        case .parsingFailed(let detail):
            return "Could not parse Gradescope response: \(detail)"
        case .network(let detail):
            return "Network error: \(detail)"
        case .noTemplateAvailable:
            return "No PDF template found for this assignment."
        case .fileNotFound:
            return "Selected file was not found."
        case .invalidFileType:
            return "Only PDF files are supported in this version."
        case .emptyFile:
            return "File is empty and cannot be submitted."
        case .duplicateSubmission:
            return "Same file was submitted to this assignment recently."
        case .confirmationRequired:
            return "Please confirm before submitting."
        case .uploadFailed:
            return "Gradescope submission failed."
        case .workflowNotFound:
            return "Submission workflow no longer exists. Start again from preflight."
        case .workflowIncomplete(let detail):
            return detail
        case .contractMismatch:
            return "Gradescope submission contract changed. Open submission editor to continue."
        case .webRunnerFailed(let detail):
            return "Web submission fallback failed: \(detail)"
        }
    }
}

struct GSCourse: Identifiable, Codable, Hashable {
    let id: String
    let shortName: String
    let fullName: String
}

struct GSAssignment: Identifiable, Codable, Hashable {
    let id: String
    let courseId: String
    let name: String
    let releaseDate: Date?
    let dueDate: Date?
    let lateDueDate: Date?
    let submissionsStatus: String?
    let grade: Double?
    let maxGrade: Double?

    var isSubmittable: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum GSTemplateResult {
    case available(downloadURL: URL, suggestedFileName: String)
    case noTemplate
}

struct GSSubmissionDraft {
    let documentId: UUID?
    let courseId: String
    let assignmentId: String
    let localFileURL: URL
}

struct GSPreflightResult {
    let isReady: Bool
    let issues: [String]
    let warnings: [String]
    let fileSHA256: String?
    let fileSizeBytes: Int64?
}

struct GSSubmissionReceipt {
    let assignmentId: String
    let submittedAt: Date
    let submissionURL: URL?
    let isDryRun: Bool
}

enum GSUploadStatus: String, Codable {
    case uploadedNeedsFinalize
    case finalized
}

enum GSUploadNextAction: String, Codable {
    case manageGroupMembers
    case assignPages
    case finalize
    case none
}

struct GSUploadResult: Codable {
    let status: GSUploadStatus
    let submissionURL: URL?
    let nextAction: GSUploadNextAction
    let workflow: GSSubmissionWorkflow?
}

enum GSRequiredFieldType: String, Codable {
    case text
    case email
    case number
    case select
    case checkbox
    case radio
    case textarea
    case hidden
    case unknown
}

struct GSRequiredFieldOption: Codable, Hashable {
    let value: String
    let label: String
}

struct GSRequiredField: Codable, Hashable {
    let name: String
    let label: String
    let type: GSRequiredFieldType
    let options: [GSRequiredFieldOption]
    let defaultValue: String?
    let isRequired: Bool
}

struct GSSubmissionSubmitButton: Codable, Hashable {
    let name: String?
    let value: String?
    let label: String
    let formActionURL: URL?
    let formMethod: String?
    let formEnctype: String?
}

struct GSSubmissionFormContract: Codable, Hashable {
    let targetURL: URL
    let method: String
    let enctype: String?
    let fileFieldName: String
    let hiddenFields: [String: String]
    let defaultFields: [String: String]
    let submitButtonSpec: GSSubmissionSubmitButton?
    let requiredFields: [GSRequiredField]
    let directUploadURL: URL?
}

struct GSGroupMemberDraft: Codable, Hashable {
    let emailOrUserId: String
    let role: String?
}

struct GSPageAssignmentDraft: Codable, Hashable {
    let questionId: String
    let pageIndexes: [Int]
}

struct GSPageQuestion: Codable, Hashable, Identifiable {
    let id: String
    let title: String
}

struct GSSubmissionWorkflow: Codable, Identifiable {
    let id: String
    let courseId: String
    let assignmentId: String
    let uploadURL: URL
    let submissionURL: URL?
    let requiresGroupStep: Bool
    let requiresPageStep: Bool
    let detectedQuestions: [GSPageQuestion]
    let detectedPageCount: Int?
    let finalized: Bool
}

struct GSGroupUpdateResult: Codable {
    let workflowId: String
    let members: [GSGroupMemberDraft]
    let warnings: [String]
}

struct GSPageAssignmentResult: Codable {
    let workflowId: String
    let assignments: [GSPageAssignmentDraft]
    let warnings: [String]
}

struct GSWebRunnerResult {
    let statusCode: Int
    let finalURL: URL
    let bodyHTML: String
}

enum GSLinkMode: String, Codable {
    case template
    case direct
}

struct GSLinkedDocument: Codable, Hashable {
    let documentId: UUID
    let courseId: String
    let assignmentId: String
    let mode: GSLinkMode
    let linkedAt: Date
    var lastSubmittedAt: Date?
    var lastSubmissionURL: String?
}

struct GSSessionSnapshot: Codable {
    let cookieArchive: Data
    let csrfToken: String
    let savedAt: Date
}

protocol GradescopeAuthenticating {
    var isAuthenticated: Bool { get }
    func restoreSession() async -> Bool
    func login(email: String, password: String) async throws
    func loginWithImportedWebSession(cookies: [HTTPCookie], accountPageHTML: String?) async throws
    func logout()
}

protocol GradescopeCatalogProviding {
    func fetchCourses() async throws -> [GSCourse]
    func fetchAssignments(courseId: String) async throws -> [GSAssignment]
}

protocol GradescopeTemplateImporting {
    func fetchTemplate(for assignment: GSAssignment) async throws -> GSTemplateResult
    func downloadTemplate(url: URL, suggestedFileName: String) async throws -> URL
}

protocol GradescopeSubmitting {
    func preflight(draft: GSSubmissionDraft) async throws -> GSPreflightResult
    func submit(draft: GSSubmissionDraft, confirmed: Bool) async throws -> GSSubmissionReceipt
    func prepareSubmissionWorkflow(draft: GSSubmissionDraft) async throws -> GSSubmissionWorkflow
    func uploadPDF(workflowId: String, confirmed: Bool) async throws -> GSUploadResult
    func updateGroupMembers(workflowId: String, members: [GSGroupMemberDraft]) async throws -> GSGroupUpdateResult
    func updatePageAssignments(workflowId: String, assignments: [GSPageAssignmentDraft]) async throws -> GSPageAssignmentResult
    func finalizeSubmission(workflowId: String) async throws -> GSSubmissionReceipt
}

protocol GradescopeSubmissionWebRunner {
    func runMultipartSubmission(
        pageURL: URL,
        targetURL: URL,
        fields: [String: String],
        fileFieldName: String,
        fileURL: URL,
        headers: [String: String]
    ) async throws -> GSWebRunnerResult

    func runFormSubmission(
        pageURL: URL,
        targetURL: URL,
        fields: [String: String],
        headers: [String: String]
    ) async throws -> GSWebRunnerResult

    func runDOMFormSubmission(
        pageURL: URL,
        fileURL: URL
    ) async throws -> GSWebRunnerResult
}

enum GradescopeDateParser {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = isoWithFractional.date(from: raw) { return date }
        if let date = isoStandard.date(from: raw) { return date }
        return fallbackFormatter.date(from: raw)
    }
}

extension Data {
    var sha256HexString: String {
        let digest = SHA256.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

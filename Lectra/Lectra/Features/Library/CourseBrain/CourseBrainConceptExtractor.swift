import Foundation

enum CourseBrainConceptSourceKind: Hashable {
    case assignment
    case lecture
    case file
    case note
    case page
    case discussion
    case module
}

struct CourseBrainConceptSource: Hashable {
    let id: String
    let text: String
    let kind: CourseBrainConceptSourceKind
}

enum CourseBrainText {
    nonisolated static func normalizeWhitespace(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func normalizeForMatching(_ raw: String) -> String {
        normalizeWhitespace(raw)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func slugify(_ raw: String) -> String {
        let lowered = normalizeForMatching(raw)
        if lowered.isEmpty {
            return "general"
        }
        return lowered.replacingOccurrences(of: " ", with: "-")
    }

    nonisolated static func titleFromConceptID(_ conceptID: String) -> String {
        conceptID
            .replacingOccurrences(of: "concept:", with: "")
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

struct CourseBrainConceptExtractor {
    static let shared = CourseBrainConceptExtractor()

    private let stopwords: Set<String> = [
        "the", "and", "for", "from", "with", "your", "this", "that", "into", "of", "to", "in", "on", "at", "by", "as", "is", "it", "be", "are", "or", "an", "a", "lab", "homework", "hw", "module", "assignment", "quiz", "lecture", "week", "class", "session", "notes", "note", "practice", "review", "page", "pages", "file", "files", "document", "documents", "course", "content", "resource", "resources", "admin", "links"
    ]

    func extractClusters(from sources: [CourseBrainConceptSource], limit: Int = 28) -> [ConceptCluster] {
        struct CandidateStats {
            var score: Double
            var appearances: Int
            var sourceKinds: Set<CourseBrainConceptSourceKind>
            var resourceIDs: Set<String>
        }

        var stats: [String: CandidateStats] = [:]

        for source in sources {
            let normalizedText = CourseBrainText.normalizeWhitespace(source.text)
            guard !normalizedText.isEmpty else { continue }

            let baseWeight = weight(for: source.kind)
            for phrase in conceptPhrases(from: normalizedText) {
                let slug = "concept:\(CourseBrainText.slugify(phrase))"
                var entry = stats[slug] ?? CandidateStats(score: 0, appearances: 0, sourceKinds: [], resourceIDs: [])
                entry.score += baseWeight
                entry.appearances += 1
                entry.sourceKinds.insert(source.kind)
                entry.resourceIDs.insert(source.id)
                stats[slug] = entry
            }
        }

        var results: [ConceptCluster] = []
        results.reserveCapacity(stats.count)

        for (id, info) in stats {
            guard info.appearances >= 2 || info.sourceKinds.count >= 2 else { continue }

            let title = CourseBrainText.titleFromConceptID(id)
            guard title.count >= 3 && title.count <= 40 else { continue }

            results.append(
                ConceptCluster(
                    id: id,
                    title: title,
                    score: info.score + Double(info.sourceKinds.count),
                    resourceIDs: info.resourceIDs.sorted()
                )
            )
        }

        results.sort { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.score > rhs.score
        }

        if results.count > limit {
            return Array(results.prefix(limit))
        }

        return results
    }

    private func weight(for kind: CourseBrainConceptSourceKind) -> Double {
        switch kind {
        case .lecture:
            return 1.25
        case .assignment:
            return 1.15
        case .note:
            return 1.05
        case .page:
            return 1.05
        case .discussion:
            return 0.95
        case .module:
            return 0.9
        case .file:
            return 1.0
        }
    }

    private func conceptPhrases(from text: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: "-:|()[]{}").union(.newlines)
        let segments = text
            .components(separatedBy: separators)
            .map(CourseBrainText.normalizeForMatching)
            .filter { !$0.isEmpty }

        var results: Set<String> = []

        for segment in segments {
            let tokens = segment
                .split(separator: " ")
                .map(String.init)
                .filter { token in
                    token.count >= 3 && !stopwords.contains(token)
                }

            guard !tokens.isEmpty else { continue }

            for n in 1...3 {
                guard tokens.count >= n else { continue }
                for index in 0...(tokens.count - n) {
                    let phrase = tokens[index..<(index + n)].joined(separator: " ")
                    guard phrase.count >= 3 && phrase.count <= 40 else { continue }
                    results.insert(phrase)
                }
            }
        }

        return results
    }
}

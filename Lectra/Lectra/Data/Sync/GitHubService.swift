//
//  GitHubService.swift
//  Lectra
//
//  Lightweight GitHub integration: connect an account (Supabase-managed GitHub
//  OAuth, token kept in the Keychain), browse repos/branches/files, pull files
//  into Lectra, and commit changes back via the REST Contents API — no libgit2,
//  no full clone. Pushes are conflict-guarded: if the remote file moved since we
//  last pulled, the push is refused so nothing is clobbered.
//

import Foundation
import Supabase
import AuthenticationServices

// MARK: - Models

struct GitHubRepo: Identifiable, Hashable {
    let fullName: String          // "owner/name"
    let defaultBranch: String
    let isPrivate: Bool
    var id: String { fullName }
    var shortName: String { fullName.split(separator: "/").last.map(String.init) ?? fullName }
}

struct GitHubBranch: Identifiable, Hashable {
    let name: String
    var id: String { name }
}

/// One entry in a repo directory listing.
struct GitHubEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let sha: String
    var id: String { path }
}

/// A pulled file's bytes plus the blob sha we based our copy on (for conflict
/// detection on push).
struct GitHubFile {
    let path: String
    let sha: String
    let data: Data
}

/// Binds a local document to a GitHub location so it can be pulled/pushed.
struct GitLink: Codable, Equatable {
    var repoFullName: String
    var branch: String
    var path: String
    var baseSha: String           // sha the local copy was last synced to
}

enum GitHubError: LocalizedError {
    case notConnected
    case http(Int, String)
    case decoding
    case conflict
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Connect a GitHub account first."
        case .http(let code, let msg): return "GitHub error \(code): \(msg)"
        case .decoding: return "Couldn’t read GitHub’s response."
        case .conflict: return "This file changed on GitHub since you pulled it. Pull the latest version first."
        case .tooLarge: return "That file is too large to open here."
        }
    }
}

// MARK: - Service

/// Stateless REST client over the GitHub Contents API. Auth comes from
/// `GitHubAuth` (Keychain-backed token).
struct GitHubService {
    static let shared = GitHubService()

    private let base = URL(string: "https://api.github.com")!
    private let maxBytes = 5 * 1024 * 1024   // contents API caps blobs ~ a few MB

    // MARK: Listing

    func repos() async throws -> [GitHubRepo] {
        let url = base.appendingPathComponent("user/repos")
            .appending(queryItems: [
                .init(name: "per_page", value: "100"),
                .init(name: "sort", value: "updated"),
                .init(name: "affiliation", value: "owner,collaborator,organization_member")
            ])
        let arr: [[String: Any]] = try await getJSONArray(url)
        return arr.compactMap { item in
            guard let fullName = item["full_name"] as? String else { return nil }
            return GitHubRepo(
                fullName: fullName,
                defaultBranch: (item["default_branch"] as? String) ?? "main",
                isPrivate: (item["private"] as? Bool) ?? false)
        }
    }

    func branches(repo: String) async throws -> [GitHubBranch] {
        let url = base.appendingPathComponent("repos/\(repo)/branches")
            .appending(queryItems: [.init(name: "per_page", value: "100")])
        let arr: [[String: Any]] = try await getJSONArray(url)
        return arr.compactMap { ($0["name"] as? String).map(GitHubBranch.init(name:)) }
    }

    /// Lists a directory in the repo. Empty `path` is the repo root.
    func contents(repo: String, path: String, ref: String) async throws -> [GitHubEntry] {
        let url = contentsURL(repo: repo, path: path, ref: ref)
        let arr: [[String: Any]] = try await getJSONArray(url)
        return arr.compactMap { item in
            guard let name = item["name"] as? String,
                  let p = item["path"] as? String,
                  let type = item["type"] as? String,
                  let sha = item["sha"] as? String else { return nil }
            return GitHubEntry(name: name, path: p, isDirectory: type == "dir", sha: sha)
        }
        .sorted { ($0.isDirectory ? 0 : 1, $0.name.lowercased()) < ($1.isDirectory ? 0 : 1, $1.name.lowercased()) }
    }

    // MARK: File pull / push

    func getFile(repo: String, path: String, ref: String) async throws -> GitHubFile {
        let url = contentsURL(repo: repo, path: path, ref: ref)
        let obj: [String: Any] = try await getJSONObject(url)
        guard let sha = obj["sha"] as? String else { throw GitHubError.decoding }
        if let size = obj["size"] as? Int, size > maxBytes { throw GitHubError.tooLarge }
        // Inline base64 content for normal-sized files.
        if let b64 = (obj["content"] as? String)?.replacingOccurrences(of: "\n", with: ""),
           let data = Data(base64Encoded: b64) {
            return GitHubFile(path: path, sha: sha, data: data)
        }
        // Fall back to the download_url for larger blobs.
        if let downloadURLString = obj["download_url"] as? String,
           let downloadURL = URL(string: downloadURLString) {
            let (data, _) = try await URLSession.shared.data(from: downloadURL)
            return GitHubFile(path: path, sha: sha, data: data)
        }
        throw GitHubError.decoding
    }

    /// Current remote sha for a path, or nil if the file doesn't exist yet.
    func remoteSha(repo: String, path: String, ref: String) async throws -> String? {
        do {
            let obj: [String: Any] = try await getJSONObject(contentsURL(repo: repo, path: path, ref: ref))
            return obj["sha"] as? String
        } catch GitHubError.http(404, _) {
            return nil
        }
    }

    /// Commits `data` to `link.path`, refusing if the remote moved past
    /// `link.baseSha`. Returns the new blob sha on success.
    func commit(_ data: Data, link: GitLink, message: String) async throws -> String {
        let current = try await remoteSha(repo: link.repoFullName, path: link.path, ref: link.branch)
        // For an existing file, the sha we base on must still be current.
        if let current, current != link.baseSha { throw GitHubError.conflict }
        // For a brand-new file we expect no remote sha.
        if current == nil, !link.baseSha.isEmpty { throw GitHubError.conflict }

        var body: [String: Any] = [
            "message": message,
            "content": data.base64EncodedString(),
            "branch": link.branch
        ]
        if let current { body["sha"] = current }

        let url = base.appendingPathComponent("repos/\(link.repoFullName)/contents/\(link.path)")
        let obj: [String: Any] = try await send(url, method: "PUT", body: body)
        guard let content = obj["content"] as? [String: Any],
              let newSha = content["sha"] as? String else { throw GitHubError.decoding }
        return newSha
    }

    // MARK: HTTP

    private func contentsURL(repo: String, path: String, ref: String) -> URL {
        base.appendingPathComponent("repos/\(repo)/contents/\(path)")
            .appending(queryItems: [.init(name: "ref", value: ref)])
    }

    private func authorizedRequest(_ url: URL, method: String) async throws -> URLRequest {
        guard let token = GitHubAuth.shared.token else { throw GitHubError.notConnected }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Lectra", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func getData(_ url: URL) async throws -> Data {
        let req = try await authorizedRequest(url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.validate(response, data: data)
        return data
    }

    private func getJSONArray(_ url: URL) async throws -> [[String: Any]] {
        let data = try await getData(url)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GitHubError.decoding
        }
        return arr
    }

    private func getJSONObject(_ url: URL) async throws -> [String: Any] {
        let data = try await getData(url)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubError.decoding
        }
        return obj
    }

    private func send(_ url: URL, method: String, body: [String: Any]) async throws -> [String: Any] {
        var req = try await authorizedRequest(url, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.validate(response, data: data)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubError.decoding
        }
        return obj
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?
                .flatMap { $0["message"] as? String } ?? "Request failed."
            throw GitHubError.http(http.statusCode, message)
        }
    }
}

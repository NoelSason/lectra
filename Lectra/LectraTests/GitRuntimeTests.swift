import XCTest
@testable import Lectra

/// Verifies real git runs inside the hidden WKWebView: the isomorphic-git engine
/// plus the native fs bridge (FileManager) and http bridge (URLSession). Local
/// tests need no network; the clone test skips when offline.
final class GitRuntimeTests: XCTestCase {

    private func tempRepoDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("git_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The core proof: init -> add -> commit -> log against the real sandbox FS.
    @MainActor
    func testLocalInitAddCommitLog() async {
        let git = GitRuntime()
        let dir = tempRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let initRes = await git.run(argv: ["init"], cwd: dir.path)
        XCTAssertEqual(initRes.exitCode, 0, initRes.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git/HEAD").path),
                      "init should create a real .git directory")

        try? Data("hi from lectra\n".utf8).write(to: dir.appendingPathComponent("hello.txt"))

        let addRes = await git.run(argv: ["add", "hello.txt"], cwd: dir.path)
        XCTAssertEqual(addRes.exitCode, 0, addRes.stderr)

        let commitRes = await git.run(argv: ["commit", "-m", "first commit"], cwd: dir.path)
        XCTAssertEqual(commitRes.exitCode, 0, commitRes.stderr)
        XCTAssertTrue(commitRes.stdout.contains("first commit"), commitRes.stdout)

        let logRes = await git.run(argv: ["log"], cwd: dir.path)
        XCTAssertEqual(logRes.exitCode, 0, logRes.stderr)
        XCTAssertTrue(logRes.stdout.contains("first commit"), logRes.stdout)
        git.shutdown()
    }

    /// status must see an untracked file created on disk by ordinary file I/O —
    /// proving the shell, the editor, and git share one filesystem.
    @MainActor
    func testStatusSeesUntrackedFile() async {
        let git = GitRuntime()
        let dir = tempRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = await git.run(argv: ["init"], cwd: dir.path)
        try? Data("# note".utf8).write(to: dir.appendingPathComponent("note.md"))

        let status = await git.run(argv: ["status"], cwd: dir.path)
        XCTAssertEqual(status.exitCode, 0, status.stderr)
        XCTAssertTrue(status.stdout.contains("note.md"), status.stdout)
        git.shutdown()
    }

    /// End-to-end network proof: clone a tiny public GitHub repo through the
    /// URLSession http bridge. Skipped (not failed) when offline.
    @MainActor
    func testCloneFromGitHub() async throws {
        let git = GitRuntime()
        let dir = tempRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let res = await git.run(argv: ["clone", "https://github.com/octocat/Hello-World.git"], cwd: dir.path)
        let lower = res.stderr.lowercased()
        if res.exitCode != 0,
           lower.contains("network") || lower.contains("connection") || lower.contains("offline") || lower.contains("could not resolve") {
            throw XCTSkip("No network available for clone: \(res.stderr)")
        }
        XCTAssertEqual(res.exitCode, 0, res.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Hello-World/.git/HEAD").path),
                      "clone should produce a checked-out working tree")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Hello-World/README").path),
                      "clone should check out repo files")
        git.shutdown()
    }
}

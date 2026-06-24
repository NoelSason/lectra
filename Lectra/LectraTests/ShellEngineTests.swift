import XCTest
@testable import Lectra

/// Exercises the native shell: parsing, pipes, redirection, globbing, variables,
/// and list operators — all against the real sandbox filesystem.
@MainActor
final class ShellEngineTests: XCTestCase {

    private func makeExecutor() -> (ShellExecutor, URL) {
        let env = ShellEnvironment()
        let dir = env.cwd.appendingPathComponent("shell_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        env.setCwd(dir)
        return (ShellExecutor(env: env, git: GitRuntime()), dir)
    }

    /// Collects everything emitted to the terminal for one line.
    private func run(_ exec: ShellExecutor, _ line: String) async -> String {
        var out = ""
        await exec.run(line) { text, _ in out += text }
        return out
    }

    func testPipeAndWordCount() async {
        let (exec, dir) = makeExecutor(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = await run(exec, "echo hello world | wc -w")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "2")
    }

    func testRedirectThenRead() async {
        let (exec, dir) = makeExecutor(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = await run(exec, "echo persisted > note.txt")
        let out = await run(exec, "cat note.txt")
        XCTAssertEqual(out, "persisted\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("note.txt").path))
    }

    func testAppendRedirect() async {
        let (exec, dir) = makeExecutor(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = await run(exec, "echo one > log.txt")
        _ = await run(exec, "echo two >> log.txt")
        let out = await run(exec, "cat log.txt")
        XCTAssertEqual(out, "one\ntwo\n")
    }

    func testAndOrShortCircuit() async {
        let (exec, dir) = makeExecutor(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = await run(exec, "cd missing_dir && echo SHOULD_NOT || echo recovered")
        XCTAssertTrue(out.contains("recovered"), out)
        XCTAssertFalse(out.contains("SHOULD_NOT"), out)
    }

    func testGlobbing() async {
        let (exec, dir) = makeExecutor(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = await run(exec, "touch a.txt b.txt c.md")
        let out = await run(exec, "ls *.txt")
        XCTAssertTrue(out.contains("a.txt"), out)
        XCTAssertTrue(out.contains("b.txt"), out)
        XCTAssertFalse(out.contains("c.md"), out)
    }

    func testVariablesAndExport() async {
        let (exec, dir) = makeExecutor(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = await run(exec, "export NAME=Lectra; echo hi $NAME")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "hi Lectra")
    }

    func testGrepThroughPipe() async {
        let (exec, dir) = makeExecutor(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = await run(exec, "echo apple > fruits.txt")
        _ = await run(exec, "echo banana >> fruits.txt")
        let out = await run(exec, "cat fruits.txt | grep ban")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "banana")
    }
}

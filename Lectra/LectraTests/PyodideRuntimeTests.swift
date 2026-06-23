import XCTest
@testable import Lectra

/// Verifies the Pyodide kernel boots and executes while its WKWebView is kept
/// off-window (so it can't capture hardware-keyboard input from the editor).
final class PyodideRuntimeTests: XCTestCase {

    @MainActor
    func testRunsPythonOffWindow() async {
        let runtime = PyodideRuntime()
        let result = await runtime.run("print(2 + 2)", cellID: "t1")
        XCTAssertNil(result.error, "unexpected error: \(result.error ?? "")")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "4")
        runtime.shutdown()
    }

    @MainActor
    func testCapturesLastExpressionRepr() async {
        let runtime = PyodideRuntime()
        let result = await runtime.run("21 * 2", cellID: "t2")
        XCTAssertNil(result.error, "unexpected error: \(result.error ?? "")")
        XCTAssertEqual(result.result, "42")
        runtime.shutdown()
    }

    @MainActor
    func testKernelStatePersistsAcrossRuns() async {
        let runtime = PyodideRuntime()
        _ = await runtime.run("x = 10", cellID: "a")
        let result = await runtime.run("print(x * 5)", cellID: "b")
        XCTAssertNil(result.error, "unexpected error: \(result.error ?? "")")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "50")
        runtime.shutdown()
    }
}

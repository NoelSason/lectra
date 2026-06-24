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

    /// The file-injection bridge used by CSV/TSV import: bytes written into the
    /// kernel FS must be readable by pandas. No network involved.
    @MainActor
    func testWriteFileLoadsIntoPandas() async {
        let runtime = PyodideRuntime()
        try? await runtime.start()
        let csv = "a,b\n1,2\n3,4\n"
        let ok = await runtime.writeFile(path: "unit_test.csv",
                                         base64: Data(csv.utf8).base64EncodedString())
        XCTAssertTrue(ok, "writeFile should report success")
        let result = await runtime.run(
            "import pandas as pd; print(pd.read_csv('unit_test.csv').shape)", cellID: "csv")
        XCTAssertNil(result.error, "unexpected error: \(result.error ?? "")")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "(2, 2)")
        runtime.shutdown()
    }

    /// Validates the package-install path end to end: micropip fetching a small
    /// pure-Python wheel from PyPI through the kernel WebView. Requires network;
    /// skipped (not failed) when offline so the suite stays green on air-gapped CI.
    @MainActor
    func testInstallsPurePythonPackageFromPyPI() async throws {
        let runtime = PyodideRuntime()
        let res = await runtime.install("cowsay")
        if !res.success, let error = res.error,
           error.lowercased().contains("network") || error.lowercased().contains("connection") {
            throw XCTSkip("No network available for micropip install: \(error)")
        }
        XCTAssertTrue(res.success, "install failed: \(res.error ?? "")")
        let result = await runtime.run("import cowsay; print('ok')", cellID: "imp")
        XCTAssertNil(result.error, "unexpected error: \(result.error ?? "")")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
        runtime.shutdown()
    }
}

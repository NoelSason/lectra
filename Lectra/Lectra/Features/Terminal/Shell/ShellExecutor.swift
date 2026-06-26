//
//  ShellExecutor.swift
//  Lectra
//
//  Runs a parsed command line: walks AndOr lists with short-circuit semantics,
//  executes pipelines by feeding one command's stdout into the next's stdin, and
//  applies redirections against FileManager. `git` is not a builtin — it's routed
//  to the GitRuntime, with clone/fetch/push progress streamed live to the screen.
//

import Foundation

@MainActor
final class ShellExecutor {
    let env: ShellEnvironment
    let git: GitRuntime
    private let python = TerminalPythonRuntime()

    init(env: ShellEnvironment, git: GitRuntime) {
        self.env = env
        self.git = git
    }

    /// Runs `line`, streaming output through `emit(text, isStderr)`. Returns the
    /// exit code of the last pipeline.
    @discardableResult
    func run(_ line: String, emit: @escaping (String, Bool) -> Void) async -> Int32 {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return env.lastExitCode }

        let cmdLine: ShellCommandLine
        do { cmdLine = try ShellParser.parse(line) }
        catch { emit((error.localizedDescription) + "\n", true); env.lastExitCode = 2; return 2 }

        var i = 0
        var lastCode: Int32 = 0
        while i < cmdLine.items.count {
            let (pipeline, connector) = cmdLine.items[i]
            lastCode = await runPipeline(pipeline, emit: emit)
            env.lastExitCode = lastCode

            // Short-circuit: with && skip the next on failure; with || skip on success.
            switch connector {
            case .and where lastCode != 0:
                i = skipUntilOr(cmdLine, from: i)
            case .or where lastCode == 0:
                i = skipUntilAnd(cmdLine, from: i)
            default:
                i += 1
            }
        }
        return lastCode
    }

    // Skip the following pipelines joined by && (their condition can't be met),
    // resuming at the next ; or || boundary.
    private func skipUntilOr(_ line: ShellCommandLine, from index: Int) -> Int {
        var j = index
        while j < line.items.count {
            let conn = line.items[j].1
            if conn == .and { j += 1; continue }
            return j + 1
        }
        return j + 1
    }
    private func skipUntilAnd(_ line: ShellCommandLine, from index: Int) -> Int {
        var j = index
        while j < line.items.count {
            let conn = line.items[j].1
            if conn == .or { j += 1; continue }
            return j + 1
        }
        return j + 1
    }

    // MARK: Pipeline

    private func runPipeline(_ pipeline: Pipeline, emit: @escaping (String, Bool) -> Void) async -> Int32 {
        var pipeInput = Data()
        var code: Int32 = 0

        for (idx, command) in pipeline.commands.enumerated() {
            let isLast = idx == pipeline.commands.count - 1

            // Expand argv.
            var argv: [String] = []
            for token in command.argv { argv.append(contentsOf: ShellExpander.expand(token, env: env)) }
            guard !argv.isEmpty else { continue }

            // Resolve input redirect (overrides the pipe).
            var io = CommandIO()
            io.stdin = pipeInput
            for redir in command.redirects {
                if case .input(let target) = redir {
                    let path = ShellExpander.expand(target, env: env).first ?? ""
                    if let url = env.resolve(path), let data = FileManager.default.contents(atPath: url.path) {
                        io.stdin = data
                    } else {
                        emit("\(path): No such file or directory\n", true)
                        code = 1
                    }
                }
            }

            // Run the command (git or builtin).
            if argv[0] == "git" {
                let result = await git.run(argv: Array(argv.dropFirst()), cwd: env.cwd.path) { line in
                    emit(line + "\n", false)
                }
                io.stdout.append(Data(result.stdout.utf8))
                io.stderr.append(Data(result.stderr.utf8))
                code = result.exitCode
            } else if TerminalPythonRuntime.commandNames.contains(argv[0]) {
                let result = await python.runCommand(arguments: Array(argv.dropFirst()), env: env)
                io.stdout.append(Data(result.stdout.utf8))
                io.stderr.append(Data(result.stderr.utf8))
                code = result.exitCode
            } else if let builtin = Builtins.all[argv[0]] {
                code = builtin.run(Array(argv.dropFirst()), io: &io, env: env)
            } else {
                emit("\(argv[0]): command not found\n", true)
                code = 127
                io.stderr = Data()
            }

            // stderr always streams to the terminal.
            if !io.stderr.isEmpty { emit(String(data: io.stderr, encoding: .utf8) ?? "", true) }

            // Handle stdout: file redirect, pipe to next, or terminal.
            var redirectedToFile = false
            for redir in command.redirects {
                switch redir {
                case .output(let target):
                    writeOut(io.stdout, target: target, append: false, emit: emit)
                    redirectedToFile = true
                case .append(let target):
                    writeOut(io.stdout, target: target, append: true, emit: emit)
                    redirectedToFile = true
                case .input: break
                }
            }
            if redirectedToFile {
                pipeInput = Data()
            } else if isLast {
                if !io.stdout.isEmpty { emit(String(data: io.stdout, encoding: .utf8) ?? "", false) }
            } else {
                pipeInput = io.stdout
            }
        }
        return code
    }

    private func writeOut(_ data: Data, target: WordToken, append: Bool, emit: @escaping (String, Bool) -> Void) {
        let path = ShellExpander.expand(target, env: env).first ?? ""
        guard let url = env.resolve(path) else { emit("\(path): outside the app sandbox\n", true); return }
        if append, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else if append && !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: data)
        } else {
            do { try data.write(to: url) } catch { emit("\(path): \(error.localizedDescription)\n", true) }
        }
    }
}

struct PythonTerminalOutput {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

@MainActor
final class TerminalPythonRuntime {
    static let commandNames: Set<String> = ["python", "python3"]
    static let versionLine = "Python 3.12.1 (Pyodide)\n"
    static let replBanner = versionLine + "Type \"exit()\" or \"quit()\" to leave.\n"

    private let runtime = PyodideRuntime()

    func runCommand(arguments: [String], env: ShellEnvironment) async -> PythonTerminalOutput {
        guard let first = arguments.first else {
            return PythonTerminalOutput(stdout: Self.replBanner, stderr: "", exitCode: 0)
        }

        if first == "--version" || first == "-V" {
            return PythonTerminalOutput(stdout: Self.versionLine, stderr: "", exitCode: 0)
        }

        if first == "-c" {
            guard arguments.count >= 2 else {
                return PythonTerminalOutput(stdout: "", stderr: "python: argument expected for -c\n", exitCode: 2)
            }
            let command = arguments[1]
            let argv = ["-c"] + Array(arguments.dropFirst(2))
            let code = wrappedCommand(command, argv: argv)
            let result = await runtime.run(code, cellID: "terminal-python-\(UUID().uuidString)")
            return Self.output(from: result, includeResult: false)
        }

        guard !first.hasPrefix("-") else {
            return PythonTerminalOutput(stdout: "", stderr: "python: unsupported option \(first)\n", exitCode: 2)
        }
        guard let url = env.resolve(first) else {
            return PythonTerminalOutput(stdout: "", stderr: "python: \(first): outside the app sandbox\n", exitCode: 1)
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return PythonTerminalOutput(stdout: "", stderr: "python: can't open file '\(first)': No such file or directory\n", exitCode: 2)
        }
        guard let data = FileManager.default.contents(atPath: url.path),
              let source = String(data: data, encoding: .utf8) else {
            return PythonTerminalOutput(stdout: "", stderr: "python: can't read file '\(first)' as UTF-8\n", exitCode: 1)
        }

        let runID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let pyDir = "/lectra_shell/\(runID)"
        let pyPath = pyDir + "/" + sanitizedFileName(url.lastPathComponent)
        do {
            try await runtime.start()
        } catch {
            return PythonTerminalOutput(
                stdout: "",
                stderr: "python: couldn't start: \(error.localizedDescription)\n",
                exitCode: 1)
        }
        guard await runtime.writeFile(path: pyPath, base64: Data(source.utf8).base64EncodedString()) else {
            return PythonTerminalOutput(stdout: "", stderr: "python: couldn't stage \(first)\n", exitCode: 1)
        }

        let argv = [first] + Array(arguments.dropFirst())
        let code = wrappedFile(path: pyPath, argv: argv, pyDir: pyDir)
        let result = await runtime.run(code, cellID: "terminal-python-\(runID)")
        return Self.output(from: result, includeResult: false)
    }

    func runInteractive(_ code: String) async -> PyodideRunResult {
        await runtime.run(code, cellID: "terminal-repl-\(UUID().uuidString)")
    }

    func shutdown() {
        runtime.shutdown()
    }

    static func output(from result: PyodideRunResult, includeResult: Bool) -> PythonTerminalOutput {
        var stdout = result.stdout
        if includeResult, let value = result.result, !value.isEmpty {
            stdout += value + "\n"
        }

        var stderr = result.stderr
        if let error = result.error, !error.isEmpty {
            stderr += error.hasSuffix("\n") ? error : error + "\n"
        }
        return PythonTerminalOutput(stdout: stdout, stderr: stderr, exitCode: result.error == nil ? 0 : 1)
    }

    private func wrappedCommand(_ source: String, argv: [String]) -> String {
        """
        import os, sys
        sys.argv = \(Self.pythonListLiteral(argv))
        os.chdir("/")
        __lectra_source = \(Self.pythonLiteral(source))
        exec(compile(__lectra_source, "<string>", "exec"), globals())
        """
    }

    private func wrappedFile(path: String, argv: [String], pyDir: String) -> String {
        """
        import os, sys
        sys.argv = \(Self.pythonListLiteral(argv))
        os.chdir(\(Self.pythonLiteral(pyDir)))
        if \(Self.pythonLiteral(pyDir)) not in sys.path:
            sys.path.insert(0, \(Self.pythonLiteral(pyDir)))
        __file__ = \(Self.pythonLiteral(path))
        with open(__file__, "r", encoding="utf-8") as __lectra_file:
            __lectra_source = __lectra_file.read()
        exec(compile(__lectra_source, __file__, "exec"), globals())
        """
    }

    private func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let safe = String(scalars)
        return safe.isEmpty ? "script.py" : safe
    }

    private static func pythonListLiteral(_ values: [String]) -> String {
        "[" + values.map(pythonLiteral).joined(separator: ", ") + "]"
    }

    private static func pythonLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json.replacingOccurrences(of: "\\/", with: "/")
    }
}

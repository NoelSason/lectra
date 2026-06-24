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

//
//  ShellParser.swift
//  Lectra
//
//  Tokenizes and parses a command line into an AST. Supports quoting, escapes,
//  variable references, pipelines (|), redirections (> >> <), and list operators
//  (&& || ;). Expansion (variables / globbing) happens later, in ShellExpander.
//

import Foundation

// MARK: - Tokens

enum QuoteKind { case none, single, double }

struct WordPart {
    var text: String
    var quote: QuoteKind
}

/// A shell "word" is a run of adjacent parts with possibly different quoting,
/// e.g. abc"$x"'lit' is three parts. Quoting controls expansion + globbing.
struct WordToken {
    var parts: [WordPart]
    var raw: String { parts.map { $0.text }.joined() }
}

enum ShellToken: Equatable {
    case word(WordToken)
    case op(String) // one of: | || && ; > >> <
    static func == (l: ShellToken, r: ShellToken) -> Bool {
        switch (l, r) {
        case let (.op(a), .op(b)): return a == b
        case let (.word(a), .word(b)): return a.raw == b.raw
        default: return false
        }
    }
}

enum ShellParseError: LocalizedError {
    case unterminatedQuote
    case syntax(String)
    var errorDescription: String? {
        switch self {
        case .unterminatedQuote: return "syntax error: unterminated quote"
        case .syntax(let s): return "syntax error near `\(s)`"
        }
    }
}

// MARK: - Lexer

struct ShellLexer {
    static func tokenize(_ line: String) throws -> [ShellToken] {
        var tokens: [ShellToken] = []
        var parts: [WordPart] = []
        var current = ""
        var currentQuote: QuoteKind = .none
        var hasWord = false

        let chars = Array(line)
        var i = 0

        func flushPart() {
            if !current.isEmpty || currentQuote != .none {
                parts.append(WordPart(text: current, quote: currentQuote))
                current = ""
                currentQuote = .none
            }
        }
        func flushWord() {
            flushPart()
            if hasWord { tokens.append(.word(WordToken(parts: parts))) }
            parts = []
            hasWord = false
        }

        while i < chars.count {
            let c = chars[i]
            switch c {
            case " ", "\t":
                flushWord()
                i += 1
            case "'":
                // single quote: literal until next '
                flushPart()
                hasWord = true
                var lit = ""
                i += 1
                while i < chars.count && chars[i] != "'" { lit.append(chars[i]); i += 1 }
                if i >= chars.count { throw ShellParseError.unterminatedQuote }
                i += 1 // closing '
                parts.append(WordPart(text: lit, quote: .single))
            case "\"":
                flushPart()
                hasWord = true
                var lit = ""
                i += 1
                while i < chars.count && chars[i] != "\"" {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        let n = chars[i + 1]
                        if n == "\"" || n == "\\" || n == "$" || n == "`" { lit.append(n); i += 2; continue }
                    }
                    lit.append(chars[i]); i += 1
                }
                if i >= chars.count { throw ShellParseError.unterminatedQuote }
                i += 1 // closing "
                parts.append(WordPart(text: lit, quote: .double))
            case "\\":
                hasWord = true
                if i + 1 < chars.count { current.append(chars[i + 1]); i += 2 }
                else { i += 1 }
            case "|":
                flushWord()
                if i + 1 < chars.count && chars[i + 1] == "|" { tokens.append(.op("||")); i += 2 }
                else { tokens.append(.op("|")); i += 1 }
            case "&":
                flushWord()
                if i + 1 < chars.count && chars[i + 1] == "&" { tokens.append(.op("&&")); i += 2 }
                else { i += 1 } // background not supported; ignore single &
            case ";":
                flushWord()
                tokens.append(.op(";")); i += 1
            case ">":
                flushWord()
                if i + 1 < chars.count && chars[i + 1] == ">" { tokens.append(.op(">>")); i += 2 }
                else { tokens.append(.op(">")); i += 1 }
            case "<":
                flushWord()
                tokens.append(.op("<")); i += 1
            default:
                hasWord = true
                current.append(c)
                i += 1
            }
        }
        flushWord()
        return tokens
    }
}

// MARK: - AST

enum Redirect {
    case input(WordToken)
    case output(WordToken)
    case append(WordToken)
}

struct SimpleCommand {
    var argv: [WordToken]
    var redirects: [Redirect]
}

struct Pipeline {
    var commands: [SimpleCommand]
}

enum Connector { case semicolon, and, or, end }

struct ShellCommandLine {
    /// Each pipeline plus the connector that follows it.
    var items: [(Pipeline, Connector)]
}

// MARK: - Parser

struct ShellParser {
    static func parse(_ line: String) throws -> ShellCommandLine {
        let tokens = try ShellLexer.tokenize(line)
        var i = 0
        var items: [(Pipeline, Connector)] = []
        var commands: [SimpleCommand] = []
        var argv: [WordToken] = []
        var redirects: [Redirect] = []

        func flushCommand() throws {
            if argv.isEmpty && redirects.isEmpty { return }
            commands.append(SimpleCommand(argv: argv, redirects: redirects))
            argv = []; redirects = []
        }
        func flushPipeline(_ conn: Connector) throws {
            try flushCommand()
            if !commands.isEmpty { items.append((Pipeline(commands: commands), conn)) }
            commands = []
        }

        while i < tokens.count {
            switch tokens[i] {
            case .word(let w):
                argv.append(w); i += 1
            case .op(let o):
                switch o {
                case "|": try flushCommand(); i += 1
                case "&&": try flushPipeline(.and); i += 1
                case "||": try flushPipeline(.or); i += 1
                case ";": try flushPipeline(.semicolon); i += 1
                case ">", ">>", "<":
                    i += 1
                    guard i < tokens.count, case .word(let target) = tokens[i] else {
                        throw ShellParseError.syntax(o)
                    }
                    switch o {
                    case ">": redirects.append(.output(target))
                    case ">>": redirects.append(.append(target))
                    default: redirects.append(.input(target))
                    }
                    i += 1
                default: i += 1
                }
            }
        }
        try flushPipeline(.end)
        return ShellCommandLine(items: items)
    }
}

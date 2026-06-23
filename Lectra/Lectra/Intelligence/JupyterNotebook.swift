//
//  JupyterNotebook.swift
//  Lectra
//
//  The on-disk `.ipynb` representation (Jupyter nbformat v4). Lectra notebooks
//  are written and re-read through these `Codable` types, so a notebook created
//  on-device stays a valid Jupyter file that also opens in Jupyter, Colab, and
//  VS Code. A small `lectra` block in the metadata is the "built for Lectra"
//  fingerprint.
//
//  Decoding is deliberately lenient (string-or-array `source`, unknown keys
//  ignored, unparseable outputs skipped) so re-opening our own files always
//  succeeds even as the format evolves.
//

import Foundation

// MARK: - Notebook

struct JupyterNotebook: Codable {
    var cells: [JupyterCell]
    var metadata: NBMetadata
    var nbformat: Int
    var nbformat_minor: Int

    init(cells: [JupyterCell], metadata: NBMetadata) {
        self.cells = cells
        self.metadata = metadata
        self.nbformat = 4
        self.nbformat_minor = 5
    }

    // MARK: Encode / decode helpers

    /// Pretty-printed `.ipynb` JSON with stable key ordering.
    func encodeIPYNB() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    init(data: Data) throws {
        self = try JSONDecoder().decode(JupyterNotebook.self, from: data)
    }
}

// MARK: - Metadata

struct NBMetadata: Codable {
    var kernelspec: KernelSpec
    var language_info: LanguageInfo
    /// Lectra's own provenance block — ignored by other notebook tools.
    var lectra: LectraMeta?

    init(lectra: LectraMeta?) {
        self.kernelspec = .python3
        self.language_info = .python
        self.lectra = lectra
    }

    struct KernelSpec: Codable {
        var display_name: String
        var language: String
        var name: String
        static let python3 = KernelSpec(display_name: "Python 3", language: "python", name: "python3")
    }

    struct LanguageInfo: Codable {
        var name: String
        var version: String?
        static let python = LanguageInfo(name: "python", version: "3.12")
    }

    /// Provenance written by Lectra so a generated notebook is recognizable and
    /// can be re-opened with its original identity.
    struct LectraMeta: Codable {
        var version: Int
        var notebookID: String
        var title: String
        var sourceDocument: String?
        var generatedAt: String
    }
}

// MARK: - Cell

struct JupyterCell: Codable {
    var id: String
    var cell_type: String          // "markdown" | "code"
    var source: [String]
    var metadata: CellMetadata
    var outputs: [JupyterOutput]?
    var execution_count: Int?

    struct CellMetadata: Codable {}

    init(id: String,
         cellType: String,
         source: [String],
         outputs: [JupyterOutput]? = nil,
         executionCount: Int? = nil) {
        self.id = id
        self.cell_type = cellType
        self.source = source
        self.metadata = CellMetadata()
        self.outputs = cellType == "code" ? (outputs ?? []) : nil
        self.execution_count = executionCount
    }

    enum CodingKeys: String, CodingKey {
        case id, cell_type, source, metadata, outputs, execution_count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        cell_type = (try? c.decode(String.self, forKey: .cell_type)) ?? "code"
        source = (try? c.decode(StringOrArray.self, forKey: .source))?.lines ?? []
        metadata = CellMetadata()
        outputs = (try? c.decode(LossyArray<JupyterOutput>.self, forKey: .outputs))?.elements
        execution_count = try? c.decodeIfPresent(Int.self, forKey: .execution_count)
    }
}

// MARK: - Output

struct JupyterOutput: Codable {
    var output_type: String        // "stream" | "execute_result" | "error"
    var name: String?              // stream: "stdout" | "stderr"
    var text: [String]?            // stream text
    var data: OutputData?          // execute_result payload
    var execution_count: Int?
    var ename: String?             // error name
    var evalue: String?            // error value
    var traceback: [String]?       // error traceback lines

    struct OutputData: Codable {
        var textPlain: [String]?
        var imagePng: String?      // base64 (matplotlib, future)
        enum CodingKeys: String, CodingKey {
            case textPlain = "text/plain"
            case imagePng = "image/png"
        }
    }

    enum CodingKeys: String, CodingKey {
        case output_type, name, text, data, execution_count, ename, evalue, traceback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        output_type = try c.decode(String.self, forKey: .output_type)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        text = (try? c.decode(StringOrArray.self, forKey: .text))?.lines
        data = try? c.decodeIfPresent(OutputData.self, forKey: .data)
        execution_count = try? c.decodeIfPresent(Int.self, forKey: .execution_count)
        ename = try? c.decodeIfPresent(String.self, forKey: .ename)
        evalue = try? c.decodeIfPresent(String.self, forKey: .evalue)
        traceback = (try? c.decode(StringOrArray.self, forKey: .traceback))?.lines
    }

    init(output_type: String,
         name: String? = nil,
         text: [String]? = nil,
         data: OutputData? = nil,
         execution_count: Int? = nil,
         ename: String? = nil,
         evalue: String? = nil,
         traceback: [String]? = nil) {
        self.output_type = output_type
        self.name = name
        self.text = text
        self.data = data
        self.execution_count = execution_count
        self.ename = ename
        self.evalue = evalue
        self.traceback = traceback
    }

    // MARK: Builders

    static func stream(_ name: String, _ text: String) -> JupyterOutput {
        JupyterOutput(output_type: "stream", name: name, text: splitKeepingNewlines(text))
    }

    static func result(_ text: String, executionCount: Int) -> JupyterOutput {
        JupyterOutput(output_type: "execute_result",
                      data: OutputData(textPlain: splitKeepingNewlines(text), imagePng: nil),
                      execution_count: executionCount)
    }

    static func error(name: String, value: String, traceback: [String]) -> JupyterOutput {
        JupyterOutput(output_type: "error", ename: name, evalue: value, traceback: traceback)
    }
}

// MARK: - Lenient decoding helpers

/// The nbformat spec allows `source`/`text`/`traceback` to be either a single
/// string or an array of lines. We accept both and always store as lines.
private struct StringOrArray: Decodable {
    let lines: [String]
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            lines = JupyterOutput.splitKeepingNewlines(single)
        } else if let many = try? decoder.singleValueContainer().decode([String].self) {
            lines = many
        } else {
            lines = []
        }
    }
}

/// Decodes an array element-by-element, skipping entries that fail to parse so a
/// single unsupported output type can't break the whole notebook.
private struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(AnyJSON.self) // consume and skip
            }
        }
        elements = result
    }
    private struct AnyJSON: Decodable {}
}

extension JupyterOutput {
    /// Splits text into nbformat-style lines, keeping the trailing newline on
    /// each line as Jupyter does.
    static func splitKeepingNewlines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "\n" {
                lines.append(current)
                current = ""
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

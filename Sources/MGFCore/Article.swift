import Foundation

/// Articles are plain Markdown files, readable on GitHub as they are. The app understands a small
/// subset: `# title`, a lead paragraph, `## sections`, paragraphs, `- lists`, pipe tables,
/// `> [!NOTE]` / `> [!WARNING]` callouts and fenced blocks. Two fences have a meaning of their own:
/// ```sh with one line is a copyable command, ```bars holds `label | unit | before | after`.
public struct Article: Equatable {
    public enum Block: Equatable {
        case paragraph(String)
        case list([String])
        case table(head: [String], rows: [[String]])
        case bars(label: String, unit: String, before: Double, after: Double)
        case code(title: String, text: String)
        case command(String)
        case note(warning: Bool, text: String)
    }
    public struct Section: Equatable, Identifiable {
        public let id: Int
        public let title: String
        public var blocks: [Block]
    }

    public var title = ""
    public var lead = ""
    public var sections: [Section] = []

    public init(markdown: String) {
        let lines = markdown.components(separatedBy: "\n")
        var paragraph: [String] = [], list: [String] = [], table: [[String]] = [], note: (warning: Bool, text: [String])?
        var blocks: [Block] = []

        func cells(_ line: String) -> [String] {
            line.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !list.isEmpty { blocks.append(.list(list)); list = [] }
            if let head = table.first { blocks.append(.table(head: head, rows: Array(table.dropFirst()))); table = [] }
            if let n = note { blocks.append(.note(warning: n.warning, text: n.text.joined(separator: " "))); note = nil }
        }
        func close() {  // end of the lead or of a section
            flush()
            if sections.isEmpty {
                if case .paragraph(let text)? = blocks.first { lead = text }
            } else {
                sections[sections.count - 1].blocks = blocks
            }
            blocks = []
        }

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            i += 1
            if line.hasPrefix("```") {
                flush()
                let info = line.dropFirst(3).split(separator: " ", maxSplits: 1).map(String.init)
                var body: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { body.append(lines[i]); i += 1 }
                i += 1
                let parts = body.first.map(cells) ?? []
                if info.first == "bars", parts.count == 4, let before = Double(parts[2]), let after = Double(parts[3]) {
                    blocks.append(.bars(label: parts[0], unit: parts[1], before: before, after: after))
                } else if info.first == "sh", body.count == 1 {
                    blocks.append(.command(body[0]))
                } else {
                    blocks.append(.code(title: info.count > 1 ? info[1] : info.first ?? "", text: body.joined(separator: "\n")))
                }
            } else if line.hasPrefix("## ") {
                close()
                sections.append(Section(id: sections.count, title: String(line.dropFirst(3)), blocks: []))
            } else if line.hasPrefix("# ") {
                title = String(line.dropFirst(2))
            } else if line.hasPrefix(">") {
                let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("[!") { flush(); note = (text.hasPrefix("[!WARNING]"), []) }
                else if !text.isEmpty { note = (note?.warning ?? false, (note?.text ?? []) + [text]) }
            } else if line.hasPrefix("- ") {
                if !paragraph.isEmpty || note != nil { flush() }
                list.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("|") {
                if !paragraph.isEmpty || !list.isEmpty || note != nil { flush() }
                let row = cells(line)
                if !row.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { table.append(row) }  // skip |---|---|
            } else if line.isEmpty {
                flush()
            } else {
                if !list.isEmpty || !table.isEmpty || note != nil { flush() }
                paragraph.append(line)
            }
        }
        close()
    }
}

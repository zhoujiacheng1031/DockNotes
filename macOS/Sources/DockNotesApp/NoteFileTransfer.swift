import Foundation

enum NoteExportFormat: String, CaseIterable, Sendable {
    case markdown
    case text

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .text: "txt"
        }
    }
}

enum NoteFileTransferError: LocalizedError {
    case unsupportedFormat(String)
    case unreadableFile(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(name): "Unsupported note format: \(name)"
        case let .unreadableFile(name): "Could not read note file: \(name)"
        }
    }
}

enum NoteFileTransfer {
    static func export(
        _ notes: [DockNote],
        to directory: URL,
        format: NoteExportFormat
    ) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return try notes.map { note in
            let baseName = sanitizedFileName(note.title.isEmpty ? "Untitled" : note.title)
            let destination = uniqueDestination(
                in: directory,
                baseName: baseName,
                fileExtension: format.fileExtension
            )
            let contents = switch format {
            case .markdown: markdown(for: note)
            case .text: note.body
            }
            try contents.write(to: destination, atomically: true, encoding: .utf8)
            return destination
        }
    }

    static func importNote(from url: URL) throws -> DockNote {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw NoteFileTransferError.unreadableFile(url.lastPathComponent)
        }
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return note(fromMarkdown: contents, fallbackTitle: url.deletingPathExtension().lastPathComponent)
        case "txt":
            return synchronizedNote(
                title: url.deletingPathExtension().lastPathComponent,
                body: contents
            )
        default:
            throw NoteFileTransferError.unsupportedFormat(url.pathExtension)
        }
    }

    static func markdown(for note: DockNote) -> String {
        var lines = ["# \(note.title.isEmpty ? "Untitled" : note.title)", ""]
        lines.append(contentsOf: note.body
            .components(separatedBy: "\n")
            .map(markdownTaskLine))
        return lines.joined(separator: "\n")
    }

    static func note(fromMarkdown markdown: String, fallbackTitle: String) -> DockNote {
        var lines = markdown.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closingIndex = lines.dropFirst().firstIndex(where: {
               $0.trimmingCharacters(in: .whitespaces) == "---"
           }) {
            lines.removeSubrange(lines.startIndex...closingIndex)
        }

        var title = fallbackTitle
        if let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ")
        }) {
            let heading = lines[headingIndex].trimmingCharacters(in: .whitespaces)
            title = String(heading.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.remove(at: headingIndex)
            if lines.first?.isEmpty == true { lines.removeFirst() }
        }
        let body = lines.map(importedTaskLine).joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        return synchronizedNote(title: title, body: body)
    }

    private static func synchronizedNote(title: String, body: String) -> DockNote {
        var note = DockNote(title: title, body: body)
        note.tasks = ChecklistParser.synchronizedTasks(in: note)
        return note
    }

    private static func markdownTaskLine(_ line: String) -> String {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let content = String(line.dropFirst(leading.count))
        for (marker, markdownMarker) in [
            ("☐ ", "- [ ] "),
            ("□ ", "- [ ] "),
            ("☑ ", "- [x] "),
            ("✓ ", "- [x] ")
        ] where content.hasPrefix(marker) {
            return String(leading) + markdownMarker + String(content.dropFirst(marker.count))
        }
        return line
    }

    private static func importedTaskLine(_ line: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"^(\s*)[-*]\s+\[([ xX])\]\s?(.*)$"#
        ) else { return line }
        let source = line as NSString
        guard let match = expression.firstMatch(
            in: line,
            range: NSRange(location: 0, length: source.length)
        ) else { return line }
        let indentation = source.substring(with: match.range(at: 1))
        let checked = source.substring(with: match.range(at: 2)).lowercased() == "x"
        let text = source.substring(with: match.range(at: 3))
        return indentation + (checked ? "☑ " : "☐ ") + text
    }

    private static func sanitizedFileName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = title.components(separatedBy: invalid).joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Untitled" : String(sanitized.prefix(96))
    }

    private static func uniqueDestination(
        in directory: URL,
        baseName: String,
        fileExtension: String
    ) -> URL {
        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(fileExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(fileExtension)
            suffix += 1
        }
        return candidate
    }
}

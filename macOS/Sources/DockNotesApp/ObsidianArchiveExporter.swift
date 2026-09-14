import Foundation

enum ObsidianArchiveExporter {
    @discardableResult
    static func export(_ note: DockNote, to directory: URL) throws -> URL {
        let accessed = directory.startAccessingSecurityScopedResource()
        defer { if accessed { directory.stopAccessingSecurityScopedResource() } }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = safeFileName(note.title)
        let noteURL = availableURL(in: directory, baseName: baseName, noteID: note.id)
        let noteName = noteURL.deletingPathExtension().lastPathComponent
        let markdown = markdown(for: note)
        try Data(markdown.utf8).write(to: noteURL, options: .atomic)
        try updateIndex(in: directory, noteName: noteName)
        return noteURL
    }

    static func safeFileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>[]#^")
        let components = title.components(separatedBy: forbidden)
        let cleaned = components.joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? "Untitled Note" : String(cleaned.prefix(120))
    }

    static func markdown(for note: DockNote) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "---",
            "docknotes-id: \(note.id.uuidString)",
            "modified: \(formatter.string(from: note.modifiedAt))",
            "archived: true"
        ]
        if let dueDate = note.dueDate { lines.append("due: \(formatter.string(from: dueDate))") }
        lines += [
            "tags:",
            "  - docknotes",
            "  - archived",
            "---",
            "",
            "# \(note.title.isEmpty ? "Untitled Note" : note.title)",
            "",
            note.body,
            "",
            "[[DockNotes Archive Index]]",
            ""
        ]
        return lines.joined(separator: "\n")
    }

    private static func availableURL(in directory: URL, baseName: String, noteID: UUID) -> URL {
        let primary = directory.appendingPathComponent(baseName).appendingPathExtension("md")
        guard FileManager.default.fileExists(atPath: primary.path) else { return primary }
        if let existing = try? String(contentsOf: primary, encoding: .utf8),
           existing.contains("docknotes-id: \(noteID.uuidString)") {
            return primary
        }
        return directory
            .appendingPathComponent("\(baseName) - \(noteID.uuidString.prefix(8))")
            .appendingPathExtension("md")
    }

    private static func updateIndex(in directory: URL, noteName: String) throws {
        let indexURL = directory.appendingPathComponent("DockNotes Archive Index.md")
        let link = "- [[\(noteName)]]"
        var contents = (try? String(contentsOf: indexURL, encoding: .utf8))
            ?? "# DockNotes Archive\n\n"
        if !contents.split(separator: "\n").contains(Substring(link)) {
            if !contents.hasSuffix("\n") { contents += "\n" }
            contents += "\(link)\n"
            try Data(contents.utf8).write(to: indexURL, options: .atomic)
        }
    }
}

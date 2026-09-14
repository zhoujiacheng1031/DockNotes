import Foundation

struct OrderedListEditResult: Equatable {
    let text: String
    let selectedRange: NSRange
}

enum OrderedListEditing {
    static func insertingReturn(in text: String, selectedRange: NSRange) -> OrderedListEditResult {
        let source = text as NSString
        guard selectedRange.location <= source.length,
              NSMaxRange(selectedRange) <= source.length else {
            return OrderedListEditResult(text: text, selectedRange: selectedRange)
        }

        let lineRange = source.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let marker = marker(in: line) else {
            return insertingPlainReturn(in: text, selectedRange: selectedRange)
        }

        let insertedMarker = "\n\(marker.indent)\(marker.number + 1)\(marker.delimiter)\(marker.spacing)"
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: selectedRange, with: insertedMarker)
        let cursor = selectedRange.location + (insertedMarker as NSString).length
        renumberFollowingLines(
            in: mutable,
            after: cursor,
            startingAt: marker.number + 2,
            indent: marker.indent,
            delimiter: marker.delimiter,
            spacing: marker.spacing
        )
        return OrderedListEditResult(
            text: mutable as String,
            selectedRange: NSRange(location: cursor, length: 0)
        )
    }

    private struct Marker {
        let indent: String
        let number: Int
        let delimiter: String
        let spacing: String
        let numberRange: NSRange
    }

    private static let markerExpression = try! NSRegularExpression(
        pattern: #"^(\s*)(\d+)([.)、])([ \t]+)(.*)$"#
    )

    private static func marker(in line: String) -> Marker? {
        let value = line as NSString
        guard let match = markerExpression.firstMatch(in: line, range: NSRange(location: 0, length: value.length)),
              match.numberOfRanges == 6,
              let number = Int(value.substring(with: match.range(at: 2))) else { return nil }
        return Marker(
            indent: value.substring(with: match.range(at: 1)),
            number: number,
            delimiter: value.substring(with: match.range(at: 3)),
            spacing: value.substring(with: match.range(at: 4)),
            numberRange: match.range(at: 2)
        )
    }

    private static func insertingPlainReturn(in text: String, selectedRange: NSRange) -> OrderedListEditResult {
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: selectedRange, with: "\n")
        return OrderedListEditResult(text: mutable as String, selectedRange: NSRange(location: selectedRange.location + 1, length: 0))
    }

    private static func renumberFollowingLines(
        in text: NSMutableString,
        after cursor: Int,
        startingAt firstNumber: Int,
        indent: String,
        delimiter: String,
        spacing: String
    ) {
        let insertedLineRange = text.lineRange(for: NSRange(location: min(cursor, text.length), length: 0))
        var offset = NSMaxRange(insertedLineRange)
        var expected = firstNumber

        while offset < text.length {
            let range = text.lineRange(for: NSRange(location: offset, length: 0))
            let line = text.substring(with: range).trimmingCharacters(in: .newlines)
            guard let found = marker(in: line),
                  found.indent == indent,
                  found.delimiter == delimiter else { break }

            let replacement = "\(expected)"
            let absoluteNumberRange = NSRange(location: range.location + found.numberRange.location, length: found.numberRange.length)
            text.replaceCharacters(in: absoluteNumberRange, with: replacement)
            let delta = (replacement as NSString).length - absoluteNumberRange.length
            offset = NSMaxRange(range) + delta
            expected += 1
        }
    }
}

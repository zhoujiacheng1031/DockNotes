import Foundation

enum ColorInput {
    static func hex(red: String, green: String, blue: String) -> String? {
        guard let red = component(red), let green = component(green), let blue = component(blue) else {
            return nil
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func normalizedHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, UInt32(digits, radix: 16) != nil else { return nil }
        return "#" + digits.uppercased()
    }

    static func components(from hex: String) -> (red: Int, green: Int, blue: Int) {
        let normalized = normalizedHex(hex) ?? "#000000"
        let digits = normalized.dropFirst()
        let value = UInt32(digits, radix: 16) ?? 0
        return (
            Int((value >> 16) & 0xFF),
            Int((value >> 8) & 0xFF),
            Int(value & 0xFF)
        )
    }

    private static func component(_ value: String) -> Int? {
        guard let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...255).contains(number) else { return nil }
        return number
    }
}

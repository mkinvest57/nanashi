import Foundation

/// Parses numeric UI entries without changing their units or the caller's validation bounds.
enum DecimalEntryParser {
    /// Keeps finite Swift `Double` literals, including scientific and hexadecimal notation.
    /// One comma can stand for the decimal point in a base-ten entry; grouping is never inferred.
    static func parse(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let value = Double(text) {
            return value.isFinite ? value : nil
        }

        // A mixed/grouped separator or hexadecimal comma is not a decimal-keypad entry.
        guard text.filter({ $0 == "," }).count == 1,
              !text.contains("."), !text.lowercased().contains("x"),
              let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value.isFinite else { return nil }
        return value
    }
}

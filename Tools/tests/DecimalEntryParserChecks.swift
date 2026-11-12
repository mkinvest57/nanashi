import Foundation

// Standalone UI-parser checks, independent of the app, storage and BLE targets:
// swiftc -swift-version 5 Strand/Screens/DecimalEntryParser.swift \
//   Tools/tests/DecimalEntryParserChecks.swift -o /tmp/decimal-entry-checks && /tmp/decimal-entry-checks
@main
struct DecimalEntryParserChecks {
    static func main() {
        let valid: [(String, Double)] = [
            ("0", 0), ("-0", -0.0), ("+42", 42), ("00042", 42),
            ("13.50", 13.5), ("13,50", 13.5), ("3,5", 3.5),
            (".5", 0.5), (",5", 0.5), ("1.", 1), ("1,", 1),
            ("+0,25", 0.25), ("-0.25", -0.25), ("-12,75", -12.75),
            (" \t7,5\n", 7.5), ("\u{00a0}7,5\u{00a0}", 7.5),
            ("1,234", 1.234), ("1.234", 1.234),
            ("1e3", 1000), ("1.5e-2", 0.015), ("1,5e-2", 0.015),
            ("-2,5E+2", -250), ("1.e3", 1000), ("1e-400", 0),
            ("0x10", 16), ("0x1p2", 4), ("0x1.fp-2", 0.484375),
            ("+0xA", 10), ("-0x.8p1", -1)
        ]
        let invalid = [
            "", " \t\n", ".", ",", "+", "-", "+,", "--1", "+-1",
            "NaN", "nan", "Inf", "-Inf", "+Infinity", "infinity",
            "1e309", "-1e309", "1,5e309", "0x1p1024",
            "1e", "1e+", "1e-", "1e1,5", "1ee3",
            "1,234.5", "1.234,5", "1,234,567", "1.234.567", "1_000",
            "1 234", "1\u{202f}234,5", "1\u{00a0}234,5",
            "3.5kg", "3,5kg", "1\n2", "12/3", "0x1,fp2", "١٫٥",
            String(repeating: "9", count: 400)
        ]

        var checked = 0
        for (text, expected) in valid {
            guard let actual = DecimalEntryParser.parse(text), actual == expected else {
                fatalError("Expected \(expected) for \(String(reflecting: text)); got \(String(describing: DecimalEntryParser.parse(text)))")
            }
            if expected == 0 {
                precondition(actual.sign == expected.sign, "Zero sign changed for \(text)")
            }
            checked += 1
        }
        for text in invalid {
            precondition(DecimalEntryParser.parse(text) == nil,
                         "Unexpected numeric entry: \(String(reflecting: text))")
            checked += 1
        }
        print("DecimalEntryParser: \(checked) standalone checks passed")
    }
}

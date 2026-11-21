import Foundation

struct DeviceCode: Hashable {
    let value: String

    static let pattern = #"^[A-Z0-9]{4}-?[A-Z0-9]{4,5}$"#

    private static let extractionPattern =
        #"(?<![A-Z0-9])[A-Z0-9]{4}[^A-Z0-9\r\n]{0,3}[A-Z0-9]{4,5}(?![A-Z0-9])"#

    static func normalize(_ raw: String) -> String {
        let characters = raw
            .uppercased()
            .unicodeScalars
            .filter { scalar in
                let value = scalar.value
                return (65...90).contains(value) || (48...57).contains(value)
            }
            .map(String.init)

        guard characters.count > 4 else { return characters.joined() }
        return characters.prefix(4).joined() + "-" + characters.dropFirst(4).joined()
    }

    static func parse(_ raw: String) -> DeviceCode? {
        let normalized = normalize(raw)
        guard normalized.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return DeviceCode(value: normalized)
    }

    static func extract(from text: String) -> DeviceCode? {
        if let code = parse(text) { return code }

        guard let expression = try? NSRegularExpression(
            pattern: extractionPattern,
            options: [.caseInsensitive]
        ) else { return nil }

        let fullRange = NSRange(text.startIndex..., in: text)
        for match in expression.matches(in: text, range: fullRange).reversed() {
            guard let range = Range(match.range, in: text),
                  let code = parse(String(text[range])) else { continue }
            return code
        }
        return nil
    }
}

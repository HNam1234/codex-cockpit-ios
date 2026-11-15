import Foundation

enum MailTextSanitizer {
    static let maximumLength = 50_000

    static func plainText(text: String?, html: [String]) -> String {
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return capped(text)
        }

        var value = html.joined(separator: "\n")
        value = replacing(
            pattern: #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#,
            in: value,
            with: ""
        )
        value = replacing(
            pattern: #"(?i)<\s*br\s*/?\s*>|<\s*/\s*(p|div|li|tr|h[1-6])\s*>"#,
            in: value,
            with: "\n"
        )
        value = replacing(pattern: #"(?s)<[^>]*>"#, in: value, with: "")
        value = decodeEntities(value)
        value = replacing(pattern: #"[\t\u00A0 ]+"#, in: value, with: " ")

        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return capped(lines.joined(separator: "\n"))
    }

    private static func capped(_ value: String) -> String {
        String(value.prefix(maximumLength))
    }

    private static func replacing(pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }

    private static func decodeEntities(_ value: String) -> String {
        var result = value
        let named = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]
        for (entity, decoded) in named {
            result = result.replacingOccurrences(of: entity, with: decoded, options: .caseInsensitive)
        }

        guard let expression = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) else {
            return result
        }
        let matches = expression.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        )
        for match in matches.reversed() {
            guard let entityRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result) else { continue }
            let raw = String(result[valueRange])
            let number = raw.lowercased().hasPrefix("x")
                ? UInt32(String(raw.dropFirst()), radix: 16)
                : UInt32(raw, radix: 10)
            guard let number, let scalar = UnicodeScalar(number) else { continue }
            result.replaceSubrange(entityRange, with: String(scalar))
        }
        return result
    }
}

enum VerificationCodeExtractor {
    private struct Candidate {
        let value: String
        let score: Int
        let location: Int
    }

    static func codes(subject: String, body: String) -> [String] {
        let safeSubject = MailTextSanitizer.plainText(text: subject, html: [])
        let safeBody = MailTextSanitizer.plainText(text: body, html: [])
        let original = safeSubject + "\n" + safeBody
        let cleaned = removingNoise(from: original)
        guard let expression = try? NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9])([A-Za-z0-9]{4,8})(?![A-Za-z0-9])"#
        ) else { return [] }

        let fullRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        let labels = labelLocations(in: cleaned)
        var bestByValue: [String: Candidate] = [:]

        for match in expression.matches(in: cleaned, range: fullRange) {
            guard let range = Range(match.range(at: 1), in: cleaned) else { continue }
            let raw = String(cleaned[range])
            guard raw.contains(where: { $0.isNumber }) else { continue }
            let normalized = raw.uppercased()
            let location = match.range(at: 1).location
            let distance = labels
                .filter { $0 <= location }
                .map { location - $0 }
                .filter { $0 <= 36 }
                .min()
            var score = distance.map { 100 - $0 } ?? 0
            if location < (safeSubject as NSString).length { score += 20 }
            let candidate = Candidate(value: normalized, score: score, location: location)
            if let existing = bestByValue[normalized],
               existing.score > candidate.score ||
                (existing.score == candidate.score && existing.location < candidate.location) {
                continue
            }
            bestByValue[normalized] = candidate
        }

        return bestByValue.values
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.location < rhs.location : lhs.score > rhs.score
            }
            .prefix(5)
            .map(\.value)
    }

    private static func labelLocations(in value: String) -> [Int] {
        let labels = ["verification code", "security code", "one-time code", "otp", "code", "mã xác minh", "mã bảo mật", "mã"]
        let lowercased = value.lowercased() as NSString
        return labels.flatMap { label -> [Int] in
            var locations: [Int] = []
            var searchRange = NSRange(location: 0, length: lowercased.length)
            while searchRange.length > 0 {
                let found = lowercased.range(of: label, options: [], range: searchRange)
                guard found.location != NSNotFound else { break }
                locations.append(found.location + found.length)
                let next = found.location + found.length
                searchRange = NSRange(location: next, length: lowercased.length - next)
            }
            return locations
        }
    }

    private static func removingNoise(from value: String) -> String {
        let patterns = [
            #"\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b"#,
            #"[$€£₫]\s*\d+(?:[.,]\d+)*"#,
            #"\b(?:\d[\s().-]*){9,15}\b"#,
            #"\b[A-Za-z0-9]{9,}\b"#
        ]
        return patterns.reduce(value) { partial, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return partial }
            let range = NSRange(partial.startIndex..<partial.endIndex, in: partial)
            return expression.stringByReplacingMatches(in: partial, range: range, withTemplate: " ")
        }
    }
}

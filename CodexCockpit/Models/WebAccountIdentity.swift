import Foundation

struct WebAccountIdentity: Codable, Equatable {
    let name: String?
    let email: String?

    init?(name: String?, email: String?) {
        let cleanName = Self.cleaned(name)
        let cleanEmail = Self.cleaned(email)
        guard cleanName != nil || cleanEmail != nil else { return nil }
        self.name = cleanName
        self.email = cleanEmail
    }

    init?(javaScriptValue: Any?) {
        guard let payload = javaScriptValue as? [String: Any] else { return nil }
        self.init(
            name: payload["name"] as? String,
            email: payload["email"] as? String
        )
    }

    init?(sessionJavaScriptValue: Any?) {
        guard let session = sessionJavaScriptValue as? [String: Any],
              let user = session["user"] as? [String: Any] else { return nil }
        self.init(javaScriptValue: user)
    }

    var label: String {
        name ?? email ?? ""
    }

    var normalizedEmail: String? {
        email?.lowercased()
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

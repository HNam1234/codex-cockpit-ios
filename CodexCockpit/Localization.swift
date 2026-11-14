import Foundation

enum L10n {
    static func text(_ key: String, language: String? = nil) -> String {
        bundle(for: language).localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg..., language: String? = nil) -> String {
        let format = text(key, language: language)
        let locale = language.map(Locale.init(identifier:)) ?? .current
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static func bundle(for language: String?) -> Bundle {
        guard let language,
              let url = Bundle.main.url(forResource: language, withExtension: "lproj"),
              let localizedBundle = Bundle(url: url) else { return .main }
        return localizedBundle
    }
}

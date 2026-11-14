import CryptoKit
import Foundation

struct TiboAlertContent: Equatable {
    let identifier: String
    let title: String
    let body: String
}

struct TiboAlertHistory: Codable, Equatable {
    private(set) var identifiers: [String]
    let limit: Int

    init(limit: Int = 32) {
        identifiers = []
        self.limit = max(1, limit)
    }

    func contains(_ identifier: String) -> Bool {
        identifiers.contains(identifier)
    }

    mutating func insert(_ identifier: String) -> Bool {
        guard !contains(identifier) else { return false }
        identifiers.append(identifier)
        if identifiers.count > limit {
            identifiers.removeFirst(identifiers.count - limit)
        }
        return true
    }
}

enum TiboAlertPolicy {
    static func content(for signal: TiboResetStatus) -> TiboAlertContent? {
        guard !signal.stale else { return nil }

        let title: String
        switch signal.status {
        case "likely":
            title = L10n.text("tibo.notification.likely")
        case "yes":
            title = L10n.text("tibo.notification.confirmed")
        default:
            return nil
        }

        let body = signal.hintPost?.text
            ?? signal.latestPost?.text
            ?? signal.message
        let eventID = signal.hintPost?.id
            ?? signal.latestPost?.id
            ?? fallbackEventID(for: signal)

        return TiboAlertContent(
            identifier: "tibo.\(signal.status).\(eventID)",
            title: title,
            body: body
        )
    }

    private static func fallbackEventID(for signal: TiboResetStatus) -> String {
        let seed = [
            signal.kind,
            signal.latestAt,
            signal.pendingAt,
            signal.message
        ]
        .compactMap { $0 }
        .joined(separator: "|")
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

extension TiboResetStatus {
    var presentationStatus: String {
        if stale { return L10n.text("tibo.status.stale") }
        switch status {
        case "yes": return L10n.text("tibo.status.confirmed")
        case "likely": return L10n.text("tibo.status.likely")
        case "no": return L10n.text("tibo.status.none")
        default: return L10n.text("tibo.status.watching")
        }
    }

    var presentationIcon: String {
        if stale { return "clock.badge.exclamationmark" }
        switch status {
        case "yes": return "checkmark.seal.fill"
        case "likely": return "sparkles"
        case "no": return "eye.fill"
        default: return "waveform.path.ecg"
        }
    }

    var presentationURL: URL? {
        let value = hintPost?.url ?? latestPost?.url
        return value.flatMap(URL.init(string:))
    }

    var presentationSource: String {
        let trimmedXSource = xSource?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedXSource?.isEmpty == false ? trimmedXSource! : source
    }

    var presentationBasis: String {
        L10n.text(probabilityBasis == nil ? "tibo.basis.history" : "tibo.basis.history_x")
    }
}

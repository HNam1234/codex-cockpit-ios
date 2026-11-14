import CryptoKit
import Foundation

struct TiboAlertContent: Equatable {
    let identifier: String
    let title: String
    let body: String
}

enum TiboAlertPolicy {
    static func content(for signal: TiboResetStatus) -> TiboAlertContent? {
        guard !signal.stale else { return nil }

        let title: String
        switch signal.status {
        case "likely":
            title = "TIBO: Có tín hiệu reset hôm nay"
        case "yes":
            title = "TIBO: Reset đã được xác nhận"
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

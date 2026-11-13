import Foundation

/// Presentation only: reads the existing layout service, never selects an input source.
struct LayoutPresentationSnapshot: Equatable {
    struct Source: Equatable {
        let id: String
        let name: String
        let language: String?
        var badge: String { LayoutPresentationSnapshot.badge(language: language, id: id) }
    }
    let selectedID: String
    let sources: [Source]
    let language: String?
    var badge: String { Self.badge(language: language, id: selectedID) }
    static func badge(language: String?, id: String) -> String {
        guard let language, !language.isEmpty else {
            let id = id.lowercased()
            return id.contains("russian") || id.hasSuffix(".ru") ? "AЯ" : "AZ"
        }
        let raw = String(language.lowercased().prefix(2))
        let code = raw == "iw" ? "he" : raw
        let labels = ["ru": "AЯ", "en": "AZ", "uk": "AУ", "be": "AБ",
                      "de": "AD", "fr": "AF", "es": "AE", "it": "AI",
                      "pt": "AP", "pl": "AP", "ja": "あ", "zh": "拼", "ko": "한",
                      "he": "עב", "el": "ΕΛ", "bg": "AБ", "hy": "ՀԱ", "ka": "ქა"]
        return labels[code] ?? code.uppercased()
    }
}

@MainActor final class LayoutPresentationState {
    private let read: () -> LayoutPresentationSnapshot
    private(set) var snapshot: LayoutPresentationSnapshot
    init(read: @escaping () -> LayoutPresentationSnapshot) {
        self.read = read; snapshot = read()
    }
    @discardableResult func refresh() -> Bool {
        let next = read()
        guard next != snapshot else { return false }
        snapshot = next
        return true
    }
}

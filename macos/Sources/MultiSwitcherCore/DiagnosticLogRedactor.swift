import Foundation

/// Redacts local identifiers before a user chooses to share a diagnostic log.
/// This is a defense-in-depth filter; the UI still shows the complete sanitized
/// report before handing it to a mail or sharing service.
public enum DiagnosticLogRedactor {
    public static func redact(_ text: String, homeDirectory: String) -> String {
        var result = text
        if !homeDirectory.isEmpty {
            result = result.replacingOccurrences(of: homeDirectory, with: "~")
        }

        result = replacing(
            pattern: #"(?i)\b(password|passwd|token|authorization|clipboard|query|typed[_ ]?text|word|text)\s*[:=]\s*[^,\r\n]+"#,
            in: result,
            template: "$1=[redacted]"
        )
        result = replacing(
            pattern: #"\b(?:[A-Za-z][A-Za-z0-9_-]*\.){2,}[A-Za-z][A-Za-z0-9_-]*\b"#,
            in: result,
            template: "[app-id]"
        )
        return result
    }

    private static func replacing(pattern: String, in text: String, template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

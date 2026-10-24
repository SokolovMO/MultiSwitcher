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
            pattern: #"(?i)\b(password|passwd|token|authorization|clipboard|query|typed[_ ]?text|word|text|url|email|address)\s*[:=]\s*[^,\r\n]+"#,
            in: result,
            template: "$1=[redacted]"
        )
        result = replacing(
            pattern: #"(?i)\b(?:https?|file)://[^\s<>\"']+"#,
            in: result,
            template: "[url]"
        )
        result = replacing(
            pattern: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            in: result,
            template: "[email]"
        )
        result = replacing(
            pattern: #"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{16,}|sk-[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9._~+/-]+=*)"#,
            in: result,
            template: "[credential]"
        )
        result = replacing(
            pattern: #"(?i)(?<![0-9a-f:])(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(?![0-9a-f:])"#,
            in: result,
            template: "[ip]"
        )
        result = replacing(
            pattern: #"(?i)(?<![A-Za-z0-9])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9])"#,
            in: result,
            template: "[ip]"
        )
        result = replacing(
            pattern: #"(?<![A-Za-z0-9])/(?:Users|private/var/folders|tmp)/[^\s,;]+"#,
            in: result,
            template: "[local-path]"
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

import AppKit
import Darwin

@main
@MainActor
enum MultiSwitcherApplication {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            let bundle = Bundle.main
            guard bundle.bundleIdentifier == "com.multiswitcher.app",
                  let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  build.range(of: "^[1-9][0-9]*$", options: .regularExpression) != nil,
                  UpdateChecker.isConfigured, let resources = bundle.resourceURL else {
                fputs("SELFTEST FAILED: bundle or updater configuration\n", stderr)
                Darwin.exit(1)
            }
            for language in ["en", "ru"] {
                let path = resources.appendingPathComponent("Lexicons/\(language).words")
                guard let words = try? String(contentsOf: path, encoding: .utf8),
                      words.split(separator: "\n").count > 1000 else {
                    fputs("SELFTEST FAILED: bundled dictionaries\n", stderr)
                    Darwin.exit(1)
                }
            }
            print("SELFTEST OK: MultiSwitcher \(build), dictionaries and updater")
            Darwin.exit(0)
        }
        L10n.configureFrameworkLocalization()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

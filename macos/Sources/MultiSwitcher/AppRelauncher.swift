import AppKit
import Foundation

/// Единая точка перезапуска приложения.
/// Shared helper for relaunching the local app bundle.
@MainActor
enum AppRelauncher {
    /// Перезапускает приложение: открывает бандл заново и завершает текущий процесс.
    static func relaunch(bundlePath: String = Bundle.main.bundlePath, arguments: [String] = []) {
        // Путь передаём ПОЗИЦИОННЫМ аргументом ($1), а НЕ интерполяцией в команду — иначе
        // путь с кавычкой/;/`$()` привёл бы к shell-инъекции. sh не пере-парсит $1.
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; app_path=$1; shift; open -n \"$app_path\" --args \"$@\"", "multiswitcher-relaunch", bundlePath] + arguments
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}

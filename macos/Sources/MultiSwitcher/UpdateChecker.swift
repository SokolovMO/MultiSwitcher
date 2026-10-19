import AppKit
import Foundation

/// Проверяет наличие обновлений через GitHub
@MainActor
enum UpdateChecker {
    private static let lastCheckKey = "com.multiswitcher.lastUpdateCheck"
    private static let autoCheckKey = "com.multiswitcher.checkUpdatesEnabled"
    private static let skippedVersionKey = "com.multiswitcher.skippedVersion"
    private static let updateDefaults = UserDefaults.standard

    static var isConfigured: Bool {
        guard let feed = configuredURL("MSUpdateFeedURL"),
              let releaseBase = configuredURL("MSReleaseBaseURL"),
              let teamID = Bundle.main.object(forInfoDictionaryKey: "MSDeveloperTeamID") as? String,
              teamID.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else { return false }
        return feed.path.hasSuffix("/releases/latest/download/version.json")
            && releaseBase.path.hasSuffix("/releases/download")
    }

    private static func configuredURL(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: raw), url.scheme == "https", url.host == "github.com" else { return nil }
        return url
    }

    private static let updateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 600
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Структура JSON версии
    private struct VersionInfo: Decodable {
        let version: String
        let url: String?
        let notes: String?
        let sha256: String?
    }

    /// Проверить при запуске (с задержкой 5 сек, не чаще раза в сутки).
    /// Отключается через настройку `checkUpdatesEnabled`. Ручная проверка (`checkNow`) работает всегда.
    static func checkOnLaunch() {
        guard isConfigured, shouldAutoCheck() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Task { await check(silent: true) }
        }
    }

    /// Периодическая тихая авто-проверка, пока приложение работает (из таймера AppDelegate).
    /// Тот же троттл (не чаще раза в сутки) и та же настройка `checkUpdatesEnabled`, что и на старте,
    /// поэтому долго-живущий инстанс тоже ловит новые версии, а не только при перезапуске.
    static func checkPeriodic() {
        guard isConfigured, shouldAutoCheck() else { return }
        Task { await check(silent: true) }
    }

    /// Автоматическая проверка выполняется не чаще раза в сутки и отключается в настройках.
    private static func shouldAutoCheck() -> Bool {
        guard updateDefaults.object(forKey: autoCheckKey) as? Bool ?? true else { return false }
        if let lastCheck = updateDefaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < 86_400 { return false }
        return true
    }

    /// Проверить вручную (всегда показывает результат)
    static func checkNow() {
        Task { await check(silent: false) }
    }

    private static func check(silent: Bool) async {
        guard let info = await fetchApplicableInfo() else {
            // The stable feed could not be reached (for example, a network error).
            rslog("UpdateChecker: stable feed unreachable")
            if !silent { await showErrorAlert() }
            return
        }

        updateDefaults.set(Date(), forKey: lastCheckKey)

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        if compareVersions(info.version, isNewerThan: currentVersion) {
            if updateDefaults.string(forKey: skippedVersionKey) == info.version && silent {
                return // Пользователь пропустил эту версию
            }
            await showUpdateAlert(info: info)
        } else if !silent {
            await showUpToDateAlert()
        }
    }

    /// Загружает только HTTPS-фид, зашитый в подписанное приложение.
    private static func fetchApplicableInfo() async -> VersionInfo? {
        guard isConfigured, let feed = configuredURL("MSUpdateFeedURL") else { return nil }
        return await fetchInfo(from: feed.absoluteString)
    }

    /// Скачивает и декодирует VersionInfo из стабильного фида.
    private static func fetchInfo(from urlString: String) async -> VersionInfo? {
        guard let url = URL(string: urlString), url.scheme == "https", url.host == "github.com" else { return nil }
        do {
            let (data, response) = try await updateSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 128 * 1024 else { return nil }
            let info = try JSONDecoder().decode(VersionInfo.self, from: data)
            guard info.version.range(of: "^[0-9]+(\\.[0-9]+){1,3}$", options: .regularExpression) != nil,
                  let sha = info.sha256,
                  sha.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { return nil }
            return info
        } catch {
            rslog("UpdateChecker fetch \(urlString): \(error)")
            return nil
        }
    }

    private static func showUpdateAlert(info: VersionInfo) async {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.updateAvailable
        alert.informativeText = "\(L10n.updateNewVersion) \(info.version)\n\(info.notes ?? "")"
        alert.addButton(withTitle: L10n.updateInstallRestart)  // 1st
        alert.addButton(withTitle: L10n.updateDownload)         // 2nd
        alert.addButton(withTitle: L10n.updateSkip)             // 3rd
        alert.addButton(withTitle: L10n.updateLater)            // 4th

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            await installAndRestart(info: info)
        case .alertSecondButtonReturn:
            openReleasePage()
        case .alertThirdButtonReturn:
            updateDefaults.set(info.version, forKey: skippedVersionKey)
        default:
            break
        }
    }

    // MARK: - Install & Restart

    private static func installAndRestart(info: VersionInfo) async {
        let version = info.version

        // 0. Версия приходит из сети — не доверяем вслепую (попадёт в URL и в сравнение).
        //    Разрешаем необязательную одну строчную букву-суффикс для бет: «3.2.0a».
        //    Класс [0-9.a-z] исключает slash/пробел/метасимволы — безопасно для URL/тега.
        guard version.range(of: "^[0-9]+(\\.[0-9]+){1,3}[a-z]?$", options: .regularExpression) != nil else {
            rslog("Update: rejected malformed version '\(version)'")
            // Семантически это недоверие данным фида, а не «повреждённый файл»:
            // на этом этапе ничего ещё не скачивалось.
            await showInstallError(L10n.updateIntegrityFailed)
            return
        }

        // 0a. sha256 обязателен для установки на месте: молча подменять приложение
        //     keylogger-класса без проверки нельзя. Нет хэша — откат на загрузку
        //     в браузере, где работает Gatekeeper/нотаризация.
        guard let expectedSHA = info.sha256 else {
            rslog("Update: release manifest has no SHA-256")
            openReleasePage()
            return
        }

        guard let dmgURL = releaseDMGURL(version: version) else {
            await showInstallError(L10n.updateDownloadFailed)
            return
        }

        // Приватная temp-директория пользователя вместо общего /tmp (аудит: предсказуемый
        // путь в shared /tmp — окно для symlink-подмены между проверкой и установкой).
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MultiSwitcher-update-\(UUID().uuidString).dmg")
        let tmpPath = tmpURL.path

        // Download to a temporary file so a release DMG does not occupy the app's
        // memory in addition to the downloaded file on disk.
        rslog("Update: downloading \(dmgURL)")
        do {
            let (downloadedURL, response) = try await updateSession.download(from: dmgURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await showInstallError(L10n.updateDownloadFailed)
                return
            }
            try FileManager.default.moveItem(at: downloadedURL, to: tmpURL)
        } catch {
            rslog("Update: download failed — \(error)")
            await showInstallError(L10n.updateDownloadFailed)
            return
        }

        // Скачанный образ убираем на ЛЮБОМ выходе с ошибкой ниже (раньше ветки отказа
        // mount выходили до регистрации уборки и DMG протекал на диск). Путь успеха
        // до defer не доживает (terminate) — там уборка явная, перед relaunch.
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // 2. Проверить sha256 (обязательно)
        let actualSHA = sha256OfFile(at: tmpPath)
        guard actualSHA?.lowercased() == expectedSHA.lowercased() else {
            rslog("Update: sha256 mismatch expected=\(expectedSHA) actual=\(actualSHA ?? "nil")")
            try? FileManager.default.removeItem(at: tmpURL)
            // Битая загрузка — НЕ «проверка не пройдена» вообще: у части пользователей сеть
            // режет/искажает скачивание с CDN GitHub (assets-хост блокируется отдельно от
            // raw.githubusercontent). Говорим прямо и предлагаем браузер.
            await showDownloadCorruptedAlert()
            return
        }
        rslog("Update: sha256 verified")

        // Наследие ≤2.6.1: путь успеха не размонтировал том (terminate съедал defer),
        // и он висел по фиксированному пути до перезагрузки. Прибираем тихо.
        detachUpdateVolume(at: "/tmp/MultiSwitcher-update-mount")

        // 3. Смонтировать DMG (уникальный mountpoint: не пересекается с прошлой попыткой
        //    и не предсказуем заранее — в пару к приватному пути загрузки выше)
        let mountPoint = NSTemporaryDirectory() + "MultiSwitcher-update-mount-\(UUID().uuidString.prefix(8))"
        let mount = Process()
        mount.launchPath = "/usr/bin/hdiutil"
        mount.arguments = ["attach", tmpPath, "-nobrowse", "-readonly", "-mountpoint", mountPoint]
        mount.standardOutput = FileHandle.nullDevice
        mount.standardError = FileHandle.nullDevice
        do {
            try mount.run()
            mount.waitUntilExit()
            guard mount.terminationStatus == 0 else {
                rslog("Update: hdiutil attach failed with status \(mount.terminationStatus)")
                await showInstallError(L10n.updateInstallFailed)
                return
            }
        } catch {
            rslog("Update: hdiutil attach error — \(error)")
            await showInstallError(L10n.updateInstallFailed)
            return
        }

        defer { detachUpdateVolume(at: mountPoint) }   // ветки ошибок; успех чистится явно

        // 4. Найти .app в смонтированном томе
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: mountPoint),
              let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            rslog("Update: no .app found in mounted DMG")
            await showInstallError(L10n.updateInstallFailed)
            return
        }

        let sourceApp = URL(fileURLWithPath: mountPoint).appendingPathComponent(appName)
        let currentApp = URL(fileURLWithPath: Bundle.main.bundlePath)

        // 5. ПРОВЕРКА ПОДПИСИ: единственная реальная защита от подмены кода.
        //    sha256 защищает лишь от битой загрузки — если подменить и DMG, и хэш,
        //    спасает только пиннинг Developer ID нашей команды.
        guard verifyNotarizedSignature(at: sourceApp.path) else {
            rslog("Update: signature/notarization check FAILED — aborting")
            await showInstallError(L10n.updateIntegrityFailed)
            return
        }

        // 5a. Идентичность бандла: тот же bundle id и версия совпадает с заявленной.
        //     Info.plist читаем напрямую с диска: Bundle(url:) кэширует инстансы по пути
        //     на всю жизнь процесса — у долгоживущего menu-bar приложения повторная
        //     попытка обновления получила бы данные ПРОШЛОГО смонтированного образа
        //     и упала бы с ложным «версия не совпала».
        let plistURL = sourceApp.appendingPathComponent("Contents/Info.plist")
        let mountedInfo = (try? Data(contentsOf: plistURL)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any]
        }
        let mountedID = mountedInfo?["CFBundleIdentifier"] as? String
        let mountedVersion = mountedInfo?["CFBundleShortVersionString"] as? String
        guard mountedID == Bundle.main.bundleIdentifier else {
            rslog("Update: bundle id mismatch (\(mountedID ?? "nil"))")
            await showInstallError(L10n.updateIntegrityFailed)
            return
        }
        guard mountedVersion == version else {
            rslog("Update: bundle version mismatch — announced \(version), contains \(mountedVersion ?? "nil")")
            await showInstallError(L10n.updateIntegrityFailed)
            return
        }

        // 6. Скопировать .app с read-only тома DMG на тот же том, что и текущее
        //    приложение. replaceItemAt НЕ умеет переносить элемент напрямую с
        //    read-only тома DMG — именно это давало «Ошибку установки».
        let stagingDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MultiSwitcher-update-staging-\(UUID().uuidString)", isDirectory: true)
        try? fm.removeItem(at: stagingDir)
        let stagedApp = stagingDir.appendingPathComponent(appName)
        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            try fm.copyItem(at: sourceApp, to: stagedApp)
        } catch {
            rslog("Update: staging copy failed — \(error)")
            await showInstallError(error.localizedDescription)
            return
        }
        defer { try? fm.removeItem(at: stagingDir) }

        // 7. Атомарно заменить .app из staging-копии (на одном томе — работает)
        do {
            _ = try fm.replaceItemAt(currentApp, withItemAt: stagedApp)
            rslog("Update: app replaced successfully")
        } catch {
            rslog("Update: replace failed — \(error)")
            await showInstallError(error.localizedDescription)
            return
        }

        // 8. Явная уборка ПЕРЕД перезапуском: relaunch завершает процесс через
        //    terminate() → exit(), поэтому defer-блоки НЕ выполняются. Без этого том
        //    оставался смонтированным до перезагрузки, а следующая попытка обновления
        //    перезаписывала backing-файл занятого образа и падала на «Resource busy»
        //    (ревью-находка, воспроизведена).
        try? fm.removeItem(at: stagingDir)
        detachUpdateVolume(at: mountPoint)
        try? fm.removeItem(at: tmpURL)

        // 9. Перезапуск
        rslog("Update: restarting...")
        AppRelauncher.relaunch(bundlePath: currentApp.path)
    }

    private static func releaseDMGURL(version: String) -> URL? {
        guard isConfigured, let base = configuredURL("MSReleaseBaseURL") else { return nil }
        return base.appendingPathComponent("v\(version)")
            .appendingPathComponent("MultiSwitcher-\(version)-arm64.dmg")
    }

    private static func openReleasePage() {
        guard let url = configuredURL("MSReleasesURL") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func runTool(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            rslog("Update: \(path) failed — \(error.localizedDescription)")
            return false
        }
    }

    /// Тихо размонтирует том обновления. Вынесено из defer, потому что путь успеха
    /// завершает процесс до раскрутки стека — defer там не срабатывает.
    private static func detachUpdateVolume(at mountPoint: String) {
        let detach = Process()
        detach.launchPath = "/usr/bin/hdiutil"
        detach.arguments = ["detach", mountPoint, "-quiet"]
        detach.standardOutput = FileHandle.nullDevice
        detach.standardError = FileHandle.nullDevice
        try? detach.run()
        detach.waitUntilExit()
    }

    /// Проверяет, что бандл подписан Developer ID нашей команды и проходит строгую
    /// проверку целостности (codesign --verify с пиннингом Team ID).
    private static func verifyNotarizedSignature(at path: String) -> Bool {
        guard let teamID = Bundle.main.object(forInfoDictionaryKey: "MSDeveloperTeamID") as? String,
              teamID.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else { return false }
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        guard runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=\(requirement)", path]) else { return false }
        return runTool("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", path])
    }

    private static func sha256OfFile(at path: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.launchPath = "/usr/bin/shasum"
        process.arguments = ["-a", "256", path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            return output.split(separator: " ").first.map(String.init)
        } catch {
            return nil
        }
    }

    private static func showAlert(style: NSAlert.Style, title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func showInstallError(_ message: String) async {
        showAlert(style: .warning, title: L10n.updateInstallFailed, message: message)
    }

    /// Битая загрузка (sha256 не совпал): файл не тот, что публиковали. Чаще всего это
    /// сеть (обрыв/подмена на пути к CDN GitHub) — предлагаем скачать в браузере, там
    /// видна реальная сетевая ошибка, работают ретраи и Gatekeeper проверит DMG сам.
    private static func showDownloadCorruptedAlert() async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.updateInstallFailed
        alert.informativeText = L10n.updateDownloadCorrupted
        alert.addButton(withTitle: L10n.updateDownload)   // «Скачать» → страница релиза в браузере
        alert.addButton(withTitle: L10n.updateLater)
        // URL строим локально из константы, а НЕ из info.url: фид приходит по сети,
        // и остальной установщик ему сознательно не доверяет (ревью-находка).
        // Сайт, а не GitHub: скачивание чаще всего срывается как раз из-за недоступного GitHub.
        if alert.runModal() == .alertFirstButtonReturn {
            openReleasePage()
        }
    }

    private static func showUpToDateAlert() async {
        showAlert(style: .informational, title: L10n.updateUpToDate, message: L10n.updateLatestInstalled)
    }

    private static func showErrorAlert() async {
        showAlert(style: .warning, title: L10n.updateCheckFailed, message: L10n.updateCheckFailedDetail)
    }

    /// Строго ли v1 новее v2. Поддерживает пред-релизы: одна строчная буква-суффикс
    /// («3.2.0a») — это БЕТА, и она СТАРШЕ по числовому ядру, но МЛАДШЕ финала того же
    /// ядра. Порядок: 3.1.0 < 3.2.0a < 3.2.0b < 3.2.0 (финал). Так тестер на «3.2.0c»
    /// получит обновление до финального «3.2.0», когда тот выйдет.
    private static func compareVersions(_ v1: String, isNewerThan v2: String) -> Bool {
        semverCompare(v1, v2) == .orderedDescending
    }

    /// Разбирает версию на числовое ядро и необязательную букву-пред-релиз.
    private static func parseVersion(_ v: String) -> (core: [Int], pre: String) {
        var s = Substring(v)
        var pre = ""
        if let last = s.last, last.isLetter {          // «3.2.0a» → pre="a", ядро "3.2.0"
            pre = String(last).lowercased()
            s = s.dropLast()
        }
        let core = s.split(separator: ".").map { Int($0) ?? 0 }
        return (core, pre)
    }

    private static func semverCompare(_ a: String, _ b: String) -> ComparisonResult {
        let (ca, pa) = parseVersion(a)
        let (cb, pb) = parseVersion(b)
        for i in 0..<max(ca.count, cb.count) {
            let x = i < ca.count ? ca[i] : 0
            let y = i < cb.count ? cb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        // Ядра равны: финал (без буквы) старше любой беты; между бетами — по букве (a<b<c).
        if pa == pb { return .orderedSame }
        if pa.isEmpty { return .orderedDescending }    // a=финал, b=бета → a новее
        if pb.isEmpty { return .orderedAscending }     // a=бета, b=финал → b новее
        return pa < pb ? .orderedAscending : .orderedDescending
    }
}

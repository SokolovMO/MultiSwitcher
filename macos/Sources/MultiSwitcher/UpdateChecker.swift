#if !canImport(Sparkle)
import AppKit
import Foundation
import MultiSwitcherCore

/// Проверяет наличие обновлений через GitHub
@MainActor
enum UpdateChecker {
    private static let lastCheckKey = "com.multiswitcher.lastUpdateCheck"
    private static let autoCheckKey = "com.multiswitcher.checkUpdatesEnabled"
    private static let skippedVersionKey = "com.multiswitcher.skippedVersion"
    private static let updateDefaults = UserDefaults.standard

    static var isConfigured: Bool {
        guard let repository = Bundle.main.object(forInfoDictionaryKey: "MSGitHubRepository") as? String,
              repository.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil,
              let releaseBase = configuredURL("MSReleaseBaseURL"),
              let releasesURL = configuredURL("MSReleasesURL"),
              let teamID = Bundle.main.object(forInfoDictionaryKey: "MSDeveloperTeamID") as? String,
              teamID.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else { return false }
        return releaseBase.absoluteString == "https://github.com/\(repository)/releases/download"
            && releasesURL.absoluteString == "https://github.com/\(repository)/releases"
    }

    private static func configuredURL(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: raw), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
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
        let buildNumber: String?
        let tag: String?
        let channel: String?
        let url: String?
        let notes: String?
        let sha256: String?

        var releaseChannel: UpdateChannel { UpdateChannel(rawValue: channel ?? "stable") ?? .stable }
        var updateIdentifier: String { "\(releaseChannel.rawValue)#\(version)#\(buildNumber ?? "")" }
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let publishedAt: String?
        let createdAt: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft
            case prerelease
            case publishedAt = "published_at"
            case createdAt = "created_at"
            case assets
        }
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

    /// The setting is already persisted by SettingsManager; keep the release
    /// and local-build updater implementations behind the same UI contract.
    static func automaticChecksDidChange(_ enabled: Bool) {
        updateDefaults.set(enabled, forKey: autoCheckKey)
    }

    static func channelDidChange() {
        updateDefaults.removeObject(forKey: lastCheckKey)
        updateDefaults.removeObject(forKey: skippedVersionKey)
        checkNow()
    }

    private static func check(silent: Bool) async {
        guard let info = await fetchApplicableInfo() else {
            rslog("UpdateChecker: GitHub Releases lookup unavailable")
            if !silent { await showErrorAlert() }
            return
        }

        updateDefaults.set(Date(), forKey: lastCheckKey)

        let currentInfo = Bundle.main.infoDictionary ?? [:]
        let currentVersion = currentInfo["CFBundleShortVersionString"] as? String ?? "0"
        let currentBuild = currentInfo["CFBundleVersion"] as? String ?? "0"

        if isNewer(info, thanVersion: currentVersion, build: currentBuild) {
            if updateDefaults.string(forKey: skippedVersionKey) == info.updateIdentifier && silent {
                return // Пользователь пропустил эту версию
            }
            await showUpdateAlert(info: info)
        } else if !silent {
            await showUpToDateAlert()
        }
    }

    /// Загружает только HTTPS-фид, зашитый в подписанное приложение.
    private static func fetchApplicableInfo() async -> VersionInfo? {
        guard isConfigured,
              let repository = Bundle.main.object(forInfoDictionaryKey: "MSGitHubRepository") as? String else { return nil }
        let requestedChannel = SettingsManager.shared.updateChannel
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(repository)/releases"
        if requestedChannel == .stable {
            components.path += "/latest"
        } else {
            components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        }
        guard let releasesURL = components.url else { return nil }

        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("MultiSwitcher/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")",
                             forHTTPHeaderField: "User-Agent")
            let (data, response) = try await updateSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 2 * 1024 * 1024 else { return nil }
            let releases: [GitHubRelease]
            if requestedChannel == .stable {
                releases = [try JSONDecoder().decode(GitHubRelease.self, from: data)]
            } else {
                releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            }
            guard let candidate = UpdateChannelPolicy.select(
                releases.compactMap(policyRelease), channel: requestedChannel
            ),
                  let release = releases.first(where: { $0.tagName == candidate.tag }),
                  let asset = release.assets.first(where: { $0.name == "version.json" }),
                  isExpectedGitHubAsset(asset.browserDownloadURL, repository: repository,
                                        tag: release.tagName, name: "version.json") else { return nil }
            guard let info = await fetchInfo(from: asset.browserDownloadURL),
                  info.tag == release.tagName,
                  info.releaseChannel == (release.prerelease ? .beta : .stable),
                  info.url == "https://github.com/\(repository)/releases/download/\(release.tagName)/MultiSwitcher-\(info.version)-arm64.dmg" else { return nil }
            return info
        } catch {
            rslog("UpdateChecker GitHub release lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func policyRelease(_ release: GitHubRelease) -> PublishedRelease? {
        let channel: UpdateChannel = release.prerelease ? .beta : .stable
        guard UpdateChannelPolicy.isValidTag(release.tagName, channel: channel) else { return nil }
        let prefix = channel == .beta ? "beta-v" : "v"
        let value = String(release.tagName.dropFirst(prefix.count))
        guard let marker = value.range(of: "-build") else { return nil }
        let version = String(value[..<marker.lowerBound])
        let build = String(value[marker.upperBound...])
        return PublishedRelease(tag: release.tagName, version: version, buildNumber: build,
                                isDraft: release.draft, isPrerelease: release.prerelease,
                                publishedAt: release.publishedAt ?? release.createdAt)
    }

    private static func isExpectedGitHubAsset(_ rawURL: String, repository: String,
                                               tag: String, name: String) -> Bool {
        guard let url = URL(string: rawURL), url.scheme == "https", url.host == "github.com" else {
            return false
        }
        return url.path == "/\(repository)/releases/download/\(tag)/\(name)"
    }

    /// Скачивает и проверяет метаданные выбранного канала.
    private static func fetchInfo(from urlString: String) async -> VersionInfo? {
        guard let url = URL(string: urlString), url.scheme == "https", url.host == "github.com" else { return nil }
        do {
            let (data, response) = try await updateSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 128 * 1024 else { return nil }
            let info = try JSONDecoder().decode(VersionInfo.self, from: data)
            guard info.version.range(of: "^[0-9]+(\\.[0-9]+){1,3}$", options: .regularExpression) != nil,
                  let buildNumber = info.buildNumber,
                  buildNumber.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil,
                  let channel = UpdateChannel(rawValue: info.channel ?? "stable"),
                  let tag = info.tag,
                  UpdateChannelPolicy.isValidTag(tag, channel: channel),
                  tag == "\(channel == .beta ? "beta-v" : "v")\(info.version)-build\(buildNumber)",
                  let sha = info.sha256,
                  sha.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { return nil }
            return info
        } catch {
            rslog("UpdateChecker manifest fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func showUpdateAlert(info: VersionInfo) async {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.updateAvailable
        let buildLine = info.buildNumber.map { " (build \($0))" } ?? ""
        let channelLine = info.releaseChannel == .beta ? "\n\(L10n.updateBetaChannel)" : ""
        alert.informativeText = "\(L10n.updateNewVersion) \(info.version)\(buildLine)\(channelLine)\n\(info.notes ?? "")"
        alert.addButton(withTitle: L10n.updateInstallRestart)  // 1st
        alert.addButton(withTitle: L10n.updateDownload)         // 2nd
        alert.addButton(withTitle: L10n.updateSkip)             // 3rd
        alert.addButton(withTitle: L10n.updateLater)            // 4th

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            await installAndRestart(info: info)
        case .alertSecondButtonReturn:
            openReleasePage(tag: info.tag)
        case .alertThirdButtonReturn:
            updateDefaults.set(info.updateIdentifier, forKey: skippedVersionKey)
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

        guard let dmgURL = releaseDMGURL(info: info) else {
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
        let mountedBuild = mountedInfo?["CFBundleVersion"] as? String
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
        if let expectedBuild = info.buildNumber, mountedBuild != expectedBuild {
            rslog("Update: bundle build mismatch — announced \(expectedBuild), contains \(mountedBuild ?? "nil")")
            await showInstallError(L10n.updateIntegrityFailed)
            return
        }

        // Save a recoverable profile snapshot before touching the installed bundle.
        // The profile backup is separate from the app staging directory and persists
        // if the process exits or installation fails.
        do {
            _ = try ProfileStore.shared.createBackupSnapshot(label: "before-update")
        } catch {
            rslog("Update: profile backup failed; refusing to replace the app")
            await showInstallError(L10n.updateInstallFailed)
            return
        }

        // 6. Stage both the incoming app and an exact rollback copy beside the
        //    installed app. This guarantees a same-volume replacement and leaves the
        //    running app untouched if there is not enough space or copying fails.
        let stagingDir = currentApp.deletingLastPathComponent()
            .appendingPathComponent(".MultiSwitcher-update-\(UUID().uuidString)", isDirectory: true)
        let stagedApp = stagingDir.appendingPathComponent(appName)
        let rollbackApp = stagingDir.appendingPathComponent("Previous-MultiSwitcher.app")
        var preserveRecoveryBackup = false
        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            try fm.copyItem(at: sourceApp, to: stagedApp)
            try fm.copyItem(at: currentApp, to: rollbackApp)
        } catch {
            rslog("Update: staging copy failed — \(error)")
            try? fm.removeItem(at: stagingDir)
            await showInstallError(error.localizedDescription)
            return
        }
        defer {
            if !preserveRecoveryBackup { try? fm.removeItem(at: stagingDir) }
        }

        // 7. Атомарно заменить .app из staging-копии (на одном томе — работает)
        do {
            _ = try fm.replaceItemAt(currentApp, withItemAt: stagedApp)
            rslog("Update: app replaced successfully")
        } catch {
            rslog("Update: replace failed — \(error)")
            await showInstallError(error.localizedDescription)
            return
        }

        // Validate the actual installed copy, not just the DMG source. If this fails,
        // restore the retained app bundle before showing an error to the user.
        guard verifyNotarizedSignature(at: currentApp.path),
              bundle(at: currentApp, matchesID: Bundle.main.bundleIdentifier ?? "", version: version,
                     build: info.buildNumber) else {
            rslog("Update: installed app failed verification; restoring previous bundle")
            do {
                try fm.removeItem(at: currentApp)
                try fm.copyItem(at: rollbackApp, to: currentApp)
                guard verifyNotarizedSignature(at: currentApp.path) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                rslog("Update: previous bundle restored after post-copy verification failure")
            } catch {
                preserveRecoveryBackup = true
                rslog("Update: automatic rollback failed; recovery bundle retained at \(stagingDir.path)")
                await showInstallError(L10n.updateInstallFailed)
                return
            }
            await showInstallError(L10n.updateIntegrityFailed)
            return
        }
        rslog("Update: installed signature and bundle metadata verified")

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

    private static func releaseDMGURL(info: VersionInfo) -> URL? {
        guard isConfigured, let base = configuredURL("MSReleaseBaseURL") else { return nil }
        guard let tag = info.tag,
              UpdateChannelPolicy.isValidTag(tag, channel: info.releaseChannel) else { return nil }
        return base.appendingPathComponent(tag)
            .appendingPathComponent("MultiSwitcher-\(info.version)-arm64.dmg")
    }

    private static func openReleasePage(tag: String? = nil) {
        guard let releasesURL = configuredURL("MSReleasesURL") else { return }
        let url: URL
        if let tag,
           let repository = Bundle.main.object(forInfoDictionaryKey: "MSGitHubRepository") as? String,
           UpdateChannelPolicy.isValidTag(tag, channel: tag.hasPrefix("beta-") ? .beta : .stable),
           let releaseURL = URL(string: "https://github.com/\(repository)/releases/tag/\(tag)") {
            url = releaseURL
        } else {
            url = releasesURL
        }
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

    private static func bundle(at appURL: URL, matchesID expectedID: String,
                               version expectedVersion: String, build expectedBuild: String?) -> Bool {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == expectedID,
              info["CFBundleShortVersionString"] as? String == expectedVersion else { return false }
        if let expectedBuild {
            return info["CFBundleVersion"] as? String == expectedBuild
        }
        return true
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

    private static func isNewer(_ info: VersionInfo, thanVersion version: String, build: String) -> Bool {
        let versionOrder = semverCompare(info.version, version)
        if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
        guard let candidateBuild = info.buildNumber else { return false }
        return compareBuildNumbers(candidateBuild, build) == .orderedDescending
    }

    private static func compareBuildNumbers(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        guard left.count == lhs.split(separator: ".").count,
              right.count == rhs.split(separator: ".").count else { return .orderedSame }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
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
#endif

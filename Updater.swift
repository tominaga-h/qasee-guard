// QaseeGuard の更新（GitHub Releases から新しいバージョンを取ってきて入れ替える）
//
// 流れ: 最新リリースを確認 → 新しければ確認ダイアログ → この Mac に合う zip をダウンロード
//       → .sha256 で照合 → 展開して署名・バンドルID・バージョンを確認
//       → QaseeGuard が終了したあとに小さなスクリプトで入れ替えて起動し直す
// どこかで失敗したら、元のアプリはそのまま残す。
import AppKit
import CryptoKit

let updateRepo = "tominaga-h/qasee-guard"

enum UpdateError: LocalizedError {
    case badResponse(Int)
    case noAsset(String)
    case checksumMissing
    case checksumMismatch
    case unzipFailed
    case appNotFound
    case signatureInvalid
    case wrongBundle(String)
    case wrongVersion(expected: String, actual: String)
    case notWritable(String)
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "GitHub からの応答が正しくありませんでした（HTTP \(code)）。"
        case .noAsset(let name): return "リリースに「\(name)」が見つかりませんでした。"
        case .checksumMissing: return "ダウンロードしたファイルを確認するためのチェックサムが見つかりませんでした。"
        case .checksumMismatch: return "ダウンロードしたファイルが壊れているか、中身が違います（チェックサム不一致）。"
        case .unzipFailed: return "ダウンロードした zip を展開できませんでした。"
        case .appNotFound: return "zip の中に QaseeGuard.app が見つかりませんでした。"
        case .signatureInvalid: return "新しいアプリの署名を確認できませんでした。"
        case .wrongBundle(let id): return "zip の中身が QaseeGuard ではありませんでした（\(id)）。"
        case .wrongVersion(let expected, let actual): return "zip の中のバージョン（\(actual)）がリリース（\(expected)）と違います。"
        case .notWritable(let path): return "「\(path)」にアプリを入れ替える権限がありません。"
        case .launchFailed: return "入れ替えの処理を開始できませんでした。"
        }
    }
}

struct ReleaseInfo {
    let version: String
    let pageURL: URL?
    let assets: [String: URL]
}

@MainActor
final class Updater {
    private(set) var isChecking = false

    /// テスト用: 環境変数 QASEEGUARD_UPDATE_AUTO_CONFIRM=1 で、ダイアログを出さずに進める
    private let autoConfirm = ProcessInfo.processInfo.environment["QASEEGUARD_UPDATE_AUTO_CONFIRM"] == "1"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// この Mac 用の zip の名前に付く環境名（Apple シリコンなら Intel 版で動いていても Apple シリコン用を選ぶ）
    var platformLabel: String {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1 {
            return "mac-apple-silicon"
        }
        return "mac-intel"
    }

    // MARK: - 確認

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let release = try await fetchLatestRelease()
                log("最新リリース \(release.version) / いまのバージョン \(currentVersion) / 環境 \(platformLabel)")
                guard isNewer(release.version, than: currentVersion) else {
                    log("最新です")
                    if !autoConfirm {
                        info("最新のバージョンです", "QaseeGuard \(currentVersion) は最新です。")
                    }
                    return
                }
                guard autoConfirm || confirmUpdate(release) else {
                    log("更新は見送り")
                    return
                }
                try await install(release)
            } catch {
                log("更新に失敗: \(error)")
                if !autoConfirm { showFailure(error) }
            }
        }
    }

    func fetchLatestRelease() async throws -> ReleaseInfo {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable { let tag_name: String; let html_url: URL?; let assets: [Asset] }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(updateRepo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QaseeGuard/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.badResponse(code) }

        let release = try JSONDecoder().decode(Release.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        var assets: [String: URL] = [:]
        for asset in release.assets { assets[asset.name] = asset.browser_download_url }
        return ReleaseInfo(version: version, pageURL: release.html_url, assets: assets)
    }

    /// "1.0.2" と "1.0.10" のように、数字ごとに比べる
    func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - 入れ替え

    func install(_ release: ReleaseInfo) async throws {
        let fm = FileManager.default
        let appURL = Bundle.main.bundleURL
        let parent = appURL.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else { throw UpdateError.notWritable(parent.path) }

        let zipName = "QaseeGuard-\(release.version)-\(platformLabel).zip"
        guard let zipURL = release.assets[zipName] else { throw UpdateError.noAsset(zipName) }
        guard let shaURL = release.assets[zipName + ".sha256"] else { throw UpdateError.checksumMissing }

        let work = fm.temporaryDirectory.appendingPathComponent("QaseeGuardUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            // ダウンロード
            log("ダウンロード: \(zipURL.absoluteString)")
            let (tmpZip, zipResponse) = try await URLSession.shared.download(from: zipURL)
            let zipCode = (zipResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard zipCode == 200 else { throw UpdateError.badResponse(zipCode) }
            let zipPath = work.appendingPathComponent(zipName)
            try fm.moveItem(at: tmpZip, to: zipPath)

            // チェックサムを照合
            let (shaData, shaResponse) = try await URLSession.shared.data(from: shaURL)
            guard (shaResponse as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.checksumMissing }
            guard let expected = String(decoding: shaData, as: UTF8.self)
                    .split(whereSeparator: \.isWhitespace).first.map({ $0.lowercased() }),
                  expected.count == 64 else { throw UpdateError.checksumMissing }
            let actual = SHA256.hash(data: try Data(contentsOf: zipPath)).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw UpdateError.checksumMismatch }
            log("チェックサム OK")

            // 展開して中身を確認
            let extract = work.appendingPathComponent("extract")
            guard run("/usr/bin/ditto", ["-x", "-k", zipPath.path, extract.path]) == 0 else { throw UpdateError.unzipFailed }
            let candidates = [extract.appendingPathComponent("QaseeGuard/QaseeGuard.app"),
                              extract.appendingPathComponent("QaseeGuard.app")]
            guard let newApp = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else { throw UpdateError.appNotFound }
            guard run("/usr/bin/codesign", ["--verify", "--strict", newApp.path]) == 0 else { throw UpdateError.signatureInvalid }

            let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
            let bundleID = info?["CFBundleIdentifier"] as? String ?? "?"
            guard bundleID == Bundle.main.bundleIdentifier else { throw UpdateError.wrongBundle(bundleID) }
            let newVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
            guard newVersion == release.version else {
                throw UpdateError.wrongVersion(expected: release.version, actual: newVersion)
            }
            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
            log("中身の確認 OK（\(bundleID) \(newVersion)）")

            // QaseeGuard の終了を待って入れ替えるスクリプトを、切り離して起動する
            let script = work.appendingPathComponent("swap.sh")
            try swapScript.write(to: script, atomically: true, encoding: .utf8)
            let logFile = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/QaseeGuard-update.log")
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
            launcher.arguments = ["-c", "nohup /bin/bash \"$0\" \"$1\" \"$2\" \"$3\" \"$4\" >>\"$5\" 2>&1 &",
                                  script.path, String(getpid()), newApp.path, appURL.path, work.path, logFile.path]
            try launcher.run()
            launcher.waitUntilExit()
            guard launcher.terminationStatus == 0 else { throw UpdateError.launchFailed }
        } catch {
            try? fm.removeItem(at: work)
            throw error
        }

        log("入れ替えのため終了します")
        NSApp.terminate(nil)
    }

    /// 引数: 1=QaseeGuard の PID, 2=新しいアプリ, 3=入れ替え先, 4=作業フォルダ
    private let swapScript = """
    #!/bin/bash
    pid="$1"; new="$2"; target="$3"; work="$4"
    echo "$(date '+%F %T') 更新開始: $target"
    for _ in $(seq 1 60); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo "QaseeGuard が終了しないため中止しました"
      rm -rf "$work"
      exit 1
    fi
    backup="$target.update-backup"
    rm -rf "$backup"
    if ! mv "$target" "$backup"; then
      echo "元のアプリを退避できなかったため中止しました"
      open "$target"
      rm -rf "$work"
      exit 1
    fi
    if ditto "$new" "$target"; then
      rm -rf "$backup"
      echo "入れ替えました"
    else
      echo "入れ替えに失敗したので元に戻しました"
      rm -rf "$target"
      mv "$backup" "$target"
    fi
    open "$target"
    rm -rf "$work"
    echo "$(date '+%F %T') 完了"
    """

    // MARK: - 小さな道具

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func log(_ message: String) {
        NSLog("QaseeGuard update: %@", message)
    }

    private func confirmUpdate(_ release: ReleaseInfo) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "新しいバージョン \(release.version) があります"
        alert.informativeText = """
        いまのバージョンは \(currentVersion) です。
        更新すると QaseeGuard が一度終了し、新しいバージョンで起動し直します。QaseeClient はそのまま動き続けます。
        """
        alert.addButton(withTitle: "更新する")
        alert.addButton(withTitle: "あとで")
        if release.pageURL != nil { alert.addButton(withTitle: "変更内容を見る") }
        let result = alert.runModal()
        if result == .alertThirdButtonReturn, let url = release.pageURL {
            NSWorkspace.shared.open(url)
            return false
        }
        return result == .alertFirstButtonReturn
    }

    private func info(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private func showFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "更新できませんでした"
        alert.informativeText = "\(error.localizedDescription)\n\nいまのバージョン（\(currentVersion)）はそのまま使えます。"
        alert.runModal()
    }
}

// QaseeGuard — QaseeClient の起動/終了ボタンと、始業時間の未起動警告を出すメニューバー常駐アプリ
import AppKit
import ServiceManagement
import UserNotifications

let qaseeBundleID = "com.zerofield.QaseeClient"
/// QaseeClient の場所（バンドルIDで探し、見つからなければ /Applications を使う）
var qaseeURL: URL {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: qaseeBundleID)
        ?? URL(fileURLWithPath: "/Applications/QaseeClient.app")
}
let startHour = 9
let startMinute = 30
let checkInterval: TimeInterval = 20

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    let defaults = UserDefaults.standard

    // MARK: - 起動

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        let wsCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            wsCenter.addObserver(self, selector: #selector(stateChanged(_:)), name: name, object: nil)
        }
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()

        setupNotifications()
        // 起動したときに始業時間を過ぎていて未起動なら通知（--test-notification で強制表示）
        if CommandLine.arguments.contains("--test-notification") {
            notifyNotStarted(test: true)
        } else if shouldWarn {
            notifyNotStarted()
        }
    }

    // MARK: - 通知

    func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: "START_QASEE", title: "QaseeClientを起動", options: [])
        let category = UNNotificationCategory(identifier: "QASEE_NOT_STARTED", actions: [start],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// test: true のときは「（テスト）」付きで、押しても QaseeClient を起動しない
    func notifyNotStarted(test: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                NSLog("QaseeGuard: 通知が許可されていません \(String(describing: error))")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = test ? "（テスト）QaseeClient が起動していません" : "QaseeClient が起動していません"
            content.body = "始業時間（\(startHour):\(String(format: "%02d", startMinute))）を過ぎています。仕事を始めるなら起動してください。"
            content.sound = .default
            content.categoryIdentifier = "QASEE_NOT_STARTED"
            let request = UNNotificationRequest(identifier: test ? "qasee-test" : "qasee-not-started",
                                                content: content, trigger: nil)
            center.add(request) { error in
                NSLog("QaseeGuard: 通知を送信 \(error.map { String(describing: $0) } ?? "OK")")
            }
        }
    }

    // アプリが前面扱いでもバナーを出す
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // 「QaseeClientを起動」ボタン（または通知そのもの）を押したら起動する
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let isTest = response.notification.request.identifier == "qasee-test"
        if !isTest && (response.actionIdentifier == "START_QASEE" || response.actionIdentifier == UNNotificationDefaultActionIdentifier) {
            DispatchQueue.main.async { if !self.isRunning { self.startQasee() } }
        }
        completionHandler()
    }

    // MARK: - 状態

    var qaseeApps: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: qaseeBundleID)
    }
    var isRunning: Bool { !qaseeApps.isEmpty }

    var todayKey: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    var isDayOff: Bool { defaults.string(forKey: "dayOffDate") == todayKey }
    var finishedToday: Bool { defaults.string(forKey: "finishedDate") == todayKey }

    var isWeekday: Bool {
        let wd = Calendar.current.component(.weekday, from: Date()) // 1=日 ... 7=土
        return wd >= 2 && wd <= 6
    }
    var isPastStart: Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0) >= startHour * 60 + startMinute
    }
    /// 平日・9:30以降・未起動・「今日は休み」でも「今日は終業」でもない → 警告
    var shouldWarn: Bool { !isRunning && isWeekday && isPastStart && !isDayOff && !finishedToday }

    var loginItemEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @objc func stateChanged(_ n: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    // MARK: - メニューバー表示

    lazy var symbolImage: NSImage = makeMenuBarSymbol(height: 16)

    func refresh() {
        guard let button = statusItem.button else { return }
        let s = NSMutableAttributedString()
        let font = NSFont.menuBarFont(ofSize: 0)
        if shouldWarn {
            // 警告中は文字だけ（赤字）
            button.image = nil
            button.appearsDisabled = false
            s.append(NSAttributedString(string: "⚠︎ 始業時間過ぎてるのに未起動！", attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.boldSystemFont(ofSize: font.pointSize)]))
        } else {
            // 「● / ○」のうしろにシンボル。停止中はシンボルも薄く表示
            button.image = symbolImage
            button.imagePosition = .imageTrailing
            button.appearsDisabled = !isRunning
            if isRunning {
                s.append(NSAttributedString(string: "●", attributes: [.foregroundColor: NSColor.systemGreen, .font: font]))
            } else {
                s.append(NSAttributedString(string: "○", attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
            }
        }
        button.attributedTitle = s
        button.toolTip = isRunning ? "QaseeClient 起動中" : "QaseeClient 停止中"
    }

    // MARK: - メニュー（開くたびに作り直す）

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: isRunning ? "QaseeClient：起動中" : "QaseeClient：停止中", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if shouldWarn {
            let w = NSMenuItem(title: "始業時間（\(startHour):\(String(format: "%02d", startMinute))）を過ぎています", action: nil, keyEquivalent: "")
            w.isEnabled = false
            menu.addItem(w)
        }
        menu.addItem(.separator())

        let start = NSMenuItem(title: "起動", action: #selector(startQasee), keyEquivalent: "")
        start.target = self
        start.isEnabled = !isRunning
        menu.addItem(start)

        let stop = NSMenuItem(title: "終了…", action: #selector(stopQasee), keyEquivalent: "")
        stop.target = self
        stop.isEnabled = isRunning
        menu.addItem(stop)

        menu.addItem(.separator())

        let dayOff = NSMenuItem(title: "今日は休み（警告を出さない）", action: #selector(toggleDayOff), keyEquivalent: "")
        dayOff.target = self
        dayOff.state = isDayOff ? .on : .off
        menu.addItem(dayOff)

        let login = NSMenuItem(title: "ログイン時にこのアプリを開く", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = loginItemEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "QaseeGuard を終了", action: #selector(quitSelf), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - 操作

    @objc func startQasee() {
        defaults.removeObject(forKey: "finishedDate") // また仕事を始めたら「終業」を取り消す
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: qaseeURL, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error = error { self.showError("QaseeClient を起動できませんでした", error) }
                self.refresh()
            }
        }
    }

    @objc func stopQasee() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "QaseeClient を終了しますか？"
        alert.informativeText = "今日は終業扱いにして、このあと未起動の警告は出しません。"
        alert.addButton(withTitle: "終了する")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        defaults.set(todayKey, forKey: "finishedDate")
        for app in qaseeApps { app.terminate() }
        // 5秒たっても残っていたら強制終了
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            for app in self.qaseeApps { app.forceTerminate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
        }
        refresh()
    }

    @objc func toggleDayOff() {
        if isDayOff { defaults.removeObject(forKey: "dayOffDate") } else { defaults.set(todayKey, forKey: "dayOffDate") }
        refresh()
    }

    @objc func toggleLoginItem() {
        do {
            if loginItemEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            showError("ログイン項目を変更できませんでした", error)
        }
    }

    @objc func quitSelf() { NSApp.terminate(nil) }

    func showError(_ title: String, _ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = error.localizedDescription
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

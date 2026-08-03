// Ipil — Khairul's desktop pet and Claude companion.
// Phase 1: Ipil watches your local Claude Code sessions (no API, no tokens) and
// mirrors their progress in slim one-way pills. Click Ipil (or a pill) to jump
// to the Claude window. Two-way chat is parked for a later phase.

import AppKit
import ServiceManagement

// Debug: `Ipil --scan` prints one watcher pass and exits (no UI).
if CommandLine.arguments.contains("--scan") {
    let watcher = SessionWatcher()
    for info in watcher.scan() {
        print("[\(info.statusLabel)] \(info.title)  (\(info.id.prefix(8)))")
        if !info.snippet.isEmpty { print("    \(info.snippet.prefix(120))") }
    }
    print("cli: \(SessionReply.cliPath ?? "NOT FOUND")")
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var pet: PetController!
    var statusItem: NSStatusItem!
    let watcher = SessionWatcher()
    let panel = SessionPanel()
    // All scans run on ONE serial queue — SessionWatcher's caches are not
    // thread-safe, and concurrent scans corrupt them (launch crash, 020826).
    let scanQueue = DispatchQueue(label: "com.khairulakbar.ipil.scan", qos: .utility)
    var scanTimer: Timer?
    var positionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        pet = PetController()
        pet.view.onClick = { [weak self] in
            self?.pet.petClicked()
            AppDelegate.openClaude() // one click on the pet → Claude's window
        }
        pet.view.menuProvider = { [weak self] in self?.buildMenu() ?? NSMenu() }
        pet.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let iconPath = Bundle.main.path(forResource: "menubar", ofType: "png"),
           let icon = NSImage(contentsOfFile: iconPath) {
            icon.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "🐈"
        }
        statusItem.menu = buildMenu()

        panel.onOpen = { _ in AppDelegate.openClaude() }
        panel.onReply = { [weak self] info, text in
            guard let self else { return .noCLI }
            let result = SessionReply.send(
                sessionId: info.id, cwd: info.cwd, text: text,
                onFinish: { [weak self] answer in
                    self?.panel.deliverAnswer(sessionId: info.id, text: answer)
                }
            )
            if case .launched = result {
                self.watcher.markSending(id: info.id)
                self.rescan()
            }
            return result
        }

        // Ipil's visibility tracks the Claude app: appear when it launches,
        // vanish when it quits. The menu bar icon stays either way.
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.syncVisibilityWithClaude()
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.syncVisibilityWithClaude()
        }
        syncVisibilityWithClaude()

        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.rescan()
        }
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.panel.position(abovePetFrame: self.pet.window.frame)
        }
        rescan()

        // `--selftest` proves the answer→pill path without spending a Claude turn:
        // it injects a fake answer and logs what the pill actually displays.
        if CommandLine.arguments.contains("--selftest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self else { return }
                let infos = self.watcher.scan()
                guard let first = infos.first else {
                    SessionReply.log("SELFTEST: no active sessions to test against")
                    exit(1)
                }
                SessionReply.log("SELFTEST: delivering fake answer to \(first.title)")
                self.panel.deliverAnswer(
                    sessionId: first.id,
                    text: "SELFTEST ANSWER — if this line reached the pill, the display path works."
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    SessionReply.log("SELFTEST: pill text now = \(self.panel.displayedText(for: first.id) ?? "<none>")")
                    exit(0)
                }
            }
        }
    }

    func rescan() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            let infos = self.watcher.scan()
            DispatchQueue.main.async {
                self.panel.update(with: infos)
                self.panel.position(abovePetFrame: self.pet.window.frame)
                if self.panel.hasWaitingSession {
                    self.pet.mood = .waiting
                } else if self.panel.hasActiveSession {
                    self.pet.mood = .working
                } else {
                    self.pet.mood = .normal
                }
            }
        }
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let toggle = NSMenuItem(
            title: panel.userHidden ? "Show Claude Bubbles" : "Hide Claude Bubbles",
            action: #selector(toggleBubbles),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        let popAll = NSMenuItem(title: "Pop Bubbles Again", action: #selector(popBubbles), keyEquivalent: "")
        popAll.target = self
        menu.addItem(popAll)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start Ipil at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ipil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc func toggleBubbles() {
        panel.toggleHidden()
        statusItem.menu = buildMenu()
    }

    @objc func popBubbles() {
        panel.showAll()
        rescan()
        statusItem.menu = buildMenu()
    }

    @objc func toggleLoginItem() {
        let svc = SMAppService.mainApp
        if svc.status == .enabled {
            try? svc.unregister()
        } else {
            try? svc.register()
        }
        statusItem.menu = buildMenu()
    }

    static var claudeIsRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.anthropic.claudefordesktop"
        ).isEmpty
    }

    func syncVisibilityWithClaude() {
        let visible = AppDelegate.claudeIsRunning
        pet.window.setIsVisible(visible)
        panel.suspended = !visible
        if visible { rescan() } else { panel.update(with: []) }
    }

    // Bring the Claude desktop app forward (like the ChatGPT pet does)
    static func openClaude() {
        let bundleId = "com.anthropic.claudefordesktop"
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

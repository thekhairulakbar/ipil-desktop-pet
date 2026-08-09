// Slim one-way status pills above Ipil — a mirror of Claude's sessions, nothing
// more. Click a pill (or Ipil himself) to jump to the Claude window; ✕ dismisses.

import AppKit

final class PanelWindow: NSWindow {
    // Key only while Khairul types a reply; otherwise pills never steal focus.
    override var canBecomeKey: Bool { true }
}

final class SessionRowView: NSView {
    static let rowWidth: CGFloat = 352
    static let rowHeight: CGFloat = 55
    static let replyExtra: CGFloat = 28
    static let answerExtra: CGFloat = 58

    let sessionId: String
    private let statusDot = NSView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let updateLabel = NSTextField(wrappingLabelWithString: "")
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private let replyButton = NSButton(title: "↩", target: nil, action: nil)
    private let replyField = NSTextField(frame: .zero)

    var onDismiss: (() -> Void)?
    var onOpen: (() -> Void)?
    var onPromote: (() -> Void)?
    var onReply: ((String) -> SessionReply.SendResult)?

    // Deck stacking: the front card is fully visible; back cards only peek a
    // title strip. A click on a peeked card brings it forward instead of
    // jumping to Claude — you promote first, read, then click through.
    var isFront = true

    var replyOpen = false {
        didSet { applyLayout() }
    }
    var height: CGFloat {
        SessionRowView.rowHeight
            + (replyOpen ? SessionRowView.replyExtra : 0)
            + (showingAnswer ? SessionRowView.answerExtra : 0)
    }
    private var showingAnswer = false
    var onHeightChange: (() -> Void)?

    private var info: SessionInfo
    // Local status the watcher refresh must not overwrite — without this, every
    // pill message vanished within 1.5s and replies looked like they did nothing.
    private var notice: String?
    private var noticeExpiry: Date?   // nil = sticky: survives every refresh

    init(info: SessionInfo) {
        self.sessionId = info.id
        self.info = info
        super.init(frame: NSRect(x: 0, y: 0, width: SessionRowView.rowWidth, height: SessionRowView.rowHeight))
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.13, alpha: 0.95).cgColor
        layer?.cornerRadius = 12
        // Hairline edge so overlapped deck cards read as separate pills
        layer?.borderColor = NSColor(white: 1, alpha: 0.09).cgColor
        layer?.borderWidth = 1

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3.5
        addSubview(statusDot)

        // Line 1: the chat's title, exactly as it reads in the Claude app
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // Line 2 (up to 2 lines): the live progress update from the chat.
        // Word-wrap + truncate-last-line — a bare truncating mode kills wrapping
        // and leaves the pill half empty.
        updateLabel.font = NSFont.systemFont(ofSize: 11)
        updateLabel.textColor = NSColor(white: 0.72, alpha: 1)
        updateLabel.maximumNumberOfLines = 2
        updateLabel.lineBreakMode = .byWordWrapping
        updateLabel.cell?.truncatesLastVisibleLine = true
        addSubview(updateLabel)

        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 9)
        closeButton.contentTintColor = NSColor(white: 0.55, alpha: 1)
        closeButton.target = self
        closeButton.action = #selector(dismissRow)
        addSubview(closeButton)

        replyButton.isBordered = false
        replyButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        replyButton.contentTintColor = NSColor(white: 0.55, alpha: 1)
        replyButton.toolTip = "Reply to this chat"
        replyButton.target = self
        replyButton.action = #selector(toggleReply)
        addSubview(replyButton)

        replyField.placeholderString = "Ask or instruct…  ⏎"
        replyField.font = NSFont.systemFont(ofSize: 11.5)
        replyField.wantsLayer = true
        replyField.isBordered = false
        replyField.drawsBackground = true
        replyField.backgroundColor = NSColor(white: 0.22, alpha: 1)
        replyField.layer?.cornerRadius = 6
        replyField.textColor = .white
        replyField.focusRingType = .none
        replyField.isHidden = true
        replyField.target = self
        replyField.action = #selector(sendReply)
        addSubview(replyField)

        apply(info)
        applyLayout()
    }

    private func applyLayout() {
        let w = SessionRowView.rowWidth
        let h = height
        setFrameSize(NSSize(width: w, height: h))
        statusDot.frame = NSRect(x: 12, y: h - 16, width: 7, height: 7)
        titleLabel.frame = NSRect(x: 26, y: h - 21, width: w - 26 - 48, height: 16)
        replyButton.frame = NSRect(x: w - 44, y: h - 21, width: 16, height: 16)
        closeButton.frame = NSRect(x: w - 24, y: h - 21, width: 16, height: 16)
        updateLabel.frame = NSRect(x: 12, y: replyOpen ? 33 : 5, width: w - 24, height: 29)
        replyField.frame = NSRect(x: 12, y: 5, width: w - 24, height: 22)
        replyField.isHidden = !replyOpen
        needsDisplay = true
        onHeightChange?()
    }

    @objc private func toggleReply() {
        replyOpen.toggle()
        if replyOpen {
            onPromote?() // typing always happens on the front card
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window?.makeFirstResponder(replyField)
        }
    }

    // Tasks run headlessly since 020826 (acceptEdits + Bash allowlist), but they
    // take minutes — flag them so a slow pill never looks broken.
    private static let taskWords = [
        "handoff", "hand off", "write", "create", "edit", "build", "commit",
        "delete", "rename", "move ", "run ", "fix ", "update", "save",
    ]

    private func looksLikeTask(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.hasPrefix("/") { return true } // slash commands invoke skills
        return SessionRowView.taskWords.contains { t.contains($0) }
    }

    @objc private func sendReply() {
        let text = replyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let isTask = looksLikeTask(text)
        replyField.stringValue = ""
        replyOpen = false
        clearNotice()
        switch onReply?(text) ?? .noCLI {
        case .launched:
            noticeExpiry = nil // sticky until the answer replaces it
            notice = isTask
                ? "⏳ Running that task — file work can take several minutes."
                : "⏳ Sent — waiting for Claude…"
        case .busy:
            noticeExpiry = Date().addingTimeInterval(12)
            notice = "⏳ Still working on your previous message — send this again shortly."
        case .noCLI:
            noticeExpiry = Date().addingTimeInterval(12)
            notice = "⚠️ Can't find the claude command — reply unavailable."
        }
        SessionReply.log("pill[\(sessionId.prefix(8))] displaying: \(notice ?? "")")
        showNotice()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isFront {
            onOpen?()
        } else {
            onPromote?()
        }
    }

    @objc private func dismissRow() {
        if showingAnswer {
            clearNotice()
            apply(info)
            return
        }
        onDismiss?()
    }

    var currentlyDisplayedText: String { updateLabel.stringValue }

    private func showNotice() {
        guard let n = notice else { return }
        updateLabel.stringValue = n
        updateLabel.textColor = showingAnswer ? NSColor(white: 0.95, alpha: 1) : NSColor.systemYellow
    }

    // Sticky by default: only a timer or a replacement clears a notice. Tying it
    // to snippet changes was wrong — on an active session the snippet churns
    // every 1.5s, so every notice vanished before it could be read (fixed 020826).
    private func noticeStillValid() -> Bool {
        guard notice != nil else { return false }
        if let exp = noticeExpiry, Date() > exp { return false }
        return true
    }

    /// Claude's answer to a pill reply — the pill grows to show it, ✕ clears it.
    func showAnswer(_ text: String) {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        notice = flat.count > 420 ? String(flat.prefix(420)) + "…" : flat
        noticeExpiry = nil
        showingAnswer = true
        updateLabel.maximumNumberOfLines = 5
        SessionReply.log("pill[\(sessionId.prefix(8))] displaying answer: \(flat.prefix(90))")
        applyLayout()
        showNotice()
    }

    private func clearNotice() {
        notice = nil
        noticeExpiry = nil
        if showingAnswer {
            showingAnswer = false
            updateLabel.maximumNumberOfLines = 2
            applyLayout()
        }
    }

    func apply(_ info: SessionInfo) {
        self.info = info
        titleLabel.stringValue = info.title
        if !noticeStillValid() { clearNotice() }
        updateLabel.textColor = NSColor(white: 0.72, alpha: 1)

        // Mirror the ChatGPT pet: show the chat's latest narration; fall back to
        // the status word when the turn hasn't produced prose yet.
        let update = info.snippet
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        updateLabel.stringValue = update.isEmpty ? info.statusLabel : update
        showNotice() // a live notice outranks the mirrored text

        let color: NSColor
        switch info.status {
        case .thinking: color = NSColor.systemOrange
        case .running: color = NSColor.systemBlue
        case .writing: color = NSColor.systemGreen
        case .yourTurn: color = NSColor.systemRed
        case .sending: color = NSColor.systemPurple
        }
        statusDot.layer?.backgroundColor = color.cgColor
    }
}

final class SessionPanel {
    private var window: PanelWindow?
    private var rows: [String: SessionRowView] = [:]
    private var dismissed: [String: Date] = [:]
    // The card the user pulled to the front (reply open, answer delivered, or
    // a click on a peeked card). nil = live ordering: most recent activity wins.
    private var pinnedId: String?
    var userHidden = false
    var suspended = false // true while the Claude app is not running

    var onOpen: ((SessionInfo) -> Void)?
    var onReply: ((SessionInfo, String) -> SessionReply.SendResult)?

    private var latestInfos: [SessionInfo] = []

    func update(with infos: [SessionInfo]) {
        var visible: [SessionInfo] = []
        for info in infos {
            if let dismissedAt = dismissed[info.id] {
                if info.lastActivity > dismissedAt.addingTimeInterval(5) {
                    dismissed[info.id] = nil
                    visible.append(info)
                }
            } else {
                visible.append(info)
            }
        }
        visible = Array(visible.prefix(4))
        latestInfos = visible

        guard !userHidden, !suspended, !visible.isEmpty else {
            window?.orderOut(nil)
            return
        }
        layout(visible)
    }

    private func layout(_ infos: [SessionInfo]) {
        // GPT-pet-style deck: the active card sits in front at full height,
        // inactive cards stack BEHIND it, each peeking only a title strip.
        // 4 sessions ≈ 121pt instead of the old 235pt column that walled off
        // the screen above Ipil.
        let peek: CGFloat = 22
        let width = SessionRowView.rowWidth

        // Front card: the pinned one if the user pulled something forward,
        // otherwise the most recently active session (watcher order).
        var ordered = infos
        if pinnedId != nil, !ordered.contains(where: { $0.id == pinnedId }) {
            pinnedId = nil
        }
        if let pid = pinnedId, let idx = ordered.firstIndex(where: { $0.id == pid }), idx > 0 {
            ordered.insert(ordered.remove(at: idx), at: 0)
        }

        let w: PanelWindow
        if let existing = window {
            w = existing
        } else {
            w = PanelWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
            window = w
        }
        guard let container = w.contentView else { return }

        var orderedRows: [SessionRowView] = []
        var newRows: [String: SessionRowView] = [:]
        for info in ordered {
            let row: SessionRowView
            if let existing = rows[info.id] {
                existing.apply(info)
                row = existing
            } else {
                row = SessionRowView(info: info)
                row.onDismiss = { [weak self] in
                    guard let self else { return }
                    self.dismissed[info.id] = Date()
                    if self.pinnedId == info.id { self.pinnedId = nil }
                    self.rows[info.id]?.removeFromSuperview()
                    self.rows[info.id] = nil
                    self.update(with: self.latestInfos)
                }
                row.onOpen = { [weak self] in
                    guard let self else { return }
                    // Clicking through to Claude releases the pin — the deck
                    // goes back to live most-recent-first ordering.
                    if self.pinnedId == info.id { self.pinnedId = nil }
                    self.onOpen?(info)
                }
                row.onPromote = { [weak self] in
                    guard let self else { return }
                    self.pinnedId = info.id
                    self.update(with: self.latestInfos)
                }
                row.onReply = { [weak self] text in
                    self?.onReply?(info, text) ?? .noCLI
                }
                row.onHeightChange = { [weak self] in
                    self?.update(with: self?.latestInfos ?? [])
                }
                container.addSubview(row)
            }
            orderedRows.append(row)
            newRows[info.id] = row
        }
        for (id, row) in rows where newRows[id] == nil {
            row.removeFromSuperview()
        }
        rows = newRows

        guard let front = orderedRows.first else {
            w.orderOut(nil)
            return
        }
        let height = front.height + CGFloat(orderedRows.count - 1) * peek

        if abs(w.frame.height - height) > 0.5 || abs(w.frame.width - width) > 0.5 {
            var frame = w.frame
            frame.origin.y += frame.size.height - height
            frame.size = NSSize(width: width, height: height)
            w.setFrame(frame, display: false)
        }
        container.setFrameSize(NSSize(width: width, height: height))

        // Front card at the bottom (nearest Ipil), fully visible. Each card
        // behind it climbs `peek` points, showing only its dot + title strip.
        for (i, row) in orderedRows.enumerated() {
            if i == 0 {
                row.setFrameOrigin(NSPoint(x: 0, y: 0))
                row.isFront = true
                row.alphaValue = 1
            } else {
                let top = front.height + CGFloat(i) * peek
                row.setFrameOrigin(NSPoint(x: 0, y: top - row.height))
                row.isFront = false
                row.alphaValue = 0.92
            }
        }
        // z-order: deepest card at the back, front card drawn last. Re-stack
        // only when the order actually changed — re-adding subviews mid-typing
        // would drop the reply field's focus.
        let desired = orderedRows.reversed().map { ObjectIdentifier($0) }
        let current = container.subviews.compactMap { $0 as? SessionRowView }.map { ObjectIdentifier($0) }
        if current != desired {
            for row in orderedRows.reversed() { container.addSubview(row) }
        }
        if !w.isVisible { w.orderFront(nil) }
    }

    func position(abovePetFrame petFrame: NSRect) {
        guard let w = window, w.isVisible else { return }
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var x = petFrame.midX - w.frame.width / 2
        var y = petFrame.maxY + 6
        x = min(max(x, screen.minX + 8), screen.maxX - w.frame.width - 8)
        if y + w.frame.height > screen.maxY {
            y = screen.maxY - w.frame.height - 8
        }
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// What the pill is actually showing — used by --selftest to verify display.
    func displayedText(for sessionId: String) -> String? {
        rows[sessionId]?.currentlyDisplayedText
    }

    func deliverAnswer(sessionId: String, text: String) {
        guard let row = rows[sessionId] else {
            SessionReply.log("pill[\(sessionId.prefix(8))] answer arrived but the pill is gone")
            return
        }
        // Bring the answer to the front of the deck — unless Khairul is mid-
        // typing in another card, in which case the answer waits behind it
        // (it is sticky; promoting the card later still shows it).
        if !rows.values.contains(where: { $0.replyOpen }) {
            pinnedId = sessionId
        }
        row.showAnswer(text)
        update(with: latestInfos) // re-layout for the taller row
    }

    func toggleHidden() {
        userHidden.toggle()
        if userHidden {
            window?.orderOut(nil)
        } else {
            update(with: latestInfos)
        }
    }

    // Re-pop everything: clear dismissals and unhide.
    func showAll() {
        dismissed.removeAll()
        userHidden = false
        update(with: latestInfos)
    }

    var hasWaitingSession: Bool {
        latestInfos.contains { $0.status == .yourTurn }
    }

    var hasActiveSession: Bool {
        latestInfos.contains { $0.isActive }
    }
}

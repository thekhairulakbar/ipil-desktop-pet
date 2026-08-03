// Watches ~/.claude/projects/**/*.jsonl — the live transcripts Claude Code writes
// for every session (desktop app and CLI). Zero API calls, zero tokens: Ipil just
// reads what Claude is already doing on this Mac.

import Foundation

struct SessionInfo {
    enum Status: Equatable {
        case thinking
        case running(String) // tool name
        case writing
        case yourTurn
        case sending // local: reply subprocess launched, waiting for transcript growth
    }

    let id: String
    let path: String
    let cwd: String
    let title: String
    var status: Status
    var snippet: String
    var lastActivity: Date

    var statusLabel: String {
        switch status {
        case .thinking: return "Thinking…"
        case .running(let tool): return "Running: \(tool)"
        case .writing: return "Writing…"
        case .yourTurn: return "Your turn — Ipil is waiting"
        case .sending: return "Sending your reply…"
        }
    }

    var isActive: Bool {
        switch status {
        case .yourTurn: return false
        default: return true
        }
    }
}

final class SessionWatcher {
    private let projectsDir = NSString(string: "~/.claude/projects").expandingTildeInPath
    private var lastSizes: [String: UInt64] = [:]
    private var headCache: [String: (title: String, cwd: String)] = [:]
    private var customTitleCache: [String: String] = [:]
    private var aiTitleCache: [String: String] = [:]
    private var appTitleScanned: Set<String> = []
    private var sendingUntil: [String: Date] = [:]

    /// Sessions with activity in the last `recentWindow` seconds are shown.
    var recentWindow: TimeInterval = 30 * 60

    func markSending(id: String) {
        sendingUntil[id] = Date().addingTimeInterval(600) // until growth, max 10 min
    }

    func scan() -> [SessionInfo] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(atPath: projectsDir) else { return [] }
        let cutoff = Date().addingTimeInterval(-recentWindow)
        var result: [SessionInfo] = []

        for project in projects {
            let dir = projectsDir + "/" + project
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = dir + "/" + file
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let mtime = attrs[.modificationDate] as? Date,
                      let size = (attrs[.size] as? NSNumber)?.uint64Value,
                      mtime > cutoff else { continue }
                if var info = parse(path: path, id: String(file.dropLast(6)), mtime: mtime, size: size) {
                    if let until = sendingUntil[info.id] {
                        let grewSinceSend = (lastSizes[info.id].map { size > $0 } ?? false)
                        if Date() < until && !grewSinceSend && info.status == .yourTurn {
                            info.status = .sending
                        } else if grewSinceSend || Date() >= until {
                            sendingUntil[info.id] = nil
                        }
                    }
                    result.append(info)
                }
                lastSizes[path] = size
            }
        }
        return result.sorted { $0.lastActivity > $1.lastActivity }
    }

    private func parse(path: String, id: String, mtime: Date, size: UInt64) -> SessionInfo? {
        let previousSize = lastSizes[path]
        let grew = previousSize.map { size != $0 } ?? false
        let touchedJustNow = Date().timeIntervalSince(mtime) < 8
        let active = grew || touchedJustNow

        guard let events = tailEvents(path: path) else { return nil }

        // Last main-thread conversational event decides the status
        var lastKind: String?          // "user" | "assistant-text" | "assistant-tool"
        var lastToolName: String?
        var snippet = ""

        for event in events.reversed() {
            guard let type = event["type"] as? String else { continue }
            if (event["isSidechain"] as? Bool) == true { continue }
            guard type == "user" || type == "assistant" else { continue }
            guard let message = event["message"] as? [String: Any] else { continue }

            if lastKind == nil {
                if type == "user" {
                    lastKind = "user"
                } else if let blocks = message["content"] as? [[String: Any]] {
                    if let tool = blocks.last(where: { ($0["type"] as? String) == "tool_use" }),
                       let name = tool["name"] as? String {
                        lastKind = "assistant-tool"
                        lastToolName = name
                    } else {
                        lastKind = "assistant-text"
                    }
                }
            }
            // Latest assistant prose for the snippet
            if snippet.isEmpty, type == "assistant",
               let blocks = message["content"] as? [[String: Any]] {
                let text = blocks
                    .filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { snippet = text }
            }
            if lastKind != nil && !snippet.isEmpty { break }
        }

        guard let kind = lastKind else { return nil }

        let status: SessionInfo.Status
        if active {
            switch kind {
            case "assistant-tool": status = .running(lastToolName ?? "tool")
            case "assistant-text": status = .writing
            default: status = .thinking
            }
        } else {
            switch kind {
            case "assistant-text": status = .yourTurn
            case "assistant-tool":
                // stalled mid-tool: still treat as thinking briefly, then hide
                if Date().timeIntervalSince(mtime) > 180 { return nil }
                status = .thinking
            default:
                if Date().timeIntervalSince(mtime) > 120 { return nil }
                status = .thinking
            }
        }

        let lastCwd = (events.last(where: { $0["cwd"] is String })?["cwd"] as? String) ?? ""
        let head = headCache[path] ?? {
            let h = readHead(path: path, fallbackTitle: fallbackTitle(fromCwd: lastCwd, id: id))
            headCache[path] = h
            return h
        }()
        // claude --resume resolves sessions per project folder, so replies must
        // run from the folder the session STARTED in — not wherever it cd'd to.
        let cwd = head.cwd.isEmpty ? lastCwd : head.cwd

        // Title = what the app shows. A rename (custom-title) ALWAYS beats the
        // regenerating ai-title, no matter which event is newer.
        for event in events.reversed() {
            guard let t = event["type"] as? String else { continue }
            if t == "custom-title", let s = event["customTitle"] as? String, !s.isEmpty {
                customTitleCache[path] = s
                break // newest rename wins; stop looking
            }
            if t == "ai-title", let s = event["aiTitle"] as? String, !s.isEmpty,
               aiTitleCache[path] == nil {
                aiTitleCache[path] = s // newest ai-title; keep scanning for a rename
            }
        }
        if customTitleCache[path] == nil, !appTitleScanned.contains(path) {
            appTitleScanned.insert(path)
            let scanned = fullScanAppTitle(path: path)
            if let c = scanned.custom { customTitleCache[path] = c }
            if let a = scanned.ai, aiTitleCache[path] == nil { aiTitleCache[path] = a }
        }
        let title = customTitleCache[path] ?? aiTitleCache[path] ?? head.title

        // Keep the full reply (capped generously) — the expanded bubble is a
        // readable mini-chat now, not a two-line teaser.
        if snippet.count > 6000 {
            snippet = String(snippet.prefix(6000)) + "…"
        }

        return SessionInfo(
            id: id, path: path, cwd: cwd, title: title,
            status: status, snippet: snippet, lastActivity: mtime
        )
    }

    private func fallbackTitle(fromCwd cwd: String, id: String) -> String {
        let folder = (cwd as NSString).lastPathComponent
        return folder.isEmpty ? String(id.prefix(8)) : folder
    }

    // Read the last chunk of the file and decode complete JSON lines.
    private func tailEvents(path: String, maxBytes: Int = 96 * 1024) -> [[String: Any]]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var events: [[String: Any]] = []
        for line in text.split(separator: "\n").dropFirst(offset > 0 ? 1 : 0) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            events.append(obj)
        }
        return events.isEmpty ? nil : events
    }

    // One-time full-file sweep for the app's chat title (title events can sit
    // anywhere in the file). Later renames are caught live by the tail scan.
    private func fullScanAppTitle(path: String) -> (custom: String?, ai: String?) {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return (nil, nil) }
        var custom: String?
        var ai: String?
        for line in text.split(separator: "\n") {
            guard line.contains("\"custom-title\"") || line.contains("\"ai-title\"") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            if let s = obj["customTitle"] as? String, !s.isEmpty { custom = s }
            else if let s = obj["aiTitle"] as? String, !s.isEmpty { ai = s }
        }
        return (custom, ai)
    }

    // Head scan: the session's ORIGINAL cwd (where --resume must run from) and a
    // title — prefer a "summary" event, else the first real user message.
    private func readHead(path: String, fallbackTitle: String) -> (title: String, cwd: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (fallbackTitle, "") }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 32 * 1024),
              let text = String(data: data, encoding: .utf8) else { return (fallbackTitle, "") }
        var title: String?
        var cwd: String?
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            if cwd == nil, let c = obj["cwd"] as? String, !c.isEmpty {
                cwd = c
            }
            if title == nil, let type = obj["type"] as? String {
                if type == "summary", let summary = obj["summary"] as? String, !summary.isEmpty {
                    title = String(summary.prefix(48))
                } else if type == "user",
                          (obj["isSidechain"] as? Bool) != true,
                          let message = obj["message"] as? [String: Any] {
                    var body: String?
                    if let s = message["content"] as? String {
                        body = s
                    } else if let blocks = message["content"] as? [[String: Any]] {
                        body = blocks
                            .filter { ($0["type"] as? String) == "text" }
                            .compactMap { $0["text"] as? String }
                            .joined(separator: " ")
                    }
                    if var b = body?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !b.isEmpty,
                       !b.hasPrefix("<"), !b.hasPrefix("Caveat:"),
                       !b.hasPrefix("Base directory for this skill"),
                       !b.hasPrefix("Launching skill"),
                       !b.hasPrefix("Tool loaded"),
                       !b.contains("<command-name>") {
                        b = b.replacingOccurrences(of: "\n", with: " ")
                        title = String(b.prefix(48))
                    }
                }
            }
            if title != nil && cwd != nil { break }
        }
        return (title ?? fallbackTitle, cwd ?? "")
    }
}

// The reply engine — revived 010826 for GPT-pet parity (↩ on each pill).
// Replies run headless via claude CLI; answers surface in the pill. They fork
// the transcript tree, so they never render inside the desktop app's UI.
enum SessionReply {
    static let cliCandidates = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        NSString(string: "~/.local/bin/claude").expandingTildeInPath,
    ]

    static var cliPath: String? {
        cliCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let logPath = NSString(string: "~/Library/Logs/Ipil.log").expandingTildeInPath

    static func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(stamp)] \(line)\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }

    private static var inFlight = Set<String>()
    private static let inFlightLock = NSLock()

    enum SendResult { case launched, busy, noCLI }

    @discardableResult
    static func send(sessionId: String, cwd: String, text: String,
                     onFinish: ((String) -> Void)? = nil) -> SendResult {
        guard let cli = cliPath else {
            log("reply FAILED: claude CLI not found in \(cliCandidates)")
            return .noCLI
        }
        inFlightLock.lock()
        if inFlight.contains(sessionId) {
            inFlightLock.unlock()
            log("reply SKIPPED (one already in flight) → session \(sessionId.prefix(8)): \(text.prefix(60))")
            return .busy
        }
        inFlight.insert(sessionId)
        inFlightLock.unlock()
        DispatchQueue.global(qos: .utility).async {
            defer {
                inFlightLock.lock()
                inFlight.remove(sessionId)
                inFlightLock.unlock()
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: cli)
            // Khairul granted pill replies task powers (020826). acceptEdits covers
            // file writes; Bash is allowlisted to file management only — no rm, no
            // sudo, no network. Anything outside the list still needs approval and
            // will stall, which the timeout below catches.
            task.arguments = [
                "--resume", sessionId, "-p", text,
                "--permission-mode", "acceptEdits",
                "--allowedTools",
                "Bash(mkdir:*),Bash(mv:*),Bash(cp:*),Bash(ls:*),Bash(cat:*),Bash(find:*),"
                    + "Bash(grep:*),Bash(touch:*),Bash(head:*),Bash(tail:*),Bash(wc:*),"
                    + "Bash(date:*),Bash(python3:*),Bash(qmd:*),Bash(echo:*),Bash(cd:*)",
            ]
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = env["TERM"] ?? "dumb"
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
            task.environment = env
            if !cwd.isEmpty, FileManager.default.fileExists(atPath: cwd) {
                task.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            log("reply → session \(sessionId.prefix(8)) cwd=\(cwd) text=\(text.prefix(80))")
            do {
                try task.run()
                // Hard ceiling: a turn stalled on an un-allowlisted approval would
                // otherwise hang forever, silently burning usage (hit 020826).
                let deadline = DispatchTime.now() + .seconds(900)
                DispatchQueue.global(qos: .background).asyncAfter(deadline: deadline) {
                    if task.isRunning {
                        log("reply TIMEOUT after 15 min — terminating session \(sessionId.prefix(8))")
                        task.terminate()
                    }
                }
                task.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                log("reply exit=\(task.terminationStatus) output: \(output.prefix(400))")
                // The answer goes to the PILL, not just this log — that gap is why
                // four successful replies looked like silence (fixed 020826).
                let answer = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let shown = answer.isEmpty
                    ? (task.terminationStatus == 0 ? "Done — no text returned." : "⚠️ Reply failed (exit \(task.terminationStatus)).")
                    : answer
                DispatchQueue.main.async { onFinish?(shown) }
            } catch {
                log("reply LAUNCH ERROR: \(error.localizedDescription)")
                let message = "⚠️ Couldn't start Claude: \(error.localizedDescription)"
                DispatchQueue.main.async { onFinish?(message) }
            }
        }
        return .launched
    }
}

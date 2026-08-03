// The pet itself: transparent always-on-top window, behavior state machine,
// dash-to-cursor for the ask flow, drag + click interactions.

import AppKit

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class PetView: NSView {
    var frameKind: SpriteFrame = .stand
    var facingRight = false
    var bobOffset: CGFloat = 0
    var overlay: String? = nil // "💤", "❤️", "🤔"

    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    private var dragged = false
    private var lastDragLocation = NSPoint.zero

    // Receive the very first click even when Ipil isn't the active app —
    // otherwise macOS eats it to focus the window and onClick never fires.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static let spriteSize = NSSize(width: 108, height: 72)
    static let overlayHeadroom: CGFloat = 34

    override func draw(_ dirtyRect: NSRect) {
        let spriteRect = NSRect(
            x: (bounds.width - PetView.spriteSize.width) / 2,
            y: bobOffset,
            width: PetView.spriteSize.width,
            height: PetView.spriteSize.height
        )
        Sprite.draw(frameKind, in: spriteRect, flipped: facingRight)

        if let overlay {
            let str = NSAttributedString(
                string: overlay,
                attributes: [.font: NSFont.systemFont(ofSize: 24)]
            )
            let size = str.size()
            str.draw(at: NSPoint(
                x: bounds.width / 2 + 14,
                y: bounds.height - size.height - 2
            ))
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragged = false
        lastDragLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - lastDragLocation.x
        let dy = now.y - lastDragLocation.y
        if abs(dx) + abs(dy) > 2 { dragged = true }
        if let w = window {
            var origin = w.frame.origin
            origin.x += dx
            origin.y += dy
            w.setFrameOrigin(origin)
        }
        lastDragLocation = now
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class PetController {
    enum State {
        case walking, idle, sitting, sleeping, dashing
        case jumping                   // vertical hop in place
        case stretching                // play-bow, always after a nap
        case zoomies                   // sudden frantic back-and-forth sprint
        case pouncing                  // crouch… then leap forward
        case flying(target: NSPoint)   // dash to cursor for the ask flow
        case parked                    // waiting near the selection
        case returning                 // fall back to the floor, then wander
    }

    let window: PetWindow
    let view: PetView
    private var timer: Timer?

    private var state: State = .walking
    private var ticksLeft = 300
    private var direction: CGFloat = -1
    private let walkSpeed: CGFloat = 1.4
    private var tick = 0
    private var heartTicks = 0
    private var actionTick = 0 // progress counter for jump/pounce arcs
    private var flyCompletion: (() -> Void)?

    var thinking = false {
        didSet {
            view.overlay = thinking ? "🤔" : currentPassiveOverlay()
        }
    }

    // Mood mirrors what Claude is doing: working = sessions running,
    // waiting = a session needs Khairul's reply, normal = quiet desktop.
    enum Mood { case normal, working, waiting }
    var mood: Mood = .normal {
        didSet { if mood != oldValue { moodChanged() } }
    }

    private func moodChanged() {
        switch mood {
        case .waiting:
            state = .sitting
            ticksLeft = 1_000_000
            view.overlay = "❗"
        case .working:
            if case .sleeping = state {
                state = .walking
                ticksLeft = Int.random(in: 150...400)
                direction = Bool.random() ? 1 : -1
            }
            if ticksLeft > 10_000 { ticksLeft = 100 }
            view.overlay = nil
        case .normal:
            if ticksLeft > 10_000 { state = .idle; ticksLeft = 60 }
            view.overlay = currentPassiveOverlay()
        }
    }

    init() {
        let windowSize = NSSize(
            width: PetView.spriteSize.width + 12,
            height: PetView.spriteSize.height + PetView.overlayHeadroom
        )
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let rect = NSRect(
            x: screen.midX - windowSize.width / 2,
            y: screen.minY,
            width: windowSize.width,
            height: windowSize.height
        )
        window = PetWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        view = PetView(frame: NSRect(origin: .zero, size: windowSize))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    func petClicked() {
        view.overlay = "❤️"
        heartTicks = 30
        if case .sleeping = state {
            state = .idle
            ticksLeft = 80
        }
    }

    // Fly to a point (near the cursor); park there until resume() is called.
    func fly(to target: NSPoint, completion: @escaping () -> Void) {
        flyCompletion = completion
        state = .flying(target: target)
        view.overlay = nil
    }

    func resume() {
        thinking = false
        state = .returning
        view.overlay = nil
    }

    private func currentPassiveOverlay() -> String? {
        if mood == .waiting { return "❗" }
        if case .sleeping = state { return "💤" }
        return nil
    }

    private func step() {
        tick += 1

        if heartTicks > 0 {
            heartTicks -= 1
            if heartTicks == 0 && !thinking {
                view.overlay = currentPassiveOverlay()
            }
        }

        let screen = NSScreen.main?.visibleFrame ?? .zero
        var origin = window.frame.origin

        switch state {
        case .walking, .dashing:
            ticksLeft -= 1
            if ticksLeft <= 0 { chooseNextState() }
            let speed = { if case .dashing = state { return walkSpeed * 3 } else { return walkSpeed } }()
            origin.x += speed * direction
            if origin.x < screen.minX { origin.x = screen.minX; direction = 1 }
            if origin.x > screen.maxX - window.frame.width {
                origin.x = screen.maxX - window.frame.width
                direction = -1
            }
            window.setFrameOrigin(origin)
            view.facingRight = direction > 0
            let stride = { if case .dashing = state { return 2 } else { return 4 } }()
            view.frameKind = (tick / stride) % 2 == 0 ? .walk1 : .walk2
            view.bobOffset = 0

        case .idle:
            ticksLeft -= 1
            if ticksLeft <= 0 { chooseNextState() }
            // standing cats flick their tail
            view.frameKind = (tick % 70) < 14 ? .tailflick : .stand
            view.bobOffset = 0

        case .sitting:
            ticksLeft -= 1
            if ticksLeft <= 0 { chooseNextState() }
            // wash the coat now and then, like the real Ipil after zoomies
            view.frameKind = (tick % 140) < 45 ? .groom : .sit
            view.bobOffset = 0

        case .sleeping:
            ticksLeft -= 1
            if ticksLeft <= 0 {
                state = .stretching // cats always stretch after a nap
                actionTick = 0
            }
            view.frameKind = .sleep
            // slow breathing
            view.bobOffset = (tick / 12) % 2 == 0 ? 0 : 1

        case .stretching:
            actionTick += 1
            view.frameKind = .stretch
            view.bobOffset = 0
            if actionTick >= 26 {
                state = .idle
                ticksLeft = Int.random(in: 40...120)
            }

        case .jumping:
            // one clean hop: sine arc inside the window's headroom
            actionTick += 1
            let duration = 20
            view.frameKind = .stand
            view.bobOffset = CGFloat(sin(Double(actionTick) / Double(duration) * .pi)) * 30
            if actionTick >= duration {
                view.bobOffset = 0
                state = .idle
                ticksLeft = Int.random(in: 30...90)
            }

        case .zoomies:
            // frantic sprint, bouncing off both screen edges
            ticksLeft -= 1
            if ticksLeft <= 0 {
                view.bobOffset = 0
                state = .sitting // cats always stop dead after zoomies
                ticksLeft = Int.random(in: 100...220)
            } else {
                origin.x += walkSpeed * 4.6 * direction
                if origin.x < screen.minX { origin.x = screen.minX; direction = 1 }
                if origin.x > screen.maxX - window.frame.width {
                    origin.x = screen.maxX - window.frame.width
                    direction = -1
                }
                window.setFrameOrigin(origin)
                view.facingRight = direction > 0
                view.frameKind = (tick / 2) % 2 == 0 ? .walk1 : .walk2
                view.bobOffset = abs(sin(CGFloat(tick) * 0.6)) * 7
            }

        case .pouncing:
            actionTick += 1
            let crouch = 12, leap = 14
            if actionTick <= crouch {
                // wind up: low crouch, tiny wiggle
                view.frameKind = .sit
                view.bobOffset = (actionTick / 3) % 2 == 0 ? 0 : -1
            } else if actionTick <= crouch + leap {
                let t = actionTick - crouch
                origin.x += 5.5 * direction
                if origin.x < screen.minX { origin.x = screen.minX; direction = 1 }
                if origin.x > screen.maxX - window.frame.width {
                    origin.x = screen.maxX - window.frame.width
                    direction = -1
                }
                window.setFrameOrigin(origin)
                view.facingRight = direction > 0
                view.frameKind = .walk1
                view.bobOffset = CGFloat(sin(Double(t) / Double(leap) * .pi)) * 22
            } else {
                view.bobOffset = 0
                state = .idle
                ticksLeft = Int.random(in: 40...120)
            }

        case .flying(let target):
            let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
            let dx = target.x - center.x
            let dy = target.y - center.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < 14 {
                state = .parked
                view.frameKind = .sit
                let done = flyCompletion
                flyCompletion = nil
                done?()
            } else {
                let stepLen: CGFloat = min(16, dist)
                origin.x += dx / dist * stepLen
                origin.y += dy / dist * stepLen
                window.setFrameOrigin(origin)
                view.facingRight = dx > 0
                view.frameKind = (tick / 2) % 2 == 0 ? .walk1 : .walk2
            }

        case .parked:
            view.frameKind = .sit
            view.bobOffset = thinking && (tick / 8) % 2 == 0 ? 1 : 0

        case .returning:
            let floorY = screen.minY
            if origin.y > floorY {
                origin.y = max(floorY, origin.y - 10)
                window.setFrameOrigin(origin)
                view.frameKind = (tick / 3) % 2 == 0 ? .walk1 : .walk2
            } else {
                state = .walking
                ticksLeft = Int.random(in: 150...400)
                direction = Bool.random() ? 1 : -1
            }
        }

        view.needsDisplay = true
    }

    private func chooseNextState() {
        if mood == .waiting {
            state = .sitting
            ticksLeft = 1_000_000
            return
        }
        // Real-cat repertoire. While Claude works (mood == .working) Ipil is
        // restless — no sleeping, a burst roughly every other state change.
        // Quiet desktop = lazier cat with occasional bursts.
        if mood == .working {
            switch Int.random(in: 0..<15) {
            case 0...3:
                state = .walking
                ticksLeft = Int.random(in: 120...350)
                direction = Bool.random() ? 1 : -1
            case 4:
                state = .idle
                ticksLeft = Int.random(in: 60...140)
            case 5:
                state = .sitting
                ticksLeft = Int.random(in: 80...180)
            case 6...7:
                state = .dashing
                ticksLeft = Int.random(in: 60...140)
            case 8...9:
                state = .jumping
                actionTick = 0
            case 10...11:
                state = .pouncing
                actionTick = 0
                direction = Bool.random() ? 1 : -1
            case 12...13:
                state = .zoomies
                ticksLeft = Int.random(in: 120...280)
                direction = Bool.random() ? 1 : -1
            default: // 14
                state = .stretching
                actionTick = 0
            }
        } else {
            switch Int.random(in: 0..<17) {
            case 0...4:
                state = .walking
                ticksLeft = Int.random(in: 150...500)
                direction = Bool.random() ? 1 : -1
            case 5...6:
                state = .idle
                ticksLeft = Int.random(in: 80...200)
            case 7...8:
                state = .sitting
                ticksLeft = Int.random(in: 120...300)
            case 9:
                state = .dashing
                ticksLeft = Int.random(in: 60...140)
            case 10:
                state = .jumping
                actionTick = 0
            case 11:
                state = .pouncing
                actionTick = 0
                direction = Bool.random() ? 1 : -1
            case 12:
                state = .zoomies
                ticksLeft = Int.random(in: 120...280)
                direction = Bool.random() ? 1 : -1
            case 13:
                state = .stretching
                actionTick = 0
            default:
                state = .sleeping
                ticksLeft = Int.random(in: 400...900)
            }
        }
        if !thinking { view.overlay = currentPassiveOverlay() }
    }
}

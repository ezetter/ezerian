import AppKit
import QuartzCore

/// The game window's content. The pixel art is shown by a layer the GPU scales up
/// with crisp, square pixels; the words are set by a second layer at the display's
/// own resolution. Keys and clicks become Avatar moves, which glide from tile to tile.
final class GameView: NSView, CALayerDelegate {
    var game: Game {
        didSet {
            screen.attach(game.world)
            snapToGame()
            game.onChange = { [weak self] in self?.needsRender = true }
            needsRender = true
        }
    }
    private let screen: Screen
    private let mapLayer = CALayer()
    private let textLayer = CALayer()
    private var texts: [TextItem] = []
    private var timer: Timer?
    private let start = CACurrentMediaTime()
    private var needsRender = true
    private var lastTick = -1

    // Gliding from one tile to the next.
    private var from = (x: 0.0, y: 0.0)
    private var to = (x: 0.0, y: 0.0)
    private var moveStart = -10.0
    private let moveTime = 0.15
    private var lastJumps = 0

    private var repeatTimer: Timer?
    private var heldKeys: [UInt16: (Int, Int)] = [:]
    private var lastKey: UInt16?
    private var mouseDirection: (Int, Int)?

    /// Called after every turn so the app can autosave now and then.
    var onTurn: (() -> Void)?

    init(game: Game) {
        self.game = game
        screen = Screen(world: game.world)
        super.init(frame: NSRect(x: 0, y: 0, width: Screen.width, height: Screen.height))
        let root = CALayer()
        root.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer = root
        wantsLayer = true
        mapLayer.magnificationFilter = .nearest
        mapLayer.minificationFilter = .linear
        mapLayer.contentsGravity = .resize
        textLayer.delegate = self
        root.addSublayer(mapLayer)
        root.addSublayer(textLayer)
        snapToGame()
        game.onChange = { [weak self] in self?.needsRender = true }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    private func snapToGame() {
        from = (Double(game.x), Double(game.y))
        to = from
        moveStart = -10
        lastJumps = game.jumps
    }

    // MARK: Drawing

    /// The largest whole-device-pixel scale that fits, centred (letterboxed in full screen).
    private func displayRect() -> CGRect {
        let backing = window?.backingScaleFactor ?? 2
        let fit = min(bounds.width * backing / CGFloat(Screen.width), bounds.height * backing / CGFloat(Screen.height))
        let k = fit >= 1 ? fit.rounded(.down) : fit
        let w = CGFloat(Screen.width) * k / backing, h = CGFloat(Screen.height) * k / backing
        return CGRect(x: ((bounds.width - w) / 2).rounded(), y: ((bounds.height - h) / 2).rounded(), width: w, height: h)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = displayRect()
        mapLayer.frame = r
        textLayer.frame = r
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
        textLayer.setNeedsDisplay()
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    func draw(_ layer: CALayer, in ctx: CGContext) {
        guard layer === textLayer, layer.bounds.width > 0 else { return }
        TextRenderer.draw(texts, in: ctx, scale: layer.bounds.width / CGFloat(Screen.width), height: layer.bounds.height)
    }

    /// The Avatar's place on screen this instant (between tiles while walking).
    private func pose(_ now: Double) -> AvatarPose {
        if game.jumps != lastJumps { snapToGame() }
        let t = max(0, min(1, (now - moveStart) / moveTime))
        let e = t * t * (3 - 2 * t)
        let x = from.x + (to.x - from.x) * e, y = from.y + (to.y - from.y) * e
        let step = t < 1 && t < 0.75 ? (game.step % 2 == 0 ? 1 : 2) : 0
        return AvatarPose(x: x, y: y, facing: game.facing, step: step)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let anim = Int((now - start) * 7)
        let moving = now - moveStart < moveTime + 0.02
        guard moving || anim != lastTick || needsRender else { return }
        lastTick = anim
        needsRender = false
        let p = pose(now)
        let t = max(0, min(1, (now - moveStart) / moveTime))
        let fb = screen.render(game, pose: p, npcT: t, frame: anim, clock: now - start)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mapLayer.contents = fb.makeImage()
        if screen.texts != texts {
            texts = screen.texts
            textLayer.setNeedsDisplay()
        }
        CATransaction.commit()
    }

    func refresh() { needsRender = true }

    // MARK: Keyboard

    private static let directionKeys: [UInt16: (Int, Int)] = [
        123: (-1, 0), 124: (1, 0), 125: (0, 1), 126: (0, -1),          // arrows
        13: (0, -1), 0: (-1, 0), 1: (0, 1), 2: (1, 0),                  // W A S D
        12: (-1, -1), 14: (1, -1), 6: (-1, 1), 8: (1, 1),               // Q E Z C
        89: (-1, -1), 91: (0, -1), 92: (1, -1), 86: (-1, 0),            // numpad 7 8 9 4
        88: (1, 0), 83: (-1, 1), 84: (0, 1), 85: (1, 1),                // numpad 6 1 2 3
    ]

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        if game.nameEntry != nil {
            enterName(event)
            return
        }
        if game.genderEntry != nil {
            chooseGender(event)
            return
        }
        if game.gameOver {
            if event.keyCode == 36 || event.keyCode == 76 {
                stopRepeating()
                heldKeys.removeAll()
                game = Game(seed: UInt64.random(in: 1...UInt64.max))
                onTurn?()
            }
            needsRender = true
            return
        }
        if game.attackPending {
            if let dir = GameView.directionKeys[event.keyCode] {
                game.attack(dx: dir.0, dy: dir.1)
                onTurn?()
            } else if event.keyCode == 53 {
                game.attackPending = false
                game.log("You lower your fists.")
            }
            needsRender = true
            return
        }
        if let c = game.conversation {
            stopRepeating()
            heldKeys.removeAll()
            if c.offer {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "y": game.answerOffer(true)
                case "n": game.answerOffer(false)
                default: break
                }
                needsRender = true
                return
            }
            switch event.keyCode {
            case _ where c.over, 53:                 // finished, or Esc
                game.endConversation()
            case 36, 76:                             // Return, Enter
                game.submitConversation()
            case 51, 117:                            // Delete, Forward Delete
                game.backspaceInConversation()
            default:
                for ch in event.characters ?? "" { game.typeInConversation(ch) }
            }
            needsRender = true
            return
        }
        if let dir = GameView.directionKeys[event.keyCode] {
            guard !event.isARepeat else { return }
            heldKeys[event.keyCode] = dir
            lastKey = event.keyCode
            stepHeld()
            startRepeating()
            return
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "m":
            game.showMap.toggle()
            game.showHelp = false
        case "g": game.showGrid.toggle()
        case "h", "?", "/": game.showHelp.toggle()
        case "l": game.lookAhead()
        case "f":
            stopRepeating()
            heldKeys.removeAll()
            game.attackPending = true
            game.log("Attack — which direction?")
        case "t":
            game.talk()
            if game.conversation != nil { stopRepeating(); heldKeys.removeAll() }
        case " ":
            game.waitTurn()
            from = (Double(game.x), Double(game.y))
            to = from
            moveStart = CACurrentMediaTime()
            onTurn?()
        case "+", "=": if game.showMap { game.mapScale = min(4, game.mapScale + 1) }
        case "-", "_": if game.showMap { game.mapScale = max(1, game.mapScale - 1) }
        case "\u{1b}":
            game.showMap = false
            game.showHelp = false
        default:
            break
        }
        needsRender = true
    }

    /// Typing into the "what is your name" prompt at the start of a new game.
    private func enterName(_ event: NSEvent) {
        switch event.keyCode {
        case 36, 76:            // Return, Enter
            game.confirmName()
            onTurn?()
        case 51, 117:           // Delete, Forward Delete
            if var entry = game.nameEntry, !entry.isEmpty { entry.removeLast(); game.nameEntry = entry }
        default:
            for ch in event.characters ?? "" { game.typeName(ch) }
        }
        needsRender = true
    }

    /// "Man or woman?": M or W picks at once; the arrows or Tab move the choice and Return takes it.
    private func chooseGender(_ event: NSEvent) {
        let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
        switch event.keyCode {
        case 36, 76:                    // Return, Enter
            game.confirmGender()
            onTurn?()
        case 123, 124, 125, 126, 48:    // arrows, Tab
            game.genderEntry?.toggle()
        default:
            if ch == "m" { game.confirmGender(female: false); onTurn?() }
            else if ch == "w" || ch == "f" { game.confirmGender(female: true); onTurn?() }
        }
        needsRender = true
    }

    override func keyUp(with event: NSEvent) {
        heldKeys.removeValue(forKey: event.keyCode)
        if heldKeys.isEmpty && mouseDirection == nil { stopRepeating() }
    }

    /// Holding two arrows (say up and right) walks diagonally.
    private func heldDirection() -> (Int, Int)? {
        if let m = mouseDirection { return m }
        guard !heldKeys.isEmpty else { return nil }
        var dx = 0, dy = 0
        for (_, d) in heldKeys { dx += d.0; dy += d.1 }
        dx = max(-1, min(1, dx)); dy = max(-1, min(1, dy))
        if dx == 0 && dy == 0, let k = lastKey, let d = heldKeys[k] { return d }
        return (dx, dy)
    }

    private func stepHeld() {
        guard let (dx, dy) = heldDirection(), dx != 0 || dy != 0 else { return }
        game.showHelp = false
        let now = CACurrentMediaTime()
        let here = pose(now)
        let jumps = game.jumps
        if game.conversation != nil { stopRepeating(); heldKeys.removeAll(); mouseDirection = nil; return }
        if game.move(dx: dx, dy: dy) {
            if game.jumps == jumps {
                from = (here.x, here.y)
                to = (Double(game.x), Double(game.y))
                moveStart = now
            } else {
                snapToGame()
            }
        }
        if game.conversation != nil { stopRepeating(); heldKeys.removeAll(); mouseDirection = nil }
        onTurn?()
        needsRender = true
    }

    private func startRepeating() {
        repeatTimer?.invalidate()
        // In a fight every blow and step is its own key press.
        if game.inCombat || game.gameOver { return }
        let timer = Timer(timeInterval: 0.22, repeats: false) { [weak self] _ in
            guard let self else { return }
            // A fight that broke out mid-stride stops the walking: every move in a fight is a choice.
            if self.game.inCombat { self.stopRepeating(); return }
            self.stepHeld()
            let again = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.game.inCombat || self.game.gameOver { self.stopRepeating(); return }
                self.stepHeld()
            }
            RunLoop.main.add(again, forMode: .common)
            self.repeatTimer = again
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    override func flagsChanged(with event: NSEvent) {
        // Losing focus mid-press can swallow key-ups; a modifier change is a good moment to resync.
        if heldKeys.isEmpty { stopRepeating() }
    }

    // MARK: Mouse

    /// Converts a window point to a pixel of the whole screen.
    private func screenPixel(for event: NSEvent) -> (Int, Int) {
        let p = convert(event.locationInWindow, from: nil)
        let r = displayRect()
        let sx = (p.x - r.minX) / r.width * CGFloat(Screen.width)
        let sy = (r.maxY - p.y) / r.height * CGFloat(Screen.height)
        return (Int(sx.rounded(.down)), Int(sy.rounded(.down)))
    }

    /// Converts a window point to a pixel of the map view, if it lies on the map.
    private func mapPixel(for event: NSEvent) -> (Int, Int)? {
        let (sx, sy) = screenPixel(for: event)
        let mx = sx - Screen.mapX, my = sy - Screen.mapY
        guard mx >= 0, my >= 0, mx < MapRenderer.pixelW, my < MapRenderer.pixelH else { return nil }
        return (mx, my)
    }

    private func direction(toward p: (Int, Int)) -> (Int, Int)? {
        let now = CACurrentMediaTime()
        let a = pose(now)
        let (cx, cy) = MapRenderer.camera(x: a.x, y: a.y)
        // Where the Avatar's body appears, leaning up and left from its feet.
        let ax = a.x * Double(MapRenderer.tile) + 10 - Double(cx), ay = a.y * Double(MapRenderer.tile) + 4 - Double(cy)
        let dx = Double(p.0) - ax, dy = Double(p.1) - ay
        guard dx * dx + dy * dy > 120 else { return nil }
        let angle = atan2(dy, dx)
        let octant = Int((angle / (Double.pi / 4)).rounded())
        let dirs = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        return dirs[(octant + 8) % 8]
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if game.genderEntry != nil {
            // Clicking a portrait of the "man or woman?" choice takes it.
            let (sx, sy) = screenPixel(for: event)
            if let female = Screen.genderChoice(atX: sx, y: sy) {
                game.confirmGender(female: female)
                onTurn?()
                needsRender = true
            }
            return
        }
        guard !game.showMap, !game.creatingCharacter, game.conversation == nil, !game.gameOver,
              let p = mapPixel(for: event), let dir = direction(toward: p) else { return }
        mouseDirection = dir
        stepHeld()
        startRepeating()
    }

    override func mouseDragged(with event: NSEvent) {
        guard mouseDirection != nil, let p = mapPixel(for: event) else { return }
        mouseDirection = direction(toward: p) ?? mouseDirection
    }

    override func mouseUp(with event: NSEvent) {
        mouseDirection = nil
        if heldKeys.isEmpty { stopRepeating() }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !game.showMap, !game.creatingCharacter, let (mx, my) = mapPixel(for: event),
              let t = screen.map.tileAt(mapPixel: mx, my) else { return }
        game.look(at: t.x, t.y)
        needsRender = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard game.showMap, abs(event.scrollingDeltaY) > 0.5 else { return }
        game.mapScale = max(1, min(4, game.mapScale + (event.scrollingDeltaY > 0 ? 1 : -1)))
        needsRender = true
    }
}

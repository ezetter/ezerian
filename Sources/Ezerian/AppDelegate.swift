import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var gameView: GameView!
    private var turnsSinceSave = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let game = SaveGame.load() ?? Game(seed: UInt64.random(in: 1...UInt64.max))
        gameView = GameView(game: game)
        gameView.onTurn = { [weak self] in self?.turnTaken() }

        window = NSWindow(contentRect: NSRect(origin: .zero, size: initialContentSize()),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "The Land of Ezerian"
        window.contentView = gameView
        window.contentMinSize = NSSize(width: Screen.width / 2, height: Screen.height / 2)
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = .black
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Ezerian2MainWindow")
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(gameView)

        buildMenus()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { save() }

    func applicationWillResignActive(_ notification: Notification) { save() }

    // MARK: Window sizing

    /// The biggest whole-pixel multiple of the 960x540 screen that fits comfortably.
    private func initialContentSize() -> NSSize {
        let screen = NSScreen.main
        let backing = screen?.backingScaleFactor ?? 2
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let k = max(1, min(visible.width * 0.94 * backing / CGFloat(Screen.width),
                           (visible.height - 30) * 0.96 * backing / CGFloat(Screen.height)).rounded(.down))
        return NSSize(width: CGFloat(Screen.width) * k / backing, height: CGFloat(Screen.height) * k / backing)
    }

    /// Snap window resizes to sizes where every game pixel is the same size on screen.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !sender.styleMask.contains(.fullScreen) else { return frameSize }
        let backing = sender.backingScaleFactor
        let content = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let k = max(1, min(content.width * backing / CGFloat(Screen.width),
                           content.height * backing / CGFloat(Screen.height)).rounded())
        let size = NSSize(width: CGFloat(Screen.width) * k / backing, height: CGFloat(Screen.height) * k / backing)
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    }

    // MARK: Saving

    private func turnTaken() {
        turnsSinceSave += 1
        if turnsSinceSave >= 150 { save() }
    }

    private func save() {
        guard let game = gameView?.game else { return }
        do {
            try SaveGame.save(game)
            turnsSinceSave = 0
        } catch {
            NSLog("Ezerian: could not save the world: \(error)")
        }
    }

    // MARK: Menus

    private func buildMenus() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About The Land of Ezerian", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Ezerian", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Ezerian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let gameItem = NSMenuItem()
        let gameMenu = NSMenu(title: "Game")
        gameMenu.addItem(withTitle: "New World…", action: #selector(newWorld), keyEquivalent: "n").target = self
        gameMenu.addItem(withTitle: "Save World", action: #selector(saveNow), keyEquivalent: "s").target = self
        gameMenu.addItem(.separator())
        gameMenu.addItem(withTitle: "Claude API Key…", action: #selector(setAPIKey), keyEquivalent: "").target = self
        let useClaude = gameMenu.addItem(withTitle: "Voice Conversations with Claude", action: #selector(toggleClaude), keyEquivalent: "")
        useClaude.target = self
        useClaude.state = ClaudeClient.shared.enabled ? .on : .off
        gameMenu.addItem(.separator())
        gameMenu.addItem(withTitle: "Map of Explored Lands  (M)", action: #selector(toggleMap), keyEquivalent: "").target = self
        gameMenu.addItem(withTitle: "Region Borders  (G)", action: #selector(toggleGrid), keyEquivalent: "").target = self
        gameMenu.addItem(withTitle: "Help  (H)", action: #selector(toggleHelp), keyEquivalent: "").target = self
        gameItem.submenu = gameMenu
        main.addItem(gameItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let full = windowMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "The Land of Ezerian",
            .credits: NSAttributedString(string: "A tile-based exploration game in the spirit of Ultima VI, painted anew."),
        ])
    }

    @objc private func newWorld() {
        let alert = NSAlert()
        alert.messageText = "Begin a new world?"
        alert.informativeText = "A fresh Land of Ezerian will be generated. The lands you have explored so far will be lost."
        alert.addButton(withTitle: "New World")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.gameView.game = Game(seed: UInt64.random(in: 1...UInt64.max))
            self.save()
        }
    }

    @objc private func saveNow() {
        save()
        gameView.game.log("The world has been saved.")
        gameView.refresh()
    }

    /// Asks for a Claude API key and keeps it in the login keychain.
    @objc private func setAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Claude API Key"
        alert.informativeText = "NPCs use Claude (\(ClaudeClient.model)) to understand what you say and answer in character. "
            + "Paste an API key from console.anthropic.com; it is kept in your login keychain. Leave it empty to remove the saved key."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-ant-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            ClaudeClient.saveKey(key.isEmpty ? nil : key)
            self?.gameView.game.log(key.isEmpty ? "The Claude API key was removed." : "The Claude API key was saved.")
            self?.gameView.refresh()
        }
    }

    @objc private func toggleClaude(_ sender: NSMenuItem) {
        ClaudeClient.shared.enabled.toggle()
        sender.state = ClaudeClient.shared.enabled ? .on : .off
        gameView.game.log(ClaudeClient.shared.enabled ? "NPCs will speak through Claude." : "NPCs will use scripted replies.")
        gameView.refresh()
    }

    @objc private func toggleMap() { gameView.game.showMap.toggle(); gameView.refresh() }
    @objc private func toggleGrid() { gameView.game.showGrid.toggle(); gameView.refresh() }
    @objc private func toggleHelp() { gameView.game.showHelp.toggle(); gameView.refresh() }
}

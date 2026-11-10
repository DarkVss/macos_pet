import AppKit

@main
@MainActor
enum PetApp {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var petController: PetController?
    private var petView: DraggablePetView?
    private var emotionPicker: NSPopUpButton?
    private var debugMenuItem: NSMenuItem?
    private var musicLabel: NSTextField?
    private let musicMonitor = MusicPlaybackMonitor(provider: AppleMusicPlaybackProvider())
    private let musicControlsHeight: CGFloat = 28
    private let debugControlsHeight: CGFloat = 44
    private var isDebugMenuEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let avatar: SpriteAvatar
        let scene: SpritePetScene
        do {
            guard let url = Bundle.main.url(forResource: "Kinoko", withExtension: "bundle") else {
                throw SpriteAvatar.InvalidPackage(reason: "Не найден встроенный аватар")
            }
            avatar = try SpriteAvatar(rootURL: url)
            scene = try SpritePetScene(size: CGSize(width: 208, height: 224), avatar: avatar)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось загрузить аватар"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }
        petController = PetController(renderer: scene)

        let view = DraggablePetView(frame: NSRect(x: 0, y: 0, width: 208, height: 224))
        view.allowsTransparency = true
        view.onDrag = { [weak self] distance in
            self?.petController?.drag(horizontalDistance: distance)
        }
        view.onDragEnded = { [weak self] in
            self?.petController?.endDragging()
        }
        view.presentScene(scene)

        let panel = NSPanel(
            contentRect: view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let container = NSView(frame: view.frame)
        container.addSubview(view)
        let picker = NSPopUpButton(frame: NSRect(x: 8, y: 8, width: 192, height: 28), pullsDown: false)
        for (index, activity) in PetState.Activity.allCases.enumerated() {
            picker.addItem(withTitle: activity.title)
            picker.lastItem?.tag = index
        }
        picker.target = self
        picker.action = #selector(selectDebugActivity(_:))
        picker.setAccessibilityLabel("Эмоция питомца")
        picker.toolTip = "Выберите эмоцию или действие для проигрывания"
        picker.isHidden = true
        container.addSubview(picker)
        let musicLabel = NSTextField(labelWithString: "Музыка")
        musicLabel.alignment = .center
        musicLabel.font = .systemFont(ofSize: 13, weight: .medium)
        musicLabel.textColor = .labelColor
        musicLabel.isHidden = true
        container.addSubview(musicLabel)
        self.musicLabel = musicLabel
        panel.contentView = container
        petView = view
        emotionPicker = picker
        panel.center()
        panel.setFrameAutosaveName("PetPosition")
        panel.orderFrontRegardless()
        self.panel = panel

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: avatar.manifest.name, action: nil, keyEquivalent: ""))
        let debugItem = NSMenuItem(title: "Отладочное меню эмоций", action: #selector(toggleDebugMenu(_:)), keyEquivalent: "")
        debugItem.target = self
        menu.addItem(debugItem)
        debugMenuItem = debugItem
        let lookItem = NSMenuItem(title: "Направление взгляда", action: nil, keyEquivalent: "")
        let lookMenu = NSMenu()
        let resetLookItem = NSMenuItem(title: "Сбросить угол взгляда", action: #selector(resetLook), keyEquivalent: "")
        resetLookItem.target = self
        lookMenu.addItem(resetLookItem)
        lookMenu.addItem(.separator())
        for index in 0..<16 {
            let item = NSMenuItem(title: "\(Double(index) * 22.5)°", action: #selector(selectLook(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            lookMenu.addItem(item)
        }
        lookItem.submenu = lookMenu
        if avatar.manifest.gaze != nil { menu.addItem(lookItem) }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Pet", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pet")
        statusItem.menu = menu
        view.menu = menu
        self.statusItem = statusItem
        setDebugMenuEnabled(true)
        musicMonitor.start { [weak self] state in
            guard let self, let label = self.musicLabel else { return }
            let hidden = state != .playing && state != .paused
            guard label.isHidden != hidden else { return }
            label.isHidden = hidden
            self.updateControlsLayout()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        musicMonitor.stop()
    }

    @objc private func toggleDebugMenu(_ sender: NSMenuItem) {
        setDebugMenuEnabled(!isDebugMenuEnabled)
    }

    private func setDebugMenuEnabled(_ enabled: Bool) {
        debugMenuItem?.state = enabled ? .on : .off
        guard enabled != isDebugMenuEnabled else { return }
        isDebugMenuEnabled = enabled
        updateControlsLayout()
    }

    private func updateControlsLayout() {
        guard let panel, let petView else { return }
        let debugHeight = isDebugMenuEnabled ? debugControlsHeight : 0
        let musicHeight = musicLabel?.isHidden == false ? musicControlsHeight : 0
        let controlsHeight = debugHeight + musicHeight
        let delta = controlsHeight - petView.frame.minY
        var frame = panel.frame
        // Grow downwards so the pet keeps its position on screen.
        frame.origin.y -= delta
        frame.size.height += delta
        panel.setFrame(frame, display: false)
        petView.setFrameOrigin(NSPoint(x: 0, y: controlsHeight))
        emotionPicker?.isHidden = !isDebugMenuEnabled
        musicLabel?.frame = NSRect(x: 8, y: debugHeight + 4, width: 192, height: 20)
        // AppKit schedules layout and drawing after the menu action finishes.
        // Drawing synchronously here can reenter an ongoing layout pass.
        panel.contentView?.needsDisplay = true
    }

    @objc private func selectDebugActivity(_ sender: NSPopUpButton) {
        guard let index = sender.selectedItem?.tag,
              PetState.Activity.allCases.indices.contains(index) else { return }
        petController?.setActivity(PetState.Activity.allCases[index])
    }

    @objc private func selectLook(_ sender: NSMenuItem) {
        petController?.look(toward: sender.tag)
    }

    @objc private func resetLook() {
        petController?.resetLook()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

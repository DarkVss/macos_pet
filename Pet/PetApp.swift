import AppKit
import SpriteKit

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
    private enum Avatar: String, CaseIterable {
        case sprite, model
        var title: String { self == .sprite ? "Кинако v0.1" : "Кинако 3D v0.1" }
    }
    private var selectedAvatar = Avatar.sprite
    private var avatarItems: [NSMenuItem] = []
    private var avatarTitleItem: NSMenuItem?
    private var lookMenuItem: NSMenuItem?
    private var renderer: (any PetRendering)?
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var petController: PetController?
    private var petView: DraggablePetView?
    private var emotionPicker: NSPopUpButton?
    private var debugMenuItem: NSMenuItem?
    private var musicControls: MusicControlsView?
    private var controlsBackdrop: ControlsBackdropView?
    private let musicProvider: any MusicPlaybackControlling = AppleMusicPlaybackProvider()
    private lazy var musicMonitor = MusicPlaybackMonitor(provider: musicProvider)
    private let debugControlsHeight: CGFloat = 44
    private var isDebugMenuEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = DraggablePetView(frame: NSRect(x: 0, y: 0, width: 208, height: 224))
        petView = view
        view.onDrag = { [weak self] distance in
            self?.petController?.drag(horizontalDistance: distance)
        }
        view.onDragEnded = { [weak self] in self?.petController?.endDragging() }
        let saved = UserDefaults.standard.string(forKey: "SelectedAvatar")
        do {
            try installAvatar(Avatar(rawValue: saved ?? "") ?? .model)
        } catch {
            do { try installAvatar(.sprite) }
            catch {
                showAvatarError(error)
                NSApplication.shared.terminate(nil)
                return
            }
            showAvatarError(error)
        }

        let panel = PetPanel(
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
        let backdrop = ControlsBackdropView(frame: .zero)
        container.addSubview(backdrop)
        controlsBackdrop = backdrop
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
        backdrop.addSubview(picker)
        let controls = MusicControlsView(frame: NSRect(x: 0, y: 0, width: 208, height: MusicControlsView.height))
        controls.onCommand = { [weak self] command in
            self?.performMusicCommand(command)
        }
        backdrop.addSubview(controls)
        musicControls = controls
        panel.contentView = container
        petView = view
        emotionPicker = picker
        panel.center()
        panel.setFrameAutosaveName("PetPosition")
        panel.orderFrontRegardless()
        self.panel = panel

        let menu = NSMenu()
        let title = NSMenuItem(title: selectedAvatar.title, action: nil, keyEquivalent: "")
        avatarTitleItem = title
        menu.addItem(title)
        let avatarMenu = NSMenu()
        for (index, avatar) in Avatar.allCases.enumerated() {
            let item = NSMenuItem(title: avatar.title, action: #selector(selectAvatar(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            avatarMenu.addItem(item)
            avatarItems.append(item)
        }
        let avatarItem = NSMenuItem(title: "Аватар", action: nil, keyEquivalent: "")
        avatarItem.submenu = avatarMenu
        menu.addItem(avatarItem)
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
        lookMenuItem = lookItem
        menu.addItem(lookItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Pet", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pet")
        statusItem.menu = menu
        view.menu = menu
        self.statusItem = statusItem
        updateAvatarControls()
        setDebugMenuEnabled(true)
        musicMonitor.start { [weak self] state in
            self?.displayMusicState(state)
        }
    }

    private func installAvatar(_ avatar: Avatar) throws {
        guard let host = petView else { return }
        let newRenderer: any PetRendering
        let content: NSView
        switch avatar {
        case .sprite:
            guard let url = Bundle.main.url(forResource: "Kinako", withExtension: "bundle") else {
                throw SpriteAvatar.InvalidPackage(reason: "Не найден встроенный спрайтовый аватар")
            }
            let scene = try SpritePetScene(size: host.bounds.size, avatar: SpriteAvatar(rootURL: url))
            let spriteView = SKView(frame: host.bounds)
            spriteView.allowsTransparency = true
            spriteView.presentScene(scene)
            newRenderer = scene
            content = spriteView
        case .model:
            guard let package = Bundle.main.url(forResource: "Kinako3D", withExtension: "bundle") else {
                throw GLBAvatar.InvalidModel(reason: "не найден встроенный пакет")
            }
            let model = try ModelPetRenderer(frame: host.bounds, url: package.appendingPathComponent("avatar.glb"))
            newRenderer = model
            content = model.view
        }
        // Build first: a failed selection leaves the existing pet and menu intact.
        for view in host.subviews { view.removeFromSuperview() }
        content.autoresizingMask = [.width, .height]
        host.addSubview(content)
        renderer = newRenderer
        if let petController { petController.replaceRenderer(newRenderer) }
        else { petController = PetController(renderer: newRenderer) }
        selectedAvatar = avatar
        UserDefaults.standard.set(avatar.rawValue, forKey: "SelectedAvatar")
        updateAvatarControls()
    }

    private func updateAvatarControls() {
        avatarTitleItem?.title = selectedAvatar.title
        for (index, item) in avatarItems.enumerated() {
            item.state = Avatar.allCases[index] == selectedAvatar ? .on : .off
        }
        lookMenuItem?.isHidden = selectedAvatar == .model
        emotionPicker?.menu?.autoenablesItems = false
        for (index, activity) in PetState.Activity.allCases.enumerated() {
            let available = renderer?.supportedActivities.contains(activity) == true
            emotionPicker?.item(at: index)?.isEnabled = available
            emotionPicker?.item(at: index)?.toolTip = available ? nil : "Для этого аватара анимация пока не подготовлена"
        }
        if let state = petController?.state, let index = PetState.Activity.allCases.firstIndex(of: state.activity) {
            emotionPicker?.selectItem(at: index)
        }
        emotionPicker?.toolTip = selectedAvatar == .model
            ? "В 3D доступны ожидание, бег и прослушивание музыки. Остальные анимации ещё не подготовлены."
            : "Выберите эмоцию или действие для проигрывания"
    }

    private func showAvatarError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Не удалось загрузить аватар"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    @objc private func selectAvatar(_ sender: NSMenuItem) {
        guard Avatar.allCases.indices.contains(sender.tag) else { return }
        let avatar = Avatar.allCases[sender.tag]
        guard avatar != selectedAvatar else { return }
        do { try installAvatar(avatar) }
        catch { showAvatarError(error) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        musicMonitor.stop()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        guard let panel else { return }
        panel.setFrame(panel.frame, display: true)
    }

    private func displayMusicState(_ state: MusicPlaybackSnapshot) {
        guard let controls = musicControls else { return }
        let wasHidden = controls.isHidden
        controls.display(state)
        petController?.setMusicActive(!controls.isHidden)
        if wasHidden != controls.isHidden { updateControlsLayout() }
    }

    private func performMusicCommand(_ command: MusicPlaybackCommand) {
        musicControls?.setCommandInProgress(true)
        Task { [weak self, musicProvider] in
            _ = await musicProvider.perform(command)
            let state = await musicProvider.playbackSnapshot()
            guard let self else { return }
            self.displayMusicState(state)
            self.musicControls?.setCommandInProgress(false)
        }
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
        let musicHeight = musicControls?.isHidden == false ? MusicControlsView.height : 0
        let controlsHeight = debugHeight + musicHeight
        controlsBackdrop?.frame = NSRect(x: 0, y: 0, width: 208, height: controlsHeight)
        controlsBackdrop?.isHidden = controlsHeight == 0
        let delta = controlsHeight - petView.frame.minY
        var frame = panel.frame
        // Grow downwards so the pet keeps its position on screen.
        frame.origin.y -= delta
        frame.size.height += delta
        panel.setFrame(frame, display: false)
        petView.setFrameOrigin(NSPoint(x: 0, y: controlsHeight))
        emotionPicker?.isHidden = !isDebugMenuEnabled
        musicControls?.setFrameOrigin(NSPoint(x: 0, y: debugHeight))
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

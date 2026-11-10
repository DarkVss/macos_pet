import AppKit

@MainActor
final class MusicControlsView: NSView {
    static let height: CGFloat = 64
    var onCommand: ((MusicPlaybackCommand) -> Void)?
    private var buttons: [NSButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        let label = NSTextField(labelWithString: "Музыка")
        label.frame = NSRect(x: 8, y: 42, width: 192, height: 18)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        addSubview(label)
        let symbols = ["backward.end.fill", "play.fill", "forward.end.fill"]
        let titles = ["Предыдущий трек", "Воспроизвести", "Следующий трек"]
        for command in MusicPlaybackCommand.allCases {
            let index = command.rawValue
            let button = NSButton(image: NSImage(systemSymbolName: symbols[index], accessibilityDescription: titles[index])!,
                                  target: self, action: #selector(selectCommand(_:)))
            button.frame = NSRect(x: 30 + CGFloat(index) * 52, y: 8, width: 44, height: 28)
            button.bezelStyle = .rounded
            button.imagePosition = .imageOnly
            button.tag = index
            button.toolTip = titles[index]
            button.setAccessibilityLabel(titles[index])
            addSubview(button)
            buttons.append(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is unsupported")
    }

    func display(_ state: MusicPlaybackState) {
        isHidden = state != .playing && state != .paused
        let title = state == .playing ? "Пауза" : "Воспроизвести"
        let button = buttons[MusicPlaybackCommand.togglePlayPause.rawValue]
        button.image = NSImage(systemSymbolName: state == .playing ? "pause.fill" : "play.fill",
                               accessibilityDescription: title)
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }

    func setCommandInProgress(_ inProgress: Bool) {
        for button in buttons { button.isEnabled = !inProgress }
    }

    @objc private func selectCommand(_ sender: NSButton) {
        guard let command = MusicPlaybackCommand(rawValue: sender.tag) else { return }
        onCommand?(command)
    }
}

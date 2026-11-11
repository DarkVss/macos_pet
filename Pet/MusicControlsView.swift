import AppKit
import QuartzCore

@MainActor
final class MusicControlsView: NSView {
    static let height: CGFloat = 86
    var onCommand: ((MusicPlaybackCommand) -> Void)?
    private var buttons: [NSButton] = []
    private let artistLine = MarqueeTextView(font: .systemFont(ofSize: 12, weight: .medium))
    private let titleLine = MarqueeTextView(font: .systemFont(ofSize: 13))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        artistLine.frame = NSRect(x: 8, y: 62, width: 192, height: 18)
        titleLine.frame = NSRect(x: 8, y: 42, width: 192, height: 18)
        addSubview(artistLine)
        addSubview(titleLine)
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

    func display(_ snapshot: MusicPlaybackSnapshot) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let state = snapshot.state
        isHidden = state != .playing && state != .paused
        artistLine.setText(snapshot.artist.isEmpty ? "Неизвестный исполнитель" : snapshot.artist)
        titleLine.setText(snapshot.title.isEmpty ? "Без названия" : snapshot.title)
        artistLine.setActive(!isHidden)
        titleLine.setActive(!isHidden)
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

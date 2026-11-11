import AppKit

/// A consistent contrast surface independent of the desktop or windows behind it.
@MainActor
final class ControlsBackdropView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 0.60).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is unsupported")
    }
}

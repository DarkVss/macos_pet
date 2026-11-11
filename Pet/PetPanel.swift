import AppKit

/// The window is the shared outer container for the pet and its companion views.
/// Keep new elements inside its content bounds and resize the window to fit them.
@MainActor
final class PetPanel: NSPanel {
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        let correction = ScreenDragConstraint.translation(
            of: frameRect, toward: .zero, screens: NSScreen.screens.map(\.frame)
        )
        super.setFrame(frameRect.offsetBy(dx: correction.x, dy: correction.y), display: flag)
    }
}

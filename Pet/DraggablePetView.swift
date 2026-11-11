import AppKit

final class DraggablePetView: NSView {
    var onDrag: ((Double) -> Void)?
    var onDragEnded: (() -> Void)?
    private var dragOrigin: (mouse: NSPoint, window: NSPoint)?
    private var directionAnchorX: CGFloat = 0

    // Route pointer events through the shared desktop interaction layer.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        dragOrigin = (mouse, window.frame.origin)
        directionAnchorX = mouse.x
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let origin = dragOrigin else { return }
        let mouse = NSEvent.mouseLocation
        let desiredOrigin = NSPoint(x: origin.window.x + mouse.x - origin.mouse.x,
                                    y: origin.window.y + mouse.y - origin.mouse.y)
        let movement = ScreenDragConstraint.translation(
            of: window.frame,
            toward: CGPoint(x: desiredOrigin.x - window.frame.minX,
                            y: desiredOrigin.y - window.frame.minY),
            screens: NSScreen.screens.map(\.frame)
        )
        window.setFrameOrigin(NSPoint(x: window.frame.minX + movement.x,
                                      y: window.frame.minY + movement.y))
        let distance = mouse.x - directionAnchorX
        if abs(distance) >= 2 {
            onDrag?(Double(distance))
            directionAnchorX = mouse.x
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        onDragEnded?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

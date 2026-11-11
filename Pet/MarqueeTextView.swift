import AppKit
import QuartzCore

/// Centers fitting text; scrolls overflowing text inside a fixed clipped viewport.
@MainActor
final class MarqueeTextView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let font: NSFont
    private var text = ""
    private var active = false
    private var viewportWidth: CGFloat = -1
    private var textWidth: CGFloat = 0

    init(font: NSFont) {
        self.font = font
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        label.font = font
        label.maximumNumberOfLines = 1
        label.cell?.lineBreakMode = .byClipping
        label.wantsLayer = true
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is unsupported")
    }

    func setText(_ value: String) {
        guard text != value else { return }
        text = value
        label.stringValue = value
        toolTip = value
        textWidth = ceil((value as NSString).size(withAttributes: [.font: font]).width) + 4
        viewportWidth = -1
        updateTextLayout()
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        updateAnimation()
    }

    override func layout() {
        super.layout()
        updateTextLayout()
    }

    private func updateTextLayout() {
        guard viewportWidth != bounds.width else { return }
        viewportWidth = bounds.width
        let overflow = textWidth > bounds.width
        label.alignment = overflow ? .left : .center
        label.frame = NSRect(x: 0, y: 0, width: max(bounds.width, textWidth), height: bounds.height)
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    private func updateAnimation() {
        label.layer?.removeAnimation(forKey: "marquee")
        let overflow = textWidth - bounds.width
        guard active, window != nil, bounds.width > 0, overflow > 0 else { return }
        let pause: Double = 1.2
        let travel = max(0.5, Double(overflow) / 25)
        let duration = 2 * (pause + travel)
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, 0, -overflow, -overflow, 0]
        animation.keyTimes = [0, NSNumber(value: pause / duration),
                              NSNumber(value: (pause + travel) / duration),
                              NSNumber(value: (2 * pause + travel) / duration), 1]
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        label.layer?.add(animation, forKey: "marquee")
    }
}

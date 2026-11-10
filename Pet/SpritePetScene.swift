import AppKit
import SpriteKit

/// Fixed cells preserve scale, ground contact, and intentional jump height.
@MainActor
final class SpritePetScene: SKScene, PetRendering {
    private let avatar: SpriteAvatar
    private var textureCache: [String: [SKTexture]] = [:]
    private let pet = SKSpriteNode()
    private var frames: [SKTexture] = []
    private var frameDuration: TimeInterval = 0.1
    private var cyclePause: TimeInterval = 0
    private var animationStart: TimeInterval?
    private var currentFrame = -1
    private var playbackFPS = 30

    init(size: CGSize, avatar: SpriteAvatar) throws {
        self.avatar = avatar
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        let scale = min(192 / Double(avatar.manifest.frameWidth), 208 / Double(avatar.manifest.frameHeight))
        pet.size = CGSize(width: Double(avatar.manifest.frameWidth) * scale,
                          height: Double(avatar.manifest.frameHeight) * scale)
        if let initial = avatar.manifest.animations[PetState.Activity.waiting.rawValue] {
            _ = try textures(for: initial)
        }
        addChild(pet)
        positionPet()
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is unsupported")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        positionPet()
    }

    private func positionPet() {
        pet.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = playbackFPS
    }

    private func textures(for sheet: SpriteAvatar.Sheet) throws -> [SKTexture] {
        if let cached = textureCache[sheet.file] { return cached }
        let image = try avatar.image(for: sheet)
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        let width = CGFloat(avatar.manifest.frameWidth) / CGFloat(image.width)
        let height = CGFloat(avatar.manifest.frameHeight) / CGFloat(image.height)
        let frames = (0..<sheet.frameCount).map { index in
            // Package rows run top-to-bottom; SpriteKit coordinates run upwards.
            let rect = CGRect(x: CGFloat(index % sheet.columns) * width,
                              y: 1 - CGFloat(index / sheet.columns + 1) * height,
                              width: width, height: height)
            let frame = SKTexture(rect: rect, in: texture)
            frame.filteringMode = .linear
            return frame
        }
        textureCache[sheet.file] = frames
        return frames
    }

    func display(_ state: PetState) {
        let clip: SpriteAvatar.Sheet
        do {
            if let direction = state.lookDirection, let gaze = avatar.manifest.gaze,
               (0..<gaze.frameCount).contains(direction) {
                clip = gaze
                frames = [try textures(for: gaze)[direction]]
            } else {
                guard let animation = avatar.manifest.animations[state.activity.rawValue] else { return }
                clip = animation
                frames = try textures(for: animation)
            }
        } catch {
            NSLog("Avatar presentation failed: %@", error.localizedDescription)
            return
        }
        frameDuration = 1 / clip.fps
        cyclePause = clip.pause
        animationStart = nil
        currentFrame = 0
        pet.texture = frames.first
        playbackFPS = frames.count == 1 ? 1 : Int(ceil(clip.fps))
        view?.preferredFramesPerSecond = playbackFPS
    }

    override func update(_ currentTime: TimeInterval) {
        guard frames.count > 1 else { return }
        if animationStart == nil { animationStart = currentTime }
        let duration = Double(frames.count) * frameDuration
        let elapsed = (currentTime - (animationStart ?? currentTime))
            .truncatingRemainder(dividingBy: duration + cyclePause)
        let index = elapsed >= duration ? 0 : min(Int(elapsed / frameDuration), frames.count - 1)
        guard index != currentFrame else { return }
        currentFrame = index

        pet.texture = frames[index]
    }
}

final class DraggablePetView: SKView {
    var onDrag: ((Double) -> Void)?
    var onDragEnded: (() -> Void)?
    private var dragOrigin: (mouse: NSPoint, window: NSPoint)?
    private var directionAnchorX: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        dragOrigin = (mouse, window.frame.origin)
        directionAnchorX = mouse.x
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let origin = dragOrigin else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: origin.window.x + mouse.x - origin.mouse.x,
                                      y: origin.window.y + mouse.y - origin.mouse.y))
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

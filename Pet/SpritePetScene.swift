import AppKit
import SpriteKit

/// Fixed cells preserve scale, ground contact, and intentional jump height.
@MainActor
final class SpritePetScene: SKScene, PetRendering {
    private let avatar: SpriteAvatar
    private var textureCache: [String: [SKTexture]] = [:]
    private let pet = SKSpriteNode()
    private let petShadow = SKSpriteNode()
    private let shadowEffect = SKEffectNode()
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
        petShadow.color = .black
        petShadow.colorBlendFactor = 1
        petShadow.alpha = 0.45
        shadowEffect.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 2.5])
        shadowEffect.zPosition = -1
        shadowEffect.addChild(petShadow)
        addChild(shadowEffect)
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
        let scale = min(size.width / 208, size.height / 224)
        pet.size = CGSize(width: 192 * scale, height: 208 * scale)
        petShadow.size = pet.size
        pet.position = CGPoint(x: size.width / 2, y: size.height / 2)
        petShadow.position = CGPoint(x: pet.position.x, y: pet.position.y - 2 * scale)
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
        shadowEffect.shouldRasterize = frames.count == 1
        setPose(frames.first)
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

        setPose(frames[index])
    }

    private func setPose(_ texture: SKTexture?) {
        pet.texture = texture
        petShadow.texture = texture
    }
}

import AppKit
import SceneKit
import QuartzCore

@MainActor
final class ModelPetRenderer: PetRendering {
    let view: SCNView
    let supportedActivities: Set<PetState.Activity> = [.waiting, .walkingRight, .walkingLeft]
    private let avatar: GLBAvatar
    private let turntable = SCNNode()
    private var displayedState: PetState?

    init(frame: NSRect, url: URL) throws {
        avatar = try GLBAvatar(url: url)
        guard avatar.clips["Running"] != nil else {
            throw GLBAvatar.InvalidModel(reason: "нет анимации Running")
        }
        view = SCNView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        turntable.addChildNode(avatar.root)
        scene.rootNode.addChildNode(turntable)
        let (min, max) = avatar.root.boundingBox
        let height = max.y - min.y
        guard height > 0, height.isFinite else { throw GLBAvatar.InvalidModel(reason: "размер модели") }
        avatar.root.position = SCNVector3(-(min.x + max.x) / 2, -(min.y + max.y) / 2, -(min.z + max.z) / 2)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = Double(height) * 0.59
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = Double(height) * 10
        camera.position = SCNVector3(0, 0, height * 3)
        scene.rootNode.addChildNode(camera)
        view.scene = scene
        view.pointOfView = camera
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = false
        view.isPlaying = false
        view.allowsCameraControl = false
    }

    func display(_ state: PetState) {
        guard state != displayedState else { return }
        displayedState = state
        avatar.restorePose()
        let running = state.activity == .walkingRight || state.activity == .walkingLeft
        // Turn 30 degrees toward the viewer from a full side profile.
        turntable.eulerAngles.y = running ? (state.activity == .walkingRight ? .pi / 3 : -.pi / 3) : 0
        if running {
            play("Running")
        } else {
            avatar.applyFirstPose(of: "IdlePose")
            play("TailIdle")
            play("IdleEars", delay: 5)
            play("IdleGesture", delay: 10)
        }
        view.isPlaying = true
        view.rendersContinuously = true
        view.needsDisplay = true
    }

    private func play(_ clipName: String, delay: TimeInterval = 0) {
        guard let clip = avatar.clips[clipName] else { return }
        let grouped = Dictionary(grouping: clip.channels, by: { ObjectIdentifier($0.node) })
        for channels in grouped.values {
            let animations: [CAAnimation] = channels.map { channel in
                let rotation = channel.path == "rotation"
                let width = rotation ? 4 : 3
                let animation = CAKeyframeAnimation(keyPath: rotation ? "orientation" : (channel.path == "scale" ? "scale" : "position"))
                animation.values = stride(from: 0, to: channel.values.count, by: width).map { index -> NSValue in
                    let v = channel.values
                    if rotation { return NSValue(scnVector4: SCNVector4(v[index], v[index + 1], v[index + 2], v[index + 3])) }
                    return NSValue(scnVector3: SCNVector3(v[index], v[index + 1], v[index + 2]))
                }
                animation.keyTimes = channel.times.map { NSNumber(value: Double($0) / clip.duration) }
                animation.duration = clip.duration
                animation.calculationMode = .linear
                return animation
            }
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = clip.duration
            group.repeatCount = .greatestFiniteMagnitude
            let animation = SCNAnimation(caAnimation: group)
            animation.startDelay = delay
            channels[0].node.addAnimation(animation, forKey: "activity-" + clipName)
        }
    }

}

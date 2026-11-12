import AppKit
import SceneKit
import QuartzCore

@MainActor
final class ModelPetRenderer: PetRendering {
    let view: SCNView
    let supportedActivities: Set<PetState.Activity> = [.waiting, .walkingRight, .walkingLeft, .listeningToMusic]
    private let avatar: GLBAvatar
    private let turntable = SCNNode()
    private let musicProp = SCNNode()
    private var standingPosition = SCNVector3Zero
    private var floorY: CGFloat = 0
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
        standingPosition = avatar.root.position
        floorY = -height / 2 + 0.005
        makeMusicProp()
        musicProp.position = SCNVector3(-0.65, -height / 2 + 0.12, 0.65)
        musicProp.isHidden = true
        scene.rootNode.addChildNode(musicProp)

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
        let music = state.activity == .listeningToMusic
        musicProp.isHidden = !music
        // Align the supporting forearm with the floor, independently of the hair silhouette.
        avatar.root.position = music ? SCNVector3(0.96, floorY + 0.317, -0.07) : standingPosition
        let running = state.activity == .walkingRight || state.activity == .walkingLeft
        // Turn 30 degrees toward the viewer from a full side profile.
        turntable.eulerAngles.y = running ? (state.activity == .walkingRight ? .pi / 3 : -.pi / 3) : 0
        if running {
            play("Running")
        } else if music {
            avatar.applyFirstPose(of: "ListeningToMusic")
            play("ListeningToMusic")
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

    private func makeMusicProp() {
        musicProp.name = "MusicRadio"
        func material(_ color: NSColor) -> SCNMaterial {
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = color
            return m
        }
        func box(_ size: SCNVector3, _ position: SCNVector3, _ color: NSColor) {
            let geometry = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0.015)
            geometry.materials = [material(color)]
            let node = SCNNode(geometry: geometry); node.position = position; musicProp.addChildNode(node)
        }
        let pink = NSColor(calibratedRed: 0.87, green: 0.40, blue: 0.65, alpha: 1)
        let dark = NSColor(calibratedRed: 0.19, green: 0.16, blue: 0.25, alpha: 1)
        box(SCNVector3(0.37, 0.23, 0.14), SCNVector3Zero, pink)
        box(SCNVector3(0.24, 0.025, 0.035), SCNVector3(0, 0.18, 0), pink)
        for x: Float in [-0.11, 0.11] {
            box(SCNVector3(0.025, 0.07, 0.035), SCNVector3(x, 0.145, 0), pink)
            let ring = SCNCylinder(radius: 0.071, height: 0.012)
            ring.materials = [material(x < 0 ? .systemCyan : .systemPink)]
            let speaker = SCNNode(geometry: ring); speaker.position = SCNVector3(x, -0.015, 0.08)
            speaker.eulerAngles.x = .pi / 2; musicProp.addChildNode(speaker)
            let cone = SCNCylinder(radius: 0.052, height: 0.014)
            cone.materials = [material(dark)]
            let inset = SCNNode(geometry: cone); inset.position = SCNVector3(x, -0.015, 0.09)
            inset.eulerAngles.x = .pi / 2; musicProp.addChildNode(inset)
        }
        box(SCNVector3(0.07, 0.035, 0.012), SCNVector3(0, 0.055, 0.078), .systemCyan)
        for (i, x) in [Float(-0.10), 0.12].enumerated() {
            let text = SCNText(string: i == 0 ? "♪" : "♫", extrusionDepth: 0)
            text.font = NSFont.systemFont(ofSize: 1)
            text.materials = [material(i == 0 ? .systemPink : .systemCyan)]
            let note = SCNNode(geometry: text); note.scale = SCNVector3(0.13, 0.13, 0.13)
            note.position = SCNVector3(x, 0.25 + Float(i) * 0.10, 0.03)
            let up = SCNAction.moveBy(x: 0.025, y: 0.06, z: 0, duration: 1)
            up.timingMode = .easeInEaseOut
            note.runAction(.repeatForever(.sequence([up, up.reversed()])))
            musicProp.addChildNode(note)
        }
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

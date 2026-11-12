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
        avatar.root.position = standingPosition
        let running = state.activity == .walkingRight || state.activity == .walkingLeft
        // Turn 30 degrees toward the viewer from a full side profile.
        turntable.eulerAngles.y = running ? (state.activity == .walkingRight ? .pi / 3 : -.pi / 3) : 0
        if running {
            play("Running")
        } else if music {
            avatar.applyFirstPose(of: "MusicSequence")
            play("MusicSequence")
            avatar.playMusicEyes()
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
        let radio = SCNNode()
        radio.eulerAngles = SCNVector3(-0.08, -0.20, 0)
        musicProp.addChildNode(radio)
        func add(_ geometry: SCNGeometry, _ position: SCNVector3, _ color: NSColor) -> SCNNode {
            geometry.materials = [material(color)]
            let node = SCNNode(geometry: geometry)
            node.position = position
            radio.addChildNode(node)
            return node
        }
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
            NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
        }
        func box(_ size: SCNVector3, _ position: SCNVector3, _ color: NSColor, radius: CGFloat = 0.01) {
            let geometry = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: radius)
            geometry.chamferSegmentCount = 6
            _ = add(geometry, position, color)
        }
        func disc(_ radius: CGFloat, _ depth: CGFloat, _ position: SCNVector3, _ color: NSColor) {
            let geometry = SCNCylinder(radius: radius, height: depth)
            geometry.radialSegmentCount = 48
            let node = add(geometry, position, color)
            node.eulerAngles.x = .pi / 2
        }
        func ring(_ radius: CGFloat, _ thickness: CGFloat, _ position: SCNVector3, _ color: NSColor) {
            let geometry = SCNTorus(ringRadius: radius, pipeRadius: thickness)
            geometry.ringSegmentCount = 48
            geometry.pipeSegmentCount = 12
            let node = add(geometry, position, color)
            node.eulerAngles.x = .pi / 2
        }
        let pink = color(0.77, 0.37, 0.57)
        let silver = color(0.85, 0.80, 0.84)
        let pale = color(1, 0.86, 0.94)
        let dark = color(0.22, 0.17, 0.27)
        // Rounded shell, inset fascia and a darker underside give the radio depth
        // without adding lighting that would change Kinako's textured appearance.
        box(SCNVector3(0.38, 0.235, 0.18), SCNVector3Zero, color(0.56, 0.29, 0.44), radius: 0.06)
        box(SCNVector3(0.366, 0.22, 0.15), SCNVector3(0, 0.006, 0.018), silver, radius: 0.055)
        box(SCNVector3(0.345, 0.199, 0.09), SCNVector3(0, 0.004, 0.065), pink, radius: 0.043)
        box(SCNVector3(0.31, 0.012, 0.012), SCNVector3(0, -0.086, 0.107), color(0.94, 0.59, 0.75), radius: 0.005)
        // An actual opening in the carry handle, rather than a square frame.
        let handle = NSBezierPath(roundedRect: NSRect(x: -0.12, y: 0.10, width: 0.24, height: 0.13), xRadius: 0.045, yRadius: 0.045)
        let opening = NSBezierPath(roundedRect: NSRect(x: -0.092, y: 0.103, width: 0.184, height: 0.098), xRadius: 0.026, yRadius: 0.026)
        handle.append(opening.reversed)
        handle.flatness = 0.0005
        let handleShape = SCNShape(path: handle, extrusionDepth: 0.025)
        handleShape.chamferRadius = 0.005
        _ = add(handleShape, SCNVector3(0, 0, -0.025), color(0.65, 0.36, 0.51))
        for (i, x) in [CGFloat(-0.108), 0.108].enumerated() {
            let accent = i == 0 ? color(0.40, 0.91, 0.96) : color(1, 0.61, 0.87)
            disc(0.077, 0.014, SCNVector3(x, -0.012, 0.113), dark)
            ring(0.067, 0.009, SCNVector3(x, -0.012, 0.126), silver)
            ring(0.056, 0.006, SCNVector3(x, -0.012, 0.135), accent)
            disc(0.048, 0.010, SCNVector3(x, -0.012, 0.136), color(0.39, 0.30, 0.43))
            disc(0.034, 0.012, SCNVector3(x, -0.012, 0.143), color(0.29, 0.23, 0.33))
            disc(0.017, 0.014, SCNVector3(x, -0.012, 0.151), color(0.51, 0.41, 0.53))
            // A small highlight keeps the rim readable at the normal desktop size.
            let highlight = SCNSphere(radius: 0.006)
            _ = add(highlight, SCNVector3(x - 0.038, 0.033, 0.141), pale)
        }
        box(SCNVector3(0.093, 0.048, 0.014), SCNVector3(0, 0.064, 0.115), pale, radius: 0.009)
        box(SCNVector3(0.076, 0.029, 0.012), SCNVector3(0, 0.065, 0.125), dark, radius: 0.005)
        for x: CGFloat in [-0.025, -0.013, 0, 0.013, 0.025] {
            box(SCNVector3(0.005, 0.009 + abs(x) * 0.3, 0.003), SCNVector3(x, 0.065, 0.133), color(0.55, 0.91, 0.90), radius: 0.001)
        }
        box(SCNVector3(0.065, 0.036, 0.012), SCNVector3(0, -0.005, 0.119), color(0.64, 0.36, 0.51), radius: 0.006)
        for x: CGFloat in [-0.016, 0.016] {
            disc(0.008, 0.006, SCNVector3(x, -0.005, 0.129), silver)
        }
        for x: CGFloat in [-0.047, 0, 0.047] {
            box(SCNVector3(0.032, 0.016, 0.036), SCNVector3(x, 0.123, 0.047), pale, radius: 0.006)
        }
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

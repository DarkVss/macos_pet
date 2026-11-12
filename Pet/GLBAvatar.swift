import AppKit
import SceneKit
import simd

/// Loader for the bundled Meshy glTF 2.0 export, not a general user-import API.
/// Unsupported encodings fail explicitly rather than producing a partial avatar.
@MainActor
final class GLBAvatar {
    struct InvalidModel: LocalizedError {
        let reason: String
        var errorDescription: String? { "Не удалось прочитать 3D-аватар: \(reason)" }
    }

    struct Channel {
        let node: SCNNode
        let path: String
        let times: [Float]
        let values: [Float]
    }

    struct Clip {
        let duration: Double
        let channels: [Channel]
    }

    let root = SCNNode()
    private(set) var clips: [String: Clip] = [:]
    private(set) var nodes: [SCNNode] = []
    private var restTransforms: [simd_float4x4] = []
    private var eyeMorphers: [SCNMorpher] = []
    private let document: Document
    private let binary: Data
    private var images: [Int: NSImage] = [:]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        func word(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset + 4 <= data.count else { throw InvalidModel(reason: "обрезанный GLB") }
            return data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
        }
        let magic = try word(0)
        let version = try word(4)
        let length = try word(8)
        guard magic == 0x46546c67, version == 2, Int(length) == data.count else {
            throw InvalidModel(reason: "заголовок GLB")
        }
        var offset = 12
        var json: Data?
        var buffer: Data?
        while offset < data.count {
            let length = Int(try word(offset))
            let type = try word(offset + 4)
            offset += 8
            guard length <= data.count - offset else { throw InvalidModel(reason: "размер блока GLB") }
            let chunk = data.subdata(in: offset..<(offset + length))
            if type == 0x4e4f534a { json = chunk }
            if type == 0x004e4942 { buffer = chunk }
            offset += length
        }
        guard let json, let buffer else { throw InvalidModel(reason: "нет JSON или BIN") }
        document = try JSONDecoder().decode(Document.self, from: json)
        binary = buffer
        guard document.asset.version == "2.0", document.extensionsRequired?.isEmpty != false else {
            throw InvalidModel(reason: "неподдерживаемое расширение glTF")
        }
        try build()
    }

    func restorePose() {
        for morpher in eyeMorphers { morpher.removeAllAnimations() }
        setEyesClosed(false)
        for (node, transform) in zip(nodes, restTransforms) {
            node.removeAllAnimations()
            node.simdTransform = transform
        }
    }

    func applyFirstPose(of clipName: String) {
        guard let clip = clips[clipName] else { return }
        for channel in clip.channels {
            let v = channel.values
            switch channel.path {
            case "rotation": channel.node.simdOrientation = simd_quatf(vector: SIMD4(v[0], v[1], v[2], v[3]))
            case "translation": channel.node.simdPosition = SIMD3(v[0], v[1], v[2])
            case "scale": channel.node.simdScale = SIMD3(v[0], v[1], v[2])
            default: break
            }
        }
    }

    func setEyesClosed(_ closed: Bool) {
        for morpher in eyeMorphers { morpher.setWeight(closed ? 1 : 0, forTargetAt: 0) }
    }

    func playMusicEyes() {
        setEyesClosed(true)
        for morpher in eyeMorphers {
            let animation = CAKeyframeAnimation(keyPath: "weights[0]")
            animation.values = [1, 1, 0, 0, 1]
            animation.keyTimes = [0, 5.0 / 23.8, 6.8 / 23.8, 22.0 / 23.8, 1].map { NSNumber(value: $0) }
            animation.duration = 23.8
            animation.repeatCount = .greatestFiniteMagnitude
            morpher.addAnimation(animation, forKey: "music-eyes")
        }
    }

    private func build() throws {
        nodes = document.nodes.map { item in
            let node = SCNNode()
            node.name = item.name
            if let m = item.matrix, m.count == 16 {
                node.simdTransform = matrix(m)
            } else {
                if let t = item.translation, t.count == 3 { node.simdPosition = SIMD3(t[0], t[1], t[2]) }
                if let r = item.rotation, r.count == 4 { node.simdOrientation = simd_quatf(vector: SIMD4(r[0], r[1], r[2], r[3])) }
                if let s = item.scale, s.count == 3 { node.simdScale = SIMD3(s[0], s[1], s[2]) }
            }
            return node
        }
        for (index, item) in document.nodes.enumerated() {
            for child in item.children ?? [] {
                guard nodes.indices.contains(child), nodes[child].parent == nil, child != index else {
                    throw InvalidModel(reason: "иерархия узлов")
                }
                nodes[index].addChildNode(nodes[child])
            }
        }
        guard document.scenes.indices.contains(document.scene ?? 0) else { throw InvalidModel(reason: "нет сцены") }
        for index in document.scenes[document.scene ?? 0].nodes {
            guard nodes.indices.contains(index) else { throw InvalidModel(reason: "корень сцены") }
            root.addChildNode(nodes[index])
        }
        for (index, item) in document.nodes.enumerated() {
            guard let meshIndex = item.mesh else { continue }
            guard document.meshes.indices.contains(meshIndex) else { throw InvalidModel(reason: "индекс сетки") }
            for primitive in document.meshes[meshIndex].primitives {
                guard primitive.mode == nil || primitive.mode == 4,
                      let position = primitive.attributes["POSITION"],
                      let normal = primitive.attributes["NORMAL"],
                      let uv = primitive.attributes["TEXCOORD_0"],
                      let indices = primitive.indices else { throw InvalidModel(reason: "формат сетки") }
                let positions = try source(position, semantic: .vertex, components: 3, float: true)
                let normals = try source(normal, semantic: .normal, components: 3, float: true)
                let texcoords = try source(uv, semantic: .texcoord, components: 2, float: true)
                let (indexData, accessor) = try packed(indices)
                guard accessor.type == "SCALAR", [5121, 5123, 5125].contains(accessor.componentType), accessor.count % 3 == 0 else {
                    throw InvalidModel(reason: "индексы треугольников")
                }
                let element = SCNGeometryElement(data: indexData, primitiveType: .triangles,
                                                primitiveCount: accessor.count / 3, bytesPerIndex: try componentSize(accessor.componentType))
                let geometry = SCNGeometry(sources: [positions, normals, texcoords], elements: [element])
                geometry.firstMaterial = try material(primitive.material)
                let meshNode = SCNNode(geometry: geometry)
                if document.meshes[meshIndex].extras?.targetNames == ["ClosedEyes"],
                   let target = primitive.targets?.first?["POSITION"] {
                    let base = try floats(position)
                    let delta = try floats(target)
                    guard base.count == delta.count else { throw InvalidModel(reason: "форма век") }
                    let vertices = stride(from: 0, to: base.count, by: 3).map { i in
                        SCNVector3(base[i] + delta[i], base[i+1] + delta[i+1], base[i+2] + delta[i+2])
                    }
                    let morpher = SCNMorpher()
                    morpher.targets = [SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [element])]
                    morpher.calculationMode = .normalized
                    meshNode.morpher = morpher
                    eyeMorphers.append(morpher)
                }
                nodes[index].addChildNode(meshNode)
                if let skinIndex = item.skin {
                    guard document.skins.indices.contains(skinIndex),
                          let weights = primitive.attributes["WEIGHTS_0"], let joints = primitive.attributes["JOINTS_0"] else {
                        throw InvalidModel(reason: "нет данных скелета")
                    }
                    let skin = document.skins[skinIndex]
                    guard skin.joints.allSatisfy({ nodes.indices.contains($0) }) else { throw InvalidModel(reason: "индекс кости") }
                    let inverse = try floats(skin.inverseBindMatrices)
                    guard inverse.count == skin.joints.count * 16 else { throw InvalidModel(reason: "матрицы скелета") }
                    let transforms = stride(from: 0, to: inverse.count, by: 16).map {
                        NSValue(scnMatrix4: SCNMatrix4(matrix(Array(inverse[$0..<($0 + 16)]))))
                    }
                    meshNode.skinner = SCNSkinner(baseGeometry: geometry, bones: skin.joints.map { nodes[$0] },
                                                 boneInverseBindTransforms: transforms,
                                                 boneWeights: try source(weights, semantic: .boneWeights, components: 4, float: true),
                                                 boneIndices: try source(joints, semantic: .boneIndices, components: 4, float: false))
                }
            }
        }
        restTransforms = nodes.map(\.simdTransform)
        for animation in document.animations {
            var channels: [Channel] = []
            var duration: Float = 0
            for channel in animation.channels {
                guard animation.samplers.indices.contains(channel.sampler), nodes.indices.contains(channel.target.node),
                      ["translation", "rotation", "scale"].contains(channel.target.path) else {
                    throw InvalidModel(reason: "канал анимации")
                }
                let sampler = animation.samplers[channel.sampler]
                guard sampler.interpolation == nil || sampler.interpolation == "LINEAR" else { throw InvalidModel(reason: "интерполяция анимации") }
                let times = try floats(sampler.input)
                let values = try floats(sampler.output)
                let width = channel.target.path == "rotation" ? 4 : 3
                guard times.count > 1, times.first == 0, zip(times, times.dropFirst()).allSatisfy({ $0 < $1 }),
                      values.count == times.count * width else { throw InvalidModel(reason: "ключи анимации") }
                duration = max(duration, times.last ?? 0)
                channels.append(Channel(node: nodes[channel.target.node], path: channel.target.path, times: times, values: values))
            }
            clips[animation.name] = Clip(duration: Double(duration), channels: channels)
        }
    }

    private func material(_ index: Int?) throws -> SCNMaterial {
        guard let index, document.materials.indices.contains(index) else { throw InvalidModel(reason: "материал") }
        let item = document.materials[index]
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = item.doubleSided ?? false
        let pbr = item.pbrMetallicRoughness
        if let texture = pbr.baseColorTexture { material.diffuse.contents = try image(texture.index) }
        // The generated base color already contains stylized shading. Unlit presentation
        // keeps it readable at desktop-pet size and avoids PBR overexposure.
        return material
    }

    private func image(_ index: Int) throws -> NSImage {
        guard document.textures.indices.contains(index) else { throw InvalidModel(reason: "индекс текстуры") }
        let source = document.textures[index].source
        if let image = images[source] { return image }
        guard document.images.indices.contains(source), let view = document.images[source].bufferView,
              let image = NSImage(data: try bytes(view)) else { throw InvalidModel(reason: "встроенная текстура") }
        images[source] = image
        return image
    }

    private func bytes(_ index: Int) throws -> Data {
        guard document.bufferViews.indices.contains(index) else { throw InvalidModel(reason: "bufferView") }
        let view = document.bufferViews[index]
        let offset = view.byteOffset ?? 0
        guard view.buffer == 0, offset >= 0, view.byteLength >= 0,
              offset <= binary.count, view.byteLength <= binary.count - offset else { throw InvalidModel(reason: "границы BIN") }
        return binary.subdata(in: offset..<(offset + view.byteLength))
    }

    private func packed(_ index: Int) throws -> (Data, Accessor) {
        guard document.accessors.indices.contains(index) else { throw InvalidModel(reason: "accessor") }
        let a = document.accessors[index]
        guard a.sparse == nil, a.normalized != true else { throw InvalidModel(reason: "sparse/normalized accessor") }
        let data = try bytes(a.bufferView)
        let widths = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16]
        guard let width = widths[a.type], a.count > 0 else { throw InvalidModel(reason: "тип accessor") }
        let size = try componentSize(a.componentType) * width
        let stride = document.bufferViews[a.bufferView].byteStride ?? size
        let offset = a.byteOffset ?? 0
        guard offset >= 0, stride >= size, data.count >= offset + size,
              a.count <= (data.count - offset - size) / stride + 1 else { throw InvalidModel(reason: "границы accessor") }
        var result = Data(capacity: a.count * size)
        for i in 0..<a.count { result.append(data[(offset + i * stride)..<(offset + i * stride + size)]) }
        return (result, a)
    }

    private func source(_ index: Int, semantic: SCNGeometrySource.Semantic, components: Int, float: Bool) throws -> SCNGeometrySource {
        let (data, a) = try packed(index)
        guard a.type == "VEC\(components)", float ? a.componentType == 5126 : [5121, 5123].contains(a.componentType) else {
            throw InvalidModel(reason: "формат \(semantic.rawValue)")
        }
        let size = try componentSize(a.componentType)
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: a.count, usesFloatComponents: float,
                                 componentsPerVector: components, bytesPerComponent: size, dataOffset: 0, dataStride: components * size)
    }

    private func floats(_ index: Int) throws -> [Float] {
        let (data, a) = try packed(index)
        guard a.componentType == 5126 else { throw InvalidModel(reason: "ожидались float") }
        return data.withUnsafeBytes { buffer in
            stride(from: 0, to: data.count, by: 4).map { Float(bitPattern: UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: $0, as: UInt32.self))) }
        }
    }

    private func componentSize(_ type: Int) throws -> Int {
        switch type {
        case 5121: return 1
        case 5123: return 2
        case 5125, 5126: return 4
        default: throw InvalidModel(reason: "компонент \(type)")
        }
    }

    private func matrix(_ m: [Float]) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
                                SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))
    }

    private struct Document: Decodable {
        struct Asset: Decodable { let version: String }
        struct Scene: Decodable { let nodes: [Int] }
        struct Node: Decodable {
            let name: String?
            let children: [Int]?
            let mesh: Int?
            let skin: Int?
            let matrix: [Float]?
            let translation: [Float]?
            let rotation: [Float]?
            let scale: [Float]?
        }
        struct Mesh: Decodable {
            struct Primitive: Decodable {
                let attributes: [String: Int]; let indices: Int?; let material: Int?; let mode: Int?
                let targets: [[String: Int]]?
            }
            struct Extras: Decodable { let targetNames: [String]? }
            let extras: Extras?
            let primitives: [Primitive]
        }
        struct Skin: Decodable { let joints: [Int]; let inverseBindMatrices: Int }
        struct Animation: Decodable {
            struct Sampler: Decodable { let input: Int; let output: Int; let interpolation: String? }
            struct Channel: Decodable {
                struct Target: Decodable { let node: Int; let path: String }
                let sampler: Int; let target: Target
            }
            let name: String; let samplers: [Sampler]; let channels: [Channel]
        }
        struct Material: Decodable {
            struct Texture: Decodable { let index: Int }
            struct PBR: Decodable {
                let baseColorTexture: Texture?
                let metallicRoughnessTexture: Texture?
                let roughnessFactor: Double?
                let metallicFactor: Double?
            }
            let pbrMetallicRoughness: PBR
            let normalTexture: Texture?
            let doubleSided: Bool?
        }
        struct Texture: Decodable { let source: Int }
        struct Image: Decodable { let bufferView: Int? }
        let asset: Asset
        let extensionsRequired: [String]?
        let scene: Int?
        let scenes: [Scene]
        let nodes: [Node]
        let meshes: [Mesh]
        let skins: [Skin]
        let animations: [Animation]
        let accessors: [Accessor]
        let bufferViews: [BufferView]
        let materials: [Material]
        let textures: [Texture]
        let images: [Image]
    }
    private struct BufferView: Decodable {
        let buffer: Int; let byteOffset: Int?; let byteLength: Int; let byteStride: Int?
    }
    private struct Accessor: Decodable {
        let bufferView: Int; let byteOffset: Int?; let componentType: Int; let count: Int; let type: String
        let normalized: Bool?
        let sparse: Sparse?
        struct Sparse: Decodable {}
    }
}

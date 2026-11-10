import Foundation
import ImageIO

/// An avatar is a directory of data and PNG sheets, independent of Xcode atlases.
/// The same loader can read a bundled avatar or a future extracted ZIP package.
struct SpriteAvatar {
    struct Sheet: Decodable {
        let file: String
        let columns: Int
        let frameCount: Int
        let fps: Double
        let pause: Double
    }

    struct Manifest: Decodable {
        let schemaVersion: Int
        let name: String
        let frameWidth: Int
        let frameHeight: Int
        let animations: [String: Sheet]
        let gaze: Sheet?
    }

    struct InvalidPackage: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    let rootURL: URL
    let manifest: Manifest
    private var images: [String: CGImage] = [:]

    init(rootURL: URL) throws {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let data = try Data(contentsOf: self.rootURL.appendingPathComponent("manifest.json"))
        manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schemaVersion == 1,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...1024).contains(manifest.frameWidth),
              (1...1024).contains(manifest.frameHeight) else {
            throw InvalidPackage(reason: "Неподдерживаемый формат аватара")
        }
        let supportedStates = Set(PetState.Activity.allCases.map(\.rawValue))
        guard Set(manifest.animations.keys) == supportedStates else {
            throw InvalidPackage(reason: "Аватар должен содержать все поддерживаемые состояния")
        }
        for activity in PetState.Activity.allCases {
            guard let sheet = manifest.animations[activity.rawValue] else {
                throw InvalidPackage(reason: "В аватаре отсутствует состояние: \(activity.title)")
            }
            try validate(sheet)
        }
        if let gaze = manifest.gaze {
            guard gaze.frameCount == 16 else {
                throw InvalidPackage(reason: "Для направления взгляда нужны 16 кадров")
            }
            try validate(gaze)
        }
    }

    private mutating func validate(_ sheet: Sheet) throws {
        guard (1...600).contains(sheet.frameCount),
              (1...64).contains(sheet.columns), sheet.columns <= sheet.frameCount,
              sheet.fps.isFinite, (1...60).contains(sheet.fps),
              sheet.pause.isFinite, (0...60).contains(sheet.pause) else {
            throw InvalidPackage(reason: "Некорректные параметры анимации: \(sheet.file)")
        }
        let width = sheet.columns * manifest.frameWidth
        let height = ((sheet.frameCount + sheet.columns - 1) / sheet.columns) * manifest.frameHeight
        guard width <= 8192, height <= 8192, width * height <= 16_777_216 else {
            throw InvalidPackage(reason: "Слишком большой лист спрайтов: \(sheet.file)")
        }
        let image: CGImage
        if let cached = images[sheet.file] {
            image = cached
        } else {
            image = try readImage(for: sheet)
            images[sheet.file] = image
        }
        guard image.width == width, image.height == height else {
            throw InvalidPackage(reason: "Размеры PNG не соответствуют сетке: \(sheet.file)")
        }
    }

    func image(for sheet: Sheet) throws -> CGImage {
        guard let image = images[sheet.file] else {
            throw InvalidPackage(reason: "Лист спрайтов не прошёл проверку: \(sheet.file)")
        }
        return image
    }

    private func readImage(for sheet: Sheet) throws -> CGImage {
        let url = rootURL.appendingPathComponent(sheet.file).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(rootURL.path + "/"), url.pathExtension.lowercased() == "png",
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_777_216,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw InvalidPackage(reason: "Не удалось загрузить PNG аватара: \(sheet.file)")
        }
        return image
    }
}

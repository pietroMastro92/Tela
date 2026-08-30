import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageMetadata: Equatable, Sendable {
    public let uti: String
    public let width: Int
    public let height: Int
    public let byteCount: Int

    public init(uti: String, width: Int, height: Int, byteCount: Int = 0) {
        self.uti = uti
        self.width = width
        self.height = height
        self.byteCount = byteCount
    }
}

public enum ImageImportError: Error, LocalizedError, Equatable {
    case notLocalFile
    case fileMissing
    case unsupportedFormat
    case unreadableImage
    case invalidDimensions
    case dimensionsTooLarge(width: Int, height: Int, maxDimension: Int)
    case unableToCreateDestination
    case unableToEncodeImage

    public var errorDescription: String? {
        switch self {
        case .notLocalFile: return "Only local image files can be imported."
        case .fileMissing: return "The selected image file no longer exists."
        case .unsupportedFormat: return "Tela supports JPEG, PNG, and HEIC images."
        case .unreadableImage: return "The image could not be decoded."
        case .invalidDimensions: return "The image has invalid dimensions."
        case let .dimensionsTooLarge(width, height, maxDimension):
            return "Image dimensions \(width)×\(height) exceed the \(maxDimension)-pixel limit."
        case .unableToCreateDestination: return "Tela could not create its artwork storage directory."
        case .unableToEncodeImage: return "Tela could not write the imported artwork."
        }
    }
}

/// Validates local JPEG/PNG/HEIC files through ImageIO and converts their
/// metadata into an Artwork value.  Pixel buffers are not kept in the timer
/// state; the normalized, app-owned copy can be re-opened by the view layer.
public final class ImageImporter: @unchecked Sendable {
    public let maxDimension: Int
    public let defaultTileCount: Int

    public init(maxDimension: Int = 4096, defaultTileCount: Int = 12) {
        self.maxDimension = max(1, maxDimension)
        self.defaultTileCount = max(1, defaultTileCount)
    }

    public func metadata(for url: URL) throws -> ImageMetadata {
        let info = try sourceMetadata(for: url)
        guard info.width <= maxDimension, info.height <= maxDimension else {
            throw ImageImportError.dimensionsTooLarge(width: info.width, height: info.height, maxDimension: maxDimension)
        }
        return info
    }

    /// Reads ImageIO metadata without applying the output-size cap. Import
    /// uses this to downsample oversized originals instead of rejecting them.
    private func sourceMetadata(for url: URL) throws -> ImageMetadata {
        guard url.isFileURL else { throw ImageImportError.notLocalFile }
        let localURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ImageImportError.fileMissing
        }
        guard let source = CGImageSourceCreateWithURL(localURL as CFURL, nil),
              let rawType = CGImageSourceGetType(source) else {
            throw ImageImportError.unreadableImage
        }

        let typeIdentifier = rawType as String
        guard Self.isSupported(typeIdentifier) else { throw ImageImportError.unsupportedFormat }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ImageImportError.unreadableImage
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { throw ImageImportError.invalidDimensions }
        let bytes = (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ImageMetadata(uti: typeIdentifier, width: width, height: height, byteCount: bytes)
    }

    public func validate(_ url: URL) throws -> ImageMetadata {
        try metadata(for: url)
    }

    public func importArtwork(
        from url: URL,
        name: String? = nil,
        tileCount: Int? = nil,
        id: UUID = UUID(),
        seed: UInt64? = nil,
        destinationDirectory: URL? = nil
    ) throws -> Artwork {
        let info = try sourceMetadata(for: url)
        let displayName: String
        if let candidate = name?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
            displayName = candidate
        } else {
            displayName = url.deletingPathExtension().lastPathComponent
        }
        let importedURL = try persistResizedImage(
            from: url,
            sourceInfo: info,
            destinationDirectory: destinationDirectory,
            id: id
        )
        let outputInfo = try sourceMetadata(for: importedURL)
        return Artwork(
            id: id,
            name: displayName,
            fileURL: importedURL,
            width: outputInfo.width,
            height: outputInfo.height,
            tileCount: tileCount ?? defaultTileCount,
            seed: seed
        )
    }

    public func `import`(
        _ url: URL,
        name: String? = nil,
        tileCount: Int? = nil,
        destinationDirectory: URL? = nil
    ) throws -> Artwork {
        try importArtwork(from: url, name: name, tileCount: tileCount, destinationDirectory: destinationDirectory)
    }

    public static func importArtwork(
        from url: URL,
        name: String? = nil,
        tileCount: Int = 12,
        destinationDirectory: URL? = nil
    ) throws -> Artwork {
        try ImageImporter(defaultTileCount: tileCount).importArtwork(
            from: url,
            name: name,
            tileCount: tileCount,
            destinationDirectory: destinationDirectory
        )
    }

    private func persistResizedImage(
        from url: URL,
        sourceInfo: ImageMetadata,
        destinationDirectory: URL?,
        id: UUID
    ) throws -> URL {
        let localURL = url.standardizedFileURL
        let accessing = localURL.startAccessingSecurityScopedResource()
        defer { if accessing { localURL.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(localURL as CFURL, nil) else {
            throw ImageImportError.unreadableImage
        }
        let directory = destinationDirectory ?? Self.defaultArtworkDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ImageImportError.unableToCreateDestination
        }

        let outputType: CFString = sourceInfo.uti == UTType.png.identifier
            ? UTType.png.identifier as CFString
            : UTType.jpeg.identifier as CFString
        let extensionName = outputType == UTType.png.identifier as CFString ? "png" : "jpg"
        let destination = directory.appendingPathComponent("\(id.uuidString).\(extensionName)")
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ImageImportError.unreadableImage
        }
        guard let destinationRef = CGImageDestinationCreateWithURL(destination as CFURL, outputType, 1, nil) else {
            throw ImageImportError.unableToEncodeImage
        }
        var properties: [CFString: Any] = [:]
        if outputType == UTType.jpeg.identifier as CFString {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        CGImageDestinationAddImage(destinationRef, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destinationRef) else {
            try? FileManager.default.removeItem(at: destination)
            throw ImageImportError.unableToEncodeImage
        }
        return destination
    }

    private static func defaultArtworkDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Tela/Artwork", isDirectory: true)
    }

    private static func isSupported(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .jpeg) || type.conforms(to: .png) || type.conforms(to: .heic) || type.conforms(to: .heif)
    }
}

public typealias LocalImageImporter = ImageImporter
public typealias ArtworkImporter = ImageImporter

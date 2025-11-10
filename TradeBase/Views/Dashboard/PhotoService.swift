//
//  PhotoService.swift
//  TradeBase
//
//  Centralized media utility for saving images/videos to app-private storage,
//  generating thumbnails, and deleting files. Used by Job listings and can be
//  reused by messaging or other features.
//

import Foundation
import UIKit
import AVFoundation

final class PhotoService {

    static let shared = PhotoService()

    // MARK: - Directories

    private let appDir: URL
    private let jobPhotosDir: URL
    private let mediaCacheDir: URL

    private init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        var app = base.appendingPathComponent("TradeBase", isDirectory: true)
        var job = app.appendingPathComponent("JobPhotos", isDirectory: true)
        var cache = app.appendingPathComponent("MediaCache", isDirectory: true)

        // Ensure dirs exist
        if !fm.fileExists(atPath: app.path) { try? fm.createDirectory(at: app, withIntermediateDirectories: true) }
        if !fm.fileExists(atPath: job.path) { try? fm.createDirectory(at: job, withIntermediateDirectories: true) }
        if !fm.fileExists(atPath: cache.path) { try? fm.createDirectory(at: cache, withIntermediateDirectories: true) }

        // Strong data protection
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: app.path)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: job.path)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: cache.path)

        // Exclude from backups
        var rvs = URLResourceValues()
        rvs.isExcludedFromBackup = true
        try? app.setResourceValues(rvs)
        try? job.setResourceValues(rvs)
        try? cache.setResourceValues(rvs)

        self.appDir = app
        self.jobPhotosDir = job
        self.mediaCacheDir = cache
    }

    // MARK: - Public API (used by JobListingEditorSheet)

    /// Save raw image data to JobPhotos, normalizing to JPEG and downscaling large images.
    /// Returns the file URL on success.
    func save(_ data: Data) async -> URL? {
        // Try to decode as image
        if let ui = UIImage(data: data) {
            // Downscale if needed and save as JPEG
            let normalized = await normalizeImage(ui, maxDimension: 3000, quality: 0.88)
            return writeJPEGToJobPhotos(normalized)
        } else {
            // Not an image? Just write raw data with a generic extension into MediaCache
            return writeRawToCache(data: data, preferredExt: "bin")
        }
    }

    /// Generate a thumbnail for an image or video URL. Cached in-memory.
    func thumbnail(for url: URL, targetSize: CGSize) -> UIImage? {
        let key = thumbKey(for: url, size: targetSize)
        if let cached = thumbCache.object(forKey: key as NSString) {
            return cached
        }

        // If it's an image file, load and scale
        if isImage(url: url) {
            if let img = UIImage(contentsOfFile: url.path) {
                let thumb = scale(image: img, toFit: targetSize)
                thumbCache.setObject(thumb, forKey: key as NSString)
                return thumb
            }
        }

        // If it looks like a video, try to grab a frame
        if isVideo(url: url) {
            if let frame = generateVideoFrame(url: url, maxSize: targetSize) {
                thumbCache.setObject(frame, forKey: key as NSString)
                return frame
            }
        }

        // Fallback: attempt decoding raw data as image
        if let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            let thumb = scale(image: img, toFit: targetSize)
            thumbCache.setObject(thumb, forKey: key as NSString)
            return thumb
        }

        return nil
    }

    /// Best-effort delete if the file is inside our managed directories.
    func delete(_ url: URL) {
        let fm = FileManager.default
        let path = url.path
        // Only delete files within our app-owned directories
        if path.hasPrefix(jobPhotosDir.path) || path.hasPrefix(mediaCacheDir.path) || path.hasPrefix(appDir.path) {
            try? fm.removeItem(at: url)
        }
        // Invalidate any cached thumbnails for this path (all sizes)
        removeCachedThumbs(forPath: path)
    }

    // MARK: - Helpers

    private func writeJPEGToJobPhotos(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return nil }
        let fm = FileManager.default
        var url = jobPhotosDir.appendingPathComponent("photo-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: [.atomic])
            try protect(url)
            return url
        } catch {
            // Fallback to temp if needed
            url = FileManager.default.temporaryDirectory.appendingPathComponent("photo-\(UUID().uuidString).jpg")
            try? data.write(to: url, options: [.atomic])
            return url
        }
    }

    private func writeRawToCache(data: Data, preferredExt: String) -> URL? {
        let fm = FileManager.default
        var url = mediaCacheDir.appendingPathComponent("blob-\(UUID().uuidString)").appendingPathExtension(preferredExt)
        do {
            try data.write(to: url, options: [.atomic])
            try protect(url)
            return url
        } catch {
            return nil
        }
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(rvs)
    }

    // MARK: - Image processing

    private func normalizeImage(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) async -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        if maxSide <= maxDimension {
            return image
        }
        let scale = maxDimension / maxSide
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        return await render(image: image, size: target)
    }

    private func render(image: UIImage, size: CGSize) async -> UIImage {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let renderer = UIGraphicsImageRenderer(size: size)
                let result = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                cont.resume(returning: result)
            }
        }
    }

    private func scale(image: UIImage, toFit targetSize: CGSize) -> UIImage {
        let size = image.size
        let scale = min(targetSize.width / size.width, targetSize.height / size.height)
        let newSize = CGSize(width: max(1, floor(size.width * scale)),
                             height: max(1, floor(size.height * scale)))
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func isImage(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "gif", "tif", "tiff"].contains(ext)
    }

    private func isVideo(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v"].contains(ext)
    }

    private func generateVideoFrame(url: URL, maxSize: CGSize) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = maxSize
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        do {
            let cg = try gen.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }

    // MARK: - Thumbnail cache

    private let thumbCache = NSCache<NSString, UIImage>()

    private func thumbKey(for url: URL, size: CGSize) -> String {
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        return "\(url.path)|\(w)x\(h)"
    }

    private func removeCachedThumbs(forPath path: String) {
        // NSCache doesn’t support enumeration of keys; rely on simple heuristic:
        // clear entire cache when a file is deleted. This is acceptable for our expected sizes.
        thumbCache.removeAllObjects()
    }
}

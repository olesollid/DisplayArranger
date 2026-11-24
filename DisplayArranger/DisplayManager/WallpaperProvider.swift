//
//  WallpaperProvider.swift
//  DisplayArranger
//
//  Loads each display's current desktop picture as a small thumbnail.
//

import AppKit
import ImageIO

final class WallpaperProvider {
    static let shared = WallpaperProvider()

    private var cache: [URL: NSImage] = [:]
    private let queue = DispatchQueue(label: "DisplayArranger.wallpapers", qos: .userInitiated)
    private let lock = NSLock()

    /// Loads thumbnails for the given displays off the main thread and delivers
    /// them on the main thread. Displays whose wallpaper can't be read (for example
    /// a file outside the sandbox, or a dynamic/aerial wallpaper without an image
    /// file) are left out, so the caller can fall back to its placeholder.
    func loadWallpapers(
        for displayIDs: [CGDirectDisplayID],
        completion: @escaping ([CGDirectDisplayID: NSImage]) -> Void
    ) {
        // NSScreen / NSWorkspace lookups happen on the main thread.
        var urls: [CGDirectDisplayID: URL] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID, displayIDs.contains(id),
                  let url = NSWorkspace.shared.desktopImageURL(for: screen) else { continue }
            urls[id] = url
        }

        queue.async {
            var images: [CGDirectDisplayID: NSImage] = [:]
            for (id, url) in urls {
                if let image = self.thumbnail(for: url) {
                    images[id] = image
                }
            }
            DispatchQueue.main.async { completion(images) }
        }
    }

    private func thumbnail(for url: URL) -> NSImage? {
        lock.lock()
        if let cached = cache[url] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            log("Could not open wallpaper at \(url.path)")
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            log("Could not decode wallpaper at \(url.path)")
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        lock.lock()
        cache[url] = image
        lock.unlock()
        return image
    }
}

//
//  DisplayManager.swift
//  DisplayArranger
//
//  Created by Ole Christian Sollid on 04/12/2025.
//

import AppKit
import CoreGraphics

/// One display as it appears in the arrangement, in global display coordinates
/// (points, primary display at origin, y grows downward).
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isPrimary: Bool
    var frame: CGRect
}

struct DisplayLayoutSnapshot {
    let displays: [DisplayInfo]
}

class DisplayManager {
    /// Number of displays (besides the primary) the app will arrange.
    static let maxExternalDisplays = 3

    /// Reads the current arrangement: the primary display plus up to
    /// `maxExternalDisplays` additional displays. Returns nil with only one display.
    func currentLayout() -> DisplayLayoutSnapshot? {
        let primary = CGMainDisplayID()
        let externals = activeDisplays()
            .filter { $0 != primary && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .prefix(Self.maxExternalDisplays)
        guard !externals.isEmpty else { return nil }

        let names = screenNames()
        let ids = [primary] + externals
        let displays = ids.map { id in
            DisplayInfo(
                id: id,
                name: names[id] ?? (id == primary ? "Main Display" : "Display"),
                isPrimary: id == primary,
                frame: CGDisplayBounds(id)
            )
        }
        return DisplayLayoutSnapshot(displays: displays)
    }

    /// Moves every non-primary display to the origin given by its frame,
    /// in a single configuration transaction.
    func apply(_ displays: [DisplayInfo]) {
        var configRef: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&configRef)
        guard beginResult == .success, let config = configRef else {
            log("CGBeginDisplayConfiguration failed: \(beginResult.rawValue)")
            return
        }

        for display in displays where !display.isPrimary {
            let result = CGConfigureDisplayOrigin(
                config,
                display.id,
                Int32(display.frame.origin.x.rounded()),
                Int32(display.frame.origin.y.rounded())
            )
            if result != .success {
                log("CGConfigureDisplayOrigin failed for \(display.id): \(result.rawValue)")
                CGCancelDisplayConfiguration(config)
                return
            }
        }

        let completeResult = CGCompleteDisplayConfiguration(config, .permanently)
        if completeResult == .success {
            log("Arrangement applied for \(displays.count) displays")
        } else {
            log("CGCompleteDisplayConfiguration failed: \(completeResult.rawValue)")
        }
    }

    /// Gets a list of all currently active (on and connected) displays.
    private func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var list = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &list, &count)
        return Array(list.prefix(Int(count)))
    }

    private func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let id = screen.displayID {
                names[id] = screen.localizedName
            }
        }
        return names
    }
}

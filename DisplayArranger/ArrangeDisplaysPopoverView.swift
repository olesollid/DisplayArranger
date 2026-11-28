//
//  ArrangeDisplaysPopoverView.swift
//  DisplayArranger
//
//  Created by Codex on 16/02/2026.
//

import AppKit
import SwiftUI

struct ArrangeDisplaysPopoverView: View {
    @ObservedObject var controller: MenuBarController

    @State private var initialDisplays: [DisplayInfo] = []
    @State private var displays: [DisplayInfo] = []
    @State private var parents: [CGDirectDisplayID: CGDirectDisplayID] = [:]
    @State private var wallpapers: [CGDirectDisplayID: NSImage] = [:]
    @State private var draggingID: CGDirectDisplayID?
    @State private var dragOffset: CGSize = .zero
    @State private var hoveredID: CGDirectDisplayID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Arrange Displays")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)

            Text("To rearrange displays, drag them to the desired position.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.68))

            arrangementCanvas

            HStack {
                Button("Quit") {
                    controller.quit()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Toggle(
                    "Run at startup",
                    isOn: Binding(
                        get: { controller.launchAtStartupEnabled },
                        set: { controller.setLaunchAtStartup(enabled: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .foregroundStyle(.white)

                Spacer()

                if hasChanges {
                    Button("Reset", action: resetLayout)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Discard changes and return to the applied layout")
                        .transition(.opacity)
                }

                if hasChanges {
                    Button("Apply", action: applyLayout)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .keyboardShortcut(.defaultAction)
                        .help("Apply the new arrangement")
                } else {
                    Button("Hide") {
                        controller.closePopover()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .animation(.easeOut(duration: 0.15), value: hasChanges)
        }
        .padding(16)
        .frame(width: 560, height: 390)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.14, alpha: 0.98)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            refreshLayout()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshLayout()
        }
    }

    private var arrangementCanvas: some View {
        GeometryReader { geometry in
            // Fit both layouts so the applied-layout outlines stay visible.
            let mapping = CanvasMapping(displays: displays + initialDisplays, canvasSize: geometry.size)
            let preview = snapPreview(mapping: mapping)

            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.11), lineWidth: 1)
                    )

                // Dimmed outlines marking where moved displays are in the applied layout.
                ForEach(movedFromApplied) { applied in
                    let rect = mapping.canvasRect(for: applied.frame)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.gray.opacity(0.55), lineWidth: 1.5)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if let preview {
                    let rect = mapping.canvasRect(for: preview)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color(nsColor: .controlAccentColor).opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                ForEach(displays) { display in
                    let rect = mapping.canvasRect(for: display.frame)
                    let isMoving = movingSet.contains(display.id)
                    let offset = isMoving ? dragOffset : .zero

                    DisplayTile(
                        size: rect.size,
                        name: display.name,
                        isPrimary: display.isPrimary,
                        wallpaper: wallpapers[display.id],
                        strokeOpacity: isMoving ? 0.78 : (display.isPrimary ? 0.35 : 0.5)
                    )
                    .position(x: rect.midX + offset.width, y: rect.midY + offset.height)
                    .zIndex(isMoving ? 1 : 0)
                    .gesture(display.isPrimary ? nil : dragGesture(for: display.id, mapping: mapping))
                }

                // Quick-snap pads sit above the tiles (not inside them) so their
                // clicks never start a drag.
                ForEach(displays.filter { !$0.isPrimary }) { display in
                    let rect = mapping.canvasRect(for: display.frame)
                    SnapPad(
                        tileSize: rect.size,
                        currentSide: currentSide(of: display),
                        isAvailable: { side in quickSnapTarget(for: display.id, side: side) != nil }
                    ) { side in
                        quickSnap(display.id, to: side)
                    }
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(draggingID == nil && hoveredID == display.id ? 1 : 0)
                    .allowsHitTesting(draggingID == nil && hoveredID == display.id)
                    .animation(.easeOut(duration: 0.15), value: hoveredID)
                    .zIndex(2)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredID = displays.last {
                        !$0.isPrimary && mapping.canvasRect(for: $0.frame).contains(location)
                    }?.id
                case .ended:
                    hoveredID = nil
                }
            }
        }
        .frame(height: 255)
        .padding(.vertical, 2)
    }

    /// True when the arrangement on the canvas differs from the applied one.
    private var hasChanges: Bool {
        displays != initialDisplays
    }

    /// Applied-layout entries for displays whose position has changed on the canvas.
    private var movedFromApplied: [DisplayInfo] {
        initialDisplays.filter { applied in
            displays.first(where: { $0.id == applied.id })?.frame != applied.frame
        }
    }

    private func applyLayout() {
        controller.apply(displays)
        // Re-read what the system actually applied; the screen-change
        // notification will refresh again once macOS settles.
        refreshLayout()
    }

    private func resetLayout() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            displays = initialDisplays
            parents = DisplayArrangement.parents(for: initialDisplays)
            draggingID = nil
            dragOffset = .zero
        }
    }

    /// The dragged display plus everything attached beyond it.
    private var movingSet: Set<CGDirectDisplayID> {
        guard let draggingID else { return [] }
        return DisplayArrangement.subtree(of: draggingID, parents: parents)
    }

    private func dragGesture(for id: CGDirectDisplayID, mapping: CanvasMapping) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                draggingID = id
                dragOffset = value.translation
            }
            .onEnded { _ in
                let target = snapPreview(mapping: mapping)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    if let target {
                        move(id, to: target)
                    }
                    draggingID = nil
                    dragOffset = .zero
                }
            }
    }

    /// Moves a display (and everything attached beyond it) so its frame becomes `target`.
    private func move(_ id: CGDirectDisplayID, to target: CGRect) {
        guard let moving = displays.first(where: { $0.id == id }) else { return }
        let dx = target.minX - moving.frame.minX
        let dy = target.minY - moving.frame.minY
        let moved = DisplayArrangement.subtree(of: id, parents: parents)
        displays = displays.map { display in
            guard moved.contains(display.id) else { return display }
            var copy = display
            copy.frame = display.frame.offsetBy(dx: dx, dy: dy)
            return copy
        }
        parents = DisplayArrangement.parents(for: displays)
    }

    private func quickSnapTarget(for id: CGDirectDisplayID, side: DisplayPlacement) -> CGRect? {
        DisplayArrangement.quickSnapFrame(moving: id, to: side, displays: displays, parents: parents)
    }

    private func quickSnap(_ id: CGDirectDisplayID, to side: DisplayPlacement) {
        guard let target = quickSnapTarget(for: id, side: side) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            move(id, to: target)
        }
    }

    private func currentSide(of display: DisplayInfo) -> DisplayPlacement? {
        guard let primary = displays.first(where: { $0.isPrimary }) else { return nil }
        return DisplayArrangement.side(of: display.frame, relativeTo: primary.frame)
    }

    /// Where the display being dragged would land if dropped now.
    private func snapPreview(mapping: CanvasMapping) -> CGRect? {
        guard let draggingID,
              let moving = displays.first(where: { $0.id == draggingID }),
              mapping.scale > 0 else { return nil }

        let proposed = moving.frame.offsetBy(
            dx: dragOffset.width / mapping.scale,
            dy: dragOffset.height / mapping.scale
        )
        return DisplayArrangement.snappedFrame(
            moving: draggingID,
            proposed: proposed,
            displays: displays,
            parents: parents,
            snapThreshold: 10 / mapping.scale
        )
    }

    private func refreshLayout() {
        let current = controller.currentLayout()?.displays ?? []
        initialDisplays = current
        displays = current
        parents = DisplayArrangement.parents(for: current)
        draggingID = nil
        dragOffset = .zero

        WallpaperProvider.shared.loadWallpapers(for: current.map(\.id)) { images in
            wallpapers = images
        }
    }
}

/// Maps global display coordinates (points) into the canvas, fitting the whole
/// arrangement with room around it to drag displays to any side.
private struct CanvasMapping {
    let scale: CGFloat
    let offset: CGPoint

    init(displays: [DisplayInfo], canvasSize: CGSize) {
        let bounds = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            scale = 0
            offset = .zero
            return
        }

        // Leave space around the arrangement for a display to be dropped outside it.
        let largest = displays.map(\.frame.size).reduce(CGSize.zero) {
            CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
        }
        let paddedWidth = bounds.width + largest.width * 0.9
        let paddedHeight = bounds.height + largest.height * 0.9
        let fit = min(canvasSize.width / paddedWidth, canvasSize.height / paddedHeight)
        scale = fit

        offset = CGPoint(
            x: canvasSize.width / 2 - bounds.midX * fit,
            y: canvasSize.height / 2 - bounds.midY * fit
        )
    }

    func canvasRect(for frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX * scale + offset.x,
            y: frame.minY * scale + offset.y,
            width: frame.width * scale,
            height: frame.height * scale
        )
    }
}

private struct DisplayTile: View {
    let size: CGSize
    let name: String
    let isPrimary: Bool
    let wallpaper: NSImage?
    let strokeOpacity: Double

    var body: some View {
        ZStack {
            background
                .frame(width: size.width, height: size.height)
                .clipped()

            VStack(spacing: 0) {
                if isPrimary {
                    // Menu bar marker, like System Settings.
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(height: max(size.height * 0.06, 3))
                }
                Spacer(minLength: 0)
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(6)
                    .frame(maxWidth: size.width)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var background: some View {
        if let wallpaper {
            Image(nsImage: wallpaper)
                .resizable()
                .scaledToFill()
        } else if NSImage(named: "DisplayBackground") != nil {
            // SwiftUI picks light/dark variant based on system settings
            Image("DisplayBackground")
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [.blue.opacity(0.9), .purple.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// Four arrow buttons in a compass layout that snap a display to a side of the
/// main display.
private struct SnapPad: View {
    let tileSize: CGSize
    let currentSide: DisplayPlacement?
    let isAvailable: (DisplayPlacement) -> Bool
    let action: (DisplayPlacement) -> Void

    private var buttonSize: CGFloat {
        min(max(min(tileSize.width, tileSize.height) / 4.2, 14), 24)
    }

    var body: some View {
        let size = buttonSize
        let spacing = size * 0.12

        VStack(spacing: spacing) {
            button(.above)
            HStack(spacing: spacing) {
                button(.left)
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: size * 0.22, height: size * 0.22)
                    .frame(width: size, height: size)
                    .allowsHitTesting(false)
                button(.right)
            }
            button(.below)
        }
        .padding(size * 0.18)
        .background(
            RoundedRectangle(cornerRadius: size * 0.6, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.9)
                // Click-through: pressing the pad's background (anywhere but a
                // button) reaches the tile underneath, so the display can be dragged.
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.6, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    private func button(_ side: DisplayPlacement) -> some View {
        SnapButton(
            side: side,
            size: buttonSize,
            isCurrent: side == currentSide,
            isEnabled: isAvailable(side)
        ) {
            action(side)
        }
    }
}

private struct SnapButton: View {
    let side: DisplayPlacement
    let size: CGFloat
    let isCurrent: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var symbol: String {
        switch side {
        case .above: return "chevron.up"
        case .below: return "chevron.down"
        case .left:  return "chevron.left"
        case .right: return "chevron.right"
        }
    }

    private var label: String {
        switch side {
        case .above: return "Move above main display"
        case .below: return "Move below main display"
        case .left:  return "Move left of main display"
        case .right: return "Move right of main display"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(
                        isCurrent
                            ? AnyShapeStyle(Color(nsColor: .controlAccentColor).gradient)
                            : AnyShapeStyle(Color.white.opacity(isHovered ? 0.32 : 0.14))
                    )
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(isCurrent ? 0.45 : 0.2), lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(SnapButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered && isEnabled ? 1.1 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct SnapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

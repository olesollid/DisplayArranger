//
//  DisplayArrangement.swift
//  DisplayArranger
//
//  Pure geometry for arranging several displays: which display hangs off which,
//  and where a dragged display should snap to.
//

import CoreGraphics

enum DisplayArrangement {
    typealias ID = CGDirectDisplayID

    /// Builds a spanning tree rooted at the primary display, linking each display
    /// to a display it shares an edge with. Returns child -> parent.
    /// Dragging a display moves it together with everything attached beyond it.
    static func parents(for displays: [DisplayInfo]) -> [ID: ID] {
        guard let primary = displays.first(where: { $0.isPrimary }) else { return [:] }

        var parents: [ID: ID] = [:]
        var visited: [DisplayInfo] = [primary]
        var queue: [DisplayInfo] = [primary]
        var remaining = displays.filter { !$0.isPrimary }

        while !remaining.isEmpty {
            if queue.isEmpty {
                // Nothing touches the tree: attach the closest remaining display.
                var best: (index: Int, parent: ID, distance: CGFloat)?
                for (index, display) in remaining.enumerated() {
                    for anchor in visited {
                        let distance = display.frame.center.distance(to: anchor.frame.center)
                        if best == nil || distance < best!.distance {
                            best = (index, anchor.id, distance)
                        }
                    }
                }
                guard let best else { break }
                let display = remaining.remove(at: best.index)
                parents[display.id] = best.parent
                visited.append(display)
                queue.append(display)
                continue
            }

            let current = queue.removeFirst()
            let touching = remaining.filter { areAdjacent($0.frame, current.frame) }
            for display in touching {
                parents[display.id] = current.id
                visited.append(display)
                queue.append(display)
            }
            remaining.removeAll { display in touching.contains { $0.id == display.id } }
        }

        return parents
    }

    /// The display and every display attached (directly or indirectly) beyond it.
    static func subtree(of root: ID, parents: [ID: ID]) -> Set<ID> {
        var result: Set<ID> = [root]
        var changed = true
        while changed {
            changed = false
            for (child, parent) in parents where result.contains(parent) && !result.contains(child) {
                result.insert(child)
                changed = true
            }
        }
        return result
    }

    /// Finds where `movingID` (and its subtree) should land when dropped with its
    /// top-left at `proposed.origin`. The result is flush against an edge of a display
    /// outside the subtree, may slide along that edge, and snaps to centred or
    /// edge-aligned positions within `snapThreshold` points. Returns nil when no
    /// spot is free of overlaps.
    static func snappedFrame(
        moving movingID: ID,
        proposed: CGRect,
        displays: [DisplayInfo],
        parents: [ID: ID],
        snapThreshold: CGFloat
    ) -> CGRect? {
        guard let moving = displays.first(where: { $0.id == movingID }) else { return nil }

        let movingSet = subtree(of: movingID, parents: parents)
        let anchors = displays.filter { !movingSet.contains($0.id) }
        let movers = displays.filter { movingSet.contains($0.id) }
        let size = moving.frame.size

        var candidates: [CGRect] = []
        for anchor in anchors {
            let a = anchor.frame
            for side in DisplayPlacement.allCases {
                let horizontal = side == .left || side == .right
                let minOverlap = min(horizontal ? size.height : size.width,
                                     horizontal ? a.height : a.width) * 0.2

                var origin: CGPoint
                switch side {
                case .left:  origin = CGPoint(x: a.minX - size.width, y: proposed.minY)
                case .right: origin = CGPoint(x: a.maxX, y: proposed.minY)
                case .above: origin = CGPoint(x: proposed.minX, y: a.minY - size.height)
                case .below: origin = CGPoint(x: proposed.minX, y: a.maxY)
                }

                if horizontal {
                    origin.y = snap(
                        clamp(origin.y, a.minY - size.height + minOverlap, a.maxY - minOverlap),
                        to: [a.midY - size.height / 2, a.minY, a.maxY - size.height],
                        threshold: snapThreshold
                    )
                } else {
                    origin.x = snap(
                        clamp(origin.x, a.minX - size.width + minOverlap, a.maxX - minOverlap),
                        to: [a.midX - size.width / 2, a.minX, a.maxX - size.width],
                        threshold: snapThreshold
                    )
                }
                candidates.append(CGRect(origin: origin, size: size))
            }
        }

        let proposedCenter = proposed.center
        let valid = candidates.filter { candidate in
            let dx = candidate.minX - moving.frame.minX
            let dy = candidate.minY - moving.frame.minY
            return movers.allSatisfy { mover in
                let moved = mover.frame.offsetBy(dx: dx, dy: dy)
                return anchors.allSatisfy { !overlaps(moved, $0.frame) }
            }
        }

        return valid.min {
            $0.center.distance(to: proposedCenter) < $1.center.distance(to: proposedCenter)
        }
    }

    /// Where `movingID` lands when quick-snapped to `side` of the primary display:
    /// centred on that edge, or the nearest free spot if something is already there.
    static func quickSnapFrame(
        moving movingID: ID,
        to side: DisplayPlacement,
        displays: [DisplayInfo],
        parents: [ID: ID]
    ) -> CGRect? {
        guard let primary = displays.first(where: { $0.isPrimary })?.frame,
              let size = displays.first(where: { $0.id == movingID })?.frame.size else { return nil }

        let origin: CGPoint
        switch side {
        case .left:  origin = CGPoint(x: primary.minX - size.width, y: primary.midY - size.height / 2)
        case .right: origin = CGPoint(x: primary.maxX, y: primary.midY - size.height / 2)
        case .above: origin = CGPoint(x: primary.midX - size.width / 2, y: primary.minY - size.height)
        case .below: origin = CGPoint(x: primary.midX - size.width / 2, y: primary.maxY)
        }

        return snappedFrame(
            moving: movingID,
            proposed: CGRect(origin: origin, size: size),
            displays: displays,
            parents: parents,
            snapThreshold: 1
        )
    }

    /// Which side of the primary display a frame mostly sits on.
    static func side(of frame: CGRect, relativeTo primary: CGRect) -> DisplayPlacement {
        let dx = frame.midX - primary.midX
        let dy = frame.midY - primary.midY
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? .right : .left
        }
        return dy >= 0 ? .below : .above
    }

    /// Two rects that share part of an edge (within a small tolerance).
    static func areAdjacent(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let touchX = abs(a.maxX - b.minX) <= tolerance || abs(b.maxX - a.minX) <= tolerance
        let touchY = abs(a.maxY - b.minY) <= tolerance || abs(b.maxY - a.minY) <= tolerance
        return (touchX && verticalOverlap > 0) || (touchY && horizontalOverlap > 0)
    }

    static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.insetBy(dx: 1, dy: 1).intersects(b)
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private static func snap(_ value: CGFloat, to targets: [CGFloat], threshold: CGFloat) -> CGFloat {
        guard let nearest = targets.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(nearest - value) <= threshold else { return value }
        return nearest
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        let dx = point.x - x
        let dy = point.y - y
        return sqrt((dx * dx) + (dy * dy))
    }
}

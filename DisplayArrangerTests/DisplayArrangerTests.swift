//
//  DisplayArrangerTests.swift
//  DisplayArrangerTests
//
//  Created by Ole Christian Sollid on 04/12/2025.
//

import CoreGraphics
import Testing
@testable import DisplayArranger

struct DisplayArrangementTests {
    // Primary 1512x982 at origin, A to the right, B below, C to the right of A.
    let displays: [DisplayInfo] = [
        DisplayInfo(id: 1, name: "Main", isPrimary: true, frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
        DisplayInfo(id: 2, name: "A", isPrimary: false, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080)),
        DisplayInfo(id: 3, name: "B", isPrimary: false, frame: CGRect(x: 166, y: 982, width: 1180, height: 820)),
        DisplayInfo(id: 4, name: "C", isPrimary: false, frame: CGRect(x: 3432, y: 0, width: 1280, height: 720)),
    ]

    @Test func buildsTreeFromAdjacency() {
        let parents = DisplayArrangement.parents(for: displays)
        #expect(parents[2] == 1)
        #expect(parents[3] == 1)
        #expect(parents[4] == 2)
        #expect(DisplayArrangement.subtree(of: 2, parents: parents) == [2, 4])
    }

    @Test func snapsToCentredLeftOfPrimary() {
        let parents = DisplayArrangement.parents(for: displays)
        let proposed = CGRect(x: -1200, y: 100, width: 1180, height: 820)
        let frame = DisplayArrangement.snappedFrame(
            moving: 3, proposed: proposed, displays: displays, parents: parents, snapThreshold: 100
        )
        #expect(frame == CGRect(x: -1180, y: 81, width: 1180, height: 820))
    }

    @Test func slidesAlongEdgeOutsideSnapThreshold() {
        let parents = DisplayArrangement.parents(for: displays)
        let proposed = CGRect(x: -1200, y: 400, width: 1180, height: 820)
        let frame = DisplayArrangement.snappedFrame(
            moving: 3, proposed: proposed, displays: displays, parents: parents, snapThreshold: 10
        )
        #expect(frame == CGRect(x: -1180, y: 400, width: 1180, height: 820))
    }

    @Test func neverOverlapsOtherDisplays() {
        let parents = DisplayArrangement.parents(for: displays)
        // Drop B right on top of A; it must land somewhere free.
        let proposed = CGRect(x: 1700, y: 100, width: 1180, height: 820)
        let frame = try! #require(DisplayArrangement.snappedFrame(
            moving: 3, proposed: proposed, displays: displays, parents: parents, snapThreshold: 10
        ))
        for other in displays where other.id != 3 {
            #expect(!DisplayArrangement.overlaps(frame, other.frame))
        }
    }

    @Test func subtreeMovesWithoutOverlap() {
        let parents = DisplayArrangement.parents(for: displays)
        // Move A (with C attached) above the primary.
        let proposed = CGRect(x: 0, y: -1100, width: 1920, height: 1080)
        let frame = try! #require(DisplayArrangement.snappedFrame(
            moving: 2, proposed: proposed, displays: displays, parents: parents, snapThreshold: 10
        ))
        #expect(frame.maxY == 0)
    }

    @Test func quickSnapCentresOnFreeSide() {
        let parents = DisplayArrangement.parents(for: displays)
        let frame = DisplayArrangement.quickSnapFrame(moving: 3, to: .above, displays: displays, parents: parents)
        #expect(frame == CGRect(x: 166, y: -820, width: 1180, height: 820))
    }

    @Test func quickSnapFindsFreeSpotWhenSideIsTaken() {
        let parents = DisplayArrangement.parents(for: displays)
        // The right side is already taken by A, so B must land somewhere free.
        let frame = try! #require(DisplayArrangement.quickSnapFrame(moving: 3, to: .right, displays: displays, parents: parents))
        for other in displays where other.id != 3 {
            #expect(!DisplayArrangement.overlaps(frame, other.frame))
        }
    }
}

import Testing
import TrackTileCore

struct ConflictRulesTests {
    /// The configuration from a real Mac: Mission Control on three fingers,
    /// App Exposé Off, full-screen swipes on three fingers. macOS keeps the
    /// four-finger flags set.
    private let trackpad: [String: Int] = [
        "TrackpadThreeFingerDrag": 0,
        "TrackpadThreeFingerVertSwipeGesture": 2,
        "TrackpadThreeFingerHorizSwipeGesture": 2,
        "TrackpadFourFingerVertSwipeGesture": 2,
        "TrackpadFourFingerHorizSwipeGesture": 2,
    ]
    private let dock: [String: Int] = [
        "showMissionControlGestureEnabled": 1,
        "showAppExposeGestureEnabled": 0,
    ]

    private func ids(_ fingers: Set<Int>, trackpad: [String: Int]? = nil, dock: [String: Int]? = nil) -> Set<String> {
        let t = trackpad ?? self.trackpad
        let d = dock ?? self.dock
        return Set(ConflictRules.conflicts(for: fingers, trackpad: { t[$0] }, dock: { d[$0] }).map(\.id))
    }

    @Test func appExposeOffIsNotAConflict() {
        #expect(ids([4]) == ["missionControl.4", "fullScreenApps.4"])
        #expect(ids([3]) == ["missionControl.3", "fullScreenApps.3"])
    }

    @Test func missingDockKeysMeanEnabled() {
        #expect(ids([4], dock: [:]) == ["missionControl.4", "appExpose.4", "fullScreenApps.4"])
    }

    @Test func missionControlOffInDock() {
        let dock = ["showMissionControlGestureEnabled": 0, "showAppExposeGestureEnabled": 0]
        #expect(ids([4], dock: dock) == ["fullScreenApps.4"])
    }

    @Test func everythingOff() {
        let off = trackpad.mapValues { _ in 0 }
        #expect(ids([3, 4], trackpad: off).isEmpty)
    }

    @Test func threeFingerDragAndPagesAreNotSuppressible() {
        var t = trackpad
        t["TrackpadThreeFingerDrag"] = 1
        t["TrackpadThreeFingerHorizSwipeGesture"] = 1
        let conflicts = ConflictRules.conflicts(for: [3], trackpad: { t[$0] }, dock: { dock[$0] })
        let byID = Dictionary(uniqueKeysWithValues: conflicts.map { ($0.id, $0) })
        #expect(byID["threeFingerDrag"]?.suppressible == false)
        #expect(byID["swipePages.3"]?.suppressible == false)
        #expect(byID["missionControl.3"]?.suppressible == true)
    }

    @Test func onlyRequestedFingerCounts() {
        #expect(ids([]).isEmpty)
        #expect(ids([4]).allSatisfy { $0.hasSuffix(".4") })
    }
}

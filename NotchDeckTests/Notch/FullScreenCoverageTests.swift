import CoreGraphics
import Testing
@testable import NotchDeck

struct FullScreenCoverageTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let ownPID: pid_t = 100
    private let otherPID: pid_t = 200

    @Test func fullScreenAppWindowCoversTheScreen() {
        let windows = [FullScreenCoverage.Window(layer: 0, bounds: screen, ownerPID: otherPID)]
        #expect(FullScreenCoverage.isCovered(screenFrame: screen, windows: windows, ownPID: ownPID))
    }

    @Test func zoomedWindowBelowTheMenuBarDoesNotCover() {
        let zoomed = CGRect(x: 0, y: 30, width: 1920, height: 1050)
        let windows = [FullScreenCoverage.Window(layer: 0, bounds: zoomed, ownerPID: otherPID)]
        #expect(!FullScreenCoverage.isCovered(screenFrame: screen, windows: windows, ownPID: ownPID))
    }

    @Test func menuBarAndOverlayLayersAreIgnored() {
        let windows = [
            FullScreenCoverage.Window(layer: 24, bounds: screen, ownerPID: otherPID),
            FullScreenCoverage.Window(layer: 20, bounds: screen, ownerPID: otherPID),
        ]
        #expect(!FullScreenCoverage.isCovered(screenFrame: screen, windows: windows, ownPID: ownPID))
    }

    @Test func ownWindowsAreIgnored() {
        let windows = [FullScreenCoverage.Window(layer: 0, bounds: screen, ownerPID: ownPID)]
        #expect(!FullScreenCoverage.isCovered(screenFrame: screen, windows: windows, ownPID: ownPID))
    }

    @Test func fullScreenWindowOnAnotherDisplayDoesNotCover() {
        let otherDisplay = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let windows = [FullScreenCoverage.Window(layer: 0, bounds: otherDisplay, ownerPID: otherPID)]
        #expect(!FullScreenCoverage.isCovered(screenFrame: screen, windows: windows, ownPID: ownPID))
    }

    @Test func appKitFramesConvertToCoreGraphicsCoordinates() {
        // A 1920×1080 display stacked above a 1800×1169 primary display.
        let external = CGRect(x: -60, y: 1169, width: 1920, height: 1080)
        let converted = FullScreenCoverage.coreGraphicsRect(fromAppKit: external, primaryScreenHeight: 1169)
        #expect(converted == CGRect(x: -60, y: -1080, width: 1920, height: 1080))

        let primary = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        #expect(FullScreenCoverage.coreGraphicsRect(fromAppKit: primary, primaryScreenHeight: 1169) == primary)
    }
}

struct NotchVisibilityTests {
    @Test func physicalNotchIsAlwaysVisible() {
        for state in NotchPresentationState.allCases {
            #expect(NotchVisibility.isVisible(state: state, hasPhysicalNotch: true, isFullScreenCovered: true))
        }
    }

    @Test func virtualNotchIsVisibleWithoutFullScreen() {
        for state in NotchPresentationState.allCases {
            #expect(NotchVisibility.isVisible(state: state, hasPhysicalNotch: false, isFullScreenCovered: false))
        }
    }

    @Test func virtualNotchHidesAtRestOverFullScreen() {
        #expect(!NotchVisibility.isVisible(state: .idle, hasPhysicalNotch: false, isFullScreenCovered: true))
        #expect(!NotchVisibility.isVisible(state: .liveActivity, hasPhysicalNotch: false, isFullScreenCovered: true))
    }

    @Test func virtualNotchShowsTransientStatesOverFullScreen() {
        for state in NotchPresentationState.allCases where state.isTransient {
            #expect(NotchVisibility.isVisible(state: state, hasPhysicalNotch: false, isFullScreenCovered: true))
        }
    }
}

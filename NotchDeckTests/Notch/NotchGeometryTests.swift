import CoreGraphics
import Testing
@testable import NotchDeck

struct NotchGeometryTests {
    /// Values reported by a 14" MacBook Pro positioned below-left of an external display.
    private let builtInFrame = CGRect(x: -883, y: -1169, width: 1800, height: 1169)

    @Test func physicalNotchIsDerivedFromAuxiliaryAreas() {
        let geometry = NotchGeometry.make(
            screenFrame: builtInFrame,
            safeAreaTopInset: 38,
            auxiliaryTopLeftArea: CGRect(x: -883, y: -38, width: 790, height: 38),
            auxiliaryTopRightArea: CGRect(x: 127, y: -38, width: 790, height: 38),
            menuBarHeight: 38
        )

        #expect(geometry.hasPhysicalNotch)
        #expect(geometry.notchFrame == CGRect(x: -93, y: -38, width: 220, height: 38))
        #expect(geometry.notchFrame.maxY == builtInFrame.maxY)
    }

    @Test func screenWithoutSafeAreaGetsVirtualNotch() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry.make(
            screenFrame: frame,
            safeAreaTopInset: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            menuBarHeight: 30
        )

        #expect(!geometry.hasPhysicalNotch)
        #expect(geometry.notchFrame == CGRect(x: 870, y: 1050, width: 180, height: 30))
    }

    @Test func virtualNotchHasMinimumHeight() {
        let geometry = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            safeAreaTopInset: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            menuBarHeight: 0
        )

        #expect(geometry.notchSize.height == NotchGeometry.minimumVirtualNotchHeight)
    }

    @Test func missingAuxiliaryAreasFallBackToVirtualNotch() {
        let geometry = NotchGeometry.make(
            screenFrame: builtInFrame,
            safeAreaTopInset: 38,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            menuBarHeight: 38
        )

        #expect(!geometry.hasPhysicalNotch)
        #expect(geometry.notchFrame.midX == builtInFrame.midX)
    }

    @Test func topCenteredFrameIsFlushWithScreenTopAndCenteredOnNotch() {
        let geometry = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            safeAreaTopInset: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            menuBarHeight: 24
        )

        let frame = geometry.topCenteredFrame(size: CGSize(width: 400, height: 200))

        #expect(frame == CGRect(x: 760, y: 880, width: 400, height: 200))
    }

    // MARK: Screen selection

    @Test func automaticPrefersNotchedScreenEvenWhenNotPrimary() {
        let candidates = [
            NotchScreenSelector.Candidate(hasPhysicalNotch: false),
            NotchScreenSelector.Candidate(hasPhysicalNotch: true),
            NotchScreenSelector.Candidate(hasPhysicalNotch: false),
        ]
        #expect(NotchScreenSelector.select(from: candidates, preference: .automatic) == 1)
        #expect(NotchScreenSelector.select(from: candidates, preference: .primary) == 0)
    }

    @Test func automaticFallsBackToPrimaryWithoutNotch() {
        let candidates = [NotchScreenSelector.Candidate(hasPhysicalNotch: false), .init(hasPhysicalNotch: false)]
        #expect(NotchScreenSelector.select(from: candidates, preference: .automatic) == 0)
    }

    @Test func noScreensSelectsNothing() {
        #expect(NotchScreenSelector.select(from: [], preference: .automatic) == nil)
    }

    // MARK: Layout

    @Test func idleSurfaceMatchesNotchExactly() {
        let notch = CGSize(width: 220, height: 38)
        let metrics = NotchLayout.metrics(for: .idle, notchSize: notch)
        #expect(metrics.outerSize == notch)
    }

    @Test func surfacesGrowWithDisclosureLevel() {
        let notch = CGSize(width: 220, height: 38)
        let sizes = [NotchPresentationState.idle, .liveActivity, .peek, .expanded].map {
            NotchLayout.metrics(for: $0, notchSize: notch).outerSize
        }
        for (smaller, larger) in zip(sizes, sizes.dropFirst()) {
            #expect(larger.width > smaller.width)
            #expect(larger.height >= smaller.height)
        }
    }

    @Test func liveActivityKeepsNotchHeight() {
        let notch = CGSize(width: 220, height: 38)
        #expect(NotchLayout.metrics(for: .liveActivity, notchSize: notch).outerSize.height == 38)
    }
}

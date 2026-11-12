import XCTest
@testable import Strand

final class CoachScrollFollowStateTests: XCTestCase {
    private func observe(_ state: inout CoachScrollFollowState, distance: Double,
                         content: Double = 1_000, viewport: Double = 600) -> Bool {
        state.observe(distanceFromBottom: distance, contentHeight: content,
                      viewportHeight: viewport, nearBottomThreshold: 64)
    }

    func testStreamGrowthFollowsOnlyAfterLayoutActuallyGrows() {
        var state = CoachScrollFollowState()
        XCTAssertTrue(observe(&state, distance: 0))
        XCTAssertFalse(observe(&state, distance: 0), "No per-token follow for unchanged layout")
        XCTAssertTrue(observe(&state, distance: 150, content: 1_150))
        XCTAssertTrue(state.followsLatest, "New content is not evidence of a user scrolling away")
        XCTAssertFalse(observe(&state, distance: 0, content: 1_150), "Programmatic follow cannot loop")
    }

    func testReadingEarlierReplyStopsFollowAndStreamCannotReenableIt() {
        var state = CoachScrollFollowState()
        _ = observe(&state, distance: 0)
        XCTAssertFalse(observe(&state, distance: 200))
        XCTAssertFalse(state.followsLatest)
        XCTAssertFalse(observe(&state, distance: 350, content: 1_150))
        XCTAssertFalse(state.shouldFollow)
    }

    func testInteractionPausesBeforeNextGeometryMeasurementArrives() {
        var state = CoachScrollFollowState()
        _ = observe(&state, distance: 0)
        state.beginInteraction(towardHistory: true)
        XCTAssertFalse(state.shouldFollow)
        XCTAssertFalse(observe(&state, distance: 200, content: 1_200))
        state.endInteraction()
        XCTAssertFalse(state.shouldFollow)
    }

    func testReturningNearBottomResumesForTheNextStreamGrowth() {
        var state = CoachScrollFollowState()
        _ = observe(&state, distance: 0)
        _ = observe(&state, distance: 200)
        XCTAssertFalse(observe(&state, distance: 40))
        XCTAssertTrue(state.shouldFollow)
        XCTAssertTrue(observe(&state, distance: 140, content: 1_100))
    }

    func testKeyboardResizeDoesNotTakeReaderAwayFromEarlierReply() {
        var state = CoachScrollFollowState()
        _ = observe(&state, distance: 0)
        _ = observe(&state, distance: 250)
        XCTAssertFalse(observe(&state, distance: 500, viewport: 350))
        XCTAssertFalse(state.shouldFollow)
        state.showLatest()
        XCTAssertTrue(state.shouldFollow)
        XCTAssertTrue(observe(&state, distance: 250, viewport: 600))
    }

    func testKeyboardOffsetBeforeViewportMeasurementKeepsOriginalFollowDecision() {
        var state = CoachScrollFollowState()
        _ = observe(&state, distance: 0)
        state.beginViewportTransition()
        XCTAssertFalse(observe(&state, distance: 280), "System offset can arrive before viewport geometry")
        XCTAssertTrue(state.shouldFollow)
        XCTAssertTrue(observe(&state, distance: 280, viewport: 320))
        XCTAssertTrue(state.completeViewportTransition(), "One settled correction is still required")
        XCTAssertFalse(state.completeViewportTransition(), "Duplicate keyboard completion does not scroll again")
    }

    func testKeyboardTransitionDoesNotResumeHistoryReaderWhenIntermediateLayoutLooksNearBottom() {
        var state = CoachScrollFollowState()
        _ = observe(&state, distance: 0)
        _ = observe(&state, distance: 250)
        state.beginViewportTransition()
        _ = observe(&state, distance: 0, viewport: 680)
        state.beginViewportTransition() // Repeated will-change notification must not replace intent.
        XCTAssertFalse(state.completeViewportTransition())
        XCTAssertFalse(state.shouldFollow)
    }

    func testUserNavigationCancelsPendingKeyboardCorrection() {
        var state = CoachScrollFollowState()
        _ = observe(&state, distance: 0)
        state.beginViewportTransition()
        state.beginInteraction(towardHistory: true)
        state.endInteraction()
        _ = observe(&state, distance: 300, viewport: 320)
        XCTAssertFalse(state.completeViewportTransition())
        XCTAssertFalse(state.shouldFollow)
    }

    func testInvalidLayoutCannotResetReadingPosition() {
        var state = CoachScrollFollowState()
        state.pause()
        let before = state
        XCTAssertFalse(observe(&state, distance: .nan))
        XCTAssertFalse(observe(&state, distance: 0, viewport: 0))
        XCTAssertEqual(state, before)
    }

    func testInitialHistoryPlacementYieldsToAnyUserNavigation() {
        var state = CoachScrollFollowState()
        _ = observe(&state, distance: 1_400, content: 2_000)
        XCTAssertFalse(state.isNearBottom)
        XCTAssertTrue(state.canPositionInitialTranscript, "Initial long history needs placement after layout")
        state.beginInteraction(towardHistory: false)
        state.endInteraction()
        _ = observe(&state, distance: 0, content: 2_000)
        XCTAssertTrue(state.shouldFollow)
        XCTAssertFalse(state.canPositionInitialTranscript, "A later initial-placement retry cannot steal navigation")
    }
}

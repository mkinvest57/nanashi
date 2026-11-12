import Foundation

/// Presentation-only policy: growing content can follow a reader already at the end, but must not
/// pull someone away from an earlier reply. Layout measurements also cover trackpad/VoiceOver scrolls.
struct CoachScrollFollowState: Equatable {
    private(set) var followsLatest = true
    private(set) var isInteracting = false
    private(set) var isNearBottom = true
    private var hasUserNavigated = false
    private var lastDistance: Double?
    private var lastContentHeight: Double?
    private var lastViewportHeight: Double?
    private var viewportTransitionFollow: Bool?

    var shouldFollow: Bool { followsLatest && !isInteracting }
    var canPositionInitialTranscript: Bool { shouldFollow && !hasUserNavigated }
    var isViewportTransitionPending: Bool { viewportTransitionFollow != nil }

    /// Keyboard layout can publish an offset change before its new viewport size. Preserve the
    /// reader's intent at the start instead of treating that system movement as history navigation.
    mutating func beginViewportTransition() {
        if viewportTransitionFollow == nil { viewportTransitionFollow = shouldFollow }
    }

    /// Called once the system finishes resizing. Explicit navigation during the transition wins.
    mutating func completeViewportTransition() -> Bool {
        defer { viewportTransitionFollow = nil }
        guard viewportTransitionFollow == true, !isInteracting else { return false }
        followsLatest = true
        return true
    }

    mutating func cancelViewportTransition() { viewportTransitionFollow = nil }

    mutating func beginInteraction(towardHistory: Bool) {
        isInteracting = true
        hasUserNavigated = true
        if viewportTransitionFollow != nil { viewportTransitionFollow = false }
        if towardHistory { followsLatest = false }
    }

    mutating func endInteraction() { isInteracting = false }
    mutating func pause() {
        followsLatest = false
        hasUserNavigated = true
        if viewportTransitionFollow != nil { viewportTransitionFollow = false }
    }
    mutating func showLatest() {
        followsLatest = true
        if viewportTransitionFollow != nil { viewportTransitionFollow = true }
    }

    /// Returns whether a content/viewport layout change needs one follow operation. Offset-only
    /// changes are observations, never reasons to request another scroll and start a feedback loop.
    mutating func observe(distanceFromBottom: Double, contentHeight: Double,
                          viewportHeight: Double, nearBottomThreshold: Double) -> Bool {
        guard distanceFromBottom.isFinite, contentHeight.isFinite, viewportHeight.isFinite,
              contentHeight >= 0, viewportHeight > 0 else { return false }
        let contentChanged = lastContentHeight.map { abs($0 - contentHeight) > 0.5 } ?? true
        let viewportChanged = lastViewportHeight.map { abs($0 - viewportHeight) > 0.5 } ?? true
        let movedAway = lastDistance.map { distanceFromBottom > $0 + 1 } ?? false
        isNearBottom = distanceFromBottom <= nearBottomThreshold
        if viewportTransitionFollow == nil && isNearBottom {
            followsLatest = true
        } else if viewportTransitionFollow == nil && !contentChanged && !viewportChanged && movedAway {
            followsLatest = false
        }
        lastDistance = distanceFromBottom
        lastContentHeight = contentHeight
        lastViewportHeight = viewportHeight
        return shouldFollow && (contentChanged || viewportChanged)
    }
}

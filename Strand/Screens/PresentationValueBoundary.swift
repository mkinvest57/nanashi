import SwiftUI

/// A presentation factory whose inputs are explicit values. Parent-only updates do not rebuild the
/// expensive subtree; its own State and environment-object observations still update normally.
/// Include every captured presentation input in `revision`. Actions may capture stable State bindings.
/// Snapshot DynamicProperty values before constructing the factory; reading them inside its body
/// would create an independent subscription that intentionally bypasses Equatable comparison.
struct PresentationValueBoundary<Revision: Equatable, Content: View>: View, Equatable {
    let revision: Revision
    @ViewBuilder let content: () -> Content

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.revision == rhs.revision }

    var body: some View { content() }
}

/// A lazy stack can defer a View's body, but it cannot defer an expensive view-builder function
/// called while constructing its children. Keep section factories behind this body boundary.
struct DeferredPresentation<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}

private struct PresentationIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Visibility of the owning page, independent of whether contextual AI is enabled.
    /// Standalone screens and sheets remain active unless a retaining tab container scopes them.
    var presentationIsActive: Bool {
        get { self[PresentationIsActiveKey.self] }
        set { self[PresentationIsActiveKey.self] = newValue }
    }
}

/// Shared by successive value copies of one mounted screen. Async callbacks can see the latest
/// visibility after an await, even when their original View captured an older environment value.
@MainActor
final class PresentationActivityState {
    var isActive = true
}

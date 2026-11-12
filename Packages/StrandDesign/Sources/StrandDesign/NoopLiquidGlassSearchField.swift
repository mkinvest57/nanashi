import SwiftUI

// MARK: - Glass search field
//
// Native field with the Glass Button (21st 4922) material; Preferences Card still
// supplies the layout. Focus, clearing and the native TextField remain functional.

/// Full-width bordered search field with a native focus ring and clearing control.
public struct NoopLiquidGlassSearchField: View {
    @Binding private var text: String
    private let prompt: String
    private let accessibilityPrompt: String
    private var externalFocus: FocusState<Bool>.Binding?
    @FocusState private var internalFocus: Bool

    public init(text: Binding<String>,
                prompt: String,
                accessibilityLabel: String? = nil,
                isFocused: FocusState<Bool>.Binding? = nil) {
        self._text = text
        self.prompt = prompt
        self.accessibilityPrompt = accessibilityLabel ?? prompt
        self.externalFocus = isFocused
    }

    public var body: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "magnifyingglass")
                .font(StrandFont.body.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .focused(focusBinding)
                .submitLabel(.search)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(StrandFont.body.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(width: NoopMetrics.formRowMinHeight, height: NoopMetrics.formRowMinHeight)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, NoopMetrics.space3)
        .frame(minHeight: NoopMetrics.controlHeight)
        .background(NoopGlassControlSurface())
        .overlay(RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous)
            .strokeBorder(focusBinding.wrappedValue ? StrandPalette.focusRing : .clear,
                          lineWidth: NoopMetrics.lineWidth))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityPrompt))
    }

    private var focusBinding: FocusState<Bool>.Binding {
        externalFocus ?? $internalFocus
    }
}

public extension View {
    /// Source-compatible helper for the shared frosted input surface.
    @ViewBuilder
    func nativeLiquidGlassSearchChrome() -> some View {
        self.noopStandardSearchChrome()
    }

    /// Circular / capsule interactive Liquid Glass button chrome (Home header, live-workout controls,
    /// workout-selection close/chips). iOS 26 only; every other platform keeps the caller's
    /// `fallback` (standard material / press style) unchanged.
    @ViewBuilder
    func nativeLiquidGlassButtonChrome<Fallback: View>(
        controlSize: ControlSize = .small,
        capsule: Bool = false,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        fallback()
    }

    /// Interactive circular `glassEffect` finish layer (e.g. Home profile photo over glass).
    /// No-op outside iOS 26 so macOS never imports the glass path.
    @ViewBuilder
    func nativeLiquidGlassCircleFinish() -> some View {
        self
    }

    @ViewBuilder
    private func noopStandardSearchChrome() -> some View {
        self.background(
            NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius, elevated: false)
        )
    }
}

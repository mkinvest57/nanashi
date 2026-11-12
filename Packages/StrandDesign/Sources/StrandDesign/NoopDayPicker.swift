#if !os(watchOS)
import SwiftUI

/// Sizing retained from DayNavBar's native calendar, centralized for both day-navigation hosts.
private enum NoopDayPickerMetrics {
    static let minimumWidth: CGFloat = 320
    static let minimumHeight: CGFloat = 360
}

public extension View {
    /// Drawer (21st 31360): a phone-width sheet gives the native calendar an actual viewport.
    /// The caller's binding retains its date/offset semantics and commits only a selected date.
    func noopDayPicker(isPresented: Binding<Bool>, selection: Binding<Date>, latestDate: Date) -> some View {
        modifier(NoopDayPickerPresentation(isPresented: isPresented, selection: selection,
                                           latestDate: latestDate))
    }
}

private struct NoopDayPickerPresentation: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selection: Date
    let latestDate: Date

    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(isPresented: $isPresented) {
            NavigationStack {
                GeometryReader { viewport in
                    ScrollView {
                        calendar
                            .frame(width: max(0, viewport.size.width - NoopMetrics.cardPadding * 2))
                            .padding(NoopMetrics.cardPadding)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .background(StrandPalette.surfaceBase)
                .navigationTitle(Text("Pick a date", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { isPresented = false } label: {
                            Text("Cancel", bundle: .module)
                        }
                        .accessibilityIdentifier("nanashi.calendar.cancel")
                    }
                }
            }
            .tint(StrandPalette.accentInk)
            .modifier(NoopSheetModifier(largeFirst: true))
        }
        #else
        content.popover(isPresented: $isPresented) {
            calendar
                .frame(minWidth: NoopDayPickerMetrics.minimumWidth)
                .padding(NoopMetrics.space3)
        }
        #endif
    }

    private var calendar: some View {
        DatePicker(selection: $selection, in: ...latestDate, displayedComponents: [.date]) {
            Text("Pick a date", bundle: .module)
        }
        .datePickerStyle(.graphical)
        .labelsHidden()
        .frame(minHeight: NoopDayPickerMetrics.minimumHeight, alignment: .top)
        .accessibilityIdentifier("nanashi.calendar.grid")
    }
}
#endif

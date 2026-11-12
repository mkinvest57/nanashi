import AppKit
import SwiftUI
import XCTest
@testable import Strand

/// Exercise a real SwiftUI hosting tree: parent chrome changes must not rebuild a page factory,
/// while page input changes and the child's own model must still render without losing State.
@MainActor
final class PresentationValueBoundaryTests: XCTestCase {
    private final class Inputs: ObservableObject {
        @Published var page = 0
        @Published var chrome = 0
    }

    private final class ChildModel: ObservableObject {
        @Published var value = 0
    }

    private final class Probe {
        var factories = 0
        var renders: [(page: Int, value: Int, identity: UUID)] = []

        func makePage(_ page: Int) -> Page {
            factories += 1
            return Page(page: page, probe: self)
        }
    }

    private struct Page: View {
        let page: Int
        let probe: Probe
        @EnvironmentObject private var model: ChildModel
        @State private var identity = UUID()

        var body: some View {
            probe.renders.append((page, model.value, identity))
            return Text("\(page):\(model.value)")
        }
    }

    private struct Harness: View {
        @ObservedObject var inputs: Inputs
        let probe: Probe

        var body: some View {
            // Snapshot the actual page input outside the factory. Reading the ObservedObject inside
            // the closure would subscribe the boundary itself to every publication, including chrome.
            let page = inputs.page
            let pageProbe = probe
            return VStack {
                Text("\(inputs.chrome)")
                PresentationValueBoundary(revision: page) {
                    pageProbe.makePage(page)
                }
                .equatable()
            }
        }
    }

    func testParentChromeDoesNotRebuildPageFactoryButPageInputDoes() throws {
        let inputs = Inputs()
        let model = ChildModel()
        let probe = Probe()
        let host = NSHostingView(rootView: Harness(inputs: inputs, probe: probe).environmentObject(model))
        settle(host)
        XCTAssertGreaterThan(probe.factories, 0)
        let initialIdentity = try XCTUnwrap(probe.renders.last?.identity)

        // The macOS 27 hosting tree performs one bootstrap parent update without consulting `==`.
        // Establish that baseline, then require exact reuse across repeated settled-tree updates.
        inputs.chrome += 1
        settle(host)
        let settledFactories = probe.factories
        for _ in 0..<5 {
            inputs.chrome += 1
            settle(host)
            XCTAssertEqual(probe.factories, settledFactories)
        }

        inputs.page = 1
        settle(host)
        XCTAssertGreaterThan(probe.factories, settledFactories)
        XCTAssertEqual(probe.renders.last?.page, 1)
        XCTAssertEqual(probe.renders.last?.identity, initialIdentity, "Input changes retain the same page's State.")
    }

    func testChildEnvironmentObjectStillUpdatesBehindUnchangedBoundary() throws {
        let inputs = Inputs()
        let model = ChildModel()
        let probe = Probe()
        let host = NSHostingView(rootView: Harness(inputs: inputs, probe: probe).environmentObject(model))
        settle(host)
        let initialFactories = probe.factories
        let initialIdentity = try XCTUnwrap(probe.renders.last?.identity)

        model.value = 42
        settle(host)
        XCTAssertEqual(probe.factories, initialFactories)
        XCTAssertEqual(probe.renders.last?.value, 42)
        XCTAssertEqual(probe.renders.last?.identity, initialIdentity)
    }

    private func settle<V: View>(_ host: NSHostingView<V>) {
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

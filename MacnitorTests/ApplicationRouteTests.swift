import MetricsKit
import XCTest
@testable import Macnitor

final class ApplicationRouteTests: XCTestCase {
    func testEveryAllowlistedRouteRoundTrips() {
        let routes: [ApplicationRoute] = [
            .overview,
            .metric(.cpu),
            .metric(.memory),
            .metric(.battery),
            .metric(.network),
            .metric(.disk),
            .metric(.gpu),
            .metric(.sensors),
            .metric(.fans),
            .menuBar,
            .alerts,
            .attentionLog,
            .about,
            .whatsNew,
            .diagnostics
        ]

        for route in routes {
            XCTAssertEqual(ApplicationRoute(url: route.url), route)
        }
    }

    func testPreviousMacitorMactricsAndMectricsLinksRemainAcceptedButNewLinksUseMacnitorScheme() {
        XCTAssertEqual(ApplicationRoute(url: URL(string: "macitor://overview")!), .overview)
        XCTAssertEqual(ApplicationRoute(url: URL(string: "mactrics://overview")!), .overview)
        XCTAssertEqual(ApplicationRoute(url: URL(string: "mectrics://overview")!), .overview)
        XCTAssertEqual(ApplicationRoute.overview.url.scheme, "macnitor")
    }

    func testRejectsUnknownAndMalformedRoutes() {
        let rejected = [
            "https://overview",
            "macnitor://unknown",
            "macnitor://metric",
            "macnitor://metric/not-a-metric",
            "macnitor://metric/clock",
            "macnitor://metric/cpu/extra",
            "macnitor://alerts/extra",
            "macnitor://menu-bar/extra",
            "macnitor://menubar",
            "macnitor://overview?command=quit",
            "macnitor://overview#fragment",
            "macnitor://user@example.com/overview",
            "macnitor://overview:1234"
        ]

        for rawURL in rejected {
            XCTAssertNil(ApplicationRoute(url: URL(string: rawURL)!))
        }
    }

    func testMetricIdentifiersAreCaseInsensitiveButRemainAllowlisted() {
        XCTAssertEqual(
            ApplicationRoute(url: URL(string: "macnitor://metric/CPU")!),
            .metric(.cpu)
        )
        XCTAssertNil(ApplicationRoute(url: URL(string: "macnitor://metric/cpu%2Falerts")!))
    }

    func testContextualActionsStayRestrainedAndMetricSpecific() {
        XCTAssertEqual(
            MetricContextualAction.actions(for: .cpu, hasLocalAddress: false),
            [.activityMonitor]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .memory, hasLocalAddress: false),
            [.activityMonitor]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .disk, hasLocalAddress: false),
            [.storageSettings]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .battery, hasLocalAddress: false),
            [.batterySettings]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .network, hasLocalAddress: true),
            [.activityMonitor, .copyLocalAddress]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .network, hasLocalAddress: false),
            [.activityMonitor]
        )
        XCTAssertTrue(
            MetricContextualAction.actions(for: .sensors, hasLocalAddress: false).isEmpty
        )
        XCTAssertTrue(
            MetricContextualAction.actions(for: .fans, hasLocalAddress: false).isEmpty
        )
    }
}

import MetricsKit
import XCTest
@testable import Mactrics

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

    func testLegacyMectricsLinksRemainAcceptedButNewLinksUseMactricsScheme() {
        XCTAssertEqual(ApplicationRoute(url: URL(string: "mectrics://overview")!), .overview)
        XCTAssertEqual(ApplicationRoute.overview.url.scheme, "mactrics")
    }

    func testRejectsUnknownAndMalformedRoutes() {
        let rejected = [
            "https://overview",
            "mactrics://unknown",
            "mactrics://metric",
            "mactrics://metric/not-a-metric",
            "mactrics://metric/clock",
            "mactrics://metric/cpu/extra",
            "mactrics://alerts/extra",
            "mactrics://menu-bar/extra",
            "mactrics://menubar",
            "mactrics://overview?command=quit",
            "mactrics://overview#fragment",
            "mactrics://user@example.com/overview",
            "mactrics://overview:1234"
        ]

        for rawURL in rejected {
            XCTAssertNil(ApplicationRoute(url: URL(string: rawURL)!))
        }
    }

    func testMetricIdentifiersAreCaseInsensitiveButRemainAllowlisted() {
        XCTAssertEqual(
            ApplicationRoute(url: URL(string: "mactrics://metric/CPU")!),
            .metric(.cpu)
        )
        XCTAssertNil(ApplicationRoute(url: URL(string: "mactrics://metric/cpu%2Falerts")!))
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

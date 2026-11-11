import XCTest
@testable import Macnitor

final class DuoBarGlyphStateTests: XCTestCase {
    func testDuoBarPreferenceDefaultsOffAndPersistsChoice() {
        let defaults = UserDefaults(suiteName: "DuoBarPreferenceTests-\(UUID().uuidString)")!
        XCTAssertFalse(DuoBarPreference.value(from: defaults))
        defaults.set(true, forKey: DuoBarPreference.key)
        XCTAssertTrue(DuoBarPreference.value(from: defaults))
    }

    func testBatteryProgressClampsAndMissingBatteryRemainsAbsent() {
        XCTAssertNil(DuoBarGlyphState(batteryPercentage: nil, isCharging: true, wifi: .unavailable, bluetooth: .unavailable).batteryProgress)
        XCTAssertEqual(DuoBarGlyphState(batteryPercentage: -4, isCharging: false, wifi: .unavailable, bluetooth: .off).batteryProgress, 0)
        XCTAssertEqual(DuoBarGlyphState(batteryPercentage: 105, isCharging: false, wifi: .unavailable, bluetooth: .off).batteryProgress, 1)
    }

    func testChargingDoesNotShowAtFullBattery() {
        XCTAssertTrue(DuoBarGlyphState(batteryPercentage: 99, isCharging: true, wifi: .weak, bluetooth: .on).isCharging)
        XCTAssertFalse(DuoBarGlyphState(batteryPercentage: 100, isCharging: true, wifi: .weak, bluetooth: .on).isCharging)
    }

    func testWiFiSignalThresholdsAndUnavailableStates() {
        XCTAssertEqual(DuoBarWiFiSignal.resolve(isAvailable: true, isConnected: true, rssi: -60), .strong)
        XCTAssertEqual(DuoBarWiFiSignal.resolve(isAvailable: true, isConnected: true, rssi: -70), .medium)
        XCTAssertEqual(DuoBarWiFiSignal.resolve(isAvailable: true, isConnected: true, rssi: -80), .weak)
        XCTAssertEqual(DuoBarWiFiSignal.resolve(isAvailable: true, isConnected: false, rssi: nil), .disconnected)
        XCTAssertEqual(DuoBarWiFiSignal.resolve(isAvailable: false, isConnected: false, rssi: nil), .unavailable)
    }

    func testBluetoothDotPresentation() {
        XCTAssertEqual(DuoBarGlyphState(batteryPercentage: nil, isCharging: false, wifi: .unavailable, bluetooth: .on).bluetoothDotCount, 4)
        XCTAssertEqual(DuoBarGlyphState(batteryPercentage: nil, isCharging: false, wifi: .unavailable, bluetooth: .off).bluetoothDotCount, 0)
        XCTAssertEqual(DuoBarGlyphState(batteryPercentage: nil, isCharging: false, wifi: .unavailable, bluetooth: .unavailable).bluetoothDotCount, 1)
    }

    func testBatteryColorCodingResolution() {
        // Off never colours the ring.
        XCTAssertEqual(
            DuoBarBatteryColor.resolve(colorCodingEnabled: false, isCharging: true, isLowPowerModeEnabled: true, batteryLevel: 0.05),
            .monochrome
        )
        // Charging wins over every other state.
        XCTAssertEqual(
            DuoBarBatteryColor.resolve(colorCodingEnabled: true, isCharging: true, isLowPowerModeEnabled: true, batteryLevel: 0.05),
            .charging
        )
        XCTAssertEqual(
            DuoBarBatteryColor.resolve(colorCodingEnabled: true, isCharging: false, isLowPowerModeEnabled: true, batteryLevel: 0.05),
            .lowPowerMode
        )
        XCTAssertEqual(
            DuoBarBatteryColor.resolve(colorCodingEnabled: true, isCharging: false, isLowPowerModeEnabled: false, batteryLevel: 0.19),
            .lowBattery
        )
        XCTAssertEqual(
            DuoBarBatteryColor.resolve(colorCodingEnabled: true, isCharging: false, isLowPowerModeEnabled: false, batteryLevel: 0.2),
            .monochrome
        )
        XCTAssertEqual(
            DuoBarBatteryColor.resolve(colorCodingEnabled: true, isCharging: false, isLowPowerModeEnabled: false, batteryLevel: nil),
            .monochrome
        )
    }
}

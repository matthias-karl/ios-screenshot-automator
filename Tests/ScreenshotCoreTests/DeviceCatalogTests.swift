import Foundation
import Testing
@testable import ScreenshotCore

@Suite struct DeviceCatalogTests {
    @Test func parsesDuoWithTwoDisplays() throws {
        let duo = try DeviceCatalog.parseCapabilities(try Fixtures.data("capabilities-duo.plist"), name: "iPhone Duo")
        #expect(duo.displays.map(\.name) == ["primary", "primary-1"])
        #expect(duo.displays[0].pixelSize == PixelSize(width: 1398, height: 2034))
        #expect(duo.displays[0].cornerRadii == CornerRadii(upperLeft: 8, upperRight: 59, lowerLeft: 8, lowerRight: 59))
        #expect(duo.displays[1].pixelSize == PixelSize(width: 2007, height: 2853))
        #expect(duo.displays[1].cornerRadii == CornerRadii(upperLeft: 55, upperRight: 55, lowerLeft: 55, lowerRight: 55))
        #expect(duo.hasDynamicIsland)
    }

    @Test func ignoresNonIntegratedDisplays() throws {
        let phone = try DeviceCatalog.parseCapabilities(try Fixtures.data("capabilities-iphone.plist"), name: "iPhone 18 Pro")
        #expect(phone.displays.map(\.name) == ["primary"])
        #expect(phone.displays[0].scale == 3)
    }

    @Test func appleTVFallsBackToMainScreen() throws {
        let tv = try DeviceCatalog.parseCapabilities(try Fixtures.data("capabilities-appletv.plist"), name: "Apple TV")
        #expect(tv.displays == [DisplaySpec(
            name: "primary", pixelSize: .init(width: 1920, height: 1080), scale: 1,
            cornerRadii: .init(upperLeft: 0, upperRight: 0, lowerLeft: 0, lowerRight: 0))])
        #expect(!tv.hasDynamicIsland)
    }

    @Test func garbagePlistThrows() {
        #expect(throws: DeviceCatalogError.self) {
            try DeviceCatalog.parseCapabilities(Data("not a plist".utf8), name: "X")
        }
    }

    @Test func loadReadsTypesAndSimulators() throws {
        let runner = FakeRunner()
        runner.stub(prefix: ["xcrun", "simctl", "list", "-j", "devicetypes"], result: .ok(String(decoding: try Fixtures.data("devicetypes.json"), as: UTF8.self)))
        runner.stub(prefix: ["xcrun", "simctl", "list", "-j", "devices", "available"], result: .ok(String(decoding: try Fixtures.data("devices.json"), as: UTF8.self)))
        let plists = [
            "iPhone 18 Pro.simdevicetype": "capabilities-iphone.plist",
            "iPhone Duo.simdevicetype": "capabilities-duo.plist",
            "Apple TV.simdevicetype": "capabilities-appletv.plist",
        ]
        let catalog = try DeviceCatalog.load(shell: runner) { url in
            // <bundle>/Contents/Resources/capabilities.plist
            let bundle = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            guard let name = plists[bundle] else { throw CocoaError(.fileNoSuchFile) }
            return try Fixtures.data(name)
        }
        // The type with an unreadable plist is skipped, not fatal.
        #expect(catalog.deviceTypes.map(\.name) == ["iPhone 18 Pro", "iPhone Duo", "Apple TV 4K (3rd generation) (at 1080p)"])
        #expect(catalog.deviceTypes[1].hasDynamicIsland)
        #expect(catalog.deviceTypes[1].minRuntimeVersion == 1769728)
        #expect(catalog.deviceTypes[2].family == "Apple TV")

        #expect(catalog.simulators.count == 2)
        let booted = try #require(catalog.simulators.first { $0.udid.hasSuffix("1") })
        #expect(booted.isBooted)
        #expect(booted.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
        #expect(booted.deviceTypeIdentifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro")
        let duo = try #require(catalog.simulators.first { $0.udid.hasSuffix("2") })
        #expect(!duo.isBooted)
    }

    @Test func simctlFailureThrows() {
        let runner = FakeRunner()
        runner.stub(prefix: ["xcrun"], result: .failure(stderr: "boom"))
        #expect(throws: DeviceCatalogError.self) { try DeviceCatalog.load(shell: runner) }
    }

    /// Smoke test against the real machine: needs Xcode 27.1 with the iPhone Duo simulator.
    @Test(.disabled("needs local Xcode"))
    func realMachineHasDuo() throws {
        let catalog = try DeviceCatalog.load(shell: ProcessRunner())
        let duo = try #require(catalog.deviceTypes.first { $0.name == "iPhone Duo" })
        #expect(duo.displays.count == 2)
    }
}

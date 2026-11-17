import Testing
@testable import ScreenshotCore

@Suite struct PlannerTests {
    // MARK: Fixtures

    static func display(_ w: Int, _ h: Int, name: String = "primary", scale: Double = 3, radius: Double = 62) -> DisplaySpec {
        DisplaySpec(name: name, pixelSize: PixelSize(width: w, height: h), scale: scale,
                    cornerRadii: CornerRadii(upperLeft: radius, upperRight: radius, lowerLeft: radius, lowerRight: radius))
    }

    static func type(_ name: String, family: String = "iPhone", min: Int, displays: [DisplaySpec], island: Bool = false) -> DeviceType {
        DeviceType(identifier: "type.\(name)", name: name, family: family, minRuntimeVersion: min,
                   displays: displays, hasDynamicIsland: island)
    }

    static func sim(_ name: String, runtime: String = "iOS-27-0", booted: Bool = false) -> Simulator {
        Simulator(udid: "UDID-\(name)-\(runtime)", name: name, deviceTypeIdentifier: "type.\(name)",
                  runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.\(runtime)", isBooted: booted)
    }

    static let duoDisplays = [
        display(1398, 2034, name: "primary", radius: 8),
        display(2007, 2853, name: "primary-1", radius: 55),
    ]

    static func catalog(ipad13: Bool = true) -> DeviceCatalog {
        var types = [
            type("iPhone 17 Pro", min: 1_703_936, displays: [display(1206, 2622)], island: true),
            type("iPhone 18 Pro", min: 1_769_472, displays: [display(1206, 2622)], island: true),
            type("iPhone 18 Pro Max", min: 1_769_472, displays: [display(1320, 2868)], island: true),
            type("iPhone Duo", min: 1_769_728, displays: duoDisplays, island: true),
            type("iPad Pro 11-inch (M5)", family: "iPad", min: 1_769_472, displays: [display(1668, 2420, scale: 2, radius: 20)]),
            type("Apple TV 4K (at 1080p)", family: "Apple TV", min: 1_048_832, displays: [display(1920, 1080, scale: 1, radius: 0)]),
            type("Apple TV 4K", family: "Apple TV", min: 1_048_832, displays: [display(3840, 2160, scale: 1, radius: 0)]),
        ]
        var sims = [
            sim("iPhone 17 Pro"), sim("iPhone 17 Pro", runtime: "iOS-27-1"),
            sim("iPhone 18 Pro"), sim("iPhone 18 Pro", runtime: "iOS-27-1"),
            sim("iPhone 18 Pro Max"), sim("iPhone Duo", runtime: "iOS-27-1"),
            sim("iPad Pro 11-inch (M5)"),
            sim("Apple TV 4K (at 1080p)", runtime: "tvOS-27-0"), sim("Apple TV 4K", runtime: "tvOS-27-0"),
        ]
        if ipad13 {
            types.append(type("iPad Pro 13-inch (M5)", family: "iPad", min: 1_769_472, displays: [display(2064, 2752, scale: 2, radius: 20)]))
            sims.append(sim("iPad Pro 13-inch (M5)"))
        }
        return DeviceCatalog(deviceTypes: types, simulators: sims)
    }

    static func config(
        platform: Platform = .iOS, sizes: [String], languages: [String] = ["de-DE", "en-US"],
        appearances: [Appearance] = [.light], landscape: [String] = []
    ) -> Config {
        Config(project: "A.xcodeproj",
               targets: [.init(platform: platform, scheme: "A", tests: "AUITests/Screenshots", sizes: sizes, landscape: landscape)],
               languages: languages, appearances: appearances)
    }

    func plan(_ config: Config, catalog: DeviceCatalog = PlannerTests.catalog(), filter: RunFilter = RunFilter()) throws -> [CaptureRun] {
        try Planner.plan(config: config, catalog: catalog, filter: filter)
    }

    // MARK: Simulator choice

    @Test func prefersNewestDeviceTypeWithMatchingDisplay() throws {
        let runs = try plan(Self.config(sizes: ["iphone-6.3"], languages: ["en-US"]))
        #expect(runs.count == 1)
        #expect(runs[0].deviceTypeName == "iPhone 18 Pro")
        #expect(runs[0].hasDynamicIsland)
        // Highest runtime of the chosen type.
        #expect(runs[0].simulator?.runtimeIdentifier.hasSuffix("iOS-27-1") == true)
        #expect(runs[0].display?.pixelSize == PixelSize(width: 1206, height: 2622))
    }

    @Test func duoSizesShareOneSimulatorButDifferInDisplay() throws {
        let runs = try plan(Self.config(sizes: ["iphone-duo-outer", "iphone-duo-inner"], languages: ["en-US"]))
        #expect(runs.count == 2)
        #expect(runs[0].simulator == runs[1].simulator)
        #expect(runs[0].display?.name == "primary")
        #expect(runs[1].display?.name == "primary-1")
    }

    @Test func foldableGetsNoDrawnIsland() throws {
        // The island position of a two-display device is unknown, so none is drawn for it.
        let runs = try plan(Self.config(sizes: ["iphone-duo-outer", "iphone-6.3"], languages: ["en-US"]))
        #expect(runs.map(\.hasDynamicIsland) == [false, true])
    }

    @Test func runsAreOrderedBySizeThenLanguageThenAppearance() throws {
        let runs = try plan(Self.config(sizes: ["iphone-6.3", "iphone-6.9"], appearances: [.light, .dark]))
        #expect(runs.count == 8)
        #expect(runs.map(\.slug) == [
            "iphone-6.3_de-DE_light", "iphone-6.3_de-DE_dark", "iphone-6.3_en-US_light", "iphone-6.3_en-US_dark",
            "iphone-6.9_de-DE_light", "iphone-6.9_de-DE_dark", "iphone-6.9_en-US_light", "iphone-6.9_en-US_dark",
        ])
        #expect(runs[0].slug == "iphone-6.3_de-DE_light")
    }

    @Test func missingSimulatorIsAnErrorEvenIfSmallerIPadExists() {
        let catalog = Self.catalog(ipad13: false)   // an iPad 11" IS installed
        #expect(throws: PlanError.noSimulator(
            size: "ipad-13", wanted: [PixelSize(width: 2064, height: 2752), PixelSize(width: 2048, height: 2732)]
        )) { try plan(Self.config(sizes: ["ipad-13"]), catalog: catalog) }
    }

    @Test func deviceTypeWithoutInstalledSimulatorIsNotAChoice() throws {
        var catalog = Self.catalog()
        catalog.simulators.removeAll { $0.name == "iPhone 18 Pro" }
        let runs = try plan(Self.config(sizes: ["iphone-6.3"], languages: ["en-US"]), catalog: catalog)
        #expect(runs[0].deviceTypeName == "iPhone 17 Pro")
    }

    @Test func unknownSizeIsAnError() {
        #expect(throws: PlanError.unknownSize("iphone-6.7")) { try plan(Self.config(sizes: ["iphone-6.7"])) }
    }

    // MARK: Platforms

    @Test func sizeOfOtherPlatformIsRejected() {
        #expect(throws: PlanError.wrongPlatform(size: "ipad-13", expected: .iOS)) {
            try plan(Self.config(platform: .tvOS, sizes: ["ipad-13"]))
        }
    }

    @Test func appleTVUsesLandscapeDisplayAndPrefersFullHD() throws {
        let runs = try plan(Self.config(platform: .tvOS, sizes: ["appletv"], languages: ["en-US"]))
        #expect(runs[0].deviceTypeName == "Apple TV 4K (at 1080p)")
        #expect(runs[0].landscape)
    }

    @Test func macNeedsNoSimulator() throws {
        let runs = try plan(Self.config(platform: .macOS, sizes: ["mac"], languages: ["en-US"]))
        #expect(runs[0].simulator == nil)
        #expect(runs[0].display == nil)
        #expect(runs[0].deviceTypeName == nil)
        #expect(!runs[0].hasDynamicIsland)
        #expect(runs[0].landscape)
    }

    @Test func landscapeFollowsTargetList() throws {
        let runs = try plan(Self.config(sizes: ["iphone-6.3", "ipad-13"], languages: ["en-US"], landscape: ["ipad-13"]))
        #expect(runs.map(\.landscape) == [false, true])
    }

    // MARK: Filter

    @Test func filterReducesRuns() throws {
        var filter = RunFilter()
        filter.sizes = ["iphone-6.3"]
        filter.languages = ["de-DE"]
        let runs = try plan(Self.config(sizes: ["iphone-6.3", "iphone-6.9"]), filter: filter)
        #expect(runs.map(\.slug) == ["iphone-6.3_de-DE_light"])
    }

    @Test func filterSkipsSizesWithoutSimulator() throws {
        var filter = RunFilter()
        filter.sizes = ["iphone-6.3"]
        let runs = try plan(Self.config(sizes: ["iphone-6.3", "ipad-13"]), catalog: Self.catalog(ipad13: false), filter: filter)
        #expect(runs.count == 2)
    }

    @Test func schemeFilterSelectsTargets() throws {
        var config = Self.config(sizes: ["iphone-6.3"], languages: ["en-US"])
        config.targets.append(.init(platform: .macOS, scheme: "Mac", tests: "M/S", sizes: ["mac"]))
        var filter = RunFilter()
        filter.scheme = "Mac"
        #expect(try plan(config, filter: filter).map(\.size.id) == ["mac"])
    }
}

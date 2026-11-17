import Foundation

/// One capture: a size in one language and appearance on one concrete simulator.
public struct CaptureRun: Equatable, Sendable {
    public var target: Config.Target
    public var size: StoreSize
    /// `nil` only on macOS.
    public var simulator: Simulator?
    /// The display the shots come from; `nil` only on macOS.
    public var display: DisplaySpec?
    public var deviceTypeName: String?
    public var hasDynamicIsland: Bool
    public var language: String
    public var appearance: Appearance
    public var landscape: Bool
    /// `<size.id>_<language>_<appearance>`
    public var slug: String

    public init(
        target: Config.Target, size: StoreSize, simulator: Simulator?, display: DisplaySpec?,
        deviceTypeName: String?, hasDynamicIsland: Bool, language: String, appearance: Appearance,
        landscape: Bool
    ) {
        self.target = target
        self.size = size
        self.simulator = simulator
        self.display = display
        self.deviceTypeName = deviceTypeName
        self.hasDynamicIsland = hasDynamicIsland
        self.language = language
        self.appearance = appearance
        self.landscape = landscape
        self.slug = "\(size.id)_\(language)_\(appearance.rawValue)"
    }
}

public struct RunFilter: Equatable, Sendable {
    public var sizes: Set<String>?
    public var languages: Set<String>?
    public var scheme: String?

    public init() {}
}

public enum PlanError: Error, Equatable, CustomStringConvertible {
    case unknownSize(String)
    case wrongPlatform(size: String, expected: Platform)
    case noSimulator(size: String, wanted: [PixelSize])

    public var description: String {
        switch self {
        case .unknownSize(let id):
            return "Unknown size \"\(id)\". Run `screenshots sizes` to list the known sizes."
        case .wrongPlatform(let size, let expected):
            return "Size \"\(size)\" belongs to a \(expected.rawValue) target, but it is listed in a target of another platform."
        case .noSimulator(let size, let wanted):
            let list = wanted.map { "\($0.width)×\($0.height)" }.joined(separator: ", ")
            return "No installed simulator has a display of \(list) (needed for \"\(size)\"). "
                + "Install a matching runtime/device in Xcode; the tool never substitutes another size."
        }
    }
}

public enum Planner {
    /// Maps the configuration to concrete runs: target → size → language → appearance.
    public static func plan(config: Config, catalog: DeviceCatalog, filter: RunFilter) throws -> [CaptureRun] {
        var runs: [CaptureRun] = []
        for target in config.targets {
            if let scheme = filter.scheme, scheme != target.scheme { continue }
            for sizeID in target.sizes {
                guard let size = StoreSizes.size(id: sizeID) else { throw PlanError.unknownSize(sizeID) }
                guard size.platform == target.platform else {
                    throw PlanError.wrongPlatform(size: sizeID, expected: size.platform)
                }
                if let sizes = filter.sizes, !sizes.contains(sizeID) { continue }

                let choice = try pick(size: size, catalog: catalog)
                let landscape = size.platform == .tvOS || size.platform == .macOS || target.landscape.contains(sizeID)
                for language in config.languages {
                    if let languages = filter.languages, !languages.contains(language) { continue }
                    for appearance in config.appearances {
                        runs.append(CaptureRun(
                            target: target, size: size,
                            simulator: choice?.simulator, display: choice?.display,
                            deviceTypeName: choice?.type.name, hasDynamicIsland: choice?.type.hasDynamicIsland ?? false,
                            language: language, appearance: appearance, landscape: landscape))
                    }
                }
            }
        }
        return runs
    }

    struct Choice {
        var type: DeviceType
        var display: DisplaySpec
        var simulator: Simulator
    }

    /// `nil` for macOS (no simulator). Otherwise the best installed match or `PlanError.noSimulator`.
    static func pick(size: StoreSize, catalog: DeviceCatalog) throws -> Choice? {
        if size.platform == .macOS { return nil }
        // tvOS displays are landscape; the table stores portrait sizes.
        let compareSwapped = size.platform == .tvOS

        struct Candidate { var type: DeviceType; var display: DisplaySpec; var rank: Int }
        var candidates: [Candidate] = []
        for type in catalog.deviceTypes where catalog.simulators.contains(where: { $0.deviceTypeIdentifier == type.identifier }) {
            for display in type.displays {
                let pixels = compareSwapped ? display.pixelSize.swapped : display.pixelSize
                if let rank = size.pixelSizes.firstIndex(of: pixels) {
                    candidates.append(Candidate(type: type, display: display, rank: rank))
                }
            }
        }
        candidates.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.type.minRuntimeVersion != $1.type.minRuntimeVersion { return $0.type.minRuntimeVersion > $1.type.minRuntimeVersion }
            return $0.type.name < $1.type.name
        }
        guard let best = candidates.first else {
            throw PlanError.noSimulator(size: size.id, wanted: size.pixelSizes)
        }
        let simulator = catalog.simulators
            .filter { $0.deviceTypeIdentifier == best.type.identifier }
            .max { $0.runtimeIdentifier.compare($1.runtimeIdentifier, options: .numeric) == .orderedAscending }!
        return Choice(type: best.type, display: best.display, simulator: simulator)
    }
}

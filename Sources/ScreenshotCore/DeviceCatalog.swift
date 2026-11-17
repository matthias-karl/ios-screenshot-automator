import Foundation

/// Corner radii in points, as in the simulator profile.
public struct CornerRadii: Equatable, Sendable {
    public var upperLeft: Double, upperRight: Double, lowerLeft: Double, lowerRight: Double

    public init(upperLeft: Double, upperRight: Double, lowerLeft: Double, lowerRight: Double) {
        self.upperLeft = upperLeft
        self.upperRight = upperRight
        self.lowerLeft = lowerLeft
        self.lowerRight = lowerRight
    }

    public static let zero = CornerRadii(upperLeft: 0, upperRight: 0, lowerLeft: 0, lowerRight: 0)
}

public struct DisplaySpec: Equatable, Sendable {
    /// `primary`, `primary-1` … as used by `simctl io --display=`.
    public var name: String
    public var pixelSize: PixelSize
    public var scale: Double
    public var cornerRadii: CornerRadii

    public init(name: String, pixelSize: PixelSize, scale: Double, cornerRadii: CornerRadii) {
        self.name = name
        self.pixelSize = pixelSize
        self.scale = scale
        self.cornerRadii = cornerRadii
    }
}

public struct DeviceType: Equatable, Sendable {
    public var identifier: String
    public var name: String
    public var family: String
    public var minRuntimeVersion: Int
    public var displays: [DisplaySpec]
    public var hasDynamicIsland: Bool

    public init(identifier: String, name: String, family: String, minRuntimeVersion: Int,
                displays: [DisplaySpec], hasDynamicIsland: Bool) {
        self.identifier = identifier
        self.name = name
        self.family = family
        self.minRuntimeVersion = minRuntimeVersion
        self.displays = displays
        self.hasDynamicIsland = hasDynamicIsland
    }
}

public struct Simulator: Equatable, Sendable {
    public var udid: String
    public var name: String
    public var deviceTypeIdentifier: String
    public var runtimeIdentifier: String
    public var isBooted: Bool

    public init(udid: String, name: String, deviceTypeIdentifier: String, runtimeIdentifier: String, isBooted: Bool) {
        self.udid = udid
        self.name = name
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.runtimeIdentifier = runtimeIdentifier
        self.isBooted = isBooted
    }
}

public enum DeviceCatalogError: Error, Equatable, CustomStringConvertible {
    case commandFailed(String)
    case unreadableOutput(String)
    case badCapabilities(device: String, reason: String)

    public var description: String {
        switch self {
        case .commandFailed(let message): return message
        case .unreadableOutput(let message): return "Unexpected simctl output: \(message)"
        case .badCapabilities(let device, let reason): return "Cannot read device profile of \(device): \(reason)"
        }
    }
}

/// Simulator device types (with display geometry) and installed simulators.
public struct DeviceCatalog: Sendable {
    public var deviceTypes: [DeviceType]
    public var simulators: [Simulator]

    public init(deviceTypes: [DeviceType], simulators: [Simulator]) {
        self.deviceTypes = deviceTypes
        self.simulators = simulators
    }

    /// - Parameter readFile: reads a file from disk; replaceable in tests.
    public static func load(
        shell: CommandRunning,
        readFile: @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) throws -> DeviceCatalog {
        struct TypesList: Decodable {
            struct Entry: Decodable {
                var name: String, identifier: String, productFamily: String
                var bundlePath: String, minRuntimeVersion: Int?
            }
            var devicetypes: [Entry]
        }
        struct DevicesList: Decodable {
            struct Entry: Decodable {
                var udid: String, name: String, deviceTypeIdentifier: String?, state: String
            }
            var devices: [String: [Entry]]
        }

        let typesOutput = try simctl(shell, ["list", "-j", "devicetypes"])
        let devicesOutput = try simctl(shell, ["list", "-j", "devices", "available"])
        let types: TypesList, devices: DevicesList
        do {
            types = try JSONDecoder().decode(TypesList.self, from: typesOutput)
            devices = try JSONDecoder().decode(DevicesList.self, from: devicesOutput)
        } catch {
            throw DeviceCatalogError.unreadableOutput(error.localizedDescription)
        }

        let deviceTypes: [DeviceType] = types.devicetypes.compactMap { entry in
            let plist = URL(fileURLWithPath: entry.bundlePath)
                .appendingPathComponent("Contents/Resources/capabilities.plist")
            // A device type whose profile we cannot read is skipped, not fatal.
            guard let data = try? readFile(plist),
                  let parsed = try? parseCapabilities(data, name: entry.name)
            else { return nil }
            return DeviceType(
                identifier: entry.identifier, name: entry.name, family: entry.productFamily,
                minRuntimeVersion: entry.minRuntimeVersion ?? 0,
                displays: parsed.displays, hasDynamicIsland: parsed.hasDynamicIsland)
        }

        let simulators = devices.devices.keys.sorted().flatMap { runtime in
            devices.devices[runtime, default: []].compactMap { entry -> Simulator? in
                guard let typeID = entry.deviceTypeIdentifier else { return nil }
                return Simulator(
                    udid: entry.udid, name: entry.name, deviceTypeIdentifier: typeID,
                    runtimeIdentifier: runtime, isBooted: entry.state == "Booted")
            }
        }
        return DeviceCatalog(deviceTypes: deviceTypes, simulators: simulators)
    }

    private static func simctl(_ shell: CommandRunning, _ arguments: [String]) throws -> Data {
        let result = try shell.run("xcrun", ["simctl"] + arguments, environment: [:])
        guard result.exitCode == 0 else {
            throw DeviceCatalogError.commandFailed(
                "xcrun simctl \(arguments.joined(separator: " ")) failed (exit \(result.exitCode)): \(result.stderrString)")
        }
        return result.stdout
    }

    /// Reads the built-in displays from a `capabilities.plist`.
    /// Devices without an `integrated` display (Apple TV) get one `primary` display
    /// from `ScreenDimensionsCapability`, without rounded corners.
    public static func parseCapabilities(_ plist: Data, name: String) throws -> (displays: [DisplaySpec], hasDynamicIsland: Bool) {
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(from: plist, options: [], format: nil)
        } catch {
            throw DeviceCatalogError.badCapabilities(device: name, reason: "not a property list")
        }
        guard let capabilities = (root as? [String: Any])?["capabilities"] as? [String: Any] else {
            throw DeviceCatalogError.badCapabilities(device: name, reason: "no \"capabilities\" dictionary")
        }

        func number(_ value: Any?) -> Double? {
            if let n = value as? NSNumber { return n.doubleValue }
            if let s = value as? String { return Double(s) }
            return nil
        }

        var displays: [DisplaySpec] = []
        for entry in capabilities["displays"] as? [[String: Any]] ?? [] where entry["displayType"] as? String == "integrated" {
            guard let displayName = entry["deviceName"] as? String,
                  let width = number(entry["width"]), let height = number(entry["height"])
            else { throw DeviceCatalogError.badCapabilities(device: name, reason: "incomplete display entry") }
            displays.append(DisplaySpec(
                name: displayName,
                pixelSize: PixelSize(width: Int(width), height: Int(height)),
                scale: number(entry["scale"]) ?? 1,
                cornerRadii: CornerRadii(
                    upperLeft: number(entry["cornerRadiusUL"]) ?? 0, upperRight: number(entry["cornerRadiusUR"]) ?? 0,
                    lowerLeft: number(entry["cornerRadiusLL"]) ?? 0, lowerRight: number(entry["cornerRadiusLR"]) ?? 0)))
        }

        if displays.isEmpty {
            guard let main = capabilities["ScreenDimensionsCapability"] as? [String: Any],
                  let width = number(main["main-screen-width"]), let height = number(main["main-screen-height"])
            else { throw DeviceCatalogError.badCapabilities(device: name, reason: "no display information") }
            displays = [DisplaySpec(
                name: "primary", pixelSize: PixelSize(width: Int(width), height: Int(height)),
                scale: number(main["main-screen-scale"]) ?? 1, cornerRadii: .zero)]
        }
        return (displays, capabilities["DeviceSupportsDynamicIsland"] as? Bool ?? false)
    }
}

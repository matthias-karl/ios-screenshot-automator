import Foundation

enum Fixtures {
    static func url(_ name: String) -> URL {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent("Fixtures/\(name)"),
              FileManager.default.fileExists(atPath: url.path)
        else { fatalError("Missing fixture \(name)") }
        return url
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }
}

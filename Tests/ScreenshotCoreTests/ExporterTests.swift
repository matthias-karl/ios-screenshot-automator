import Foundation
import Testing
@testable import ScreenshotCore

@Suite struct ExporterTests {
    func makeRun() -> CaptureRun {
        let size = StoreSizes.size(id: "iphone-6.3")!
        let target = Config.Target(platform: .iOS, scheme: "Demo", tests: "DemoUITests/Screenshots", sizes: ["iphone-6.3"])
        return CaptureRun(target: target, size: size, simulator: nil, display: nil, deviceTypeName: nil,
                          hasDynamicIsland: false, language: "de-DE", appearance: .light, landscape: false)
    }

    func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Makes `xcresulttool export attachments` write `manifest` plus a small file per exported name.
    func stubExport(_ fake: FakeRunner, manifest: Data, files: [String]) {
        fake.stub(prefix: ["xcrun", "xcresulttool", "export", "attachments"]) { argv in
            let out = URL(fileURLWithPath: argv[argv.index(after: argv.firstIndex(of: "--output-path")!)])
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try manifest.write(to: out.appendingPathComponent("manifest.json"))
            for name in files { try Data("png:\(name)".utf8).write(to: out.appendingPathComponent(name)) }
            return .ok()
        }
    }

    /// A manifest with one test per list of attachment names (human-readable names as Xcode writes them).
    func manifest(_ humanNames: [String]) throws -> (Data, [String]) {
        let attachments = humanNames.enumerated().map { index, name in
            ["exportedFileName": "file\(index).png", "suggestedHumanReadableName": name, "isAssociatedWithFailure": false] as [String: Any]
        }
        let json = try JSONSerialization.data(withJSONObject: [["testIdentifier": "T/test()", "attachments": attachments]])
        return (json, humanNames.indices.map { "file\($0).png" })
    }

    func exportedFileNames(from manifestData: Data) throws -> [String] {
        let entries = try JSONSerialization.jsonObject(with: manifestData) as! [[String: Any]]
        return entries.flatMap { ($0["attachments"] as! [[String: Any]]).map { $0["exportedFileName"] as! String } }
    }

    @Test func exportsFixtureShotsSortedByName() throws {
        let fake = FakeRunner()
        let data = try Fixtures.data("manifest.json")
        stubExport(fake, manifest: data, files: try exportedFileNames(from: data))
        let raw = try tempRoot()
        let shots = try Exporter.export(xcresult: URL(fileURLWithPath: "/x/a.xcresult"), run: makeRun(), rawRoot: raw, shell: fake)
        #expect(shots.map(\.name) == ["01_Home", "02_Items", "03_Detail", "04_Settings"])
        let dir = raw.appendingPathComponent("iphone-6.3/de-DE-light")
        #expect(shots.map(\.file) == ["01_Home", "02_Items", "03_Detail", "04_Settings"].map { dir.appendingPathComponent("\($0).png") })
        #expect(try Data(contentsOf: shots[0].file).starts(with: Data("png:".utf8)))
        #expect(fake.calls[0].prefix(4) == ["xcrun", "xcresulttool", "export", "attachments"])
        #expect(fake.calls[0].contains("/x/a.xcresult"))
    }

    @Test func foreignAttachmentsAreIgnored() throws {
        let fake = FakeRunner()
        let (data, files) = try manifest(["Screenshot_1.png", "sa2v2__01_Home_0_5F2C1E9A-1B2C-4D3E-8F90-123456789ABC.png", "Launch Screen.png"])
        stubExport(fake, manifest: data, files: files)
        let shots = try Exporter.export(xcresult: URL(fileURLWithPath: "/x"), run: makeRun(), rawRoot: try tempRoot(), shell: fake)
        #expect(shots.map(\.name) == ["01_Home"])
    }

    @Test func emptyManifestIsAnErrorNamingTheRun() throws {
        let fake = FakeRunner()
        stubExport(fake, manifest: Data("[]".utf8), files: [])
        #expect(throws: ExportError.noShots(slug: "iphone-6.3_de-DE_light")) {
            try Exporter.export(xcresult: URL(fileURLWithPath: "/x"), run: makeRun(), rawRoot: try tempRoot(), shell: fake)
        }
    }

    @Test func onlyForeignAttachmentsCountsAsNoShots() throws {
        let fake = FakeRunner()
        let (data, files) = try manifest(["Screenshot_1.png"])
        stubExport(fake, manifest: data, files: files)
        #expect(throws: ExportError.noShots(slug: "iphone-6.3_de-DE_light")) {
            try Exporter.export(xcresult: URL(fileURLWithPath: "/x"), run: makeRun(), rawRoot: try tempRoot(), shell: fake)
        }
    }

    @Test func duplicateShotIsAnError() throws {
        let fake = FakeRunner()
        let (data, files) = try manifest(["sa2v2__01_Home_0_AAAAAAAA-0000-0000-0000-000000000001.png",
                                          "sa2v2__01_Home_1_AAAAAAAA-0000-0000-0000-000000000002.png"])
        stubExport(fake, manifest: data, files: files)
        #expect(throws: ExportError.duplicateShot(slug: "iphone-6.3_de-DE_light", name: "01_Home")) {
            try Exporter.export(xcresult: URL(fileURLWithPath: "/x"), run: makeRun(), rawRoot: try tempRoot(), shell: fake)
        }
    }

    @Test func otherProtocolVersionIsAMismatch() throws {
        let fake = FakeRunner()
        let (data, files) = try manifest(["sa2v3__x_0_AAAAAAAA-0000-0000-0000-000000000001.png"])
        stubExport(fake, manifest: data, files: files)
        #expect(throws: ExportError.protocolMismatch(found: 3, expected: 2)) {
            try Exporter.export(xcresult: URL(fileURLWithPath: "/x"), run: makeRun(), rawRoot: try tempRoot(), shell: fake)
        }
    }

    @Test func oldFilesInTargetFolderAreRemoved() throws {
        let fake = FakeRunner()
        let (data, files) = try manifest(["sa2v2__01_Home_0_AAAAAAAA-0000-0000-0000-000000000001.png"])
        stubExport(fake, manifest: data, files: files)
        let raw = try tempRoot()
        let dir = raw.appendingPathComponent("iphone-6.3/de-DE-light")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stale = dir.appendingPathComponent("99_Old.png")
        try Data("old".utf8).write(to: stale)
        _ = try Exporter.export(xcresult: URL(fileURLWithPath: "/x"), run: makeRun(), rawRoot: raw, shell: fake)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test func staleFilesAreRemovedEvenWhenExportFindsNothing() throws {
        let fake = FakeRunner()
        stubExport(fake, manifest: Data("[]".utf8), files: [])
        let raw = try tempRoot()
        let dir = raw.appendingPathComponent("iphone-6.3/de-DE-light")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stale = dir.appendingPathComponent("99_Old.png")
        try Data("old".utf8).write(to: stale)
        _ = try? Exporter.export(xcresult: URL(fileURLWithPath: "/x"), run: makeRun(), rawRoot: raw, shell: fake)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test func toolFailureIsReported() {
        let fake = FakeRunner()
        fake.stub(prefix: ["xcrun", "xcresulttool"], result: .failure(1, stderr: "bad bundle"))
        do {
            _ = try Exporter.export(xcresult: URL(fileURLWithPath: "/x"), run: makeRun(), rawRoot: FileManager.default.temporaryDirectory.appendingPathComponent("e-\(UUID().uuidString)"), shell: fake)
            Issue.record("expected an error")
        } catch let ExportError.toolFailed(message) {
            #expect(message.contains("bad bundle"))
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}

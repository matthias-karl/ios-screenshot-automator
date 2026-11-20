import Foundation
import Testing
@testable import ScreenshotCore

@Suite struct ReportTests {
    @Test func indexListsEveryImageGroupedByLanguage() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString)")
        let finalDir = output.appendingPathComponent("final")
        for language in ["de-DE", "en-US"] {
            for name in ["iphone-6.3_01_Home.png", "ipad-13_01_Home.png"] {
                let url = finalDir.appendingPathComponent(language).appendingPathComponent(name)
                try Composer.writePNG(TestImage.opaque(PixelSize(width: 10, height: 20), .pRed), to: url)
            }
        }
        let index = output.appendingPathComponent("index.html")
        try Report.writeIndex(finalDir: finalDir, to: index)
        let html = try String(contentsOf: index, encoding: .utf8)

        #expect(html.components(separatedBy: "<img ").count - 1 == 4)
        #expect(html.contains("src=\"final/de-DE/iphone-6.3_01_Home.png\""))
        #expect(html.contains("src=\"final/en-US/ipad-13_01_Home.png\""))
        #expect(html.contains("<h2>de-DE</h2>") && html.contains("<h2>en-US</h2>"))
        #expect(!html.contains(output.path))     // relative paths only
    }

    @Test func emptyOutputStillProducesAValidPage() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output.appendingPathComponent("final"), withIntermediateDirectories: true)
        let index = output.appendingPathComponent("index.html")
        try Report.writeIndex(finalDir: output.appendingPathComponent("final"), to: index)
        let html = try String(contentsOf: index, encoding: .utf8)
        #expect(html.contains("<html"))
        #expect(!html.contains("<img "))
    }
}

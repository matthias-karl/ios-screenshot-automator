import Foundation

/// Writes `index.html`: all finished images by language and size, to look through at a glance.
public enum Report {
    public static func writeIndex(finalDir: URL, to url: URL) throws {
        let fm = FileManager.default
        let base = url.deletingLastPathComponent().standardizedFileURL
        let languages = ((try? fm.contentsOfDirectory(atPath: finalDir.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()

        var body = ""
        for language in languages {
            let dir = finalDir.appendingPathComponent(language)
            let files = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.lowercased().hasSuffix(".png") }.sorted()
            guard !files.isEmpty else { continue }
            body += "<h2>\(escape(language))</h2>\n"

            var currentSize: String?
            for file in files {
                let size = file.split(separator: "_", maxSplits: 1).first.map(String.init) ?? file
                if size != currentSize {
                    if currentSize != nil { body += "</div>\n" }
                    body += "<h3>\(escape(size))</h3>\n<div class=\"row\">\n"
                    currentSize = size
                }
                let path = relativePath(from: base, to: dir.appendingPathComponent(file).standardizedFileURL)
                let encoded = path.split(separator: "/", omittingEmptySubsequences: false)
                    .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                    .joined(separator: "/")
                body += "<figure><img src=\"\(encoded)\" alt=\"\(escape(file))\"><figcaption>\(escape(file))</figcaption></figure>\n"
            }
            if currentSize != nil { body += "</div>\n" }
        }
        if body.isEmpty { body = "<p>No images yet. Run <code>screenshots run</code>.</p>\n" }

        let html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Screenshots</title>
        <style>
        body { font: 14px -apple-system, system-ui, sans-serif; margin: 2rem; color: #222; background: #fafafa; }
        .row { display: flex; gap: 1rem; flex-wrap: wrap; align-items: flex-start; }
        figure { margin: 0; }
        img { height: 420px; width: auto; border: 1px solid #ddd; background: #fff; }
        figcaption { color: #666; font-size: 12px; margin-top: .25rem; }
        </style>
        </head>
        <body>
        <h1>Screenshots</h1>
        \(body)</body>
        </html>
        """
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func relativePath(from base: URL, to target: URL) -> String {
        let from = base.pathComponents, to = target.pathComponents
        var common = 0
        while common < from.count, common < to.count, from[common] == to[common] { common += 1 }
        let up = Array(repeating: "..", count: from.count - common)
        return (up + to[common...]).joined(separator: "/")
    }
}

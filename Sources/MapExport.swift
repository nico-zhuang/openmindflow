import AppKit
import Darwin

enum MapExportFormat {
    case pdf, png, jpeg, markdown

    fileprivate var suffix: String {
        switch self {
        case .pdf: ".pdf"
        case .png: ".png"
        case .jpeg: ".jpg"
        case .markdown: ".md"
        }
    }
}

enum MapExportError: LocalizedError {
    case invalidDestination, destinationExists, tooLarge, renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidDestination: "Choose an output file outside any .mindnode package with the matching extension."
        case .destinationExists: "The output file already exists; choose another name."
        case .tooLarge: "The map is too large to export at full size."
        case .renderFailed: "The map could not be rendered."
        }
    }
}

func exportMarkdown(_ roots: [MapNode], relationships: [MapRelationship] = []) -> String {
    func containsMedia(_ nodes: [MapNode]) -> Bool {
        nodes.contains { $0.image != nil || $0.video != nil || containsMedia($0.children) }
    }
    func containsNotes(_ nodes: [MapNode]) -> Bool {
        nodes.contains { $0.note != nil || containsNotes($0.children) }
    }
    var output = containsMedia(roots) ? "> Images and other media are not embedded in this Markdown export.\n\n" : ""
    if !relationships.isEmpty { output += "> Cross-node relationships are not embedded in this Markdown export.\n\n" }
    if containsNotes(roots) { output += "> Notes are not included in this Markdown export.\n\n" }
    func append(_ nodes: [MapNode], depth: Int) {
        for node in nodes {
            let text = node.title.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            var escaped = ""
            for character in text {
                switch character {
                case "\\", "*", "_", "`", "[", "]": escaped += "\\" + String(character)
                case "&": escaped += "&amp;"
                case "<": escaped += "&lt;"
                case ">": escaped += "&gt;"
                case "\n": escaped += "<br>"
                default: escaped.append(character)
                }
            }
            if escaped.isEmpty && node.image != nil { escaped = "[Image omitted]" }
            if escaped.isEmpty && node.video != nil { escaped = "[Video omitted]" }
            output += String(repeating: "  ", count: depth) + "- " + escaped + "\n"
            append(node.children, depth: depth + 1)
        }
    }
    append(roots, depth: 0)
    return output
}

func exportMap(_ canvas: MapCanvas, as format: MapExportFormat, to url: URL) throws {
    guard url.isFileURL, url.lastPathComponent.lowercased().hasSuffix(format.suffix),
          !url.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents.contains(where: {
              $0.lowercased().hasSuffix(".mindnode")
          }) else { throw MapExportError.invalidDestination }
    var info = stat()
    if lstat(url.path, &info) == 0 { throw MapExportError.destinationExists }
    guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    let data: Data
    if format == .markdown {
        data = Data(exportMarkdown(canvas.model.roots, relationships: canvas.model.relationships).utf8)
    } else {
        // Render on a detached canvas: no viewport, selection, model, or source file is modified.
        let roots = canvas.model.roots
        let snapshot = MapCanvas(model: MapModel(roots: roots, selected: UUID(),
            theme: canvas.model.theme, canvasColor: canvas.model.canvasColor))
        snapshot.model.relationships = canvas.model.relationships
        snapshot.branchStyles = canvas.branchStyles
        snapshot.nativePresentation = canvas.nativePresentation
        snapshot.embeddedTheme = canvas.embeddedTheme
        snapshot.localizationDefaults = canvas.localizationDefaults
        snapshot.appearance = canvas.effectiveAppearance
        let world = mapLayout(roots).reduce(CGRect.null) { $0.union($1.frame) }
        let initial = world.isNull ? CGSize(width: 320, height: 240) :
            CGSize(width: ceil(world.width) + 128, height: ceil(world.height) + 128)
        snapshot.frame = CGRect(origin: .zero, size: initial)
        var fitted = false
        for _ in 0..<8 {
            guard snapshot.bounds.width > 0, snapshot.bounds.height > 0,
                  snapshot.bounds.width <= 8192, snapshot.bounds.height <= 8192,
                  snapshot.bounds.width * snapshot.bounds.height <= 32_000_000 else { throw MapExportError.tooLarge }
            let visible = snapshot.fitMapInView()
            if visible.isNull || snapshot.bounds.insetBy(dx: 30, dy: 30).contains(visible) {
                fitted = true
                break
            }
            // A clipped fit is at the canvas's 0.35 minimum zoom; infer full world bounds.
            snapshot.frame.size = CGSize(width: max(snapshot.bounds.width, ceil(visible.width / 0.35) + 128),
                                         height: max(snapshot.bounds.height, ceil(visible.height / 0.35) + 128))
        }
        guard fitted else { throw MapExportError.tooLarge }
        if format == .pdf {
            data = snapshot.dataWithPDF(inside: snapshot.bounds)
        } else {
            let width = Int(ceil(snapshot.bounds.width)), height = Int(ceil(snapshot.bounds.height))
            let scale = min(2, 8192 / CGFloat(width), 8192 / CGFloat(height),
                            sqrt(32_000_000 / CGFloat(width * height)))
            let pixelsWide = Int(CGFloat(width) * scale), pixelsHigh = Int(CGFloat(height) * scale)
            guard pixelsWide > 0, pixelsHigh > 0, pixelsWide * pixelsHigh <= 32_000_000 else {
                throw MapExportError.tooLarge
            }
            guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0) else { throw MapExportError.renderFailed }
            image.size = snapshot.bounds.size // Physical size stays in points; pixels encode the real DPI.
            guard let context = NSGraphicsContext(bitmapImageRep: image) else { throw MapExportError.renderFailed }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            snapshot.displayIgnoringOpacity(snapshot.bounds, in: context)
            NSGraphicsContext.restoreGraphicsState()
            guard let rendered = image.representation(using: format == .png ? .png : .jpeg,
                                                       properties: format == .jpeg ? [.compressionFactor: 0.9] : [:]) else {
                throw MapExportError.renderFailed
            }
            data = rendered
        }
    }
    guard !data.isEmpty else { throw MapExportError.renderFailed }
    var pattern = (url.deletingLastPathComponent().path + "/.map-export-XXXXXX").utf8CString
    let temporary = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
        guard let start = bytes.baseAddress else { throw MapExportError.renderFailed }
        let fd = mkstemp(start)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        close(fd)
        return String(cString: start)
    }
    defer { unlink(temporary) }
    try data.write(to: URL(fileURLWithPath: temporary))
    guard link(temporary, url.path) == 0 else {
        if errno == EEXIST { throw MapExportError.destinationExists }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

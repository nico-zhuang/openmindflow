import Foundation

@main
enum NativeTabsBundleTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func main() throws {
        let script = "scripts/build-openmindflow-tabs-0.5-local.sh"
        require(FileManager.default.fileExists(atPath: script), "separate 0.5 builder must exist")
        let source = try String(contentsOfFile: script, encoding: .utf8)
        let opening = "cat > \"$app/Contents/Info.plist\" <<'PLIST'\n"
        guard let start = source.range(of: opening),
              let end = source.range(of: "\nPLIST", range: start.upperBound..<source.endIndex),
              let plist = try PropertyListSerialization.propertyList(from: Data(source[start.upperBound..<end.lowerBound].utf8), format: nil) as? [String: Any] else {
            fatalError("Separate builder must contain a parseable Info.plist heredoc")
        }
        require(plist["CFBundleIdentifier"] as? String == "local.openmindflow.tabs.20261027", "0.5 bundle identifier")
        require(plist["CFBundleShortVersionString"] as? String == "0.5.0", "0.5 version")
        require(plist["CFBundleVersion"] as? String == "6", "0.5 build")
        let exports = plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        let native = exports.first { $0["UTTypeIdentifier"] as? String == "local.openmindflow.document" }
        require(native != nil, "unchanged native document UTI")
        require((native?["UTTypeConformsTo"] as? [String])?.contains("public.data") == true, "data conformance")
        let tags = native?["UTTypeTagSpecification"] as? [String: String] ?? [:]
        require(tags["public.filename-extension"] == "mflw", "mflw extension")
        require(tags["public.mime-type"] == "application/vnd.openmindflow.mflw", "mflw MIME")
        let documents = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        require(documents.contains { ($0["CFBundleTypeRole"] as? String) == "Editor" &&
            ($0["LSItemContentTypes"] as? [String])?.contains("local.openmindflow.document") == true }, "Editor association")
        require(FileManager.default.fileExists(atPath: "scripts/package-openmindflow-tabs-0.5-dmg.sh"), "separate packager")
        print("PASS: separate 0.5 Info.plist metadata and Editor document association")
    }
}
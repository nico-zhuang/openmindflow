import Foundation

// Run from the repository root; compatible with the HEADLESS_TEST source suite.
@main
enum NativeDocumentBundleTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() throws {
        let buildScript = try String(contentsOfFile: "scripts/build-openmindflow-local.sh", encoding: .utf8)
        let packageScript = try String(contentsOfFile: "scripts/package-openmindflow-local-dmg.sh", encoding: .utf8)
        let opening = "cat > \"$app/Contents/Info.plist\" <<'PLIST'\n"
        guard let start = buildScript.range(of: opening),
              let end = buildScript.range(of: "\nPLIST", range: start.upperBound..<buildScript.endIndex) else {
            fatalError("Cannot locate generated Info.plist in build script")
        }
        let plistXML = String(buildScript[start.upperBound..<end.lowerBound])
        let plist = try PropertyListSerialization.propertyList(from: Data(plistXML.utf8), format: nil) as! [String: Any]
        let exports = plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        let nativeType = exports.first { $0["UTTypeIdentifier"] as? String == "local.openmindflow.document" }
        require(nativeType != nil, "exported native document UTI")
        let tags = nativeType?["UTTypeTagSpecification"] as? [String: Any] ?? [:]
        require(tags["public.filename-extension"] as? String == "mflw", "mflw extension")
        require(tags["public.mime-type"] as? String == "application/vnd.openmindflow.mflw", "native document MIME")
        let documents = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        require(documents.contains { document in
            document["CFBundleTypeRole"] as? String == "Editor" &&
            (document["LSItemContentTypes"] as? [String])?.contains("local.openmindflow.document") == true
        }, "Editor document association")
        require(plist["CFBundleIdentifier"] as? String == "local.openmindflow.nativeformat.20261027", "distinct candidate bundle ID")
        require(plist["CFBundleShortVersionString"] as? String == "0.4.0", "version 0.4.0")
        require(plist["CFBundleVersion"] as? String == "5", "build 5")
        for metadata in [
            "CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
            "UTExportedTypeDeclarations", "UTTypeIdentifier", "UTTypeTagSpecification",
            "public.filename-extension", "public.mime-type", "CFBundleDocumentTypes",
            "LSItemContentTypes", "CFBundleTypeRole"
        ] {
            require(packageScript.contains(metadata), "packager validates \(metadata)")
        }
        require(packageScript.contains("local.openmindflow.nativeformat.20261027"), "packager expects distinct bundle ID")
        require(packageScript.contains("0.4.0") && packageScript.contains("!= 5"), "packager expects version 0.4.0 build 5")
        print("PASS: native document Info.plist and package metadata checks")
    }
}

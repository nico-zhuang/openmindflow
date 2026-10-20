# MindNode v9 importer TDD / authorization report

- User authorized read-only use of `.mindnode` packages in `/Users/nicozhuang/极境造物/会议纪要/`. Neither private prose nor source packages are copied into this repository.
- RED: `swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Tests/MindNodeImporterTests.swift -o /tmp/mindnode-import-tests && /tmp/mindnode-import-tests` exited 133 at the first root/title assertion against an empty importer stub. (Initial missing-file failure and one test syntax error were corrected before behavioral RED.)
- macOS compilation failure `no such module 'FoundationXML'` traced via `swift -e 'import Foundation; print(XMLParser.self)'` → `NSXMLParser`; removed unsupported module import only.
- GREEN: exact `swiftc` command exits 0 with `import tests passed`. Synthetic binary plist tests cover title XML decoding, child/UUID/fold state, empty maps, malformed bytes, unsupported version, XML plist, malformed XML, DOCTYPE/XXE, duplicate UUID, 8 MiB cap and non-directory input.
- Integration: user-authorized packages returned 1 map/30 nodes, 2/34, 1/27 and 0/0; before/after SHA-256 of each source `contents.xml` matched. No node text was printed or written to project files.
- `bash build.sh`, `plutil -lint` and Mach-O inspection succeeded with the import module linked. Open-panel wiring and runtime UX are a separate task.

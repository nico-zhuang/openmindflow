# MindNode v9 importer TDD / authorization report

- User authorized read-only use of `.mindnode` packages in `/Users/nicozhuang/极境造物/会议纪要/`. Neither private prose nor source packages are copied into this repository.
- RED: `swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Tests/MindNodeImporterTests.swift -o /tmp/mindnode-import-tests && /tmp/mindnode-import-tests` exited 133 at the first root/title assertion against an empty importer stub. (Initial missing-file failure and one test syntax error were corrected before behavioral RED.)
- macOS compilation failure `no such module 'FoundationXML'` traced via `swift -e 'import Foundation; print(XMLParser.self)'` → `NSXMLParser`; removed unsupported module import only.
- GREEN: exact `swiftc` command exits 0 with `import tests passed`. Synthetic binary plist tests cover title XML decoding, child/UUID/fold state, empty maps, malformed bytes, unsupported version, XML plist, malformed XML, DOCTYPE/XXE, duplicate UUID, 8 MiB cap and non-directory input.
- Integration: user-authorized packages returned 1 map/30 nodes, 2/34, 1/27 and 0/0; before/after SHA-256 of each source `contents.xml` matched. No node text was printed or written to project files.
- `bash build.sh`, `plutil -lint` and Mach-O inspection succeeded with the import module linked. Open-panel wiring and runtime UX are a separate task.

## Review fixes and source provenance

- The user authorized the **whole** `/Users/nicozhuang/极境造物/会议纪要/` directory, not exactly three files. A, B and C are populated v9 samples; D is the empty-map v9 sample. Relative package names: A=`曾test猫头.mindnode`, B=`0514.mindnode`, C=`20261014_五建项目启动会.mindnode`, D=`思维导图6.mindnode`. Filenames only; no original node text was retained.
- Reproducible read-only command for each selected package: `before=$(shasum -a 256 "$pkg/contents.xml" | awk '{print $1}'); /tmp/mindnode-import-tests "$pkg"; after=$(shasum -a 256 "$pkg/contents.xml" | awk '{print $1}'); test "$before" = "$after"`. This was rerun after parser hardening; `before` and `after` were identical for each:
  - A maps=1 nodes=30 SHA-256 `0030dde7f9e189cb73df9a36d679987fac2bb27ed5b1b560c7c22456afe8cb50`
  - B maps=2 nodes=34 SHA-256 `82b3afc0fed09321a10fb1ccc862afa6cfe6d840923eb601378048da1c26c86f`
  - C maps=1 nodes=27 SHA-256 `38dade2e169a67ae9c6b1d2715607c5c6a75d087cbfe1a598abc2f2a03ef2856`
  - D maps=0 nodes=0 SHA-256 `7138fca495e5c3e3152369d769477bb7de0a3126d97d9fd6987803207a858591`
- RED added scalar type and XML nesting assertions: before fix `swiftc ... && /tmp/mindnode-import-tests` exited 133 at the integral-real v9 rejection assertion (test line 41). GREEN after strict CoreFoundation scalar checks and 64-level abort: exact command exits 0 `import tests passed`. Added deep/wide tree, cross-map duplicate and valid/unknown inline-title checks.
- Second review identified the earlier `FileManager.createDirectory` was idempotent and recursive cleanup could race. Test now uses atomic `mkdirat` on a temporary-directory FD, pins the created package/scratch by `openat(O_DIRECTORY|O_NOFOLLOW)`, verifies absolute resolved path, owner marker and directory inode, then removes only known entries via `unlinkat` and **nonrecursive** `AT_REMOVEDIR`; never `removeItem` on a directory. Reran tests: `import tests passed`; temporary scratch directory count after completion = 0. Two 307/340-byte leftover synthetic fixtures from the original intentional RED assertion traps were separately verified by resolved absolute path and exact inventory, then removed via file `rm` + empty `rmdir` only.


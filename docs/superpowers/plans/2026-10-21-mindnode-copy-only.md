# MindNode Copy-Only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Copy an unchanged synthetic v9 `.mindnode` directory package to a new sibling destination without losing any file bytes, following symlinks, or replacing an existing target.

**Architecture:** A single Foundation/Darwin utility `MindNodePackage.copyUnmodified(from:to:)` validates the v9 source through the existing importer, rejects symbolic links in either the original or staged tree, stages a recursive `copyfile` into a unique private sibling, verifies regular-file bytes, then atomically publishes with `renameatx_np(..., RENAME_EXCL)`. No application menu calls this utility yet. This is an internal **synthetic-fixture gate**, not hardened concurrent/adversarial user-package support.

**Tech Stack:** Swift 6.2.1, Foundation, Darwin; `copyfile(3)` and `renameatx_np(2)` on macOS; no dependency added.

## Global Constraints

- Original app and authorized user packages remain read-only; tests create only their own synthetic temp package.
- Destination must be a **different, nonexistent** `.mindnode` entry in the source's trusted sibling directory. No overwrite/merge on collision; `COPYFILE_EXCL` is *insufficient* for recursive directory collision because a local probe returned success on an existing directory.
- The copy must contain exactly the same binary `contents.xml`, resource paths and regular-file bytes; validate by `MindNodeImporter.load(output)` as well as raw byte comparison. Unknown plist dictionaries remain untouched.
- Reject root/nested symlinks, irregular files, malformed/unsupported v9 packages, nested destination, package beyond the existing 8 MiB `contents.xml` bound or the internal 64 MiB total regular-file bound, and any failed copy. Clean only a uniquely owned private staging directory whose resolved absolute path and inode match what was created.
- `copyfile` is path-based: this first gate assumes the caller controls a stable sibling directory; before enabling GUI writes to arbitrary user packages, replace with descriptor-relative no-follow traversal and cleanup. Mark this specific throughput/security ceiling with `ponytail:` in the implementation.

---

### Task 1: Package copy safety and byte identity

**Files:** Create `Sources/MindNodePackage.swift`; create `Tests/MindNodePackageTests.swift` (test already written RED in this worktree); document the additional test command in `README.md` only after it passes.

**Interfaces:** `enum MindNodePackage { static func copyUnmodified(from source: URL, to destination: URL) throws }`, consumes `MindNodeImporter.load(_:) throws -> [MapNode]`. It does not receive `MapModel` and cannot export changed maps.

- [x] **RED:** run `swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Tests/MindNodePackageTests.swift -o /tmp/mindmap-package-tests`. Expected compile failure: `cannot find 'MindNodePackage' in scope`, with no test syntax errors. Synthetic test checks `contents.xml`, nested resource bytes, original bytes unchanged, successful importer reopen, existing output collision, nested output rejection, nested symlink rejection and root symlink rejection.
- [x] **GREEN:** implement one utility. Check source/destination file URLs, same literal parent, distinct v9 `.mindnode` names; `lstat` source/parent and `fstatat(parentFD, destinationName, ..., AT_SYMLINK_NOFOLLOW)`; open parent `O_RDONLY | O_DIRECTORY | O_NOFOLLOW`; reject anything except regular files/directories when enumerating source and stage. Call `MindNodeImporter.load(source)` before copy. Create stage with `mkdtemp` in same parent, record its inode, and keep cleanup `defer` guarded by resolved absolute stage path, parent, inode and ownership. Call:

```swift
copyfile(source.path, stagePayload.path, nil,
         copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL | COPYFILE_NOFOLLOW))
```

Then compare each relative regular-file path and bytes (including `contents.xml`) from source and stage, ensure no unexpected entries, and `MindNodeImporter.load(stagePayload)` succeeds. Publish **only** with:

```swift
renameatx_np(parentFD, stagePayloadRelativePath, parentFD, destination.lastPathComponent,
             UInt32(RENAME_EXCL))
```

If `errno == EEXIST`, throw without touching existing destination. On any other error also clean only the owned staging tree. Never call ordinary `rename`, which may replace. The API itself is not exposed in `App.swift` in this task.
- [x] **Verify:** `swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Sources/MindNodePackage.swift Tests/MindNodePackageTests.swift -o /tmp/mindmap-package-tests && /tmp/mindmap-package-tests`; expected `synthetic v9 copy, resources, collisions and symlinks passed`.
- [x] **Regression:** run `bash build.sh` and the four existing assertion commands in `README.md`, then `plutil -lint build/MindMap.app/Contents/Info.plist` and `git diff --check`. Expected all exit 0. Commit source/test/README only; retain untracked `dist/`, unchanged user packages and any running GUI process.

## Release stop line

Until an independent GUI open gate passes, this utility stays internal. Even after synthetic copy passes, do not call it a `.mindnode` writer for edited maps or claim original MindNode can open the copy: only a safe bounded original-app run on a synthetic disposable output could supply that evidence. If a concurrent path-swap threat is in scope, the path-based staging approach is insufficient; use dirfd/openat-based recursive reading and descriptor-relative cleanup first.

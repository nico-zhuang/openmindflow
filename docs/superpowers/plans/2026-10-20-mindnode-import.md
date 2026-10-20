# MindNode v9 Read-only Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read user-selected real `.mindnode` v9 package documents without modifying their originals and load their plain-text tree into the independent editor.

**Architecture:** A Foundation-only decoder reads one bounded package `contents.xml` as a binary property list, validates the observed v9 `canvas.mindMaps[*].mainNode` tree, parses XML paragraph title strings without resolving external entities, and returns `[MapNode]`. AppKit calls it from an Open panel; unsupported format/version produces an explicit error and never silently falls back to an empty tree.

**Tech Stack:** Swift 6.2.1, Foundation, FoundationXML, AppKit; no third-party dependencies.

## Global Constraints

- Only read paths explicitly chosen by the user. Never modify original `.mindnode` documents or their style/resources.
- The authorized `/Users/nicozhuang/极境造物/会议纪要/` samples are v9 directory packages with binary plist `contents.xml`; package-format `.mindnode` elsewhere may differ.
- Never record original node prose in tests, commits, logs, or responses. Generate synthetic fixtures in memory.
- Bound `contents.xml` to 8 MiB, number of nodes to 10,000, depth to 200; reject invalid version, malformed fields, duplicate UUIDs, malformed XML, and non-package paths.
- `.mindmap.json` save remains separate; never offer a MindNode-format export or overwrite a `.mindnode` path.

---

### Task 1: Safe v9 package decoder

**Files:** Create `Sources/MindNodeImporter.swift`, `Tests/MindNodeImporterTests.swift`.

**Interfaces:** `enum MindNodeImporter { static func load(_ url: URL) throws -> [MapNode] }` and `enum ImportError: LocalizedError` for unsupported/oversize/malformed cases.

- [ ] Write synthetic test in `@main` test runner: serialize an in-memory v9 plist using `PropertyListSerialization` with a root and child, UUIDs, `title.text = "<p>Hello &amp; world</p>"`; write only the synthetic fixture into a unique temporary `.mindnode` directory. Assert two parsed titles, exact IDs and hierarchy, plus zero-map package returns empty array. Assert malformed bytes, unsupported version, malformed title XML, `<!DOCTYPE`/external-entity title XML, duplicate IDs, 8 MiB cap and non-directory path all throw. The test runner removes only its own verified unique temporary package.
- [ ] Run `swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Tests/MindNodeImporterTests.swift -o /tmp/mindnode-import-tests && /tmp/mindnode-import-tests`; expected failure because importer does not exist.
- [ ] Implement reader: require a `.mindnode` package directory and direct regular `contents.xml`; use `Data(contentsOf:options:.mappedIfSafe)` only after a file-size check; verify property-list format is `.binary`, `version == 9`, and `canvas.mindMaps` is a list; recursively decode nodes with depth/node-count/duplicate guards, ID `UUID(uuidString:)`, title text XMLParser (no external entities) accepting a single `<p>` root, fold bool; reject invalid shapes. Do not parse style/resources or use HTML WebKit.
- [ ] Run the same test command; expected `import tests passed` and exit 0. Let the synthetic test runner optionally accept a package path and report **only** map/node counts. Run it on four samples from the user-approved directory (three populated plus one empty package), checking source-file SHA-256 before/after; never print node content.

### Task 2: Open-panel integration

**Files:** Modify `Sources/App.swift`, `README.md` and existing build command if FoundationXML linking is needed.

- [ ] Add an AppKit action “Open MindNode (Read-only)…” invoking `NSOpenPanel` for `.mindnode` packages, calls `MindNodeImporter.load`, then sets editor roots and selected root only on successful parse. Explain in the UI that only text/tree/fold state is imported; styles, notes and attachments are not round-tripped. Empty maps must show an explicit empty-document state. Show an `NSAlert` on failure; do not mutate the current editor on error.
- [ ] On successful import clear any previously opened `.mindmap.json` destination (`fileURL = nil`) so Save always opens a fresh panel and targets `.mindmap.json`; never use the imported source path or a stale earlier JSON destination.
- [ ] Run model, layout and importer tests plus `bash build.sh`; expected all pass and runnable app exists. Test opening one authorized sample without writing to it and compare SHA-256 before/after.

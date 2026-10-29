<div align="center">
  <img src="docs/images/openmindflow-icon.png" width="108" alt="OpenMindFlow icon: a root node with three colorful branches on navy">
  <h1>OpenMindFlow</h1>
  <p><strong>A native canvas. A file format of your own. Careful interoperability.</strong></p>
  <p>An independent macOS mind-map editor for shaping ideas, editing branches, and keeping your work in <code>.mflw</code> documents.</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-26%2B%20%7C%20arm64-1c3556?style=flat-square" alt="macOS 26+, arm64">
    <img src="https://img.shields.io/badge/release-v0.6.1-19a9a2?style=flat-square" alt="Stable channel v0.6.1">
    <img src="https://img.shields.io/badge/repository-private-596579?style=flat-square" alt="Private repository">
  </p>
  <p><a href="README.md">简体中文</a> · <strong>English</strong></p>
</div>

Edit nodes and branches on a native canvas, save and reopen `.mflw` documents, and use bounded MindNode v9 import and export-to-new-copy when needed.

> **Access:** This repository and its Releases are **private**; you need an authorized GitHub account to download the App. “Stable” is a product release channel, not an Apple security certification. The App is **ad-hoc signed, without a Developer ID signature or Apple notarization**, and has no automatic installer.

## Start here

| Looking for… | Go to… |
| --- | --- |
| v0.6.1 downloads | [DMG](https://github.com/nico-zhuang/openmindflow/releases/download/v0.6.1/OpenMindFlow-Stable-0.6.1-20261029.dmg) · [ZIP](https://github.com/nico-zhuang/openmindflow/releases/download/v0.6.1/OpenMindFlow-Stable-0.6.1-20261029.zip) · [full release notes](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.1) |
| File formats and limits | [Native documents](#your-own-documents-not-renamed-json) · [MindNode v9](#mindnode-v9-bounded-interoperability) |
| Verification and project history | [v0.6.1 release record](docs/2026-10-29-openmindflow-0.6.1-repository-migration.md) · [development archive](README.history.md) |

**Requirements:** macOS 26 or newer on Apple Silicon (arm64). The current package is **v0.6.1 / build 8**, bundle ID `com.nicozhuang.openmindflow`. Sign in to GitHub with an account authorized for this private repository before downloading; do not provide the App with a GitHub token.

## What you can do

- **Work on a native canvas.** Add main and child nodes, move and fold branches, and switch between the outline, styling, and notes as you organize your map.
- **Keep maps separate.** Manage multiple documents in windows and tabs; make common text, connection, and layout changes to selected nodes. These are existing capabilities, not a claim of feature parity with another mind-map editor.
- **Choose your interface language.** In Settings, follow the system language or select Simplified Chinese or English. This does not translate the text you put into nodes. This introduction is also available [in Chinese](README.md).
- **Keep control of the file.** Save in the independent `.mflw` format, and use the limited MindNode v9 import and “export as a new copy” path only when appropriate.

## Documents and compatibility

### Your own documents, not renamed JSON

A `.mflw` file has an `OMFLW001` magic header, a length field, and a SHA-256 check; its body is a **binary property list**, not JSON with a different extension. You can save, reopen, and edit it in OpenMindFlow. Legacy `.mindmap.json` files are migration inputs and are not silently rewritten just by opening them.

### MindNode v9: bounded interoperability

OpenMindFlow can read supported **MindNode v9 binary-plist packages/files** without writing to the source. The imported `.mindnode` is never an automatic save target: a limited set of preservable edits can be exported to a **new copy**. If an edit cannot be preserved in the original format, that export is refused, while saving as `.mflw` remains available. This is not a claim that every MindNode file is supported, that both formats are fully interchangeable, or that the original MindNode app has accepted every exported copy. OpenMindFlow is independent and is not affiliated with MindNode or IdeasOnCanvas.

## Install and upgrade

1. Open the [v0.6.1 Stable Release](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.1) in an authorized browser session and download the DMG or ZIP. The App does not download or install updates automatically.
2. For the ZIP, extract it with macOS Finder / Archive Utility or `ditto -x -k`. This ZIP contains AppleDouble metadata; extracting it with command-line `unzip -q` exposes `._` files inside the signed bundle and makes strict signature verification fail.
3. Check the App and its provenance under your own macOS security policy. **An ad-hoc signature does not prove publisher identity, Gatekeeper acceptance, or notarization.** Do not treat verification steps as a reason to replace a running older App or an important document.

**Upgrading from v0.6.0 requires a manual download.** The old signed binary pins the former repository URL and rejects redirects, so its update checker cannot reliably discover the renamed repository. The new checker reads only bounded Releases metadata at the new URL. Anonymous access to a private repository can return 403/404; in that case the App directs you to sign in via your browser rather than claiming you are up to date. The [v0.6.0 Release](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.0) and its original assets remain intact.

<details>
<summary>v0.6.1 file checksums (SHA-256)</summary>

| File | SHA-256 |
| --- | --- |
| `OpenMindFlow-Stable-0.6.1-20261029.dmg` | `23994fb05bf22b98d77e632f73e0cf64e1470b65b603de0fabbe8bf10dee5bac` |
| `OpenMindFlow-Stable-0.6.1-20261029.zip` | `1bbf9e2681c7e0c3055c1772dae23da08192f206dfef64f83e6dd70c3ccbd886` |

</details>

## Verification, limits, and project records

For v0.6.1, **80/80 safe offscreen Swift suites and 3/3 interaction submodes** passed. The source App, DMG, and ZIP App extracted with macOS `ditto` also passed strict signature and file checks. Offscreen tests are **not** a hands-on Finder, mouse/keyboard, system VoiceOver, or original MindNode acceptance test. See the [release record](docs/2026-10-29-openmindflow-0.6.1-repository-migration.md) for the evidence and explicitly excluded tests.

This repository currently has **no LICENSE**; private access or a download does not grant public redistribution rights. For earlier candidates and detailed verification history, read the [byte-for-byte archive of the former README](README.history.md). The editorial decisions behind this introduction are documented in the [Ask Five Pro review](docs/2026-10-29-openmindflow-bilingual-readme-review.md).

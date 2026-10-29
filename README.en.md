<div align="center">
  <img src="docs/images/openmindflow-icon.png" width="92" alt="OpenMindFlow project icon: a root node and three colorful branches on navy">
  <h1>OpenMindFlow</h1>
  <p><strong>A native Mac mind-map editor for organizing ideas.</strong><br>Build and arrange branches, then keep your work in an independent <code>.mflw</code> document.</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-26%2B%20%7C%20arm64-1c3556?style=flat-square" alt="macOS 26 or later, Apple Silicon arm64">
    <img src="https://img.shields.io/badge/release-v0.6.1-19a9a2?style=flat-square" alt="v0.6.1 released">
  </p>
  <p>Language / 语言<br>
    <a href="README.md" aria-label="切换到简体中文"><img src="https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-%E5%88%87%E6%8D%A2-596579?style=for-the-badge" alt="简体中文 · 阅读中文版"></a>
    <a href="README.en.md" aria-label="Current language: English"><img src="https://img.shields.io/badge/English-Current-19a9a2?style=for-the-badge" alt="English · Current page"></a>
  </p>
  <p><a href="https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.1" aria-label="Open v0.6.1 download page (authorized accounts only for now)"><img src="https://img.shields.io/badge/Download-v0.6.1-1c3556?style=for-the-badge" alt="Download v0.6.1 · authorized accounts only for now"></a></p>
  <p><a href="#quick-start">Install and run</a> · <a href="#core-experience">Core experience</a> · <a href="#current-status-and-known-limits">Current status</a></p>
</div>

> **Product imagery:** There is no verified screenshot or interaction GIF of an **actual v0.6.1 application window** yet. The image above is a project icon, not a UI screenshot; older offscreen prototype renders are not presented as this version's interface. We will add real product imagery only after checking its version, permissions, and content.

OpenMindFlow is for people who want to turn ideas into maps they can continue editing: start with a topic, add nodes, rearrange branches, and switch between a canvas and an outline. It is an independently developed macOS app and does not require MindNode to be installed. Its MindNode v9 interoperability covers only a defined subset, as explained below.

## Core experience

These capabilities exist in the **source at the v0.6.1 tag**, with automated verification recorded at release time. This does not mean each interaction has been retested on a real desktop in this round.

| What you can do | Benefit and current evidence |
| --- | --- |
| **Shape ideas on a canvas** | Create, edit, move, and fold nodes and branches; arrange the layout when needed. Core editing code and offscreen checks exist; pointer feel still needs hands-on review. |
| **Move between outline and canvas** | Use the outline, styling, and notes panels to find content and adjust its presentation. Choose a Simplified Chinese or English interface; this does not translate text you wrote. |
| **Keep maps separate** | Work with multiple documents, windows, and tabs, each with its own editing state. Real-window behavior still needs focused verification. |
| **Save and export** | Save and reopen native `.mflw` documents; export PDF, PNG, JPEG, and Markdown. Markdown is a text hierarchy summary and **does not losslessly preserve media, notes, or cross-node relationships**. |
| **Read a limited subset of MindNode v9** | Import supported binary-plist files or directory packages; export only a subset of fidelity-preserving edits to a **new copy**. The original is not overwritten; acceptance by MindNode itself has not been established. |

## Quick start

**System:** macOS 26 or later on Apple Silicon (arm64). The released **v0.6.1 / build 8** is labeled Stable as a product release channel—not as Apple notarization or proof of broad desktop acceptance.

1. The repository and Releases are **still private**. With an authorized GitHub browser session, open the [v0.6.1 Release](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.1) and download the [DMG](https://github.com/nico-zhuang/openmindflow/releases/download/v0.6.1/OpenMindFlow-Stable-0.6.1-20261029.dmg) or [ZIP](https://github.com/nico-zhuang/openmindflow/releases/download/v0.6.1/OpenMindFlow-Stable-0.6.1-20261029.zip). The App does not ask for a GitHub token or automatically download and install updates.
2. For the DMG, open it in Finder and check that it contains the OpenMindFlow App and an `/Applications` shortcut; if you choose to install it in Applications, drag the App onto that shortcut yourself. For the ZIP, use Finder / Archive Utility or the verified `ditto` command below; **do not use `unzip -q`** to scatter AppleDouble `._` files into the signed App. Check the file and its origin against your macOS security policy before opening it. Real Finder drag-and-drop, installation, and first launch have not been independently tested in this round.
3. Once the App opens, create a map, add nodes, and save an `.mflw` document. Keep independent backups of important work while coverage grows. The App is **ad-hoc signed only**: it has no Developer ID signature, Apple notarization, or automatic installer. Code-signature integrity is not publisher identity; do not turn off macOS protections just to try it.

For example, if you saved the ZIP under its original filename in Downloads, extract it into a new private directory and verify its signature (adjust the ZIP path if your browser changed the filename):

```bash
unpacked="$(mktemp -d /private/tmp/openmindflow-unpack-XXXXXXXX)"
ditto -x -k "$HOME/Downloads/OpenMindFlow-Stable-0.6.1-20261029.zip" "$unpacked"
codesign --verify --deep --strict "$unpacked/OpenMindFlow-Stable-0.6.1.app"
```

**This round extracted the original v0.6.1 ZIP into an equivalent new directory with `ditto` and passed strict signature verification.** This is not a claim of automatic installation or a hands-on GUI first launch.

<details>
<summary>v0.6.1 download checksums (SHA-256)</summary>

| File | SHA-256 |
| --- | --- |
| `OpenMindFlow-Stable-0.6.1-20261029.dmg` | `23994fb05bf22b98d77e632f73e0cf64e1470b65b603de0fabbe8bf10dee5bac` |
| `OpenMindFlow-Stable-0.6.1-20261029.zip` | `1bbf9e2681c7e0c3055c1772dae23da08192f206dfef64f83e6dd70c3ccbd886` |

On macOS, run `shasum -a 256 PATH_TO_DOWNLOADED_FILE` and compare the result with the relevant row. **Replace the explanatory path with your actual file path; it is not a literal filename.**

</details>

### Build from source (optional)

The default `main` branch still has an earlier App prototype. Its old `build.sh` is **not** the v0.6.1 builder. With Swift command-line tools and SSH read access to the repository, use the frozen [v0.6.1 tag](https://github.com/nico-zhuang/openmindflow/tree/v0.6.1) and the dedicated builder in a new, privately owned scratch directory:

```bash
scratch="$(mktemp -d /private/tmp/openmindflow-local-XXXXXXXX)"
git clone --depth 1 --branch v0.6.1 git@github.com:nico-zhuang/openmindflow.git "$scratch/source"
bash "$scratch/source/scripts/build-openmindflow-0.6.1-stable-local.sh" \
  "$scratch/OpenMindFlow-Stable-0.6.1.app"
codesign --verify --deep --strict "$scratch/OpenMindFlow-Stable-0.6.1.app"
```

The `mktemp` command above creates a fresh private directory; the script requires an owned `0700` directory matching `/private/tmp/openmindflow-local-*` and refuses to replace an existing App. **This exact clone/build/signature-verification sequence succeeded in this round on macOS 26.5 / arm64**; compilation emitted AVFoundation deprecated-API warnings. The isolated ad-hoc build is not installed or launched automatically. GUI launch and Finder installation still need separate hands-on checks.

**Upgrading from v0.6.0:** Its old binary pins the pre-rename repository address and rejects redirects; download v0.6.1 manually from the new Release. The previous [v0.6.0 Release](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.0) and its assets remain available to authorized accounts.

## Current status and known limits

- **What was tested:** The v0.6.1 release record reports **80/80 safe offscreen Swift suites plus 3/3 interaction submodes**, with checks for the App, DMG, and ZIP App extracted with macOS `ditto`. These are release-time records, not a fresh run of all suites in this round or a substitute for real-desktop acceptance. See the [release evidence](https://github.com/nico-zhuang/openmindflow/blob/v0.6.1/docs/2026-10-29-openmindflow-0.6.1-repository-migration.md).
- **Still to verify on a real Mac:** A current-version window image, Finder double-click handling of `.mflw`, pointer drag and resize behavior, system VoiceOver, and actual MindNode acceptance of a newly exported copy. Back up important data independently. An old screenshot or synthetic window check does not establish these results.
- **Format boundaries:** `.mflw` uses an `OMFLW001` marker, length and SHA-256 check, and a **binary property list** body; it is not renamed JSON. Older `.mindmap.json` is migration input only. MindNode v9 import is limited to supported binary-plist files / directory packages; ZIP containers, newer versions, and unknown structures are not covered broadly. Edits that cannot be exported faithfully can still be saved as `.mflw`.
- **Branches:** The default `main` still has an earlier App prototype; this page describes the released [v0.6.1 source snapshot](https://github.com/nico-zhuang/openmindflow/tree/v0.6.1) and package. Ongoing work is on [`feature/native-editor-v2`](https://github.com/nico-zhuang/openmindflow/tree/feature/native-editor-v2). **Do not expect a build of `main` to match this release.**

## Relationship to MindNode

OpenMindFlow is developed independently, with MindNode's mind-mapping experience and v9 file interoperability as points of study. It is **not an official MindNode / IdeasOnCanvas product and is not affiliated with or endorsed by them**. The MindNode name and trademarks belong to their respective owners; the limited compatibility here does not imply official support. The maintainer still needs to review third-party code, graphics, and applicable licensing. This is not a legal conclusion.

## What comes next

1. Verify the current signed build's real desktop interactions, Finder document association, system accessibility, and actual MindNode acceptance of exported copies; add a compliant real-window screenshot and demo only after that review.
2. Refine the supported MindNode v9 subset, rejection messages, and export-to-new-copy guidance while keeping originals read-only.
3. Resolve source/icon/third-party rights, private Git history before publication, and future distribution signing, notarization, and external feedback workflow. These are not promised shipped features.

## Feedback, source, and licensing

GitHub **Issues are currently disabled**, and there is no established public contribution process or `LICENSE` file. Reading the source or downloading a build does not itself grant a general modification, redistribution, or open-source license. The maintainer will decide when privacy, rights, and issue intake are ready. Earlier design and development notes are available in the [previous README at v0.6.1](https://github.com/nico-zhuang/openmindflow/blob/v0.6.1/README.md); local paths in historical documents are not public download links.

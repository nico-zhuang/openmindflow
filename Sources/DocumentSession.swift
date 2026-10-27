import AppKit
import Foundation
import Darwin

internal enum DocumentOperationError: LocalizedError {
    case unsupported, cancelled
    var errorDescription: String? {
        switch self {
        case .unsupported: "Select a .mflw document, legacy .mindmap.json file, or use Import MindNode."
        case .cancelled: "The document operation was cancelled."
        }
    }
}

internal struct LoadedDocument {
    let document: OwnMapDocument
    let archive: MindNodeArchive?
    let nativeURL: URL?
    let digest: Data?
    let identity: NativeMapFile.FileIdentity?
}

final class DocumentSession {
    let canvas: MapCanvas
    let outline: MapOutlineView
    let inspector: StyleInspector
    let splitController: NSSplitViewController
    private(set) var fileURL: URL?
    private(set) var mindNodeArchive: MindNodeArchive?
    private(set) var dirty = false
    weak var window: NSWindow?
    var onTitleChange: (() -> Void)?
    var onFindChange: (() -> Void)?
    var findWindow: NSPanel?
    var findField: NSSearchField?
    var findStatus: NSTextField?
    var findMatches: [UUID] = []
    var findIndex = 0

    private var savedNativeSHA256: Data?
    private var savedNativeIdentity: NativeMapFile.FileIdentity?
    var nativeIdentity: NativeMapFile.FileIdentity? { savedNativeIdentity }
    /// A same-path reopen keeps the editor's original baseline rather than silently loading replacement bytes.
    func verifyNativeBaseline() throws {
        guard let fileURL, let digest = savedNativeSHA256, let identity = savedNativeIdentity else { return }
        let current = try NativeMapFile.readWithFileIdentity(fileURL)
        guard current.identity == identity, current.digest == digest else { throw NativeMapFile.FileError.conflict }
    }
    private var savedRoots: [MapNode]
    private var savedRelationships: [MapRelationship]
    private var savedTheme: String?
    private var savedCanvasColor: String?

    init(canvas: MapCanvas, defaults: UserDefaults) {
        self.canvas = canvas
        savedRoots = canvas.model.roots
        savedRelationships = canvas.model.relationships
        savedTheme = canvas.model.theme
        savedCanvasColor = canvas.model.canvasColor
        canvas.localizationDefaults = defaults
        let split = NSSplitViewController()
        let sidebarController = NSViewController()
        let outline = MapOutlineView(canvas: canvas, defaults: defaults)
        self.outline = outline
        sidebarController.view = outline
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebar.canCollapse = true
        sidebar.minimumThickness = 180
        sidebar.maximumThickness = 320
        split.addSplitViewItem(sidebar)
        sidebar.isCollapsed = true
        let canvasController = NSViewController()
        canvasController.view = canvas
        split.addSplitViewItem(NSSplitViewItem(viewController: canvasController))
        let inspectorController = NSViewController()
        let inspector = StyleInspector(canvas: canvas, defaults: defaults)
        self.inspector = inspector
        inspectorController.view = inspector
        let style = NSSplitViewItem(viewController: inspectorController)
        style.canCollapse = true
        style.minimumThickness = 260
        style.maximumThickness = 320
        style.holdingPriority = .defaultHigh
        split.addSplitViewItem(style)
        style.isCollapsed = true
        self.splitController = split
        canvas.onEditNote = { [weak self] id in
            guard let self, self.canvas.model.selectedIDs == [id] else { return }
            if self.splitController.splitViewItems[2].isCollapsed { self.togglePane(at: 2) }
            _ = self.inspector.selectNotes(for: id)
        }
        canvas.onChange = { [weak self] in
            guard let self else { return }
            self.syncDirty()
            self.outline.reloadMap()
            self.inspector.refresh()
            if self.findWindow?.isVisible == true { self.onFindChange?() }
        }
        canvas.onSelectionChange = { [weak self] in
            self?.outline.syncSelection()
            self?.inspector.refresh()
        }
    }

    func commitPendingEditors() -> Bool { canvas.commitEditing() && inspector.commitNoteEditing() }
    func currentDocument() -> OwnMapDocument {
        OwnMapDocument(roots: canvas.model.roots, relationships: canvas.model.relationships,
                       theme: canvas.model.theme, canvasColor: canvas.model.canvasColor)
    }
    func syncDirty() {
        dirty = canvas.model.roots != savedRoots || canvas.model.relationships != savedRelationships ||
            canvas.model.theme != savedTheme || canvas.model.canvasColor != savedCanvasColor
        onTitleChange?()
    }
    func preflightMap(at url: URL) throws -> LoadedDocument {
        if url.pathExtension == "mflw" {
            let result = try NativeMapFile.readWithFileIdentity(url)
            let archive = try result.payload.mindNodeArchive.map {
                try PropertyListDecoder().decode(MindNodeArchive.self, from: $0)
            }
            return LoadedDocument(document: result.payload.document, archive: archive,
                                  nativeURL: url, digest: result.digest, identity: result.identity)
        }
        guard url.lastPathComponent.hasSuffix(".mindmap.json") else { throw DocumentOperationError.unsupported }
        return LoadedDocument(document: try readOwnDocument(url), archive: nil,
                              nativeURL: nil, digest: nil, identity: nil)
    }
    func preflightMindNode(at url: URL) throws -> MindNodeArchive { try MindNodeArchive(importing: url) }
    func installDocument(_ loaded: LoadedDocument) {
        let document = loaded.document
        canvas.replacingModel = true
        defer { canvas.replacingModel = false }
        canvas.model = MapModel(roots: document.roots, selected: document.roots.first?.id ?? UUID(),
                                theme: document.theme, canvasColor: document.canvasColor)
        canvas.model.relationships = document.relationships
        canvas.branchStyles = loaded.archive?.imported.styles ?? [:]
        canvas.nativePresentation = loaded.archive?.imported.presentation ?? [:]
        canvas.embeddedTheme = loaded.archive?.imported.theme
        mindNodeArchive = loaded.archive
        fileURL = loaded.nativeURL
        savedNativeSHA256 = loaded.digest
        savedNativeIdentity = loaded.identity
        savedRoots = document.roots
        savedRelationships = document.relationships
        savedTheme = document.theme
        savedCanvasColor = document.canvasColor
        dirty = false
        outline.reloadMap()
        inspector.refresh()
        onTitleChange?()
        canvas.fitMapInView()
        onFindChange?()
        window?.makeFirstResponder(canvas)
    }
    func exportCurrentMindNode(to url: URL) throws {
        guard commitPendingEditors() else { throw DocumentOperationError.cancelled }
        let document = currentDocument()
        if let mindNodeArchive {
            try mindNodeArchive.export(document: document, to: url)
        } else {
            try MindNodeWriter.write(document.roots, to: url, imported: nil,
                                     relationships: document.relationships,
                                     theme: document.theme, canvasColor: document.canvasColor)
        }
    }
    /// Case aliases and hardlinks must retain the original digest/inode conflict guard.
    private func refersToCurrentNativeFile(_ destination: URL) -> Bool {
        guard let fileURL else { return false }
        if fileURL == destination { return true }
        var opened = stat(), chosen = stat()
        guard lstat(destination.path, &chosen) == 0,
              chosen.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { return false }
        guard let lastRead = savedNativeSHA256, let openedIdentity = savedNativeIdentity,
              lstat(fileURL.path, &opened) == 0,
              opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              openedIdentity == NativeMapFile.FileIdentity(device: UInt64(opened.st_dev),
                                                           inode: UInt64(opened.st_ino)) else { return true }
        do { try NativeMapFile.verifyExpectedCurrent(fileURL, expectedCurrentSHA256: lastRead) }
        catch { return true }
        return opened.st_dev == chosen.st_dev && opened.st_ino == chosen.st_ino
    }
    func saveCurrentMap(to url: URL) throws {
        guard commitPendingEditors() else { throw DocumentOperationError.cancelled }
        guard url.pathExtension == "mflw" else { throw DocumentOperationError.unsupported }
        let document = currentDocument()
        let archiveData: Data?
        if let mindNodeArchive {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            archiveData = try encoder.encode(mindNodeArchive)
        } else { archiveData = nil }
        let payload = NativeMapFile.Payload(document: document, mindNodeArchive: archiveData)
        if fileURL != nil && savedNativeSHA256 == nil { throw NativeMapFile.FileError.conflict }
        #if HEADLESS_TEST
        if ProcessInfo.processInfo.environment["MINDMAP_PANEL_ACTION"] == "save-failure" { throw POSIXError(.EIO) }
        #endif
        try NativeMapFile.write(payload, to: url,
                                expectedCurrentSHA256: refersToCurrentNativeFile(url) ? savedNativeSHA256 : nil)
        let result = try NativeMapFile.readWithFileIdentity(url)
        guard result.payload.document.roots == document.roots,
              result.payload.document.relationships == document.relationships,
              result.payload.document.theme == document.theme,
              result.payload.document.canvasColor == document.canvasColor,
              result.payload.mindNodeArchive == archiveData else { throw NativeMapFile.FileError.conflict }
        fileURL = url
        savedNativeSHA256 = result.digest
        savedNativeIdentity = result.identity
        savedRoots = document.roots
        savedRelationships = document.relationships
        savedTheme = document.theme
        savedCanvasColor = document.canvasColor
        dirty = false
        onTitleChange?()
    }
    private func togglePane(at index: Int) {
        let window = splitController.view.window
        let frame = window?.frame
        let host = window?.contentView
        let oldOrigin = host.map { canvas.convert(CGPoint.zero, to: $0) }
        let item = splitController.splitViewItems[index]
        item.isCollapsed.toggle()
        if let frame, window?.frame != frame { window?.setFrame(frame, display: true) }
        host?.layoutSubtreeIfNeeded()
        if let oldOrigin, let host {
            let newOrigin = canvas.convert(CGPoint.zero, to: host)
            canvas.shiftViewport(by: CGPoint(x: oldOrigin.x - newOrigin.x, y: oldOrigin.y - newOrigin.y))
        }
        if item.isCollapsed { window?.makeFirstResponder(canvas) }
    }
    func toggleOutline() { togglePane(at: 0) }
    func toggleStyle() {
        guard !splitController.splitViewItems[2].isCollapsed ? commitPendingEditors() : true else { return }
        togglePane(at: 2)
    }
}
